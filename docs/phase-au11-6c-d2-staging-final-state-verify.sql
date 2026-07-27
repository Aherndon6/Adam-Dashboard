-- ============================================================================
-- AU-11 Step 6C-D2 — CHECKPOINT I: FINAL-STATE VERIFICATION  (READ-ONLY, MECHANICALLY ENFORCED)
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Strictly NON-MUTATING: no BEGIN/COMMIT, no INSERT/UPDATE/DELETE/DDL — only SELECT and RAISE.
-- Authoritative Checkpoint-I gate. PART 1 is a single DO block that RAISEs 'FINAL-STATE FAIL: …' on ANY mismatch
-- (mechanical enforcement, not display) covering the FULL end-state: D2 installed (3 RPCs exact-sig + no overloads
-- + SECURITY DEFINER + empty search_path + owner∉{anon,authenticated} + EXECUTE ACLs; reservable column exact
-- shape), D1 + frozen intact, fixture ABSENT, zero residue, reused owner integrity-asserted (unique+email+auth-backed). PART 2/3 re-emit the same facts
-- as human-readable evidence. If PART 1 raises, the script aborts and PARTS 2/3 do not run — a FAIL cannot be
-- silently displayed-and-missed. (catalog-verify remains available as supplementary detail but is display-only.)
-- ============================================================================

