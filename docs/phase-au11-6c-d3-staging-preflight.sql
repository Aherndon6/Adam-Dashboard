-- ============================================================================
-- AU-11 Step 6C-D3 — READ-ONLY PREFLIGHT  (Step 7A artifact; NOT executed here)
-- ----------------------------------------------------------------------------
-- STAGING ONLY. STRICTLY READ-ONLY: SELECT + catalog inspection only.
--   • No DO blocks, no BEGIN/COMMIT, no DDL, no DML, no temp tables.
--   • No application/business function is invoked. Frozen/lifecycle RPCs are
--     INSPECTED via the catalog (pg_get_functiondef/md5/pg_get_function_*),
--     NEVER CALLED. Only PostgreSQL catalog/introspection + aggregate/string
--     built-ins are used (see the read-only function classification in the
--     companion review doc, section "Read-only proof").
--   • Output hygiene: counts, booleans, catalog metadata, md5 digests, and
--     redacted labels only. NO auth_user_id, NO transaction ids, NO account
--     numbers/keys-as-values, NO raw transaction descriptions, NO household
--     balances/amounts, NO emails, NO raw auth identifiers, NO raw RLS
--     expressions, NO function bodies.
--   • Checksum method = the repository's established md5(pg_get_functiondef(oid))
--     (frozen baselines: save_reconciliation_with_commitments 1bfde751ac647c5e9a25ba168d08150c;
--      save_goal_funding_snapshots 154231b3f180349ec328f08ccbe77076).
--
-- EXECUTION GATES (both passes live in THIS file):
--   PASS 1 — CATALOG-SAFE DISCOVERY. Every statement reads ONLY pg_catalog /
--            information_schema (plus VALUES lists). NO PASS-1 statement directly
--            references an uncertain relation or column as a FROM/subquery target.
--            Cannot error on a missing relation/column.
--   PASS 2 — AGGREGATE DATA-QUALITY. Directly references real relations/columns.
--            AUTHORIZED ONLY AFTER the named PASS-1 prerequisites are confirmed.
--            Each PASS-2 query header lists its REQUIRED relations + columns and
--            the PASS-1 gate that must confirm them.
--
-- Purpose: gather the database FACTS the D3 composite-closeout design needs, so
--   policy decisions can be separated from database facts. No design is made here.
-- ============================================================================


-- ############################################################################
-- ############################  PASS 1 — DISCOVERY  ##########################
-- ############################################################################

-- ── PF0A — staging relation/column existence (catalog-only; gates PF0B) ──
SELECT 'P1_PF0A_staging_exists' AS section,
       (to_regclass('public.app_environment') IS NOT NULL) AS app_environment_exists,
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='app_environment' AND column_name='env') AS env_column_exists;
-- Gate: PF0B (PASS 2) is authorized ONLY IF app_environment_exists=true AND env_column_exists=true.

-- ── P1-REL — existence of every relation the preflight/design touches (no direct ref) ──
SELECT 'P1_REL_existence' AS section, r.relname,
       (to_regclass('public.'||r.relname) IS NOT NULL) AS relation_exists
FROM (VALUES ('app_environment'),('cash_commitments'),('discretionary_reservation_batches'),
             ('goal_registry'),('goal_funding_snapshots'),('weekly_reconciliations'),
             ('transactions'),('accounts')) AS r(relname)
ORDER BY r.relname;

-- ── P1-COL — existence + type of every UNCERTAIN column (VALUES LEFT JOIN catalog) ──
SELECT 'P1_COL_existence' AS section, v.table_name, v.column_name,
       (c.column_name IS NOT NULL) AS column_exists, c.data_type
FROM (VALUES
        ('goal_registry','reservable'),
        ('weekly_reconciliations','chk'),
        ('cash_commitments','status'),
        ('cash_commitments','commitment_source'),
        ('cash_commitments','cleared_date'),
        ('cash_commitments','reflected_model_week'),
        ('cash_commitments','resolved_model_week'),
        ('transactions','account_key'),
        ('transactions','amount'),
        ('transactions','transaction_date'),
        ('transactions','posted_date'),
        ('transactions','cleared'),
        ('transactions','reconciled'),
        ('transactions','transfer_pair_id'),
        ('accounts','key')
     ) AS v(table_name, column_name)
