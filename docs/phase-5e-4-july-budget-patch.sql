-- =============================================================================
-- Phase 5E-4 — July Budget Patch: misc.goal_sweep correction
-- Project: usayoldrawwmjsmretin
-- Date: 2026-06-27
-- =============================================================================
-- Context:
--   The phase-5b-seed.sql set misc.goal_sweep to $2,300 with no end_month,
--   meaning it bleeds into July. But July added $850 in new expenses:
--     - home.mortgage_rent $5,300 → $5,400 (+$100) [already correct in seed]
--     - health_fitness.diablos_preston_fee $750 Jul–Dec 2026 [already in seed]
--   Those two rows are already correct. Only misc.goal_sweep needs fixing:
--   June stays $2,300; July onward becomes $1,450.
--
-- Also confirms:
--   - home.mortgage_rent:             June $5,300 / July+ $5,400 (seed-correct)
--   - health_fitness.diablos_preston_fee: $750 Jul–Dec 2026 (seed-correct)
--   - misc.extra:                     $1,869 (unchanged, preserved)
--
-- Safe to run from Supabase SQL Editor (auth.uid() is null; trigger uses
-- COALESCE(auth.uid(), OLD.updated_by) on UPDATE so no explicit UUID needed).
--
-- Idempotent: guarded against double-run.
-- Does NOT touch any prior-month rows or June history.
-- =============================================================================

DO $$
DECLARE
  adam_id          uuid;
  goal_sweep_june  uuid;   -- the $2,300 row (start June, no end)
  july_count       integer;
BEGIN

  -- Resolve Adam's UUID for the new INSERT row.
  SELECT id INTO adam_id
  FROM auth.users
  WHERE email = 'adam@herndons.us'
  LIMIT 1;

  IF adam_id IS NULL THEN
    RAISE EXCEPTION 'adam@herndons.us not found in auth.users';
  END IF;

  -- Idempotency guard: if a misc.goal_sweep row already starts on 2026-07-01,
  -- this patch has already been applied. Stop cleanly.
  SELECT COUNT(*) INTO july_count
  FROM budget_line_rules
  WHERE category_key = 'misc.goal_sweep'
    AND start_month  = '2026-07-01'
    AND is_active    = true;

  IF july_count > 0 THEN
    RAISE NOTICE 'July misc.goal_sweep row already exists — patch already applied, skipping.';
    RETURN;
  END IF;

  -- Find the open-ended $2,300 goal_sweep row (the June baseline).
  SELECT id INTO goal_sweep_june
  FROM budget_line_rules
  WHERE category_key = 'misc.goal_sweep'
    AND start_month  = '2026-06-01'
    AND end_month    IS NULL
    AND is_active    = true
  LIMIT 1;

  IF goal_sweep_june IS NULL THEN
    RAISE EXCEPTION
      'Could not find open-ended misc.goal_sweep row (start_month=2026-06-01, end_month=NULL). '
      'Check budget_line_rules for unexpected state before running this patch.';
  END IF;

  -- Step 1: Close the $2,300 row at June 2026.
  -- end_month = '2026-06-01' keeps it active for June (end_month >= June).
  UPDATE budget_line_rules
     SET end_month  = '2026-06-01',
         notes      = COALESCE(notes, '') || ' [Closed June 2026 by 5E-4 patch; replaced by $1,450 row for July+]'
   WHERE id = goal_sweep_june;

  RAISE NOTICE 'Closed $2,300 misc.goal_sweep row at end_month=2026-06-01 (id: %)', goal_sweep_june;

  -- Step 2: Insert the $1,450 row starting July 2026.
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, notes, created_by, updated_by)
  VALUES
    ('misc.goal_sweep', 'Extra Pay Going to Spreadsheet', 1450, '2026-07-01', NULL,
     'Reduced from $2,300: $850 absorbed by rent increase (+$100) and Diablos fee (+$750). Phase 5E-4.',
     adam_id, adam_id);

  RAISE NOTICE 'Inserted $1,450 misc.goal_sweep row for 2026-07-01 onward.';
  RAISE NOTICE 'Patch complete. Run verification query below to confirm.';

END;
$$;


-- =============================================================================
-- VERIFICATION — run after the DO block (separately, or uncomment here)
-- =============================================================================

-- July balance check: Total Planned = Total Income should be $15,938
SELECT
  'July 2026 budget summary' AS label,
  SUM(CASE WHEN category_key LIKE 'income.%' THEN amount ELSE 0 END)          AS total_income,
  SUM(CASE WHEN category_key NOT LIKE 'income.%' THEN amount ELSE 0 END)      AS total_planned,
  SUM(CASE WHEN category_key LIKE 'income.%' THEN amount ELSE 0 END)
  - SUM(CASE WHEN category_key NOT LIKE 'income.%' THEN amount ELSE 0 END)    AS difference
FROM budget_line_rules
WHERE is_active    = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01');

-- July key rows: confirm rent $5,400, Diablos $750, goal_sweep $1,450, extra $1,869
SELECT category_key, line_label, amount, start_month, end_month
FROM budget_line_rules
WHERE is_active    = true
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01')
  AND category_key IN (
    'home.mortgage_rent',
    'health_fitness.diablos_preston_fee',
    'misc.goal_sweep',
    'misc.extra'
  )
ORDER BY category_key;

-- June guard: confirm June key rows intact (goal_sweep $2,300, rent $5,300, no Diablos)
SELECT category_key, line_label, amount, start_month, end_month
FROM budget_line_rules
WHERE is_active    = true
  AND start_month <= '2026-06-01'
  AND (end_month IS NULL OR end_month >= '2026-06-01')
  AND category_key IN (
    'misc.goal_sweep',
    'home.mortgage_rent',
    'health_fitness.diablos_preston_fee'
  )
ORDER BY category_key;
-- Expected: goal_sweep=$2300, mortgage_rent=$5300. diablos_preston_fee must NOT appear (start_month=2026-07-01).

-- Duplicate active goal_sweep check — must return exactly 2 rows total (one June, one July+)
SELECT category_key, line_label, amount, start_month, end_month, is_active
FROM budget_line_rules
WHERE category_key = 'misc.goal_sweep'
ORDER BY start_month;
-- Expected: row 1 — start=2026-06-01, end=2026-06-01, amount=2300, is_active=true
--           row 2 — start=2026-07-01, end=NULL,       amount=1450, is_active=true
