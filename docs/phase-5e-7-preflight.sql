-- ═══════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-7 Preflight
-- Role Enforcement / Security Maturity Gate
-- Run in Supabase SQL Editor BEFORE applying any code or DB changes.
-- All queries read live pg_policies — no DB mutations.
--
-- Output columns: check_id | status | object | details
-- status values: PASS | FAIL | REVIEW
-- ═══════════════════════════════════════════════════════════════════

-- ── P1: Helper functions exist ───────────────────────────────────────
SELECT
  'P1' AS check_id,
  CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END AS status,
  'public functions' AS object,
  'Expected 3: is_allowed_user, can_write_financials, is_owner — found ' || COUNT(*)::text AS details
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('is_allowed_user', 'can_write_financials', 'is_owner');

-- ── P2: app_users roles set correctly AND rows active ───────────────
-- FAIL if row is missing, inactive, or has wrong role.
SELECT
  'P2' AS check_id,
  CASE
    WHEN u.email IS NULL THEN 'FAIL'
    WHEN u.active IS NOT TRUE THEN 'FAIL'
    WHEN u.role != e.expected_role THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'app_users: ' || e.email AS object,
  CASE
    WHEN u.email IS NULL THEN 'ROW MISSING — user not in app_users table'
    WHEN u.active IS NOT TRUE THEN 'INACTIVE — active=' || u.active::text || ' role=' || COALESCE(u.role,'NULL')
    ELSE 'role=' || COALESCE(u.role,'NULL') || ' active=' || u.active::text
  END AS details
FROM (
  VALUES
    ('adam@herndons.us',      'owner'),
    ('wherndon22@gmail.com',  'household_admin')
) AS e(email, expected_role)
LEFT JOIN public.app_users u ON u.email = e.email
ORDER BY e.email;

-- ── P3: All expected app tables exist AND have RLS enabled ──────────
-- FAIL rows appear for each missing table AND each table with RLS disabled.
SELECT
  'P3' AS check_id,
  CASE
    WHEN pt.tablename IS NULL THEN 'FAIL'
    WHEN NOT pt.rowsecurity THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  e.tbl AS object,
  CASE
    WHEN pt.tablename IS NULL THEN 'TABLE MISSING — not found in pg_tables'
    WHEN NOT pt.rowsecurity THEN 'RLS DISABLED — writes unprotected'
    ELSE 'RLS enabled'
  END AS details
FROM (
  VALUES
    ('transactions'),('budget_transactions'),('budget_line_rules'),
    ('accounts'),('categories'),('weekly_reconciliations'),
    ('weekly_tasks'),('weekly_notes'),('model_week_overrides'),
    ('goals'),('wishlist_items'),('custom_tasks'),
    ('budget_rules'),('goal_registry'),('app_users')
) AS e(tbl)
LEFT JOIN pg_tables pt
  ON pt.schemaname = 'public' AND pt.tablename = e.tbl
ORDER BY e.tbl;

-- ── P4: Full live policy listing for all app tables ─────────────────
-- Read this carefully before proceeding. Every row is a live policy.
SELECT
  'P4' AS check_id,
  'REVIEW' AS status,
  tablename AS object,
  policyname || ' | cmd=' || cmd
    || ' | roles=' || array_to_string(roles,',')
    || ' | qual=' || COALESCE(qual,'(none)')
    || ' | with_check=' || COALESCE(with_check,'(none)') AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'transactions','budget_transactions','budget_line_rules',
    'accounts','categories','weekly_reconciliations',
    'weekly_tasks','weekly_notes','model_week_overrides',
    'goals','wishlist_items','custom_tasks',
    'budget_rules','goal_registry','app_users'
  )
ORDER BY tablename, cmd, policyname;

-- ── P5: Flag any non-SELECT policy using is_allowed_user() ──────────
-- is_allowed_user() in write policies is a role-enforcement violation.
-- cmd='ALL' is treated as write-capable.
SELECT
  'P5' AS check_id,
  'FAIL' AS status,
  tablename AS object,
  policyname || ' | cmd=' || cmd
    || ' | qual=' || COALESCE(qual,'(none)')
    || ' | with_check=' || COALESCE(with_check,'(none)')
    || ' — WRITE POLICY USES is_allowed_user()' AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
  AND (qual ILIKE '%is_allowed_user%' OR with_check ILIKE '%is_allowed_user%')
  AND tablename IN (
    'transactions','budget_transactions','budget_line_rules',
    'accounts','categories','weekly_reconciliations',
    'weekly_tasks','weekly_notes','model_week_overrides',
    'goals','wishlist_items','custom_tasks',
    'budget_rules','goal_registry','app_users'
  )
