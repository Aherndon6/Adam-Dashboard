-- ═══════════════════════════════════════════════════════════════════
-- Phase 5F-1 Grant Repair — Herndon Financial OS
-- Fixes: V11, V14, V17 FAIL — validate_commitment_state retained EXECUTE
-- for both anon and authenticated; save_reconciliation_with_commitments
-- and repair_commitments_for_week retained EXECUTE for anon — despite
-- "REVOKE ALL ... FROM PUBLIC" in phase-5f-1-migration.sql.
--
-- ROOT CAUSE (independently confirmed, not just taken on report): every
-- Supabase project ships with a schema-level default privilege rule,
-- roughly:
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS
--   TO anon, authenticated, service_role;
-- This fires automatically at CREATE FUNCTION time and grants EXECUTE
-- directly to anon and authenticated as their own ACL entries — separate
-- from, and NOT removed by, "REVOKE ALL ... FROM PUBLIC". The migration's
-- REVOKE ALL FROM PUBLIC was correct under plain PostgreSQL semantics
-- (where EXECUTE defaults to PUBLIC only) but didn't account for
-- Supabase's per-role default-privilege auto-grant, which attached
-- role-specific grants at the moment each function was created.
--
-- Durability note: CREATE OR REPLACE FUNCTION on an already-existing
-- function does NOT reset its ACL (REPLACE preserves the existing
-- object's grants; default privileges only fire on first CREATE). So
-- this repair is safe against a future CREATE OR REPLACE redeploy of
-- these three functions. It would NOT survive a DROP + recreate (e.g.
-- rollback followed by re-running the migration from scratch) — that's
-- exactly why phase-5f-1-migration.sql is also being patched (separately)
-- to bake the anon/authenticated revokes into the REVOKE ALL lines
-- directly, so a future clean install doesn't reintroduce this gap.
--
-- Scope: EXECUTE privilege on these three functions only. No table,
-- policy, constraint, RLS, or function-body change. service_role is
-- out of scope — untouched, same as the original migration.
-- Date: 2026-07-01
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

SET LOCAL search_path TO public;

-- ── 1. validate_commitment_state — internal helper, no caller should
--       have EXECUTE at all (called only by the two SECURITY DEFINER
--       RPCs below, as the function owner) ───────────────────────────
REVOKE ALL ON FUNCTION validate_commitment_state(
  UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT
) FROM PUBLIC, anon, authenticated;
-- No GRANT — internal helper only.

-- ── 2. save_reconciliation_with_commitments — authenticated only ──────
REVOKE ALL ON FUNCTION save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB
) TO authenticated;

-- ── 3. repair_commitments_for_week — authenticated only ────────────────
REVOKE ALL ON FUNCTION repair_commitments_for_week(
  INT, INT, TEXT, JSONB, JSONB
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION repair_commitments_for_week(
  INT, INT, TEXT, JSONB, JSONB
) TO authenticated;

COMMIT;

-- ── Post-repair verification ────────────────────────────────────────
-- Run after COMMIT, against committed state. Run each SELECT individually
-- (Supabase's SQL editor only shows the last statement's result when
-- multiple are run together) — or run all three, then rerun
-- phase-5f-1-validation.sql's combined result set (V11, V14, V17, and
-- V18 as the independent cross-check) for the full gate.

SELECT
  'validate_commitment_state' AS function_name,
  has_function_privilege('anon',
    'public.validate_commitment_state(UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT)', 'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',
    'public.validate_commitment_state(UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT)', 'EXECUTE') AS authenticated_execute,
  'expect anon=false, authenticated=false' AS expected;

SELECT
  'save_reconciliation_with_commitments' AS function_name,
  has_function_privilege('anon',
    'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)', 'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',
    'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)', 'EXECUTE') AS authenticated_execute,
  'expect anon=false, authenticated=true' AS expected;

SELECT
  'repair_commitments_for_week' AS function_name,
  has_function_privilege('anon',
    'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)', 'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',
    'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)', 'EXECUTE') AS authenticated_execute,
  'expect anon=false, authenticated=true' AS expected;

-- After confirming all three rows above, rerun phase-5f-1-validation.sql
-- (or just its COMBINED RESULT SET query) to confirm the fix through the
-- same validation gate used for the original migration — V11/V14/V17
-- should now PASS, and V18's independent cross-check via
-- information_schema.role_routine_grants should show no anon rows and
-- exactly one authenticated row per RPC (none for validate_commitment_state).
-- ═══════════════════════════════════════════════════════════════════
