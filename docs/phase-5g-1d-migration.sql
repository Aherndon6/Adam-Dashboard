-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Slice 2 — MIGRATION (additive; INERT). Authored, NOT executed.
-- Creates EXACTLY TWO functions and no others:
--   1) public.save_weekly_closeout_with_snapshots(...)  — 13-param closeout wrapper
--   2) public.correct_goal_funding_snapshot(...)        — 6-param owner-only Option B
-- Both SECURITY DEFINER, SET search_path=public,pg_temp, fully schema-qualified, no dynamic
-- SQL, no EXCEPTION handler. They CALL the two deployed RPCs directly (never reproduce them)
-- and NEVER write weekly_reconciliations / cash_commitments / goal_funding_snapshots directly.
-- The finite-NUMERIC predicate and the goal_registry mutex are INLINED in each (no helper).
--
-- DEPLOYED INERT: after this migration NO PUBLIC/anon/authenticated EXECUTE exists on either
-- function. authenticated EXECUTE is granted only at the Slice-7 activation gate. Staging
-- real-caller tests use the separate phase-5g-1d-staging-grant.sql / -ungrant.sql package.
--
-- Grounding facts encoded here:
--   * deployed recon RPC IGNORES p_recorded_at and stamps recorded_at=NOW(); the wrapper passes
--     now() for signature compatibility only (Companion Amendment 3 / Rev 8 §8.3).
--   * deployed snapshot RPC signature is (INT,INT,JSONB) → (p_model_year,p_week_num,p_rows).
--   * weekly_reconciliations is week_num-keyed (model_year DEFAULT 2026).
-- Spec: docs/phase-5g-1d-slice2-proposed-2026-07-11.md (Rev 8). E1 DDL untouched.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public, pg_temp;

-- ██ Environment guard — deploys to PRODUCTION or approved STAGING; unknown hard-stops. ██
-- Single-file body (identical by construction; the only env-specific part is this guard).
--   production = system_identifier 7632885393857617092 AND public.app_environment ABSENT.
--   staging    = system_identifier = c_staging_sysid (pinned) AND public.app_environment PRESENT
--                with EXACTLY one row, env='staging' (no other rows/values).
--   anything else (ambiguous / unknown) → HARD STOP.
DO $$
DECLARE
  v_sysid BIGINT; v_has_appenv BOOLEAN; v_appenv_total INT; v_appenv_staging INT; v_staging_marker BOOLEAN; v_env TEXT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 0;  -- <<FILL: exact staging system_identifier (read-only query in preflight header). 0 = UNSET → staging deploy hard-stops until pinned. Do not guess.
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  v_has_appenv := to_regclass('public.app_environment') IS NOT NULL;
  -- NEVER query public.app_environment unless it exists (a bare EXISTS is planned even under a
  -- boolean AND, and errors on production where the table is absent). Guard with an explicit IF.
  v_staging_marker := false;
  IF v_has_appenv THEN
    SELECT count(*), count(*) FILTER (WHERE env = 'staging') INTO v_appenv_total, v_appenv_staging
      FROM public.app_environment;
    v_staging_marker := (v_appenv_total = 1 AND v_appenv_staging = 1);  -- exactly one row, env='staging', no others
  END IF;
  IF v_sysid = c_prod_sysid AND NOT v_has_appenv THEN
    v_env := 'production';
  ELSIF v_sysid = c_staging_sysid AND v_has_appenv AND v_staging_marker THEN
    v_env := 'staging';
  ELSE
    RAISE EXCEPTION 'HARD STOP: unknown/ambiguous environment (sysid=%, app_environment=%, staging_marker=%). Pin c_staging_sysid before staging deploy. Aborting migration.', v_sysid, v_has_appenv, v_staging_marker;
  END IF;
  RAISE NOTICE 'MIGRATION environment resolved: %', v_env;
  IF to_regclass('public.goal_funding_snapshots') IS NULL
     OR to_regprocedure('public.save_goal_funding_snapshots(INT,INT,JSONB)') IS NULL
     OR to_regprocedure('public.save_reconciliation_with_commitments(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ,JSONB,JSONB)') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: deployed dependencies missing. Aborting migration.'; END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 1) WRAPPER — save_weekly_closeout_with_snapshots (13 params; RETURNS JSONB)
