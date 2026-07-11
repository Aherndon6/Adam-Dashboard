-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 PRODUCTION First Opening-Anchor Seed
--
--   TARGET ......... PRODUCTION  Adam-Dashboard (usayoldrawwmjsmretin)
--   NEVER RUN IN ... STAGING     herndon-fos-staging (pkwotgqivgaapwuqgwqb)
--
-- Writes the FIRST `opening_anchor` snapshot row per eligible goal at the anchor
-- week. THE SEED IS THE GO-LIVE EVENT — with rows present, the live C3 overlay
-- stops being inert and consumes these values in runModel / getGoalFunded.
--
-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ SEED-TIME CAPTURE — VALUES ARE NOT HARDCODED TRUTH.                       │
-- │ The four CAPTURE-AT-SEED-TIME values ship UNSET (sentinel -1). This file  │
-- │ is COMMITTED with the -1 sentinels; the operator replaces them ONLY with  │
-- │ the Adam-approved First-Anchor Value Card values, produces the value-only │
-- │ diff, and commits the final seed-value SQL BEFORE execution (E2). Guard B │
-- │ HARD-STOPS while any sentinel remains, so stale/hardcoded seeding is      │
-- │ impossible.                                                               │
-- └──────────────────────────────────────────────────────────────────────────┘
--
-- ██ EXECUTION GATE E2 ██ DO NOT RUN. Seed execution requires: Value Card
-- approval → sentinel fill → value-only diff → commit of final seed SQL →
-- SEPARATE in-session Adam approval. Run outside Wendy's Budget-entry hours,
-- in a supervised window (RC-1 basis-coherence / freeze timing).
--
-- Anchor (basis-coherence, RC-1): the anchor is the LATEST reconciled week at
-- seed time. Guard A HARD-STOPS unless v_anchor_week = max(week_num) from
-- weekly_reconciliations (fresh-value/stale-week seeding is prohibited). Set
-- v_anchor_week to the latest reconciled model week. HISTORICAL NOTE (2026-07-11):
-- Week 5 reconciled 2026-07-11 and E2 executed the same day on the wk-5 basis (Guard A
-- confirmed max(week_num)=5). The earlier "Jul 12–17 window" language was a planning
-- estimate, not a technical guard; the wk-6 re-anchor / Alaska-freeze-deferral paths did
-- not fire. Guard A remains the mechanical basis-coherence check for any future re-run.
-- week_num-only (weekly_reconciliations has no model_year; inherited from 5F-1;
-- safe under the single 31-week 2026 model).
--
-- EXCLUDED (never seeded): adam_401k (auto/payroll YTD), wewe_rccl / wewe_dcl
-- (AMEX holding, 5G-1B), taxable_etf (deferred). Alaska is snapshotted for its
-- FUNDED AMOUNT ONLY — this does NOT change Alaska status or model any payout/
-- release behaviour. 529s / bryce_vehicle / christmas_cruise are assumed $0
-- unless final seed-time confirmation differs (per the Value Card).
--
-- Direct guarded INSERT (owner; bypasses RLS): the write RPC cannot run from the
-- SQL editor (auth.uid()=NULL ⇒ can_write_financials()=false). This script
-- re-applies the SAME invariants the RPC enforces (reconciled week, goal exists,
-- non-auto, non-excluded, non-negative, source='opening_anchor').
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ══════════════════════════════════════════════════════════════════════════
-- ██ PRODUCTION GUARD ██ — Adam-Dashboard (usayoldrawwmjsmretin)
-- INVERTED counterpart of the staging guard: REQUIRES the production fingerprint
-- and REFUSES staging herndon-fos-staging (pkwotgqivgaapwuqgwqb) and every other
-- cluster. Shared block — identical across the PRODUCTION 5G-1C-2 package (plus
-- the goal_funding_snapshots existence check the seed needs).
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_sysid     BIGINT;
  v_bal       NUMERIC(12,2);
  v_tx        BIGINT;
  v_reg_ids   BIGINT;
  v_adam_tgt  NUMERIC(12,2);
  v_wendy_tgt NUMERIC(12,2);
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid IS DISTINCT FROM 7632885393857617092 THEN
    RAISE EXCEPTION 'HARD STOP: system_identifier % <> 7632885393857617092 — target is NOT Adam-Dashboard (usayoldrawwmjsmretin). Aborting.', v_sysid;
  END IF;
  IF to_regclass('public.app_environment') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: public.app_environment present — looks like staging herndon-fos-staging (pkwotgqivgaapwuqgwqb), not production. Aborting.';
  END IF;
  IF to_regclass('public.goal_funding_snapshots') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots missing. Run docs/phase-5g-1c-2-prod-migration.sql first. Aborting.';
  END IF;
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing (accounts/transactions). Aborting.';
  END IF;
  -- Dependency tables must EXIST before we query them (intentional hard-stop msg,
  -- not a raw missing-relation error): goal_registry (13-ID + IRA targets) and
  -- weekly_reconciliations (Guard A max(week_num) anchor check downstream).
  IF to_regclass('public.goal_registry') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry missing — cannot check IDs/targets. Aborting.';
  END IF;
  IF to_regclass('public.weekly_reconciliations') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: weekly_reconciliations missing. Aborting.';
  END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: accounts.amex_gold missing — not production. Aborting.'; END IF;
  IF v_bal IS DISTINCT FROM -8248.50 THEN
    RAISE EXCEPTION 'HARD STOP: amex_gold starting_balance % <> -8248.50 — not the Adam-Dashboard production fingerprint. Aborting.', v_bal;
  END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx < 40 THEN RAISE EXCEPTION 'HARD STOP: transactions=% < 40 floor — empty/non-production DB. Aborting.', v_tx; END IF;
  SELECT count(*) INTO v_reg_ids FROM public.goal_registry
   WHERE id IN ('adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529',
                'preston_529','bryce_vehicle','christmas_cruise',
                'adam_401k','wewe_rccl','wewe_dcl','taxable_etf');
  IF v_reg_ids <> 13 THEN RAISE EXCEPTION 'HARD STOP: goal_registry canonical-id count % <> 13. Aborting.', v_reg_ids; END IF;
  SELECT target INTO v_adam_tgt  FROM public.goal_registry WHERE id='adam_ira';
  SELECT target INTO v_wendy_tgt FROM public.goal_registry WHERE id='wendy_ira';
  IF v_adam_tgt IS DISTINCT FROM 7500 THEN RAISE EXCEPTION 'HARD STOP: adam_ira target % <> 7500 (stale IRA target). Aborting.', v_adam_tgt; END IF;
  IF v_wendy_tgt IS DISTINCT FROM 7500 THEN RAISE EXCEPTION 'HARD STOP: wendy_ira target % <> 7500 (stale IRA target). Aborting.', v_wendy_tgt; END IF;
  -- app_users exact-identity assertion — OMITTED by deterministic fallback (Fable
  -- RC-5/RC-6): assert aherndon6@gmail.com + wherndon22@gmail.com ONLY if the
  -- app_users schema supports it; else omit + document. Schema unverified this
  -- pass; omitted to avoid a false-abort. system_identifier equality already
  -- uniquely identifies Adam-Dashboard (usayoldrawwmjsmretin).
