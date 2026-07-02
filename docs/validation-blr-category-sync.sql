-- ============================================================
-- Reusable validation — budget_line_rules / categories sync guard
-- ============================================================
-- Rule: any active budget_line_rules.category_key for an operating month
-- must exist as a row in public.categories before that month can be
-- considered operating-ready. Register (_getRegisterCategoryLabel) can
-- only resolve/save a category that exists in `categories`; a BLR row
-- with no matching categories row is invisible to Register even though
-- Budget will happily display its line_label.
--
-- Origin: Phase 5E-8 live-use bug, 2026-07-02. entertainment.event_1/
-- event_2/week_1-4 were seeded into budget_line_rules for July 2026
-- (docs/phase-5e-6-migration.sql) but never inserted into `categories`
-- (docs/phase-5d-1-migration.sql only seeded 4 static entertainment
-- leaves). Register showed stale labels for ~undetermined time until
-- caught via live use. Root-caused and data-corrected via
-- docs/2026-07-02-register-budget-category-sync.sql.
--
-- Usage: this file is a template, not a one-shot migration. Copy the
-- DO block below into any future budget_line_rules seed/migration that
-- activates rules for a new operating month, substituting v_month.
-- Run it as the LAST step of such a migration, after all INSERTs.
-- Read-only — makes no changes, only reports/raises.
--
-- No schema changes. No RLS changes. Not tied to entertainment or any
-- specific category — general across the whole categories/budget_line_rules
-- relationship.
-- ============================================================

SET search_path TO public;

-- ── Ad hoc / manual use — inspect without failing ──────────────────────────
-- Substitute the target month ISO (first-of-month) for '2026-07-01' below.
SELECT
  blr.category_key,
  blr.line_label,
  blr.start_month,
  blr.end_month,
  (c.key IS NOT NULL) AS exists_in_categories
FROM budget_line_rules blr
LEFT JOIN categories c ON c.key = blr.category_key
WHERE blr.is_active = true
  AND blr.start_month <= '2026-07-01'   -- <-- substitute target month
  AND (blr.end_month IS NULL OR blr.end_month >= '2026-07-01')
ORDER BY exists_in_categories, blr.category_key;


-- ── Hard-stop guard — copy into future migrations as the final step ────────
-- Substitute v_month. Aborts the migration (RAISE EXCEPTION) if any active
-- budget_line_rules row for that month has no matching categories row.
DO $$
DECLARE
  v_month   DATE := '2026-07-01';  -- <-- substitute target month
  v_missing TEXT;
BEGIN
  SELECT STRING_AGG(blr.category_key || ' ("' || COALESCE(blr.line_label,'') || '")', ', ')
    INTO v_missing
  FROM budget_line_rules blr
  LEFT JOIN categories c ON c.key = blr.category_key
  WHERE blr.is_active = true
    AND blr.start_month <= v_month
    AND (blr.end_month IS NULL OR blr.end_month >= v_month)
    AND c.key IS NULL;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'OPERATING-READINESS GUARD FAILED for %: active budget_line_rules category_key(s) with no matching categories row: %. '
      'Register cannot resolve or save these categories until each key is added to categories (or the BLR row is corrected). '
      'This month should not be treated as operating-ready until this guard passes. Aborting.',
      v_month, v_missing;
  END IF;

  RAISE NOTICE 'Operating-readiness guard passed for %: every active budget_line_rules.category_key exists in categories.', v_month;
END $$;


-- ============================================================
-- Deferred/future hardening — NOT implemented, audit required first
-- ============================================================
-- A DB-level FK (budget_line_rules.category_key -> categories.key) would
-- make this guard unconditional instead of relying on someone remembering
-- to run it. Not added now:
--   - Historical/legacy budget_line_rules rows (June and earlier, and any
--     closed/inactive rows) have not been audited for category_key values
--     that may not exist in categories today. Adding the FK before that
--     audit risks the migration itself failing, or silently requiring a
--     backfill that hasn't been scoped.
--   - Needs its own preflight (this file's SELECT, run across ALL rows —
--     not just is_active=true / operating-month-scoped — before any
--     ALTER TABLE ADD CONSTRAINT is drafted).
--   - Out of scope for Phase 5E-8. Track as a distinct future task, not
--     folded into the live-use bugfix.
