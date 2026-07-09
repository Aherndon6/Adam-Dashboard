-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 RLS Behavioral Smoke — GATE 1 (policy-level)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — STAGING ONLY (project pkwotgqivgaapwuqgwqb). DO NOT RUN on production
-- (usayoldrawwmjsmretin). Run AFTER re-applying phase-5g-1c-2-migration.sql on a
-- freshly-marked staging DB, and AFTER seeding the two [STAGING] app_users rows.
--
-- WHAT THIS IS: a POLICY-LEVEL RLS + RPC smoke via SET LOCAL ROLE +
-- request.jwt.claims, entirely inside one transaction that ROLLS BACK. It proves
-- the table policies (SELECT/INSERT/UPDATE), grants, TRUNCATE/DELETE protection,
-- AND the save_goal_funding_snapshots RPC end-to-end (authorized happy-path,
-- idempotent re-upsert, and the input-validation rejection matrix) as the
-- impersonated role. It is NOT a complete real-caller smoke — the Auth/JWT/
-- PostgREST path is Gate 2 (phase-5g-1c-2-rls-smoke-gate2.md). RLS is not
-- "cleared" until Gate 2 passes.
--
-- SAFETY: outer BEGIN/ROLLBACK — nothing here persists. Every expected-error probe
-- is caught with an inner BEGIN/EXCEPTION so it cannot poison the transaction.
-- Any deviation from the expected matrix RAISEs EXCEPTION and aborts loudly.
--   * RLS/grant denials are caught as `insufficient_privilege` (SQLSTATE 42501).
--   * RPC validation denials RAISE plain EXCEPTIONs — caught as OTHERS with an
--     asserted SQLERRM substring so an unrelated failure cannot masquerade as an
--     expected denial.
--   * Expected-denial table INSERTs set created_by_user_id = NULL so the ONLY
--     possible rejection is RLS (a NULL FK column is not FK-checked).
--
-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ ⚠ DO NOT RUN THE COMMITTED FILE DIRECTLY.                                  │
-- │ 1. COPY this file to scratchpad (keeps real staging IDs out of git).       │
-- │ 2. REPLACE all four tokens with real STAGING values.                       │
-- │ 3. Run the scratchpad copy on STAGING only.                                │
-- │ The TOKEN GUARD below hard-stops (friendly message, before any UUID cast)  │
-- │ if any token is still unreplaced.                                          │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Tokens (staging values only; fill the scratch copy or use psql \set):
--   <<W_UUID>>   auth.users id of the [STAGING] writer  (role owner/household_admin)
--   <<W_EMAIL>>  email of the [STAGING] writer          (matches app_users)
--   <<V_UUID>>   auth.users id of the [STAGING] viewer  (role viewer)
--   <<V_EMAIL>>  email of the [STAGING] viewer          (matches app_users)
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ── STAGING GUARD ────────────────────────────────────────────────────────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.'; END IF;
  IF to_regclass('public.goal_funding_snapshots') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots absent. Re-apply phase-5g-1c-2-migration.sql before the smoke. Aborting.'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (amex_gold=-8248.50). Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (transactions=% > 25). Aborting.', v_tx; END IF;
END $$;

-- ── TOKEN GUARD: friendly hard-stop BEFORE any UUID cast if tokens unreplaced ─
-- Pure text comparison on the token LITERALS: if a token was replaced with a real
-- value it no longer contains '<<', so this passes; if unreplaced it hard-stops
-- with a readable message instead of an "invalid input syntax for type uuid" cast
-- error deeper in the file.
DO $$
BEGIN
  IF '<<W_UUID>>'  LIKE '%<<%' OR '<<W_EMAIL>>' LIKE '%<<%'
  OR '<<V_UUID>>'  LIKE '%<<%' OR '<<V_EMAIL>>' LIKE '%<<%' THEN
    RAISE EXCEPTION 'HARD STOP: identity tokens not replaced. Copy this file to scratchpad and substitute <<W_UUID>>/<<W_EMAIL>>/<<V_UUID>>/<<V_EMAIL>> with real STAGING values before running.';
  END IF;
