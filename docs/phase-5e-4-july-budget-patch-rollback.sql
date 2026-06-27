-- =============================================================================
-- Phase 5E-4 — July Budget Patch ROLLBACK
-- Project: usayoldrawwmjsmretin
-- Date: 2026-06-27
-- =============================================================================
-- Reverses phase-5e-4-july-budget-patch.sql.
-- Restores misc.goal_sweep to a single open-ended $2,300 row (June onward).
--
-- Safe to run if the patch was applied. Idempotent — checks state before acting.
-- DO NOT run if you have already built July budget line data on top of the $1,450
-- row (e.g., any 5E-5 edits referencing that row). In that case, manual review
-- is required before rolling back.
-- =============================================================================

DO $$
DECLARE
  july_row_id   uuid;
  june_row_id   uuid;
  july_count    integer;
BEGIN

  -- Guard: check whether the patch was actually applied.
  SELECT COUNT(*) INTO july_count
  FROM budget_line_rules
  WHERE category_key = 'misc.goal_sweep'
    AND start_month  = '2026-07-01'
    AND is_active    = true;

  IF july_count = 0 THEN
    RAISE NOTICE 'No July misc.goal_sweep row found — patch may not have been applied. Nothing to roll back.';
    RETURN;
  END IF;

  -- Step 1: Deactivate (do not hard-delete) the $1,450 July row.
  UPDATE budget_line_rules
     SET is_active = false,
         notes     = COALESCE(notes, '') || ' [Deactivated by 5E-4 rollback]'
   WHERE category_key = 'misc.goal_sweep'
     AND start_month  = '2026-07-01'
     AND is_active    = true;

  RAISE NOTICE 'Deactivated $1,450 misc.goal_sweep row (start_month=2026-07-01).';

  -- Step 2: Re-open the June $2,300 row (remove end_month cap).
  UPDATE budget_line_rules
     SET end_month = NULL,
         notes     = COALESCE(notes, '') || ' [end_month restored by 5E-4 rollback]'
   WHERE category_key = 'misc.goal_sweep'
     AND start_month  = '2026-06-01'
     AND end_month    = '2026-06-01'
     AND is_active    = true;

  GET DIAGNOSTICS june_row_id = ROW_COUNT;
  IF june_row_id::text = '0' THEN
    RAISE WARNING 'Could not find June $2,300 misc.goal_sweep row with end_month=2026-06-01. '
      'It may already be open-ended or was modified. Check budget_line_rules manually.';
  ELSE
    RAISE NOTICE 'Restored June $2,300 misc.goal_sweep row to open-ended (end_month=NULL).';
  END IF;

  RAISE NOTICE 'Rollback complete.';

END;
$$;


-- =============================================================================
-- ROLLBACK VERIFICATION — run after the DO block
-- =============================================================================

-- Confirm exactly one active misc.goal_sweep row, starting June, amount $2,300
SELECT category_key, line_label, amount, start_month, end_month, is_active
FROM budget_line_rules
WHERE category_key = 'misc.goal_sweep'
ORDER BY start_month;
-- Expected after rollback:
--   row 1 — start=2026-06-01, end=NULL, amount=2300, is_active=true
--   row 2 — start=2026-07-01, end=NULL, amount=1450, is_active=false  (deactivated, not deleted)

-- Confirm July no longer has an active misc.goal_sweep at $1,450
SELECT COUNT(*) AS active_july_goal_sweep
FROM budget_line_rules
WHERE category_key = 'misc.goal_sweep'
  AND start_month <= '2026-07-01'
  AND (end_month IS NULL OR end_month >= '2026-07-01')
  AND is_active = true;
-- Expected: 1 (the restored $2,300 open-ended row applies to July too after rollback)

-- Confirm June still shows $2,300
SELECT category_key, line_label, amount
FROM budget_line_rules
WHERE category_key = 'misc.goal_sweep'
  AND start_month <= '2026-06-01'
  AND (end_month IS NULL OR end_month >= '2026-06-01')
  AND is_active = true;
-- Expected: 1 row, amount=2300
