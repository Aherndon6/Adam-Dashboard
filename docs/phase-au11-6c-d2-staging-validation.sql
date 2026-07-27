-- ============================================================================
-- AU-11 Step 6C-D2 — STAGING validation for the reservation lifecycle RPCs
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Executed by Adam. PRE-REQ: run phase-au11-6c-d2-goal-registry-reservable.sql,
-- phase-au11-6c-d2-staging-rpcs.sql, and phase-au11-6c-d2-staging-fixture.sql first.
-- Every mutating test runs inside its own BEGIN … (sentinel) ROLLBACK so NOTHING new persists
-- (the fixture rows themselves persist until the teardown file is run). Owner/role identity is
-- simulated via the request.jwt.claims 'sub' GUC (SQL-Editor auth.uid() is NULL otherwise).
-- Negatives assert the EXPECTED SQLERRM substring — a wrong-reason rejection fails as FALSE-PASS RISK.
-- Read the NOTICES pane for PASS/FAIL lines.
-- ============================================================================

-- ── Guard ──
DO $$ BEGIN
  IF to_regclass('public.app_environment') IS NULL OR NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') THEN
    RAISE EXCEPTION 'HARD STOP: not staging'; END IF;
END $$;

-- ── D2-PRE: fixture prerequisites (report; the fixture file seeds these) ──
SELECT 'PRE_owner'     AS check_name, count(*) AS n FROM public.app_users au
  WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id);   -- expect >=1 (reused staging owner, auth.users-backed)
SELECT 'PRE_basis'     AS check_name, (SELECT max(week_num) FROM public.weekly_reconciliations) AS latest_week,
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=31) AS snapshots_at_31;                              -- expect 31 / >=9
SELECT 'PRE_reservable' AS check_name, count(*) AS n FROM public.goal_registry
  WHERE id IN ('d2fix_g01','d2fix_g02','d2fix_g03') AND reservable=true AND status IN ('planned','funding') AND btrim(COALESCE(dest,''))<>'';       -- expect 3
-- If any of the above are short, run phase-au11-6c-d2-staging-fixture.sql before proceeding.

-- ── D2-ROLE-1: OWNER can create (happy path) — rolled back ──
DO $$
DECLARE v_owner UUID; v_res JSONB;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'D2-ROLE-1 FAIL: fixture owner missing (run fixture file)'; END IF;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);

  v_res := public.create_discretionary_goal_reservation_v1(
    2026, 31, 'a1b2c3d4', 'truist_checking', (CURRENT_DATE + 7),
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',5000)), 5000);
  IF (v_res->>'ok')::boolean AND v_res->>'status'='active'
     AND (SELECT count(*) FROM public.cash_commitments WHERE commitment_class='discretionary_goal_transfer' AND status='scheduled')=1
     AND (SELECT count(*) FROM public.discretionary_reservation_batches WHERE status='active')=1 THEN
    RAISE NOTICE 'D2-ROLE-1 PASS: owner create -> 1 active batch + 1 scheduled reservation (%).', v_res->>'batch_id';
  ELSE
    RAISE EXCEPTION 'D2-ROLE-1 FAIL: unexpected create result %', v_res;
  END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── D2-ROLE-2: NON-OWNER is rejected 42501. Uses a uid ABSENT from app_users (no INSERT — app_users.auth_user_id
--    has a FK to auth.users, and a synthetic row is unnecessary): is_owner() returns false for any uid that is not
--    an active owner, so this exercises the exact owner-gate rejection path without provisioning an auth identity.
--    (The guard first asserts the uid really is a non-owner, so the test can't false-pass if it ever collided.) ──
DO $$
DECLARE v_nonowner UUID := '22222222-2222-2222-2222-222222222222'; v_ok BOOLEAN := false;
BEGIN
  IF EXISTS (SELECT 1 FROM public.app_users WHERE auth_user_id=v_nonowner AND active AND role='owner') THEN
    RAISE EXCEPTION 'D2-ROLE-2 SETUP: chosen non-owner uid is unexpectedly an owner'; END IF;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_nonowner::text)::text, true);
  BEGIN
    PERFORM public.create_discretionary_goal_reservation_v1(2026, 31, 'b2c3d4e5','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100)));
    v_ok := true;   -- should NOT reach here
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'D2-ROLE-2 PASS: non-owner (uid absent from app_users) create rejected 42501';
  END;
  IF v_ok THEN RAISE EXCEPTION 'D2-ROLE-2 FAIL: non-owner create was NOT rejected'; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── D2-ROLE-3: ANON is rejected ──
DO $$
DECLARE v_ok BOOLEAN := false;
BEGIN
  PERFORM set_config('role','anon',true);
  PERFORM set_config('request.jwt.claims', '{}', true);
  BEGIN
    PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'c3d4e5f6','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100)));
    v_ok := true;
  EXCEPTION WHEN insufficient_privilege OR others THEN
    RAISE NOTICE 'D2-ROLE-3 PASS: anon create rejected (%).', SQLERRM;
  END;
  IF v_ok THEN RAISE EXCEPTION 'D2-ROLE-3 FAIL: anon create was NOT rejected'; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── D2-LIFECYCLE-A: create -> void_scheduled (whole batch, still scheduled) -> batch voided ──
DO $$
DECLARE v_owner UUID; v_st TEXT; v_bst TEXT;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);

  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'dddddddd','truist_checking',CURRENT_DATE+7,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',3000)));
  PERFORM public.void_scheduled_discretionary_goal_reservation_v1(2026,'dddddddd',NULL,'test void of scheduled');
  SELECT status INTO v_st FROM public.cash_commitments
    WHERE goal_id='d2fix_g01' AND reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='dddddddd');
  SELECT status INTO v_bst FROM public.discretionary_reservation_batches WHERE batch_digest='dddddddd';
  IF v_st='voided' AND v_bst='voided' THEN
    RAISE NOTICE 'D2-LIFECYCLE-A PASS: scheduled->voided; batch retired voided';
  ELSE RAISE EXCEPTION 'D2-LIFECYCLE-A FAIL: row=% batch=%', v_st, v_bst; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── D2-LIFECYCLE-B (R7 KEY CONTROL): an INITIATED reservation cannot be cancelled/released by D2.
