-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 3: CORE CLOSEOUT assertions G2-1..G2-8 (READ ONLY). Authored, NOT executed.
-- These are PRE (capture) + POST (assert) helpers. The RPC calls happen via PostgREST (gate2-exec-template.sh)
-- BETWEEN a test's PRE and POST blocks. Run the GUARD once, then run each labeled block at the runbook step.
-- No block mutates state. PRODUCTION IS NOT TOUCHED. Balance-free (synthetic 100..900).
-- ORDER (per runbook §3): G2-19a (monotonic.sql) → G2-1 → G2-2 → G2-3 → G2-4 → G2-5 → G2-6 → G2-7 → G2-8.
-- ─────────────────────────────────────────────────────────────────────────

-- ╔═══════════════════ RUN FIRST: fingerprint guard (read-only) ═══════════════════╗
DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — Gate 2 is staging-only.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t = 1 AND v_s = 1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  RAISE NOTICE 'CORE guard OK (staging).';
END $$;

-- ═══ G2-1 (anon) / G2-2 (unauthorized) — pre-write auth rejects; assert NO wk6 state created ═══
-- RUN: G2-1/G2-2 POST  (after the anon and unauthorized PostgREST calls return 401/403/42501)
DO $$
DECLARE v_r INT; v_s INT;
BEGIN
  SELECT count(*) INTO v_r FROM public.weekly_reconciliations WHERE week_num=6;
  SELECT count(*) INTO v_s FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=6;
  IF v_r <> 0 OR v_s <> 0 THEN RAISE EXCEPTION 'G2-1/2 FAIL: wk6 state created by a rejected auth call (recon=%, snap=%)', v_r, v_s; END IF;
  RAISE NOTICE 'G2-1/G2-2 PASS: no wk6 state after anon/unauthorized rejects.';
END $$;

