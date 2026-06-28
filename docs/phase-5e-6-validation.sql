-- ============================================================
-- Phase 5E-6 Validation — Monthly Entertainment Buckets
-- Purpose: Read-only. Run after migration to confirm correctness.
-- Date: 2026-06-27
-- All checks have expected values. Review output against expected.
-- ============================================================

-- ── Check 1: Parent entertainment has no active July 2026 rule ───────────────
SELECT
  COUNT(*) AS active_parent_july_count
FROM budget_line_rules
WHERE category_key = 'entertainment'
  AND is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01');
-- Expected: 0


-- ── Check 2: Parent entertainment is still active for June 2026 ──────────────
SELECT
  COUNT(*) AS active_parent_june_count,
  SUM(amount) AS june_parent_budget
FROM budget_line_rules
WHERE category_key = 'entertainment'
  AND is_active = true
  AND start_month <= '2026-06-01'
  AND (end_month IS NULL OR end_month >= '2026-06-01');
-- Expected: count=1, budget=1500


-- ── Check 3: Exactly 6 active July child rows ─────────────────────────────────
SELECT
  COUNT(*) AS active_july_child_count
FROM budget_line_rules
WHERE category_key IN (
  'entertainment.event_1','entertainment.event_2','entertainment.event_3',
  'entertainment.event_4','entertainment.event_5',
  'entertainment.week_1','entertainment.week_2','entertainment.week_3',
  'entertainment.week_4','entertainment.week_5'
)
  AND is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01');
-- Expected: 6


-- ── Check 4: July child rows total exactly $1,500 ────────────────────────────
SELECT
  SUM(amount) AS july_child_total
FROM budget_line_rules
WHERE category_key IN (
  'entertainment.event_1','entertainment.event_2',
  'entertainment.week_1','entertainment.week_2',
  'entertainment.week_3','entertainment.week_4'
)
  AND is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01');
-- Expected: 1500


-- ── Check 5: Detail of all active July entertainment child rows ───────────────
SELECT
  category_key,
  line_label,
  amount,
  start_month,
  end_month
FROM budget_line_rules
WHERE category_key LIKE 'entertainment.%'
  AND is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01')
ORDER BY category_key;
-- Expected: 6 rows — event_1 Seattle $300, event_2 Wewe's Lunches $200,
--           week_1 through week_4 each $250


-- ── Check 6: Future months do not have active entertainment child rows ─────────
-- (Immediately post-migration — no child rows should cover August or beyond)
SELECT
  category_key,
  line_label,
  amount,
  start_month,
  end_month
FROM budget_line_rules
WHERE category_key LIKE 'entertainment.%'
  AND is_active = true
  AND start_month <= '2026-08-01'
  AND (end_month IS NULL OR end_month >= '2026-08-01');
-- Expected: 0 rows
-- Note: This is the immediate post-migration state. Budget Line Admin may
--       intentionally activate child keys for August/September later.


-- ── Check 7: No duplicate active child rules for July ────────────────────────
SELECT
  category_key,
  COUNT(*) AS duplicate_count
FROM budget_line_rules
WHERE category_key LIKE 'entertainment.%'
  AND is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01')
GROUP BY category_key
HAVING COUNT(*) > 1;
-- Expected: 0 rows


-- ── Check 8: Overall July 2026 Total Planned Budget unchanged ─────────────────
-- Entertainment: was $1,500 (parent), now $1,500 (children sum). Net change = $0.
SELECT
  COALESCE(SUM(amount), 0) AS july_total_living_expenses
FROM budget_line_rules
WHERE is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01')
  AND category_key NOT LIKE 'income.%'
  AND category_key != 'misc.goal_sweep';
-- Expected: same value as pre-migration (entertainment swap is net $0)


-- ── Check 9: No inactive child slots erroneously activated for July ───────────
SELECT
  category_key,
  line_label,
  amount
FROM budget_line_rules
WHERE category_key IN (
  'entertainment.event_3','entertainment.event_4','entertainment.event_5',
  'entertainment.week_5'
)
  AND is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01');
-- Expected: 0 rows (these slots not activated for July)


-- ── Check 10: Parent entertainment rule correctly closed ──────────────────────
SELECT
  id,
  category_key,
  line_label,
  amount,
  start_month,
  end_month,
  is_active
FROM budget_line_rules
WHERE category_key = 'entertainment'
ORDER BY start_month DESC;
-- Expected: is_active=true, end_month='2026-06-01' (closed at June)


-- ── Check 11: July Budget Balance (income vs planned) ────────────────────────
-- Income total:
SELECT
  COALESCE(SUM(amount), 0) AS july_income_total
FROM budget_line_rules
WHERE is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01')
  AND category_key LIKE 'income.%';
-- Expected: 15938

-- Total planned (expenses including goal_sweep, excluding income):
SELECT
  COALESCE(SUM(amount), 0) AS july_total_planned
FROM budget_line_rules
WHERE is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01')
  AND category_key NOT LIKE 'income.%';
-- Expected: 15938 (balanced at $0)

-- ============================================================
-- Validation complete.
-- If all checks show expected values, 5E-6 migration is confirmed good.
-- ============================================================
