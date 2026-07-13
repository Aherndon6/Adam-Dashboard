-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D — ACTIVATION GRANTS ROLLBACK (reverses Phase 1 + Phase 2). AUTHORED, NOT EXECUTED.
-- Requires its OWN separate explicit Adam approval. Restores the PRE-ACTIVATION grant posture:
--   • REVOKE the two new functions back to INERT (undo G-10/G-11);
--   • RE-GRANT the old recon RPC, repair RPC, snapshot RPC, and the two table write-grant sets
--     (undo G-01..G-08) so the pre-activation write paths work again.
-- GRANT-ONLY: no function body, RLS, or data is touched. Env-guarded (prod or staging).
--
-- NOTE on weekly_reconciliations (G-06/07/08): the PRE-activation state was Supabase-default role
-- grants (RLS-gated), not an explicit repo grant. This rollback RE-GRANTS INSERT/UPDATE/DELETE
-- explicitly, which restores the effective write capability; if bit-exact default-grant restoration
-- is required, restore from the Slice-6 pre-activation restore point instead. Capture the exact
-- pre-state with -validation.sql BEFORE Phase 2 so rollback is verifiable.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public, pg_temp;

DO $$
DECLARE v_sysid BIGINT; v_has_appenv BOOLEAN; v_appenv_total INT; v_appenv_staging INT; v_staging_marker BOOLEAN;
  c_prod_sysid CONSTANT BIGINT := 7632885393857617092; c_staging_sysid CONSTANT BIGINT := 0;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  v_has_appenv := to_regclass('public.app_environment') IS NOT NULL; v_staging_marker := false;
  IF v_has_appenv THEN SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
    v_staging_marker := (v_appenv_total=1 AND v_appenv_staging=1); END IF;
  IF (v_sysid=c_prod_sysid AND NOT v_has_appenv) THEN RAISE NOTICE 'ROLLBACK env: production';
  ELSIF (v_sysid=c_staging_sysid AND v_has_appenv AND v_staging_marker) THEN RAISE NOTICE 'ROLLBACK env: staging';
  ELSE RAISE EXCEPTION 'HARD STOP: unknown/ambiguous environment (sysid=%). Aborting rollback.', v_sysid; END IF;
END $$;

-- Undo Phase 1 (de-activate the new functions → INERT)
REVOKE EXECUTE ON FUNCTION public.save_weekly_closeout_with_snapshots(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.correct_goal_funding_snapshot(
  INT,INT,TEXT,NUMERIC,NUMERIC,TEXT) FROM authenticated;

-- Undo Phase 2 (restore the pre-activation write paths)
GRANT EXECUTE ON FUNCTION public.save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_goal_funding_snapshots(INT, INT, JSONB) TO authenticated;
GRANT INSERT, UPDATE ON public.goal_funding_snapshots TO authenticated;               -- no DELETE (matches E1)
GRANT INSERT, UPDATE, DELETE ON public.weekly_reconciliations TO authenticated;

DO $$
BEGIN
  IF has_function_privilege('authenticated','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE')
     OR has_function_privilege('authenticated','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE')
     THEN RAISE EXCEPTION 'ROLLBACK: new functions still granted (should be inert)'; END IF;
  IF NOT has_function_privilege('authenticated','public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)','EXECUTE')
     THEN RAISE EXCEPTION 'ROLLBACK: old recon RPC not restored'; END IF;
  RAISE NOTICE 'ROLLBACK PASS: pre-activation grant posture restored; new functions inert; old write paths re-granted.';
END $$;

COMMIT;
