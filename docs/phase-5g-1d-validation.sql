-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Slice 2 — VALIDATION (READ ONLY). Authored, NOT executed.
-- Run AFTER the migration (staging or production inert deploy). Proves: exactly two new
-- functions; INERT grant state (no PUBLIC/anon/authenticated EXECUTE); the two deployed RPCs
-- byte-unchanged; structural asserts (SECURITY DEFINER, search_path, no dynamic SQL, inlined
-- finiteness rejection present in BOTH, per-goal goal_registry FOR UPDATE present in BOTH,
-- reserved advisory namespace, no _gf_is_finite_amount helper). Balance-free.
-- The preflight baseline md5s (recon + snapshot RPC) must be pasted into v_recon_md5 /
-- v_snap_md5 below (LOCAL only; they are NON-secret function-definition hashes, not balances).
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_wrapper regprocedure := to_regprocedure('public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)');
  v_optb    regprocedure := to_regprocedure('public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)');
  v_recon   regprocedure := to_regprocedure('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)');
  v_snap    regprocedure := to_regprocedure('public.save_goal_funding_snapshots(INT,INT,JSONB)');
  v_recon_md5 TEXT := '<<PASTE preflight baseline-recon-rpc md5 LOCAL>>';
  v_snap_md5  TEXT := '<<PASTE preflight baseline-snapshot-rpc md5 LOCAL>>';
  v_grants INT; r RECORD;
BEGIN
  -- exactly two new functions exist; no third/helper
  IF v_wrapper IS NULL OR v_optb IS NULL THEN RAISE EXCEPTION 'V: wrapper/Option B not deployed'; END IF;
  IF to_regprocedure('public._gf_is_finite_amount(numeric)') IS NOT NULL THEN RAISE EXCEPTION 'V: unexpected _gf_is_finite_amount helper — must be inlined'; END IF;

  -- INERT grant state: no EXECUTE for anon/authenticated on either new function.
  -- (anon/authenticated INHERIT PUBLIC grants, so a PUBLIC EXECUTE would surface here too;
  --  has_function_privilege cannot take the PUBLIC pseudo-role directly.) Belt-and-suspenders:
  --  also assert proacl carries no explicit PUBLIC (=) grant.
  SELECT count(*) INTO v_grants FROM (
    SELECT 1 WHERE has_function_privilege('anon',         v_wrapper, 'EXECUTE')
    UNION ALL SELECT 1 WHERE has_function_privilege('authenticated',v_wrapper, 'EXECUTE')
    UNION ALL SELECT 1 WHERE has_function_privilege('anon',         v_optb,    'EXECUTE')
    UNION ALL SELECT 1 WHERE has_function_privilege('authenticated',v_optb,    'EXECUTE')) g;
  IF v_grants <> 0 THEN RAISE EXCEPTION 'V: functions are NOT inert — % anon/authenticated EXECUTE grant(s) present (expected 0 pre-activation)', v_grants; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, unnest(COALESCE(p.proacl, '{}'::aclitem[])) a
              WHERE p.oid IN (v_wrapper::oid, v_optb::oid) AND (a::text LIKE '=%X%')) THEN
    RAISE EXCEPTION 'V: an explicit PUBLIC EXECUTE grant is present (expected none pre-activation)'; END IF;

  -- byte-unchanged proof for the two deployed RPCs
  IF md5(pg_get_functiondef(v_recon)) IS DISTINCT FROM v_recon_md5 THEN RAISE EXCEPTION 'V: reconciliation RPC definition CHANGED'; END IF;
  IF md5(pg_get_functiondef(v_snap))  IS DISTINCT FROM v_snap_md5  THEN RAISE EXCEPTION 'V: snapshot RPC definition CHANGED'; END IF;

  -- structural asserts on BOTH new functions
  FOR r IN SELECT p.oid, p.proname, p.prosecdef, p.proconfig, pg_get_functiondef(p.oid) AS def
             FROM pg_proc p WHERE p.oid IN (v_wrapper::oid, v_optb::oid) LOOP
    IF NOT r.prosecdef THEN RAISE EXCEPTION 'V: % is not SECURITY DEFINER', r.proname; END IF;
    IF NOT (r.proconfig @> ARRAY['search_path=public, pg_temp']) THEN RAISE EXCEPTION 'V: % search_path not pinned', r.proname; END IF;
    IF position('EXECUTE ' in r.def) > 0 AND position('EXECUTE FUNCTION' in r.def) = 0 THEN RAISE EXCEPTION 'V: % may contain dynamic EXECUTE', r.proname; END IF;
    -- straight-line: no EXCEPTION handler (checks the handler syntax 'EXCEPTION WHEN', NOT ordinary 'RAISE EXCEPTION')
    IF position('EXCEPTION WHEN' in r.def) <> 0 THEN RAISE EXCEPTION 'V: % must not contain an EXCEPTION handler (straight-line, no swallowed errors)', r.proname; END IF;
    -- inlined finiteness rejection present
    IF position($q$<> 'NaN'::numeric$q$ in r.def) = 0
       OR position($q$<> 'Infinity'::numeric$q$ in r.def) = 0
       OR position($q$<> '-Infinity'::numeric$q$ in r.def) = 0 THEN
      RAISE EXCEPTION 'V: % missing inlined NaN/Infinity/-Infinity rejection', r.proname; END IF;
    -- per-goal goal_registry FOR UPDATE present
    IF position('goal_registry' in r.def) = 0 OR position('FOR UPDATE' in r.def) = 0 THEN
      RAISE EXCEPTION 'V: % missing goal_registry FOR UPDATE mutex', r.proname; END IF;
    -- registry-drift guard present (wrapper: eligible-nine count; Option B: FOUND after FOR UPDATE)
    IF position('registry drift' in r.def) = 0 THEN
      RAISE EXCEPTION 'V: % missing a registry-drift guard', r.proname; END IF;
    -- reserved advisory namespace present
    IF position('1734501000' in r.def) = 0 THEN RAISE EXCEPTION 'V: % missing reserved advisory namespace', r.proname; END IF;
  END LOOP;

  -- old reconciliation RPC direct authenticated EXECUTE still PRESENT at Slice-2 (revoked only in Slice-7)
  IF NOT has_function_privilege('authenticated', v_recon, 'EXECUTE') THEN
    RAISE EXCEPTION 'V: reconciliation RPC authenticated EXECUTE already revoked — that is a Slice-7 action, not Slice-2'; END IF;

  RAISE NOTICE 'VALIDATION PASS: two functions inert; deployed RPCs byte-unchanged; structural + inline + mutex + namespace OK; old-RPC grant intact.';
END $$;

-- Grant matrix snapshot (evidence). anon/authenticated only — they inherit any PUBLIC grant,
-- and has_function_privilege cannot take the PUBLIC pseudo-role.
SELECT 'grant-matrix' AS check, n AS grantee,
       has_function_privilege(n,'public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)','EXECUTE') AS wrapper_exec,
       has_function_privilege(n,'public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)','EXECUTE') AS optionb_exec
FROM (VALUES ('anon'),('authenticated')) AS g(n);

COMMIT;
