-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 PRODUCTION Rollback (BREAK-GLASS)
--
--   TARGET ......... PRODUCTION  Adam-Dashboard (usayoldrawwmjsmretin)
--   NEVER RUN IN ... STAGING     herndon-fos-staging (pkwotgqivgaapwuqgwqb)
--
-- NOT byte-identical to staging (RC-6). Preserves the destructive SEQUENCE only:
-- BEGIN/COMMIT, DROP RPC → DROP TABLE, NO CASCADE. Adds RC-6 protections: a
-- non-empty-table REFUSAL gated on v_confirm_export_done, and RB4 asserts
-- app_environment stays ABSENT (production has none).
--
-- ██ WHEN ALLOWED ██
--   • BEFORE the seed (empty table): normal if prod validation fails.
--   • AFTER the seed: BREAK-GLASS ONLY for a structural / schema / RLS defect.
--     Value mistakes are corrected with source='correction', NOT a drop.
--
-- ██ REQUIRED EXPORT BEFORE ANY POST-SEED ROLLBACK ██
--   The table holds real household anchor data once seeded. BEFORE dropping:
--     1. Export every row — run and SAVE the output of:
--          SELECT * FROM public.goal_funding_snapshots ORDER BY model_year, week_num, goal_id;
--        (or COPY (SELECT * FROM public.goal_funding_snapshots) TO STDOUT WITH CSV HEADER;)
--        to exports/goal_funding_snapshots-prod-rollback-<timestamp>.csv and COMMIT it.
--     2. ONLY THEN set v_confirm_export_done := true in the refusal block below.
--   If the table is non-empty and v_confirm_export_done is false, this HARD-STOPS.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ══════════════════════════════════════════════════════════════════════════
-- ██ PRODUCTION GUARD ██ — Adam-Dashboard (usayoldrawwmjsmretin)
-- INVERTED counterpart of the staging guard: REQUIRES the production fingerprint
-- and REFUSES staging herndon-fos-staging (pkwotgqivgaapwuqgwqb) and every other
-- cluster. On failure RAISE aborts the surrounding transaction (nothing dropped).
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_sysid     BIGINT;
  v_bal       NUMERIC(12,2);
  v_tx        BIGINT;
  v_reg_ids   BIGINT;
  v_adam_tgt  NUMERIC(12,2);
  v_wendy_tgt NUMERIC(12,2);
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid IS DISTINCT FROM 7632885393857617092 THEN
    RAISE EXCEPTION 'HARD STOP: system_identifier % <> 7632885393857617092 — target is NOT Adam-Dashboard (usayoldrawwmjsmretin). Aborting.', v_sysid;
  END IF;
  IF to_regclass('public.app_environment') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: public.app_environment present — looks like staging herndon-fos-staging (pkwotgqivgaapwuqgwqb), not production. Aborting.';
  END IF;
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing (accounts/transactions). Aborting.';
  END IF;
  -- Dependency tables must EXIST before we query them (intentional hard-stop msg,
  -- not a raw missing-relation error): goal_registry (13-ID + IRA targets) and
  -- weekly_reconciliations (anchor/reconciled-week logic downstream).
  IF to_regclass('public.goal_registry') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry missing — cannot check IDs/targets. Aborting.';
  END IF;
  IF to_regclass('public.weekly_reconciliations') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: weekly_reconciliations missing. Aborting.';
  END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: accounts.amex_gold missing — not production. Aborting.'; END IF;
  IF v_bal IS DISTINCT FROM -8248.50 THEN
    RAISE EXCEPTION 'HARD STOP: amex_gold starting_balance % <> -8248.50 — not the Adam-Dashboard production fingerprint. Aborting.', v_bal;
  END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx < 40 THEN RAISE EXCEPTION 'HARD STOP: transactions=% < 40 floor — empty/non-production DB. Aborting.', v_tx; END IF;
  SELECT count(*) INTO v_reg_ids FROM public.goal_registry
   WHERE id IN ('adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529',
                'preston_529','bryce_vehicle','christmas_cruise',
                'adam_401k','wewe_rccl','wewe_dcl','taxable_etf');
  IF v_reg_ids <> 13 THEN RAISE EXCEPTION 'HARD STOP: goal_registry canonical-id count % <> 13. Aborting.', v_reg_ids; END IF;
  SELECT target INTO v_adam_tgt  FROM public.goal_registry WHERE id='adam_ira';
  SELECT target INTO v_wendy_tgt FROM public.goal_registry WHERE id='wendy_ira';
  IF v_adam_tgt IS DISTINCT FROM 7500 THEN RAISE EXCEPTION 'HARD STOP: adam_ira target % <> 7500 (stale IRA target). Aborting.', v_adam_tgt; END IF;
  IF v_wendy_tgt IS DISTINCT FROM 7500 THEN RAISE EXCEPTION 'HARD STOP: wendy_ira target % <> 7500 (stale IRA target). Aborting.', v_wendy_tgt; END IF;
  -- app_users exact-identity assertion — OMITTED by deterministic fallback (Fable
  -- RC-5/RC-6): assert aherndon6@gmail.com + wherndon22@gmail.com ONLY if the
  -- app_users schema supports it; else omit + document. Schema unverified this
  -- pass; omitted to avoid a false-abort. system_identifier equality already
  -- uniquely identifies Adam-Dashboard (usayoldrawwmjsmretin).
END $$;

-- ── RC-6 NON-EMPTY REFUSAL: never drop seeded data without an exported backup ─
DO $$
DECLARE
  v_confirm_export_done BOOLEAN := false;   -- flip to TRUE only AFTER exporting rows (see header)
  v_rows BIGINT;
BEGIN
  SELECT count(*) INTO v_rows FROM public.goal_funding_snapshots;
  IF v_rows > 0 AND NOT v_confirm_export_done THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots has % row(s). Export them (see header) and set v_confirm_export_done:=true before rollback (RC-6). Aborting.', v_rows;
  END IF;
  IF v_rows > 0 THEN
    RAISE NOTICE 'RC-6: dropping a NON-EMPTY goal_funding_snapshots (% rows) with export confirmed.', v_rows;
  END IF;
END $$;

-- ── Drop the RPC first, then the table (the updated_at trigger drops with it) ─
-- No CASCADE: fail loud if an unexpected dependency exists.
DROP FUNCTION public.save_goal_funding_snapshots(INT,INT,JSONB);
DROP TABLE public.goal_funding_snapshots;

-- DO NOT drop public.fn_set_updated_at() (shared, from 5D-1).
-- Production has NO public.app_environment (staging-only sentinel); nothing to retain here.

COMMIT;

-- ── Confirm teardown ────────────────────────────────────────────────────────
SELECT 'RB1' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='public' AND table_name='goal_funding_snapshots') AS expected_true;
SELECT 'RB2' AS check,
       NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                   WHERE n.nspname='public' AND p.proname='save_goal_funding_snapshots') AS expected_true;
SELECT 'RB3' AS check,
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='fn_set_updated_at') AS expected_true;  -- shared, retained
-- RB4 adapted for production (RC-6): app_environment does not exist here — assert it
-- stays ABSENT, rather than querying app_environment.env='staging' as the staging file did.
SELECT 'RB4' AS check,
       to_regclass('public.app_environment') IS NULL AS expected_true;    -- prod has no sentinel
