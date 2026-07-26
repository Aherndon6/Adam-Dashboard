-- ============================================================================
-- AU-11 Step 6C-D1 — STAGING-ONLY additive reservation-persistence migration
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Authored by Claude; EXECUTED BY ADAM in the Supabase SQL Editor
-- against the staging project (pkwotgqivgaapwuqgwqb, confirmed <> prod
-- usayoldrawwmjsmretin). Claude ran no SQL. Run inside one transaction.
--
-- Scope (6C-D0 approved, staging-only): additive nullable columns on
-- cash_commitments; +1 commitment_class value; +1 commitment_source value;
-- bidirectional reservation-shape constraint; discretionary_reservation_batches
-- control table; FK; partial unique indexes (one-active-batch, per-goal); RLS +
-- grants on the batch table; comments. NO RPCs. NO client. NO production.
--
-- Frozen/untouched: runModel, authoritativeCurrentChk, getCashAvailabilityEngine,
-- isReservedAsOf, all existing RPCs, save_weekly_closeout_with_snapshots, the
-- nine-goal closeout contract, and cash_commitments RLS (unchanged).
--
-- Preconditions: run docs/phase-au11-6c-d1-staging-preflight.sql FIRST and
-- confirm PASS (env=staging; zero au11 rows; captured constraint names).
-- ============================================================================
BEGIN;

-- ── Guard 1: staging sentinel (second line of defense; Adam still selects target) ──
DO $$
BEGIN
  IF to_regclass('public.app_environment') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env = 'staging') THEN
    RAISE EXCEPTION 'HARD STOP: public.app_environment env=staging not found. Refusing to run outside staging.';
  END IF;
  -- Guard 2: never run where AU-11 reservation rows already exist (idempotency / re-run safety)
  IF EXISTS (SELECT 1 FROM public.cash_commitments WHERE commitment_class = 'discretionary_goal_transfer') THEN
    RAISE EXCEPTION 'HARD STOP: discretionary_goal_transfer rows already present. Aborting.';
  END IF;
END $$;

-- ── (A) additive nullable columns on cash_commitments (no defaults; no table rewrite) ──
ALTER TABLE public.cash_commitments
  ADD COLUMN reservation_batch_id    UUID,        -- FK -> discretionary_reservation_batches.id
  ADD COLUMN goal_id                 TEXT,        -- goal_registry.id
  ADD COLUMN destination_account_ref TEXT,        -- historical LABEL/REFERENCE (goal_registry.dest), NOT accounts.key
  ADD COLUMN bank_reference          TEXT,        -- confirmation/cancellation evidence (NULL until initiated/disposed)
  ADD COLUMN bank_submitted_at       TIMESTAMPTZ; -- scheduled->initiated timestamp

-- ── (B)+(C) widen commitment_class (+ discretionary_goal_transfer) and
--            commitment_source (+ au11_reservation), by the ACTUAL captured
--            constraint names (catalog-dynamic; robust to naming drift). ──
DO $$
DECLARE
  v_cls      TEXT;
  v_src      TEXT;
  v_cls_def  TEXT;
  v_src_def  TEXT;
  v_val      TEXT;
