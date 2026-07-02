# Phase 5F-1 — Cash Commitment Capture + Cash Availability Engine
**Version:** 3.12 (surgical final correction — two stale ACs fixed, no redesign: AC-97 rewritten from the abandoned v3.9 "Skip / not due stages no row, re-prompted later" behavior to the current invariant that no Phase 2 branch for a protected WD obligation may silently stage zero rows, matching AC-108; AC-87's save-patch expected error string corrected to the round-5 "non-terminal commitment (status=initiated)" guard wording, matching AC-43/AC-102/AC-103; 116 ACs)  
**Status:** Build-ready. `available_balance` retained in 5F-1 scope; posted/current balance is the recommended default for Wendy's first live use.  
**Gate:** Must follow 5E-7 (Role Enforcement) and 5E-8 (7/1 Wendy Readiness)  
**Author:** Adam Herndon + Claude  
**Date:** 2026-06-30  

---

## v3.12 Changelog (surgical final correction, from the final adversarial review)

Not a hardening round and not a redesign — two stale acceptance criteria corrected so the "all 116 ACs pass" build gate is internally consistent. No SQL, engine, RPC, schema, or UI-behavior change. `available_balance` stays in scope.

1. **AC-97 was stale and contradicted AC-108 (the material fix).** It still asserted the abandoned v3.9 behavior: "Skip / not due" stages no row and the WD event is re-prompted in a future week. v3.10 removed that behavior (a week-N WD event does not reappear in week N+1 — `eid` bakes the model week into identity), renaming the branch to "WD event doesn't apply this week (mismatch)" and staging an auditable `voided`/`voided` row with mandatory `resolution_notes`. Rewritten to assert the current invariant: no Phase 2 branch for a `protected_required` WD obligation may silently stage zero rows. Now consistent with AC-108, the Phase 2 payload table, and the v3.10/v3.11 body text.
2. **AC-87's save-patch expected error string was stale.** It cited the pre-round-5 wording "reflected_model_week (5) on active-status commitment must equal p_week_num=3." The guard's actual message became "reflected_model_week (5) on non-terminal commitment (status=initiated) must equal p_week_num=3 ..." when round 5 switched the guard from an explicit active-status list to `status NOT IN ('cleared','voided')`. AC-43 was rewritten in v3.11; AC-87 was missed. Corrected so AC-87, AC-43, AC-102, and AC-103 all assert the same message for the same guard.

Verification performed after the edits: `grep -c '^### AC-'` = 116 (unchanged, both fixes were in-place rewrites); no AC still asserts "Skip / not due" or "stages no row" as current behavior (remaining hits are historical changelog narrative); no AC still asserts the stale "on active-status commitment" error string; no AC contradicts AC-108 or the non-terminal reflected-week guard.

---

## v3.11 Changelog (round 6 hardening, from v3.10 review — intended as the final review pass)

1. **resolution_notes is now genuinely server-required for voided/voided rows**, not just client-side. v3.10 described the Phase 2 mismatch row as having "mandatory resolution_notes," but the RPC insert/patch paths never actually enforced it — a client bug could still produce a `voided`/`voided` row with null notes, silently defeating the entire point of replacing "no row" with "auditable row." `validate_commitment_state` gained a `p_resolution_notes` parameter (12th, `DEFAULT NULL`) and now rejects `resolution_type='voided'` with null or whitespace-only `resolution_notes`, wired through all four insert/patch call sites in both RPCs. `paid_from_other_account` stays exempt. Because the rule lives inside the canonical validator rather than as an insert-time-only check, it also blocks a later attempt to blank out `resolution_notes` on an already-voided row — a side effect worth having, not originally asked for. This also means the rule is **not** scoped to only the new Phase 2 branch: it applies equally to Phase 1's plain "Void" response, which was exactly as under-audited before this pass.
2. **AC-43 was stale** — it described a patch guard behavior (`reflected_model_week` on a non-terminal row passing through unvalidated) that stopped being true once round 3 added the non-terminal week guard and round 5 closed the `carried_unresolved` gap in it. Rewritten to match current behavior, with an explicit note on why the old version was wrong and since when.
3. **Two more ACs (AC-57, AC-92) were quietly broken by the same round-5 change**, found during this round's audit rather than reported externally: both staged a `status:"voided", resolution_type:"voided"` patch with no `resolution_notes`, which the new requirement (item 1 above) would now reject before either AC could demonstrate what it actually set out to test. Both payloads corrected.
4. **Scope's Dashboard bullet was stale** — still said Review Required fires only on "unknown basis + active reserves," which stopped being the complete rule in v3.8 (AC-79) and v3.10 (AC-105–107) once the `bank_pending`-reserve trigger was added. Corrected to state both conditions.
5. AC count grew from 109 to 116.

This round's process note: three of six new-behavior findings this round (items 1, 3) were self-audit results, not externally reported — a deliberate check of "does this new rule break any AC that predates it," applied specifically because that exact failure mode (a new guard silently invalidating an old AC's example payload) had already happened once with AC-43. Recommend this specific check — "for every new validation rule added, grep the AC section for payloads that would now hit it" — become a standing step for any future changes to this spec, not just this round's.

---

## v3.10 Changelog (round 5 hardening, from v3.9 review)

Two of these four are direct fallout from the v3.8 balance-basis matrix — the third round in a row where fixing available_balance has surfaced a new edge case. See the deep-analysis note at the end of this document for what that pattern implies about scope.

1. **carried_unresolved was missing from the live reflected-week guard.** v3.9's patch-path guard enumerated active statuses explicitly (`'planned','scheduled','initiated','bank_pending','stale_review'`) and silently omitted `carried_unresolved` — so a Phase 1 "Amount changed" patch that forgot to also send `reflected_model_week:null` could leave a stale reflected week on a `carried_unresolved` row unvalidated, keeping its reserve incorrectly off. Fixed by switching the guard from an explicit list to `status NOT IN ('cleared','voided')`, matching the phrasing already used on the insert-path guard one section above — this closes the immediate bug and removes the entire bug *class* (a status list someone has to remember to keep in sync), rather than just adding one more name to the list. A full audit of every other status enumeration in this spec (see deep-analysis note at the end of this document) found no other instance of the same pattern.
2. **Phase 2's "Bank pending" branch could still double-subtract under available_balance.** v3.9 denied it the reflection follow-up on the theory that `bank_pending` was already a maximal-uncertainty state, borrowing the reasoning from Phase 1's "Cleared + not sure." That analogy was wrong: Phase 2's "Bank pending" is the user stating a known fact (this transaction shows pending), not expressing uncertainty — and many banks' available balances already net out pending transactions. Bank pending now gets the same three-way reflection follow-up as every other non-terminal Phase 2 branch.
3. **"Skip / not due this week" could silently drop a protected obligation.** v3.9 staged no row and asserted the WD event would "be re-prompted in a future week" — a claim not actually supported by the WD Event Tagging format documented in this same spec, where the model week is baked into the event's identity (`{model_year}mw{model_week}_...`), not a rolling pointer. Renamed to "WD event doesn't apply this week (mismatch)" and changed to require an actual `voided` row with mandatory `resolution_notes`, so a `protected_required` obligation (Amex, rent, tax transfer) can never disappear with a single click and no audit trail.
4. Corrected inverted wording in the `chk_cleared_reflected_before_resolved` explanatory note (no behavior change — the check itself was always correct).
5. AC count grew from 101 to 109.

---

## v3.9 Changelog (round 4 hardening, from v3.8 review)

v3.8 fixed the available_balance double-subtraction risk but, in doing so, introduced a new gap of its own: decoupling `reflected_model_week` from `status` meant a row could become non-reserved while still being operationally unresolved, and Phase 1's `isReservedAsOf()`-based source filter had no way to know the difference. This pass fixes that, plus three smaller but real gaps:

1. **Phase 1 source query fix (the substantive one).** Changed from `isReservedAsOf(c, current_week - 1)` to `origin_model_week < current_week AND status NOT IN ('cleared','voided') AND resolved_model_week IS NULL` — reflected-but-unresolved items no longer silently disappear from the reconciliation workflow. Added a `reserveActive` display flag (still `isReservedAsOf()`, now used for UI context rather than as the filter), a new "hold fell off" response that explicitly nulls `reflected_model_week` back out (using the pre-existing key-present-null patch mechanism, no RPC change needed), and a new no-op "still accurate" acknowledgment so Phase 1's save-gate means "every row has an explicit response," not "every row reached a terminal status" — the latter would have been actively wrong for an item that's supposed to sit in reflected-but-not-yet-cleared state for multiple weeks.
2. `validate_commitment_state` now rejects `cleared` rows where `reflected_model_week > resolved_model_week` — unreachable through `save_reconciliation_with_commitments` (its terminal week guards already force both fields equal), but reachable through `repair_commitments_for_week`, which allows independent values for exactly the reason repair exists. Backed with a matching table `CHECK` constraint, `chk_cleared_reflected_before_resolved`.
3. Phase 2 gained an explicit payload table (status / reflected / resolved / resolution_type / commitment_source / reflection-follow-up-applies?) for all seven response branches, including a "Skip / not due" branch that stages no row at all — this was previously left to prose and implementation memory.
4. Malformed-patch handling (accepted in round 3 as "no pre-cast validation on patch paths") now has explicit ACs proving the safety net that was always architecturally true but never tested: a cast failure anywhere in either RPC aborts the entire call atomically — including the `weekly_reconciliations` upsert and any earlier-in-the-same-call inserts/patches — and the client's existing "show error, keep form open, don't refresh" path means no partial write is ever presented as saved.
5. AC count grew from 87 to 101.

---

## v3.8 Changelog (round 3 hardening, from v3.7 review)

v3.7 closed the NULL-bypass and ownership-boundary gaps. This pass closes the one functional gap (balance-basis double-subtraction) plus remaining validator/documentation gaps:

1. **Balance-Basis Decision Matrix** (the substantive fix): Phase 0's `available_balance` basis previously had no defined relationship to reservation logic, creating a real double-subtraction risk — an available balance commonly already nets out pending debits before they post, so reserving them anyway would subtract twice. Added an explicit two-step decision flow for Phase 1 (clearance question, then a reflection question scoped to `available_balance` + non-terminal outcomes) and the equivalent for Phase 2/3 new commitments and repair's historical backfill. No engine or schema change was needed — `isReservedAsOf()` already treats `reflected_model_week` as authoritative independent of `status` — but the RPC layer needed a new guard: `save_reconciliation_with_commitments` now rejects `reflected_model_week` on an active-status row unless it equals `p_week_num`, so the "already reflected" claim can't be backdated or misattributed to a different week. `repair_commitments_for_week` is intentionally exempt, since recording that a commitment was reflected in a *different* week's balance than the one being repaired is exactly what repair is for.
2. `Review Required` no longer depends solely on `balance_basis === 'unknown'` — it now also fires whenever any actively-reserved commitment has `status = 'bank_pending'`, regardless of basis, since `bank_pending` is the shared "genuine uncertainty" signal for both "not sure if cleared" and "not sure if already reflected."
3. `validate_commitment_state` rejects `NULL` `affects_deployable_cash` explicitly (currently unreachable through the two production RPCs, since both already default it via `COALESCE` and the column is `NOT NULL`, but the helper is the canonical validator and is called directly by several ACs).
4. `validate_commitment_state` now requires `resolution_type = 'amount_changed'` to carry a real audit trail: `original_amount_cents` must be present and different from `amount_cents`.
5. `validate_commitment_state` gained a `p_cleared_date` parameter (default `NULL`, so existing illustrative calls without it are unaffected) and rejects a non-null `cleared_date` on any non-`cleared` status — `cleared_date` was previously a free-floating field with no consistency check.
6. Repair's terminal-row mutability (already true behaviorally since v3.6) is now explicit spec prose plus an AC: `repair_commitments_for_week` may revise terminal historical rows, but only within `origin_model_week = p_week_num`, `FOR UPDATE`, row-count validation, and post-merge `validate_commitment_state()` — it is not a backdoor to an arbitrary week's terminal row.
7. Both RPCs' insert paths gained pre-cast format validation for `model_year`, `origin_model_week`, `amount_cents`, `original_amount_cents`, `reflected_model_week`, `resolved_model_week`, and `affects_deployable_cash` — clean RPC errors instead of raw Postgres cast exceptions. Deliberately **not** extended to the patch paths — flagged as a scoping call, not an oversight; see the rationale comment at the insert-path validation block.
8. AC count grew from 76 to 87.

---

## v3.7 Changelog (round 2 hardening, from v3.6 review)

v3.6 closed the audit-field spoofing and locking gaps. This pass closes the remaining NULL-bypass and ownership-boundary issues:

1. Every RPC-level parameter check that used a bare `<>`, `NOT IN`, or `NOT BETWEEN` comparison now explicitly rejects `NULL` first — those comparisons evaluate to `NULL` (not `TRUE`) against a `NULL` operand in SQL, so the original checks silently passed a `NULL` through. Applies to `p_model_year`, `p_week_num`, `p_balance_basis` (save) and `p_model_year`, `p_week_num` (repair — `p_balance_basis` stays legitimately optional there).
2. `jsonb_typeof(...) <> 'array'` is replaced with `jsonb_typeof(...) IS DISTINCT FROM 'array'` for `p_new_commitments` and `p_patched` in both RPCs — `jsonb_typeof('null'::jsonb)` returns SQL `NULL`, which the old comparison couldn't catch.
3. `commitment_source` and `source_account` now distinguish "key absent" (defaults) from "key present but empty string" (rejected) in both insert paths — previously both cases silently defaulted, which let a caller send `commitment_source: ''` and get `wd_reconciliation` instead of an error.
4. `recorded_at` is now server-owned (`NOW()`), matching the `resolved_at`/`resolved_by` treatment from v3.6. `p_recorded_at` remains a required, validated-non-null parameter so the caller must signal a genuine reconciliation event, but its value is no longer written.
5. `original_amount_cents` can no longer be explicitly set by the client in `save_reconciliation_with_commitments` patches — only auto-preserved. `repair_commitments_for_week` keeps the client-settable path, since historical correction legitimately needs to backfill a known prior amount.
6. `validate_commitment_state` now validates `origin_model_week` directly (rejects `NULL` and out-of-range), rather than depending on both RPCs to have already checked it correctly.
7. The 837-vs-832 regression test count mismatch is resolved: build sequence now cites 832 as the grep-verified baseline and instructs re-verification immediately before build.
8. AC count grew from 67 to 76 to cover the round-2 hardening items.

