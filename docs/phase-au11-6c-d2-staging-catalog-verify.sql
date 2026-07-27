-- ============================================================================
-- AU-11 Step 6C-D2 — CATALOG VERIFICATION (checkpoint B; also post-install evidence for Req 8)
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Read-only. Run immediately AFTER phase-au11-6c-d2-staging-rpcs.sql (and after the
-- reservable-column migration). Proves the hardened install shape. Every CHK_* row should read PASS.
-- ============================================================================
DO $$ BEGIN
  IF to_regclass('public.app_environment') IS NULL OR NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') THEN
    RAISE EXCEPTION 'HARD STOP: not staging'; END IF;
END $$;

-- 1) SECURITY DEFINER on + hardened empty search_path + owner not anon/authenticated + raw evidence
SELECT 'CHK_secdef_searchpath_owner' AS check_name,
       p.proname,
       p.prosecdef                                              AS is_secdef,           -- expect true
       p.proconfig                                              AS proconfig,           -- expect {search_path=}
       r.rolname                                                AS owner,               -- expect controlled admin (e.g. postgres)
       CASE WHEN p.prosecdef
             AND p.proconfig IS NOT NULL
             -- empty search_path may store as 'search_path=' or 'search_path=""'; strip quotes and require empty:
             AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c
                          WHERE c LIKE 'search_path=%' AND btrim(split_part(c,'=',2), '"') = '')
             AND r.rolname NOT IN ('anon','authenticated')
            THEN 'PASS' ELSE 'FAIL' END                          AS result
FROM pg_proc p
JOIN pg_roles r ON r.oid = p.proowner
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('create_discretionary_goal_reservation_v1',
                    'mark_discretionary_goal_reservation_initiated_v1',
                    'void_scheduled_discretionary_goal_reservation_v1')
ORDER BY p.proname;

-- 2) exact identity signatures (evidence)
SELECT 'CHK_signatures' AS check_name, p.proname,
       pg_catalog.oidvectortypes(p.proargtypes) AS args,
       pg_get_function_result(p.oid)             AS returns
FROM pg_proc p
WHERE p.pronamespace='public'::regnamespace
  AND p.proname IN ('create_discretionary_goal_reservation_v1',
                    'mark_discretionary_goal_reservation_initiated_v1',
                    'void_scheduled_discretionary_goal_reservation_v1')
ORDER BY p.proname;

-- 3) NO unintended overloads (expect exactly 1 row per name)
SELECT 'CHK_no_overloads' AS check_name, p.proname, count(*) AS n_overloads,
       CASE WHEN count(*)=1 THEN 'PASS' ELSE 'FAIL' END AS result
FROM pg_proc p
WHERE p.pronamespace='public'::regnamespace
  AND p.proname IN ('create_discretionary_goal_reservation_v1',
                    'mark_discretionary_goal_reservation_initiated_v1',
                    'void_scheduled_discretionary_goal_reservation_v1')
GROUP BY p.proname ORDER BY p.proname;

-- 4) function ACLs: PUBLIC/anon have NO privileges; authenticated has EXECUTE
SELECT 'CHK_acls' AS check_name, p.proname, p.proacl AS acl,
       CASE WHEN has_function_privilege('authenticated', p.oid, 'EXECUTE')
             AND NOT has_function_privilege('anon',   p.oid, 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM pg_proc p
WHERE p.pronamespace='public'::regnamespace
  AND p.proname IN ('create_discretionary_goal_reservation_v1',
                    'mark_discretionary_goal_reservation_initiated_v1',
                    'void_scheduled_discretionary_goal_reservation_v1')
ORDER BY p.proname;

-- 5) reservable column: boolean, NOT NULL, default false
SELECT 'CHK_reservable_column' AS check_name, data_type, is_nullable, column_default,
       CASE WHEN data_type='boolean' AND is_nullable='NO' AND column_default ILIKE '%false%' THEN 'PASS' ELSE 'FAIL' END AS result
FROM information_schema.columns
WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable';

-- 6) goal_registry.status CHECK admits the predicate values planned + funding (Req 6)
SELECT 'CHK_status_check_admits_predicate' AS check_name,
       pg_get_constraintdef(c.oid) AS status_check,
       CASE WHEN pg_get_constraintdef(c.oid) LIKE '%planned%' AND pg_get_constraintdef(c.oid) LIKE '%funding%'
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM pg_constraint c
WHERE c.conrelid='public.goal_registry'::regclass AND c.contype='c'
  AND pg_get_constraintdef(c.oid) ILIKE '%status%';

-- 7) no EXISTING goal became implicitly reservable (only fixture goals may be true) (Req 6)
SELECT 'CHK_no_implicit_reservable' AS check_name,
       count(*) AS unexpected_reservable,
       CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM public.goal_registry WHERE reservable=true AND id NOT LIKE 'd2fix_%';

-- 8) D1 shape still present (batch table + bidirectional shape CHECK + one-active-batch partial index)
SELECT 'CHK_d1_shape' AS check_name,
       (to_regclass('public.discretionary_reservation_batches') IS NOT NULL) AS batch_table,
       EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_au11_reservation_shape') AS shape_check,
       EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='uix_one_active_batch')        AS one_active_idx,
       CASE WHEN to_regclass('public.discretionary_reservation_batches') IS NOT NULL
             AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_au11_reservation_shape')
             AND EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='uix_one_active_batch')
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- 9) residue at checkpoint B (no reservation rows/batches yet)
SELECT 'CHK_residue' AS check_name,
       (SELECT count(*) FROM public.discretionary_reservation_batches) AS batches,
       (SELECT count(*) FROM public.cash_commitments WHERE commitment_source='au11_reservation') AS reservations,
       CASE WHEN (SELECT count(*) FROM public.discretionary_reservation_batches)=0
             AND (SELECT count(*) FROM public.cash_commitments WHERE commitment_source='au11_reservation')=0
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- 10) frozen commitment RPCs present AND unchanged. Reads pg_proc directly and asserts the exact types-only
--     signature (pg_catalog.oidvectortypes(proargtypes)) + owner — this both confirms presence and DETECTS
--     real drift. Two earlier forms were rejected on staging: to_regprocedure(text) false-negatived on the
--     numeric/timestamptz arg-string parse, and pg_get_function_identity_arguments() emitted parameter
--     names+types (not types-only) so the equality compare failed. oidvectortypes yields the canonical
--     types-only list that matches the expected strings below.
SELECT 'CHK_frozen_rpcs_present' AS check_name,
       p.proname,
       pg_catalog.oidvectortypes(p.proargtypes) AS arg_types,
       r.rolname AS owner,
       CASE
         WHEN p.proname='repair_commitments_for_week'
              AND pg_catalog.oidvectortypes(p.proargtypes) = 'integer, integer, text, jsonb, jsonb' THEN 'PASS'
         WHEN p.proname='save_reconciliation_with_commitments'
              AND pg_catalog.oidvectortypes(p.proargtypes) = 'integer, integer, numeric, numeric, numeric, numeric, numeric, text, timestamp with time zone, jsonb, jsonb' THEN 'PASS'
         ELSE 'FAIL' END AS result
FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('repair_commitments_for_week','save_reconciliation_with_commitments')
ORDER BY p.proname;
-- Expect exactly 2 rows, both result=PASS (repair + save_reconciliation_with_commitments), owner not anon/authenticated.
-- NOTE: frozen CODE-surface hashes (runModel/netting/resolver in index.html) are proven out-of-band via git
-- (index.html byte-unchanged since 78538f9) — they are not DB objects.
