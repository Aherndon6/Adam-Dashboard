-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Gate 2 — SUB-PHASE 1: CURRENT-STATE INSPECTION (READ ONLY). Authored, NOT executed.
-- Reports the exact pre-Gate-2 staging state so the operator can capture a baseline before any test.
-- Hard-stops on the wrong staging fingerprint. Nothing is mutated. PRODUCTION IS NOT TOUCHED.
-- Reports: all weekly_reconciliations rows; all cash_commitments rows; snapshots grouped by week+source;
-- any existing synthetic Gate-2 artifacts; any existing G2-20 helper/trigger; current EXECUTE grants on
-- both new functions; current exact signatures; current function definitions + MD5s; Week-5 anchor
-- completeness; whether Week-6+ test state already exists.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
BEGIN
  -- EXACT staging fingerprint — production and any unknown/ambiguous environment hard-stop.
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production system_identifier — Gate 2 is staging-only. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint (sysid=%, appenv total=%, staging=%). Aborting.', v_sysid, v_appenv_total, v_appenv_staging; END IF;
  RAISE NOTICE 'INSPECT: staging fingerprint OK; identity current_user=%, session_user=%', current_user, session_user;
END $$;

-- ── (a) actual column contracts (never inferred — reported from the catalog) ──
SELECT 'cols-weekly_reconciliations' AS check, ordinal_position AS ord, column_name, data_type, is_nullable, column_default
  FROM information_schema.columns WHERE table_schema='public' AND table_name='weekly_reconciliations' ORDER BY ordinal_position;
SELECT 'cols-cash_commitments' AS check, ordinal_position AS ord, column_name, data_type, is_nullable, column_default
  FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' ORDER BY ordinal_position;
SELECT 'cols-goal_funding_snapshots' AS check, ordinal_position AS ord, column_name, data_type, is_nullable, column_default
  FROM information_schema.columns WHERE table_schema='public' AND table_name='goal_funding_snapshots' ORDER BY ordinal_position;

-- ── (b) all weekly_reconciliations rows (balance-free dump; synthetic staging values) ──
SELECT 'weekly_reconciliations' AS check, * FROM public.weekly_reconciliations ORDER BY week_num;

-- ── (c) all cash_commitments rows ──
SELECT 'cash_commitments' AS check, id, expected_item_id, model_year, origin_model_week, payee,
       commitment_class, required_or_discretionary, amount_cents, status, reflected_model_week,
       resolved_model_week, notes, created_at, updated_at
  FROM public.cash_commitments ORDER BY origin_model_week, expected_item_id;

-- ── (d) snapshot rows grouped by week and source ──
SELECT 'snapshots-by-week-source' AS check, model_year, week_num, source, count(*) AS n,
       min(funded_amount) AS min_amt, max(funded_amount) AS max_amt
  FROM public.goal_funding_snapshots GROUP BY model_year, week_num, source ORDER BY week_num, source;
-- full snapshot dump (goal-level; synthetic values)
SELECT 'snapshots-detail' AS check, model_year, week_num, goal_id, funded_amount, source, note
  FROM public.goal_funding_snapshots ORDER BY week_num, source, goal_id;

-- ── (e) existing synthetic Gate-2 artifacts (should be none at start) ──
SELECT 'existing-gate2-snapshots' AS check, count(*) AS marked_gate2
  FROM public.goal_funding_snapshots WHERE COALESCE(note,'') LIKE '%[GATE2]%';
SELECT 'existing-gate2-commitments' AS check, count(*) AS marked_gate2
  FROM public.cash_commitments WHERE expected_item_id LIKE '\_\_GATE2\_%' OR expected_item_id LIKE '\_\_ATOMIC\_TEST\_%';
SELECT 'existing-week6plus-snapshots' AS check, count(*) AS n
  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6;
SELECT 'existing-week6plus-recon' AS check, count(*) AS n
  FROM public.weekly_reconciliations WHERE week_num >= 6;

-- ── (f) any existing G2-20 helper/trigger (must be absent) ──
SELECT 'g2-20-helper-present' AS check, (to_regproc('public._gf_atomic_test_fail') IS NOT NULL) AS helper_present;
SELECT 'g2-20-trigger-present' AS check, count(*) AS trigger_rows
  FROM pg_trigger WHERE tgname='_gf_atomic_test_fail_trg' AND NOT tgisinternal;

-- ── (g) current EXECUTE grants on both new functions (temporary grant should be ACTIVE now) ──
SELECT 'grant-wrapper' AS check,
       has_function_privilege('authenticated','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE') AS authenticated_exec,
       has_function_privilege('anon','public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE') AS anon_exec;
SELECT 'grant-optionb' AS check,
       has_function_privilege('authenticated','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE') AS authenticated_exec,
       has_function_privilege('anon','public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE') AS anon_exec;

-- ── (h) current exact signatures + SECURITY DEFINER + search_path of both new functions ──
SELECT 'signatures' AS check, p.proname, pg_get_function_identity_arguments(p.oid) AS args,
       p.prosecdef AS security_definer, p.proconfig AS settings
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN ('save_weekly_closeout_with_snapshots','correct_goal_funding_snapshot')
  ORDER BY p.proname;

-- ── (i) current function definitions + MD5s (both NEW functions AND the two deployed dependencies) ──
SELECT 'md5-wrapper'  AS check, md5(pg_get_functiondef('public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)'::regprocedure)) AS md5;
SELECT 'md5-optionb'  AS check, md5(pg_get_functiondef('public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)'::regprocedure)) AS md5;
SELECT 'md5-recon-dep' AS check,
       md5(pg_get_functiondef('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)'::regprocedure)) AS md5,
       '1bfde751ac647c5e9a25ba168d08150c' AS expected_baseline;
SELECT 'md5-snapshot-dep' AS check,
       md5(pg_get_functiondef('public.save_goal_funding_snapshots(INT,INT,JSONB)'::regprocedure)) AS md5,
       '154231b3f180349ec328f08ccbe77076' AS expected_baseline;

-- ── (j) Week-5 anchor completeness (must be exactly the eligible nine, opening_anchor, marked) ──
SELECT 'week5-anchor-completeness' AS check,
       count(*) FILTER (WHERE source='opening_anchor'
         AND goal_id = ANY(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'])
         AND COALESCE(note,'') LIKE '%[STAGING-FIXTURE]%') AS eligible_anchor_marked,
       count(*) AS total_week5_rows
  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5;
SELECT 'week5-anchor-values' AS check, goal_id, funded_amount, source, note
  FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=5 ORDER BY goal_id;

-- ── (k) whether Week-6+ test state already exists (should be zero at start) ──
SELECT 'week6plus-state-summary' AS check,
       (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num >= 6) AS recon_week6plus,
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num >= 6) AS snap_week6plus;

COMMIT;