LEFT JOIN information_schema.columns c
       ON c.table_schema='public' AND c.table_name=v.table_name AND c.column_name=v.column_name
ORDER BY v.table_name, v.column_name;

-- ── A1 — FROZEN WRAPPER: save_weekly_closeout_with_snapshots full identity (inspect, never invoke) ──
--   Expanded per Step-7A review: identity args, result, proretset, allargtypes, argmodes, argnames,
--   overload count, security/owner/config/ACLs, md5. No body printed.
SELECT 'A1_frozen_wrapper' AS section,
       n.nspname                                              AS schema_name,
       p.proname                                              AS function_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid)   AS identity_arguments,
       pg_catalog.oidvectortypes(p.proargtypes)               AS in_arg_types,
       pg_catalog.pg_get_function_result(p.oid)               AS function_result,
       pg_catalog.format_type(p.prorettype, NULL)             AS return_type,
       p.proretset                                            AS returns_set,
       p.proallargtypes                                       AS all_arg_type_oids,
       p.proargmodes                                          AS arg_modes,
       p.proargnames                                          AS arg_names,
       p.prokind                                              AS prokind,
       p.provolatile                                          AS volatility,
       p.prosecdef                                            AS security_definer,
       pg_catalog.pg_get_userbyid(p.proowner)                 AS owner_role,
       p.proconfig                                            AS proconfig_search_path,
       pg_catalog.has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
       count(*) OVER (PARTITION BY p.proname)                 AS overload_count,
       md5(pg_catalog.pg_get_functiondef(p.oid))              AS body_md5
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'save_weekly_closeout_with_snapshots'
ORDER BY identity_arguments;

-- ── A2 — related frozen RPCs (same expanded fields) + pinned-baseline boolean ──
SELECT 'A2_frozen_related' AS section,
       p.proname                                              AS function_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid)   AS identity_arguments,
       pg_catalog.pg_get_function_result(p.oid)               AS function_result,
       p.proretset                                            AS returns_set,
       p.proargmodes                                          AS arg_modes,
       p.proargnames                                          AS arg_names,
       p.prosecdef                                            AS security_definer,
       pg_catalog.pg_get_userbyid(p.proowner)                 AS owner_role,
       p.proconfig                                            AS proconfig_search_path,
       pg_catalog.has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
       count(*) OVER (PARTITION BY p.proname)                 AS overload_count,
       md5(pg_catalog.pg_get_functiondef(p.oid))              AS body_md5,
       CASE p.proname
         WHEN 'save_reconciliation_with_commitments' THEN (md5(pg_catalog.pg_get_functiondef(p.oid)) = '1bfde751ac647c5e9a25ba168d08150c')
         WHEN 'save_goal_funding_snapshots'          THEN (md5(pg_catalog.pg_get_functiondef(p.oid)) = '154231b3f180349ec328f08ccbe77076')
         ELSE NULL   -- repair_commitments_for_week: signature-authoritative only, no pinned md5 baseline
       END                                                    AS matches_pinned_baseline
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('save_reconciliation_with_commitments','save_goal_funding_snapshots','repair_commitments_for_week')
ORDER BY p.proname, identity_arguments;

-- ── B1 — cash_commitments column metadata (catalog only) ──
SELECT 'B1_cc_columns' AS section,
       c.column_name, c.data_type, c.is_nullable, c.column_default, c.is_generated, c.identity_generation
FROM information_schema.columns c
WHERE c.table_schema='public' AND c.table_name='cash_commitments'
  AND c.column_name IN ('status','reservation_batch_id','goal_id','destination_account_ref',
                        'bank_reference','bank_submitted_at','cleared_date','reflected_model_week',
                        'resolved_model_week','resolution_type','resolved_at','resolved_by',
                        'commitment_class','commitment_source','origin_model_week','expected_item_id',
                        'amount_cents','model_year','source_account','updated_at')
ORDER BY c.ordinal_position;

-- ── B2 — presence booleans for the exact clear-transition columns §F step 10 writes ──
SELECT 'B2_clear_cols_present' AS section,
       bool_or(column_name='cleared_date')         AS has_cleared_date,
       bool_or(column_name='reflected_model_week') AS has_reflected_model_week,
       bool_or(column_name='resolved_model_week')  AS has_resolved_model_week,
       bool_or(column_name='resolution_type')      AS has_resolution_type,
       bool_or(column_name='resolved_at')          AS has_resolved_at,
       bool_or(column_name='resolved_by')          AS has_resolved_by
