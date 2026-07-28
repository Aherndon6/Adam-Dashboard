-- ============================================================================
-- AU-11 Step 6C-D3 — STAGING FIXTURE (ledger-tracked, removable, OWNERSHIP-PROVEN)  [7D-B DRAFT]
-- STAGING ONLY. NOT executed by Claude. Adam executes. Deterministic, FAIL-CLOSED on any pre-existing key.
-- Schema-exact INSERTs against committed 5F-1 (cash_commitments), D1 (batch + reservation cols),
-- 5E (transactions), goal_registry, goal_funding_snapshots. Owner referenced by subquery (NO literal UUID).
-- Writer-contract-faithful transactions (RC-1): posted_date NULL / reconciled FALSE / transfer_pair_id NULL.
-- Basis: model week 30 (avoids the removed D2 wk-31 fixture). Sentinel chk=3030.30. Fixture goal ids d3fix_g0*.
-- SAFETY (7D-H1 hardening): this fixture is INSTALL-ONCE-ON-A-CLEAN-SLATE. It refuses to run (RAISE) if ANY
-- fixture-owned key or ANY conflicting Week-30 basis/snapshot row pre-exists — it NEVER silently reuses a
-- pre-existing row. All inserts are plain (NO ON CONFLICT); every row is proven created-by-this-run via
-- ROW_COUNT, and the ledger records EXACT per-row ownership for every teardown target (35 records).
-- To re-install, run the teardown first.
-- ============================================================================
BEGIN;

-- ── Fixture ledger (drives teardown / records exact ownership) ──
CREATE TABLE IF NOT EXISTS public.d3_fixture_ledger (
  ref_kind text NOT NULL, ref_key text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ref_kind, ref_key));
ALTER TABLE public.d3_fixture_ledger ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.d3_fixture_ledger FROM PUBLIC, anon, authenticated;

DO $fix$
DECLARE
  v_owner uuid;
  c_epoch  CONSTANT date := DATE '2026-06-07';
  v_ws date := c_epoch + 7*(30-1);          -- week-30 start
  v_we date := v_ws + 6;                     -- week-30 end
  v_batch uuid;
  r int;
  c_snap_goals CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
  c_fix_goals  CONSTANT text[] := ARRAY['d3fix_g01','d3fix_g02','d3fix_g03','d3fix_g04','d3fix_g05','d3fix_g06','d3fix_g07'];
