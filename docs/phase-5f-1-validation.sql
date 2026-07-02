-- ═══════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5F-1 Validation
-- Cash Commitment Capture + Cash Availability Engine
-- Run in Supabase SQL Editor AFTER applying phase-5f-1-migration.sql.
-- All queries read live catalog/schema only — no DB mutations.
-- Run each SELECT individually (Supabase SQL editor only returns the
-- last statement's result when multiple SELECTs are run together).
--
-- Output columns: check_id | status | object | details
-- status values: PASS | FAIL | REVIEW
-- ═══════════════════════════════════════════════════════════════════

SET search_path TO public;

-- ── V1: weekly_reconciliations.balance_basis exists with expected CHECK ──
SELECT
  'V1' AS check_id,
  CASE
    WHEN c.column_name IS NULL THEN 'FAIL'
    WHEN con.conname IS NULL THEN 'FAIL'
    WHEN pg_get_constraintdef(con.oid) NOT ILIKE '%posted_current_balance%'
      OR pg_get_constraintdef(con.oid) NOT ILIKE '%available_balance%'
      OR pg_get_constraintdef(con.oid) NOT ILIKE '%unknown%'
      THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'weekly_reconciliations.balance_basis' AS object,
  CASE
    WHEN c.column_name IS NULL THEN 'COLUMN MISSING'
    WHEN con.conname IS NULL THEN 'column exists but no CHECK constraint found'
    ELSE 'column exists, type=' || c.data_type || ', CHECK=' || pg_get_constraintdef(con.oid)
  END AS details
FROM (SELECT 1) x
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public' AND c.table_name = 'weekly_reconciliations' AND c.column_name = 'balance_basis'
LEFT JOIN pg_constraint con
  ON con.conrelid = 'public.weekly_reconciliations'::regclass
  AND con.contype = 'c'
  AND pg_get_constraintdef(con.oid) ILIKE '%balance_basis%';


-- ── V2: cash_commitments table exists with RLS enabled ────────────────
SELECT
  'V2' AS check_id,
  CASE
    WHEN pt.tablename IS NULL THEN 'FAIL'
    WHEN NOT pt.rowsecurity THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'cash_commitments' AS object,
  CASE
    WHEN pt.tablename IS NULL THEN 'TABLE MISSING'
    WHEN NOT pt.rowsecurity THEN 'table exists but RLS NOT enabled'
    ELSE 'table exists, RLS enabled'
  END AS details
FROM (SELECT 1) x
LEFT JOIN pg_tables pt
  ON pt.schemaname = 'public' AND pt.tablename = 'cash_commitments';


-- ── V3: all 28 expected columns exist on cash_commitments ─────────────
-- Fail-loud per column — LEFT JOIN so a missing column emits its own FAIL row
-- rather than silently vanishing from a COUNT(*) check.
SELECT
  'V3' AS check_id,
  CASE WHEN c.column_name IS NULL THEN 'FAIL'
       WHEN c.data_type <> e.expected_type THEN 'FAIL'
       ELSE 'PASS' END AS status,
  'cash_commitments.' || e.col AS object,
  CASE
    WHEN c.column_name IS NULL THEN 'COLUMN MISSING (expected type ' || e.expected_type || ')'
    WHEN c.data_type <> e.expected_type THEN 'type mismatch: expected ' || e.expected_type || ', found ' || c.data_type
    ELSE 'ok, type=' || c.data_type
  END AS details
FROM (
  VALUES
    ('id','uuid'),
    ('expected_item_id','text'),
    ('model_year','integer'),
    ('commitment_source','text'),
    ('origin_model_week','integer'),
    ('payee','text'),
    ('commitment_class','text'),
    ('required_or_discretionary','text'),
    ('source_account','text'),
    ('amount_cents','integer'),
    ('original_amount_cents','integer'),
    ('status','text'),
    ('affects_deployable_cash','boolean'),
    ('reflected_model_week','integer'),
    ('due_date','date'),
    ('expected_clear_date','date'),
    ('cleared_date','date'),
    ('resolved_model_week','integer'),
    ('resolved_at','timestamp with time zone'),
    ('resolved_by','uuid'),
    ('resolution_type','text'),
    ('resolution_notes','text'),
    ('initiated_by','text'),
    ('notes','text'),
    ('created_at','timestamp with time zone'),
    ('updated_at','timestamp with time zone'),
    ('created_by','uuid'),
    ('updated_by','uuid')
) AS e(col, expected_type)
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public' AND c.table_name = 'cash_commitments' AND c.column_name = e.col
ORDER BY e.col;


-- ── V4: all 7 named CHECK constraints exist on cash_commitments ───────
SELECT
  'V4' AS check_id,
  CASE WHEN con.conname IS NULL THEN 'FAIL' ELSE 'PASS' END AS status,
  'cash_commitments.' || e.cname AS object,
  CASE
    WHEN con.conname IS NULL THEN 'CONSTRAINT MISSING'
    ELSE pg_get_constraintdef(con.oid)
  END AS details
FROM (
  VALUES
    ('chk_week_origin_range'),
    ('chk_week_reflected_range'),
    ('chk_week_resolved_range'),
    ('chk_resolved_after_origin'),
    ('chk_reflected_after_origin'),
    ('chk_source_account_only_truist'),
    ('chk_cleared_reflected_before_resolved')
) AS e(cname)
LEFT JOIN pg_constraint con
  ON con.conrelid = 'public.cash_commitments'::regclass
  AND con.contype = 'c'
  AND con.conname = e.cname
ORDER BY e.cname;


-- ── V5: updated_at/updated_by trigger exists ───────────────────────────
SELECT
  'V5' AS check_id,
  CASE
    WHEN t.tgname IS NULL THEN 'FAIL'
    WHEN p.proname IS NULL THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'trg_cash_commitments_updated' AS object,
  CASE
    WHEN t.tgname IS NULL THEN 'TRIGGER MISSING on cash_commitments'
    WHEN p.proname IS NULL THEN 'trigger exists but backing function fn_cash_commitments_set_updated not found'
    ELSE 'trigger exists, fires ' ||
         CASE WHEN t.tgtype & 2 = 2 THEN 'BEFORE' ELSE 'AFTER' END || ' ' ||
         CASE WHEN t.tgtype & 16 = 16 THEN 'UPDATE' ELSE '?' END ||
         ', function=' || p.proname
  END AS details
FROM (SELECT 1) x
LEFT JOIN pg_trigger t
  ON t.tgrelid = 'public.cash_commitments'::regclass
  AND t.tgname = 'trg_cash_commitments_updated'
  AND NOT t.tgisinternal
LEFT JOIN pg_proc p
  ON p.oid = t.tgfoid AND p.proname = 'fn_cash_commitments_set_updated';


-- ── V6: RLS SELECT policy cc_select exists, uses is_allowed_user() ─────
SELECT
  'V6' AS check_id,
  CASE
    WHEN p.policyname IS NULL THEN 'FAIL'
    WHEN p.qual NOT ILIKE '%is_allowed_user%' THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'cash_commitments.cc_select' AS object,
  CASE
    WHEN p.policyname IS NULL THEN 'SELECT policy cc_select MISSING'
    WHEN p.qual NOT ILIKE '%is_allowed_user%' THEN 'policy exists but does not use is_allowed_user(): qual=' || COALESCE(p.qual,'(none)')
    ELSE 'cmd=SELECT | qual=' || p.qual
  END AS details
FROM (SELECT 1) x
LEFT JOIN pg_policies p
  ON p.schemaname = 'public' AND p.tablename = 'cash_commitments'
  AND p.policyname = 'cc_select' AND p.cmd = 'SELECT';

-- V6a: cc_insert / cc_update policies also exist (documentation/defense-in-depth —
-- not evaluated via REST since INSERT/UPDATE are never granted to authenticated,
-- but should still exist as written in the migration).
SELECT
  'V6a' AS check_id,
  CASE WHEN p.policyname IS NULL THEN 'FAIL' ELSE 'PASS' END AS status,
  'cash_commitments.' || e.pname AS object,
  CASE WHEN p.policyname IS NULL THEN 'POLICY MISSING'
       ELSE 'cmd=' || p.cmd || ' | qual=' || COALESCE(p.qual,'(none)') || ' | with_check=' || COALESCE(p.with_check,'(none)')
  END AS details
FROM (VALUES ('cc_insert','INSERT'), ('cc_update','UPDATE')) AS e(pname, pcmd)
LEFT JOIN pg_policies p
  ON p.schemaname = 'public' AND p.tablename = 'cash_commitments'
  AND p.policyname = e.pname AND p.cmd = e.pcmd
ORDER BY e.pname;


-- ── V7: no unexpected write grants on cash_commitments ─────────────────
-- Scoped to cash_commitments only — 5F-1 does not touch grants on any other
-- table. INSERT/UPDATE/DELETE must not be exposed to PUBLIC, anon, or
-- authenticated; all commitment mutation goes through the two RPCs.
SELECT
  'V7' AS check_id,
  'FAIL' AS status,
  'cash_commitments' AS object,
  'unexpected grant: grantee=' || grantee || ' privilege=' || privilege_type AS details
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'cash_commitments'
  AND grantee IN ('PUBLIC','anon','authenticated')
  AND privilege_type IN ('INSERT','UPDATE','DELETE')
UNION ALL
SELECT
  'V7', 'PASS', 'cash_commitments',
  'no INSERT/UPDATE/DELETE grants found for PUBLIC, anon, or authenticated'
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.role_table_grants
  WHERE table_schema = 'public' AND table_name = 'cash_commitments'
    AND grantee IN ('PUBLIC','anon','authenticated')
    AND privilege_type IN ('INSERT','UPDATE','DELETE')
);


