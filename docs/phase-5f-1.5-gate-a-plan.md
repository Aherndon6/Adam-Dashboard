> **Historical governance artifact — provenance only.** 5F-1.5 Gate A shipped and is live (2026-07-05/06; see CODEX_STATUS.md under the 5F-1.5 Gate A shipped record). This document is the original audit or plan and is not current implementation authority. Where it differs from shipped behavior, committed code, tests, AGENTS.md, and CODEX_STATUS.md govern. Retained for provenance and audit traceability.

# Phase 5F-1.5 Gate A Implementation Plan

Date: 2026-07-05. Plan only, no code changed. Baseline: working tree at `4a4e3ab`, static regression 1219, e2e knowns WC-3/BR-3 only. Applies approved OQ answers: income convention (OQ2), no reimbursement status tracking (OQ3), AMEX SQL held (OQ1).

## Commit A1 — Budget credits net into category actuals

### Exact changes (index.html only)

1. **Register-pass aggregation, `renderBudget()` lines ~6467-6480.**
   Current: `if(!(amt<0))return;` then `spentByKey[k]+=Math.abs(amt)`.
   New: drop the outflow-only guard; accumulate `spentByKey[k]+=(-amt)` for rows passing `_isCountableBudgetSpend` (outflow adds positive spend, credit subtracts). Update the 5E-9 comment block (lines 6467-6471) to state the net convention and cite 5F-1.5 item 2 / the RESY case.
   Recommended shape: extract this pass into a small pure function `_computeRegisterSpend(rows, catByKey)` placed next to `_isCountableBudgetSpend` (~line 7420), returning the per-key net map; `renderBudget` merges its output. Mirrors the 5E-9 convention (pure predicate + source-pattern wiring) and makes A1/A2 directly unit-testable instead of regex-only. Fallback if you want zero refactor: inline two-line change, source-pattern tests only.

2. **Expense row render, line ~6580.**
   Current: `(s>0?f(s):'—')` hides a negative net (credit exceeds spend).
   New: render nonzero values with explicit sign; negative net styled as a credit (green, minus sign). Zero stays `—` (preserves current skip-zero behavior at line 6564; a fully offset category with `b===0` still disappears — same as today, acceptable).
   No change needed to parent totals (6523-6541), grand totals (6584), or Remaining color logic (rem = b − s handles negative s correctly).

### Tests

- Rewrite `5E9-14` (test_regression.js ~7577): it asserts `if(!(amt<0))return;` and `Math.abs(amt)` — both intentionally removed. New assertions: net accumulation present, outflow-only guard absent.
- New `5F15-A1-xx` pure-function tests (if extraction accepted): RESY case (−72.50 spend +50 credit → 22.50 net), credit-only category (negative net), mixed categories, income/transfer/excluded rows ignored (delegates to `_isCountableBudgetSpend`, no predicate change — 5E9-01..12 stay untouched and green).
- Rewrite e2e `BUD-6` (e2e.js ~1542): its $15 inflow row is asserted "must not count" (85.66, not 100.66). Deliberate flip: now expects **70.66** (85.66 − 15.00). Jabian/Greenlight exclusion assertions unchanged. Comment updated to say the inflow-offset is 5F-1.5 behavior.
- `5E9-15/16/17` (no cleared filter, account-agnostic, loading gate) unaffected — verify green.

### Risk / rollback