UNION ALL
SELECT
  'P5' AS check_id,
  'PASS' AS status,
  'all write policies' AS object,
  'No write policies use is_allowed_user()' AS details
WHERE NOT EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public'
    AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
    AND (qual ILIKE '%is_allowed_user%' OR with_check ILIKE '%is_allowed_user%')
    AND tablename IN (
      'transactions','budget_transactions','budget_line_rules',
      'accounts','categories','weekly_reconciliations',
      'weekly_tasks','weekly_notes','model_week_overrides',
      'goals','wishlist_items','custom_tasks',
      'budget_rules','goal_registry','app_users'
    )
);

-- ── P6: Classify each write policy ──────────────────────────────────
SELECT
  'P6' AS check_id,
  CASE
    WHEN qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%'
      THEN 'REVIEW'
    WHEN qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%'
      THEN 'REVIEW'
    WHEN qual ILIKE '%is_allowed_user%' OR with_check ILIKE '%is_allowed_user%'
      THEN 'FAIL'
    ELSE 'REVIEW'
  END AS status,
  tablename AS object,
  policyname || ' | cmd=' || cmd || ' | predicate='
    || CASE
         WHEN qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%'
           THEN 'can_write_financials()'
         WHEN qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%'
           THEN 'is_owner()'
         WHEN qual ILIKE '%is_allowed_user%' OR with_check ILIKE '%is_allowed_user%'
           THEN 'is_allowed_user() [VIOLATION]'
         ELSE 'other — inspect manually'
       END AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
  AND tablename IN (
    'transactions','budget_transactions','budget_line_rules',
    'accounts','categories','weekly_reconciliations',
    'weekly_tasks','weekly_notes','model_week_overrides',
    'goals','wishlist_items','custom_tasks'
  )
ORDER BY tablename, cmd, policyname;

-- ── P7: Missing DELETE policies (tables expected to support DELETE) ──
-- App write paths call DELETE on: weekly_reconciliations, model_week_overrides,
-- wishlist_items, custom_tasks, budget_transactions, transactions.
-- Report any of those tables lacking a DELETE policy.
SELECT
  'P7' AS check_id,
  'FAIL' AS status,
  t.tbl AS object,
  'No DELETE policy found — app DELETE calls will be rejected by RLS' AS details
FROM (
  VALUES
    ('weekly_reconciliations'),
    ('model_week_overrides'),
    ('wishlist_items'),
    ('custom_tasks'),
    ('budget_transactions'),
    ('transactions')
) AS t(tbl)
WHERE NOT EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = t.tbl
    AND cmd IN ('DELETE','ALL')
)
UNION ALL
SELECT
  'P7' AS check_id,
  'PASS' AS status,
  tablename AS object,
  'DELETE policy exists: ' || policyname AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND cmd IN ('DELETE','ALL')
  AND tablename IN (
    'weekly_reconciliations','model_week_overrides',
    'wishlist_items','custom_tasks','budget_transactions','transactions'
  )
ORDER BY object;

-- ── P8: budget_line_rules write policy check (STOP CONDITION) ───────
-- Product decision: BLR writes are household operational (canWriteFinancials).
-- Migration docs show is_owner(). If live DB shows is_owner(), that blocks Wendy.
-- A FAIL here means Wendy cannot add/edit/archive budget lines — stop and resolve
-- before proceeding with 5E-7 app-side changes.
SELECT
  'P8' AS check_id,
  CASE
    WHEN qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%'
      THEN 'FAIL'   -- owner-only conflicts with Wendy-ready
    WHEN qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%'
      THEN 'PASS'   -- matches product decision
    ELSE 'REVIEW'
  END AS status,
  'budget_line_rules' AS object,
  policyname || ' | cmd=' || cmd
    || ' | qual=' || COALESCE(qual,'(none)')
    || ' | with_check=' || COALESCE(with_check,'(none)')
    || CASE
         WHEN qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%'
           THEN ' — MISMATCH: is_owner() blocks Wendy (household_admin). App guards use canWriteFinancials(). SQL migration required before 5E-8.'
         ELSE ''
       END AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'budget_line_rules'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
UNION ALL
SELECT
  'P8' AS check_id,
  'FAIL' AS status,
  'budget_line_rules' AS object,
  'ZERO write policies found — all writes to budget_line_rules will be rejected by RLS. STOP CONDITION.' AS details
WHERE NOT EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'budget_line_rules'
    AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
)
ORDER BY status, details;
