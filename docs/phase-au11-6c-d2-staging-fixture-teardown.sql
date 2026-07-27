-- ============================================================================
-- AU-11 Step 6C-D2 — DETERMINISTIC STAGING FIXTURE (teardown + zero-residue proof) — ledger-scoped, ASSERTED
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Executed by Adam. Deletes ONLY rows recorded in public.d2_fixture_ledger — and now ENFORCES
-- the fixture manifest with in-transaction HARD assertions BEFORE any delete, asserts exact deletion row counts,
-- asserts zero residue, drops the ledger, and asserts the drop — all before COMMIT. Any deviation aborts the
-- whole transaction (nothing deleted, ledger intact). The reused real owner (app_users) is never touched.
-- Order respects FKs: goal_funding_snapshots.goal_id -> goal_registry(id) is ON DELETE RESTRICT, so snapshots
-- are deleted before the fixture goals. NO unledgered/attribute-based deletion of reservation artifacts: global
-- D2 residue was already cleaned to 0 at Checkpoint E and is ASSERTED (not re-deleted) here.
-- ============================================================================
BEGIN;

-- ── Guard: staging (hardened) + ledger MUST exist ──
DO $$
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: app_environment missing — cannot certify staging.'; END IF;
  -- Require >=1 environment row AND every row = 'staging' (fails closed on empty or any non-staging row;
  -- also holds for a singleton staging table). Adam independently verifies the project ref is pkwotgqivgaapwuqgwqb.
  IF (SELECT count(*) FROM public.app_environment) < 1
     OR EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging') THEN
    RAISE EXCEPTION 'HARD STOP: app_environment does not certify staging (need >=1 row, every row env=staging).'; END IF;
  -- Ledger existence is REQUIRED (no NOTICE fallback): teardown only runs against an installed fixture.
  IF to_regclass('public.d2_fixture_ledger') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: d2_fixture_ledger absent — no installed fixture to tear down.'; END IF;
END $$;

-- evidence: manifest (display only — the enforcement is the assertion block below)
SELECT 'TD_planned' AS phase, kind, count(*) AS ledgered FROM public.d2_fixture_ledger GROUP BY kind ORDER BY kind;

-- ── PRE-DELETE HARD ASSERTIONS (manifest identity + ledger↔business coherence + zero global residue) ──
DO $$
DECLARE
  v_total INT; v_snap INT; v_goal INT; v_recon INT; v_unknown INT;
  v_dgoal INT; v_dsnap INT; v_badn INT;
  v_recon_ref TEXT; v_bad TEXT; v_res INT; v_bat INT;
