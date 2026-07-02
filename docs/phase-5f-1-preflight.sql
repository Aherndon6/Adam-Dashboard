-- ═══════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5F-1 Preflight
-- Cash Commitment Capture + Cash Availability Engine
-- Run in Supabase SQL Editor BEFORE applying phase-5f-1-migration.sql.
-- All queries read live schema/catalog only — no DB mutations.
--
-- Output columns: check_id | status | object | details
-- status values: PASS | FAIL | REVIEW
-- ═══════════════════════════════════════════════════════════════════

SET search_path TO public;

-- ── PF1: weekly_reconciliations exists with RLS enabled ─────────────
SELECT
  'PF1' AS check_id,
  CASE
    WHEN pt.tablename IS NULL THEN 'FAIL'
    WHEN NOT pt.rowsecurity THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'weekly_reconciliations' AS object,
  CASE
    WHEN pt.tablename IS NULL THEN 'TABLE MISSING'
    WHEN NOT pt.rowsecurity THEN 'RLS DISABLED'
    ELSE 'table exists, RLS enabled'
  END AS details
FROM (SELECT 1) x
LEFT JOIN pg_tables pt
  ON pt.schemaname = 'public' AND pt.tablename = 'weekly_reconciliations';

-- ── PF2: weekly_reconciliations current column inventory ────────────
-- REVIEW only — confirms current shape before ALTER ADD COLUMN balance_basis.
-- Read this row list before migration. Migration is additive (ADD COLUMN
-- IF NOT EXISTS) so this is informational, not a gate.
SELECT
  'PF2' AS check_id,
  'REVIEW' AS status,
  'weekly_reconciliations' AS object,
  column_name || ' | ' || data_type || ' | nullable=' || is_nullable AS details
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'weekly_reconciliations'
ORDER BY ordinal_position;

-- ── PF3: balance_basis does not already exist on weekly_reconciliations ──
-- PASS = column absent — expected pre-migration state.
-- REVIEW = column already exists — migration's ADD COLUMN IF NOT EXISTS
-- will no-op, so inspect the existing CHECK constraint against the spec's
-- definition by hand before relying on it.
SELECT
  'PF3' AS check_id,
  CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'REVIEW' END AS status,
  'weekly_reconciliations.balance_basis' AS object,
  CASE
    WHEN COUNT(*) = 0 THEN 'column does not exist yet — expected pre-migration state'
    ELSE 'column already exists — confirm existing CHECK constraint matches spec before migration runs (ADD COLUMN IF NOT EXISTS will no-op)'
  END AS details
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'weekly_reconciliations'
  AND column_name = 'balance_basis';

-- ── PF4: week_num has a unique constraint/index on weekly_reconciliations ──
-- App code POSTs with Prefer: resolution=merge-duplicates keyed on week_num
-- (index.html ~line 2015) — this requires a unique constraint/index to
-- function as an upsert target. Confirm it actually exists at the DB level.
SELECT
  'PF4' AS check_id,
  CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS status,
  'weekly_reconciliations.week_num' AS object,
  CASE
    WHEN COUNT(*) > 0 THEN 'unique constraint/index found: ' || string_agg(indexname, ', ')
    ELSE 'NO UNIQUE CONSTRAINT/INDEX on week_num — merge-duplicates upsert in app code has no valid conflict target'
  END AS details
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'weekly_reconciliations'
  AND indexdef ILIKE '%week_num%'
  AND (indexdef ILIKE '%UNIQUE%');

-- ── PF5: cash_commitments does not already exist ─────────────────────
SELECT
  'PF5' AS check_id,
  CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
  'cash_commitments' AS object,
  CASE
    WHEN COUNT(*) = 0 THEN 'table does not exist — clear to CREATE'
    ELSE 'TABLE ALREADY EXISTS — do not run CREATE TABLE unqualified; inspect before proceeding'
  END AS details
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'cash_commitments';

-- ── PF6: required helper functions exist (is_allowed_user, can_write_financials) ──
-- Both RPCs and the RLS SELECT policy in the 5F-1 migration depend on these.
SELECT
  'PF6' AS check_id,
  CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END AS status,
  'public functions' AS object,
  'Expected 2: is_allowed_user, can_write_financials — found ' || COUNT(*)::text
    || ' (' || COALESCE(string_agg(routine_name, ', '), 'none') || ')' AS details
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('is_allowed_user', 'can_write_financials');

-- ── PF7: 5F-1 functions do not already exist ─────────────────────────
-- validate_commitment_state, save_reconciliation_with_commitments,
-- repair_commitments_for_week — none should be present pre-migration.
SELECT
  'PF7' AS check_id,
  CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
  'public functions (5F-1 new)' AS object,
  CASE
    WHEN COUNT(*) = 0 THEN 'none of the 3 target functions exist yet — clear to CREATE'
    ELSE 'ALREADY EXISTS: ' || string_agg(routine_name, ', ') || ' — do not blind CREATE OR REPLACE without reviewing existing definition'
  END AS details
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'validate_commitment_state',
    'save_reconciliation_with_commitments',
    'repair_commitments_for_week'
  );

-- ── PF8: auth.users has no orphan risk for created_by/resolved_by FKs ──
-- cash_commitments.created_by defaults to auth.uid() NOT NULL REFERENCES
-- auth.users(id). Confirm both app identities resolve to real auth.users rows
-- before the FK becomes load-bearing.
SELECT
  'PF8' AS check_id,
  CASE WHEN au.id IS NULL THEN 'FAIL' ELSE 'PASS' END AS status,
  'auth.users: ' || e.email AS object,
  CASE WHEN au.id IS NULL THEN 'NOT FOUND in auth.users' ELSE 'id=' || au.id::text END AS details
FROM (
  VALUES ('adam@herndons.us'), ('wherndon22@gmail.com')
) AS e(email)
LEFT JOIN auth.users au ON au.email = e.email
ORDER BY e.email;

-- ── PF9: gen_random_uuid() is available (pgcrypto/pgcrypto-equivalent) ──
-- cash_commitments.id default depends on it.
SELECT
  'PF9' AS check_id,
  CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS status,
  'gen_random_uuid()' AS object,
  CASE WHEN COUNT(*) > 0 THEN 'function available' ELSE 'NOT AVAILABLE — enable pgcrypto extension before migration' END AS details
FROM pg_proc
WHERE proname = 'gen_random_uuid';

-- ── PF10: current regression baseline sanity (informational only) ───
-- Not a DB check — reminder that AC-76 requires re-running
-- grep -c '^test(' test_regression.js immediately before build and using
-- that live output as the baseline, not any number stated in the spec.
SELECT
  'PF10' AS check_id,
  'REVIEW' AS status,
  'test_regression.js' AS object,
  'DB preflight cannot check this — re-run grep -c ''^test('' test_regression.js immediately before build and use its output as the baseline per AC-76' AS details;
