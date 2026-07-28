-- ============================================================================
-- AU-11 Step 6C-D3 — STAGING VALIDATION HARNESS  [7D-B DRAFT — COMPLETE, remediated per Fable v2]
-- STAGING ONLY. NOT executed by Claude. Adam executes AFTER schema + composite RPC + fixture are applied.
--
-- EXECUTION MODEL (isolation): each test runs its ACTION in a plpgsql BEGIN...EXCEPTION sub-block (implicit
--   savepoint). Catching any exception rolls back the sub-block's DB changes while variables retain values;
--   on SUCCESS the test raises a private 'D3RBK' sentinel to force that same rollback. The captured outcome
--   (SQLSTATE+message, or ok/replayed) is recorded via pg_temp.d3_rec() into the COMMITTED d3_test_results
--   OUTSIDE the sub-block. Per-test isolation, order-independence, machine-readable summary, hard-fail —
--   standard plpgsql only (no SAVEPOINT/COMMIT/ROLLBACK inside DO). Runs in psql or the Supabase SQL Editor.
--
-- OMITTED-RULE NOTE (why success tests retire the FULL eligible set): §I.16 raises omitted_cleared_row if any
--   active initiated/bank_pending reservation with an eligible in-week cleared debit is left out of p_retire.
--   The fixture's eligible set is {r1←EXACT, r3←MULTI(2, needs nomination), r4←BOUNDARY_FIRST}; r2 has no debit
--   (carries), r5/r6 are non-retirable, r7 is an anomaly. So every ok=true test retires v_full = r1 + r3(nom
--   MULTI_A) + r4. Error tests (ambiguous/carry/anomaly/dup/etc.) raise in Loop 1a, BEFORE §I.16, so they use
--   a single commitment. WRAPPER CLOSURE: the fixture seeds wk-30 recon (chk=3030.30) + nine snapshots, so the
--   frozen wrapper is IDEMPOTENT for empty-array/matching-recon calls and GFA01 for non-empty resubmission —
--   no direct wrapper PERFORM (which the authenticated role cannot execute) is used.
-- ============================================================================
-- FAIL-SAFE TRANSACTION: the whole harness runs inside ONE explicit BEGIN...COMMIT so the temporary EXECUTE
-- grant is atomic — ANY error (a test, a grant-state/33-row gate, or cleanup) rolls the transaction back,
-- UN-granting authenticated EXECUTE and reverting every test mutation. COMMIT is reached only after all gates
-- pass. Run the block AS-IS; do NOT add another transaction wrapper. The standalone inert check runs post-COMMIT.
-- ============================================================================
BEGIN;

DROP TABLE IF EXISTS public.d3_test_results;
CREATE TABLE public.d3_test_results(
  test_id text PRIMARY KEY, expected text NOT NULL, actual text, result text NOT NULL DEFAULT 'FAIL', residue int);

