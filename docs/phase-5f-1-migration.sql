-- ============================================================
-- Phase 5F-1 Migration — Cash Commitment Capture + Cash
-- Availability Engine
-- Spec: docs/phase-5f-1-spec.md (v3.12, frozen)
-- Purpose: ALTER weekly_reconciliations (balance_basis); CREATE
--          cash_commitments + constraints + trigger; RLS;
--          explicit REVOKE/GRANT; CREATE validate_commitment_state
--          + REVOKE PUBLIC; CREATE save_reconciliation_with_commitments
--          + REVOKE/GRANT; CREATE repair_commitments_for_week +
--          REVOKE/GRANT.
-- Date: 2026-07-01
-- Author: Adam Herndon + Claude
-- Gate: 5E-7 and 5E-8 complete. Preflight (phase-5f-1-preflight.sql)
--       run clean 2026-07-01 — PF1-PF9 all PASS, PF2/PF10 REVIEW
--       (informational, not gates).
-- Run phase-5f-1-validation.sql immediately after this file.
-- Rollback: phase-5f-1-rollback.sql
-- Wrapped in BEGIN/COMMIT for atomicity: a failure on any statement
-- (table, trigger, RLS, grant, or either RPC) rolls back the entire
-- migration rather than leaving a partial 5F-1 DB layer installed.
-- Execution-gate change requested by Adam 2026-07-01; no DB-object
-- logic changed from the frozen v3.12 spec.
-- ============================================================

BEGIN;

SET LOCAL search_path TO public;

-- ══════════════════════════════════════════════════════════════
-- 1. weekly_reconciliations — add balance_basis
-- ══════════════════════════════════════════════════════════════
-- Additive only. ADD COLUMN IF NOT EXISTS is a safe no-op if PF3
-- ever comes back REVIEW (column already present) — but PF3 came
-- back PASS (absent) on 2026-07-01, so this is expected to run live.

ALTER TABLE weekly_reconciliations
  ADD COLUMN IF NOT EXISTS balance_basis TEXT
    CHECK (balance_basis IN ('posted_current_balance','available_balance','unknown'));


-- ══════════════════════════════════════════════════════════════
-- 2. cash_commitments table
-- ══════════════════════════════════════════════════════════════
-- No reflected_in_balance column exists anywhere — reflected_model_week
-- (below) is the only field that drives reservation logic
-- (isReservedAsOf() in index.html), independent of status.