END $$;

-- ── RPC PREREQ: at least one reconciled week must exist ──────────────────────
-- The RPC checks the reconciled-week guard BEFORE per-row validation, so the
-- rejection matrix (and the happy-path) are only meaningful against a reconciled
-- week. Fail fast here rather than mis-firing probes later.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations) THEN
    RAISE EXCEPTION 'HARD STOP: no reconciled week exists; seed/record a weekly_reconciliations row before the Gate 1 RPC smoke.';
  END IF;
END $$;

-- ── IDENTITY PREREQ: the two [STAGING] app_users + auth.users rows exist ─────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.app_users
                 WHERE auth_user_id = '<<W_UUID>>' AND lower(email)=lower('<<W_EMAIL>>')
                   AND active AND role IN ('owner','household_admin')) THEN
    RAISE EXCEPTION 'HARD STOP: writer app_users row missing/misconfigured. Aborting.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.app_users
                 WHERE auth_user_id = '<<V_UUID>>' AND lower(email)=lower('<<V_EMAIL>>')
                   AND active AND role = 'viewer') THEN
    RAISE EXCEPTION 'HARD STOP: viewer app_users row missing/misconfigured (active, role=viewer). Aborting.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id='<<W_UUID>>') THEN
    RAISE EXCEPTION 'HARD STOP: writer auth.users row <<W_UUID>> missing (FK target). Aborting.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id='<<V_UUID>>') THEN
    RAISE EXCEPTION 'HARD STOP: viewer auth.users row <<V_UUID>> missing. Aborting.'; END IF;
  RAISE NOTICE 'PREREQ ok: writer + viewer identities present and configured.';
END $$;

-- ── PRE-SMOKE EXACT GRANT ASSERTIONS (run as owner) ─────────────────────────
DO $$
DECLARE g TEXT[];
BEGIN
  SELECT array_agg(privilege_type ORDER BY privilege_type) INTO g
    FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name='goal_funding_snapshots' AND grantee='anon';
  IF g IS NOT NULL THEN RAISE EXCEPTION 'GRANT FAIL: anon has privileges % (expected none).', g; END IF;

  SELECT array_agg(privilege_type::text ORDER BY privilege_type::text) INTO g
    FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name='goal_funding_snapshots' AND grantee='authenticated';
  IF g IS DISTINCT FROM ARRAY['INSERT','SELECT','UPDATE']::text[] THEN
    RAISE EXCEPTION 'GRANT FAIL: goal_funding_snapshots authenticated grants = % (expected INSERT,SELECT,UPDATE).', g; END IF;

  IF has_table_privilege('authenticated','public.goal_funding_snapshots','DELETE')    THEN RAISE EXCEPTION 'GRANT FAIL: authenticated DELETE.'; END IF;
  IF has_table_privilege('authenticated','public.goal_funding_snapshots','TRUNCATE')  THEN RAISE EXCEPTION 'GRANT FAIL: authenticated TRUNCATE.'; END IF;
  IF has_table_privilege('authenticated','public.goal_funding_snapshots','REFERENCES')THEN RAISE EXCEPTION 'GRANT FAIL: authenticated REFERENCES.'; END IF;
  IF has_table_privilege('authenticated','public.goal_funding_snapshots','TRIGGER')   THEN RAISE EXCEPTION 'GRANT FAIL: authenticated TRIGGER.'; END IF;
  IF has_table_privilege('anon','public.goal_funding_snapshots','SELECT')             THEN RAISE EXCEPTION 'GRANT FAIL: anon SELECT.'; END IF;

  -- RPC EXECUTE: authenticated yes, anon no.
  IF NOT has_function_privilege('authenticated','public.save_goal_funding_snapshots(int,int,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT FAIL: authenticated lacks EXECUTE on the RPC.'; END IF;
  IF has_function_privilege('anon','public.save_goal_funding_snapshots(int,int,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT FAIL: anon has EXECUTE on the RPC.'; END IF;
  RAISE NOTICE 'GRANTS ok: exact authenticated set; anon empty; RPC EXECUTE authenticated-only.';
END $$;

-- ── GROUND-TRUTH SEED (owner insert; bypasses RLS by design) ─────────────────
-- One throwaway snapshot row (model_year 2099 cannot collide with live data) so
-- read-visibility probes have a target. A real, eligible goal_id is chosen so the
-- FK holds. Rolled back with the outer transaction.
DO $$
DECLARE v_goal TEXT;
BEGIN
  SELECT id INTO v_goal FROM public.goal_registry
   WHERE COALESCE(auto,false)=false AND id <> ALL (ARRAY['wewe_rccl','wewe_dcl','taxable_etf'])
   ORDER BY id LIMIT 1;
  IF v_goal IS NULL THEN RAISE EXCEPTION 'SETUP FAIL: no eligible goal_id in goal_registry.'; END IF;
  INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source,note)
    VALUES (2099,1,v_goal,100,'opening_anchor','__gate1_ground_truth__');
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- D — ANON (SET ROLE anon): every table op + the RPC permission-denied
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE ok BOOLEAN;
BEGIN
  PERFORM set_config('role','anon', true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF current_user <> 'anon' THEN RAISE EXCEPTION 'harness: anon role not applied (current_user=%).', current_user; END IF;

  ok := true;
  BEGIN PERFORM 1 FROM public.goal_funding_snapshots LIMIT 1; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON FAIL: SELECT was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source,created_by_user_id)
          VALUES (2099,2,'__x__',0,'opening_anchor',NULL);
    ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON FAIL: INSERT was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN TRUNCATE public.goal_funding_snapshots; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON FAIL: TRUNCATE was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026,1,'[]'::jsonb); ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON FAIL: RPC EXECUTE was NOT permission-denied.'; END IF;
  RAISE NOTICE 'D ANON PASS: harness ok; all table ops + RPC permission-denied.';