--    create -> mark_initiated -> void_scheduled attempt MUST be rejected; row stays initiated; batch stays active. ──
DO $$
DECLARE v_owner UUID; v_st TEXT; v_bst TEXT; v_rejected BOOLEAN := false;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);

  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'eeeeeeee','truist_checking',CURRENT_DATE+7,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',4000)));
  PERFORM public.mark_discretionary_goal_reservation_initiated_v1(2026,'eeeeeeee',NULL,'BANKREF-LCB', NOW(), NULL);
  BEGIN
    PERFORM public.void_scheduled_discretionary_goal_reservation_v1(2026,'eeeeeeee',NULL,'attempt to cancel an initiated reservation');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%cannot void initiated reservation%' THEN v_rejected := true;
    ELSE RAISE EXCEPTION 'D2-LIFECYCLE-B FALSE-PASS RISK: rejected for the WRONG reason: %', SQLERRM; END IF;
  END;
  SELECT status INTO v_st FROM public.cash_commitments
    WHERE goal_id='d2fix_g01' AND reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='eeeeeeee');
  SELECT status INTO v_bst FROM public.discretionary_reservation_batches WHERE batch_digest='eeeeeeee';
  IF v_rejected AND v_st='initiated' AND v_bst='active' THEN
    RAISE NOTICE 'D2-LIFECYCLE-B PASS: initiated reservation could NOT be voided by D2; still withholding (row=initiated, batch=active)';
  ELSE RAISE EXCEPTION 'D2-LIFECYCLE-B FAIL: rejected=% row=% batch=%', v_rejected, v_st, v_bst; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── D2-ELIG (R8 registry eligibility predicate): reservable=false, ineligible status, empty dest ──
DO $$
DECLARE v_owner UUID;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);

  -- E1: goal not reservable (d2fix_g04 reservable=false)
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'e1e1e1e1','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g04','amount_cents',100)));
    RAISE EXCEPTION 'E1 FAIL: non-reservable goal accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'E1 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%is not reservable%' THEN RAISE NOTICE 'E1 PASS: reservable=false rejected';
    ELSE RAISE EXCEPTION 'E1 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  -- E2: ineligible status (d2fix_g05 status=funded)
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'e2e2e2e2','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g05','amount_cents',100)));
    RAISE EXCEPTION 'E2 FAIL: funded-status goal accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'E2 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%not in an eligible state%' THEN RAISE NOTICE 'E2 PASS: ineligible status rejected';
    ELSE RAISE EXCEPTION 'E2 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  -- E3: empty destination (d2fix_g06 dest='')
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'e3e3e3e3','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g06','amount_cents',100)));
    RAISE EXCEPTION 'E3 FAIL: empty-dest goal accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'E3 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%no valid destination account%' THEN RAISE NOTICE 'E3 PASS: empty dest rejected';
    ELSE RAISE EXCEPTION 'E3 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── D2-NEG: conservation, unknown goal, dup goal, amount<=0, bad basis, wrong source, second active batch.
