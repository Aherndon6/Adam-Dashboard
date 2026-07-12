-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 7: HALF-CLOSE REPAIR G2-18 / G2-18b. Authored, NOT executed.
-- Closes wk8 (then G2-16b runs — see optionb.sql), closes wk9, then induces a synthetic half-close on wk9 and
-- proves repair completes ONLY the missing rows with recorded_at UNCHANGED and nothing else changed anywhere.
-- Deterministic PRE capture + POST comparison for: the full wk9 reconciliation row (all balances + recorded_at);
-- all wk9 cash_commitments; all wk9 eligible snapshots; retained eligible rows; any wewe_* rows; all snapshots
-- and reconciliations OUTSIDE wk9. MANDATORY blocked-advance (wk10 cannot close while wk9 is incomplete) for
-- BOTH the one-missing and zero-snapshot states. Every mutating block carries the exact staging fingerprint
-- guard. PRODUCTION IS NOT TOUCHED. Balance-free (wk9 floor-respecting values: adam_ira=120, others 200..900).
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
  RAISE NOTICE 'HALFCLOSE guard OK (staging).';
END $$;

-- ═══ CLOSE-W8 (HTTP G2_close_w8) — valid contiguous close ═══
-- RUN: CLOSE-W8 POST
DO $$
DECLARE v_r INT; v_s INT;
BEGIN
  SELECT count(*) INTO v_r FROM public.weekly_reconciliations WHERE week_num=8;
  SELECT count(*) INTO v_s FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=8 AND source='reconciliation';
  IF v_r <> 1 OR v_s <> 9 THEN RAISE EXCEPTION 'CLOSE-W8 FAIL: wk8 not cleanly closed (recon=%, snap=%)', v_r, v_s; END IF;
  RAISE NOTICE 'CLOSE-W8 PASS: wk8 closed (9 reconciliation). >>> NOW RUN G2-16b (optionb.sql: above-following reject) BEFORE closing wk9. <<<';
END $$;

-- ═══ CLOSE-W9 (HTTP G2_close_w9) — valid contiguous close; capture the FULL wk9 baseline ═══
-- RUN: CLOSE-W9 POST — capture wk9 recon fields+recorded_at, wk9 eligible-snapshot fingerprints, wk9 commitments,
--       and the OUTSIDE-wk9 fingerprints (snapshots + reconciliations) for the no-unrelated-change proof.
SELECT 'CLOSE-W9 POST' AS blk,
  (SELECT recorded_at FROM public.weekly_reconciliations WHERE week_num=9) AS wk9_recorded_at,
  md5(coalesce((SELECT round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text FROM public.weekly_reconciliations WHERE week_num=9),'')) AS fp_recon9,
  md5(coalesce((SELECT string_agg(goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9),'')) AS fp_snap9_all,
  md5(coalesce((SELECT string_agg(goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9 AND goal_id <> 'bailey_529'),'')) AS fp_snap9_except_bailey,
  md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||amount_cents::text||'|'||status||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments WHERE origin_model_week=9),'')) AS fp_cc9,
  md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(resolution_type,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) AS fp_cc_all,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num <> 9),'')) AS fp_snap_outside9,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations WHERE week_num <> 9),'')) AS fp_recon_outside9;

