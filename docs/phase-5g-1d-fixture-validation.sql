-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — SYNTHETIC WEEK-5 FIXTURE VALIDATION (READ ONLY). Authored, NOT executed.
-- Proves the fixture is EXACTLY the eligible-nine set at 2026/wk5, source='opening_anchor', every
-- row marked [STAGING-FIXTURE], no unmarked eligible row, no wewe_* correction row, and no other
-- snapshot rows anywhere. Mirrors the 5G-1D preflight staging-fixture assertion. Staging only.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_marked INT; v_unmarked INT; v_total_wk5 INT; v_wewe INT; v_other INT;
  v_appenv_total INT; v_appenv_staging INT;
  c_eligible9 CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
BEGIN
  -- EXACT staging fingerprint — sysid + app_environment exactly one row, env='staging'
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'FV: production system_identifier — staging only'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'FV: app_environment absent — not the approved staging env'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'FV: not the approved staging fingerprint (sysid=%, appenv total=%, staging=%)', v_sysid, v_appenv_total, v_appenv_staging; END IF;

  -- exactly the eligible nine, opening_anchor, all marked
  SELECT count(DISTINCT goal_id) INTO v_marked FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=5 AND source='opening_anchor'
      AND goal_id = ANY(c_eligible9) AND COALESCE(note,'') LIKE '%[STAGING-FIXTURE]%';
  IF v_marked <> 9 THEN RAISE EXCEPTION 'FV: only % of the eligible nine are opening_anchor + marked', v_marked; END IF;

  -- no eligible wk5 opening_anchor row left unmarked
  SELECT count(*) INTO v_unmarked FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=5 AND source='opening_anchor'
      AND goal_id = ANY(c_eligible9) AND COALESCE(note,'') NOT LIKE '%[STAGING-FIXTURE]%';
  IF v_unmarked <> 0 THEN RAISE EXCEPTION 'FV: % eligible wk5 opening_anchor row(s) unmarked', v_unmarked; END IF;

  -- no wewe_rccl/wewe_dcl correction row at wk5 (fixture is eligible-nine only)
  SELECT count(*) INTO v_wewe FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=5 AND goal_id IN ('wewe_rccl','wewe_dcl');
  IF v_wewe <> 0 THEN RAISE EXCEPTION 'FV: unexpected wewe_* row at wk5 (fixture must be eligible-nine only)'; END IF;

  -- wk5 contains exactly the nine eligible rows (no extras)
  SELECT count(*) INTO v_total_wk5 FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5;
  IF v_total_wk5 <> 9 THEN RAISE EXCEPTION 'FV: wk5 has % rows, expected exactly 9', v_total_wk5; END IF;

  -- no snapshot rows at any other week (clean fixture)
  SELECT count(*) INTO v_other FROM public.goal_funding_snapshots WHERE NOT (model_year=2026 AND week_num=5);
  IF v_other <> 0 THEN RAISE EXCEPTION 'FV: % snapshot row(s) outside wk5 — fixture not clean', v_other; END IF;

  RAISE NOTICE 'FIXTURE VALIDATION PASS: exactly the eligible-nine at 2026/wk5, opening_anchor, all [STAGING-FIXTURE]; no wewe_*; no other rows.';
END $$;

-- Rows dump (eyeball the synthetic values; balance-free).
SELECT 'FV-rows' AS check, goal_id, funded_amount, source, note
  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5 ORDER BY goal_id;

COMMIT;
