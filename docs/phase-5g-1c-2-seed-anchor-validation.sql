-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 Seed-Anchor Validation (STAGING)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — run on STAGING ONLY, AFTER phase-5g-1c-2-seed-anchor.sql. Separated
-- from phase-5g-1c-2-validation.sql so the schema validation (which asserts an
-- empty table, V7) is not falsely failed by the presence of seed rows.
-- Read-only. STAGING ONLY. Anchor = model_year 2026, week_num 5 (D2).
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

-- ── STAGING GUARD ───────────────────────────────────────────────────────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.'; END IF;
  IF to_regclass('public.goal_funding_snapshots') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots missing. Run migration + seed first. Aborting.'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint. Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (tx=%). Aborting.', v_tx; END IF;
END $$;

-- ── SA1: anchor rows exist, all source='opening_anchor' at (2026, wk 5) ──────
SELECT 'SA1' AS check,
       (SELECT count(*) FROM public.goal_funding_snapshots
         WHERE model_year=2026 AND week_num=5) >= 1
       AND NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots
         WHERE model_year=2026 AND week_num=5 AND source <> 'opening_anchor') AS expected_true;

-- ── SA2: NO excluded goal_ids present (adam_401k / wewe_rccl / wewe_dcl / taxable_etf) ─
SELECT 'SA2' AS check,
       NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots
         WHERE model_year=2026 AND week_num=5
           AND goal_id IN ('adam_401k','wewe_rccl','wewe_dcl','taxable_etf')) AS expected_true;

-- ── SA3: NO auto goals present (join goal_registry) ─────────────────────────
SELECT 'SA3' AS check,
       NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots s
         JOIN public.goal_registry g ON g.id=s.goal_id
        WHERE s.model_year=2026 AND s.week_num=5 AND COALESCE(g.auto,false)=true) AS expected_true;

-- ── SA4: every snapshot goal_id exists in goal_registry; funded_amount >= 0 ──
SELECT 'SA4' AS check,
       NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots s
         WHERE s.model_year=2026 AND s.week_num=5
           AND (NOT EXISTS (SELECT 1 FROM public.goal_registry g WHERE g.id=s.goal_id)
                OR s.funded_amount < 0)) AS expected_true;

-- ── SA5: anchor week is reconciled (week_num-only; inherited from 5F-1) ──────
SELECT 'SA5' AS check,
       EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=5) AS expected_true;

-- ── SA6: natural key is unique at the anchor (no dup goal per year/week) ─────
SELECT 'SA6' AS check,
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5)
       = (SELECT count(DISTINCT goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5) AS expected_true;

-- ── SA7: no capture-at-seed-time goal was left at the UNSET sentinel (-1) ────
-- (Belt-and-suspenders: the seed's Guard B already blocks this, but re-assert on
-- the persisted rows in case a row was written by another path.)
SELECT 'SA7' AS check,
       NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots
         WHERE model_year=2026 AND week_num=5 AND funded_amount < 0) AS expected_true;

-- ── SA8 (ADVISORY, INFORMATIONAL — never fails the suite) ────────────────────
-- One-sided AMEX over-attribution advisory (§8 DQ #1). Computes, at the anchor:
--   amex_held_snapshot_sum   = Σ funded_amount for the AMEX-held goal set
--   reconciled_amx           = weekly_reconciliations.amx (reconciled AMEX Savings) at wk 5
--   over_attribution_amount  = snapshot_sum − reconciled_amx
--   is_over_attributed       = over_attribution_amount > 1   (the ONLY advisory flag)
-- Over-attribution (goals claim MORE than the reconciled AMEX holds) is the only
-- condition worth a flag. Under-attribution / positive AMEX float (negative
-- over_attribution_amount) is EXPECTED — the RCCL/DCL holding sits in AMEX Savings
-- but is EXCLUDED from snapshots — so it is informational, NEVER a failure. This
-- is advisory in 5G-1C; the hard two-sided gate is 5G-1E. The AMEX-held goal set
-- is documented app-side; the list below is for eyeball review only.
WITH agg AS (
  SELECT COALESCE(sum(funded_amount),0)::NUMERIC(12,2) AS snapshot_sum
    FROM public.goal_funding_snapshots
   WHERE model_year=2026 AND week_num=5
     AND goal_id IN ('adam_ira','wendy_ira','bailey_529','bryce_529','preston_529')
), amx AS (
  SELECT amx::NUMERIC(12,2) AS reconciled_amx
    FROM public.weekly_reconciliations WHERE week_num=5
)
SELECT 'SA8-advisory' AS note,
       agg.snapshot_sum                                   AS amex_held_snapshot_sum,
       amx.reconciled_amx                                 AS reconciled_amx,
       (agg.snapshot_sum - amx.reconciled_amx)::NUMERIC(12,2) AS over_attribution_amount,
       (agg.snapshot_sum - amx.reconciled_amx) > 1        AS is_over_attributed,
       'advisory only; over_attribution > $1 is a flag; under-attribution (negative) is expected (RCCL/DCL holding excluded); hard gate is 5G-1E' AS interpretation
  FROM agg CROSS JOIN amx;

-- ── SA9: full anchor row dump (eyeball the staging-draft values) ─────────────
SELECT 'SA9-rows' AS check, model_year, week_num, goal_id, funded_amount, source, note
  FROM public.goal_funding_snapshots
 WHERE model_year=2026 AND week_num=5
 ORDER BY goal_id;
