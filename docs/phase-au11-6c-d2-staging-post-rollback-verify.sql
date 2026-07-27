-- ============================================================================
-- AU-11 Step 6C-D2 — POST-ROLLBACK (Checkpoint G) D1-intact + frozen-RPC verification  (READ-ONLY)
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Run AFTER phase-au11-6c-d2-staging-rollback.sql. Proves the D2 rollback left the D1 additive
-- schema and the frozen commitment RPCs INTACT. Two parts:
--   PART 1 — structural HARD-STOP assertions (schema/owner/type/uniqueness/exact columns/predicate/nullability/
--            exact RPC signatures + no overloads). Drift raises 'D1 VERIFY FAIL'.
--   PART 2 — an evidence result set emitting the exact pg_get_constraintdef / pg_get_indexdef / RPC signatures
--            for exact comparison against the Gate D1-1 captured baseline (the authoritative normalized forms;
--            this file does not fabricate them). Frozen CODE surfaces (index.html) are git-verified at 78538f9.
-- ============================================================================

-- ── PART 1: structural assertions (gate) ──
DO $$
DECLARE v_cols TEXT;
BEGIN
  -- guard: not staging
  IF to_regclass('public.app_environment') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: not staging.'; END IF;

  -- D1 CHECK constraint: exactly one, public schema, owning table cash_commitments, type 'c', validated
  IF (SELECT count(*) FROM pg_constraint c
        WHERE c.conname='chk_au11_reservation_shape'
          AND c.connamespace='public'::regnamespace
          AND c.conrelid='public.cash_commitments'::regclass
          AND c.contype='c' AND c.convalidated) <> 1 THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: chk_au11_reservation_shape not exactly one validated CHECK on public.cash_commitments.'; END IF;

  -- D1 unique partial index: exactly one, public schema, owning table discretionary_reservation_batches, UNIQUE, partial
  IF (SELECT count(*) FROM pg_index i
        JOIN pg_class ic ON ic.oid=i.indexrelid
        JOIN pg_namespace n ON n.oid=ic.relnamespace
        JOIN pg_class tc ON tc.oid=i.indrelid
       WHERE ic.relname='uix_one_active_batch' AND n.nspname='public'
         AND tc.relname='discretionary_reservation_batches'
         AND i.indisunique IS TRUE AND i.indpred IS NOT NULL) <> 1 THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: uix_one_active_batch not a unique partial index on public.discretionary_reservation_batches.'; END IF;
  -- exact indexed columns in order: (model_year, source_account)
  SELECT string_agg(a.attname, ',' ORDER BY k.ord) INTO v_cols
    FROM pg_index i
    JOIN pg_class ic ON ic.oid=i.indexrelid
    JOIN pg_namespace n ON n.oid=ic.relnamespace
    CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
    JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum
   WHERE ic.relname='uix_one_active_batch' AND n.nspname='public';
  IF v_cols IS DISTINCT FROM 'model_year,source_account' THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: uix_one_active_batch columns are [%] (expected model_year,source_account).', v_cols; END IF;

  -- D1 additive cash_commitments columns: type + nullability (not merely existence)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments'
                   AND column_name='reservation_batch_id' AND data_type='uuid' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: cash_commitments.reservation_batch_id not uuid/nullable.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments'
                   AND column_name='goal_id' AND data_type='text' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: cash_commitments.goal_id not text/nullable.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments'
                   AND column_name='destination_account_ref' AND data_type='text' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: cash_commitments.destination_account_ref not text/nullable.'; END IF;

  -- frozen RPCs: exact signature EXACTLY once; reject unexpected overloads
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='repair_commitments_for_week') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='repair_commitments_for_week'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, integer, text, jsonb, jsonb') THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: repair_commitments_for_week absent/not-exact-signature/overloaded.'; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='save_reconciliation_with_commitments') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='save_reconciliation_with_commitments'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, integer, numeric, numeric, numeric, numeric, numeric, text, timestamp with time zone, jsonb, jsonb') THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: save_reconciliation_with_commitments absent/not-exact-signature/overloaded.'; END IF;

  -- D2 reservable column must be ABSENT (rollback removed it)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable') THEN
    RAISE EXCEPTION 'D1 VERIFY FAIL: goal_registry.reservable still present (rollback did not remove it).'; END IF;

  RAISE NOTICE 'D1 VERIFY: all structural assertions passed.';
END $$;

-- ── PART 2: evidence result set (emit exact defs/sigs for comparison to the Gate D1-1 baseline) ──
SELECT *
FROM (
  SELECT 'constraintdef_chk_au11_reservation_shape' AS item,
         pg_get_constraintdef((SELECT c.oid FROM pg_constraint c
           WHERE c.conname='chk_au11_reservation_shape' AND c.conrelid='public.cash_commitments'::regclass)) AS detail
  UNION ALL
  SELECT 'indexdef_uix_one_active_batch',
         pg_get_indexdef((SELECT i.indexrelid FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid
           JOIN pg_namespace n ON n.oid=ic.relnamespace
           WHERE ic.relname='uix_one_active_batch' AND n.nspname='public'))
  UNION ALL
  SELECT 'sig_repair_commitments_for_week',
         (SELECT pg_catalog.oidvectortypes(proargtypes) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='repair_commitments_for_week')
  UNION ALL
  SELECT 'sig_save_reconciliation_with_commitments',
         (SELECT pg_catalog.oidvectortypes(proargtypes) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='save_reconciliation_with_commitments')
) AS ev
ORDER BY item;