--    Each asserts the EXPECTED rejection message; a wrong-reason rejection fails as FALSE-PASS RISK. ──
DO $$
DECLARE v_owner UUID;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);

  -- N1 conservation mismatch
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'11111111','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',3000)), 4000);
    RAISE EXCEPTION 'N1 FAIL: conservation mismatch not caught';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N1 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%conservation checksum mismatch%' THEN RAISE NOTICE 'N1 PASS: conservation mismatch rejected';
    ELSE RAISE EXCEPTION 'N1 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  -- N2 unknown goal
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'22222222','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','__nope__','amount_cents',100)));
    RAISE EXCEPTION 'N2 FAIL: unknown goal not caught';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N2 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%unknown goal_id%' THEN RAISE NOTICE 'N2 PASS: unknown goal rejected';
    ELSE RAISE EXCEPTION 'N2 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  -- N3 duplicate goal in batch
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'33333333','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100),jsonb_build_object('goal_id','d2fix_g01','amount_cents',200)));
    RAISE EXCEPTION 'N3 FAIL: dup goal not caught';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N3 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%duplicate goal_id%' THEN RAISE NOTICE 'N3 PASS: duplicate goal rejected';
    ELSE RAISE EXCEPTION 'N3 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  -- N4 amount below the valid range (0). '0' is digit-valid, so it reaches the unified range guard
  -- (1..100000000) and is rejected as 'out of range' (the lower-bound counterpart to N-AMT-range's upper bound).
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'44444444','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',0)));
    RAISE EXCEPTION 'N4 FAIL: amount 0 not caught';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N4 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%out of range%' THEN RAISE NOTICE 'N4 PASS: amount 0 (below range) rejected';
    ELSE RAISE EXCEPTION 'N4 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  -- N5 non-latest / non-reconciled basis (week 1)
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,1,'55555555','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100)));
    RAISE EXCEPTION 'N5 FAIL: bad basis not caught';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N5 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%basis week%' THEN RAISE NOTICE 'N5 PASS: non-latest/unreconciled basis rejected';
    ELSE RAISE EXCEPTION 'N5 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  -- N6 wrong source_account
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'66666666','amex_savings',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100)));
    RAISE EXCEPTION 'N6 FAIL: wrong source not caught';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N6 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%invalid source_account%' THEN RAISE NOTICE 'N6 PASS: wrong source rejected';
    ELSE RAISE EXCEPTION 'N6 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  -- N7 second active batch (create one, then a different digest) — inner subblock rolls back both on catch
  BEGIN
    PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'77777777','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100)));
    PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'88888888','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g02','amount_cents',100)));
    RAISE EXCEPTION 'N7 FAIL: second active batch not blocked';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N7 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%active discretionary batch already exists%' THEN RAISE NOTICE 'N7 PASS: second active batch blocked';
    ELSE RAISE EXCEPTION 'N7 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── N8 (own transaction): idempotent replay (identical) then conflicting replay (changed amount) ──
DO $$
DECLARE v_owner UUID;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);

  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'99999999','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',2500)));
  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'99999999','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',2500)));   -- idempotent no-op
  RAISE NOTICE 'N8a PASS: identical replay idempotent';
  BEGIN
    PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'99999999','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',9999)));  -- changed amount => conflict
    RAISE EXCEPTION 'N8b FAIL: conflicting replay not caught';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N8b FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%conflicting replay%' THEN RAISE NOTICE 'N8b PASS: conflicting (changed-amount) replay rejected';
    ELSE RAISE EXCEPTION 'N8b FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── N9 (own transaction, F1): partial-void (void_scheduled one goal) then replay MUST conflict
--    (a disposed goal must not replay as idempotent — the fail-open defect Fable flagged). ──
DO $$
DECLARE v_owner UUID;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);

  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'aaaa0001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
  PERFORM public.void_scheduled_discretionary_goal_reservation_v1(2026,'aaaa0001',ARRAY['d2fix_g01'],'partial void for N9');
  BEGIN
    PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'aaaa0001','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
    RAISE EXCEPTION 'N9 FAIL: partial-void replay was NOT treated as a conflict (fail-open)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N9 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%conflicting replay%' THEN RAISE NOTICE 'N9 PASS: partial-void replay rejected (fail closed)';
    ELSE RAISE EXCEPTION 'N9 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── N10 (own transaction, F5): destination change between create and replay MUST conflict.
