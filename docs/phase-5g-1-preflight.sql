-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1 Preflight (READ-ONLY)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — DO NOT RUN until the staging gate (Spec §3) is satisfied and Adam
-- approves. Read-only: proves the target is staging, proves the 5G-1 object
-- names are unused, and captures baseline evidence (Spec §4.2).
--
-- Timing: run AFTER the staging marker exists and AFTER the schema-only DB
-- baseline dump is captured, and BEFORE phase-5g-1-migration.sql (Spec §4.2, §10).
-- Save the output as exports/db-baseline-5G-1-preflight-<timestamp>.txt.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

-- ── STAGING GUARD (shared block; identical in preflight/migration/validation/rollback/seed) ─
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: app_environment missing. Run phase-5g-1-staging-env-marker.sql first. Aborting.';
  END IF;
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing (accounts/transactions). Aborting.';
  END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (amex_gold=-8248.50). Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (transactions=% > 25). Aborting.', v_tx; END IF;
END $$;

-- ── P1: target 5G-1 tables must NOT already exist ───────────────────────────
SELECT 'P1' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.tables
         WHERE table_schema='public' AND table_name IN ('planned_outflows','outflow_events')) AS expected_true;

-- ── P2: no existing policies with the 5G-1 names ────────────────────────────
SELECT 'P2' AS check,
       NOT EXISTS (SELECT 1 FROM pg_policies
         WHERE schemaname='public' AND tablename IN ('planned_outflows','outflow_events')) AS expected_true;

-- ── P3: no existing indexes/triggers/functions with the 5G-1 names ──────────
SELECT 'P3a' AS check,
       NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                   AND indexname IN ('uq_planned_outflows_key','idx_planned_outflows_status_due',
                                     'idx_outflow_events_plan_date','idx_outflow_events_type')) AS expected_true;
SELECT 'P3b' AS check,
       NOT EXISTS (SELECT 1 FROM pg_trigger
                   WHERE tgname IN ('set_planned_outflows_updated_at','guard_planned_outflows_immutable',
                                    'block_outflow_events_mutation')) AS expected_true;
SELECT 'P3c' AS check,
       NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                   WHERE n.nspname='public'
                     AND p.proname IN ('fn_block_outflow_event_mutation','fn_guard_planned_outflows_immutable')) AS expected_true;

-- ── P4: dependencies that MUST exist ────────────────────────────────────────
SELECT 'P4a' AS check, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='fn_set_updated_at') AS expected_true;
SELECT 'P4b' AS check, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='can_write_financials') AS expected_true;
SELECT 'P4c' AS check, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='is_allowed_user') AS expected_true;
-- P4d: all three accounts the guard + migration reference must exist.
SELECT 'P4d' AS check,
       (SELECT count(*) FROM public.accounts
        WHERE key IN ('amex_gold','amex_savings','truist_checking')) = 3 AS expected_true;

-- ── P5: baseline evidence — object inventory snapshot (informational) ────────
SELECT 'P5-tables'   AS evidence, count(*) AS public_tables FROM information_schema.tables WHERE table_schema='public';
SELECT 'P5-accounts' AS evidence, count(*) AS accounts_rows FROM public.accounts;
SELECT 'P5-env'      AS evidence, env FROM public.app_environment;
-- Capture these lines into the baseline evidence file alongside the
-- pg_dump --schema-only baseline (Spec §4.2).
