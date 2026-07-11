-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1C-2.1 Leg 2 — Week-5 HOLDING-STATE CORRECTION: VALIDATION
--
--   TARGET ......... PRODUCTION  Adam-Dashboard (usayoldrawwmjsmretin)
--   NEVER RUN IN ... STAGING     herndon-fos-staging (pkwotgqivgaapwuqgwqb)
--
-- SENTINEL TEMPLATE — SHIPS UNFILLED (ELEVEN -1 pins). Run AFTER the correction.
-- REPEATABLE READ, READ ONLY transaction: READ ONLY at the default READ COMMITTED
-- isolation does NOT give a stable transaction-wide snapshot, so REPEATABLE READ is
-- required — the production guard, the SA-COR assertions, and the final rows dump all
-- inspect the SAME committed snapshot (a consistent validation view that cannot shift
-- mid-transaction), and the transaction cannot mutate.
-- Fill the nine E2 pins (E2 Value Card) + v_card_rccl/v_card_dcl (two-row correction
-- Value Card) LOCAL-ONLY; the committed template keeps its -1 pins. It PROVES every
-- original E2 row's id/source/exact funded amount, the exact 11-row partition, the
-- correction note, the anchor basis, and independent RCCL/DCL target parity — not just counts.
--
-- Supersedes the E2 SA-PROD "count=9 / no-excluded-id" checks for Week 5: Week 5 now
-- intentionally holds ELEVEN rows (9 opening_anchor + 2 correction). The table-wide
-- count=11 and "no other week" checks are PRE-5G-1D ONLY (5G-1D legitimately writes
-- other weeks); they are NOT the durable snapshot contract.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path TO public;

-- ██ PRODUCTION GUARD ██ — full material fingerprint + execution identity.
DO $$
DECLARE
  v_sysid BIGINT; v_bal NUMERIC(12,2); v_tx BIGINT; v_reg_ids BIGINT;
  v_adam_tgt NUMERIC(12,2); v_wendy_tgt NUMERIC(12,2);
BEGIN
  RAISE NOTICE 'EXECUTION IDENTITY: current_user=%, session_user=%', current_user, session_user;
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing (accounts/transactions). Aborting.'; END IF;
  IF to_regclass('public.goal_funding_snapshots') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots missing. Aborting.'; END IF;
  IF to_regclass('public.goal_registry') IS NULL OR to_regclass('public.weekly_reconciliations') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry / weekly_reconciliations missing. Aborting.'; END IF;
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid IS DISTINCT FROM 7632885393857617092 THEN
    RAISE EXCEPTION 'HARD STOP: system_identifier % <> 7632885393857617092 — NOT Adam-Dashboard. Aborting.', v_sysid; END IF;
  IF to_regclass('public.app_environment') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: public.app_environment present — looks like staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND OR v_bal IS DISTINCT FROM -8248.50 THEN
    RAISE EXCEPTION 'HARD STOP: amex_gold starting_balance % <> -8248.50. Aborting.', v_bal; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx < 40 THEN RAISE EXCEPTION 'HARD STOP: transactions=% < 40 floor. Aborting.', v_tx; END IF;
  SELECT count(*) INTO v_reg_ids FROM public.goal_registry
   WHERE id IN ('adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529',
                'preston_529','bryce_vehicle','christmas_cruise','adam_401k','wewe_rccl','wewe_dcl','taxable_etf');
  IF v_reg_ids <> 13 THEN RAISE EXCEPTION 'HARD STOP: goal_registry canonical-id count % <> 13. Aborting.', v_reg_ids; END IF;
  SELECT target INTO v_adam_tgt FROM public.goal_registry WHERE id='adam_ira';
  SELECT target INTO v_wendy_tgt FROM public.goal_registry WHERE id='wendy_ira';
  IF v_adam_tgt IS DISTINCT FROM 7500 OR v_wendy_tgt IS DISTINCT FROM 7500 THEN
    RAISE EXCEPTION 'HARD STOP: IRA target(s) <> 7500. Aborting.'; END IF;
