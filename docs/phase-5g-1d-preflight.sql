-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Slice 2 — PREFLIGHT (READ ONLY). Authored, NOT executed.
--
--   TARGET ......... PRODUCTION  Adam-Dashboard (usayoldrawwmjsmretin)   [staging-first: run on staging too]
--   NEVER MUTATES .. read-only; no writes, no grants, no DDL.
--
-- Non-financial structural fingerprint only (no household balances/targets). Confirms the
-- environment, that the two DEPLOYED RPCs exist with their exact signatures (captures their
-- definition hashes for the byte-unchanged proof), that is_owner()/can_write_financials()
-- exist (Gate A), that the two NEW functions do NOT yet exist, and that the Week-5 opening
-- anchor is complete by goal_id (nine eligible opening_anchor rows; the two wewe_* correction
-- rows are tolerated).  Spec: docs/phase-5g-1d-slice2-proposed-2026-07-11.md (Rev 8).
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

-- ── READ-ONLY QUERY Adam must run to PIN the staging system_identifier (fill c_staging_sysid
--    in migration.sql + rollback.sql + below). Do NOT guess it. On STAGING run:
--       SELECT system_identifier FROM pg_control_system();
--       SELECT env FROM public.app_environment;                    -- expect one row, env='staging'
--    Paste the returned system_identifier as c_staging_sysid (a BIGINT) in all three files LOCAL.
DO $$
DECLARE
  v_sysid BIGINT; v_tx BIGINT; v_reg_ids BIGINT; v_cnt INT; v_unmarked INT;
  v_has_appenv BOOLEAN; v_appenv_total INT; v_appenv_staging INT; v_staging_marker BOOLEAN; v_env TEXT;
  v_recon_owner TEXT; v_snap_owner TEXT; v_isowner_owner TEXT; v_canwrite_owner TEXT;  -- P0-3 SECURITY DEFINER owner baseline
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 0;  -- <<FILL: exact staging system_identifier (same value in migration/rollback). 0 = UNSET.
  c_fixture_marker CONSTANT TEXT := '[STAGING-FIXTURE]';  -- required note marker on the synthetic staging anchor
  c_eligible9 CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska',
                                       'bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