BEGIN
  SELECT conname, pg_get_constraintdef(oid) INTO v_cls, v_cls_def FROM pg_constraint
    WHERE conrelid = 'public.cash_commitments'::regclass AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%commitment_class%';
  SELECT conname, pg_get_constraintdef(oid) INTO v_src, v_src_def FROM pg_constraint
    WHERE conrelid = 'public.cash_commitments'::regclass AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%commitment_source%';
  IF v_cls IS NULL OR v_src IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: could not locate commitment_class/commitment_source CHECK (cls=%, src=%)', v_cls, v_src;
  END IF;

  -- Fail-closed def alignment: the live class CHECK must hold EXACTLY the 7 known values (and not the new one),
  -- and the live source CHECK the 3 known values (and not the new one). Aborts on any drift from the D0 baseline.
  FOREACH v_val IN ARRAY ARRAY['credit_card_payment','rent','bill_payment','tax_transfer','savings_transfer','manual_hold','other_transfer'] LOOP
    IF position('''' || v_val || '''' IN v_cls_def) = 0 THEN
      RAISE EXCEPTION 'HARD STOP: class CHECK missing expected value % (live def drift): %', v_val, v_cls_def;
    END IF;
  END LOOP;
  IF position('discretionary_goal_transfer' IN v_cls_def) > 0 THEN
    RAISE EXCEPTION 'HARD STOP: commitment_class already widened (discretionary_goal_transfer present): %', v_cls_def;
  END IF;
  FOREACH v_val IN ARRAY ARRAY['wd_reconciliation','manual_reconciliation','historical_repair'] LOOP
    IF position('''' || v_val || '''' IN v_src_def) = 0 THEN
      RAISE EXCEPTION 'HARD STOP: source CHECK missing expected value % (live def drift): %', v_val, v_src_def;
    END IF;
  END LOOP;
  IF position('au11_reservation' IN v_src_def) > 0 THEN
    RAISE EXCEPTION 'HARD STOP: commitment_source already widened (au11_reservation present): %', v_src_def;
  END IF;

  EXECUTE format('ALTER TABLE public.cash_commitments DROP CONSTRAINT %I', v_cls);
  ALTER TABLE public.cash_commitments ADD CONSTRAINT cash_commitments_commitment_class_check
    CHECK (commitment_class IN (
      'credit_card_payment','rent','bill_payment','tax_transfer',
      'savings_transfer','manual_hold','other_transfer',
      'discretionary_goal_transfer'));                            -- NEW (exactly +1)

  EXECUTE format('ALTER TABLE public.cash_commitments DROP CONSTRAINT %I', v_src);
  ALTER TABLE public.cash_commitments ADD CONSTRAINT cash_commitments_commitment_source_check
    CHECK (commitment_source IN (
      'wd_reconciliation','manual_reconciliation','historical_repair',
      'au11_reservation'));                                       -- NEW (exactly +1)
END $$;

-- ── (D) bidirectional reservation-shape constraint (NOT VALID, then VALIDATE) ──
-- discretionary_goal_transfer  <=>  commitment_source='au11_reservation'
-- Reservation rows: batch/goal/destination_ref NOT NULL, discretionary_deployment,
-- source_account='truist_checking' (U1). Non-reservation rows: all reservation-only
-- columns NULL (bank_reference is reservation-only in v1). This makes it IMPOSSIBLE
-- for the frozen wrapper (which never sets commitment_source='au11_reservation') to
-- persist a reservation row.
ALTER TABLE public.cash_commitments
  ADD CONSTRAINT chk_au11_reservation_shape CHECK (
    (commitment_class = 'discretionary_goal_transfer'
       AND commitment_source = 'au11_reservation'
       AND reservation_batch_id IS NOT NULL AND goal_id IS NOT NULL
       AND destination_account_ref IS NOT NULL
       AND required_or_discretionary = 'discretionary_deployment'
       AND source_account = 'truist_checking')
    OR
    (commitment_class <> 'discretionary_goal_transfer'
       AND commitment_source <> 'au11_reservation'
       AND reservation_batch_id IS NULL AND goal_id IS NULL
       AND destination_account_ref IS NULL AND bank_reference IS NULL AND bank_submitted_at IS NULL)
  ) NOT VALID;
ALTER TABLE public.cash_commitments VALIDATE CONSTRAINT chk_au11_reservation_shape;

-- ── (E) batch-control table ──
CREATE TABLE public.discretionary_reservation_batches (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_digest      TEXT NOT NULL,                       -- Step-6B deterministic cycle digest
  model_year        INT  NOT NULL DEFAULT 2026,
  source_account    TEXT NOT NULL DEFAULT 'truist_checking'
                        CHECK (source_account = 'truist_checking'),
  basis_model_week  INT  NOT NULL CHECK (basis_model_week BETWEEN 1 AND 31),
  status            TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active','retired','voided')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by        UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at       TIMESTAMPTZ,
  resolved_by       UUID REFERENCES auth.users(id),
  resolution_type   TEXT CHECK (resolution_type IS NULL OR resolution_type IN ('retired','voided')),
  resolution_notes  TEXT,
  UNIQUE (model_year, batch_digest)
);

-- ── (F) FK: reservation rows -> batch (history never cascade-deleted) ──
ALTER TABLE public.cash_commitments
  ADD CONSTRAINT fk_au11_batch FOREIGN KEY (reservation_batch_id)
      REFERENCES public.discretionary_reservation_batches(id)
      ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── (G) DB-enforced ONE ACTIVE BATCH per (model_year, source_account) ──
CREATE UNIQUE INDEX uix_one_active_batch
  ON public.discretionary_reservation_batches (model_year, source_account)
  WHERE status = 'active';

-- ── (H) per-goal uniqueness within a batch (scoped to reservation rows) ──
CREATE UNIQUE INDEX uix_au11_batch_goal
  ON public.cash_commitments (model_year, reservation_batch_id, goal_id)
  WHERE commitment_class = 'discretionary_goal_transfer';

-- ── (I) supporting index: active-batch lifecycle scans / composite matching ──
CREATE INDEX ix_au11_active
  ON public.cash_commitments (model_year, source_account, status)
  WHERE commitment_class = 'discretionary_goal_transfer';

-- ── (J) RLS + grants on the batch table (RPC-only writes; SELECT for allowed users) ──
ALTER TABLE public.discretionary_reservation_batches ENABLE ROW LEVEL SECURITY;
CREATE POLICY drb_select ON public.discretionary_reservation_batches
  FOR SELECT USING (public.is_allowed_user());
-- Defense-in-depth (not evaluated via REST since write privs are revoked below):
CREATE POLICY drb_insert ON public.discretionary_reservation_batches
  FOR INSERT WITH CHECK (public.can_write_financials() AND model_year = 2026);
CREATE POLICY drb_update ON public.discretionary_reservation_batches
  FOR UPDATE USING (public.can_write_financials())
             WITH CHECK (public.can_write_financials() AND model_year = 2026);
REVOKE ALL ON public.discretionary_reservation_batches FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.discretionary_reservation_batches TO authenticated;

-- ── (K) comments ──
COMMENT ON TABLE  public.discretionary_reservation_batches IS
  'AU-11 discretionary-goal reservation batches. One ACTIVE batch per (model_year, source_account) '
  'enforced by uix_one_active_batch. Writes are RPC-only (no INSERT/UPDATE/DELETE grant). Step 6C-D1 (staging).';
COMMENT ON COLUMN public.cash_commitments.reservation_batch_id IS
  'AU-11: FK to discretionary_reservation_batches.id. NULL for all non-reservation rows.';
COMMENT ON COLUMN public.cash_commitments.goal_id IS
  'AU-11: goal_registry.id for a discretionary_goal_transfer reservation. NULL otherwise.';
COMMENT ON COLUMN public.cash_commitments.destination_account_ref IS
  'AU-11: historical destination LABEL/REFERENCE captured from goal_registry.dest at authorization time. '
  'NOT a canonical accounts.key. Immutable; never sole retirement evidence.';
COMMENT ON INDEX public.uix_one_active_batch IS
  'AU-11 load-bearing invariant: at most one active reservation batch per (model_year, source_account), '
  'independent of RPC correctness.';

COMMIT;
-- After COMMIT: reload PostgREST schema cache (NOTIFY pgrst, ''reload schema''; or Supabase API restart)
-- so the new columns/table are exposed. Then run docs/phase-au11-6c-d1-staging-validation.sql.
