-- ════════════════════════════════════════════════════════════════════════════
-- 2027 rollover Package C: server package (D-11, frozen spec v2.1 §10).
--
-- AUTHORED AND TESTED LOCALLY ONLY. Not applied to staging or production. Application is a later
-- owner-gated package (G), which first verifies that the live bodies equal the base below.
--
-- Base (proven: the repository source reproduces the recorded production md5(pg_get_functiondef)):
--   save_weekly_closeout_with_snapshots   docs/phase-5g-1d-migration.sql        e2a112b376dc32c43e1615e4a4abf24a
--   save_reconciliation_with_commitments  docs/phase-5f-1-migration.sql         1bfde751ac647c5e9a25ba168d08150c
--   save_goal_funding_snapshots           docs/phase-5g-1c-2-prod-migration.sql 154231b3f180349ec328f08ccbe77076
--   correct_goal_funding_snapshot         docs/phase-5g-1d-migration.sql        (no recorded production pin)
--   validate_commitment_state             docs/phase-5f-1-migration.sql         (no recorded production pin)
--
-- Contents, all §10 D-11 scope:
--   1. two immutable helpers, plan_year_of_week and opening_week_of_plan (no client EXECUTE: N-9);
--   2. cash_commitments: week checks >= 1; P-Y1 table check;
--   3. goal_funding_snapshots: week check >= 1; P-Y2 table check;
--   4. validate_commitment_state: week >= 1;
--   5. save_reconciliation_with_commitments: P-Y3; week >= 1; cross-year patch scope;
--   6. save_goal_funding_snapshots: week >= 1; never at the opening position (with P-Y2, which places every
--      opening_anchor row there, it can never write an opening anchor);
--   7. save_weekly_closeout_with_snapshots: P-Y3; eligibility from R(Y) by derive → lock → re-derive;
--      archived contradiction; proven global contiguity; first-close re-verification (IP-2 to IP-6);
--      global latest week for reopen; snapshot reads and writes scoped to p_model_year;
--   8. correct_goal_funding_snapshot: P-Y3; eligibility from R(Y); archived contradiction; rejects
--      the opening position.
-- Unchanged: function signatures (so owners and grants carry over), RLS, grants, the advisory lock
-- key, other tables, repair_commitments_for_week.
-- ════════════════════════════════════════════════════════════════════════════
BEGIN;

-- ── 1. Period helpers (§3): the 2026 exception lives here and in the client mirror only ──
-- plan_year_of_week(n): the calendar year of weekStart(n) = 2026-06-07 + 7·(n−1) (P2). NULL for n < 1.
CREATE FUNCTION public.plan_year_of_week(p_week INT) RETURNS INT
LANGUAGE sql IMMUTABLE STRICT
SET search_path = pg_catalog
AS $$ SELECT CASE WHEN p_week >= 1 THEN extract(year FROM DATE '2026-06-07' + 7 * (p_week - 1))::int END $$;
REVOKE ALL ON FUNCTION public.plan_year_of_week(INT) FROM PUBLIC, anon, authenticated;

-- opening_week_of_plan(Y): 5 for 2026 (frozen legacy exception); firstWeekOfPlan(Y) − 1 for Y >= 2027,
-- where firstWeekOfPlan(Y) is the absolute week starting on the first Sunday of Y. NULL otherwise.
CREATE FUNCTION public.opening_week_of_plan(p_year INT) RETURNS INT
LANGUAGE sql IMMUTABLE STRICT
SET search_path = pg_catalog
AS $$ SELECT CASE
         WHEN p_year = 2026 THEN 5
         WHEN p_year >= 2027 THEN
           ((make_date(p_year, 1, 1) + (7 - extract(dow FROM make_date(p_year, 1, 1))::int) % 7) - DATE '2026-06-07') / 7
       END $$;
REVOKE ALL ON FUNCTION public.opening_week_of_plan(INT) FROM PUBLIC, anon, authenticated;

-- ── 2. cash_commitments: weeks >= 1; P-Y1 (§6) ──
ALTER TABLE public.cash_commitments
  DROP CONSTRAINT chk_week_origin_range,
  DROP CONSTRAINT chk_week_reflected_range,
  DROP CONSTRAINT chk_week_resolved_range,
  ADD CONSTRAINT chk_week_origin_range    CHECK (origin_model_week >= 1),
  ADD CONSTRAINT chk_week_reflected_range CHECK (reflected_model_week IS NULL OR reflected_model_week >= 1),
  ADD CONSTRAINT chk_week_resolved_range  CHECK (resolved_model_week IS NULL OR resolved_model_week >= 1),
  ADD CONSTRAINT chk_cc_plan_year         CHECK (COALESCE(model_year = public.plan_year_of_week(origin_model_week), false));

-- ── 3. goal_funding_snapshots: week >= 1; P-Y2 (§6). With uq_gfs_year_week_goal this allows at most
--       one opening snapshot per (plan year, goal). ──
ALTER TABLE public.goal_funding_snapshots
  DROP CONSTRAINT chk_gfs_week_range,
  ADD CONSTRAINT chk_gfs_week_range CHECK (week_num >= 1),
  ADD CONSTRAINT chk_gfs_plan_year  CHECK (COALESCE(CASE WHEN source = 'opening_anchor'
                                                         THEN week_num = public.opening_week_of_plan(model_year)
                                                         ELSE model_year = public.plan_year_of_week(week_num) END, false));

