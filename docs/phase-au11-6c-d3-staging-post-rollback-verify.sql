-- ============================================================================
-- AU-11 Step 6C-D3 — STAGING POST-ROLLBACK VERIFY  [7D-B DRAFT]  (READ-ONLY, single result set)
-- STAGING ONLY. NOT executed by Claude. Run AFTER the D3 rollback. Proves D3 objects are ABSENT and D1/D2 +
-- frozen surfaces are INTACT + unchanged. No mutation.
-- EVIDENCE DESIGN: ONE result set (UNION ALL) so every check is visible in the Supabase editor (which shows only
--   the last result set); every object check is SCHEMA/TABLE-QUALIFIED; the D1 shape CHECK is definition-verified
--   against the D2-proven canon; D2 RPCs are checked by EXACT signature; frozen RPCs by pinned md5. Each row
--   carries a PASS/FAIL, plus a final PRV_OVERALL row.
-- ============================================================================
WITH
d3 AS (  -- D3 objects ABSENT (schema/table-qualified)
  SELECT
    (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id') AS col,
    (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname IN ('fk_au11_cleared_txn','chk_au11_cleared_txn_attribution')) AS cons,
    (SELECT count(*) FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i') AS idx,
    -- EXACT-signature absence (not schema+name-only, which would false-fail on a legitimate overload):
    (to_regprocedure('public.close_week_with_reservations_v1(integer,integer,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,integer,jsonb)') IS NULL) AS rpc_absent ),
d1def AS (  -- D1 shape CHECK normalized def (qualified, validated)
  SELECT lower(regexp_replace(regexp_replace(pg_get_constraintdef(c.oid), '::text', '', 'g'), '[()[:space:]]', '', 'g')) AS def
  FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
  WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_reservation_shape' AND c.contype='c' AND c.convalidated ),
d1 AS (  -- D1 surfaces INTACT (schema/table-qualified)
  SELECT
    (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments'
       AND column_name IN ('reservation_batch_id','goal_id','destination_account_ref','bank_reference','bank_submitted_at')) AS d1_cols,   -- 5
    (SELECT count(*) FROM d1def) AS shape_valid,   -- 1
    ((SELECT def FROM d1def) = $canon$checkcommitment_class='discretionary_goal_transfer'andcommitment_source='au11_reservation'andreservation_batch_idisnotnullandgoal_idisnotnullanddestination_account_refisnotnullandrequired_or_discretionary='discretionary_deployment'andsource_account='truist_checking'orcommitment_class<>'discretionary_goal_transfer'andcommitment_source<>'au11_reservation'andreservation_batch_idisnullandgoal_idisnullanddestination_account_refisnullandbank_referenceisnullandbank_submitted_atisnull$canon$) AS def_ok,
    (SELECT count(*) FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='discretionary_reservation_batches' AND ic.relname='uix_one_active_batch' AND ic.relkind='i') AS uix_active_batch,   -- 1
    (SELECT count(*) FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_batch_goal' AND ic.relkind='i') AS uix_batch_goal ),   -- 1
d2 AS (  -- D2 lifecycle RPCs present by EXACT signature
  SELECT
    (to_regprocedure('public.create_discretionary_goal_reservation_v1(integer, integer, text, text, date, jsonb, integer)') IS NOT NULL) AS d2_create,
    (to_regprocedure('public.mark_discretionary_goal_reservation_initiated_v1(integer, text, text[], text, timestamp with time zone, date)') IS NOT NULL) AS d2_mark,
    (to_regprocedure('public.void_scheduled_discretionary_goal_reservation_v1(integer, text, text[], text)') IS NOT NULL) AS d2_void ),
fz AS (  -- frozen RPC md5s (exact signatures; ABSENT sentinel avoids NULL-input error)
  SELECT
    (CASE WHEN to_regprocedure('public.save_weekly_closeout_with_snapshots(int,int,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,int)') IS NOT NULL
          THEN md5(pg_get_functiondef(to_regprocedure('public.save_weekly_closeout_with_snapshots(int,int,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,int)'))) ELSE 'ABSENT' END) AS wrapper_md5,
    (CASE WHEN to_regprocedure('public.save_reconciliation_with_commitments(int,int,numeric,numeric,numeric,numeric,numeric,text,timestamptz,jsonb,jsonb)') IS NOT NULL
          THEN md5(pg_get_functiondef(to_regprocedure('public.save_reconciliation_with_commitments(int,int,numeric,numeric,numeric,numeric,numeric,text,timestamptz,jsonb,jsonb)'))) ELSE 'ABSENT' END) AS recon_md5,
    (CASE WHEN to_regprocedure('public.save_goal_funding_snapshots(int,int,jsonb)') IS NOT NULL
          THEN md5(pg_get_functiondef(to_regprocedure('public.save_goal_funding_snapshots(int,int,jsonb)'))) ELSE 'ABSENT' END) AS snapshot_md5 )
SELECT 'PRV_d3_absent' AS check_name,
       (SELECT to_jsonb(d3) FROM d3) AS detail,
       (SELECT CASE WHEN col=0 AND cons=0 AND idx=0 AND rpc_absent THEN 'PASS' ELSE 'FAIL' END FROM d3) AS result
UNION ALL SELECT 'PRV_d1_intact',
       (SELECT to_jsonb(d1) FROM d1),
       (SELECT CASE WHEN d1_cols=5 AND shape_valid=1 AND def_ok AND uix_active_batch=1 AND uix_batch_goal=1 THEN 'PASS' ELSE 'FAIL' END FROM d1)
UNION ALL SELECT 'PRV_d2_signatures_present',   -- exact-signature PRESENCE (not body/grant/security integrity)
       (SELECT to_jsonb(d2) FROM d2),
       (SELECT CASE WHEN d2_create AND d2_mark AND d2_void THEN 'PASS' ELSE 'FAIL' END FROM d2)
UNION ALL SELECT 'PRV_frozen_intact',
       (SELECT to_jsonb(fz) FROM fz),
       (SELECT CASE WHEN wrapper_md5='e2a112b376dc32c43e1615e4a4abf24a' AND recon_md5='1bfde751ac647c5e9a25ba168d08150c' AND snapshot_md5='154231b3f180349ec328f08ccbe77076' THEN 'PASS' ELSE 'FAIL' END FROM fz)
UNION ALL SELECT 'PRV_OVERALL',
       jsonb_build_object('staging', (EXISTS(SELECT 1 FROM public.app_environment) AND NOT EXISTS(SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging'))),
       (SELECT CASE WHEN
            (EXISTS(SELECT 1 FROM public.app_environment) AND NOT EXISTS(SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging'))
            AND (SELECT col=0 AND cons=0 AND idx=0 AND rpc_absent FROM d3)
            AND (SELECT d1_cols=5 AND shape_valid=1 AND def_ok AND uix_active_batch=1 AND uix_batch_goal=1 FROM d1)
            AND (SELECT d2_create AND d2_mark AND d2_void FROM d2)
            AND (SELECT wrapper_md5='e2a112b376dc32c43e1615e4a4abf24a' AND recon_md5='1bfde751ac647c5e9a25ba168d08150c' AND snapshot_md5='154231b3f180349ec328f08ccbe77076' FROM fz)
          THEN 'PASS' ELSE 'FAIL' END)
ORDER BY 1;
-- ============================================================================
