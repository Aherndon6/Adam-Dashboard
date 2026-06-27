-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-1 Migration
-- ═══════════════════════════════════════════════════════════════════════════
-- Run ONLY after all phase-5e-preflight.sql checks pass.
-- Do NOT run until index.html changes are reviewed and approved.
-- Safe to run while showTransactionLedger remains default false.
-- Do NOT enable showTransactionLedger in the app until all validations (V1–V10, V3a, V3b) pass.
--
-- Intentionally NOT idempotent. No IF NOT EXISTS guards are used.
-- A partial or repeated run will fail loudly (duplicate table/policy/index errors).
-- This is by design: silent idempotency would mask a broken migration state.
-- If a partial run occurred, investigate and clean up before retrying.
-- ─────────────────────────────────────────────────────────────────────────

-- ── 1. transactions table ─────────────────────────────────────────────────
-- user_id: DEFAULT auth.uid() so inserts from UI populate automatically.
--   Role: creator/audit context only. RLS security boundary is is_allowed_user()
--   / is_owner() (household-level), not per-user. This matches the existing pattern
--   on accounts, categories, and budget_transactions.
-- amount sign convention: positive = inflow (money into account),
--   negative = outflow. CHECK (amount <> 0) prevents zero-dollar rows.
-- is_split, reconciled, transfer_pair_id: reserved for later phases.
--   is_split omitted from 5E-1; will be added as ALTER TABLE when split UI lands.
--   reconciled reserved for Phase 5F. transfer_pair_id reserved for transfer linking.
-- source: 'migration' included now to avoid a schema change on future backfills.
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE public.transactions (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID          NOT NULL DEFAULT auth.uid()
                                   REFERENCES auth.users(id),
  account_key      TEXT          NOT NULL
                                   REFERENCES public.accounts(key)
                                     ON UPDATE CASCADE
                                     ON DELETE RESTRICT,
  transaction_date DATE          NOT NULL,
  posted_date      DATE,
  payee            TEXT,
  memo             TEXT,
  amount           NUMERIC(12,2) NOT NULL,
  category_key     TEXT
                                   REFERENCES public.categories(key)
                                     ON UPDATE CASCADE
                                     ON DELETE SET NULL,
  cleared          BOOLEAN       NOT NULL DEFAULT FALSE,
  reconciled       BOOLEAN       NOT NULL DEFAULT FALSE,
  transfer_pair_id UUID,
  source           TEXT          NOT NULL DEFAULT 'manual',
  notes            TEXT,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_transactions_amount_nonzero
    CHECK (amount <> 0),
  CONSTRAINT chk_transactions_source
    CHECK (source IN ('manual', 'import', 'migration'))
);

COMMENT ON TABLE public.transactions IS
  'Phase 5E-1 — account-first transaction ledger. '
  'user_id is creator/audit context; RLS boundary is is_allowed_user() / is_owner() (household-level). '
  'amount: positive = inflow, negative = outflow. Never zero. '
  'is_split: deferred — will be added as ALTER TABLE when split UI is introduced. '
  'reconciled: reserved for Phase 5F. '
  'transfer_pair_id: reserved for transfer linking (two rows share same UUID).';

COMMENT ON COLUMN public.transactions.user_id IS
  'Creator/audit context. DEFAULT auth.uid() populates on insert. '
  'Not the RLS boundary — security is household-level via is_allowed_user() / is_owner().';

COMMENT ON COLUMN public.transactions.amount IS
  'Signed: positive = inflow (money into account), negative = outflow. '
  'CHECK (amount <> 0) enforced. UI displays two columns: Outflow (abs of negative), Inflow (positive).';

COMMENT ON COLUMN public.transactions.reconciled IS
  'Reserved for Phase 5F reconciliation workflow. Not surfaced in Phase 5E UI.';

COMMENT ON COLUMN public.transactions.transfer_pair_id IS
  'Reserved for transfer linking. Deferred to later phase.';

COMMENT ON COLUMN public.transactions.source IS
  'Origin: manual (UI), import (CSV/OFX), migration (backfill).';

-- ── 2. Indexes ────────────────────────────────────────────────────────────
-- Primary query pattern: account register in deterministic ascending order.
-- Three-level tie-break (date, created_at, id) prevents unstable ordering
-- when multiple transactions share the same date.
CREATE INDEX idx_transactions_account_date
  ON public.transactions(account_key, transaction_date ASC, created_at ASC, id ASC);

CREATE INDEX idx_transactions_user_id
  ON public.transactions(user_id);

-- Sparse: most rows will have null transfer_pair_id.
CREATE INDEX idx_transactions_transfer_pair
  ON public.transactions(transfer_pair_id)
  WHERE transfer_pair_id IS NOT NULL;

