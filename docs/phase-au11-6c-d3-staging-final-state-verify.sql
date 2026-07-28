-- ============================================================================
-- AU-11 Step 6C-D3 — CHECKPOINT I: FINAL-STATE VERIFICATION (READ-ONLY, MECHANICALLY ENFORCED)  [7D-B]
-- ----------------------------------------------------------------------------
-- STAGING ONLY. NOT executed by Claude. Strictly NON-MUTATING (SELECT + RAISE only; no DDL/DML/temp/role/side-effect).
-- Proves the resting end-state after I4 clean-reapply (schema + composite RPC reapplied; fixture NOT reinstalled):
--   D1 shape CHECK unchanged · D3 (column/FK/CHECK/index/RPC) installed, validated, exact-signature, resting-inert ·
--   ALL THREE frozen objects' md5 intact · fixture ABSENT + zero residue (incl. zero attribution residue) · S3(b)
--   post-attribution invariant holds for ANY attributed reservation · reused-owner integrity (email-AGNOSTIC; NO UUID/email).
--
-- HARDENING: every catalog lookup is schema/table-qualified; the composite RPC is resolved by EXACT 14-arg
--   to_regprocedure OID (fail-closed RAISE if NULL; inspected by p.oid — no schema+proname count, no overload false-fail);
--   the D3 index is proven by EXACT STRUCTURAL catalog assertions (btree, one key col, no INCLUDE, no expression, exact
--   key column, normalized-exact predicate) — NOT substring/ILIKE; ALL THREE frozen objects (wrapper/reconciliation/
--   snapshot) are resolved by EXACT to_regprocedure signature with fail-closed `IS DISTINCT FROM` md5 (md5-of-NULL never
--   passes; 'ABSENT' sentinel in PART 2); the D3 attribution CHECK and D1 shape CHECK match PINNED normalized canons
--   (exact, not substring); resting-inert grants checked by OID; owner-integrity is email-AGNOSTIC (exactly one active
--   auth-backed owner; no email pinned or exposed). PART 2 is ONE UNION-ALL result set (the Supabase editor shows only
--   the LAST result set) ending FS_OVERALL.
--
-- EVIDENCE MODEL: PART 1 is the mechanical hard-stop — ANY mismatch RAISEs 'FINAL-STATE FAIL: …' and aborts the batch
--   (the editor then shows the ERROR, not results). If PART 1 passes, PART 2's single result set is the durable
--   evidence; FS_OVERALL = PASS is the checkpoint pass signal. (Do NOT rely on PART 1's closing NOTICE — it is suppressed.)
-- ============================================================================

-- ── PART 1 — mechanically-enforced gate (RAISE on any mismatch) ──
DO $fs$
DECLARE
  v_rpc   regprocedure;
  v_wrap  regprocedure; v_recon regprocedure; v_snap regprocedure;
  v_secdef boolean; v_owner text; v_emptysp boolean; v_ret text; v_args text; v_vol "char"; v_par "char";
  v_anon boolean; v_auth boolean;
BEGIN
  -- staging gate (fail-closed: table absent, empty, or any non-'staging' row ⇒ fail)
  IF to_regclass('public.app_environment') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.app_environment)
     OR EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: not staging.'; END IF;

  -- D3 column: uuid / nullable / no default
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='cash_commitments'
                    AND column_name='cleared_transaction_id' AND data_type='uuid' AND is_nullable='YES' AND column_default IS NULL) THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: cleared_transaction_id column missing/wrong shape.'; END IF;

  -- D3 FK: qualified + validated + CASCADE/RESTRICT + NOT DEFERRABLE + references public.transactions
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
                  WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='fk_au11_cleared_txn' AND c.contype='f'
                    AND c.convalidated AND c.confupdtype='c' AND c.confdeltype='r' AND c.condeferrable=false
                    AND c.confrelid='public.transactions'::regclass) THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: fk_au11_cleared_txn missing/invalid/wrong actions/ref.'; END IF;

  -- D3 attribution CHECK: qualified + validated + PINNED normalized canon (strip ::text + parens + whitespace)
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
                  WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_cleared_txn_attribution' AND c.contype='c' AND c.convalidated
                    AND lower(regexp_replace(regexp_replace(pg_get_constraintdef(c.oid),'::text','','g'),'[[:space:]()]','','g'))
                        = $d3$checkcasewhencommitment_source='au11_reservation'andstatus='cleared'thencleared_transaction_idisnotnullelsecleared_transaction_idisnullend$d3$) THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: chk_au11_cleared_txn_attribution missing/invalid/wrong expression.'; END IF;

  -- D3 index: EXACT STRUCTURAL shape — public.cash_commitments, btree, unique, exactly one key column (no INCLUDE),
  --   no expression, key column = cleared_transaction_id, predicate exactly (cleared_transaction_id IS NOT NULL).
  IF NOT EXISTS (SELECT 1 FROM pg_index i
                   JOIN pg_class ic ON ic.oid=i.indexrelid
                   JOIN pg_class t  ON t.oid=i.indrelid
                   JOIN pg_namespace n ON n.oid=t.relnamespace
                   JOIN pg_am am ON am.oid=ic.relam
                   JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=i.indkey[0] AND NOT a.attisdropped
                  WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i'
                    AND i.indisunique AND i.indnatts=1 AND i.indnkeyatts=1 AND i.indexprs IS NULL
                    AND am.amname='btree' AND a.attname='cleared_transaction_id'
                    AND i.indpred IS NOT NULL
                    AND lower(regexp_replace(pg_get_expr(i.indpred, i.indrelid),'[()[:space:]]','','g')) = 'cleared_transaction_idisnotnull') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: uix_au11_cleared_txn missing/wrong exact shape.'; END IF;

  -- D3 composite RPC: EXACT 14-arg OID (fail-closed) + inspect by p.oid (owner/secdef/empty search_path/jsonb/VOLATILE/PARALLEL-UNSAFE/exact args)
  v_rpc := to_regprocedure('public.close_week_with_reservations_v1(integer,integer,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,integer,jsonb)');
  IF v_rpc IS NULL THEN RAISE EXCEPTION 'FINAL-STATE FAIL: composite RPC (exact 14-arg signature) not found.'; END IF;
  SELECT p.prosecdef, pg_get_userbyid(p.proowner),
         EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE split_part(cfg,'=',1)='search_path' AND btrim(split_part(cfg,'=',2),'"')=''),
         pg_catalog.format_type(p.prorettype,NULL), pg_catalog.oidvectortypes(p.proargtypes), p.provolatile, p.proparallel
    INTO v_secdef, v_owner, v_emptysp, v_ret, v_args, v_vol, v_par
    FROM pg_proc p WHERE p.oid=v_rpc;
  IF v_secdef IS NOT TRUE OR v_owner <> 'postgres' OR v_emptysp IS NOT TRUE OR v_ret <> 'jsonb'
     OR v_args <> 'integer, integer, numeric, numeric, numeric, numeric, numeric, text, jsonb, jsonb, jsonb, text, integer, jsonb'
     OR v_vol <> 'v' OR v_par <> 'u' THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: composite RPC identity/security wrong (secdef=%, owner=%, empty_sp=%, ret=%, args=%, vol=%, par=%).',
      v_secdef, v_owner, v_emptysp, v_ret, v_args, v_vol, v_par; END IF;

  -- D3 composite RPC resting-inert grants (by OID)
  v_anon := has_function_privilege('anon', v_rpc, 'EXECUTE');
  v_auth := has_function_privilege('authenticated', v_rpc, 'EXECUTE');
  IF v_anon OR v_auth THEN RAISE EXCEPTION 'FINAL-STATE FAIL: composite EXECUTE not inert (anon=%, authenticated=%).', v_anon, v_auth; END IF;

  -- D1 shape CHECK unchanged: qualified + validated + PINNED normalized canon
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
                  WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_reservation_shape' AND c.contype='c' AND c.convalidated
                    AND lower(regexp_replace(regexp_replace(pg_get_constraintdef(c.oid),'::text','','g'),'[()[:space:]]','','g'))
                        = $d1$checkcommitment_class='discretionary_goal_transfer'andcommitment_source='au11_reservation'andreservation_batch_idisnotnullandgoal_idisnotnullanddestination_account_refisnotnullandrequired_or_discretionary='discretionary_deployment'andsource_account='truist_checking'orcommitment_class<>'discretionary_goal_transfer'andcommitment_source<>'au11_reservation'andreservation_batch_idisnullandgoal_idisnullanddestination_account_refisnullandbank_referenceisnullandbank_submitted_atisnull$d1$) THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: D1 shape CHECK missing/invalid/altered.'; END IF;

  -- frozen objects md5 intact: ALL THREE, EXACT signatures (fail-closed RAISE if NULL) + IS DISTINCT FROM pinned
  v_wrap := to_regprocedure('public.save_weekly_closeout_with_snapshots(int,int,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,int)');
  IF v_wrap IS NULL THEN RAISE EXCEPTION 'FINAL-STATE FAIL: frozen wrapper (exact signature) not found.'; END IF;
  IF md5(pg_get_functiondef(v_wrap)) IS DISTINCT FROM 'e2a112b376dc32c43e1615e4a4abf24a' THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: frozen wrapper md5 drift.'; END IF;
  v_recon := to_regprocedure('public.save_reconciliation_with_commitments(int,int,numeric,numeric,numeric,numeric,numeric,text,timestamptz,jsonb,jsonb)');
  IF v_recon IS NULL THEN RAISE EXCEPTION 'FINAL-STATE FAIL: frozen reconciliation (exact signature) not found.'; END IF;
  IF md5(pg_get_functiondef(v_recon)) IS DISTINCT FROM '1bfde751ac647c5e9a25ba168d08150c' THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: frozen reconciliation md5 drift.'; END IF;
  v_snap := to_regprocedure('public.save_goal_funding_snapshots(int,int,jsonb)');
  IF v_snap IS NULL THEN RAISE EXCEPTION 'FINAL-STATE FAIL: frozen snapshot (exact signature) not found.'; END IF;
  IF md5(pg_get_functiondef(v_snap)) IS DISTINCT FROM '154231b3f180349ec328f08ccbe77076' THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: frozen snapshot md5 drift.'; END IF;

  -- fixture ABSENT + zero residue (incl. zero attribution residue)
  IF EXISTS (SELECT 1 FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_%') THEN RAISE EXCEPTION 'FINAL-STATE FAIL: fixture reservation residue.'; END IF;
  IF EXISTS (SELECT 1 FROM public.transactions WHERE memo LIKE '[STAGING-FIXTURE]%') THEN RAISE EXCEPTION 'FINAL-STATE FAIL: fixture transaction residue.'; END IF;
  IF to_regclass('public.d3_fixture_ledger') IS NOT NULL THEN RAISE EXCEPTION 'FINAL-STATE FAIL: d3_fixture_ledger still present.'; END IF;
  IF EXISTS (SELECT 1 FROM public.cash_commitments WHERE cleared_transaction_id IS NOT NULL AND expected_item_id LIKE 'd3fix_%') THEN RAISE EXCEPTION 'FINAL-STATE FAIL: fixture attribution residue.'; END IF;

  -- S3(b) post-attribution consistency invariant for EVERY attributed reservation (0 violations; vacuous in dormant staging)
  IF EXISTS (SELECT 1 FROM public.cash_commitments cc JOIN public.transactions t ON t.id=cc.cleared_transaction_id
             WHERE cc.cleared_transaction_id IS NOT NULL
               AND NOT (cc.commitment_source='au11_reservation' AND cc.status='cleared'
                        AND t.account_key='truist_checking' AND t.cleared=true AND t.amount<0
                        AND (t.amount*100) = (- cc.amount_cents::numeric)
                        AND t.transaction_date >= (DATE '2026-06-07' + 7*(cc.resolved_model_week-1))
                        AND t.transaction_date <= (DATE '2026-06-07' + 7*(cc.resolved_model_week-1) + 6))) THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: S3(b) post-attribution consistency invariant violated.'; END IF;

  -- reused-owner integrity (EMAIL-AGNOSTIC), two-count invariant so a MALFORMED second active owner cannot hide:
  --   (1) exactly one ACTIVE owner exists; (2) that sole active owner is auth-backed (non-null id + exactly one auth.users row,
  --   guaranteed by auth.users.id PK). qualifying ⊆ active, so active=1 AND qualifying=1 ⇒ the one active owner is the backed one.
  IF (SELECT count(*) FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE) <> 1
     OR (SELECT count(*) FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
           AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id)) <> 1 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: owner integrity — need exactly one active owner AND that owner auth-backed (active_owners=%, qualifying_owners=%).',
      (SELECT count(*) FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE),
      (SELECT count(*) FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
         AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id));
  END IF;

  RAISE NOTICE 'FINAL-STATE: all Checkpoint-I assertions PASSED (editor may suppress this; rely on PART 2 FS_OVERALL).';