END $$;

-- ── Capture + guarded insert ────────────────────────────────────────────────
DO $$
DECLARE
  -- ══ ANCHOR (RC-1 basis-coherence: set to the LATEST reconciled model week) ══
  v_model_year INT := 2026;
  v_anchor_week INT := 5;                       -- SET to max(week_num). E2 executed on the wk-5 basis 2026-07-11 (Guard A enforces = max).
  v_latest_rec  INT;                            -- latest reconciled week (Guard A single-source)

  -- ══ CAPTURE-AT-SEED-TIME (TODO: fill from custodian/bank reality; -1 = UNSET) ══
  v_adam_ira        NUMERIC(12,2) := -1;        -- TODO observed cumulative funded at anchor-week end
  v_wendy_ira       NUMERIC(12,2) := -1;        -- TODO observed cumulative funded at anchor-week end
  v_wendy_sep       NUMERIC(12,2) := -1;        -- TODO completed goal; planning ~17859 unless custodian differs
  v_alaska          NUMERIC(12,2) := -1;        -- TODO funded amount ONLY (do not change status/payout)

  -- ══ EXPECTED $0 — but STILL captured from the Value Card (UNSET -1 sentinels) ══
  -- These are expected to be $0 unless seed-time confirmation differs, but they
  -- are NOT pre-filled: the operator must set all five from the approved First-
  -- Anchor Value Card (typically 0), so Guard B forces an explicit confirmation
  -- for every one of the nine seeded goals (aligns with the nine validation pins).
  v_bailey_529      NUMERIC(12,2) := -1;        -- Value Card (expected 0)
  v_bryce_529       NUMERIC(12,2) := -1;        -- Value Card (expected 0)
  v_preston_529     NUMERIC(12,2) := -1;        -- Value Card (expected 0)
  v_bryce_vehicle   NUMERIC(12,2) := -1;        -- Value Card (expected 0)
  v_christmas_cruise NUMERIC(12,2) := -1;       -- Value Card (expected 0)

  v_inserted INT;
