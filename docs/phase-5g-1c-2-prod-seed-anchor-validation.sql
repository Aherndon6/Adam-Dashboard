-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 PRODUCTION Seed-Anchor Validation
--
--   TARGET ......... PRODUCTION  Adam-Dashboard (usayoldrawwmjsmretin)
--   NEVER RUN IN ... STAGING     herndon-fos-staging (pkwotgqivgaapwuqgwqb)
--
-- Run AFTER docs/phase-5g-1c-2-prod-seed-anchor.sql. Read-only. NOT byte-identical
-- to staging: adds the authoritative SA-PROD block (sentinel pins that HARD-STOP
-- if unset, Value-Card funded_amount pinning, table-wide count=9, table-wide
-- exclusions) with a SINGLE-SOURCED anchor literal so wk 5 / wk 6 cannot drift
-- across checks (RC-3). Anchor validity uses "week is reconciled" (NOT max) to
-- avoid same-session false-fail (RC-1). SA8/SA9 remain read-only evidence.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

-- ══════════════════════════════════════════════════════════════════════════
-- ██ PRODUCTION GUARD ██ — Adam-Dashboard (usayoldrawwmjsmretin)
-- INVERTED counterpart of the staging guard: REQUIRES the production fingerprint
-- and REFUSES staging herndon-fos-staging (pkwotgqivgaapwuqgwqb) and every other
-- cluster. Shared block — identical across the PRODUCTION 5G-1C-2 package (plus
-- the goal_funding_snapshots existence check this validation needs).
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
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots missing. Run the prod migration + seed first. Aborting.';
  END IF;
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing (accounts/transactions). Aborting.';
  END IF;
  -- Dependency tables must EXIST before we query them (intentional hard-stop msg,
  -- not a raw missing-relation error): goal_registry (13-ID + IRA targets) and
  -- weekly_reconciliations (SA-PROD anchor-reconciled + SA8 downstream).
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

-- ══════════════════════════════════════════════════════════════════════════
-- ██ SA-PROD ██ — AUTHORITATIVE seed-anchor assertions (RC-3). SINGLE-SOURCED
-- anchor literal (v_anchor_week) + nine Value-Card pins (v_card_*). Fill BOTH
-- from the SAME Adam-approved First-Anchor Value Card used for the seed. Every
-- pin ships UNSET (-1); this block HARD-STOPS until all nine are set. Covers:
-- sentinel discipline, single anchor week, table-wide count=9, table-wide
-- exclusions, SA-complete (all 9 ids present), source/nonneg/registry/non-auto,
-- and exact Value-Card funded_amount pinning. A NOTICE prints only on full pass.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  -- SINGLE-SOURCED anchor literal — set to the SAME week the seed used (wk 5 or wk 6).
  v_anchor_week INT := 5;
  -- Value-Card pins — fill from the approved card; must equal the seeded values.
  v_card_adam_ira         NUMERIC(12,2) := -1;
  v_card_wendy_ira        NUMERIC(12,2) := -1;
  v_card_wendy_sep        NUMERIC(12,2) := -1;
  v_card_alaska           NUMERIC(12,2) := -1;
  v_card_bailey_529       NUMERIC(12,2) := -1;
  v_card_bryce_529        NUMERIC(12,2) := -1;
  v_card_preston_529      NUMERIC(12,2) := -1;
  v_card_bryce_vehicle    NUMERIC(12,2) := -1;
  v_card_christmas_cruise NUMERIC(12,2) := -1;
  v_expected CONSTANT TEXT[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska',
    'bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
  v_total INT;
  gid   TEXT;
  v_amt NUMERIC(12,2);
  v_pin NUMERIC(12,2);
BEGIN
  -- (0) Sentinel discipline — HARD-STOP if any pin is still UNSET (-1) (RC-3).
  IF v_card_adam_ira<0 OR v_card_wendy_ira<0 OR v_card_wendy_sep<0 OR v_card_alaska<0
     OR v_card_bailey_529<0 OR v_card_bryce_529<0 OR v_card_preston_529<0
     OR v_card_bryce_vehicle<0 OR v_card_christmas_cruise<0 THEN
    RAISE EXCEPTION 'HARD STOP: Value-Card pins still UNSET (-1). Fill all nine v_card_* from the SAME approved First-Anchor Value Card used for the seed (E2).';
  END IF;

  -- (1) Anchor week is RECONCILED (NOT max — avoids same-session false-fail, RC-1).
  IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=v_anchor_week) THEN
    RAISE EXCEPTION 'HARD STOP: anchor week % is not reconciled. Aborting.', v_anchor_week;
  END IF;

  -- (2) Exactly one seeded week and it IS the anchor (first-anchor invariant).
  IF EXISTS (SELECT 1 FROM public.goal_funding_snapshots
              WHERE model_year=2026 AND week_num<>v_anchor_week) THEN
    RAISE EXCEPTION 'HARD STOP: snapshot rows exist at a week other than the anchor %. Aborting.', v_anchor_week;
  END IF;

  -- (3) Table-wide count = 9 (RC-3).
  SELECT count(*) INTO v_total FROM public.goal_funding_snapshots;
  IF v_total <> 9 THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots table-wide count % <> 9. Aborting.', v_total;
  END IF;

  -- (4) Table-wide EXCLUSIONS — none anywhere in the table (RC-3 / RC-4 overlay gap).
  IF EXISTS (SELECT 1 FROM public.goal_funding_snapshots
              WHERE goal_id IN ('adam_401k','wewe_rccl','wewe_dcl','taxable_etf')) THEN
    RAISE EXCEPTION 'HARD STOP: an excluded goal_id (adam_401k/wewe_rccl/wewe_dcl/taxable_etf) is present in the table. Aborting.';
  END IF;

  -- (5) SA-complete — each of the 9 expected goal_ids present EXACTLY ONCE at the anchor.
  FOREACH gid IN ARRAY v_expected LOOP
    IF (SELECT count(*) FROM public.goal_funding_snapshots
         WHERE model_year=2026 AND week_num=v_anchor_week AND goal_id=gid) <> 1 THEN
      RAISE EXCEPTION 'HARD STOP: expected goal_id % not present exactly once at anchor %. Aborting.', gid, v_anchor_week;
    END IF;
  END LOOP;

  -- (6) Row invariants — source='opening_anchor', funded>=0, in registry, non-auto.
  IF EXISTS (SELECT 1 FROM public.goal_funding_snapshots s
              WHERE s.model_year=2026 AND s.week_num=v_anchor_week
                AND (s.source<>'opening_anchor' OR s.funded_amount<0
                     OR NOT EXISTS (SELECT 1 FROM public.goal_registry g WHERE g.id=s.goal_id)
                     OR EXISTS (SELECT 1 FROM public.goal_registry g WHERE g.id=s.goal_id AND COALESCE(g.auto,false)=true))) THEN
    RAISE EXCEPTION 'HARD STOP: a row violates source/nonneg/registry/non-auto invariants. Aborting.';
  END IF;

  -- (7) CARD-VALUE PINNING — each funded_amount = its approved card pin (RC-3).
  FOREACH gid IN ARRAY v_expected LOOP
    SELECT funded_amount INTO v_amt FROM public.goal_funding_snapshots
      WHERE model_year=2026 AND week_num=v_anchor_week AND goal_id=gid;
    v_pin := CASE gid
      WHEN 'adam_ira'         THEN v_card_adam_ira
      WHEN 'wendy_ira'        THEN v_card_wendy_ira
      WHEN 'wendy_sep'        THEN v_card_wendy_sep
      WHEN 'alaska'           THEN v_card_alaska
      WHEN 'bailey_529'       THEN v_card_bailey_529
      WHEN 'bryce_529'        THEN v_card_bryce_529
      WHEN 'preston_529'      THEN v_card_preston_529
      WHEN 'bryce_vehicle'    THEN v_card_bryce_vehicle
      WHEN 'christmas_cruise' THEN v_card_christmas_cruise
    END;
    IF v_amt IS DISTINCT FROM v_pin THEN
      RAISE EXCEPTION 'HARD STOP: % funded_amount % <> Value-Card pin %. Aborting.', gid, v_amt, v_pin;
    END IF;
  END LOOP;

  RAISE NOTICE 'SA-PROD PASS: 9 rows at single anchor week %, all source=opening_anchor, no excluded ids table-wide, all funded_amounts = Value-Card pins.', v_anchor_week;
