-- ============================================================
-- Phase 5E-6 Preflight — Monthly Entertainment Buckets
-- Purpose: Read-only. Run before migration to verify assumptions.
-- Date: 2026-06-27
-- Safe to run multiple times. Makes no changes.
-- ============================================================

SET search_path TO public;

-- ── 1. Current active budget_line_rules for 'entertainment' parent key ───────
SELECT
  id,
  category_key,
  line_label,
  amount,
  start_month,
  end_month,
  is_active,
  created_at
FROM budget_line_rules
WHERE category_key = 'entertainment'
ORDER BY start_month DESC;

-- Expected: exactly one row, is_active=true, end_month IS NULL (open-ended through June close)
-- If more than one active row exists, migration will hard-stop.


-- ── 2. Any existing rows for proposed child keys ─────────────────────────────
SELECT
  id,
  category_key,
  line_label,
  amount,
  start_month,
  end_month,
  is_active
FROM budget_line_rules
WHERE category_key IN (
  'entertainment.event_1','entertainment.event_2','entertainment.event_3',
  'entertainment.event_4','entertainment.event_5',
  'entertainment.week_1','entertainment.week_2','entertainment.week_3',
  'entertainment.week_4','entertainment.week_5'
)
ORDER BY category_key, start_month;

-- Expected: zero rows. Any existing rows will trigger migration hard-stop for active July conflicts.


-- ── 3. June Entertainment budget total (before migration) ────────────────────
SELECT
  COALESCE(SUM(amount), 0) AS june_entertainment_total
FROM budget_line_rules
WHERE category_key = 'entertainment'
  AND is_active = true
  AND start_month <= '2026-06-01'
  AND (end_month IS NULL OR end_month >= '2026-06-01');

-- Expected: 1500.00


-- ── 4. July Entertainment budget total (before migration) ────────────────────
SELECT
  COALESCE(SUM(amount), 0) AS july_entertainment_total
FROM budget_line_rules
WHERE category_key = 'entertainment'
  AND is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01');

-- Expected: 1500.00 (still active for July before migration closes it)


-- ── 5. Existing budget_transactions using 'entertainment' parent key ──────────
SELECT
  COUNT(*) AS txn_count,
  MIN(transaction_date) AS earliest,
  MAX(transaction_date) AS latest,
  SUM(amount) AS total_amount
FROM budget_transactions
WHERE category_key = 'entertainment';

-- These transactions remain valid after migration.
-- They will display correctly via _getCategoryDisplayLabel fallback.
-- No data change is made to these rows.


-- ── 6. Sample of entertainment transactions (up to 10) ───────────────────────
SELECT
  id,
  transaction_date,
  description,
  amount,
  category_key
FROM budget_transactions
WHERE category_key = 'entertainment'
ORDER BY transaction_date DESC
LIMIT 10;


-- ── 7. Existing transactions using proposed child keys ───────────────────────
SELECT
  category_key,
  COUNT(*) AS txn_count
FROM budget_transactions
WHERE category_key IN (
  'entertainment.event_1','entertainment.event_2','entertainment.event_3',
  'entertainment.event_4','entertainment.event_5',
  'entertainment.week_1','entertainment.week_2','entertainment.week_3',
  'entertainment.week_4','entertainment.week_5'
)
GROUP BY category_key;

-- Expected: zero rows (no prior use of child keys)


-- ── 8. Duplicate/overlap risk for proposed July child rows ───────────────────
-- Check: would any of the 6 proposed inserts conflict with existing active rules?
SELECT
  r.category_key,
  r.line_label,
  r.amount,
  r.start_month,
  r.end_month,
  r.is_active
FROM budget_line_rules r
WHERE r.category_key IN (
  'entertainment.event_1','entertainment.event_2',
  'entertainment.week_1','entertainment.week_2',
  'entertainment.week_3','entertainment.week_4'
)
  AND r.is_active = true
  AND r.start_month <= '2026-07-01'
  AND (r.end_month IS NULL OR r.end_month >= '2026-07-01');

-- Expected: zero rows. Any result means migration will hard-stop.


-- ── 9. Count of active entertainment rules (for migration guard) ─────────────
SELECT COUNT(*) AS active_parent_entertainment_count
FROM budget_line_rules
WHERE category_key = 'entertainment'
  AND is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01');

-- Expected: 1. Migration will hard-stop if count != 1.


-- ── 10. Overall July 2026 budget total (for balance verification) ─────────────
SELECT
  COALESCE(SUM(amount), 0) AS july_total_planned
FROM budget_line_rules
WHERE is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01')
  AND category_key NOT LIKE 'income.%'
  AND category_key != 'misc.goal_sweep';

-- Expected: ~14,488 (living expenses excluding goal_sweep)
-- After migration: will add 6 child rows ($1,500) and remove parent row ($1,500) → net $0 change


-- ============================================================
-- Preflight complete. Review all output above before proceeding
-- to phase-5e-6-migration.sql.
-- ============================================================
