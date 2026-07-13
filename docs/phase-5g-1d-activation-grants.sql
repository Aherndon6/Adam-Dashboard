-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D — ACTIVATION GRANTS (Phase 1 of 2). AUTHORED, NOT EXECUTED.
-- Requires its OWN separate explicit Adam approval at the Gate B / Slice-7 activation step.
--
-- WHAT THIS DOES: grants authenticated EXECUTE on the two NEW functions the Slice-6 inert
-- migration deployed WITHOUT grants, making them callable — the ACTIVATION grants (Gate C
-- register rows 10, 11):
--   G-10  save_weekly_closeout_with_snapshots(...)   -> authenticated EXECUTE
--   G-11  correct_goal_funding_snapshot(...)          -> authenticated EXECUTE (owner-only in-body)
--
-- SEQUENCE (safe, no broken window — Gate B runbook §4):
--   (1) run THIS file (Phase 1) while the OLD browser is still deployed. The old browser keeps
--       using the old recon RPC (still granted); the wrapper becomes callable but nothing calls
--       it yet.  (2) deploy the updated browser (merge -> main -> Pages).  (3) verify the new
--       browser drives the wrapper (Week-6 supervised smoke).  (4) THEN run
--       phase-5g-1d-activation-revokes.sql (Phase 2) to revoke the old surfaces.
-- DO NOT run the Phase-2 revokes before the new browser is deployed and verified.
--
-- ENVIRONMENT-GUARDED: production (system_identifier 7632885393857617092, app_environment ABSENT)
-- or approved STAGING (system_identifier c_staging_sysid, app_environment PRESENT env='staging');
-- unknown/ambiguous hard-stops. GRANT-ONLY: no function body, RLS, or data is touched.
-- Spec: docs/phase-5g-1d-gatec-register-2026-07-13.md ; grounds:
--   wrapper/Option B signatures docs/phase-5g-1d-migration.sql:66/365.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public, pg_temp;

-- ██ Environment guard (identical to the migration) ██
DO $$
DECLARE
  v_sysid BIGINT; v_has_appenv BOOLEAN; v_appenv_total INT; v_appenv_staging INT; v_staging_marker BOOLEAN; v_env TEXT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 0;  -- <<FILL exact staging system_identifier for a staging rehearsal; 0 = staging hard-stops until pinned.
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  v_has_appenv := to_regclass('public.app_environment') IS NOT NULL;
  v_staging_marker := false;
  IF v_has_appenv THEN
    SELECT count(*), count(*) FILTER (WHERE env = 'staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
    v_staging_marker := (v_appenv_total = 1 AND v_appenv_staging = 1);
  END IF;
  IF v_sysid = c_prod_sysid AND NOT v_has_appenv THEN v_env := 'production';
  ELSIF v_sysid = c_staging_sysid AND v_has_appenv AND v_staging_marker THEN v_env := 'staging';
  ELSE RAISE EXCEPTION 'HARD STOP: unknown/ambiguous environment (sysid=%, app_environment=%, staging_marker=%). Aborting activation grants.', v_sysid, v_has_appenv, v_staging_marker;
  END IF;
  RAISE NOTICE 'ACTIVATION GRANTS environment resolved: %', v_env;

  -- Preconditions: the two NEW functions exist at their EXACT signatures (Slice-6 inert deploy done),
  -- and are currently INERT (no authenticated EXECUTE) — this file is what grants them.
  IF to_regprocedure('public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)') IS NULL
     OR to_regprocedure('public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: new functions not deployed (run Slice-6 inert migration first). Aborting.';
  END IF;
  IF has_function_privilege('authenticated','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE')
     OR has_function_privilege('authenticated','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE') THEN
    RAISE NOTICE 'NOTE: a new function already has authenticated EXECUTE (already activated?). GRANT is idempotent.';
  END IF;
END $$;

-- ── G-10  ACTIVATE the closeout wrapper (exact 13-arg signature) ──
GRANT EXECUTE ON FUNCTION public.save_weekly_closeout_with_snapshots(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT
) TO authenticated;

-- ── G-11  ACTIVATE Option B (routing grant; owner-only enforced IN-BODY via public.is_owner()) ──
GRANT EXECUTE ON FUNCTION public.correct_goal_funding_snapshot(
  INT,INT,TEXT,NUMERIC,NUMERIC,TEXT
) TO authenticated;

-- Post-grant assertion: both new functions now callable by authenticated; anon still has none.
DO $$
BEGIN
  IF NOT has_function_privilege('authenticated','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE') THEN
    RAISE EXCEPTION 'G-10/G-11: activation grant did not take'; END IF;
  IF has_function_privilege('anon','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE')
     OR has_function_privilege('anon','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE') THEN
    RAISE EXCEPTION 'G-10/G-11: anon must have NO EXECUTE'; END IF;
  RAISE NOTICE 'ACTIVATION GRANTS PASS: wrapper + Option B EXECUTE granted to authenticated (anon none). Old recon RPC still granted (Phase 2 revokes it after browser verification).';
END $$;

COMMIT;
