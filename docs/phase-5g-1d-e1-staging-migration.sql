-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — STAGING E1 snapshot-layer MIGRATION. Authored, NOT executed.
-- Re-deploys the E1 snapshot layer (goal_funding_snapshots + save_goal_funding_snapshots)
-- to STAGING so the 5G-1D staging preflight can pass (staging lacks the layer after the C2
-- rehearsal was rolled back). PRODUCTION IS NOT TOUCHED; the production E1 objects are not
-- modified or rerun.
--
-- IDENTITY: the body BELOW the STAGING GUARD (from "-- ── 1. goal_funding_snapshots" to the
-- post-commit SELECTs) is COPIED VERBATIM from the committed production E1 migration
-- docs/phase-5g-1c-2-prod-migration.sql (lines 114-303). ONLY the header + guard differ, so
-- the deployed table/RPC/RLS/grants are byte-identical to the production E1 contract. The
-- validation proves the RPC md5(pg_get_functiondef) equals the pinned production capture.
--
-- EXACT STAGING FINGERPRINT GUARD: system_identifier = 7656985631720456337 AND exactly one
-- public.app_environment row with env='staging'. Any other environment (incl. production)
-- HARD-STOPS. Additive only (CREATE, not CREATE OR REPLACE); BEGIN/COMMIT so a mid-file
-- failure leaves no partial objects. Separately rollbackable (phase-5g-1d-e1-staging-rollback.sql).
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ══════════════════════════════════════════════════════════════════════════
-- ██ STAGING GUARD ██ — exact fingerprint; REFUSES production and every unknown cluster.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_sysid BIGINT; v_has_appenv BOOLEAN; v_appenv_total INT; v_appenv_staging INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;  -- confirmed staging system_identifier
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN
    RAISE EXCEPTION 'HARD STOP: production system_identifier — this staging-only E1 migration must never run on production. Aborting.';
  END IF;
  v_has_appenv := to_regclass('public.app_environment') IS NOT NULL;
  IF NOT v_has_appenv THEN
    RAISE EXCEPTION 'HARD STOP: public.app_environment absent — not the approved staging environment. Aborting.';
  END IF;
  SELECT count(*), count(*) FILTER (WHERE env = 'staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint (sysid=%, app_environment rows=%, env=staging rows=%). Aborting.', v_sysid, v_appenv_total, v_appenv_staging;
  END IF;
  -- Dependencies the E1 body needs (fail loud here, not mid-DDL):
  IF to_regclass('public.goal_registry') IS NULL OR to_regclass('public.weekly_reconciliations') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry / weekly_reconciliations missing on staging. Aborting.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='fn_set_updated_at') THEN
    RAISE EXCEPTION 'HARD STOP: shared public.fn_set_updated_at() missing (5D-1). Aborting.'; END IF;
  IF to_regprocedure('public.is_allowed_user()') IS NULL OR to_regprocedure('public.can_write_financials()') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: is_allowed_user()/can_write_financials() missing (RLS policies depend on them). Aborting.'; END IF;
  RAISE NOTICE 'STAGING E1 MIGRATION environment: staging (sysid %)', v_sysid;
END $$;

-- ── 1. goal_funding_snapshots ────────────────────────────────────────────────
-- Week-anchored OBSERVED CUMULATIVE funded amount per goal, applied in runModel
-- like reconData (overwrite at anchor). Zero rows => identical to pre-5G-1C
-- behaviour (identity gate). Surrogate UUID PK; uniqueness is the natural key
-- (model_year, week_num, goal_id). created_by_user_id is nullable audit context
-- (auth.uid()=NULL under the SQL editor); RLS is HOUSEHOLD-level, not row-owner.
CREATE TABLE public.goal_funding_snapshots (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  model_year          INT           NOT NULL,
  week_num            INT           NOT NULL,           -- MODEL week (1..31)
  goal_id             TEXT          NOT NULL REFERENCES public.goal_registry(id)
                                      ON UPDATE CASCADE ON DELETE RESTRICT,
  funded_amount       NUMERIC(12,2) NOT NULL,           -- observed cumulative funded at that week's end
  source              TEXT          NOT NULL,           -- opening_anchor | reconciliation | correction
  note                TEXT,
  created_by_user_id  UUID          DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),

  CONSTRAINT uq_gfs_year_week_goal UNIQUE (model_year, week_num, goal_id),
  CONSTRAINT chk_gfs_funded_nonneg CHECK (funded_amount >= 0),
  CONSTRAINT chk_gfs_source        CHECK (source IN ('opening_anchor','reconciliation','correction')),
  CONSTRAINT chk_gfs_week_range    CHECK (week_num BETWEEN 1 AND 31)
);

