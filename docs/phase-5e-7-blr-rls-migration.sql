-- ═══════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-7 BLR RLS Alignment Migration
-- Surgical: budget_line_rules write policies only.
-- Scope: Replace is_owner() with can_write_financials() on
--        INSERT, UPDATE, DELETE policies.
-- No schema changes. No data changes. No function changes.
-- SELECT policy is NOT touched.
-- Idempotent: safe to re-run.
--
-- Run in: Supabase SQL Editor → Primary Database → Role: postgres
-- Run AFTER: docs/phase-5e-7-preflight.sql confirms P8 FAIL
-- Run BEFORE: 5E-8 Wendy Operating Readiness
--
-- After running, execute docs/phase-5e-7-blr-rls-validation.sql
-- and then re-run P8 (preflight) and V12 (validation) to confirm PASS.
-- ═══════════════════════════════════════════════════════════════════

-- ── STEP 1: Drop existing write policies ────────────────────────────
-- These currently use is_owner(), which blocks household_admin (Wendy).
-- IF EXISTS makes this safe to re-run even if already dropped.

DROP POLICY IF EXISTS budget_line_rules_insert ON public.budget_line_rules;
DROP POLICY IF EXISTS budget_line_rules_update ON public.budget_line_rules;
DROP POLICY IF EXISTS budget_line_rules_delete ON public.budget_line_rules;

-- ── STEP 2: Re-create write policies using can_write_financials() ───
-- Grants INSERT/UPDATE/DELETE to owner AND household_admin.
-- Viewer role is excluded (can_write_financials() returns false for viewer).

CREATE POLICY budget_line_rules_insert
  ON public.budget_line_rules
  FOR INSERT
  TO authenticated
  WITH CHECK (can_write_financials());

CREATE POLICY budget_line_rules_update
  ON public.budget_line_rules
  FOR UPDATE
  TO authenticated
  USING (can_write_financials())
  WITH CHECK (can_write_financials());

CREATE POLICY budget_line_rules_delete
  ON public.budget_line_rules
  FOR DELETE
  TO authenticated
  USING (can_write_financials());

-- ── STEP 3: Verify ──────────────────────────────────────────────────
-- Run docs/phase-5e-7-blr-rls-validation.sql immediately after.
-- Then re-run P8 from docs/phase-5e-7-preflight.sql.
-- Then re-run V12 from docs/phase-5e-7-validation.sql.
-- All three must return PASS before proceeding to 5E-8.


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK BLOCK — DO NOT RUN UNLESS EXPLICITLY DIRECTED
-- Reverts write policies back to is_owner().
-- This re-blocks Wendy. Only use if migration must be undone.
-- ═══════════════════════════════════════════════════════════════════
--
-- DROP POLICY IF EXISTS budget_line_rules_insert ON public.budget_line_rules;
-- DROP POLICY IF EXISTS budget_line_rules_update ON public.budget_line_rules;
-- DROP POLICY IF EXISTS budget_line_rules_delete ON public.budget_line_rules;
--
-- CREATE POLICY budget_line_rules_insert
--   ON public.budget_line_rules
--   FOR INSERT
--   TO authenticated
--   WITH CHECK (is_owner());
--
-- CREATE POLICY budget_line_rules_update
--   ON public.budget_line_rules
--   FOR UPDATE
--   TO authenticated
--   USING (is_owner())
--   WITH CHECK (is_owner());
--
-- CREATE POLICY budget_line_rules_delete
--   ON public.budget_line_rules
--   FOR DELETE
--   TO authenticated
--   USING (is_owner());
