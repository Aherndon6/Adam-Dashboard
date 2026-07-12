-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (pkwotgqivgaapwuqgwqb)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Slice 2 — STAGING UNGRANT (restore INERT). Authored, NOT executed.
-- Reverts the temporary staging grant so the final staging grant state == the intended inert
-- production state (no PUBLIC/anon/authenticated EXECUTE on either new function). Run AFTER the
-- real-caller matrix. HARD-STOPS on production.
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
    RAISE EXCEPTION 'HARD STOP: this is PRODUCTION — ungrant script is staging-only. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: app_environment sentinel absent — not the expected staging env. Aborting.'; END IF;
  SELECT count(*),
         count(*) FILTER (WHERE env='staging')
    INTO v_appenv_total, v_appenv_staging
    FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint (sysid=%, appenv total=%, staging=%). Aborting.', v_sysid, v_appenv_total, v_appenv_staging; END IF;
END $$;

REVOKE ALL ON FUNCTION public.save_weekly_closeout_with_snapshots(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.correct_goal_funding_snapshot(
  INT,INT,TEXT,NUMERIC,NUMERIC,TEXT
) FROM PUBLIC, anon, authenticated;

-- Prove restored INERT state == intended inert production state (0 EXECUTE grants).
DO $$
DECLARE v_grants INT;
BEGIN
  -- anon/authenticated inherit any PUBLIC grant; has_function_privilege cannot take PUBLIC.
  SELECT count(*) INTO v_grants FROM (
    SELECT 1 WHERE has_function_privilege('anon','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE')
    UNION ALL SELECT 1 WHERE has_function_privilege('authenticated','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE')
    UNION ALL SELECT 1 WHERE has_function_privilege('anon','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE')
    UNION ALL SELECT 1 WHERE has_function_privilege('authenticated','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE')) g;
  IF v_grants <> 0 THEN RAISE EXCEPTION 'UNGRANT: % EXECUTE grant(s) remain — not restored to inert', v_grants; END IF;
  RAISE NOTICE 'UNGRANT PASS: staging restored to intended inert production grant state (0 EXECUTE).';
END $$;

COMMIT;