-- ═══ G2-18 — one-missing half-close repair ═══
-- RUN: G2-18 INDUCE (MUTATING) — remove ONE eligible wk9 row (bailey_529, value 500)
DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT; v_n INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — staging only.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t=1 AND v_s=1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  DELETE FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9 AND goal_id='bailey_529';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'G2-18 INDUCE FAIL: expected to remove exactly 1 wk9 bailey_529 row, removed %', v_n; END IF;
  IF (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9 AND goal_id = ANY(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'])) <> 8 THEN
    RAISE EXCEPTION 'G2-18 INDUCE FAIL: wk9 not reduced to 8 eligible'; END IF;
  RAISE NOTICE 'G2-18 INDUCE: wk9 bailey_529 removed (8/9). Now run G2_block_w10() (blocked-advance) then RUN G2-18 BLOCKED, then G2_18_repair() then RUN G2-18 POST.';
END $$;
-- RUN: G2-18 BLOCKED (after G2_block_w10() while wk9 is one-missing) — wk10 must NOT close; no wk10 state
DO $$
BEGIN
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=10) <> 0
     OR (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=10) <> 0 THEN
    RAISE EXCEPTION 'G2-18 BLOCKED FAIL: wk10 gained state while wk9 was incomplete (advance not blocked)'; END IF;
  RAISE NOTICE 'G2-18 BLOCKED PASS: wk10 cannot close while wk9 is one-missing; no wk10 state.';
END $$;
-- RUN: G2-18 POST (after G2_18_repair(); paste CLOSE-W9 fingerprints)
DO $$
DECLARE v_bailey TEXT; v_now timestamptz; v_elig INT; v_r9 TEXT; v_x TEXT; v_cc9 TEXT; v_out TEXT; v_rout TEXT;
  c_r9 CONSTANT TEXT := '{{FP_RECON9}}'; c_except CONSTANT TEXT := '{{FP_SNAP9_EXCEPT_BAILEY}}';
  c_cc9 CONSTANT TEXT := '{{FP_CC9}}'; c_out CONSTANT TEXT := '{{FP_SNAP_OUTSIDE9}}'; c_rout CONSTANT TEXT := '{{FP_RECON_OUTSIDE9}}';
  c_prev CONSTANT timestamptz := '{{WK9_RECORDED_AT}}';
BEGIN
  -- the removed row is recreated with the correct value + source
  SELECT round(funded_amount,2)||'/'||source INTO v_bailey FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9 AND goal_id='bailey_529';
  IF v_bailey IS DISTINCT FROM '500.00/reconciliation' THEN RAISE EXCEPTION 'G2-18 FAIL: bailey_529 not repaired to 500/reconciliation (got %)', v_bailey; END IF;
  SELECT count(*) INTO v_elig FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9 AND goal_id = ANY(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']);
  IF v_elig <> 9 THEN RAISE EXCEPTION 'G2-18 FAIL: wk9 not complete after repair (% of 9)', v_elig; END IF;
  -- the OTHER EIGHT retained rows are byte-identical
  SELECT md5(coalesce((SELECT string_agg(goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9 AND goal_id <> 'bailey_529'),'')) INTO v_x;
  IF v_x IS DISTINCT FROM c_except THEN RAISE EXCEPTION 'G2-18 FAIL: a retained wk9 eligible row changed during repair'; END IF;
  -- wk9 reconciliation row + recorded_at unchanged (recon RPC must NOT run in repair)
  SELECT recorded_at INTO v_now FROM public.weekly_reconciliations WHERE week_num=9;
  IF v_now IS DISTINCT FROM c_prev THEN RAISE EXCEPTION 'G2-18 FAIL: recorded_at changed during repair'; END IF;
  SELECT md5(coalesce((SELECT round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text FROM public.weekly_reconciliations WHERE week_num=9),'')) INTO v_r9;
  IF v_r9 IS DISTINCT FROM c_r9 THEN RAISE EXCEPTION 'G2-18 FAIL: wk9 reconciliation row changed'; END IF;
  -- wk9 commitments + everything outside wk9 unchanged
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||amount_cents::text||'|'||status||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments WHERE origin_model_week=9),'')) INTO v_cc9;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num <> 9),'')) INTO v_out;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations WHERE week_num <> 9),'')) INTO v_rout;
  IF v_cc9 IS DISTINCT FROM c_cc9 THEN RAISE EXCEPTION 'G2-18 FAIL: a wk9 cash_commitments row changed'; END IF;
  IF v_out IS DISTINCT FROM c_out THEN RAISE EXCEPTION 'G2-18 FAIL: a snapshot outside wk9 changed (incl. any wewe_* row)'; END IF;
  IF v_rout IS DISTINCT FROM c_rout THEN RAISE EXCEPTION 'G2-18 FAIL: a reconciliation outside wk9 changed'; END IF;
  RAISE NOTICE 'G2-18 PASS: exactly the one missing row recreated (500/reconciliation); other eight byte-identical; wk9 recon+recorded_at, wk9 commitments, and all outside-wk9 state unchanged.';
END $$;

-- ═══ G2-18b — zero-snapshot half-close repair (item B) ═══
-- RUN: G2-18b INDUCE (MUTATING) — remove ALL NINE eligible wk9 rows (keep the wk9 reconciliation row)
DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT; v_n INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — staging only.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t=1 AND v_s=1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  DELETE FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9
    AND goal_id = ANY(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 9 THEN RAISE EXCEPTION 'G2-18b INDUCE FAIL: expected to remove 9 wk9 eligible rows, removed %', v_n; END IF;
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=9) <> 1 THEN
    RAISE EXCEPTION 'G2-18b INDUCE FAIL: wk9 reconciliation row must remain (zero-snapshot half-close)'; END IF;
  RAISE NOTICE 'G2-18b INDUCE: wk9 reconciliation-only (0 eligible). Now run G2_block_w10() then RUN G2-18b BLOCKED, then G2_18b_repair() then RUN G2-18b POST.';
