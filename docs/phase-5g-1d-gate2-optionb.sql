-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 5: OPTION B G2-14, G2-15, G2-16a, G2-17 (+ G2-16b run in Sub-phase 7).
-- Authored, NOT executed. G2-14 corrects wk7 adam_ira 100→120 (source=correction). G2-16a proves the
-- below-preceding-bound reject (new < wk6 preceding 100). G2-16b proves the above-following-bound reject
-- AFTER wk8 is validly closed (new > wk8 following 120). All rejects assert the CANONICAL FP-3 whole-state
-- fingerprint unchanged; G2-14 asserts FP_CC + FP_RECON + all-other-snapshots unchanged and the single focal
-- change. Runs BEFORE wk8+ close (except G2-16b). No block mutates state. PRODUCTION IS NOT TOUCHED. Balance-free.
-- ─────────────────────────────────────────────────────────────────────────

-- ╔═══ RUN FIRST: fingerprint guard ═══╗
DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — staging only.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t=1 AND v_s=1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  RAISE NOTICE 'OPTIONB guard OK (staging).';
END $$;

-- ═══ G2-14 — correct wk7 adam_ira 100→120 within bounds; only that row changes ═══
-- RUN: G2-14 PRE  (adam_ira wk7 must be 100/reconciliation; capture FP_CC, FP_RECON, FP_SNAP_EXCEPT_W7ADAM)
SELECT 'G2-14 PRE' AS blk,
  (SELECT round(funded_amount,2)||'/'||source FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=7 AND goal_id='adam_ira') AS adam_ira_wk7,
  md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(resolution_type,'')||'|'||origin_model_week::text||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) AS fp_cc,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) AS fp_recon,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND NOT (week_num=7 AND goal_id='adam_ira')),'')) AS fp_snap_except;
-- RUN: G2-14 POST  (after correct → corrected:true; paste PRE fp_cc/fp_recon/fp_snap_except)
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snapx TEXT; v_focal INT; v_rows INT;
  c_cc CONSTANT TEXT := '{{G2_14_FP_CC}}'; c_recon CONSTANT TEXT := '{{G2_14_FP_RECON}}'; c_snapx CONSTANT TEXT := '{{G2_14_FP_SNAP_EXCEPT}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(resolution_type,'')||'|'||origin_model_week::text||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND NOT (week_num=7 AND goal_id='adam_ira')),'')) INTO v_snapx;
  SELECT count(*) INTO v_focal FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=7 AND goal_id='adam_ira' AND round(funded_amount,2)=120 AND source='correction' AND COALESCE(note,'') LIKE '%[STAGING-FIXTURE][GATE2]%';
  SELECT count(*) INTO v_rows FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=7 AND goal_id='adam_ira';
  IF v_cc IS DISTINCT FROM c_cc THEN RAISE EXCEPTION 'G2-14 FAIL: a commitment changed'; END IF;
  IF v_recon IS DISTINCT FROM c_recon THEN RAISE EXCEPTION 'G2-14 FAIL: a reconciliation/recorded_at changed'; END IF;
  IF v_snapx IS DISTINCT FROM c_snapx THEN RAISE EXCEPTION 'G2-14 FAIL: a snapshot OTHER than wk7 adam_ira changed'; END IF;
  IF v_focal <> 1 OR v_rows <> 1 THEN RAISE EXCEPTION 'G2-14 FAIL: wk7 adam_ira not exactly one 120/correction/marked row (focal=%, rows=%)', v_focal, v_rows; END IF;
  RAISE NOTICE 'G2-14 PASS: in-place source=correction wk7 adam_ira=120; ONLY that row changed. (This 120/correction row is the G2-19c prior and the G2-16b selected row.) Re-run fingerprints.sql to capture the new FP-3 for G2-15/16a/17.';
END $$;

