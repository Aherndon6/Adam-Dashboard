-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — STAGING E1 VALIDATION (READ ONLY). Authored, NOT executed.
-- Run AFTER phase-5g-1d-e1-staging-migration.sql. Proves the staging E1 table + RPC match the
-- exact deployed PRODUCTION E1 contract (identity), the RLS/grants are correct, the pre-existing
-- objects are untouched, and no production fingerprint can pass. Fill the pinned values LOCAL.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_rpc     regprocedure := to_regprocedure('public.save_goal_funding_snapshots(INT,INT,JSONB)');
  v_recon   regprocedure := to_regprocedure('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)');
  -- IDENTITY PROOF: paste the PRODUCTION E1 RPC md5 (captured read-only per the preflight header):
  c_prod_e1_rpc_md5    TEXT := '<<PASTE production save_goal_funding_snapshots md5(pg_get_functiondef) LOCAL>>';
  -- pre-migration baselines from the preflight (paste LOCAL to prove pre-existing objects unchanged):
  c_baseline_recon_md5 TEXT := '<<PASTE preflight baseline-recon-rpc-md5 LOCAL>>';
  c_baseline_reg_md5   TEXT := '<<PASTE preflight baseline-goal-registry LOCAL>>';
  c_baseline_appenv_md5 TEXT := '<<PASTE preflight baseline-app-environment md5 LOCAL>>';
  v_sysid BIGINT; v_cnt INT; v_grants INT; v_def TEXT; v_cur TEXT;
  v_idxdef TEXT; v_trgdef TEXT; v_roles TEXT[]; v_cmd TEXT; v_qual TEXT; v_wc TEXT;
  v_appenv_total INT; v_appenv_staging INT; v_condef TEXT;
