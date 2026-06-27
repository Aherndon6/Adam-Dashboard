-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 5D-1 Pre-Migration Preflight — Herndon Financial OS
-- Run ALL queries below BEFORE executing phase-5d-1-migration.sql.
-- Save the output of each query. Do not proceed if any check fails.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- P1: Diablos / GLP baseline check
-- Purpose: Confirm these rows do not already exist in budget_line_rules.
--   The migration uses WHERE NOT EXISTS, so if either row already exists the
--   migration will skip the insert — but the rollback would still delete it.
--   That would corrupt pre-existing data.
--
-- EXPECTED RESULT: 0 rows
-- If any rows are returned: STOP. Do not run the migration.
--   Adjust phase-5d-1-migration.sql and phase-5d-1-rollback.sql so the rollback
--   targets only the specific rows Phase 5D-1 actually inserts, not pre-existing ones.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT category_key, amount, start_month, end_month, is_active
FROM budget_line_rules
WHERE category_key IN (
  'health_fitness.diablos_preston_fee',
  'health_fitness.wendy_glp_meds'
)
ORDER BY category_key, start_month;

-- Save result: _____ rows (expected 0)

-- ─────────────────────────────────────────────────────────────────────────────
-- P2: fn_set_updated_at() prior definition capture
-- Purpose: The migration uses CREATE OR REPLACE, which silently overwrites any
--   existing function body. Save the current definition so it can be restored
--   if rollback is needed and the original was different.
--
-- EXPECTED RESULTS:
--   A) Function does not exist → query returns error "does not exist" → fine.
--      Document: fn_set_updated_at() did not exist pre-5D-1. Rollback may DROP it.
--   B) Function exists → save the full pg_get_functiondef() output.
--      If the body is identical to the Phase 5D-1 version (sets NEW.updated_at = now()),
--      no restoration is needed on rollback — dropping it is safe if no other triggers use it.
--      If the body is different → document the difference. Rollback must restore the original.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
  CASE
    WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_set_updated_at'
                                         AND pg_function_is_visible(oid))
    THEN pg_get_functiondef('fn_set_updated_at()'::regprocedure)::text
    ELSE '-- fn_set_updated_at does not exist pre-5D-1'
  END AS fn_definition;

-- Save result: [ ] did not exist   [ ] existed — body saved below
-- Prior body (paste if existed):
-- ___________________________________________________________________________

-- ─────────────────────────────────────────────────────────────────────────────
-- P3: fn_set_updated_at() trigger usage check
-- Purpose: Even if fn_set_updated_at() exists, confirm what triggers currently
--   use it. This determines whether rollback can drop the function safely.
--
-- EXPECTED RESULT (pre-migration): 0 rows OR rows for non-5D-1 triggers.
--   If 0 rows: function is unused or absent; rollback can DROP FUNCTION.
--   If rows exist: document which tables/triggers use it. Rollback must NOT drop
--   the function if any non-5D-1 trigger depends on it.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT tgname AS trigger_name, c.relname AS table_name
FROM pg_trigger t
JOIN pg_class  c ON c.oid = t.tgrelid
JOIN pg_proc   p ON p.oid = t.tgfoid
WHERE p.proname = 'fn_set_updated_at';

-- Save result: _____ rows
-- Trigger(s) found (if any): ________________________________________________

-- ─────────────────────────────────────────────────────────────────────────────
-- P4: RLS prerequisite check
-- Purpose: The migration creates RLS policies that call is_allowed_user() and
--   is_owner(). Confirm these functions exist before running.
--   Note: get_my_role() does not exist in this project. The correct write-guard
--   function is is_owner(), matching the pattern on all existing tables
--   (budget_line_rules, budget_transactions, etc.). Migration updated accordingly.
--
-- EXPECTED RESULT: 2 rows (both functions present)
-- If fewer than 2: STOP. Required RLS helper is missing.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT proname FROM pg_proc
WHERE proname IN ('is_allowed_user','is_owner')
ORDER BY proname;

-- Save result: _____ rows (expected 2: is_allowed_user, is_owner)

-- ─────────────────────────────────────────────────────────────────────────────
-- P5: accounts / categories tables absent check
-- Purpose: Confirm neither table exists before migration (would indicate a prior
--   partial run). If either table exists, investigate before proceeding.
--
-- EXPECTED RESULT: 0 rows
-- ─────────────────────────────────────────────────────────────────────────────

SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN ('accounts','categories');

-- Save result: _____ rows (expected 0)

-- ─────────────────────────────────────────────────────────────────────────────
-- Preflight sign-off checklist (fill in before running migration)
-- ─────────────────────────────────────────────────────────────────────────────
--
--  [ ] P1: Diablos/GLP rows = 0. Safe to proceed.
--  [ ] P2: fn_set_updated_at() prior body saved (or confirmed absent).
--  [ ] P3: fn_set_updated_at() trigger usage documented.
--  [ ] P4: is_allowed_user() and get_my_role() both present.
--  [ ] P5: accounts and categories tables absent.
--  [ ] All checks passed. Ready to run phase-5d-1-migration.sql.