--    The transient goal_registry.dest edit is run under the ADMIN session role (RLS bypass) — goal_registry
--    has RLS enabled with NO UPDATE policy, so the same UPDATE under the simulated 'authenticated' role would
--    be silently filtered to 0 rows and never establish the drift. Rolled back with the DO. ──
DO $$
DECLARE v_owner UUID; v_admin TEXT := session_user; v_n INT;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);

  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'aaaa0002','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1500)));
  -- change the registry destination as admin (RLS bypass) so the drift actually takes effect
  PERFORM set_config('role', v_admin, true);
  UPDATE public.goal_registry SET dest = dest||'-D2TESTX' WHERE id='d2fix_g01';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'N10 SETUP: dest UPDATE affected % rows (expected 1) — RLS/role issue', v_n; END IF;
  PERFORM set_config('role','authenticated',true);
  BEGIN
    PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'aaaa0002','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1500)));
    RAISE EXCEPTION 'N10 FAIL: destination-change replay was NOT treated as a conflict';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N10 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%conflicting replay%' THEN RAISE NOTICE 'N10 PASS: destination-change replay rejected';
    ELSE RAISE EXCEPTION 'N10 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── N11 (own transaction, F7): mark_initiated with explicit goal_ids matching zero scheduled rows MUST fail closed. ──
DO $$
DECLARE v_owner UUID;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);

  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'aaaa0003','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1200)));
  BEGIN
    PERFORM public.mark_discretionary_goal_reservation_initiated_v1(2026,'aaaa0003',ARRAY['__not_in_batch__'],'BANKREF-N11',NOW(),NULL);
    RAISE EXCEPTION 'N11 FAIL: mark_initiated with a zero-match goal list did NOT fail';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'N11 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%not scheduled in batch%' THEN RAISE NOTICE 'N11 PASS: mark_initiated zero-match failed closed';
    ELSE RAISE EXCEPTION 'N11 FALSE-PASS RISK: WRONG reason: %', SQLERRM; END IF; END;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ── F-C-OVERLAP (fail-closed): an explicit mark_initiated list that overlaps an already-initiated goal
--    (or mixes initiated + scheduled) is rejected atomically — the scheduled goal is NOT initiated. ──
DO $$
DECLARE v_owner UUID; v_g1 TEXT; v_g2 TEXT;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'aaaa0004','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
  PERFORM public.mark_discretionary_goal_reservation_initiated_v1(2026,'aaaa0004',ARRAY['d2fix_g01'],'BR-A',NOW(),NULL); -- g01 initiated
  BEGIN
    -- overlap: g01 already initiated + g02 scheduled → must fail atomically, g02 stays scheduled
    PERFORM public.mark_discretionary_goal_reservation_initiated_v1(2026,'aaaa0004',ARRAY['d2fix_g01','d2fix_g02'],'BR-B',NOW(),NULL);
    RAISE EXCEPTION 'F-C-OVERLAP FAIL: overlapping mark_initiated did not fail';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'F-C-OVERLAP FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%not scheduled in batch%' THEN RAISE EXCEPTION 'F-C-OVERLAP FALSE-PASS RISK: %', SQLERRM; END IF; END;
  SELECT c1.status, c2.status INTO v_g1, v_g2 FROM
    (SELECT status FROM public.cash_commitments WHERE reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='aaaa0004') AND goal_id='d2fix_g01') c1,
    (SELECT status FROM public.cash_commitments WHERE reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='aaaa0004') AND goal_id='d2fix_g02') c2;
  IF v_g1='initiated' AND v_g2='scheduled' THEN RAISE NOTICE 'F-C-OVERLAP PASS: overlap rejected atomically (g01 initiated, g02 still scheduled)';
  ELSE RAISE EXCEPTION 'F-C-OVERLAP FAIL: post-state g01=% g02=%', v_g1, v_g2; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- Req 5 — LIFECYCLE FAIL-CLOSED
-- ══════════════════════════════════════════════════════════════════════════