Risk: low-medium. Two-line semantic change + one render condition; no fetch, no schema, no write path. Behavior change is user-visible by design (Wewe's Lunches drops by $50). Rollback: single `git revert`, no data impact.

## Commit A2 — Budget income actuals

### Exact changes (index.html only)

1. **Income accumulation, same Register pass.** Extend the A1 helper (or add a sibling pass) to also return `incomeByKey`: rows with `amount>0` whose raw `_categoriesCache` row is active, `is_leaf`, and `behavior_class` in (`income`,`commission_income`). `reimbursable_income` (Jabian Deposits, display_only) stays excluded. Negative rows on income keys (rare salary reversal) net against the key. Data source is the existing month-scoped `_budgetRegisterSpendCache` — **no fetch change**; `select=category_key,amount,transaction_date` already suffices. Uncleared rows count, consistent with spend convention.
2. **Income row render, lines ~6482-6505.** Per OQ2:
   - Spent cell (6495): `incomeByKey[c.key]` received amount; `—` when zero.
   - Remaining cell (6497): budget − received; positive = still expected (muted), negative = exceeded budget (green).
   - Total Income row (6500-6505): sums of the displayed rows only (production registry rows: `income.net_salary`, `income.net_salary_spouse`). Hidden income categories are NOT folded in silently, per OQ2.
3. **No change** to `_isCountableBudgetSpend`, the balance row (`budgetDiff`, 6597 — compares budget to budget, untouched), or `budget_transactions` pass.

### Tests

- New `5F15-A2-xx`: pure-function income map cases (salary inflow counted, commission_income counted, reimbursable_income excluded, outflow on income key nets, non-income inflow not in income map); source-pattern: income Spent cell no longer hardcodes `—`, Total Income sums displayed rows.
- Check `5B-xx`/`5E8-R20`-style slice-window tests near the income section for offset breakage (5E-9 precedent: widen windows, don't change assertions).
- e2e: extend `BUD-6` injection with a `income.net_salary` +$1,850 row and an income category in `_categoriesCache`; assert income actual renders and does not leak into expense spend.

### Risk / rollback

Risk: medium. New rendering semantics in the most-looked-at table; convention risk (does Wendy read "Remaining $X" on income as expected-still or error?) — mitigated by muted styling and the agreed convention. Rollback: single revert. Depends on A1's helper shape, so A2 lands after A1.

## Commit A3 — Goals Funding Plan now-marker fix

### Exact changes (index.html only)

- `_renderGoalsFunding()`: line ~4659 (`nowIdx2`) and line ~4670 (`nowIdx3`): `currentW-23` → `currentW-1`. Model week n maps to Cal Wk 22+n everywhere else in this function (line 4642, 4653); marker joins that convention. Today: model wk 5 → index 4 → Cal Wk 27. No other change; clamp bounds stay.

### Tests

- New `5F15-A3-01`: source-pattern — `_renderGoalsFunding` contains `currentW-1` twice and `currentW-23` zero times.
- Existing `getCalWeek` tests (lines 84-85) already pin the model→calendar mapping; no change.

### Risk / rollback

Risk: low. Display-only, two tokens. Independent of A1/A2 — can land first if you want a fast visible win for Wendy. Rollback: trivial revert.

## Commit separation and order

Three separate commits, in order **A3 → A1 → A2** (A3 is independent and zero-risk; A1 establishes the helper A2 extends; a credits regression stays bisectable from an income regression). A1+A2 must not merge: they change different user-facing semantics in the same table.

## AMEX Gold

Held per OQ1. When the value is confirmed: data-only UPDATE doc following `docs/2026-07-01-amex-gold-starting-balance-correction.sql` (preflight → guarded update → validation), stored as negative amount-owed. No SQL drafted until explicit approval.

## Stop conditions

- Any A2 ambiguity about income categories requiring a `categories` data change (e.g. a salary key missing/miscategorized in production) → stop, report, no SQL.
- Static suite must return to green (rebased count per AC-76 re-grep) before each commit; e2e delta limited to the deliberate BUD-6 rewrite plus knowns WC-3/BR-3. Any other e2e movement → stop.
- If slice-window test churn exceeds widening windows (i.e. assertions themselves would have to weaken) → stop and report instead of weakening.
- No touching: reconciliation internals, Review Required rendering, repair mode, WC-3, register code, report modal, 5F-2+.
- e2e run is manual (Adam, `node e2e.js`) — each commit ships with exact manual verification steps.
