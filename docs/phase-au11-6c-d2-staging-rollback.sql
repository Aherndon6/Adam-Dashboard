-- ============================================================================
-- AU-11 Step 6C-D2 — STAGING-PROOF rollback (drop the RPCs + reservable column)  [CHECKPOINT G]
-- ----------------------------------------------------------------------------
-- SCOPE: STAGING PROOF of a CONTROLLED TRANSITION from the expected installed D1+D2 state to D2-removed,
-- D1-intact. NOT the production rollback (production would drop the functions but RETAIN reservable).
--
-- PROOF SEQUENCE (in order):
--   (A) expected D1/frozen PRE-state certified  → (B) complete expected D2 install certified
--   → (C) lifecycle advisory lock acquired/held  → (D) zero reservation + metadata residue certified
--   → bare D2 DROPs  → (E) D2 absence certified in-transaction  → COMMIT
--   → [separately] D1/frozen post-state independently recertified (phase-au11-6c-d2-staging-post-rollback-verify.sql)
--
-- (A) mirrors the post-rollback verifier's critical D1/frozen assertions (schema/owner/type/nullability/exact
-- constraint definition/exact index columns+predicate/exact frozen-RPC signatures/no overloads). The constraint
-- and index definitions are compared in a CANONICAL form (lowercase; '::text' casts, parentheses, and whitespace
-- stripped) so the check is machine-exact but robust to PostgreSQL's cast/paren rendering. Any drift fails CLOSED
-- (nothing dropped) and emits actual-vs-expected for reconciliation against the Gate D1-1 captured baseline.
-- Set-aware staging guard; single BEGIN/COMMIT; bare DROPs (no IF EXISTS); non-reserved check_name alias.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '5s';   -- fail cleanly (55P03) rather than hang if the lifecycle lock is contended

-- ── Guard: staging (set-aware — >=1 row AND every row env='staging') ──
DO $$
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: app_environment missing — cannot certify staging.'; END IF;
  IF (SELECT count(*) FROM public.app_environment) < 1
     OR EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging') THEN
    RAISE EXCEPTION 'HARD STOP: app_environment does not certify staging (need >=1 row, every row env=staging).'; END IF;
END $$;

-- ── (A) expected D1/frozen PRE-STATE certification (before any destructive change) ──
DO $$
DECLARE
  v_cols TEXT; v_def TEXT; v_pred TEXT;
  c_expected_def CONSTANT TEXT :=
    $canon$checkcommitment_class='discretionary_goal_transfer'andcommitment_source='au11_reservation'andreservation_batch_idisnotnullandgoal_idisnotnullanddestination_account_refisnotnullandrequired_or_discretionary='discretionary_deployment'andsource_account='truist_checking'orcommitment_class<>'discretionary_goal_transfer'andcommitment_source<>'au11_reservation'andreservation_batch_idisnullandgoal_idisnullanddestination_account_refisnullandbank_referenceisnullandbank_submitted_atisnull$canon$;