-- ── PART 1 — mechanically-enforced gate (RAISE on any mismatch) ──
DO $$
DECLARE v_cols TEXT; v_pred TEXT;
BEGIN
  -- staging
  IF to_regclass('public.app_environment') IS NULL
     OR (SELECT count(*) FROM public.app_environment) < 1
     OR EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: not staging (need >=1 row, every row env=staging).'; END IF;

  -- D2 RPCs: each present exactly once with the exact signature (no overloads)
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='create_discretionary_goal_reservation_v1') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='create_discretionary_goal_reservation_v1'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, integer, text, text, date, jsonb, integer') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: create_... missing/not-exact-signature/overloaded.'; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='mark_discretionary_goal_reservation_initiated_v1') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='mark_discretionary_goal_reservation_initiated_v1'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, text, text[], text, timestamp with time zone, date') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: mark_... missing/not-exact-signature/overloaded.'; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='void_scheduled_discretionary_goal_reservation_v1') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='void_scheduled_discretionary_goal_reservation_v1'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, text, text[], text') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: void_... missing/not-exact-signature/overloaded.'; END IF;

  -- D2 RPC security posture: SECURITY DEFINER + empty search_path + owner∉{anon,authenticated} + EXECUTE ACLs
  IF EXISTS (
     SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
      WHERE p.pronamespace='public'::regnamespace
        AND p.proname IN ('create_discretionary_goal_reservation_v1','mark_discretionary_goal_reservation_initiated_v1','void_scheduled_discretionary_goal_reservation_v1')
        AND ( p.prosecdef IS NOT TRUE
              OR p.proconfig IS NULL
              OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%' AND btrim(split_part(c,'=',2),'"')='')
              OR r.rolname IN ('anon','authenticated')
              OR has_function_privilege('anon', p.oid, 'EXECUTE')
              OR NOT has_function_privilege('authenticated', p.oid, 'EXECUTE') )) THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: a D2 RPC violates secdef/empty-search_path/owner/ACL posture.'; END IF;

  -- reservable column: exactly one live {boolean, NOT NULL, DEFAULT false}
  IF (SELECT count(*) FROM pg_attribute a JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
       WHERE a.attrelid='public.goal_registry'::regclass AND a.attname='reservable'
         AND a.atttypid='pg_catalog.bool'::regtype AND a.attnotnull IS TRUE AND a.attisdropped IS FALSE
         AND pg_catalog.pg_get_expr(d.adbin, d.adrelid)='false') <> 1 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: goal_registry.reservable not exactly one live {boolean, NOT NULL, DEFAULT false} column.'; END IF;

  -- goal_registry status CHECK admits BOTH 'planned' and 'funding' (same semantics as CHK_status_check_admits_predicate)
  IF NOT EXISTS (
     SELECT 1 FROM pg_constraint c
      WHERE c.conrelid='public.goal_registry'::regclass AND c.contype='c'
        AND pg_get_constraintdef(c.oid) ILIKE '%status%'
        AND pg_get_constraintdef(c.oid) LIKE '%planned%'
        AND pg_get_constraintdef(c.oid) LIKE '%funding%') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: goal_registry status CHECK does not admit both planned and funding.'; END IF;

  -- zero implicitly-reservable NON-fixture goals (exact CHK_no_implicit_reservable semantics)
  IF (SELECT count(*) FROM public.goal_registry WHERE reservable=true AND id NOT LIKE 'd2fix_%') <> 0 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: % non-fixture goal(s) are implicitly reservable=true.',
      (SELECT count(*) FROM public.goal_registry WHERE reservable=true AND id NOT LIKE 'd2fix_%'); END IF;

  -- D1 shape intact
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                  WHERE n.nspname='public' AND c.relname='discretionary_reservation_batches' AND c.relkind='r') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: discretionary_reservation_batches base table missing.'; END IF;
  IF (SELECT count(*) FROM pg_constraint WHERE conname='chk_au11_reservation_shape'
        AND conrelid='public.cash_commitments'::regclass AND contype='c' AND convalidated) <> 1 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: chk_au11_reservation_shape not one validated CHECK on cash_commitments.'; END IF;
  IF (SELECT count(*) FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_namespace n ON n.oid=ic.relnamespace
        JOIN pg_class tc ON tc.oid=i.indrelid
       WHERE ic.relname='uix_one_active_batch' AND n.nspname='public' AND tc.relname='discretionary_reservation_batches'
         AND i.indisunique IS TRUE AND i.indpred IS NOT NULL) <> 1 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: uix_one_active_batch not a unique partial index on the batch table.'; END IF;
  SELECT string_agg(a.attname, ',' ORDER BY k.ord) INTO v_cols
    FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_namespace n ON n.oid=ic.relnamespace
    CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS k(attnum,ord)
    JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum
   WHERE ic.relname='uix_one_active_batch' AND n.nspname='public';
  IF v_cols IS DISTINCT FROM 'model_year,source_account' THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: uix_one_active_batch columns [%] (expected model_year,source_account).', v_cols; END IF;
  -- exact partial predicate (canonicalized: lowercase; casts/parens/whitespace stripped) must be status='active'
  SELECT lower(regexp_replace(regexp_replace(pg_get_expr(i.indpred, i.indrelid), '::text', '', 'g'), '[()[:space:]]', '', 'g'))
    INTO v_pred
    FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_namespace n ON n.oid=ic.relnamespace
   WHERE ic.relname='uix_one_active_batch' AND n.nspname='public';
  IF v_pred IS DISTINCT FROM $canon$status='active'$canon$ THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: uix_one_active_batch predicate [%] (expected status=active).', v_pred; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='reservation_batch_id' AND data_type='uuid' AND is_nullable='YES')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='goal_id' AND data_type='text' AND is_nullable='YES')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='destination_account_ref' AND data_type='text' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: cash_commitments D1 additive columns missing/wrong type/nullability.'; END IF;

  -- frozen commitment RPCs: exact signature exactly once, no overloads
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='repair_commitments_for_week') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='repair_commitments_for_week'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, integer, text, jsonb, jsonb') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: repair_commitments_for_week absent/not-exact-signature/overloaded.'; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='save_reconciliation_with_commitments') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='save_reconciliation_with_commitments'
                      AND pg_catalog.oidvectortypes(proargtypes)='integer, integer, numeric, numeric, numeric, numeric, numeric, text, timestamp with time zone, jsonb, jsonb') THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: save_reconciliation_with_commitments absent/not-exact-signature/overloaded.'; END IF;

  -- fixture ABSENT (the core of Checkpoint I)
  IF (SELECT count(*) FROM public.goal_registry WHERE id LIKE 'd2fix_%') <> 0 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: d2fix_ fixture goals still present.'; END IF;
  IF (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=31 AND goal_id LIKE 'd2fix_%') <> 0 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: fixture snapshots still present.'; END IF;
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=31 AND chk=3131.31) <> 0 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: fixture week-31 reconciliation still present.'; END IF;
  IF to_regclass('public.d2_fixture_ledger') IS NOT NULL THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: d2_fixture_ledger still present.'; END IF;

  -- zero reservation/batch residue
  IF (SELECT count(*) FROM public.discretionary_reservation_batches) <> 0 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: reservation batches present.'; END IF;
  IF (SELECT count(*) FROM public.cash_commitments WHERE commitment_source='au11_reservation') <> 0 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: au11_reservation commitments present.'; END IF;

  -- reused-owner integrity: exactly one qualifying active owner, email-anchored, non-null auth id + auth.users backing
  -- (the exact staging auth UUID is intentionally NOT pinned/published here — public repo; see execution record 2026-07-27)
  IF (SELECT count(*) FROM public.app_users au
        WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
          AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id)) <> 1 THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: not exactly one qualifying active owner.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.app_users au
        WHERE au.role='owner' AND au.active IS TRUE
          AND au.email='aherndon6@gmail.com'
          AND au.auth_user_id IS NOT NULL
          AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id)) THEN
    RAISE EXCEPTION 'FINAL-STATE FAIL: owner-integrity assertion failed (need exactly one active owner, email aherndon6@gmail.com, non-null auth_user_id, auth.users backing).'; END IF;

  RAISE NOTICE 'FINAL-STATE: all Checkpoint-I assertions PASSED (D2 installed, D1+frozen intact, fixture absent, zero residue, owner integrity-asserted).';