END $fs$;

-- ── PART 2 — durable end-state evidence: ONE result set (editor shows only the last), ending FS_OVERALL ──
WITH
rpc AS (SELECT to_regprocedure('public.close_week_with_reservations_v1(integer,integer,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,integer,jsonb)') AS oid),
stg AS (SELECT (to_regclass('public.app_environment') IS NOT NULL
                AND EXISTS(SELECT 1 FROM public.app_environment)
                AND NOT EXISTS(SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging')) AS ok),
col AS (SELECT data_type, is_nullable, (column_default IS NULL) AS default_null, count(*) AS n
        FROM information_schema.columns
        WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id'
          AND data_type='uuid' AND is_nullable='YES' AND column_default IS NULL
        GROUP BY data_type, is_nullable, (column_default IS NULL)),
fk AS (SELECT c.confupdtype::text AS upd, c.confdeltype::text AS del, c.condeferrable AS deferrable, c.convalidated AS valid,
              (c.confrelid='public.transactions'::regclass) AS ref_ok, count(*) AS n
       FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
       WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='fk_au11_cleared_txn' AND c.contype='f'
         AND c.convalidated AND c.confupdtype='c' AND c.confdeltype='r' AND c.condeferrable=false AND c.confrelid='public.transactions'::regclass
       GROUP BY c.confupdtype::text, c.confdeltype::text, c.condeferrable, c.convalidated, (c.confrelid='public.transactions'::regclass)),
d3chk AS (SELECT count(*) AS n FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
          WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_cleared_txn_attribution' AND c.contype='c' AND c.convalidated
            AND lower(regexp_replace(regexp_replace(pg_get_constraintdef(c.oid),'::text','','g'),'[[:space:]()]','','g'))
                = $d3$checkcasewhencommitment_source='au11_reservation'andstatus='cleared'thencleared_transaction_idisnotnullelsecleared_transaction_idisnullend$d3$),
idx AS (SELECT count(*) AS n, max(pg_get_indexdef(i.indexrelid)) AS indexdef, max(am.amname) AS am, bool_and(i.indisunique) AS uniq,
               max(i.indnatts) AS natts, max(i.indnkeyatts) AS nkeyatts, max(a.attname) AS key_col,
               max(pg_get_expr(i.indpred, i.indrelid)) AS predicate
        FROM pg_index i
          JOIN pg_class ic ON ic.oid=i.indexrelid
          JOIN pg_class t  ON t.oid=i.indrelid
          JOIN pg_namespace n ON n.oid=t.relnamespace
          JOIN pg_am am ON am.oid=ic.relam
          JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=i.indkey[0] AND NOT a.attisdropped
        WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i'
          AND i.indisunique AND i.indnatts=1 AND i.indnkeyatts=1 AND i.indexprs IS NULL
          AND am.amname='btree' AND a.attname='cleared_transaction_id'
          AND i.indpred IS NOT NULL
          AND lower(regexp_replace(pg_get_expr(i.indpred, i.indrelid),'[()[:space:]]','','g')) = 'cleared_transaction_idisnotnull'),
d1 AS (SELECT count(*) AS n FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
       WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_reservation_shape' AND c.contype='c' AND c.convalidated
         AND lower(regexp_replace(regexp_replace(pg_get_constraintdef(c.oid),'::text','','g'),'[()[:space:]]','','g'))
             = $d1$checkcommitment_class='discretionary_goal_transfer'andcommitment_source='au11_reservation'andreservation_batch_idisnotnullandgoal_idisnotnullanddestination_account_refisnotnullandrequired_or_discretionary='discretionary_deployment'andsource_account='truist_checking'orcommitment_class<>'discretionary_goal_transfer'andcommitment_source<>'au11_reservation'andreservation_batch_idisnullandgoal_idisnullanddestination_account_refisnullandbank_referenceisnullandbank_submitted_atisnull$d1$),
prpc AS (SELECT p.prosecdef, pg_get_userbyid(p.proowner) AS owner, pg_catalog.format_type(p.prorettype,NULL) AS ret,
                pg_catalog.oidvectortypes(p.proargtypes) AS args, p.provolatile::text AS vol, p.proparallel::text AS par,
                EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE split_part(cfg,'=',1)='search_path' AND btrim(split_part(cfg,'=',2),'"')='') AS empty_sp
         FROM pg_proc p WHERE p.oid=(SELECT oid FROM rpc)),
grants AS (SELECT (SELECT CASE WHEN oid IS NOT NULL THEN has_function_privilege('anon', oid, 'EXECUTE') END FROM rpc) AS anon_exec,
                  (SELECT CASE WHEN oid IS NOT NULL THEN has_function_privilege('authenticated', oid, 'EXECUTE') END FROM rpc) AS auth_exec),
fz AS (SELECT
    (CASE WHEN to_regprocedure('public.save_weekly_closeout_with_snapshots(int,int,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,int)') IS NOT NULL
          THEN md5(pg_get_functiondef(to_regprocedure('public.save_weekly_closeout_with_snapshots(int,int,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,int)'))) ELSE 'ABSENT' END) AS wrapper_md5,
    (CASE WHEN to_regprocedure('public.save_reconciliation_with_commitments(int,int,numeric,numeric,numeric,numeric,numeric,text,timestamptz,jsonb,jsonb)') IS NOT NULL
          THEN md5(pg_get_functiondef(to_regprocedure('public.save_reconciliation_with_commitments(int,int,numeric,numeric,numeric,numeric,numeric,text,timestamptz,jsonb,jsonb)'))) ELSE 'ABSENT' END) AS recon_md5,
    (CASE WHEN to_regprocedure('public.save_goal_funding_snapshots(int,int,jsonb)') IS NOT NULL
          THEN md5(pg_get_functiondef(to_regprocedure('public.save_goal_funding_snapshots(int,int,jsonb)'))) ELSE 'ABSENT' END) AS snapshot_md5),
fixture AS (SELECT
   (SELECT count(*) FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_%') AS res_resid,
   (SELECT count(*) FROM public.transactions WHERE memo LIKE '[STAGING-FIXTURE]%') AS txn_resid,
   (to_regclass('public.d3_fixture_ledger') IS NULL) AS ledger_absent,
   (SELECT count(*) FROM public.cash_commitments WHERE cleared_transaction_id IS NOT NULL AND expected_item_id LIKE 'd3fix_%') AS attr_resid),
s3b AS (SELECT count(*) AS violations FROM public.cash_commitments cc JOIN public.transactions t ON t.id=cc.cleared_transaction_id
        WHERE cc.cleared_transaction_id IS NOT NULL
          AND NOT (cc.commitment_source='au11_reservation' AND cc.status='cleared'
                   AND t.account_key='truist_checking' AND t.cleared=true AND t.amount<0
                   AND (t.amount*100) = (- cc.amount_cents::numeric)
                   AND t.transaction_date >= (DATE '2026-06-07' + 7*(cc.resolved_model_week-1))
                   AND t.transaction_date <= (DATE '2026-06-07' + 7*(cc.resolved_model_week-1) + 6))),
own AS (SELECT
   (SELECT count(*) FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE) AS active_owners,
   (SELECT count(*) FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id)) AS qualifying_owners),
r AS (SELECT
   (SELECT count(*)=1 FROM col) AS col_ok,
   (SELECT count(*)=1 FROM fk)  AS fk_ok,
   (SELECT n=1 FROM d3chk) AS chk_ok,
   (SELECT n=1 FROM idx)   AS idx_ok,
   (SELECT n=1 FROM d1)    AS d1_ok,
   ((SELECT oid FROM rpc) IS NOT NULL
      AND (SELECT count(*)=1 FROM prpc)
      AND (SELECT bool_and(prosecdef AND owner='postgres' AND ret='jsonb'
             AND args='integer, integer, numeric, numeric, numeric, numeric, numeric, text, jsonb, jsonb, jsonb, text, integer, jsonb'
             AND vol='v' AND par='u' AND empty_sp) FROM prpc)) AS rpc_ok,
   (SELECT anon_exec IS NOT TRUE AND auth_exec IS NOT TRUE FROM grants) AS inert_ok,
   (SELECT wrapper_md5='e2a112b376dc32c43e1615e4a4abf24a' AND recon_md5='1bfde751ac647c5e9a25ba168d08150c' AND snapshot_md5='154231b3f180349ec328f08ccbe77076' FROM fz) AS frozen_ok,
   (SELECT res_resid=0 AND txn_resid=0 AND ledger_absent AND attr_resid=0 FROM fixture) AS fixture_ok,
   (SELECT violations=0 FROM s3b) AS s3b_ok,
   (SELECT active_owners=1 AND qualifying_owners=1 FROM own) AS owner_ok,
   (SELECT ok FROM stg) AS staging_ok)
SELECT check_name, detail, result FROM (
  SELECT 1 AS ord, 'FS_column' AS check_name, (SELECT to_jsonb(col) FROM col) AS detail, (SELECT CASE WHEN col_ok THEN 'PASS' ELSE 'FAIL' END FROM r) AS result
  UNION ALL SELECT 2,  'FS_fk_valid',        (SELECT to_jsonb(fk) FROM fk),           (SELECT CASE WHEN fk_ok      THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 3,  'FS_check_valid',     (SELECT to_jsonb(d3chk) FROM d3chk),     (SELECT CASE WHEN chk_ok     THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 4,  'FS_index',           (SELECT to_jsonb(idx) FROM idx),         (SELECT CASE WHEN idx_ok     THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 5,  'FS_d1_shape',        (SELECT to_jsonb(d1) FROM d1),           (SELECT CASE WHEN d1_ok      THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 6,  'FS_rpc',             (SELECT to_jsonb(prpc) FROM prpc),       (SELECT CASE WHEN rpc_ok     THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 7,  'FS_rpc_inert',       (SELECT to_jsonb(grants) FROM grants),   (SELECT CASE WHEN inert_ok   THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 8,  'FS_frozen_md5',      (SELECT to_jsonb(fz) FROM fz),           (SELECT CASE WHEN frozen_ok  THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 9,  'FS_fixture_absent',  (SELECT to_jsonb(fixture) FROM fixture), (SELECT CASE WHEN fixture_ok THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 10, 'FS_s3b_invariant',   (SELECT to_jsonb(s3b) FROM s3b),         (SELECT CASE WHEN s3b_ok     THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 11, 'FS_owner_integrity', (SELECT to_jsonb(own) FROM own),         (SELECT CASE WHEN owner_ok   THEN 'PASS' ELSE 'FAIL' END FROM r)
  UNION ALL SELECT 12, 'FS_OVERALL',
       jsonb_build_object('staging', (SELECT ok FROM stg)),
       (SELECT CASE WHEN staging_ok AND col_ok AND fk_ok AND chk_ok AND idx_ok AND d1_ok AND rpc_ok AND inert_ok AND frozen_ok AND fixture_ok AND s3b_ok AND owner_ok
                    THEN 'PASS' ELSE 'FAIL' END FROM r)
) q ORDER BY ord;
-- ============================================================================
