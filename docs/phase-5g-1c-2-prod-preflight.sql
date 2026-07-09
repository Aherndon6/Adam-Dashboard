-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 PRODUCTION Preflight (READ-ONLY)
--   goal_funding_snapshots + save_goal_funding_snapshots RPC.
--
--   TARGET ......... PRODUCTION  Adam-Dashboard (usayoldrawwmjsmretin)
--   NEVER RUN IN ... STAGING     herndon-fos-staging (pkwotgqivgaapwuqgwqb)
--
-- NOT byte-identical to the staging preflight: prod lacks public.app_environment
-- so P6-env is REPLACED (P6-sysid + P6-txcount), and hard IRA-target / 13-ID /
-- adam_401k.auto gates are added. Read-only: proves the target is PRODUCTION,
-- proves the 5G-1C-2 object names are unused, proves dependencies exist, and
-- captures baseline evidence (incl. the observed production transaction count).
--
-- Timing: run AFTER the pg_dump schema-only baseline + scripts/export-ai-review-pack.sh
-- are captured and Supabase backup/PITR is confirmed, and BEFORE
-- docs/phase-5g-1c-2-prod-migration.sql. Run outside Wendy's Budget-entry hours.
-- Save the output as exports/db-baseline-5G-1C-2-prod-preflight-<timestamp>.txt.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

-- ══════════════════════════════════════════════════════════════════════════
-- ██ PRODUCTION GUARD ██ — Adam-Dashboard (usayoldrawwmjsmretin)
-- INVERTED counterpart of the staging guard: REQUIRES the production fingerprint
-- and REFUSES staging herndon-fos-staging (pkwotgqivgaapwuqgwqb) and every other
-- cluster. Shared block — identical across the PRODUCTION 5G-1C-2 package.
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

-- ── P1: target 5G-1C-2 table must NOT already exist ─────────────────────────
SELECT 'P1' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.tables
         WHERE table_schema='public' AND table_name='goal_funding_snapshots') AS expected_true;

-- ── P2: no existing policies with the 5G-1C-2 table name ────────────────────
SELECT 'P2' AS check,
       NOT EXISTS (SELECT 1 FROM pg_policies
         WHERE schemaname='public' AND tablename='goal_funding_snapshots') AS expected_true;

-- ── P3: no existing indexes/triggers/functions with the 5G-1C-2 names ───────
SELECT 'P3a' AS check,
       NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                   AND indexname IN ('idx_gfs_year_week','uq_gfs_year_week_goal')) AS expected_true;
SELECT 'P3b' AS check,
       NOT EXISTS (SELECT 1 FROM pg_trigger
                   WHERE tgname='set_goal_funding_snapshots_updated_at') AS expected_true;
SELECT 'P3c' AS check,
       NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                   WHERE n.nspname='public' AND p.proname='save_goal_funding_snapshots') AS expected_true;

-- ── P4: dependencies that MUST exist ────────────────────────────────────────
SELECT 'P4a' AS check, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='fn_set_updated_at') AS expected_true;
SELECT 'P4b' AS check, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='can_write_financials') AS expected_true;
SELECT 'P4c' AS check, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='is_allowed_user') AS expected_true;
-- P4d: FK parent table goal_registry must exist.
SELECT 'P4d' AS check, to_regclass('public.goal_registry') IS NOT NULL AS expected_true;
-- P4e: reconciliation table weekly_reconciliations must exist (RPC reconciled-week guard).
SELECT 'P4e' AS check, to_regclass('public.weekly_reconciliations') IS NOT NULL AS expected_true;
-- ── PROD HARD GATES (added vs staging preflight) ────────────────────────────
-- P4f: all 9 SEEDED goal IDs present in goal_registry (completeness before seed).
SELECT 'P4f' AS check,
       (SELECT count(*) FROM public.goal_registry
         WHERE id IN ('adam_ira','wendy_ira','wendy_sep','alaska','bailey_529',
                      'bryce_529','preston_529','bryce_vehicle','christmas_cruise')) = 9 AS expected_true;