END $$;

-- ── PART 2 — end-state summary evidence (D2 present · fixture absent · zero residue) ──
SELECT *
FROM (
  SELECT 'D2_reservable_present'   AS check_name, (SELECT count(*)::bigint FROM information_schema.columns WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable') AS n   -- expect 1
  UNION ALL SELECT 'D2_rpcs_present',          (SELECT count(*)::bigint FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN ('create_discretionary_goal_reservation_v1','mark_discretionary_goal_reservation_initiated_v1','void_scheduled_discretionary_goal_reservation_v1'))  -- expect 3
  UNION ALL SELECT 'FIX_goals_absent',         (SELECT count(*)::bigint FROM public.goal_registry WHERE id LIKE 'd2fix_%')                                  -- expect 0 (no residue)
  UNION ALL SELECT 'FIX_snapshots_absent',     (SELECT count(*)::bigint FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=31 AND goal_id LIKE 'd2fix_%')  -- expect 0
  UNION ALL SELECT 'FIX_recon_wk31_absent',    (SELECT count(*)::bigint FROM public.weekly_reconciliations WHERE week_num=31 AND chk=3131.31)               -- expect 0
  UNION ALL SELECT 'FIX_ledger_absent',        (CASE WHEN to_regclass('public.d2_fixture_ledger') IS NULL THEN 0 ELSE 1 END)::bigint                        -- expect 0
  UNION ALL SELECT 'RESIDUE_batches',          (SELECT count(*)::bigint FROM public.discretionary_reservation_batches)                                      -- expect 0
  UNION ALL SELECT 'RESIDUE_reservations',     (SELECT count(*)::bigint FROM public.cash_commitments WHERE commitment_source='au11_reservation')            -- expect 0
  UNION ALL SELECT 'STATUS_admits_planned_funding',
         (CASE WHEN EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.goal_registry'::regclass AND c.contype='c'
                             AND pg_get_constraintdef(c.oid) ILIKE '%status%' AND pg_get_constraintdef(c.oid) LIKE '%planned%' AND pg_get_constraintdef(c.oid) LIKE '%funding%')
               THEN 1 ELSE 0 END)::bigint                                                                                                                    -- expect 1
  UNION ALL SELECT 'IMPLICIT_reservable_nonfixture',
         (SELECT count(*)::bigint FROM public.goal_registry WHERE reservable=true AND id NOT LIKE 'd2fix_%')                                                  -- expect 0
  UNION ALL SELECT 'ONE_ACTIVE_IDX_predicate_ok',
         (CASE WHEN (SELECT lower(regexp_replace(regexp_replace(pg_get_expr(i.indpred,i.indrelid),'::text','','g'),'[()[:space:]]','','g'))
                       FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_namespace n ON n.oid=ic.relnamespace
                      WHERE ic.relname='uix_one_active_batch' AND n.nspname='public') = 'status=''active'''
               THEN 1 ELSE 0 END)::bigint                                                                                                                    -- expect 1
) AS fs
ORDER BY check_name;
-- Semantics: for the *_absent and RESIDUE_* rows, n=0 means "nothing present" (the desired end-state);
-- D2_reservable_present=1 and D2_rpcs_present=3 mean the D2 objects are installed.

-- ── PART 3 — reused-owner integrity evidence (pinned identity) ──
WITH q AS (
  SELECT au.auth_user_id, au.email FROM public.app_users au
   WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id)
   ORDER BY au.auth_user_id)
SELECT 'owner_integrity' AS check_name,
       (SELECT count(*) FROM q)                            AS qualifying_owners,
       (SELECT email FROM q LIMIT 1)                       AS selected_email,
       ((SELECT auth_user_id FROM q LIMIT 1) IS NOT NULL)  AS auth_user_id_present,
       ((SELECT count(*) FROM q) > 0)                      AS auth_user_backing_exists,
       CASE WHEN (SELECT count(*) FROM q)=1
             AND (SELECT email FROM q LIMIT 1)='aherndon6@gmail.com'
             AND (SELECT auth_user_id FROM q LIMIT 1) IS NOT NULL
            THEN 'PASS' ELSE 'FAIL' END                    AS gate;
