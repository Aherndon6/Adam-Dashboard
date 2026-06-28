-- ============================================================
-- Phase 5E-6 Rollback — Monthly Entertainment Buckets
-- Purpose: Reverse the 5E-6 migration. Restore standalone entertainment rule.
-- Date: 2026-06-27
-- Run only if migration must be undone.
-- ============================================================

SET search_path TO public;

-- ── Guard: Confirm parent entertainment rule exists in closed state ───────────
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM budget_line_rules
  WHERE category_key = 'entertainment'
    AND is_active = true
    AND end_month = '2026-06-01';

  IF v_count = 0 THEN
    RAISE EXCEPTION
      'HARD STOP: No entertainment parent rule found with end_month=2026-06-01. '
      'Migration may not have run, or was already rolled back. Aborting.';
  END IF;
END $$;


-- ── Step 1: Reopen the old standalone entertainment rule (remove end_month) ───
UPDATE budget_line_rules
SET
  end_month    = NULL,
  updated_at   = NOW()
WHERE category_key = 'entertainment'
  AND is_active = true
  AND end_month = '2026-06-01';


-- ── Step 2: Deactivate the 6 July 2026 child rows ────────────────────────────
-- Sets is_active=false. Does not hard-delete.
UPDATE budget_line_rules
SET
  is_active    = false,
  updated_at   = NOW()
WHERE category_key IN (
  'entertainment.event_1','entertainment.event_2',
  'entertainment.week_1','entertainment.week_2',
  'entertainment.week_3','entertainment.week_4'
)
  AND start_month = '2026-07-01'
  AND is_active = true;


-- ── Verification: parent rule restored, no active child rows ──────────────────
SELECT
  'parent_rule' AS check_type,
  category_key,
  line_label,
  amount,
  start_month,
  end_month,
  is_active
FROM budget_line_rules
WHERE category_key = 'entertainment'
UNION ALL
SELECT
  'child_rows' AS check_type,
  category_key,
  line_label,
  amount,
  start_month,
  end_month,
  is_active
FROM budget_line_rules
WHERE category_key LIKE 'entertainment.%'
ORDER BY check_type, category_key, start_month;

-- Expected after rollback:
--   parent_rule: is_active=true, end_month=NULL (open-ended)
--   child_rows: all is_active=false

-- ── Confirm no active parent/child overlap remains ───────────────────────────
SELECT COUNT(*) AS active_entertainment_overlap
FROM budget_line_rules
WHERE (category_key = 'entertainment' OR category_key LIKE 'entertainment.%')
  AND is_active = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01');
-- Expected: 1 (only the reopened parent rule, no child rules)

-- ============================================================
-- Rollback complete. Run phase-5e-6-preflight.sql to verify
-- the system is back to pre-migration state.
-- ============================================================
