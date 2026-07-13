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
--   (B) EXACT ACL RESTORATION  ← the fenced, NON-EXECUTING template at the bottom. Separate approval.
--       Goal: reproduce the EXACT captured pre-activation grant matrix (repair RPC, snapshot RPC,
--       snapshot INSERT/UPDATE, weekly_reconciliations INSERT/UPDATE/DELETE) by generating narrow
--       GRANT/REVOKE statements FROM the captured privilege matrix — each re-grant checked against
--       the pre-activation capture from -activation-grants-validation.sql (run BEFORE Phase 1/Phase 2).
--       This is a GRANT-ONLY operation.
--
--   ⚠ THE SLICE-6 DUMP IS NOT A GRANT-RESTORE TOOL. It is the catastrophic DISASTER-RECOVERY floor
--       ONLY. It was captured BEFORE Slice 6 and BEFORE the supervised Week-6 closeout, so it predates
--       the first production write. After ANY post-dump production write (the Week-6 reconciliation +
--       nine snapshots, or later), restoring the dump would ALSO revert that data and is NOT a routine
--       Gate B rollback. A dump restore is a deliberate DR action requiring: (1) separate DR approval;
--       (2) explicit acknowledgement of the restore-point timestamp; (3) a plan to preserve/replay
--       post-dump data or explicit acceptance of its loss; (4) verification that the restore scope
--       will not unintentionally overwrite valid later reconciliation/snapshot state. NEVER use it to
--       "restore grants" — that is (B)'s job, from the captured matrix.
--
-- No function body, RLS, or data is touched by (A) or (B). Env-guarded (prod or staging). Balance-free.
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
-- ║ (B) EXACT ACL RESTORATION TEMPLATE — NON-EXECUTING. Separate approval.  ║
-- ║ Uncomment ONLY the grants the captured pre-activation matrix shows were ║
-- ║ TRUE, verify each against -activation-grants-validation.sql's before-   ║
-- ║ Phase-1 capture, then run. This is GRANT-ONLY and reproduces the matrix ║
-- ║ from the capture — do NOT reach for the Slice-6 dump to recreate grants ║
-- ║ (it is the DR floor only; restoring it reverts post-dump production      ║
-- ║ data — see the ⚠ note at the top of this file).                         ║
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
-- -- capability; it is NOT guaranteed bit-identical to the default aclitem. This residual grant-shape
-- -- difference is accepted as a grant-only tradeoff — do NOT resort to a dump restore to erase it
-- -- (that would revert post-dump production data; the dump is DR-only, see the ⚠ note at the top).
-- GRANT INSERT, UPDATE, DELETE ON public.weekly_reconciliations TO authenticated;                                     -- ONLY if the captured matrix + row-9 posture call for DELETE
-- -- Verify each grant equals the captured pre-activation value, then:
-- COMMIT;
