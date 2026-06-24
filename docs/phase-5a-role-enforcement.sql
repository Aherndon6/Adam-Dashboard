-- ═══════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5A: Role Enforcement
-- Run in Supabase SQL Editor (supabase.com → project → SQL Editor)
-- Date: June 24, 2026 (revised)
-- Run steps IN ORDER. Verify each step before proceeding.
--
-- Role model:
--   owner          = Adam — full financial + platform/admin access
--   household_admin = Wendy — full financial operating access, no platform admin
--   viewer          = future read-only role
--
-- goals table uses row-qualified RLS: can_write_financials() applies only
-- to rows where key != 'anthropic_key'. Owner can write any goals row.
-- This is enforced at the DB level — not UI-only.
-- ═══════════════════════════════════════════════════════════════════


-- ── STEP 0: Verify current app_users state ──────────────────────────
-- Run this first. Confirm auth_user_id is populated for both users.
SELECT email, role, active, auth_user_id IS NOT NULL AS has_uid
FROM public.app_users
ORDER BY created_at;


-- ── STEP 1: Set role values ──────────────────────────────────────────
-- Target each user by exact email. Do NOT use != pattern — it would
-- silently promote any future user added to app_users.
UPDATE public.app_users SET role = 'owner'           WHERE email = 'adam@herndons.us';
UPDATE public.app_users SET role = 'household_admin' WHERE email = 'wherndon22@gmail.com';

-- Verify — must show adam@herndons.us = owner, wherndon22@gmail.com = household_admin.
-- No other rows should be changed. Do not proceed to Step 2 if either row is wrong.
SELECT email, role, active, auth_user_id IS NOT NULL AS has_uid
FROM public.app_users
WHERE email IN ('adam@herndons.us', 'wherndon22@gmail.com')
ORDER BY email;


-- ── STEP 2: Create helper functions ─────────────────────────────────

-- can_write_financials: financial operating writes — owner OR household_admin
-- Covers: weekly data, actuals, transfers, goals, model overrides, wishlist, custom tasks
CREATE OR REPLACE FUNCTION public.can_write_financials()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.app_users
    WHERE auth_user_id = auth.uid()
      AND active = true
      AND role IN ('owner', 'household_admin')
  );
END;
$$;

-- is_owner: platform/admin writes — owner only
-- Covers: app_users management, security settings, future destructive admin controls
-- Note: currently no RLS policies on app_users write path are in scope;
-- this function exists for future platform-admin gates.
CREATE OR REPLACE FUNCTION public.is_owner()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.app_users
    WHERE auth_user_id = auth.uid()
      AND active = true
      AND role = 'owner'
  );
END;
$$;

-- Drop is_editor_or_owner if it was created in a prior run — replaced by can_write_financials
DROP FUNCTION IF EXISTS public.is_editor_or_owner();

-- Verify functions:
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('is_allowed_user', 'can_write_financials', 'is_owner')
ORDER BY routine_name;
-- Expected: 3 rows


-- ── STEP 3: Update write policies ───────────────────────────────────
-- SELECT policies unchanged — all active users read all tables (is_allowed_user).
-- All write policies move to can_write_financials() for financial tables.

-- weekly_reconciliations
DROP POLICY IF EXISTS "weekly_reconciliations_insert_app_users" ON public.weekly_reconciliations;
CREATE POLICY "weekly_reconciliations_insert_app_users" ON public.weekly_reconciliations
  FOR INSERT TO authenticated WITH CHECK (public.can_write_financials());

DROP POLICY IF EXISTS "weekly_reconciliations_update_app_users" ON public.weekly_reconciliations;
CREATE POLICY "weekly_reconciliations_update_app_users" ON public.weekly_reconciliations
  FOR UPDATE TO authenticated
  USING (public.can_write_financials()) WITH CHECK (public.can_write_financials());

-- weekly_tasks
DROP POLICY IF EXISTS "weekly_tasks_insert_app_users" ON public.weekly_tasks;
CREATE POLICY "weekly_tasks_insert_app_users" ON public.weekly_tasks
  FOR INSERT TO authenticated WITH CHECK (public.can_write_financials());

DROP POLICY IF EXISTS "weekly_tasks_update_app_users" ON public.weekly_tasks;
CREATE POLICY "weekly_tasks_update_app_users" ON public.weekly_tasks
  FOR UPDATE TO authenticated
  USING (public.can_write_financials()) WITH CHECK (public.can_write_financials());

-- weekly_notes
DROP POLICY IF EXISTS "weekly_notes_insert_app_users" ON public.weekly_notes;
CREATE POLICY "weekly_notes_insert_app_users" ON public.weekly_notes
  FOR INSERT TO authenticated WITH CHECK (public.can_write_financials());