FROM information_schema.columns
WHERE table_schema='public' AND table_name='cash_commitments';

-- ── B3 — ALL CHECK/UNIQUE/FK constraint definitions on the two AU-11 tables (schema text) ──
SELECT 'B3_constraints' AS section,
       cl.relname AS table_name, con.conname AS constraint_name, con.contype AS contype,
       pg_catalog.pg_get_constraintdef(con.oid) AS definition
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class cl ON cl.oid=con.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid=cl.relnamespace
WHERE n.nspname='public' AND cl.relname IN ('cash_commitments','discretionary_reservation_batches')
ORDER BY cl.relname, con.contype, con.conname;

-- ── B4 — status CHECK TEXTUAL HEURISTIC (mentions, NOT proof of admissibility) ──
--   A value's presence in the definition text is a heuristic only; actual admissibility
--   is unresolved unless logically unambiguous from the full def or later proved by an
--   approved non-persistent probe. Columns are named definition_mentions_* accordingly.
WITH status_checks AS (
  SELECT pg_catalog.pg_get_constraintdef(con.oid) AS def
  FROM pg_catalog.pg_constraint con
  JOIN pg_catalog.pg_class cl ON cl.oid=con.conrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=cl.relnamespace
  WHERE n.nspname='public' AND cl.relname='cash_commitments' AND con.contype='c'
    AND pg_catalog.pg_get_constraintdef(con.oid) ILIKE '%status%'
)
SELECT 'B4_status_check' AS section,
       (SELECT count(*) FROM status_checks)                                        AS status_check_count,
       (SELECT string_agg(def, ' || ') FROM status_checks)                         AS status_check_defs,
       COALESCE((SELECT bool_or(def LIKE '%''scheduled''%')   FROM status_checks), NULL) AS definition_mentions_scheduled,
       COALESCE((SELECT bool_or(def LIKE '%''initiated''%')   FROM status_checks), NULL) AS definition_mentions_initiated,
       COALESCE((SELECT bool_or(def LIKE '%''bank_pending''%')FROM status_checks), NULL) AS definition_mentions_bank_pending,
       COALESCE((SELECT bool_or(def LIKE '%''stale_review''%')FROM status_checks), NULL) AS definition_mentions_stale_review,
       COALESCE((SELECT bool_or(def LIKE '%''voided''%')      FROM status_checks), NULL) AS definition_mentions_voided,
       COALESCE((SELECT bool_or(def LIKE '%''cleared''%')     FROM status_checks), NULL) AS definition_mentions_cleared;
-- status_check_count=0 ⇒ no DB CHECK on status (DB-level unconstrained). A definition_mentions_* = false
-- with count>0 is a STRONG (not absolute) hint a widening is needed; confirm from the full def or a probe.

-- ── B5 — batch/commitment indexes incl. one-active-batch partial predicate (schema text) ──
SELECT 'B5_indexes' AS section,
       t.relname AS table_name, i.relname AS index_name,
       pg_catalog.pg_get_indexdef(i.oid) AS index_def,
       pg_catalog.pg_get_expr(x.indpred, x.indrelid) AS partial_predicate
FROM pg_catalog.pg_index x
JOIN pg_catalog.pg_class i ON i.oid=x.indexrelid
JOIN pg_catalog.pg_class t ON t.oid=x.indrelid
JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
WHERE n.nspname='public' AND t.relname IN ('cash_commitments','discretionary_reservation_batches')
ORDER BY t.relname, i.relname;

-- ── C1 — transactions column metadata (catalog only; NO row data) ──
SELECT 'C1_transactions_columns' AS section,
       c.column_name, c.data_type, c.is_nullable
FROM information_schema.columns c
WHERE c.table_schema='public' AND c.table_name='transactions'
ORDER BY c.ordinal_position;

-- ── C2 — transactions indexes relevant to deterministic matching (schema text) ──
SELECT 'C2_transactions_indexes' AS section,
       i.relname AS index_name, x.indisunique AS is_unique,
       pg_catalog.pg_get_indexdef(i.oid) AS index_def
