-- ============================================================================
-- AU-11 Step 6C-D3 — I4a DURABLE POST-CHECK  (READ-ONLY, single result ROW)
-- ----------------------------------------------------------------------------
-- STAGING ONLY. NOT executed by Claude. Run IMMEDIATELY AFTER I4a schema apply
-- (phase-au11-6c-d3-staging-schema.sql) and BEFORE I4b composite-RPC apply.
-- Returns durable catalog evidence via a SELECT result set (NOT a RAISE NOTICE,
-- which the Supabase editor suppresses). Every check is schema/table-qualified.
-- Proves the four D-9 objects are present, validated, and correctly shaped, and
-- that the target is staging. No mutation.
-- Expected single row: col_uuid_yes_null=1, fk_valid=1, chk_valid=1, idx=1, result=PASS.
-- ============================================================================
WITH pc AS (
  SELECT
    -- cleared_transaction_id column exists as uuid / nullable / no default
    (SELECT count(*) FROM information_schema.columns
       WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id'
         AND data_type='uuid' AND is_nullable='YES' AND column_default IS NULL) AS col_uuid_yes_null,
    -- fk_au11_cleared_txn present AND validated
    (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
       WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='fk_au11_cleared_txn' AND c.contype='f' AND c.convalidated) AS fk_valid,
    -- chk_au11_cleared_txn_attribution present AND validated
    (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
       WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_cleared_txn_attribution' AND c.contype='c' AND c.convalidated) AS chk_valid,
    -- uix_au11_cleared_txn present (as an index relation)
    (SELECT count(*) FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace
       WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i') AS idx,
    -- staging gate (fail-closed: empty table OR any non-'staging' row ⇒ not staging)
    (EXISTS(SELECT 1 FROM public.app_environment) AND NOT EXISTS(SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging')) AS staging_ok
)
SELECT col_uuid_yes_null, fk_valid, chk_valid, idx,
       CASE WHEN staging_ok AND col_uuid_yes_null=1 AND fk_valid=1 AND chk_valid=1 AND idx=1
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM pc;
-- ============================================================================