DROP POLICY IF EXISTS "weekly_notes_update_app_users" ON public.weekly_notes;
CREATE POLICY "weekly_notes_update_app_users" ON public.weekly_notes
  FOR UPDATE TO authenticated
  USING (public.can_write_financials()) WITH CHECK (public.can_write_financials());

-- model_week_overrides (household_admin gets Edit Week access)
DROP POLICY IF EXISTS "model_week_overrides_insert_app_users" ON public.model_week_overrides;
CREATE POLICY "model_week_overrides_insert_app_users" ON public.model_week_overrides
  FOR INSERT TO authenticated WITH CHECK (public.can_write_financials());

DROP POLICY IF EXISTS "model_week_overrides_update_app_users" ON public.model_week_overrides;
CREATE POLICY "model_week_overrides_update_app_users" ON public.model_week_overrides
  FOR UPDATE TO authenticated
  USING (public.can_write_financials()) WITH CHECK (public.can_write_financials());

DROP POLICY IF EXISTS "model_week_overrides_delete_app_users" ON public.model_week_overrides;
CREATE POLICY "model_week_overrides_delete_app_users" ON public.model_week_overrides
  FOR DELETE TO authenticated USING (public.can_write_financials());

-- goals: row-qualified split
-- Policy A (financial): can_write_financials() for all rows EXCEPT anthropic_key
-- Policy B (owner):     is_owner() for ALL rows (including anthropic_key) — OR semantics combine them
-- Net effect:
--   household_admin can write any goals row where key != 'anthropic_key'
--   household_admin CANNOT insert, update, or delete the anthropic_key row (neither policy passes)
--   owner can write any goals row
--   WITH CHECK on UPDATE prevents renaming a row TO anthropic_key (new row value also checked)

DROP POLICY IF EXISTS "goals_insert_app_users" ON public.goals;
DROP POLICY IF EXISTS "goals_financial_insert" ON public.goals;
DROP POLICY IF EXISTS "goals_owner_insert" ON public.goals;

CREATE POLICY "goals_financial_insert" ON public.goals
  FOR INSERT TO authenticated
  WITH CHECK (public.can_write_financials() AND key != 'anthropic_key');

CREATE POLICY "goals_owner_insert" ON public.goals
  FOR INSERT TO authenticated
  WITH CHECK (public.is_owner());

DROP POLICY IF EXISTS "goals_update_app_users" ON public.goals;
DROP POLICY IF EXISTS "goals_financial_update" ON public.goals;
DROP POLICY IF EXISTS "goals_owner_update" ON public.goals;

CREATE POLICY "goals_financial_update" ON public.goals
  FOR UPDATE TO authenticated
  USING (public.can_write_financials() AND key != 'anthropic_key')
  WITH CHECK (public.can_write_financials() AND key != 'anthropic_key');

CREATE POLICY "goals_owner_update" ON public.goals
  FOR UPDATE TO authenticated
  USING (public.is_owner())
  WITH CHECK (public.is_owner());

DROP POLICY IF EXISTS "goals_delete_app_users" ON public.goals;
DROP POLICY IF EXISTS "goals_financial_delete" ON public.goals;
DROP POLICY IF EXISTS "goals_owner_delete" ON public.goals;

CREATE POLICY "goals_financial_delete" ON public.goals
  FOR DELETE TO authenticated
  USING (public.can_write_financials() AND key != 'anthropic_key');

CREATE POLICY "goals_owner_delete" ON public.goals
  FOR DELETE TO authenticated
  USING (public.is_owner());

-- wishlist_items
DROP POLICY IF EXISTS "wishlist_items_insert_app_users" ON public.wishlist_items;
CREATE POLICY "wishlist_items_insert_app_users" ON public.wishlist_items
  FOR INSERT TO authenticated WITH CHECK (public.can_write_financials());

DROP POLICY IF EXISTS "wishlist_items_update_app_users" ON public.wishlist_items;
CREATE POLICY "wishlist_items_update_app_users" ON public.wishlist_items
  FOR UPDATE TO authenticated
  USING (public.can_write_financials()) WITH CHECK (public.can_write_financials());

DROP POLICY IF EXISTS "wishlist_items_delete_app_users" ON public.wishlist_items;
CREATE POLICY "wishlist_items_delete_app_users" ON public.wishlist_items
  FOR DELETE TO authenticated USING (public.can_write_financials());

-- custom_tasks
DROP POLICY IF EXISTS "custom_tasks_insert_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_insert_app_users" ON public.custom_tasks
  FOR INSERT TO authenticated WITH CHECK (public.can_write_financials());

DROP POLICY IF EXISTS "custom_tasks_update_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_update_app_users" ON public.custom_tasks
  FOR UPDATE TO authenticated
  USING (public.can_write_financials()) WITH CHECK (public.can_write_financials());

