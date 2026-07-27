-- ============================================================================
-- AU-11 Step 6C-D2 — STAGING-ONLY reservation lifecycle RPCs (create / initiate / void-scheduled)
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Authored by Claude; to be EXECUTED BY ADAM in the Supabase SQL Editor
-- against staging pkwotgqivgaapwuqgwqb (<> prod usayoldrawwmjsmretin). Claude ran no SQL.
-- Depends on the D1 schema (applied + validated on staging) AND on the additive
-- goal_registry.reservable column (phase-au11-6c-d2-goal-registry-reservable.sql — run FIRST).
-- Installs three owner-only SECURITY DEFINER RPCs:
--   1) create_discretionary_goal_reservation_v1
--   2) mark_discretionary_goal_reservation_initiated_v1
--   3) void_scheduled_discretionary_goal_reservation_v1   (scheduled-only; NO cancel of initiated — R7)
--
-- HARDENING (11/10 pass):
--   • SECURITY DEFINER + SET search_path = '' (empty). pg_catalog is always implicitly searched FIRST,
--     so built-ins resolve; pg_temp is NOT in the path, so caller-created temp objects cannot shadow.
--     Every application object is schema-qualified: public.<table>, public.is_owner(), auth.uid(),
--     pg_catalog.pg_advisory_xact_lock / pg_catalog.hashtextextended. No unqualified public reference
--     exists, so there is no object-shadowing path through caller-created objects.
--   • Deterministic input validation: allowed JSON keys only; digit-only amounts in [1..100000000];
--     BIGINT total (no overflow); empty/NULL/malformed goal-id arrays fail closed; NULL/ineligible
--     status fails closed. batch_digest canonical form is exactly 8 lowercase hex (uppercase rejected,
--     no normalization). source_account is an exact, case-sensitive match. Replay is set-based and
--     row-order independent.
--
-- Ownership: created by the SQL-Editor admin role (postgres); SECURITY DEFINER therefore runs as that
-- controlled role, NOT anon/authenticated/an app user. Verified in phase-au11-6c-d2-staging-catalog-verify.sql.
-- Grant posture: EXECUTE to authenticated, but every body asserts is_owner() (owner-only); PUBLIC/anon revoked.
-- Direct cash_commitments / discretionary_reservation_batches writes remain RPC-only (D1 RLS).
--
-- R7: once 'initiated', a reservation stays withholding and is resolved ONLY by the D3 composite closeout
--     (cleared Register evidence). D2 has NO release-of-initiated path.
-- R8: reservation eligibility is driven by centralized Goal Registry metadata (status + reservable + dest).
-- ============================================================================
BEGIN;

-- ── staging + dependency guard ──
DO $$
BEGIN
  IF to_regclass('public.app_environment') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') THEN
    RAISE EXCEPTION 'HARD STOP: not staging — refusing to install AU-11 D2 RPCs.';
  END IF;
  IF to_regclass('public.discretionary_reservation_batches') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: D1 schema (discretionary_reservation_batches) missing. Apply D1 first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable') THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry.reservable missing. Apply phase-au11-6c-d2-goal-registry-reservable.sql first.';
  END IF;
END $$;

