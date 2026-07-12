-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (pkwotgqivgaapwuqgwqb)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Slice 2 — STAGING TEMPORARY GRANT. Authored, NOT executed.
-- Grants authenticated EXECUTE on the two new functions FOR THE STAGING REAL-CALLER MATRIX
-- ONLY. It HARD-STOPS if run against production (system_identifier fingerprint). It must be
-- reverted in the same session with phase-5g-1d-ungrant.sql; validation then proves the
-- restored INERT state == the intended inert production state. This grant is NEVER part of the
-- committed production migration.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
BEGIN
  -- EXACT staging fingerprint — production and any unknown/ambiguous environment hard-stop.
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN
    RAISE EXCEPTION 'HARD STOP: this is PRODUCTION — staging temporary grant refused. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: app_environment sentinel absent — not the expected staging env. Aborting.'; END IF;
  SELECT count(*),
         count(*) FILTER (WHERE env='staging')
    INTO v_appenv_total, v_appenv_staging
    FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint (sysid=%, appenv total=%, staging=%). Aborting.', v_sysid, v_appenv_total, v_appenv_staging; END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.save_weekly_closeout_with_snapshots(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.correct_goal_funding_snapshot(
  INT,INT,TEXT,NUMERIC,NUMERIC,TEXT
) TO authenticated;

SELECT 'staging-grant' AS check,
       has_function_privilege('authenticated','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE') AS wrapper_exec,
       has_function_privilege('authenticated','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE') AS optionb_exec;

COMMIT;