---

## v3.6 Changelog (hardening pass, from v3.5 review)

v3.5 was cash-model-correct but left audit/control gaps. This pass closes them:

1. `resolved_at`/`resolved_by` are now fully server-derived on every insert and patch path in both RPCs. Neither RPC reads `resolved_at` or `resolved_by` from the JSON payload anywhere. On insert, they populate when the row lands in a resolved state (`cleared`/`voided`/`carried_unresolved`, or a non-null `resolution_type`/`resolved_model_week`). On patch, the same condition triggers `COALESCE(existing, NOW()/auth.uid())` so a legitimate transition is never left unaudited because the client omitted the keys, and a client can never spoof either field.
2. Terminal immutability guard in `save_reconciliation_with_commitments` now also blocks `resolved_at` and `resolved_by` on `cleared`/`voided` rows. Only `notes` and `resolution_notes` are patchable on terminal rows — audit fields included.
3. Both patch prefetches (`save_reconciliation_with_commitments` and `repair_commitments_for_week`) now use `SELECT ... FOR UPDATE` to lock the row before merge, closing a read-then-write race on concurrent patches.
4. `source_account` is validated against `'truist_checking'` in both insert paths (RPC-level `RAISE EXCEPTION`) and enforced at the table level with a `CHECK` constraint, since 5F-1 supports exactly one source account and a typo previously would have created a commitment that never reserves cash.
5. Patch paths in both RPCs now auto-preserve `original_amount_cents` the first time `amount_cents` changes, and normalize `resolution_type='amount_changed'` when an amount edit resolves a row to `carried_unresolved` — see AC-66 for the scoping decision on when normalization does and does not apply.
6. `repair_commitments_for_week`'s patch path picked up the same `source_account`, audit-ownership, row-locking, and amount-preservation treatment as the save path (it previously had no prefetch at all).
7. AC count grew from the v3.5 placeholder of 55 to 67 — the hardening pass surfaced 16 distinct testable behaviors and combining them into 2 ACs would have under-tested the change. See AC-54 through AC-67.

---

## Problem Statement

The OS overstates deployable surplus when a known required outflow is initiated or pending but has not yet reduced the Truist Checking balance.

**Week 25 / Model Week 3 (Jun 21–27) — exact facts:**

| Item | Value |
|---|---|
| Actual Truist Checking (6/27 reconciliation) | $23,133.88 |
| Operating floor | $6,500.00 |
| Amex Platinum initiated — not yet cleared Truist | $6,368.48 |
| Raw surplus above floor (informational only) | $16,633.88 |
| Correct adjusted available checking | $16,765.40 |
| **Correct adjusted deployable surplus (operational)** | **$10,265.40** |

**Critical invariant:**

```
Before Amex clears:   actualChecking=$23,133.88 | reserve=$6,368.48 | adjustedDeployable=$10,265.40
After Amex clears:    actualChecking=$16,765.40  | reserve=$0        | adjustedDeployable=$10,265.40
```

---

## Scope

### In scope (5F-1)

- `cash_commitments` table — SELECT only to authenticated; all writes via SECURITY DEFINER RPCs
- `balance_basis` on `weekly_reconciliations`
- WD event tagging (`eid`, `cc`, `rod`)
- `PLAN_YEAR`, `isReservedAsOf()`, `getCashAvailabilityEngine()`, `validate_commitment_state()`
- `runModel()` — reconciled/projected distinction, `reconciledWeeks` carry-forward guard, `remainingAdjustedSweep`
- `save_reconciliation_with_commitments()` RPC — inserts scoped to p_week_num, terminal week guards, terminal immutability (including audit fields), lifecycle merged-row guard, historical_repair and invalid source rejected, explicit commitment_class/source_account validation, p_recorded_at required (value server-owned), week-scoped patches with FOR UPDATE, reflected_model_week pinned to p_week_num on active-status rows, post-patch merged validation
- `repair_commitments_for_week()` RPC — reconciliation-row guards on inserts AND patch path, explicit commitment_class/source_account validation, week-scoped patches with FOR UPDATE, intentionally permissive on terminal-row correction and cross-week reflected_model_week within its own origin_model_week scope
- Reconciliation form 4-phase flow, repair mode (Historical Phase 2, later-clearance support)
- Dashboard: adjusted deployable, raw=informational, Review Required when unknown basis + active reserves OR any active reserve has status='bank_pending' (see Balance-Basis Decision Matrix)
- 116 ACs
- Preflight, migration, validation, rollback SQL

### Non-goals (must not be touched in production code)

- `budget_transactions`, `budget_line_rules`, category actuals, budget variance
- `runModel()` income or `_getBudgetLivingExpenses()`
- `chk/sav/amx/tax/lc` in `weekly_reconciliations`
- Hard delete of commitment records

---

## DB Migration

### 1. Modify weekly_reconciliations

```sql
ALTER TABLE weekly_reconciliations
  ADD COLUMN IF NOT EXISTS balance_basis TEXT
    CHECK (balance_basis IN ('posted_current_balance','available_balance','unknown'));
```

### 2. cash_commitments table

No `reflected_in_balance` column exists anywhere.

```sql
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
                               -- 5F-1 supports exactly one source account; see chk_source_account_only_truist below
  amount_cents               INT NOT NULL CHECK (amount_cents > 0),
  original_amount_cents      INT CHECK (original_amount_cents IS NULL OR original_amount_cents > 0),
  status                     TEXT NOT NULL DEFAULT 'planned'
                               CHECK (status IN (
                                 'planned','scheduled','initiated','bank_pending',
                                 'cleared','voided','carried_unresolved','stale_review'
                               )),
  affects_deployable_cash    BOOLEAN NOT NULL DEFAULT true,
  reflected_model_week       INT,   -- NULL = not yet reflected. N = reflected in balance entered at Week N.
  due_date                   DATE,
  expected_clear_date        DATE,
  cleared_date               DATE,
  resolved_model_week        INT,   -- NULL = open. N = resolved at Week N.
  resolved_at                TIMESTAMPTZ,
  resolved_by                UUID REFERENCES auth.users(id),
  resolution_type            TEXT
                               CHECK (resolution_type IN (
                                 'cleared','voided','paid_from_other_account',
                                 'amount_changed','carried_unresolved'
                               )),
  resolution_notes           TEXT,
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
    CHECK (status <> 'cleared' OR reflected_model_week IS NULL OR resolved_model_week IS NULL
           OR reflected_model_week <= resolved_model_week)
);
```