-- ── 4. validate_commitment_state ──
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
  IF p_origin_model_week < 1 THEN
    RAISE EXCEPTION 'origin_model_week out of range (%)', v_ctx;
  END IF;

  -- ── Week ranges ────────────────────────────────────────────────────────────
  IF p_reflected_model_week IS NOT NULL AND p_reflected_model_week < 1 THEN
    RAISE EXCEPTION 'reflected_model_week out of range (%)', v_ctx;
  END IF;
  IF p_resolved_model_week IS NOT NULL AND p_resolved_model_week < 1 THEN
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

-- ── 5. save_reconciliation_with_commitments ──
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
  IF p_week_num IS NULL OR p_week_num < 1 THEN
    RAISE EXCEPTION 'invalid week_num: %', p_week_num;
  END IF;
  -- 2027 rollover P-Y3: the plan year is the plan year of the week (§6).
  IF p_model_year IS NULL OR p_model_year IS DISTINCT FROM public.plan_year_of_week(p_week_num) THEN
    RAISE EXCEPTION 'invalid model_year: %', p_model_year;
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
    IF v_owm < 1 THEN
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
    -- 2027 rollover (§8, §10): a commitment of an earlier plan year may be patched (it keeps its
    -- own model_year and origin); a later plan year's commitment may not.
    WHERE id = (v_item->>'id')::UUID
      AND model_year <= p_model_year
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
      AND model_year <= p_model_year
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

