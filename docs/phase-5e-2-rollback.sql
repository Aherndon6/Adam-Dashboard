-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-2 Rollback
-- ═══════════════════════════════════════════════════════════════════════════
-- Reverts Phase 5E-2 write policies and grants.
-- Does NOT affect the transactions table structure or data.
-- Does NOT affect the allow_read (SELECT) policy from Phase 5E-1.
-- Does NOT affect the GRANT SELECT from Phase 5E-1.
--
-- After running this rollback:
--   - authenticated users retain read access (allow_read + GRANT SELECT)
--   - authenticated users lose INSERT, UPDATE, DELETE access
--   - Existing transaction rows are preserved unchanged
--   - App UI becomes read-only again (same as Phase 5E-1 state)
--
-- App-layer rollback (no code push required):
--   Set showTransactionLedger=false in console.
--   This removes all write UI immediately without a code deployment.
-- ─────────────────────────────────────────────────────────────────────────

-- ── 1. Revoke write grants ─────────────────────────────────────────────────
-- Column-level REVOKE must mirror column-level grants exactly.

REVOKE INSERT (account_key, transaction_date, payee, memo, amount, category_key, cleared, source)
  ON public.transactions FROM authenticated;

REVOKE UPDATE (transaction_date, payee, memo, amount, category_key, cleared)
  ON public.transactions FROM authenticated;

-- DELETE was table-level
REVOKE DELETE ON public.transactions FROM authenticated;

-- ── 2. Drop write policies ─────────────────────────────────────────────────
DROP POLICY IF EXISTS "financial_writer_insert" ON public.transactions;
DROP POLICY IF EXISTS "financial_writer_update" ON public.transactions;
DROP POLICY IF EXISTS "financial_writer_delete" ON public.transactions;

-- ── 3. Verify rollback ─────────────────────────────────────────────────────
-- Run after rollback to confirm clean state.

SELECT * FROM (

  -- Write policies gone
  SELECT 'RB1' AS check, 'write_policies_removed',
         (COUNT(*) = 0)::text AS result, 'true' AS expected
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'transactions'
     AND policyname IN ('financial_writer_insert','financial_writer_update','financial_writer_delete')

  UNION ALL

  -- allow_read still present
  SELECT 'RB2', 'allow_read_intact',
         (COUNT(*) = 1)::text, 'true'
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'transactions'
     AND policyname = 'allow_read'

  UNION ALL

  -- No INSERT grant columns remain
  SELECT 'RB3', 'insert_grant_removed',
         (COUNT(*) = 0)::text, 'true'
    FROM information_schema.role_column_grants
   WHERE table_schema = 'public' AND table_name = 'transactions'
     AND grantee = 'authenticated' AND privilege_type = 'INSERT'

  UNION ALL

  -- No UPDATE grant columns remain
  SELECT 'RB4', 'update_grant_removed',
         (COUNT(*) = 0)::text, 'true'
    FROM information_schema.role_column_grants
   WHERE table_schema = 'public' AND table_name = 'transactions'
     AND grantee = 'authenticated' AND privilege_type = 'UPDATE'

  UNION ALL

  -- No DELETE table grant remains
  SELECT 'RB5', 'delete_grant_removed',
         (COUNT(*) = 0)::text, 'true'
    FROM information_schema.role_table_grants
   WHERE table_schema = 'public' AND table_name = 'transactions'
     AND grantee = 'authenticated' AND privilege_type = 'DELETE'

) checks
ORDER BY check;
