-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-2 Preflight Checks
-- ═══════════════════════════════════════════════════════════════════════════
-- Run ALL checks before executing phase-5e-2-migration.sql.
-- Every check must return the documented expected value.
-- Stop and investigate any failure before proceeding.
--
-- Run as a single UNION ALL so the Supabase SQL editor returns all rows.
-- ─────────────────────────────────────────────────────────────────────────

SELECT * FROM (

  -- VP1: transactions table must exist (Phase 5E-1 must have run)
  SELECT 'VP1' AS check,
         'table_exists' AS item,
         EXISTS (
           SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = 'transactions'
         )::text AS expected_true,
         'true' AS expected

  UNION ALL

  -- VP2: user_id column default is auth.uid()
  -- Confirms Phase 5E-1 migration applied correctly.
  -- Uses ILIKE because Postgres may render as 'auth.uid()' or '(auth.uid())'.
  SELECT 'VP2',
         'user_id_default',
         (column_default ILIKE '%auth.uid%')::text,
         'true'
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name   = 'transactions'
     AND column_name  = 'user_id'

  UNION ALL

  -- VP3: write policy count = 0
  -- Confirms financial_writer_insert/update/delete do not already exist.
  -- A non-zero result means 5E-2 migration was already run (partially or fully).
  -- Stop and investigate before retrying.
  SELECT 'VP3',
         'write_policy_count_zero',
         (COUNT(*) = 0)::text,
         'true'
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename  = 'transactions'
     AND policyname IN ('financial_writer_insert','financial_writer_update','financial_writer_delete')

  UNION ALL

  -- VP4: can_write_financials() function must exist
  -- This is the predicate used in all three write policies.
  -- Source inspection confirms it covers owner + household_admin.
  SELECT 'VP4',
         'can_write_financials_exists',
         EXISTS (
           SELECT 1 FROM pg_proc
            WHERE proname = 'can_write_financials'
              AND pronamespace = 'public'::regnamespace
         )::text,
         'true'

  UNION ALL

  -- VP5: allow_read policy still present (regression guard)
  -- 5E-1 SELECT policy must not have been dropped.
  SELECT 'VP5',
         'allow_read_present',
         EXISTS (
           SELECT 1 FROM pg_policies
            WHERE schemaname = 'public'
              AND tablename  = 'transactions'
              AND policyname = 'allow_read'
              AND cmd        = 'SELECT'
         )::text,
         'true'

) checks
ORDER BY check;

-- ─────────────────────────────────────────────────────────────────────────
-- Additional: inspect can_write_financials() source to confirm predicate
-- Expected: prosrc contains 'household_admin' and 'owner'
-- ─────────────────────────────────────────────────────────────────────────
SELECT proname, prosrc
  FROM pg_proc
 WHERE proname = 'can_write_financials'
   AND pronamespace = 'public'::regnamespace;