-- ═══ G2-15 — stale expected_prior (=999) → reject; whole-state FP-3 unchanged ═══
-- RUN: G2-15 POST  (paste the post-G2-14 FP-3)
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC_PG14}}'; c_recon CONSTANT TEXT := '{{FP_RECON_PG14}}'; c_snap CONSTANT TEXT := '{{FP_SNAP_PG14}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-15 FAIL: stale-prior reject changed state'; END IF;
  RAISE NOTICE 'G2-15 PASS: stale expected_prior rejected; whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-16a — below preceding bound (new 50 < wk6 preceding 100; expected_prior=120 current) → reject ═══
-- RUN: G2-16a POST  (paste the post-G2-14 FP-3)
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC_PG14}}'; c_recon CONSTANT TEXT := '{{FP_RECON_PG14}}'; c_snap CONSTANT TEXT := '{{FP_SNAP_PG14}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-16a FAIL: below-preceding reject changed state'; END IF;
  RAISE NOTICE 'G2-16a PASS: below-preceding-bound (new 50 < wk6 100) rejected; whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-17 — Wendy Option B → 42501; whole-state FP-3 unchanged ═══
-- RUN: G2-17 POST  (paste the post-G2-14 FP-3)
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC_PG14}}'; c_recon CONSTANT TEXT := '{{FP_RECON_PG14}}'; c_snap CONSTANT TEXT := '{{FP_SNAP_PG14}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-17 FAIL: Wendy 42501 reject changed state'; END IF;
  RAISE NOTICE 'G2-17 PASS: Wendy Option B rejected (42501); whole-state FP-3 unchanged.';
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- ║  G2-16b — ABOVE-FOLLOWING-BOUND reject. RUN IN SUB-PHASE 7, IMMEDIATELY AFTER "CLOSE-W8",           ║
-- ║  BEFORE closing wk9 or any step that alters wk7 adam_ira. Requires: wk8 closed with adam_ira=120,   ║
-- ║  wk7 adam_ira still 120/correction (its expected_prior). new=130 > following (wk8=120) → reject.    ║
-- ═══════════════════════════════════════════════════════════════════════════
-- RUN: G2-16b PRE  (confirm the selected row + following bound; capture current FP-3 AFTER CLOSE-W8)
SELECT 'G2-16b PRE' AS blk,
  (SELECT round(funded_amount,2)||'/'||source FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=7 AND goal_id='adam_ira') AS wk7_adam_ira_selected,
  (SELECT round(funded_amount,2) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=8 AND goal_id='adam_ira') AS wk8_adam_ira_following,
  md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) AS fp_cc,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) AS fp_recon,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) AS fp_snap;
-- RUN: G2-16b POST  (after the above-following call rejects "correction above following effective value")
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT; v_sel TEXT; v_prev int; v_next int;
  c_cc CONSTANT TEXT := '{{G2_16B_FP_CC}}'; c_recon CONSTANT TEXT := '{{G2_16B_FP_RECON}}'; c_snap CONSTANT TEXT := '{{G2_16B_FP_SNAP}}';
BEGIN
  -- precondition: the selected wk7 row is unchanged (120/correction) and wk8 is the following bound (120)
  SELECT round(funded_amount,2)||'/'||source INTO v_sel FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=7 AND goal_id='adam_ira';
  IF v_sel IS DISTINCT FROM '120.00/correction' THEN RAISE EXCEPTION 'G2-16b PRECONDITION FAIL: wk7 adam_ira is not the selected 120/correction row (got %)', v_sel; END IF;
  IF (SELECT round(funded_amount,2) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=8 AND goal_id='adam_ira') IS DISTINCT FROM 120 THEN
    RAISE EXCEPTION 'G2-16b PRECONDITION FAIL: wk8 adam_ira following bound is not 120 — close wk8 first'; END IF;
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-16b FAIL: above-following reject changed state'; END IF;
  RAISE NOTICE 'G2-16b PASS: above-following-bound (new 130 > wk8 following 120) rejected; whole-state FP-3 unchanged; selected wk7 row preserved.';
END $$;