-- ── V8: authenticated has exactly SELECT on cash_commitments ───────────
SELECT
  'V8' AS check_id,
  CASE
    WHEN array_agg(privilege_type::text ORDER BY privilege_type::text) = ARRAY['SELECT']::text[] THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'cash_commitments (authenticated grants)' AS object,
  'authenticated privileges found: ' || COALESCE(string_agg(privilege_type, ', ' ORDER BY privilege_type), '(none)') AS details
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'cash_commitments' AND grantee = 'authenticated';


-- ══════════════════════════════════════════════════════════════════════
-- Function checks — validate_commitment_state
-- ══════════════════════════════════════════════════════════════════════

-- ── V9: validate_commitment_state signature (12 params, exact order) ───
SELECT
  'V9' AS check_id,
  CASE WHEN par.parameter_name IS NULL THEN 'FAIL'
       WHEN par.data_type <> e.expected_type THEN 'FAIL'
       ELSE 'PASS' END AS status,
  'validate_commitment_state arg#' || e.pos AS object,
  CASE
    WHEN par.parameter_name IS NULL THEN 'MISSING at position ' || e.pos || ' — expected ' || e.pname || ' ' || e.expected_type
    WHEN par.data_type <> e.expected_type THEN 'type mismatch at position ' || e.pos || ': expected ' || e.expected_type || ', found ' || par.data_type
    ELSE 'ok: ' || par.parameter_name || ' ' || par.data_type
  END AS details
FROM (
  VALUES
    (1,'p_id','uuid'),
    (2,'p_status','text'),
    (3,'p_resolved_model_week','integer'),
    (4,'p_reflected_model_week','integer'),
    (5,'p_resolution_type','text'),
    (6,'p_origin_model_week','integer'),
    (7,'p_amount_cents','integer'),
    (8,'p_original_amount_cents','integer'),
    (9,'p_required_or_discretionary','text'),
    (10,'p_affects_deployable_cash','boolean'),
    (11,'p_cleared_date','date'),
    (12,'p_resolution_notes','text')
) AS e(pos, pname, expected_type)
LEFT JOIN information_schema.routines r
  ON r.routine_schema = 'public' AND r.routine_name = 'validate_commitment_state'
