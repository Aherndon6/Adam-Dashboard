-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D — ACTIVATION LOCKDOWN REVOKES (Phase 2 of 2). AUTHORED, NOT EXECUTED.
-- Requires its OWN separate explicit Adam approval. RUN ONLY AFTER: (a) Phase-1 grants ran,
-- (b) the updated browser is deployed, and (c) the Week-6 supervised closeout smoke PASSED —
-- so household writers are already going through the wrapper. Running this before the new
-- browser is verified would break the ordinary closeout.
--
-- WHAT THIS DOES (Gate C register rows 1-8): makes reconciliation + goal-snapshot writes
-- RPC-ONLY for authenticated. EACH BLOCK IS INDEPENDENT — comment out any surface Adam did
-- NOT approve for revocation. Row 9 (deleteRecon anchored-week UI guard) is an index.html
-- change, NOT SQL; row 8 (weekly_reconciliations DELETE) is paired with it.
--   G-01  REVOKE old recon RPC direct EXECUTE          (wrapper calls it as definer owner)
--   G-02  REVOKE repair_commitments_for_week EXECUTE    (audit: zero callers)
--   G-03  REVOKE save_goal_funding_snapshots EXECUTE    (wrapper/Option B call it as definer)
--   G-04  REVOKE goal_funding_snapshots INSERT
--   G-05  REVOKE goal_funding_snapshots UPDATE
--   G-06  REVOKE weekly_reconciliations INSERT
--   G-07  REVOKE weekly_reconciliations UPDATE
--   G-08  REVOKE weekly_reconciliations DELETE          (pair with the deleteRecon UI guard, row 9)
--
-- EXACT-SIGNATURE for every function REVOKE (name + full ordered arg-type list — never bare name).
-- GRANT-ONLY: no function body, RLS policy, or data is touched. Env-guarded (prod or staging).
-- Spec: docs/phase-5g-1d-gatec-register-2026-07-13.md
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public, pg_temp;

DO $$
DECLARE
  v_sysid BIGINT; v_has_appenv BOOLEAN; v_appenv_total INT; v_appenv_staging INT; v_staging_marker BOOLEAN; v_env TEXT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 0;  -- <<FILL for staging rehearsal
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  v_has_appenv := to_regclass('public.app_environment') IS NOT NULL;
  v_staging_marker := false;
  IF v_has_appenv THEN
    SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
    v_staging_marker := (v_appenv_total=1 AND v_appenv_staging=1);
  END IF;
  IF v_sysid = c_prod_sysid AND NOT v_has_appenv THEN v_env := 'production';
  ELSIF v_sysid = c_staging_sysid AND v_has_appenv AND v_staging_marker THEN v_env := 'staging';
  ELSE RAISE EXCEPTION 'HARD STOP: unknown/ambiguous environment (sysid=%). Aborting lockdown revokes.', v_sysid; END IF;
  RAISE NOTICE 'LOCKDOWN REVOKES environment resolved: %', v_env;
  -- Precondition: the wrapper is ALREADY activated (Phase 1 ran) — otherwise revoking the old RPC
  -- would leave NO working closeout path.
  IF NOT has_function_privilege('authenticated','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE') THEN
    RAISE EXCEPTION 'HARD STOP: wrapper is NOT yet granted (run Phase-1 activation grants + deploy/verify the browser first). Aborting.'; END IF;
END $$;

-- ── G-01  old reconciliation RPC — REVOKE authenticated EXECUTE (exact 11-arg signature) ──
REVOKE EXECUTE ON FUNCTION public.save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB
) FROM authenticated;

-- ── G-02  repair_commitments_for_week — REVOKE authenticated EXECUTE (exact 5-arg signature) ──
REVOKE EXECUTE ON FUNCTION public.repair_commitments_for_week(
  INT, INT, TEXT, JSONB, JSONB
) FROM authenticated;

-- ── G-03  save_goal_funding_snapshots — REVOKE authenticated EXECUTE (exact 3-arg signature) ──
REVOKE EXECUTE ON FUNCTION public.save_goal_funding_snapshots(
  INT, INT, JSONB
) FROM authenticated;

-- ── G-04 / G-05  goal_funding_snapshots table — REVOKE authenticated INSERT / UPDATE ──
REVOKE INSERT ON public.goal_funding_snapshots FROM authenticated;
REVOKE UPDATE ON public.goal_funding_snapshots FROM authenticated;

-- ── G-06 / G-07 / G-08  weekly_reconciliations table — REVOKE authenticated INSERT / UPDATE / DELETE ──
-- (Current grant is Supabase-default + RLS-gated; capture the exact pre-state at preflight. These
--  REVOKEs are explicit and idempotent.)  G-08 is paired with the deleteRecon UI guard (register row 9).
REVOKE INSERT ON public.weekly_reconciliations FROM authenticated;
REVOKE UPDATE ON public.weekly_reconciliations FROM authenticated;
REVOKE DELETE ON public.weekly_reconciliations FROM authenticated;

-- Post-revoke assertions (grant-state only; the behavioral wrapper-succeeds/bypass-fails proof
-- pair is the Slice-7 real-caller smoke, Gate B runbook §7).
DO $$
BEGIN
  IF has_function_privilege('authenticated','public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)','EXECUTE')
     THEN RAISE EXCEPTION 'G-01: old recon RPC still granted'; END IF;
  IF has_function_privilege('authenticated','public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)','EXECUTE')
     THEN RAISE EXCEPTION 'G-02: repair RPC still granted'; END IF;
  IF has_function_privilege('authenticated','public.save_goal_funding_snapshots(INT, INT, JSONB)','EXECUTE')
     THEN RAISE EXCEPTION 'G-03: snapshot RPC still granted'; END IF;
  IF has_table_privilege('authenticated','public.goal_funding_snapshots','INSERT')
     OR has_table_privilege('authenticated','public.goal_funding_snapshots','UPDATE')
     THEN RAISE EXCEPTION 'G-04/05: goal_funding_snapshots table write still granted'; END IF;
  IF has_table_privilege('authenticated','public.weekly_reconciliations','INSERT')
     OR has_table_privilege('authenticated','public.weekly_reconciliations','UPDATE')
     OR has_table_privilege('authenticated','public.weekly_reconciliations','DELETE')
     THEN RAISE EXCEPTION 'G-06/07/08: weekly_reconciliations table write still granted'; END IF;
  -- SELECT must remain for both tables (the app reads them).
  IF NOT has_table_privilege('authenticated','public.goal_funding_snapshots','SELECT')
     OR NOT has_table_privilege('authenticated','public.weekly_reconciliations','SELECT')
     THEN RAISE EXCEPTION 'SELECT must remain granted (the app reads these tables)'; END IF;
  RAISE NOTICE 'LOCKDOWN REVOKES PASS: reconciliation + snapshot writes are now RPC-only for authenticated; SELECT retained; wrapper + Option B remain granted.';
END $$;

COMMIT;
