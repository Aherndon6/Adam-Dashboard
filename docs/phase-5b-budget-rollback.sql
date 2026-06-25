-- =============================================================================
-- Phase 5B — Budget Module: ROLLBACK
-- Run in Supabase SQL Editor to undo phase-5b-budget-schema.sql and
-- phase-5b-seed.sql completely.
-- WARNING: This permanently deletes all budget_transactions and
-- budget_line_rules data. Do not run unless you intend a full teardown.
-- =============================================================================

-- Step 1: Drop triggers (must precede table drops)
DROP TRIGGER IF EXISTS budget_line_rules_updated   ON budget_line_rules;
DROP TRIGGER IF EXISTS budget_line_rules_created   ON budget_line_rules;
DROP TRIGGER IF EXISTS budget_transactions_updated ON budget_transactions;
DROP TRIGGER IF EXISTS budget_transactions_created ON budget_transactions;

-- Step 2: Drop trigger functions
DROP FUNCTION IF EXISTS budget_line_rules_set_updated();
DROP FUNCTION IF EXISTS budget_line_rules_set_created();
DROP FUNCTION IF EXISTS budget_transactions_set_updated();
DROP FUNCTION IF EXISTS budget_transactions_set_created();

-- Step 3: Drop tables (CASCADE removes RLS policies and indexes automatically)
DROP TABLE IF EXISTS budget_transactions;
DROP TABLE IF EXISTS budget_line_rules;

-- Verification: confirm tables are gone
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN ('budget_line_rules','budget_transactions');
-- Expected: 0 rows