END $$;
-- RUN: G2-18b BLOCKED (after G2_block_w10() while wk9 is zero-snapshot) — wk10 must NOT close; no wk10 state
DO $$
BEGIN
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=10) <> 0
     OR (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=10) <> 0 THEN
    RAISE EXCEPTION 'G2-18b BLOCKED FAIL: wk10 gained state while wk9 was zero-snapshot'; END IF;
  RAISE NOTICE 'G2-18b BLOCKED PASS: wk10 cannot close while wk9 is zero-snapshot; no wk10 state.';
END $$;
-- RUN: G2-18b POST (after G2_18b_repair(); paste CLOSE-W9 fingerprints)
DO $$
DECLARE v_elig INT; v_src INT; v_vals INT; v_now timestamptz; v_r9 TEXT; v_cc9 TEXT; v_out TEXT; v_rout TEXT;
  c_r9 CONSTANT TEXT := '{{FP_RECON9}}'; c_cc9 CONSTANT TEXT := '{{FP_CC9}}';
  c_out CONSTANT TEXT := '{{FP_SNAP_OUTSIDE9}}'; c_rout CONSTANT TEXT := '{{FP_RECON_OUTSIDE9}}'; c_prev CONSTANT timestamptz := '{{WK9_RECORDED_AT}}';
BEGIN
  -- exactly the nine eligible recreated, all source=reconciliation, with the floor-respecting wk9 values
  SELECT count(*) INTO v_elig FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9 AND goal_id = ANY(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']);
  SELECT count(*) INTO v_src FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=9 AND source <> 'reconciliation';
  IF v_elig <> 9 OR v_src <> 0 THEN RAISE EXCEPTION 'G2-18b FAIL: zero-snapshot repair did not write all nine reconciliation rows (elig=%, non-recon=%)', v_elig, v_src; END IF;
  SELECT count(*) INTO v_vals FROM (VALUES ('adam_ira',120),('wendy_ira',200),('wendy_sep',300),('alaska',400),('bailey_529',500),('bryce_529',600),('preston_529',700),('bryce_vehicle',800),('christmas_cruise',900)) e(gid,amt)
    JOIN public.goal_funding_snapshots s ON s.model_year=2026 AND s.week_num=9 AND s.goal_id=e.gid WHERE round(s.funded_amount,2)=e.amt AND s.source='reconciliation';
  IF v_vals <> 9 THEN RAISE EXCEPTION 'G2-18b FAIL: recreated wk9 values drift from the floor-respecting nine (% of 9)', v_vals; END IF;
  -- recon row + recorded_at unchanged; outside wk9 unchanged
  SELECT recorded_at INTO v_now FROM public.weekly_reconciliations WHERE week_num=9;
  IF v_now IS DISTINCT FROM c_prev THEN RAISE EXCEPTION 'G2-18b FAIL: recorded_at changed during zero-snapshot repair'; END IF;
  SELECT md5(coalesce((SELECT round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text FROM public.weekly_reconciliations WHERE week_num=9),'')) INTO v_r9;
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||amount_cents::text||'|'||status||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments WHERE origin_model_week=9),'')) INTO v_cc9;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num <> 9),'')) INTO v_out;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations WHERE week_num <> 9),'')) INTO v_rout;
  IF v_r9 IS DISTINCT FROM c_r9 THEN RAISE EXCEPTION 'G2-18b FAIL: wk9 reconciliation row changed'; END IF;
  IF v_cc9 IS DISTINCT FROM c_cc9 THEN RAISE EXCEPTION 'G2-18b FAIL: a wk9 cash_commitments row changed'; END IF;
  IF v_out IS DISTINCT FROM c_out THEN RAISE EXCEPTION 'G2-18b FAIL: a snapshot outside wk9 changed (incl. any wewe_* row)'; END IF;
  IF v_rout IS DISTINCT FROM c_rout THEN RAISE EXCEPTION 'G2-18b FAIL: a reconciliation outside wk9 changed'; END IF;
  RAISE NOTICE 'G2-18b PASS: exactly the nine missing eligible rows recreated (source=reconciliation, floor-respecting values); recorded_at + all outside-wk9 state unchanged; distinct from the branch-H corrupt case.';
END $$;