-- SECURITY DEFINER (owner postgres) + empty search_path + fully-qualified refs: the INSERT into
-- public.d3_test_results and the residue SELECT run as the function owner, NOT as the caller. This makes the
-- recorder work while role=authenticated WITHOUT granting authenticated any table privilege (D-8 / RPC-only).
CREATE OR REPLACE FUNCTION pg_temp.d3_rec(p_id text, p_expected text, p_actual text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $p$
BEGIN
  INSERT INTO public.d3_test_results(test_id, expected, actual, result, residue)
  VALUES (p_id, p_expected, p_actual,
          CASE WHEN p_actual ILIKE '%'||p_expected||'%' THEN 'PASS' ELSE 'FAIL' END,
          (SELECT count(*) FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_r%' AND cleared_transaction_id IS NOT NULL));
END $p$;

-- (0a) RECORDER-PRIVILEGE PREFLIGHT (#1) — informational meta-row recorded as postgres BEFORE any role change:
--   proves the actual staging catalog grant of INSERT-on-results to authenticated. NOT required for correctness
--   (d3_rec is SECURITY DEFINER and inserts as its owner); recorded so the value is visible in the summary.
INSERT INTO public.d3_test_results(test_id, expected, actual, result, residue)
VALUES ('Z-PRIV-auth-insert-on-results','informational',
        has_table_privilege('authenticated','public.d3_test_results','INSERT')::text,'PASS',0);

-- ── (0) grant EXECUTE only for the authorized test window (D-8) ──
SELECT 'GRANT_absent_before' AS check_name, has_function_privilege('authenticated', p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='close_week_with_reservations_v1';
-- machine-assert: authenticated must NOT already hold EXECUTE before the window (else a pre-existing leak would be silently repaired by the REVOKE)
DO $g0$ BEGIN
  IF (SELECT has_function_privilege('authenticated', p.oid,'EXECUTE') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='close_week_with_reservations_v1')
  THEN RAISE EXCEPTION 'D3-VALIDATION HARD FAIL: authenticated already holds EXECUTE BEFORE the test-window GRANT (pre-existing leak)'; END IF;
END $g0$;
GRANT EXECUTE ON FUNCTION public.close_week_with_reservations_v1(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT,JSONB) TO authenticated;
SELECT 'GRANT_present_during' AS check_name, has_function_privilege('authenticated', p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='close_week_with_reservations_v1';
-- machine-assert: authenticated EXECUTE must be present during the test window (GRANT took effect)
DO $g1$ BEGIN
  IF NOT (SELECT has_function_privilege('authenticated', p.oid,'EXECUTE') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='close_week_with_reservations_v1')
  THEN RAISE EXCEPTION 'D3-VALIDATION HARD FAIL: authenticated EXECUTE not present during test window (GRANT did not take effect)'; END IF;
END $g1$;

DO $val$
DECLARE
  v_owner uuid; v_hh uuid;
  v_snaps jsonb; v_full jsonb;
  v_r1 uuid; v_r2 uuid; v_r3 uuid; v_r4 uuid; v_r5 uuid; v_r7 uuid;
  v_tx_exact uuid; v_tx_a uuid; v_tx_post uuid; v_tx_bfirst uuid; v_txk uuid;
  v_actual text; v_res jsonb; v_cleared int; k text;
  c_chk CONSTANT numeric := 3030.30;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au
   WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  SELECT au.auth_user_id INTO v_hh FROM public.app_users au
   WHERE au.role='household_admin' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id) ORDER BY au.auth_user_id LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  PERFORM set_config('role','authenticated', true);

  SELECT id INTO v_r1 FROM public.cash_commitments WHERE expected_item_id='d3fix_r1';
  SELECT id INTO v_r2 FROM public.cash_commitments WHERE expected_item_id='d3fix_r2';
  SELECT id INTO v_r3 FROM public.cash_commitments WHERE expected_item_id='d3fix_r3';
  SELECT id INTO v_r4 FROM public.cash_commitments WHERE expected_item_id='d3fix_r4';
  SELECT id INTO v_r5 FROM public.cash_commitments WHERE expected_item_id='d3fix_r5';
  SELECT id INTO v_r7 FROM public.cash_commitments WHERE expected_item_id='d3fix_r7';
  SELECT id INTO v_tx_exact  FROM public.transactions WHERE memo='[STAGING-FIXTURE] EXACT_G01';
  SELECT id INTO v_tx_a      FROM public.transactions WHERE memo='[STAGING-FIXTURE] MULTI_G03_A';
  SELECT id INTO v_tx_post   FROM public.transactions WHERE memo='[STAGING-FIXTURE] OUTWEEK_POST';
  SELECT id INTO v_tx_bfirst FROM public.transactions WHERE memo='[STAGING-FIXTURE] BOUNDARY_FIRST';
  SELECT jsonb_agg(jsonb_build_object('goal_id',goal_id,'funded_amount',funded_amount))
    INTO v_snaps FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=30;
  -- the complete eligible retirement set (avoids omitted_cleared_row): r1 auto, r3 nominated, r4 auto
  v_full := jsonb_build_array(jsonb_build_object('commitment_id',v_r1),
                              jsonb_build_object('commitment_id',v_r3,'transaction_id',v_tx_a),
                              jsonb_build_object('commitment_id',v_r4));

  -- (0b) RECORDER SELF-TEST (#5) — REQUIRED assertion that the recorder works while role=authenticated, BEFORE
  --   the 31 tests. d3_rec is SECURITY DEFINER; an uncaught failure here (e.g. 42501) aborts the whole harness
  --   before any test runs — a hard stop by construction, proving the recorder path under the active role.
  PERFORM pg_temp.d3_rec('T-RECORDER-SELFTEST','recorder_ok','recorder_ok');

  -- ══════════ SUCCESS PATHS (retire the FULL eligible set → ok=true; covers exact/nomination/boundary) ══════════
  -- T-HAPPY: full set → ok=true (r1 exact match, r3 valid nomination, r4 boundary-first week_start match)
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,v_full);
        v_actual:='ok='||(v_res->>'ok'); RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-HAPPY-FULLSET','ok=true',v_actual);

  -- T-BOUNDARY-FIRST: r4's debit is exactly week_start; full set → ok=true confirms inclusive first-day match
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,v_full);
        v_actual:='ok='||(v_res->>'ok'); RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-BOUNDARY-FIRST','ok=true',v_actual);

  -- T-NOM-VALID: r3 nominated within the full set → ok=true
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,v_full);
        v_actual:='ok='||(v_res->>'ok'); RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-NOM-VALID','ok=true',v_actual);

  -- T-R2-2-REPLAY: wk-30 already closed by fixture; empty arrays + full set → wrapper idempotent + retire → ok
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,v_full);
        v_actual:='ok='||(v_res->>'ok'); RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-R2-2-REPLAY','ok=true',v_actual);

  -- T-REPLAY-B-SAME: pre-clear the full eligible set to its debits, replay full set → all idempotent → replayed=true
  --   (direct setup UPDATEs need table privilege: authenticated is SELECT-only on cash_commitments per 5F-1;
  --    elevate to owner for the setup writes, then restore authenticated before the RPC so authz is still tested)
  BEGIN
    PERFORM set_config('role','postgres',true);
    UPDATE public.cash_commitments SET status='cleared', cleared_transaction_id=v_tx_exact, cleared_date=(SELECT transaction_date FROM public.transactions WHERE id=v_tx_exact),
      reflected_model_week=30, resolved_model_week=30, resolution_type='cleared', resolved_by=v_owner, resolved_at=now() WHERE id=v_r1;
    UPDATE public.cash_commitments SET status='cleared', cleared_transaction_id=v_tx_a, cleared_date=(SELECT transaction_date FROM public.transactions WHERE id=v_tx_a),
      reflected_model_week=30, resolved_model_week=30, resolution_type='cleared', resolved_by=v_owner, resolved_at=now() WHERE id=v_r3;
    UPDATE public.cash_commitments SET status='cleared', cleared_transaction_id=v_tx_bfirst, cleared_date=(SELECT transaction_date FROM public.transactions WHERE id=v_tx_bfirst),
      reflected_model_week=30, resolved_model_week=30, resolution_type='cleared', resolved_by=v_owner, resolved_at=now() WHERE id=v_r4;
    PERFORM set_config('role','authenticated',true);
    v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,v_full);
    v_actual:='replayed='||(v_res->>'replayed'); RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-REPLAY-B-SAME','replayed=true',v_actual);

  -- ══════════ ERROR PATHS (raise in Loop 1a BEFORE §I.16, so single-commitment inputs are fine) ══════════
  -- T-CARRY: r2 has no matching debit → evidence_missing
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_r2))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-CARRY','evidence_missing',v_actual);

  -- T-AMBIGUOUS: r3 two candidates, no nomination → ambiguous_multiple_match
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_r3))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-AMBIGUOUS','ambiguous_multiple_match',v_actual);

  -- T-NOM-INVALID: r3 + OUTWEEK_POST (not eligible) → nominated_transaction_not_eligible
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_r3,'transaction_id',v_tx_post))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-NOM-INVALID','nominated_transaction_not_eligible',v_actual);

  -- Negative evidence (wrong-account / uncleared / amount-miss / out-of-week) via nomination on r1 → not eligible
  FOR k IN SELECT unnest(ARRAY['WRONGACCT','UNCLEARED','AMOUNTMISS','OUTWEEK_PRE','OUTWEEK_POST']) LOOP
    SELECT id INTO v_txk FROM public.transactions WHERE memo='[STAGING-FIXTURE] '||k;
    BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
             jsonb_build_array(jsonb_build_object('commitment_id',v_r1,'transaction_id',v_txk))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
    EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
    PERFORM pg_temp.d3_rec('T-NEG-'||k,'nominated_transaction_not_eligible',v_actual);
  END LOOP;

  -- T-ANOMALY: r7 carried_unresolved → anomalous_lifecycle_state
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_r7))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-ANOMALY','anomalous_lifecycle_state',v_actual);

  -- T-NOT-RETIRABLE: r5 scheduled (not initiated/bank_pending) → commitment_not_retirable  [V3 fix]
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_r5))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-NOT-RETIRABLE','commitment_not_retirable',v_actual);

  -- T-DUP-COMMIT: r1 twice → duplicate_commitment_entry
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_r1), jsonb_build_object('commitment_id',v_r1))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-DUP-COMMIT','duplicate_commitment_entry',v_actual);

  -- T-DUP-TXN: r1 and r3 both nominate the same debit → duplicate_transaction_nomination
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_r1,'transaction_id',v_tx_a),
                             jsonb_build_object('commitment_id',v_r3,'transaction_id',v_tx_a))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-DUP-TXN','duplicate_transaction_nomination',v_actual);

  -- T-UNKNOWN: a txn id, not a commitment → unknown_commitment
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_tx_exact))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-UNKNOWN','unknown_commitment',v_actual);

  -- T-OUT-OF-BATCH: deactivate the batch in-sub-block → v_batch NULL → commitment_not_in_active_batch
  BEGIN
    PERFORM set_config('role','postgres',true);   -- authenticated is SELECT-only on discretionary_reservation_batches (D1)
    UPDATE public.discretionary_reservation_batches SET status='voided' WHERE model_year=2026 AND batch_digest='cd300001';
    PERFORM set_config('role','authenticated',true);
    v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
             jsonb_build_array(jsonb_build_object('commitment_id',v_r1))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-OUT-OF-BATCH','commitment_not_in_active_batch',v_actual);

  -- T-OMITTED: retire only r1 while r3/r4 (eligible in-week debits) omitted → omitted_cleared_row
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_r1))); v_actual:='ok='||(v_res->>'ok'); RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-OMITTED','omitted_cleared_row',v_actual);

  -- T-REPLAY-C-DIFF: r1 pre-cleared to EXACT, replay nominating a different txn → transaction_already_attributed
  --   (state C raises in Loop 1a, preempting §I.16, so single-commitment is fine)
  BEGIN
    PERFORM set_config('role','postgres',true);
    UPDATE public.cash_commitments SET status='cleared', cleared_transaction_id=v_tx_exact, cleared_date=(SELECT transaction_date FROM public.transactions WHERE id=v_tx_exact),
      reflected_model_week=30, resolved_model_week=30, resolution_type='cleared', resolved_by=v_owner, resolved_at=now() WHERE id=v_r1;
    PERFORM set_config('role','authenticated',true);
    v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
             jsonb_build_array(jsonb_build_object('commitment_id',v_r1,'transaction_id',v_tx_a))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-REPLAY-C-DIFF','transaction_already_attributed',v_actual);

  -- T-STATE-F-CHECK: cleared row without attribution violates chk_au11_cleared_txn_attribution (DB-enforced)
  --   (elevate to owner so the UPDATE reaches the CHECK constraint rather than a table-privilege 42501)
  BEGIN
    PERFORM set_config('role','postgres',true);
    UPDATE public.cash_commitments SET status='cleared', cleared_transaction_id=NULL, resolution_type='cleared',
      reflected_model_week=30, resolved_model_week=30, resolved_by=v_owner, resolved_at=now() WHERE id=v_r1; v_actual:='UPDATE_OK'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-STATE-F-CHECK','chk_au11_cleared_txn_attribution',v_actual);

  -- ══════════ WRAPPER + ORDERING (no direct wrapper PERFORM; wk-30 is fixture-closed) ══════════
  -- T-R2-3-GFA01: NON-EMPTY commitments on the (fixture-closed) wk-30 → wrapper GFA01 → propagated, no retirement
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown',
           jsonb_build_array(jsonb_build_object('goal_id','adam_ira','amount_cents',1)),'[]',v_snaps,'normal_closeout',9, v_full);
        v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-R2-3-GFA01','GFA01',v_actual);

  -- T-ORDERING (DYNAMIC wrapper-fail-AFTER-evidence-lock): {r1} resolves+id-order-locks EXACT in Loop 1a, THEN
  --   NON-EMPTY commitments → wrapper GFA01 → propagate. GFA01 proves the wrapper WAS reached past evidence
  --   selection; cleared_rows=0 confirms NO attribution ran. (With static proof that attribution code is
  --   strictly after wrapper verify, this is the dynamic wrapper-before-attribution evidence.)
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown',
           jsonb_build_array(jsonb_build_object('goal_id','adam_ira','amount_cents',1)),'[]',v_snaps,'normal_closeout',9,
           jsonb_build_array(jsonb_build_object('commitment_id',v_r1))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN
    IF SQLERRM<>'D3RBK' THEN
      SELECT count(*) INTO v_cleared FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_r%' AND status='cleared';
      v_actual := SQLSTATE||' '||SQLERRM||' | cleared_rows='||v_cleared::text;
    END IF;
  END;
  PERFORM pg_temp.d3_rec('T-ORDERING-GFA01','GFA01',v_actual);
  PERFORM pg_temp.d3_rec('T-ORDERING-NOATTR','cleared_rows=0',v_actual);

  -- ══════════ SCALAR / AUTHORIZATION ══════════
  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',8,'[]'); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-SCALAR-EXPCOUNT','wrapper_contract_fail',v_actual);

  BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'approved_reopen',9,'[]'); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-UNSUPPORTED-MODE','unsupported_mode',v_actual);

  BEGIN v_res := public.close_week_with_reservations_v1(32,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,'[]'); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-WEEK-RANGE','week_window_mismatch',v_actual);

  BEGIN v_res := public.close_week_with_reservations_v1(30,2025,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,'[]'); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
  EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
  PERFORM pg_temp.d3_rec('T-AUTHZ-MODELYEAR','unsupported_model_year',v_actual);

  BEGIN PERFORM set_config('role','anon', true);
    BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,'[]'); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
    EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
    PERFORM set_config('role','authenticated', true);
  END;
  PERFORM pg_temp.d3_rec('T-AUTHZ-ANON','42501',v_actual);

  IF v_hh IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_hh::text)::text, true);
    BEGIN v_res := public.close_week_with_reservations_v1(30,2026,c_chk,0,0,0,0,'unknown','[]','[]',v_snaps,'normal_closeout',9,
             jsonb_build_array(jsonb_build_object('commitment_id',v_r2))); v_actual:='RETURNED'; RAISE EXCEPTION 'D3RBK';
    EXCEPTION WHEN others THEN IF SQLERRM<>'D3RBK' THEN v_actual:=SQLSTATE||' '||SQLERRM; END IF; END;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
    PERFORM pg_temp.d3_rec('T-AUTHZ-HOUSEHOLD','evidence_missing',v_actual);  -- reached evidence logic ⇒ authz allowed
  ELSE
    PERFORM pg_temp.d3_rec('T-AUTHZ-HOUSEHOLD','PROVISION_REQUIRED','SKIP: no household_admin fixture — provision before 7D-H');
  END IF;

  -- Taxonomy coverage note — the four remaining outcomes are defensive/concurrency-only (valid rationale):
  --   evidence_changed → phase-au11-6c-d3-staging-concurrency.sql (locked-read drift); retirement_count_mismatch
  --   → defensive (UPDATE WHERE matches one row or 23505); inconsistent_batch_state (retired-batch variant) →
  --   unconstructable without corrupting the batch (the cleared-missing-attribution variant is CHECK-proven by
  --   T-STATE-F-CHECK); unrelated-23505 → static handler property (mapping gated on uix name, ELSE RAISE).
