-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D — ACTIVATION ROLLBACK. AUTHORED, NOT EXECUTED. Separate Adam approval.
-- ═══════════════════════════════════════════════════════════════════════════
-- TWO clearly-scoped rollbacks — apply the NARROWEST that resolves the problem (P0-2):
--
--   (A) OPERATIONAL-CONTINUITY ROLLBACK  ← the executable BEGIN/COMMIT block below (default).
--       Goal: restore a WORKING ordinary closeout FAST after an activation problem.
--         • REVOKE the two new functions back to INERT (undo G-10/G-11);
--         • RE-GRANT ONLY the old reconciliation RPC (undo G-01) so the ordinary weekly closeout
--           works again. The old RPC is SECURITY DEFINER — re-granting its EXECUTE restores the
--           reconciliation INSERT/UPDATE path WITHOUT re-granting any table write.
--       Deliberately does NOT re-grant the repair RPC, the direct snapshot RPC, snapshot table
--       INSERT/UPDATE, or weekly_reconciliations INSERT/UPDATE/DELETE. Those are NOT needed for
--       ordinary-closeout continuity (the reverted browser writes through the old RPC), and the
--       row-9 posture intentionally keeps weekly_reconciliations DELETE revoked. Pair with the
--       browser-revert (redeploy the pre-activation index.html).
--       This restores WRITE CAPABILITY for the ordinary closeout — it does NOT claim to restore the
--       exact pre-activation grant matrix bit-for-bit. If you need that, use (B).
--
--   (B) EXACT-RESTORE  ← the fenced, NON-EXECUTING template at the bottom. Separate approval.
--       Goal: reproduce the EXACT captured pre-activation grant matrix (repair RPC, snapshot RPC,
--       snapshot INSERT/UPDATE, weekly_reconciliations INSERT/UPDATE/DELETE). It "restores exactly"
--       ONLY insofar as each re-grant is checked against the pre-activation capture from
--       -activation-grants-validation.sql (run BEFORE Phase 1/Phase 2). The TRUE bit-exact floor is
--       the Slice-6 pre-activation restore-point pg_dump, not this script.
--
-- No function body, RLS, or data is touched by either. Env-guarded (prod or staging). Balance-free.
-- NEVER deletes reconciliation or snapshot rows — wrong values use the correction path (Option B),
-- never a drop (plan §9).
-- ─────────────────────────────────────────────────────────────────────────

-- ╔═══════════════════════════════════════════════════════════════════════╗
-- ║ (A) OPERATIONAL-CONTINUITY ROLLBACK — default; restores ordinary close ║
-- ╚═══════════════════════════════════════════════════════════════════════╝
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

-- A1 — de-activate the two new functions (→ INERT); undo G-10/G-11.
REVOKE EXECUTE ON FUNCTION public.save_weekly_closeout_with_snapshots(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.correct_goal_funding_snapshot(
  INT,INT,TEXT,NUMERIC,NUMERIC,TEXT) FROM authenticated;

-- A2 — restore ONLY the ordinary-closeout write path: re-grant the old reconciliation RPC (undo
-- G-01). SECURITY DEFINER ⇒ this alone restores reconciliation INSERT/UPDATE via the RPC. No table
-- grant, no repair/snapshot RPC, no DELETE — those stay revoked (not needed for continuity).
GRANT EXECUTE ON FUNCTION public.save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB) TO authenticated;

DO $$
BEGIN
  IF has_function_privilege('authenticated','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE')
     OR has_function_privilege('authenticated','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE')
     THEN RAISE EXCEPTION 'ROLLBACK(A): new functions still granted (should be inert)'; END IF;
  IF NOT has_function_privilege('authenticated','public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)','EXECUTE')
     THEN RAISE EXCEPTION 'ROLLBACK(A): old recon RPC not restored'; END IF;
  RAISE NOTICE 'ROLLBACK(A) PASS: new functions inert; ordinary closeout restored via the old recon RPC. Repair/snapshot RPC, table writes, and weekly_reconciliations DELETE remain revoked (row-9). Pair with the browser-revert. For an EXACT pre-activation matrix, apply section (B) under its own approval.';
END $$;

COMMIT;

-- ╔═══════════════════════════════════════════════════════════════════════╗
-- ║ (B) EXACT-RESTORE TEMPLATE — NON-EXECUTING. Separate Adam approval.     ║
-- ║ Uncomment ONLY the grants the captured pre-activation matrix shows were ║
-- ║ TRUE, verify each against -activation-grants-validation.sql's before-   ║
-- ║ Phase-1 capture, then run. The Slice-6 restore-point dump is the true   ║
-- ║ bit-exact floor if anything below is uncertain.                          ║
-- ╚═══════════════════════════════════════════════════════════════════════╝
-- BEGIN;
-- SET LOCAL search_path TO public, pg_temp;
-- -- (same environment guard as section A — copy it here before running)
-- -- Re-grant ONLY what the captured matrix recorded as granted pre-activation:
-- GRANT EXECUTE ON FUNCTION public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB) TO authenticated;         -- iff captured TRUE
-- GRANT EXECUTE ON FUNCTION public.save_goal_funding_snapshots(INT, INT, JSONB) TO authenticated;                     -- iff captured TRUE
-- GRANT INSERT, UPDATE ON public.goal_funding_snapshots TO authenticated;                                             -- iff captured TRUE (E1: no DELETE)
-- -- weekly_reconciliations pre-activation write was Supabase-DEFAULT role grants (RLS-gated), NOT an
-- -- explicit repo grant. Re-granting INSERT/UPDATE/DELETE explicitly APPROXIMATES that effective
-- -- capability; it is NOT guaranteed bit-identical to the default aclitem. For bit-exact fidelity,
-- -- restore weekly_reconciliations from the Slice-6 restore-point dump instead.
-- GRANT INSERT, UPDATE, DELETE ON public.weekly_reconciliations TO authenticated;                                     -- ONLY if the captured matrix + row-9 posture call for DELETE
-- -- Verify each grant equals the captured pre-activation value, then:
-- COMMIT;
