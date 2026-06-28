-- ============================================================
-- Phase 5E-6 Migration — Monthly Entertainment Buckets
-- Purpose: Convert entertainment from standalone leaf to parent/group.
--          Close old parent rule at June 2026.
--          Seed 6 active July 2026 child rows totaling $1,500.
-- Date: 2026-06-27
-- Author: adam@herndons.us
-- Idempotent: yes (WHERE NOT EXISTS guards prevent re-insertion)
-- Hard-stop guards: DO $$ RAISE EXCEPTION on unsafe preconditions.
-- ============================================================

-- ── Guard 1: Exactly one active parent entertainment rule must exist ──────────
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM budget_line_rules
  WHERE category_key = 'entertainment'
    AND is_active = true
    AND start_month <= '2026-07-01'
    AND (end_month IS NULL OR end_month >= '2026-07-01');

  IF v_count = 0 THEN
    RAISE EXCEPTION
      'HARD STOP: No active entertainment parent rule found that covers July 2026. '
      'Migration assumes exactly one active open-ended parent rule. '
      'Run preflight to diagnose. Aborting.';
  END IF;

  IF v_count > 1 THEN
    RAISE EXCEPTION
      'HARD STOP: Found % active entertainment parent rules covering July 2026 (expected 1). '
      'Resolve overlapping rules before running this migration. '
      'Run preflight query #9 to identify conflicting rows. Aborting.', v_count;
  END IF;
END $$;


-- ── Guard 2: No existing active July rows for any of the 6 activated child keys
DO $$
DECLARE
  v_conflicts TEXT;
BEGIN
  SELECT STRING_AGG(category_key || ' (start: ' || start_month || ')', ', ')
    INTO v_conflicts
  FROM budget_line_rules
  WHERE category_key IN (
    'entertainment.event_1','entertainment.event_2',
    'entertainment.week_1','entertainment.week_2',
    'entertainment.week_3','entertainment.week_4'
  )
    AND is_active = true
    AND start_month <= '2026-07-01'
    AND (end_month IS NULL OR end_month >= '2026-07-01');

  IF v_conflicts IS NOT NULL THEN
    RAISE EXCEPTION
      'HARD STOP: The following child keys already have active rules covering July 2026: %. '
      'This migration is not idempotent for pre-existing child rows. '
      'Run preflight query #8 to inspect. Aborting.', v_conflicts;
  END IF;
END $$;


-- ── Guard 3: No unexpected active rows for inactive child slots ───────────────
DO $$
DECLARE
  v_conflicts TEXT;
BEGIN
  SELECT STRING_AGG(category_key || ' (start: ' || start_month || ')', ', ')
    INTO v_conflicts
  FROM budget_line_rules
  WHERE category_key IN (
    'entertainment.event_3','entertainment.event_4','entertainment.event_5',
    'entertainment.week_5'
  )
    AND is_active = true
    AND start_month <= '2026-07-01'
    AND (end_month IS NULL OR end_month >= '2026-07-01');

  IF v_conflicts IS NOT NULL THEN
    RAISE EXCEPTION
      'HARD STOP: Inactive child slots already have active July rules: %. '
      'These should have no rows yet. Investigate before proceeding. Aborting.', v_conflicts;
  END IF;
END $$;


-- ── Step 1: Close old standalone entertainment rule at end of June 2026 ───────
-- Sets end_month = '2026-06-01' (June 2026 ISO month marker).
-- Rule remains active for June. Rule is inactive for July+.
-- Condition: only updates if end_month is not already correctly set.
UPDATE budget_line_rules
SET
  end_month    = '2026-06-01',
  updated_by   = 'adam@herndons.us',
  updated_at   = NOW()
WHERE category_key = 'entertainment'
  AND is_active = true
  AND (end_month IS NULL OR end_month > '2026-06-01');


-- ── Step 2: Insert 6 July 2026 child rows ────────────────────────────────────
-- One-time rules: start_month = end_month = '2026-07-01'.
-- Labels represent July-specific naming; future months use their own BLR rows.
-- WHERE NOT EXISTS prevents re-insertion on idempotent re-run.

-- entertainment.event_1 → Seattle, $300
INSERT INTO budget_line_rules
  (category_key, line_label, amount, start_month, end_month, is_active, created_by)
SELECT
  'entertainment.event_1', 'Seattle', 300, '2026-07-01', '2026-07-01', true, 'adam@herndons.us'
WHERE NOT EXISTS (
  SELECT 1 FROM budget_line_rules
  WHERE category_key = 'entertainment.event_1'
    AND start_month = '2026-07-01'
    AND is_active = true
);

-- entertainment.event_2 → Wewe's Lunches, $200
INSERT INTO budget_line_rules
  (category_key, line_label, amount, start_month, end_month, is_active, created_by)
SELECT
  'entertainment.event_2', 'Wewe''s Lunches', 200, '2026-07-01', '2026-07-01', true, 'adam@herndons.us'
WHERE NOT EXISTS (
  SELECT 1 FROM budget_line_rules
  WHERE category_key = 'entertainment.event_2'
    AND start_month = '2026-07-01'
    AND is_active = true
);

-- entertainment.week_1 → Entertainment Week 1, $250
INSERT INTO budget_line_rules
  (category_key, line_label, amount, start_month, end_month, is_active, created_by)
SELECT
  'entertainment.week_1', 'Entertainment Week 1', 250, '2026-07-01', '2026-07-01', true, 'adam@herndons.us'
WHERE NOT EXISTS (
  SELECT 1 FROM budget_line_rules
  WHERE category_key = 'entertainment.week_1'
    AND start_month = '2026-07-01'
    AND is_active = true
);

-- entertainment.week_2 → Entertainment Week 2, $250
INSERT INTO budget_line_rules
  (category_key, line_label, amount, start_month, end_month, is_active, created_by)
SELECT
  'entertainment.week_2', 'Entertainment Week 2', 250, '2026-07-01', '2026-07-01', true, 'adam@herndons.us'
WHERE NOT EXISTS (
  SELECT 1 FROM budget_line_rules
  WHERE category_key = 'entertainment.week_2'
    AND start_month = '2026-07-01'
    AND is_active = true
);

-- entertainment.week_3 → Entertainment Week 3, $250
INSERT INTO budget_line_rules
  (category_key, line_label, amount, start_month, end_month, is_active, created_by)
SELECT
  'entertainment.week_3', 'Entertainment Week 3', 250, '2026-07-01', '2026-07-01', true, 'adam@herndons.us'
WHERE NOT EXISTS (
  SELECT 1 FROM budget_line_rules
  WHERE category_key = 'entertainment.week_3'
    AND start_month = '2026-07-01'
    AND is_active = true
);

-- entertainment.week_4 → Entertainment Week 4, $250
INSERT INTO budget_line_rules
  (category_key, line_label, amount, start_month, end_month, is_active, created_by)
SELECT
  'entertainment.week_4', 'Entertainment Week 4', 250, '2026-07-01', '2026-07-01', true, 'adam@herndons.us'
WHERE NOT EXISTS (
  SELECT 1 FROM budget_line_rules
  WHERE category_key = 'entertainment.week_4'
    AND start_month = '2026-07-01'
    AND is_active = true
);


-- ── Post-migration summary ────────────────────────────────────────────────────
SELECT
  category_key,
  line_label,
  amount,
  start_month,
  end_month,
  is_active
FROM budget_line_rules
WHERE category_key = 'entertainment'
   OR category_key LIKE 'entertainment.%'
ORDER BY category_key, start_month;

-- Run phase-5e-6-validation.sql to verify correctness.
-- ============================================================
