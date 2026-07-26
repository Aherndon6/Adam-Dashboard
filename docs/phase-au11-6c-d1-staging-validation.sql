-- ============================================================================
-- AU-11 Step 6C-D1 — STAGING forward validation (READ-ONLY except the rolled-back
-- frozen-wrapper noninterference probe). Run AFTER the migration + schema-cache reload.
-- STAGING ONLY. Executed by Adam. Compare each result to the Expected column.
-- ============================================================================

-- ── Existing data + classes unchanged ──
SELECT 'V1_rowcount_unchanged' AS test, count(*) AS rows FROM public.cash_commitments;  -- Expect == preflight ROWCOUNT
SELECT 'V2_no_au11_rows' AS test, count(*) AS n FROM public.cash_commitments
  WHERE commitment_class='discretionary_goal_transfer';                                 -- Expect 0
SELECT 'V3_no_batch_rows' AS test, count(*) AS n FROM public.discretionary_reservation_batches; -- Expect 0
SELECT 'V4_existing_cols_null_on_nonres' AS test, count(*) AS violations
  FROM public.cash_commitments
  WHERE commitment_class<>'discretionary_goal_transfer'
    AND (reservation_batch_id IS NOT NULL OR goal_id IS NOT NULL
         OR destination_account_ref IS NOT NULL OR bank_reference IS NOT NULL OR bank_submitted_at IS NOT NULL); -- Expect 0

-- ── Schema shape ──
SELECT 'V5_new_columns' AS test, column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='cash_commitments'
    AND column_name IN ('reservation_batch_id','goal_id','destination_account_ref','bank_reference','bank_submitted_at')
  ORDER BY column_name;   -- Expect: all is_nullable=YES, column_default NULL; types uuid/text/text/text/timestamptz
-- Target the EXACT captured constraint names (chk_au11_reservation_shape ALSO contains these column
-- names post-migration, so an ILIKE-on-def scalar subquery is no longer unique).
SELECT 'V6_class_value_legal' AS test,
  CASE WHEN pg_get_constraintdef((SELECT oid FROM pg_constraint
        WHERE conrelid='public.cash_commitments'::regclass AND conname='cash_commitments_commitment_class_check'))
       ILIKE '%discretionary_goal_transfer%' THEN 'PASS' ELSE 'FAIL' END AS result;
SELECT 'V7_source_value_legal' AS test,
  CASE WHEN pg_get_constraintdef((SELECT oid FROM pg_constraint
        WHERE conrelid='public.cash_commitments'::regclass AND conname='cash_commitments_commitment_source_check'))
       ILIKE '%au11_reservation%' THEN 'PASS' ELSE 'FAIL' END AS result;
SELECT 'V8_shape_validated' AS test, convalidated
  FROM pg_constraint WHERE conname='chk_au11_reservation_shape';   -- Expect convalidated = true
SELECT 'V9_fk_valid' AS test, convalidated
  FROM pg_constraint WHERE conname='fk_au11_batch';                -- Expect true
SELECT 'V10_indexes' AS test, indexname, indexdef FROM pg_indexes
  WHERE schemaname='public' AND indexname IN ('uix_one_active_batch','uix_au11_batch_goal','ix_au11_active')
  ORDER BY indexname;   -- Expect all three with the exact WHERE predicates
SELECT 'V11_batch_rls_enabled' AS test, relrowsecurity
  FROM pg_class WHERE oid='public.discretionary_reservation_batches'::regclass;   -- Expect true
SELECT 'V12_batch_write_denied' AS test, grantee, privilege_type
  FROM information_schema.role_table_grants
  WHERE table_schema='public' AND table_name='discretionary_reservation_batches'
    AND grantee IN ('anon','authenticated') AND privilege_type IN ('INSERT','UPDATE','DELETE');  -- Expect 0 rows

-- ── Frozen-wrapper NONINTERFERENCE probe (rolled back; proves the SHAPE constraint blocks a
-- reservation-class insert that carries a non-au11 source, as the frozen wrapper would emit).
-- NOTE: created_by is NOT NULL DEFAULT auth.uid(); auth.uid() is NULL in the SQL Editor, so we supply a
-- valid existing user id via a subquery — otherwise a not_null_violation would fire BEFORE the shape CHECK
-- and mask the real test. With created_by valid, the ONLY remaining violation is chk_au11_reservation_shape.
DO $$
DECLARE v_uid UUID;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'V13 SETUP: no auth.users row on staging to supply created_by'; END IF;
  BEGIN
    INSERT INTO public.cash_commitments
      (expected_item_id, model_year, commitment_source, origin_model_week, payee,
       commitment_class, required_or_discretionary, source_account, amount_cents, status, created_by)
    VALUES ('AU11-PROBE-should-fail', 2026, 'manual_reconciliation', 7, 'probe',
            'discretionary_goal_transfer', 'discretionary_deployment', 'truist_checking', 100, 'scheduled', v_uid);
    RAISE EXCEPTION 'V13 FAIL: reservation-class row inserted WITHOUT au11_reservation source (shape constraint ineffective)';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'V13 PASS: reservation-class insert without au11_reservation source rejected by CHECK (%).', SQLERRM;
  END;
  RAISE EXCEPTION 'V13 rollback sentinel';   -- force rollback of the whole DO block (no persisted probe row)
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'V13 rollback sentinel%' THEN RAISE; END IF;
END $$;
SELECT 'V13_probe_left_no_rows' AS test, count(*) AS n
  FROM public.cash_commitments WHERE expected_item_id='AU11-PROBE-should-fail';   -- Expect 0

-- ── repair_commitments_for_week unchanged (still 7-class only) ──
SELECT 'V14_repair_class_locked' AS test,
  CASE WHEN pg_get_functiondef('public.repair_commitments_for_week(int,int,text,jsonb,jsonb)'::regprocedure)
       ILIKE '%repair: invalid commitment_class%' THEN 'PASS: still rejects unknown class' ELSE 'REVIEW' END AS result;

-- ── Planner review (existing-class query must not regress; AU-11 predicate can use the partial index) ──
EXPLAIN SELECT * FROM public.cash_commitments
  WHERE source_account='truist_checking' AND status IN ('initiated','bank_pending')
    AND commitment_class='credit_card_payment';                  -- existing-class path unaffected by partial indexes
EXPLAIN SELECT * FROM public.cash_commitments
  WHERE commitment_class='discretionary_goal_transfer' AND model_year=2026 AND source_account='truist_checking';