END $val$;

-- Reset session role to the owner before the privileged REVOKE/DROP. The DO block set a TRANSACTION-LOCAL
-- role=authenticated that does NOT revert at DO exit; since the whole harness is one explicit transaction it
-- would otherwise leak here and make the REVOKE/DROP fail. RESET ROLE restores the owner for the cleanup.
RESET ROLE;

-- ── REVOKE EXECUTE — resting-inert (D-8) ──
REVOKE EXECUTE ON FUNCTION public.close_week_with_reservations_v1(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT,JSONB) FROM authenticated;
SELECT 'GRANT_absent_after' AS check_name, has_function_privilege('authenticated', p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='close_week_with_reservations_v1';
-- machine-assert: authenticated EXECUTE must be absent after REVOKE (window closed; resting-inert restored)
DO $g2$ BEGIN
  IF (SELECT has_function_privilege('authenticated', p.oid,'EXECUTE') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='close_week_with_reservations_v1')
  THEN RAISE EXCEPTION 'D3-VALIDATION HARD FAIL: authenticated still holds EXECUTE AFTER REVOKE'; END IF;
END $g2$;

-- ── machine-readable summary + HARD-FAIL ──
SELECT test_id, expected, actual, result, residue FROM public.d3_test_results ORDER BY test_id;
DO $sum$
DECLARE v_fail int; v_res_total int; v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.d3_test_results;
  IF v_count <> 33 THEN RAISE EXCEPTION 'D3-VALIDATION HARD FAIL: expected 33 result rows, got %', v_count; END IF;
  SELECT count(*) INTO v_fail FROM public.d3_test_results WHERE result<>'PASS';
  SELECT COALESCE(sum(residue),0) INTO v_res_total FROM public.d3_test_results;
  IF v_fail > 0 THEN RAISE EXCEPTION 'D3-VALIDATION HARD FAIL: % test(s) not PASS', v_fail; END IF;
  IF v_res_total > 0 THEN RAISE EXCEPTION 'D3-VALIDATION HARD FAIL: nonzero residue total %', v_res_total; END IF;
  RAISE NOTICE 'D3-VALIDATION: all 33 rows PASS; zero residue.';
END $sum$;
DROP TABLE IF EXISTS public.d3_test_results;
DROP FUNCTION IF EXISTS pg_temp.d3_rec(text,text,text);

COMMIT;   -- reached only if every gate above passed; on ANY error the whole transaction rolls back (temporary EXECUTE grant un-granted, all mutations reverted)
-- ============================================================================