LEFT JOIN information_schema.parameters par
  ON par.specific_name = r.specific_name AND par.ordinal_position = e.pos
ORDER BY e.pos;

-- V9a: parameter count sanity — catches extra/missing trailing params V9's
-- LEFT JOIN alone wouldn't flag (e.g. a 13th param added by accident).
SELECT
  'V9a' AS check_id,
  CASE WHEN COUNT(*) = 12 THEN 'PASS' ELSE 'FAIL' END AS status,
  'validate_commitment_state (param count)' AS object,
  'expected 12 parameters, found ' || COUNT(*)::text AS details
FROM information_schema.routines r
JOIN information_schema.parameters par ON par.specific_name = r.specific_name
WHERE r.routine_schema = 'public' AND r.routine_name = 'validate_commitment_state';

-- ── V10: validate_commitment_state is SECURITY INVOKER (not DEFINER) ───
-- Deliberately not SECURITY DEFINER — it writes nothing and is the shared
-- validator both RPCs call; it should run with the caller's own privileges.
SELECT
  'V10' AS check_id,
  CASE WHEN r.security_type = 'INVOKER' THEN 'PASS' ELSE 'FAIL' END AS status,
  'validate_commitment_state (security_type)' AS object,
  'security_type=' || COALESCE(r.security_type, 'FUNCTION NOT FOUND') AS details
FROM information_schema.routines r
WHERE r.routine_schema = 'public' AND r.routine_name = 'validate_commitment_state';