FROM pg_catalog.pg_index x
JOIN pg_catalog.pg_class i ON i.oid=x.indexrelid
JOIN pg_catalog.pg_class t ON t.oid=x.indrelid
JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
WHERE n.nspname='public' AND t.relname='transactions'
ORDER BY i.relname;

-- ── C3M1 — accounts column metadata (catalog only) ──
SELECT 'C3M1_accounts_columns' AS section,
       c.column_name, c.data_type, c.is_nullable
FROM information_schema.columns c
WHERE c.table_schema='public' AND c.table_name='accounts'
ORDER BY c.ordinal_position;

-- ── C3M2 — accounts CANDIDATE-FIELD presence (key / active / status / type / institution / ledger-role) ──
SELECT 'C3M2_accounts_candidate_fields' AS section, v.candidate_role, v.column_name,
       (c.column_name IS NOT NULL) AS column_exists, c.data_type
FROM (VALUES
        ('key',          'key'),      ('active','active'),   ('active','is_active'),
        ('status',       'status'),   ('type','type'),       ('type','kind'),
        ('type',         'account_type'), ('institution','institution'), ('institution','bank'),
        ('ledger_role',  'ledger_role'), ('ledger_role','role'), ('display','name')
     ) AS v(candidate_role, column_name)
LEFT JOIN information_schema.columns c
       ON c.table_schema='public' AND c.table_name='accounts' AND c.column_name=v.column_name
ORDER BY v.candidate_role, v.column_name;

-- ── C3M3 — accounts constraints + indexes (schema text; establishes key uniqueness posture) ──
SELECT 'C3M3_accounts_constraints' AS section,
       con.conname AS constraint_name, con.contype AS contype,
       pg_catalog.pg_get_constraintdef(con.oid) AS definition
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class cl ON cl.oid=con.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid=cl.relnamespace
WHERE n.nspname='public' AND cl.relname='accounts'
ORDER BY con.contype, con.conname;

-- ── C3M4 — how transactions.account_key relates to accounts (FK discovery; schema text) ──
SELECT 'C3M4_txn_account_fk' AS section,
       con.conname AS constraint_name,
       pg_catalog.pg_get_constraintdef(con.oid) AS definition,
       confrel.relname AS references_table
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class cl ON cl.oid=con.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid=cl.relnamespace
LEFT JOIN pg_catalog.pg_class confrel ON confrel.oid=con.confrelid
WHERE n.nspname='public' AND cl.relname='transactions' AND con.contype='f'
  AND pg_catalog.pg_get_constraintdef(con.oid) ILIKE '%account%'
ORDER BY con.conname;

-- ── E1 — candidate calendar / week-mapping tables (metadata only) ──
SELECT 'E1_calendar_tables' AS section, table_schema, table_name
FROM information_schema.tables
WHERE table_schema='public'
  AND (table_name ILIKE '%week%' OR table_name ILIKE '%calendar%' OR table_name ILIKE '%model_week%')
ORDER BY table_name;

-- ── E2 — candidate week->date resolver functions (names only; not invoked) ──
SELECT 'E2_week_date_functions' AS section,
       p.proname AS function_name, pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND (p.proname ILIKE '%week%date%' OR p.proname ILIKE '%date%week%'
       OR p.proname ILIKE '%calweek%' OR p.proname ILIKE '%week_span%' OR p.proname ILIKE '%week_window%')
ORDER BY p.proname;

-- ── E3 — date/week columns on reconciliation + snapshot tables (metadata only) ──
SELECT 'E3_recon_snapshot_date_cols' AS section,
       c.table_name, c.column_name, c.data_type, c.is_nullable
FROM information_schema.columns c
WHERE c.table_schema='public' AND c.table_name IN ('weekly_reconciliations','goal_funding_snapshots')
  AND (c.data_type IN ('date','timestamp with time zone','timestamp without time zone')
       OR c.column_name ILIKE '%date%' OR c.column_name ILIKE '%week%')
ORDER BY c.table_name, c.ordinal_position;

