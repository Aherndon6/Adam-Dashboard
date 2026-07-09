-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 PRODUCTION Migration
--   (goal_funding_snapshots + save_goal_funding_snapshots RPC)
--
--   TARGET ......... PRODUCTION  Adam-Dashboard (usayoldrawwmjsmretin)
--   NEVER RUN IN ... STAGING     herndon-fos-staging (pkwotgqivgaapwuqgwqb)
--
-- Body BELOW the guard is BYTE-IDENTICAL to the staging-validated
-- docs/phase-5g-1c-2-migration.sql after stripping the header + guard block
-- (mechanical diff proof required before execution, recorded in the commit
-- message). ONLY the header and the PRODUCTION GUARD differ from staging.
-- Additive only: guard → CREATE (not CREATE OR REPLACE) → RLS → grant
-- normalization → empty-proof → COMMIT.
--
-- ██ EXECUTION GATE E1 ██ DO NOT RUN. Production DDL requires a SEPARATE
-- in-session Adam approval. Preconditions: (1) pg_dump schema-only baseline +
-- scripts/export-ai-review-pack.sh captured, (2) Supabase backup/PITR confirmed,
-- (3) prod preflight all-green, (4) run outside Wendy's Budget-entry hours.
--
-- SCHEMA ONLY — no seed. The first opening_anchor is a SEPARATE, approval-gated
-- file (docs/phase-5g-1c-2-prod-seed-anchor.sql), with values captured at seed
-- time from the approved First-Anchor Value Card (never hardcoded truth).
--
-- Wrapped in BEGIN/COMMIT so a mid-file failure leaves NO partial objects.
-- Intentionally NOT idempotent (CREATE, no IF NOT EXISTS except the guards): a
-- partial/repeat run fails loudly.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ══════════════════════════════════════════════════════════════════════════
-- ██ PRODUCTION GUARD ██ — Adam-Dashboard (usayoldrawwmjsmretin)
-- INVERTED counterpart of the staging guard: REQUIRES the production fingerprint
-- and REFUSES staging herndon-fos-staging (pkwotgqivgaapwuqgwqb) and every other
-- cluster. On failure RAISE aborts the surrounding transaction (nothing commits).
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_sysid     BIGINT;
  v_bal       NUMERIC(12,2);
  v_tx        BIGINT;
  v_reg_ids   BIGINT;
  v_adam_tgt  NUMERIC(12,2);
  v_wendy_tgt NUMERIC(12,2);
BEGIN
  -- (1) STRONGEST FINGERPRINT — cluster system_identifier equality. Captured
  --     read-only from Adam-Dashboard (usayoldrawwmjsmretin) on 2026-07-09:
  --     7632885393857617092. No other cluster (incl. staging
  --     herndon-fos-staging pkwotgqivgaapwuqgwqb) can match this value.
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid IS DISTINCT FROM 7632885393857617092 THEN
    RAISE EXCEPTION 'HARD STOP: system_identifier % <> 7632885393857617092 — target is NOT Adam-Dashboard (usayoldrawwmjsmretin). Aborting.', v_sysid;
  END IF;
  -- (2) Production has NO staging sentinel; app_environment MUST be absent.
  IF to_regclass('public.app_environment') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: public.app_environment present — looks like staging herndon-fos-staging (pkwotgqivgaapwuqgwqb), not production. Aborting.';
  END IF;
  -- (3) Baseline schema present.
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing (accounts/transactions). Aborting.';
  END IF;
  -- (3b) Dependency tables must EXIST before we query them (intentional hard-stop
  --      msg, not a raw missing-relation error): goal_registry (13-ID + IRA
  --      targets, factors 6/7) and weekly_reconciliations (RPC reconciled-week guard).
  IF to_regclass('public.goal_registry') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry missing — cannot check IDs/targets. Aborting.';
  END IF;
  IF to_regclass('public.weekly_reconciliations') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: weekly_reconciliations missing. Aborting.';
  END IF;
  -- (4) AMEX Gold production fingerprint (A4 correction: -8248.50) — REQUIRED.
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: accounts.amex_gold missing — not production. Aborting.'; END IF;
  IF v_bal IS DISTINCT FROM -8248.50 THEN
    RAISE EXCEPTION 'HARD STOP: amex_gold starting_balance % <> -8248.50 — not the Adam-Dashboard production fingerprint. Aborting.', v_bal;
  END IF;
  -- (5) Production transaction floor — committed literal >= 40 (observed 95 at probe, 2026-07-09).
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx < 40 THEN
    RAISE EXCEPTION 'HARD STOP: transactions=% < 40 floor — empty/non-production DB. Aborting.', v_tx;
  END IF;
  -- (6) goal_registry holds the 13 canonical production goal IDs (9 seeded + 4 excluded).
  SELECT count(*) INTO v_reg_ids FROM public.goal_registry
   WHERE id IN ('adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529',
                'preston_529','bryce_vehicle','christmas_cruise',
                'adam_401k','wewe_rccl','wewe_dcl','taxable_etf');
  IF v_reg_ids <> 13 THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry canonical-id count % <> 13 — production registry assumption broken. Aborting.', v_reg_ids;
  END IF;
  -- (7) IRA targets are the corrected $7,500 (commit 1dcc686); catches a stale
  --     $7,000 registry (doc-drift risk flagged in the 2026-07-08 integrity review).
  SELECT target INTO v_adam_tgt  FROM public.goal_registry WHERE id='adam_ira';
  SELECT target INTO v_wendy_tgt FROM public.goal_registry WHERE id='wendy_ira';
  IF v_adam_tgt IS DISTINCT FROM 7500 THEN RAISE EXCEPTION 'HARD STOP: adam_ira target % <> 7500 (stale IRA target). Aborting.', v_adam_tgt; END IF;
  IF v_wendy_tgt IS DISTINCT FROM 7500 THEN RAISE EXCEPTION 'HARD STOP: wendy_ira target % <> 7500 (stale IRA target). Aborting.', v_wendy_tgt; END IF;
  -- (8) app_users exact-identity assertion — OMITTED by deterministic fallback
  --     (Fable RC-5/RC-6). Assert exactly aherndon6@gmail.com + wherndon22@gmail.com
  --     ONLY if the app_users schema supports it; else omit + document. The
  --     app_users↔auth.users column shape was NOT verified in this file-creation
  --     pass, so a hardcoded join could false-abort a legitimate production run.
  --     Omitted deliberately (no soft "if available" logic). Factor (1)
  --     system_identifier equality already uniquely identifies production.
  -- (9) Migration-specific dependency — fail loud here, not mid-DDL.
  --     (goal_registry / weekly_reconciliations existence already checked at (3b).)
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                 WHERE n.nspname='public' AND p.proname='fn_set_updated_at') THEN
    RAISE EXCEPTION 'HARD STOP: shared public.fn_set_updated_at() missing (5D-1). Aborting.';
  END IF;
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
