-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 10: TEARDOWN & RESTORE. Authored, NOT executed.
-- Refuses to delete ANYTHING until an exact pre-delete FOOTPRINT GATE proves there is no unknown Week-6+
-- state. Only the recognized synthetic Gate-2 rows (exact week/goal/source/value/balance predicates) are
-- then deleted — never a bare `week_num >= 6`. The Week-5 restore is grounded in the actual
-- goal_funding_snapshots schema (created_by_user_id is NULLABLE DEFAULT auth.uid(); the E1 fixture-seed
-- inserts WITHOUT it, so no real UUID is embedded). Every mutating action is under the exact staging guard.
-- PRODUCTION IS NOT TOUCHED. Balance-free.
--
-- PERMITTED safe-interruption recovery states (all recognized, none treated as "unknown"):
--   * Week-9 one-row-missing half-close (8 eligible at wk9);   * Week-9 zero-snapshot half-close (0 eligible, recon kept);
--   * surviving G2-20 trigger/helper (dropped in step 1);      * surviving _gate2_wk5_backup (used by the wk5 restore);
--   * surviving __ATOMIC_TEST_PATCH__ pre-seed (recognized commitment marker → deleted).
--
-- The two Adam/Wendy staging auth/app_users fixtures are NOT deleted here — DEFERRED to a later, separately
-- approved step (no authoritative cleanup file requires it in this package).
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT;
  v_del_snap INT; v_del_recon INT; v_del_cc INT; v_anchor INT; v_anchor_vals INT; v_w5_total INT; v_bad_existing INT;
  v_bad_w10 INT; v_bad_goal INT; v_bad_source INT; v_bad_value INT; v_bad_corr INT; v_bad_recon INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
  c_eligible9 CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
  c_syn_values numeric[] := ARRAY[100,120,200,300,400,500,600,700,800,900];  -- the only synthetic snapshot values in the terminal footprint