-- ── F1 — authz helper functions: identity + md5 (no body) + EXECUTE posture ──
SELECT 'F1_authz_helpers' AS section,
       p.proname AS function_name, pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       p.prosecdef AS security_definer, pg_catalog.pg_get_userbyid(p.proowner) AS owner_role,
       p.proconfig AS proconfig_search_path,
       pg_catalog.has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
       md5(pg_catalog.pg_get_functiondef(p.oid)) AS body_md5
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('can_write_financials','is_owner')
ORDER BY p.proname, identity_arguments;

-- ── F2 — RLS policies SANITIZED: metadata + presence booleans + md5 + helper-reference booleans ──
--   RAW qual / with_check are NEVER emitted (they may contain identity-bearing literals). We emit
--   only their md5 and booleans indicating which known helper each expression references.
SELECT 'F2_rls_policies' AS section,
       schemaname, tablename, policyname, cmd, roles,
       (qual IS NOT NULL)                                                                    AS qual_present,
       (with_check IS NOT NULL)                                                              AS with_check_present,
       md5(coalesce(qual,''))                                                                AS qual_md5,
       md5(coalesce(with_check,''))                                                          AS with_check_md5,
       (position('can_write_financials' in coalesce(qual,'')||' '||coalesce(with_check,'')) > 0) AS refs_can_write_financials,
       (position('is_owner'             in coalesce(qual,'')||' '||coalesce(with_check,'')) > 0) AS refs_is_owner,
       (position('auth.uid'             in coalesce(qual,'')||' '||coalesce(with_check,'')) > 0) AS refs_auth_uid,
       (position('auth.role'            in coalesce(qual,'')||' '||coalesce(with_check,'')) > 0) AS refs_auth_role
FROM pg_catalog.pg_policies
WHERE schemaname='public'
  AND tablename IN ('cash_commitments','discretionary_reservation_batches','transactions',
                    'weekly_reconciliations','goal_funding_snapshots')
ORDER BY tablename, policyname;

-- ── F3 — table RLS enablement + write-grant posture (booleans/roles only) ──
SELECT 'F3_table_rls' AS section,
       c.relname AS table_name, c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced,
       pg_catalog.has_table_privilege('authenticated', c.oid, 'INSERT') AS authenticated_insert,
       pg_catalog.has_table_privilege('authenticated', c.oid, 'UPDATE') AS authenticated_update,
       pg_catalog.has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated_select
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname IN ('cash_commitments','discretionary_reservation_batches','transactions',
                    'weekly_reconciliations','goal_funding_snapshots')
ORDER BY c.relname;

-- ── G1 — LOCK CONTRACT (partial evidence). Establishes: advisory-lock fn used, exact advisory-key
--         expression (a single extracted expression, NOT a body), and FOR UPDATE count. Positional
--         offsets are SUPPORTING evidence only; full lock ORDER is NOT established here (see review). ──
SELECT 'G1_lock_contract' AS section,
       p.proname AS function_name,
       (position('pg_advisory_xact_lock' in pg_catalog.pg_get_functiondef(p.oid)) > 0)              AS uses_advisory_xact_lock,
       substring(pg_catalog.pg_get_functiondef(p.oid) from 'pg_advisory_xact_lock[^;]*')            AS advisory_lock_expr,
       (length(lower(pg_catalog.pg_get_functiondef(p.oid)))
        - length(replace(lower(pg_catalog.pg_get_functiondef(p.oid)), 'for update', '')))
        / length('for update')                                                                      AS for_update_count,
       position('pg_advisory_xact_lock' in lower(pg_catalog.pg_get_functiondef(p.oid)))             AS advisory_lock_offset,      -- supporting
       position('for update'            in lower(pg_catalog.pg_get_functiondef(p.oid)))             AS first_for_update_offset,   -- supporting
       position('update public.'        in lower(pg_catalog.pg_get_functiondef(p.oid)))             AS first_update_stmt_offset,  -- supporting
       position('insert into public.'   in lower(pg_catalog.pg_get_functiondef(p.oid)))             AS first_insert_stmt_offset   -- supporting
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('create_discretionary_goal_reservation_v1',
                    'mark_discretionary_goal_reservation_initiated_v1',
                    'void_scheduled_discretionary_goal_reservation_v1')
ORDER BY p.proname;