END $$;
RESET ROLE;

-- ══════════════════════════════════════════════════════════════════════════
-- C — UNAUTHORIZED AUTHENTICATED (valid claims, sub NOT in app_users)
--   SELECT -> 0 rows (RLS filters); INSERT -> RLS 42501; RPC -> not authorized
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE cnt INT; ok BOOLEAN;
BEGIN
  PERFORM set_config('role','authenticated', true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000000cc","email":"nobody-not-allowlisted@herndons.test","role":"authenticated"}', true);
  IF current_user <> 'authenticated' THEN RAISE EXCEPTION 'harness: authenticated role not applied.'; END IF;

  SELECT count(*) INTO cnt FROM public.goal_funding_snapshots;
  IF cnt <> 0 THEN RAISE EXCEPTION 'UNAUTH FAIL: SELECT leaked % rows (expected 0).', cnt; END IF;

  ok := true;
  BEGIN INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source,created_by_user_id)
          VALUES (2099,3,'__x__',0,'opening_anchor',NULL);
    ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'UNAUTH FAIL: INSERT was NOT denied by RLS.'; END IF;

  -- RPC rejects (has EXECUTE as authenticated, but can_write_financials()=false)
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026,1,'[]'::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%not authorized%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'UNAUTH FAIL: RPC did NOT reject (expected "not authorized").'; END IF;
  RAISE NOTICE 'C UNAUTH PASS: harness ok; read 0-row; write denied; RPC not authorized.';
END $$;
RESET ROLE;