COMMENT ON TABLE public.goal_funding_snapshots IS
  'Phase 5G-1C-2 — week-anchored observed CUMULATIVE funded amount per goal. '
  'Applied in runModel like reconData (OVERWRITE at anchor, not additive). '
  'Zero rows => byte-identical to pre-5G-1C behaviour (identity gate). '
  'source: opening_anchor (first seed) | reconciliation (weekly closeout, 5G-1D) | '
  'correction (only sanctioned monotonicity break). Excluded by the write RPC: '
  'auto goals (adam_401k), holding/deferred goals (wewe_rccl, wewe_dcl, taxable_etf). '
  'Reconciliation validated by week_num only (weekly_reconciliations has no model_year; '
  'inherited from 5F-1; safe only under the single 31-week 2026 model).';

CREATE INDEX idx_gfs_year_week ON public.goal_funding_snapshots (model_year, week_num);

-- Shared updated_at trigger (reuse 5D-1 helper; do NOT redefine it).
CREATE TRIGGER set_goal_funding_snapshots_updated_at
  BEFORE UPDATE ON public.goal_funding_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ── 2. Write RPC — the house-way, authorized, validated, idempotent path ──────
-- SECURITY DEFINER + SET search_path=public (closes the search_path hijack class).
-- Authorization is enforced HERE via can_write_financials(), NOT delegated to RLS.
-- Explicit IS NULL checks throughout (bare <>/NOT IN vs NULL silently bypass guards).
CREATE FUNCTION public.save_goal_funding_snapshots(
  p_model_year INT,
  p_week_num   INT,
  p_rows       JSONB
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row      JSONB;
  v_goal_id  TEXT;
  v_amount   NUMERIC(12,2);
  v_source   TEXT;
  v_note     TEXT;
  v_count    INTEGER := 0;
  v_excluded TEXT[]  := ARRAY['wewe_rccl','wewe_dcl','taxable_etf'];  -- holding/deferred (5G-1B/1E)
BEGIN
  -- (1) Authorization — reject any caller who cannot write financials.
  IF NOT public.can_write_financials() THEN
    RAISE EXCEPTION 'save_goal_funding_snapshots: not authorized';
  END IF;

  -- (2) Scalar input validation.
  IF p_model_year IS NULL OR p_model_year < 2020 OR p_model_year > 2100 THEN
    RAISE EXCEPTION 'save_goal_funding_snapshots: invalid model_year (%).', p_model_year;
  END IF;
  IF p_week_num IS NULL OR p_week_num < 1 OR p_week_num > 31 THEN
    RAISE EXCEPTION 'save_goal_funding_snapshots: week_num % out of range 1..31.', p_week_num;
  END IF;

  -- (3) Payload shape — validated before the business-state (reconciled) check.
  --     p_rows must be a non-empty JSON array. NULL is rejected EXPLICITLY (never
  --     COALESCEd to a silent no-op). An empty array is ALSO rejected: every real
  --     save carries >=1 goal row, so [] signals a malformed caller, not a
  --     legitimate no-op. (Decision: reject empty; revisit only if a no-op save
  --     ever has a caller.)
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'save_goal_funding_snapshots: p_rows must be a JSON array.';
  END IF;
  IF jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'save_goal_funding_snapshots: p_rows must contain at least one row (empty array not allowed).';
  END IF;

  -- (4) Week must be reconciled. week_num-ONLY lookup: weekly_reconciliations has
  --     no model_year column (inherited from 5F-1; safe only under the single
  --     31-week 2026 model). Applies to ALL sources incl. opening_anchor (R4).
  IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num = p_week_num) THEN
    RAISE EXCEPTION 'save_goal_funding_snapshots: week % is not reconciled.', p_week_num;
  END IF;

  -- (5) Per-row validation + idempotent upsert on (model_year, week_num, goal_id).
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_goal_id := v_row->>'goal_id';
    v_source  := v_row->>'source';
    v_note    := v_row->>'note';

    IF v_goal_id IS NULL THEN
      RAISE EXCEPTION 'save_goal_funding_snapshots: a row is missing goal_id.';
    END IF;
    IF (v_row->'funded_amount') IS NULL OR jsonb_typeof(v_row->'funded_amount') <> 'number' THEN
      RAISE EXCEPTION 'save_goal_funding_snapshots: goal_id=% has null/non-numeric funded_amount.', v_goal_id;
    END IF;
    v_amount := (v_row->>'funded_amount')::NUMERIC(12,2);
    IF v_amount < 0 THEN
      RAISE EXCEPTION 'save_goal_funding_snapshots: negative funded_amount for goal_id=%.', v_goal_id;
    END IF;
    IF v_source IS NULL OR v_source NOT IN ('opening_anchor','reconciliation','correction') THEN
      RAISE EXCEPTION 'save_goal_funding_snapshots: invalid source "%" for goal_id=%.', v_source, v_goal_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.goal_registry g WHERE g.id = v_goal_id) THEN
      RAISE EXCEPTION 'save_goal_funding_snapshots: goal_id % not in goal_registry.', v_goal_id;
    END IF;
    IF EXISTS (SELECT 1 FROM public.goal_registry g WHERE g.id = v_goal_id AND g.auto = true) THEN
      RAISE EXCEPTION 'save_goal_funding_snapshots: goal_id % is an auto goal (excluded from snapshots).', v_goal_id;
    END IF;
    IF v_goal_id = ANY (v_excluded) THEN
      RAISE EXCEPTION 'save_goal_funding_snapshots: goal_id % is excluded (holding/deferred; 5G-1B/1E).', v_goal_id;
    END IF;

    INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note)
    VALUES (p_model_year, p_week_num, v_goal_id, v_amount, v_source, v_note)
    ON CONFLICT (model_year, week_num, goal_id) DO UPDATE
      SET funded_amount = EXCLUDED.funded_amount,
          source        = EXCLUDED.source,
          note          = EXCLUDED.note;   -- updated_at bumped by set_..._updated_at trigger
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END $$;

