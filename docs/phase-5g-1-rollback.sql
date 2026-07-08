-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1 Rollback
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — STAGING ONLY. Drops everything phase-5g-1-migration.sql created, in
-- FK-safe order, wrapped in BEGIN/COMMIT so a mid-drop failure leaves the DB
-- unchanged. Leaves public.app_environment (the staging sentinel) intact.
--
-- Diff check (AT-7): the DB baseline is captured POST-marker/PRE-migration
-- (Spec §4.2, §10), so it already includes app_environment. A fresh schema-only
-- dump AFTER this rollback should therefore diff-equal that baseline. Never run
-- against production.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ── STAGING GUARD ───────────────────────────────────────────────────────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.'; END IF;
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing. Aborting.'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint. Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (tx=%). Aborting.', v_tx; END IF;
END $$;

-- ── Drop child table first; triggers/policies drop with their tables ─────────
-- No CASCADE: fail loud if an unexpected dependency exists.
DROP TABLE public.outflow_events;
DROP TABLE public.planned_outflows;

-- Drop 5G-1 trigger functions (their triggers dropped with the tables above).
DROP FUNCTION public.fn_block_outflow_event_mutation();
DROP FUNCTION public.fn_guard_planned_outflows_immutable();

-- DO NOT drop public.fn_set_updated_at() (shared, from 5D-1).
-- DO NOT drop public.app_environment (staging sentinel retained by design).

COMMIT;

-- ── Confirm teardown ────────────────────────────────────────────────────────
SELECT 'RB1' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='public' AND table_name IN ('planned_outflows','outflow_events')) AS expected_true;
SELECT 'RB2' AS check,
       NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                   WHERE n.nspname='public'
                     AND p.proname IN ('fn_block_outflow_event_mutation','fn_guard_planned_outflows_immutable')) AS expected_true;
SELECT 'RB3' AS check,
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='fn_set_updated_at') AS expected_true;  -- shared, retained
SELECT 'RB4' AS check,
       EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') AS expected_true;    -- sentinel kept