BEGIN
  -- Guard A (RC-1 basis-coherence, MECHANICAL): the anchor MUST be the LATEST
  -- reconciled week — not merely "reconciled", but equal to max(week_num). If a
  -- newer closeout has landed (e.g. wk 6), a wk-5 seed HARD-STOPS: re-anchor and
  -- regenerate the Value Card. (week_num-only; weekly_reconciliations has no model_year.)
  SELECT max(week_num) INTO v_latest_rec FROM public.weekly_reconciliations;
  IF v_latest_rec IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: no reconciled weeks exist — cannot anchor. Aborting.';
  END IF;
  IF v_anchor_week <> v_latest_rec THEN
    RAISE EXCEPTION 'HARD STOP: v_anchor_week % <> latest reconciled week % (basis-coherence). Re-anchor to % and regenerate the Value Card. Aborting.', v_anchor_week, v_latest_rec, v_latest_rec;
  END IF;

  -- Guard B: ALL NINE seed values MUST be set (block stale/hardcoded/omitted seeding).
  -- Every one of the nine seeded goals — including the five expected-$0 goals — must
  -- be filled from the approved Value Card; any remaining -1 hard-stops.
  IF v_adam_ira < 0 OR v_wendy_ira < 0 OR v_wendy_sep < 0 OR v_alaska < 0
     OR v_bailey_529 < 0 OR v_bryce_529 < 0 OR v_preston_529 < 0
     OR v_bryce_vehicle < 0 OR v_christmas_cruise < 0 THEN
    RAISE EXCEPTION 'HARD STOP: one or more of the nine seed values still UNSET (-1). Populate ALL nine (adam_ira, wendy_ira, wendy_sep, alaska, bailey_529, bryce_529, preston_529, bryce_vehicle, christmas_cruise) from the Adam-approved First-Anchor Value Card before running (E2).';
  END IF;

  -- Guarded INSERT: JOIN to goal_registry drops any goal absent on this DB and any
  -- auto goal; the WHERE drops the deferred/holding ids defensively. source is
  -- opening_anchor for every row. Idempotent re-upsert on the natural key.
  INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note)
  SELECT v_model_year, v_anchor_week, x.goal_id, x.amount, 'opening_anchor', x.note
  FROM (VALUES
      ('adam_ira',         v_adam_ira,         '[PROD opening_anchor] capture-at-seed-time observed funded'),
      ('wendy_ira',        v_wendy_ira,        '[PROD opening_anchor] capture-at-seed-time observed funded'),
      ('wendy_sep',        v_wendy_sep,        '[PROD opening_anchor] completed goal; planning ~17859 unless custodian differs'),
      ('alaska',           v_alaska,           '[PROD opening_anchor] funded amount only; status/payout unchanged'),
      ('bailey_529',       v_bailey_529,       '[PROD opening_anchor] assumed 0 unless seed-time confirmation differs'),
      ('bryce_529',        v_bryce_529,        '[PROD opening_anchor] assumed 0 unless seed-time confirmation differs'),
      ('preston_529',      v_preston_529,      '[PROD opening_anchor] assumed 0 unless seed-time confirmation differs'),
      ('bryce_vehicle',    v_bryce_vehicle,    '[PROD opening_anchor] assumed 0 unless seed-time confirmation differs'),
      ('christmas_cruise', v_christmas_cruise, '[PROD opening_anchor] assumed 0 unless seed-time confirmation differs')
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

-- Report (rows just written; validated in docs/phase-5g-1c-2-prod-seed-anchor-validation.sql).
-- Anchor week single-sourced from max(week_num) so it tracks wk 5 / wk 6 automatically.
SELECT 'SEED' AS check, model_year, week_num, goal_id, funded_amount, source
  FROM public.goal_funding_snapshots
 WHERE model_year = 2026 AND week_num = (SELECT max(week_num) FROM public.weekly_reconciliations)
 ORDER BY goal_id;

COMMIT;