CREATE TABLE cash_commitments (
  id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expected_item_id           TEXT UNIQUE NOT NULL,
  model_year                 INT NOT NULL DEFAULT 2026,
  commitment_source          TEXT NOT NULL DEFAULT 'wd_reconciliation'
                               CHECK (commitment_source IN (
                                 'wd_reconciliation',
                                 'manual_reconciliation',
                                 'historical_repair'
                               )),
  origin_model_week          INT NOT NULL,
  payee                      TEXT NOT NULL,
  commitment_class           TEXT NOT NULL
                               CHECK (commitment_class IN (
                                 'credit_card_payment','rent','bill_payment',
                                 'tax_transfer','savings_transfer','manual_hold','other_transfer'
                               )),
  required_or_discretionary  TEXT NOT NULL
                               CHECK (required_or_discretionary IN (
                                 'protected_required','discretionary_deployment','forecast_only'
                               )),
  source_account             TEXT NOT NULL DEFAULT 'truist_checking',
                               -- 5F-1 supports exactly one source account; see
                               -- chk_source_account_only_truist below. This CHECK is a hard
                               -- DB-level backstop, not a substitute for the RPC-level
                               -- rejection in both RPCs below — the RPC check produces a
                               -- clean, callable error message ("invalid source_account: %")
                               -- before the row ever reaches this constraint. The CHECK exists
                               -- so a future write path that bypasses the RPCs (there
                               -- shouldn't be one, but grants can drift) cannot silently
                               -- create an unreserved commitment against an untracked account.
  amount_cents               INT NOT NULL CHECK (amount_cents > 0),
  original_amount_cents      INT CHECK (original_amount_cents IS NULL OR original_amount_cents > 0),
  status                     TEXT NOT NULL DEFAULT 'planned'
                               CHECK (status IN (
                                 'planned','scheduled','initiated','bank_pending',
                                 'cleared','voided','carried_unresolved','stale_review'
                               )),
  affects_deployable_cash    BOOLEAN NOT NULL DEFAULT true,
  reflected_model_week       INT,   -- NULL = not yet reflected. N = reflected in balance entered at Week N.
                               -- This is the ONLY field isReservedAsOf() and getCashAvailabilityEngine()
                               -- read to decide whether a debit is already netted out of the balance
                               -- being entered. It is independent of status — a row can be
                               -- reflected-but-not-yet-cleared (carried_unresolved with
                               -- reflected_model_week set) for multiple weeks. Under
                               -- available_balance, setting this to the current p_week_num is what
                               -- prevents double-subtraction; leaving it null keeps the reserve active.
                               -- Both RPCs restrict this to p_week_num on non-terminal rows (a live
                               -- reconciliation can only mark a debit as reflected in the balance
                               -- being entered THIS week) — see the guards in both RPCs below.
                               -- repair_commitments_for_week is intentionally exempt from that
                               -- restriction, since recording that a commitment was reflected in a
                               -- different week's balance than the one being repaired is exactly what
                               -- repair is for.
  due_date                   DATE,
  expected_clear_date        DATE,
  cleared_date               DATE,
  resolved_model_week        INT,   -- NULL = open. N = resolved at Week N.
  resolved_at                TIMESTAMPTZ,
  resolved_by                UUID REFERENCES auth.users(id),
                               -- resolved_at/resolved_by are fully server-derived in both RPCs
                               -- (NOW()/auth.uid()) on every insert and patch path. Neither RPC
                               -- ever reads these two fields from the client JSON payload. On
                               -- patch, both RPCs use COALESCE(existing, NOW()/auth.uid()) so a
                               -- legitimate transition into a resolved state is audited even if
                               -- the client omits the keys, and a client can never spoof either
                               -- field. On a terminal (cleared/voided) row, the live save RPC's
                               -- terminal immutability guard blocks patches to resolved_at/
                               -- resolved_by along with every other terminal field — only notes
                               -- and resolution_notes remain patchable.
  resolution_type            TEXT
                               CHECK (resolution_type IN (
                                 'cleared','voided','paid_from_other_account',
                                 'amount_changed','carried_unresolved'
                               )),
  resolution_notes           TEXT,
                               -- resolution_notes is genuinely server-required (not just a client
                               -- form field) for any row landing on status='voided' with
                               -- resolution_type='voided' (plain dismissal — "this obligation
                               -- doesn't apply," whether from Phase 1's "Void" response or Phase
                               -- 2's "WD event doesn't apply this week (mismatch)" branch).
                               -- Enforced in validate_commitment_state() below, not merely at the
                               -- UI layer, so a client bug cannot produce a voided/voided row with
                               -- null notes and silently defeat the audit trail this field exists
                               -- for. resolution_type='paid_from_other_account' is deliberately
                               -- exempt — it's a considered routing decision, not a one-click
                               -- dismissal.
  initiated_by               TEXT,
  notes                      TEXT,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by                 UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  updated_by                 UUID DEFAULT auth.uid() REFERENCES auth.users(id),

  CONSTRAINT chk_week_origin_range
    CHECK (origin_model_week BETWEEN 1 AND 31),
  CONSTRAINT chk_week_reflected_range
    CHECK (reflected_model_week IS NULL OR reflected_model_week BETWEEN 1 AND 31),
  CONSTRAINT chk_week_resolved_range
    CHECK (resolved_model_week IS NULL OR resolved_model_week BETWEEN 1 AND 31),
  CONSTRAINT chk_resolved_after_origin
    CHECK (resolved_model_week IS NULL OR resolved_model_week >= origin_model_week),
  CONSTRAINT chk_reflected_after_origin
    CHECK (reflected_model_week IS NULL OR reflected_model_week >= origin_model_week),
  CONSTRAINT chk_source_account_only_truist
    CHECK (source_account IN ('truist_checking')),
  CONSTRAINT chk_cleared_reflected_before_resolved
    -- A cleared debit cannot first be reflected AFTER it is resolved — reflection must occur
    -- at or before resolution, never after. Backs validate_commitment_state()'s equivalent
    -- check. Unreachable through save_reconciliation_with_commitments (its terminal week
    -- guards already force reflected_model_week = resolved_model_week = p_week_num), but
    -- reachable through repair_commitments_for_week, which allows independent values for
    -- exactly the reason repair exists. The IS NULL branches exist only so this constraint
    -- doesn't fire ahead of the more specific "cleared requires resolved_model_week" /
    -- "cleared requires reflected_model_week" checks enforced elsewhere — a cleared row with
    -- either field null is already invalid for other reasons.
    CHECK (status <> 'cleared' OR reflected_model_week IS NULL OR resolved_model_week IS NULL
           OR reflected_model_week <= resolved_model_week)
);


-- ══════════════════════════════════════════════════════════════
-- 3. Trigger — updated_at / updated_by
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_cash_commitments_set_updated()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  NEW.updated_by = auth.uid();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cash_commitments_updated
  BEFORE UPDATE ON cash_commitments
  FOR EACH ROW EXECUTE FUNCTION fn_cash_commitments_set_updated();


-- ══════════════════════════════════════════════════════════════
-- 4. RLS
-- ══════════════════════════════════════════════════════════════
-- SECURITY DEFINER RPCs (save_reconciliation_with_commitments,
-- repair_commitments_for_week — sections 7-8 below) run as the function
-- owner and bypass RLS (standard PostgreSQL behavior). The INSERT/UPDATE
-- policies below are defined for documentation intent and defense-in-depth
-- only — they are not evaluated by direct REST callers, because INSERT/
-- UPDATE are never granted to authenticated on this table (section 5).
-- All commitment mutations go through the two RPCs; REST can only SELECT.

ALTER TABLE cash_commitments ENABLE ROW LEVEL SECURITY;

CREATE POLICY cc_select ON cash_commitments
  FOR SELECT USING (is_allowed_user());

-- These policies are not evaluated via REST (INSERT/UPDATE not granted to authenticated).
-- Defined for documentation and defense-in-depth if grant model ever changes.
CREATE POLICY cc_insert ON cash_commitments
  FOR INSERT WITH CHECK (can_write_financials() AND model_year = 2026);

CREATE POLICY cc_update ON cash_commitments
  FOR UPDATE
  USING  (can_write_financials())
  WITH CHECK (can_write_financials() AND model_year = 2026);


-- ══════════════════════════════════════════════════════════════
-- 5. Table grants — explicit REVOKE then SELECT only
-- ══════════════════════════════════════════════════════════════

-- Explicit revoke before grant — do not rely on defaults
REVOKE ALL ON cash_commitments FROM PUBLIC;
REVOKE ALL ON cash_commitments FROM anon;
REVOKE ALL ON cash_commitments FROM authenticated;

-- SELECT only. INSERT/UPDATE blocked — mutations through RPCs only.
GRANT SELECT ON cash_commitments TO authenticated;


-- ══════════════════════════════════════════════════════════════
-- 6. validate_commitment_state() — SECURITY INVOKER helper
-- ══════════════════════════════════════════════════════════════
-- Does not write tables. Called only by the two SECURITY DEFINER RPCs
-- below (and directly by regression tests). No SECURITY DEFINER / SET
-- search_path clause here — deliberately omitted (defaults to SECURITY
-- INVOKER), since this function performs no table writes and is not
-- itself a privilege-escalation surface; it is the canonical state
-- validator both RPCs delegate to, so it does not depend on either
-- caller having already sanitized inputs (explicit NULL / range checks
-- throughout, not assumptions).
--
-- Parameter order below is load-bearing: p_resolved_model_week (3rd)
-- comes BEFORE p_reflected_model_week (4th). Every call site in both
-- RPCs (sections 7-8) must pass resolved-week then reflected-week in
-- that order — swapping them would silently validate the wrong week
-- field against the wrong guard.

CREATE OR REPLACE FUNCTION validate_commitment_state(
  p_id                         UUID,
  p_status                     TEXT,
  p_resolved_model_week        INT,
  p_reflected_model_week       INT,
  p_resolution_type            TEXT,
  p_origin_model_week          INT,
  p_amount_cents               INT,
  p_original_amount_cents      INT,
  p_required_or_discretionary  TEXT,
  p_affects_deployable_cash    BOOLEAN,
  p_cleared_date               DATE DEFAULT NULL,
  p_resolution_notes           TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_ctx TEXT := CASE WHEN p_id IS NOT NULL THEN 'id=' || p_id ELSE 'new row' END;
BEGIN
  -- ── Enum validity (explicit, canonical errors before DB CHECK fires) ──────
  IF p_status IS NULL THEN
    RAISE EXCEPTION 'status is required (%)', v_ctx;
  END IF;
  IF p_status NOT IN (
    'planned','scheduled','initiated','bank_pending',
    'cleared','voided','carried_unresolved','stale_review'
  ) THEN
    RAISE EXCEPTION 'invalid status: % (%)', p_status, v_ctx;
  END IF;
  IF p_required_or_discretionary IS NULL THEN
    RAISE EXCEPTION 'required_or_discretionary is required (%)', v_ctx;
  END IF;
  IF p_required_or_discretionary NOT IN (
    'protected_required','discretionary_deployment','forecast_only'
  ) THEN
    RAISE EXCEPTION 'invalid required_or_discretionary: % (%)', p_required_or_discretionary, v_ctx;
  END IF;

  -- ── Amount validity ────────────────────────────────────────────────────────
  IF p_amount_cents IS NULL OR p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'amount_cents must be > 0 (%)', v_ctx;
  END IF;
  IF p_original_amount_cents IS NOT NULL AND p_original_amount_cents <= 0 THEN
    RAISE EXCEPTION 'original_amount_cents must be > 0 or null (%)', v_ctx;
  END IF;

  -- ── origin_model_week validity ───────────────────────────────────────────
  -- This helper is the canonical state validator for both RPCs — it should not depend on
  -- callers having already validated origin_model_week themselves. Reject NULL and
  -- out-of-range values directly, rather than assuming upstream checks caught it.
  IF p_origin_model_week IS NULL THEN
    RAISE EXCEPTION 'origin_model_week is required (%)', v_ctx;
  END IF;
  IF p_origin_model_week NOT BETWEEN 1 AND 31 THEN
    RAISE EXCEPTION 'origin_model_week out of range (%)', v_ctx;
  END IF;

  -- ── Week ranges ────────────────────────────────────────────────────────────
  IF p_reflected_model_week IS NOT NULL AND p_reflected_model_week NOT BETWEEN 1 AND 31 THEN
    RAISE EXCEPTION 'reflected_model_week out of range (%)', v_ctx;
  END IF;
  IF p_resolved_model_week IS NOT NULL AND p_resolved_model_week NOT BETWEEN 1 AND 31 THEN
    RAISE EXCEPTION 'resolved_model_week out of range (%)', v_ctx;
  END IF;
  IF p_reflected_model_week IS NOT NULL AND p_reflected_model_week < p_origin_model_week THEN
    RAISE EXCEPTION 'reflected_model_week < origin_model_week (%)', v_ctx;
  END IF;
  IF p_resolved_model_week IS NOT NULL AND p_resolved_model_week < p_origin_model_week THEN
    RAISE EXCEPTION 'resolved_model_week < origin_model_week (%)', v_ctx;
  END IF;

  -- ── affects_deployable_cash validity ────────────────────────────────────────
  -- `NOT NULL` evaluates to NULL, not TRUE — a bare `NOT p_affects_deployable_cash` check below
  -- would silently fail to fire if this were NULL. Both RPCs already default it to true via
  -- COALESCE before calling this helper, and the table column is NOT NULL, so this is currently
  -- unreachable through the two production call paths — but this helper is the canonical
  -- validator, called directly by tests (see AC-49, AC-75) and potentially by future callers,
  -- so it must not assume its inputs were already sanitized upstream.
  IF p_affects_deployable_cash IS NULL THEN
    RAISE EXCEPTION 'affects_deployable_cash is required (%)', v_ctx;
  END IF;

  -- ── protected_required must affect deployable cash ─────────────────────────
  IF p_required_or_discretionary = 'protected_required' AND NOT p_affects_deployable_cash THEN
    RAISE EXCEPTION 'protected_required commitment must have affects_deployable_cash=true (%)', v_ctx;
  END IF;

  -- ── cleared_date validity ────────────────────────────────────────────────────
  -- cleared_date is informational only (isReservedAsOf / getCashAvailabilityEngine never read
  -- it — reflected_model_week and resolved_model_week are what drive reservation logic), but it
  -- must not be allowed to float free of status. A cleared_date on an initiated/bank_pending/
  -- voided/carried_unresolved row would be a dangling, misleading audit artifact.
  IF p_cleared_date IS NOT NULL AND p_status <> 'cleared' THEN
    RAISE EXCEPTION 'cleared_date must be null unless status=cleared (%)', v_ctx;
  END IF;

  -- ── Status / resolution_type consistency matrix ────────────────────────────
  -- cleared: needs both week fields and resolution_type=cleared
  IF p_status = 'cleared' THEN
    IF p_resolved_model_week IS NULL THEN
      RAISE EXCEPTION 'cleared requires resolved_model_week (%)', v_ctx;
    END IF;
    IF p_reflected_model_week IS NULL THEN
      RAISE EXCEPTION 'cleared requires reflected_model_week — balance must reflect this debit (%)', v_ctx;
    END IF;
    IF p_resolution_type IS DISTINCT FROM 'cleared' THEN
      RAISE EXCEPTION 'cleared requires resolution_type=cleared (%)', v_ctx;
    END IF;
    -- A debit cannot be operationally cleared (resolved) in an earlier week than the balance
    -- that first reflects it — reflection has to happen at or before resolution, never after.
    -- Both week guards on the save RPC's live insert/patch paths already force reflected =
    -- resolved = p_week_num, so this is unreachable through save — but repair_commitments_for_week
    -- allows independent reflected_model_week / resolved_model_week values (that's the whole
    -- point of repair), and nothing there previously stopped reflected > resolved.
    IF p_reflected_model_week > p_resolved_model_week THEN
      RAISE EXCEPTION 'cleared requires reflected_model_week <= resolved_model_week (%)', v_ctx;
    END IF;
  END IF;

  -- voided: needs resolved_model_week and terminal resolution_type
  IF p_status = 'voided' THEN
    IF p_resolved_model_week IS NULL THEN
      RAISE EXCEPTION 'voided requires resolved_model_week (%)', v_ctx;
    END IF;
    IF p_resolution_type NOT IN ('voided','paid_from_other_account') THEN
      RAISE EXCEPTION 'voided requires resolution_type in (voided, paid_from_other_account) (%)', v_ctx;
    END IF;
    -- Plain voided/voided (not paid_from_other_account) is a flat dismissal — "this obligation
    -- doesn't apply" — with no other field carrying a reason. This is exactly the "Skip / not
    -- due" → "WD event doesn't apply this week (mismatch)" flow from Phase 2, and the plain
    -- "Void" response in Phase 1 for an existing commitment. Both need a real audit reason on
    -- the row itself, not just a client-side form requirement — otherwise a client bug (or a
    -- future caller that doesn't route through this exact UI) can recreate the "silent
    -- dismissal, no trace" failure mode the resolution_notes requirement exists to close.
    -- paid_from_other_account is deliberately exempt: it's a considered routing decision, not a
    -- one-click dismissal, and the source account (once wired to real accounts) is itself part
    -- of the audit trail. Applies uniformly regardless of which UI flow produced the row —
    -- there's no way for the RPC to know that anyway, and there shouldn't need to be.
    IF p_resolution_type = 'voided'
       AND (p_resolution_notes IS NULL OR btrim(p_resolution_notes) = '') THEN
      RAISE EXCEPTION 'voided with resolution_type=voided requires non-empty resolution_notes (%)', v_ctx;
    END IF;
  END IF;

  -- carried_unresolved: no resolved_model_week; restricted resolution_type
  IF p_status = 'carried_unresolved' THEN
    IF p_resolved_model_week IS NOT NULL THEN
      RAISE EXCEPTION 'carried_unresolved must have null resolved_model_week (%)', v_ctx;
    END IF;
    IF p_resolution_type IS NOT NULL
       AND p_resolution_type NOT IN ('carried_unresolved','amount_changed') THEN
      RAISE EXCEPTION
        'carried_unresolved resolution_type must be null, carried_unresolved, or amount_changed (%)', v_ctx;
    END IF;
  END IF;

  -- amount_changed must carry real audit evidence, not just the label. Without this, a row
  -- could claim resolution_type='amount_changed' with no original amount on record — the save
  -- and repair patch paths already guarantee this in practice (original_amount_cents is
  -- auto-preserved whenever amount_cents changes), but this closes the gap for direct inserts
  -- and for any caller of this helper that doesn't go through those patch code paths.
  IF p_resolution_type = 'amount_changed' THEN
    IF p_original_amount_cents IS NULL THEN
      RAISE EXCEPTION 'amount_changed requires original_amount_cents (%)', v_ctx;
    END IF;
    IF p_original_amount_cents = p_amount_cents THEN
      RAISE EXCEPTION 'amount_changed requires original_amount_cents <> amount_cents (%)', v_ctx;
    END IF;
  END IF;

  -- Active statuses: no resolved_model_week, no resolution_type.
  IF p_status IN ('planned','scheduled','initiated','bank_pending','stale_review') THEN
    IF p_resolved_model_week IS NOT NULL THEN
      RAISE EXCEPTION 'active status % must have null resolved_model_week (%)', p_status, v_ctx;
    END IF;
    IF p_resolution_type IS NOT NULL THEN
      RAISE EXCEPTION 'active status % must have null resolution_type (%)', p_status, v_ctx;
    END IF;
  END IF;
END;
$$;

-- REVOKE targets PUBLIC, anon, and authenticated explicitly, not PUBLIC
-- alone: Supabase's schema-level ALTER DEFAULT PRIVILEGES grants EXECUTE
-- directly to anon/authenticated (as their own ACL entries) at CREATE
-- FUNCTION time, separate from — and not removed by — a PUBLIC-only
-- REVOKE. Confirmed live 2026-07-01 (phase-5f-1-validation.sql V11) and
-- fixed with phase-5f-1-grant-repair.sql; baked in here so a future
-- clean install doesn't reintroduce the same gap.
REVOKE ALL ON FUNCTION validate_commitment_state(
  UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT
) FROM PUBLIC, anon, authenticated;
-- No GRANT — internal helper only. Called by SECURITY DEFINER RPCs.


-- ══════════════════════════════════════════════════════════════
-- 7. RPC — save_reconciliation_with_commitments
-- ══════════════════════════════════════════════════════════════
-- SECURITY DEFINER: runs as the function owner, bypasses RLS on
-- cash_commitments and weekly_reconciliations by design — this is the
-- only path (besides repair, section 8) permitted to write
-- cash_commitments at all (section 5 REVOKEs INSERT/UPDATE from
-- authenticated on the base table). SET search_path = public pins the
-- resolution of every unqualified identifier inside this function body,
-- closing the SECURITY DEFINER search_path hijack class of vulnerability.
-- Authorization is NOT delegated to RLS here — the can_write_financials()
-- check at the top of the function body is the real gate.

CREATE OR REPLACE FUNCTION save_reconciliation_with_commitments(
  p_week_num         INT,
  p_model_year       INT,
  p_chk              NUMERIC,
  p_sav              NUMERIC,
  p_amx              NUMERIC,
  p_tax              NUMERIC,
  p_lc               NUMERIC,
  p_balance_basis    TEXT,
  p_recorded_at      TIMESTAMPTZ,
  p_new_commitments  JSONB DEFAULT '[]',
  p_patched          JSONB DEFAULT '[]'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item              JSONB;
  v_count             INT;
  v_row               cash_commitments%ROWTYPE;
  v_existing          cash_commitments%ROWTYPE;
  v_status            TEXT;
  v_patch_status      TEXT;
  v_rwm               INT;
  v_rfm               INT;
  v_rt                TEXT;
  v_ac                INT;
  v_owm               INT;
  v_my                INT;
  v_oac               INT;
  v_rod               TEXT;
  v_adc               BOOLEAN;
  v_cd                DATE;
  v_rn                TEXT;
  v_csource           TEXT;
  v_source_account    TEXT;
  v_resolved_at       TIMESTAMPTZ;
  v_resolved_by       UUID;
  v_amount_changed    BOOLEAN;
  v_new_status        TEXT;
  v_new_rt            TEXT;
  v_new_rwm           INT;
  v_becomes_resolved  BOOLEAN;
  v_lifecycle_patched BOOLEAN;
BEGIN
  -- ── Authorization ────────────────────────────────────────────────────────
  IF NOT can_write_financials() THEN
    RAISE EXCEPTION 'save_reconciliation_with_commitments: not authorized';
  END IF;

  -- ── RPC-level input validation ───────────────────────────────────────────
  -- Explicit IS NULL checks throughout this block: a bare `<>` or `NOT IN` or `NOT BETWEEN`
  -- comparison against NULL evaluates to NULL (not TRUE) in SQL, so it silently fails to fire
  -- and the guard is bypassed. Every one of these checks must reject NULL explicitly.
  IF p_model_year IS NULL OR p_model_year <> 2026 THEN
    RAISE EXCEPTION 'invalid model_year: %', p_model_year;
  END IF;
  IF p_week_num IS NULL OR p_week_num NOT BETWEEN 1 AND 31 THEN
    RAISE EXCEPTION 'invalid week_num: %', p_week_num;
  END IF;
  -- Phase 0 requires balance_basis be selected before save — NULL must not pass.
  IF p_balance_basis IS NULL OR p_balance_basis NOT IN ('posted_current_balance','available_balance','unknown') THEN
    RAISE EXCEPTION 'invalid balance_basis: %', p_balance_basis;
  END IF;
  IF p_recorded_at IS NULL THEN
    RAISE EXCEPTION 'recorded_at must not be null — reconciliation is an audit event';
  END IF;
  IF p_chk IS NULL OR p_sav IS NULL OR p_amx IS NULL OR p_tax IS NULL OR p_lc IS NULL THEN
    RAISE EXCEPTION 'balance fields must not be null';
  END IF;
  -- jsonb_typeof(<jsonb null literal>) returns SQL NULL, not the string 'null' — a bare
  -- `<> 'array'` comparison against that NULL is itself NULL (not TRUE), so a JSON null payload
  -- silently passes this check. IS DISTINCT FROM treats NULL as a real, non-matching value.
  IF jsonb_typeof(COALESCE(p_new_commitments,'[]'::jsonb)) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'p_new_commitments must be a JSON array';
  END IF;
  IF jsonb_typeof(COALESCE(p_patched,'[]'::jsonb)) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'p_patched must be a JSON array';
  END IF;

  -- ── Upsert reconciliation row ─────────────────────────────────────────────
  -- recorded_at is server-owned, like resolved_at/resolved_by. p_recorded_at is retained as a
  -- required parameter (validated non-null above) so the caller must signal this is a genuine
  -- audit event, but the authoritative timestamp written is always NOW() — the client cannot
  -- backdate or postdate a reconciliation record.
  INSERT INTO weekly_reconciliations
    (week_num, chk, sav, amx, tax, lc, balance_basis, recorded_at)
  VALUES
    (p_week_num, p_chk, p_sav, p_amx, p_tax, p_lc, p_balance_basis, NOW())
  ON CONFLICT (week_num) DO UPDATE SET
    chk           = EXCLUDED.chk,
    sav           = EXCLUDED.sav,
    amx           = EXCLUDED.amx,
    tax           = EXCLUDED.tax,
    lc            = EXCLUDED.lc,
    balance_basis = EXCLUDED.balance_basis,
    recorded_at   = NOW();

  -- ── Insert new commitments ─────────────────────────────────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_new_commitments,'[]')) LOOP

    -- Explicit field presence checks (clean RPC errors before table constraints fire)
    IF v_item->>'expected_item_id' IS NULL OR v_item->>'expected_item_id' = '' THEN
      RAISE EXCEPTION 'commitment missing expected_item_id';
    END IF;
    IF v_item->>'model_year' IS NULL THEN RAISE EXCEPTION 'commitment missing model_year'; END IF;
    IF v_item->>'origin_model_week' IS NULL THEN RAISE EXCEPTION 'commitment missing origin_model_week'; END IF;
    IF v_item->>'amount_cents' IS NULL THEN RAISE EXCEPTION 'commitment missing amount_cents'; END IF;
    IF v_item->>'payee' IS NULL OR v_item->>'payee' = '' THEN RAISE EXCEPTION 'commitment missing payee'; END IF;
    IF v_item->>'commitment_class' IS NULL OR v_item->>'commitment_class' = '' THEN
      RAISE EXCEPTION 'commitment missing commitment_class';
    END IF;
    IF v_item->>'commitment_class' NOT IN (
      'credit_card_payment','rent','bill_payment',
      'tax_transfer','savings_transfer','manual_hold','other_transfer'
    ) THEN
      RAISE EXCEPTION 'save: invalid commitment_class: %', v_item->>'commitment_class';
    END IF;
    IF v_item->>'required_or_discretionary' IS NULL THEN
      RAISE EXCEPTION 'commitment missing required_or_discretionary';
    END IF;

    -- Pre-cast format validation — clean RPC errors instead of raw Postgres cast exceptions
    -- (e.g. "invalid input syntax for type integer") if a caller sends a non-numeric string.
    -- Scoped to the insert path only: this is where externally-shaped JSON first enters the
    -- system, and every field validated here is either required (already null-checked above)
    -- or optional-but-format-sensitive. Patch paths deliberately do not duplicate this — a
    -- malformed patch is already a single-row, fully-atomic failure with a real (if less
    -- friendly) Postgres error, and doubling this validation across both insert and patch
    -- paths in both RPCs was judged not worth the added surface for a single-tenant app where
    -- the caller is this app's own client JS, not an arbitrary external API consumer. Flagging
    -- this scoping choice for review rather than assuming it's obviously correct.
    IF v_item->>'model_year' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment model_year must be a valid integer, got: %', v_item->>'model_year';
    END IF;
    IF v_item->>'origin_model_week' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment origin_model_week must be a valid integer, got: %', v_item->>'origin_model_week';
    END IF;
    IF v_item->>'amount_cents' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment amount_cents must be a valid integer, got: %', v_item->>'amount_cents';
    END IF;
    IF (v_item ? 'original_amount_cents') AND NULLIF(v_item->>'original_amount_cents','') IS NOT NULL
       AND v_item->>'original_amount_cents' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment original_amount_cents must be a valid integer, got: %', v_item->>'original_amount_cents';
    END IF;
    IF (v_item ? 'reflected_model_week') AND NULLIF(v_item->>'reflected_model_week','') IS NOT NULL
       AND v_item->>'reflected_model_week' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment reflected_model_week must be a valid integer, got: %', v_item->>'reflected_model_week';
    END IF;
    IF (v_item ? 'resolved_model_week') AND NULLIF(v_item->>'resolved_model_week','') IS NOT NULL
       AND v_item->>'resolved_model_week' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment resolved_model_week must be a valid integer, got: %', v_item->>'resolved_model_week';
    END IF;
    IF (v_item ? 'affects_deployable_cash') AND NULLIF(v_item->>'affects_deployable_cash','') IS NOT NULL
       AND v_item->>'affects_deployable_cash' !~* '^(true|false|t|f|1|0|yes|no|on|off)$' THEN
      RAISE EXCEPTION 'commitment affects_deployable_cash must be a valid boolean, got: %', v_item->>'affects_deployable_cash';
    END IF;

    -- Extract fields
    v_my      := (v_item->>'model_year')::INT;
    v_owm     := (v_item->>'origin_model_week')::INT;
    v_ac      := (v_item->>'amount_cents')::INT;
    v_oac     := NULLIF(v_item->>'original_amount_cents','')::INT;
    v_rod     := v_item->>'required_or_discretionary';
    v_adc     := COALESCE((v_item->>'affects_deployable_cash')::BOOLEAN, true);
    v_rwm     := NULLIF(v_item->>'resolved_model_week','')::INT;
    v_rfm     := NULLIF(v_item->>'reflected_model_week','')::INT;
    v_rt      := NULLIF(v_item->>'resolution_type','');
    v_cd      := NULLIF(v_item->>'cleared_date','')::DATE;
    v_rn      := NULLIF(v_item->>'resolution_notes','');
    -- commitment_source: missing key defaults to wd_reconciliation; a present-but-empty value
    -- is a caller bug, not "unset" — reject it rather than silently defaulting (matches AC-52).
    IF (v_item ? 'commitment_source') AND NULLIF(v_item->>'commitment_source','') IS NULL THEN
      RAISE EXCEPTION 'save: commitment_source cannot be empty';
    END IF;
    v_csource := CASE WHEN v_item ? 'commitment_source'
                   THEN v_item->>'commitment_source' ELSE 'wd_reconciliation' END;
    -- Effective status BEFORE validation — default applied here, not at INSERT
    v_status  := COALESCE(NULLIF(v_item->>'status',''), 'planned');

    -- source_account: RPC-validated allowlist of one. Never trust free text from the client.
    -- Missing key defaults to truist_checking; a present-but-empty value is a caller bug — reject
    -- it rather than silently defaulting, same distinction as commitment_source above.
    IF (v_item ? 'source_account') AND NULLIF(v_item->>'source_account','') IS NULL THEN
      RAISE EXCEPTION 'invalid source_account: (empty). 5F-1 only supports truist_checking';
    END IF;
    v_source_account := CASE WHEN v_item ? 'source_account'
                           THEN v_item->>'source_account' ELSE 'truist_checking' END;
    IF v_source_account <> 'truist_checking' THEN
      RAISE EXCEPTION 'invalid source_account: %. 5F-1 only supports truist_checking', v_source_account;
    END IF;

    -- resolved_at / resolved_by are server-owned audit fields — never read from v_item.
    -- Populated only when the row lands in a resolved state on insert.
    IF v_status IN ('cleared','voided','carried_unresolved') OR v_rt IS NOT NULL OR v_rwm IS NOT NULL THEN
      v_resolved_at := NOW();
      v_resolved_by := auth.uid();
    ELSE
      v_resolved_at := NULL;
      v_resolved_by := NULL;
    END IF;

    IF v_my <> p_model_year THEN
      RAISE EXCEPTION 'commitment model_year (%) != p_model_year (%)', v_my, p_model_year;
    END IF;
    IF v_owm NOT BETWEEN 1 AND 31 THEN
      RAISE EXCEPTION 'invalid origin_model_week: %', v_owm;
    END IF;

    -- Scope guard: live reconciliation only inserts commitments for the current week
    IF v_owm <> p_week_num THEN
      RAISE EXCEPTION
        'save: new commitment origin_model_week (%) must equal p_week_num (%) — prior-week patches via p_patched; historical inserts via repair_commitments_for_week',
        v_owm, p_week_num;
    END IF;

    -- Source guard: historical_repair and other invalid sources rejected
    IF v_csource NOT IN ('wd_reconciliation', 'manual_reconciliation') THEN
      RAISE EXCEPTION
        'save: invalid commitment_source: % (allowed: wd_reconciliation, manual_reconciliation — historical repairs use repair_commitments_for_week)',
        v_csource;
    END IF;

    -- Terminal week guards: new cleared/voided rows must resolve in the current week
    IF v_status = 'cleared' THEN
      IF v_rfm IS DISTINCT FROM p_week_num OR v_rwm IS DISTINCT FROM p_week_num THEN
        RAISE EXCEPTION
          'save: new cleared commitment must have reflected_model_week=% and resolved_model_week=% — later clearance goes through repair_commitments_for_week',
          p_week_num, p_week_num;
      END IF;
    END IF;
    IF v_status = 'voided' THEN
      IF v_rwm IS DISTINCT FROM p_week_num THEN
        RAISE EXCEPTION
          'save: new voided commitment must have resolved_model_week=%', p_week_num;
      END IF;
    END IF;

    -- Active-status new commitments: reflected_model_week, if set, must equal p_week_num.
    -- This is the server-side backing for the available_balance "already reflected in the
    -- balance being entered this week" answer (Phase 2/3) — a brand-new commitment created
    -- this week cannot already be reflected in some other week's balance. Terminal statuses
    -- are excluded here since they're already covered by the two guards immediately above.
    IF v_status NOT IN ('cleared','voided') AND v_rfm IS NOT NULL AND v_rfm IS DISTINCT FROM p_week_num THEN
      RAISE EXCEPTION
        'save: new commitment reflected_model_week (%) must equal p_week_num (%) for non-terminal status — a live reconciliation can only mark a debit as reflected in the balance being entered this week',
        v_rfm, p_week_num;
    END IF;

    PERFORM validate_commitment_state(
      NULL, v_status, v_rwm, v_rfm, v_rt, v_owm, v_ac, v_oac, v_rod, v_adc, v_cd, v_rn
    );

    INSERT INTO cash_commitments (
      expected_item_id, model_year, commitment_source,
      origin_model_week, payee, commitment_class,
      required_or_discretionary, source_account,
      amount_cents, original_amount_cents, status,
      affects_deployable_cash, reflected_model_week,
      resolved_model_week, resolved_at, resolved_by,
      resolution_type, resolution_notes,
      due_date, expected_clear_date, cleared_date,
      initiated_by, notes, created_by
    ) VALUES (
      v_item->>'expected_item_id', v_my, v_csource,
      v_owm, v_item->>'payee', v_item->>'commitment_class',
      v_rod, v_source_account,
      v_ac, v_oac, v_status, v_adc,
      v_rfm, v_rwm,
      v_resolved_at,
      v_resolved_by,
      v_rt, v_rn,
      NULLIF(v_item->>'due_date','')::DATE,
      NULLIF(v_item->>'expected_clear_date','')::DATE,
      NULLIF(v_item->>'cleared_date','')::DATE,
      NULLIF(v_item->>'initiated_by',''),
      NULLIF(v_item->>'notes',''),
      auth.uid()
    )
    ON CONFLICT (expected_item_id) DO NOTHING;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count = 0 THEN
      RAISE EXCEPTION
        'commitment already exists: expected_item_id=%. Route updates through p_patched.',
        v_item->>'expected_item_id';
    END IF;
  END LOOP;

  -- ── Patch existing commitments ─────────────────────────────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_patched,'[]')) LOOP
    IF v_item->>'id' IS NULL THEN
      RAISE EXCEPTION 'patched commitment missing id field';
    END IF;
    IF (v_item ? 'amount_cents') AND (v_item->>'amount_cents')::INT <= 0 THEN
      RAISE EXCEPTION 'patch amount_cents must be > 0';
    END IF;

    -- Pre-fetch existing row (scope-matched — same conditions as UPDATE WHERE), locked for update.
    -- FOR UPDATE closes the read-then-write race between prefetch and the UPDATE below.
    SELECT * INTO v_existing FROM cash_commitments
    WHERE id = (v_item->>'id')::UUID
      AND model_year = p_model_year
      AND origin_model_week <= p_week_num
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION
        'commitment not found, model_year mismatch, or origin_model_week > p_week_num for id=%',
        v_item->>'id';
    END IF;

    -- Terminal immutability guard: cleared/voided rows accept notes-only patches.
    -- Audit fields (resolved_at, resolved_by) are included — they must be as immutable as
    -- every other terminal field, otherwise "only notes/resolution_notes may be patched" is a lie.
    IF v_existing.status IN ('cleared', 'voided') THEN
      IF (v_item ? 'amount_cents')
         OR (v_item ? 'original_amount_cents')
         OR (v_item ? 'status')
         OR (v_item ? 'reflected_model_week')
         OR (v_item ? 'resolved_model_week')
         OR (v_item ? 'resolution_type')
         OR (v_item ? 'cleared_date')
         OR (v_item ? 'resolved_at')
         OR (v_item ? 'resolved_by') THEN
        RAISE EXCEPTION
          'save: cannot mutate terminal fields on % commitment id=%. Only notes and resolution_notes may be patched.',
          v_existing.status, v_item->>'id';
      END IF;
    END IF;

    -- Incoming terminal-status week validation (for active rows being transitioned)
    IF v_item ? 'status' THEN
      v_patch_status := v_item->>'status';
      IF v_patch_status = 'cleared' THEN
        IF (v_item ? 'reflected_model_week')
           AND NULLIF(v_item->>'reflected_model_week','')::INT IS NOT NULL
           AND (v_item->>'reflected_model_week')::INT <> p_week_num THEN
          RAISE EXCEPTION
            'live recon: clearing reflected_model_week must equal p_week_num=% (use repair RPC for historical clearance)',
            p_week_num;
        END IF;
        IF (v_item ? 'resolved_model_week')
           AND NULLIF(v_item->>'resolved_model_week','')::INT IS NOT NULL
           AND (v_item->>'resolved_model_week')::INT <> p_week_num THEN
          RAISE EXCEPTION
            'live recon: clearing resolved_model_week must equal p_week_num=%', p_week_num;
        END IF;
      END IF;
      IF v_patch_status = 'voided' THEN
        IF (v_item ? 'resolved_model_week')
           AND NULLIF(v_item->>'resolved_model_week','')::INT IS NOT NULL
           AND (v_item->>'resolved_model_week')::INT <> p_week_num THEN
          RAISE EXCEPTION
            'live recon: voiding resolved_model_week must equal p_week_num=%', p_week_num;
        END IF;
      END IF;
    END IF;

    -- Track lifecycle field involvement for post-UPDATE merged-row guard
    v_lifecycle_patched := (v_item ? 'status')
                        OR (v_item ? 'reflected_model_week')
                        OR (v_item ? 'resolved_model_week')
                        OR (v_item ? 'resolution_type');

    -- Resulting (post-merge) status/resolution_type/resolved_model_week, computed against the
    -- locked v_existing row. Used to derive resolved_at/resolved_by server-side (never from v_item)
    -- and to auto-preserve original_amount_cents / normalize resolution_type on amount changes.
    v_amount_changed := (v_item ? 'amount_cents')
                     AND (v_item->>'amount_cents')::INT IS DISTINCT FROM v_existing.amount_cents;
    v_new_status := COALESCE(NULLIF(v_item->>'status',''), v_existing.status);
    v_new_rt     := CASE
                       -- Amount-change audit trail: an amount edit that resolves a row to
                       -- carried_unresolved always carries resolution_type='amount_changed',
                       -- overriding whatever the client sent — this is the one status where
                       -- validate_commitment_state permits that resolution_type. Amount edits
                       -- on still-active rows (planned/scheduled/initiated/bank_pending/stale_review)
                       -- are left alone: validate_commitment_state requires resolution_type IS NULL
                       -- for active statuses, so there is no audit-reason slot to fill there —
                       -- original_amount_cents (below) is the audit trail in that case.
                       WHEN v_amount_changed AND v_new_status = 'carried_unresolved'
                         THEN 'amount_changed'
                       WHEN v_item ? 'resolution_type'
                         THEN NULLIF(v_item->>'resolution_type','')
                       ELSE v_existing.resolution_type
                     END;
    v_new_rwm    := CASE WHEN v_item ? 'resolved_model_week'
                       THEN NULLIF(v_item->>'resolved_model_week','')::INT
                       ELSE v_existing.resolved_model_week END;
    v_becomes_resolved := v_new_status IN ('cleared','voided','carried_unresolved')
                        OR v_new_rt IS NOT NULL
                        OR v_new_rwm IS NOT NULL;

    UPDATE cash_commitments SET
      status               = v_new_status,
      amount_cents         = CASE WHEN v_item ? 'amount_cents'
                               THEN (v_item->>'amount_cents')::INT ELSE amount_cents END,
      -- original_amount_cents: server-owned in live save, unlike repair. The client cannot
      -- explicitly set or override this field here — it is auto-preserved the first time
      -- amount_cents changes and otherwise left alone. If a client sends original_amount_cents
      -- in a live save patch, that value is ignored (not an error) — the audit trail for a live
      -- amount edit is always "what it was right before this patch," never a client-asserted value.
      -- Repair keeps the more permissive client-settable path since historical correction
      -- sometimes needs to backfill a known prior amount that predates any commitment row.
      original_amount_cents= CASE
                               WHEN v_amount_changed AND v_existing.original_amount_cents IS NULL
                                 THEN v_existing.amount_cents
                               ELSE original_amount_cents
                             END,
      reflected_model_week = CASE WHEN v_item ? 'reflected_model_week'
                               THEN NULLIF(v_item->>'reflected_model_week','')::INT
                               ELSE reflected_model_week END,
      resolved_model_week  = CASE WHEN v_item ? 'resolved_model_week'
                               THEN NULLIF(v_item->>'resolved_model_week','')::INT
                               ELSE resolved_model_week END,
      -- resolved_at / resolved_by: server-owned. Never read from v_item — set only when the
      -- merged row lands in a resolved state, and only if not already set (no re-stamping).
      resolved_at          = CASE WHEN v_becomes_resolved
                               THEN COALESCE(v_existing.resolved_at, NOW()) ELSE v_existing.resolved_at END,
      resolved_by          = CASE WHEN v_becomes_resolved
                               THEN COALESCE(v_existing.resolved_by, auth.uid()) ELSE v_existing.resolved_by END,
      resolution_type      = v_new_rt,
      resolution_notes     = CASE WHEN v_item ? 'resolution_notes'
                               THEN NULLIF(v_item->>'resolution_notes','') ELSE resolution_notes END,
      cleared_date         = CASE WHEN v_item ? 'cleared_date'
                               THEN NULLIF(v_item->>'cleared_date','')::DATE ELSE cleared_date END,
      notes                = CASE WHEN v_item ? 'notes'
                               THEN NULLIF(v_item->>'notes','') ELSE notes END,
      updated_at           = NOW(),
      updated_by           = auth.uid()
    WHERE id = (v_item->>'id')::UUID
      AND model_year = p_model_year
      AND origin_model_week <= p_week_num
    RETURNING * INTO v_row;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count <> 1 THEN
      RAISE EXCEPTION
        'commitment patch failed (concurrency or scope mismatch) for id=%', v_item->>'id';
    END IF;

    PERFORM validate_commitment_state(
      v_row.id, v_row.status, v_row.resolved_model_week, v_row.reflected_model_week,
      v_row.resolution_type, v_row.origin_model_week, v_row.amount_cents,
      v_row.original_amount_cents, v_row.required_or_discretionary, v_row.affects_deployable_cash,
      v_row.cleared_date, v_row.resolution_notes
    );

    -- Lifecycle merged-row guard: if any lifecycle field was touched, enforce p_week_num on merged result.
    -- Catches lifecycle mutations that omit status but set week fields directly.
    IF v_lifecycle_patched THEN
      IF v_row.status = 'cleared' THEN
        IF v_row.reflected_model_week IS DISTINCT FROM p_week_num THEN
          RAISE EXCEPTION
            'save patch: cleared commitment reflected_model_week (%) must equal p_week_num=% — route historical clearance through repair_commitments_for_week',
            v_row.reflected_model_week, p_week_num;
        END IF;
        IF v_row.resolved_model_week IS DISTINCT FROM p_week_num THEN
          RAISE EXCEPTION
            'save patch: cleared commitment resolved_model_week (%) must equal p_week_num=%',
            v_row.resolved_model_week, p_week_num;
        END IF;
      END IF;
      IF v_row.status = 'voided' THEN
        IF v_row.resolved_model_week IS DISTINCT FROM p_week_num THEN
          RAISE EXCEPTION
            'save patch: voided commitment resolved_model_week (%) must equal p_week_num=%',
            v_row.resolved_model_week, p_week_num;
        END IF;
      END IF;
      -- Active-status rows: reflected_model_week, if set, must equal p_week_num. Server-side
      -- backing for the available_balance "already reflected in the balance being entered this
      -- week" answer (Phase 1 Step 2) — a live patch can only assert reflection in the current
      -- week's balance, not some other week's. (repair_commitments_for_week is intentionally
      -- exempt — see its patch-path scope rules.)
      --
      -- Uses `status NOT IN ('cleared','voided')` — i.e. "any non-terminal status" — rather than
      -- an explicit list of active statuses. v3.9 originally spelled out
      -- ('planned','scheduled','initiated','bank_pending','stale_review') here and silently
      -- omitted 'carried_unresolved', which let a client that patches status to
      -- carried_unresolved (Step 1 "Amount changed") while forgetting to also send
      -- reflected_model_week:null slip a stale, pre-transition reflected_model_week through
      -- unvalidated — the reserve would then incorrectly stay off. This guard needs to cover
      -- every non-terminal status by construction, not by a list someone has to remember to
      -- extend the next time a status is added — matching the phrasing already used on the
      -- insert-path guard immediately above.
      IF v_row.status NOT IN ('cleared','voided')
         AND v_row.reflected_model_week IS NOT NULL
         AND v_row.reflected_model_week IS DISTINCT FROM p_week_num THEN
        RAISE EXCEPTION
          'save patch: reflected_model_week (%) on non-terminal commitment (status=%) must equal p_week_num=% — a live reconciliation can only mark a debit as reflected in the balance being entered this week, or explicitly clear reflected_model_week to null',
          v_row.reflected_model_week, v_row.status, p_week_num;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'week_num', p_week_num);