COMMENT ON FUNCTION public.save_goal_funding_snapshots(INT,INT,JSONB) IS
  'Phase 5G-1C-2 write RPC. SECURITY DEFINER; authorization via can_write_financials(). '
  'Idempotent upsert on (model_year, week_num, goal_id). Rejects: unauthorized caller, '
  'null/invalid model_year, week_num outside 1..31, null/non-array/EMPTY p_rows, '
  'unreconciled week (week_num-only), invalid/missing goal_id, negative funded_amount, '
  'invalid source, auto goals (adam_401k), holding/deferred goals '
  '(wewe_rccl/wewe_dcl/taxable_etf). 5G-1D adds the closeout UI caller.';

-- ── 3. RLS — every policy scoped TO authenticated (never PUBLIC/anon) ────────
-- Writes go through the RPC, but the table also carries conforming write policies
-- as defense-in-depth for any direct PostgREST path. No DELETE policy (snapshots
-- are append/correct-only; no hard delete).
ALTER TABLE public.goal_funding_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_read" ON public.goal_funding_snapshots
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "financial_writer_insert" ON public.goal_funding_snapshots
  FOR INSERT TO authenticated WITH CHECK (public.can_write_financials());
CREATE POLICY "financial_writer_update" ON public.goal_funding_snapshots
  FOR UPDATE TO authenticated USING (public.can_write_financials()) WITH CHECK (public.can_write_financials());

-- ── 4. Grants — NORMALIZE (revoke all) then grant least-privilege ────────────
-- Supabase/Postgres default privileges grant broad table privileges (incl.
-- TRUNCATE, which BYPASSES RLS) to authenticated/anon on new public tables.
-- GRANT is additive and does NOT reset those, so REVOKE ALL first. New functions
-- also default to EXECUTE for PUBLIC — revoke and re-grant narrowly.
-- service_role is intentionally left untouched (backend/admin; bypasses RLS by design).
REVOKE ALL ON public.goal_funding_snapshots FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.goal_funding_snapshots TO authenticated;  -- no DELETE
REVOKE ALL ON FUNCTION public.save_goal_funding_snapshots(INT,INT,JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_goal_funding_snapshots(INT,INT,JSONB) TO authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;  -- idempotent

-- ── 5. Schema-only proof: the table must be empty (no seed here) ─────────────
DO $$
BEGIN
  IF (SELECT count(*) FROM public.goal_funding_snapshots) <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: migration is schema-only; table must be empty. Aborting.';
  END IF;
END $$;

COMMIT;

-- Post-commit sanity (full checks in phase-5g-1c-2-validation.sql):
SELECT 'M-table' AS check,
       (SELECT count(*) FROM information_schema.tables
        WHERE table_schema='public' AND table_name='goal_funding_snapshots') AS expected_1;
SELECT 'M-rpc' AS check,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='save_goal_funding_snapshots') AS expected_1;