BEGIN
  -- staging guard + reuse existing active auth-backed owner
  IF NOT EXISTS (SELECT 1 FROM public.app_environment) OR EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging') THEN
    RAISE EXCEPTION 'D3-FIXTURE: not staging'; END IF;
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au
   WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=au.auth_user_id)
   ORDER BY au.auth_user_id LIMIT 1;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'D3-FIXTURE: no qualifying active auth-backed owner'; END IF;

  -- ══ FAIL-CLOSED ABSENCE GUARD — refuse to run if any fixture-owned key OR conflicting wk-30 basis pre-exists ══
  IF EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=30) THEN
    RAISE EXCEPTION 'D3-FIXTURE precheck: a week_num=30 reconciliation already exists (conflicting basis) — run teardown / clear wk30 first'; END IF;
  IF EXISTS (SELECT 1 FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=30 AND goal_id = ANY(c_snap_goals)) THEN
    RAISE EXCEPTION 'D3-FIXTURE precheck: a 2026/week-30 snapshot already exists for a designated goal (conflicting basis)'; END IF;
  IF EXISTS (SELECT 1 FROM public.goal_registry WHERE id LIKE 'd3fix_%') THEN   -- full namespace (symmetry with teardown 'd3fix_%' + commitments guard)
    RAISE EXCEPTION 'D3-FIXTURE precheck: a d3fix-namespace goal already exists'; END IF;
  IF EXISTS (SELECT 1 FROM public.discretionary_reservation_batches WHERE model_year=2026 AND batch_digest='cd300001') THEN
    RAISE EXCEPTION 'D3-FIXTURE precheck: batch cd300001 already exists'; END IF;
  IF EXISTS (SELECT 1 FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_%') THEN
    RAISE EXCEPTION 'D3-FIXTURE precheck: d3fix cash_commitments already exist'; END IF;
  IF EXISTS (SELECT 1 FROM public.transactions WHERE memo LIKE '[STAGING-FIXTURE]%') THEN
    RAISE EXCEPTION 'D3-FIXTURE precheck: [STAGING-FIXTURE] transactions already exist'; END IF;
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger) THEN
    RAISE EXCEPTION 'D3-FIXTURE precheck: d3_fixture_ledger is non-empty (prior-run residue) — run teardown first'; END IF;

  -- ── reservable fixture goals (plain INSERT; absence proven above) + per-row ledger ──
  INSERT INTO public.goal_registry (id, name, tier, target, priority, status, reservable, dest, auto) VALUES
    ('d3fix_g01','D3 Fixture Goal 01','fixture',1000,301,'funding',true ,'Fixture Checking A',false),
    ('d3fix_g02','D3 Fixture Goal 02','fixture',1000,302,'funding',true ,'Fixture Checking B',false),
    ('d3fix_g03','D3 Fixture Goal 03','fixture',1000,303,'funding',true ,'Fixture Checking C',false),
    ('d3fix_g04','D3 Fixture Goal 04','fixture',1000,304,'funding',true ,'Fixture Checking D',false),
    ('d3fix_g05','D3 Fixture Goal 05','fixture',1000,305,'funding',true ,'Fixture Checking E',false),
    ('d3fix_g06','D3 Fixture Goal 06','fixture',1000,306,'funding',true ,'Fixture Checking F',false),
    ('d3fix_g07','D3 Fixture Goal 07','fixture',1000,307,'funding',true ,'Fixture Checking G',false);
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 7 THEN RAISE EXCEPTION 'D3-FIXTURE: expected 7 goals created, got %', r; END IF;
  INSERT INTO public.d3_fixture_ledger(ref_kind,ref_key)
    SELECT 'goal_registry', g FROM unnest(c_fix_goals) g;

  -- ── basis: week-30 sentinel reconciliation (plain INSERT; proven created) + per-row ledger ──
  INSERT INTO public.weekly_reconciliations (week_num, chk, sav, amx, tax, lc, balance_basis, recorded_at)
  VALUES (30, 3030.30, 0, 0, 0, 0, 'unknown', now());
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 1 THEN RAISE EXCEPTION 'D3-FIXTURE: expected 1 wk30 reconciliation, got %', r; END IF;
  INSERT INTO public.d3_fixture_ledger(ref_kind,ref_key) VALUES ('weekly_reconciliations','30:3030.30');

  -- ── nine eligible-goal snapshots (frozen nine-goal contract; plain INSERT; proven created) + PER-ROW ledger ──
  INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note)
  SELECT 2026, 30, g, 100.00, 'correction', '[STAGING-FIXTURE] d3' FROM unnest(c_snap_goals) g;
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 9 THEN RAISE EXCEPTION 'D3-FIXTURE: expected 9 snapshots created, got %', r; END IF;
  INSERT INTO public.d3_fixture_ledger(ref_kind,ref_key)
    SELECT 'goal_funding_snapshots', '2026:30:'||g FROM unnest(c_snap_goals) g;

  -- ── active reservation batch cd300001 (basis week 30; plain INSERT; proven created) + ledger ──
  INSERT INTO public.discretionary_reservation_batches (batch_digest, model_year, source_account, basis_model_week, status, created_by)
  VALUES ('cd300001', 2026, 'truist_checking', 30, 'active', v_owner)
  RETURNING id INTO v_batch;
  IF v_batch IS NULL THEN RAISE EXCEPTION 'D3-FIXTURE: batch cd300001 not created'; END IF;
  INSERT INTO public.d3_fixture_ledger(ref_kind,ref_key) VALUES ('discretionary_reservation_batches','cd300001');

  -- ── reservation rows (au11_reservation shape; distinct goal per row; various lifecycle states; plain INSERT) ──
  --   r1 g01 initiated  amount $100.00  → matches EXACT debit (happy path)
  --   r2 g02 initiated  amount $200.00  → NO matching debit (carry-forward)
  --   r3 g03 initiated  amount $300.00  → TWO matching debits (ambiguous → nomination)
  --   r4 g04 bank_pending amount $400.00 → matches BOUNDARY-first debit
  --   r5 g05 scheduled  amount $500.00  → not retirable (carries)
  --   r6 g06 stale_review amount $600.00 → carries
  --   r7 g07 carried_unresolved amount $700.00 → ANOMALY (D-5 hard-fail when named)
  INSERT INTO public.cash_commitments
    (expected_item_id, model_year, commitment_source, origin_model_week, payee, commitment_class,
     required_or_discretionary, source_account, amount_cents, status, reservation_batch_id, goal_id,
     destination_account_ref, bank_reference, bank_submitted_at, created_by)
  VALUES
    ('d3fix_r1', 2026,'au11_reservation',30,'D3 g01','discretionary_goal_transfer','discretionary_deployment','truist_checking', 10000,'initiated',       v_batch,'d3fix_g01','Fixture Checking A','bref-r1', now(), v_owner),
    ('d3fix_r2', 2026,'au11_reservation',30,'D3 g02','discretionary_goal_transfer','discretionary_deployment','truist_checking', 20000,'initiated',       v_batch,'d3fix_g02','Fixture Checking B','bref-r2', now(), v_owner),
    ('d3fix_r3', 2026,'au11_reservation',30,'D3 g03','discretionary_goal_transfer','discretionary_deployment','truist_checking', 30000,'initiated',       v_batch,'d3fix_g03','Fixture Checking C','bref-r3', now(), v_owner),
    ('d3fix_r4', 2026,'au11_reservation',30,'D3 g04','discretionary_goal_transfer','discretionary_deployment','truist_checking', 40000,'bank_pending',    v_batch,'d3fix_g04','Fixture Checking D','bref-r4', now(), v_owner),
    ('d3fix_r5', 2026,'au11_reservation',30,'D3 g05','discretionary_goal_transfer','discretionary_deployment','truist_checking', 50000,'scheduled',       v_batch,'d3fix_g05','Fixture Checking E', NULL,     NULL,  v_owner),
    ('d3fix_r6', 2026,'au11_reservation',30,'D3 g06','discretionary_goal_transfer','discretionary_deployment','truist_checking', 60000,'stale_review',    v_batch,'d3fix_g06','Fixture Checking F','bref-r6', now(), v_owner),
    ('d3fix_r7', 2026,'au11_reservation',30,'D3 g07','discretionary_goal_transfer','discretionary_deployment','truist_checking', 70000,'carried_unresolved',v_batch,'d3fix_g07','Fixture Checking G','bref-r7', now(), v_owner);
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 7 THEN RAISE EXCEPTION 'D3-FIXTURE: expected 7 reservation rows created, got %', r; END IF;
  INSERT INTO public.d3_fixture_ledger(ref_kind,ref_key)
    SELECT 'cash_commitments', e FROM unnest(ARRAY['d3fix_r1','d3fix_r2','d3fix_r3','d3fix_r4','d3fix_r5','d3fix_r6','d3fix_r7']) e;

  -- ── writer-contract-faithful synthetic transactions (checking; posted_date NULL / reconciled FALSE; plain INSERT) ──
  --   memo carries a stable tag the validation harness matches on. user_id = owner (subquery, no literal UUID).
  INSERT INTO public.transactions (user_id, account_key, transaction_date, payee, memo, amount, cleared, source) VALUES
    (v_owner,'truist_checking', v_ws+3, 'D3 EXACT g01',   '[STAGING-FIXTURE] EXACT_G01',       -100.00, true,  'manual'),  -- r1 exact
    (v_owner,'truist_checking', v_ws+2, 'D3 MULTI g03 A', '[STAGING-FIXTURE] MULTI_G03_A',     -300.00, true,  'manual'),  -- r3 candidate A
    (v_owner,'truist_checking', v_ws+2, 'D3 MULTI g03 B', '[STAGING-FIXTURE] MULTI_G03_B',     -300.00, true,  'manual'),  -- r3 candidate B
    (v_owner,'truist_checking', v_ws,   'D3 BOUNDARY g04','[STAGING-FIXTURE] BOUNDARY_FIRST',  -400.00, true,  'manual'),  -- r4 first-day
    (v_owner,'truist_checking', v_we,   'D3 BOUNDARY LST','[STAGING-FIXTURE] BOUNDARY_LAST',   -450.00, true,  'manual'),  -- last-day (no reservation; boundary+)
    (v_owner,'truist_checking', v_ws-1, 'D3 OUTWEEK pre', '[STAGING-FIXTURE] OUTWEEK_PRE',     -100.00, true,  'manual'),  -- exact amt but day before window
    (v_owner,'truist_checking', v_we+1, 'D3 OUTWEEK post','[STAGING-FIXTURE] OUTWEEK_POST',    -100.00, true,  'manual'),  -- exact amt but day after window
    (v_owner,'truist_checking', v_ws+1, 'D3 UNCLEARED',   '[STAGING-FIXTURE] UNCLEARED',       -100.00, false, 'manual'),  -- exact but not cleared
    (v_owner,'truist_savings',  v_ws+1, 'D3 WRONGACCT',   '[STAGING-FIXTURE] WRONGACCT',       -100.00, true,  'manual'),  -- exact amt/date but wrong account
    (v_owner,'truist_checking', v_ws+1, 'D3 AMOUNTMISS',  '[STAGING-FIXTURE] AMOUNTMISS',      -100.01, true,  'manual');  -- off by one cent
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 10 THEN RAISE EXCEPTION 'D3-FIXTURE: expected 10 transactions created, got %', r; END IF;
  INSERT INTO public.d3_fixture_ledger(ref_kind,ref_key)
    SELECT 'transactions', t FROM unnest(ARRAY['EXACT_G01','MULTI_G03_A','MULTI_G03_B','BOUNDARY_FIRST','BOUNDARY_LAST','OUTWEEK_PRE','OUTWEEK_POST','UNCLEARED','WRONGACCT','AMOUNTMISS']) t;

  -- ══ POST-INSERT OWNERSHIP ASSERTIONS (exact counts exist + ledger has exact ownership for every teardown target) ══
  IF (SELECT count(*) FROM public.goal_registry WHERE id = ANY(c_fix_goals)) <> 7 THEN RAISE EXCEPTION 'D3-FIXTURE assert: goals <> 7'; END IF;
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=30 AND chk=3030.30) <> 1 THEN RAISE EXCEPTION 'D3-FIXTURE assert: wk30 sentinel recon <> 1'; END IF;
  IF (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=30 AND note LIKE '[STAGING-FIXTURE]%') <> 9 THEN RAISE EXCEPTION 'D3-FIXTURE assert: fixture snapshots <> 9'; END IF;
  IF (SELECT count(*) FROM public.discretionary_reservation_batches WHERE model_year=2026 AND batch_digest='cd300001' AND status='active') <> 1 THEN RAISE EXCEPTION 'D3-FIXTURE assert: active batch <> 1'; END IF;
  IF (SELECT count(*) FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_r%') <> 7 THEN RAISE EXCEPTION 'D3-FIXTURE assert: reservation rows <> 7'; END IF;
  IF (SELECT count(*) FROM public.transactions WHERE memo LIKE '[STAGING-FIXTURE]%') <> 10 THEN RAISE EXCEPTION 'D3-FIXTURE assert: fixture transactions <> 10'; END IF;
  -- ledger exact ownership: 7 goals + 1 recon + 9 snapshots + 1 batch + 7 commitments + 10 txns = 35
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='goal_registry')                       <> 7  THEN RAISE EXCEPTION 'D3-FIXTURE assert: ledger goal_registry <> 7'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='weekly_reconciliations')              <> 1  THEN RAISE EXCEPTION 'D3-FIXTURE assert: ledger weekly_reconciliations <> 1'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='goal_funding_snapshots')              <> 9  THEN RAISE EXCEPTION 'D3-FIXTURE assert: ledger goal_funding_snapshots <> 9'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='discretionary_reservation_batches')   <> 1  THEN RAISE EXCEPTION 'D3-FIXTURE assert: ledger batch <> 1'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='cash_commitments')                    <> 7  THEN RAISE EXCEPTION 'D3-FIXTURE assert: ledger cash_commitments <> 7'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='transactions')                        <> 10 THEN RAISE EXCEPTION 'D3-FIXTURE assert: ledger transactions <> 10'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger) <> 35 THEN RAISE EXCEPTION 'D3-FIXTURE assert: total ledger ownership records <> 35 (got %)', (SELECT count(*) FROM public.d3_fixture_ledger); END IF;

  RAISE NOTICE 'D3-FIXTURE seeded (fail-closed, ownership-proven): 7 goals, wk30 sentinel recon, 9 snapshots, batch cd300001, 7 reservations, 10 txns; ledger=35 exact ownership records.';
END $fix$;

-- FIX-CHECK (display): fixture presence + exact ownership ledger
SELECT 'FIX_CHECK' AS check_name,
       (SELECT count(*) FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_r%') AS reservation_rows,                                   -- expect 7
       (SELECT count(*) FROM public.transactions WHERE memo LIKE '[STAGING-FIXTURE]%') AS fixture_txns,                                             -- expect 10
       (SELECT count(*) FROM public.discretionary_reservation_batches WHERE batch_digest='cd300001' AND status='active') AS active_batch,           -- expect 1
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=30 AND note LIKE '[STAGING-FIXTURE]%') AS snapshots,  -- expect 9
       (SELECT count(*) FROM public.goal_registry WHERE id LIKE 'd3fix_%') AS goals,                                                                -- expect 7
       (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=30 AND chk=3030.30) AS recon,                                             -- expect 1
       (SELECT count(*) FROM public.d3_fixture_ledger) AS ledger_records;                                                                           -- expect 35

COMMIT;
-- ============================================================================