BEGIN
  -- batch table is a base table
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                  WHERE n.nspname='public' AND c.relname='discretionary_reservation_batches' AND c.relkind='r') THEN
    RAISE EXCEPTION 'HARD STOP: public.discretionary_reservation_batches is not the expected base table.'; END IF;

  -- cash_commitments D1 additive columns: exact type + nullability
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments'
                   AND column_name='reservation_batch_id' AND data_type='uuid' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'HARD STOP: cash_commitments.reservation_batch_id not uuid/nullable.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments'
                   AND column_name='goal_id' AND data_type='text' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'HARD STOP: cash_commitments.goal_id not text/nullable.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments'
                   AND column_name='destination_account_ref' AND data_type='text' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'HARD STOP: cash_commitments.destination_account_ref not text/nullable.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments'
                   AND column_name='commitment_source' AND data_type='text') THEN
    RAISE EXCEPTION 'HARD STOP: cash_commitments.commitment_source (D1) missing/not text.'; END IF;

  -- chk_au11_reservation_shape: exactly one validated CHECK on cash_commitments, with the expected normalized def
  IF (SELECT count(*) FROM pg_constraint c
        WHERE c.conname='chk_au11_reservation_shape' AND c.connamespace='public'::regnamespace
          AND c.conrelid='public.cash_commitments'::regclass AND c.contype='c' AND c.convalidated) <> 1 THEN
    RAISE EXCEPTION 'HARD STOP: chk_au11_reservation_shape not exactly one validated CHECK on public.cash_commitments.'; END IF;
  SELECT lower(regexp_replace(regexp_replace(pg_get_constraintdef(c.oid), '::text', '', 'g'), '[()[:space:]]', '', 'g'))
    INTO v_def
    FROM pg_constraint c WHERE c.conname='chk_au11_reservation_shape' AND c.conrelid='public.cash_commitments'::regclass;
  IF v_def IS DISTINCT FROM c_expected_def THEN
    RAISE EXCEPTION 'HARD STOP: chk_au11_reservation_shape definition drift.  actual=[%]  expected=[%]', v_def, c_expected_def; END IF;

  -- uix_one_active_batch: exactly one UNIQUE PARTIAL index on the batch table, exact key columns + predicate
  IF (SELECT count(*) FROM pg_index i
        JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_namespace n ON n.oid=ic.relnamespace
        JOIN pg_class tc ON tc.oid=i.indrelid
       WHERE ic.relname='uix_one_active_batch' AND n.nspname='public'
         AND tc.relname='discretionary_reservation_batches'
         AND i.indisunique IS TRUE AND i.indpred IS NOT NULL) <> 1 THEN
    RAISE EXCEPTION 'HARD STOP: uix_one_active_batch not a unique partial index on public.discretionary_reservation_batches.'; END IF;
  SELECT string_agg(a.attname, ',' ORDER BY k.ord) INTO v_cols
    FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_namespace n ON n.oid=ic.relnamespace
    CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
    JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum
   WHERE ic.relname='uix_one_active_batch' AND n.nspname='public';
  IF v_cols IS DISTINCT FROM 'model_year,source_account' THEN
    RAISE EXCEPTION 'HARD STOP: uix_one_active_batch columns [%] (expected model_year,source_account).', v_cols; END IF;
  SELECT lower(regexp_replace(regexp_replace(pg_get_expr(i.indpred, i.indrelid), '::text', '', 'g'), '[()[:space:]]', '', 'g'))
    INTO v_pred
    FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_namespace n ON n.oid=ic.relnamespace
   WHERE ic.relname='uix_one_active_batch' AND n.nspname='public';
  IF v_pred IS DISTINCT FROM $canon$status='active'$canon$ THEN
    RAISE EXCEPTION 'HARD STOP: uix_one_active_batch predicate [%] (expected status=active).', v_pred; END IF;

  -- frozen RPCs: exact signature EXACTLY once; reject unexpected overloads
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='repair_commitments_for_week') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='repair_commitments_for_week'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, integer, text, jsonb, jsonb') THEN
    RAISE EXCEPTION 'HARD STOP: repair_commitments_for_week absent/not-exact-signature/overloaded.'; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='save_reconciliation_with_commitments') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='save_reconciliation_with_commitments'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, integer, numeric, numeric, numeric, numeric, numeric, text, timestamp with time zone, jsonb, jsonb') THEN
    RAISE EXCEPTION 'HARD STOP: save_reconciliation_with_commitments absent/not-exact-signature/overloaded.'; END IF;

  RAISE NOTICE 'ROLLBACK (A): expected D1/frozen pre-state certified.';
END $$;

-- ── (B) complete expected D2 install certification (exact sigs, no overloads, reservable column shape) ──
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='create_discretionary_goal_reservation_v1') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='create_discretionary_goal_reservation_v1'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, integer, text, text, date, jsonb, integer') THEN
    RAISE EXCEPTION 'HARD STOP: create_... absent/not-exact-signature/overloaded — install not in expected state.'; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='mark_discretionary_goal_reservation_initiated_v1') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='mark_discretionary_goal_reservation_initiated_v1'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, text, text[], text, timestamp with time zone, date') THEN
    RAISE EXCEPTION 'HARD STOP: mark_... absent/not-exact-signature/overloaded — install not in expected state.'; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='void_scheduled_discretionary_goal_reservation_v1') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='void_scheduled_discretionary_goal_reservation_v1'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, text, text[], text') THEN
    RAISE EXCEPTION 'HARD STOP: void_... absent/not-exact-signature/overloaded — install not in expected state.'; END IF;
  -- reservable column: exactly one live {boolean, NOT NULL, DEFAULT false} column via pg_attrdef
  IF (SELECT count(*)
        FROM pg_attribute a JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
       WHERE a.attrelid='public.goal_registry'::regclass AND a.attname='reservable'
         AND a.atttypid='pg_catalog.bool'::regtype AND a.attnotnull IS TRUE AND a.attisdropped IS FALSE
         AND pg_catalog.pg_get_expr(d.adbin, d.adrelid)='false') <> 1 THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry.reservable is not exactly one live {boolean, NOT NULL, DEFAULT false} column.'; END IF;
  RAISE NOTICE 'ROLLBACK (B): complete expected D2 install certified.';
END $$;

-- ── (C) acquire the D2 reservation-lifecycle advisory lock (identical key to the RPCs), held to COMMIT ──
DO $$
BEGIN
  -- matches create/mark/void: pg_advisory_xact_lock(hashtextextended('au11_disc:'||p_model_year||':'||p_source_account, 0))
  -- create validates p_model_year=2026 AND p_source_account='truist_checking' BEFORE its lock; mark/void hardcode
  -- 'truist_checking' — so the only admissible lock string is 'au11_disc:2026:truist_checking'.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('au11_disc:' || 2026 || ':' || 'truist_checking', 0));