-- ═══ G2-3 — owner new closeout wk6 ═══
-- RUN: G2-3 PRE  (capture: wk6 must be empty)
SELECT 'G2-3 PRE' AS blk,
       (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=6) AS recon_wk6,
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=6) AS snap_wk6;
-- RUN: G2-3 POST  (after owner normal_closeout wk6 returns success)
DO $$
DECLARE v_recon INT; v_snap INT; v_src INT; v_ts timestamptz; v_age interval;
BEGIN
  SELECT count(*) INTO v_recon FROM public.weekly_reconciliations WHERE week_num=6;
  IF v_recon <> 1 THEN RAISE EXCEPTION 'G2-3 FAIL: expected 1 wk6 reconciliation row, got %', v_recon; END IF;
  SELECT count(*) INTO v_snap FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=6 AND goal_id = ANY(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']);
  IF v_snap <> 9 THEN RAISE EXCEPTION 'G2-3 FAIL: expected 9 eligible wk6 snapshots, got %', v_snap; END IF;
  SELECT count(*) INTO v_src FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=6 AND source <> 'reconciliation';
  IF v_src <> 0 THEN RAISE EXCEPTION 'G2-3 FAIL: % wk6 snapshot(s) not source=reconciliation', v_src; END IF;
  -- recorded_at is a server NOW() (recent), not a client value
  SELECT recorded_at INTO v_ts FROM public.weekly_reconciliations WHERE week_num=6;
  v_age := clock_timestamp() - v_ts;
  IF v_ts IS NULL OR v_age > interval '1 hour' THEN RAISE EXCEPTION 'G2-3 FAIL: recorded_at not a recent server stamp (%, age %)', v_ts, v_age; END IF;
  RAISE NOTICE 'G2-3 PASS: wk6 closed (1 recon, 9 reconciliation snapshots, server recorded_at %). CAPTURE recorded_at=% for G2-4/G2-5/G2-6.', v_ts, v_ts;
END $$;

-- RUN: CORE POST-G2-3 FP — re-run phase-5g-1d-gate2-fingerprints.sql; capture the current FP-3 as
--   (CC0, RECON_W6, SNAP_W6). G2-4, G2-5, G2-6 are all existing-state adjudications on the closed wk6 with
--   NO legitimate change between them, so all three compare against this same captured FP-3 (item 7).

-- ═══ G2-4 — identity retry wk6 (empty arrays) → idempotent; whole-state FP-3 unchanged ═══
-- RUN: G2-4 POST
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC0}}'; c_recon CONSTANT TEXT := '{{FP_RECON_W6}}'; c_snap CONSTANT TEXT := '{{FP_SNAP_W6}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-4 FAIL: idempotent retry changed state (recorded_at must be unchanged)'; END IF;
  RAISE NOTICE 'G2-4 PASS: idempotent retry; whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-5 — GFA01 non-empty commitment resubmit wk6 → whole-state FP-3 unchanged ═══
-- RUN: G2-5 POST  (after the call returns code=GFA01, hint=REQUIRES_SUPERVISED_ADJUDICATION)
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC0}}'; c_recon CONSTANT TEXT := '{{FP_RECON_W6}}'; c_snap CONSTANT TEXT := '{{FP_SNAP_W6}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-5 FAIL: GFA01 changed state (esp. a leaked commitment)'; END IF;
  RAISE NOTICE 'G2-5 PASS: GFA01 raised; whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-6 — changed-value resubmit of the already-closed wk6 → hard-stop; whole-state FP-3 unchanged ═══
-- RUN: G2-6 POST  (after the changed-balance call hard-stops "route to supervised reopen/correction")
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{FP_CC0}}'; c_recon CONSTANT TEXT := '{{FP_RECON_W6}}'; c_snap CONSTANT TEXT := '{{FP_SNAP_W6}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-6 FAIL: changed-value resubmit changed state (changed balance must NOT leak into the closed week)'; END IF;
  RAISE NOTICE 'G2-6 PASS: changed-value resubmit hard-stopped; whole-state FP-3 unchanged (NOT a new-closeout failure).';
END $$;

-- ═══ G2-7 — non-contiguous wk8 while wk7 open → pre-write reject; NO wk8 state ═══
-- (RUN BEFORE G2-8 closes wk7.)
-- RUN: G2-7 PRE   → wk7 must be open (0 rows) and wk8 empty
SELECT 'G2-7 PRE' AS blk,
       (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=7) AS recon_wk7,
       (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=8) AS recon_wk8,
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=8) AS snap_wk8;
-- RUN: G2-7 POST  (after the wk8 call hard-stops "not the next contiguous closeout week")
DO $$
BEGIN
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=8) <> 0
     OR (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=8) <> 0 THEN
    RAISE EXCEPTION 'G2-7 FAIL: wk8 state created by a non-contiguous call'; END IF;
  RAISE NOTICE 'G2-7 PASS: non-contiguous wk8 rejected, no wk8 state.';
END $$;

-- ═══ G2-8 — Wendy (household_admin) normal close wk7 → success ═══
-- RUN: G2-8 PRE   → wk7 empty
SELECT 'G2-8 PRE' AS blk,
       (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=7) AS recon_wk7,
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=7) AS snap_wk7;
-- RUN: G2-8 POST  (after Wendy's normal_closeout wk7 returns success)
DO $$
DECLARE v_recon INT; v_snap INT; v_src INT;
BEGIN
  SELECT count(*) INTO v_recon FROM public.weekly_reconciliations WHERE week_num=7;
  SELECT count(*) INTO v_snap FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=7 AND goal_id = ANY(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']);
  SELECT count(*) INTO v_src FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=7 AND source <> 'reconciliation';
  IF v_recon <> 1 OR v_snap <> 9 OR v_src <> 0 THEN RAISE EXCEPTION 'G2-8 FAIL: wk7 not cleanly closed (recon=%, snap=%, non-recon-src=%)', v_recon, v_snap, v_src; END IF;
  RAISE NOTICE 'G2-8 PASS: Wendy closed wk7 (household_admin may normal-close). CAPTURE wk7 recorded_at now for the reopen sub-phase.';
END $$;
