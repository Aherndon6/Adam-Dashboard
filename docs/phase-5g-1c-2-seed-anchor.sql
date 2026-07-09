-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 First Opening-Anchor Seed (STAGING DRAFT)
-- ═══════════════════════════════════════════════════════════════════════════
-- STAGING ONLY. Writes the FIRST `opening_anchor` snapshot row per eligible goal
-- at the anchor week. Separated from the schema migration on purpose: the
-- PRODUCTION seed is a LATER, Adam-approved script, NOT this file.
--
-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ SEED-TIME CAPTURE — VALUES ARE NOT HARDCODED PRODUCTION TRUTH.            │
-- │ Every funded_amount below is a STAGING DRAFT / seed-time placeholder.     │
-- │ The four CAPTURE-AT-SEED-TIME values ship UNSET (sentinel -1) and the     │
-- │ script HARD-STOPS until the operator fills them from custodian/bank       │
-- │ reality at seed time. This makes accidental stale/hardcoded seeding       │
-- │ impossible. For a staging rehearsal, set them to any staging test figure  │
-- │ (e.g. the plan's illustrative values) to exercise the path.               │
-- └──────────────────────────────────────────────────────────────────────────┘
--
-- Anchor (confirmed decision D2): model week 5 (Cal Wk 27), AFTER Saturday's
-- closeout is reconciled. Fallback: model week 4 ONLY if forced to seed before
-- that closeout (then 5G-1D rolls wk 5 forward). The script asserts the chosen
-- week is reconciled (week_num-only; weekly_reconciliations has no model_year —
-- inherited from 5F-1; safe only under the single 31-week 2026 model).
--
-- EXCLUDED (never seeded): adam_401k (auto/payroll YTD), wewe_rccl / wewe_dcl
-- (AMEX holding, 5G-1B), taxable_etf (deferred). Alaska is snapshotted for its
-- FUNDED AMOUNT ONLY — this does NOT change Alaska status or model any payout/
-- release behaviour. 529s / bryce_vehicle / christmas_cruise are assumed $0
-- unless final seed-time confirmation differs.
--
-- Direct guarded INSERT (owner; bypasses RLS): the write RPC cannot run from the
-- SQL editor (auth.uid()=NULL ⇒ can_write_financials()=false). This script
-- re-applies the SAME invariants the RPC enforces (reconciled week, goal exists,
-- non-auto, non-excluded, non-negative, source='opening_anchor').
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ── STAGING GUARD (shared block) ────────────────────────────────────────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.'; END IF;
  IF to_regclass('public.goal_funding_snapshots') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots missing. Run phase-5g-1c-2-migration.sql first. Aborting.'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint. Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (tx=%). Aborting.', v_tx; END IF;
END $$;

-- ── Capture + guarded insert ────────────────────────────────────────────────
DO $$
DECLARE
  -- ══ ANCHOR (D2) ══
  v_model_year INT := 2026;
  v_anchor_week INT := 5;                       -- model wk 5 (Cal Wk 27); fallback wk 4 (see header)

  -- ══ CAPTURE-AT-SEED-TIME (TODO: fill from custodian/bank reality; -1 = UNSET) ══
  v_adam_ira        NUMERIC(12,2) := -1;        -- TODO observed cumulative funded at anchor-week end
  v_wendy_ira       NUMERIC(12,2) := -1;        -- TODO observed cumulative funded at anchor-week end
  v_wendy_sep       NUMERIC(12,2) := -1;        -- TODO completed goal; planning ~17859 unless custodian differs
  v_alaska          NUMERIC(12,2) := -1;        -- TODO funded amount ONLY (do not change status/payout)

  -- ══ ASSUMED $0 UNLESS SEED-TIME CONFIRMATION DIFFERS ══
  v_bailey_529      NUMERIC(12,2) := 0;         -- confirm at seed time
  v_bryce_529       NUMERIC(12,2) := 0;         -- confirm at seed time
  v_preston_529     NUMERIC(12,2) := 0;         -- confirm at seed time
  v_bryce_vehicle   NUMERIC(12,2) := 0;         -- confirm at seed time
  v_christmas_cruise NUMERIC(12,2) := 0;        -- confirm at seed time

  v_inserted INT;
BEGIN
  -- Guard A: anchor week reconciled (week_num-only; see header).
  IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num = v_anchor_week) THEN
    RAISE EXCEPTION 'HARD STOP: anchor week % is not reconciled on staging. Seed after its closeout, or use the wk-4 fallback (see header).', v_anchor_week;
  END IF;

  -- Guard B: capture-at-seed-time values MUST be set (block stale/hardcoded seeding).
  IF v_adam_ira < 0 OR v_wendy_ira < 0 OR v_wendy_sep < 0 OR v_alaska < 0 THEN
    RAISE EXCEPTION 'HARD STOP: capture-at-seed-time values still UNSET (-1). Populate v_adam_ira / v_wendy_ira / v_wendy_sep / v_alaska from reality at seed time before running. (Staging rehearsal: set staging test figures.)';
  END IF;

  -- Guarded INSERT: JOIN to goal_registry drops any goal absent on this DB and any
  -- auto goal; the WHERE drops the deferred/holding ids defensively. source is
  -- opening_anchor for every row. Idempotent re-upsert on the natural key.
  INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note)
  SELECT v_model_year, v_anchor_week, x.goal_id, x.amount, 'opening_anchor', x.note
  FROM (VALUES
      ('adam_ira',         v_adam_ira,         '[STAGING DRAFT] capture-at-seed-time observed funded'),
      ('wendy_ira',        v_wendy_ira,        '[STAGING DRAFT] capture-at-seed-time observed funded'),
      ('wendy_sep',        v_wendy_sep,        '[STAGING DRAFT] completed goal; planning ~17859 unless custodian differs'),
      ('alaska',           v_alaska,           '[STAGING DRAFT] funded amount only; status/payout unchanged'),
      ('bailey_529',       v_bailey_529,       '[STAGING DRAFT] assumed 0 unless seed-time confirmation differs'),
      ('bryce_529',        v_bryce_529,        '[STAGING DRAFT] assumed 0 unless seed-time confirmation differs'),
      ('preston_529',      v_preston_529,      '[STAGING DRAFT] assumed 0 unless seed-time confirmation differs'),
      ('bryce_vehicle',    v_bryce_vehicle,    '[STAGING DRAFT] assumed 0 unless seed-time confirmation differs'),
      ('christmas_cruise', v_christmas_cruise, '[STAGING DRAFT] assumed 0 unless seed-time confirmation differs')
    ) AS x(goal_id, amount, note)
  JOIN public.goal_registry g ON g.id = x.goal_id AND COALESCE(g.auto,false) = false
  WHERE x.goal_id <> ALL (ARRAY['wewe_rccl','wewe_dcl','taxable_etf','adam_401k'])
  ON CONFLICT (model_year, week_num, goal_id) DO UPDATE
    SET funded_amount = EXCLUDED.funded_amount,
        source        = EXCLUDED.source,
        note          = EXCLUDED.note;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RAISE NOTICE 'SEED-ANCHOR: % opening_anchor rows written at model_year=% week_num=%.', v_inserted, v_model_year, v_anchor_week;
END $$;

-- Report (rows just written; validated in phase-5g-1c-2-seed-anchor-validation.sql).
SELECT 'SEED' AS check, model_year, week_num, goal_id, funded_amount, source
  FROM public.goal_funding_snapshots
 WHERE model_year = 2026 AND week_num = 5
 ORDER BY goal_id;

COMMIT;