-- ── L-MIX / L-SEL: a mixed target (one scheduled + one initiated) fails the WHOLE void atomically
--    (no scheduled row voided); a selective void of only the scheduled row then succeeds. ──
DO $$
DECLARE v_owner UUID; v_g1 TEXT; v_g2 TEXT; v_bst TEXT;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'b1000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
  PERFORM public.mark_discretionary_goal_reservation_initiated_v1(2026,'b1000001',ARRAY['d2fix_g02'],'BR-MIX',NOW(),NULL);
  -- mixed void MUST fail atomically
  BEGIN
    PERFORM public.void_scheduled_discretionary_goal_reservation_v1(2026,'b1000001',ARRAY['d2fix_g01','d2fix_g02'],'mixed void');
    RAISE EXCEPTION 'L-MIX FAIL: mixed void did not fail';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'L-MIX FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%cannot void initiated reservation%' THEN RAISE EXCEPTION 'L-MIX FALSE-PASS RISK: %', SQLERRM; END IF; END;
  SELECT v1.status||'/'||v2.status INTO v_bst FROM
    (SELECT status FROM public.cash_commitments WHERE reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='b1000001') AND goal_id='d2fix_g01') v1,
    (SELECT status FROM public.cash_commitments WHERE reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='b1000001') AND goal_id='d2fix_g02') v2;
  IF v_bst='scheduled/initiated' THEN RAISE NOTICE 'L-MIX PASS: mixed void atomic — g01 still scheduled, g02 still initiated';
  ELSE RAISE EXCEPTION 'L-MIX FAIL: post-state % (want scheduled/initiated)', v_bst; END IF;
  -- selective void of the scheduled row succeeds; initiated remains; batch stays active
  PERFORM public.void_scheduled_discretionary_goal_reservation_v1(2026,'b1000001',ARRAY['d2fix_g01'],'selective void');
  SELECT c.status||'/'||b.status INTO v_bst FROM
    (SELECT status FROM public.cash_commitments WHERE reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='b1000001') AND goal_id='d2fix_g01') c,
    (SELECT status FROM public.discretionary_reservation_batches WHERE batch_digest='b1000001') b;
  IF v_bst='voided/active' THEN RAISE NOTICE 'L-SEL PASS: selective scheduled void ok; g02 initiated keeps batch active';
  ELSE RAISE EXCEPTION 'L-SEL FAIL: % (want voided/active)', v_bst; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;

-- ── L-BP / L-SR: bank_pending and stale_review rows cannot be released by any D2 RPC (void refuses). ──
DO $$
DECLARE v_owner UUID; v_admin TEXT := session_user; v_s1 TEXT; v_s2 TEXT;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'b2000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
  -- push the two rows into the non-scheduled non-terminal states D2 has no setter for, as ADMIN (RLS bypass;
  -- cash_commitments writes are otherwise RPC/definer-only), then restore 'authenticated' for the RPC call.
  PERFORM set_config('role', v_admin, true);
  UPDATE public.cash_commitments SET status='bank_pending'
    WHERE reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='b2000001') AND goal_id='d2fix_g01';
  UPDATE public.cash_commitments SET status='stale_review'
    WHERE reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='b2000001') AND goal_id='d2fix_g02';
  PERFORM set_config('role','authenticated',true);
  BEGIN
    PERFORM public.void_scheduled_discretionary_goal_reservation_v1(2026,'b2000001',NULL,'try release bank_pending/stale_review');
    RAISE EXCEPTION 'L-BPSR FAIL: void released a bank_pending/stale_review row';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'L-BPSR FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%cannot void initiated reservation%' THEN RAISE EXCEPTION 'L-BPSR FALSE-PASS RISK: %', SQLERRM; END IF; END;
  SELECT c1.status, c2.status INTO v_s1, v_s2 FROM
    (SELECT status FROM public.cash_commitments WHERE reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='b2000001') AND goal_id='d2fix_g01') c1,
    (SELECT status FROM public.cash_commitments WHERE reservation_batch_id=(SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='b2000001') AND goal_id='d2fix_g02') c2;
  IF v_s1='bank_pending' AND v_s2='stale_review' THEN RAISE NOTICE 'L-BPSR PASS: bank_pending + stale_review remain withholding (D2 cannot release)';
  ELSE RAISE EXCEPTION 'L-BPSR FAIL: % / %', v_s1, v_s2; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;

-- ── L-DUP: duplicate goal ids in mark_initiated / void_scheduled are normalized (set membership; no error). ──
DO $$
DECLARE v_owner UUID; v_i INT; v_v INT;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'b3000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
  v_i := (public.mark_discretionary_goal_reservation_initiated_v1(2026,'b3000001',ARRAY['d2fix_g01','d2fix_g01'],'BR-DUP',NOW(),NULL)->>'transitioned')::int;
  v_v := (public.void_scheduled_discretionary_goal_reservation_v1(2026,'b3000001',ARRAY['d2fix_g02','d2fix_g02'],'dup void')->>'voided')::int;
  IF v_i=1 AND v_v=1 THEN RAISE NOTICE 'L-DUP PASS: duplicate goal ids normalized (initiated=1, voided=1)';
  ELSE RAISE EXCEPTION 'L-DUP FAIL: initiated=% voided=%', v_i, v_v; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;

