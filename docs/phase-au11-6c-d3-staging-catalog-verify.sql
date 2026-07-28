-- ============================================================================
-- AU-11 Step 6C-D3 — STAGING CATALOG-VERIFY  [7D-B DRAFT]  (READ-ONLY, single result set)
-- STAGING ONLY. NOT executed by Claude. Asserts D-9 schema objects + composite RPC catalog identity/security,
-- plus D1-shape-unchanged and frozen-wrapper integrity. No mutation.
-- HARDENING: ONE result set (UNION ALL) so every check is visible in the Supabase editor; the composite RPC and
--   frozen RPCs are resolved by EXACT signature via to_regprocedure (not schema+name); the D3 attribution CHECK
--   and the D1 shape CHECK are compared against PINNED normalized canonical definitions (not substring / not
--   convalidated-only); index checks are schema/table-qualified. Each row carries PASS/FAIL + a final CHK_OVERALL.
-- ============================================================================
WITH
rpc AS (SELECT to_regprocedure('public.close_week_with_reservations_v1(integer,integer,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,integer,jsonb)') AS oid),
col AS (SELECT data_type, is_nullable, column_default FROM information_schema.columns
        WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id'),
fk AS (SELECT c.confupdtype, c.confdeltype, c.condeferrable, c.convalidated, (c.confrelid='public.transactions'::regclass) AS ref_ok
       FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
       WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='fk_au11_cleared_txn' AND c.contype='f'),
d3chk AS (SELECT c.convalidated,
            lower(regexp_replace(regexp_replace(pg_get_constraintdef(c.oid),'::text','','g'),'[[:space:]()]','','g')) AS def
          FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
          WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_cleared_txn_attribution' AND c.contype='c'),
idx AS (SELECT pg_get_indexdef(i.indexrelid) AS def, i.indisunique
        FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace
        WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i'),
d1 AS (SELECT c.convalidated,
          lower(regexp_replace(regexp_replace(pg_get_constraintdef(c.oid),'::text','','g'),'[()[:space:]]','','g')) AS def
        FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
        WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_reservation_shape' AND c.contype='c'),
prpc AS (SELECT p.prosecdef, pg_get_userbyid(p.proowner) AS owner, p.provolatile, p.proparallel,
                pg_catalog.format_type(p.prorettype,NULL) AS ret,
                COALESCE(array_to_string(p.proconfig,','),'NONE') AS cfg,
                EXISTS(SELECT 1 FROM unnest(p.proconfig) k WHERE split_part(k,'=',1)='search_path' AND btrim(split_part(k,'=',2),'"')='') AS empty_sp,
                pg_catalog.oidvectortypes(p.proargtypes) AS args
         FROM pg_proc p WHERE p.oid=(SELECT oid FROM rpc)),
grants AS (SELECT
             (SELECT CASE WHEN oid IS NOT NULL THEN has_function_privilege('anon', oid, 'EXECUTE') END FROM rpc) AS anon_exec,
             (SELECT CASE WHEN oid IS NOT NULL THEN has_function_privilege('authenticated', oid, 'EXECUTE') END FROM rpc) AS auth_exec),
fz AS (SELECT
    (CASE WHEN to_regprocedure('public.save_weekly_closeout_with_snapshots(int,int,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,int)') IS NOT NULL
          THEN md5(pg_get_functiondef(to_regprocedure('public.save_weekly_closeout_with_snapshots(int,int,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,int)'))) ELSE 'ABSENT' END) AS wrapper_md5,
    (CASE WHEN to_regprocedure('public.save_reconciliation_with_commitments(int,int,numeric,numeric,numeric,numeric,numeric,text,timestamptz,jsonb,jsonb)') IS NOT NULL
          THEN md5(pg_get_functiondef(to_regprocedure('public.save_reconciliation_with_commitments(int,int,numeric,numeric,numeric,numeric,numeric,text,timestamptz,jsonb,jsonb)'))) ELSE 'ABSENT' END) AS recon_md5,
    (CASE WHEN to_regprocedure('public.save_goal_funding_snapshots(int,int,jsonb)') IS NOT NULL
          THEN md5(pg_get_functiondef(to_regprocedure('public.save_goal_funding_snapshots(int,int,jsonb)'))) ELSE 'ABSENT' END) AS snapshot_md5),
r AS (  -- per-check pass booleans (canons pinned below)
  SELECT
    (SELECT count(*)=1 AND bool_and(data_type='uuid' AND is_nullable='YES' AND column_default IS NULL) FROM col) AS col_ok,
    (SELECT count(*)=1 AND bool_and(confupdtype='c' AND confdeltype='r' AND condeferrable=false AND convalidated AND ref_ok) FROM fk) AS fk_ok,
    (SELECT count(*)=1 AND bool_and(convalidated AND def = $d3$checkcasewhencommitment_source='au11_reservation'andstatus='cleared'thencleared_transaction_idisnotnullelsecleared_transaction_idisnullend$d3$) FROM d3chk) AS check_ok,
    (SELECT count(*)=1 AND bool_and(indisunique AND def ILIKE '%(cleared_transaction_id)%' AND def ILIKE '%WHERE (cleared_transaction_id IS NOT NULL)%') FROM idx) AS idx_ok,
    (SELECT count(*)=1 AND bool_and(convalidated AND def = $d1$checkcommitment_class='discretionary_goal_transfer'andcommitment_source='au11_reservation'andreservation_batch_idisnotnullandgoal_idisnotnullanddestination_account_refisnotnullandrequired_or_discretionary='discretionary_deployment'andsource_account='truist_checking'orcommitment_class<>'discretionary_goal_transfer'andcommitment_source<>'au11_reservation'andreservation_batch_idisnullandgoal_idisnullanddestination_account_refisnullandbank_referenceisnullandbank_submitted_atisnull$d1$) FROM d1) AS d1_ok,
    ((SELECT oid FROM rpc) IS NOT NULL
       AND (SELECT count(*)=1 AND bool_and(prosecdef AND owner='postgres' AND empty_sp AND provolatile='v' AND proparallel='u' AND ret='jsonb') FROM prpc)) AS rpc_ok,
    (SELECT NOT anon_exec AND NOT auth_exec FROM grants) AS grants_ok,
    (SELECT wrapper_md5='e2a112b376dc32c43e1615e4a4abf24a' AND recon_md5='1bfde751ac647c5e9a25ba168d08150c' AND snapshot_md5='154231b3f180349ec328f08ccbe77076' FROM fz) AS frozen_ok )
SELECT check_name, detail, result FROM (
  SELECT 1 AS ord, 'CHK_column' AS check_name, (SELECT to_jsonb(col) FROM col) AS detail, (SELECT CASE WHEN col_ok THEN 'PASS' ELSE 'FAIL' END FROM r) AS result
  UNION ALL SELECT 2, 'CHK_fk', (SELECT to_jsonb(fk) FROM fk), (SELECT CASE WHEN fk_ok THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 3, 'CHK_check_def', (SELECT to_jsonb(d3chk) FROM d3chk), (SELECT CASE WHEN check_ok THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 4, 'CHK_index', (SELECT to_jsonb(idx) FROM idx), (SELECT CASE WHEN idx_ok THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 5, 'CHK_d1_shape_def', (SELECT to_jsonb(d1) FROM d1), (SELECT CASE WHEN d1_ok THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 6, 'CHK_rpc', (SELECT to_jsonb(prpc) FROM prpc), (SELECT CASE WHEN rpc_ok THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 7, 'CHK_rpc_grants_inert', (SELECT to_jsonb(grants) FROM grants), (SELECT CASE WHEN grants_ok THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 8, 'CHK_frozen_md5', (SELECT to_jsonb(fz) FROM fz), (SELECT CASE WHEN frozen_ok THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 9, 'CHK_OVERALL',
        jsonb_build_object('staging', (EXISTS(SELECT 1 FROM public.app_environment) AND NOT EXISTS(SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging'))),
        (SELECT CASE WHEN (EXISTS(SELECT 1 FROM public.app_environment) AND NOT EXISTS(SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging'))
                      AND col_ok AND fk_ok AND check_ok AND idx_ok AND d1_ok AND rpc_ok AND grants_ok AND frozen_ok
                     THEN 'PASS' ELSE 'FAIL' END FROM r)
) q ORDER BY ord;
-- ============================================================================
