-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 5F-1 Rollback — Herndon Financial OS
-- Cash Commitment Capture + Cash Availability Engine
-- Undoes the durable database changes made by phase-5f-1-migration.sql.
-- Generated: 2026-07-01
--
-- WHEN TO RUN THIS:
--   - Migration ran but phase-5f-1-validation.sql (V1-V18) reveals a FAIL
--   - Migration succeeded and validated clean, but later JS/regression work
--     (Build Sequence steps 6-13) surfaces a cash-safety defect that traces
--     back to the DB layer and the fastest safe path is a full revert
--   - Any point before UI/JS work depends on cash_commitments existing, where
--     you want to return to the pre-5F-1 database state
--
-- WHEN NOT TO RUN THIS:
--   - Migration failed partway through — read which statement failed first.
--     Objects created before the failure point still exist; this script
--     still applies (IF EXISTS guards make every step safe to run even if
--     some objects were never created), but confirm nothing downstream
--     (index.html, test_regression.js) already assumes cash_commitments
--     exists before you drop it.
--   - JS-only bugs in isReservedAsOf() / getCashAvailabilityEngine() / the
--     reconciliation form once Build Sequence steps 6+ are underway — fix
--     in index.html, do not drop the DB layer under working JS.
--   - Any point after real commitment rows exist in cash_commitments that
--     Wendy or Adam have relied on (Phase 2/3 reconciliation entries) —
--     dropping the table at that point is a genuine data-loss event, not
--     a clean revert. Export the table first (see Step 0 below).
--
-- SCOPE:
--   Removes: save_reconciliation_with_commitments(), repair_commitments_for_week(),
--            validate_commitment_state(), trg_cash_commitments_updated trigger,
--            fn_cash_commitments_set_updated() trigger function, cash_commitments
--            table (with it: all rows, all 7 named CHECK constraints, both RLS
--            policies, the cc_select policy, and the UNIQUE constraint on
--            expected_item_id — all owned by the table, gone automatically).
--   Conditional (Step 5, commented out by default): weekly_reconciliations.balance_basis.
--   Preserves unconditionally: weekly_reconciliations.chk/sav/amx/tax/lc/week_num/
--            recorded_at (5F-1 never altered these — the migration's only touch on
--            this table was ADD COLUMN balance_basis), every row already in
--            weekly_reconciliations, and every other table in the schema.
--
-- OUT OF SCOPE — THIS SCRIPT NEVER TOUCHES:
--   budget_transactions, budget_line_rules, category actuals/variance, income
--   logic, transactions, accounts, categories, goals, wishlist_items,
--   custom_tasks, weekly_tasks, weekly_notes, model_week_overrides, or any
--   RLS/grants outside cash_commitments. If a rollback ever needs to touch
--   any of those, that is a scope violation of this file — stop and write
--   a separate, explicitly-reviewed script instead of extending this one.
--
-- ── weekly_reconciliations.balance_basis DECISION ───────────────────────────
-- The migration's ALTER TABLE ... ADD COLUMN IF NOT EXISTS balance_basis was
-- additive and non-destructive to any pre-existing column. Whether rollback
-- should also remove that column is a separate decision from removing
-- cash_commitments, because balance_basis can accumulate real operator data
-- (Adam or Wendy's Phase 0 "posted_current_balance / available_balance /
-- unknown" selection for a given week) independently of whether any
-- cash_commitments rows exist yet.
--
--   Case A — No reconciliation has been saved with a non-null balance_basis
--   yet (fresh migration, nothing recorded through it): safe to drop the
--   column with no data loss. Uncomment Step 5 below.
--
--   Case B — At least one weekly_reconciliations row already has a non-null
--   balance_basis value: dropping the column PERMANENTLY DESTROYS that data.
--   Run the pre-check query immediately below before deciding. Do not
--   uncomment Step 5 if it returns any rows unless you have confirmed with
--   Adam that losing that basis selection is acceptable.
--
-- Pre-check (run this manually before deciding on Step 5):
--   SELECT week_num, balance_basis, recorded_at FROM weekly_reconciliations
--   WHERE balance_basis IS NOT NULL ORDER BY week_num;
--   -- If this returns 0 rows: Case A, Step 5 is safe to uncomment.
--   -- If this returns any rows: Case B, STOP and confirm with Adam first.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Step 0 (optional) — export cash_commitments before dropping ────────────
-- Uncomment and run this SELECT first (or use Supabase's table export) if any
-- real commitment rows exist and you want a recovery copy before Step 4 drops
-- the table. Not part of the transactional rollback below — read-only, run
-- separately, save the output somewhere durable.
--
-- SELECT * FROM cash_commitments ORDER BY origin_model_week, created_at;


BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1: Drop save_reconciliation_with_commitments (exact signature)
-- SECURITY DEFINER RPC — dropping it removes the live-reconciliation write path.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 2: Drop repair_commitments_for_week (exact signature)
-- SECURITY DEFINER RPC — dropping it removes the historical-repair write path.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS repair_commitments_for_week(
  INT, INT, TEXT, JSONB, JSONB
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 3: Drop validate_commitment_state (exact signature)
-- SECURITY INVOKER helper — no other object depends on it once Steps 1-2 have
-- run (both RPCs called it by name inside plpgsql function bodies, which
-- Postgres does not track as a hard DROP dependency the way it would a view
-- referencing a column — so this DROP does not require CASCADE and does not
-- need to run before Steps 1-2, but the order here mirrors reverse-of-creation
-- for readability).
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS validate_commitment_state(
  UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 4: Drop cash_commitments trigger, trigger function, and table
-- Order matters here: the trigger depends on the function, so the trigger
-- must go first (or the function DROP needs CASCADE — explicit order avoids
-- relying on CASCADE for something this consequential). DROP TABLE at the end
-- takes the RLS policies (cc_select, cc_insert, cc_update), all 7 named CHECK
-- constraints, the UNIQUE constraint on expected_item_id, and every row with
-- it — nothing here needs a separate DROP POLICY or DROP CONSTRAINT, those
-- are owned by the table and disappear with it.
-- ─────────────────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_cash_commitments_updated ON cash_commitments;

DROP FUNCTION IF EXISTS fn_cash_commitments_set_updated();

DROP TABLE IF EXISTS cash_commitments;

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 5 (CONDITIONAL — commented out by default): weekly_reconciliations.balance_basis
-- Uncomment ONLY after running the pre-check query in the decision block above
-- and confirming Case A (no non-null balance_basis values exist), or after
-- explicit confirmation from Adam that losing recorded basis selections is
-- acceptable. Left commented by default so a routine rollback run does not
-- silently discard operator data.
--
-- WARNING: this permanently deletes any balance_basis value already recorded
-- against any week_num row. weekly_reconciliations.chk/sav/amx/tax/lc/week_num/
-- recorded_at are NEVER touched by this step or any other step in this file —
-- only the balance_basis column itself is affected, and only if uncommented.
-- ─────────────────────────────────────────────────────────────────────────────

-- ALTER TABLE weekly_reconciliations DROP COLUMN IF EXISTS balance_basis;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════════
-- POST-ROLLBACK VERIFICATION QUERIES
-- Run after COMMIT. All must match expected results before declaring rollback done.
-- ═══════════════════════════════════════════════════════════════════════════════

-- R1: cash_commitments table absent
SELECT COUNT(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'cash_commitments';
-- Expect: 0

-- R2: all three 5F-1 functions absent
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('validate_commitment_state','save_reconciliation_with_commitments','repair_commitments_for_week');
-- Expect: 0 rows

-- R3: fn_cash_commitments_set_updated absent
SELECT COUNT(*) FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name = 'fn_cash_commitments_set_updated';
-- Expect: 0

-- R4: trg_cash_commitments_updated absent (implied by R1, checked directly too)
SELECT COUNT(*) FROM pg_trigger WHERE tgname = 'trg_cash_commitments_updated';
-- Expect: 0

-- R5: cash_commitments RLS policies gone (implied by R1, checked directly too)
SELECT COUNT(*) FROM pg_policies WHERE tablename = 'cash_commitments';
-- Expect: 0

-- R6: weekly_reconciliations core columns unchanged — chk/sav/amx/tax/lc/week_num/recorded_at
-- must all still be present regardless of whether Step 5 ran.
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'weekly_reconciliations'
  AND column_name IN ('week_num','chk','sav','amx','tax','lc','recorded_at')
ORDER BY column_name;
-- Expect: 7 rows, unchanged from pre-5F-1 (week_num integer, chk/sav/amx/tax/lc numeric,
-- recorded_at timestamp with time zone)

-- R7: weekly_reconciliations.balance_basis status — informational, depends on Step 5
SELECT COUNT(*) AS balance_basis_column_present FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'weekly_reconciliations' AND column_name = 'balance_basis';
-- Expect: 1 if Step 5 was left commented out (default) — column persists, harmlessly unused.
-- Expect: 0 only if Step 5 was deliberately uncommented and run.

-- R8: weekly_reconciliations row count unchanged by this rollback (informational —
-- this file never issues DELETE/UPDATE against weekly_reconciliations rows).
SELECT COUNT(*) AS weekly_reconciliations_row_count FROM weekly_reconciliations;

-- R9: out-of-scope tables untouched — spot check row counts are simply present
-- (not compared to a pre-rollback baseline here; this file never writes to
-- these tables, so any change would have to come from something else entirely).
SELECT 'budget_transactions' AS tbl, COUNT(*) FROM budget_transactions
UNION ALL
SELECT 'budget_line_rules', COUNT(*) FROM budget_line_rules
UNION ALL
SELECT 'transactions', COUNT(*) FROM transactions;
-- Informational only — confirms these tables still exist and are queryable
-- after rollback. This file has no DDL or DML against any of them.
-- ═══════════════════════════════════════════════════════════════════════════════
