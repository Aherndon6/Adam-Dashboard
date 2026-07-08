-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1 Staging Environment Marker (BOOTSTRAP)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — DO NOT RUN until Adam has (a) confirmed OUT OF BAND that the target
-- Supabase project ref is NOT the production ref `usayoldrawwmjsmretin`
-- (Settings → General, or psql \conninfo host db.<ref>.supabase.co), and
-- (b) reviewed this file. Run EXACTLY ONCE, on STAGING ONLY.
--
-- Prerequisite: staging must ALREADY have the current baseline schema AND the
-- seeded accounts registry (public.accounts incl. amex_gold, public.transactions,
-- is_allowed_user(), can_write_financials(), fn_set_updated_at()). This marker
-- does not provision the baseline; it marks an already-provisioned staging project.
--
-- The SQL fingerprint guard is a SECOND line of defense, NOT a substitute for the
-- explicit project-ref proof in (a). Atomic: BEGIN/COMMIT so a failure mid-create
-- leaves no partial marker object.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

DO $$
DECLARE v_amex_gold_bal NUMERIC(12,2); v_tx_count BIGINT;
BEGIN
  -- Prereq: baseline schema must exist.
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION
      'HARD STOP: baseline schema missing (public.accounts / public.transactions not found). '
      'Provision staging with the current schema before creating the marker. Aborting.';
  END IF;

  -- Non-idempotent: refuse if the marker already exists.
  IF to_regclass('public.app_environment') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: public.app_environment already exists. Marker is run once. Aborting.';
  END IF;

  -- amex_gold must EXIST (else the fingerprint check below is a silent no-op).
  SELECT starting_balance INTO v_amex_gold_bal FROM public.accounts WHERE key = 'amex_gold';
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). '
      'Seed the accounts registry before marking staging. Aborting.';
  END IF;

  -- Production fingerprint 1: amex_gold prod anchor = -8248.50 (A4, 2026-07-06).
  IF v_amex_gold_bal = -8248.50 THEN
    RAISE EXCEPTION
      'HARD STOP: amex_gold.starting_balance = -8248.50 (production anchor). '
      'Target looks like PRODUCTION or an unscrubbed prod clone. Aborting.';
  END IF;

  -- Production fingerprint 2: production-scale register.
  SELECT count(*) INTO v_tx_count FROM public.transactions;
  IF v_tx_count > 25 THEN
    RAISE EXCEPTION
      'HARD STOP: public.transactions has % rows (> 25). '
      'Target looks like PRODUCTION or an unscrubbed prod clone. Aborting.', v_tx_count;
  END IF;
END $$;

-- ── Create the sentinel (single-row, env='staging') ─────────────────────────
CREATE TABLE public.app_environment (
  env    TEXT        NOT NULL,
  set_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_app_environment_env CHECK (env = 'staging')
);
CREATE UNIQUE INDEX uq_app_environment_singleton ON public.app_environment ((true));
INSERT INTO public.app_environment (env) VALUES ('staging');

COMMIT;

SELECT 'MARKER' AS check, env, set_at FROM public.app_environment;
-- Expected: exactly one row, env='staging'.
