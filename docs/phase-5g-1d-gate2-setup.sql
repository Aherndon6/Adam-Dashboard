-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 2: PRECONDITION GATE (READ ONLY, assert). Authored, NOT executed.
-- Hard-stops unless the exact clean Gate-2 starting state holds: staging fingerprint; Week-5 anchor is the
-- exact synthetic nine (values 100..900, opening_anchor, [STAGING-FIXTURE]); ZERO Week-6+ reconciliation or
-- snapshot rows; NO marked Gate-2 residue; NO G2-20 helper/trigger; temporary grant ACTIVE on both new
-- functions for authenticated and NOT for anon. Nothing is mutated. PRODUCTION IS NOT TOUCHED.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT;
  v_anchor INT; v_anchor_vals INT; v_w6_recon INT; v_w6_snap INT;
  v_gate2_snap INT; v_gate2_cc INT; v_helper BOOLEAN; v_trg INT;
  v_wrap_auth BOOLEAN; v_wrap_anon BOOLEAN; v_opb_auth BOOLEAN; v_opb_anon BOOLEAN;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
  c_eligible9 CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
  c_wrap CONSTANT text := 'public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)';
  c_opb  CONSTANT text := 'public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)';
BEGIN
  -- EXACT staging fingerprint
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production system_identifier — Gate 2 is staging-only. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint. Aborting.'; END IF;

  -- Week-5 anchor is the exact synthetic nine (marked opening_anchor) AND exactly 9 rows total at wk5
  SELECT count(*) INTO v_anchor FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=5 AND source='opening_anchor'
      AND goal_id = ANY(c_eligible9) AND COALESCE(note,'') LIKE '%[STAGING-FIXTURE]%';
  IF v_anchor <> 9 THEN RAISE EXCEPTION 'SETUP: Week-5 anchor incomplete (% of 9 marked eligible). Aborting.', v_anchor; END IF;
  SELECT count(*) INTO v_anchor_vals FROM (VALUES
     ('adam_ira',100),('wendy_ira',200),('wendy_sep',300),('alaska',400),('bailey_529',500),
     ('bryce_529',600),('preston_529',700),('bryce_vehicle',800),('christmas_cruise',900)) e(gid,amt)
    JOIN public.goal_funding_snapshots s ON s.model_year=2026 AND s.week_num=5 AND s.goal_id=e.gid
    WHERE round(s.funded_amount,2) = e.amt AND s.source='opening_anchor';
  IF v_anchor_vals <> 9 THEN RAISE EXCEPTION 'SETUP: Week-5 anchor values drift from the synthetic 100..900 baseline (% of 9 match). Aborting.', v_anchor_vals; END IF;
  IF (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5) <> 9 THEN
    RAISE EXCEPTION 'SETUP: Week-5 has rows beyond the nine eligible anchor. Aborting.'; END IF;

  -- ZERO Week-6+ reconciliation / snapshot rows
  SELECT count(*) INTO v_w6_recon FROM public.weekly_reconciliations WHERE week_num >= 6;
  SELECT count(*) INTO v_w6_snap  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6;
  IF v_w6_recon <> 0 THEN RAISE EXCEPTION 'SETUP: % Week-6+ reconciliation row(s) already present — not a clean start. Aborting.', v_w6_recon; END IF;
  IF v_w6_snap  <> 0 THEN RAISE EXCEPTION 'SETUP: % Week-6+ snapshot row(s) already present — not a clean start. Aborting.', v_w6_snap; END IF;

  -- NO marked Gate-2 residue
  SELECT count(*) INTO v_gate2_snap FROM public.goal_funding_snapshots WHERE COALESCE(note,'') LIKE '%[GATE2]%';
  SELECT count(*) INTO v_gate2_cc   FROM public.cash_commitments WHERE expected_item_id LIKE '\_\_GATE2\_%' OR expected_item_id LIKE '\_\_ATOMIC\_TEST\_%';
  IF v_gate2_snap <> 0 OR v_gate2_cc <> 0 THEN RAISE EXCEPTION 'SETUP: Gate-2 marked residue present (snap=%, cc=%) — run teardown first. Aborting.', v_gate2_snap, v_gate2_cc; END IF;

  -- NO G2-20 helper/trigger
  v_helper := to_regproc('public._gf_atomic_test_fail') IS NOT NULL;
  SELECT count(*) INTO v_trg FROM pg_trigger WHERE tgname='_gf_atomic_test_fail_trg' AND NOT tgisinternal;
  IF v_helper OR v_trg <> 0 THEN RAISE EXCEPTION 'SETUP: a G2-20 test object is present (helper=%, trigger=%) — STOP; drop it before proceeding. Aborting.', v_helper, v_trg; END IF;

  -- Temporary grant ACTIVE for authenticated, NOT for anon (Gate 2 needs the authenticated EXECUTE path)
  v_wrap_auth := has_function_privilege('authenticated', c_wrap, 'EXECUTE');
  v_wrap_anon := has_function_privilege('anon',          c_wrap, 'EXECUTE');
  v_opb_auth  := has_function_privilege('authenticated', c_opb,  'EXECUTE');
  v_opb_anon  := has_function_privilege('anon',          c_opb,  'EXECUTE');
  IF NOT (v_wrap_auth AND v_opb_auth) THEN
    RAISE EXCEPTION 'SETUP: temporary grant NOT active (wrapper auth=%, optionb auth=%) — apply phase-5g-1d-staging-grant.sql first. Aborting.', v_wrap_auth, v_opb_auth; END IF;
  IF v_wrap_anon OR v_opb_anon THEN
    RAISE EXCEPTION 'SETUP: anon has EXECUTE (wrapper=%, optionb=%) — unexpected; anon must never be granted. Aborting.', v_wrap_anon, v_opb_anon; END IF;

  RAISE NOTICE 'GATE-2 SETUP GATE PASS: staging fingerprint OK; Week-5 anchor exact (nine, 100..900, marked); zero Week-6+ state; no Gate-2 residue; no G2-20 objects; grant active for authenticated only.';
END $$;

COMMIT;
