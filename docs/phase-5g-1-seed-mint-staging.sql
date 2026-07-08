-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1 Mint Seed (STAGING TEST DATA ONLY)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — STAGING ONLY. Separated from the schema migration on purpose (#11):
-- the PRODUCTION seed is a LATER, Adam-approved script, NOT this file.
--
-- BLOCKING UNKNOWNS before any production seed (do NOT invent):
--   • Vendor: Mint Mobile vs US Mobile — UNCONFIRMED (key slugs provisional).
--   • amount_cents for each line — UNCONFIRMED (seeded NULL here).
--   • Exact due dates — the 2027-02-01 / 2027-05-23 dates are the roadmap's
--     working values and must be confirmed.
--   • Whether an in-window line exists, and any opening-adjustment snapshot.
--
-- These rows are STAGING test fixtures (labels prefixed [STAGING]) to exercise
-- the Cash Planning read path. amount_cents = NULL so validation S2
-- (amount-unconfirmed) correctly flags them. No outflow_events are seeded.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ── STAGING GUARD (shared block) ────────────────────────────────────────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.';
  END IF;
  IF to_regclass('public.planned_outflows') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: planned_outflows missing. Run phase-5g-1-migration.sql first. Aborting.';
  END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint. Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (tx=%). Aborting.', v_tx; END IF;
END $$;

-- ── Staging test seed (amounts NULL = TBD; NO events) ───────────────────────
INSERT INTO public.planned_outflows
  (key, label, planning_bucket, amount_cents, due_date, funding_mode, funding_account_key, source_account_key, auto_renew, recurrence, status, notes)
VALUES
  ('mint_adam',   '[STAGING] Mobile plan — Adam',   'save_up_bill', NULL, DATE '2027-02-01', 'transfer_funded', 'amex_savings', 'truist_checking', false, 'annual', 'active', 'STAGING TEST. Vendor (Mint vs US Mobile), amount, date all TBD (Spec §7/§11).'),
  ('mint_bailey', '[STAGING] Mobile plan — Bailey', 'save_up_bill', NULL, DATE '2027-05-23', 'transfer_funded', 'amex_savings', 'truist_checking', false, 'annual', 'active', 'STAGING TEST. Vendor (Mint vs US Mobile), amount, date all TBD (Spec §7/§11).');

SELECT 'SEED' AS check,
       (SELECT count(*) FROM public.planned_outflows WHERE key IN ('mint_adam','mint_bailey')) AS expected_2,
       (SELECT count(*) FROM public.planned_outflows
        WHERE key IN ('mint_adam','mint_bailey') AND amount_cents IS NULL) AS expected_2_unconfirmed,
       (SELECT count(*) FROM public.outflow_events) AS expected_0_events;

COMMIT;