END $$;

-- ── (D) preflight: fail closed on reservation state / fixture residue / any real reservable metadata (lock held) ──
DO $$
DECLARE v_batches INT := 0; v_res INT := 0; v_d2fix INT := 0; v_reservable_n INT := 0; v_ids TEXT;
BEGIN
  -- direct counts (pre-state (A) proved the table exists — do NOT treat missing as zero)
  SELECT count(*) INTO v_batches FROM public.discretionary_reservation_batches;
  SELECT count(*) INTO v_res FROM public.cash_commitments WHERE commitment_source='au11_reservation';
  SELECT count(*) INTO v_d2fix FROM public.goal_registry WHERE id LIKE 'd2fix_%';
  SELECT count(*), string_agg(id, ', ') INTO v_reservable_n, v_ids FROM public.goal_registry WHERE reservable=true;

  RAISE NOTICE 'ROLLBACK preflight: batches=%, au11_reservations=%, d2fix_goals=%, reservable_true=% [%]',
    v_batches, v_res, v_d2fix, v_reservable_n, COALESCE(v_ids,'none');

  IF v_batches <> 0 THEN RAISE EXCEPTION 'HARD STOP: % reservation batch(es) exist — resolve/teardown before rollback.', v_batches; END IF;
  IF v_res     <> 0 THEN RAISE EXCEPTION 'HARD STOP: % au11_reservation commitment(s) exist — resolve/teardown before rollback.', v_res; END IF;
  IF v_d2fix   <> 0 THEN RAISE EXCEPTION 'HARD STOP: % d2fix_ fixture goal(s) still present — Checkpoint F teardown incomplete.', v_d2fix; END IF;
  IF v_reservable_n <> 0 THEN RAISE EXCEPTION 'HARD STOP: % goal(s) have reservable=true [%] — refusing to drop meaningful metadata (use the production rollback design).', v_reservable_n, COALESCE(v_ids,'?'); END IF;
END $$;

-- ── bare D2 DROPs (no IF EXISTS; existence certified in (B)) — functions before the column ──
DROP FUNCTION public.create_discretionary_goal_reservation_v1(INT,INT,TEXT,TEXT,DATE,JSONB,INT);
DROP FUNCTION public.mark_discretionary_goal_reservation_initiated_v1(INT,TEXT,TEXT[],TEXT,TIMESTAMPTZ,DATE);
DROP FUNCTION public.void_scheduled_discretionary_goal_reservation_v1(INT,TEXT,TEXT[],TEXT);
ALTER TABLE public.goal_registry DROP COLUMN reservable;

-- ── (E) assert BOTH functions and column ABSENT before COMMIT ──
DO $$
DECLARE v_fn INT; v_col INT;
BEGIN
  SELECT count(*) INTO v_fn FROM pg_proc WHERE pronamespace='public'::regnamespace
     AND proname IN ('create_discretionary_goal_reservation_v1','mark_discretionary_goal_reservation_initiated_v1','void_scheduled_discretionary_goal_reservation_v1');
  SELECT count(*) INTO v_col FROM information_schema.columns
   WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable';
  IF v_fn  <> 0 THEN RAISE EXCEPTION 'HARD STOP: % D2 function(s) still present after DROP.', v_fn; END IF;
  IF v_col <> 0 THEN RAISE EXCEPTION 'HARD STOP: goal_registry.reservable still present after DROP.'; END IF;
  RAISE NOTICE 'ROLLBACK (E): D2 absence certified in-transaction.';
END $$;

COMMIT;   -- releases the advisory lock

-- ── post-commit corroborating evidence (all four n must be 0) ──
SELECT *
FROM (
  SELECT 'RB_functions_absent' AS check_name,
         (SELECT count(*)::bigint FROM pg_proc WHERE pronamespace='public'::regnamespace
           AND proname IN ('create_discretionary_goal_reservation_v1','mark_discretionary_goal_reservation_initiated_v1','void_scheduled_discretionary_goal_reservation_v1')) AS n
  UNION ALL SELECT 'RB_column_absent',
         (SELECT count(*)::bigint FROM information_schema.columns WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable')
  UNION ALL SELECT 'RB_batches',
         (SELECT count(*)::bigint FROM public.discretionary_reservation_batches)
  UNION ALL SELECT 'RB_reservations',
         (SELECT count(*)::bigint FROM public.cash_commitments WHERE commitment_source='au11_reservation')
) AS rb
ORDER BY check_name;
-- Proves ONLY D2 absence + zero residue. Run phase-au11-6c-d2-staging-post-rollback-verify.sql next for the
-- INDEPENDENT D1/frozen post-state recertification (same critical structural assertions as pre-state (A)).
