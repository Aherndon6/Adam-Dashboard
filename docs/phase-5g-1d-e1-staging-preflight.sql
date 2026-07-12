-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — STAGING E1 PREFLIGHT (READ ONLY). Authored, NOT executed.
-- Confirms staging is ready to receive the E1 snapshot layer + the synthetic Week-5 fixture,
-- and captures the read-only baselines the validation will compare (reconciliation RPC md5,
-- goal_registry fingerprint, app_environment state). PRODUCTION IS NOT TOUCHED.
--
-- ── The production E1 RPC md5 to PIN for the identity proof (Adam runs this READ-ONLY on
--    PRODUCTION once and pastes the value into phase-5g-1d-e1-staging-validation.sql LOCAL):
--       SELECT md5(pg_get_functiondef('public.save_goal_funding_snapshots(INT,INT,JSONB)'::regprocedure));
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
BEGIN
  RAISE NOTICE 'EXECUTION IDENTITY: current_user=%, session_user=%', current_user, session_user;

  -- (a) exact staging fingerprint; production and unknown hard-stop
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production system_identifier — staging-only preflight. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent — not the approved staging env. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint (sysid=%, appenv rows=%, env=staging rows=%). Aborting.', v_sysid, v_appenv_total, v_appenv_staging; END IF;

  -- (b) dependencies the E1 body + fixture need
  IF to_regclass('public.goal_registry') IS NULL OR to_regclass('public.weekly_reconciliations') IS NULL
     OR to_regclass('public.cash_commitments') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry / weekly_reconciliations / cash_commitments missing. Aborting.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='fn_set_updated_at') THEN
    RAISE EXCEPTION 'HARD STOP: public.fn_set_updated_at() missing (5D-1). Aborting.'; END IF;
  IF to_regprocedure('public.is_allowed_user()') IS NULL OR to_regprocedure('public.can_write_financials()') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: is_allowed_user()/can_write_financials() missing. Aborting.'; END IF;
  IF to_regprocedure('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: deployed reconciliation RPC missing on staging. Aborting.'; END IF;

  -- (c) the E1 objects must be ABSENT (fresh re-deploy after the C2 rollback)
  IF to_regclass('public.goal_funding_snapshots') IS NOT NULL THEN RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots already exists — not a fresh E1 deploy. Aborting.'; END IF;
  IF to_regprocedure('public.save_goal_funding_snapshots(INT,INT,JSONB)') IS NOT NULL THEN RAISE EXCEPTION 'HARD STOP: save_goal_funding_snapshots already exists. Aborting.'; END IF;

  -- (d) the eligible-nine must exist in goal_registry (fixture FK target)
  IF (SELECT count(*) FROM public.goal_registry WHERE id = ANY(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'])) <> 9 THEN
    RAISE EXCEPTION 'HARD STOP: staging goal_registry is missing one or more of the eligible nine (fixture FK target). Seed goal_registry first. Aborting.'; END IF;

  RAISE NOTICE 'STAGING E1 PREFLIGHT PASS: staging fingerprint OK; deps present; E1 objects absent; eligible-nine registry present.';
END $$;

-- Read-only BASELINES to pin (compared post-migration by the validation):
SELECT 'baseline-recon-rpc-md5' AS check, md5(pg_get_functiondef('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)'::regprocedure)) AS val;
SELECT 'baseline-goal-registry' AS check, md5(string_agg(id||'|'||coalesce(target::text,'')||'|'||coalesce(auto::text,''), ',' ORDER BY id)) AS val FROM public.goal_registry;
SELECT 'baseline-app-environment' AS check, md5(coalesce(string_agg(env, ',' ORDER BY env),'')) AS val, count(*) AS total FROM public.app_environment;

COMMIT;
