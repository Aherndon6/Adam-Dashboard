-- =============================================================================
-- Phase 5B — Budget Module: Schema Migration
-- Tables: budget_line_rules, budget_transactions
-- Run in Supabase SQL Editor (project: usayoldrawwmjsmretin)
-- Date: June 24, 2026
-- SAFE TO RERUN: all CREATE TRIGGER / CREATE POLICY statements are preceded
-- by DROP IF EXISTS so the migration is idempotent.
-- =============================================================================

-- =============================================================================
-- SECTION 1: CREATE TABLES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table: budget_line_rules
-- Recurring, effective-dated monthly budget amounts.
-- Adam (owner) controls all writes. Wendy (household_admin) can read.
-- start_month / end_month stored as first day of month (e.g. 2026-07-01).
-- A rule is active for a selected month if:
--   start_month <= selected_month_start
--   AND (end_month IS NULL OR end_month >= selected_month_start)
-- No two active rules may share the same category_key for the same month.
-- created_by / updated_by:
--   App (browser) writes: trigger uses auth.uid() — client cannot spoof.
--   Seed script (SQL Editor): auth.uid() is null; trigger falls back to the
--   caller-supplied value via COALESCE. Seed script MUST supply a valid UUID.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS budget_line_rules (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_key  text NOT NULL,
  line_label    text NOT NULL,
  amount        numeric NOT NULL,
  start_month   date NOT NULL,
  end_month     date,
  is_active     boolean NOT NULL DEFAULT true,
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid NOT NULL REFERENCES auth.users(id),
  updated_by    uuid REFERENCES auth.users(id),

  CONSTRAINT budget_line_rules_amount_positive CHECK (amount > 0),
  CONSTRAINT budget_line_rules_start_first_of_month
    CHECK (EXTRACT(DAY FROM start_month) = 1),
  CONSTRAINT budget_line_rules_end_first_of_month
    CHECK (end_month IS NULL OR EXTRACT(DAY FROM end_month) = 1),
  CONSTRAINT budget_line_rules_end_after_start
    CHECK (end_month IS NULL OR end_month >= start_month)
);

-- Trigger functions — use COALESCE so app writes use auth.uid() (spoof-proof)
-- while seed scripts can supply their own UUID when auth.uid() is null.

DROP TRIGGER IF EXISTS budget_line_rules_created ON budget_line_rules;
DROP TRIGGER IF EXISTS budget_line_rules_updated ON budget_line_rules;

CREATE OR REPLACE FUNCTION budget_line_rules_set_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth AS $$
BEGIN
  -- App write: auth.uid() is set → use it (client cannot override).
  -- Seed script: auth.uid() is null → fall back to caller-supplied value.
  -- If both are null, the NOT NULL constraint will reject the row.
  NEW.created_by := COALESCE(auth.uid(), NEW.created_by);
  NEW.updated_by := COALESCE(auth.uid(), NEW.created_by);
  RETURN NEW;
END;
$$;

CREATE TRIGGER budget_line_rules_created
  BEFORE INSERT ON budget_line_rules
  FOR EACH ROW EXECUTE FUNCTION budget_line_rules_set_created();

CREATE OR REPLACE FUNCTION budget_line_rules_set_updated()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth AS $$
BEGIN
  NEW.updated_at := now();
  -- App writes: auth.uid() is set; seed scripts do not UPDATE, only INSERT.
  NEW.updated_by := COALESCE(auth.uid(), OLD.updated_by);
  -- Lock created_by — can never be changed after insert.
  NEW.created_by := OLD.created_by;
  RETURN NEW;
END;
$$;

CREATE TRIGGER budget_line_rules_updated
  BEFORE UPDATE ON budget_line_rules
  FOR EACH ROW EXECUTE FUNCTION budget_line_rules_set_updated();


