-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-1 Rollback
-- ═══════════════════════════════════════════════════════════════════════════
--
-- SAFE WINDOW: before Phase 5F is applied and before any data is entered
-- that would be materially lost. Once real transaction data exists, dropping
-- this table is a data-loss event, not just a schema rollback.
--
-- ROLLBACK BECOMES UNSAFE OR DESTRUCTIVE AFTER ANY OF:
--   1. Phase 5F creates reconciliation session/state tables that FK into transactions
--   2. Any phase links budget_transactions to transactions
--   3. Any import pipeline creates FK dependencies on transactions
--   4. Real transaction data has been entered that you do not want to lose
--
-- If any of the above apply, DO NOT run this file until it has been extended
-- to handle those dependencies, and confirm with Adam before executing.
-- ─────────────────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS public.transactions CASCADE;

-- Verify rollback complete
SELECT 'ROLLBACK_CHECK' AS check,
       NOT EXISTS (
         SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = 'transactions'
       ) AS expected_true;
