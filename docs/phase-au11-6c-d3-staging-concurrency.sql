-- ============================================================================
-- AU-11 Step 6C-D3 — STAGING CONCURRENCY PROOF (two psql sessions)  [7D-B DRAFT]
-- STAGING ONLY. NOT executed by Claude. Requires the D3 schema + composite RPC + fixture applied.
-- EXECUTION MODE: OWNER/SERVICE session (the RPC is resting-inert post-7D-H2 — no authenticated EXECUTE grant).
--   Each session runs as the owner login role and sets jwt claims=owner so auth.uid()=owner and
--   can_write_financials() passes; the owner can EXECUTE the RPC with no grant. No GRANT/REVOKE is performed,
--   so there is no grant-exposure window. Open TWO owner sessions (A, B). Run blocks in the exact order
--   A1 → B1 → A2 → B2 → V. PASS is objective (SQLSTATE / blocking behavior), not timing.
-- Proves: (1) the au11_disc advisory lock serializes concurrent composite/create calls (single-flight);
--         (2) the partial unique index uix_au11_cleared_txn prevents one Register debit retiring two
--             commitments across independent sessions (transaction_already_attributed / 23505).
-- ============================================================================

-- ===================== SESSION A — block A1 (run first; leave txn OPEN) =====================
BEGIN;
  SET LOCAL lock_timeout = '3s';
  SELECT set_config('request.jwt.claims',
    json_build_object('sub',(SELECT au.auth_user_id FROM public.app_users au
      WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
        AND EXISTS(SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1)::text)::text, true);
  -- owner/service-session mode: do NOT set role=authenticated. The jwt claims above make auth.uid()=owner, so
  -- can_write_financials() (keys on auth.uid(), SECURITY DEFINER) passes; the owner login role can EXECUTE the
  -- resting-inert RPC with no grant. Advisory-lock serialization + unique-index conflict are role-independent.
  -- Acquire the shared AU-11 advisory lock for 2026/truist_checking and HOLD it (do NOT commit).
  SELECT pg_advisory_xact_lock(hashtextextended('au11_disc:2026:truist_checking', 0)) AS a1_lock_acquired;
-- >>> STOP. Do NOT COMMIT. Switch to Session B, run B1. <<<

-- ===================== SESSION B — block B1 (run while A is open) =====================
-- B calls the composite, which must BLOCK on the advisory lock A holds, then abort on lock_timeout (55P03).
BEGIN;
  SET LOCAL lock_timeout = '3s';
  SELECT set_config('request.jwt.claims',
    json_build_object('sub',(SELECT au.auth_user_id FROM public.app_users au
      WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
        AND EXISTS(SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1)::text)::text, true);
  -- owner/service-session mode: do NOT set role=authenticated. The jwt claims above make auth.uid()=owner, so
  -- can_write_financials() (keys on auth.uid(), SECURITY DEFINER) passes; the owner login role can EXECUTE the
  -- resting-inert RPC with no grant. Advisory-lock serialization + unique-index conflict are role-independent.
  -- PASS-B1: this BLOCKS on the au11_disc advisory lock (acquired by the composite at §I.6, BEFORE any evidence
  --          resolution or the §I.16 omitted-check) that A holds, then FAILS with SQLSTATE 55P03 (lock timeout)
  --          — objective proof B serialized on the composite's advisory lock.
  --          PAYLOAD = the FULL eligible set (r1 auto + r3 nominated MULTI_A + r4 auto): a VALID closeout whose
  --          ONLY correctly-run (two-session) failure is the lock. If accidentally run single-session (no
  --          contention) it returns ok=true — a clean "two-session context not established, redo" signal, NOT
  --          omitted_cleared_row (which the earlier single-commitment payload produced and which looked like a bug).
  SELECT public.close_week_with_reservations_v1(30,2026,3030.30,0,0,0,0,'unknown','[]'::jsonb,'[]'::jsonb,
    (SELECT jsonb_agg(jsonb_build_object('goal_id',goal_id,'funded_amount',funded_amount)) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=30),
    'normal_closeout',9,
    jsonb_build_array(
      jsonb_build_object('commitment_id',(SELECT id FROM public.cash_commitments WHERE expected_item_id='d3fix_r1')),
      jsonb_build_object('commitment_id',(SELECT id FROM public.cash_commitments WHERE expected_item_id='d3fix_r3'),'transaction_id',(SELECT id FROM public.transactions WHERE memo='[STAGING-FIXTURE] MULTI_G03_A')),
      jsonb_build_object('commitment_id',(SELECT id FROM public.cash_commitments WHERE expected_item_id='d3fix_r4')))) AS b1_should_lock_timeout;
ROLLBACK;

-- ===================== SESSION A — block A2 (after B1 timed out) =====================
ROLLBACK;  -- release A's advisory lock (nothing persisted)
-- PASS-A2: ROLLBACK succeeds; A held the lock throughout B1.

-- ===================== SESSION B — block B2 (attribution-uniqueness across sessions) =====================
-- With no lock contention now, prove the unique index blocks two commitments claiming the SAME debit across
-- independent attribution. B2 uses two commitments (r1, r3) both nominating EXACT_G01 in one composite call:
BEGIN;
  SELECT set_config('request.jwt.claims',
    json_build_object('sub',(SELECT au.auth_user_id FROM public.app_users au
      WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
        AND EXISTS(SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1)::text)::text, true);
  -- owner/service-session mode: do NOT set role=authenticated. The jwt claims above make auth.uid()=owner, so
  -- can_write_financials() (keys on auth.uid(), SECURITY DEFINER) passes; the owner login role can EXECUTE the
  -- resting-inert RPC with no grant. Advisory-lock serialization + unique-index conflict are role-independent.
  -- PASS-B2: rejected pre-wrapper with 'duplicate_transaction_nomination' (same debit selected twice), the
  --          deterministic pre-check; the partial unique index remains the DB backstop if that check were bypassed.
  SELECT public.close_week_with_reservations_v1(30,2026,3030.30,0,0,0,0,'unknown','[]'::jsonb,'[]'::jsonb,
    (SELECT jsonb_agg(jsonb_build_object('goal_id',goal_id,'funded_amount',funded_amount)) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=30),
    'normal_closeout',9,
    jsonb_build_array(
      jsonb_build_object('commitment_id',(SELECT id FROM public.cash_commitments WHERE expected_item_id='d3fix_r1'),'transaction_id',(SELECT id FROM public.transactions WHERE memo='[STAGING-FIXTURE] EXACT_G01')),
      jsonb_build_object('commitment_id',(SELECT id FROM public.cash_commitments WHERE expected_item_id='d3fix_r3'),'transaction_id',(SELECT id FROM public.transactions WHERE memo='[STAGING-FIXTURE] EXACT_G01')))) AS b2_should_dup_txn;
ROLLBACK;

-- ===================== VERIFY — block V (either session) =====================
-- PASS-V: no residual attribution from the aborted/ rolled-back sessions.
SELECT 'CONC_residue' AS check_name,
       (SELECT count(*) FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_r%' AND cleared_transaction_id IS NOT NULL) AS attributed_rows,  -- expect 0
       (SELECT count(*) FROM public.discretionary_reservation_batches WHERE batch_digest='cd300001' AND status='retired') AS retired_batch;              -- expect 0

-- ── OBJECTIVE PASS CRITERIA ──
--   REQUIRES TWO CONCURRENT psql SESSIONS (a session pooler/direct connection, NOT the transaction pooler, and
--   NOT the Supabase SQL editor — each editor run is a separate connection and cannot hold A's lock across B).
--   PASS-A1: lock acquired, txn held open.
--   PASS-B1: composite aborts with SQLSTATE 55P03 (lock timeout) while A holds au11_disc lock.
--            (B1 returning ok=true ⇒ the two-session context was NOT established (B saw no contention) — REDO
--             with two concurrent sessions; it is NOT a logic pass and NOT a logic failure.)
--   PASS-A2: A ROLLBACK succeeds.
--   PASS-B2: composite aborts with 'duplicate_transaction_nomination' (same debit for two commitments).
--   PASS-V : zero residual attribution / zero retired batch.
-- Any deviation (B1 fails for a reason other than 55P03 / B2 succeeds or fails otherwise / nonzero V) = concurrency FAIL.
-- ============================================================================
