-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D — GATE B ADJUNCT PREFLIGHT (READ ONLY). AUTHORED, NOT EXECUTED.
-- Fable P2-1: an EXTRA read-only pre-Phase-1 state check, run in the same sitting immediately
-- BEFORE `docs/phase-5g-1d-activation-grants.sql`. It proves production is in the exact expected
-- pre-activation state so the FIRST supervised closeout will land at model week_num=6 (calendar
-- Week 28) with a clean partition. ANY different result is a HARD STOP before Phase 1.
--
--   NEVER MUTATES — read-only; no writes, no grants, no DDL.
--   TARGET ......... PRODUCTION Adam-Dashboard (usayoldrawwmjsmretin)  [staging-safe: env-guarded]
--
-- Expected (all must hold):
--   wk5-anchor .......... anchor9=9, corrections=2, total_rows_wk5=11
--   recon-weeks ......... latest_reconciled=5, rows=5, only_weeks_1_to_5=true
--   post-anchor-snaps ... rows_at_week_ge_6=0
-- Companion: docs/phase-5g-1d-gateb-activation-runbook-2026-07-13.md §1.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_has_appenv BOOLEAN; v_appenv_total INT; v_appenv_staging INT; v_staging_marker BOOLEAN; v_env TEXT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 0;  -- <<FILL for a staging rehearsal; 0 = staging hard-stops until pinned
  v_anchor9 INT; v_corr INT; v_wk5_total INT;
  v_recon_rows INT; v_recon_latest INT; v_recon_out_of_range INT;
  v_snaps_ge6 INT;
BEGIN
  -- ── environment guard (production OR approved staging; anything else hard-stops) ──
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  v_has_appenv := to_regclass('public.app_environment') IS NOT NULL;
  v_staging_marker := false;
  IF v_has_appenv THEN
    SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
    v_staging_marker := (v_appenv_total=1 AND v_appenv_staging=1);
  END IF;
  IF v_sysid = c_prod_sysid AND NOT v_has_appenv THEN v_env := 'production';
  ELSIF v_sysid = c_staging_sysid AND v_has_appenv AND v_staging_marker THEN v_env := 'staging';
  ELSE RAISE EXCEPTION 'HARD STOP: unknown/ambiguous environment (sysid=%). Aborting adjunct preflight.', v_sysid; END IF;
  RAISE NOTICE 'GATE B ADJUNCT PREFLIGHT environment: %', v_env;

  -- ── (1) Week-5 snapshot partition: 9 opening_anchor + 2 correction = 11 total ──
  SELECT count(*) FILTER (WHERE source='opening_anchor'),
         count(*) FILTER (WHERE source='correction'),
         count(*)
    INTO v_anchor9, v_corr, v_wk5_total
    FROM public.goal_funding_snapshots
   WHERE model_year=2026 AND week_num=5;
  IF v_anchor9 <> 9 OR v_corr <> 2 OR v_wk5_total <> 11 THEN
    RAISE EXCEPTION 'HARD STOP: Week-5 partition wrong (opening_anchor=%, correction=%, total=%; expected 9/2/11). Aborting before Phase 1.', v_anchor9, v_corr, v_wk5_total; END IF;

  -- ── (2) weekly_reconciliations: exactly 5 rows, weeks 1..5 only, latest=5 ──
  SELECT count(*), max(week_num), count(*) FILTER (WHERE week_num NOT BETWEEN 1 AND 5)
    INTO v_recon_rows, v_recon_latest, v_recon_out_of_range
    FROM public.weekly_reconciliations;
  IF v_recon_rows <> 5 OR v_recon_latest <> 5 OR v_recon_out_of_range <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: weekly_reconciliations not weeks 1-5 only (rows=%, latest=%, out_of_range=%; expected 5/5/0). The first closeout must land at week_num=6. Aborting before Phase 1.', v_recon_rows, v_recon_latest, v_recon_out_of_range; END IF;

  -- ── (3) NO post-anchor snapshots yet (nothing at model week >= 6) ──
  SELECT count(*) INTO v_snaps_ge6 FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6;
  IF v_snaps_ge6 <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: % goal_funding_snapshots row(s) already exist at week_num>=6 (expected 0). Aborting before Phase 1.', v_snaps_ge6; END IF;

  RAISE NOTICE 'GATE B ADJUNCT PREFLIGHT PASS: wk5 9/2/11; weekly_reconciliations 5 rows (weeks 1-5, latest 5); 0 snapshots at week>=6. Clean pre-activation state; first closeout will persist week_num=6 (calendar Week 28).';
END $$;

-- Evidence rows (labelled; read-only) — capture verbatim.
SELECT 'wk5-anchor' AS check,
       count(*) FILTER (WHERE source='opening_anchor') AS anchor9,
       count(*) FILTER (WHERE source='correction')     AS corrections,
       count(*)                                         AS total_rows_wk5
  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5;

SELECT 'recon-weeks' AS check,
       max(week_num) AS latest_reconciled,
       count(*)      AS rows,
       (count(*) FILTER (WHERE week_num NOT BETWEEN 1 AND 5) = 0) AS only_weeks_1_to_5
  FROM public.weekly_reconciliations;

SELECT 'post-anchor-snaps' AS check,
       count(*) AS rows_at_week_ge_6
  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6;

COMMIT;
