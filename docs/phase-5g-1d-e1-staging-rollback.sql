-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — STAGING E1 ROLLBACK. Authored, NOT executed.
-- Drops the staging E1 snapshot layer (RPC then table). Run AFTER the fixture cleanup
-- (phase-5g-1d-fixture-cleanup.sql) so no snapshot rows remain. Additive rollback: touches
-- ONLY the two E1 objects; no legacy reconciliation object, goal_registry, or the staging
-- marker is changed. PRODUCTION IS NOT TOUCHED. Exact staging fingerprint; else hard-stops.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production system_identifier — staging-only rollback. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint. Aborting.'; END IF;
  -- refuse to drop while snapshot rows still exist (run the fixture cleanup first)
  IF to_regclass('public.goal_funding_snapshots') IS NOT NULL
     AND (SELECT count(*) FROM public.goal_funding_snapshots) <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots is non-empty — run phase-5g-1d-fixture-cleanup.sql first. Aborting.'; END IF;
END $$;

DROP FUNCTION IF EXISTS public.save_goal_funding_snapshots(INT,INT,JSONB);
DROP TABLE    IF EXISTS public.goal_funding_snapshots;

DO $$
BEGIN
  IF to_regclass('public.goal_funding_snapshots') IS NOT NULL
     OR to_regprocedure('public.save_goal_funding_snapshots(INT,INT,JSONB)') IS NOT NULL THEN
    RAISE EXCEPTION 'RB: E1 object still present after drop'; END IF;
  -- prove legacy objects + marker untouched
  IF to_regprocedure('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)') IS NULL
     OR to_regclass('public.goal_registry') IS NULL OR to_regclass('public.weekly_reconciliations') IS NULL THEN
    RAISE EXCEPTION 'RB: a legacy object is missing — rollback must be additive only'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') THEN
    RAISE EXCEPTION 'RB: staging marker changed'; END IF;
  RAISE NOTICE 'STAGING E1 ROLLBACK PASS: two E1 objects dropped; reconciliation RPC / goal_registry / weekly_reconciliations / staging marker intact.';
END $$;

COMMIT;