-- ── 3. updated_at trigger ─────────────────────────────────────────────────
-- Reuses fn_set_updated_at() created in Phase 5D-1. No new function needed.
CREATE TRIGGER set_transactions_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ── 4. RLS ────────────────────────────────────────────────────────────────
-- 5E-1 posture: database-read-only (least privilege).
-- Only the SELECT policy and SELECT grant are created here.
-- INSERT/UPDATE/DELETE policies and grants are added in 5E-2 when writes are introduced.
-- This ensures the DB enforces the same read-only constraint as the UI.
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

-- SELECT: household-level read (same as accounts/categories)
CREATE POLICY "allow_read" ON public.transactions
  FOR SELECT
  USING (public.is_allowed_user());

-- ── 5. Grants ─────────────────────────────────────────────────────────────
-- 5E-1 least-privilege: SELECT only.
-- authenticated role can read but cannot write until 5E-2 adds write policies and grants.
GRANT SELECT ON public.transactions TO authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;  -- idempotent

-- ── 6. Post-migration validation queries ──────────────────────────────────
-- Run these immediately after the migration to confirm it applied correctly.
-- All checks should return their documented expected value before proceeding.

-- V1: table exists
SELECT 'V1' AS check,
       EXISTS (
         SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = 'transactions'
       ) AS expected_true;

-- V2: RLS enabled on public.transactions specifically
-- Scoped via pg_class + pg_namespace to avoid matching a 'transactions' table
-- in any other schema that may exist.
SELECT 'V2' AS check,
       c.relrowsecurity AS expected_true
  FROM pg_class     c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relname = 'transactions';

-- V3: exactly 1 policy on public.transactions (5E-1 is SELECT-only — no write policies yet)
SELECT 'V3' AS check,
       COUNT(*) AS expected_1
  FROM pg_policies
 WHERE schemaname = 'public'
   AND tablename  = 'transactions';

-- V3a: allow_read policy on public.transactions uses is_allowed_user()
SELECT 'V3a' AS check,
       policyname,
       qual AS using_expression
  FROM pg_policies
 WHERE schemaname = 'public'
   AND tablename  = 'transactions'
   AND policyname = 'allow_read';
-- Expected: policyname = 'allow_read', qual contains 'is_allowed_user'

-- V3b: no write policies on public.transactions in 5E-1 (defensive check)
SELECT 'V3b' AS check,
       COUNT(*) AS expected_0
  FROM pg_policies
 WHERE schemaname = 'public'
   AND tablename  = 'transactions'
   AND policyname IN ('owner_insert','owner_update','owner_delete');

-- V4: updated_at trigger attached to public.transactions specifically
-- Joins through pg_class + pg_namespace to confirm the trigger is on the right table,
-- not just that a trigger with this name exists somewhere in the database.
SELECT 'V4' AS check,
       COUNT(*) AS expected_1
  FROM pg_trigger   t
  JOIN pg_class     c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relname = 'transactions'
   AND t.tgname  = 'set_transactions_updated_at';

-- V5: correct index count on public.transactions (PK + 3 explicit = 4 total)
SELECT 'V5' AS check,
       COUNT(*) AS expected_4
  FROM pg_indexes
 WHERE schemaname = 'public'
   AND tablename  = 'transactions';

-- V6: user_id default is auth.uid()
SELECT 'V6' AS check,
       column_default AS expected_auth_uid
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name   = 'transactions'
   AND column_name  = 'user_id';
-- Expected: 'auth.uid()'

-- V7: account_key FK has ON DELETE RESTRICT
SELECT 'V7' AS check,
       rc.delete_rule AS expected_RESTRICT
  FROM information_schema.referential_constraints rc
  JOIN information_schema.key_column_usage kcu
    ON kcu.constraint_name = rc.constraint_name
 WHERE kcu.table_name = 'transactions'
   AND kcu.column_name = 'account_key';

-- V8: category_key FK has ON DELETE SET NULL
SELECT 'V8' AS check,
       rc.delete_rule AS expected_SET_NULL
  FROM information_schema.referential_constraints rc
  JOIN information_schema.key_column_usage kcu
    ON kcu.constraint_name = rc.constraint_name
 WHERE kcu.table_name = 'transactions'
   AND kcu.column_name = 'category_key';

-- V9: amount nonzero CHECK exists
SELECT 'V9' AS check,
       COUNT(*) AS expected_1
  FROM information_schema.check_constraints
 WHERE constraint_name = 'chk_transactions_amount_nonzero';

-- V10: source enum CHECK exists
SELECT 'V10' AS check,
       COUNT(*) AS expected_1
  FROM information_schema.check_constraints
 WHERE constraint_name = 'chk_transactions_source';
