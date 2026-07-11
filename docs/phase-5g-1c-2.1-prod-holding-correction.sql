-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1C-2.1 Leg 2 — Week-5 HOLDING-STATE CORRECTION (RCCL/DCL)
--
--   TARGET ......... PRODUCTION  Adam-Dashboard (usayoldrawwmjsmretin)
--   NEVER RUN IN ... STAGING     herndon-fos-staging (pkwotgqivgaapwuqgwqb)
--
-- SENTINEL TEMPLATE — SHIPS UNFILLED (ELEVEN -1 pins). DO NOT RUN.
--   Nine of the pins are the EXISTING E2 opening_anchor funded amounts (proof that
--   they are unchanged); two are the RCCL/DCL correction values. All eleven ship as
--   -1 and Guard B HARD-STOPS while any is NULL or < 0. The operator fills all eleven
--   LOCAL-ONLY (nine from the approved E2 Value Card, two from the approved two-row
--   correction Value Card), produces a value-only diff vs this committed template,
--   and runs the LOCAL copy. The committed template keeps its -1 pins; the filled
--   household values are NEVER committed.
--
-- INTEGRITY: PROVES each of the nine E2 rows EXACTLY (goal_id, model_year, week_num,
--   source=opening_anchor, funded_amount == its E2 pin) BEFORE inserting. Does NOT
--   rely on row count / source count / updated_at / eyeballing. The correction values
--   MUST equal their live goal_registry targets (full funding); a partial-funding case
--   is a SEPARATE reviewed correction package (there is no bypass flag here).
--
-- CONCURRENCY: after the guard, the transaction takes SHARE ROW EXCLUSIVE on
--   goal_funding_snapshots and SHARE on weekly_reconciliations (lock_timeout 5s) so the
--   check->insert window cannot race a concurrent snapshot/reconciliation mutation.
--
-- WHY A DIRECT GUARDED INSERT (not the RPC): save_goal_funding_snapshots REJECTS
--   wewe_rccl/wewe_dcl. Owner path, bypasses RLS in the SQL editor (as the E2 seed).
--   Plain INSERT (NO ON CONFLICT): a rerun raises a UNIQUE(model_year,week_num,goal_id)
--   violation and fails loudly.
--
-- SNAPSHOT SEMANTIC: funded_amount = cumulative funded PROGRESS, not cash held.
--   Payout does NOT reset it to zero; releases are a later lifecycle layer (5G-1B).
--   Never write RCCL/DCL to zero merely because payment occurred. Adds an OMITTED
--   Week-5 opening-state fact. DOES NOT TOUCH the nine E2 opening_anchor rows.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public;

-- ══════════════════════════════════════════════════════════════════════════
-- ██ PRODUCTION GUARD ██ — full material fingerprint + execution identity.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_sysid BIGINT; v_bal NUMERIC(12,2); v_tx BIGINT; v_reg_ids BIGINT;
  v_adam_tgt NUMERIC(12,2); v_wendy_tgt NUMERIC(12,2);
BEGIN
  RAISE NOTICE 'EXECUTION IDENTITY: current_user=%, session_user=%', current_user, session_user;
  -- (a) existence BEFORE querying
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing (accounts/transactions). Aborting.'; END IF;
  IF to_regclass('public.goal_funding_snapshots') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots missing (run E1 first). Aborting.'; END IF;
  IF to_regclass('public.goal_registry') IS NULL OR to_regclass('public.weekly_reconciliations') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry / weekly_reconciliations missing. Aborting.'; END IF;
  -- (b) cluster fingerprint + staging rejection
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid IS DISTINCT FROM 7632885393857617092 THEN
    RAISE EXCEPTION 'HARD STOP: system_identifier % <> 7632885393857617092 — NOT Adam-Dashboard. Aborting.', v_sysid; END IF;
  IF to_regclass('public.app_environment') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: public.app_environment present — looks like staging. Aborting.'; END IF;
  -- (c) AMEX Gold fingerprint
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND OR v_bal IS DISTINCT FROM -8248.50 THEN
    RAISE EXCEPTION 'HARD STOP: amex_gold starting_balance % <> -8248.50 — not the production fingerprint. Aborting.', v_bal; END IF;
  -- (d) transaction floor
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx < 40 THEN RAISE EXCEPTION 'HARD STOP: transactions=% < 40 floor. Aborting.', v_tx; END IF;
  -- (e) 13 canonical registry IDs
  SELECT count(*) INTO v_reg_ids FROM public.goal_registry
   WHERE id IN ('adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529',
                'preston_529','bryce_vehicle','christmas_cruise','adam_401k','wewe_rccl','wewe_dcl','taxable_etf');
  IF v_reg_ids <> 13 THEN RAISE EXCEPTION 'HARD STOP: goal_registry canonical-id count % <> 13. Aborting.', v_reg_ids; END IF;
  -- (f) IRA targets
  SELECT target INTO v_adam_tgt FROM public.goal_registry WHERE id='adam_ira';
  SELECT target INTO v_wendy_tgt FROM public.goal_registry WHERE id='wendy_ira';
  IF v_adam_tgt IS DISTINCT FROM 7500 OR v_wendy_tgt IS DISTINCT FROM 7500 THEN
    RAISE EXCEPTION 'HARD STOP: IRA target(s) <> 7500 (stale registry). Aborting.'; END IF;