-- ══════════════════════════════════════════════════════════════════════════
-- B — VIEWER (active, role=viewer): read yes, write no, RPC no
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE cnt INT; upd INT; ok BOOLEAN;
BEGIN
  PERFORM set_config('role','authenticated', true);
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","email":"%s","role":"authenticated"}','<<V_UUID>>','<<V_EMAIL>>'), true);
  IF (auth.uid())::text <> '<<V_UUID>>' THEN RAISE EXCEPTION 'harness: viewer uid claim not applied.'; END IF;

  SELECT count(*) INTO cnt FROM public.goal_funding_snapshots;
  IF cnt < 1 THEN RAISE EXCEPTION 'VIEWER FAIL: SELECT returned 0 (read gate should pass).'; END IF;

  ok := true;
  BEGIN INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source,created_by_user_id)
          VALUES (2099,4,'__x__',0,'opening_anchor',NULL);
    ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'VIEWER FAIL: INSERT was NOT denied by RLS.'; END IF;

  -- UPDATE denial is a silent 0-row (USING can_write_financials() = false)
  UPDATE public.goal_funding_snapshots SET funded_amount=999 WHERE note='__gate1_ground_truth__';
  GET DIAGNOSTICS upd = ROW_COUNT;
  IF upd <> 0 THEN RAISE EXCEPTION 'VIEWER FAIL: UPDATE affected % rows (expected 0).', upd; END IF;

  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026,1,'[]'::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%not authorized%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'VIEWER FAIL: RPC did NOT reject (expected "not authorized").'; END IF;
  RAISE NOTICE 'B VIEWER PASS: harness ok; read ok; write denied; update 0-row; RPC not authorized.';
END $$;
RESET ROLE;

-- post-check as owner: viewer's denied/no-op writes changed nothing
DO $$
DECLARE amt NUMERIC(12,2);
BEGIN
  SELECT funded_amount INTO amt FROM public.goal_funding_snapshots WHERE note='__gate1_ground_truth__';
  IF NOT FOUND THEN RAISE EXCEPTION 'POST-VIEWER FAIL: ground-truth row missing (unexpected deletion).'; END IF;
  IF amt <> 100 THEN RAISE EXCEPTION 'POST-VIEWER FAIL: ground-truth funded_amount mutated to %.', amt; END IF;
  RAISE NOTICE 'POST-VIEWER ok: no mutation from denied writes.';
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- A — WRITER (role owner/household_admin): table writes ok; RPC full behavior
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  new_cbu UUID; v_cbu UUID; ok BOOLEAN; upd INT; n INT;
  v_goal TEXT; v_goal2 TEXT; v_auto TEXT; v_recweek INT; v_badweek INT;