-- -----------------------------------------------------------------------------
-- Table: budget_transactions
-- Actual household transactions entered by Wendy or Adam.
-- transaction_type drives inflow/outflow behavior (no direction field):
--   household_expense    = normal spending against budget categories
--   reimbursable_expense = charge to Jabian or Other; excluded from budget
--   reimbursement_income = deposit received for a prior reimbursable_expense
-- Constraint rules:
--   household_expense    → category_key NOT NULL, excluded_from_budget = false
--   reimbursable_expense → excluded_from_budget = true
--   reimbursement_income → excluded_from_budget = true, category_key = null
-- is_cleared / cleared_date: Wendy marks transactions as cleared vs
--   her card/account statement balance as part of her weekly reconciliation.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS budget_transactions (
  id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_date             date NOT NULL,
  amount                       numeric NOT NULL,
  transaction_type             text NOT NULL,
  category_key                 text,
  description                  text,
  payment_account              text,
  excluded_from_budget         boolean NOT NULL DEFAULT false,
  is_cleared                   boolean NOT NULL DEFAULT false,
  cleared_date                 date,
  reimbursement_source         text,
  reimbursement_status         text,
  expected_reimbursement_month date,
  reimbursed_date              date,
  notes                        text,
  created_at                   timestamptz NOT NULL DEFAULT now(),
  updated_at                   timestamptz NOT NULL DEFAULT now(),
  created_by                   uuid NOT NULL REFERENCES auth.users(id),
  updated_by                   uuid REFERENCES auth.users(id),

  CONSTRAINT budget_transactions_amount_positive
    CHECK (amount > 0),

  CONSTRAINT budget_transactions_type_valid
    CHECK (transaction_type IN (
      'household_expense',
      'reimbursable_expense',
      'reimbursement_income'
    )),

  CONSTRAINT budget_transactions_reimbursement_status_valid
    CHECK (reimbursement_status IS NULL OR reimbursement_status IN (
      'pending', 'submitted', 'reimbursed'
    )),

  CONSTRAINT budget_transactions_reimbursement_source_valid
    CHECK (reimbursement_source IS NULL OR reimbursement_source IN (
      'Jabian', 'Other'
    )),

  CONSTRAINT budget_transactions_type_rules
    CHECK (
      (
        transaction_type = 'household_expense'
        AND category_key IS NOT NULL
        AND excluded_from_budget = false
      )
      OR (
        transaction_type = 'reimbursable_expense'
        AND excluded_from_budget = true
        AND reimbursement_source IS NOT NULL
        AND reimbursement_status IS NOT NULL
      )
      OR (
        transaction_type = 'reimbursement_income'
        AND excluded_from_budget = true
        AND category_key IS NULL
      )
    ),

  CONSTRAINT budget_transactions_expected_reimb_first_of_month
    CHECK (
      expected_reimbursement_month IS NULL
      OR EXTRACT(DAY FROM expected_reimbursement_month) = 1
    ),

  -- cleared_date must be NULL when is_cleared = false.
  -- (A cleared_date set on an uncleared transaction would be silent dirty data.)
  CONSTRAINT budget_transactions_cleared_date_consistency
    CHECK (is_cleared = true OR cleared_date IS NULL)
);

DROP TRIGGER IF EXISTS budget_transactions_created ON budget_transactions;
DROP TRIGGER IF EXISTS budget_transactions_updated ON budget_transactions;

CREATE OR REPLACE FUNCTION budget_transactions_set_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth AS $$
BEGIN
  NEW.created_by := COALESCE(auth.uid(), NEW.created_by);
  NEW.updated_by := COALESCE(auth.uid(), NEW.created_by);
  RETURN NEW;
END;
$$;

CREATE TRIGGER budget_transactions_created
  BEFORE INSERT ON budget_transactions
  FOR EACH ROW EXECUTE FUNCTION budget_transactions_set_created();

CREATE OR REPLACE FUNCTION budget_transactions_set_updated()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth AS $$
BEGIN
  NEW.updated_at := now();
  NEW.updated_by := COALESCE(auth.uid(), OLD.updated_by);
  NEW.created_by := OLD.created_by;
  RETURN NEW;
END;
$$;

CREATE TRIGGER budget_transactions_updated
  BEFORE UPDATE ON budget_transactions
  FOR EACH ROW EXECUTE FUNCTION budget_transactions_set_updated();


-- =============================================================================
-- SECTION 2: ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE budget_line_rules    ENABLE ROW LEVEL SECURITY;
ALTER TABLE budget_transactions  ENABLE ROW LEVEL SECURITY;

