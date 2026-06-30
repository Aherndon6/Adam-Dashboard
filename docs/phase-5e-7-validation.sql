-- ═══════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-7 Validation
-- Role Enforcement / Security Maturity Gate
-- Run AFTER applying 5E-7 code changes. Confirms policy matrix.
-- All queries read live pg_policies — no DB mutations.
--
-- Output columns: check_id | status | object | details
-- status values: PASS | FAIL | REVIEW
-- ═══════════════════════════════════════════════════════════════════

-- ── V1: transactions — write policies use can_write_financials() + source='manual' ──
SELECT
  'V1' AS check_id,
  CASE
    WHEN COUNT(*) >= 3
      AND bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      AND bool_and(qual ILIKE '%manual%' OR with_check ILIKE '%manual%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'transactions (write policies)' AS object,
  'Write policies found: ' || COUNT(*)::text
    || ' | All use can_write_financials: '
    || bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text
    || ' | All restrict manual source: '
    || bool_and(qual ILIKE '%manual%' OR with_check ILIKE '%manual%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'transactions'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- V1a: per-command breakdown for transactions
SELECT
  'V1a' AS check_id,
  CASE
    WHEN (qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      AND (qual ILIKE '%manual%' OR with_check ILIKE '%manual%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'transactions | ' || cmd AS object,
  policyname
    || ' | qual=' || COALESCE(qual,'(none)')
    || ' | with_check=' || COALESCE(with_check,'(none)') AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'transactions'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
ORDER BY cmd;

-- ── V2: budget_transactions — separate legacy table ──────────────────
SELECT
  'V2' AS check_id,
  CASE
    WHEN COUNT(*) >= 3
      AND bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'budget_transactions (write policies)' AS object,
  'Write policies found: ' || COUNT(*)::text
    || ' | All use can_write_financials: '
    || bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'budget_transactions'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V3: accounts — owner-only writes ────────────────────────────────
SELECT
  'V3' AS check_id,
  CASE
    WHEN COUNT(*) >= 3
      AND bool_and(qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%')
      AND NOT bool_or(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'accounts (write policies)' AS object,
  'Write policies: ' || COUNT(*)::text
    || ' | All is_owner(): '
    || bool_and(qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%')::text
    || ' | Any canWriteFinancials (unexpected): '
    || bool_or(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'accounts'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V4: categories — owner-only writes ──────────────────────────────
SELECT
  'V4' AS check_id,
  CASE
    WHEN COUNT(*) >= 3
      AND bool_and(qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%')
      AND NOT bool_or(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'categories (write policies)' AS object,
  'Write policies: ' || COUNT(*)::text
    || ' | All is_owner(): '
    || bool_and(qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'categories'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V5: goals — row-qualified split ─────────────────────────────────
-- financial policy: can_write_financials() AND key <> 'anthropic_key'  (explicit negative condition)
-- owner policy:     is_owner() — covers ALL rows including anthropic_key
SELECT
  'V5a' AS check_id,
  CASE
    -- Must find a policy using can_write_financials() that also has an explicit
    -- negative condition (<> or !=) for anthropic_key, not just any mention of it.
    WHEN SUM(CASE
      WHEN (qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
        AND (
          qual ~* $sql$<>\s*'anthropic_key'$sql$ OR qual ~* $sql$!=\s*'anthropic_key'$sql$
          OR with_check ~* $sql$<>\s*'anthropic_key'$sql$ OR with_check ~* $sql$!=\s*'anthropic_key'$sql$
        )
      THEN 1 ELSE 0 END) >= 1
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'goals — financial write policy (anthropic_key excluded with <> or !=)' AS object,
  'Requires a can_write_financials() policy with explicit <> or != anthropic_key negative condition'
    || ' | Write policies found: ' || COUNT(*)::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'goals'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

SELECT
  'V5b' AS check_id,
  CASE
    WHEN SUM(CASE WHEN (qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%') THEN 1 ELSE 0 END) >= 1
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'goals — owner write policy (covers anthropic_key)' AS object,
  'Policy using is_owner() must exist to protect anthropic_key writes' AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'goals'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V6: weekly_reconciliations — can_write_financials() ─────────────
SELECT
  'V6' AS check_id,
  CASE
    WHEN COUNT(*) >= 2
      AND bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'weekly_reconciliations (write policies)' AS object,
  'Write policies: ' || COUNT(*)::text
    || ' | All can_write_financials: '
    || bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'weekly_reconciliations'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V7: weekly_tasks — can_write_financials() ───────────────────────
SELECT
  'V7' AS check_id,
  CASE
    WHEN COUNT(*) >= 2
      AND bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'weekly_tasks (write policies)' AS object,
  'Write policies: ' || COUNT(*)::text
    || ' | All can_write_financials: '
    || bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'weekly_tasks'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V8: weekly_notes — can_write_financials() ───────────────────────
SELECT
  'V8' AS check_id,
  CASE
    WHEN COUNT(*) >= 2
      AND bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'weekly_notes (write policies)' AS object,
  'Write policies: ' || COUNT(*)::text
    || ' | All can_write_financials: '
    || bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'weekly_notes'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V9: model_week_overrides — can_write_financials() ───────────────
SELECT
  'V9' AS check_id,
  CASE
    WHEN COUNT(*) >= 3
      AND bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'model_week_overrides (write policies)' AS object,
  'Write policies: ' || COUNT(*)::text
    || ' | All can_write_financials: '
    || bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'model_week_overrides'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V10: wishlist_items — can_write_financials() ────────────────────
SELECT
  'V10' AS check_id,
  CASE
    WHEN COUNT(*) >= 3
      AND bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'wishlist_items (write policies)' AS object,
  'Write policies: ' || COUNT(*)::text
    || ' | All can_write_financials: '
    || bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'wishlist_items'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V11: custom_tasks — can_write_financials() ──────────────────────
SELECT
  'V11' AS check_id,
  CASE
    WHEN COUNT(*) >= 3
      AND bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'custom_tasks (write policies)' AS object,
  'Write policies: ' || COUNT(*)::text
    || ' | All can_write_financials: '
    || bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'custom_tasks'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V12: budget_line_rules — STOP CONDITION check ───────────────────
-- Product decision: household operational (canWriteFinancials).
-- If live = is_owner(), migration required before 5E-8.
SELECT
  'V12' AS check_id,
  CASE
    WHEN COUNT(*) = 0 THEN 'FAIL'  -- no write policies at all
    WHEN bool_and(qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%')
      AND NOT bool_or(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'FAIL'  -- owner-only: Wendy blocked
    WHEN bool_and(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
      THEN 'PASS'  -- matches product decision
    ELSE 'REVIEW'
  END AS status,
  'budget_line_rules (write policies)' AS object,
  'Write policies: ' || COUNT(*)::text
    || ' | Uses can_write_financials: '
    || bool_or(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')::text
    || ' | Uses is_owner (blocks Wendy): '
    || bool_or(qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%')::text
    || CASE
         WHEN bool_and(qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%')
           AND NOT bool_or(qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%')
           THEN ' — STOP: SQL migration required to change is_owner() to can_write_financials() before 5E-8'
         ELSE ''
       END AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'budget_line_rules'
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL');

-- ── V13: SELECT policies use is_allowed_user() — fail-loud for missing tables ─
-- LEFT JOIN expected table list so tables with ZERO SELECT policies emit FAIL.
-- Per-policy row output for tables that do have policies; FAIL row for tables that have none.
SELECT
  'V13' AS check_id,
  CASE
    WHEN p.policyname IS NULL THEN 'FAIL'
    WHEN p.qual ILIKE '%is_allowed_user%' THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  e.tbl || COALESCE(' | ' || p.policyname, '') AS object,
  CASE
    WHEN p.policyname IS NULL
      THEN 'ZERO SELECT policies found — table has no read policy; all SELECTs will be blocked'
    WHEN p.qual NOT ILIKE '%is_allowed_user%'
      THEN 'cmd=SELECT | qual=' || COALESCE(p.qual,'(none)') || ' — VIOLATION: SELECT policy does not use is_allowed_user()'
    ELSE 'cmd=SELECT | qual=' || COALESCE(p.qual,'(none)')
  END AS details
FROM (
  VALUES
    ('transactions'),('budget_transactions'),('budget_line_rules'),
    ('accounts'),('categories'),('weekly_reconciliations'),
    ('weekly_tasks'),('weekly_notes'),('model_week_overrides'),
    ('goals'),('wishlist_items'),('custom_tasks')
) AS e(tbl)
LEFT JOIN pg_policies p
  ON p.schemaname = 'public'
  AND p.tablename = e.tbl
  AND p.cmd = 'SELECT'
ORDER BY e.tbl, p.policyname;

-- ── V14: No write policies on budget_rules or goal_registry ─────────
-- These tables should be read-only from the app (seeded via SQL only).
SELECT
  'V14' AS check_id,
  CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'REVIEW' END AS status,
  tablename AS object,
  CASE WHEN COUNT(*) = 0
    THEN 'No write policies — read-only as expected'
    ELSE COUNT(*)::text || ' write policies found — verify intent'
  END AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('budget_rules','goal_registry')
  AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
GROUP BY tablename
UNION ALL
SELECT 'V14','PASS','budget_rules','No write policies found' WHERE NOT EXISTS (
  SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='budget_rules' AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
)
UNION ALL
SELECT 'V14','PASS','goal_registry','No write policies found' WHERE NOT EXISTS (
  SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='goal_registry' AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
);

-- ── V15: Summary — count PASS/FAIL across all checks ────────────────
-- Helper: run all checks above and look for any FAIL rows.
-- This check is informational — scan the full output above for FAILs.
SELECT
  'V15' AS check_id,
  'REVIEW' AS status,
  'manual inspection required' AS object,
  'Scan all rows above. Any FAIL row requires resolution before 5E-8 Wendy Operating Readiness.' AS details;
