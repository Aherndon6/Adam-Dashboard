-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 6: MONOTONICITY G2-19a..d (G2-19a runs in Sub-phase 3). Authored, NOT executed.
-- G2-19a/b/c are rejects → assert the CANONICAL FP-3 whole-state fingerprint unchanged (item 7).
-- G2-19d is a CONTROLLED synthetic mutation: it FIRST asserts the backup table is ABSENT (hard-stop to the
-- recovery path if present), creates it FRESH, verifies exactly one backed-up row, removes one wk5 anchor row,
-- confirms the anchor-incomplete hard-stop, then RESTORES and drops the backup only after validation.
-- Every mutating block carries the exact staging fingerprint guard. PRODUCTION IS NOT TOUCHED.
--   G2-19a runs in Sub-phase 3 (before G2-3 closes wk6). G2-19b/c/d run in Sub-phase 6.
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
  RAISE NOTICE 'MONOTONIC guard OK (staging).';
END $$;

-- ═══ G2-19a — anchor prior (RUN IN SUB-PHASE 3, BEFORE G2-3 closes wk6) ═══
-- prior = wk5 opening_anchor (adam_ira=100). Submit wk6 adam_ira=50 (<100) → reject; whole-state FP-3 unchanged.
-- RUN: G2-19a PRE  — capture FP-3 (initial state: only the wk5 anchor)
SELECT 'G2-19a PRE' AS blk,
  md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) AS fp_cc,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) AS fp_recon,
  md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) AS fp_snap;
-- RUN: G2-19a POST  (after the below-anchor wk6 call rejects "monotonic violation")
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{G2_19A_FP_CC}}'; c_recon CONSTANT TEXT := '{{G2_19A_FP_RECON}}'; c_snap CONSTANT TEXT := '{{G2_19A_FP_SNAP}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-19a FAIL: below-anchor wk6 call changed state'; END IF;
  RAISE NOTICE 'G2-19a PASS: below-anchor wk6 rejected (prior=opening_anchor); whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-19b — reconciliation prior (wk8; prior = closed wk7 reconciliation, wendy_ira=200) → reject ═══
-- RUN: G2-19b POST  (paste the current FP-3, captured just before via fingerprints.sql)
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{G2_19B_FP_CC}}'; c_recon CONSTANT TEXT := '{{G2_19B_FP_RECON}}'; c_snap CONSTANT TEXT := '{{G2_19B_FP_SNAP}}';
BEGIN
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-19b FAIL: below-reconciliation-prior reject changed state'; END IF;
  RAISE NOTICE 'G2-19b PASS: below-reconciliation-prior (wendy_ira 50 < wk7 200) rejected; whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-19c — correction prior (wk8; prior = wk7 corrected adam_ira=120, source=correction) → reject ═══
-- RUN: G2-19c PRE  (confirm the prior is a correction)
SELECT 'G2-19c PRE' AS blk, round(funded_amount,2) AS adam_ira_wk7, source
  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=7 AND goal_id='adam_ira';
-- RUN: G2-19c POST  (paste the current FP-3)
DO $$
DECLARE v_cc TEXT; v_recon TEXT; v_snap TEXT;
  c_cc CONSTANT TEXT := '{{G2_19C_FP_CC}}'; c_recon CONSTANT TEXT := '{{G2_19C_FP_RECON}}'; c_snap CONSTANT TEXT := '{{G2_19C_FP_SNAP}}';
