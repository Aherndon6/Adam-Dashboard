-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1 Validation (post-migration SCHEMA validation)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — run on STAGING immediately after phase-5g-1-migration.sql and BEFORE
-- the seed. Schema/RLS/trigger/constraint validation only. All V-checks must
-- return their documented expected value.
--
-- SEED validation (S1/S2/S3) lives in a SEPARATE file
-- (phase-5g-1-seed-mint-staging-validation.sql), run only AFTER the seed. This
-- file's V7 asserts the tables are EMPTY, so running it post-seed would falsely
-- fail — run this pre-seed. All probes below insert-then-rollback, so this file
-- is non-mutating and safe to re-run pre-seed.
--
-- Enforcement-layer note (V9 / #6): append-only for the `authenticated` role via
-- PostgREST is enforced by RLS STRUCTURALLY — no UPDATE/DELETE policy (V3d) +
-- INSERT-only grant (V4f). V9 proves the TRIGGER layer, which additionally blocks
-- privileged/RLS-bypassing roles (service_role, and the SQL-editor role this runs
-- as). V9 does NOT run as `authenticated` and does NOT simulate RLS. RLS
-- *behavioral* verification for real callers is a separate live-smoke step (Spec §14).
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

-- ── STAGING GUARD ───────────────────────────────────────────────────────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.'; END IF;
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing. Aborting.'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint. Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (tx=%). Aborting.', v_tx; END IF;
END $$;

-- ── V1: both tables exist ───────────────────────────────────────────────────
SELECT 'V1' AS check,
       (SELECT count(*) FROM information_schema.tables
        WHERE table_schema='public' AND table_name IN ('planned_outflows','outflow_events')) = 2 AS expected_true;

-- ── V2: RLS enabled on both ─────────────────────────────────────────────────
SELECT 'V2' AS check, bool_and(c.relrowsecurity) AS expected_true
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname IN ('planned_outflows','outflow_events');

-- ── V3: policy counts / shape ───────────────────────────────────────────────
SELECT 'V3a' AS check, (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='planned_outflows') = 3 AS expected_true;
SELECT 'V3b' AS check, (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='outflow_events') = 2 AS expected_true;
SELECT 'V3c' AS check, NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='planned_outflows' AND cmd='DELETE') AS expected_true;
SELECT 'V3d' AS check, NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='outflow_events' AND cmd IN ('UPDATE','DELETE')) AS expected_true;

-- ── V4: predicates + roles + grants ─────────────────────────────────────────
SELECT 'V4a' AS check,
       bool_and(qual LIKE '%can_write_financials%' OR with_check LIKE '%can_write_financials%') AS expected_true
  FROM pg_policies WHERE schemaname='public' AND tablename IN ('planned_outflows','outflow_events') AND cmd IN ('INSERT','UPDATE','DELETE');
SELECT 'V4b' AS check,
       bool_and(qual LIKE '%is_allowed_user%') AS expected_true
  FROM pg_policies WHERE schemaname='public' AND tablename IN ('planned_outflows','outflow_events') AND cmd='SELECT';
SELECT 'V4c' AS check,
       bool_and(roles = ARRAY['authenticated']::name[]) AS expected_true
  FROM pg_policies WHERE schemaname='public' AND tablename IN ('planned_outflows','outflow_events');
SELECT 'V4d' AS check,
       NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
         AND tablename IN ('planned_outflows','outflow_events') AND ('public' = ANY(roles) OR 'anon' = ANY(roles))) AS expected_true;
SELECT 'V4e' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants
         WHERE table_schema='public' AND table_name IN ('planned_outflows','outflow_events') AND grantee='anon') AS expected_true;
SELECT 'V4f' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants
         WHERE table_schema='public' AND table_name='outflow_events' AND grantee='authenticated'
           AND privilege_type IN ('UPDATE','DELETE')) AS expected_true;
SELECT 'V4g' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants
         WHERE table_schema='public' AND table_name='planned_outflows' AND grantee='authenticated'
           AND privilege_type='DELETE') AS expected_true;
-- V4h/V4i: authenticated grant is EXACTLY the intended set (catches stray
-- TRUNCATE/REFERENCES/TRIGGER/DELETE left by Supabase default privileges, not
-- just UPDATE/DELETE). array_agg is NULL if no grants → correctly not-equal → false.
SELECT 'V4h' AS check,
       (SELECT array_agg(privilege_type::text ORDER BY privilege_type::text)
          FROM information_schema.role_table_grants
         WHERE table_schema='public' AND table_name='outflow_events' AND grantee='authenticated')
       = ARRAY['INSERT','SELECT']::text[] AS expected_true;
