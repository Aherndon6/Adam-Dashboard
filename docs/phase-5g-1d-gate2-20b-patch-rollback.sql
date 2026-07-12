-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 9: G2-20b ATOMIC ROLLBACK — commitment PATCH. Authored, NOT executed.
-- Proves that when the snapshot step fails AFTER the reconciliation RPC has applied a synthetic commitment
-- PATCH, the single wrapper transaction rolls back BOTH halves — no wk10 recon, no wk10 snapshots, and the
-- pre-seeded __ATOMIC_TEST_PATCH__ row's fields are IDENTICAL to pre-state (patch reverted). Neither deployed
-- RPC is modified — only the cleared temporary staging trigger/helper. Target week: wk10.
-- Committed template is placeholder-only: {{OWNER_UID}} is filled LOCALLY (a real auth.users id); never commit it.
-- Every mutating block carries the exact staging fingerprint guard. PRODUCTION IS NOT TOUCHED. Balance-free.
-- ─────────────────────────────────────────────────────────────────────────

-- ═══ STEP 0 (MUTATING) — pre-seed a single clearly-synthetic committed row at wk10; capture pre-state ═══
DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — staging only.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t=1 AND v_s=1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  IF EXISTS (SELECT 1 FROM public.cash_commitments WHERE expected_item_id='__ATOMIC_TEST_PATCH__') THEN
    RAISE EXCEPTION 'HARD STOP: __ATOMIC_TEST_PATCH__ already exists — clean up before G2-20b.'; END IF;
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=10) <> 0
     OR (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=10) <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: wk10 is not fresh.'; END IF;
END $$;

-- Unresolved-placeholder guard: hard-stop if {{OWNER_UID}} was not filled (i.e. this is the committed
-- template, not a filled local copy) — BEFORE the mutating INSERT below.
DO $$
BEGIN
  IF '{{OWNER_UID}}' LIKE '{{%}}' THEN
    RAISE EXCEPTION 'HARD STOP: {{OWNER_UID}} placeholder unresolved — this is the committed template. Fill a real auth.users id in a local copy (see the fill-copy workflow) before running G2-20b.'; END IF;
END $$;

-- Pre-seed (owner insert). created_by is NOT NULL → supply the LOCAL {{OWNER_UID}} (a real auth.users id).
INSERT INTO public.cash_commitments
  (expected_item_id, model_year, origin_model_week, payee, commitment_class,
   required_or_discretionary, amount_cents, status, notes, created_by)
VALUES
  ('__ATOMIC_TEST_PATCH__', 2026, 10, '__GATE2_ATOMIC__', 'other_transfer',
   'discretionary_deployment', 100, 'planned', '[STAGING-FIXTURE][GATE2] G2-20b patch target', '{{OWNER_UID}}'::uuid);

-- capture pre-state: record id → fill {{PATCH_ID}}; capture the pre-seed ROW byte-fingerprint + whole-state
-- fingerprints (FP_CC_ALL, FP_RECON_ALL, FP_SNAP_OUT10) for the no-unrelated-change proof after rollback.
SELECT 'G2-20b PRE' AS blk, id AS patch_id, amount_cents, original_amount_cents, status, updated_at,
  md5(id::text||'|'||expected_item_id||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(resolution_type,'')||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(notes,'')||'|'||updated_at::text) AS fp_preseed_row
  FROM public.cash_commitments WHERE expected_item_id='__ATOMIC_TEST_PATCH__';
SELECT 'G2-20b PRE-global' AS blk,
  md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(resolution_type,'')||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) AS fp_cc_all,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) AS fp_recon_all,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num <> 10),'')) AS fp_snap_out10;

-- ═══ STEP 1 (MUTATING) — existence gate + install helper then trigger ═══
DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT; v_trg INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — staging only.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t=1 AND v_s=1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  SELECT count(*) INTO v_trg FROM pg_trigger WHERE tgname='_gf_atomic_test_fail_trg' AND NOT tgisinternal;
  IF to_regproc('public._gf_atomic_test_fail') IS NOT NULL OR v_trg <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: a G2-20 test object already exists — do NOT continue. Run emergency cleanup first.'; END IF;
END $$;

CREATE FUNCTION public._gf_atomic_test_fail() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN IF NEW.funded_amount = 424242.42 THEN RAISE EXCEPTION 'ATOMIC-TEST synthetic failure'; END IF; RETURN NEW; END $f$;
CREATE TRIGGER _gf_atomic_test_fail_trg BEFORE INSERT ON public.goal_funding_snapshots
  FOR EACH ROW EXECUTE FUNCTION public._gf_atomic_test_fail();

-- ═══ STEP 2 (HTTP) — run G2_20b() ═══
--   Owner new closeout wk10 with the sentinel snapshot AND a p_patched that modifies __ATOMIC_TEST_PATCH__
--   (amount_cents→222; fill {{PATCH_ID}} from STEP 0). The recon RPC applies the patch; the snapshot INSERT
--   then trips the trigger → the RPC transaction aborts. EXPECT an error response. Then run STEP 3.