END $$;

-- ── SA8 (ADVISORY, INFORMATIONAL — never fails) — one-sided AMEX over-attribution ──
-- amex_held_snapshot_sum − reconciled_amx (weekly_reconciliations.amx) at the anchor.
-- Over-attribution (> $1) is the ONLY advisory flag; under-attribution (negative,
-- RCCL/DCL holding excluded) is EXPECTED. Advisory in 5G-1C; hard two-sided gate is
-- 5G-1E. Anchor single-sourced from the seeded week (max in goal_funding_snapshots).
WITH anchor AS (
  SELECT max(week_num) AS wk FROM public.goal_funding_snapshots WHERE model_year=2026
), agg AS (
  SELECT COALESCE(sum(s.funded_amount),0)::NUMERIC(12,2) AS snapshot_sum
    FROM public.goal_funding_snapshots s, anchor
   WHERE s.model_year=2026 AND s.week_num=anchor.wk
     AND s.goal_id IN ('adam_ira','wendy_ira','bailey_529','bryce_529','preston_529')
), amx AS (
  SELECT wr.amx::NUMERIC(12,2) AS reconciled_amx
    FROM public.weekly_reconciliations wr, anchor WHERE wr.week_num=anchor.wk
)
SELECT 'SA8-advisory' AS note,
       agg.snapshot_sum                                       AS amex_held_snapshot_sum,
       amx.reconciled_amx                                     AS reconciled_amx,
       (agg.snapshot_sum - amx.reconciled_amx)::NUMERIC(12,2) AS over_attribution_amount,
       (agg.snapshot_sum - amx.reconciled_amx) > 1            AS is_over_attributed,
       'advisory only; over_attribution > $1 is a flag; under-attribution (negative) is expected (RCCL/DCL holding excluded); hard gate is 5G-1E' AS interpretation
  FROM agg CROSS JOIN amx;

-- ── SA9: full anchor row dump (eyeball the seeded Value-Card values) ──────────
SELECT 'SA9-rows' AS check, model_year, week_num, goal_id, funded_amount, source, note
  FROM public.goal_funding_snapshots
 WHERE model_year=2026 AND week_num=(SELECT max(week_num) FROM public.goal_funding_snapshots WHERE model_year=2026)
 ORDER BY goal_id;