BEGIN
  -- (0) ledger integrity — reject NULL identity values and duplicate (kind,ref) pairs FIRST. The fixture
  -- creates d2_fixture_ledger with `kind TEXT NOT NULL, ref TEXT NOT NULL, PRIMARY KEY (kind,ref)`, so NULLs
  -- and duplicate (kind,ref) pairs are impossible for the fixture-created table. These assertions are
  -- defense-in-depth against a pre-existing/foreign table that `CREATE TABLE IF NOT EXISTS` would NOT have
  -- re-constrained, and they close the three-valued-logic gap (a NULL ref evades NOT IN / <> / string_agg).
  IF EXISTS (SELECT 1 FROM public.d2_fixture_ledger WHERE kind IS NULL OR ref IS NULL) THEN
    RAISE EXCEPTION 'HARD STOP: fixture ledger contains NULL kind or ref values.'; END IF;
  IF EXISTS (SELECT 1 FROM public.d2_fixture_ledger GROUP BY kind, ref HAVING count(*) <> 1) THEN
    RAISE EXCEPTION 'HARD STOP: fixture ledger contains duplicate kind/ref entries.'; END IF;

  -- (1) counts by kind + no unknown kinds + total = 19 ; DISTINCT-ref counts prove nine UNIQUE identities per kind
  SELECT count(*) FILTER (WHERE kind='goal_funding_snapshots'),
         count(*) FILTER (WHERE kind='goal_registry'),
         count(*) FILTER (WHERE kind='weekly_reconciliations'),
         count(*) FILTER (WHERE kind NOT IN ('goal_funding_snapshots','goal_registry','weekly_reconciliations')),
         count(*),
         count(DISTINCT ref) FILTER (WHERE kind='goal_registry'),
         count(DISTINCT ref) FILTER (WHERE kind='goal_funding_snapshots')
    INTO v_snap, v_goal, v_recon, v_unknown, v_total, v_dgoal, v_dsnap
    FROM public.d2_fixture_ledger;
  IF v_unknown <> 0 THEN RAISE EXCEPTION 'HARD STOP: ledger contains % unknown kind value(s).', v_unknown; END IF;
  IF v_snap <> 9 OR v_goal <> 9 OR v_recon <> 1 OR v_total <> 19 THEN
    RAISE EXCEPTION 'HARD STOP: ledger manifest mismatch (snapshots=%, goals=%, recon=%, total=%; expected 9/9/1/19).',
      v_snap, v_goal, v_recon, v_total; END IF;
  IF v_dgoal <> 9 OR v_dsnap <> 9 THEN
    RAISE EXCEPTION 'HARD STOP: ledger refs not nine-unique per kind (distinct goals=%, distinct snapshots=%; expected 9/9).',
      v_dgoal, v_dsnap; END IF;

  -- (2a) the sole reconciliation ledger ref is exactly '31'
  SELECT ref INTO v_recon_ref FROM public.d2_fixture_ledger WHERE kind='weekly_reconciliations';
  IF v_recon_ref IS DISTINCT FROM '31' THEN RAISE EXCEPTION 'HARD STOP: reconciliation ledger ref is % (expected 31).', COALESCE(v_recon_ref,'<null>'); END IF;

  -- (2b) the week-31 reconciliation row is the fixture sentinel
  IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=31 AND chk=3131.31) THEN
    RAISE EXCEPTION 'HARD STOP: week 31 reconciliation is not the fixture sentinel (week_num=31 AND chk=3131.31).'; END IF;

  -- (2c) all nine goal refs are the exact known D2 fixture goal IDs (count-based; refs are non-null per (0))
  SELECT count(*), string_agg(ref, ', ') INTO v_badn, v_bad FROM public.d2_fixture_ledger
   WHERE kind='goal_registry'
     AND ref NOT IN ('d2fix_g01','d2fix_g02','d2fix_g03','d2fix_g04','d2fix_g05','d2fix_g06','d2fix_g07','d2fix_g08','d2fix_g09');
  IF v_badn <> 0 THEN RAISE EXCEPTION 'HARD STOP: % unexpected goal ledger ref(s): %.', v_badn, COALESCE(v_bad,'<none-captured>'); END IF;

  -- (2d) all nine snapshot refs are exactly 2026:31:<the nine fixture goal ids> (count-based)
  SELECT count(*), string_agg(ref, ', ') INTO v_badn, v_bad FROM public.d2_fixture_ledger
   WHERE kind='goal_funding_snapshots'
     AND ref NOT IN ('2026:31:d2fix_g01','2026:31:d2fix_g02','2026:31:d2fix_g03','2026:31:d2fix_g04','2026:31:d2fix_g05',
                     '2026:31:d2fix_g06','2026:31:d2fix_g07','2026:31:d2fix_g08','2026:31:d2fix_g09');
  IF v_badn <> 0 THEN RAISE EXCEPTION 'HARD STOP: % unexpected snapshot ledger ref(s): %.', v_badn, COALESCE(v_bad,'<none-captured>'); END IF;

  -- (2e) every ledger reference resolves to an existing business row
  SELECT string_agg(l.ref, ', ') INTO v_bad FROM public.d2_fixture_ledger l
   WHERE l.kind='goal_registry' AND NOT EXISTS (SELECT 1 FROM public.goal_registry g WHERE g.id=l.ref);
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'HARD STOP: goal ledger ref(s) with no business row: %.', v_bad; END IF;
  SELECT string_agg(l.ref, ', ') INTO v_bad FROM public.d2_fixture_ledger l
   WHERE l.kind='goal_funding_snapshots'
     AND NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots s
                       WHERE s.model_year=2026 AND s.week_num=31 AND ('2026:31:'||s.goal_id)=l.ref);
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'HARD STOP: snapshot ledger ref(s) with no business row: %.', v_bad; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=31) THEN
    RAISE EXCEPTION 'HARD STOP: reconciliation ledger ref 31 has no business row.'; END IF;

  -- (2f) snapshot goal-id set == ledgered goal-id set (coherent nine-goal set)
  IF EXISTS (
       SELECT regexp_replace(ref,'^2026:31:','') FROM public.d2_fixture_ledger WHERE kind='goal_funding_snapshots'
       EXCEPT
       SELECT ref FROM public.d2_fixture_ledger WHERE kind='goal_registry')
     OR EXISTS (
       SELECT ref FROM public.d2_fixture_ledger WHERE kind='goal_registry'
       EXCEPT
       SELECT regexp_replace(ref,'^2026:31:','') FROM public.d2_fixture_ledger WHERE kind='goal_funding_snapshots') THEN
    RAISE EXCEPTION 'HARD STOP: snapshot goal-id set does not match ledgered goal-id set.'; END IF;

  -- (4) global D2 residue must ALREADY be zero (Checkpoint E cleaned it). ASSERT — do NOT delete by attributes.
  SELECT count(*) INTO v_res FROM public.cash_commitments WHERE commitment_source='au11_reservation';
  SELECT count(*) INTO v_bat FROM public.discretionary_reservation_batches;
  IF v_res <> 0 OR v_bat <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: pre-teardown D2 residue not zero (au11_reservations=%, batches=%) — investigate; teardown does not delete non-ledgered reservation artifacts.', v_res, v_bat; END IF;