-- ============================================================================
-- 1) create_discretionary_goal_reservation_v1
--    Owner-only. Advisory-locked single-flight. Idempotent replay (before basis check).
--    Deterministic shape validation. Registry eligibility (new batch). Conservation. All-or-nothing.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_discretionary_goal_reservation_v1(
  p_model_year         INT,
  p_basis_model_week   INT,
  p_batch_digest       TEXT,
  p_source_account     TEXT,
  p_expected_clear_date DATE,
  p_rows               JSONB,               -- [{goal_id, amount_cents, destination_account_ref?}]
  p_expected_total_cents INT DEFAULT NULL   -- optional conservation checksum
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE
  v_uid        UUID := auth.uid();
  v_row        JSONB;
  v_goal       TEXT;
  v_amt        INT;
  v_amt_num    NUMERIC;
  v_dest_req   TEXT;
  v_dest_reg   TEXT;
  v_gstatus    TEXT;
  v_reservable BOOLEAN;
  v_total      BIGINT := 0;
  v_batch_id   UUID;
  v_eid        TEXT;
  v_existing   RECORD;
  v_seen       TEXT[] := ARRAY[]::TEXT[];
  v_out        JSONB := '[]'::jsonb;
BEGIN
  IF NOT public.is_owner() THEN RAISE EXCEPTION 'not authorized: owner only' USING ERRCODE='42501'; END IF;
  IF p_model_year IS DISTINCT FROM 2026 THEN RAISE EXCEPTION 'invalid model_year %', p_model_year; END IF;
  IF p_source_account IS DISTINCT FROM 'truist_checking' THEN RAISE EXCEPTION 'invalid source_account % (exact, case-sensitive)', p_source_account; END IF;
  IF p_basis_model_week IS NULL OR p_basis_model_week < 1 OR p_basis_model_week > 31 THEN RAISE EXCEPTION 'invalid basis_model_week %', p_basis_model_week; END IF;
  IF p_batch_digest IS NULL OR p_batch_digest !~ '^[0-9a-f]{8}$' THEN RAISE EXCEPTION 'invalid batch_digest (want exactly 8 lowercase hex; no normalization applied): %', p_batch_digest; END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN RAISE EXCEPTION 'p_rows must be a non-empty JSON array'; END IF;
  IF jsonb_array_length(p_rows) > 20 THEN RAISE EXCEPTION 'p_rows exceeds max batch size (20)'; END IF;

  -- single-flight: serialize create/initiate/void (and, later, the D3 composite) on (model_year, source_account)
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('au11_disc:'||p_model_year||':'||p_source_account, 0));

  -- ── deterministic per-row SHAPE validation (runs for BOTH replay and new-batch paths so a malformed
  --    request fails closed identically either way): allowed keys only, goal_id present + unique,
  --    digit-only amount in [1..100000000], BIGINT total (cannot overflow). ──
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) AS t(value) LOOP
    IF jsonb_typeof(v_row) <> 'object' THEN RAISE EXCEPTION 'each row must be a JSON object; got %', jsonb_typeof(v_row); END IF;
    IF EXISTS (SELECT 1 FROM jsonb_object_keys(v_row) AS k(key)
                 WHERE k.key NOT IN ('goal_id','amount_cents','destination_account_ref')) THEN
      RAISE EXCEPTION 'row has an unexpected key (allowed: goal_id, amount_cents, destination_account_ref): %', v_row; END IF;
    v_goal := v_row->>'goal_id';
    IF v_goal IS NULL OR btrim(v_goal) = '' THEN RAISE EXCEPTION 'row missing goal_id'; END IF;
    IF v_goal = ANY(v_seen) THEN RAISE EXCEPTION 'duplicate goal_id in batch: %', v_goal; END IF;
    v_seen := v_seen || v_goal;
    IF (v_row->>'amount_cents') IS NULL OR (v_row->>'amount_cents') !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'goal % amount_cents must be a positive integer (digits only)', v_goal; END IF;
    v_amt_num := (v_row->>'amount_cents')::numeric;   -- numeric parse cannot overflow on long input
    IF v_amt_num < 1 OR v_amt_num > 100000000 THEN
      RAISE EXCEPTION 'goal % amount_cents out of range (1..100000000): %', v_goal, v_amt_num; END IF;
    v_total := v_total + v_amt_num::bigint;
  END LOOP;
  IF p_expected_total_cents IS NOT NULL AND p_expected_total_cents::bigint <> v_total THEN
    RAISE EXCEPTION 'conservation checksum mismatch: expected %, computed %', p_expected_total_cents, v_total;
  END IF;

  -- ── idempotent replay / conflict on (model_year, batch_digest) — evaluated BEFORE the basis-latest
  -- precondition (F4). Compares the request ONLY against NON-TERMINAL rows (F1) and includes
  -- destination_account_ref (F5). Set-based ⇒ row-order independent. Eligibility is NOT re-checked here
  -- (an existing obligation replays as a precise no-op regardless of later registry drift). ──
  SELECT * INTO v_existing FROM public.discretionary_reservation_batches
    WHERE model_year = p_model_year AND batch_digest = p_batch_digest;
  IF FOUND THEN
    IF v_existing.status <> 'active' THEN
      RAISE EXCEPTION 'batch % is % (terminal) — cannot recreate', p_batch_digest, v_existing.status;
    END IF;
    FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) AS t(value) LOOP
      v_goal := v_row->>'goal_id'; v_amt := (v_row->>'amount_cents')::int;
      SELECT dest INTO v_dest_reg FROM public.goal_registry WHERE id = v_goal;
      -- F-B: a replay request that carries a destination_account_ref must agree with the registry (parity
      -- with the new-batch path), else it is a conflict — never a silent idempotent no-op.
      v_dest_req := v_row->>'destination_account_ref';
      IF v_dest_req IS NOT NULL AND v_dest_req <> COALESCE(v_dest_reg,'') THEN
        RAISE EXCEPTION 'conflicting replay for batch % goal % (client destination_account_ref=% <> registry=%)', p_batch_digest, v_goal, v_dest_req, v_dest_reg;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.cash_commitments
                       WHERE reservation_batch_id = v_existing.id AND goal_id = v_goal
                         AND amount_cents = v_amt
                         AND destination_account_ref IS NOT DISTINCT FROM v_dest_reg
                         AND status IN ('scheduled','initiated','bank_pending','stale_review')) THEN
        RAISE EXCEPTION 'conflicting replay for batch % goal % (no matching ACTIVE reservation — amount/destination/status mismatch, or goal was disposed)', p_batch_digest, v_goal;
      END IF;
    END LOOP;
    IF (SELECT count(*) FROM public.cash_commitments
          WHERE reservation_batch_id = v_existing.id
            AND status IN ('scheduled','initiated','bank_pending','stale_review')) <> jsonb_array_length(p_rows) THEN
      RAISE EXCEPTION 'conflicting replay for batch % (active-row-count mismatch vs request)', p_batch_digest;
    END IF;
    RETURN jsonb_build_object('ok',true,'idempotent',true,'batch_id',v_existing.id,'batch_digest',p_batch_digest,'status','active');
  END IF;

  -- ── NEW batch below: reconciled-basis precondition (latest fully-closed reconciliation:
  -- reconciled AND >=9 goal snapshots), matching closeoutState 'complete'. ──
  IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num = p_basis_model_week) THEN
    RAISE EXCEPTION 'basis week % is not reconciled', p_basis_model_week;
  END IF;
  IF (SELECT count(*) FROM public.goal_funding_snapshots
        WHERE model_year = p_model_year AND week_num = p_basis_model_week) < 9 THEN
    RAISE EXCEPTION 'basis week % is not fully closed (<9 goal snapshots)', p_basis_model_week;
  END IF;
  IF p_basis_model_week <> (SELECT max(week_num) FROM public.weekly_reconciliations) THEN
    RAISE EXCEPTION 'basis week % is not the latest reconciled week (%).',
      p_basis_model_week, (SELECT max(week_num) FROM public.weekly_reconciliations);
  END IF;

  -- ── single-active-batch (explicit, ahead of the partial-unique-index backstop) ──
  IF EXISTS (SELECT 1 FROM public.discretionary_reservation_batches
               WHERE model_year = p_model_year AND source_account = p_source_account
                 AND status = 'active' AND batch_digest <> p_batch_digest) THEN
    RAISE EXCEPTION 'an active discretionary batch already exists for %/% — void or retire it first', p_model_year, p_source_account;
  END IF;

  -- ── centralized Goal Registry eligibility predicate (R8/F6) — registry metadata only, NOT an embedded
  --    list, NOT inferred from ambiguous fields (auto/stretch). Runs on the NEW-batch path. ──
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) AS t(value) LOOP
    v_goal := v_row->>'goal_id';
    SELECT status, COALESCE(reservable,false), dest
      INTO v_gstatus, v_reservable, v_dest_reg
      FROM public.goal_registry WHERE id = v_goal;
    IF NOT FOUND THEN RAISE EXCEPTION 'unknown goal_id % (not in goal_registry)', v_goal; END IF;
    IF v_gstatus IS NULL OR v_gstatus NOT IN ('planned','funding') THEN
      RAISE EXCEPTION 'goal % is not in an eligible state (status=%, require planned|funding)', v_goal, COALESCE(v_gstatus,'<null>'); END IF;
    IF NOT v_reservable THEN
      RAISE EXCEPTION 'goal % is not reservable (goal_registry.reservable is not true)', v_goal; END IF;
    IF v_dest_reg IS NULL OR btrim(v_dest_reg) = '' THEN
      RAISE EXCEPTION 'goal % has no valid destination account (goal_registry.dest is empty)', v_goal; END IF;
    -- optional stale-client cross-check: if a client supplied destination_account_ref it MUST match registry
    v_dest_req := v_row->>'destination_account_ref';
    IF v_dest_req IS NOT NULL AND v_dest_req <> v_dest_reg THEN
      RAISE EXCEPTION 'goal % destination_account_ref mismatch (client=%, registry=%)', v_goal, v_dest_req, v_dest_reg;
    END IF;
  END LOOP;

  -- ── insert the batch (uix_one_active_batch is the DB backstop for single-active-batch) ──
  INSERT INTO public.discretionary_reservation_batches
    (batch_digest, model_year, source_account, basis_model_week, status, created_by)
  VALUES (p_batch_digest, p_model_year, p_source_account, p_basis_model_week, 'active', v_uid)
  RETURNING id INTO v_batch_id;

  -- ── insert one reservation row per goal ──
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) AS t(value) LOOP
    v_goal := v_row->>'goal_id'; v_amt := (v_row->>'amount_cents')::int;
    SELECT dest INTO v_dest_reg FROM public.goal_registry WHERE id = v_goal;
    v_eid := 'disc-goal:v1:'||p_model_year||':w'||p_basis_model_week||':'||p_batch_digest||':'||v_goal;
    INSERT INTO public.cash_commitments
      (expected_item_id, model_year, commitment_source, origin_model_week, payee,
       commitment_class, required_or_discretionary, source_account, amount_cents, status,
       affects_deployable_cash, expected_clear_date,
       reservation_batch_id, goal_id, destination_account_ref, created_by)
    VALUES
      (v_eid, p_model_year, 'au11_reservation', p_basis_model_week,
       COALESCE((SELECT name FROM public.goal_registry WHERE id=v_goal), v_goal),
       'discretionary_goal_transfer', 'discretionary_deployment', p_source_account, v_amt, 'scheduled',
       true, p_expected_clear_date,
       v_batch_id, v_goal, v_dest_reg, v_uid);
    v_out := v_out || jsonb_build_object('goal_id',v_goal,'amount_cents',v_amt,'destination_account_ref',v_dest_reg,'expected_item_id',v_eid,'status','scheduled');
  END LOOP;

  RETURN jsonb_build_object('ok',true,'batch_id',v_batch_id,'batch_digest',p_batch_digest,'status','active',
                            'total_cents',v_total,'rows',v_out);
