-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1 Seed Validation (STAGING)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — run on STAGING ONLY, AFTER phase-5g-1-seed-mint-staging.sql.
-- Separated from phase-5g-1-validation.sql so the schema validation (which
-- asserts empty tables, V7) is not falsely failed by the presence of seed rows.
-- Read-only. STAGING ONLY.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

-- ── STAGING GUARD ───────────────────────────────────────────────────────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.'; END IF;
  IF to_regclass('public.planned_outflows') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: planned_outflows missing. Run migration + seed first. Aborting.'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint. Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (tx=%). Aborting.', v_tx; END IF;
END $$;

-- ── S1: two staging Mint plans, transfer_funded to amex_savings, out-of-window ─
SELECT 'S1' AS check,
       (SELECT count(*) FROM public.planned_outflows
        WHERE key IN ('mint_adam','mint_bailey')
          AND funding_mode='transfer_funded' AND funding_account_key='amex_savings'
          AND auto_renew=false AND due_date > DATE '2027-01-09') = 2 AS expected_true;

-- ── S2: amount-unconfirmed guard — any NULL-amount plan BLOCKS enabling the flag ─
SELECT 'S2' AS check, key, label, amount_cents AS must_be_confirmed
  FROM public.planned_outflows WHERE amount_cents IS NULL ORDER BY key;

-- ── S3: no events seeded ────────────────────────────────────────────────────
SELECT 'S3' AS check, (SELECT count(*) FROM public.outflow_events) = 0 AS expected_true;