-- ── I1 — UNIQUE indexes across the reservation/register/recon/snapshot tables (schema text) ──
SELECT 'I1_uniqueness' AS section,
       t.relname AS table_name, i.relname AS index_name, x.indisunique AS is_unique,
       pg_catalog.pg_get_indexdef(i.oid) AS index_def
FROM pg_catalog.pg_index x
JOIN pg_catalog.pg_class i ON i.oid=x.indexrelid
JOIN pg_catalog.pg_class t ON t.oid=x.indrelid
JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
WHERE n.nspname='public'
  AND t.relname IN ('cash_commitments','discretionary_reservation_batches','transactions',
                    'weekly_reconciliations','goal_funding_snapshots')
  AND x.indisunique = true
ORDER BY t.relname, i.relname;

-- ── I2 — weekly_reconciliations PK/UNIQUE (one-recon-per-week idempotency anchor) ──
SELECT 'I2_recon_key' AS section,
       con.conname AS constraint_name, con.contype AS contype,
       pg_catalog.pg_get_constraintdef(con.oid) AS definition
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class cl ON cl.oid=con.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid=cl.relnamespace
WHERE n.nspname='public' AND cl.relname='weekly_reconciliations' AND con.contype IN ('p','u')
ORDER BY con.contype, con.conname;

-- ── I3 — targeted idempotency-field uniqueness posture (heuristic on unique-index defs) ──
--   Whether each retry-relevant field appears in ANY unique index. Heuristic (text match on indexdef);
--   confirm exact key membership from I1/C2 defs. Covers transfer_pair_id, bank_reference, batch_digest,
--   expected_item_id, and the (batch,goal) uniqueness.
WITH uidx AS (
  SELECT t.relname AS table_name, pg_catalog.pg_get_indexdef(i.oid) AS def
  FROM pg_catalog.pg_index x
  JOIN pg_catalog.pg_class i ON i.oid=x.indexrelid
  JOIN pg_catalog.pg_class t ON t.oid=x.indrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
  WHERE n.nspname='public' AND x.indisunique=true
    AND t.relname IN ('cash_commitments','discretionary_reservation_batches','transactions')
)
SELECT 'I3_idempotency_fields' AS section,
       bool_or(def ILIKE '%transfer_pair_id%')                        AS transfer_pair_id_in_unique_index,
       bool_or(def ILIKE '%bank_reference%')                          AS bank_reference_in_unique_index,
       bool_or(def ILIKE '%batch_digest%')                            AS batch_digest_in_unique_index,
       bool_or(def ILIKE '%expected_item_id%')                        AS expected_item_id_in_unique_index,
       bool_or(def ILIKE '%reservation_batch_id%' AND def ILIKE '%goal_id%') AS batch_goal_pair_in_unique_index
FROM uidx;


-- ############################################################################
-- ########  PASS 2 — AGGREGATE DATA-QUALITY (authorized only after PASS 1)  ##
-- ############################################################################
-- Each query below directly references real relations/columns and is AUTHORIZED
-- ONLY AFTER its listed PASS-1 prerequisite confirms every required object exists.

