-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-2 Migration
-- ═══════════════════════════════════════════════════════════════════════════
-- Run ONLY after all phase-5e-2-preflight.sql checks pass (VP1–VP5).
-- Prerequisite: Phase 5E-1 migration must already be applied (transactions
-- table, allow_read policy, and GRANT SELECT must exist).
--
-- Safe to run while showTransactionLedger remains default false.
-- Do NOT enable write UI until migration validations (VM1–VM12) pass.
--
-- Intentionally NOT idempotent. No IF NOT EXISTS guards are used.
-- A partial or repeated run will fail loudly (duplicate policy errors).
-- This is by design: silent idempotency would mask a broken migration state.
-- If a partial run occurred, investigate and clean up before retrying.
-- ─────────────────────────────────────────────────────────────────────────

-- ── 1. Write Policies ─────────────────────────────────────────────────────
-- Predicate: can_write_financials() — covers owner (Adam) + household_admin (Wendy).
-- is_owner() would block Wendy. is_allowed_user() would allow future viewer roles.
-- can_write_financials() is the correct household write predicate for this project.
--
-- All write policies are restricted to source = 'manual'.
-- This ensures:
--   - UI cannot create import or migration rows
--   - Edit and delete are limited to manually-entered transactions
--   - Future import rows (Phase 5I) are protected from accidental UI modification
-- ─────────────────────────────────────────────────────────────────────────

-- INSERT: only allow manual source; user_id populated by DEFAULT auth.uid()
CREATE POLICY "financial_writer_insert" ON public.transactions
  FOR INSERT
  WITH CHECK (public.can_write_financials() AND source = 'manual');

-- UPDATE: full edit on manual rows only
-- account_key, user_id, source, created_at excluded from UPDATE grant (see below)
CREATE POLICY "financial_writer_update" ON public.transactions
  FOR UPDATE
  USING  (public.can_write_financials() AND source = 'manual')
  WITH CHECK (public.can_write_financials() AND source = 'manual');

-- DELETE: manual rows only
CREATE POLICY "financial_writer_delete" ON public.transactions
  FOR DELETE
  USING (public.can_write_financials() AND source = 'manual');

-- ── 2. Column-Level Grants ────────────────────────────────────────────────
-- NOTE: Supabase grants ALL privileges to anon and authenticated at the table
-- level by default. Column-level grants here are additive, not restrictive —
-- they do not prevent writes to unlisted columns when a table-level grant exists.
-- Security is enforced via RLS policies (source='manual', can_write_financials(),
-- user_id=auth.uid() checks). Column grants are kept for documentation intent
-- and in case table-level defaults are ever revoked.
--
-- INSERT: user_id intentionally excluded from explicit grant.
--   notes excluded — no UI field in 5E-2.
--   id, created_at, updated_at excluded — server-generated.
GRANT INSERT (account_key, transaction_date, payee, memo, amount, category_key, cleared, source)
  ON public.transactions TO authenticated;

-- UPDATE: only mutable fields.
--   account_key excluded — transactions cannot be moved between accounts in 5E-2.
--   user_id, source, created_at, updated_at excluded — audit/system fields.
--   notes excluded — no UI field in 5E-2.
GRANT UPDATE (transaction_date, payee, memo, amount, category_key, cleared)
  ON public.transactions TO authenticated;

-- DELETE: table-level (no column concept for DELETE in PostgreSQL)
GRANT DELETE ON public.transactions TO authenticated;

-- ── 2a. INSERT Policy Hardening (user_id spoofing guard) ──────────────────
-- Since table-level grants allow clients to send user_id in POST body,
-- add explicit user_id check to INSERT policy's WITH CHECK.
-- Applied post-migration on 2026-06-27 after VM6/VM8 investigation.
ALTER POLICY "financial_writer_insert" ON public.transactions
  WITH CHECK (
    public.can_write_financials()
    AND source = 'manual'
    AND (user_id = auth.uid() OR user_id IS NULL)
  );

-- ── 3. Post-Migration Validation Queries ──────────────────────────────────
-- Run immediately after migration as a single UNION ALL.
-- All checks must return expected values before enabling write UI.
-- ─────────────────────────────────────────────────────────────────────────

