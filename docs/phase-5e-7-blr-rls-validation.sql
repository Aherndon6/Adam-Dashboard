-- ═══════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-7 BLR RLS Alignment Validation
-- Run AFTER docs/phase-5e-7-blr-rls-migration.sql
-- Confirms budget_line_rules write policies were updated correctly.
--
-- Output columns: check_id | status | object | details
-- status values: PASS | FAIL
--
-- After all checks return PASS:
--   1. Re-run P8 in docs/phase-5e-7-preflight.sql
--   2. Re-run V12 in docs/phase-5e-7-validation.sql
--   Both must also return PASS before proceeding to 5E-8.
-- ═══════════════════════════════════════════════════════════════════

-- ── BM1: All three write policies exist ─────────────────────────────
SELECT
  'BM1' AS check_id,
  CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END AS status,
  'budget_line_rules (write policy count)' AS object,
  'Expected 3 write policies (INSERT, UPDATE, DELETE) — found: ' || COUNT(*)::text
    || CASE WHEN COUNT(*) <> 3 THEN ' — FAIL: run migration and retry' ELSE '' END AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'budget_line_rules'
  AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL');

-- ── BM2: All write policies use can_write_financials() ──────────────
SELECT
  'BM2' AS check_id,
  CASE
    WHEN COUNT(*) = 0 THEN 'FAIL'
    WHEN bool_and(
      qual ILIKE '%can_write_financials%'
      OR with_check ILIKE '%can_write_financials%'
    ) THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'budget_line_rules (can_write_financials predicate)' AS object,
  'Write policies using can_write_financials(): '
    || SUM(CASE
         WHEN qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%'
         THEN 1 ELSE 0
       END)::text
    || ' of ' || COUNT(*)::text
    || CASE
         WHEN NOT bool_and(
           qual ILIKE '%can_write_financials%' OR with_check ILIKE '%can_write_financials%'
         ) THEN ' — FAIL: one or more write policies still missing can_write_financials()'
         ELSE ''
       END AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'budget_line_rules'
  AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL');

-- ── BM3: No write policy uses is_owner() ────────────────────────────
SELECT
  'BM3' AS check_id,
  CASE
    WHEN bool_or(
      qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%'
    ) THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'budget_line_rules (no is_owner on writes)' AS object,
  CASE
    WHEN bool_or(qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%')
      THEN 'FAIL: ' || SUM(CASE
             WHEN qual ILIKE '%is_owner%' OR with_check ILIKE '%is_owner%' THEN 1 ELSE 0
           END)::text || ' write policy/policies still use is_owner() — migration incomplete'
    ELSE 'No write policy uses is_owner() — Wendy unblocked'
  END AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'budget_line_rules'
  AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL');

-- ── BM4: Per-policy breakdown — each write policy ───────────────────
-- COALESCE(qual,'') and COALESCE(with_check,'') prevent NULL-propagation false FAILs.
-- INSERT policies have qual=NULL (no USING clause).
-- DELETE policies have with_check=NULL (no WITH CHECK clause).
SELECT
  'BM4' AS check_id,
  CASE
    WHEN (COALESCE(qual,'') ILIKE '%can_write_financials%' OR COALESCE(with_check,'') ILIKE '%can_write_financials%')
      AND NOT (COALESCE(qual,'') ILIKE '%is_owner%' OR COALESCE(with_check,'') ILIKE '%is_owner%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'budget_line_rules | ' || cmd AS object,
  policyname
    || ' | qual=' || COALESCE(qual, '(none)')
    || ' | with_check=' || COALESCE(with_check, '(none)') AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'budget_line_rules'
  AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
ORDER BY cmd;

-- ── BM5: SELECT policy untouched — still uses is_allowed_user() ─────
SELECT
  'BM5' AS check_id,
  CASE
    WHEN COUNT(*) = 0
      THEN 'FAIL'
    WHEN bool_and(qual ILIKE '%is_allowed_user%')
      THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'budget_line_rules (SELECT policy intact)' AS object,
  'SELECT policies found: ' || COUNT(*)::text
    || ' | All use is_allowed_user(): '
    || COALESCE(bool_and(qual ILIKE '%is_allowed_user%')::text, 'N/A')
    || CASE
         WHEN COUNT(*) = 0 THEN ' — FAIL: SELECT policy missing; reads will be blocked'
         WHEN NOT bool_and(qual ILIKE '%is_allowed_user%')
           THEN ' — FAIL: SELECT policy does not use is_allowed_user()'
         ELSE ''
       END AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'budget_line_rules'
  AND cmd = 'SELECT';

-- ── BM6: Full policy listing for budget_line_rules ──────────────────
SELECT
  'BM6' AS check_id,
  'REVIEW' AS status,
  'budget_line_rules | ' || cmd AS object,
  policyname
    || ' | roles=' || array_to_string(roles, ',')
    || ' | qual=' || COALESCE(qual, '(none)')
    || ' | with_check=' || COALESCE(with_check, '(none)') AS details
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'budget_line_rules'
ORDER BY cmd, policyname;

-- ── BM7: Next steps reminder ─────────────────────────────────────────
SELECT
  'BM7' AS check_id,
  'REVIEW' AS status,
  'next steps' AS object,
  'If BM1–BM5 all PASS: (1) Re-run P8 in docs/phase-5e-7-preflight.sql, '
    || '(2) Re-run V12 in docs/phase-5e-7-validation.sql. '
    || 'Both must PASS before proceeding to Phase 5E-8 Wendy Operating Readiness.' AS details;
