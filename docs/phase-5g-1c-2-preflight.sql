-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 Preflight (READ-ONLY)
-- ═══════════════════════════════════════════════════════════════════════════
-- Goal Funding State Integrity — goal_funding_snapshots + save_goal_funding_snapshots RPC.
--
-- DRAFT — DO NOT RUN until the staging gate is satisfied and Adam approves.
-- STAGING ONLY (project pkwotgqivgaapwuqgwqb). Read-only: proves the target is
-- staging, proves the 5G-1C-2 object names are unused, proves the dependencies
-- exist, and captures baseline evidence.
--
-- Timing: run AFTER the staging marker exists and AFTER the schema-only DB
-- baseline dump is captured, and BEFORE phase-5g-1c-2-migration.sql.
-- Save the output as exports/db-baseline-5G-1C-2-preflight-<timestamp>.txt.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

-- ── STAGING GUARD (shared block; identical across the 5G-1C-2 package) ────────
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

-- ── P1: target 5G-1C-2 table must NOT already exist ─────────────────────────
SELECT 'P1' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.tables
         WHERE table_schema='public' AND table_name='goal_funding_snapshots') AS expected_true;

-- ── P2: no existing policies with the 5G-1C-2 table name ────────────────────
SELECT 'P2' AS check,
       NOT EXISTS (SELECT 1 FROM pg_policies
         WHERE schemaname='public' AND tablename='goal_funding_snapshots') AS expected_true;

-- ── P3: no existing indexes/triggers/functions with the 5G-1C-2 names ───────
SELECT 'P3a' AS check,
       NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                   AND indexname IN ('idx_gfs_year_week','uq_gfs_year_week_goal')) AS expected_true;
SELECT 'P3b' AS check,
       NOT EXISTS (SELECT 1 FROM pg_trigger
                   WHERE tgname='set_goal_funding_snapshots_updated_at') AS expected_true;
SELECT 'P3c' AS check,
       NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                   WHERE n.nspname='public' AND p.proname='save_goal_funding_snapshots') AS expected_true;

-- ── P4: dependencies that MUST exist ────────────────────────────────────────
SELECT 'P4a' AS check, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='fn_set_updated_at') AS expected_true;
SELECT 'P4b' AS check, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='can_write_financials') AS expected_true;
SELECT 'P4c' AS check, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='is_allowed_user') AS expected_true;
-- P4d: FK parent table goal_registry must exist.
SELECT 'P4d' AS check, to_regclass('public.goal_registry') IS NOT NULL AS expected_true;
-- P4e: reconciliation table weekly_reconciliations must exist (RPC reconciled-week guard).
SELECT 'P4e' AS check, to_regclass('public.weekly_reconciliations') IS NOT NULL AS expected_true;

-- ── P5: FK-type + schema assumptions this migration is built on ──────────────
-- P5a: goal_registry.id is TEXT (the FK goal_id → goal_registry(id) requires it).
SELECT 'P5a' AS check,
       (SELECT data_type FROM information_schema.columns
        WHERE table_schema='public' AND table_name='goal_registry' AND column_name='id') = 'text' AS expected_true;
-- P5b: weekly_reconciliations HAS week_num — the RPC's reconciled-week lookup key.
SELECT 'P5b' AS check,
       EXISTS (SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='weekly_reconciliations' AND column_name='week_num') AS expected_true;
-- P5c: weekly_reconciliations has NO model_year column. This is WHY the RPC and
--      seed validate reconciliation by week_num ALONE (inherited from 5F-1). Safe
--      only under the current single 31-week 2026 model — documented, not a defect.
SELECT 'P5c' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='weekly_reconciliations' AND column_name='model_year') AS expected_true;

-- ── P6: baseline evidence — inventory + reconciled-week map (informational) ──
SELECT 'P6-tables'    AS evidence, count(*) AS public_tables FROM information_schema.tables WHERE table_schema='public';
SELECT 'P6-goals'     AS evidence, count(*) AS goal_registry_rows FROM public.goal_registry;
SELECT 'P6-env'       AS evidence, env FROM public.app_environment;
-- Reconciled model weeks currently present (drives the seed-anchor week choice; D2 = model wk 5).
SELECT 'P6-recweeks'  AS evidence, week_num FROM public.weekly_reconciliations ORDER BY week_num;
-- Goals that are EXCLUDED from 5G-1C-2 snapshots by policy (auto + holding/deferred),
-- for eyeball confirmation before the seed. (adam_401k via auto; the rest by id.)
SELECT 'P6-excluded'  AS evidence, id, name, auto
  FROM public.goal_registry
 WHERE COALESCE(auto,false) = true
    OR id IN ('wewe_rccl','wewe_dcl','taxable_etf')
 ORDER BY id;
-- Capture these lines into the baseline evidence file alongside the pg_dump baseline.
