-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — SYNTHETIC WEEK-5 FIXTURE CLEANUP / RESET. Authored, NOT executed.
-- Deletes ONLY the exact synthetic Week-5 fixture rows (model_year=2026, week_num=5,
-- source='opening_anchor', goal_id in the eligible nine, note contains [STAGING-FIXTURE]).
-- NOT an unrestricted marker delete across all weeks. Before deleting it proves the Week-5
-- partition is exactly those nine marked rows (hard-stop on any unmarked/unexpected wk5 row);
-- after, it proves exactly nine deleted, none remain, and no other snapshot row changed. Safe to
-- run before the E1 rollback / to reset between runs. PRODUCTION IS NOT TOUCHED; exact staging
-- fingerprint; else hard-stops.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT;
  v_wk5_total INT; v_wk5_fixture INT; v_other_before INT; v_other_after INT; v_del INT; v_left INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
  c_eligible9 CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production system_identifier — staging-only cleanup. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint. Aborting.'; END IF;
  IF to_regclass('public.goal_funding_snapshots') IS NULL THEN RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots missing (nothing to clean). Aborting.'; END IF;

  -- PRE: the Week-5 partition must be EXACTLY the nine eligible marked fixture rows.
  SELECT count(*) INTO v_wk5_total FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5;
  SELECT count(*) INTO v_wk5_fixture FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=5 AND source='opening_anchor'
      AND goal_id = ANY(c_eligible9) AND COALESCE(note,'') LIKE '%[STAGING-FIXTURE]%';
  IF v_wk5_fixture <> 9 THEN RAISE EXCEPTION 'HARD STOP: expected 9 eligible marked wk5 fixture rows, found %. Aborting.', v_wk5_fixture; END IF;
  IF v_wk5_total <> 9 THEN RAISE EXCEPTION 'HARD STOP: wk5 has % rows but only 9 are the fixture — unmarked/unexpected wk5 row present. Aborting.', v_wk5_total; END IF;
  SELECT count(*) INTO v_other_before FROM public.goal_funding_snapshots WHERE NOT (model_year=2026 AND week_num=5);

  -- DELETE only the exact fixture rows (all five predicates), never an unrestricted marker sweep.
  DELETE FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=5 AND source='opening_anchor'
      AND goal_id = ANY(c_eligible9) AND COALESCE(note,'') LIKE '%[STAGING-FIXTURE]%';
  GET DIAGNOSTICS v_del = ROW_COUNT;

  -- POST: exactly 9 deleted, none remain, no other snapshot row changed.
  IF v_del <> 9 THEN RAISE EXCEPTION 'FIXTURE CLEANUP: deleted % rows <> 9', v_del; END IF;
  SELECT count(*) INTO v_left FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=5 AND source='opening_anchor'
      AND goal_id = ANY(c_eligible9) AND COALESCE(note,'') LIKE '%[STAGING-FIXTURE]%';
  IF v_left <> 0 THEN RAISE EXCEPTION 'FIXTURE CLEANUP: % fixture row(s) remain', v_left; END IF;
  SELECT count(*) INTO v_other_after FROM public.goal_funding_snapshots WHERE NOT (model_year=2026 AND week_num=5);
  IF v_other_after <> v_other_before THEN RAISE EXCEPTION 'FIXTURE CLEANUP: other-week rows changed (% -> %)', v_other_before, v_other_after; END IF;
  RAISE NOTICE 'FIXTURE CLEANUP PASS: exactly 9 fixture rows deleted; none remain; % other-week row(s) unchanged.', v_other_after;
END $$;

COMMIT;
