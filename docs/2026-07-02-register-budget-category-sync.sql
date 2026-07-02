-- ============================================================
-- Phase 5E-8 — Register/Budget category_key data correction
-- Purpose: Register's category dropdown/label resolution
--          (_getRegisterCategoryLabel, shipped in commit 238b245) sources
--          from `categories`, and only ever shows a budget_line_rules
--          line_label override when a row in `categories` shares that
--          exact category_key. The 6 Entertainment "slot" keys used by
--          the Budget module for July 2026 (entertainment.event_1,
--          event_2, week_1-4 — see docs/phase-5e-6-migration.sql) were
--          seeded into budget_line_rules but never into `categories`.
--          Result: Register can never show/save "Seattle" / "Wewe's
--          Lunches" / "Entertainment Week 1-4", even though the fix in
--          238b245 is working exactly as designed against the data as it
--          exists today. This script closes that data gap.
-- Date: 2026-07-02
-- Author: adam@herndons.us (drafted by Claude, reviewed before execution)
-- Classification: 5E-8 live-use DATA correction. Not an app refactor.
--                 Not 5F-1 work.
-- Scope guarantees:
--   - Data-only SQL (categories INSERTs only)
--   - No UPDATEs to existing categories rows (ON CONFLICT DO NOTHING only)
--   - No DELETEs
--   - No schema changes (no CREATE/ALTER/DROP on any table)
--   - No RLS changes (no GRANT/REVOKE/POLICY statements)
--   - No index.html changes bundled with this file
-- Idempotent: yes. Re-running after a successful run finds 0 missing rows
--             and inserts nothing.
-- Hard-stop guards: DO $$ RAISE EXCEPTION on unsafe preconditions (same
--             convention as docs/phase-5e-6-migration.sql Guards 1-3).
-- Execution order: run each SECTION in order. Sections 1 and 2 are
--             read-only — review their output before running Section 3.
-- ============================================================

SET search_path TO public;


-- ============================================================
-- SECTION 1: PREFLIGHT (read-only)
-- ============================================================

-- 1a. Full visibility — every active-July-2026 budget_line_rules row,
--     flagged by whether its category_key exists in categories.
--     General/query-driven: not limited to entertainment.
SELECT
  blr.category_key,
  blr.line_label      AS july_blr_line_label,
  blr.amount,
  blr.start_month,
  blr.end_month,
  (c.key IS NOT NULL) AS exists_in_categories
FROM budget_line_rules blr
LEFT JOIN categories c ON c.key = blr.category_key
WHERE blr.is_active = true
  AND blr.start_month <= '2026-07-01'
  AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
ORDER BY exists_in_categories, blr.category_key;


-- 1b. Missing only — this is the exact set Section 3 will attempt to insert.
SELECT blr.category_key, blr.line_label, blr.amount, blr.start_month, blr.end_month
FROM budget_line_rules blr
LEFT JOIN categories c ON c.key = blr.category_key
WHERE blr.is_active = true
  AND blr.start_month <= '2026-07-01'
  AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
  AND c.key IS NULL
ORDER BY blr.category_key;