BEGIN
  -- environment: EXACT staging fingerprint — sysid + app_environment exactly one row, env='staging'
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'V: production system_identifier — staging validation only'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'V: app_environment absent — not the approved staging env'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = 7656985631720456337 AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'V: not the approved staging fingerprint (sysid=%, appenv total=%, staging=%)', v_sysid, v_appenv_total, v_appenv_staging; END IF;

  -- (1) table + RPC exist with the exact contract
  IF to_regclass('public.goal_funding_snapshots') IS NULL THEN RAISE EXCEPTION 'V: goal_funding_snapshots missing'; END IF;
  IF v_rpc IS NULL THEN RAISE EXCEPTION 'V: save_goal_funding_snapshots(INT,INT,JSONB) missing'; END IF;

  -- (2) IDENTITY: staging RPC definition md5 == the pinned production E1 md5 (mechanical, no manual divergence)
  IF md5(pg_get_functiondef(v_rpc)) IS DISTINCT FROM c_prod_e1_rpc_md5 THEN
    RAISE EXCEPTION 'V: staging E1 RPC definition does NOT match production (identity FAIL)'; END IF;

  -- (3) RPC security posture + EXACT function-EXECUTE grants
  SELECT p.prosecdef::text INTO v_cur FROM pg_proc p WHERE p.oid = v_rpc::oid;
  IF v_cur <> 'true' THEN RAISE EXCEPTION 'V: E1 RPC not SECURITY DEFINER'; END IF;
  IF NOT (SELECT proconfig @> ARRAY['search_path=public'] FROM pg_proc WHERE oid = v_rpc::oid) THEN
    RAISE EXCEPTION 'V: E1 RPC search_path not pinned to public'; END IF;
  IF NOT has_function_privilege('authenticated', v_rpc, 'EXECUTE') THEN RAISE EXCEPTION 'V: E1 RPC authenticated EXECUTE missing (E1 contract)'; END IF;
  IF has_function_privilege('anon', v_rpc, 'EXECUTE') THEN RAISE EXCEPTION 'V: E1 RPC anon must not have EXECUTE'; END IF;
  -- PUBLIC has no function EXECUTE (proacl '=...X' entry absent; anon/authenticated inherit PUBLIC)
  IF EXISTS (SELECT 1 FROM pg_proc p, unnest(COALESCE(p.proacl,'{}'::aclitem[])) a
             WHERE p.oid = v_rpc::oid AND (a::text LIKE '=%X%')) THEN
    RAISE EXCEPTION 'V: PUBLIC has EXECUTE on the E1 RPC (must be none)'; END IF;

  -- (4) table structural contract — EXACT definitions (pg_get_constraintdef / pg_constraint), not name-only
  -- PRIMARY KEY (id)
  SELECT pg_get_constraintdef(oid) INTO v_condef FROM pg_constraint
    WHERE conrelid='public.goal_funding_snapshots'::regclass AND contype='p';
  IF v_condef IS DISTINCT FROM 'PRIMARY KEY (id)' THEN RAISE EXCEPTION 'V: primary key not PRIMARY KEY (id): %', v_condef; END IF;
  -- uq_gfs_year_week_goal = UNIQUE (model_year, week_num, goal_id)
  SELECT pg_get_constraintdef(oid) INTO v_condef FROM pg_constraint
    WHERE conrelid='public.goal_funding_snapshots'::regclass AND conname='uq_gfs_year_week_goal';
  IF v_condef IS DISTINCT FROM 'UNIQUE (model_year, week_num, goal_id)' THEN RAISE EXCEPTION 'V: uq_gfs_year_week_goal wrong: %', v_condef; END IF;
  -- chk_gfs_funded_nonneg enforces funded_amount >= 0
  SELECT pg_get_constraintdef(oid) INTO v_condef FROM pg_constraint
    WHERE conrelid='public.goal_funding_snapshots'::regclass AND conname='chk_gfs_funded_nonneg';
  IF v_condef IS NULL OR position('funded_amount >= ' in v_condef)=0 OR position('0' in v_condef)=0 THEN
    RAISE EXCEPTION 'V: chk_gfs_funded_nonneg wrong: %', v_condef; END IF;
  -- chk_gfs_source permits exactly opening_anchor / reconciliation / correction
  SELECT pg_get_constraintdef(oid) INTO v_condef FROM pg_constraint
    WHERE conrelid='public.goal_funding_snapshots'::regclass AND conname='chk_gfs_source';
  IF v_condef IS NULL OR position('source' in v_condef)=0 OR position('opening_anchor' in v_condef)=0
     OR position('reconciliation' in v_condef)=0 OR position('correction' in v_condef)=0 THEN
    RAISE EXCEPTION 'V: chk_gfs_source wrong: %', v_condef; END IF;
  -- chk_gfs_week_range enforces week_num between 1 and 31
  SELECT pg_get_constraintdef(oid) INTO v_condef FROM pg_constraint
    WHERE conrelid='public.goal_funding_snapshots'::regclass AND conname='chk_gfs_week_range';
  IF v_condef IS NULL OR position('week_num >= 1' in v_condef)=0 OR position('week_num <= 31' in v_condef)=0 THEN
    RAISE EXCEPTION 'V: chk_gfs_week_range wrong: %', v_condef; END IF;
  -- FK: goal_id -> public.goal_registry(id), ON UPDATE CASCADE, ON DELETE RESTRICT (default RESTRICT is
  -- omitted from constraintdef text, so assert the action codes directly: confupdtype='c', confdeltype='r')
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.goal_funding_snapshots'::regclass AND contype='f'
      AND confrelid='public.goal_registry'::regclass
      AND confupdtype='c' AND confdeltype='r'
      AND conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='public.goal_funding_snapshots'::regclass AND attname='goal_id')]
      AND confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='public.goal_registry'::regclass AND attname='id')]) THEN
    RAISE EXCEPTION 'V: goal_id FK to goal_registry(id) with ON UPDATE CASCADE / ON DELETE RESTRICT not found'; END IF;
  -- core column types + NOT NULL
  IF (SELECT format_type(atttypid,atttypmod)||'|'||attnotnull FROM pg_attribute WHERE attrelid='public.goal_funding_snapshots'::regclass AND attname='model_year')    IS DISTINCT FROM 'integer|true'       THEN RAISE EXCEPTION 'V: model_year not integer NOT NULL'; END IF;
  IF (SELECT format_type(atttypid,atttypmod)||'|'||attnotnull FROM pg_attribute WHERE attrelid='public.goal_funding_snapshots'::regclass AND attname='week_num')      IS DISTINCT FROM 'integer|true'       THEN RAISE EXCEPTION 'V: week_num not integer NOT NULL'; END IF;
  IF (SELECT format_type(atttypid,atttypmod)||'|'||attnotnull FROM pg_attribute WHERE attrelid='public.goal_funding_snapshots'::regclass AND attname='goal_id')       IS DISTINCT FROM 'text|true'          THEN RAISE EXCEPTION 'V: goal_id not text NOT NULL'; END IF;
  IF (SELECT format_type(atttypid,atttypmod)||'|'||attnotnull FROM pg_attribute WHERE attrelid='public.goal_funding_snapshots'::regclass AND attname='funded_amount') IS DISTINCT FROM 'numeric(12,2)|true' THEN RAISE EXCEPTION 'V: funded_amount not numeric(12,2) NOT NULL'; END IF;
  IF (SELECT format_type(atttypid,atttypmod)||'|'||attnotnull FROM pg_attribute WHERE attrelid='public.goal_funding_snapshots'::regclass AND attname='source')        IS DISTINCT FROM 'text|true'          THEN RAISE EXCEPTION 'V: source not text NOT NULL'; END IF;
  -- RLS enabled
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.goal_funding_snapshots'::regclass) THEN
    RAISE EXCEPTION 'V: RLS not enabled'; END IF;

  -- (4b) POLICY definitions — exactly 3, exact names/roles/commands/expressions
  SELECT count(*) INTO v_cnt FROM pg_policies WHERE schemaname='public' AND tablename='goal_funding_snapshots';
  IF v_cnt <> 3 THEN RAISE EXCEPTION 'V: expected exactly 3 policies, found %', v_cnt; END IF;
  -- allow_read: SELECT / authenticated / USING is_allowed_user()
  SELECT roles, cmd, qual, with_check INTO v_roles, v_cmd, v_qual, v_wc FROM pg_policies
    WHERE schemaname='public' AND tablename='goal_funding_snapshots' AND policyname='allow_read';
  IF v_cmd IS DISTINCT FROM 'SELECT' OR v_roles IS DISTINCT FROM ARRAY['authenticated']
     OR position('is_allowed_user()' in COALESCE(v_qual,'')) = 0 THEN
    RAISE EXCEPTION 'V: allow_read policy definition wrong (cmd=%, roles=%, qual=%)', v_cmd, v_roles, v_qual; END IF;
  -- financial_writer_insert: INSERT / authenticated / WITH CHECK can_write_financials()
  SELECT roles, cmd, qual, with_check INTO v_roles, v_cmd, v_qual, v_wc FROM pg_policies
    WHERE schemaname='public' AND tablename='goal_funding_snapshots' AND policyname='financial_writer_insert';
  IF v_cmd IS DISTINCT FROM 'INSERT' OR v_roles IS DISTINCT FROM ARRAY['authenticated']
     OR position('can_write_financials()' in COALESCE(v_wc,'')) = 0 THEN
    RAISE EXCEPTION 'V: financial_writer_insert policy definition wrong (cmd=%, roles=%, with_check=%)', v_cmd, v_roles, v_wc; END IF;
  -- financial_writer_update: UPDATE / authenticated / USING and WITH CHECK can_write_financials()
  SELECT roles, cmd, qual, with_check INTO v_roles, v_cmd, v_qual, v_wc FROM pg_policies
    WHERE schemaname='public' AND tablename='goal_funding_snapshots' AND policyname='financial_writer_update';
  IF v_cmd IS DISTINCT FROM 'UPDATE' OR v_roles IS DISTINCT FROM ARRAY['authenticated']
     OR position('can_write_financials()' in COALESCE(v_qual,'')) = 0
     OR position('can_write_financials()' in COALESCE(v_wc,'')) = 0 THEN
    RAISE EXCEPTION 'V: financial_writer_update policy definition wrong (cmd=%, roles=%, using=%, with_check=%)', v_cmd, v_roles, v_qual, v_wc; END IF;

  -- (4c) INDEX definition — idx_gfs_year_week on public.goal_funding_snapshots (model_year, week_num) in order
  SELECT pg_get_indexdef(i.indexrelid) INTO v_idxdef FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
    WHERE c.relname='idx_gfs_year_week' AND i.indrelid='public.goal_funding_snapshots'::regclass;
  IF v_idxdef IS NULL THEN RAISE EXCEPTION 'V: idx_gfs_year_week missing on goal_funding_snapshots'; END IF;
  IF position('(model_year, week_num)' in v_idxdef) = 0 THEN
    RAISE EXCEPTION 'V: idx_gfs_year_week columns/order wrong: %', v_idxdef; END IF;

  -- (4d) TRIGGER definition — BEFORE UPDATE, FOR EACH ROW, invokes fn_set_updated_at, enabled
  SELECT pg_get_triggerdef(t.oid) INTO v_trgdef FROM pg_trigger t
    WHERE t.tgrelid='public.goal_funding_snapshots'::regclass AND t.tgname='set_goal_funding_snapshots_updated_at';
  IF v_trgdef IS NULL THEN RAISE EXCEPTION 'V: updated_at trigger missing'; END IF;
  IF position('BEFORE UPDATE' in v_trgdef) = 0 OR position('FOR EACH ROW' in v_trgdef) = 0
     OR position('fn_set_updated_at()' in v_trgdef) = 0 THEN
    RAISE EXCEPTION 'V: updated_at trigger definition wrong: %', v_trgdef; END IF;
  IF (SELECT tgenabled FROM pg_trigger WHERE tgrelid='public.goal_funding_snapshots'::regclass AND tgname='set_goal_funding_snapshots_updated_at') = 'D' THEN
    RAISE EXCEPTION 'V: updated_at trigger is DISABLED'; END IF;

  -- (5) EXACT table-privilege matrix
  --   authenticated: SELECT/INSERT/UPDATE = yes; DELETE/TRUNCATE/REFERENCES/TRIGGER = no
  IF NOT (has_table_privilege('authenticated','public.goal_funding_snapshots','SELECT')
      AND has_table_privilege('authenticated','public.goal_funding_snapshots','INSERT')
      AND has_table_privilege('authenticated','public.goal_funding_snapshots','UPDATE')) THEN
    RAISE EXCEPTION 'V: authenticated must have SELECT+INSERT+UPDATE'; END IF;
  IF has_table_privilege('authenticated','public.goal_funding_snapshots','DELETE')
     OR has_table_privilege('authenticated','public.goal_funding_snapshots','TRUNCATE')
     OR has_table_privilege('authenticated','public.goal_funding_snapshots','REFERENCES')
     OR has_table_privilege('authenticated','public.goal_funding_snapshots','TRIGGER') THEN
    RAISE EXCEPTION 'V: authenticated must NOT have DELETE/TRUNCATE/REFERENCES/TRIGGER'; END IF;
  --   anon: none of the seven
  IF has_table_privilege('anon','public.goal_funding_snapshots','SELECT')
     OR has_table_privilege('anon','public.goal_funding_snapshots','INSERT')
     OR has_table_privilege('anon','public.goal_funding_snapshots','UPDATE')
     OR has_table_privilege('anon','public.goal_funding_snapshots','DELETE')
     OR has_table_privilege('anon','public.goal_funding_snapshots','TRUNCATE')
     OR has_table_privilege('anon','public.goal_funding_snapshots','REFERENCES')
     OR has_table_privilege('anon','public.goal_funding_snapshots','TRIGGER') THEN
    RAISE EXCEPTION 'V: anon must have NO table privilege'; END IF;
  --   PUBLIC: no table privileges (relacl carries no '=' grant; anon/authenticated inherit PUBLIC)
  IF EXISTS (SELECT 1 FROM pg_class c, unnest(COALESCE(c.relacl,'{}'::aclitem[])) a
             WHERE c.oid='public.goal_funding_snapshots'::regclass AND a::text LIKE '=%') THEN
    RAISE EXCEPTION 'V: PUBLIC has a table privilege (must be none)'; END IF;

  -- (6) empty table (migration is schema-only)
  IF (SELECT count(*) FROM public.goal_funding_snapshots) <> 0 THEN RAISE EXCEPTION 'V: table must be empty post-migration'; END IF;

  -- (7) pre-existing objects UNCHANGED vs the preflight baselines
  IF md5(pg_get_functiondef(v_recon)) IS DISTINCT FROM c_baseline_recon_md5 THEN RAISE EXCEPTION 'V: reconciliation RPC changed'; END IF;
  IF (SELECT md5(string_agg(id||'|'||coalesce(target::text,'')||'|'||coalesce(auto::text,''), ',' ORDER BY id)) FROM public.goal_registry) IS DISTINCT FROM c_baseline_reg_md5 THEN
    RAISE EXCEPTION 'V: goal_registry changed'; END IF;
  IF (SELECT md5(coalesce(string_agg(env, ',' ORDER BY env),'')) FROM public.app_environment) IS DISTINCT FROM c_baseline_appenv_md5 THEN
    RAISE EXCEPTION 'V: app_environment changed'; END IF;

  RAISE NOTICE 'STAGING E1 VALIDATION PASS: table+RPC match production E1 (identity md5 equal); RLS/grants correct; empty; reconciliation RPC / goal_registry / app_environment unchanged.';
END $$;

COMMIT;