`chk_source_account_only_truist` is a hard DB-level backstop, not a substitute for the RPC-level rejection below — the RPC check produces a clean, callable error message (`invalid source_account: %`) before the row ever reaches the constraint; the CHECK exists so a future write path that bypasses the RPCs (there shouldn't be one, but grants can drift) cannot silently create an unreserved commitment.

`chk_cleared_reflected_before_resolved` backs `validate_commitment_state`'s equivalent check the same way — a `cleared` row cannot have `reflected_model_week > resolved_model_week`. Stated correctly: a cleared debit cannot first be reflected *after* it is resolved — reflection must occur at or before resolution, never after. (An earlier draft of this note had the direction backwards; corrected in v3.10.) The `IS NULL` branches exist only so this constraint doesn't fire ahead of the more specific "cleared requires resolved_model_week" / "cleared requires reflected_model_week" checks already enforced elsewhere — a `cleared` row with either field null is already invalid for other reasons.

### 3. Trigger

```sql
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
```

### 4. RLS

SECURITY DEFINER RPCs run as the function owner and bypass RLS (standard PostgreSQL behavior). RLS INSERT/UPDATE policies are defined for documentation intent but are not evaluated by direct REST callers (blocked at grant level).

```sql
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
```

### 5. Table grants — explicit REVOKE then SELECT only

```sql
-- Explicit revoke before grant — do not rely on defaults
REVOKE ALL ON cash_commitments FROM PUBLIC;
REVOKE ALL ON cash_commitments FROM anon;
REVOKE ALL ON cash_commitments FROM authenticated;

-- SELECT only. INSERT/UPDATE blocked — mutations through RPCs only.
GRANT SELECT ON cash_commitments TO authenticated;
```

### 6. validate_commitment_state() — SECURITY INVOKER helper

Does not write tables. Called only by SECURITY DEFINER RPCs. Explicitly validates `p_status` and `p_required_or_discretionary` for null and invalid values before any structural checks.

```sql
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

REVOKE ALL ON FUNCTION validate_commitment_state(
  UUID, TEXT, INT, INT, TEXT, INT, INT, INT, TEXT, BOOLEAN, DATE, TEXT
) FROM PUBLIC;
-- No GRANT — internal helper only. Called by SECURITY DEFINER RPCs.
```

### 7. RPC — save_reconciliation_with_commitments

**Insert path rules:**
- `expected_item_id` must be non-null and non-empty (explicit RPC error, not table NOT NULL failure)
- `origin_model_week` must equal `p_week_num`
- `commitment_source` must be `'wd_reconciliation'` or `'manual_reconciliation'`; `'historical_repair'` is rejected
- `commitment_class` must be one of the seven allowed values (explicit RPC error before table CHECK)
- `source_account` must be `'truist_checking'`; any other value (including empty/typo'd strings) raises an explicit RPC error before the row reaches the `chk_source_account_only_truist` table constraint
- `resolved_at` and `resolved_by` are never read from the payload. They are computed server-side: populated (`NOW()` / `auth.uid()`) when the inserted row's status is `cleared`/`voided`/`carried_unresolved` or it carries a non-null `resolution_type`/`resolved_model_week`; otherwise null. The client cannot spoof either field on insert.
- New cleared commitments: `reflected_model_week` and `resolved_model_week` must both equal `p_week_num`
- New voided commitments: `resolved_model_week` must equal `p_week_num`

**Patch path rules:**
- `origin_model_week <= p_week_num` (scope guard; applied to pre-fetch SELECT and UPDATE WHERE)
- Pre-fetch SELECT uses `FOR UPDATE` — the row is locked before merge, closing the read-then-write race on concurrent patches
- Existing cleared or voided rows: only `notes` and `resolution_notes` may be changed; all other fields are immutable, including `resolved_at` and `resolved_by` — a terminal row cannot have its audit trail rewritten
- Terminal lifecycle transitions (cleared/voided): `reflected_model_week` and `resolved_model_week` on the merged row must equal `p_week_num`
- `resolved_at` and `resolved_by` are never read from the payload on patch either. When the merged row transitions into a resolved state (`cleared`/`voided`/`carried_unresolved`, or a non-null `resolution_type`/`resolved_model_week`), the RPC sets `resolved_at = COALESCE(existing, NOW())` and `resolved_by = COALESCE(existing, auth.uid())` — a legitimate transition is audited even if the client omits the keys, and the client cannot control or spoof either field
- Amount-change handling: if `amount_cents` is patched and differs from the existing amount, `original_amount_cents` is auto-preserved from the pre-patch value the first time (unless the client explicitly supplies `original_amount_cents`). If the amount change resolves the row to `carried_unresolved`, `resolution_type` is normalized to `'amount_changed'` server-side regardless of what the client sent — see AC-66 for why this normalization does not extend to amount edits on still-active rows
- `resolution_type='voided'` requires non-empty `resolution_notes` (enforced in `validate_commitment_state`, not just client-side) — applies to any row landing on plain `voided`/`voided`, whether from Phase 1's "Void" response or Phase 2's "WD event doesn't apply this week"; `paid_from_other_account` remains exempt
- Post-UPDATE: `validate_commitment_state()` on merged RETURNING row; lifecycle merged-row guard if any lifecycle field was patched

```sql
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

REVOKE ALL ON FUNCTION save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_reconciliation_with_commitments(
  INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB
) TO authenticated;
```

### 8. RPC — repair_commitments_for_week

Scope rules:
- Insert path: `expected_item_id` explicit required; `origin_model_week` must equal `p_week_num`; `commitment_class` validated before INSERT; `commitment_source` hardcoded to `'historical_repair'`; `source_account` must be `'truist_checking'` (same RPC-level rejection as save); `resolved_at`/`resolved_by` are server-owned, never read from the payload (same rule as save); `resolution_type='voided'` requires non-empty `resolution_notes` (same rule as save, e.g. repair's "Void / was never owed" option); reconciliation-row existence guards on `reflected_model_week` and `resolved_model_week`
- Patch path: `origin_model_week = p_week_num` (strict); pre-fetch SELECT uses `FOR UPDATE` (repair previously had no prefetch at all — added in this pass); `original_amount_cents` auto-preserved on first amount change (but, unlike save, still explicitly client-settable — see below); `resolved_at`/`resolved_by` server-derived on transitions into a resolved state, never client-controlled; `resolution_type='voided'` requires non-empty `resolution_notes` (same rule as save); post-RETURNING `validate_commitment_state()`; reconciliation-row existence guards on merged row's `reflected_model_week` and `resolved_model_week`

**Terminal-row mutability — explicit statement of intent.** `save_reconciliation_with_commitments` and `repair_commitments_for_week` deliberately differ here, and that difference is load-bearing, not an oversight:

- `save_reconciliation_with_commitments` cannot mutate a `cleared`/`voided` row at all except `notes` and `resolution_notes` — this is live reconciliation, and a terminal row reached through the live flow is final. See the terminal immutability guard in section 7.
- `repair_commitments_for_week` has no equivalent terminal immutability guard, and this is intentional: repair exists specifically to revise historical rows, including rows that are already terminal (e.g. correcting which week an Amex payment actually cleared in, discovered weeks after the fact). Repair may revise a terminal historical row, but only within the same guardrails every repair patch already has — `origin_model_week = p_week_num` (strict equality, so a repair call can only touch rows that originated in the week it's repairing), the `FOR UPDATE` row lock, the `GET DIAGNOSTICS`/`ROW_COUNT` check, and post-merge `validate_commitment_state()` plus the reconciliation-row-existence guards on the merged result. Nothing about "repair can touch terminal rows" relaxes any of those — it only means repair's patch path doesn't add a fifth guard blocking terminal fields specifically.
- Practical implication: a client cannot use `repair_commitments_for_week` as a backdoor to rewrite an arbitrary terminal row from an arbitrary week — the `origin_model_week = p_week_num` scope guard confines every repair call to the one week it declares it's repairing.

```sql
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

REVOKE ALL ON FUNCTION repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB) TO authenticated;
```

---

## WD Event Tagging

Protected outflow events in WD array: `eid` (expected_item_id), `cc` (commitment_class), `rod` (required_or_discretionary). Format: `{model_year}mw{model_week}_{normalized_payee}_{due_date_YYYY_MM_DD}`. Manual items: `crypto.randomUUID()` client-side.

| Payee | cc | rod |
|---|---|---|
| AMEX Platinum, Gold | credit_card_payment | protected_required |
| Disney Visa | credit_card_payment | protected_required |
| Rent (Tiffany Dye) | rent | protected_required |
| Kia payment | bill_payment | protected_required |
| Tax transfers (Vio) | tax_transfer | protected_required |

---

## isReservedAsOf()

```js
function isReservedAsOf(c, weekNum) {
  if (c.model_year !== PLAN_YEAR) return false;
  if (c.origin_model_week > weekNum) return false;
  if (!c.affects_deployable_cash) return false;
  if (c.status === 'voided') return false;
  if (c.resolution_type === 'voided') return false;
  if (c.resolution_type === 'paid_from_other_account') return false;
  if (c.reflected_model_week != null && c.reflected_model_week <= weekNum) return false;
  if (c.resolved_model_week == null) return true;
  return c.resolved_model_week > weekNum;
}
```

| Scenario | reflected_model_week | resolved_model_week | Week 3 | Week 4 |
|---|---|---|---|---|
| Initiated, unresolved | null | null | true | true |
| Cleared at Week 4, reflected Week 4 | 4 | 4 | **true** ✓ | **false** ✓ |
| Bank pending, reflected Week 3 | 3 | null | **false** ✓ | **false** ✓ |
| Still `initiated` (not cleared), but `available_balance` basis already reflected it in Week 3 | 3 | null | **false** ✓ | **false** ✓ |
| status=voided | any | any | **false** ✓ | **false** ✓ |
| resolution_type=paid_from_other_account | any | any | **false** ✓ | **false** ✓ |
| carried_unresolved | null | null | **true** ✓ | **true** ✓ |

The fourth row is the load-bearing scenario for `available_balance` basis: `reflected_model_week` is authoritative independent of `status`, which is exactly why the Balance-Basis Decision Matrix (Reconciliation Form section) can answer "already reflected?" without any change to this function or to `getCashAvailabilityEngine()` — only the reconciliation form's question flow and the RPC-side `reflected_model_week = p_week_num` guard on active-status rows needed to change.

---

## getCashAvailabilityEngine()

```js
function getCashAvailabilityEngine(actualBalanceCents, floorCents, commitments, sourceAccount, modelWeekNum) {
  var reservedProtectedCents = commitments
    .filter(function(c) {
      return c.source_account === sourceAccount && isReservedAsOf(c, modelWeekNum);
    })
    .reduce(function(sum, c) { return sum + c.amount_cents; }, 0);
  return {
    rawSurplusAboveFloorCents:         actualBalanceCents - floorCents,              // informational only
    reservedProtectedCents:            reservedProtectedCents,
    adjustedAvailableCashCents:        actualBalanceCents - reservedProtectedCents,
    adjustedDeployableSurplusCents:    Math.max(0, (actualBalanceCents - reservedProtectedCents) - floorCents)
  };
}
```

Week 3 verification: `adjustedDeployableSurplusCents = 1026540` ($10,265.40) ✓

---

## runModel() Changes

### Constants and state

```js
const PLAN_YEAR = 2026;
var commitmentData = [];
```

### loadAll() addition

```js
fetch(SUPA_URL + '/rest/v1/cash_commitments?model_year=eq.' + PLAN_YEAR + '&select=*', {headers: h})
```

### reconciledWeeks guard (built before week loop)

```js
var _reconciledWeekNums = {};
for (var _rw in reconData) { _reconciledWeekNums[parseInt(_rw, 10)] = true; }
```

### Engine block (inside week loop, after recon override, before waterfall)

```js
// ── Cash Availability Engine ─────────────────────────────────────────────────
var _isReconciled = !!(reconData[num]);
var _caCommitments;
if (_isReconciled) {
  _caCommitments = commitmentData.filter(function(c) {
    return c.source_account === 'truist_checking' && isReservedAsOf(c, num);
  });
} else {
  // Projected: carry-forward only. origin_model_week < num prevents double-reserve with WD.
  // reconciledWeeks guard prevents unreconciled/seed commitments from reducing sweep capacity.
  _caCommitments = commitmentData.filter(function(c) {
    return c.source_account === 'truist_checking'
      && c.origin_model_week < num
      && (_reconciledWeekNums[c.origin_model_week] || c.commitment_source === 'historical_repair')
      && isReservedAsOf(c, num);
  });
}
var _cae = getCashAvailabilityEngine(
  Math.round(chk * 100), Math.round(effFl * 100),
  _caCommitments, 'truist_checking', num
);
var adjustedAvailableForSweep = _cae.adjustedDeployableSurplusCents / 100;
var _balanceBasisUnknown   = _isReconciled && reconData[num].balance_basis === 'unknown';
var _hasActiveReserves     = _caCommitments.length > 0 && _cae.reservedProtectedCents > 0;
// bank_pending is the shared "genuine uncertainty" status for both "not sure if cleared"
// (posted_current_balance) and "not sure if already reflected" (available_balance) — see the
// Balance-Basis Decision Matrix. Either kind of uncertainty on an active reserve triggers
// Review Required, not just an unknown week-level basis.
var _hasBankPendingReserve = _caCommitments.some(function(c) { return c.status === 'bank_pending'; });
var _reviewRequired        = _hasActiveReserves && (_balanceBasisUnknown || _hasBankPendingReserve);
var remainingAdjustedSweep = adjustedAvailableForSweep;
// ────────────────────────────────────────────────────────────────────────────
```

### Waterfall sweep pattern — defensively clamped

```js
var sweepAmt = r(Math.max(0, Math.min(proposedAmt, remainingAdjustedSweep)));
remainingAdjustedSweep = Math.max(0, r(remainingAdjustedSweep - sweepAmt));
```

`chk` is never modified. Raw surplus is informational only. `remainingAdjustedSweep` is guaranteed non-negative after every sweep site regardless of float rounding residue.

---

## Reconciliation Form — 4-Phase Flow

### Phase 0: Balance Basis (required first)

`posted_current_balance` / `available_balance` / `unknown`. Stored in RPC payload. This choice determines how Phase 1 and Phase 2 interpret "is this debit already reflected in the number I'm about to enter" — see the Balance-Basis Decision Matrix immediately below. Getting this wrong is not cosmetic: an `available_balance` figure commonly already nets out pending holds and authorizations, so a debit can be reflected in it well before the debit finally posts. Reserving that debit anyway double-subtracts it — this is the exact failure mode 5F-1 exists to prevent, so the matrix has to be explicit, not left to Phase 1/2 UI improvisation.

### Balance-Basis Decision Matrix

Governs both Phase 1 (existing prior-week commitments) and Phase 2/3 (new current-week commitments).

**`posted_current_balance`** — a posted/current balance never reflects a debit until it has actually cleared the bank. Clearance and "reflection" are the same event; there is no separate question.

| Response | status | reflected_model_week | resolved_model_week | resolution_type |
|---|---|---|---|---|
| Cleared / posted | `cleared` | current_week | current_week | `cleared` |
| Initiated / not yet posted | unchanged (active) | `null` | `null` | — |
| Not sure whether posted | `bank_pending` | `null` | `null` | — |

**`available_balance`** — clearance and reflection are two *separate* questions, because an available balance often already nets out a pending debit before it posts. For any item that is not "Cleared" under the clearance question (i.e. still not cleared, or amount changed), ask a second, independent question: **"Does the balance you're about to enter already reflect this debit?"**

| Response to the reflection question | reflected_model_week | resolved_model_week | Notes |
|---|---|---|---|
| Yes, already reflected | current_week | unchanged from the clearance answer (`null` if not cleared) | Stops the reserve from double-counting this week forward — `isReservedAsOf()` already treats `reflected_model_week` as authoritative independent of `status`, so no schema or engine change was needed for this, only the explicit question |
| No, not reflected | `null` | unchanged from the clearance answer | Reserve stays active — this is the existing default behavior |
| Not sure | `null`, and `status` is forced to `bank_pending` regardless of the clearance answer | unchanged | Conservative reserve stays active; see Review Required below |

The reflection question does **not** apply when the clearance answer was "Cleared" (basis-agnostic — a genuinely cleared/posted debit is reflected in any balance figure taken afterward, posted or available) or "Void" / "Paid from different account" (terminal, not reserved regardless of `reflected_model_week`).

**`unknown`** — always reserve conservatively. Never set `reflected_model_week` on the strength of a guess. `Review Required` fires whenever an unknown-basis week has any active reserve — unchanged from earlier versions.

**Review Required trigger (all bases).** In addition to the existing `balance_basis === 'unknown'` condition, `Review Required` now also fires whenever any actively-reserved commitment for the week has `status === 'bank_pending'`, regardless of basis. `bank_pending` is deliberately reused as the shared "genuine uncertainty" status for both "not sure if it cleared" (`posted_current_balance`) and "not sure if it's already reflected" (`available_balance`) — introducing a second uncertainty concept/column was considered and rejected as unnecessary schema growth for the same underlying meaning ("this reserved item's status is not confidently known"). This is a design call, flagged for your review rather than silently assumed — see v3.8 changelog.

**Server-side enforcement.** The "already reflected" answer is not just a UI convention — `save_reconciliation_with_commitments` now rejects a patch or new-commitment insert that sets `reflected_model_week` on a non-terminal (active-status) row to anything other than `p_week_num`. A live reconciliation call can only assert "reflected in the balance I am entering right now" — it cannot backdate or forward-date reflection for an active row. (`repair_commitments_for_week` is intentionally exempt from this specific constraint — historical repair legitimately needs to record that a Week 3 commitment cleared in Week 4, which is exactly a reflected/resolved week different from `origin_model_week`.) See the insert- and patch-path terminal week guards in sections 7 and the lifecycle merged-row guard.

### Phase 1: Prior Unresolved Commitment Resolution

**Source query (v3.9 fix).** Prior versions sourced Phase 1 from `isReservedAsOf(c, current_week - 1)` — that was correct through v3.7, but v3.8's balance-basis matrix broke it: a v3.8 "already reflected" answer sets `reflected_model_week` on a row whose `status` stays non-terminal (`initiated`, `bank_pending`, `carried_unresolved`). `isReservedAsOf()` correctly returns `false` for that row from a *cash-reserve-math* standpoint — it's no longer counted against deployable cash — but the commitment itself is still operationally unresolved: it hasn't cleared, been voided, or been paid elsewhere. Filtering Phase 1 by `isReservedAsOf()` alone makes that row **disappear from the reconciliation workflow**, with nothing left to ever prompt the user to terminalize it. This was a real gap introduced by the v3.8 fix, not a pre-existing one — before v3.8 there was no path that set `reflected_model_week` on a non-terminal row, so the two concepts (reserved vs. operationally resolved) happened to coincide and the shortcut worked. They no longer coincide.

Phase 1's source query is therefore:

```
origin_model_week < current_week
  AND status NOT IN ('cleared','voided')
  AND resolved_model_week IS NULL
```

`resolved_model_week IS NULL` is redundant given `status NOT IN ('cleared','voided')` under `validate_commitment_state`'s existing rules (only `cleared`/`voided` can carry a non-null `resolved_model_week`) — kept anyway as cheap defense-in-depth against a data anomaly, not because it changes which rows match.

For each row pulled by this query, compute and display `reserveActive = isReservedAsOf(c, current_week - 1)` so the UI can show the user which prior items are currently counted against deployable cash and which are reflected-but-still-open — these are different facts and both matter.

Sent as p_patched (not p_new_commitments). **Save disabled until every row shown in Phase 1 has an explicit response for this week** — "resolved" no longer means "reached a terminal status," since a reflected-but-not-yet-cleared item is legitimately expected to stay in that state across multiple weeks. A "no change, still accurate" acknowledgment (see Step 1 below) satisfies the gate without producing a patch entry — the RPC has nothing to do with a no-op, this gating is enforced client-side only, same as the existing basis-selected and no-Cleared-and-not-reflected-staged pre-RPC checks.

**Cleared + not reflected → blocked** (client and server-side via `validate_commitment_state()`), regardless of basis.

**Step 1 — clearance / status question**, always asked:

| Selection | status | reflected_model_week | resolved_model_week | resolution_type |
|---|---|---|---|---|
| Cleared (reflected) | cleared | current_week | current_week | cleared |
| Cleared + not reflected | **BLOCKED** | — | — | — |
| Cleared + not sure | bank_pending | null | null | — |
| Still not cleared | carried_unresolved | null | null | carried_unresolved |
| Amount changed | carried_unresolved | null | null | amount_changed |
| Paid from different account | voided | null | current_week | paid_from_other_account |
| Void *(requires non-empty `resolution_notes` — server-enforced as of v3.11, see the resolution_notes correction under Phase 2 below)* | voided | null | current_week | voided |
| No change, still accurate *(only offered when the row is non-terminal and its current state — including `reflected_model_week` — is still correct; typically the response for an item that's `reserveActive=false` this week because it was already marked reflected last week and nothing has changed)* | unchanged | unchanged | unchanged | unchanged — **no patch entry sent**, satisfies the per-item acknowledgment gate as a no-op |
| Still pending, no longer reflected — hold fell off *(only offered when the row currently has a non-null `reflected_model_week` and non-terminal status — i.e. the specific state v3.8 introduced)* | unchanged | **explicit patch to `null`** (key present, JSON `null` value — same key-existence mechanism as AC-8) | unchanged | unchanged |

The "hold fell off" response is the operational undo for a prior "already reflected" answer: an available-balance hold or pending authorization that was netted into a past week's balance can later be released without the debit actually posting, at which point the reserve needs to come back on. Because `isReservedAsOf()` already treats `reflected_model_week` as authoritative independent of `status` (documented under `isReservedAsOf()` above), clearing it back to `null` is sufficient — the row becomes `reserveActive=true` again on the very next `runModel()` pass with no other field changes required.

**Step 2 — reflection question**, asked only when `balance_basis === 'available_balance'` AND Step 1's answer was "Still not cleared" or "Amount changed" (the two non-terminal, not-yet-cleared outcomes): apply the `available_balance` row of the Decision Matrix above on top of Step 1's result. "Cleared + not sure" already resolves to `bank_pending`, which is maximally conservative and Review-Required on its own — Step 2 does not re-ask on top of it, since asking two different "not sure" questions about the same item is confusing, not more accurate. Step 1's terminal outcomes ("Cleared," "Paid from different account," "Void") never reach Step 2. Step 2 does not apply to the two new Step 1 responses ("No change" and "hold fell off") — both already fully determine `reflected_model_week` on their own.

### Phase 2: Current-Week WD Obligation Prompts

New commitment rows for current-week WD-tagged events with no existing commitment row. Sent as p_new_commitments with `origin_model_week = p_week_num`, `commitment_source = 'wd_reconciliation'` unless noted otherwise.

**Payload table.** Exact staged payload for each response, so the client doesn't have to infer shape from prose:

| Response | p_new_commitments row created? | status | reflected_model_week | resolved_model_week | resolution_type | commitment_source | available_balance reflection follow-up applies? |
|---|---|---|---|---|---|---|---|
| Not paid yet / not initiated | Yes | `planned` | null | null | null | `wd_reconciliation` | No — an obligation that hasn't been paid can't already be reflected in any balance |
| Paid / initiated | Yes | `initiated` | null (unless follow-up says yes) | null | null | `wd_reconciliation` | Yes |
| Bank pending | Yes | `bank_pending` | null (unless follow-up says yes) | null | null | `wd_reconciliation` | **Yes — see v3.10 correction below** |
| Cleared / reflected this week | Yes | `cleared` | current_week | current_week | `cleared` | `wd_reconciliation` | No — terminal, basis-agnostic (same rule as Phase 1's "Cleared" outcome) |
| Amount changed (expected vs. actual differs at entry) | Yes | `carried_unresolved` | null (unless follow-up says yes) | null | `amount_changed` | `wd_reconciliation` | Yes. `amount_cents` = actual amount; `original_amount_cents` = the WD-expected amount — required non-null and different, per `validate_commitment_state`'s AC-82 check |
| Paid from a different account | Yes | `voided` | null | current_week | `paid_from_other_account` | `wd_reconciliation` | No — terminal |
| WD event doesn't apply this week (mismatch — see v3.10 correction below) | Yes | `voided` | null | current_week | `voided` | `wd_reconciliation` | No — terminal |

**v3.10 correction — Bank pending must also get the reflection follow-up.** v3.9 denied Bank pending the follow-up on the theory that it was "already the maximal-uncertainty state, same as Phase 1's Cleared + not sure." That analogy doesn't hold: Phase 1's "Cleared + not sure" means the user doesn't know whether the debit cleared. Phase 2's "Bank pending" means the user *does* know the debit is pending — that's a definite fact, not uncertainty — and many banks' available balances already net out pending/authorized-but-unposted transactions. Forcing `reflected_model_week=null` unconditionally on a known-pending debit re-creates exactly the double-subtraction bug the balance-basis matrix exists to prevent. Bank pending now gets the same three-way follow-up as every other non-terminal branch: Yes → `reflected_model_week=p_week_num`, no extra reserve. No → `reflected_model_week=null`, reserve stays active. Not sure → `reflected_model_week=null` (same payload as "No" — `status` is already `bank_pending`, nothing further to override), reserve stays active, and Review Required already fires from `status='bank_pending'` regardless of the answer.

**v3.10 correction — "Skip / not due this week" could silently drop a protected obligation.** v3.9's version staged no row and claimed the WD-tagged obligation would be "re-prompted in a future week's Phase 2 once it's actually current." That claim doesn't hold up against the WD Event Tagging format actually documented in this spec: `eid` is built as `{model_year}mw{model_week}_{normalized_payee}_{due_date}` — the model week is baked into the event's identity, not a rolling/recurring pointer. Nothing else in this spec describes a mechanism that would cause a WD event tagged for week N to reappear as a Phase 2 candidate in week N+1. For a `protected_required` obligation (Amex, rent, tax transfers — see the WD Event Tagging table), a UI flow that can make the *only* prompt for that obligation disappear with a single click, with no row and no audit trail, is a real cash-safety gap — this is exactly the class of failure 5F-1 exists to prevent, on the WD-capture side rather than the reservation-math side.

Renamed to **"WD event doesn't apply this week (mismatch)"** and changed to stage an actual row rather than nothing: `status='voided'`, `resolution_type='voided'`, mandatory `resolution_notes` explaining the mismatch. This uses only mechanics `validate_commitment_state` already supports for `voided` — no new status, no speculative "reschedule to a future week" flow invented for this spec, since due-date rescheduling of WD events isn't otherwise described anywhere in 5F-1. The obligation is fully captured and audited rather than vanishing; if it turns out the obligation is still owed, there's a `voided` row on record for Adam to find and correct, instead of nothing at all.

**v3.11 correction — the resolution_notes requirement above must be server-enforced, not just client-side.** v3.10 blocked empty/missing `resolution_notes` client-side only ("same spirit as the Cleared + not reflected → blocked rule"), but never actually added the server-side check — the RPC insert/patch paths still accepted `resolution_notes = NULLIF(v_item->>'resolution_notes','')` with no requirement behind it. A client bug (or any future caller that doesn't route through this exact form) could still produce `status='voided'`, `resolution_type='voided'`, `resolution_notes=NULL` — exactly the "silent dismissal, no real audit trail" outcome this whole redesign exists to prevent. `validate_commitment_state` now rejects `resolution_type='voided'` with null/empty `resolution_notes` directly (see section 6), which applies uniformly to every insert and patch path in both RPCs — the RPC has no way to know which UI screen produced a given payload, and there's no reason it should need to. This also means the requirement isn't actually scoped to "just the new mismatch branch": it applies to *any* row that ends up `voided`/`voided`, which includes Phase 1's plain "Void" response for an existing commitment (see that table above) and repair's "Void / was never owed" option. That's correct, not scope creep — Phase 1's plain Void was exactly as under-audited as the thing this fix was written to close, and there's no principled reason to protect one and not the other. `paid_from_other_account` remains exempt, per the same reasoning as before.

**Reflection question mechanics.** When `balance_basis === 'available_balance'` and the row above says the follow-up applies, ask "does the balance you're about to enter already reflect this debit?" for that staged commitment before finalizing the payload. Yes → `reflected_model_week = p_week_num` on the staged insert (the save RPC's insert-path guard — see round 3 changelog — rejects any other value for a non-terminal status). No → leave `reflected_model_week` null. Not sure → leave `reflected_model_week` null, and if the base response wasn't already `bank_pending`, override `status` to `bank_pending` (this is now the shared "not sure" landing state across every branch that offers the follow-up, not just its own dedicated branch).

### Phase 3: Generic Catch-All

Manual items: `crypto.randomUUID()`, `commitment_source='manual_reconciliation'`, `origin_model_week = p_week_num`. Same reflection-question treatment as Phase 2 when `balance_basis === 'available_balance'`.

### Phase 4: Balance Entry

Existing 5-field form. Amber warning if unknown basis.

### Save — RPC

1. Pre-RPC validation: every Phase 1 row has an explicit response for this week (terminal, "hold fell off," or "no change, still accurate" — see Phase 1); basis selected; no Cleared+not-reflected staged; balances valid; `recorded_at` populated from `Date.now()`.
2. Call `save_reconciliation_with_commitments` RPC.
3. **Conflict error:** Refresh `commitmentData`, show existing row status, prompt user to route via Phase 1 patch.
4. Other error: show message, keep form open, retry safe.
5. Ok: refresh reconData + commitmentData, rerun runModel(), close form.

**Malformed patch payloads.** Patch paths deliberately don't duplicate the insert paths' pre-cast validation (accepted scoping decision, round 3). A malformed patch field (non-numeric `amount_cents`, `reflected_model_week`, `resolved_model_week`; malformed `cleared_date`; malformed `id`) still fails safely: PL/pgSQL functions run as a single implicit transaction per call, so a cast exception anywhere — insert loop or patch loop — aborts the *entire* RPC call, including the `weekly_reconciliations` upsert that ran earlier in the same call and any commitment rows already inserted/patched in earlier loop iterations. `EXCEPTION WHEN OTHERS THEN RAISE;` re-raises without swallowing or partially committing anything. Client behavior on any RPC error (step 4 above) already covers this: show the message, keep the form open, don't refresh/close as if it succeeded. See AC-98 through AC-101.

---

## Historical Backfill — Repair Mode

### Detection

Post-loadAll: for each reconciled week in reconData, find WD events with `eid` missing from commitmentData. Flag those weeks.

### Repair Form

**Phase 0 (repair):** Show stored balance (read-only). Collect `balance_basis` if null.

**Historical Phase 2 (repair):** For each missing WD-tagged obligation from the affected week:

> **AMEX Platinum $6,368.48** — origin: Week 3 (Jun 21–27)
>
> ( ) Not cleared yet — reserve from Week 3 forward  
> ( ) Cleared by Week \_\_\_ [selector — must have reconciliation row; enforced server-side]  
> ( ) Paid from a different account  
> ( ) Void / was never owed  

"Cleared by Week 4" → `origin_model_week=3, reflected_model_week=4, resolved_model_week=4, status=cleared, commitment_source=historical_repair`. Server validates Week 4 has a reconciliation row.

**"Not cleared yet" under `available_balance` basis:** the historical week being repaired may itself have been recorded on an `available_balance` basis, in which case the same double-subtraction risk applies retroactively. If the reconciliation row for the origin week (or any week being backfilled) has `balance_basis='available_balance'`, add the same reflection follow-up: "Was this already reflected in the balance entered for Week \_\_\_?" Yes → `reflected_model_week` = that week (must have a reconciliation row — same server-side check as "Cleared by Week X"). No / not sure → `reflected_model_week` stays null (not sure additionally sets `status='bank_pending'`). Unlike the live save path, `repair_commitments_for_week` does **not** require this reflected week to equal `p_week_num` — repair's whole purpose is recording reflection/clearance in a week other than the one being repaired.

**Phase 3 (repair):** Catch-all for other unrecorded payments.

**No Phase 4.** Balances never modified.

**RPC:** `repair_commitments_for_week(week_num, model_year, balance_basis_or_null, new_commitments, patched)`.

**Smoke requirement:** Week 3 Amex must exist, `adjustedDeployableSurplusCents = 1026540`. Hard gate.

---

## Dashboard Display

### Adjusted deployable

```
Truist Checking (posted · 6/27)       $23,133.88
  − Amex Platinum (initiated)          −$6,368.48
  Adjusted available checking          $16,765.40
  − Operating floor                    −$6,500.00
  ─────────────────────────────────────────────────
  Adjusted deployable surplus          $10,265.40
  Raw surplus above floor (informational):  $16,633.88
```

### Command verdict chip

Driven by `_reviewRequired` from the engine block (see runModel() Changes above), not `_balanceBasisUnknown` alone.

| Condition | Verdict |
|---|---|
| Known basis, active reserves, none `bank_pending` | `Deployable +$10,265.40` |
| No active reserves | `Deployable +$X` |
| Unknown basis + active reserves | `⚠ Review Required — est. deployable $X` |
| Any basis + at least one active reserve has `status='bank_pending'` | `⚠ Review Required — est. deployable $X` |
| Unknown basis + no active reserves | `Deployable +$X` |

---

## Acceptance Criteria + Required Tests

### AC-1: Week 3 exact math

`getCashAvailabilityEngine(2313388, 650000, [{amount_cents:636848, ...}], 'truist_checking', 3)`  
`adjustedDeployableSurplusCents === 1026540` ✓ `rawSurplusAboveFloorCents === 1663388` (informational) ✓

### AC-2: Critical invariant — adjustedDeployable stable across clearance

Before: reserve=$6,368.48, adjustedDeployable=$10,265.40. After: reserve=$0, adjustedDeployable=$10,265.40. Delta=$0 ✓

### AC-3: Historical Week 3 reserves after Week 4 clears

`reflected_model_week=4, resolved_model_week=4` → `isReservedAsOf(c,3)=true`, `isReservedAsOf(c,4)=false` ✓

### AC-4: reflected_model_week=3 — no reserve at Week 3+

`isReservedAsOf({...c, reflected_model_week:3}, 3)` → false ✓

### AC-5: Carry-forward when unresolved

`status='carried_unresolved', reflected_model_week=null, resolved_model_week=null` → `isReservedAsOf(c,3)=true`, `isReservedAsOf(c,5)=true` ✓

### AC-6: Terminal statuses

`status='voided'` → false ✓. `resolution_type='voided'` → false ✓. `resolution_type='paid_from_other_account'` → false ✓

### AC-7: Patch final-state rejects incomplete patch

Existing: `status='initiated'`. Patch: `{id:"...", status:"cleared"}`. Expected: exception "cleared requires resolved_model_week". Row unchanged.

### AC-8: Patch key-existence — intentional NULL

`{id:"...", "resolved_model_week":null}` (key present, value null) → field set to NULL ✓. Key absent → field unchanged ✓

### AC-9: p_new_commitments conflict raises exception

Send existing `expected_item_id` in p_new_commitments. Expected: exception "commitment already exists." Row not modified.

### AC-10: Repair insert "Cleared by Week X" blocked if Week X has no reconciliation row

`repair_commitments_for_week` with `reflected_model_week=5`, Week 5 has no reconciliation row → exception. No rows written.

### AC-11: REVOKE PUBLIC + GRANT authenticated — all three functions

- `has_function_privilege('anon', 'save_reconciliation_with_commitments(...)', 'EXECUTE')` → false ✓
- `has_function_privilege('authenticated', 'save_reconciliation_with_commitments(...)', 'EXECUTE')` → true ✓
- `has_function_privilege('anon', 'repair_commitments_for_week(...)', 'EXECUTE')` → false ✓
- `has_function_privilege('authenticated', 'repair_commitments_for_week(...)', 'EXECUTE')` → true ✓
- `has_function_privilege('anon', 'validate_commitment_state(...)', 'EXECUTE')` → false ✓
- `has_function_privilege('authenticated', 'validate_commitment_state(...)', 'EXECUTE')` → false ✓

### AC-12: RPC atomicity — both new-row and existing-row cases

**Case A — No prior reconciliation row:**  
Inject constraint violation in p_new_commitments during Week 7 (no existing row). Expected: `weekly_reconciliations` row for Week 7 does NOT appear after failure. `commitmentData` unchanged.

**Case B — Prior reconciliation row exists:**  
Inject same failure during Week 3 (row already exists). Expected: `weekly_reconciliations` row for Week 3 is unchanged (reverts to pre-call state). `commitmentData` unchanged. Atomicity holds for upsert rollback.

### AC-13: Projected carry-forward ignores unreconciled seed commitments

Seed: `origin_model_week=7`, `commitment_source='wd_reconciliation'`, Week 7 has no reconciliation row. Projected Week 8: excluded from `_caCommitments`. `adjustedAvailableForSweep` not reduced ✓

### AC-14: historical_repair commitments carry in projected weeks

`commitment_source='historical_repair'`, `origin_model_week=3`: included in projected Week 4 filter via `|| commitment_source === 'historical_repair'` branch ✓

### AC-15: Unknown basis + active reserves → "Review Required"

Reconcile Week N, `balance_basis='unknown'`, one active commitment. Verdict: `⚠ Review Required — est. deployable $X` ✓. Unknown basis + no reserves → `Deployable +$X` ✓

### AC-16: No double-reservation in projected weeks

Projected Week 3, Amex `origin_model_week=3`: `origin_model_week < 3` is false → excluded ✓

### AC-17: Waterfall aggregate cap

Alaska $2,000 + IRA $1,000, `adjustedAvailableForSweep=$2,500`: Alaska sweeps $2,000 (remaining=$500), IRA sweeps $500 (remaining=$0). Total $2,500, not $3,000 ✓

### AC-18: Command verdict uses adjusted deployable, not raw

After Amex commitment created: verdict `Deployable +$10,265.40`. Raw `$16,633.88` under "(informational)" only ✓

### AC-19: Multiple commitments aggregate

Amex $6,368.48 + Disney $5,925.13, both unresolved, Week 3:  
`adjustedDeployable = max(0, (2313388-1229361) - 650000) = 434027 ($4,340.27)` ✓

### AC-20: Below-floor protection

`adjustedAvailableCashCents < floorCents` → `adjustedDeployableSurplusCents = 0`. Never negative ✓

### AC-21: Historical backfill — Week 3 smoke gate

Repair form used. Amex row created with `historical_repair`. Engine for Week 3: `adjustedDeployableSurplusCents = 1026540`. Verdict `Deployable +$10,265.40` ✓. **Hard gate — must pass before smoke is marked complete.**

### AC-22: DB constraint integrity

`INSERT origin_model_week=32` → chk_week_origin_range fires ✓. `INSERT resolved_model_week=2, origin=3` → chk_resolved_after_origin fires ✓. `INSERT original_amount_cents=0` → check fires ✓

### AC-23: RLS / model_year — RPC rejects p_model_year=2025

RPC called with `p_model_year=2025` → server raises exception before any write ✓

### AC-24: Amount changed

`amount_cents=620000, original_amount_cents=636848, resolution_type='amount_changed', resolved_model_week=null` ✓

### AC-25: Manual UUID uniqueness

Two manual payments, same payee/amount/week → two distinct UUIDs → two rows, no UNIQUE violation ✓

### AC-26: validate_commitment_state called by both RPCs on both paths

Both RPCs call helper before INSERT and on RETURNING row after UPDATE. `{status:'cleared'}` alone raises exception from either RPC ✓

### AC-27: DO NOTHING does not silently overwrite

Send existing cleared row's `expected_item_id` in p_new_commitments with `status='planned'`. Exception raised. Row remains cleared ✓

### AC-28: Conflict error triggers commitmentData refresh

RPC returns "commitment already exists." UI refreshes `commitmentData`, shows existing row's status, prompts route through Phase 1 patch ✓

### AC-29: Direct authenticated INSERT rejected; RPC insert succeeds

Direct REST INSERT → `ERROR permission denied for table cash_commitments` ✓. Same payload via RPC → succeeds ✓

### AC-30: Direct authenticated UPDATE rejected; RPC patch succeeds

Direct REST UPDATE → `ERROR permission denied for table cash_commitments` ✓. Same via RPC → succeeds ✓

### AC-31: validate_commitment_state is SECURITY INVOKER and not PUBLIC-executable

`procsecdef = false` for `validate_commitment_state` ✓. Both anon and authenticated `has_function_privilege` → false ✓

### AC-32: Missing status defaults to 'planned' before validation

Commitment with no `status` field → `v_status = 'planned'`, `validate_commitment_state()` called with `'planned'`. Row inserted with `status='planned'` ✓. If `resolved_model_week=4` also sent → validation catches "active status planned must have null resolved_model_week" ✓

### AC-33: Invalid status/resolution_type combinations rejected

| Combination | Expected exception |
|---|---|
| `cleared` + `resolution_type=null` | cleared requires resolution_type=cleared |
| `cleared` + `resolution_type='voided'` | cleared requires resolution_type=cleared |
| `voided` + `resolution_type='cleared'` | voided requires resolution_type in (voided, paid_from_other_account) |
| `carried_unresolved` + `resolution_type='cleared'` | resolution_type must be null, carried_unresolved, or amount_changed |
| `planned` + `resolution_type='cleared'` | active status planned must have null resolution_type |
| `voided` + `resolution_type='voided'` + `resolution_notes=null` (v3.11) | voided with resolution_type=voided requires non-empty resolution_notes |

### AC-34: initiated + paid_from_other_account rejected

`status='initiated', resolution_type='paid_from_other_account'` → exception "active status initiated must have null resolution_type". Reserve is NOT removed ✓

### AC-35: save RPC rejects new commitments where origin_model_week != p_week_num

Week 4 save (`p_week_num=4`): p_new_commitments contains `origin_model_week=3`. Expected: exception containing "origin_model_week (3) must equal p_week_num (4)" ✓

### AC-36: save RPC rejects invalid commitment_source in p_new_commitments

p_new_commitments contains `commitment_source='historical_repair'` → exception "invalid commitment_source: historical_repair" ✓. Ditto for any other non-allowed value ✓

### AC-37: save RPC cannot patch commitments with origin_model_week > p_week_num

Week 3 save: p_patched contains id of a Week 5 commitment. Pre-fetch SELECT returns NOT FOUND → exception before UPDATE ✓

### AC-38: repair RPC cannot patch commitments with origin_model_week != p_week_num

Week 3 repair: p_patched contains id of a Week 4 commitment. WHERE `origin_model_week = 3` fails → exception ✓

### AC-39: save RPC rejects new cleared commitment where reflected or resolved week != p_week_num

`p_week_num=3`, new commitment `{status:'cleared', reflected_model_week:4, resolved_model_week:4}` → exception "new cleared commitment must have reflected_model_week=3 and resolved_model_week=3" ✓

### AC-40: save RPC rejects new voided commitment where resolved_model_week != p_week_num

`p_week_num=3`, new commitment `{status:'voided', resolved_model_week:5, resolution_type:'voided'}` → exception "new voided commitment must have resolved_model_week=3" ✓

### AC-41: Live save cannot mutate terminal fields on cleared/voided row

Existing Week 3 row: `status='cleared'`. Patch: `{id:"...", amount_cents:999}` → exception "cannot mutate terminal fields on cleared commitment". Row unchanged ✓

### AC-42: Notes-only patch on cleared/voided row is allowed

Existing Week 3 row: `status='cleared'`. Patch: `{id:"...", notes:"verified 6/28"}` → succeeds ✓. `{id:"...", resolution_notes:"reconciled"}` → succeeds ✓

### AC-43: Lifecycle-field patch without status cannot bypass p_week_num guard (rewritten v3.11 — was stale)

**This AC originally (pre-round-3) described the guard as firing only on transitions to `cleared`/`voided`, and claimed a patch that set `reflected_model_week` on a still-`initiated` row with no `status` key would pass through unvalidated. That was true before the round-3 and round-5 guards existed. It has been wrong since round 3 added the non-terminal `reflected_model_week = p_week_num` guard, and leaving the AC unrewritten would have encoded the old, incorrect behavior as the test target. Corrected here.**

Existing Week 3 row: `status='initiated'`, `reflected_model_week=NULL`, `p_week_num=3` for this save call.

- Patch `{id:"...", reflected_model_week:5}` (no `status` key) → `v_row.status` remains `'initiated'` after UPDATE → the non-terminal reflected-week guard (`status NOT IN ('cleared','voided')`) fires because `reflected_model_week=5 IS DISTINCT FROM p_week_num=3` → exception "reflected_model_week (5) on non-terminal commitment (status=initiated) must equal p_week_num=3 — a live reconciliation can only mark a debit as reflected in the balance being entered this week, or explicitly clear reflected_model_week to null" ✓
- Patch `{id:"...", reflected_model_week:3}` (equal to `p_week_num`) → guard does not fire, patch succeeds ✓
- Patch `{id:"...", reflected_model_week:null}` (explicit null) → guard's `IS NOT NULL` condition is false, guard does not fire, patch succeeds, `reflected_model_week` cleared ✓
- Status transitions to `cleared` still separately require `status` in the payload and both week fields pinned to `p_week_num`: `{id:"...", status:"cleared", reflected_model_week:3, resolved_model_week:3, resolution_type:"cleared"}` → succeeds; the same payload with `reflected_model_week:5` → the cleared-specific lifecycle guard fires with the same exception shape ✓

### AC-44: Missing expected_item_id rejected in both save and repair insert paths

Save: `p_new_commitments=[{model_year:2026, amount_cents:100, ...}]` (no expected_item_id field) → exception "commitment missing expected_item_id" ✓. Repair: same → exception ✓

### AC-45: Invalid commitment_class rejected in both save and repair insert paths

Save: `commitment_class='wire_transfer'` → exception "save: invalid commitment_class: wire_transfer" ✓. Repair: same → exception "repair: invalid commitment_class: wire_transfer" ✓

### AC-46: p_recorded_at null rejected by save RPC

`save_reconciliation_with_commitments(p_week_num:3, ..., p_recorded_at:null)` → exception "recorded_at must not be null" before any write ✓

### AC-47: remainingAdjustedSweep never goes below zero after multiple sweeps

Scenario: `adjustedAvailableForSweep=$0.01`; three sweep sites each proposing $1,000. After sweep 1: sweepAmt=$0.01, remaining=$0.00. After sweeps 2+3: sweepAmt=$0.00, remaining=$0.00. `Math.max(0, ...)` clamp prevents -$0.001 float residue ✓

### AC-48: Table privileges explicitly revoked before SELECT grant

- `has_table_privilege('PUBLIC', 'cash_commitments', 'SELECT')` → false ✓
- `has_table_privilege('anon', 'cash_commitments', 'SELECT')` → false ✓
- `has_table_privilege('authenticated', 'cash_commitments', 'INSERT')` → false ✓
- `has_table_privilege('authenticated', 'cash_commitments', 'UPDATE')` → false ✓
- `has_table_privilege('authenticated', 'cash_commitments', 'SELECT')` → true ✓

### AC-49: validate_commitment_state rejects invalid/null status and required_or_discretionary

- `p_status = NULL` → "status is required" ✓
- `p_status = 'pending'` → "invalid status: pending" ✓
- `p_required_or_discretionary = NULL` → "required_or_discretionary is required" ✓
- `p_required_or_discretionary = 'optional'` → "invalid required_or_discretionary: optional" ✓

### AC-50: protected_required with affects_deployable_cash=false rejected

`required_or_discretionary='protected_required', affects_deployable_cash=false` → exception ✓

### AC-51: repair RPC patch path rejects reflected/resolved weeks with no reconciliation row

Existing repair row: `origin_model_week=3`. Patch: `{id:"...", status:"cleared", reflected_model_week:9, resolved_model_week:9}` where Week 9 has no reconciliation row → exception "repair patch: merged reflected_model_week=9 has no reconciliation row" ✓

### AC-52: save insert invalid commitment_source covers all non-allowed values

`commitment_source='seed'`, `commitment_source='import'`, `commitment_source=''` → all raise exception ✓

### AC-53: Budget actuals non-goal sentinel (test-only guard)

After all code paths: `_getBudgetLivingExpenses()` output unchanged. Zero writes in `budget_transactions` or `budget_line_rules`. **No production code reads or writes budget tables in 5F-1.**

---

## Acceptance Criteria — Audit/Control Hardening (v3.6)

### AC-54: Insert payload cannot spoof resolved_at or resolved_by

Save: `p_new_commitments=[{..., status:'planned', resolved_at:'2020-01-01T00:00:00Z', resolved_by:'<attacker-uuid>'}]` → row inserted with `resolved_at=NULL`, `resolved_by=NULL` (status is active, so neither is populated) ✓. Repeat with `status:'cleared', reflected_model_week:p_week_num, resolved_model_week:p_week_num, resolution_type:'cleared'` plus the same spoofed `resolved_at`/`resolved_by` → row inserted with `resolved_at=NOW()` (not the spoofed timestamp) and `resolved_by=auth.uid()` (not the attacker UUID) ✓. Repeat both cases against `repair_commitments_for_week` insert path ✓

### AC-55: Patch payload cannot spoof resolved_at or resolved_by

Existing active row (`status='initiated'`). Patch: `{id:"...", status:"cleared", reflected_model_week:p_week_num, resolved_model_week:p_week_num, resolution_type:"cleared", resolved_at:'2020-01-01T00:00:00Z', resolved_by:'<attacker-uuid>'}` → merged row has `resolved_at=NOW()` and `resolved_by=auth.uid()`, not the spoofed values ✓. Repeat against `repair_commitments_for_week` patch path ✓

### AC-56: Transition to cleared sets resolved_at/resolved_by server-side

Existing row `status='initiated'`, `resolved_at=NULL`, `resolved_by=NULL`. Patch (save path): `{id:"...", status:"cleared", reflected_model_week:p_week_num, resolved_model_week:p_week_num, resolution_type:"cleared"}` — **no `resolved_at`/`resolved_by` keys sent at all**. Merged row: `resolved_at=NOW()`, `resolved_by=auth.uid()` ✓. Repeat via `repair_commitments_for_week` ✓

### AC-57: Transition to voided sets resolved_at/resolved_by server-side

Existing row `status='initiated'`, `resolved_at=NULL`. Patch: `{id:"...", status:"voided", resolved_model_week:p_week_num, resolution_type:"voided", resolution_notes:"duplicate entry, voided"}` — `resolution_notes` included per the v3.11 requirement (this patch would otherwise be rejected before it could demonstrate anything); no `resolved_at`/`resolved_by` keys sent. Merged row: `resolved_at=NOW()`, `resolved_by=auth.uid()` ✓

### AC-58: carried_unresolved sets resolved_at/resolved_by server-side

Existing row `status='initiated'`. Patch: `{id:"...", status:"carried_unresolved", resolution_type:"carried_unresolved"}` — no `resolved_at`/`resolved_by` keys. Merged row: `resolved_at=NOW()`, `resolved_by=auth.uid()`, `resolved_model_week` remains NULL (per `validate_commitment_state`, `carried_unresolved` requires null `resolved_model_week`) ✓. This is a deliberate divergence from `resolved_model_week`: the audit fields answer "who/when marked this unresolved," which is populated, while `resolved_model_week` answers "which model week resolved it," which by definition does not exist for `carried_unresolved`.

### AC-59: Terminal row cannot patch resolved_at or resolved_by

Existing Week 3 row: `status='cleared'`. Patch (save path): `{id:"...", resolved_at:"2026-06-30T00:00:00Z"}` → exception "cannot mutate terminal fields on cleared commitment". Repeat with `{id:"...", resolved_by:"<any-uuid>"}` → same exception. Row unchanged in both cases ✓. (`repair_commitments_for_week`'s patch path has no terminal-immutability guard by design — repair's purpose includes correcting already-terminal historical rows — so this AC applies to the save path only; see v3.6 changelog item 6.)

### AC-60: Save patch prefetch uses FOR UPDATE

Concurrency test: two concurrent `save_reconciliation_with_commitments` calls patch the same `id`. Second transaction blocks on the prefetch `SELECT ... FOR UPDATE` until the first commits or rolls back, rather than both reading stale `v_existing` and racing on the `UPDATE` ✓

### AC-61: Repair patch prefetch uses FOR UPDATE

Same concurrency test as AC-60, run against `repair_commitments_for_week` ✓

### AC-62: Invalid source_account rejected in save insert path

Save: `p_new_commitments=[{..., source_account:'truist-checking'}]` (hyphen typo) → exception "invalid source_account: truist-checking. 5F-1 only supports truist_checking". No row written ✓. Repeat with `source_account:'truist_checkingg'` and `source_account:'chase_checking'` — both rejected ✓

### AC-63: Invalid source_account rejected in repair insert path

Same three variants as AC-62, run against `repair_commitments_for_week` insert path ✓

### AC-64: source_account CHECK constraint exists at the table level

`INSERT INTO cash_commitments (..., source_account, ...) VALUES (..., 'truist-checking', ...)` issued directly against the table (bypassing both RPCs, e.g. as the table owner in a test harness) → `chk_source_account_only_truist` violation ✓. This is a backstop, not the primary defense — see the note under the `CREATE TABLE` block for why both the RPC check and the CHECK constraint are kept.

### AC-65: amount_cents patch preserves original_amount_cents automatically

Existing row: `amount_cents=636848`, `original_amount_cents=NULL`. Patch (save path): `{id:"...", amount_cents:620000}` — **no `original_amount_cents` key sent**. Merged row: `amount_cents=620000`, `original_amount_cents=636848` (auto-preserved from pre-patch value) ✓. Second patch on the same row: `{id:"...", amount_cents:600000}` — `original_amount_cents` stays `636848` (not re-stamped to `620000`, since it was already non-null) ✓. Repeat both steps via `repair_commitments_for_week` ✓

### AC-66: amount_cents patch normalizes resolution_type='amount_changed' only when the row resolves to carried_unresolved

Case A: existing row `status='carried_unresolved'`. Patch: `{id:"...", amount_cents:620000}` (no `resolution_type` sent, or `resolution_type` sent as something else) → merged row: `resolution_type='amount_changed'`, overriding any client-supplied value ✓. Case B: existing row `status='initiated'` (still active). Patch: `{id:"...", amount_cents:620000}` (no status change) → merged row: `amount_cents=620000`, `original_amount_cents` auto-preserved per AC-65, `resolution_type` unchanged (stays NULL) — normalization does **not** fire, because `validate_commitment_state` requires `resolution_type IS NULL` for active statuses and forcing `'amount_changed'` here would make every active-row amount correction fail validation. The audit trail for Case B is `original_amount_cents` alone. This scoping decision is called out explicitly for Adam's review — flagged as a judgment call, not an unstated assumption.

### AC-67: AC count is consistent across the spec

Header, Scope, Files Changed, Build Sequence, and this AC section all state 116 ACs / 116 new tests. `grep -c '^### AC-' docs/phase-5f-1-spec.md` returns 116. `test_regression.js` implements AC-1 through AC-116 with no gaps or duplicate numbers ✓

---

## Acceptance Criteria — Round 2 Hardening (v3.7)

### AC-68: save RPC rejects NULL p_model_year, p_week_num, and p_balance_basis

`save_reconciliation_with_commitments(p_week_num:3, p_model_year:NULL, ...)` → exception "invalid model_year: <null>" ✓. `save_reconciliation_with_commitments(p_week_num:NULL, ...)` → exception "invalid week_num: <null>" ✓. `save_reconciliation_with_commitments(..., p_balance_basis:NULL, ...)` → exception "invalid balance_basis: <null>" ✓. All three raise before any write — confirms the `IS NULL OR` guard actually fires, since a bare `<>`/`NOT BETWEEN`/`NOT IN` comparison against NULL evaluates to NULL (not TRUE) in SQL and would otherwise let the NULL through silently.

### AC-69: repair RPC rejects NULL p_model_year and p_week_num

`repair_commitments_for_week(p_week_num:3, p_model_year:NULL, ...)` → exception "invalid model_year: <null>" ✓. `repair_commitments_for_week(p_week_num:NULL, ...)` → exception "invalid week_num: <null>" ✓. `repair_commitments_for_week(..., p_balance_basis:NULL, ...)` with no other errors → succeeds (balance_basis stays optional in repair — NULL means "leave it alone," not "invalid") ✓

### AC-70: JSON null payload rejected cleanly in both RPCs

Save: `p_new_commitments := 'null'::jsonb` → exception "p_new_commitments must be a JSON array" ✓ (not silently treated as `[]`, and not silently passed through — `jsonb_typeof('null'::jsonb)` is SQL NULL, so the check must use `IS DISTINCT FROM 'array'`, not `<> 'array'`). Same for `p_patched := 'null'::jsonb` ✓. Repeat both cases against `repair_commitments_for_week` ✓

### AC-71: commitment_source missing defaults; empty string rejects

Save insert: item with no `commitment_source` key → `v_csource='wd_reconciliation'`, row inserted ✓. Item with `commitment_source:''` → exception "save: commitment_source cannot be empty". No row written ✓. (Matches AC-52's existing coverage of non-empty invalid values — this AC closes the empty-string gap specifically.)

### AC-72: source_account missing defaults; empty string rejects, in both save and repair insert paths

Save insert: item with no `source_account` key → `v_source_account='truist_checking'`, row inserted ✓. Item with `source_account:''` → exception "invalid source_account: (empty). 5F-1 only supports truist_checking". No row written ✓. Repeat both cases against `repair_commitments_for_week` insert path ✓

### AC-73: recorded_at is server-owned

`save_reconciliation_with_commitments(..., p_recorded_at: '2020-01-01T00:00:00Z', ...)` where the actual call time is 2026-06-30 → `weekly_reconciliations.recorded_at` for the row is set to the real call time (`NOW()`), not `2020-01-01`. `p_recorded_at` remains a required, non-null parameter (AC-46 still covers null-rejection) but its value is never written — it exists only so the caller must explicitly signal a genuine reconciliation event ✓

### AC-74: live save patch cannot explicitly patch original_amount_cents

Existing row: `amount_cents=636848`, `original_amount_cents=NULL`, `status='initiated'`. Patch (save path): `{id:"...", amount_cents:620000, original_amount_cents:999999}` → merged row: `amount_cents=620000`, `original_amount_cents=636848` (server auto-preserved value, the client-supplied `999999` is silently ignored, not an error) ✓. Contrast with `repair_commitments_for_week`, where the same patch on an equivalent historical row honors the client-supplied `original_amount_cents=999999`, since repair legitimately needs to backfill a known prior amount ✓

### AC-75: validate_commitment_state rejects null/out-of-range origin_model_week

`validate_commitment_state(NULL, 'planned', NULL, NULL, NULL, NULL, 100, NULL, 'discretionary_deployment', true)` (origin_model_week=NULL) → exception "origin_model_week is required" ✓. Same call with `p_origin_model_week:0` → exception "origin_model_week out of range" ✓. Same with `p_origin_model_week:32` → exception "origin_model_week out of range" ✓. Confirms the helper is a complete state validator independent of caller-side checks.

### AC-76: existing regression baseline count is consistent

`grep -c '^test(' test_regression.js` immediately before build start matches the number stated in Build Sequence step 13. If it does not match (e.g. the file moved since this spec was written), the build sequence's stated number is wrong and must be corrected before proceeding — the grep output is the source of truth, not the spec text ✓

---

## Acceptance Criteria — Round 3 Hardening (v3.8)

### AC-77: available_balance + debit already reflected → reflected_model_week set, no extra reserve

Phase 1 patch, `balance_basis='available_balance'`, Step 1 answer "Still not cleared" (→ `carried_unresolved`), Step 2 answer "Yes, already reflected": `{id:"...", status:"carried_unresolved", resolution_type:"carried_unresolved", reflected_model_week:p_week_num}` → merged row has `reflected_model_week=p_week_num`. `isReservedAsOf(mergedRow, p_week_num)` → **false** — the item does not double-count against `adjustedDeployableSurplusCents` for the week whose available balance already nets it out ✓. Repeat for a brand-new Phase 2 commitment (insert, not patch): `{..., status:"initiated", reflected_model_week:p_week_num}` → same result ✓

### AC-78: available_balance + debit not reflected → reserve remains active

Same setup as AC-77, Step 2 answer "No": `{id:"...", status:"carried_unresolved", resolution_type:"carried_unresolved"}` (no `reflected_model_week` key) → merged row has `reflected_model_week=null`. `isReservedAsOf(mergedRow, p_week_num)` → **true** — reserve stays active, matching pre-v3.8 default behavior for available_balance ✓

### AC-79: available_balance + not sure → conservative reserve + Review Required; generalizes to any basis

Same setup as AC-77, Step 2 answer "Not sure": merged row has `reflected_model_week=null`, `status='bank_pending'`. `isReservedAsOf()` → **true** (conservative — unchanged reserve). Dashboard: `_hasBankPendingReserve=true` → `_reviewRequired=true` even though `balance_basis='available_balance'` (a *known* basis) — confirms Review Required is no longer gated on `balance_basis==='unknown'` alone ✓. Repeat with `balance_basis='posted_current_balance'` and the existing "Cleared + not sure" path (which already produced `bank_pending` pre-v3.8) → Review Required now also fires there, which it did not before this change ✓

### AC-80: posted_current_balance + pending debit → reserve remains active

`balance_basis='posted_current_balance'`, Phase 1 Step 1 answer "Still not cleared" → `carried_unresolved`, `reflected_model_week=null`. No Step 2 applies (basis is not `available_balance`). `isReservedAsOf()` → **true** ✓. This is unchanged pre-existing behavior, captured explicitly per the balance-basis matrix rather than left implicit.

### AC-81: validate_commitment_state rejects NULL affects_deployable_cash

`validate_commitment_state(NULL, 'planned', NULL, NULL, NULL, 3, 100, NULL, 'discretionary_deployment', NULL)` (`p_affects_deployable_cash=NULL`) → exception "affects_deployable_cash is required" ✓. Confirms the helper does not depend on the two RPCs' `COALESCE(..., true)` defaulting having already run.

### AC-82: amount_changed requires a real original_amount_cents audit trail

`validate_commitment_state(..., p_status:'carried_unresolved', p_resolution_type:'amount_changed', p_amount_cents:620000, p_original_amount_cents:NULL, ...)` → exception "amount_changed requires original_amount_cents" ✓. Same call with `p_original_amount_cents:620000` (equal to `p_amount_cents`) → exception "amount_changed requires original_amount_cents <> amount_cents" ✓. Same call with `p_original_amount_cents:636848` (different) → passes ✓. Confirms `amount_changed` cannot be used as a label with no evidence behind it, closing the gap that the save/repair patch paths' auto-preserve logic already prevents in practice but this helper didn't independently enforce.

### AC-83: cleared_date rejected unless status='cleared'

`validate_commitment_state(..., p_status:'initiated', ..., p_cleared_date:'2026-06-30')` → exception "cleared_date must be null unless status=cleared" ✓. Same with `p_status:'bank_pending'`, `p_status:'voided'`, `p_status:'carried_unresolved'` — all rejected with a non-null `p_cleared_date` ✓. `p_status:'cleared'` with a non-null `p_cleared_date` → passes (subject to the other cleared-status requirements) ✓. `p_cleared_date:NULL` passes regardless of status (default case, matches the function's `DEFAULT NULL`) ✓

### AC-84: repair terminal-row mutability is explicitly allowed only through the repair path and only for origin_model_week=p_week_num

`save_reconciliation_with_commitments` patch against a `cleared` row → blocked (terminal immutability guard; unchanged from v3.6, re-verified here for contrast) ✓. `repair_commitments_for_week` patch against a `cleared` row whose `origin_model_week = p_week_num` → succeeds, subject to `FOR UPDATE`, row-count validation, and post-merge `validate_commitment_state()` (no terminal-field blocklist in repair — by design) ✓. `repair_commitments_for_week` patch against a row whose `origin_model_week != p_week_num` (regardless of terminal status) → fails at the prefetch (`NOT FOUND`), same as any other repair patch scope violation — confirms repair cannot be used as a backdoor to revise an arbitrary week's terminal row from a different week's repair call ✓

### AC-85: pre-cast validation catches empty/non-numeric model_year, origin_model_week, amount_cents, and week fields

Save insert: `{..., model_year:"abc", ...}` → exception "commitment model_year must be a valid integer, got: abc" (not a raw Postgres cast error) ✓. Repeat for `origin_model_week:"3.5"`, `amount_cents:""`  (present-but-empty on a required field — presence check already catches pure absence, this catches empty-string specifically since `''` is not `NULL`), `original_amount_cents:"abc"`, `reflected_model_week:"abc"`, `resolved_model_week:"abc"` — each rejected with a field-specific clean error before any cast is attempted ✓. Repeat all cases against `repair_commitments_for_week`'s insert path ✓

### AC-86: pre-cast validation catches invalid affects_deployable_cash

Save insert: `{..., affects_deployable_cash:"maybe"}` → exception "commitment affects_deployable_cash must be a valid boolean, got: maybe" ✓. Valid forms (`"true"`, `"false"`, `"1"`, `"0"`, `"yes"`, `"no"`, `"on"`, `"off"`, case-insensitive) all pass the pre-cast check ✓. Repeat against `repair_commitments_for_week`'s insert path ✓

### AC-87: reflected_model_week on an active-status row is pinned to p_week_num in live save, but not in repair

Save insert: new commitment `{..., status:"initiated", reflected_model_week:5}` where `p_week_num=3` → exception "new commitment reflected_model_week (5) must equal p_week_num (3) for non-terminal status" ✓. Save patch: existing `status='initiated'` row, patch `{id:"...", reflected_model_week:5}` where `p_week_num=3` → exception "reflected_model_week (5) on non-terminal commitment (status=initiated) must equal p_week_num=3 — a live reconciliation can only mark a debit as reflected in the balance being entered this week, or explicitly clear reflected_model_week to null" ✓ (v3.12: expected string corrected to match the round-5 guard wording; the prior "on active-status commitment" text was stale and contradicted AC-43, AC-102, AC-103). Contrast: `repair_commitments_for_week` patch on an equivalent active-status row with `reflected_model_week` set to a week other than `p_week_num` → succeeds (repair's whole purpose includes recording that a commitment was reflected in a different week's balance than the one being repaired) ✓

---

## Acceptance Criteria — Round 4 Hardening (v3.9)

### AC-88: reflected-but-unresolved prior item appears in Phase 1 even though isReservedAsOf() is false

Setup: Week 3 item `status='initiated'`, `reflected_model_week=3` (set via a prior "already reflected" answer under `available_balance` basis), `resolved_model_week=null`, `origin_model_week=3`. At Week 4 reconciliation: `isReservedAsOf(c, 3) = false` (reflected at week 3, `weekNum=3`, so `reflected_model_week <= weekNum` → excluded from reserve math) — but the Phase 1 source query (`origin_model_week < current_week AND status NOT IN ('cleared','voided') AND resolved_model_week IS NULL`) still returns this row for Week 4's Phase 1 ✓. Confirms the row does not silently drop out of the reconciliation workflow just because it stopped being reserved.

### AC-89: user can mark a reflected-but-unresolved item cleared

Same setup as AC-88. Phase 1 Step 1 response "Cleared (reflected)" on this item → patch `{id:"...", status:"cleared", reflected_model_week:4, resolved_model_week:4, resolution_type:"cleared"}` → succeeds, subject to the same terminal week guards as any other Step 1 "Cleared" response (reflected/resolved both pinned to the current week, `current_week=4` here — note this legitimately *moves* `reflected_model_week` from 3 to 4, which is fine since the row is non-terminal going into the patch) ✓

### AC-90: user can keep a reflected-but-unresolved item reflected without a reserve (no-op acknowledgment)

Same setup as AC-88. Phase 1 Step 1 response "No change, still accurate" → no patch entry is sent for this item's `id` in `p_patched` ✓. The row's `reflected_model_week` remains 3, `isReservedAsOf(c, 4) = false` continues to hold, and the client-side Phase 1 gate still counts this item as "responded to" for Week 4's save despite zero server calls for it ✓

### AC-91: user can clear reflected_model_week back to NULL and the reserve becomes active again

Same setup as AC-88. Phase 1 Step 1 response "Still pending, no longer reflected — hold fell off" → patch `{id:"...", reflected_model_week: null}` (key present, JSON `null` — same key-existence mechanism as AC-8) → merged row has `reflected_model_week=NULL`, `status` unchanged (`initiated`). `isReservedAsOf(mergedRow, 4) = true` — the reserve is active again with no other field touched ✓

### AC-92: user can void or pay-from-other-account a reflected-but-unresolved item

Same setup as AC-88. Phase 1 Step 1 response "Void" → patch `{id:"...", status:"voided", resolved_model_week:4, resolution_type:"voided", resolution_notes:"no longer owed"}` → succeeds (`resolution_notes` required per v3.11 — see AC-110); `isReservedAsOf()` → false regardless of the pre-existing `reflected_model_week=3` (status=voided short-circuits before the reflected check) ✓. Repeat with "Paid from different account" → same result with `resolution_type:"paid_from_other_account"`, `resolution_notes` optional for this resolution_type ✓

### AC-93: cleared rejected when reflected_model_week > resolved_model_week

`validate_commitment_state(..., p_status:'cleared', p_reflected_model_week:5, p_resolved_model_week:4, p_resolution_type:'cleared', ...)` → exception "cleared requires reflected_model_week <= resolved_model_week" ✓. Reachable in practice only through `repair_commitments_for_week` (save's terminal week guards always force both fields equal to `p_week_num`, so `reflected > resolved` can't arise through save) — repair insert `{status:'cleared', reflected_model_week:5, resolved_model_week:4, ...}` where both weeks 4 and 5 have reconciliation rows (passing the existence guards) → still rejected by this new check ✓

### AC-94: cleared allowed when reflected_model_week < resolved_model_week

`validate_commitment_state(..., p_status:'cleared', p_reflected_model_week:3, p_resolved_model_week:4, p_resolution_type:'cleared', ...)` → passes (subject to the other cleared-status requirements) ✓. Matches the spec's own Week 3/Week 4 historical backfill example (Amex reflected at Week 3, resolved/cleared at Week 4).

### AC-95: cleared allowed when reflected_model_week = resolved_model_week

`validate_commitment_state(..., p_status:'cleared', p_reflected_model_week:4, p_resolved_model_week:4, p_resolution_type:'cleared', ...)` → passes ✓. This is the common case — save's live "Cleared (reflected)" response always produces this.

### AC-96: Phase 2 payload table — new-row branches match the documented shape exactly

For each of "Not paid yet," "Paid / initiated," "Bank pending," "Cleared / reflected," "Amount changed," and "Paid from a different account," staging a Phase 2 response produces exactly the `status` / `reflected_model_week` / `resolved_model_week` / `resolution_type` / `commitment_source` combination documented in the Phase 2 payload table, with no undocumented field left implicit ✓. "Amount changed" specifically: staged row has `original_amount_cents` set to the WD-expected amount and `amount_cents` set to the actual amount, satisfying AC-82's non-null-and-different requirement at insert time (not just at patch time) ✓

### AC-97: no Phase 2 branch for a protected WD obligation silently stages zero rows

**Rewritten in v3.12 — was stale.** The original AC-97 described the abandoned v3.9 "Skip / not due — stages no row, re-prompted in a future week" behavior. That behavior was removed in v3.10 (renamed to "WD event doesn't apply this week (mismatch)," staging an auditable `voided`/`voided` row) because a week-N WD event does not reappear in week N+1: `eid` bakes the model week into the event's identity (`{model_year}mw{model_week}_...`), so a silent skip made a `protected_required` obligation vanish with no trace. Leaving the old AC-97 in place contradicted AC-108, the Phase 2 payload table, and the v3.10/v3.11 body text. Restated as the invariant it should always have asserted.

Every Phase 2 response for a WD-tagged obligation stages exactly one `p_new_commitments` row — no branch stages zero rows. Specifically, "WD event doesn't apply this week (mismatch)" does **not** silently skip: it stages `{status:"voided", resolution_type:"voided", resolved_model_week:p_week_num, resolution_notes:"<explanation>", commitment_source:"wd_reconciliation"}`, with `resolution_notes` mandatory (client-side and server-side via `validate_commitment_state` — see AC-108, AC-110). After the reconciliation, the WD-tagged obligation's `eid` is present in `commitmentData` as an auditable row, not absent — a `protected_required` obligation (Amex, rent, tax transfer) can never disappear with a single click and no audit trail ✓. Enumerating the seven Phase 2 branches (Phase 2 payload table), all seven set "row created? = Yes"; none is a no-op skip ✓

### AC-98: malformed patch numeric/date field causes RPC failure (save)

`save_reconciliation_with_commitments` patch `{id:"<valid-uuid>", amount_cents:"abc"}` → Postgres cast exception (`invalid input syntax for type integer`), RPC call fails, no rows written ✓. Repeat for `reflected_model_week:"abc"`, `resolved_model_week:"abc"`, `cleared_date:"not-a-date"`, and `id:"not-a-uuid"` — each fails the call ✓. Confirms patch paths intentionally surface a raw-but-safe cast error rather than a custom message, per the accepted round-3 scoping decision.

### AC-99: malformed patch numeric/date field causes RPC failure (repair)

Same five malformed-field cases as AC-98, run against `repair_commitments_for_week`'s patch path ✓

### AC-100: weekly_reconciliations and commitmentData are unchanged after a malformed-patch failure

Setup: Week 5 has no existing `weekly_reconciliations` row. Call `save_reconciliation_with_commitments(p_week_num:5, ..., p_patched:[{id:"<valid-uuid-from-an-earlier-week>", amount_cents:"abc"}])` → call fails. After failure: no `weekly_reconciliations` row exists for Week 5 (the upsert that ran earlier in the same call was rolled back along with everything else — PL/pgSQL functions are atomic per call) ✓. Repeat with an existing Week 5 row already present before the call → that row is byte-for-byte unchanged after the failed call, not partially updated ✓. In both cases, `commitmentData` (re-fetched from `cash_commitments`) shows zero changes from any row touched earlier in the same failed call, including any `p_new_commitments` rows that were successfully inserted before the patch loop hit the malformed field ✓

### AC-101: UI keeps the form open and shows an error; no partial write is ever presented as saved

On any RPC error — including the malformed-patch cases in AC-98–100 — the client follows the existing "Other error" path (Save — RPC, step 4): show the error message, keep the reconciliation form open with the user's staged input intact, do not refresh `reconData`/`commitmentData`, do not call `runModel()`, do not close the form. The "Ok" path (step 5 — refresh, rerun, close) only executes after a genuinely successful RPC response. A user retrying after a malformed-field error is retrying against a database state identical to before their first attempt, not a partially-applied one ✓

---

## Acceptance Criteria — Round 5 Hardening (v3.10)

### AC-102: carried_unresolved is included in the non-terminal reflected-week guard

Existing row: `status='initiated'`, `reflected_model_week=3`, `resolved_model_week=null`, `origin_model_week=3`. Week 4 patch (Step 1 "Amount changed"): `{id:"...", status:"carried_unresolved", resolution_type:"amount_changed", amount_cents:620000, original_amount_cents:636848}` — **omits the `reflected_model_week:null` key**, reproducing the exact client-bug scenario that motivated this fix. Merged row: `status='carried_unresolved'`, `reflected_model_week=3` (retained, unpatched), `p_week_num=4`. The guard fires — `status NOT IN ('cleared','voided')` is true for `carried_unresolved`, `reflected_model_week=3 IS DISTINCT FROM p_week_num=4` — exception "reflected_model_week (3) on non-terminal commitment (status=carried_unresolved) must equal p_week_num=4 — a live reconciliation can only mark a debit as reflected in the balance being entered this week, or explicitly clear reflected_model_week to null" ✓. Row unchanged (patch failed before UPDATE committed).

### AC-103: carried_unresolved patch with stale reflected_model_week is rejected (contrast case)

Same setup as AC-102, but the patch instead explicitly re-sends the stale value: `{id:"...", status:"carried_unresolved", resolution_type:"amount_changed", amount_cents:620000, original_amount_cents:636848, reflected_model_week:3}` — same rejection as AC-102, confirming the guard catches both "omitted key, stale value retained" and "stale value explicitly resent" the same way ✓

### AC-104: carried_unresolved patch with reflected_model_week:null is accepted and the reserve is restored

Same setup as AC-102, corrected patch: `{id:"...", status:"carried_unresolved", resolution_type:"amount_changed", amount_cents:620000, original_amount_cents:636848, reflected_model_week:null}` (key present, JSON `null`) → merged row: `reflected_model_week=NULL` → guard's `reflected_model_week IS NOT NULL` condition is false, guard does not fire, patch succeeds ✓. `isReservedAsOf(mergedRow, 4) = true` — the amount-changed reserve is active again at the new amount ✓

### AC-105: Phase 2 bank_pending + available_balance + reflected "Yes" does not reserve

`balance_basis='available_balance'`, Phase 2 base response "Bank pending," follow-up "Yes": staged row `{status:"bank_pending", reflected_model_week:p_week_num, ...}` → insert succeeds (bank_pending is non-terminal, guard permits `reflected_model_week=p_week_num`) ✓. `isReservedAsOf(row, p_week_num) = false` — no double-subtraction against a debit the user has confirmed is already netted into the available balance ✓

### AC-106: Phase 2 bank_pending + available_balance + reflected "No" reserves

Same setup as AC-105, follow-up "No": staged row `{status:"bank_pending", reflected_model_week:null, ...}` → `isReservedAsOf(row, p_week_num) = true` — reserve stays active, matching pre-v3.10 default behavior ✓

### AC-107: Phase 2 bank_pending + available_balance + "Not sure" reserves and shows Review Required

Same setup as AC-105, follow-up "Not sure": staged row `{status:"bank_pending", reflected_model_week:null, ...}` — payload-identical to AC-106's "No" case, confirming the two only differ in why the user answered that way, not in what gets stored. `isReservedAsOf(row, p_week_num) = true` (conservative) ✓. Dashboard: `_hasBankPendingReserve=true` → `_reviewRequired=true` ✓

### AC-108: "WD event doesn't apply this week" stages an auditable voided row, not a silent skip

Phase 2 response "WD event doesn't apply this week (mismatch)" for a `protected_required` WD-tagged event (e.g. Amex payment) without a `resolution_notes` explanation → client-side blocked before an RPC call is even attempted, same as "Cleared + not reflected" (Phase 1). If the client-side block is bypassed or buggy, the RPC layer independently rejects it too — see AC-110. With a non-empty `resolution_notes`: staged row `{status:"voided", resolution_type:"voided", resolved_model_week:p_week_num, resolution_notes:"<explanation>", ...}` → insert succeeds ✓. The WD-tagged obligation now has a permanent, queryable row (`commitmentData` is not empty for this `eid`) instead of vanishing with no trace — confirms the v3.9 "no row staged, re-prompted later" design (which this replaces) is no longer in effect for this branch.

### AC-109: chk_cleared_reflected_before_resolved documentation states the rule in the correct direction

The prose accompanying `chk_cleared_reflected_before_resolved` reads "a cleared debit cannot first be reflected after it is resolved — reflection must occur at or before resolution, never after," matching the actual `CHECK` expression (`reflected_model_week <= resolved_model_week`) and the matching `validate_commitment_state` comment. This AC exists only to catch a documentation regression — no runtime behavior changed in this pass; the v3.9 rule was always correctly implemented, only its plain-English explanation was backwards.

---

## Acceptance Criteria — Round 6 Hardening (v3.11)

### AC-110: Phase 2 mismatch with status=voided/resolution_type=voided and missing resolution_notes is rejected by the RPC, not only client-side

Bypassing the client-side block entirely, call `save_reconciliation_with_commitments` directly: `p_new_commitments=[{..., status:"voided", resolution_type:"voided", resolved_model_week:p_week_num, resolution_notes:null}]` → exception "voided with resolution_type=voided requires non-empty resolution_notes". No row written ✓. Repeat with `resolution_notes` key omitted entirely, and with `resolution_notes:"   "` (whitespace only — caught by `btrim`) — both rejected the same way ✓

### AC-111: same, with notes, succeeds

Identical payload to AC-110 with `resolution_notes:"WD event mismatch — Amex due date was actually next week"` → insert succeeds ✓

### AC-112: repair voided/voided without notes is rejected

`repair_commitments_for_week` insert: `{..., status:"voided", resolution_type:"voided", resolved_model_week:p_week_num, resolution_notes:null}` (repair's "Void / was never owed" option) → exception "voided with resolution_type=voided requires non-empty resolution_notes". No row written ✓. Repeat for `repair_commitments_for_week`'s patch path: existing non-terminal row, patch `{id:"...", status:"voided", resolution_type:"voided", resolved_model_week:p_week_num}` with no `resolution_notes` → same rejection, patch fails, row unchanged ✓

### AC-113: repair voided/voided with notes succeeds

Same as AC-112 with `resolution_notes:"payment confirmed never issued"` on both the insert and patch variants → both succeed ✓

### AC-114: the resolution_notes requirement is not scoped to Phase 2 — Phase 1's plain "Void" is equally covered

Phase 1 Step 1 "Void" response on an existing commitment, patch `{id:"...", status:"voided", resolved_model_week:p_week_num, resolution_type:"voided"}` with no `resolution_notes` → rejected by the same `validate_commitment_state` check, same exception ✓. Confirms the rule applies uniformly by `(status, resolution_type)`, not by which UI flow produced the payload — there is no mechanism by which the RPC could distinguish "Phase 1 Void" from "Phase 2 mismatch" even if it wanted to, since both arrive as the identical `{status, resolution_type}` combination.

### AC-115: resolution_notes cannot be blanked out on an already-voided/voided row after the fact

Existing row: `status='voided'`, `resolution_type='voided'`, `resolution_notes='original explanation'` (already validated at creation). Patch `{id:"...", resolution_notes:""}` — `resolution_notes` is one of only two fields the terminal immutability guard allows patching on a terminal row (see section 7), so the field-level guard does not block this patch — but the post-UPDATE `validate_commitment_state()` call now runs against the merged row's new `resolution_notes=NULL` (`NULLIF('','')`), `p_status='voided'` (unchanged), `p_resolution_type='voided'` (unchanged) → exception "voided with resolution_type=voided requires non-empty resolution_notes". Patch fails, `resolution_notes` remains `'original explanation'` ✓. This wasn't explicitly asked for but falls directly out of implementing the rule inside `validate_commitment_state` rather than only as an insert-time check — the audit trail can't be erased later, not just skipped at creation.

### AC-116: paid_from_other_account remains exempt from the resolution_notes requirement

`{status:"voided", resolution_type:"paid_from_other_account", resolved_model_week:p_week_num, resolution_notes:null}` (or key omitted) → succeeds, both on insert and patch, both RPCs — confirms the requirement is scoped to plain `resolution_type='voided'` only, per the explicit scoping decision (this AC, not just prose, is the guardrail against someone later "fixing" this by requiring notes everywhere).

---

## SQL Files Required

| File | Purpose |
|---|---|
| `docs/phase-5f-1-preflight.sql` | Confirm `weekly_reconciliations` schema; `cash_commitments` not exist; `is_allowed_user`/`can_write_financials` exist; `week_num` unique on `weekly_reconciliations`; `validate_commitment_state` not exist |
| `docs/phase-5f-1-migration.sql` | ALTER `weekly_reconciliations` (balance_basis); CREATE `cash_commitments` + constraints + trigger; REVOKE ALL (PUBLIC/anon/authenticated) then GRANT SELECT; RLS; CREATE `validate_commitment_state` + REVOKE PUBLIC; CREATE `save_reconciliation_with_commitments` + REVOKE/GRANT; CREATE `repair_commitments_for_week` + REVOKE/GRANT |
| `docs/phase-5f-1-validation.sql` | Table exists, all columns, RLS policies, trigger, DB constraints; SELECT granted, INSERT/UPDATE denied, explicit REVOKE verified (has_table_privilege checks); all three functions exist; SECURITY DEFINER on two RPCs; SECURITY INVOKER on helper; PUBLIC execute revoked on all three; authenticated execute on two RPCs only; has_function_privilege checks for anon + authenticated on all three |
| `docs/phase-5f-1-rollback.sql` | DROP FUNCTION save_reconciliation_with_commitments; DROP FUNCTION repair_commitments_for_week; DROP FUNCTION validate_commitment_state; DROP TRIGGER; DROP FUNCTION fn_cash_commitments_set_updated; DROP TABLE cash_commitments; DROP COLUMN balance_basis |

---

## Files Changed (5F-1 Build)

| File | Change |
|---|---|
| `index.html` | PLAN_YEAR; commitmentData; isReservedAsOf(); getCashAvailabilityEngine(); loadAll() + backfill detection; runModel() engine + reconciledWeeks + remainingAdjustedSweep (clamped); 4-phase recon form + RPC save + conflict UX; repair form + repair RPC; dashboard + informational label + Review Required verdict |
| `test_regression.js` | AC-1 through AC-116 (116 new tests) |
| `docs/phase-5f-1-preflight.sql` | New |
| `docs/phase-5f-1-migration.sql` | New |
| `docs/phase-5f-1-validation.sql` | New |
| `docs/phase-5f-1-rollback.sql` | New |
| `docs/phase-5f-1-smoke-checklist.md` | New — Week 3 $10,265.40 hard gate |
| `docs/phase-status.md` | Add 5F-1 entry |

---

## Build Sequence (after 5E-7 and 5E-8 complete)

1. Add PLAN_YEAR constant to index.html
2. Tag WD protected outflow events with eid, cc, rod
3. Write and run phase-5f-1-preflight.sql — all checks must pass
4. Write and run phase-5f-1-migration.sql (REVOKE, table, trigger, RLS, helper, both RPCs)
5. Run phase-5f-1-validation.sql — all privilege and structural checks must pass
6. Implement isReservedAsOf()
7. Implement getCashAvailabilityEngine()
8. Add commitmentData + loadAll() + backfill detection + reconciledWeeks
9. Implement runModel() engine block + remainingAdjustedSweep (clamped) at all sweep sites
10. Implement 4-phase reconciliation form + save RPC + conflict UX
11. Implement repair mode form + repair RPC
12. Update dashboard: adjusted display, raw=informational, Review Required verdict
13. Write 116 regression tests — all 832 existing + 116 new must pass before smoke. 832 is the ground-truth baseline (`grep -c '^test(' test_regression.js` against the current file at spec time) — resolves the earlier 837/832 mismatch; re-run this grep immediately before build starts and treat its output, not this number, as the actual gate if the file has moved since this spec was written.
14. Browser smoke checklist — Week 3 backfill + $10,265.40 is a hard gate
15. Update phase-status.md
16. Commit and push

**Do not start until 5E-7 and 5E-8 are complete and committed.**

---

## Deep Analysis — Path to Build-Ready (added v3.10, at Adam's request)

This is five review rounds (v3.6 through v3.10), each finding real issues — not nitpicks, actual bugs. That pattern itself is data, and it's worth being direct about what it says rather than just fixing the next batch and moving on.

### What kind of bugs these actually were

Rounds 1–3 (v3.6–v3.8) found classic server-trust gaps: client-controllable audit fields, missing NULL checks, missing row locks, an unenforced source_account allowlist. That's a known category, mechanical to check for, and now closed — I re-verified in this pass (see "self-audit" below) that the pattern doesn't recur elsewhere.

Round 3 also introduced the balance-basis matrix (v3.8) to fix a real bug: `available_balance` reservation had no defined behavior and could double-subtract. That fix was correct in direction but under-specified in surface area, and **rounds 4 and 5 have each found a new edge case that fix created** — Phase 1's source query didn't account for the new reflected-but-non-terminal state (v3.9), and Phase 2's `bank_pending` branch and the "Skip" branch both had reasoning errors specific to the same feature (v3.10). Three consecutive rounds finding bugs in the same feature is a signal, not a coincidence: `available_balance` handling is the highest-complexity, highest-bug-density part of this spec, by a clear margin over everything else in 5F-1.

### Self-audit performed this round

Since the round-5 carried_unresolved bug was specifically "a status enumeration went stale," I grepped every explicit status `IN`/`NOT IN` list in this spec against what it should logically cover:

- Table `CHECK (status IN (...))` and `validate_commitment_state`'s enum-validity check — both intentionally exhaustive (list all 8 statuses), correct as full lists.
- The "active statuses: no resolved_model_week, no resolution_type" block — deliberately excludes `carried_unresolved` and `cleared`/`voided` because each has its own dedicated rule block with different requirements. Not an oversight; a different rule category.
- `resolved_at`/`resolved_by` population logic (4 call sites, insert + patch, both RPCs) — a deliberately curated 3-item list (`cleared`, `voided`, `carried_unresolved`) representing "audit-worthy transition," a different semantic than "non-terminal." Correct as-is.
- Terminal immutability guard (`status IN ('cleared','voided')`) — correct; `carried_unresolved` is intentionally excluded because it's still open, not terminal.
- The one bug: the live reflected-week patch guard, which needed "non-terminal" semantics but was written as a partial explicit list. Fixed, and now matches the phrasing already used one section above it.

No other instance of the same pattern found. I'm confident in this specific claim because I checked every status-list site in the file, not just the one ChatGPT flagged.

### A scope option worth deciding on explicitly, not by default

`available_balance` is optional in Phase 0 — `posted_current_balance` and `unknown` are the other two choices, and neither has generated a bug in five rounds of review. Given the concrete Week 3 example in this spec's own problem statement uses a posted balance, it's worth asking directly: how often do you actually reconcile against an available balance rather than a posted one? If the honest answer is "rarely, or I'm not sure yet," there's a real option here: ship 5F-1 v1 supporting `posted_current_balance` and `unknown` only, and gate `available_balance` behind a follow-up phase once the simpler two bases have run clean in production for a few weeks. That would cut the single largest source of edge cases out of the initial build without losing any capability you're not yet using, and it directly reduces the risk surface for the thing this system exists to protect — not overstating deployable cash. I'm not making this call for you — it's a real product tradeoff, not an engineering one — but I'd be doing you a disservice not to surface it plainly after watching it be the source of 3 of the last 3 rounds' findings.

### What I'd actually recommend instead of a round 6

Spec review has a diminishing-returns curve, and I think we're on the flat part of it now. The last two rounds found narrower, more specific issues than the first three — a good sign the bug density is dropping, but also a sign that the remaining bugs (if any) are the kind that are cheaper to find by running the thing than by reading it closer. Concretely, I'd:

1. **Build it.** Implement the 116 ACs as actual tests in `test_regression.js` before writing any of the 4-phase UI — the RPCs and `validate_commitment_state` are fully specified now and don't need another prose pass.
2. **Run the Week 3 Amex scenario for real** against a staging Supabase instance, not just as a spec-level AC — the smoke checklist's hard gate ($10,265.40) is the one number in this whole spec that has to be exactly right, and nothing catches a wiring mistake like running the actual numbers.
3. **Decide the `available_balance` scope question above before, not during, build** — it changes how much of Phase 1/2's UI work is in scope for v1.
4. **If you want one more review pass, point it at the client-side JS once it exists, not the spec again.** The spec-level bugs found so far were all things a careful implementer could also introduce fresh while translating this into `index.html` (e.g., the exact same "forgot to include a status in a list" mistake is just as easy to make in JS as it was in SQL) — a diff-level code review after a real implementation attempt will catch a different, probably more useful, set of issues than a sixth read of the prose.

### Addendum — round 6 happened anyway, at Adam's explicit request, and here's an honest read of what it found

Round 6 (v3.11) found: one real server-side enforcement gap (resolution_notes was described as mandatory but never actually enforced — a genuine miss, not a nitpick), one stale AC that would have shipped a test encoding wrong behavior (AC-43), and two more stale ACs found by auditing rather than being reported (AC-57, AC-92) — plus a one-line Scope summary that had drifted from the actual dashboard logic two rounds ago. That's a materially smaller and more mechanical batch than any prior round: no new design flaws, no new functional gaps, no new bug classes. It's exactly the "narrower, more specific" pattern predicted above, one round further along the curve.

I don't think a round 7 would find nothing — a spec this size, reviewed by prose alone, will probably always yield one more thing to someone looking hard enough. But the marginal issues at this depth (a doc-wording direction, a parameter that needed a default, a test payload missing one field) are no longer the kind that would produce wrong cash math or a silent data-integrity hole in production; they're the kind that would get caught in code review or by the regression suite itself the first time someone ran it. That's a different risk category than rounds 1–5 were catching, and it's the signal I'd use to actually stop: **this spec is build-ready now.** The `available_balance` scope decision above is the one thing I'd still want an explicit answer to before starting, not because leaving it in is wrong, but because it's a product call, not a spec-completeness one, and it's the only open question left that isn't mine to resolve by writing more prose.

My honest assessment: this spec is build-ready now, with the `available_balance` scope question above being the one open item I'd actually want a decision on before starting, not because the spec is wrong if you keep it in scope, but because keeping it in scope means the highest-risk part of the system is also the least battle-tested by review, and that's worth doing with eyes open rather than by default.