DROP POLICY IF EXISTS "custom_tasks_delete_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_delete_app_users" ON public.custom_tasks
  FOR DELETE TO authenticated USING (public.can_write_financials());


-- ── STEP 4: Verify policies ──────────────────────────────────────────
-- All write policies should now reference can_write_financials().
-- SELECT policies should still reference is_allowed_user().
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('weekly_reconciliations','weekly_tasks','weekly_notes',
                    'model_week_overrides','goals','wishlist_items','custom_tasks')
ORDER BY tablename, cmd;


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK SQL — run this to revert Phase 5A if anything breaks
-- ═══════════════════════════════════════════════════════════════════

/*
-- Restore weekly_reconciliations
DROP POLICY IF EXISTS "weekly_reconciliations_insert_app_users" ON public.weekly_reconciliations;
CREATE POLICY "weekly_reconciliations_insert_app_users" ON public.weekly_reconciliations
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
DROP POLICY IF EXISTS "weekly_reconciliations_update_app_users" ON public.weekly_reconciliations;
CREATE POLICY "weekly_reconciliations_update_app_users" ON public.weekly_reconciliations
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());

-- Restore weekly_tasks
DROP POLICY IF EXISTS "weekly_tasks_insert_app_users" ON public.weekly_tasks;
CREATE POLICY "weekly_tasks_insert_app_users" ON public.weekly_tasks
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
DROP POLICY IF EXISTS "weekly_tasks_update_app_users" ON public.weekly_tasks;
CREATE POLICY "weekly_tasks_update_app_users" ON public.weekly_tasks
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());

-- Restore weekly_notes
DROP POLICY IF EXISTS "weekly_notes_insert_app_users" ON public.weekly_notes;
CREATE POLICY "weekly_notes_insert_app_users" ON public.weekly_notes
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
DROP POLICY IF EXISTS "weekly_notes_update_app_users" ON public.weekly_notes;
CREATE POLICY "weekly_notes_update_app_users" ON public.weekly_notes
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());

-- Restore model_week_overrides
DROP POLICY IF EXISTS "model_week_overrides_insert_app_users" ON public.model_week_overrides;
CREATE POLICY "model_week_overrides_insert_app_users" ON public.model_week_overrides
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
DROP POLICY IF EXISTS "model_week_overrides_update_app_users" ON public.model_week_overrides;
CREATE POLICY "model_week_overrides_update_app_users" ON public.model_week_overrides
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
DROP POLICY IF EXISTS "model_week_overrides_delete_app_users" ON public.model_week_overrides;
CREATE POLICY "model_week_overrides_delete_app_users" ON public.model_week_overrides
  FOR DELETE TO authenticated USING (public.is_allowed_user());

-- Restore goals (drop all Phase 5A policies, restore original)
DROP POLICY IF EXISTS "goals_financial_insert" ON public.goals;
DROP POLICY IF EXISTS "goals_owner_insert" ON public.goals;
DROP POLICY IF EXISTS "goals_financial_update" ON public.goals;
DROP POLICY IF EXISTS "goals_owner_update" ON public.goals;
DROP POLICY IF EXISTS "goals_financial_delete" ON public.goals;
DROP POLICY IF EXISTS "goals_owner_delete" ON public.goals;
CREATE POLICY "goals_insert_app_users" ON public.goals
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
CREATE POLICY "goals_update_app_users" ON public.goals
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());

-- Restore wishlist_items
DROP POLICY IF EXISTS "wishlist_items_insert_app_users" ON public.wishlist_items;
CREATE POLICY "wishlist_items_insert_app_users" ON public.wishlist_items
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
DROP POLICY IF EXISTS "wishlist_items_update_app_users" ON public.wishlist_items;
CREATE POLICY "wishlist_items_update_app_users" ON public.wishlist_items
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
DROP POLICY IF EXISTS "wishlist_items_delete_app_users" ON public.wishlist_items;
CREATE POLICY "wishlist_items_delete_app_users" ON public.wishlist_items
  FOR DELETE TO authenticated USING (public.is_allowed_user());

-- Restore custom_tasks
DROP POLICY IF EXISTS "custom_tasks_insert_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_insert_app_users" ON public.custom_tasks
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
DROP POLICY IF EXISTS "custom_tasks_update_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_update_app_users" ON public.custom_tasks
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
DROP POLICY IF EXISTS "custom_tasks_delete_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_delete_app_users" ON public.custom_tasks
  FOR DELETE TO authenticated USING (public.is_allowed_user());

-- Drop new functions
DROP FUNCTION IF EXISTS public.can_write_financials();
DROP FUNCTION IF EXISTS public.is_owner();
*/
