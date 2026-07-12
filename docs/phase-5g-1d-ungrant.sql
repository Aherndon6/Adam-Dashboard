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
DECLARE v_sysid BIGINT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN
    RAISE EXCEPTION 'HARD STOP: this is PRODUCTION — ungrant script is staging-only. Aborting.'; END IF;
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