-- 1c. Explicit spot-check on the 6 keys named in the bug report, plus a
--     positive confirmation of whether each row found in 1b matches the
--     expected entertainment.event_N / week_N slot pattern (Execution
--     rule #3: confirm the missing rows are exactly the expected keys).
SELECT k AS category_key, EXISTS(SELECT 1 FROM categories c WHERE c.key = k) AS exists_in_categories
FROM unnest(ARRAY[
  'entertainment.event_1','entertainment.event_2',
  'entertainment.week_1','entertainment.week_2','entertainment.week_3','entertainment.week_4'
]) AS k
ORDER BY k;

SELECT
  blr.category_key,
  blr.line_label,
  (blr.category_key ~ '^entertainment\.(event|week)_[1-9][0-9]*$') AS matches_expected_slot_pattern
FROM budget_line_rules blr
LEFT JOIN categories c ON c.key = blr.category_key
WHERE blr.is_active = true
  AND blr.start_month <= '2026-07-01'
  AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
  AND c.key IS NULL
ORDER BY blr.category_key;
-- Every row here must show matches_expected_slot_pattern = true before proceeding.
-- If any row shows false, STOP. Do not run Section 3 until that key is reviewed
-- manually (its parent_key/behavior_class cannot be safely auto-derived).


-- 1d. HARD STOP GUARD — automated version of 1c's check. Aborts the whole
--     script (this statement and everything after it, in the same
--     transaction/session) if any missing key falls outside the known
--     pattern. Execution rule #2: "Stop unless preflight #4 returns 0 rows."
DO $$
DECLARE
  v_unexpected TEXT;
BEGIN
  SELECT STRING_AGG(blr.category_key, ', ')
    INTO v_unexpected
  FROM budget_line_rules blr
  LEFT JOIN categories c ON c.key = blr.category_key
  WHERE blr.is_active = true
    AND blr.start_month <= '2026-07-01'
    AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
    AND c.key IS NULL
    AND blr.category_key !~ '^entertainment\.(event|week)_[1-9][0-9]*$';

  IF v_unexpected IS NOT NULL THEN
    RAISE EXCEPTION
      'HARD STOP: preflight found missing category_key(s) outside the known entertainment.event_N/week_N pattern: %. '
      'Do not proceed with the INSERT (Section 3) until these are reviewed manually. Aborting.', v_unexpected;
  END IF;

  RAISE NOTICE 'Guard passed: all missing active-July BLR category_keys match the expected entertainment.event_N/week_N pattern (or none are missing).';
END $$;


-- 1e. Reference count — record this number. Compared automatically against
--     inserted_count and still_missing_count inside Section 3's DO block.
SELECT COUNT(*) AS preflight_missing_count
FROM budget_line_rules blr
LEFT JOIN categories c ON c.key = blr.category_key
WHERE blr.is_active = true
  AND blr.start_month <= '2026-07-01'
  AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
  AND c.key IS NULL;


-- ============================================================
-- SECTION 2: PREVIEW (read-only) — exactly what each missing row will
-- become. Run and review this before running Section 3. Same SELECT
-- shape (minus is_system) as the INSERT's source query in Section 3, so
-- what you see here is exactly what gets written.
-- ============================================================
SELECT
  blr.category_key AS key,
  regexp_replace(
    regexp_replace(blr.category_key, '^entertainment\.event_([0-9]+)$', 'Entertainment Event \1'),
    '^entertainment\.week_([0-9]+)$', 'Entertainment Week \1'
  ) AS proposed_label,
  'entertainment'::text AS parent_key,
  true::boolean          AS is_leaf,
  'expense'::text         AS behavior_class,
  'tracked'::text         AS budget_treatment,
  'operating'::text       AS cashflow_treatment,
  'entertainment'::text   AS budget_line_key,
  'entertainment'::text   AS budget_group_key,
  'active'::text          AS lifecycle_status,
  4040 + (ROW_NUMBER() OVER (ORDER BY blr.category_key))*10 AS display_order
FROM budget_line_rules blr
LEFT JOIN categories c ON c.key = blr.category_key
WHERE blr.is_active = true
  AND blr.start_month <= '2026-07-01'
  AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
  AND c.key IS NULL
  AND blr.category_key ~ '^entertainment\.(event|week)_[1-9][0-9]*$'
ORDER BY blr.category_key;


-- ============================================================
-- SECTION 3: INSERT (data-only, idempotent, guarded)
-- Run only after reviewing Section 2's preview output.
-- Wrapped in a DO block so preflight_missing_count / inserted_count /
-- still_missing_count are captured and reconciled automatically —
-- RAISE NOTICE reports all three; RAISE EXCEPTION fires if the
-- relationship (missing_before - inserted = missing_after) doesn't
-- hold, or if anything is still missing afterward, so a silent partial
-- insert cannot go unnoticed.
-- ============================================================
DO $$
DECLARE
  v_missing_before INT;
  v_inserted_count INT;
  v_missing_after  INT;
BEGIN
  SELECT COUNT(*) INTO v_missing_before
  FROM budget_line_rules blr
  LEFT JOIN categories c ON c.key = blr.category_key
  WHERE blr.is_active = true
    AND blr.start_month <= '2026-07-01'
    AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
    AND c.key IS NULL;

  INSERT INTO categories
    (key, label, parent_key, is_leaf, behavior_class, budget_treatment,
     cashflow_treatment, budget_line_key, budget_group_key, is_system,
     lifecycle_status, display_order)
  SELECT
    blr.category_key,
    regexp_replace(
      regexp_replace(blr.category_key, '^entertainment\.event_([0-9]+)$', 'Entertainment Event \1'),
      '^entertainment\.week_([0-9]+)$', 'Entertainment Week \1'
    ),
    'entertainment', true, 'expense', 'tracked', 'operating',
    'entertainment', 'entertainment', true, 'active',
    4040 + (ROW_NUMBER() OVER (ORDER BY blr.category_key))*10
  FROM budget_line_rules blr
  LEFT JOIN categories c ON c.key = blr.category_key
  WHERE blr.is_active = true
    AND blr.start_month <= '2026-07-01'
    AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
    AND c.key IS NULL
    AND blr.category_key ~ '^entertainment\.(event|week)_[1-9][0-9]*$'
  ON CONFLICT (key) DO NOTHING;

  GET DIAGNOSTICS v_inserted_count = ROW_COUNT;

  SELECT COUNT(*) INTO v_missing_after
  FROM budget_line_rules blr
  LEFT JOIN categories c ON c.key = blr.category_key
  WHERE blr.is_active = true
    AND blr.start_month <= '2026-07-01'
    AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
    AND c.key IS NULL;

  RAISE NOTICE 'preflight_missing_count=% inserted_count=% still_missing_count=%',
    v_missing_before, v_inserted_count, v_missing_after;

  -- ON CONFLICT DO NOTHING can only skip a row here if it was inserted by
  -- something else between the preflight and this INSERT (race condition) —
  -- under the WHERE clause above, a row counted as "missing" cannot already
  -- exist at query-plan time. Reconciliation still enforced defensively.
  IF v_missing_before - v_inserted_count <> v_missing_after THEN
    RAISE EXCEPTION
      'RECONCILIATION FAILED: missing_before(%) - inserted(%) != missing_after(%). Investigate before trusting this migration.',
      v_missing_before, v_inserted_count, v_missing_after;
  END IF;

  IF v_missing_after <> 0 THEN
    RAISE EXCEPTION
      'HARD STOP: % active-July BLR category_key(s) still missing from categories after insert. Re-run Section 1 preflight to see which.',
      v_missing_after;
  END IF;
END $$;


-- ============================================================
-- SECTION 4: VALIDATION (read-only, run after Section 3)
-- ============================================================

-- 4.1 All active-July BLR category_keys now exist in categories. Expect 0.
SELECT COUNT(*) AS still_missing
FROM budget_line_rules blr
LEFT JOIN categories c ON c.key = blr.category_key
WHERE blr.is_active = true
  AND blr.start_month <= '2026-07-01'
  AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
  AND c.key IS NULL;

-- 4.2 Register-eligible (leaf && assignable — same derivation _normalizeCatRow
--     uses client-side: is_leaf AND lifecycle_status='active' AND
--     behavior_class <> 'savings_allocation' AND budget_treatment <> 'planned_allocation').
SELECT key, label, is_leaf, lifecycle_status, behavior_class, budget_treatment,
  (is_leaf AND lifecycle_status='active'
    AND behavior_class IS DISTINCT FROM 'savings_allocation'
    AND budget_treatment IS DISTINCT FROM 'planned_allocation') AS assignable
FROM categories
WHERE key IN ('entertainment.event_1','entertainment.event_2',
              'entertainment.week_1','entertainment.week_2','entertainment.week_3','entertainment.week_4')
ORDER BY key;
-- Expect: is_leaf=true, assignable=true on all 6 present rows.

-- 4.3 Parent/group categories remain non-assignable (unaffected by this change).
SELECT key, is_leaf,
  (is_leaf AND lifecycle_status='active'
    AND behavior_class IS DISTINCT FROM 'savings_allocation'
    AND budget_treatment IS DISTINCT FROM 'planned_allocation') AS assignable
FROM categories
WHERE key IN ('entertainment','auto_transport','bills_utilities','food_dining','health_fitness','home','misc','personal_care');
-- Expect: is_leaf=false, assignable=false on all.

-- 4.4 No duplicate keys (UNIQUE constraint already guarantees this
--     structurally; also catches case/whitespace near-duplicates it wouldn't).
SELECT lower(trim(key)) AS normalized_key, COUNT(*), STRING_AGG(key,', ')
FROM categories GROUP BY normalized_key HAVING COUNT(*) > 1;
-- Expect 0 rows.

-- 4.5 No unrelated categories touched. This INSERT never UPDATEs an existing
--     row (ON CONFLICT DO NOTHING only), so run this query and compare
--     row-for-row against a snapshot taken before Section 3 if you want a
--     full diff; at minimum, confirm the total count grew by exactly
--     inserted_count from Section 3's RAISE NOTICE output.
SELECT COUNT(*) AS total_categories FROM categories;

SELECT key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
       budget_line_key, budget_group_key, lifecycle_status, display_order
FROM categories
WHERE key ~ '^entertainment\.'
ORDER BY key;
-- Sanity check: should now show all 10 entertainment children (4 original +
-- up to 6 new), each with is_leaf=true and the expected behavior_class/
-- budget_treatment/cashflow_treatment ('expense'/'tracked'/'operating').


-- ============================================================
-- ROLLBACK (not executed — reference only, in case of a bad insert)
-- ============================================================
-- DELETE FROM categories
-- WHERE key IN ('entertainment.event_1','entertainment.event_2',
--               'entertainment.week_1','entertainment.week_2',
--               'entertainment.week_3','entertainment.week_4')
--   AND is_system = true
--   AND created_at > now() - interval '1 hour';  -- safety bound, adjust as needed
-- Only ever run manually, row-by-row reviewed. Not part of normal execution.
