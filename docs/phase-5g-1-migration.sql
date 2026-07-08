-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1 Migration (planned_outflows + outflow_events)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — DO NOT RUN until: (1) staging gate satisfied (Spec §3), (2) DB baseline
-- captured post-marker/pre-migration (Spec §4.2, §10), (3) all preflight checks
-- pass, (4) Adam approves. STAGING ONLY. No prod DDL.
--
-- SCHEMA ONLY — no seed. Mint seed is a separate, approval-gated file
-- (phase-5g-1-seed-mint-staging.sql for staging; the production seed is a later
-- Adam-approved script). Vendor (Mint Mobile vs US Mobile), amounts, and exact
-- dates are unconfirmed (Spec §7, §11).
--
-- Wrapped in BEGIN/COMMIT so a mid-file failure leaves NO partial objects.
-- Intentionally NOT idempotent: CREATE (not CREATE OR REPLACE), no IF NOT EXISTS
-- except the guards. A partial/repeat run fails loudly.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ── STAGING GUARD (on failure, RAISE aborts the transaction; nothing commits) ─
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: app_environment missing. Run phase-5g-1-staging-env-marker.sql first. Aborting.';
  END IF;
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing (accounts/transactions). Aborting.';
  END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (amex_gold=-8248.50). Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (transactions=% > 25). Aborting.', v_tx; END IF;
END $$;

-- ── 1. planned_outflows (the plan; NO stored balance — rollup lives in events)
-- created_by_user_id: nullable audit context (auth.uid()=NULL under SQL editor).
-- RLS is HOUSEHOLD-level (is_allowed_user()/can_write_financials()), not row-owner.
-- created_by_user_id, created_at, and key are IMMUTABLE post-insert (trigger below).
CREATE TABLE public.planned_outflows (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by_user_id  UUID        DEFAULT auth.uid() REFERENCES auth.users(id),
  key                 TEXT        NOT NULL,
  label               TEXT        NOT NULL,
  planning_bucket     TEXT        NOT NULL,
  amount_cents        BIGINT,
  due_date            DATE        NOT NULL,
  funding_mode        TEXT        NOT NULL DEFAULT 'transfer_funded',
  funding_account_key TEXT        REFERENCES public.accounts(key) ON UPDATE CASCADE ON DELETE RESTRICT,
  source_account_key  TEXT        REFERENCES public.accounts(key) ON UPDATE CASCADE ON DELETE RESTRICT,
  auto_renew          BOOLEAN     NOT NULL DEFAULT false,
  recurrence          TEXT,
  status              TEXT        NOT NULL DEFAULT 'active',
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_planned_outflows_amount       CHECK (amount_cents IS NULL OR amount_cents > 0),
  CONSTRAINT chk_planned_outflows_bucket       CHECK (planning_bucket IN ('save_up_bill','upcoming_spend')),
  CONSTRAINT chk_planned_outflows_funding_mode CHECK (funding_mode IN ('transfer_funded','earmark_funded')),
  CONSTRAINT chk_planned_outflows_status       CHECK (status IN ('active','archived','paid_closed')),
  CONSTRAINT chk_planned_outflows_transfer_funding CHECK (
    funding_mode <> 'transfer_funded'
    OR (funding_account_key IS NOT NULL AND source_account_key IS NOT NULL)
  )
);

COMMENT ON TABLE public.planned_outflows IS
  'Phase 5G-1 — Cash Planning plan entity. NO stored balance: current set-aside = '
  'SUM(outflow_events.amount_cents). amount_cents NULL = TBD. due_date may fall outside '
  'the weekly model window. created_by_user_id nullable audit context (household-level RLS). '
  'created_by_user_id/created_at/key immutable post-insert. No hard delete via app/RLS.';

CREATE UNIQUE INDEX uq_planned_outflows_key ON public.planned_outflows(key);
CREATE INDEX idx_planned_outflows_status_due ON public.planned_outflows(status, due_date ASC);

CREATE TRIGGER set_planned_outflows_updated_at
  BEFORE UPDATE ON public.planned_outflows
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- Immutability of audit + identity columns (CREATE, not OR REPLACE).
-- Runs BEFORE the updated_at trigger (name sorts before 'set_...'); it never
-- touches updated_at, so a normal label/amount edit is unaffected.
CREATE FUNCTION public.fn_guard_planned_outflows_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.created_by_user_id IS DISTINCT FROM OLD.created_by_user_id
     OR NEW.created_at       IS DISTINCT FROM OLD.created_at
     OR NEW.key              IS DISTINCT FROM OLD.key THEN
    RAISE EXCEPTION
      'planned_outflows: created_by_user_id, created_at, and key are immutable after insert. '
      'To retire/rename, archive (status) and create a new row.';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER guard_planned_outflows_immutable
  BEFORE UPDATE ON public.planned_outflows
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_planned_outflows_immutable();

