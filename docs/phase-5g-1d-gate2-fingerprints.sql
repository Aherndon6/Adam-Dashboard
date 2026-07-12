-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — CANONICAL FULL-STATE FINGERPRINTS (READ ONLY). Authored, NOT executed.
-- The single source of truth for the deterministic whole-database fingerprints every rejection/adjudication
-- test uses to prove NO unrelated state changed (item 7). Three md5s over stable-ordered aggregates:
--   FP_CC    — every cash_commitments row (all mutable fields, incl. updated_at) ORDER BY id
--   FP_RECON — every weekly_reconciliations row (all balances + balance_basis + recorded_at) ORDER BY week_num
--   FP_SNAP  — every 2026 goal_funding_snapshots row (goal_id/funded/source/note) ORDER BY week_num, goal_id
-- Because FP_SNAP spans ALL weeks it also proves "no unrelated week changed" and covers the two wewe_* rows
-- wherever they exist. A rejection test asserts all three unchanged. A test that legitimately mutates ONE
-- surface asserts the OTHER two unchanged + the focal change. PRODUCTION IS NOT TOUCHED.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE v_sysid BIGINT; v_t INT; v_s INT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: production — staging only.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_t, v_s FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_t=1 AND v_s=1) THEN RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint.'; END IF;
  RAISE NOTICE 'FINGERPRINTS guard OK (staging).';
END $$;

-- ╔══ CANONICAL FP-3 CAPTURE — run before AND after every rejection/adjudication call; paste the md5s ══╗
-- The identical three expressions are inlined in each test's POST block (no shared DB object is created).
SELECT
  md5(coalesce((SELECT string_agg(
        id::text||'|'||expected_item_id||'|'||model_year::text||'|'||origin_model_week::text||'|'||payee||'|'
        ||commitment_class||'|'||required_or_discretionary||'|'||amount_cents::text||'|'
        ||coalesce(original_amount_cents::text,'')||'|'||status||'|'||coalesce(reflected_model_week::text,'')||'|'
        ||coalesce(resolved_model_week::text,'')||'|'||coalesce(resolution_type,'')||'|'||coalesce(notes,'')||'|'
        ||updated_at::text, ',' ORDER BY id)
      FROM public.cash_commitments),'')) AS fp_cc,
  md5(coalesce((SELECT string_agg(
        week_num::text||'|'||round(chk,2)::text||'|'||round(sav,2)::text||'|'||round(amx,2)::text||'|'
        ||round(tax,2)::text||'|'||round(lc,2)::text||'|'||coalesce(balance_basis,'')||'|'||recorded_at::text,
        ',' ORDER BY week_num)
      FROM public.weekly_reconciliations),'')) AS fp_recon,
  md5(coalesce((SELECT string_agg(
        week_num::text||'|'||goal_id||'|'||round(funded_amount,2)::text||'|'||source||'|'||coalesce(note,''),
        ',' ORDER BY week_num, goal_id)
      FROM public.goal_funding_snapshots WHERE model_year=2026),'')) AS fp_snap;

-- Per-week breakdowns (optional operator context; not required for the FP-3 compare above).
SELECT 'per-week-recon' AS check, week_num, round(chk,2) chk, round(sav,2) sav, round(amx,2) amx, round(tax,2) tax, round(lc,2) lc, balance_basis, recorded_at
  FROM public.weekly_reconciliations ORDER BY week_num;
SELECT 'per-week-snap' AS check, week_num, source, count(*) n, string_agg(goal_id||'='||round(funded_amount,2)::text, ', ' ORDER BY goal_id) rows
  FROM public.goal_funding_snapshots WHERE model_year=2026 GROUP BY week_num, source ORDER BY week_num, source;

COMMIT;