END $$;

-- ── Concurrency: hold the write path steady across the check -> insert window ──
SET LOCAL lock_timeout = '5s';
LOCK TABLE public.goal_funding_snapshots IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.weekly_reconciliations IN SHARE MODE;

-- ── Guarded correction insert (11-pin integrity proof) ───────────────────────
DO $$
DECLARE
  v_anchor_week INT := 5;
  -- NINE E2 opening_anchor pins (LOCAL fill from the approved E2 Value Card; -1 = UNSET)
  v_p_adam_ira         NUMERIC(12,2) := -1;
  v_p_wendy_ira        NUMERIC(12,2) := -1;
  v_p_wendy_sep        NUMERIC(12,2) := -1;
  v_p_alaska           NUMERIC(12,2) := -1;
  v_p_bailey_529       NUMERIC(12,2) := -1;
  v_p_bryce_529        NUMERIC(12,2) := -1;
  v_p_preston_529      NUMERIC(12,2) := -1;
  v_p_bryce_vehicle    NUMERIC(12,2) := -1;
  v_p_christmas_cruise NUMERIC(12,2) := -1;
  -- TWO correction values (LOCAL fill from the approved two-row Value Card; -1 = UNSET)
  v_rccl NUMERIC(12,2) := -1;
  v_dcl  NUMERIC(12,2) := -1;
  v_note TEXT := 'Omitted Week-5 opening-state holding fact added after E2; cumulative funded progress (held in AMEX Savings), NOT a payout event (5G-1C-2.1 Leg 2).';
  v_expected TEXT[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
  v_total INT; v_oa INT; v_rc INT; v_dc INT; v_maxrec INT; v_inserted INT;
  v_rccl_tgt NUMERIC(12,2); v_dcl_tgt NUMERIC(12,2);
  gid TEXT; v_pin NUMERIC(12,2); v_amt NUMERIC(12,2); v_src TEXT;
BEGIN
  -- Guard B: ALL ELEVEN pins must be set (NULL-safe).
  IF v_p_adam_ira IS NULL OR v_p_adam_ira<0 OR v_p_wendy_ira IS NULL OR v_p_wendy_ira<0
     OR v_p_wendy_sep IS NULL OR v_p_wendy_sep<0 OR v_p_alaska IS NULL OR v_p_alaska<0
     OR v_p_bailey_529 IS NULL OR v_p_bailey_529<0 OR v_p_bryce_529 IS NULL OR v_p_bryce_529<0
     OR v_p_preston_529 IS NULL OR v_p_preston_529<0 OR v_p_bryce_vehicle IS NULL OR v_p_bryce_vehicle<0
     OR v_p_christmas_cruise IS NULL OR v_p_christmas_cruise<0
     OR v_rccl IS NULL OR v_rccl<0 OR v_dcl IS NULL OR v_dcl<0 THEN
    RAISE EXCEPTION 'HARD STOP: one of the ELEVEN pins is NULL or < 0. Fill nine E2 pins (E2 Value Card) + v_rccl + v_dcl (two-row Value Card), LOCAL only. Aborting.';
  END IF;

  -- Preconditions ---------------------------------------------------------------
  SELECT count(*) INTO v_total FROM public.goal_funding_snapshots;                       -- whole table (pre-5G-1D)
  IF v_total <> 9 THEN RAISE EXCEPTION 'HARD STOP: table-wide count % <> 9 (expected only the nine E2 rows). Aborting.', v_total; END IF;
  SELECT count(*) INTO v_oa FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=v_anchor_week AND source='opening_anchor';        -- includes model_year
  IF v_oa <> 9 THEN RAISE EXCEPTION 'HARD STOP: opening_anchor rows at 2026/wk % = % <> 9. Aborting.', v_anchor_week, v_oa; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=v_anchor_week) THEN
    RAISE EXCEPTION 'HARD STOP: week % is not reconciled. Aborting.', v_anchor_week; END IF;
  SELECT max(week_num) INTO v_maxrec FROM public.weekly_reconciliations;                 -- basis guard (E2 Guard A)
  IF v_maxrec IS DISTINCT FROM v_anchor_week THEN
    RAISE EXCEPTION 'HARD STOP: max reconciled week % <> % — the anchor basis has moved; re-review before correcting. Aborting.', v_maxrec, v_anchor_week; END IF;
  SELECT count(*) INTO v_rc FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=v_anchor_week AND goal_id='wewe_rccl';
  SELECT count(*) INTO v_dc FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=v_anchor_week AND goal_id='wewe_dcl';
  IF v_rc <> 0 OR v_dc <> 0 THEN RAISE EXCEPTION 'HARD STOP: a wk-% RCCL/DCL row already exists (rccl=%, dcl=%). Aborting.', v_anchor_week, v_rc, v_dc; END IF;

  -- PROVE each of the nine E2 rows EXACTLY (id, source=opening_anchor, funded == E2 pin).
  FOREACH gid IN ARRAY v_expected LOOP
    v_pin := CASE gid
      WHEN 'adam_ira' THEN v_p_adam_ira WHEN 'wendy_ira' THEN v_p_wendy_ira WHEN 'wendy_sep' THEN v_p_wendy_sep
      WHEN 'alaska' THEN v_p_alaska WHEN 'bailey_529' THEN v_p_bailey_529 WHEN 'bryce_529' THEN v_p_bryce_529
      WHEN 'preston_529' THEN v_p_preston_529 WHEN 'bryce_vehicle' THEN v_p_bryce_vehicle
      WHEN 'christmas_cruise' THEN v_p_christmas_cruise END;
    SELECT funded_amount, source INTO v_amt, v_src FROM public.goal_funding_snapshots
      WHERE model_year=2026 AND week_num=v_anchor_week AND goal_id=gid;
    IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: E2 opening_anchor row % missing at 2026/wk %. Aborting.', gid, v_anchor_week; END IF;
    IF v_src IS DISTINCT FROM 'opening_anchor' THEN RAISE EXCEPTION 'HARD STOP: E2 row % source % <> opening_anchor. Aborting.', gid, v_src; END IF;
    IF v_amt IS DISTINCT FROM v_pin THEN RAISE EXCEPTION 'HARD STOP: E2 row % funded_amount % <> E2 Value-Card pin %. Aborting.', gid, v_amt, v_pin; END IF;
  END LOOP;

  -- Full-funding guard: each correction MUST equal its live goal_registry target.
  SELECT target INTO v_rccl_tgt FROM public.goal_registry WHERE id='wewe_rccl';
  SELECT target INTO v_dcl_tgt  FROM public.goal_registry WHERE id='wewe_dcl';
  IF v_rccl IS DISTINCT FROM v_rccl_tgt THEN
    RAISE EXCEPTION 'HARD STOP: v_rccl % <> wewe_rccl registry target % (full-funding correction; partial funding is a separate reviewed package). Aborting.', v_rccl, v_rccl_tgt; END IF;
  IF v_dcl IS DISTINCT FROM v_dcl_tgt THEN
    RAISE EXCEPTION 'HARD STOP: v_dcl % <> wewe_dcl registry target %. Aborting.', v_dcl, v_dcl_tgt; END IF;

  -- Plain INSERT of exactly two rows — NO ON CONFLICT (a rerun fails on the unique key).
  INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note)
  VALUES (2026, v_anchor_week, 'wewe_rccl', v_rccl, 'correction', v_note),
         (2026, v_anchor_week, 'wewe_dcl',  v_dcl,  'correction', v_note);
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted <> 2 THEN RAISE EXCEPTION 'HARD STOP: inserted % rows <> 2. Aborting.', v_inserted; END IF;
  RAISE NOTICE 'HOLDING-CORRECTION: 2 correction rows written at week_num=%; nine E2 opening_anchor rows proven unchanged pre-insert.', v_anchor_week;
END $$;

COMMIT;

-- POST-COMMIT report (evidence of the committed state): expect ELEVEN wk-5 rows
-- (nine opening_anchor + two correction). Runs only if the transaction above committed.
SELECT 'COR-post-commit' AS check, model_year, week_num, goal_id, funded_amount, source
  FROM public.goal_funding_snapshots
 WHERE model_year=2026 AND week_num=5
 ORDER BY source, goal_id;