-- ══════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.save_weekly_closeout_with_snapshots(
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
  p_expected_count  INT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  c_eligible9   CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska',
                                         'bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
  c_anchor_week CONSTANT int := 5;
  v_row         jsonb;
  v_gid         text;
  v_amt         numeric;
  v_ids         text[] := ARRAY[]::text[];
  v_snap_rows   jsonb;          -- source-pinned rows for the snapshot RPC
  v_has_recon   boolean;
  v_elig_cnt    int;            -- eligible-nine snapshot rows present at target week
  v_reg_cnt     int;
  v_complete_cnt int;           -- post-anchor weeks (6..31) that are nine-complete
  v_max_complete int;
  v_rec         record;
  v_diff        int;
  v_empty_arrays boolean;
BEGIN
  -- ── STEP 1a  p_mode (strict; NULL/unknown raise before anything) ──
  IF p_mode IS NULL OR p_mode NOT IN ('normal_closeout','approved_reopen') THEN
    RAISE EXCEPTION 'invalid p_mode: %', COALESCE(p_mode,'<null>') USING ERRCODE = '22023';
  END IF;

  -- ── STEP 1b  authorization (owner boundary FIRST for reopen) ──
  IF p_mode = 'approved_reopen' THEN
    IF NOT public.is_owner() THEN
      RAISE EXCEPTION 'approved_reopen requires owner (public.is_owner()=false)' USING ERRCODE = '42501';
    END IF;
  ELSE
    IF NOT public.can_write_financials() THEN
      RAISE EXCEPTION 'not authorized to write financials' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ── STEP 1c  pure-input validation (NO state reads) ──
  IF p_model_year IS DISTINCT FROM 2026 THEN RAISE EXCEPTION 'invalid model_year: %', p_model_year; END IF;
  IF p_week_num IS NULL OR p_week_num < 1 OR p_week_num > 31 THEN RAISE EXCEPTION 'invalid week_num: %', p_week_num; END IF;

  -- balances: finite (reject NaN/±Inf; numeric NaN = NaN so `v=v` is NOT used), non-null; NOT nonnegative
  IF NOT (p_chk IS NOT NULL AND p_chk <> 'NaN'::numeric AND p_chk <> 'Infinity'::numeric AND p_chk <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_chk must be a finite number'; END IF;
  IF NOT (p_sav IS NOT NULL AND p_sav <> 'NaN'::numeric AND p_sav <> 'Infinity'::numeric AND p_sav <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_sav must be a finite number'; END IF;
  IF NOT (p_amx IS NOT NULL AND p_amx <> 'NaN'::numeric AND p_amx <> 'Infinity'::numeric AND p_amx <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_amx must be a finite number'; END IF;
  IF NOT (p_tax IS NOT NULL AND p_tax <> 'NaN'::numeric AND p_tax <> 'Infinity'::numeric AND p_tax <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_tax must be a finite number'; END IF;
  IF NOT (p_lc  IS NOT NULL AND p_lc  <> 'NaN'::numeric AND p_lc  <> 'Infinity'::numeric AND p_lc  <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_lc must be a finite number';  END IF;

  -- strict JSON arrays (NULL / JSON null / object / string / number / boolean rejected, no coercion)
  IF p_new_commitments IS NULL OR jsonb_typeof(p_new_commitments) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'p_new_commitments must be a JSON array'; END IF;
  IF p_patched IS NULL OR jsonb_typeof(p_patched) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'p_patched must be a JSON array'; END IF;

  -- snapshot rows: array of exactly 9; each {goal_id ∈ c_eligible9, funded_amount finite ≥0}, NO 'source' key
  IF p_snapshot_rows IS NULL OR jsonb_typeof(p_snapshot_rows) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'p_snapshot_rows must be a JSON array'; END IF;
  IF jsonb_array_length(p_snapshot_rows) <> 9 THEN RAISE EXCEPTION 'p_snapshot_rows must have exactly 9 rows, got %', jsonb_array_length(p_snapshot_rows); END IF;
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_snapshot_rows) LOOP
    IF v_row ? 'source' THEN RAISE EXCEPTION 'p_snapshot_rows must not carry a source field'; END IF;
    v_gid := v_row->>'goal_id';
    IF v_gid IS NULL OR NOT (v_gid = ANY(c_eligible9)) THEN RAISE EXCEPTION 'unexpected/absent goal_id in snapshot rows: %', COALESCE(v_gid,'<null>'); END IF;
    IF v_gid = ANY(v_ids) THEN RAISE EXCEPTION 'duplicate goal_id in snapshot rows: %', v_gid; END IF;
    v_ids := array_append(v_ids, v_gid);
    IF (v_row->'funded_amount') IS NULL OR jsonb_typeof(v_row->'funded_amount') IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'funded_amount for % must be a JSON number', v_gid; END IF;
    v_amt := (v_row->>'funded_amount')::numeric;
    IF NOT (v_amt <> 'NaN'::numeric AND v_amt <> 'Infinity'::numeric AND v_amt <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'funded_amount for % must be finite', v_gid; END IF;
    IF v_amt < 0 THEN RAISE EXCEPTION 'funded_amount for % must be >= 0', v_gid; END IF;
  END LOOP;
  -- exact-set: 9 distinct ids == c_eligible9 (subset already enforced; count 9 + no dup ⇒ equality)
  IF array_length(v_ids,1) <> 9 THEN RAISE EXCEPTION 'snapshot rows must cover exactly the eligible nine'; END IF;
  -- p_expected_count is ENFORCED as a mandatory client/server cross-check (must equal the
  -- eligible-nine count). The server-derived nine-set above remains the authoritative control of
  -- WHICH goals/values; this only cross-checks the COUNT so the param is never merely ignored.
  IF p_expected_count IS DISTINCT FROM 9 THEN RAISE EXCEPTION 'p_expected_count must equal 9 (got %)', p_expected_count; END IF;

  -- source-pinned, cents-normalized payload for the snapshot RPC (built once)
  SELECT jsonb_agg(jsonb_build_object(
           'goal_id', r->>'goal_id',
           'funded_amount', round((r->>'funded_amount')::numeric, 2),
           'source', 'reconciliation'))
    INTO v_snap_rows
    FROM jsonb_array_elements(p_snapshot_rows) r;

  v_empty_arrays := (jsonb_array_length(p_new_commitments) = 0 AND jsonb_array_length(p_patched) = 0);

  -- ── STEP 2  serialize (BOTH locks before any state read) ──
  PERFORM pg_advisory_xact_lock(1734501000, p_model_year * 100 + p_week_num);              -- year/week advisory
  PERFORM 1 FROM public.goal_registry WHERE id = ANY(c_eligible9) ORDER BY id FOR UPDATE;  -- per-goal mutex (§4.1)

  -- ── STEP 3  post-lock state reads ──
  SELECT count(*) INTO v_reg_cnt FROM public.goal_registry WHERE id = ANY(c_eligible9);
  IF v_reg_cnt <> 9 THEN RAISE EXCEPTION 'eligible-nine registry drift: % of 9 present', v_reg_cnt; END IF;
  SELECT count(*) INTO v_elig_cnt FROM public.goal_funding_snapshots
    WHERE model_year = 2026 AND week_num = c_anchor_week AND source = 'opening_anchor' AND goal_id = ANY(c_eligible9);
  IF v_elig_cnt <> 9 THEN RAISE EXCEPTION 'opening anchor incomplete at week 5 (% of 9)', v_elig_cnt; END IF;

  -- ══ STEP 4  approved_reopen state machine (A–F) ══
  IF p_mode = 'approved_reopen' THEN
    -- A. preconditions: target = latest completed week, complete recon + nine-complete snapshots
    IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num = p_week_num) THEN
      RAISE EXCEPTION 'approved_reopen: week % has no reconciliation', p_week_num; END IF;
    SELECT count(*) INTO v_elig_cnt FROM public.goal_funding_snapshots
      WHERE model_year=2026 AND week_num=p_week_num AND goal_id = ANY(c_eligible9);
    IF v_elig_cnt <> 9 THEN RAISE EXCEPTION 'approved_reopen: week % is not fully closed (% of 9)', p_week_num, v_elig_cnt; END IF;
    -- latest completed week = max nine-complete post-anchor week
    SELECT max(wk) INTO v_max_complete FROM (
      SELECT week_num AS wk FROM public.goal_funding_snapshots
       WHERE model_year=2026 AND week_num >= 6 AND goal_id = ANY(c_eligible9)
       GROUP BY week_num HAVING count(*) = 9) s;
    IF v_max_complete IS DISTINCT FROM p_week_num THEN
      RAISE EXCEPTION 'approved_reopen: week % is not the latest completed week (latest=%)', p_week_num, v_max_complete; END IF;

    -- B. snapshots never changed by reopen: submitted amounts must equal persisted eligible nine
    SELECT count(*) INTO v_diff FROM jsonb_array_elements(v_snap_rows) r
      LEFT JOIN public.goal_funding_snapshots s
        ON s.model_year=2026 AND s.week_num=p_week_num AND s.goal_id = r->>'goal_id'
      WHERE s.goal_id IS NULL OR round(s.funded_amount,2) IS DISTINCT FROM (r->>'funded_amount')::numeric;
    IF v_diff <> 0 THEN RAISE EXCEPTION 'approved_reopen may not change snapshot amounts (use Option B)'; END IF;

    -- C. compare submitted reconciliation with persisted
    SELECT chk,sav,amx,tax,lc,balance_basis INTO v_rec FROM public.weekly_reconciliations WHERE week_num=p_week_num;
    IF round(v_rec.chk,2)=round(p_chk,2) AND round(v_rec.sav,2)=round(p_sav,2)
       AND round(v_rec.amx,2)=round(p_amx,2) AND round(v_rec.tax,2)=round(p_tax,2)
       AND round(v_rec.lc,2)=round(p_lc,2) AND v_rec.balance_basis IS NOT DISTINCT FROM p_balance_basis THEN
      -- D. persisted reconciliation ALREADY equals submitted (a retry)
      IF v_empty_arrays THEN
        RETURN jsonb_build_object('ok',true,'mode','approved_reopen','idempotent',true,'week_num',p_week_num,'snapshot_count',9);
      ELSE
        RAISE EXCEPTION 'fully closed week %: non-empty commitment resubmission on reopen — re-read and use supervised adjudication', p_week_num
          USING ERRCODE = 'GFA01', HINT = 'REQUIRES_SUPERVISED_ADJUDICATION';
      END IF;
    ELSE
      -- E. genuine reopen: apply once (RECONCILIATION ACTUALS ONLY). A reopen corrects balances;
      --    it may NOT carry commitment operations — re-applying commitment creates/patches through
      --    the deployed RPC cannot be proven duplicate-safe (its create path errors on an existing
      --    expected_item_id and is not idempotent), so reopen REQUIRES EMPTY commitment arrays and
      --    any commitment change routes to a separate supervised commitment-repair path (item A).
      IF NOT v_empty_arrays THEN
        RAISE EXCEPTION 'approved_reopen must not carry commitment operations (use the supervised commitment-repair path)'; END IF;
      -- Deployed RPC RE-STAMPS recorded_at=NOW() (ignores the arg); now() passed for signature
      -- compatibility only. Empty commitment arrays passed. Snapshot RPC NOT called.
      PERFORM public.save_reconciliation_with_commitments(
        p_week_num => p_week_num, p_model_year => 2026,
        p_chk => p_chk, p_sav => p_sav, p_amx => p_amx, p_tax => p_tax, p_lc => p_lc,
        p_balance_basis => p_balance_basis, p_recorded_at => now(),
        p_new_commitments => '[]'::jsonb, p_patched => '[]'::jsonb);
      -- post-call reconciliation read-back (same identity surface as the pre-call compare, incl. basis)
      IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=p_week_num
                       AND round(chk,2)=round(p_chk,2) AND round(sav,2)=round(p_sav,2)
                       AND round(amx,2)=round(p_amx,2) AND round(tax,2)=round(p_tax,2)
                       AND round(lc,2)=round(p_lc,2)
                       AND balance_basis IS NOT DISTINCT FROM p_balance_basis) THEN
        RAISE EXCEPTION 'approved_reopen post-call read-back mismatch'; END IF;
      RETURN jsonb_build_object('ok',true,'mode','approved_reopen','reopened',true,'week_num',p_week_num,
                                'reopened_at', clock_timestamp());  -- feedback only; NOT persisted
    END IF;
  END IF;

  -- ══ STEP 4b  normal_closeout mode/week gates ══
  IF p_week_num BETWEEN 1 AND 4 THEN RAISE EXCEPTION 'week % is legacy pre-anchor, out of snapshot-closeout scope', p_week_num; END IF;
  IF p_week_num = 5 THEN RAISE EXCEPTION 'week 5 is the opening anchor; not a normal-closeout write'; END IF;

  -- ══ STEP 5  normal_closeout state branch (week ≥ 6) ══
  SELECT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num = p_week_num) INTO v_has_recon;
  SELECT count(*) INTO v_elig_cnt FROM public.goal_funding_snapshots
    WHERE model_year=2026 AND week_num=p_week_num AND goal_id = ANY(c_eligible9);
  -- completeness stats over post-anchor weeks 6..31
  SELECT count(*), max(wk) INTO v_complete_cnt, v_max_complete FROM (
    SELECT week_num AS wk FROM public.goal_funding_snapshots
     WHERE model_year=2026 AND week_num >= 6 AND goal_id = ANY(c_eligible9)
     GROUP BY week_num HAVING count(*) = 9) s;
  v_complete_cnt := COALESCE(v_complete_cnt, 0);

  IF NOT v_has_recon AND v_elig_cnt >= 1 THEN
    -- branch H: snapshots without reconciliation → corrupt
    RAISE EXCEPTION 'corrupt state: snapshots without reconciliation at week %', p_week_num;

  ELSIF NOT v_has_recon AND v_elig_cnt = 0 THEN
    -- branch E: NORMAL NEW CLOSEOUT. Sequence: exact next contiguous week; every earlier complete.
    IF p_week_num <> 6 + v_complete_cnt THEN
      RAISE EXCEPTION 'week % is not the next contiguous closeout week (expected %)', p_week_num, 6 + v_complete_cnt; END IF;
    IF v_max_complete IS NOT NULL AND v_max_complete >= p_week_num THEN
      RAISE EXCEPTION 'a later week is already complete — non-contiguous'; END IF;
    -- MONOTONIC non-decrease (the deployed snapshot RPC does NOT enforce this): each submitted
    -- funded_amount must be >= the latest EFFECTIVE prior snapshot for that goal (max week < target,
    -- ANY source). A decrease hard-stops → supervised correction path (Option B).
    FOR v_row IN SELECT * FROM jsonb_array_elements(v_snap_rows) LOOP
      SELECT funded_amount INTO v_amt FROM public.goal_funding_snapshots
        WHERE model_year=2026 AND goal_id=v_row->>'goal_id' AND week_num < p_week_num
        ORDER BY week_num DESC LIMIT 1;
      -- Every eligible post-anchor goal MUST have a prior (the complete Week-5 anchor guarantees it).
      -- A NULL prior means a broken snapshot chain (defense-in-depth; unreachable — the STEP-3 anchor
      -- guard fires first). Hard-stop rather than silently allow.
      IF v_amt IS NULL THEN
        RAISE EXCEPTION 'broken snapshot chain: % has no effective prior snapshot before week % (anchor incomplete?)', v_row->>'goal_id', p_week_num; END IF;
      IF round((v_row->>'funded_amount')::numeric,2) < round(v_amt,2) THEN
        RAISE EXCEPTION 'monotonic violation: % submitted % < prior effective % (use the correction path)',
          v_row->>'goal_id', (v_row->>'funded_amount')::numeric, v_amt; END IF;
    END LOOP;
    -- reconciliation first (recorded_at=NOW() by the deployed RPC; now() passed for compatibility)
    PERFORM public.save_reconciliation_with_commitments(
      p_week_num => p_week_num, p_model_year => 2026,
      p_chk => p_chk, p_sav => p_sav, p_amx => p_amx, p_tax => p_tax, p_lc => p_lc,
      p_balance_basis => p_balance_basis, p_recorded_at => now(),
      p_new_commitments => p_new_commitments, p_patched => p_patched);
    -- then snapshots (source pinned reconciliation)
    PERFORM public.save_goal_funding_snapshots(p_model_year => 2026, p_week_num => p_week_num, p_rows => v_snap_rows);
    -- read-back: exactly the eligible nine present with the submitted values
    SELECT count(*) INTO v_diff FROM jsonb_array_elements(v_snap_rows) r
      LEFT JOIN public.goal_funding_snapshots s
        ON s.model_year=2026 AND s.week_num=p_week_num AND s.goal_id=r->>'goal_id'
      WHERE s.goal_id IS NULL OR round(s.funded_amount,2) IS DISTINCT FROM (r->>'funded_amount')::numeric;
    IF v_diff <> 0 THEN RAISE EXCEPTION 'normal closeout post-write read-back mismatch'; END IF;
    RETURN jsonb_build_object('ok',true,'mode','normal_closeout','week_num',p_week_num,'snapshot_count',9);

  ELSIF v_has_recon AND v_elig_cnt = 9 THEN
    -- branch F: FULLY CLOSED — identity (empty arrays only) / adjudication / hard stop
    SELECT chk,sav,amx,tax,lc,balance_basis INTO v_rec FROM public.weekly_reconciliations WHERE week_num=p_week_num;
    SELECT count(*) INTO v_diff FROM jsonb_array_elements(v_snap_rows) r
      LEFT JOIN public.goal_funding_snapshots s
        ON s.model_year=2026 AND s.week_num=p_week_num AND s.goal_id=r->>'goal_id'
      WHERE s.goal_id IS NULL OR round(s.funded_amount,2) IS DISTINCT FROM (r->>'funded_amount')::numeric;
    IF round(v_rec.chk,2)=round(p_chk,2) AND round(v_rec.sav,2)=round(p_sav,2)
       AND round(v_rec.amx,2)=round(p_amx,2) AND round(v_rec.tax,2)=round(p_tax,2)
       AND round(v_rec.lc,2)=round(p_lc,2) AND v_rec.balance_basis IS NOT DISTINCT FROM p_balance_basis
       AND v_diff = 0 THEN
      IF v_empty_arrays THEN
        RETURN jsonb_build_object('ok',true,'mode','normal_closeout','idempotent',true,'week_num',p_week_num,'snapshot_count',9);
      ELSE
        RAISE EXCEPTION 'fully closed week %: non-empty commitment resubmission — re-read and use supervised adjudication', p_week_num
          USING ERRCODE = 'GFA01', HINT = 'REQUIRES_SUPERVISED_ADJUDICATION';
      END IF;
    ELSE
      RAISE EXCEPTION 'week % already fully closed with different values — route to supervised reopen/correction', p_week_num;
    END IF;

  ELSE
    -- branch G: HALF-CLOSE REPAIR (has recon, 0..8 eligible snapshots — INCLUDING the reconciliation-only
    -- zero-snapshot legacy half-close, item B). Target must be the earliest incomplete post-anchor week.
    IF v_complete_cnt <> (p_week_num - 6) THEN
      RAISE EXCEPTION 'earlier post-anchor week incomplete — repair the earliest gap first (complete=%, expected %)', v_complete_cnt, p_week_num - 6; END IF;
    -- commitment arrays MUST be empty for repair
    IF NOT v_empty_arrays THEN RAISE EXCEPTION 'half-close repair requires empty commitment arrays'; END IF;
    -- reconciliation balances/basis must equal persisted
    SELECT chk,sav,amx,tax,lc,balance_basis INTO v_rec FROM public.weekly_reconciliations WHERE week_num=p_week_num;
    IF NOT (round(v_rec.chk,2)=round(p_chk,2) AND round(v_rec.sav,2)=round(p_sav,2)
       AND round(v_rec.amx,2)=round(p_amx,2) AND round(v_rec.tax,2)=round(p_tax,2)
       AND round(v_rec.lc,2)=round(p_lc,2) AND v_rec.balance_basis IS NOT DISTINCT FROM p_balance_basis) THEN
      RAISE EXCEPTION 'half-close repair: submitted reconciliation differs from persisted (that is a reopen)'; END IF;
    -- each PRESENT eligible row must equal the submitted amount (else correction anomaly); preserve source/note
    SELECT count(*) INTO v_diff FROM jsonb_array_elements(v_snap_rows) r
      JOIN public.goal_funding_snapshots s
        ON s.model_year=2026 AND s.week_num=p_week_num AND s.goal_id=r->>'goal_id'
      WHERE round(s.funded_amount,2) IS DISTINCT FROM (r->>'funded_amount')::numeric;
    IF v_diff <> 0 THEN RAISE EXCEPTION 'half-close repair: a present eligible row differs — correction anomaly (use Option B)'; END IF;
    -- write ONLY the missing eligible rows (source reconciliation). Recon RPC NOT called → recorded_at unchanged.
    SELECT jsonb_agg(r) INTO v_snap_rows FROM jsonb_array_elements(v_snap_rows) r
      WHERE NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots s
                          WHERE s.model_year=2026 AND s.week_num=p_week_num AND s.goal_id=r->>'goal_id');
    IF v_snap_rows IS NULL OR jsonb_array_length(v_snap_rows) = 0 THEN
      RAISE EXCEPTION 'half-close repair: no missing rows computed (inconsistent state)'; END IF;
    -- MONOTONIC non-decrease on the missing rows too (vs latest effective prior, any source)
    FOR v_row IN SELECT * FROM jsonb_array_elements(v_snap_rows) LOOP
      SELECT funded_amount INTO v_amt FROM public.goal_funding_snapshots
        WHERE model_year=2026 AND goal_id=v_row->>'goal_id' AND week_num < p_week_num
        ORDER BY week_num DESC LIMIT 1;
      IF v_amt IS NULL THEN  -- broken snapshot chain (defense-in-depth; anchor guard fires first)
        RAISE EXCEPTION 'half-close repair broken chain: % has no effective prior before week %', v_row->>'goal_id', p_week_num; END IF;
      IF round((v_row->>'funded_amount')::numeric,2) < round(v_amt,2) THEN
        RAISE EXCEPTION 'half-close repair monotonic violation: % % < prior effective % (correction path)',
          v_row->>'goal_id', (v_row->>'funded_amount')::numeric, v_amt; END IF;
    END LOOP;
    PERFORM public.save_goal_funding_snapshots(p_model_year => 2026, p_week_num => p_week_num, p_rows => v_snap_rows);
    -- read-back: complete eligible nine now present
    SELECT count(*) INTO v_elig_cnt FROM public.goal_funding_snapshots
      WHERE model_year=2026 AND week_num=p_week_num AND goal_id = ANY(c_eligible9);
    IF v_elig_cnt <> 9 THEN RAISE EXCEPTION 'half-close repair read-back: % of 9', v_elig_cnt; END IF;
    RETURN jsonb_build_object('ok',true,'mode','normal_closeout','repaired',true,'week_num',p_week_num,'snapshot_count',9);
  END IF;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- 2) OPTION B — correct_goal_funding_snapshot (6 params; owner-only in-body)
-- ══════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.correct_goal_funding_snapshot(
  p_model_year        INT,
  p_week_num          INT,
  p_goal_id           TEXT,
  p_new_funded_amount NUMERIC,
  p_expected_prior    NUMERIC,
  p_note              TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  c_eligible9 CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska',
                                       'bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
  v_prev int; v_next int;
  v_cur  numeric; v_prev_amt numeric; v_next_amt numeric;
  v_between int; v_cnt int;
BEGIN
  -- STEP 1-6  authorization + pure-input validation (no state read)
  IF NOT public.is_owner() THEN RAISE EXCEPTION 'correction requires owner (is_owner()=false)' USING ERRCODE='42501'; END IF;
  IF p_model_year IS DISTINCT FROM 2026 THEN RAISE EXCEPTION 'invalid model_year: %', p_model_year; END IF;
  IF p_week_num IS NULL OR p_week_num < 6 OR p_week_num > 31 THEN RAISE EXCEPTION 'invalid week_num (must be post-anchor 6..31): %', p_week_num; END IF;
  IF p_week_num = 5 THEN RAISE EXCEPTION 'no Week-5 correction via Option B (anchor is guarded-SQL only)'; END IF;
  IF p_goal_id IS NULL OR NOT (p_goal_id = ANY(c_eligible9)) THEN RAISE EXCEPTION 'goal_id not eligible: %', COALESCE(p_goal_id,'<null>'); END IF;
  IF NOT (p_new_funded_amount IS NOT NULL AND p_new_funded_amount <> 'NaN'::numeric AND p_new_funded_amount <> 'Infinity'::numeric AND p_new_funded_amount <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_new_funded_amount must be finite'; END IF;
  IF p_new_funded_amount < 0 THEN RAISE EXCEPTION 'p_new_funded_amount must be >= 0'; END IF;
  IF NOT (p_expected_prior IS NOT NULL AND p_expected_prior <> 'NaN'::numeric AND p_expected_prior <> 'Infinity'::numeric AND p_expected_prior <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_expected_prior must be finite'; END IF;
  IF p_expected_prior < 0 THEN RAISE EXCEPTION 'p_expected_prior must be >= 0'; END IF;
  IF p_note IS NULL OR btrim(p_note) = '' THEN RAISE EXCEPTION 'p_note must be non-empty'; END IF;

  -- STEP 7  year/week advisory lock; 7b per-goal registry mutex (assert the row was locked)
  PERFORM pg_advisory_xact_lock(1734501000, p_model_year * 100 + p_week_num);
  PERFORM 1 FROM public.goal_registry WHERE id = p_goal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'goal_registry row for % not found/locked (registry drift)', p_goal_id; END IF;

  -- STEP 8  identify neighbourhood, then lock target + neighbours in ONE ascending-week_num statement
  v_prev := (SELECT max(week_num) FROM public.goal_funding_snapshots WHERE model_year=p_model_year AND goal_id=p_goal_id AND week_num < p_week_num);
  v_next := (SELECT min(week_num) FROM public.goal_funding_snapshots WHERE model_year=p_model_year AND goal_id=p_goal_id AND week_num > p_week_num);
  PERFORM 1 FROM public.goal_funding_snapshots
    WHERE model_year=p_model_year AND goal_id=p_goal_id AND week_num IN (v_prev, p_week_num, v_next)
    ORDER BY week_num FOR UPDATE;

  -- STEP 9  under all locks: target exists, neighbourhood unchanged, expected-prior, bounds
  SELECT funded_amount INTO v_cur FROM public.goal_funding_snapshots
    WHERE model_year=p_model_year AND week_num=p_week_num AND goal_id=p_goal_id;
  IF v_cur IS NULL THEN RAISE EXCEPTION 'Option B target row missing (never backfills): %/wk%/%', p_model_year, p_week_num, p_goal_id; END IF;
  SELECT count(*) INTO v_between FROM public.goal_funding_snapshots
    WHERE model_year=p_model_year AND goal_id=p_goal_id
      AND ((v_prev IS NOT NULL AND week_num > v_prev AND week_num < p_week_num)
        OR (v_next IS NOT NULL AND week_num > p_week_num AND week_num < v_next));
  IF v_between <> 0 THEN RAISE EXCEPTION 'Option B neighbourhood changed between identify and lock — retry'; END IF;
  IF round(v_cur,2) IS DISTINCT FROM round(p_expected_prior,2) THEN
    RAISE EXCEPTION 'stale expected_prior: persisted %, expected %', round(v_cur,2), round(p_expected_prior,2); END IF;
  IF v_prev IS NOT NULL THEN
    SELECT funded_amount INTO v_prev_amt FROM public.goal_funding_snapshots WHERE model_year=p_model_year AND week_num=v_prev AND goal_id=p_goal_id;
    IF round(p_new_funded_amount,2) < round(v_prev_amt,2) THEN RAISE EXCEPTION 'correction below preceding effective value (% < %)', p_new_funded_amount, v_prev_amt; END IF;
  END IF;
  IF v_next IS NOT NULL THEN
    SELECT funded_amount INTO v_next_amt FROM public.goal_funding_snapshots WHERE model_year=p_model_year AND week_num=v_next AND goal_id=p_goal_id;
    IF round(p_new_funded_amount,2) > round(v_next_amt,2) THEN RAISE EXCEPTION 'correction above following effective value (% > %)', p_new_funded_amount, v_next_amt; END IF;
  END IF;

  -- STEP 10  call-through the deployed snapshot RPC (in-place upsert; source=correction). No direct table write.
  PERFORM public.save_goal_funding_snapshots(
    p_model_year => p_model_year, p_week_num => p_week_num,
    p_rows => jsonb_build_array(jsonb_build_object(
      'goal_id', p_goal_id, 'funded_amount', round(p_new_funded_amount,2),
      'source', 'correction', 'note', btrim(p_note))));

  -- STEP 11  read-back: exactly one natural-key row with corrected amount + source + note
  SELECT count(*) INTO v_cnt FROM public.goal_funding_snapshots
    WHERE model_year=p_model_year AND week_num=p_week_num AND goal_id=p_goal_id
      AND round(funded_amount,2)=round(p_new_funded_amount,2) AND source='correction' AND note=btrim(p_note);
  IF v_cnt <> 1 THEN RAISE EXCEPTION 'Option B read-back: expected exactly 1 corrected row, got %', v_cnt; END IF;
  RETURN jsonb_build_object('ok',true,'corrected',true,'model_year',p_model_year,'week_num',p_week_num,'goal_id',p_goal_id);
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- INERT grant normalization (exact signatures). NO authenticated EXECUTE here.
-- authenticated EXECUTE is granted only at the Slice-7 activation gate.
-- ══════════════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION public.save_weekly_closeout_with_snapshots(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.correct_goal_funding_snapshot(
  INT,INT,TEXT,NUMERIC,NUMERIC,TEXT
) FROM PUBLIC, anon, authenticated;

COMMIT;