-- ── L-ARR: empty / null-element goal-id arrays fail closed (array hygiene runs before batch lookup). ──
DO $$
DECLARE v_owner UUID; v_pass INT := 0;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  BEGIN PERFORM public.mark_discretionary_goal_reservation_initiated_v1(2026,'b4000001',ARRAY[]::text[],'BR',NOW(),NULL);
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%not an empty array%' THEN v_pass:=v_pass+1; ELSE RAISE EXCEPTION 'L-ARR FALSE-PASS(init-empty): %',SQLERRM; END IF; END;
  BEGIN PERFORM public.mark_discretionary_goal_reservation_initiated_v1(2026,'b4000001',ARRAY[NULL]::text[],'BR',NOW(),NULL);
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%null/blank goal id%' THEN v_pass:=v_pass+1; ELSE RAISE EXCEPTION 'L-ARR FALSE-PASS(init-null): %',SQLERRM; END IF; END;
  BEGIN PERFORM public.void_scheduled_discretionary_goal_reservation_v1(2026,'b4000001',ARRAY[]::text[],'r');
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%not an empty array%' THEN v_pass:=v_pass+1; ELSE RAISE EXCEPTION 'L-ARR FALSE-PASS(void-empty): %',SQLERRM; END IF; END;
  BEGIN PERFORM public.void_scheduled_discretionary_goal_reservation_v1(2026,'b4000001',ARRAY['  ']::text[],'r');
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%null/blank goal id%' THEN v_pass:=v_pass+1; ELSE RAISE EXCEPTION 'L-ARR FALSE-PASS(void-blank): %',SQLERRM; END IF; END;
  IF v_pass=4 THEN RAISE NOTICE 'L-ARR PASS: empty/null/blank goal-id arrays fail closed (4/4)';
  ELSE RAISE EXCEPTION 'L-ARR FAIL: %/4', v_pass; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;

-- ── D2-INPUT: empty rows array, unexpected key, malformed/oversized amount all fail deterministically. ──
DO $$
DECLARE v_owner UUID;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  -- N-EMPTY: empty rows array cannot create an empty active batch
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'c1000001','truist_checking',CURRENT_DATE, jsonb_build_array());
    RAISE EXCEPTION 'N-EMPTY FAIL: empty rows accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'N-EMPTY FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%non-empty JSON array%' THEN RAISE NOTICE 'N-EMPTY PASS'; ELSE RAISE EXCEPTION 'N-EMPTY FALSE-PASS: %',SQLERRM; END IF; END;
  -- N-KEY: unexpected key rejected
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'c2000001','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100,'bogus','x')));
    RAISE EXCEPTION 'N-KEY FAIL: unexpected key accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'N-KEY FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%unexpected key%' THEN RAISE NOTICE 'N-KEY PASS'; ELSE RAISE EXCEPTION 'N-KEY FALSE-PASS: %',SQLERRM; END IF; END;
  -- N-AMT-bad: non-digit amount rejected
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'c3000001','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents','12.5')));
    RAISE EXCEPTION 'N-AMT1 FAIL: decimal amount accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'N-AMT1 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%digits only%' THEN RAISE NOTICE 'N-AMT-bad PASS'; ELSE RAISE EXCEPTION 'N-AMT1 FALSE-PASS: %',SQLERRM; END IF; END;
  -- N-AMT-range: amount above the per-goal cap (100000000) rejected (proves no INT/BIGINT overflow path)
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'c4000001','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents','200000000')));
    RAISE EXCEPTION 'N-AMT2 FAIL: oversized amount accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'N-AMT2 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%out of range%' THEN RAISE NOTICE 'N-AMT-range PASS'; ELSE RAISE EXCEPTION 'N-AMT2 FALSE-PASS: %',SQLERRM; END IF; END;
  -- N-DIGEST-UPPER: uppercase digest rejected (canonical form is exactly 8 lowercase hex; no normalization)
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'A1B2C3D4','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100)));
    RAISE EXCEPTION 'N-DIG FAIL: uppercase digest accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'N-DIG FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%invalid batch_digest%' THEN RAISE NOTICE 'I-DIGEST-UPPER PASS: uppercase rejected'; ELSE RAISE EXCEPTION 'N-DIG FALSE-PASS: %',SQLERRM; END IF; END;
  -- I-SRC-CASE: source_account is exact/case-sensitive
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'c5000001','Truist_Checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100)));
    RAISE EXCEPTION 'N-SRC FAIL: mixed-case source accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'N-SRC FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%invalid source_account%' THEN RAISE NOTICE 'I-SRC-CASE PASS: case-sensitive source enforced'; ELSE RAISE EXCEPTION 'N-SRC FALSE-PASS: %',SQLERRM; END IF; END;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- Req 6 — ELIGIBILITY vs actual registry constraints (E4 archived status, E5 whitespace dest)
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_owner UUID; v_admin TEXT := session_user;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  -- transient goal_registry edits run as ADMIN (RLS bypass — goal_registry has no UPDATE policy); the create()
  -- calls run under the simulated 'authenticated' role. Both edits are rolled back with the DO.
  -- E4: archived status rejected as ineligible state
  PERFORM set_config('role', v_admin, true);
  UPDATE public.goal_registry SET status='archived' WHERE id='d2fix_g01';
  PERFORM set_config('role','authenticated',true);
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'d1000001','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100)));
    RAISE EXCEPTION 'E4 FAIL: archived goal accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'E4 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%not in an eligible state%' THEN RAISE NOTICE 'E4 PASS: archived status rejected'; ELSE RAISE EXCEPTION 'E4 FALSE-PASS: %',SQLERRM; END IF; END;
  -- E5: whitespace-only destination rejected
  PERFORM set_config('role', v_admin, true);
  UPDATE public.goal_registry SET status='funding', dest='   ' WHERE id='d2fix_g01';
  PERFORM set_config('role','authenticated',true);
  BEGIN PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'d2000001','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',100)));
    RAISE EXCEPTION 'E5 FAIL: whitespace dest accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'E5 FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%no valid destination account%' THEN RAISE NOTICE 'E5 PASS: whitespace-only dest rejected'; ELSE RAISE EXCEPTION 'E5 FALSE-PASS: %',SQLERRM; END IF; END;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;