SELECT 'V4i' AS check,
       (SELECT array_agg(privilege_type::text ORDER BY privilege_type::text)
          FROM information_schema.role_table_grants
         WHERE table_schema='public' AND table_name='planned_outflows' AND grantee='authenticated')
       = ARRAY['INSERT','SELECT','UPDATE']::text[] AS expected_true;

-- ── V5: triggers present ────────────────────────────────────────────────────
SELECT 'V5a' AS check, EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='block_outflow_events_mutation') AS expected_true;
SELECT 'V5b' AS check, EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='guard_planned_outflows_immutable') AS expected_true;

-- ── V6: shape ───────────────────────────────────────────────────────────────
SELECT 'V6a' AS check, EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='set_planned_outflows_updated_at') AS expected_true;
SELECT 'V6b' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='outflow_events' AND column_name='updated_at') AS expected_true;
SELECT 'V6c' AS check,
       (SELECT count(*) FROM information_schema.columns
        WHERE table_schema='public' AND table_name IN ('planned_outflows','outflow_events')
          AND column_name='created_by_user_id' AND is_nullable='YES') = 2 AS expected_true;
SELECT 'V6d' AS check,
       (SELECT is_nullable FROM information_schema.columns
        WHERE table_schema='public' AND table_name='outflow_events' AND column_name='funding_account_key') = 'NO' AS expected_true;

-- ── V7: schema-only migration — both tables empty (run PRE-seed) ─────────────
SELECT 'V7' AS check,
       (SELECT count(*) FROM public.planned_outflows) = 0
       AND (SELECT count(*) FROM public.outflow_events) = 0 AS expected_true;

-- ── V8: constraints present (existence) ─────────────────────────────────────
SELECT 'V8a' AS check, EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_outflow_events_sign') AS expected_true;
SELECT 'V8b' AS check, EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_outflow_events_memo') AS expected_true;
SELECT 'V8c' AS check, EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_planned_outflows_transfer_funding') AS expected_true;

-- ── V8d: constraints BEHAVE — bad event rows are rejected (probe, rolled back) ─
DO $$
DECLARE
  v_pid UUID;
  v_neg_setaside    BOOLEAN := false;
  v_pos_paid        BOOLEAN := false;
  v_memoless_adjust BOOLEAN := false;
  v_null_fund       BOOLEAN := false;
BEGIN
  BEGIN
    INSERT INTO public.planned_outflows (key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key)
      VALUES ('__v8d_probe__','V8d probe','save_up_bill', DATE '2027-03-01','transfer_funded','amex_savings','truist_checking')
      RETURNING id INTO v_pid;

    BEGIN INSERT INTO public.outflow_events (planned_outflow_id,event_type,amount_cents,event_date,funding_account_key)
            VALUES (v_pid,'set_aside',-500, DATE '2027-03-01','amex_savings');   -- set_aside must be > 0
      EXCEPTION WHEN OTHERS THEN v_neg_setaside := true; END;
    BEGIN INSERT INTO public.outflow_events (planned_outflow_id,event_type,amount_cents,event_date,funding_account_key)
            VALUES (v_pid,'paid',500, DATE '2027-03-01','amex_savings');         -- paid must be < 0
      EXCEPTION WHEN OTHERS THEN v_pos_paid := true; END;
    BEGIN INSERT INTO public.outflow_events (planned_outflow_id,event_type,amount_cents,event_date,funding_account_key)
            VALUES (v_pid,'adjust',100, DATE '2027-03-01','amex_savings');       -- adjust requires memo
      EXCEPTION WHEN OTHERS THEN v_memoless_adjust := true; END;
    BEGIN INSERT INTO public.outflow_events (planned_outflow_id,event_type,amount_cents,event_date,funding_account_key)
            VALUES (v_pid,'set_aside',100, DATE '2027-03-01', NULL);             -- funding_account_key NOT NULL
      EXCEPTION WHEN OTHERS THEN v_null_fund := true; END;

    RAISE EXCEPTION 'V8D_PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%V8D_PROBE_ROLLBACK%' THEN RAISE; END IF;
  END;
  IF NOT (v_neg_setaside AND v_pos_paid AND v_memoless_adjust AND v_null_fund) THEN
    RAISE EXCEPTION 'V8d FAIL: constraint rejection wrong (neg_setaside=%, pos_paid=%, memoless_adjust=%, null_fund=%).',
      v_neg_setaside, v_pos_paid, v_memoless_adjust, v_null_fund;
  END IF;
  RAISE NOTICE 'V8d PASS: sign/memo/funding constraints reject bad rows; probe rolled back.';