SELECT * FROM (

  -- VM1: financial_writer_insert policy exists with FOR INSERT
  SELECT 'VM1' AS check, 'financial_writer_insert_exists' AS item,
         (COUNT(*) = 1)::text AS result, 'true' AS expected
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'transactions'
     AND policyname = 'financial_writer_insert' AND cmd = 'INSERT'

  UNION ALL

  -- VM2: financial_writer_update policy exists with FOR UPDATE
  SELECT 'VM2', 'financial_writer_update_exists',
         (COUNT(*) = 1)::text, 'true'
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'transactions'
     AND policyname = 'financial_writer_update' AND cmd = 'UPDATE'

  UNION ALL

  -- VM3: financial_writer_delete policy exists with FOR DELETE
  SELECT 'VM3', 'financial_writer_delete_exists',
         (COUNT(*) = 1)::text, 'true'
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'transactions'
     AND policyname = 'financial_writer_delete' AND cmd = 'DELETE'

  UNION ALL

  -- VM4: allow_read policy still present (regression — must not have been dropped)
  SELECT 'VM4', 'allow_read_intact',
         (COUNT(*) = 1)::text, 'true'
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'transactions'
     AND policyname = 'allow_read' AND cmd = 'SELECT'

  UNION ALL

  -- VM5: INSERT grant covers all 8 required columns
  SELECT 'VM5', 'insert_required_columns',
         (COUNT(*) = 8)::text, 'true'
    FROM information_schema.role_column_grants
   WHERE table_schema = 'public' AND table_name = 'transactions'
     AND grantee = 'authenticated' AND privilege_type = 'INSERT'
     AND column_name IN ('account_key','transaction_date','payee','memo',
                         'amount','category_key','cleared','source')

  UNION ALL

  -- VM6: INSERT policy WITH CHECK enforces source=manual
  -- NOTE: Supabase grants ALL privileges to authenticated at table level by default,
  -- so column-level grant restriction is not achievable (role_column_grants reflects
  -- inherited table-level grants, not just explicit column grants). Security is
  -- enforced via RLS policies. This check verifies the policy predicate instead.
  SELECT 'VM6', 'insert_policy_enforces_manual_source',
         (with_check ILIKE '%manual%')::text, 'true'
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'transactions'
     AND policyname = 'financial_writer_insert'

  UNION ALL

  -- VM7: UPDATE grant covers all 6 required columns
  SELECT 'VM7', 'update_required_columns',
         (COUNT(*) = 6)::text, 'true'
    FROM information_schema.role_column_grants
   WHERE table_schema = 'public' AND table_name = 'transactions'
     AND grantee = 'authenticated' AND privilege_type = 'UPDATE'
     AND column_name IN ('transaction_date','payee','memo',
                         'amount','category_key','cleared')

  UNION ALL

  -- VM8: UPDATE policy WITH CHECK enforces source=manual
  -- NOTE: Same Supabase default table-level grant issue as VM6.
  -- Verified instead that the UPDATE policy predicate prevents source changes.
  SELECT 'VM8', 'update_policy_enforces_manual_source',
         (with_check ILIKE '%manual%')::text, 'true'
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'transactions'
     AND policyname = 'financial_writer_update'

  UNION ALL

  -- VM9: DELETE table-level grant exists for authenticated
  SELECT 'VM9', 'delete_grant_exists',
         (COUNT(*) = 1)::text, 'true'
    FROM information_schema.role_table_grants
   WHERE table_schema = 'public' AND table_name = 'transactions'
     AND grantee = 'authenticated' AND privilege_type = 'DELETE'

  UNION ALL

  -- VM10: SELECT grant still present (regression — must not have been revoked)
  -- Phase 5E-1 issued GRANT SELECT at table level, so check role_table_grants (not role_column_grants).
  SELECT 'VM10', 'select_grant_intact',
         (COUNT(*) > 0)::text, 'true'
    FROM information_schema.role_table_grants
   WHERE table_schema = 'public' AND table_name = 'transactions'
     AND grantee = 'authenticated' AND privilege_type = 'SELECT'

  UNION ALL

  -- VM11: user_id column default still auth.uid() (regression guard)
  SELECT 'VM11', 'user_id_default_intact',
         (column_default ILIKE '%auth.uid%')::text, 'true'
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'transactions'
     AND column_name = 'user_id'

  UNION ALL

  -- VM12: total policy count on transactions = 4
  -- allow_read + financial_writer_insert + financial_writer_update + financial_writer_delete
  SELECT 'VM12', 'total_policy_count',
         COUNT(*)::text, '4'
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'transactions'

) checks
ORDER BY check;

-- ── Manual policy inspection (run after UNION ALL) ─────────────────────────
-- Visually confirm write policies use can_write_financials() and source = 'manual'.
SELECT policyname, cmd, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'public'
   AND tablename  = 'transactions'
 ORDER BY policyname;