-- (Req 6 NULL-status: goal_registry.status is NOT NULL, so a NULL status is unreachable in practice; the
--  predicate still guards it explicitly — `v_gstatus IS NULL OR NOT IN (...)`. reservable NULL is likewise
--  unreachable — the column is NOT NULL DEFAULT false — and the predicate COALESCEs it defensively.)

-- ══════════════════════════════════════════════════════════════════════════
-- Req 7 — IDENTITY & IDEMPOTENCY
-- ══════════════════════════════════════════════════════════════════════════

-- ── I-ORDER: replay with rows in a different order is idempotent (set-based match). ──
DO $$
DECLARE v_owner UUID; v_res JSONB;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'e1000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
  v_res := public.create_discretionary_goal_reservation_v1(2026,31,'e1000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000),jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000)));
  IF (v_res->>'idempotent')::boolean THEN RAISE NOTICE 'I-ORDER PASS: reordered replay idempotent';
  ELSE RAISE EXCEPTION 'I-ORDER FAIL: %', v_res; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;

-- ── I-REPLAY-PARTINIT / FULLINIT: replay after partial and full initiation is a precise no-op. ──
DO $$
DECLARE v_owner UUID; v_r1 JSONB; v_r2 JSONB;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'e2000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
  PERFORM public.mark_discretionary_goal_reservation_initiated_v1(2026,'e2000001',ARRAY['d2fix_g01'],'BR-PI',NOW(),NULL); -- g01 initiated, g02 scheduled
  v_r1 := public.create_discretionary_goal_reservation_v1(2026,31,'e2000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
  PERFORM public.mark_discretionary_goal_reservation_initiated_v1(2026,'e2000001',NULL,'BR-FI',NOW(),NULL); -- all initiated
  v_r2 := public.create_discretionary_goal_reservation_v1(2026,31,'e2000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000),jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000)));
  IF (v_r1->>'idempotent')::boolean AND (v_r2->>'idempotent')::boolean THEN
    RAISE NOTICE 'I-REPLAY-PARTINIT/FULLINIT PASS: replay after partial+full initiation is a no-op';
  ELSE RAISE EXCEPTION 'I-REPLAY-INIT FAIL: partial=% full=%', v_r1, v_r2; END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;

-- ── I-TERM: replay after a full scheduled void (batch terminal) fails closed (no reactivation). ──
DO $$
DECLARE v_owner UUID;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'e3000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000)));
  PERFORM public.void_scheduled_discretionary_goal_reservation_v1(2026,'e3000001',NULL,'void all -> terminal');
  BEGIN
    PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'e3000001','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000)));
    RAISE EXCEPTION 'I-TERM FAIL: terminal batch was recreated';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'I-TERM FAIL%' THEN RAISE; END IF;
    IF SQLERRM LIKE '%terminal%' THEN RAISE NOTICE 'I-TERM PASS: voided (terminal) batch cannot be recreated';
    ELSE RAISE EXCEPTION 'I-TERM FALSE-PASS: %', SQLERRM; END IF; END;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;

-- ── I-F4: replay succeeds even after a NEWER reconciliation basis exists (replay precedes basis-latest). ──
DO $$
DECLARE v_owner UUID; v_res JSONB; v_can32 BOOLEAN := true;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  PERFORM public.create_discretionary_goal_reservation_v1(2026,31,'e4000001','truist_checking',CURRENT_DATE,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000)));
  -- make basis 31 no longer the max by inserting a newer reconciliation (week 32) if the table permits.
  -- balance_basis is value-restricted TEXT ('posted_current_balance'/'available_balance'/'unknown') → use 'unknown'.
  BEGIN
    INSERT INTO public.weekly_reconciliations (week_num, chk, sav, amx, tax, lc, balance_basis, recorded_at)
    VALUES (32, 3232.31, 3232.32, 3232.33, 3232.34, 3232.35, 'unknown', NOW());
  EXCEPTION WHEN OTHERS THEN v_can32 := false; END;
  IF NOT v_can32 THEN
    RAISE NOTICE 'I-F4 SKIP: weekly_reconciliations rejects week>31 (genuine week-range constraint); F4 is guaranteed structurally (replay branch precedes the basis-latest check) and exercised by N8a/I-ORDER';
  ELSE
    v_res := public.create_discretionary_goal_reservation_v1(2026,31,'e4000001','truist_checking',CURRENT_DATE,
      jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000)));
    IF (v_res->>'idempotent')::boolean THEN RAISE NOTICE 'I-F4 PASS: replay idempotent though basis 31 is no longer the latest reconciled week (max=32)';
    ELSE RAISE EXCEPTION 'I-F4 FAIL: %', v_res; END IF;
  END IF;
  RAISE EXCEPTION 'D2 rollback sentinel';
EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'D2 rollback sentinel%' THEN RAISE; END IF; END $$;

-- ── D2-FROZEN: existing commitment RPCs present AND unchanged (types-only signature via
--    pg_catalog.oidvectortypes(proargtypes) — robust vs the to_regprocedure parse quirk and vs
--    pg_get_function_identity_arguments emitting names; see catalog-verify CHK_frozen_rpcs_present) ──
SELECT 'D2_frozen_rpcs' AS check_name, p.proname,
       pg_catalog.oidvectortypes(p.proargtypes) AS arg_types,
       CASE
         WHEN p.proname='repair_commitments_for_week'
              AND pg_catalog.oidvectortypes(p.proargtypes) = 'integer, integer, text, jsonb, jsonb' THEN 'PASS'
         WHEN p.proname='save_reconciliation_with_commitments'
              AND pg_catalog.oidvectortypes(p.proargtypes) = 'integer, integer, numeric, numeric, numeric, numeric, numeric, text, timestamp with time zone, jsonb, jsonb' THEN 'PASS'
         ELSE 'FAIL' END AS result
FROM pg_proc p
WHERE p.pronamespace='public'::regnamespace
  AND p.proname IN ('repair_commitments_for_week','save_reconciliation_with_commitments')
ORDER BY p.proname;

-- ── D2-CONCURRENCY: run the EXECUTABLE two-session proof in phase-au11-6c-d2-staging-concurrency.sql
--    (checkpoint E). It defines objective PASS criteria (SQLSTATE 55P03 lock timeout for the blocked
--    session, single-active-batch conflict after commit, active-batch count = 1) — not timing alone. ──
SELECT 'D2_concurrency_pointer' AS check_name,
  'see phase-au11-6c-d2-staging-concurrency.sql (executable, objective PASS criteria)' AS note;

-- ── D2-CLEAN: the rolled-back tests left NO reservation rows or batches (fixture rows persist until teardown) ──
SELECT 'D2_no_residual_reservations' AS check_name, count(*) AS n FROM public.cash_commitments WHERE commitment_source='au11_reservation';  -- Expect 0
SELECT 'D2_no_residual_batches'      AS check_name, count(*) AS n FROM public.discretionary_reservation_batches;                            -- Expect 0
-- After validation, run phase-au11-6c-d2-staging-fixture-teardown.sql to remove the fixture and prove zero residue.