-- ── V11: validate_commitment_state — PUBLIC execute revoked, no GRANTs ─
-- No GRANT was ever issued for this function (internal helper only) — both
-- anon and authenticated should show false.
SELECT 'V11' AS check_id,
  CASE WHEN NOT has_function_privilege('anon',
    'public.validate_commitment_state(UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END AS status,
  'validate_commitment_state (anon EXECUTE)' AS object,
  'expected false (no grant ever issued)' AS details
UNION ALL
SELECT 'V11',
  CASE WHEN NOT has_function_privilege('authenticated',
    'public.validate_commitment_state(UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END,
  'validate_commitment_state (authenticated EXECUTE)',
  'expected false (no grant ever issued — internal helper, called only by the two SECURITY DEFINER RPCs)';


-- ══════════════════════════════════════════════════════════════════════
-- Function checks — save_reconciliation_with_commitments
-- ══════════════════════════════════════════════════════════════════════

-- ── V12: save_reconciliation_with_commitments signature (11 params) ────
SELECT
  'V12' AS check_id,
  CASE WHEN par.parameter_name IS NULL THEN 'FAIL'
       WHEN par.data_type <> e.expected_type THEN 'FAIL'
       ELSE 'PASS' END AS status,
  'save_reconciliation_with_commitments arg#' || e.pos AS object,
  CASE
    WHEN par.parameter_name IS NULL THEN 'MISSING at position ' || e.pos || ' — expected ' || e.pname || ' ' || e.expected_type
    WHEN par.data_type <> e.expected_type THEN 'type mismatch at position ' || e.pos || ': expected ' || e.expected_type || ', found ' || par.data_type
    ELSE 'ok: ' || par.parameter_name || ' ' || par.data_type
  END AS details
FROM (
  VALUES
    (1,'p_week_num','integer'),
    (2,'p_model_year','integer'),
    (3,'p_chk','numeric'),
    (4,'p_sav','numeric'),
    (5,'p_amx','numeric'),
    (6,'p_tax','numeric'),
    (7,'p_lc','numeric'),
    (8,'p_balance_basis','text'),
    (9,'p_recorded_at','timestamp with time zone'),
    (10,'p_new_commitments','jsonb'),
    (11,'p_patched','jsonb')
) AS e(pos, pname, expected_type)
LEFT JOIN information_schema.routines r
  ON r.routine_schema = 'public' AND r.routine_name = 'save_reconciliation_with_commitments'
LEFT JOIN information_schema.parameters par
  ON par.specific_name = r.specific_name AND par.ordinal_position = e.pos
ORDER BY e.pos;

SELECT
  'V12a' AS check_id,
  CASE WHEN COUNT(*) = 11 THEN 'PASS' ELSE 'FAIL' END AS status,
  'save_reconciliation_with_commitments (param count)' AS object,
  'expected 11 parameters, found ' || COUNT(*)::text AS details
FROM information_schema.routines r
JOIN information_schema.parameters par ON par.specific_name = r.specific_name
WHERE r.routine_schema = 'public' AND r.routine_name = 'save_reconciliation_with_commitments';

-- ── V13: save_reconciliation_with_commitments is SECURITY DEFINER,
--         with search_path pinned to public ───────────────────────────
-- SECURITY DEFINER without a pinned search_path is a privilege-escalation
-- vector (a caller-controlled search_path could redirect an unqualified
-- identifier to a caller-owned object). The migration's SET search_path =
-- public clause is what closes that — confirm it actually landed in
-- pg_proc.proconfig, not just in the source text.
SELECT
  'V13' AS check_id,
  CASE WHEN r.security_type = 'DEFINER' THEN 'PASS' ELSE 'FAIL' END AS status,
  'save_reconciliation_with_commitments (security_type)' AS object,
  'security_type=' || COALESCE(r.security_type, 'FUNCTION NOT FOUND') AS details
FROM information_schema.routines r
WHERE r.routine_schema = 'public' AND r.routine_name = 'save_reconciliation_with_commitments';

SELECT
  'V13a' AS check_id,
  CASE WHEN array_to_string(p.proconfig, ',') ILIKE '%search_path=public%' THEN 'PASS' ELSE 'FAIL' END AS status,
  'save_reconciliation_with_commitments (search_path pin)' AS object,
  'proconfig=' || COALESCE(array_to_string(p.proconfig, ', '), '(none set — VULNERABLE)') AS details
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'save_reconciliation_with_commitments';

-- ── V14: save_reconciliation_with_commitments grants — authenticated
--         only, anon denied, PUBLIC denied ────────────────────────────
SELECT 'V14' AS check_id,
  CASE WHEN NOT has_function_privilege('anon',
    'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END AS status,
  'save_reconciliation_with_commitments (anon EXECUTE)' AS object,
  'expected false' AS details
UNION ALL
SELECT 'V14',
  CASE WHEN has_function_privilege('authenticated',
    'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END,
  'save_reconciliation_with_commitments (authenticated EXECUTE)',
  'expected true (explicit GRANT in migration section 7)';


-- ══════════════════════════════════════════════════════════════════════
-- Function checks — repair_commitments_for_week
-- ══════════════════════════════════════════════════════════════════════

-- ── V15: repair_commitments_for_week signature (5 params) ──────────────
SELECT
  'V15' AS check_id,
  CASE WHEN par.parameter_name IS NULL THEN 'FAIL'
       WHEN par.data_type <> e.expected_type THEN 'FAIL'
       ELSE 'PASS' END AS status,
  'repair_commitments_for_week arg#' || e.pos AS object,
  CASE
    WHEN par.parameter_name IS NULL THEN 'MISSING at position ' || e.pos || ' — expected ' || e.pname || ' ' || e.expected_type
    WHEN par.data_type <> e.expected_type THEN 'type mismatch at position ' || e.pos || ': expected ' || e.expected_type || ', found ' || par.data_type
    ELSE 'ok: ' || par.parameter_name || ' ' || par.data_type
  END AS details
FROM (
  VALUES
    (1,'p_week_num','integer'),
    (2,'p_model_year','integer'),
    (3,'p_balance_basis','text'),
    (4,'p_new_commitments','jsonb'),
    (5,'p_patched','jsonb')
) AS e(pos, pname, expected_type)
LEFT JOIN information_schema.routines r
  ON r.routine_schema = 'public' AND r.routine_name = 'repair_commitments_for_week'
LEFT JOIN information_schema.parameters par
  ON par.specific_name = r.specific_name AND par.ordinal_position = e.pos
ORDER BY e.pos;

SELECT
  'V15a' AS check_id,
  CASE WHEN COUNT(*) = 5 THEN 'PASS' ELSE 'FAIL' END AS status,
  'repair_commitments_for_week (param count)' AS object,
  'expected 5 parameters, found ' || COUNT(*)::text AS details
FROM information_schema.routines r
JOIN information_schema.parameters par ON par.specific_name = r.specific_name
WHERE r.routine_schema = 'public' AND r.routine_name = 'repair_commitments_for_week';

-- ── V16: repair_commitments_for_week is SECURITY DEFINER, search_path pinned ──
SELECT
  'V16' AS check_id,
  CASE WHEN r.security_type = 'DEFINER' THEN 'PASS' ELSE 'FAIL' END AS status,
  'repair_commitments_for_week (security_type)' AS object,
  'security_type=' || COALESCE(r.security_type, 'FUNCTION NOT FOUND') AS details
FROM information_schema.routines r
WHERE r.routine_schema = 'public' AND r.routine_name = 'repair_commitments_for_week';

SELECT
  'V16a' AS check_id,
  CASE WHEN array_to_string(p.proconfig, ',') ILIKE '%search_path=public%' THEN 'PASS' ELSE 'FAIL' END AS status,
  'repair_commitments_for_week (search_path pin)' AS object,
  'proconfig=' || COALESCE(array_to_string(p.proconfig, ', '), '(none set — VULNERABLE)') AS details
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'repair_commitments_for_week';

-- ── V17: repair_commitments_for_week grants — authenticated only ───────
SELECT 'V17' AS check_id,
  CASE WHEN NOT has_function_privilege('anon',
    'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END AS status,
  'repair_commitments_for_week (anon EXECUTE)' AS object,
  'expected false' AS details
UNION ALL
SELECT 'V17',
  CASE WHEN has_function_privilege('authenticated',
    'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END,
  'repair_commitments_for_week (authenticated EXECUTE)',
  'expected true (explicit GRANT in migration section 8)';


-- ── V18: consolidated function-grant matrix (eyeball cross-check) ──────
-- Redundant with V11/V14/V17 by design — same facts from
-- information_schema.role_routine_grants instead of has_function_privilege,
-- as an independent cross-check using a different code path. A mismatch
-- between this and V11/V14/V17 would itself be worth investigating.
SELECT
  'V18' AS check_id,
  'REVIEW' AS status,
  routine_name AS object,
  'grantee=' || grantee || ' | privilege=' || privilege_type AS details
FROM information_schema.role_routine_grants
WHERE routine_schema = 'public'
  AND routine_name IN ('validate_commitment_state','save_reconciliation_with_commitments','repair_commitments_for_week')
ORDER BY routine_name, grantee;


-- ── V19: smokeable summary ──────────────────────────────────────────────
-- Informational only. Scan every check above for FAIL before moving to
-- Build Sequence step 6 (isReservedAsOf()) — do not touch index.html or
-- test_regression.js until V1-V18 are clean (REVIEW rows V18 and the
-- balance_basis-absent branch of PF3 excepted; both are eyeball/informational
-- by design, not gates).
SELECT
  'V19' AS check_id,
  'REVIEW' AS status,
  'summary' AS object,
  'weekly_reconciliations.balance_basis: ' ||
    (SELECT COUNT(*)::text FROM information_schema.columns WHERE table_schema='public' AND table_name='weekly_reconciliations' AND column_name='balance_basis') ||
    ' | cash_commitments table: ' ||
    (SELECT COUNT(*)::text FROM pg_tables WHERE schemaname='public' AND tablename='cash_commitments') ||
    ' | cash_commitments columns found: ' ||
    (SELECT COUNT(*)::text FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments') || '/28' ||
    ' | named CHECK constraints found: ' ||
    (SELECT COUNT(*)::text FROM pg_constraint WHERE conrelid='public.cash_commitments'::regclass AND contype='c'
       AND conname IN ('chk_week_origin_range','chk_week_reflected_range','chk_week_resolved_range',
                        'chk_resolved_after_origin','chk_reflected_after_origin',
                        'chk_source_account_only_truist','chk_cleared_reflected_before_resolved')) || '/7' ||
    ' | functions found: ' ||
    (SELECT COUNT(*)::text FROM information_schema.routines WHERE routine_schema='public'
       AND routine_name IN ('validate_commitment_state','save_reconciliation_with_commitments','repair_commitments_for_week')) || '/3'
  AS details;

-- Scan V1-V18 for any FAIL row before proceeding. If clean, 5F-1 DB layer
-- is validated — hold for Build Sequence step 6+ (JS engine work) per
-- the ground rule to stop and report before touching index.html.


-- ══════════════════════════════════════════════════════════════════════
-- COMBINED RESULT SET — run this single query for the full V1-V19 picture
-- ══════════════════════════════════════════════════════════════════════
-- Supabase's SQL editor only displays the last statement's result when
-- multiple SELECTs are run together — this wraps every check above
-- (V1-V19, unchanged logic, each check's own subquery byte-for-byte)
-- into one UNION ALL so a single Run shows every row in one grid.
-- Individual checks above remain runnable on their own for drill-down
-- (e.g. inspecting all 28 of V3's per-column rows, or V9's 12 per-
-- parameter rows, in isolation).
--
-- Gate: scan the status column for any FAIL. V18 and V19 are REVIEW by
-- design (informational cross-check and summary, not pass/fail gates).
SELECT check_id, status, object, details
FROM (
  SELECT 10 AS sort_key, * FROM (
SELECT
  'V1' AS check_id,
  CASE
    WHEN c.column_name IS NULL THEN 'FAIL'
    WHEN con.conname IS NULL THEN 'FAIL'
    WHEN pg_get_constraintdef(con.oid) NOT ILIKE '%posted_current_balance%'
      OR pg_get_constraintdef(con.oid) NOT ILIKE '%available_balance%'
      OR pg_get_constraintdef(con.oid) NOT ILIKE '%unknown%'
      THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'weekly_reconciliations.balance_basis' AS object,
  CASE
    WHEN c.column_name IS NULL THEN 'COLUMN MISSING'
    WHEN con.conname IS NULL THEN 'column exists but no CHECK constraint found'
    ELSE 'column exists, type=' || c.data_type || ', CHECK=' || pg_get_constraintdef(con.oid)
  END AS details
FROM (SELECT 1) x
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public' AND c.table_name = 'weekly_reconciliations' AND c.column_name = 'balance_basis'
LEFT JOIN pg_constraint con
  ON con.conrelid = 'public.weekly_reconciliations'::regclass
  AND con.contype = 'c'
  AND pg_get_constraintdef(con.oid) ILIKE '%balance_basis%'
  ) v_v1
UNION ALL
  SELECT 20 AS sort_key, * FROM (
SELECT
  'V2' AS check_id,
  CASE
    WHEN pt.tablename IS NULL THEN 'FAIL'
    WHEN NOT pt.rowsecurity THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'cash_commitments' AS object,
  CASE
    WHEN pt.tablename IS NULL THEN 'TABLE MISSING'
    WHEN NOT pt.rowsecurity THEN 'table exists but RLS NOT enabled'
    ELSE 'table exists, RLS enabled'
  END AS details
FROM (SELECT 1) x
LEFT JOIN pg_tables pt
  ON pt.schemaname = 'public' AND pt.tablename = 'cash_commitments'
  ) v_v2
UNION ALL
  SELECT 30 AS sort_key, * FROM (
SELECT
  'V3' AS check_id,
  CASE WHEN c.column_name IS NULL THEN 'FAIL'
       WHEN c.data_type <> e.expected_type THEN 'FAIL'
       ELSE 'PASS' END AS status,
  'cash_commitments.' || e.col AS object,
  CASE
    WHEN c.column_name IS NULL THEN 'COLUMN MISSING (expected type ' || e.expected_type || ')'
    WHEN c.data_type <> e.expected_type THEN 'type mismatch: expected ' || e.expected_type || ', found ' || c.data_type
    ELSE 'ok, type=' || c.data_type
  END AS details
FROM (
  VALUES
    ('id','uuid'),
    ('expected_item_id','text'),
    ('model_year','integer'),
    ('commitment_source','text'),
    ('origin_model_week','integer'),
    ('payee','text'),
    ('commitment_class','text'),
    ('required_or_discretionary','text'),
    ('source_account','text'),
    ('amount_cents','integer'),
    ('original_amount_cents','integer'),
    ('status','text'),
    ('affects_deployable_cash','boolean'),
    ('reflected_model_week','integer'),
    ('due_date','date'),
    ('expected_clear_date','date'),
    ('cleared_date','date'),
    ('resolved_model_week','integer'),
    ('resolved_at','timestamp with time zone'),
    ('resolved_by','uuid'),
    ('resolution_type','text'),
    ('resolution_notes','text'),
    ('initiated_by','text'),
    ('notes','text'),
    ('created_at','timestamp with time zone'),
    ('updated_at','timestamp with time zone'),
    ('created_by','uuid'),
    ('updated_by','uuid')
) AS e(col, expected_type)
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public' AND c.table_name = 'cash_commitments' AND c.column_name = e.col
ORDER BY e.col
  ) v_v3
UNION ALL
  SELECT 40 AS sort_key, * FROM (
SELECT
  'V4' AS check_id,
  CASE WHEN con.conname IS NULL THEN 'FAIL' ELSE 'PASS' END AS status,
  'cash_commitments.' || e.cname AS object,
  CASE
    WHEN con.conname IS NULL THEN 'CONSTRAINT MISSING'
    ELSE pg_get_constraintdef(con.oid)
  END AS details
FROM (
  VALUES
    ('chk_week_origin_range'),
    ('chk_week_reflected_range'),
    ('chk_week_resolved_range'),
    ('chk_resolved_after_origin'),
    ('chk_reflected_after_origin'),
    ('chk_source_account_only_truist'),
    ('chk_cleared_reflected_before_resolved')
) AS e(cname)
LEFT JOIN pg_constraint con
  ON con.conrelid = 'public.cash_commitments'::regclass
  AND con.contype = 'c'
  AND con.conname = e.cname
ORDER BY e.cname
  ) v_v4
UNION ALL
  SELECT 50 AS sort_key, * FROM (
SELECT
  'V5' AS check_id,
  CASE
    WHEN t.tgname IS NULL THEN 'FAIL'
    WHEN p.proname IS NULL THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'trg_cash_commitments_updated' AS object,
  CASE
    WHEN t.tgname IS NULL THEN 'TRIGGER MISSING on cash_commitments'
    WHEN p.proname IS NULL THEN 'trigger exists but backing function fn_cash_commitments_set_updated not found'
    ELSE 'trigger exists, fires ' ||
         CASE WHEN t.tgtype & 2 = 2 THEN 'BEFORE' ELSE 'AFTER' END || ' ' ||
         CASE WHEN t.tgtype & 16 = 16 THEN 'UPDATE' ELSE '?' END ||
         ', function=' || p.proname
  END AS details
FROM (SELECT 1) x
LEFT JOIN pg_trigger t
  ON t.tgrelid = 'public.cash_commitments'::regclass
  AND t.tgname = 'trg_cash_commitments_updated'
  AND NOT t.tgisinternal
LEFT JOIN pg_proc p
  ON p.oid = t.tgfoid AND p.proname = 'fn_cash_commitments_set_updated'
  ) v_v5
UNION ALL
  SELECT 60 AS sort_key, * FROM (
SELECT
  'V6' AS check_id,
  CASE
    WHEN p.policyname IS NULL THEN 'FAIL'
    WHEN p.qual NOT ILIKE '%is_allowed_user%' THEN 'FAIL'
    ELSE 'PASS'
  END AS status,
  'cash_commitments.cc_select' AS object,
  CASE
    WHEN p.policyname IS NULL THEN 'SELECT policy cc_select MISSING'
    WHEN p.qual NOT ILIKE '%is_allowed_user%' THEN 'policy exists but does not use is_allowed_user(): qual=' || COALESCE(p.qual,'(none)')
    ELSE 'cmd=SELECT | qual=' || p.qual
  END AS details
FROM (SELECT 1) x
LEFT JOIN pg_policies p
  ON p.schemaname = 'public' AND p.tablename = 'cash_commitments'
  AND p.policyname = 'cc_select' AND p.cmd = 'SELECT'
  ) v_v6
UNION ALL
  SELECT 61 AS sort_key, * FROM (
SELECT
  'V6a' AS check_id,
  CASE WHEN p.policyname IS NULL THEN 'FAIL' ELSE 'PASS' END AS status,
  'cash_commitments.' || e.pname AS object,
  CASE WHEN p.policyname IS NULL THEN 'POLICY MISSING'
       ELSE 'cmd=' || p.cmd || ' | qual=' || COALESCE(p.qual,'(none)') || ' | with_check=' || COALESCE(p.with_check,'(none)')
  END AS details
FROM (VALUES ('cc_insert','INSERT'), ('cc_update','UPDATE')) AS e(pname, pcmd)
LEFT JOIN pg_policies p
  ON p.schemaname = 'public' AND p.tablename = 'cash_commitments'
  AND p.policyname = e.pname AND p.cmd = e.pcmd
ORDER BY e.pname
  ) v_v6a
UNION ALL
  SELECT 70 AS sort_key, * FROM (
SELECT
  'V7' AS check_id,
  'FAIL' AS status,
  'cash_commitments' AS object,
  'unexpected grant: grantee=' || grantee || ' privilege=' || privilege_type AS details
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'cash_commitments'
  AND grantee IN ('PUBLIC','anon','authenticated')
  AND privilege_type IN ('INSERT','UPDATE','DELETE')
UNION ALL
SELECT
  'V7', 'PASS', 'cash_commitments',
  'no INSERT/UPDATE/DELETE grants found for PUBLIC, anon, or authenticated'
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.role_table_grants
  WHERE table_schema = 'public' AND table_name = 'cash_commitments'
    AND grantee IN ('PUBLIC','anon','authenticated')
    AND privilege_type IN ('INSERT','UPDATE','DELETE')
)
  ) v_v7
UNION ALL
  SELECT 80 AS sort_key, * FROM (
SELECT
  'V8' AS check_id,
  CASE
    WHEN array_agg(privilege_type::text ORDER BY privilege_type::text) = ARRAY['SELECT']::text[] THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'cash_commitments (authenticated grants)' AS object,
  'authenticated privileges found: ' || COALESCE(string_agg(privilege_type, ', ' ORDER BY privilege_type), '(none)') AS details
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'cash_commitments' AND grantee = 'authenticated'
  ) v_v8
UNION ALL
  SELECT 90 AS sort_key, * FROM (
SELECT
  'V9' AS check_id,
  CASE WHEN par.parameter_name IS NULL THEN 'FAIL'
       WHEN par.data_type <> e.expected_type THEN 'FAIL'
       ELSE 'PASS' END AS status,
  'validate_commitment_state arg#' || e.pos AS object,
  CASE
    WHEN par.parameter_name IS NULL THEN 'MISSING at position ' || e.pos || ' — expected ' || e.pname || ' ' || e.expected_type
    WHEN par.data_type <> e.expected_type THEN 'type mismatch at position ' || e.pos || ': expected ' || e.expected_type || ', found ' || par.data_type
    ELSE 'ok: ' || par.parameter_name || ' ' || par.data_type
  END AS details
FROM (
  VALUES
    (1,'p_id','uuid'),
    (2,'p_status','text'),
    (3,'p_resolved_model_week','integer'),
    (4,'p_reflected_model_week','integer'),
    (5,'p_resolution_type','text'),
    (6,'p_origin_model_week','integer'),
    (7,'p_amount_cents','integer'),
    (8,'p_original_amount_cents','integer'),
    (9,'p_required_or_discretionary','text'),
    (10,'p_affects_deployable_cash','boolean'),
    (11,'p_cleared_date','date'),
    (12,'p_resolution_notes','text')
) AS e(pos, pname, expected_type)
LEFT JOIN information_schema.routines r
  ON r.routine_schema = 'public' AND r.routine_name = 'validate_commitment_state'
LEFT JOIN information_schema.parameters par
  ON par.specific_name = r.specific_name AND par.ordinal_position = e.pos
ORDER BY e.pos
  ) v_v9
UNION ALL
  SELECT 91 AS sort_key, * FROM (
SELECT
  'V9a' AS check_id,
  CASE WHEN COUNT(*) = 12 THEN 'PASS' ELSE 'FAIL' END AS status,
  'validate_commitment_state (param count)' AS object,
  'expected 12 parameters, found ' || COUNT(*)::text AS details
FROM information_schema.routines r
JOIN information_schema.parameters par ON par.specific_name = r.specific_name
WHERE r.routine_schema = 'public' AND r.routine_name = 'validate_commitment_state'
  ) v_v9a
UNION ALL
  SELECT 100 AS sort_key, * FROM (
SELECT
  'V10' AS check_id,
  CASE WHEN r.security_type = 'INVOKER' THEN 'PASS' ELSE 'FAIL' END AS status,
  'validate_commitment_state (security_type)' AS object,
  'security_type=' || COALESCE(r.security_type, 'FUNCTION NOT FOUND') AS details
FROM information_schema.routines r
WHERE r.routine_schema = 'public' AND r.routine_name = 'validate_commitment_state'
  ) v_v10
UNION ALL
  SELECT 110 AS sort_key, * FROM (
SELECT 'V11' AS check_id,
  CASE WHEN NOT has_function_privilege('anon',
    'public.validate_commitment_state(UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END AS status,
  'validate_commitment_state (anon EXECUTE)' AS object,
  'expected false (no grant ever issued)' AS details
UNION ALL
SELECT 'V11',
  CASE WHEN NOT has_function_privilege('authenticated',
    'public.validate_commitment_state(UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END,
  'validate_commitment_state (authenticated EXECUTE)',
  'expected false (no grant ever issued — internal helper, called only by the two SECURITY DEFINER RPCs)'
  ) v_v11
UNION ALL
  SELECT 120 AS sort_key, * FROM (
SELECT
  'V12' AS check_id,
  CASE WHEN par.parameter_name IS NULL THEN 'FAIL'
       WHEN par.data_type <> e.expected_type THEN 'FAIL'
       ELSE 'PASS' END AS status,
  'save_reconciliation_with_commitments arg#' || e.pos AS object,
  CASE
    WHEN par.parameter_name IS NULL THEN 'MISSING at position ' || e.pos || ' — expected ' || e.pname || ' ' || e.expected_type
    WHEN par.data_type <> e.expected_type THEN 'type mismatch at position ' || e.pos || ': expected ' || e.expected_type || ', found ' || par.data_type
    ELSE 'ok: ' || par.parameter_name || ' ' || par.data_type
  END AS details
FROM (
  VALUES
    (1,'p_week_num','integer'),
    (2,'p_model_year','integer'),
    (3,'p_chk','numeric'),
    (4,'p_sav','numeric'),
    (5,'p_amx','numeric'),
    (6,'p_tax','numeric'),
    (7,'p_lc','numeric'),
    (8,'p_balance_basis','text'),
    (9,'p_recorded_at','timestamp with time zone'),
    (10,'p_new_commitments','jsonb'),
    (11,'p_patched','jsonb')
) AS e(pos, pname, expected_type)
LEFT JOIN information_schema.routines r
  ON r.routine_schema = 'public' AND r.routine_name = 'save_reconciliation_with_commitments'
LEFT JOIN information_schema.parameters par
  ON par.specific_name = r.specific_name AND par.ordinal_position = e.pos
ORDER BY e.pos
  ) v_v12
UNION ALL
  SELECT 121 AS sort_key, * FROM (
SELECT
  'V12a' AS check_id,
  CASE WHEN COUNT(*) = 11 THEN 'PASS' ELSE 'FAIL' END AS status,
  'save_reconciliation_with_commitments (param count)' AS object,
  'expected 11 parameters, found ' || COUNT(*)::text AS details
FROM information_schema.routines r
JOIN information_schema.parameters par ON par.specific_name = r.specific_name
WHERE r.routine_schema = 'public' AND r.routine_name = 'save_reconciliation_with_commitments'
  ) v_v12a
UNION ALL
  SELECT 130 AS sort_key, * FROM (
SELECT
  'V13' AS check_id,
  CASE WHEN r.security_type = 'DEFINER' THEN 'PASS' ELSE 'FAIL' END AS status,
  'save_reconciliation_with_commitments (security_type)' AS object,
  'security_type=' || COALESCE(r.security_type, 'FUNCTION NOT FOUND') AS details
FROM information_schema.routines r
WHERE r.routine_schema = 'public' AND r.routine_name = 'save_reconciliation_with_commitments'
  ) v_v13
UNION ALL
  SELECT 131 AS sort_key, * FROM (
SELECT
  'V13a' AS check_id,
  CASE WHEN array_to_string(p.proconfig, ',') ILIKE '%search_path=public%' THEN 'PASS' ELSE 'FAIL' END AS status,
  'save_reconciliation_with_commitments (search_path pin)' AS object,
  'proconfig=' || COALESCE(array_to_string(p.proconfig, ', '), '(none set — VULNERABLE)') AS details
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'save_reconciliation_with_commitments'
  ) v_v13a
UNION ALL
  SELECT 140 AS sort_key, * FROM (
SELECT 'V14' AS check_id,
  CASE WHEN NOT has_function_privilege('anon',
    'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END AS status,
  'save_reconciliation_with_commitments (anon EXECUTE)' AS object,
  'expected false' AS details
UNION ALL
SELECT 'V14',
  CASE WHEN has_function_privilege('authenticated',
    'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END,
  'save_reconciliation_with_commitments (authenticated EXECUTE)',
  'expected true (explicit GRANT in migration section 7)'
  ) v_v14
UNION ALL
  SELECT 150 AS sort_key, * FROM (
SELECT
  'V15' AS check_id,
  CASE WHEN par.parameter_name IS NULL THEN 'FAIL'
       WHEN par.data_type <> e.expected_type THEN 'FAIL'
       ELSE 'PASS' END AS status,
  'repair_commitments_for_week arg#' || e.pos AS object,
  CASE
    WHEN par.parameter_name IS NULL THEN 'MISSING at position ' || e.pos || ' — expected ' || e.pname || ' ' || e.expected_type
    WHEN par.data_type <> e.expected_type THEN 'type mismatch at position ' || e.pos || ': expected ' || e.expected_type || ', found ' || par.data_type
    ELSE 'ok: ' || par.parameter_name || ' ' || par.data_type
  END AS details
FROM (
  VALUES
    (1,'p_week_num','integer'),
    (2,'p_model_year','integer'),
    (3,'p_balance_basis','text'),
    (4,'p_new_commitments','jsonb'),
    (5,'p_patched','jsonb')
) AS e(pos, pname, expected_type)
LEFT JOIN information_schema.routines r
  ON r.routine_schema = 'public' AND r.routine_name = 'repair_commitments_for_week'
LEFT JOIN information_schema.parameters par
  ON par.specific_name = r.specific_name AND par.ordinal_position = e.pos
ORDER BY e.pos
  ) v_v15
UNION ALL
  SELECT 151 AS sort_key, * FROM (
SELECT
  'V15a' AS check_id,
  CASE WHEN COUNT(*) = 5 THEN 'PASS' ELSE 'FAIL' END AS status,
  'repair_commitments_for_week (param count)' AS object,
  'expected 5 parameters, found ' || COUNT(*)::text AS details
FROM information_schema.routines r
JOIN information_schema.parameters par ON par.specific_name = r.specific_name
WHERE r.routine_schema = 'public' AND r.routine_name = 'repair_commitments_for_week'
  ) v_v15a
UNION ALL
  SELECT 160 AS sort_key, * FROM (
SELECT
  'V16' AS check_id,
  CASE WHEN r.security_type = 'DEFINER' THEN 'PASS' ELSE 'FAIL' END AS status,
  'repair_commitments_for_week (security_type)' AS object,
  'security_type=' || COALESCE(r.security_type, 'FUNCTION NOT FOUND') AS details
FROM information_schema.routines r
WHERE r.routine_schema = 'public' AND r.routine_name = 'repair_commitments_for_week'
  ) v_v16
UNION ALL
  SELECT 161 AS sort_key, * FROM (
SELECT
  'V16a' AS check_id,
  CASE WHEN array_to_string(p.proconfig, ',') ILIKE '%search_path=public%' THEN 'PASS' ELSE 'FAIL' END AS status,
  'repair_commitments_for_week (search_path pin)' AS object,
  'proconfig=' || COALESCE(array_to_string(p.proconfig, ', '), '(none set — VULNERABLE)') AS details
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'repair_commitments_for_week'
  ) v_v16a
UNION ALL
  SELECT 170 AS sort_key, * FROM (
SELECT 'V17' AS check_id,
  CASE WHEN NOT has_function_privilege('anon',
    'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END AS status,
  'repair_commitments_for_week (anon EXECUTE)' AS object,
  'expected false' AS details
UNION ALL
SELECT 'V17',
  CASE WHEN has_function_privilege('authenticated',
    'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)', 'EXECUTE')
    THEN 'PASS' ELSE 'FAIL' END,
  'repair_commitments_for_week (authenticated EXECUTE)',
  'expected true (explicit GRANT in migration section 8)'
  ) v_v17
UNION ALL
  SELECT 180 AS sort_key, * FROM (
SELECT
  'V18' AS check_id,
  'REVIEW' AS status,
  routine_name AS object,
  'grantee=' || grantee || ' | privilege=' || privilege_type AS details
FROM information_schema.role_routine_grants
WHERE routine_schema = 'public'
  AND routine_name IN ('validate_commitment_state','save_reconciliation_with_commitments','repair_commitments_for_week')
ORDER BY routine_name, grantee
  ) v_v18
UNION ALL
  SELECT 190 AS sort_key, * FROM (
SELECT
  'V19' AS check_id,
  'REVIEW' AS status,
  'summary' AS object,
  'weekly_reconciliations.balance_basis: ' ||
    (SELECT COUNT(*)::text FROM information_schema.columns WHERE table_schema='public' AND table_name='weekly_reconciliations' AND column_name='balance_basis') ||
    ' | cash_commitments table: ' ||
    (SELECT COUNT(*)::text FROM pg_tables WHERE schemaname='public' AND tablename='cash_commitments') ||
    ' | cash_commitments columns found: ' ||
    (SELECT COUNT(*)::text FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments') || '/28' ||
    ' | named CHECK constraints found: ' ||
    (SELECT COUNT(*)::text FROM pg_constraint WHERE conrelid='public.cash_commitments'::regclass AND contype='c'
       AND conname IN ('chk_week_origin_range','chk_week_reflected_range','chk_week_resolved_range',
                        'chk_resolved_after_origin','chk_reflected_after_origin',
                        'chk_source_account_only_truist','chk_cleared_reflected_before_resolved')) || '/7' ||
    ' | functions found: ' ||
    (SELECT COUNT(*)::text FROM information_schema.routines WHERE routine_schema='public'
       AND routine_name IN ('validate_commitment_state','save_reconciliation_with_commitments','repair_commitments_for_week')) || '/3'
  AS details
  ) v_v19
) all_checks
ORDER BY sort_key, object;
-- ═══════════════════════════════════════════════════════════════════
