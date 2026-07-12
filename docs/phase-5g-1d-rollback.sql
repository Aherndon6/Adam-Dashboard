-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Slice 2 — ROLLBACK (additive drop only). Authored, NOT executed.
-- Requires its OWN separate explicit Adam approval. Drops EXACTLY the two new functions.
-- The E1 objects (goal_funding_snapshots table + save_goal_funding_snapshots RPC) and the
-- deployed reconciliation RPC are UNTOUCHED. NO snapshot/reconciliation DATA is deleted —
-- wrong values use the correction path, never a drop. Because the inert migration granted
-- nothing, no grant restoration is needed; if a staging temporary grant is still present,
-- run phase-5g-1d-ungrant.sql first.
-- ENVIRONMENT-GUARDED: rehearsable on approved STAGING and runnable on PRODUCTION; unknown
-- hard-stops (same dual guard as the migration, so the staging rollback rehearsal path exists).
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_has_appenv BOOLEAN; v_appenv_total INT; v_appenv_staging INT; v_staging_marker BOOLEAN;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 0;  -- <<FILL: exact staging system_identifier (same value as migration). 0 = UNSET.
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  v_has_appenv := to_regclass('public.app_environment') IS NOT NULL;
  v_staging_marker := false;
  IF v_has_appenv THEN   -- only query app_environment when it exists (see migration note)
    SELECT count(*), count(*) FILTER (WHERE env = 'staging') INTO v_appenv_total, v_appenv_staging
      FROM public.app_environment;
    v_staging_marker := (v_appenv_total = 1 AND v_appenv_staging = 1);
  END IF;
  IF (v_sysid = c_prod_sysid AND NOT v_has_appenv) THEN
    RAISE NOTICE 'ROLLBACK environment: production';
  ELSIF (v_sysid = c_staging_sysid AND v_has_appenv AND v_staging_marker) THEN
    RAISE NOTICE 'ROLLBACK environment: staging (rehearsal)';
  ELSE
    RAISE EXCEPTION 'HARD STOP: unknown/ambiguous environment (sysid=%, app_environment=%, staging_marker=%). Aborting rollback.', v_sysid, v_has_appenv, v_staging_marker;
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.save_weekly_closeout_with_snapshots(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT);
DROP FUNCTION IF EXISTS public.correct_goal_funding_snapshot(
  INT,INT,TEXT,NUMERIC,NUMERIC,TEXT);

-- Prove exactly the two are gone and the deployed objects remain.
DO $$
BEGIN
  IF to_regprocedure('public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)') IS NOT NULL
     OR to_regprocedure('public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)') IS NOT NULL THEN
    RAISE EXCEPTION 'RB: a new function still exists after drop'; END IF;
  IF to_regprocedure('public.save_goal_funding_snapshots(INT,INT,JSONB)') IS NULL
     OR to_regprocedure('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)') IS NULL
     OR to_regclass('public.goal_funding_snapshots') IS NULL THEN
    RAISE EXCEPTION 'RB: a deployed object was affected — must remain intact'; END IF;
  RAISE NOTICE 'ROLLBACK PASS: two new functions dropped; E1 + reconciliation RPC intact; no data deleted.';
END $$;

COMMIT;
