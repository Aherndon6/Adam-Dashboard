-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — SYNTHETIC WEEK-5 FIXTURE SEED. Authored, NOT executed.
-- Seeds the nine eligible opening_anchor rows at model_year=2026, week_num=5 with CLEARLY
-- SYNTHETIC, non-household funded amounts, each note carrying [STAGING-FIXTURE]. Direct
-- guarded INSERT (mirrors the E2 seed pattern; the anchor bypasses the reconciled-week RPC
-- check). INSERT-ONLY: hard-stops unless goal_funding_snapshots is COMPLETELY EMPTY, and uses a
-- plain INSERT (NO ON CONFLICT) — it never overwrites or relabels an existing row. Reseeding
-- requires phase-5g-1d-fixture-cleanup.sql first. No wewe_rccl/wewe_dcl. PRODUCTION IS NOT
-- TOUCHED; exact staging fingerprint; else hard-stops.
--
-- SYNTHETIC VALUES (round hundreds, obviously NOT household balances; ascending, positive, and
-- all far below the 424242.42 G2-20 sentinel so monotonic increases and Option-B corrections
-- are testable): adam_ira 100, wendy_ira 200, wendy_sep 300, alaska 400, bailey_529 500,
-- bryce_529 600, preston_529 700, bryce_vehicle 800, christmas_cruise 900.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT; v_reg INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
  c_eligible9 CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production system_identifier — staging-only fixture. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint. Aborting.'; END IF;
  IF to_regclass('public.goal_funding_snapshots') IS NULL THEN RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots missing — run the staging E1 migration first. Aborting.'; END IF;
  SELECT count(*) INTO v_reg FROM public.goal_registry WHERE id = ANY(c_eligible9);
  IF v_reg <> 9 THEN RAISE EXCEPTION 'HARD STOP: eligible-nine missing from goal_registry (FK target). Aborting.'; END IF;
  -- INSERT-ONLY: the table must be COMPLETELY EMPTY (reseeding requires fixture cleanup first).
  IF (SELECT count(*) FROM public.goal_funding_snapshots) <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots is non-empty — run phase-5g-1d-fixture-cleanup.sql first (seed never overwrites). Aborting.'; END IF;
END $$;

-- Plain INSERT (NO ON CONFLICT) of the nine synthetic opening_anchor rows, with the exact
-- inserted-row-count proof captured in the SAME block. A duplicate would raise on the
-- natural-key unique constraint and fail loudly — the seed never overwrites/relabels.
DO $$
DECLARE v_ins INT; v_total INT;
BEGIN
  INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note)
  SELECT 2026, 5, x.goal_id, x.amount, 'opening_anchor', '[STAGING-FIXTURE] synthetic anchor (non-household)'
  FROM (VALUES
      ('adam_ira',         100.00::numeric),
      ('wendy_ira',        200.00::numeric),
      ('wendy_sep',        300.00::numeric),
      ('alaska',           400.00::numeric),
      ('bailey_529',       500.00::numeric),
      ('bryce_529',        600.00::numeric),
      ('preston_529',      700.00::numeric),
      ('bryce_vehicle',    800.00::numeric),
      ('christmas_cruise', 900.00::numeric)
  ) AS x(goal_id, amount);
  GET DIAGNOSTICS v_ins = ROW_COUNT;
  IF v_ins <> 9 THEN RAISE EXCEPTION 'FIXTURE SEED: inserted % rows <> 9', v_ins; END IF;
  SELECT count(*) INTO v_total FROM public.goal_funding_snapshots;
  IF v_total <> 9 THEN RAISE EXCEPTION 'FIXTURE SEED: table has % rows <> 9 (insert-only invariant broken)', v_total; END IF;
  RAISE NOTICE 'FIXTURE SEED PASS: inserted exactly 9 synthetic [STAGING-FIXTURE] opening_anchor rows at 2026/wk5.';
END $$;

COMMIT;
