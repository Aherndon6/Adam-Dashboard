-- ============================================================================
-- AU-11 Step 6C-D3 — STAGING FIXTURE TEARDOWN (LEDGER-OWNERSHIP-VERIFIED, count-asserted)  [7D-B DRAFT]
-- STAGING ONLY. NOT executed by Claude. Removes the entire D3 fixture and ASSERTS zero residue.
-- OWNERSHIP MODEL: the fixture's d3_fixture_ledger is the authoritative ownership record (35 rows the H1
--   fixture inserted). Teardown PROVES ledger integrity (exists, 35 rows, allowed kinds + exact per-kind
--   counts, non-null keys — PK enforces uniqueness) and a full LEDGER⇔FIXTURE BIJECTION (every ledger
--   reference resolves to a fixture object, and every namespaced fixture object is represented in the ledger,
--   proving namespace exclusivity) BEFORE any deletion. It then deletes through ledger-owned references with
--   EXACT ROW_COUNT assertions (reservations 7 · transactions 10 · batch 1 · snapshots 9 · reconciliation 1 ·
--   goals 7), asserts zero residue (incl. dangling attribution), and only AFTER the owned objects are gone
--   empties the ledger (asserting 35 removed) and drops it. Atomic BEGIN…COMMIT; fails closed on any mismatch.
-- FK order: cash_commitments (referencing) → transactions → batch → snapshots → reconciliation → goals → ledger.
-- ============================================================================
BEGIN;
DO $td$
DECLARE r int; v_ct int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.app_environment) OR EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging') THEN
    RAISE EXCEPTION 'D3-TEARDOWN: not staging'; END IF;

  -- ═══ PHASE 0 — LEDGER INTEGRITY (reqs 1-4) ═══
  IF to_regclass('public.d3_fixture_ledger') IS NULL THEN
    RAISE EXCEPTION 'D3-TEARDOWN: ledger table absent — cannot prove ownership (do NOT pattern-delete)'; END IF;                                   -- 1
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger WHERE ref_kind IS NULL OR ref_key IS NULL) THEN
    RAISE EXCEPTION 'D3-TEARDOWN: ledger has null ref_kind/ref_key'; END IF;                                                                       -- 4 (uniqueness is PK-enforced)
  SELECT count(*) INTO v_ct FROM public.d3_fixture_ledger;
  IF v_ct <> 35 THEN RAISE EXCEPTION 'D3-TEARDOWN: ledger has % records, expected exactly 35', v_ct; END IF;                                       -- 2
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger WHERE ref_kind NOT IN
      ('goal_registry','weekly_reconciliations','goal_funding_snapshots','discretionary_reservation_batches','cash_commitments','transactions')) THEN
    RAISE EXCEPTION 'D3-TEARDOWN: ledger contains a disallowed ref_kind'; END IF;                                                                  -- 3 (allowed kinds)
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='goal_registry')                     <> 7  THEN RAISE EXCEPTION 'D3-TEARDOWN: ledger goal_registry <> 7'; END IF;                     -- 3 (per-kind)
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='weekly_reconciliations')            <> 1  THEN RAISE EXCEPTION 'D3-TEARDOWN: ledger weekly_reconciliations <> 1'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='goal_funding_snapshots')            <> 9  THEN RAISE EXCEPTION 'D3-TEARDOWN: ledger goal_funding_snapshots <> 9'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='discretionary_reservation_batches') <> 1  THEN RAISE EXCEPTION 'D3-TEARDOWN: ledger batch <> 1'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='cash_commitments')                  <> 7  THEN RAISE EXCEPTION 'D3-TEARDOWN: ledger cash_commitments <> 7'; END IF;
  IF (SELECT count(*) FROM public.d3_fixture_ledger WHERE ref_kind='transactions')                      <> 10 THEN RAISE EXCEPTION 'D3-TEARDOWN: ledger transactions <> 10'; END IF;

  -- ═══ PHASE 1 — LEDGER ⇒ FIXTURE (every ledger reference resolves to a fixture object, req 5) ═══
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger l WHERE l.ref_kind='goal_registry'
             AND NOT EXISTS (SELECT 1 FROM public.goal_registry g WHERE g.id=l.ref_key)) THEN
    RAISE EXCEPTION 'D3-TEARDOWN: a ledger goal_registry ref does not resolve'; END IF;
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger l WHERE l.ref_kind='weekly_reconciliations'
             AND NOT (l.ref_key='30:3030.30' AND EXISTS (SELECT 1 FROM public.weekly_reconciliations w WHERE w.week_num=30 AND w.chk=3030.30))) THEN
    RAISE EXCEPTION 'D3-TEARDOWN: the ledger weekly_reconciliations ref does not resolve'; END IF;
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger l WHERE l.ref_kind='goal_funding_snapshots'
             AND NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots s
                             WHERE s.model_year=2026 AND s.week_num=30 AND s.note LIKE '[STAGING-FIXTURE]%'
                               AND l.ref_key = ('2026:30:'||s.goal_id))) THEN
    RAISE EXCEPTION 'D3-TEARDOWN: a ledger goal_funding_snapshots ref does not resolve'; END IF;
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger l WHERE l.ref_kind='discretionary_reservation_batches'
             AND NOT EXISTS (SELECT 1 FROM public.discretionary_reservation_batches b WHERE b.model_year=2026 AND b.batch_digest=l.ref_key)) THEN
    RAISE EXCEPTION 'D3-TEARDOWN: the ledger batch ref does not resolve'; END IF;
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger l WHERE l.ref_kind='cash_commitments'
             AND NOT EXISTS (SELECT 1 FROM public.cash_commitments c WHERE c.expected_item_id=l.ref_key)) THEN
    RAISE EXCEPTION 'D3-TEARDOWN: a ledger cash_commitments ref does not resolve'; END IF;
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger l WHERE l.ref_kind='transactions'
             AND NOT EXISTS (SELECT 1 FROM public.transactions t WHERE t.memo = ('[STAGING-FIXTURE] '||l.ref_key))) THEN
    RAISE EXCEPTION 'D3-TEARDOWN: a ledger transactions ref does not resolve'; END IF;

  -- ═══ PHASE 1b — FIXTURE ⇒ LEDGER (namespace exclusivity: every namespaced object is ledgered, reqs 6-7) ═══
  --   namespace count == ledger count for each kind ⇒ NO extraneous non-fixture object matches the pattern,
  --   so the subsequent ledger-driven deletes cannot miss/over-reach.
  IF (SELECT count(*) FROM public.goal_registry WHERE id LIKE 'd3fix_%')                                                        <> 7  THEN RAISE EXCEPTION 'D3-TEARDOWN: d3fix goals in namespace <> 7 (un-ledgered residue)'; END IF;
  IF (SELECT count(*) FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_%')                                       <> 7  THEN RAISE EXCEPTION 'D3-TEARDOWN: d3fix commitments in namespace <> 7'; END IF;
  IF (SELECT count(*) FROM public.transactions WHERE memo LIKE '[STAGING-FIXTURE]%')                                            <> 10 THEN RAISE EXCEPTION 'D3-TEARDOWN: [STAGING-FIXTURE] transactions <> 10'; END IF;
  IF (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=30 AND note LIKE '[STAGING-FIXTURE]%') <> 9 THEN RAISE EXCEPTION 'D3-TEARDOWN: fixture snapshots <> 9'; END IF;
  IF (SELECT count(*) FROM public.discretionary_reservation_batches WHERE model_year=2026 AND batch_digest='cd300001')          <> 1  THEN RAISE EXCEPTION 'D3-TEARDOWN: batch cd300001 <> 1'; END IF;
  IF (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=30 AND chk=3030.30)                                     <> 1  THEN RAISE EXCEPTION 'D3-TEARDOWN: wk30 sentinel reconciliation <> 1'; END IF;

  -- ═══ PHASE 2 — DELETE OWNED OBJECTS through ledger-owned references, EXACT count asserts (req 8) ═══
  DELETE FROM public.cash_commitments
   WHERE expected_item_id IN (SELECT ref_key FROM public.d3_fixture_ledger WHERE ref_kind='cash_commitments');
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 7 THEN RAISE EXCEPTION 'D3-TEARDOWN: deleted % reservation rows, expected 7', r; END IF;
  RAISE NOTICE 'D3-TEARDOWN reservation rows removed: %', r;

  DELETE FROM public.transactions
   WHERE memo IN (SELECT '[STAGING-FIXTURE] '||ref_key FROM public.d3_fixture_ledger WHERE ref_kind='transactions');
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 10 THEN RAISE EXCEPTION 'D3-TEARDOWN: deleted % transactions, expected 10', r; END IF;
  RAISE NOTICE 'D3-TEARDOWN fixture transactions removed: %', r;

  DELETE FROM public.discretionary_reservation_batches
   WHERE model_year=2026 AND batch_digest IN (SELECT ref_key FROM public.d3_fixture_ledger WHERE ref_kind='discretionary_reservation_batches');
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 1 THEN RAISE EXCEPTION 'D3-TEARDOWN: deleted % batch, expected 1', r; END IF;

  DELETE FROM public.goal_funding_snapshots
   WHERE model_year=2026 AND week_num=30 AND note LIKE '[STAGING-FIXTURE]%'
     AND ('2026:30:'||goal_id) IN (SELECT ref_key FROM public.d3_fixture_ledger WHERE ref_kind='goal_funding_snapshots');
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 9 THEN RAISE EXCEPTION 'D3-TEARDOWN: deleted % snapshots, expected 9', r; END IF;

  DELETE FROM public.weekly_reconciliations
   WHERE week_num=30 AND chk=3030.30
     AND EXISTS (SELECT 1 FROM public.d3_fixture_ledger WHERE ref_kind='weekly_reconciliations' AND ref_key='30:3030.30');
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 1 THEN RAISE EXCEPTION 'D3-TEARDOWN: deleted % reconciliation, expected 1', r; END IF;

  DELETE FROM public.goal_registry
   WHERE id IN (SELECT ref_key FROM public.d3_fixture_ledger WHERE ref_kind='goal_registry');
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 7 THEN RAISE EXCEPTION 'D3-TEARDOWN: deleted % goals, expected 7', r; END IF;

  -- ═══ PHASE 3 — ASSERTED ZERO RESIDUE (owned objects gone; incl. dangling attribution) ═══
  IF EXISTS (SELECT 1 FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_r%') THEN RAISE EXCEPTION 'D3-TEARDOWN residue: reservation rows'; END IF;
  IF EXISTS (SELECT 1 FROM public.transactions WHERE memo LIKE '[STAGING-FIXTURE]%') THEN RAISE EXCEPTION 'D3-TEARDOWN residue: fixture transactions'; END IF;
  IF EXISTS (SELECT 1 FROM public.discretionary_reservation_batches WHERE batch_digest='cd300001') THEN RAISE EXCEPTION 'D3-TEARDOWN residue: batch'; END IF;
  IF EXISTS (SELECT 1 FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=30 AND note LIKE '[STAGING-FIXTURE]%') THEN RAISE EXCEPTION 'D3-TEARDOWN residue: snapshots'; END IF;
  IF EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=30 AND chk=3030.30) THEN RAISE EXCEPTION 'D3-TEARDOWN residue: reconciliation'; END IF;
  IF EXISTS (SELECT 1 FROM public.goal_registry WHERE id LIKE 'd3fix_%') THEN RAISE EXCEPTION 'D3-TEARDOWN residue: goals'; END IF;
  IF EXISTS (SELECT 1 FROM public.cash_commitments cc WHERE cc.commitment_source='au11_reservation'
             AND cc.cleared_transaction_id IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM public.transactions t WHERE t.id=cc.cleared_transaction_id)) THEN
    RAISE EXCEPTION 'D3-TEARDOWN residue: dangling attribution'; END IF;

  -- ═══ PHASE 4 — EMPTY THE LEDGER ONLY AFTER OWNED OBJECTS ARE GONE (req 9) ═══
  IF (SELECT count(*) FROM public.d3_fixture_ledger) <> 35 THEN RAISE EXCEPTION 'D3-TEARDOWN: ledger row count changed during teardown (<> 35)'; END IF;
  DELETE FROM public.d3_fixture_ledger;
  GET DIAGNOSTICS r = ROW_COUNT; IF r <> 35 THEN RAISE EXCEPTION 'D3-TEARDOWN: deleted % ledger records, expected 35', r; END IF;
  IF EXISTS (SELECT 1 FROM public.d3_fixture_ledger) THEN RAISE EXCEPTION 'D3-TEARDOWN: ledger not empty after delete'; END IF;

  RAISE NOTICE 'D3-TEARDOWN PASS: ledger-verified (35 owned records) → removed 7 reservations, 10 transactions, 1 batch, 9 snapshots, 1 reconciliation, 7 goals (exact counts); ledger emptied.';
END $td$;

-- Drop the now-empty ledger table (after the DO block proved it empty).
DROP TABLE IF EXISTS public.d3_fixture_ledger;

-- final single residue result (all zero) + ledger-absent
SELECT 'TD_residue' AS check_name,
       (SELECT count(*) FROM public.cash_commitments WHERE expected_item_id LIKE 'd3fix_r%') AS reservation_rows,       -- 0
       (SELECT count(*) FROM public.transactions WHERE memo LIKE '[STAGING-FIXTURE]%') AS fixture_txns,                  -- 0
       (SELECT count(*) FROM public.discretionary_reservation_batches WHERE batch_digest='cd300001') AS batch,           -- 0
       (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=30 AND note LIKE '[STAGING-FIXTURE]%') AS snapshots,  -- 0
       (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=30 AND chk=3030.30) AS reconciliation,         -- 0
       (SELECT count(*) FROM public.goal_registry WHERE id LIKE 'd3fix_%') AS goals,                                     -- 0
       (CASE WHEN to_regclass('public.d3_fixture_ledger') IS NULL THEN 0 ELSE 1 END) AS ledger_present;                  -- 0
COMMIT;
-- ============================================================================
