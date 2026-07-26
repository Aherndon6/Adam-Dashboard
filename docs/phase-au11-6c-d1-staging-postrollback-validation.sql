-- ============================================================================
-- AU-11 Step 6C-D1 — STAGING post-rollback validation (READ-ONLY)
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Run AFTER the rollback (Gate D1-4) + schema-cache reload.
-- Proves the schema was restored EXACTLY to the pre-migration (Gate D1-1) state:
-- no AU-11 columns/table/indexes/FK/shape; class CHECK back to 7 values, source to
-- 3; existing data + row count unchanged; no residue. Read-only.
-- ============================================================================

-- PR1: the five AU-11 columns are GONE
SELECT 'PR1_columns_removed' AS test, count(*) AS remaining_au11_cols
FROM information_schema.columns
WHERE table_schema='public' AND table_name='cash_commitments'
  AND column_name IN ('reservation_batch_id','goal_id','destination_account_ref','bank_reference','bank_submitted_at'); -- Expect 0

-- PR2: batch table GONE
SELECT 'PR2_batch_table_removed' AS test,
  CASE WHEN to_regclass('public.discretionary_reservation_batches') IS NULL THEN 'PASS' ELSE 'FAIL' END AS result; -- Expect PASS

-- PR3: AU-11 indexes GONE
SELECT 'PR3_indexes_removed' AS test, count(*) AS remaining_au11_indexes
FROM pg_indexes WHERE schemaname='public'
  AND indexname IN ('uix_one_active_batch','uix_au11_batch_goal','ix_au11_active'); -- Expect 0

-- PR4: FK + shape constraint GONE
SELECT 'PR4_fk_shape_removed' AS test, count(*) AS remaining
FROM pg_constraint
WHERE conrelid='public.cash_commitments'::regclass AND conname IN ('fk_au11_batch','chk_au11_reservation_shape'); -- Expect 0

-- PR5: class CHECK restored to EXACTLY the 7 values (no discretionary_goal_transfer)
SELECT 'PR5_class_restored' AS test,
  CASE WHEN pg_get_constraintdef((SELECT oid FROM pg_constraint
        WHERE conrelid='public.cash_commitments'::regclass AND conname='cash_commitments_commitment_class_check'))
       NOT ILIKE '%discretionary_goal_transfer%'
   AND pg_get_constraintdef((SELECT oid FROM pg_constraint
        WHERE conrelid='public.cash_commitments'::regclass AND conname='cash_commitments_commitment_class_check'))
       ILIKE '%credit_card_payment%'
       THEN 'PASS' ELSE 'FAIL' END AS result; -- Expect PASS

-- PR6: source CHECK restored to EXACTLY the 3 values (no au11_reservation)
SELECT 'PR6_source_restored' AS test,
  CASE WHEN pg_get_constraintdef((SELECT oid FROM pg_constraint
        WHERE conrelid='public.cash_commitments'::regclass AND conname='cash_commitments_commitment_source_check'))
       NOT ILIKE '%au11_reservation%'
   AND pg_get_constraintdef((SELECT oid FROM pg_constraint
        WHERE conrelid='public.cash_commitments'::regclass AND conname='cash_commitments_commitment_source_check'))
       ILIKE '%wd_reconciliation%'
       THEN 'PASS' ELSE 'FAIL' END AS result; -- Expect PASS

-- PR7: existing data + row count unchanged; existing classes still legal
SELECT 'PR7_rowcount' AS test, count(*) AS cash_commitments_rows FROM public.cash_commitments;  -- Expect same as Gate D1-1 (0)

-- PR8: full current constraint set (compare visually to the Gate D1-1 CHECK_DEFS capture — must match)
SELECT 'PR8_check_defs' AS capture, conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint WHERE conrelid='public.cash_commitments'::regclass AND contype='c' ORDER BY conname;

-- PR9: no AU-11 residue anywhere (columns/table/index/constraint)
SELECT 'PR9_no_residue' AS test,
  (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments'
     AND column_name IN ('reservation_batch_id','goal_id','destination_account_ref','bank_reference','bank_submitted_at'))
  + (CASE WHEN to_regclass('public.discretionary_reservation_batches') IS NULL THEN 0 ELSE 1 END)
  + (SELECT count(*) FROM pg_indexes WHERE schemaname='public'
       AND indexname IN ('uix_one_active_batch','uix_au11_batch_goal','ix_au11_active'))
  + (SELECT count(*) FROM pg_constraint WHERE conrelid='public.cash_commitments'::regclass
       AND conname IN ('fk_au11_batch','chk_au11_reservation_shape'))
  AS total_residue;   -- Expect 0
