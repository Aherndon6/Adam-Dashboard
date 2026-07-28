-- ============================================================================
-- AU-11 Step 6C-D3 — STAGING COMPOSITE RPC  close_week_with_reservations_v1  [7D-B DRAFT]
-- ----------------------------------------------------------------------------
-- STAGING ONLY. NOT executed by Claude. Adam executes. Apply ONLY after the D-9 schema (A-G) passes.
-- Implements the single canonical execution order (design addendum §I, steps 1-19) EXACTLY, incl. the
-- FROZEN sequencing requirement: wrapper is invoked ONCE and its result CAPTURED + VERIFIED BEFORE ANY
-- cash_commitments attribution/lifecycle/resolution or batch-state update occurs.
--
-- CORRECTED SEQUENCE (conformance to frozen §I, not a design change):
--   Loop 1 (pre-wrapper, NO mutation): resolve candidate set → validate nomination → collect selected txn
--     ids → acquire FOR UPDATE row locks → recheck predicate on locked rows → build in-memory attribution
--     plan (v_plan). Evidence row locks are HELD across the wrapper call within the same transaction.
--   Wrapper: called EXACTLY ONCE per composite invocation; result captured (v_wrapper) and verified.
--   Loop 2 (post-wrapper, mutation): apply attribution UPDATEs from the validated/locked plan only.
--   Then: omitted_cleared_row → batch retirement → S3(b) invariants → return.
--
-- Preserves: can_write_financials() (D-1) · truist_checking (D-2) · 2026-only (D-10) · internal week
--   derivation (D-6) · exact-one-debit + canonical amount rule (D-4/§S5) · §S1 nomination · pass-through
--   arrays first closeout / empty on replay (D-7) · GFA01 propagation · FOR UPDATE before locked recheck
--   (§S3a) · targeted 23505→transaction_already_attributed only for uix_au11_cleared_txn · anomaly
--   hard-fail (D-5) · S3(b) post-attribution invariant (D-11 detect).
--
-- OUTCOME TAXONOMY (precision #5): not_authorized(42501) · unsupported_model_year · unsupported_mode ·
--   week_window_mismatch · duplicate_commitment_entry · duplicate_transaction_nomination · unknown_commitment
--   · commitment_not_in_active_batch · commitment_not_retirable(status∉{initiated,bank_pending}) ·
--   anomalous_lifecycle_state(planned/carried_unresolved) · evidence_missing
--   · nominated_transaction_not_eligible · ambiguous_multiple_match(also the partial/aggregate BLOCK, by
--   construction: only an exact-one debit qualifies) · omitted_cleared_row · evidence_changed ·
--   transaction_already_attributed(23505 on uix only) · retirement_count_mismatch · inconsistent_batch_state
--   · wrapper_contract_fail · GFA01(propagated).
-- REPLAY STATES (precision #4): A active+unclaimed→plan+attribute · B same commit+same txn→idempotent no-op
--   · C same commit+different txn→transaction_already_attributed · D different commit+same txn→
--   duplicate_transaction_nomination (pre-wrapper) / transaction_already_attributed (index) · E attributed
--   evidence changed→S3(b) · F cleared commit missing attribution→inconsistent_batch_state · G non-cleared
--   carrying attribution→anomaly (caught by S3(b)/CHECK).
-- ============================================================================
-- SELF-CONTAINED STAGING APPLY: BEGIN … pre-guard … CREATE (verbatim RPC below) … REVOKEs … post-assert … COMMIT.
-- The CREATE FUNCTION body is the durable composite RPC (unchanged); the guards are staging-apply scaffolding.
-- ============================================================================
BEGIN;

-- ── PRE-GUARD (staging + ownership + D-9 prerequisite + frozen wrapper by EXACT signature; fail closed) ──
DO $$
DECLARE v_wrap regprocedure;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.app_environment) OR EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging') THEN
    RAISE EXCEPTION 'G1 pre-guard: not staging (app_environment)'; END IF;
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'G1 pre-guard: current_user=% (must be postgres so the RPC is owned by postgres); run SET ROLE postgres; and retry', current_user; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id' AND data_type='uuid') THEN
    RAISE EXCEPTION 'G1 pre-guard: D-9 cleared_transaction_id column missing (apply the schema first)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='fk_au11_cleared_txn' AND c.convalidated) THEN
    RAISE EXCEPTION 'G1 pre-guard: fk_au11_cleared_txn missing/not valid'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_cleared_txn_attribution' AND c.convalidated) THEN
    RAISE EXCEPTION 'G1 pre-guard: chk_au11_cleared_txn_attribution missing/not valid'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i') THEN
    RAISE EXCEPTION 'G1 pre-guard: uix_au11_cleared_txn missing'; END IF;
  -- frozen wrapper by EXACT 13-arg signature; fail-closed on absence, then compare md5 with IS DISTINCT FROM
  v_wrap := to_regprocedure('public.save_weekly_closeout_with_snapshots(integer,integer,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,integer)');
  IF v_wrap IS NULL THEN RAISE EXCEPTION 'G1 pre-guard: frozen wrapper (exact 13-arg signature) not found'; END IF;
  IF md5(pg_get_functiondef(v_wrap)) IS DISTINCT FROM 'e2a112b376dc32c43e1615e4a4abf24a' THEN
    RAISE EXCEPTION 'G1 pre-guard: frozen wrapper md5 drift (actual=%)', md5(pg_get_functiondef(v_wrap)); END IF;
END $$;

CREATE OR REPLACE FUNCTION public.close_week_with_reservations_v1(
  p_week_num        INT,
  p_model_year      INT,
  p_chk             NUMERIC,
  p_sav             NUMERIC,
  p_amx             NUMERIC,
  p_tax             NUMERIC,
  p_lc              NUMERIC,
  p_balance_basis   TEXT,
  p_new_commitments JSONB,
  p_patched         JSONB,
  p_snapshot_rows   JSONB,
  p_mode            TEXT,
  p_expected_count  INT,
  p_retire          JSONB
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  c_epoch      CONSTANT date := DATE '2026-06-07';   -- D-6 pinned 2026 model epoch (wk1 start); 7-day weeks
  c_source     CONSTANT text := 'truist_checking';   -- D-2 authoritative evidence account / D lock source
  v_week_start date; v_week_end date;
  v_batch      RECORD;
  v_entry      jsonb; v_cid uuid; v_txn_nom uuid;
  v_cc         RECORD;
  v_cand_cnt   int; v_chosen uuid;
  v_locked     RECORD;
  v_seen_cid   uuid[] := ARRAY[]::uuid[];
  v_seen_txn   uuid[] := ARRAY[]::uuid[];
  v_chosen_set uuid[] := ARRAY[]::uuid[];
  v_plan       jsonb := '[]'::jsonb;   -- validated/locked attribution plan (NO mutation until after wrapper)
  v_planrow    jsonb;
  v_wrapper    jsonb;
  v_retired    jsonb := '[]'::jsonb;
  v_carried    jsonb := '[]'::jsonb;
  v_batch_status text;
  v_replayed   boolean := true;        -- stays true only if every entry was an idempotent no-op
  v_rowcount   int;
BEGIN
  -- ══ §I.1 authorize caller (D-1) ══
  IF NOT public.can_write_financials() THEN
    RAISE EXCEPTION 'not authorized (can_write_financials)' USING ERRCODE='42501'; END IF;

  -- ══ §I.2 pure scalar validation ══
  IF p_model_year IS DISTINCT FROM 2026 THEN
    RAISE EXCEPTION 'unsupported_model_year: % (D3 supports 2026 only)', p_model_year USING ERRCODE='22023'; END IF;
  IF p_mode IS DISTINCT FROM 'normal_closeout' THEN
    RAISE EXCEPTION 'unsupported_mode: % (D3 composite passes normal_closeout only)', COALESCE(p_mode,'<null>') USING ERRCODE='22023'; END IF;
  IF p_week_num IS NULL OR p_week_num < 1 OR p_week_num > 31 THEN
    RAISE EXCEPTION 'week_window_mismatch: week_num % out of 1..31', p_week_num USING ERRCODE='22023'; END IF;
  IF p_expected_count IS DISTINCT FROM 9 THEN
    RAISE EXCEPTION 'wrapper_contract_fail: p_expected_count must be 9 (got %)', p_expected_count USING ERRCODE='22023'; END IF;

  -- ══ §I.3 validate wrapper arrays SHAPE only (never modified — pass-through, D-7) ══
  IF p_new_commitments IS NULL OR jsonb_typeof(p_new_commitments) <> 'array' THEN
    RAISE EXCEPTION 'wrapper_contract_fail: p_new_commitments must be a JSON array'; END IF;
  IF p_patched IS NULL OR jsonb_typeof(p_patched) <> 'array' THEN
    RAISE EXCEPTION 'wrapper_contract_fail: p_patched must be a JSON array'; END IF;
  IF p_retire IS NULL OR jsonb_typeof(p_retire) <> 'array' THEN
    RAISE EXCEPTION 'p_retire must be a JSON array'; END IF;

  -- ══ §I.4 validate the complete p_retire input set (dup/malformed) — §S1 ══
  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_retire) LOOP
    IF jsonb_typeof(v_entry) <> 'object' OR NOT (v_entry ? 'commitment_id') THEN
      RAISE EXCEPTION 'p_retire entry malformed (need object with commitment_id): %', v_entry; END IF;
    BEGIN v_cid := (v_entry->>'commitment_id')::uuid; EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'p_retire malformed commitment_id: %', v_entry->>'commitment_id'; END;
    IF v_cid = ANY(v_seen_cid) THEN RAISE EXCEPTION 'duplicate_commitment_entry: %', v_cid; END IF;
    v_seen_cid := v_seen_cid || v_cid;
    IF (v_entry ? 'transaction_id') AND jsonb_typeof(v_entry->'transaction_id') <> 'null' THEN
      BEGIN v_txn_nom := (v_entry->>'transaction_id')::uuid; EXCEPTION WHEN others THEN
        RAISE EXCEPTION 'p_retire malformed transaction_id: %', v_entry->>'transaction_id'; END;
      IF v_txn_nom = ANY(v_seen_txn) THEN RAISE EXCEPTION 'duplicate_transaction_nomination: %', v_txn_nom; END IF;
      v_seen_txn := v_seen_txn || v_txn_nom;
    END IF;
  END LOOP;

  -- ══ §I.5 derive + validate week window internally from the pinned epoch (D-6) ══
  v_week_start := c_epoch + (7 * (p_week_num - 1));
  v_week_end   := v_week_start + 6;

  -- ══ §I.6 acquire the shared AU-11 advisory lock (single-flight; same key as D2) ══
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('au11_disc:'||p_model_year||':'||c_source, 0));

  -- ══ §I.7 load the active reservation batch (NULL is legal: nothing to retire; wrapper still pins week) ══
  SELECT b.* INTO v_batch FROM public.discretionary_reservation_batches b
   WHERE b.model_year = p_model_year AND b.source_account = c_source AND b.status = 'active';

  -- ══ §I.8-9 LOOP 1a — resolve candidate/nomination + replay states, BUILD PLAN. No lock, no mutation. ══
  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_retire) LOOP
    v_cid := (v_entry->>'commitment_id')::uuid;
    v_txn_nom := CASE WHEN (v_entry ? 'transaction_id') AND jsonb_typeof(v_entry->'transaction_id') <> 'null'
                      THEN (v_entry->>'transaction_id')::uuid ELSE NULL END;

    SELECT cc.* INTO v_cc FROM public.cash_commitments cc WHERE cc.id = v_cid;
    IF NOT FOUND OR v_cc.commitment_source <> 'au11_reservation' THEN
      RAISE EXCEPTION 'unknown_commitment: %', v_cid; END IF;
    IF v_batch.id IS NULL OR v_cc.reservation_batch_id <> v_batch.id THEN
      RAISE EXCEPTION 'commitment_not_in_active_batch: %', v_cid; END IF;
    IF v_cc.status IN ('planned','carried_unresolved') THEN
      RAISE EXCEPTION 'anomalous_lifecycle_state: % has unsupported status %', v_cid, v_cc.status USING ERRCODE='22023'; END IF;

    -- REPLAY states B/C/F: commitment already cleared (result-building only; NO mutation)
    IF v_cc.status = 'cleared' THEN
      IF v_cc.cleared_transaction_id IS NULL THEN
        RAISE EXCEPTION 'inconsistent_batch_state: cleared commitment % missing attribution', v_cid; END IF;   -- F
      IF v_txn_nom IS NOT NULL AND v_cc.cleared_transaction_id IS DISTINCT FROM v_txn_nom THEN
        RAISE EXCEPTION 'transaction_already_attributed: % cleared by a different transaction', v_cid; END IF;  -- C
      v_retired := v_retired || jsonb_build_object('commitment_id', v_cid, 'goal_id', v_cc.goal_id, 'idempotent', true);  -- B
      CONTINUE;
    END IF;

    IF v_cc.status NOT IN ('initiated','bank_pending') THEN
      RAISE EXCEPTION 'commitment_not_retirable: % status % (only initiated/bank_pending are retirable in D3)', v_cid, v_cc.status USING ERRCODE='22023'; END IF;

    v_replayed := false;

    -- candidate set (§E predicate) + nomination (§S1)
    IF v_txn_nom IS NULL THEN
      SELECT count(*) INTO v_cand_cnt FROM public.transactions t
       WHERE t.account_key=c_source AND t.amount<0 AND t.cleared=true
         AND (t.amount*100) = (- v_cc.amount_cents::numeric)
         AND t.transaction_date>=v_week_start AND t.transaction_date<=v_week_end
         AND NOT EXISTS (SELECT 1 FROM public.cash_commitments x WHERE x.cleared_transaction_id=t.id AND x.status='cleared');
      IF v_cand_cnt=0 THEN RAISE EXCEPTION 'evidence_missing: no eligible cleared debit for %', v_cid USING ERRCODE='22023'; END IF;
      IF v_cand_cnt>1 THEN RAISE EXCEPTION 'ambiguous_multiple_match: % has % eligible debits (nominate one)', v_cid, v_cand_cnt USING ERRCODE='22023'; END IF;
      SELECT t.id INTO v_chosen FROM public.transactions t
       WHERE t.account_key=c_source AND t.amount<0 AND t.cleared=true
         AND (t.amount*100) = (- v_cc.amount_cents::numeric)
         AND t.transaction_date>=v_week_start AND t.transaction_date<=v_week_end
         AND NOT EXISTS (SELECT 1 FROM public.cash_commitments x WHERE x.cleared_transaction_id=t.id AND x.status='cleared');
    ELSE
      SELECT count(*) INTO v_cand_cnt FROM public.transactions t
       WHERE t.id=v_txn_nom AND t.account_key=c_source AND t.amount<0 AND t.cleared=true
         AND (t.amount*100) = (- v_cc.amount_cents::numeric)
         AND t.transaction_date>=v_week_start AND t.transaction_date<=v_week_end
         AND NOT EXISTS (SELECT 1 FROM public.cash_commitments x WHERE x.cleared_transaction_id=t.id AND x.status='cleared');
      IF v_cand_cnt<>1 THEN RAISE EXCEPTION 'nominated_transaction_not_eligible: % for %', v_txn_nom, v_cid USING ERRCODE='22023'; END IF;
      v_chosen := v_txn_nom;
    END IF;

    -- reject two commitments selecting the SAME debit in one call (state D, pre-wrapper deterministic)
    IF v_chosen = ANY(v_chosen_set) THEN
      RAISE EXCEPTION 'duplicate_transaction_nomination: debit % selected for two commitments', v_chosen; END IF;
    v_chosen_set := v_chosen_set || v_chosen;

    v_plan := v_plan || jsonb_build_object('commitment_id', v_cid, 'txn_id', v_chosen,
                                           'goal_id', v_cc.goal_id, 'amount_cents', v_cc.amount_cents);
  END LOOP;

  -- ══ §I.10 lock ALL selected evidence rows in DETERMINISTIC transactions.id ORDER (deadlock-safe) ══
  --   One id-ordered FOR UPDATE statement (per §I.10). Locks held across the wrapper call this transaction.
  PERFORM 1 FROM public.transactions t
    WHERE t.id IN (SELECT (e->>'txn_id')::uuid FROM jsonb_array_elements(v_plan) e)
    ORDER BY t.id
    FOR UPDATE;

  -- ══ §I.11 re-evaluate the FULL predicate on each LOCKED row (evidence_changed on drift) ══
  FOR v_planrow IN SELECT value FROM jsonb_array_elements(v_plan) LOOP
    v_cid    := (v_planrow->>'commitment_id')::uuid;
    v_chosen := (v_planrow->>'txn_id')::uuid;
    SELECT t.* INTO v_locked FROM public.transactions t WHERE t.id=v_chosen;   -- already locked above
    IF NOT (v_locked.account_key=c_source AND v_locked.amount<0 AND v_locked.cleared=true
            AND (v_locked.amount*100) = (- (v_planrow->>'amount_cents')::int::numeric)
            AND v_locked.transaction_date>=v_week_start AND v_locked.transaction_date<=v_week_end
            AND NOT EXISTS (SELECT 1 FROM public.cash_commitments x WHERE x.cleared_transaction_id=v_locked.id AND x.status='cleared')) THEN
      RAISE EXCEPTION 'evidence_changed: locked debit % no longer satisfies the predicate for %', v_chosen, v_cid USING ERRCODE='22023'; END IF;
  END LOOP;

  -- ══ §I.12-13 call the frozen wrapper EXACTLY ONCE, capture, and VERIFY — BEFORE any attribution ══
  v_wrapper := public.save_weekly_closeout_with_snapshots(
    p_week_num, p_model_year, p_chk, p_sav, p_amx, p_tax, p_lc,
    p_balance_basis, p_new_commitments, p_patched, p_snapshot_rows, p_mode, p_expected_count);
  -- GFA01 (or any raise) inside the wrapper propagates automatically → full rollback, NO attribution applied.
  IF v_wrapper IS NULL OR jsonb_typeof(v_wrapper) <> 'object'
     OR (v_wrapper->>'ok') IS DISTINCT FROM 'true'
     OR (v_wrapper->>'mode') IS DISTINCT FROM 'normal_closeout'
     OR (v_wrapper->>'week_num')::int IS DISTINCT FROM p_week_num
     OR (v_wrapper->>'snapshot_count')::int IS DISTINCT FROM 9 THEN
    RAISE EXCEPTION 'wrapper_contract_fail: %', COALESCE(v_wrapper::text,'<null>');
  END IF;

  -- ══ §I.14-15 LOOP 2 — apply attribution ONLY NOW (after wrapper capture+verify), from the locked plan ══
  FOR v_planrow IN SELECT value FROM jsonb_array_elements(v_plan) LOOP
    v_cid    := (v_planrow->>'commitment_id')::uuid;
    v_chosen := (v_planrow->>'txn_id')::uuid;
    BEGIN
      UPDATE public.cash_commitments
         SET status='cleared', cleared_transaction_id=v_chosen,
             cleared_date=(SELECT transaction_date FROM public.transactions WHERE id=v_chosen),  -- row locked in §I.10
             reflected_model_week=p_week_num, resolved_model_week=p_week_num,
             resolution_type='cleared', resolved_by=auth.uid(), resolved_at=now()
       WHERE id=v_cid AND status IN ('initiated','bank_pending');
      GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    EXCEPTION WHEN unique_violation THEN
      -- targeted mapping ONLY for the attribution index; re-raise any unrelated unique violation
      IF SQLERRM ILIKE '%uix_au11_cleared_txn%' THEN
        RAISE EXCEPTION 'transaction_already_attributed: % already attributed to another commitment', v_chosen USING ERRCODE='23505';
      ELSE RAISE; END IF;
    END;
    IF v_rowcount <> 1 THEN RAISE EXCEPTION 'retirement_count_mismatch: % rows updated for %', v_rowcount, v_cid; END IF;
    v_retired := v_retired || jsonb_build_object('commitment_id', v_cid, 'goal_id', v_planrow->>'goal_id');
  END LOOP;

  -- ══ §I.16 omitted/unclaimed rule: an active in-batch reservation with an eligible in-week cleared debit
  --          that was NOT in p_retire → omitted_cleared_row (no silent skip) ══
  IF v_batch.id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.cash_commitments cc
       WHERE cc.reservation_batch_id=v_batch.id AND cc.commitment_source='au11_reservation'
         AND cc.status IN ('initiated','bank_pending') AND cc.id <> ALL(v_seen_cid)
         AND EXISTS (SELECT 1 FROM public.transactions t
                      WHERE t.account_key=c_source AND t.amount<0 AND t.cleared=true
                        AND (t.amount*100) = (- cc.amount_cents::numeric)
                        AND t.transaction_date>=v_week_start AND t.transaction_date<=v_week_end
                        AND NOT EXISTS (SELECT 1 FROM public.cash_commitments x WHERE x.cleared_transaction_id=t.id AND x.status='cleared'))
    ) THEN RAISE EXCEPTION 'omitted_cleared_row: an active reservation has an eligible in-week cleared debit but was omitted from p_retire'; END IF;

    -- ══ §I.17 batch retirement: retire iff every reservation row in the batch is terminal ══
    IF NOT EXISTS (SELECT 1 FROM public.cash_commitments cc
                    WHERE cc.reservation_batch_id=v_batch.id AND cc.commitment_source='au11_reservation'
                      AND cc.status NOT IN ('cleared','voided')) THEN
      UPDATE public.discretionary_reservation_batches
         SET status='retired', resolution_type='retired', resolved_at=now(), resolved_by=auth.uid()
       WHERE id=v_batch.id AND status='active';
    END IF;
    SELECT status INTO v_batch_status FROM public.discretionary_reservation_batches WHERE id=v_batch.id;
  END IF;

  -- ══ §I.18 final invariants — S3(b) post-attribution consistency for every attributed row ══
  IF EXISTS (
    SELECT 1 FROM public.cash_commitments cc JOIN public.transactions t ON t.id=cc.cleared_transaction_id
    WHERE cc.cleared_transaction_id IS NOT NULL
      AND NOT (cc.commitment_source='au11_reservation' AND cc.status='cleared'
               AND t.account_key=c_source AND t.cleared=true AND t.amount<0
               AND (t.amount*100) = (- cc.amount_cents::numeric)
               AND t.transaction_date >= (c_epoch + 7*(cc.resolved_model_week-1))
               AND t.transaction_date <= (c_epoch + 7*(cc.resolved_model_week-1) + 6))
  ) THEN RAISE EXCEPTION 'inconsistent_batch_state: S3(b) post-attribution consistency invariant violated'; END IF;

  -- ══ §I.19 structured result ══
  -- 'carried' is structurally [] in D3 v1 (carry-forward is an implicit outcome per D-3: an unclaimed
  -- reservation simply stays active/withholding and is not enumerated); like 'blocked', it is a stable
  -- response-shape field reserved for a later slice, never a silent success signal.
  RETURN jsonb_build_object(
    'ok', true, 'mode', v_wrapper->>'mode', 'week_num', p_week_num, 'snapshot_count', 9,
    'retired', v_retired, 'carried', v_carried, 'blocked', '[]'::jsonb,
    'batch_status', v_batch_status, 'replayed', v_replayed);
