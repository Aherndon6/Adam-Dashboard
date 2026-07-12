-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 8: G2-20a ATOMIC ROLLBACK — commitment CREATE. Authored, NOT executed.
-- Proves that when the snapshot step fails AFTER the reconciliation RPC has run (persisting a synthetic
-- commitment CREATE), the single wrapper transaction rolls back BOTH halves — no wk10 recon row, no wk10
-- snapshots, and __ATOMIC_TEST_WD__ stays absent. Neither deployed RPC is modified — the only mechanism is
-- the cleared temporary staging trigger/helper on goal_funding_snapshots. Target week: wk10 (next contiguous).
-- Every mutating block carries the exact staging fingerprint guard. PRODUCTION IS NOT TOUCHED. Balance-free.
-- ─────────────────────────────────────────────────────────────────────────

-- ═══ STEP 1 (MUTATING) — pre-setup existence gate + install helper then trigger ═══
DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT; v_trg INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — staging only.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t=1 AND v_s=1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  -- pre-setup existence gate: STOP the suite if a G2-20 test object already exists
  SELECT count(*) INTO v_trg FROM pg_trigger WHERE tgname='_gf_atomic_test_fail_trg' AND NOT tgisinternal;
  IF to_regproc('public._gf_atomic_test_fail') IS NOT NULL OR v_trg <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: a G2-20 test object already exists (helper or trigger) — do NOT continue while a test object is present. Run emergency cleanup first.'; END IF;
  -- fresh wk10 required (no recon, no snapshots)
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=10) <> 0
     OR (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=10) <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: wk10 is not fresh (must have no recon/snapshots).'; END IF;
  -- the create target must be ABSENT before the test
  IF EXISTS (SELECT 1 FROM public.cash_commitments WHERE expected_item_id='__ATOMIC_TEST_WD__') THEN
    RAISE EXCEPTION 'HARD STOP: __ATOMIC_TEST_WD__ already exists — clean up before G2-20a.'; END IF;
END $$;

CREATE FUNCTION public._gf_atomic_test_fail() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN IF NEW.funded_amount = 424242.42 THEN RAISE EXCEPTION 'ATOMIC-TEST synthetic failure'; END IF; RETURN NEW; END $f$;
CREATE TRIGGER _gf_atomic_test_fail_trg BEFORE INSERT ON public.goal_funding_snapshots
  FOR EACH ROW EXECUTE FUNCTION public._gf_atomic_test_fail();

-- ═══ STEP 2 PRE — capture deterministic full-state fingerprints (read) ═══
-- FP_CC_ALL (every commitment), FP_RECON_ALL (every reconciliation), FP_SNAP_OUT10 (every 2026 snapshot
-- OUTSIDE wk10) + wk10 absence + create-target absence. Counts alone would not prove no unrelated change.
SELECT 'G2-20a PRE' AS blk,
       (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=10) AS recon_wk10,
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=10) AS snap_wk10,
       (SELECT count(*) FROM public.cash_commitments WHERE expected_item_id='__ATOMIC_TEST_WD__') AS create_target_present,
  md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(resolution_type,'')||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) AS fp_cc_all,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) AS fp_recon_all,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num <> 10),'')) AS fp_snap_out10;

-- ═══ STEP 3 (HTTP) — run G2_20a() ═══
--   Owner new closeout wk10 with the sentinel snapshot (adam_ira=424242.42) AND a synthetic commitment
--   CREATE (__ATOMIC_TEST_WD__). The recon RPC creates the recon row + commitment; the snapshot INSERT then
--   trips the trigger → the RPC's transaction aborts with "ATOMIC-TEST synthetic failure". EXPECT an error
--   response (not success). Then run STEP 4.

-- ═══ STEP 4 POST — prove FULL rollback + whole-state fingerprints unchanged (read) ═══
-- Paste the STEP 2 PRE fingerprints. Proves NO unrelated commitment/reconciliation/snapshot changed.
DO $$
DECLARE v_recon INT; v_snap INT; v_wd INT; v_cc TEXT; v_rec TEXT; v_out TEXT;
  c_cc CONSTANT TEXT := '{{G2_20A_FP_CC_ALL}}'; c_rec CONSTANT TEXT := '{{G2_20A_FP_RECON_ALL}}'; c_out CONSTANT TEXT := '{{G2_20A_FP_SNAP_OUT10}}';
BEGIN
  SELECT count(*) INTO v_recon FROM public.weekly_reconciliations WHERE week_num=10;
  SELECT count(*) INTO v_snap  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=10;
  SELECT count(*) INTO v_wd    FROM public.cash_commitments WHERE expected_item_id='__ATOMIC_TEST_WD__';
  IF v_recon <> 0 THEN RAISE EXCEPTION 'G2-20a FAIL: wk10 reconciliation row persisted (rollback incomplete)'; END IF;
  IF v_snap  <> 0 THEN RAISE EXCEPTION 'G2-20a FAIL: wk10 snapshot row(s) persisted'; END IF;
  IF v_wd    <> 0 THEN RAISE EXCEPTION 'G2-20a FAIL: commitment CREATE (__ATOMIC_TEST_WD__) persisted — CREATE not rolled back'; END IF;
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(resolution_type,'')||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_rec;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num <> 10),'')) INTO v_out;
  IF v_cc  IS DISTINCT FROM c_cc  THEN RAISE EXCEPTION 'G2-20a FAIL: an unrelated cash_commitments row changed'; END IF;
  IF v_rec IS DISTINCT FROM c_rec THEN RAISE EXCEPTION 'G2-20a FAIL: an unrelated weekly_reconciliations row changed'; END IF;
  IF v_out IS DISTINCT FROM c_out THEN RAISE EXCEPTION 'G2-20a FAIL: a snapshot outside wk10 changed'; END IF;
  RAISE NOTICE 'G2-20a PASS: full rollback — no wk10 recon/snapshots, __ATOMIC_TEST_WD__ absent; all commitments, all reconciliations, and all snapshots outside wk10 byte-identical to pre-call.';
END $$;

-- ═══ STEP 5 (MUTATING) — teardown: drop TRIGGER first, HELPER second; assert both absent ═══
DROP TRIGGER IF EXISTS _gf_atomic_test_fail_trg ON public.goal_funding_snapshots;   -- trigger first
DROP FUNCTION IF EXISTS public._gf_atomic_test_fail();                              -- helper second
DO $$
DECLARE v_trg INT;
BEGIN
  SELECT count(*) INTO v_trg FROM pg_trigger WHERE tgname='_gf_atomic_test_fail_trg' AND NOT tgisinternal;
  IF to_regproc('public._gf_atomic_test_fail') IS NOT NULL OR v_trg <> 0 THEN
    RAISE EXCEPTION 'G2-20a TEARDOWN FAIL: helper or trigger still present'; END IF;
  RAISE NOTICE 'G2-20a TEARDOWN PASS: trigger + helper dropped and confirmed absent.';
END $$;

-- ═══ EMERGENCY CLEANUP (operator disconnect mid-test) — idempotent; run as owner BEFORE anything else ═══
--   DROP TRIGGER IF EXISTS _gf_atomic_test_fail_trg ON public.goal_funding_snapshots;
--   DROP FUNCTION IF EXISTS public._gf_atomic_test_fail();
--   -- then re-run STEP 4 POST to confirm no partial wk10 state; teardown removes any wk10 residue.