-- ── PF0B — staging row certification ──
--   REQUIRES: relation public.app_environment; column env.  GATE: P1_PF0A must show
--   app_environment_exists=true AND env_column_exists=true.
SELECT 'P2_PF0B_staging_cert' AS section,
       (SELECT count(*) FROM public.app_environment)                                       AS environment_rows,
       (SELECT count(*) FROM public.app_environment WHERE env='staging')                   AS staging_rows,
       (SELECT count(*) FROM public.app_environment WHERE env IS DISTINCT FROM 'staging')  AS non_staging_rows,
       (EXISTS (SELECT 1 FROM public.app_environment)
        AND NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging')) AS all_rows_are_staging;

-- ── D1 — Register data-quality aggregates (counts only; NO amounts/rows) ──
--   REQUIRES: relation public.transactions; columns posted_date, cleared, reconciled, transfer_pair_id.
--   GATE: P1_REL_existence.transactions=true AND P1_COL_existence confirms those four columns.
SELECT 'P2_D1_txn_quality' AS section,
       (SELECT count(*) FROM public.transactions)                                                       AS total_rows,
       (SELECT count(*) FROM public.transactions WHERE posted_date IS NOT NULL)                         AS posted_date_populated,
       (SELECT count(*) FROM public.transactions WHERE cleared = true)                                  AS cleared_true,
       (SELECT count(*) FROM public.transactions WHERE reconciled = true)                               AS reconciled_true,
       (SELECT count(*) FROM public.transactions WHERE transfer_pair_id IS NOT NULL)                    AS transfer_pair_populated,
       (SELECT count(*) FROM public.transactions WHERE cleared = true AND posted_date IS NOT NULL)      AS cleared_and_posted,
       (SELECT count(*) FROM public.transactions WHERE posted_date IS NOT NULL AND cleared IS DISTINCT FROM true) AS posted_but_not_cleared,
       (SELECT count(*) FROM public.transactions WHERE cleared = true AND posted_date IS NULL)          AS cleared_but_no_posted_date;

-- ── C3AGG — account-key candidate mapping (aggregate counts only; NO key value emitted) ──
--   REQUIRES: relation public.accounts + column key; relation public.transactions + column account_key.
--   GATE: P1_REL_existence(accounts,transactions)=true AND P1_COL_existence(accounts.key, transactions.account_key)=true.
--   NOTE: accounts_literal_key_match is LITERAL-KEY EQUALITY ONLY — it is NOT proof of the authoritative
--   source-account mapping (that is a policy selection informed by C3M2/C3M4 metadata). 0/1 count, no key value.
SELECT 'P2_C3AGG_account_key_candidates' AS section,
       (SELECT count(*) FROM public.accounts a WHERE a.key = 'truist_checking')  AS accounts_literal_key_match,
       (SELECT count(DISTINCT a.key) FROM public.accounts a)                      AS distinct_account_keys,
       (SELECT count(DISTINCT t.account_key) FROM public.transactions t)          AS distinct_txn_account_keys;

-- ── H1 — current staging residue (counts only) ──
--   REQUIRES: discretionary_reservation_batches(status); goal_registry(id, reservable);
--             goal_funding_snapshots(model_year, goal_id); weekly_reconciliations(chk).
--   GATE: P1_REL_existence + P1_COL_existence(goal_registry.reservable, weekly_reconciliations.chk)=true.
SELECT 'P2_H1_residue' AS section,
       (SELECT count(*) FROM public.discretionary_reservation_batches WHERE status='active')                 AS active_batches,
       (SELECT count(*) FROM public.discretionary_reservation_batches)                                       AS all_batches,
       (SELECT count(*) FROM public.goal_registry WHERE id LIKE 'd2fix_%')                                   AS fixture_goals,
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND goal_id LIKE 'd2fix_%') AS fixture_snapshots,
       (SELECT count(*) FROM public.weekly_reconciliations WHERE chk=3131.31)                                AS fixture_reconciliation_rows,
       (SELECT count(*) FROM public.goal_registry WHERE reservable=true AND id NOT LIKE 'd2fix_%')           AS implicit_nonfixture_reservable_goals;

-- ── H2 — au11_reservation commitments by EXPECTED state (explicit counts; no arbitrary status text) ──
--   REQUIRES: cash_commitments(commitment_source, status).  GATE: P1_COL_existence confirms both columns.
SELECT 'P2_H2_reservation_by_status' AS section,
       count(*) FILTER (WHERE status='scheduled')     AS scheduled,
       count(*) FILTER (WHERE status='initiated')     AS initiated,
       count(*) FILTER (WHERE status='bank_pending')  AS bank_pending,
       count(*) FILTER (WHERE status='stale_review')  AS stale_review,
       count(*) FILTER (WHERE status='cleared')       AS cleared,
       count(*) FILTER (WHERE status='voided')        AS voided,
       count(*) FILTER (WHERE status IS NULL)         AS null_status,
       count(*) FILTER (WHERE status IS NOT NULL
                          AND status NOT IN ('scheduled','initiated','bank_pending','stale_review','cleared','voided')) AS other_status
FROM public.cash_commitments
WHERE commitment_source = 'au11_reservation';

-- ============================================================================
-- END. PASS 1 is catalog-safe and always runnable. PASS 2 is authorized only
-- after PASS-1 prerequisites confirm every referenced relation/column exists.
-- No writes; no application/business RPC invoked. Interpret against the decision
-- matrix in docs/phase-au11-6c-d3-preflight-review-2026-07-27.md.
-- ============================================================================