-- RLS helpers used here (all defined in docs/phase-5a-role-enforcement.sql):
--   is_allowed_user()      → user exists in app_users with active=true
--   can_write_financials() → role IN ('owner','household_admin') AND is_allowed_user()
--   is_owner()             → role = 'owner' AND is_allowed_user()
--
-- Scope: only Adam (owner) and Wendy (household_admin) are in app_users.
-- No other authenticated Supabase user can access budget data.

-- budget_line_rules: allowed users read; owner writes only
DROP POLICY IF EXISTS "budget_line_rules_select" ON budget_line_rules;
DROP POLICY IF EXISTS "budget_line_rules_insert" ON budget_line_rules;
DROP POLICY IF EXISTS "budget_line_rules_update" ON budget_line_rules;
DROP POLICY IF EXISTS "budget_line_rules_delete" ON budget_line_rules;

CREATE POLICY "budget_line_rules_select"
  ON budget_line_rules FOR SELECT
  TO authenticated
  USING (is_allowed_user());

CREATE POLICY "budget_line_rules_insert"
  ON budget_line_rules FOR INSERT
  TO authenticated
  WITH CHECK (is_owner());

CREATE POLICY "budget_line_rules_update"
  ON budget_line_rules FOR UPDATE
  TO authenticated
  USING (is_owner())
  WITH CHECK (is_owner());

CREATE POLICY "budget_line_rules_delete"
  ON budget_line_rules FOR DELETE
  TO authenticated
  USING (is_owner());

-- budget_transactions: allowed users read; owner or household_admin write
-- (both Adam and Wendy can add/edit/delete transactions)
DROP POLICY IF EXISTS "budget_transactions_select" ON budget_transactions;
DROP POLICY IF EXISTS "budget_transactions_insert" ON budget_transactions;
DROP POLICY IF EXISTS "budget_transactions_update" ON budget_transactions;
DROP POLICY IF EXISTS "budget_transactions_delete" ON budget_transactions;

CREATE POLICY "budget_transactions_select"
  ON budget_transactions FOR SELECT
  TO authenticated
  USING (is_allowed_user());

CREATE POLICY "budget_transactions_insert"
  ON budget_transactions FOR INSERT
  TO authenticated
  WITH CHECK (can_write_financials());

CREATE POLICY "budget_transactions_update"
  ON budget_transactions FOR UPDATE
  TO authenticated
  USING (can_write_financials())
  WITH CHECK (can_write_financials());

CREATE POLICY "budget_transactions_delete"
  ON budget_transactions FOR DELETE
  TO authenticated
  USING (can_write_financials());


-- =============================================================================
-- SECTION 3: INDEXES
-- =============================================================================

-- Line rules: fast lookup by month and category
CREATE INDEX IF NOT EXISTS idx_budget_line_rules_category_key
  ON budget_line_rules (category_key);

CREATE INDEX IF NOT EXISTS idx_budget_line_rules_month_range
  ON budget_line_rules (start_month, end_month);

-- Transactions: fast lookup by month and category
CREATE INDEX IF NOT EXISTS idx_budget_transactions_date
  ON budget_transactions (transaction_date);

CREATE INDEX IF NOT EXISTS idx_budget_transactions_category_key
  ON budget_transactions (category_key);

CREATE INDEX IF NOT EXISTS idx_budget_transactions_type
  ON budget_transactions (transaction_type);


-- =============================================================================
-- ROLLBACK SQL — uncomment and run to undo everything above
-- =============================================================================

-- DROP TRIGGER IF EXISTS budget_line_rules_updated ON budget_line_rules;
-- DROP TRIGGER IF EXISTS budget_line_rules_created ON budget_line_rules;
-- DROP TRIGGER IF EXISTS budget_transactions_updated ON budget_transactions;
-- DROP TRIGGER IF EXISTS budget_transactions_created ON budget_transactions;
-- DROP FUNCTION IF EXISTS budget_line_rules_set_updated();
-- DROP FUNCTION IF EXISTS budget_line_rules_set_created();
-- DROP FUNCTION IF EXISTS budget_transactions_set_updated();
-- DROP FUNCTION IF EXISTS budget_transactions_set_created();
-- DROP TABLE IF EXISTS budget_transactions;
-- DROP TABLE IF EXISTS budget_line_rules;