-- ═══ STEP 3 POST — prove FULL rollback + pre-seed byte-identical + whole-state unchanged (read) ═══
-- Paste the STEP 0 pre-seed row fingerprint and the global fingerprints.
DO $$
DECLARE v_recon INT; v_snap INT; v_rowfp TEXT; v_cc TEXT; v_rec TEXT; v_out TEXT;
  c_rowfp CONSTANT TEXT := '{{G2_20B_FP_PRESEED_ROW}}';
  c_cc CONSTANT TEXT := '{{G2_20B_FP_CC_ALL}}'; c_rec CONSTANT TEXT := '{{G2_20B_FP_RECON_ALL}}'; c_out CONSTANT TEXT := '{{G2_20B_FP_SNAP_OUT10}}';
BEGIN
  SELECT count(*) INTO v_recon FROM public.weekly_reconciliations WHERE week_num=10;
  SELECT count(*) INTO v_snap  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=10;
  IF v_recon <> 0 THEN RAISE EXCEPTION 'G2-20b FAIL: wk10 reconciliation row persisted'; END IF;
  IF v_snap  <> 0 THEN RAISE EXCEPTION 'G2-20b FAIL: wk10 snapshot row(s) persisted'; END IF;
  -- the pre-seeded commitment row is BYTE-IDENTICAL to pre-state (patch fully rolled back)
  SELECT md5(id::text||'|'||expected_item_id||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(resolution_type,'')||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(notes,'')||'|'||updated_at::text) INTO v_rowfp
    FROM public.cash_commitments WHERE expected_item_id='__ATOMIC_TEST_PATCH__';
  IF v_rowfp IS DISTINCT FROM c_rowfp THEN RAISE EXCEPTION 'G2-20b FAIL: __ATOMIC_TEST_PATCH__ not byte-identical to pre-state — PATCH not fully rolled back'; END IF;
  -- whole-state unchanged (no unrelated commitment / reconciliation / snapshot changed)
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(resolution_type,'')||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_rec;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num <> 10),'')) INTO v_out;
  IF v_cc  IS DISTINCT FROM c_cc  THEN RAISE EXCEPTION 'G2-20b FAIL: an unrelated cash_commitments row changed'; END IF;
  IF v_rec IS DISTINCT FROM c_rec THEN RAISE EXCEPTION 'G2-20b FAIL: an unrelated weekly_reconciliations row changed'; END IF;
  IF v_out IS DISTINCT FROM c_out THEN RAISE EXCEPTION 'G2-20b FAIL: a snapshot outside wk10 changed'; END IF;
  RAISE NOTICE 'G2-20b PASS: full rollback — no wk10 recon/snapshots; __ATOMIC_TEST_PATCH__ byte-identical to pre-state; all commitments/reconciliations/snapshots-outside-wk10 unchanged.';
END $$;

-- ═══ STEP 4 (MUTATING) — teardown: drop TRIGGER first, HELPER second; remove the pre-seed; assert clean ═══
DROP TRIGGER IF EXISTS _gf_atomic_test_fail_trg ON public.goal_funding_snapshots;   -- trigger first
DROP FUNCTION IF EXISTS public._gf_atomic_test_fail();                              -- helper second
DELETE FROM public.cash_commitments WHERE expected_item_id='__ATOMIC_TEST_PATCH__';  -- remove pre-seed
DO $$
DECLARE v_trg INT;
BEGIN
  SELECT count(*) INTO v_trg FROM pg_trigger WHERE tgname='_gf_atomic_test_fail_trg' AND NOT tgisinternal;
  IF to_regproc('public._gf_atomic_test_fail') IS NOT NULL OR v_trg <> 0 THEN
    RAISE EXCEPTION 'G2-20b TEARDOWN FAIL: helper or trigger still present'; END IF;
  IF EXISTS (SELECT 1 FROM public.cash_commitments WHERE expected_item_id='__ATOMIC_TEST_PATCH__') THEN
    RAISE EXCEPTION 'G2-20b TEARDOWN FAIL: pre-seed commitment still present'; END IF;
  RAISE NOTICE 'G2-20b TEARDOWN PASS: trigger + helper dropped; pre-seed removed; all confirmed absent.';
END $$;

-- ═══ EMERGENCY CLEANUP (operator disconnect mid-test) — idempotent; run as owner BEFORE anything else ═══
--   DROP TRIGGER IF EXISTS _gf_atomic_test_fail_trg ON public.goal_funding_snapshots;
--   DROP FUNCTION IF EXISTS public._gf_atomic_test_fail();
--   DELETE FROM public.cash_commitments WHERE expected_item_id='__ATOMIC_TEST_PATCH__';
--   -- then re-run STEP 3 POST to confirm no partial wk10 state.