END;
$fn$;

-- ============================================================================
-- 2) mark_discretionary_goal_reservation_initiated_v1  (scheduled -> initiated)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.mark_discretionary_goal_reservation_initiated_v1(
  p_model_year          INT,
  p_batch_digest        TEXT,
  p_goal_ids            TEXT[],            -- NULL => all scheduled rows; non-empty array => those goals; empty array => ERROR
  p_bank_reference      TEXT,
  p_bank_submitted_at   TIMESTAMPTZ,
  p_expected_clear_date DATE DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE
  v_batch RECORD;
  v_updated INT := 0;
  v_bad     TEXT;
BEGIN
  IF NOT public.is_owner() THEN RAISE EXCEPTION 'not authorized: owner only' USING ERRCODE='42501'; END IF;
  IF p_bank_reference IS NULL OR btrim(p_bank_reference) = '' THEN RAISE EXCEPTION 'bank_reference required to mark initiated'; END IF;
  IF p_bank_submitted_at IS NULL THEN RAISE EXCEPTION 'bank_submitted_at required'; END IF;
  -- goal-id array hygiene: NULL => all; empty array or any null/blank element => fail closed.
  -- Duplicates are normalized (set membership via = ANY has no additional effect).
  IF p_goal_ids IS NOT NULL THEN
    IF array_length(p_goal_ids,1) IS NULL THEN RAISE EXCEPTION 'p_goal_ids may be NULL (=all) or a non-empty array, not an empty array'; END IF;
    IF EXISTS (SELECT 1 FROM unnest(p_goal_ids) AS g(id) WHERE g.id IS NULL OR btrim(g.id)='') THEN
      RAISE EXCEPTION 'p_goal_ids contains a null/blank goal id'; END IF;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('au11_disc:'||p_model_year||':truist_checking', 0));

  SELECT * INTO v_batch FROM public.discretionary_reservation_batches
    WHERE model_year = p_model_year AND batch_digest = p_batch_digest;
  IF NOT FOUND THEN RAISE EXCEPTION 'batch % not found', p_batch_digest; END IF;
  IF v_batch.status <> 'active' THEN RAISE EXCEPTION 'batch % is % (not active)', p_batch_digest, v_batch.status; END IF;
  -- F-F: the advisory-lock key above hardcodes truist_checking; guard that the batch matches so a future
  -- second source can never serialize on the wrong key (create() locks on the batch's own source_account).
  IF v_batch.source_account <> 'truist_checking' THEN RAISE EXCEPTION 'unexpected source_account % (lock-key guard)', v_batch.source_account; END IF;

  -- F-C (fail-closed for explicit lists): EVERY named goal must currently be a 'scheduled' row in this batch.
  -- This makes an explicit-goal call all-or-nothing: an overlapping/mixed/already-initiated/absent goal aborts
  -- the WHOLE call (nothing transitioned) rather than silently partially succeeding. The NULL form keeps its
  -- documented "advance all schedulable rows" semantics.
  IF p_goal_ids IS NOT NULL THEN
    SELECT string_agg(g.id, ', ') INTO v_bad
      FROM (SELECT DISTINCT unnest(p_goal_ids) AS id) g
     WHERE NOT EXISTS (SELECT 1 FROM public.cash_commitments c
                         WHERE c.reservation_batch_id = v_batch.id
                           AND c.commitment_class = 'discretionary_goal_transfer'
                           AND c.status = 'scheduled'
                           AND c.goal_id = g.id);
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'goal(s) not scheduled in batch % (already initiated/voided, or not in batch): %', p_batch_digest, v_bad;
    END IF;
  END IF;

  UPDATE public.cash_commitments
     SET status = 'initiated',
         bank_reference = p_bank_reference,
         bank_submitted_at = p_bank_submitted_at,
         expected_clear_date = COALESCE(p_expected_clear_date, expected_clear_date),
         updated_at = NOW(), updated_by = auth.uid()
   WHERE reservation_batch_id = v_batch.id
     AND commitment_class = 'discretionary_goal_transfer'
     AND status = 'scheduled'
     AND (p_goal_ids IS NULL OR goal_id = ANY(p_goal_ids));
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  -- F7: bank_reference is write-once at the scheduled->initiated transition; replays never overwrite it.
  -- With the F-C precheck, explicit-goal calls always transition (>0) or already RAISEd; the v_updated=0
  -- path is reachable only for the NULL (all) form when there are no schedulable rows left.
  IF v_updated = 0 THEN
    IF p_goal_ids IS NOT NULL THEN
      RAISE EXCEPTION 'no scheduled rows for the named goals in batch % (already initiated/voided, or not in batch)', p_batch_digest;
    END IF;
    IF EXISTS (SELECT 1 FROM public.cash_commitments
                 WHERE reservation_batch_id = v_batch.id
                   AND commitment_class = 'discretionary_goal_transfer'
                   AND status IN ('initiated','bank_pending','stale_review')) THEN
      RETURN jsonb_build_object('ok',true,'batch_digest',p_batch_digest,'transitioned',0,'idempotent',true);
    END IF;
    RAISE EXCEPTION 'batch % has no scheduled rows to initiate', p_batch_digest;
  END IF;
  RETURN jsonb_build_object('ok',true,'batch_digest',p_batch_digest,'transitioned',v_updated);
END;
$fn$;

-- ============================================================================
-- 3) void_scheduled_discretionary_goal_reservation_v1  (scheduled -> voided ONLY)
-- ----------------------------------------------------------------------------
-- R7/F2 (owner ruling: option (b)): D2 has NO path that cancels or releases an INITIATED reservation.
-- Once a reservation reaches 'initiated'/'bank_pending'/'stale_review' it MUST remain withholding and can
-- be resolved ONLY through the D3 composite closeout (cleared Register evidence + posted-date controls).
-- D2's only "undo" is voiding a reservation that is still 'scheduled'. If ANY targeted row is non-scheduled
-- non-terminal, the WHOLE call is rejected atomically (no scheduled row is voided in that mixed-state case).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.void_scheduled_discretionary_goal_reservation_v1(
  p_model_year     INT,
  p_batch_digest   TEXT,
  p_goal_ids       TEXT[],                 -- NULL => all scheduled rows; non-empty => those goals; empty => ERROR
  p_reason         TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE
  v_batch RECORD;
  v_blocked TEXT;
  v_voided INT := 0;
  v_remaining_active INT;
BEGIN
  IF NOT public.is_owner() THEN RAISE EXCEPTION 'not authorized: owner only' USING ERRCODE='42501'; END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'reason required'; END IF;
  IF p_goal_ids IS NOT NULL THEN
    IF array_length(p_goal_ids,1) IS NULL THEN RAISE EXCEPTION 'p_goal_ids may be NULL (=all scheduled) or a non-empty array, not an empty array'; END IF;
    IF EXISTS (SELECT 1 FROM unnest(p_goal_ids) AS g(id) WHERE g.id IS NULL OR btrim(g.id)='') THEN
      RAISE EXCEPTION 'p_goal_ids contains a null/blank goal id'; END IF;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('au11_disc:'||p_model_year||':truist_checking', 0));

  SELECT * INTO v_batch FROM public.discretionary_reservation_batches
    WHERE model_year = p_model_year AND batch_digest = p_batch_digest;
  IF NOT FOUND THEN RAISE EXCEPTION 'batch % not found', p_batch_digest; END IF;
  IF v_batch.status <> 'active' THEN RAISE EXCEPTION 'batch % is % (not active)', p_batch_digest, v_batch.status; END IF;
  IF v_batch.source_account <> 'truist_checking' THEN RAISE EXCEPTION 'unexpected source_account % (lock-key guard)', v_batch.source_account; END IF;  -- F-F

  -- HARD BLOCK (R7), evaluated BEFORE any UPDATE ⇒ mixed-state calls fail atomically with nothing voided:
  -- if ANY targeted row has advanced past 'scheduled' (initiated/bank_pending/stale_review), refuse the call.
  SELECT string_agg(goal_id||' ('||status||')', ', ') INTO v_blocked
    FROM public.cash_commitments
   WHERE reservation_batch_id = v_batch.id
     AND commitment_class = 'discretionary_goal_transfer'
     AND status IN ('initiated','bank_pending','stale_review')
     AND (p_goal_ids IS NULL OR goal_id = ANY(p_goal_ids));
  IF v_blocked IS NOT NULL THEN
    RAISE EXCEPTION 'cannot void initiated reservation(s) in batch % [%] — D2 does not cancel or release initiated transfers; they resolve only through the D3 composite closeout (cleared Register evidence)', p_batch_digest, v_blocked;
  END IF;

  UPDATE public.cash_commitments
     SET status = 'voided', resolution_type = 'voided',
         resolved_model_week = v_batch.basis_model_week,
         resolution_notes = p_reason,
         resolved_at = NOW(), resolved_by = auth.uid(), updated_at = NOW(), updated_by = auth.uid()
   WHERE reservation_batch_id = v_batch.id
     AND commitment_class = 'discretionary_goal_transfer'
     AND status = 'scheduled'
     AND (p_goal_ids IS NULL OR goal_id = ANY(p_goal_ids));
  GET DIAGNOSTICS v_voided = ROW_COUNT;

  IF v_voided = 0 THEN
    RAISE EXCEPTION 'no scheduled rows to void in batch % (targets: %)', p_batch_digest, p_goal_ids;
  END IF;

  -- if no non-terminal reservation rows remain, retire the batch as voided
  SELECT count(*) INTO v_remaining_active FROM public.cash_commitments
    WHERE reservation_batch_id = v_batch.id
      AND status IN ('scheduled','initiated','bank_pending','stale_review');
  IF v_remaining_active = 0 THEN
    UPDATE public.discretionary_reservation_batches
       SET status='voided', resolution_type='voided', resolved_at=NOW(), resolved_by=auth.uid(),
           resolution_notes=p_reason, updated_at=NOW()
     WHERE id = v_batch.id;
  END IF;

  RETURN jsonb_build_object('ok',true,'batch_digest',p_batch_digest,'voided',v_voided,
                            'batch_status',(SELECT status FROM public.discretionary_reservation_batches WHERE id=v_batch.id));
END;
$fn$;

-- ── grants: EXECUTE to authenticated (in-body is_owner() is the real gate); revoke PUBLIC/anon ──
REVOKE ALL ON FUNCTION public.create_discretionary_goal_reservation_v1(INT,INT,TEXT,TEXT,DATE,JSONB,INT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_discretionary_goal_reservation_initiated_v1(INT,TEXT,TEXT[],TEXT,TIMESTAMPTZ,DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.void_scheduled_discretionary_goal_reservation_v1(INT,TEXT,TEXT[],TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_discretionary_goal_reservation_v1(INT,INT,TEXT,TEXT,DATE,JSONB,INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_discretionary_goal_reservation_initiated_v1(INT,TEXT,TEXT[],TEXT,TIMESTAMPTZ,DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.void_scheduled_discretionary_goal_reservation_v1(INT,TEXT,TEXT[],TEXT) TO authenticated;

COMMIT;
-- After COMMIT: reload the PostgREST schema cache. Then run phase-au11-6c-d2-staging-catalog-verify.sql
-- (checkpoint B), then the fixture, then validation.
