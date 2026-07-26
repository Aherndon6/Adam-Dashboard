-- ============================================================================
-- AU-11 Step 6C-D1 — STAGING preflight (READ-ONLY capture + legality gates)
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Run BEFORE the migration. Read-only (no DDL/DML). Executed by Adam.
-- Captures the exact live constraint names/definitions (do NOT assume July-7 export),
-- confirms staging identity, resolves U1/U4, and asserts the D1 legality conditions.
-- ============================================================================

-- ── HARD GUARD: abort the ENTIRE preflight unless this is staging (read-only; RAISE only, no DDL/DML) ──
DO $$
BEGIN
  IF to_regclass('public.app_environment') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env = 'staging') THEN
    RAISE EXCEPTION 'HARD STOP: public.app_environment env=staging not found — refusing to run the AU-11 6C-D1 preflight outside staging.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.app_environment WHERE env = 'production') THEN
    RAISE EXCEPTION 'HARD STOP: app_environment env=production present — this is NOT staging. Aborting.';
  END IF;
END $$;

-- ── Environment identity (must be staging) ──
SELECT 'ENV' AS check, env, set_at FROM public.app_environment;   -- expect env='staging' (cols: env, set_at)
SELECT 'ENV_NOT_PROD' AS check,
       CASE WHEN EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging')
            THEN 'PASS: staging sentinel present' ELSE 'FAIL: staging sentinel absent' END AS result;

-- ── Capture current cash_commitments CHECK constraints VERBATIM (names + defs) ──
SELECT 'CHECK_DEFS' AS capture, conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid='public.cash_commitments'::regclass AND contype='c'
ORDER BY conname;

-- ── Capture columns / indexes / FKs / RLS / grants / triggers / rowcount ──
SELECT 'COLUMNS' AS capture, column_name, data_type, is_nullable, column_default
FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' ORDER BY ordinal_position;
SELECT 'INDEXES' AS capture, indexname, indexdef FROM pg_indexes
WHERE schemaname='public' AND tablename='cash_commitments' ORDER BY indexname;
SELECT 'FKEYS' AS capture, conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid='public.cash_commitments'::regclass AND contype='f' ORDER BY conname;
SELECT 'RLS' AS capture, policyname, cmd, qual, with_check FROM pg_policies
WHERE schemaname='public' AND tablename='cash_commitments' ORDER BY policyname;
SELECT 'GRANTS' AS capture, grantee, privilege_type FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='cash_commitments' ORDER BY grantee, privilege_type;
SELECT 'TRIGGERS' AS capture, tgname FROM pg_trigger
WHERE tgrelid='public.cash_commitments'::regclass AND NOT tgisinternal ORDER BY tgname;
SELECT 'ROWCOUNT' AS capture, count(*) AS cash_commitments_rows FROM public.cash_commitments;

-- ── D1 legality gates ──
SELECT 'GATE_no_au11_rows' AS gate,
       CASE WHEN NOT EXISTS (SELECT 1 FROM public.cash_commitments WHERE commitment_class='discretionary_goal_transfer')
            THEN 'PASS' ELSE 'FAIL: reservation rows already exist' END AS result;
SELECT 'GATE_no_batch_table' AS gate,
       CASE WHEN to_regclass('public.discretionary_reservation_batches') IS NULL
            THEN 'PASS' ELSE 'FAIL: batch table already exists' END AS result;
SELECT 'GATE_no_d2_rpc' AS gate,
       CASE WHEN to_regprocedure('public.create_discretionary_goal_reservation_v1(int,int,text,text,date,jsonb)') IS NULL
            THEN 'PASS' ELSE 'FAIL: 6C-D2 RPC already present' END AS result;

-- ── U1: canonical Truist Checking accounts.key (Register evidence source) ──
-- accounts canonical cols (docs/phase-5d-1-migration.sql:42): key, label, account_type, lifecycle_status.
SELECT 'U1_checking_key' AS preflight, key, label, account_type, lifecycle_status
FROM public.accounts WHERE key='truist_checking';                -- expect exactly one row (account_type='checking')

-- ── U3 confirm: goal_registry relation + dest field present (label, not accounts.key) ──
SELECT 'U3_goal_registry' AS preflight,
       CASE WHEN to_regclass('public.goal_registry') IS NOT NULL THEN 'PASS: relation exists' ELSE 'FAIL' END AS result;
SELECT 'U3_dest_field' AS preflight, column_name, data_type
FROM information_schema.columns
WHERE table_schema='public' AND table_name='goal_registry' AND column_name IN ('dest','id','status','auto','stretch');
-- Confirm there is NO accounts.key-typed destination column (dest is a label):
SELECT 'U3_no_dest_key' AS preflight, count(*) AS dest_accountkey_cols
FROM information_schema.columns
WHERE table_schema='public' AND table_name='goal_registry' AND column_name IN ('dest_account_key','destination_account_key');

-- ── U4: is transactions.reconciled actually populated? (reserved for 5F per schema) ──
SELECT 'U4_reconciled_usage' AS preflight,
       count(*) FILTER (WHERE reconciled) AS reconciled_true,
       count(*) FILTER (WHERE cleared)    AS cleared_true,
       count(*) FILTER (WHERE posted_date IS NOT NULL) AS posted_date_set,
       count(*) AS total
FROM public.transactions;   -- if reconciled_true=0 -> rely on cleared+posted_date+date-span (as designed)

-- ── U2 note (no DB relation): model-week -> calendar-date span is APP-SIDE
-- (getCalWeek + WD spans in index.html). No DB week->date table exists; the
-- composite (6C-D3) must receive the week's date window as a parameter. Recorded
-- here as a 6C-D3 preflight item; NOT a D1 schema dependency.
SELECT 'U2_note' AS preflight,
       'model-week->date span is app-side (getCalWeek/WD); pass date window to the 6C-D3 composite' AS finding;