BEGIN
  -- EXACT staging fingerprint
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production — Gate 2 teardown is staging-only. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint. Aborting.'; END IF;

  -- (1) drop any residual G2-20 scaffolding (idempotent). The G2-19d backup is dropped in step 5 AFTER
  --     any needed restore, so an interrupted G2-19d can still be recovered here.
  DROP TRIGGER IF EXISTS _gf_atomic_test_fail_trg ON public.goal_funding_snapshots;
  DROP FUNCTION IF EXISTS public._gf_atomic_test_fail();

  -- ═══ PRE-DELETE FOOTPRINT GATE — refuse to delete anything if any unknown Week-6+ state exists ═══
  -- (a) no reconciliation OR snapshot at Week 10 or above (G2-20a/b roll back; wk10 must be absent)
  SELECT (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num >= 10)
       + (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 10) INTO v_bad_w10;
  IF v_bad_w10 <> 0 THEN RAISE EXCEPTION 'TEARDOWN HARD STOP: % unexpected Week-10+ recon/snapshot row(s) — unknown state, refusing to delete. Investigate manually.', v_bad_w10; END IF;
  -- (b) every Week-6+ snapshot goal is one of the eligible nine (no unexpected goal)
  SELECT count(*) INTO v_bad_goal FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6 AND goal_id <> ALL(c_eligible9);
  IF v_bad_goal <> 0 THEN RAISE EXCEPTION 'TEARDOWN HARD STOP: % Week-6+ snapshot(s) for a non-eligible goal — unknown state. Aborting.', v_bad_goal; END IF;
  -- (c) every Week-6+ snapshot source is reconciliation|correction, and corrections occur ONLY at wk7 (the Option-B week)
  SELECT count(*) INTO v_bad_source FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6 AND source NOT IN ('reconciliation','correction');
  IF v_bad_source <> 0 THEN RAISE EXCEPTION 'TEARDOWN HARD STOP: % Week-6+ snapshot(s) with an unexpected source — unknown state. Aborting.', v_bad_source; END IF;
  SELECT count(*) INTO v_bad_corr FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6 AND source='correction' AND week_num <> 7;
  IF v_bad_corr <> 0 THEN RAISE EXCEPTION 'TEARDOWN HARD STOP: % correction snapshot(s) outside wk7 — unknown state. Aborting.', v_bad_corr; END IF;
  -- (d) every Week-6+ snapshot value is one of the synthetic terminal values (no household/other value)
  SELECT count(*) INTO v_bad_value FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6 AND round(funded_amount,2) <> ALL(c_syn_values);
  IF v_bad_value <> 0 THEN RAISE EXCEPTION 'TEARDOWN HARD STOP: % Week-6+ snapshot(s) with a non-synthetic funded_amount — unknown state. Aborting.', v_bad_value; END IF;
  -- (e) every Week-6..9 reconciliation carries the exact synthetic balance set (chk∈{1000,1001}, sav/amx/tax/lc/basis fixed)
  SELECT count(*) INTO v_bad_recon FROM public.weekly_reconciliations WHERE week_num BETWEEN 6 AND 9
    AND NOT (round(chk,2) = ANY(ARRAY[1000,1001]::numeric[]) AND round(sav,2)=2000 AND round(amx,2)=3000 AND round(tax,2)=4000 AND round(lc,2)=5000 AND balance_basis='available_balance');
  IF v_bad_recon <> 0 THEN RAISE EXCEPTION 'TEARDOWN HARD STOP: % Week-6..9 reconciliation row(s) with non-synthetic balances — unknown state. Aborting.', v_bad_recon; END IF;
  RAISE NOTICE 'TEARDOWN FOOTPRINT GATE PASS: no unknown Week-6+ state (no wk10+ rows; eligible-nine only; source recon|correction, corrections only wk7; synthetic values/balances only).';

  -- ═══ CONSTRAINED DELETES — only the recognized synthetic rows (exact predicates; never a bare week_num>=6) ═══
  DELETE FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num BETWEEN 6 AND 9 AND goal_id = ANY(c_eligible9)
      AND source IN ('reconciliation','correction') AND round(funded_amount,2) = ANY(c_syn_values);
  GET DIAGNOSTICS v_del_snap = ROW_COUNT;
  DELETE FROM public.weekly_reconciliations
    WHERE week_num BETWEEN 6 AND 9 AND round(chk,2) = ANY(ARRAY[1000,1001]::numeric[])
      AND round(sav,2)=2000 AND round(amx,2)=3000 AND round(tax,2)=4000 AND round(lc,2)=5000 AND balance_basis='available_balance';
  GET DIAGNOSTICS v_del_recon = ROW_COUNT;
  -- commitments: ONLY the approved Gate-2/atomic identifiers (a non-Gate-2 commitment can never match)
  DELETE FROM public.cash_commitments
    WHERE expected_item_id LIKE '\_\_GATE2\_%' OR expected_item_id LIKE '\_\_ATOMIC\_TEST\_%';
  GET DIAGNOSTICS v_del_cc = ROW_COUNT;
  -- prove the constrained deletes cleared all recognized Week-6+ rows (any residue = a predicate gap, hard-stop)
  IF (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6) <> 0
     OR (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num >= 6) <> 0
     OR (SELECT count(*) FROM public.cash_commitments WHERE expected_item_id LIKE '\_\_GATE2\_%' OR expected_item_id LIKE '\_\_ATOMIC\_TEST\_%') <> 0 THEN
    RAISE EXCEPTION 'TEARDOWN FAIL: recognized Week-6+ rows remain after constrained delete — predicate gap. Aborting.'; END IF;

  -- ═══ (5) GENUINE Week-5 restore (grounded; refuses corruption; never overwrites; validates; backup last) ═══
  -- (5a) refuse to proceed if any PRESENT wk5 eligible row is wrong (amount/source/goal/marker) — never
  --      restore over corruption. Per-goal correctness check against the canonical baseline:
  SELECT count(*) INTO v_bad_existing FROM (VALUES
     ('adam_ira',100),('wendy_ira',200),('wendy_sep',300),('alaska',400),('bailey_529',500),
     ('bryce_529',600),('preston_529',700),('bryce_vehicle',800),('christmas_cruise',900)) e(gid,amt)
    JOIN public.goal_funding_snapshots s ON s.model_year=2026 AND s.week_num=5 AND s.goal_id=e.gid
    WHERE NOT (round(s.funded_amount,2)=e.amt AND s.source='opening_anchor' AND COALESCE(s.note,'') LIKE '%[STAGING-FIXTURE]%');
  IF v_bad_existing <> 0 THEN
    RAISE EXCEPTION 'TEARDOWN HARD STOP: % existing Week-5 eligible row(s) are incorrect (amount/source/marker). Do NOT restore over corruption; investigate manually.', v_bad_existing; END IF;

  -- (5b) restore missing rows from a surviving backup, WITHOUT overwriting
  IF to_regclass('public._gate2_wk5_backup') IS NOT NULL THEN
    INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note, created_by_user_id)
      SELECT model_year, week_num, goal_id, funded_amount, source, note, created_by_user_id
        FROM public._gate2_wk5_backup WHERE model_year=2026 AND week_num=5
      ON CONFLICT (model_year, week_num, goal_id) DO NOTHING;
  END IF;
  -- (5c) reconstruct any STILL-missing row from the repository-grounded canonical baseline (E1 fixture-seed
  --      mechanism: insert WITHOUT created_by_user_id → nullable DEFAULT auth.uid()=NULL in the SQL editor;
  --      no real UUID embedded). Never overwrites an existing row.
  INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note)
    SELECT 2026, 5, e.gid, e.amt, 'opening_anchor', '[STAGING-FIXTURE] anchor (teardown-restored)'
      FROM (VALUES ('adam_ira',100),('wendy_ira',200),('wendy_sep',300),('alaska',400),('bailey_529',500),
                   ('bryce_529',600),('preston_529',700),('bryce_vehicle',800),('christmas_cruise',900)) e(gid,amt)
      WHERE NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots s
                          WHERE s.model_year=2026 AND s.week_num=5 AND s.goal_id=e.gid);

  -- (5d) validate the EXACT nine-row baseline (values/source/marker) BEFORE dropping the backup
  SELECT count(*) INTO v_anchor FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=5 AND source='opening_anchor'
      AND goal_id = ANY(c_eligible9) AND COALESCE(note,'') LIKE '%[STAGING-FIXTURE]%';
  SELECT count(*) INTO v_anchor_vals FROM (VALUES
     ('adam_ira',100),('wendy_ira',200),('wendy_sep',300),('alaska',400),('bailey_529',500),
     ('bryce_529',600),('preston_529',700),('bryce_vehicle',800),('christmas_cruise',900)) e(gid,amt)
    JOIN public.goal_funding_snapshots s ON s.model_year=2026 AND s.week_num=5 AND s.goal_id=e.gid
    WHERE round(s.funded_amount,2) = e.amt AND s.source='opening_anchor';
  SELECT count(*) INTO v_w5_total FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5;
  IF v_anchor <> 9 OR v_anchor_vals <> 9 OR v_w5_total <> 9 THEN
    RAISE EXCEPTION 'TEARDOWN HARD STOP: Week-5 anchor still not the exact nine after restore (marked=%, values=%, total=%). Do NOT drop the backup; investigate.', v_anchor, v_anchor_vals, v_w5_total; END IF;
  -- (5e) drop the backup ONLY after a successful restore + validation
  DROP TABLE IF EXISTS public._gate2_wk5_backup;

  -- (6) final proof: no Week-6+ test rows remain; no scaffolding remains
  IF to_regproc('public._gf_atomic_test_fail') IS NOT NULL
     OR (SELECT count(*) FROM pg_trigger WHERE tgname='_gf_atomic_test_fail_trg' AND NOT tgisinternal) <> 0
     OR to_regclass('public._gate2_wk5_backup') IS NOT NULL THEN
    RAISE EXCEPTION 'TEARDOWN FAIL: G2-20 / backup scaffolding still present'; END IF;

  RAISE NOTICE 'GATE-2 TEARDOWN PASS: footprint gate OK; removed % Week-6..9 snapshot(s), % reconciliation row(s), % synthetic commitment(s); Week-5 anchor exact (nine, 100..900, marked); no scaffolding remains.', v_del_snap, v_del_recon, v_del_cc;
END $$;

COMMIT;

-- ── OPERATOR NEXT STEPS (run separately; NOT executed by this file) ──
-- (7) Run docs/phase-5g-1d-ungrant.sql  — THE ONLY grant-change mechanism; reverts the temporary
--     authenticated EXECUTE on both new functions to the intended inert production state.
-- (8) Re-run docs/phase-5g-1d-validation.sql — prove:
--       * both new functions are INERT again (no PUBLIC/anon/authenticated EXECUTE);
--       * deployed RPC definitions are BYTE-UNCHANGED:
--           save_reconciliation_with_commitments md5 == 1bfde751ac647c5e9a25ba168d08150c
--           save_goal_funding_snapshots        md5 == 154231b3f180349ec328f08ccbe77076
-- (9) DEFERRED (separate approval): cleanup of the Adam/Wendy staging auth/app_users fixtures. NOT done here.