BEGIN
  -- pick eligible goals + a reconciled/unreconciled week (as owner, before impersonation)
  SELECT id INTO v_goal  FROM public.goal_registry WHERE COALESCE(auto,false)=false
     AND id <> ALL (ARRAY['wewe_rccl','wewe_dcl','taxable_etf']) ORDER BY id LIMIT 1;
  SELECT id INTO v_goal2 FROM public.goal_registry WHERE COALESCE(auto,false)=false
     AND id <> ALL (ARRAY['wewe_rccl','wewe_dcl','taxable_etf']) AND id <> v_goal ORDER BY id LIMIT 1;
  SELECT id INTO v_auto  FROM public.goal_registry WHERE auto=true ORDER BY id LIMIT 1;   -- may be NULL
  SELECT min(week_num) INTO v_recweek FROM public.weekly_reconciliations;                 -- may be NULL
  SELECT min(w) INTO v_badweek FROM generate_series(1,31) w
    WHERE NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=w);       -- may be NULL

  PERFORM set_config('role','authenticated', true);
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","email":"%s","role":"authenticated"}','<<W_UUID>>','<<W_EMAIL>>'), true);
  IF (auth.uid())::text <> '<<W_UUID>>' THEN RAISE EXCEPTION 'harness: writer uid claim not applied.'; END IF;

  -- direct table INSERT relying on DEFAULT auth.uid() -> proves auth.uid(), FK, write policy
  INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source)
    VALUES (2099,5,v_goal,250,'opening_anchor')
    RETURNING created_by_user_id INTO new_cbu;
  IF new_cbu::text <> '<<W_UUID>>' THEN RAISE EXCEPTION 'WRITER FAIL: created_by_user_id=% (expected default auth.uid()).', new_cbu; END IF;

  -- direct table UPDATE allowed (USING/WITH CHECK can_write_financials())
  UPDATE public.goal_funding_snapshots SET funded_amount=260 WHERE model_year=2099 AND week_num=5 AND goal_id=v_goal;
  GET DIAGNOSTICS upd = ROW_COUNT;
  IF upd <> 1 THEN RAISE EXCEPTION 'WRITER FAIL: UPDATE affected % rows (expected 1).', upd; END IF;

  -- DELETE / TRUNCATE blocked (no grant -> insufficient_privilege)
  ok := true;
  BEGIN DELETE FROM public.goal_funding_snapshots WHERE model_year=2099 AND week_num=5; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: DELETE was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN TRUNCATE public.goal_funding_snapshots; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: TRUNCATE was NOT permission-denied.'; END IF;

  -- ── RPC happy-path (v_recweek guaranteed reconciled by the prereq guard) ──
  -- authorized upsert of one row; created_by_user_id must default to auth.uid()
  n := public.save_goal_funding_snapshots(2026, v_recweek,
         format('[{"goal_id":"%s","funded_amount":123.45,"source":"reconciliation"}]', v_goal)::jsonb);
  IF n <> 1 THEN RAISE EXCEPTION 'WRITER FAIL: RPC returned % (expected 1).', n; END IF;
  SELECT count(*), max(created_by_user_id::text)::uuid INTO n, v_cbu FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=v_recweek AND goal_id=v_goal AND funded_amount=123.45;
  IF n <> 1 THEN RAISE EXCEPTION 'WRITER FAIL: RPC row not found post-upsert.'; END IF;
  IF v_cbu::text <> '<<W_UUID>>' THEN
    RAISE EXCEPTION 'WRITER FAIL: RPC created_by_user_id=% (expected default auth.uid()=<<W_UUID>>).', v_cbu; END IF;

  -- idempotent re-upsert (same key, new amount/source) -> still one row, updated,
  -- and created_by_user_id PRESERVED (ON CONFLICT DO UPDATE never touches it)
  n := public.save_goal_funding_snapshots(2026, v_recweek,
         format('[{"goal_id":"%s","funded_amount":200.00,"source":"correction"}]', v_goal)::jsonb);
  SELECT count(*), max(created_by_user_id::text)::uuid INTO n, v_cbu FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=v_recweek AND goal_id=v_goal;
  IF n <> 1 THEN RAISE EXCEPTION 'WRITER FAIL: re-upsert created a duplicate (count=%).', n; END IF;
  IF v_cbu::text <> '<<W_UUID>>' THEN
    RAISE EXCEPTION 'WRITER FAIL: re-upsert did not preserve created_by_user_id (got %).', v_cbu; END IF;

  -- ── RPC rejection matrix (each RAISEs inside the RPC; assert SQLERRM) ──
  -- null p_rows (explicit NULL rejection, not a silent no-op)
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026, v_recweek, NULL); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%must be a JSON array%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted NULL p_rows.'; END IF;

  -- empty array p_rows (rejected; no legitimate no-op save)
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026, v_recweek, '[]'::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%at least one row%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted an empty p_rows array.'; END IF;

  -- negative funded_amount
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026, v_recweek,
          format('[{"goal_id":"%s","funded_amount":-5,"source":"opening_anchor"}]', v_goal)::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%negative funded_amount%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted a negative funded_amount.'; END IF;

  -- invalid source
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026, v_recweek,
          format('[{"goal_id":"%s","funded_amount":1,"source":"bogus"}]', v_goal)::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%invalid source%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted an invalid source.'; END IF;

  -- invalid goal_id
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026, v_recweek,
          '[{"goal_id":"__does_not_exist__","funded_amount":1,"source":"opening_anchor"}]'::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%not in goal_registry%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted a non-existent goal_id.'; END IF;

  -- excluded holding goal
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026, v_recweek,
          '[{"goal_id":"wewe_rccl","funded_amount":1,"source":"opening_anchor"}]'::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%excluded%' OR SQLERRM LIKE '%not in goal_registry%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted an excluded holding goal (wewe_rccl).'; END IF;

  -- auto goal (only assertable if an auto goal exists on this DB)
  IF v_auto IS NOT NULL THEN
    ok := true;
    BEGIN PERFORM public.save_goal_funding_snapshots(2026, v_recweek,
            format('[{"goal_id":"%s","funded_amount":1,"source":"opening_anchor"}]', v_auto)::jsonb); ok := false;
      EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%auto goal%' THEN NULL; ELSE RAISE; END IF; END;
    IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted an auto goal (%).', v_auto; END IF;
  ELSE
    RAISE NOTICE 'WRITER: no auto goal on staging — auto-goal rejection probe SKIPPED.';
  END IF;

  -- week_num out of range
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(2026, 32,
          format('[{"goal_id":"%s","funded_amount":1,"source":"opening_anchor"}]', v_goal)::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%out of range%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted week_num=32.'; END IF;

  -- null model_year
  ok := true;
  BEGIN PERFORM public.save_goal_funding_snapshots(NULL, v_recweek,
          format('[{"goal_id":"%s","funded_amount":1,"source":"opening_anchor"}]', v_goal)::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%invalid model_year%' THEN NULL; ELSE RAISE; END IF; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted a NULL model_year.'; END IF;

  -- unreconciled week (only assertable if an unreconciled week exists)
  IF v_badweek IS NOT NULL THEN
    ok := true;
    BEGIN PERFORM public.save_goal_funding_snapshots(2026, v_badweek,
            format('[{"goal_id":"%s","funded_amount":1,"source":"opening_anchor"}]', v_goal)::jsonb); ok := false;
      EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%not reconciled%' THEN NULL; ELSE RAISE; END IF; END;
    IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: RPC accepted an unreconciled week (%).', v_badweek; END IF;
  ELSE
    RAISE NOTICE 'WRITER: all 31 weeks reconciled on staging — unreconciled-week rejection probe SKIPPED.';
  END IF;

  RAISE NOTICE 'A WRITER PASS: table writes ok; delete/truncate blocked; RPC happy-path + created_by_user_id(default/preserved) + full rejection matrix (null/empty p_rows, neg, source, goal, excluded, auto, week-range, model_year, unreconciled) enforced.';
END $$;
RESET ROLE;

-- ── FINAL GROUND-TRUTH: row intact (owner view) ──────────────────────────────
DO $$
DECLARE amt NUMERIC(12,2);
BEGIN
  SELECT funded_amount INTO amt FROM public.goal_funding_snapshots WHERE note='__gate1_ground_truth__';
  IF NOT FOUND THEN RAISE EXCEPTION 'FINAL FAIL: ground-truth row missing (unexpected deletion).'; END IF;
  IF amt <> 100 THEN RAISE EXCEPTION 'FINAL FAIL: ground-truth funded_amount mutated to %.', amt; END IF;
  RAISE NOTICE 'FINAL owner view ok. Matrix PASSED if you saw D/C/B/A PASS notices (+ any documented SKIPs).';
END $$;

-- ── NOTHING PERSISTS ─────────────────────────────────────────────────────────
ROLLBACK;

-- Post-rollback confirmation (run as owner). Gate 1 runs AFTER seed-anchor in the
-- approved rehearsal sequence, so the table is NOT empty here: the whole Gate 1
-- transaction rolled back, so its ground-truth (model_year=2099) and
-- __gate1_ground_truth__ probe rows are gone, while the 9 committed seed-anchor
-- rows (model_year=2026, week_num=5) remain untouched.
SELECT 'G1-clean' AS check,
       (SELECT count(*) FROM public.goal_funding_snapshots
         WHERE model_year=2026 AND week_num=5) = 9
       AND NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots WHERE model_year=2099)
       AND NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots WHERE note='__gate1_ground_truth__')
       AS expected_true;