END $$;

-- ██ SA-COR ██ — authoritative post-correction assertions (11-pin, exact partition).
DO $$
DECLARE
  v_anchor_week INT := 5;
  -- NINE E2 pins + TWO correction pins (LOCAL fill from the SAME Value Cards; -1 = UNSET)
  v_p_adam_ira         NUMERIC(12,2) := -1;
  v_p_wendy_ira        NUMERIC(12,2) := -1;
  v_p_wendy_sep        NUMERIC(12,2) := -1;
  v_p_alaska           NUMERIC(12,2) := -1;
  v_p_bailey_529       NUMERIC(12,2) := -1;
  v_p_bryce_529        NUMERIC(12,2) := -1;
  v_p_preston_529      NUMERIC(12,2) := -1;
  v_p_bryce_vehicle    NUMERIC(12,2) := -1;
  v_p_christmas_cruise NUMERIC(12,2) := -1;
  v_card_rccl NUMERIC(12,2) := -1;
  v_card_dcl  NUMERIC(12,2) := -1;
  -- Approved non-sensitive correction note (must be byte-identical to the correction file).
  v_note TEXT := 'Omitted Week-5 opening-state holding fact added after E2; cumulative funded progress (held in AMEX Savings), NOT a payout event (5G-1C-2.1 Leg 2).';
  v_expected TEXT[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
  v_tw INT; v_total INT; v_oa INT; v_cor INT; v_corids INT; v_bad INT; v_distinct INT; v_other INT; v_maxrec INT; v_badnote INT;
  gid TEXT; v_pin NUMERIC(12,2); v_amt NUMERIC(12,2); v_src TEXT; v_rccl NUMERIC(12,2); v_dcl NUMERIC(12,2);
  v_rccl_tgt NUMERIC(12,2); v_dcl_tgt NUMERIC(12,2);
BEGIN
  -- Guard: all ELEVEN pins set (NULL-safe).
  IF v_p_adam_ira IS NULL OR v_p_adam_ira<0 OR v_p_wendy_ira IS NULL OR v_p_wendy_ira<0
     OR v_p_wendy_sep IS NULL OR v_p_wendy_sep<0 OR v_p_alaska IS NULL OR v_p_alaska<0
     OR v_p_bailey_529 IS NULL OR v_p_bailey_529<0 OR v_p_bryce_529 IS NULL OR v_p_bryce_529<0
     OR v_p_preston_529 IS NULL OR v_p_preston_529<0 OR v_p_bryce_vehicle IS NULL OR v_p_bryce_vehicle<0
     OR v_p_christmas_cruise IS NULL OR v_p_christmas_cruise<0
     OR v_card_rccl IS NULL OR v_card_rccl<0 OR v_card_dcl IS NULL OR v_card_dcl<0 THEN
    RAISE EXCEPTION 'HARD STOP: one of the ELEVEN pins is NULL or < 0. Fill nine E2 pins + v_card_rccl + v_card_dcl LOCAL. Aborting.';
  END IF;

  -- Table-wide count = 11 (PRE-5G-1D ONLY; catches rows under another model_year).
  SELECT count(*) INTO v_tw FROM public.goal_funding_snapshots;
  IF v_tw <> 11 THEN RAISE EXCEPTION 'PRE-5G-1D CHECK: table-wide count % <> 11. Aborting.', v_tw; END IF;

  -- Anchor basis unchanged: Week 5 reconciled AND max reconciled week still 5.
  IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=v_anchor_week) THEN
    RAISE EXCEPTION 'HARD STOP: week % is not reconciled. Aborting.', v_anchor_week; END IF;
  SELECT max(week_num) INTO v_maxrec FROM public.weekly_reconciliations;
  IF v_maxrec IS DISTINCT FROM v_anchor_week THEN
    RAISE EXCEPTION 'HARD STOP: max reconciled week % <> % — anchor basis moved between correction and validation. Aborting.', v_maxrec, v_anchor_week; END IF;

  -- Week 5 partition: exactly 11 = 9 opening_anchor + 2 correction.
  SELECT count(*) INTO v_total FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=v_anchor_week;
  IF v_total <> 11 THEN RAISE EXCEPTION 'HARD STOP: 2026/wk-% count % <> 11. Aborting.', v_anchor_week, v_total; END IF;
  SELECT count(*) INTO v_oa  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=v_anchor_week AND source='opening_anchor';
  SELECT count(*) INTO v_cor FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=v_anchor_week AND source='correction';
  IF v_oa <> 9 THEN RAISE EXCEPTION 'HARD STOP: opening_anchor rows % <> 9 (nine E2 pins must be unchanged). Aborting.', v_oa; END IF;
  IF v_cor <> 2 THEN RAISE EXCEPTION 'HARD STOP: correction rows % <> 2. Aborting.', v_cor; END IF;

  -- Prove EACH of the nine E2 rows: present, source=opening_anchor, funded == E2 pin.
  FOREACH gid IN ARRAY v_expected LOOP
    v_pin := CASE gid
      WHEN 'adam_ira' THEN v_p_adam_ira WHEN 'wendy_ira' THEN v_p_wendy_ira WHEN 'wendy_sep' THEN v_p_wendy_sep
      WHEN 'alaska' THEN v_p_alaska WHEN 'bailey_529' THEN v_p_bailey_529 WHEN 'bryce_529' THEN v_p_bryce_529
      WHEN 'preston_529' THEN v_p_preston_529 WHEN 'bryce_vehicle' THEN v_p_bryce_vehicle
      WHEN 'christmas_cruise' THEN v_p_christmas_cruise END;
    SELECT funded_amount, source INTO v_amt, v_src FROM public.goal_funding_snapshots
      WHERE model_year=2026 AND week_num=v_anchor_week AND goal_id=gid;
    IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: E2 row % missing at 2026/wk %. Aborting.', gid, v_anchor_week; END IF;
    IF v_src IS DISTINCT FROM 'opening_anchor' THEN RAISE EXCEPTION 'HARD STOP: E2 row % source % <> opening_anchor. Aborting.', gid, v_src; END IF;
    IF v_amt IS DISTINCT FROM v_pin THEN RAISE EXCEPTION 'HARD STOP: E2 row % funded % <> E2 pin %. Aborting.', gid, v_amt, v_pin; END IF;
  END LOOP;

  -- The two correction rows are EXACTLY wewe_rccl + wewe_dcl.
  SELECT count(*) INTO v_corids FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=v_anchor_week AND source='correction' AND goal_id IN ('wewe_rccl','wewe_dcl');
  IF v_corids <> 2 THEN RAISE EXCEPTION 'HARD STOP: correction rows are not exactly {wewe_rccl,wewe_dcl}. Aborting.'; END IF;

  -- No unexpected goal_id or source anywhere at wk 5.
  SELECT count(*) INTO v_bad FROM public.goal_funding_snapshots s
    WHERE s.model_year=2026 AND s.week_num=v_anchor_week
      AND ( s.goal_id <> ALL (v_expected || ARRAY['wewe_rccl','wewe_dcl'])
            OR s.source NOT IN ('opening_anchor','correction') );
  IF v_bad > 0 THEN RAISE EXCEPTION 'HARD STOP: % wk-% row(s) have an unexpected goal_id/source. Aborting.', v_bad, v_anchor_week; END IF;

  -- RCCL/DCL correction pinned to the Value Card.
  SELECT funded_amount INTO v_rccl FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=v_anchor_week AND goal_id='wewe_rccl' AND source='correction';
  SELECT funded_amount INTO v_dcl  FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=v_anchor_week AND goal_id='wewe_dcl'  AND source='correction';
  IF v_rccl IS DISTINCT FROM v_card_rccl THEN RAISE EXCEPTION 'HARD STOP: wewe_rccl funded % <> Value-Card pin. Aborting.', v_rccl; END IF;
  IF v_dcl  IS DISTINCT FROM v_card_dcl  THEN RAISE EXCEPTION 'HARD STOP: wewe_dcl funded % <> Value-Card pin. Aborting.', v_dcl;  END IF;

  -- Independent full-funding parity: stored funded == Value-Card pin == live goal_registry target.
  SELECT target INTO v_rccl_tgt FROM public.goal_registry WHERE id='wewe_rccl';
  SELECT target INTO v_dcl_tgt  FROM public.goal_registry WHERE id='wewe_dcl';
  IF v_rccl_tgt IS NULL OR v_dcl_tgt IS NULL THEN RAISE EXCEPTION 'HARD STOP: wewe_rccl/wewe_dcl registry target missing. Aborting.'; END IF;
  IF v_rccl IS DISTINCT FROM v_rccl_tgt OR v_card_rccl IS DISTINCT FROM v_rccl_tgt THEN
    RAISE EXCEPTION 'HARD STOP: wewe_rccl parity broken — stored %, pin %, registry target %. Aborting.', v_rccl, v_card_rccl, v_rccl_tgt; END IF;
  IF v_dcl IS DISTINCT FROM v_dcl_tgt OR v_card_dcl IS DISTINCT FROM v_dcl_tgt THEN
    RAISE EXCEPTION 'HARD STOP: wewe_dcl parity broken — stored %, pin %, registry target %. Aborting.', v_dcl, v_card_dcl, v_dcl_tgt; END IF;

  -- Correction note is EXACTLY the approved non-sensitive note on BOTH correction rows.
  SELECT count(*) INTO v_badnote FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=v_anchor_week AND source='correction'
      AND (note IS DISTINCT FROM v_note);
  IF v_badnote > 0 THEN RAISE EXCEPTION 'HARD STOP: % correction row(s) do not carry the exact approved note. Aborting.', v_badnote; END IF;

  -- Row invariants at wk 5: funded_amount not null and >= 0, in registry, NON-AUTO.
  SELECT count(*) INTO v_bad FROM public.goal_funding_snapshots s
    WHERE s.model_year=2026 AND s.week_num=v_anchor_week
      AND ( s.funded_amount IS NULL OR s.funded_amount < 0
            OR NOT EXISTS (SELECT 1 FROM public.goal_registry g WHERE g.id=s.goal_id)
            OR EXISTS (SELECT 1 FROM public.goal_registry g WHERE g.id=s.goal_id AND COALESCE(g.auto,false)=true) );
  IF v_bad > 0 THEN RAISE EXCEPTION 'HARD STOP: % wk-% row(s) violate nonnull/nonneg/registry/non-auto invariants. Aborting.', v_bad, v_anchor_week; END IF;

  -- No duplicate natural keys (defense beyond the UNIQUE constraint).
  SELECT count(*), count(DISTINCT (model_year, week_num, goal_id)) INTO v_total, v_distinct FROM public.goal_funding_snapshots;
  IF v_total <> v_distinct THEN RAISE EXCEPTION 'HARD STOP: duplicate natural keys present. Aborting.'; END IF;

  -- PRE-5G-1D ONLY: no rows at any other week (NOT the durable contract).
  SELECT count(*) INTO v_other FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num<>v_anchor_week;
  IF v_other <> 0 THEN RAISE EXCEPTION 'PRE-5G-1D CHECK: % rows exist at a week other than % (expected 0 before 5G-1D). Investigate.', v_other, v_anchor_week; END IF;

  RAISE NOTICE 'SA-COR PASS: table-wide=11; anchor basis wk-% (max reconciled=5); 9 opening_anchor (funded==E2 pins) + 2 correction (RCCL/DCL stored==Value-Card pin==live registry target, exact note); no unexpected id/source; row invariants hold; no duplicate keys.', v_anchor_week;
END $$;

-- SA-COR rows dump (eyeball against the E2 Value Card + the two-row correction Value Card).
SELECT 'SA-COR-rows' AS check, model_year, week_num, goal_id, funded_amount, source
  FROM public.goal_funding_snapshots
 WHERE model_year=2026 AND week_num=5
 ORDER BY source, goal_id;

COMMIT;
