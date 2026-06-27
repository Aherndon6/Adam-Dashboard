-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 5D-1 Rollback — Herndon Financial OS
-- Undoes all durable database changes made by phase-5d-1-migration.sql.
-- Generated: 2026-06-26
--
-- TIMING: This rollback is safe ONLY as an immediate Phase 5D-1 rollback,
-- before any later phase adds FK references into accounts or categories, or
-- adds application logic that depends on those tables existing. Once Phase 5E
-- or later phases are applied, this script will need to be extended to remove
-- those dependencies first. Do not run this script against a post-5D-1 schema
-- without auditing what else now depends on these tables.
--
-- WHEN TO RUN THIS:
--   - Migration succeeded but V1-V15 validation queries reveal unexpected results
--   - Database validated but flag=true smoke test reveals data integrity problems
--   - Any phase where you want to return to the pre-5D-1 database state
--
-- WHEN NOT TO RUN THIS:
--   - Migration failed before COMMIT — PostgreSQL already rolled back; nothing to undo
--   - flag=false regression failures that are JS-only bugs — fix in code, not DB
--   - flag=true smoke test failures that are UI/logic issues — keep DB, fix JS
--     (flag defaults to false; production is unaffected while you debug)
--
-- SCOPE:
--   Removes: accounts table, categories table, their triggers and policies,
--             Diablos and GLP Meds budget_line_rules rows.
--   Preserves: rent budget_line_rules rows ($5,300/$5,400 — pre-existed 5D-1),
--               all other budget_line_rules, all other tables and functions,
--               fn_set_updated_at() — see decision block below.
--
-- ── fn_set_updated_at() DECISION ────────────────────────────────────────────
-- The migration used CREATE OR REPLACE on fn_set_updated_at(). Three cases:
--
-- Case A — Function did not exist pre-5D-1 (P2 preflight returned error):
--   Safe to DROP. Uncomment the DROP FUNCTION line in Step 4 below.
--
-- Case B — Function existed with the SAME body pre-5D-1 (P2 captured identical def):
--   Check P3 preflight result. If no other triggers use it beyond the 5D-1 ones
--   (which DROP TABLE CASCADE already removes), uncomment the DROP.
--   If other triggers use it, leave the function — do NOT uncomment the DROP.
--
-- Case C — Function existed with a DIFFERENT body pre-5D-1 (P2 captured different def):
--   Do NOT DROP. Instead, restore the original body by running a CREATE OR REPLACE
--   with the body saved in the P2 preflight output. Add that statement here before
--   executing the rollback.
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1: Drop categories table (CASCADE handles trigger + policies + self-ref FKs)
-- No other table holds a FK into categories in Phase 5D-1.
-- If other tables were added that reference categories, list them here first.
-- ─────────────────────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS categories CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 2: Drop accounts table (CASCADE handles trigger + policies)
-- No other table holds a FK into accounts in Phase 5D-1.
-- ─────────────────────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS accounts CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 3: budget_line_rules rollback
-- Preflight P1 (run 2026-06-26) confirmed both rows already existed before
-- Phase 5D-1 migration ran:
--   health_fitness.diablos_preston_fee | 750.00 | 2026-07-01 | 2026-12-01 | true
--   health_fitness.wendy_glp_meds      | 404.00 | 2026-08-01 | 2026-12-01 | true
--
-- The migration's WHERE NOT EXISTS guards skipped both inserts.
-- Phase 5D-1 did not create these rows, so rollback must not delete them.
-- No rollback action required for budget_line_rules.
-- ─────────────────────────────────────────────────────────────────────────────

-- (no-op)

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 4: Drop fn_set_updated_at() — CONDITIONAL
-- Uncomment ONLY if the pre-check query above returned no other trigger users.
-- ─────────────────────────────────────────────────────────────────────────────

-- DROP FUNCTION IF EXISTS fn_set_updated_at() CASCADE;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════════
-- POST-ROLLBACK VERIFICATION QUERIES
-- Run after COMMIT. All must match expected results before declaring rollback done.
-- ═══════════════════════════════════════════════════════════════════════════════

-- R1: accounts table absent — expect error "relation does not exist" or 0 results via pg_class
SELECT COUNT(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'accounts';
-- Expect: 0

-- R2: categories table absent
SELECT COUNT(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'categories';
-- Expect: 0

-- R3: Diablos row still present (pre-existed Phase 5D-1; rollback does not touch it)
SELECT category_key, amount, start_month, end_month, is_active
FROM budget_line_rules
WHERE category_key = 'health_fitness.diablos_preston_fee'
  AND start_month   = '2026-07-01';
-- Expect: 1 row — 750.00 | 2026-07-01 | 2026-12-01 | true

-- R4: GLP Meds row still present (pre-existed Phase 5D-1; rollback does not touch it)
SELECT category_key, amount, start_month, end_month, is_active
FROM budget_line_rules
WHERE category_key = 'health_fitness.wendy_glp_meds'
  AND start_month   = '2026-08-01';
-- Expect: 1 row — 404.00 | 2026-08-01 | 2026-12-01 | true

-- R5: Rent rows unchanged — expect both pre-existing rows still present
SELECT amount, start_month, end_month FROM budget_line_rules
WHERE category_key = 'home.mortgage_rent' AND is_active = true
ORDER BY start_month DESC;
-- Expect: 5400 | 2026-07-01 | NULL
--         5300 | 2026-06-01 | 2026-06-01

-- R6: No orphaned policies for accounts or categories
SELECT COUNT(*) FROM pg_policies
WHERE tablename IN ('accounts','categories');
-- Expect: 0

-- R7: No orphaned triggers for accounts or categories
SELECT COUNT(*) FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname IN ('accounts','categories');
-- Expect: 0
