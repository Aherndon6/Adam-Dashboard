-- ============================================================================
-- AU-11 Step 6C-D2 — EXECUTABLE two-session concurrency proof (checkpoint E)
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Requires the fixture (owner + basis week 31 + reservable goals g01/g02).
-- Open TWO Supabase SQL Editor sessions/tabs (Session A and Session B). Run the blocks in the
-- exact order given (A1 → B1 → A2 → B2 → V → CLEANUP). Each block is idempotent-safe and cleans up.
-- PASS is defined by OBJECTIVE results (SQLSTATE / error text / row counts), NOT by timing alone.
--
-- What this proves: pg_advisory_xact_lock serializes concurrent create() calls (single-flight), and the
-- single-active-batch invariant holds under contention — two active batches can never coexist.
-- ============================================================================

-- ===================== SESSION A — block A1 (run first; leave txn OPEN) =====================
-- Acquires the advisory lock and inserts a batch, then HOLDS the transaction open (do NOT commit yet).
BEGIN;
  SET LOCAL lock_timeout = '3s';
  -- Set the JWT claims FIRST, while still on the admin session role: the owner-selection subquery reads
  -- auth.users, which the 'authenticated' role cannot SELECT (permission denied). Switch role AFTER.
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', (SELECT au.auth_user_id FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1)::text)::text, true);
  SELECT set_config('role','authenticated',true);
  -- PASS-A1: returns ok=true, status=active (batch cc000001 created, advisory lock now held by this txn)
  SELECT public.create_discretionary_goal_reservation_v1(
    2026, 31, 'cc000001', 'truist_checking', CURRENT_DATE+7,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g01','amount_cents',1000))) AS a1_result;
-- >>> STOP here. Do NOT COMMIT. Switch to Session B and run B1. <<<

-- ===================== SESSION B — block B1 (run while A is still open) =====================
-- Attempts a DIFFERENT-digest create; must BLOCK on the advisory lock and then abort on lock_timeout.
BEGIN;
  SET LOCAL lock_timeout = '3s';
  -- Set the JWT claims FIRST, while still on the admin session role: the owner-selection subquery reads
  -- auth.users, which the 'authenticated' role cannot SELECT (permission denied). Switch role AFTER.
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', (SELECT au.auth_user_id FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1)::text)::text, true);
  SELECT set_config('role','authenticated',true);
  -- PASS-B1: this call BLOCKS (A holds the lock) then FAILS with SQLSTATE 55P03
  --          ("canceling statement due to lock timeout"). That error is the objective proof B was
  --          blocked on create()'s advisory lock — not a timing guess. If it instead SUCCEEDS or fails
  --          with any other error, PASS-B1 FAILS.
  SELECT public.create_discretionary_goal_reservation_v1(
    2026, 31, 'cc000002', 'truist_checking', CURRENT_DATE+7,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000))) AS b1_should_lock_timeout;
ROLLBACK;   -- end B's (aborted) txn

-- ===================== SESSION A — block A2 (after B1 has timed out) =====================
COMMIT;     -- releases the advisory lock; batch cc000001 is now committed + active
-- PASS-A2: COMMIT succeeds.

-- ===================== SESSION B — block B2 (after A has committed) =====================
-- Now the lock is free; B acquires it but must fail the single-active-batch invariant.
BEGIN;
  SET LOCAL lock_timeout = '3s';
  -- Set the JWT claims FIRST, while still on the admin session role: the owner-selection subquery reads
  -- auth.users, which the 'authenticated' role cannot SELECT (permission denied). Switch role AFTER.
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', (SELECT au.auth_user_id FROM public.app_users au WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1)::text)::text, true);
  SELECT set_config('role','authenticated',true);
  -- PASS-B2: FAILS with 'an active discretionary batch already exists' (single-active-batch invariant).
  SELECT public.create_discretionary_goal_reservation_v1(
    2026, 31, 'cc000002', 'truist_checking', CURRENT_DATE+7,
    jsonb_build_array(jsonb_build_object('goal_id','d2fix_g02','amount_cents',2000))) AS b2_should_conflict;
ROLLBACK;

-- ===================== VERIFY — block V (either session) =====================
-- PASS-C: exactly ONE active batch exists (cc000001). Two active batches must be impossible.
SELECT 'CONC_active_batch_count' AS check_name, count(*) AS active_batches,
       CASE WHEN count(*)=1 THEN 'PASS' ELSE 'FAIL' END AS result
FROM public.discretionary_reservation_batches WHERE status='active';

-- ===================== CLEANUP — block CLEANUP (either session) =====================
-- Remove the committed cc000001 batch + its reservation row so residue returns to zero.
BEGIN;
  DELETE FROM public.cash_commitments
    WHERE reservation_batch_id = (SELECT id FROM public.discretionary_reservation_batches WHERE batch_digest='cc000001');
  DELETE FROM public.discretionary_reservation_batches WHERE batch_digest='cc000001';
COMMIT;
-- PASS-CLEAN: both counts 0.
SELECT 'CONC_residue' AS check_name,
       (SELECT count(*) FROM public.discretionary_reservation_batches) AS batches,
       (SELECT count(*) FROM public.cash_commitments WHERE commitment_source='au11_reservation') AS reservations,
       CASE WHEN (SELECT count(*) FROM public.discretionary_reservation_batches)=0
             AND (SELECT count(*) FROM public.cash_commitments WHERE commitment_source='au11_reservation')=0
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- ── OBJECTIVE PASS CRITERIA (all must hold) ──
--   PASS-A1 : A1 returns ok=true / status=active.
--   PASS-B1 : B1 aborts with SQLSTATE 55P03 (lock timeout) while A is open  ← blocking proven objectively.
--   PASS-A2 : A2 COMMIT succeeds.
--   PASS-B2 : B2 aborts with 'an active discretionary batch already exists'.
--   PASS-C  : exactly one active batch after the sequence.
--   PASS-CLEAN: zero batches / zero au11 reservations after cleanup.
-- Any deviation (B1 succeeding, B1 failing for another reason, B2 succeeding, or count<>1) = concurrency FAIL.