EXCEPTION WHEN OTHERS THEN
  RAISE;
END;
$$;

-- REVOKE targets PUBLIC, anon, and authenticated explicitly — see the
-- comment on validate_commitment_state's REVOKE above for why a
-- PUBLIC-only revoke is insufficient on Supabase. The GRANT immediately
-- below restores authenticated only.
REVOKE ALL ON FUNCTION save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB
) TO authenticated;


-- ══════════════════════════════════════════════════════════════
-- 8. RPC — repair_commitments_for_week
-- ══════════════════════════════════════════════════════════════
-- SECURITY DEFINER, SET search_path = public — same rationale as
-- save_reconciliation_with_commitments above.
--
-- Terminal-row mutability — explicit statement of intent. This RPC and
-- save_reconciliation_with_commitments deliberately differ here, and that
-- difference is load-bearing, not an oversight:
--   - save cannot mutate a cleared/voided row at all except notes and
--     resolution_notes (live reconciliation; a terminal row reached
--     through the live flow is final).
--   - repair has no equivalent terminal immutability guard, and this is
--     intentional: repair exists specifically to revise historical rows,
--     including rows that are already terminal (e.g. correcting which
--     week an Amex payment actually cleared in, discovered weeks after
--     the fact). Repair may revise a terminal historical row, but only
--     within the same guardrails every repair patch already has —
--     origin_model_week = p_week_num (strict equality, so a repair call
--     can only touch rows that originated in the week it's repairing),
--     the FOR UPDATE row lock, the GET DIAGNOSTICS/ROW_COUNT check, and
--     post-merge validate_commitment_state() plus the reconciliation-row-
--     existence guards on the merged result.
--   - Practical implication: a client cannot use this RPC as a backdoor
--     to rewrite an arbitrary terminal row from an arbitrary week — the
--     origin_model_week = p_week_num scope guard confines every repair
--     call to the one week it declares it's repairing.

CREATE OR REPLACE FUNCTION repair_commitments_for_week(
  p_week_num         INT,
  p_model_year       INT,
  p_balance_basis    TEXT  DEFAULT NULL,
  p_new_commitments  JSONB DEFAULT '[]',
  p_patched          JSONB DEFAULT '[]'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item              JSONB;
  v_count             INT;
  v_row               cash_commitments%ROWTYPE;
  v_existing          cash_commitments%ROWTYPE;
  v_status            TEXT;
  v_rwm               INT;
  v_rfm               INT;
  v_rt                TEXT;
  v_ac                INT;
  v_owm               INT;
  v_my                INT;
  v_oac               INT;
  v_rod               TEXT;
  v_adc               BOOLEAN;
  v_cd                DATE;
  v_rn                TEXT;
  v_source_account    TEXT;
  v_resolved_at       TIMESTAMPTZ;
  v_resolved_by       UUID;
  v_amount_changed    BOOLEAN;
  v_new_status        TEXT;
  v_new_rt            TEXT;
  v_new_rwm           INT;
  v_becomes_resolved  BOOLEAN;
BEGIN
  -- ── Authorization ────────────────────────────────────────────────────────
  IF NOT can_write_financials() THEN
    RAISE EXCEPTION 'repair_commitments_for_week: not authorized';
  END IF;

  -- ── Input validation ─────────────────────────────────────────────────────
  -- Explicit IS NULL checks — see save_reconciliation_with_commitments for why a bare
  -- `<>` / `NOT BETWEEN` comparison against NULL silently fails to fire.
  IF p_model_year IS NULL OR p_model_year <> 2026 THEN
    RAISE EXCEPTION 'invalid model_year: %', p_model_year;
  END IF;
  IF p_week_num IS NULL OR p_week_num NOT BETWEEN 1 AND 31 THEN
    RAISE EXCEPTION 'invalid week_num: %', p_week_num;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM weekly_reconciliations WHERE week_num = p_week_num) THEN
    RAISE EXCEPTION 'repair: no reconciliation row for week_num=%', p_week_num;
  END IF;
  -- p_balance_basis stays optional in repair (repair may only be correcting commitments,
  -- not the balance basis) — NULL is a legitimate "leave it alone" signal here, not an error.
  IF p_balance_basis IS NOT NULL
     AND p_balance_basis NOT IN ('posted_current_balance','available_balance','unknown') THEN
    RAISE EXCEPTION 'invalid balance_basis: %', p_balance_basis;
  END IF;
  IF jsonb_typeof(COALESCE(p_new_commitments,'[]'::jsonb)) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'p_new_commitments must be a JSON array';
  END IF;
  IF jsonb_typeof(COALESCE(p_patched,'[]'::jsonb)) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'p_patched must be a JSON array';
  END IF;

  -- ── Optionally patch balance_basis ───────────────────────────────────────
  IF p_balance_basis IS NOT NULL THEN
    UPDATE weekly_reconciliations SET balance_basis = p_balance_basis WHERE week_num = p_week_num;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count <> 1 THEN
      RAISE EXCEPTION 'repair: failed to update balance_basis for week_num=%', p_week_num;
    END IF;
  END IF;

  -- ── Insert new commitments ─────────────────────────────────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_new_commitments,'[]')) LOOP

    IF v_item->>'expected_item_id' IS NULL OR v_item->>'expected_item_id' = '' THEN
      RAISE EXCEPTION 'commitment missing expected_item_id';
    END IF;
    IF v_item->>'model_year' IS NULL THEN RAISE EXCEPTION 'commitment missing model_year'; END IF;
    IF v_item->>'origin_model_week' IS NULL THEN RAISE EXCEPTION 'commitment missing origin_model_week'; END IF;
    IF v_item->>'amount_cents' IS NULL THEN RAISE EXCEPTION 'commitment missing amount_cents'; END IF;
    IF v_item->>'payee' IS NULL OR v_item->>'payee' = '' THEN RAISE EXCEPTION 'commitment missing payee'; END IF;
    IF v_item->>'commitment_class' IS NULL OR v_item->>'commitment_class' = '' THEN
      RAISE EXCEPTION 'commitment missing commitment_class';
    END IF;
    IF v_item->>'commitment_class' NOT IN (
      'credit_card_payment','rent','bill_payment',
      'tax_transfer','savings_transfer','manual_hold','other_transfer'
    ) THEN
      RAISE EXCEPTION 'repair: invalid commitment_class: %', v_item->>'commitment_class';
    END IF;
    IF v_item->>'required_or_discretionary' IS NULL THEN
      RAISE EXCEPTION 'commitment missing required_or_discretionary';
    END IF;

    -- Pre-cast format validation — same rationale and scope as save's insert path (clean RPC
    -- errors instead of raw Postgres cast exceptions; insert-path only, not patch).
    IF v_item->>'model_year' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment model_year must be a valid integer, got: %', v_item->>'model_year';
    END IF;
    IF v_item->>'origin_model_week' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment origin_model_week must be a valid integer, got: %', v_item->>'origin_model_week';
    END IF;
    IF v_item->>'amount_cents' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment amount_cents must be a valid integer, got: %', v_item->>'amount_cents';
    END IF;
    IF (v_item ? 'original_amount_cents') AND NULLIF(v_item->>'original_amount_cents','') IS NOT NULL
       AND v_item->>'original_amount_cents' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment original_amount_cents must be a valid integer, got: %', v_item->>'original_amount_cents';
    END IF;
    IF (v_item ? 'reflected_model_week') AND NULLIF(v_item->>'reflected_model_week','') IS NOT NULL
       AND v_item->>'reflected_model_week' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment reflected_model_week must be a valid integer, got: %', v_item->>'reflected_model_week';
    END IF;
    IF (v_item ? 'resolved_model_week') AND NULLIF(v_item->>'resolved_model_week','') IS NOT NULL
       AND v_item->>'resolved_model_week' !~ '^-?[0-9]+$' THEN
      RAISE EXCEPTION 'commitment resolved_model_week must be a valid integer, got: %', v_item->>'resolved_model_week';
    END IF;
    IF (v_item ? 'affects_deployable_cash') AND NULLIF(v_item->>'affects_deployable_cash','') IS NOT NULL
       AND v_item->>'affects_deployable_cash' !~* '^(true|false|t|f|1|0|yes|no|on|off)$' THEN
      RAISE EXCEPTION 'commitment affects_deployable_cash must be a valid boolean, got: %', v_item->>'affects_deployable_cash';
    END IF;

    v_my     := (v_item->>'model_year')::INT;
    v_owm    := (v_item->>'origin_model_week')::INT;
    v_ac     := (v_item->>'amount_cents')::INT;
    v_oac    := NULLIF(v_item->>'original_amount_cents','')::INT;
    v_rod    := v_item->>'required_or_discretionary';
    v_adc    := COALESCE((v_item->>'affects_deployable_cash')::BOOLEAN, true);
    v_rwm    := NULLIF(v_item->>'resolved_model_week','')::INT;
    v_rfm    := NULLIF(v_item->>'reflected_model_week','')::INT;
    v_rt     := NULLIF(v_item->>'resolution_type','');
    v_cd     := NULLIF(v_item->>'cleared_date','')::DATE;
    v_rn     := NULLIF(v_item->>'resolution_notes','');
    v_status := COALESCE(NULLIF(v_item->>'status',''), 'planned');

    -- source_account: same RPC-validated allowlist of one as save, including the same
    -- present-but-empty rejection (missing key defaults; empty string is a caller bug).
    IF (v_item ? 'source_account') AND NULLIF(v_item->>'source_account','') IS NULL THEN
      RAISE EXCEPTION 'invalid source_account: (empty). 5F-1 only supports truist_checking';
    END IF;
    v_source_account := CASE WHEN v_item ? 'source_account'
                           THEN v_item->>'source_account' ELSE 'truist_checking' END;
    IF v_source_account <> 'truist_checking' THEN
      RAISE EXCEPTION 'invalid source_account: %. 5F-1 only supports truist_checking', v_source_account;
    END IF;

    -- resolved_at / resolved_by are server-owned audit fields — never read from v_item, even in
    -- historical repair. Populated only when the row lands in a resolved state on insert.
    IF v_status IN ('cleared','voided','carried_unresolved') OR v_rt IS NOT NULL OR v_rwm IS NOT NULL THEN
      v_resolved_at := NOW();
      v_resolved_by := auth.uid();
    ELSE
      v_resolved_at := NULL;
      v_resolved_by := NULL;
    END IF;

    IF v_my <> p_model_year THEN
      RAISE EXCEPTION 'commitment model_year (%) != p_model_year (%)', v_my, p_model_year;
    END IF;
    IF v_owm NOT BETWEEN 1 AND 31 THEN
      RAISE EXCEPTION 'invalid origin_model_week: %', v_owm;
    END IF;
    IF v_owm <> p_week_num THEN
      RAISE EXCEPTION 'repair: origin_model_week (%) must equal p_week_num (%)', v_owm, p_week_num;
    END IF;

    PERFORM validate_commitment_state(
      NULL, v_status, v_rwm, v_rfm, v_rt, v_owm, v_ac, v_oac, v_rod, v_adc, v_cd, v_rn
    );

    -- Reconciliation-row existence guards (insert path)
    IF v_rfm IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM weekly_reconciliations WHERE week_num = v_rfm) THEN
        RAISE EXCEPTION
          'repair: reflected_model_week=% has no reconciliation row — cannot attribute clearance to unreconciled week',
          v_rfm;
      END IF;
    END IF;
    IF v_status = 'cleared' AND v_rwm IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM weekly_reconciliations WHERE week_num = v_rwm) THEN
        RAISE EXCEPTION
          'repair: resolved_model_week=% has no reconciliation row for cleared status', v_rwm;
      END IF;
    END IF;

    INSERT INTO cash_commitments (
      expected_item_id, model_year, commitment_source,
      origin_model_week, payee, commitment_class,
      required_or_discretionary, source_account,
      amount_cents, original_amount_cents, status,
      affects_deployable_cash, reflected_model_week,
      resolved_model_week, resolved_at, resolved_by,
      resolution_type, resolution_notes,
      due_date, expected_clear_date, cleared_date,
      initiated_by, notes, created_by
    ) VALUES (
      v_item->>'expected_item_id', v_my,
      'historical_repair',    -- hardcoded; caller cannot override
      v_owm, v_item->>'payee', v_item->>'commitment_class',
      v_rod, v_source_account,
      v_ac, v_oac, v_status, v_adc,
      v_rfm, v_rwm,
      v_resolved_at,
      v_resolved_by,
      v_rt, v_rn,
      NULLIF(v_item->>'due_date','')::DATE,
      NULLIF(v_item->>'expected_clear_date','')::DATE,
      NULLIF(v_item->>'cleared_date','')::DATE,
      NULLIF(v_item->>'initiated_by',''),
      NULLIF(v_item->>'notes',''),
      auth.uid()
    )
    ON CONFLICT (expected_item_id) DO NOTHING;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count = 0 THEN
      RAISE EXCEPTION
        'repair: commitment already exists: expected_item_id=%. Route updates through p_patched.',
        v_item->>'expected_item_id';
    END IF;
  END LOOP;

  -- ── Patch existing commitments ─────────────────────────────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_patched,'[]')) LOOP
    IF v_item->>'id' IS NULL THEN
      RAISE EXCEPTION 'repair: patched commitment missing id';
    END IF;
    IF (v_item ? 'amount_cents') AND (v_item->>'amount_cents')::INT <= 0 THEN
      RAISE EXCEPTION 'repair: patch amount_cents must be > 0';
    END IF;

    -- Pre-fetch existing row (scope-matched — same conditions as UPDATE WHERE), locked for update.
    -- Same FOR UPDATE treatment as save_reconciliation_with_commitments — repair previously had
    -- no prefetch at all, which meant no row lock and no basis for auto-preserving
    -- original_amount_cents or deriving resolved_at/resolved_by server-side.
    SELECT * INTO v_existing FROM cash_commitments
    WHERE id = (v_item->>'id')::UUID
      AND model_year = p_model_year
      AND origin_model_week = p_week_num    -- strict equality — repair only touches its own week
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION
        'repair: patch failed — not found, model_year mismatch, or origin_model_week != p_week_num for id=%',
        v_item->>'id';
    END IF;

    -- Resulting (post-merge) status/resolution_type/resolved_model_week, computed against the
    -- locked v_existing row. Same derivation as save — see save_reconciliation_with_commitments
    -- for the rationale on why amount-change normalization is scoped to carried_unresolved only.
    v_amount_changed := (v_item ? 'amount_cents')
                     AND (v_item->>'amount_cents')::INT IS DISTINCT FROM v_existing.amount_cents;
    v_new_status := COALESCE(NULLIF(v_item->>'status',''), v_existing.status);
    v_new_rt     := CASE
                       WHEN v_amount_changed AND v_new_status = 'carried_unresolved'
                         THEN 'amount_changed'
                       WHEN v_item ? 'resolution_type'
                         THEN NULLIF(v_item->>'resolution_type','')
                       ELSE v_existing.resolution_type
                     END;
    v_new_rwm    := CASE WHEN v_item ? 'resolved_model_week'
                       THEN NULLIF(v_item->>'resolved_model_week','')::INT
                       ELSE v_existing.resolved_model_week END;
    v_becomes_resolved := v_new_status IN ('cleared','voided','carried_unresolved')
                        OR v_new_rt IS NOT NULL
                        OR v_new_rwm IS NOT NULL;

    UPDATE cash_commitments SET
      status               = v_new_status,
      amount_cents         = CASE WHEN v_item ? 'amount_cents' THEN (v_item->>'amount_cents')::INT ELSE amount_cents END,
      -- original_amount_cents: auto-preserved the first time amount_cents changes, unless the
      -- client explicitly supplies original_amount_cents (repair backfilling a known prior amount).
      original_amount_cents= CASE
                               WHEN v_amount_changed AND v_existing.original_amount_cents IS NULL
                                 THEN v_existing.amount_cents
                               WHEN v_item ? 'original_amount_cents'
                                 THEN NULLIF(v_item->>'original_amount_cents','')::INT
                               ELSE original_amount_cents
                             END,
      reflected_model_week = CASE WHEN v_item ? 'reflected_model_week' THEN NULLIF(v_item->>'reflected_model_week','')::INT ELSE reflected_model_week END,
      resolved_model_week  = CASE WHEN v_item ? 'resolved_model_week' THEN NULLIF(v_item->>'resolved_model_week','')::INT ELSE resolved_model_week END,
      -- resolved_at / resolved_by: server-owned, never read from v_item. Same rule as save.
      resolved_at          = CASE WHEN v_becomes_resolved
                               THEN COALESCE(v_existing.resolved_at, NOW()) ELSE v_existing.resolved_at END,
      resolved_by          = CASE WHEN v_becomes_resolved
                               THEN COALESCE(v_existing.resolved_by, auth.uid()) ELSE v_existing.resolved_by END,
      resolution_type      = v_new_rt,
      resolution_notes     = CASE WHEN v_item ? 'resolution_notes' THEN NULLIF(v_item->>'resolution_notes','') ELSE resolution_notes END,
      cleared_date         = CASE WHEN v_item ? 'cleared_date' THEN NULLIF(v_item->>'cleared_date','')::DATE ELSE cleared_date END,
      notes                = CASE WHEN v_item ? 'notes' THEN NULLIF(v_item->>'notes','') ELSE notes END,
      updated_at           = NOW(),
      updated_by           = auth.uid()
    WHERE id = (v_item->>'id')::UUID
      AND model_year = p_model_year
      AND origin_model_week = p_week_num    -- strict equality — repair only touches its own week
    RETURNING * INTO v_row;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count <> 1 THEN
      RAISE EXCEPTION
        'repair: patch failed (concurrency or scope mismatch) for id=%', v_item->>'id';
    END IF;

    PERFORM validate_commitment_state(
      v_row.id, v_row.status, v_row.resolved_model_week, v_row.reflected_model_week,
      v_row.resolution_type, v_row.origin_model_week, v_row.amount_cents,
      v_row.original_amount_cents, v_row.required_or_discretionary, v_row.affects_deployable_cash,
      v_row.cleared_date, v_row.resolution_notes
    );

    -- Reconciliation-row existence guards on merged result (patch path)
    IF v_row.reflected_model_week IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM weekly_reconciliations WHERE week_num = v_row.reflected_model_week) THEN
        RAISE EXCEPTION
          'repair patch: merged reflected_model_week=% has no reconciliation row',
          v_row.reflected_model_week;
      END IF;
    END IF;
    IF v_row.status = 'cleared' AND v_row.resolved_model_week IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM weekly_reconciliations WHERE week_num = v_row.resolved_model_week) THEN
        RAISE EXCEPTION
          'repair patch: merged resolved_model_week=% has no reconciliation row for cleared status',
          v_row.resolved_model_week;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'week_num', p_week_num);
EXCEPTION WHEN OTHERS THEN
  RAISE;
END;
$$;

-- REVOKE targets PUBLIC, anon, and authenticated explicitly — same
-- Supabase default-privilege reason as the other two REVOKEs above.
REVOKE ALL ON FUNCTION repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB) TO authenticated;


COMMIT;

-- ── Post-migration summary ────────────────────────────────────────────────────
-- Runs after COMMIT, against committed state — informational only, not part
-- of the atomic migration itself. Matches the post-rollback verification
-- convention in phase-5f-1-rollback.sql.
SELECT 'weekly_reconciliations.balance_basis' AS object, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'weekly_reconciliations' AND column_name = 'balance_basis'
UNION ALL
SELECT 'cash_commitments (table)', tablename, 'n/a' FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'cash_commitments'
UNION ALL
SELECT 'functions', routine_name, 'n/a' FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('validate_commitment_state','save_reconciliation_with_commitments','repair_commitments_for_week','fn_cash_commitments_set_updated');

-- Run phase-5f-1-validation.sql to verify structure, RLS, grants, and
-- function privileges before touching index.html or test_regression.js.
-- ============================================================