END $$;

-- ── V9: APPEND-ONLY TRIGGER PROOF (privileged role; NOT an RLS test — see header)
DO $$
DECLARE v_update_blocked BOOLEAN := false; v_delete_blocked BOOLEAN := false;
BEGIN
  BEGIN
    INSERT INTO public.planned_outflows (key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key)
      VALUES ('__v9_probe__','V9 probe','save_up_bill', DATE '2027-03-01','transfer_funded','amex_savings','truist_checking');
    INSERT INTO public.outflow_events (planned_outflow_id,event_type,amount_cents,event_date,funding_account_key)
      SELECT id,'set_aside',1000, DATE '2027-03-01','amex_savings' FROM public.planned_outflows WHERE key='__v9_probe__';

    BEGIN UPDATE public.outflow_events SET memo='mutate' WHERE event_type='set_aside' AND amount_cents=1000;
      EXCEPTION WHEN OTHERS THEN v_update_blocked := true; END;
    BEGIN DELETE FROM public.outflow_events WHERE event_type='set_aside' AND amount_cents=1000;
      EXCEPTION WHEN OTHERS THEN v_delete_blocked := true; END;

    RAISE EXCEPTION 'V9_PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%V9_PROBE_ROLLBACK%' THEN RAISE; END IF;
  END;
  IF NOT (v_update_blocked AND v_delete_blocked) THEN
    RAISE EXCEPTION 'V9 FAIL: outflow_events append-only trigger NOT enforced (update_blocked=%, delete_blocked=%).',
      v_update_blocked, v_delete_blocked;
  END IF;
  RAISE NOTICE 'V9 PASS: outflow_events UPDATE and DELETE rejected by trigger; probe rolled back.';
END $$;

-- ── V9b: planned_outflows IMMUTABILITY PROOF (key/created_at immutable; label editable)
DO $$
DECLARE v_key_blocked BOOLEAN := false; v_created_blocked BOOLEAN := false; v_label_ok BOOLEAN := false;
BEGIN
  BEGIN
    INSERT INTO public.planned_outflows (key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key)
      VALUES ('__v9b_probe__','V9b probe','save_up_bill', DATE '2027-03-01','transfer_funded','amex_savings','truist_checking');

    BEGIN UPDATE public.planned_outflows SET key='__v9b_renamed__' WHERE key='__v9b_probe__';
      EXCEPTION WHEN OTHERS THEN v_key_blocked := true; END;
    BEGIN UPDATE public.planned_outflows SET created_at = now() - interval '1 day' WHERE key='__v9b_probe__';
      EXCEPTION WHEN OTHERS THEN v_created_blocked := true; END;
    BEGIN UPDATE public.planned_outflows SET label='edited' WHERE key='__v9b_probe__'; v_label_ok := true;
      EXCEPTION WHEN OTHERS THEN v_label_ok := false; END;

    RAISE EXCEPTION 'V9B_PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%V9B_PROBE_ROLLBACK%' THEN RAISE; END IF;
  END;
  IF NOT (v_key_blocked AND v_created_blocked AND v_label_ok) THEN
    RAISE EXCEPTION 'V9b FAIL: immutability wrong (key_blocked=%, created_blocked=%, label_ok=%).',
      v_key_blocked, v_created_blocked, v_label_ok;
  END IF;
  RAISE NOTICE 'V9b PASS: key/created_at immutable; label editable; probe rolled back.';
END $$;

-- ── V10: rollup semantics (documentation) ───────────────────────────────────
--   set_aside_balance_cents(plan) = SUM(amount_cents) over its outflow_events.
SELECT 'V10' AS check, 'rollup = SUM(amount_cents) per plan; no stored balance' AS note;

-- Seed validation (S1/S2/S3) is in phase-5g-1-seed-mint-staging-validation.sql.