END $$;

-- ── DELETES (ledger-scoped, FK order) with exact ROW_COUNT assertions, then residue + ledger-drop assertions ──
DO $$
DECLARE v_n INT;
BEGIN
  -- 1) fixture snapshots (before goals — ON DELETE RESTRICT); expect exactly 9
  DELETE FROM public.goal_funding_snapshots s
    WHERE s.model_year=2026 AND s.week_num=31
      AND EXISTS (SELECT 1 FROM public.d2_fixture_ledger l WHERE l.kind='goal_funding_snapshots' AND l.ref='2026:31:'||s.goal_id);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 9 THEN RAISE EXCEPTION 'HARD STOP: deleted % fixture snapshots (expected 9).', v_n; END IF;

  -- 2) fixture reconciliation; expect exactly 1
  DELETE FROM public.weekly_reconciliations w
    WHERE EXISTS (SELECT 1 FROM public.d2_fixture_ledger l WHERE l.kind='weekly_reconciliations' AND l.ref=w.week_num::text);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'HARD STOP: deleted % fixture reconciliations (expected 1).', v_n; END IF;

  -- 3) fixture goals; expect exactly 9
  DELETE FROM public.goal_registry g
    WHERE EXISTS (SELECT 1 FROM public.d2_fixture_ledger l WHERE l.kind='goal_registry' AND l.ref=g.id);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 9 THEN RAISE EXCEPTION 'HARD STOP: deleted % fixture goals (expected 9).', v_n; END IF;

  -- (6) assert zero fixture residue INSIDE the transaction, before dropping the ledger
  IF (SELECT count(*) FROM public.goal_registry WHERE id LIKE 'd2fix_%') <> 0
     OR (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=31 AND goal_id LIKE 'd2fix_%') <> 0
     OR (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num=31 AND chk=3131.31) <> 0
     OR (SELECT count(*) FROM public.cash_commitments WHERE commitment_source='au11_reservation') <> 0
     OR (SELECT count(*) FROM public.discretionary_reservation_batches) <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: fixture residue remains after deletes — refusing to drop the ledger.'; END IF;
END $$;

-- drop the ledger (NO IF EXISTS — existence was required at the guard)
DROP TABLE public.d2_fixture_ledger;

-- (6) assert the ledger is gone BEFORE commit
DO $$ BEGIN
  IF to_regclass('public.d2_fixture_ledger') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: d2_fixture_ledger still present after DROP.'; END IF;
END $$;

COMMIT;

-- ── post-commit persisted-state evidence (six-row; corroborates, not the sole failure detector) ──
-- NOTE: alias is `check_name`, not `check` — `check` is a reserved keyword and `ORDER BY check` throws 42601.
SELECT *
FROM (
  SELECT
    'RES_goals' AS check_name,
    count(*)::bigint AS n
  FROM public.goal_registry
  WHERE id LIKE 'd2fix_%'

  UNION ALL

  SELECT
    'RES_snapshots',
    count(*)::bigint
  FROM public.goal_funding_snapshots
  WHERE model_year = 2026
    AND week_num = 31
    AND goal_id LIKE 'd2fix_%'

  UNION ALL

  SELECT
    'RES_recon_wk31',
    count(*)::bigint
  FROM public.weekly_reconciliations
  WHERE week_num = 31
    AND chk = 3131.31

  UNION ALL

  SELECT
    'RES_reservations',
    count(*)::bigint
  FROM public.cash_commitments
  WHERE commitment_source = 'au11_reservation'

  UNION ALL

  SELECT
    'RES_batches',
    count(*)::bigint
  FROM public.discretionary_reservation_batches

  UNION ALL

  SELECT
    'RES_ledger',
    CASE
      WHEN to_regclass('public.d2_fixture_ledger') IS NULL THEN 0
      ELSE 1
    END::bigint
) AS residue
ORDER BY check_name;
-- All six n must be 0. The fixture never creates an app_users/auth row (it reuses an existing owner), so there is
-- no owner residue; the reused real owner is never touched. All destructive steps are gated by in-transaction
-- assertions above, so a stale/partial/foreign ledger aborts the whole transaction with nothing deleted.