END $fn$;

-- Resting-inert grant posture (D-8): revoke from PUBLIC/anon/authenticated at rest. EXECUTE is granted to
-- authenticated ONLY during the authorized test matrix (validation harness) and revoked immediately after.
REVOKE ALL ON FUNCTION public.close_week_with_reservations_v1(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT,JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.close_week_with_reservations_v1(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT,JSONB) FROM anon;
REVOKE ALL ON FUNCTION public.close_week_with_reservations_v1(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT,JSONB) FROM authenticated;

-- ── POST-CREATE ASSERTION (resolve the EXACT 14-arg OID via to_regprocedure; fail closed BEFORE COMMIT) ──
DO $$
DECLARE v_oid regprocedure; v_owner text; v_secdef boolean; v_cfg boolean; v_ret text; v_vol "char"; v_par "char"; v_args text; v_anon boolean; v_auth boolean;
BEGIN
  v_oid := to_regprocedure('public.close_week_with_reservations_v1(integer,integer,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,integer,jsonb)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'G1 assert: exact 14-arg close_week_with_reservations_v1 not found'; END IF;
  SELECT pg_get_userbyid(p.proowner), p.prosecdef,
         EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE split_part(cfg,'=',1)='search_path' AND btrim(split_part(cfg,'=',2),'"')=''),
         pg_catalog.format_type(p.prorettype,NULL), p.provolatile, p.proparallel, pg_catalog.oidvectortypes(p.proargtypes)
    INTO v_owner, v_secdef, v_cfg, v_ret, v_vol, v_par, v_args
    FROM pg_proc p WHERE p.oid = v_oid;
  IF v_args <> 'integer, integer, numeric, numeric, numeric, numeric, numeric, text, jsonb, jsonb, jsonb, text, integer, jsonb' THEN
    RAISE EXCEPTION 'G1 assert: RPC signature=% (expected exact 14-arg)', v_args; END IF;
  IF v_owner <> 'postgres' THEN RAISE EXCEPTION 'G1 assert: RPC owner=% (must be postgres)', v_owner; END IF;
  IF v_secdef IS NOT TRUE THEN RAISE EXCEPTION 'G1 assert: RPC not SECURITY DEFINER'; END IF;
  IF v_cfg IS NOT TRUE THEN RAISE EXCEPTION 'G1 assert: RPC search_path not empty'; END IF;
  IF v_ret <> 'jsonb' THEN RAISE EXCEPTION 'G1 assert: RPC return type=% (must be jsonb)', v_ret; END IF;
  IF v_vol <> 'v' THEN RAISE EXCEPTION 'G1 assert: RPC volatility=% (must be v=VOLATILE)', v_vol; END IF;
  IF v_par <> 'u' THEN RAISE EXCEPTION 'G1 assert: RPC parallel=% (must be u=UNSAFE)', v_par; END IF;
  v_anon := has_function_privilege('anon', v_oid, 'EXECUTE');
  v_auth := has_function_privilege('authenticated', v_oid, 'EXECUTE');
  IF v_anon OR v_auth THEN RAISE EXCEPTION 'G1 assert: grants not inert (anon=%, authenticated=%)', v_anon, v_auth; END IF;
  RAISE NOTICE 'G1 PASS: exact 14-arg close_week_with_reservations_v1 (owner=postgres, SECURITY DEFINER, search_path='''', jsonb, VOLATILE, PARALLEL UNSAFE); grants inert.';
END $$;

COMMIT;
-- ============================================================================