-- ── 2. outflow_events (append-only ledger; signed amounts; NO updated_at) ─────
-- funding_account_key is NOT NULL (#5): each event permanently records the real
-- account that moved, so a later edit to the plan's funding_account_key does not
-- rewrite history. The app copies the parent's funding_account_key by default.
CREATE TABLE public.outflow_events (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by_user_id  UUID        DEFAULT auth.uid() REFERENCES auth.users(id),
  planned_outflow_id  UUID        NOT NULL REFERENCES public.planned_outflows(id) ON DELETE RESTRICT,
  event_type          TEXT        NOT NULL,
  amount_cents        BIGINT      NOT NULL,
  event_date          DATE        NOT NULL,
  funding_account_key TEXT        NOT NULL REFERENCES public.accounts(key) ON UPDATE CASCADE ON DELETE RESTRICT,
  memo                TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_outflow_events_sign CHECK (
       (event_type = 'set_aside'          AND amount_cents > 0)
    OR (event_type = 'paid'               AND amount_cents < 0)
    OR (event_type IN ('opening_adjustment','adjust','reversal') AND amount_cents <> 0)
  ),
  CONSTRAINT chk_outflow_events_memo CHECK (
    event_type NOT IN ('opening_adjustment','adjust','reversal')
    OR (memo IS NOT NULL AND length(btrim(memo)) > 0)
  )
);

COMMENT ON TABLE public.outflow_events IS
  'Phase 5G-1 — append-only ledger. Signed amount_cents: opening_adjustment(+ usually), '
  'set_aside(+), paid(-), adjust(±), reversal(±). set-aside balance = SUM(amount_cents). '
  'No updates/deletes: corrections are new adjust/reversal rows (memo required). '
  'funding_account_key NOT NULL (records the account that moved). No updated_at by design.';

CREATE INDEX idx_outflow_events_plan_date
  ON public.outflow_events(planned_outflow_id, event_date ASC, created_at ASC, id ASC);
CREATE INDEX idx_outflow_events_type ON public.outflow_events(event_type);

-- ── 3. Append-only enforcement (trigger layer; CREATE, not OR REPLACE) ──────
CREATE FUNCTION public.fn_block_outflow_event_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'outflow_events is append-only: % is not permitted. '
    'Record a compensating adjust/reversal event instead.', TG_OP;
END $$;

CREATE TRIGGER block_outflow_events_mutation
  BEFORE UPDATE OR DELETE ON public.outflow_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_block_outflow_event_mutation();

-- ── 4. RLS — every policy scoped TO authenticated (never PUBLIC/anon) ────────
ALTER TABLE public.planned_outflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outflow_events   ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_read" ON public.planned_outflows
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "financial_writer_insert" ON public.planned_outflows
  FOR INSERT TO authenticated WITH CHECK (public.can_write_financials());
CREATE POLICY "financial_writer_update" ON public.planned_outflows
  FOR UPDATE TO authenticated USING (public.can_write_financials()) WITH CHECK (public.can_write_financials());

-- outflow_events: household read; financial-writer INSERT ONLY (append-only).
-- No UPDATE/DELETE policy → RLS default-deny for authenticated; trigger (step 3)
-- additionally blocks any role that bypasses RLS (e.g. service_role).
CREATE POLICY "allow_read" ON public.outflow_events
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "financial_writer_insert" ON public.outflow_events
  FOR INSERT TO authenticated WITH CHECK (public.can_write_financials());

-- ── 5. Grants — NORMALIZE (revoke all) then grant least-privilege ────────────
-- Supabase/Postgres default privileges grant broad table privileges to
-- authenticated and anon on new public tables — including TRUNCATE, which
-- BYPASSES RLS. GRANT is additive and does NOT reset those, so we REVOKE ALL
-- from PUBLIC/anon/authenticated first, then grant exactly the intended subset.
-- service_role is intentionally left untouched (backend/admin; bypasses RLS by design).
-- (Staging rehearsal 2026-07-08 caught authenticated retaining DELETE/UPDATE/TRUNCATE
-- because only anon had been revoked previously.)
REVOKE ALL ON public.planned_outflows FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.outflow_events   FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.planned_outflows TO authenticated;  -- no DELETE
GRANT SELECT, INSERT         ON public.outflow_events   TO authenticated;  -- append-only
GRANT USAGE ON SCHEMA public TO authenticated;  -- idempotent

-- ── 6. Schema-only proof: both tables must be empty (no seed here) ───────────
DO $$
BEGIN
  IF (SELECT count(*) FROM public.planned_outflows) <> 0
     OR (SELECT count(*) FROM public.outflow_events) <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: migration is schema-only; tables must be empty. Aborting.';
  END IF;
END $$;

COMMIT;

-- Post-commit sanity (full checks in phase-5g-1-validation.sql):
SELECT 'M-tables' AS check,
       (SELECT count(*) FROM information_schema.tables
        WHERE table_schema='public' AND table_name IN ('planned_outflows','outflow_events')) AS expected_2;
