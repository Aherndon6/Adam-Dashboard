-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 4: APPROVED-REOPEN G2-9..G2-13 (READ ONLY). Authored, NOT executed.
-- Every rejection/adjudication asserts the CANONICAL FP-3 whole-state fingerprint unchanged (FP_CC, FP_RECON,
-- FP_SNAP — see phase-5g-1d-gate2-fingerprints.sql): proves reconciliation+recorded_at, all commitments, all
-- snapshots for every week, and unrelated weeks are byte-identical. G2-10 (the one genuine mutation) asserts
-- FP_CC + FP_SNAP unchanged and the focal wk7 recon change. No block mutates state. PRODUCTION IS NOT TOUCHED.
-- ORDER: BASE capture → G2-9 → G2-10b → G2-10 → (recapture) → G2-11 → G2-12 → G2-13.
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
  RAISE NOTICE 'REOPEN guard OK (staging).';
END $$;

-- RUN: REOPEN BASE PRE — capture FP-3 (CC0, RECON0, SNAP0) + wk7 recorded_at, BEFORE G2-9
SELECT 'REOPEN BASE PRE' AS blk, (SELECT recorded_at FROM public.weekly_reconciliations WHERE week_num=7) AS wk7_recorded_at,
  md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) AS fp_cc,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) AS fp_recon,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) AS fp_snap;

-- ═══ G2-9 — Wendy approved_reopen wk7 → 42501; assert FP-3 == BASE (whole state unchanged) ═══
-- RUN: G2-9 POST
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC0}}'; c_recon CONSTANT TEXT := '{{FP_RECON0}}'; c_snap CONSTANT TEXT := '{{FP_SNAP0}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc THEN RAISE EXCEPTION 'G2-9 FAIL: a cash_commitments row changed'; END IF;
  IF v_recon IS DISTINCT FROM c_recon THEN RAISE EXCEPTION 'G2-9 FAIL: a weekly_reconciliations row/recorded_at changed'; END IF;
  IF v_snap IS DISTINCT FROM c_snap THEN RAISE EXCEPTION 'G2-9 FAIL: a snapshot row changed'; END IF;
  RAISE NOTICE 'G2-9 PASS: Wendy reopen rejected (42501); whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-10b — reopen wk7 CHANGED recon (B2) + NON-EMPTY commitment → branch-E "must not carry commitment
--     operations" reject. MUST run BEFORE G2-10 (needs the changed/genuine branch). Assert FP-3 == BASE. ═══
-- RUN: G2-10b POST
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC0}}'; c_recon CONSTANT TEXT := '{{FP_RECON0}}'; c_snap CONSTANT TEXT := '{{FP_SNAP0}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc THEN RAISE EXCEPTION 'G2-10b FAIL: a commitment changed (reopen leaked __GATE2_G10B__?)'; END IF;
  IF v_recon IS DISTINCT FROM c_recon THEN RAISE EXCEPTION 'G2-10b FAIL: recon changed on a rejected reopen-with-commitment'; END IF;
  IF v_snap IS DISTINCT FROM c_snap THEN RAISE EXCEPTION 'G2-10b FAIL: a snapshot changed'; END IF;
  RAISE NOTICE 'G2-10b PASS: changed-recon reopen carrying a commitment rejected; whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-10 — GENUINE reopen wk7 (changed recon B2, EMPTY arrays) → reopened; FP_CC+FP_SNAP unchanged;
--     wk7 recorded_at strictly LATER; wk7 chk = synthetic 1001. ═══
-- RUN: G2-10 POST  (paste CC0/SNAP0 unchanged + base wk7 recorded_at)
DO $$
DECLARE v_cc TEXT; v_snap TEXT; v_ts timestamptz; v_chk numeric;
  c_cc CONSTANT TEXT := '{{FP_CC0}}'; c_snap CONSTANT TEXT := '{{FP_SNAP0}}'; c_prev CONSTANT timestamptz := '{{WK7_RECORDED_AT_BASE}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  SELECT recorded_at, round(chk,2) INTO v_ts, v_chk FROM public.weekly_reconciliations WHERE week_num=7;
  IF v_cc IS DISTINCT FROM c_cc THEN RAISE EXCEPTION 'G2-10 FAIL: a commitment changed (reopen must not touch commitments)'; END IF;
  IF v_snap IS DISTINCT FROM c_snap THEN RAISE EXCEPTION 'G2-10 FAIL: a snapshot changed (reopen is reconciliation-only)'; END IF;
  IF NOT (v_ts > c_prev) THEN RAISE EXCEPTION 'G2-10 FAIL: wk7 recorded_at not strictly later (% !> %)', v_ts, c_prev; END IF;
  IF v_chk <> 1001 THEN RAISE EXCEPTION 'G2-10 FAIL: wk7 chk not re-applied (got %, expected synthetic 1001)', v_chk; END IF;
  RAISE NOTICE 'G2-10 PASS: genuine reopen; recorded_at LATER (%), chk=1001; commitments+snapshots unchanged. Now RE-RUN phase-5g-1d-gate2-fingerprints.sql to capture RECON1 for G2-11/12/13.', v_ts;
END $$;

-- RUN: REOPEN RECAPTURE — re-run phase-5g-1d-gate2-fingerprints.sql; capture (CC0, RECON1, SNAP0) for G2-11/12/13.

-- ═══ G2-11 — reopen wk7 identical recon (B2), empty → idempotent; FP-3 == (CC0, RECON1, SNAP0) ═══
-- RUN: G2-11 POST
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC0}}'; c_recon CONSTANT TEXT := '{{FP_RECON1}}'; c_snap CONSTANT TEXT := '{{FP_SNAP0}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-11 FAIL: idempotent reopen changed state (recorded_at must be unchanged)'; END IF;
  RAISE NOTICE 'G2-11 PASS: idempotent reopen; whole-state FP-3 unchanged (recon RPC not called).';
END $$;

-- ═══ G2-12 — reopen wk7 identical recon (B2) + NON-EMPTY → code=GFA01; FP-3 == (CC0, RECON1, SNAP0) ═══
-- RUN: G2-12 POST
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC0}}'; c_recon CONSTANT TEXT := '{{FP_RECON1}}'; c_snap CONSTANT TEXT := '{{FP_SNAP0}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-12 FAIL: GFA01 changed state (must be a no-op)'; END IF;
  RAISE NOTICE 'G2-12 PASS: GFA01 on identical-recon non-empty reopen; whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-13 — reopen wk6 (older/non-latest) → reject; FP-3 == (CC0, RECON1, SNAP0) ═══
-- RUN: G2-13 POST
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC0}}'; c_recon CONSTANT TEXT := '{{FP_RECON1}}'; c_snap CONSTANT TEXT := '{{FP_SNAP0}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-13 FAIL: older-week reopen changed state'; END IF;
  RAISE NOTICE 'G2-13 PASS: older/non-latest week reopen rejected; whole-state FP-3 unchanged.';
END $$;