BEGIN
  RAISE NOTICE 'EXECUTION IDENTITY: current_user=%, session_user=%', current_user, session_user;

  -- (a) baseline + 5G-1C-2 schema present
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL
     OR to_regclass('public.weekly_reconciliations') IS NULL OR to_regclass('public.cash_commitments') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing. Aborting.'; END IF;
  IF to_regclass('public.goal_funding_snapshots') IS NULL OR to_regclass('public.goal_registry') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots / goal_registry missing (E1 not applied?). Aborting.'; END IF;

  -- (b) EXACT environment fingerprint — production OR approved staging; anything else hard-stops.
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  v_has_appenv := to_regclass('public.app_environment') IS NOT NULL;
  v_staging_marker := false;
  IF v_has_appenv THEN   -- only query app_environment when it exists (bare EXISTS is planned even under AND)
    SELECT count(*), count(*) FILTER (WHERE env = 'staging') INTO v_appenv_total, v_appenv_staging
      FROM public.app_environment;
    v_staging_marker := (v_appenv_total = 1 AND v_appenv_staging = 1);  -- exactly one row, env='staging', no others
  END IF;
  IF v_sysid = c_prod_sysid AND NOT v_has_appenv THEN v_env := 'production';
  ELSIF v_sysid = c_staging_sysid AND v_has_appenv AND v_staging_marker THEN v_env := 'staging';
  ELSE
    RAISE EXCEPTION 'HARD STOP: unknown/ambiguous environment (sysid=%, app_environment=%, staging_marker=%). Pin c_staging_sysid before staging. Aborting.', v_sysid, v_has_appenv, v_staging_marker;
  END IF;
  RAISE NOTICE 'PREFLIGHT environment: %', v_env;

  -- (b1) canonical registry ids (both environments)
  SELECT count(*) INTO v_reg_ids FROM public.goal_registry
   WHERE id IN ('adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529',
                'preston_529','bryce_vehicle','christmas_cruise','adam_401k','wewe_rccl','wewe_dcl','taxable_etf');
  IF v_reg_ids <> 13 THEN RAISE EXCEPTION 'HARD STOP: goal_registry canonical-id count % <> 13. Aborting.', v_reg_ids; END IF;

  -- (b2) ENVIRONMENT-SPECIFIC structural checks
  IF v_env = 'production' THEN
    -- production keeps the transaction-count structural floor (a production fingerprint)
    SELECT count(*) INTO v_tx FROM public.transactions;
    IF v_tx < 40 THEN RAISE EXCEPTION 'HARD STOP: transactions=% < 40 production floor. Aborting.', v_tx; END IF;
  ELSE
    -- staging: do NOT require production transaction volume. Require the EXACT approved synthetic
    -- Week-5 fixture: the eligible-nine SET, each source='opening_anchor' AND carrying the marker,
    -- with NO eligible wk5 opening_anchor row left unmarked (proves the whole set is synthetic).
    SELECT count(DISTINCT goal_id) INTO v_cnt FROM public.goal_funding_snapshots
      WHERE model_year=2026 AND week_num=5 AND source='opening_anchor'
        AND goal_id = ANY(c_eligible9) AND COALESCE(note,'') LIKE '%'||c_fixture_marker||'%';
    IF v_cnt <> 9 THEN RAISE EXCEPTION 'HARD STOP: staging synthetic Week-5 fixture: only % of the eligible nine are opening_anchor+marked "%". Aborting.', v_cnt, c_fixture_marker; END IF;
    SELECT count(*) INTO v_unmarked FROM public.goal_funding_snapshots
      WHERE model_year=2026 AND week_num=5 AND source='opening_anchor'
        AND goal_id = ANY(c_eligible9) AND COALESCE(note,'') NOT LIKE '%'||c_fixture_marker||'%';
    IF v_unmarked <> 0 THEN RAISE EXCEPTION 'HARD STOP: % eligible wk5 opening_anchor row(s) are NOT marked "%" — mixed/real data on staging. Aborting.', v_unmarked, c_fixture_marker; END IF;
  END IF;

  -- (c) Gate A predicates exist
  IF to_regprocedure('public.is_owner()') IS NULL OR to_regprocedure('public.can_write_financials()') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: is_owner()/can_write_financials() missing (role enforcement not applied). Aborting.'; END IF;

  -- (d) the two DEPLOYED RPCs exist with EXACT signatures (byte-unchanged baseline)
  IF to_regprocedure('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: deployed reconciliation RPC signature not found. Aborting.'; END IF;
  IF to_regprocedure('public.save_goal_funding_snapshots(INT,INT,JSONB)') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: deployed snapshot RPC signature not found. Aborting.'; END IF;

  -- (d1) SECURITY DEFINER OWNER BASELINE (P0-3): capture the owner of every deployed function the
  -- new wrapper/Option B will run AS (they are created owned by whoever runs the migration) or CALL
  -- as the definer owner. That owner MUST be a single trusted role — never a client role — and the
  -- migration pins the two new functions to exactly this owner, so the Gate-B lockdown can prove the
  -- definer identity still executes the (soon-to-be-authenticated-revoked) inner RPCs.
  v_recon_owner    := (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)'::regprocedure);
  v_snap_owner     := (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'public.save_goal_funding_snapshots(INT,INT,JSONB)'::regprocedure);
  v_isowner_owner  := (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'public.is_owner()'::regprocedure);
  v_canwrite_owner := (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid = 'public.can_write_financials()'::regprocedure);
  RAISE NOTICE 'OWNER BASELINE: recon=%, snapshot=%, is_owner=%, can_write_financials=%', v_recon_owner, v_snap_owner, v_isowner_owner, v_canwrite_owner;
  IF v_recon_owner IS NULL OR v_recon_owner <> v_snap_owner OR v_recon_owner <> v_isowner_owner OR v_recon_owner <> v_canwrite_owner THEN
    RAISE EXCEPTION 'HARD STOP: deployed SECURITY DEFINER functions do not share one owner (recon=%, snapshot=%, is_owner=%, can_write=%). The new wrapper/Option B must be created by that same trusted owner. Aborting.', v_recon_owner, v_snap_owner, v_isowner_owner, v_canwrite_owner; END IF;
  IF v_recon_owner IN ('anon','authenticated','public') THEN
    RAISE EXCEPTION 'HARD STOP: deployed functions are owned by a client role (%) — never acceptable for SECURITY DEFINER. Aborting.', v_recon_owner; END IF;

  -- (e) the two NEW functions must NOT already exist (fresh deploy)
  IF to_regprocedure('public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: wrapper already exists — not a fresh deploy. Aborting.'; END IF;
  IF to_regprocedure('public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: Option B already exists — not a fresh deploy. Aborting.'; END IF;
  IF to_regprocedure('public._gf_is_finite_amount(numeric)') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: unexpected _gf_is_finite_amount helper exists (this package inlines, never a helper). Aborting.'; END IF;

  -- (f) complete Week-5 opening anchor BY ID (nine eligible; wewe_* correction rows tolerated)
  SELECT count(*) INTO v_cnt FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=5 AND source='opening_anchor' AND goal_id = ANY(c_eligible9);
  IF v_cnt <> 9 THEN RAISE EXCEPTION 'HARD STOP: Week-5 opening anchor incomplete (% of 9 eligible opening_anchor rows). Aborting.', v_cnt; END IF;

  RAISE NOTICE 'PREFLIGHT PASS: fingerprint OK; deployed RPCs present; new functions absent; Week-5 anchor complete (9 eligible).';
END $$;

-- Byte-unchanged BASELINE hashes for the two deployed RPCs (compare in validation post-migration).
SELECT 'baseline-recon-rpc'    AS check, md5(pg_get_functiondef('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)'::regprocedure)) AS def_md5;
SELECT 'baseline-snapshot-rpc' AS check, md5(pg_get_functiondef('public.save_goal_funding_snapshots(INT,INT,JSONB)'::regprocedure)) AS def_md5;

-- SECURITY DEFINER OWNER BASELINE (P0-3): committable evidence — the migration pins the two NEW
-- functions to this exact owner; validation + the Gate-B lockdown re-assert it (owner never drifts).
SELECT 'definer-owner-baseline' AS check, p.proname, pg_get_userbyid(p.proowner) AS owner, p.prosecdef AS security_definer
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN
  ('save_reconciliation_with_commitments','save_goal_funding_snapshots','is_owner','can_write_financials')
ORDER BY p.proname;

-- Reserved advisory namespace must be unused by any other object (documented invariant).
SELECT 'advisory-namespace' AS check, 1734501000 AS reserved_ns_for_5g_1d_closeout_and_correction;

COMMIT;