BEGIN
  IF (SELECT source FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=7 AND goal_id='adam_ira') <> 'correction' THEN
    RAISE EXCEPTION 'G2-19c PRECONDITION FAIL: wk7 adam_ira prior is not a correction — run G2-14 first'; END IF;
  SELECT md5(coalesce((SELECT string_agg(id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'||updated_at::text, ',' ORDER BY id) FROM public.cash_commitments),'')) INTO v_cc;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text, ',' ORDER BY week_num) FROM public.weekly_reconciliations),'')) INTO v_recon;
  SELECT md5(coalesce((SELECT string_agg(week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''), ',' ORDER BY week_num, goal_id) FROM public.goal_funding_snapshots WHERE model_year=2026),'')) INTO v_snap;
  IF v_cc IS DISTINCT FROM c_cc OR v_recon IS DISTINCT FROM c_recon OR v_snap IS DISTINCT FROM c_snap THEN
    RAISE EXCEPTION 'G2-19c FAIL: below-corrected-prior reject changed state'; END IF;
  RAISE NOTICE 'G2-19c PASS: below-corrected-prior (adam_ira 100 < wk7 corrected 120) rejected; whole-state FP-3 unchanged.';
END $$;

-- ═══ G2-19d — broken chain: remove ONE wk5 eligible anchor row → anchor-incomplete hard-stop ═══
-- Rerunnable & recovery-safe: hard-stop if a prior backup survives. Target the eligible goal 'preston_529' (wk5=700).

-- RUN: G2-19d D1 (MUTATING) — assert backup ABSENT, create FRESH, verify one row, remove the anchor row
DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT; v_n INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — staging only.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t=1 AND v_s=1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  -- rerunnable safety: the backup MUST NOT already exist (a survivor means a prior run was interrupted)
  IF to_regclass('public._gate2_wk5_backup') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: public._gate2_wk5_backup already exists — a prior G2-19d run was interrupted. Run the RECOVERY block below (restore from it, then drop it), or run gate2-teardown.sql, before retrying.'; END IF;
  -- the row to be removed must currently exist exactly once
  SELECT count(*) INTO v_n FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5 AND goal_id='preston_529';
  IF v_n <> 1 THEN RAISE EXCEPTION 'G2-19d D1 FAIL: expected exactly 1 wk5 preston_529 anchor row, found %', v_n; END IF;
  -- create FRESH (no IF NOT EXISTS), back up exactly one row, then delete the anchor row
  CREATE TABLE public._gate2_wk5_backup (LIKE public.goal_funding_snapshots INCLUDING ALL);
  INSERT INTO public._gate2_wk5_backup
    SELECT * FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5 AND goal_id='preston_529';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'G2-19d D1 FAIL: expected to back up exactly 1 row, backed up %', v_n; END IF;
  DELETE FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5 AND goal_id='preston_529';
  IF (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5) <> 8 THEN
    RAISE EXCEPTION 'G2-19d D1 FAIL: wk5 anchor not reduced to 8'; END IF;
  RAISE NOTICE 'G2-19d D1: wk5 preston_529 removed (anchor 8/9); backup created. Now run G2_19d() — expect anchor-incomplete hard-stop — then run D3.';
END $$;

-- RUN: G2-19d D2 (HTTP) — run G2_19d() (a later-week closeout). Expect: "opening anchor incomplete at week 5". Then D3.

-- RUN: G2-19d D3 (MUTATING) — assert no state created, RESTORE from backup, validate the exact nine, drop backup
DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT; v_n INT; v_vals INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — staging only.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t=1 AND v_s=1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  IF to_regclass('public._gate2_wk5_backup') IS NULL THEN RAISE EXCEPTION 'G2-19d D3 FAIL: backup missing — cannot restore (was D1 run?)'; END IF;
  -- the hard-stopped later-week call must have created NO wk8 state
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=8) <> 0
     OR (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=8) <> 0 THEN
    RAISE EXCEPTION 'G2-19d FAIL: later-week call under an incomplete anchor created state'; END IF;
  -- restore ONLY if absent (never overwrite an existing row)
  INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note, created_by_user_id)
    SELECT model_year, week_num, goal_id, funded_amount, source, note, created_by_user_id
      FROM public._gate2_wk5_backup WHERE model_year=2026 AND week_num=5 AND goal_id='preston_529'
    ON CONFLICT (model_year, week_num, goal_id) DO NOTHING;
  -- validate exact nine, values, source, marker
  SELECT count(*) INTO v_n FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5
    AND source='opening_anchor' AND goal_id = ANY(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'])
    AND COALESCE(note,'') LIKE '%[STAGING-FIXTURE]%';
  SELECT count(*) INTO v_vals FROM (VALUES ('adam_ira',100),('wendy_ira',200),('wendy_sep',300),('alaska',400),('bailey_529',500),('bryce_529',600),('preston_529',700),('bryce_vehicle',800),('christmas_cruise',900)) e(gid,amt)
    JOIN public.goal_funding_snapshots s ON s.model_year=2026 AND s.week_num=5 AND s.goal_id=e.gid WHERE round(s.funded_amount,2)=e.amt AND s.source='opening_anchor';
  IF v_n <> 9 OR v_vals <> 9 OR (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5) <> 9 THEN
    RAISE EXCEPTION 'G2-19d D3 FAIL: anchor not fully/exactly restored (marked=%, values=%)', v_n, v_vals; END IF;
  DROP TABLE public._gate2_wk5_backup;   -- drop only AFTER successful restore + validation
  RAISE NOTICE 'G2-19d PASS: anchor-incomplete hard-stop confirmed; wk5 anchor restored to the exact nine; backup dropped.';
END $$;

-- ═══ RECOVERY (only if D1 hard-stopped on a surviving backup, or an interruption left the anchor short) ═══
-- Run as owner; restores from the surviving backup without overwriting, validates, then drops it.
--   DO $$ BEGIN
--     IF to_regclass('public._gate2_wk5_backup') IS NULL THEN RAISE EXCEPTION 'no backup to recover from'; END IF;
--     INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source,note,created_by_user_id)
--       SELECT model_year,week_num,goal_id,funded_amount,source,note,created_by_user_id FROM public._gate2_wk5_backup
--       ON CONFLICT (model_year,week_num,goal_id) DO NOTHING;
--     -- verify the exact nine (as in D3), then: DROP TABLE public._gate2_wk5_backup;
--   END $$;
