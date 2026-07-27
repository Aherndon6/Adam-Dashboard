-- ============================================================================
-- AU-11 Step 6C-D2 — additive Goal Registry metadata: `reservable`
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Executed by Adam. Per owner ruling R8/F6: reservation eligibility
-- must be driven by CENTRALIZED Goal Registry metadata, not an embedded approved-
-- goal list in the RPC, and NOT inferred from ambiguous existing fields (`auto`,
-- `stretch`). The registry has an explicit *state* field (`status`) and a
-- destination (`dest`) but NO explicit *reservation-eligibility* field — so the
-- smallest additive change is a single boolean column.
--
--   reservable BOOLEAN NOT NULL DEFAULT false
--
-- Additive and backward-compatible: default false => NOTHING becomes reservable
-- until an owner explicitly opts a goal in (fail-closed). The app reads
-- goal_registry via anon SELECT and maps known columns only (mapGoalFromDB
-- ignores unknown columns) + has a hardcoded fallback, so this column is inert
-- to the client. No index needed (small table). No data backfill.
--
-- The create() RPC eligibility predicate (see phase-au11-6c-d2-staging-rpcs.sql):
--     status IN ('planned','funding')                 -- eligible/active goal state
--     AND COALESCE(reservable,false) = true           -- explicit reservation eligibility (THIS column)
--     AND dest IS NOT NULL AND btrim(dest) <> ''       -- valid destination account (registry dest)
-- ============================================================================
BEGIN;

DO $$ BEGIN
  IF to_regclass('public.app_environment') IS NULL OR NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') THEN
    RAISE EXCEPTION 'HARD STOP: not staging — refusing goal_registry.reservable add.'; END IF;
  IF to_regclass('public.goal_registry') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry missing.'; END IF;
END $$;

ALTER TABLE public.goal_registry
  ADD COLUMN IF NOT EXISTS reservable BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.goal_registry.reservable IS
  'AU-11 (6C-D2): explicit opt-in for discretionary goal-funding reservations. '
  'Default false (fail-closed). Set true only for goals an owner has approved as '
  'reservable. Consumed by create_discretionary_goal_reservation_v1 together with '
  'status IN (planned,funding) and a non-empty dest.';

COMMIT;
-- Verify: SELECT column_name,data_type,is_nullable,column_default
--           FROM information_schema.columns
--          WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable';
-- Expect: boolean / NO / false.
-- Rollback: see phase-au11-6c-d2-staging-rollback.sql (DROP COLUMN reservable) — legal only when no
-- create() RPC depends on it (i.e., after the RPCs are dropped) and no reservation batches exist.