-- P4g: adam_ira target is the corrected $7,500 (no stale $7,000).
SELECT 'P4g' AS check,
       (SELECT target FROM public.goal_registry WHERE id='adam_ira') = 7500 AS expected_true;
-- P4h: wendy_ira target is the corrected $7,500 (no stale $7,000).
SELECT 'P4h' AS check,
       (SELECT target FROM public.goal_registry WHERE id='wendy_ira') = 7500 AS expected_true;
-- P4i: adam_401k is an AUTO goal (will be RPC/seed-excluded).
SELECT 'P4i' AS check,
       (SELECT COALESCE(auto,false) FROM public.goal_registry WHERE id='adam_401k') = true AS expected_true;
-- P4j: the 4 EXCLUDED ids exist and are the excluded set (adam_401k via auto; rest by id).
SELECT 'P4j' AS check,
       (SELECT count(*) FROM public.goal_registry
         WHERE id IN ('adam_401k','wewe_rccl','wewe_dcl','taxable_etf')) = 4 AS expected_true;

-- ── P5: FK-type + schema assumptions this migration is built on ──────────────
-- P5a: goal_registry.id is TEXT (the FK goal_id → goal_registry(id) requires it).
SELECT 'P5a' AS check,
       (SELECT data_type FROM information_schema.columns
        WHERE table_schema='public' AND table_name='goal_registry' AND column_name='id') = 'text' AS expected_true;
-- P5b: weekly_reconciliations HAS week_num — the RPC's reconciled-week lookup key.
SELECT 'P5b' AS check,
       EXISTS (SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='weekly_reconciliations' AND column_name='week_num') AS expected_true;
-- P5c: weekly_reconciliations has NO model_year column. This is WHY the RPC and
--      seed validate reconciliation by week_num ALONE (inherited from 5F-1). Safe
--      only under the current single 31-week 2026 model — documented, not a defect.
SELECT 'P5c' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='weekly_reconciliations' AND column_name='model_year') AS expected_true;

-- ── P6: baseline evidence — inventory + reconciled-week map (informational) ──
SELECT 'P6-tables'    AS evidence, count(*) AS public_tables FROM information_schema.tables WHERE table_schema='public';
SELECT 'P6-goals'     AS evidence, count(*) AS goal_registry_rows FROM public.goal_registry;
-- P6-env REPLACED: production has NO public.app_environment. Positive prod
-- identity evidence instead — system_identifier (must equal the guarded
-- 7632885393857617092) and the observed transaction count (RC-4 evidence; the
-- committed guard floor is a literal >= 40, observed 95 at the 2026-07-09 probe).
SELECT 'P6-sysid'     AS evidence, system_identifier AS prod_system_identifier FROM pg_control_system();
SELECT 'P6-txcount'   AS evidence, count(*) AS observed_transaction_count FROM public.transactions;
-- Reconciled model weeks currently present + the LATEST (drives the anchor: the
-- seed's Guard A requires v_anchor_week = max(week_num); basis-coherence RC-1).
SELECT 'P6-recweeks'  AS evidence, week_num FROM public.weekly_reconciliations ORDER BY week_num;
SELECT 'P6-latestrec' AS evidence, max(week_num) AS latest_reconciled_week FROM public.weekly_reconciliations;
-- Goals that are EXCLUDED from 5G-1C-2 snapshots by policy (auto + holding/deferred),
-- for eyeball confirmation before the seed. (adam_401k via auto; the rest by id.)
SELECT 'P6-excluded'  AS evidence, id, name, auto
  FROM public.goal_registry
 WHERE COALESCE(auto,false) = true
    OR id IN ('wewe_rccl','wewe_dcl','taxable_etf')
 ORDER BY id;
-- Capture these lines into the baseline evidence file alongside the pg_dump baseline.