-- ── 6. save_goal_funding_snapshots ──
CREATE OR REPLACE FUNCTION public.save_goal_funding_snapshots(
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
  IF p_week_num IS NULL OR p_week_num < 1 THEN
    RAISE EXCEPTION 'save_goal_funding_snapshots: week_num % out of range (must be >= 1).', p_week_num;
  END IF;
  -- 2027 rollover O2 (§7.2): opening anchors are control data written only by initialization. P-Y2
  -- places every opening_anchor row at the opening position, so refusing that position is enough.
  IF p_week_num = public.opening_week_of_plan(p_model_year) THEN
    RAISE EXCEPTION 'save_goal_funding_snapshots: week % is the opening position of plan %.', p_week_num, p_model_year;
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

-- ── 7. save_weekly_closeout_with_snapshots ──
CREATE OR REPLACE FUNCTION public.save_weekly_closeout_with_snapshots(
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
  c_first_closeable CONSTANT int := 6;  -- openingWeekOfPlan(2026) + 1: global contiguity starts here (§10)
  v_open_wk     int;            -- openingWeekOfPlan(p_model_year)
  v_elig        text[];         -- R(p_model_year), identifier order (§7.1)
  v_elig2       text[];         -- R(p_model_year) re-derived under the locks (§7.4 OD-4)
  v_n           int;            -- |R(p_model_year)|
  v_row         jsonb;
  v_gid         text;
  v_amt         numeric;
  v_ids         text[] := ARRAY[]::text[];
  v_snap_rows   jsonb;          -- source-pinned rows for the snapshot RPC
  v_has_recon   boolean;
  v_elig_cnt    int;            -- tracked-goal snapshot rows present at the target week
  v_reg_cnt     int;
  v_k           int[];          -- K: complete weeks >= 6, every plan year (§10)
  v_complete_cnt int;
  v_max_complete int;
  v_gap         int;
  v_rec         record;
  v_diff        int;
  v_empty_arrays boolean;
  v_branch      text;
  v_prev        text[];         -- R(p_model_year - 1), identifier order
  v_preds       text[] := ARRAY[]::text[];
  v_pred        text;
  v_reason      text;
  v_final       numeric;
  v_status      text;
  v_a           record;
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
  IF p_week_num IS NULL OR p_week_num < 1 THEN RAISE EXCEPTION 'invalid week_num: %', p_week_num; END IF;
  -- P-Y3 (§6): the plan year is the plan year of the week.
  IF p_model_year IS NULL OR p_model_year IS DISTINCT FROM public.plan_year_of_week(p_week_num) THEN
    RAISE EXCEPTION 'invalid model_year: % (week % belongs to plan %)', p_model_year, p_week_num, public.plan_year_of_week(p_week_num);
  END IF;
  v_open_wk := public.opening_week_of_plan(p_model_year);
  IF v_open_wk IS NULL THEN RAISE EXCEPTION 'invalid model_year: % (no opening position)', p_model_year; END IF;

  -- balances: finite (reject NaN/±Inf; numeric NaN = NaN so `v=v` is NOT used), non-null; NOT nonnegative
  IF NOT (p_chk IS NOT NULL AND p_chk <> 'NaN'::numeric AND p_chk <> 'Infinity'::numeric AND p_chk <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_chk must be a finite number'; END IF;
  IF NOT (p_sav IS NOT NULL AND p_sav <> 'NaN'::numeric AND p_sav <> 'Infinity'::numeric AND p_sav <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_sav must be a finite number'; END IF;
  IF NOT (p_amx IS NOT NULL AND p_amx <> 'NaN'::numeric AND p_amx <> 'Infinity'::numeric AND p_amx <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_amx must be a finite number'; END IF;
  IF NOT (p_tax IS NOT NULL AND p_tax <> 'NaN'::numeric AND p_tax <> 'Infinity'::numeric AND p_tax <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_tax must be a finite number'; END IF;
  IF NOT (p_lc  IS NOT NULL AND p_lc  <> 'NaN'::numeric AND p_lc  <> 'Infinity'::numeric AND p_lc  <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_lc must be a finite number';  END IF;

  -- strict JSON arrays (NULL / JSON null / object / string / number / boolean rejected, no coercion)
  IF p_new_commitments IS NULL OR jsonb_typeof(p_new_commitments) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'p_new_commitments must be a JSON array'; END IF;
  IF p_patched IS NULL OR jsonb_typeof(p_patched) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'p_patched must be a JSON array'; END IF;

  -- snapshot rows: shape only here. Which goals they must cover is derived from the database
  -- under the locks (STEP 3); the submitted list is never the authority.
  IF p_snapshot_rows IS NULL OR jsonb_typeof(p_snapshot_rows) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'p_snapshot_rows must be a JSON array'; END IF;
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_snapshot_rows) LOOP
    IF v_row ? 'source' THEN RAISE EXCEPTION 'p_snapshot_rows must not carry a source field'; END IF;
    v_gid := v_row->>'goal_id';
    IF v_gid IS NULL THEN RAISE EXCEPTION 'unexpected/absent goal_id in snapshot rows: <null>'; END IF;
    IF v_gid = ANY(v_ids) THEN RAISE EXCEPTION 'duplicate goal_id in snapshot rows: %', v_gid; END IF;
    v_ids := array_append(v_ids, v_gid);
    IF (v_row->'funded_amount') IS NULL OR jsonb_typeof(v_row->'funded_amount') IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'funded_amount for % must be a JSON number', v_gid; END IF;
    v_amt := (v_row->>'funded_amount')::numeric;
    IF NOT (v_amt <> 'NaN'::numeric AND v_amt <> 'Infinity'::numeric AND v_amt <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'funded_amount for % must be finite', v_gid; END IF;
    IF v_amt < 0 THEN RAISE EXCEPTION 'funded_amount for % must be >= 0', v_gid; END IF;
  END LOOP;

  -- source-pinned, cents-normalized payload for the snapshot RPC (built once)
  SELECT jsonb_agg(jsonb_build_object(
           'goal_id', r->>'goal_id',
           'funded_amount', round((r->>'funded_amount')::numeric, 2),
           'source', 'reconciliation'))
    INTO v_snap_rows
    FROM jsonb_array_elements(p_snapshot_rows) r;

  v_empty_arrays := (jsonb_array_length(p_new_commitments) = 0 AND jsonb_array_length(p_patched) = 0);

  -- ── STEP 2  serialize: the existing advisory lock, then derive → lock → re-derive R(Y) (§7.4 OD-4) ──
  PERFORM pg_advisory_xact_lock(1734501000, p_model_year * 100 + p_week_num);              -- year/week advisory
  SELECT COALESCE(array_agg(goal_id ORDER BY goal_id), ARRAY[]::text[]) INTO v_elig
    FROM public.goal_funding_snapshots
   WHERE model_year = p_model_year AND week_num = v_open_wk AND source = 'opening_anchor';
  v_n := cardinality(v_elig);
  IF v_n = 0 THEN RAISE EXCEPTION 'no opening state for plan %: no opening anchors at week %', p_model_year, v_open_wk; END IF;
  PERFORM 1 FROM public.goal_registry WHERE id = ANY(v_elig) ORDER BY id FOR UPDATE;     -- per-goal mutex (§4.1)
  SELECT COALESCE(array_agg(goal_id ORDER BY goal_id), ARRAY[]::text[]) INTO v_elig2
    FROM public.goal_funding_snapshots
   WHERE model_year = p_model_year AND week_num = v_open_wk AND source = 'opening_anchor';
  IF v_elig2 IS DISTINCT FROM v_elig THEN
    RAISE EXCEPTION 'opening state of plan % changed while locking; retry', p_model_year; END IF;

  -- ── STEP 3  post-lock state reads ──
  SELECT count(*) INTO v_reg_cnt FROM public.goal_registry WHERE id = ANY(v_elig);
  IF v_reg_cnt <> v_n THEN RAISE EXCEPTION 'eligible-set registry drift: % of % present', v_reg_cnt, v_n; END IF;
  -- archived contradiction (§7.5): a goal tracked in the target week's plan but archived in the registry
  SELECT min(id) INTO v_gid FROM public.goal_registry WHERE id = ANY(v_elig) AND status = 'archived';
  IF v_gid IS NOT NULL THEN
    RAISE EXCEPTION 'archived contradiction: goal % is tracked in plan % but archived in the registry', v_gid, p_model_year; END IF;
  -- the submitted rows must cover exactly R(Y)
  SELECT min(x) INTO v_gid FROM unnest(v_ids) x WHERE NOT (x = ANY(v_elig));
  IF v_gid IS NOT NULL THEN RAISE EXCEPTION 'unexpected/absent goal_id in snapshot rows: % (not tracked in plan %)', v_gid, p_model_year; END IF;
  IF cardinality(v_ids) <> v_n THEN
    RAISE EXCEPTION 'snapshot rows must cover exactly the % goals tracked in plan % (got %)', v_n, p_model_year, cardinality(v_ids); END IF;
  -- p_expected_count is a mandatory client/server cross-check of the server-derived count
  IF p_expected_count IS DISTINCT FROM v_n THEN RAISE EXCEPTION 'p_expected_count must equal % (got %)', v_n, p_expected_count; END IF;

  -- K (§10): complete weeks >= 6 across plan years. Complete = reconciliation present plus a
  -- snapshot for every goal tracked in that week's plan year.
  WITH plans AS (
    SELECT a.model_year, array_agg(a.goal_id) AS ids, count(*) AS n
      FROM public.goal_funding_snapshots a
     WHERE a.source = 'opening_anchor' AND a.week_num = public.opening_week_of_plan(a.model_year)
     GROUP BY a.model_year)
  SELECT array_agg(r.week_num ORDER BY r.week_num) INTO v_k
    FROM public.weekly_reconciliations r
    JOIN plans p ON p.model_year = public.plan_year_of_week(r.week_num)
   WHERE r.week_num >= c_first_closeable
     AND (SELECT count(*) FROM public.goal_funding_snapshots s
           WHERE s.model_year = p.model_year AND s.week_num = r.week_num AND s.goal_id = ANY(p.ids)) = p.n;
  v_k := COALESCE(v_k, ARRAY[]::int[]);
  v_complete_cnt := cardinality(v_k);
  v_max_complete := v_k[v_complete_cnt];
  SELECT min(g) INTO v_gap FROM generate_series(c_first_closeable, COALESCE(v_max_complete, 0)) g WHERE NOT (g = ANY(v_k));

  -- ══ STEP 4  approved_reopen state machine (A–F) ══
  IF p_mode = 'approved_reopen' THEN
    -- A. preconditions: target = latest completed week (global), complete recon + complete snapshots
    IF NOT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num = p_week_num) THEN
      RAISE EXCEPTION 'approved_reopen: week % has no reconciliation', p_week_num; END IF;
    SELECT count(*) INTO v_elig_cnt FROM public.goal_funding_snapshots
      WHERE model_year=p_model_year AND week_num=p_week_num AND goal_id = ANY(v_elig);
    IF v_elig_cnt <> v_n THEN RAISE EXCEPTION 'approved_reopen: week % is not fully closed (% of %)', p_week_num, v_elig_cnt, v_n; END IF;
    IF v_max_complete IS DISTINCT FROM p_week_num THEN
      RAISE EXCEPTION 'approved_reopen: week % is not the latest completed week (latest=%)', p_week_num, v_max_complete; END IF;

    -- B. snapshots never changed by reopen: submitted amounts must equal persisted tracked set
    SELECT count(*) INTO v_diff FROM jsonb_array_elements(v_snap_rows) r
      LEFT JOIN public.goal_funding_snapshots s
        ON s.model_year=p_model_year AND s.week_num=p_week_num AND s.goal_id = r->>'goal_id'
      WHERE s.goal_id IS NULL OR round(s.funded_amount,2) IS DISTINCT FROM (r->>'funded_amount')::numeric;
    IF v_diff <> 0 THEN RAISE EXCEPTION 'approved_reopen may not change snapshot amounts (use Option B)'; END IF;

    -- C. compare submitted reconciliation with persisted
    SELECT chk,sav,amx,tax,lc,balance_basis INTO v_rec FROM public.weekly_reconciliations WHERE week_num=p_week_num;
    IF round(v_rec.chk,2)=round(p_chk,2) AND round(v_rec.sav,2)=round(p_sav,2)
       AND round(v_rec.amx,2)=round(p_amx,2) AND round(v_rec.tax,2)=round(p_tax,2)
       AND round(v_rec.lc,2)=round(p_lc,2) AND v_rec.balance_basis IS NOT DISTINCT FROM p_balance_basis THEN
      -- D. persisted reconciliation ALREADY equals submitted (a retry)
      IF v_empty_arrays THEN
        RETURN jsonb_build_object('ok',true,'mode','approved_reopen','idempotent',true,'week_num',p_week_num,'snapshot_count',v_n);
      ELSE
        RAISE EXCEPTION 'fully closed week %: non-empty commitment resubmission on reopen — re-read and use supervised adjudication', p_week_num
          USING ERRCODE = 'GFA01', HINT = 'REQUIRES_SUPERVISED_ADJUDICATION';
      END IF;
    ELSE
      -- E. genuine reopen: apply once (RECONCILIATION ACTUALS ONLY); empty commitment arrays only.
      IF NOT v_empty_arrays THEN
        RAISE EXCEPTION 'approved_reopen must not carry commitment operations (use the supervised commitment-repair path)'; END IF;
      PERFORM public.save_reconciliation_with_commitments(
        p_week_num => p_week_num, p_model_year => p_model_year,
        p_chk => p_chk, p_sav => p_sav, p_amx => p_amx, p_tax => p_tax, p_lc => p_lc,
        p_balance_basis => p_balance_basis, p_recorded_at => now(),
        p_new_commitments => '[]'::jsonb, p_patched => '[]'::jsonb);
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

  -- ══ STEP 4b  normal_closeout week gate: never at or before the plan's opening position (O2) ══
  IF p_week_num < v_open_wk THEN RAISE EXCEPTION 'week % is legacy pre-anchor, out of snapshot-closeout scope', p_week_num; END IF;
  IF p_week_num = v_open_wk THEN RAISE EXCEPTION 'week % is the opening anchor of plan %; not a normal-closeout write', p_week_num, p_model_year; END IF;

  -- ══ STEP 5  normal_closeout state branch ══
  SELECT EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num = p_week_num) INTO v_has_recon;
  SELECT count(*) INTO v_elig_cnt FROM public.goal_funding_snapshots
    WHERE model_year=p_model_year AND week_num=p_week_num AND goal_id = ANY(v_elig);
  v_branch := CASE WHEN NOT v_has_recon AND v_elig_cnt >= 1 THEN 'corrupt'
                   WHEN NOT v_has_recon THEN 'new'
                   WHEN v_elig_cnt = v_n THEN 'closed'
                   ELSE 'repair' END;

  IF v_branch = 'corrupt' THEN
    -- branch H: snapshots without reconciliation → corrupt
    RAISE EXCEPTION 'corrupt state: snapshots without reconciliation at week %', p_week_num;
  END IF;
  -- proven global contiguity (§10): a gap makes every normal closeout raise, naming the gap; only
  -- the half-close repair of the earliest incomplete week proceeds.
  IF v_branch IN ('new','closed') AND v_gap IS NOT NULL THEN
    RAISE EXCEPTION 'closed weeks are not contiguous: week % is incomplete below completed week %; repair it first', v_gap, v_max_complete; END IF;
  IF v_branch = 'new' THEN
    -- branch E sequence: exactly the next closeable week.
    IF p_week_num <> c_first_closeable + v_complete_cnt THEN
      RAISE EXCEPTION 'week % is not the next contiguous closeout week (expected %)', p_week_num, c_first_closeable + v_complete_cnt; END IF;
  ELSIF v_branch = 'repair' THEN
    -- branch G sequence: the target is the earliest incomplete week (every earlier week complete).
    IF (SELECT count(*) FROM unnest(v_k) w WHERE w < p_week_num) <> (p_week_num - c_first_closeable) THEN
      RAISE EXCEPTION 'earlier post-anchor week incomplete — repair the earliest gap first (complete=%, expected %)',
        (SELECT count(*) FROM unnest(v_k) w WHERE w < p_week_num), p_week_num - c_first_closeable; END IF;
  END IF;

  -- ══ STEP 5b  first-close re-verification (§7.4, §10; v2.1 OD-3 scope: new close and half-close
  --    repair of plan Y's first closeable week, Y >= 2027; never an idempotent retry or a reopen) ══
  IF p_model_year >= 2027 AND p_week_num = v_open_wk + 1 AND v_branch IN ('new','repair') THEN
    -- OD-4 step 5: share-lock exactly the R(Y-1) registry rows the verification relies on, in identifier order.
    SELECT COALESCE(array_agg(goal_id ORDER BY goal_id), ARRAY[]::text[]) INTO v_prev
      FROM public.goal_funding_snapshots
     WHERE model_year = p_model_year - 1 AND week_num = public.opening_week_of_plan(p_model_year - 1) AND source = 'opening_anchor';
    PERFORM 1 FROM public.goal_registry WHERE id = ANY(v_prev) ORDER BY id FOR SHARE;
    -- OD-4 step 6: IP-2 to IP-6, from the database only.
    FOR v_a IN SELECT goal_id, funded_amount, note FROM public.goal_funding_snapshots
                WHERE model_year = p_model_year AND week_num = v_open_wk AND source = 'opening_anchor' ORDER BY goal_id LOOP
      -- anchor-note grammar (§7.4): new | carry:<id> | carry:<id>;reason=<text>
      IF v_a.note = 'new' THEN
        v_pred := NULL; v_reason := NULL;
      ELSIF v_a.note ~ '^carry:[a-z0-9_]+$' THEN
        v_pred := substring(v_a.note FROM '^carry:([a-z0-9_]+)$'); v_reason := NULL;
      ELSIF v_a.note ~ '^carry:[a-z0-9_]+;reason=[^\r\n]*[^[:space:]][^\r\n]*$' THEN  -- the reason must not be blank
        v_pred := substring(v_a.note FROM '^carry:([a-z0-9_]+);reason='); v_reason := substring(v_a.note FROM ';reason=([^\r\n]+)$');
      ELSE
        RAISE EXCEPTION 'first-close re-verification: the opening anchor note of % is outside the anchor-note grammar', v_a.goal_id;
      END IF;
      -- IP-2 (first-close form): the anchor's goal exists in the registry and is not archived
      SELECT status INTO v_status FROM public.goal_registry WHERE id = v_a.goal_id;
      IF NOT FOUND OR v_status = 'archived' THEN
        RAISE EXCEPTION 'first-close re-verification (IP-2): goal % is missing or archived', v_a.goal_id; END IF;
      -- IP-3: no anchor's goal has any plan Y-1 snapshot
      IF EXISTS (SELECT 1 FROM public.goal_funding_snapshots WHERE model_year = p_model_year - 1 AND goal_id = v_a.goal_id) THEN
        RAISE EXCEPTION 'first-close re-verification (IP-3): % has a plan % snapshot', v_a.goal_id, p_model_year - 1; END IF;
      IF v_pred IS NOT NULL THEN
        -- IP-4: a successor names only a goal tracked in plan Y-1, and at most one successor names it
        IF NOT (v_pred = ANY(v_prev)) THEN
          RAISE EXCEPTION 'first-close re-verification (IP-4): % names %, which is not tracked in plan %', v_a.goal_id, v_pred, p_model_year - 1; END IF;
        IF v_pred = ANY(v_preds) THEN
          RAISE EXCEPTION 'first-close re-verification (IP-4): % is carried by more than one successor', v_pred; END IF;
        v_preds := array_append(v_preds, v_pred);
        -- IP-5: the carried opening value equals the predecessor's final plan Y-1 value (week
        -- openingWeekOfPlan(Y)), unless the note states a reason
        SELECT funded_amount INTO v_final FROM public.goal_funding_snapshots
         WHERE model_year = p_model_year - 1 AND week_num = v_open_wk AND goal_id = v_pred;
        IF v_final IS NULL THEN
          RAISE EXCEPTION 'first-close re-verification (IP-5): % has no final plan % value at week %', v_pred, p_model_year - 1, v_open_wk; END IF;
        IF v_reason IS NULL AND round(v_a.funded_amount,2) IS DISTINCT FROM round(v_final,2) THEN
          RAISE EXCEPTION 'first-close re-verification (IP-5): % opens at % but % ended plan % at %, with no stated reason',
            v_a.goal_id, round(v_a.funded_amount,2), v_pred, p_model_year - 1, round(v_final,2); END IF;
      END IF;
    END LOOP;
    -- IP-4 and IP-6: every plan Y-1 tracked goal is carried or closed, never both, never neither
    FOR v_a IN SELECT id, status FROM public.goal_registry WHERE id = ANY(v_prev) ORDER BY id LOOP
      IF v_a.id = ANY(v_preds) THEN
        IF v_a.status IN ('executed','archived') THEN
          RAISE EXCEPTION 'first-close re-verification (IP-4): % is both carried and closed (status %)', v_a.id, v_a.status; END IF;
      ELSIF v_a.status IS NULL OR v_a.status NOT IN ('executed','archived') THEN
        RAISE EXCEPTION 'first-close re-verification (IP-4/IP-6): % is neither carried nor closed (status %)', v_a.id, v_a.status;
      END IF;
    END LOOP;
    IF cardinality(v_prev) <> (SELECT count(*) FROM public.goal_registry WHERE id = ANY(v_prev)) THEN
      RAISE EXCEPTION 'first-close re-verification (IP-4): a plan % tracked goal is missing from the registry', p_model_year - 1; END IF;
  END IF;

  IF v_branch = 'new' THEN
    -- MONOTONIC non-decrease: each submitted funded_amount must be >= the latest EFFECTIVE prior
    -- snapshot of that goal in this plan year (max week < target, ANY source, including the
    -- opening anchor). A decrease hard-stops → supervised correction path (Option B).
    FOR v_row IN SELECT * FROM jsonb_array_elements(v_snap_rows) LOOP
      SELECT funded_amount INTO v_amt FROM public.goal_funding_snapshots
        WHERE model_year=p_model_year AND goal_id=v_row->>'goal_id' AND week_num < p_week_num
        ORDER BY week_num DESC LIMIT 1;
      IF v_amt IS NULL THEN
        RAISE EXCEPTION 'broken snapshot chain: % has no effective prior snapshot before week % (anchor incomplete?)', v_row->>'goal_id', p_week_num; END IF;
      IF round((v_row->>'funded_amount')::numeric,2) < round(v_amt,2) THEN
        RAISE EXCEPTION 'monotonic violation: % submitted % < prior effective % (use the correction path)',
          v_row->>'goal_id', (v_row->>'funded_amount')::numeric, v_amt; END IF;
    END LOOP;
    -- reconciliation first (recorded_at=NOW() by the deployed RPC; now() passed for compatibility)
    PERFORM public.save_reconciliation_with_commitments(
      p_week_num => p_week_num, p_model_year => p_model_year,
      p_chk => p_chk, p_sav => p_sav, p_amx => p_amx, p_tax => p_tax, p_lc => p_lc,
      p_balance_basis => p_balance_basis, p_recorded_at => now(),
      p_new_commitments => p_new_commitments, p_patched => p_patched);
    -- then snapshots (source pinned reconciliation)
    PERFORM public.save_goal_funding_snapshots(p_model_year => p_model_year, p_week_num => p_week_num, p_rows => v_snap_rows);
    -- read-back: exactly the tracked set present with the submitted values
    SELECT count(*) INTO v_diff FROM jsonb_array_elements(v_snap_rows) r
      LEFT JOIN public.goal_funding_snapshots s
        ON s.model_year=p_model_year AND s.week_num=p_week_num AND s.goal_id=r->>'goal_id'
      WHERE s.goal_id IS NULL OR round(s.funded_amount,2) IS DISTINCT FROM (r->>'funded_amount')::numeric;
    IF v_diff <> 0 THEN RAISE EXCEPTION 'normal closeout post-write read-back mismatch'; END IF;
    RETURN jsonb_build_object('ok',true,'mode','normal_closeout','week_num',p_week_num,'snapshot_count',v_n);

  ELSIF v_branch = 'closed' THEN
    -- branch F: FULLY CLOSED — identity (empty arrays only) / adjudication / hard stop
    SELECT chk,sav,amx,tax,lc,balance_basis INTO v_rec FROM public.weekly_reconciliations WHERE week_num=p_week_num;
    SELECT count(*) INTO v_diff FROM jsonb_array_elements(v_snap_rows) r
      LEFT JOIN public.goal_funding_snapshots s
        ON s.model_year=p_model_year AND s.week_num=p_week_num AND s.goal_id=r->>'goal_id'
      WHERE s.goal_id IS NULL OR round(s.funded_amount,2) IS DISTINCT FROM (r->>'funded_amount')::numeric;
    IF round(v_rec.chk,2)=round(p_chk,2) AND round(v_rec.sav,2)=round(p_sav,2)
       AND round(v_rec.amx,2)=round(p_amx,2) AND round(v_rec.tax,2)=round(p_tax,2)
       AND round(v_rec.lc,2)=round(p_lc,2) AND v_rec.balance_basis IS NOT DISTINCT FROM p_balance_basis
       AND v_diff = 0 THEN
      IF v_empty_arrays THEN
        RETURN jsonb_build_object('ok',true,'mode','normal_closeout','idempotent',true,'week_num',p_week_num,'snapshot_count',v_n);
      ELSE
        RAISE EXCEPTION 'fully closed week %: non-empty commitment resubmission — re-read and use supervised adjudication', p_week_num
          USING ERRCODE = 'GFA01', HINT = 'REQUIRES_SUPERVISED_ADJUDICATION';
      END IF;
    ELSE
      RAISE EXCEPTION 'week % already fully closed with different values — route to supervised reopen/correction', p_week_num;
    END IF;

  ELSE
    -- branch G: HALF-CLOSE REPAIR (has recon, some tracked snapshots missing)
    IF NOT v_empty_arrays THEN RAISE EXCEPTION 'half-close repair requires empty commitment arrays'; END IF;
    SELECT chk,sav,amx,tax,lc,balance_basis INTO v_rec FROM public.weekly_reconciliations WHERE week_num=p_week_num;
    IF NOT (round(v_rec.chk,2)=round(p_chk,2) AND round(v_rec.sav,2)=round(p_sav,2)
       AND round(v_rec.amx,2)=round(p_amx,2) AND round(v_rec.tax,2)=round(p_tax,2)
       AND round(v_rec.lc,2)=round(p_lc,2) AND v_rec.balance_basis IS NOT DISTINCT FROM p_balance_basis) THEN
      RAISE EXCEPTION 'half-close repair: submitted reconciliation differs from persisted (that is a reopen)'; END IF;
    -- each PRESENT tracked row must equal the submitted amount (else correction anomaly); preserve source/note
    SELECT count(*) INTO v_diff FROM jsonb_array_elements(v_snap_rows) r
      JOIN public.goal_funding_snapshots s
        ON s.model_year=p_model_year AND s.week_num=p_week_num AND s.goal_id=r->>'goal_id'
      WHERE round(s.funded_amount,2) IS DISTINCT FROM (r->>'funded_amount')::numeric;
    IF v_diff <> 0 THEN RAISE EXCEPTION 'half-close repair: a present eligible row differs — correction anomaly (use Option B)'; END IF;
    -- write ONLY the missing tracked rows (source reconciliation). Recon RPC NOT called → recorded_at unchanged.
    SELECT jsonb_agg(r) INTO v_snap_rows FROM jsonb_array_elements(v_snap_rows) r
      WHERE NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots s
                          WHERE s.model_year=p_model_year AND s.week_num=p_week_num AND s.goal_id=r->>'goal_id');
    IF v_snap_rows IS NULL OR jsonb_array_length(v_snap_rows) = 0 THEN
      RAISE EXCEPTION 'half-close repair: no missing rows computed (inconsistent state)'; END IF;
    FOR v_row IN SELECT * FROM jsonb_array_elements(v_snap_rows) LOOP
      SELECT funded_amount INTO v_amt FROM public.goal_funding_snapshots
        WHERE model_year=p_model_year AND goal_id=v_row->>'goal_id' AND week_num < p_week_num
        ORDER BY week_num DESC LIMIT 1;
      IF v_amt IS NULL THEN
        RAISE EXCEPTION 'half-close repair broken chain: % has no effective prior before week %', v_row->>'goal_id', p_week_num; END IF;
      IF round((v_row->>'funded_amount')::numeric,2) < round(v_amt,2) THEN
        RAISE EXCEPTION 'half-close repair monotonic violation: % % < prior effective % (correction path)',
          v_row->>'goal_id', (v_row->>'funded_amount')::numeric, v_amt; END IF;
    END LOOP;
    PERFORM public.save_goal_funding_snapshots(p_model_year => p_model_year, p_week_num => p_week_num, p_rows => v_snap_rows);
    SELECT count(*) INTO v_elig_cnt FROM public.goal_funding_snapshots
      WHERE model_year=p_model_year AND week_num=p_week_num AND goal_id = ANY(v_elig);
    IF v_elig_cnt <> v_n THEN RAISE EXCEPTION 'half-close repair read-back: % of %', v_elig_cnt, v_n; END IF;
    RETURN jsonb_build_object('ok',true,'mode','normal_closeout','repaired',true,'week_num',p_week_num,'snapshot_count',v_n);
  END IF;
END $$;

-- ── 8. correct_goal_funding_snapshot ──
CREATE OR REPLACE FUNCTION public.correct_goal_funding_snapshot(
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
  v_open_wk int;
  v_prev int; v_next int;
  v_cur  numeric; v_prev_amt numeric; v_next_amt numeric;
  v_between int; v_cnt int;
BEGIN
  -- STEP 1-6  authorization + pure-input validation (no state read)
  IF NOT public.is_owner() THEN RAISE EXCEPTION 'correction requires owner (is_owner()=false)' USING ERRCODE='42501'; END IF;
  IF p_week_num IS NULL OR p_week_num < 1 THEN RAISE EXCEPTION 'invalid week_num: %', p_week_num; END IF;
  -- 2027 rollover P-Y3 (§6) and the opening position (O2): corrections apply to closeable weeks only.
  IF p_model_year IS NULL OR p_model_year IS DISTINCT FROM public.plan_year_of_week(p_week_num) THEN RAISE EXCEPTION 'invalid model_year: %', p_model_year; END IF;
  v_open_wk := public.opening_week_of_plan(p_model_year);
  IF p_week_num = v_open_wk THEN RAISE EXCEPTION 'no correction at the opening position (week % of plan %); opening anchors are written only by initialization', p_week_num, p_model_year; END IF;
  IF v_open_wk IS NULL OR p_week_num < v_open_wk + 1 THEN RAISE EXCEPTION 'invalid week_num (must be a closeable week of plan %): %', p_model_year, p_week_num; END IF;
  IF p_goal_id IS NULL THEN RAISE EXCEPTION 'goal_id not eligible: <null>'; END IF;
  IF NOT (p_new_funded_amount IS NOT NULL AND p_new_funded_amount <> 'NaN'::numeric AND p_new_funded_amount <> 'Infinity'::numeric AND p_new_funded_amount <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_new_funded_amount must be finite'; END IF;
  IF p_new_funded_amount < 0 THEN RAISE EXCEPTION 'p_new_funded_amount must be >= 0'; END IF;
  IF NOT (p_expected_prior IS NOT NULL AND p_expected_prior <> 'NaN'::numeric AND p_expected_prior <> 'Infinity'::numeric AND p_expected_prior <> '-Infinity'::numeric) THEN RAISE EXCEPTION 'p_expected_prior must be finite'; END IF;
  IF p_expected_prior < 0 THEN RAISE EXCEPTION 'p_expected_prior must be >= 0'; END IF;
  IF p_note IS NULL OR btrim(p_note) = '' THEN RAISE EXCEPTION 'p_note must be non-empty'; END IF;

  -- STEP 7  year/week advisory lock; 7b per-goal registry mutex (assert the row was locked)
  PERFORM pg_advisory_xact_lock(1734501000, p_model_year * 100 + p_week_num);
  PERFORM 1 FROM public.goal_registry WHERE id = p_goal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'goal_registry row for % not found/locked (registry drift)', p_goal_id; END IF;
  -- 2027 rollover: eligibility is R(p_model_year), the goals with an opening anchor for the plan (§7.1).
  IF NOT EXISTS (SELECT 1 FROM public.goal_funding_snapshots WHERE model_year = p_model_year AND week_num = v_open_wk
                   AND source = 'opening_anchor' AND goal_id = p_goal_id) THEN
    RAISE EXCEPTION 'goal_id not eligible: % (not tracked in plan %)', p_goal_id, p_model_year; END IF;
  -- Archived contradiction (§7.5): a goal tracked in the plan but archived in the registry fails closed.
  IF EXISTS (SELECT 1 FROM public.goal_registry g JOIN public.goal_funding_snapshots a ON a.goal_id = g.id
              WHERE a.model_year = p_model_year AND a.week_num = v_open_wk AND a.source = 'opening_anchor' AND g.status = 'archived') THEN
    RAISE EXCEPTION 'archived contradiction: a goal tracked in plan % is archived in the registry', p_model_year; END IF;

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

COMMIT;
