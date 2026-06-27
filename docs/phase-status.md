# Herndon Financial OS — Phase Status

## Roadmap Sequence (as of 2026-06-27)

| Phase  | Name                                           | Status             |
|--------|------------------------------------------------|--------------------|
| 5E-1   | SQL Foundation + Read-Only Register Shell      | Complete           |
| 5E-2   | Transaction Writes                             | Complete           |
| 5E-3   | Register Live by Default                       | Complete           |
| 5E-4   | Budget Correctness + Display Fixes             | Complete           |
| 5E-5   | Budget Line Admin (required before 7/1)        | Complete (pending browser smoke) |
| 5E-6   | Role Enforcement / Security Maturity Gate      | Not started        |
| 5E-7   | 7/1 Wendy Operating Readiness                  | Not started        |
| 5E-8   | Category Registry Admin                        | Deferred (unless 7/1 blocker found) |
| 5F-0   | Needs Attention / Dashboard Usefulness         | Not started        |
| 5F-1   | Reconciliation Design + Read-Only Scaffold     | Not started        |
| 5F-2   | Reconciliation Writes                          | Not started        |
| 5G     | Splits                                         | Not started        |
| 5H     | Transfers                                      | Not started        |
| 5I     | Import Readiness                               | Not started        |
| 5J     | Budget Integration / Actuals                  | Not started        |

### Phase 5E-5 — Budget Line Admin (COMPLETE + HARDENED, 2026-06-27)
Minimal Budget Rule Admin UI inside the Budget tab.

**What shipped (base):**
- "Manage Lines" button in Budget header (write users only) — opens Add modal
- Inline "Edit" and "Archive" buttons on each budget line row (expense rows: both; income rows: Edit only)
- **Edit modal**: label + amount editable; scope locked to "from selected month forward" only
  - Closes prior active row at end of prior month (or deactivates if row started same month)
  - Inserts replacement row starting selected month, preserving original `end_month`
  - Income warning banner when editing income lines
  - Shows "Effective Range: From [month] through [end] / onward (open-ended)"
- **Add modal**: category key from existing `BUDGET_CATEGORY_REGISTRY` leaf keys only (no free-form keys)
  - Scope: one-time (start=end=month) or ongoing (start=month, end=null)
  - Keys with an active overlapping rule for selected month shown as disabled
- **Archive modal**: shows what will happen before confirming
  - Case A (has prior history): closes row at end of prior month, preserves all history
  - Case B (started this month): sets `is_active = false`
  - No hard delete under any circumstance
- After each save: reloads `budget_line_rules` cache from Supabase and re-renders Budget
- Total Income / Total Planned Budget / Budget Balance recalculate automatically after each change
- No auto-forcing rebalance — out-of-balance warning shown; Adam decides what to adjust
- `canWriteFinancials()` guards all `_blrOpen*` functions; unauthenticated users see no admin controls

**Hardening patch (same commit session):**
- `_blrDupCheck` (point-in-time) replaced by `_blrHasOverlap` (full interval overlap)
  - Two intervals overlap when `new_start <= existing_end AND existing_start <= new_end`
  - Open-ended rows use FAR sentinel `9999-12-01` for comparison
  - One-time July add correctly does NOT conflict with an August-forward row
  - Ongoing July-forward add correctly IS blocked by an August-forward row
- `_blrSaveEdit`: replacement row now inherits `currentRow.end_month` (not hardcoded null)
- `_blrSaveEdit`: best-effort rollback — if replacement INSERT fails after the close/deactivate PATCH succeeds, attempts to restore the prior row to its original state; error message distinguishes clean rollback from double-failure
- `_blrSaveEdit`, `_blrSaveAdd`, `_blrSaveArchive`: all have direct `canWriteFinancials()` guards (defense-in-depth; RLS is the real gate)
- Add modal dropdown disable: updated to use `_blrHasOverlap` for point-in-month check
- Smoke checklist AC-10a added: edit a bounded row, confirm January (after end_month) stays clean

**Regression tests:**
- 18 base tests (5E5-01 through 5E5-18)
- 10 hardening tests (5E5-H01 through 5E5-H10)
- **28 total 5E-5 tests; 813/813 full suite passing**

**Explicit scope limitations (documented, deferred to 5E-6):**
- "Selected month only" edit (three-row split) NOT in 5E-5 — too risky for 7/1
- New category creation (keys not in `BUDGET_CATEGORY_REGISTRY`) NOT in 5E-5
  - New category creation requires Category Registry Admin (Phase 5E-6 or later)
  - Any key not in BUDGET_CATEGORY_REGISTRY will not render in the Budget table

**No schema change.** All operations use existing `budget_line_rules` table and REST API.

**Gate:** Must complete browser smoke checklist (AC-1 through AC-10a) before 5E-6.

---

### Phase 5E-4 — Budget Correctness + Display Fixes (COMPLETE, 2026-06-27)
**What shipped:**
- Fixed Budget topbar subtitle (was bleeding Register account name)
- Removed `misc.goal_sweep` exclusion from totals — now included in Total Planned Budget
- Renamed "Monthly Living Expenses (excl. goal sweep)" to "Total Planned Budget"
- Budget balance row drives from `incomeTotal` (from budget lines), not hardcoded $15,938
- Out-of-balance warning: amber banner + explanation when plan ≠ income
- Balanced confirmation: green checkmark when plan = income
- `misc.goal_sweep` row annotated as "(flexible sweep line)"
- Help text updated: Extra Pay is the usual sweep line; Misc → Extra or other discretionary can also absorb changes
- Reconciliation section on Budget annotated with transitional note (moves to Transactions in 5F-2)
- July SQL patch: `docs/phase-5e-4-july-budget-patch.sql` — closes $2,300 goal_sweep at June, opens $1,450 for July+
- 12 new static regression tests (5E4-01 through 5E4-12); 785/785 passed
- Updated stale tests: 5B-24 (label change), 5E1-01 (flag now defaults true)

**Non-goals:** No `_getBudgetLivingExpenses()` changes (feeds runModel — untouched). No new schema. No Budget Line Admin UI (that's 5E-5).

---

### Phase 5E-6 — Role Enforcement / Security Maturity Gate (PLANNED, NOT STARTED)
Absorbs deferred Phase 4C. Must complete before reconciliation, splits, imports, transfers, or budget integration.

**Purpose:** Formalize and verify role-based write access across all current policies before the schema grows further.

**Scope:**
- Document role/capability matrix: owner (Adam), household_admin (Wendy), viewer (future read-only)
- Audit all write policies and classify by predicate:
  - `is_allowed_user()` = read access only — must not appear on any write policy
  - `can_write_financials()` = household financial writes (transactions, budget line rules)
  - `is_owner()` = owner-only admin/config/sensitive writes (accounts, categories, budget tables)
- Confirm no write policy uses `is_allowed_user()`
- Confirm Wendy can write only to intended household financial workflows
- Confirm viewer role (when added) can read but cannot write
- Confirm owner-only tables remain owner-only
- Add SQL preflight, validation, and smoke scripts
- Update docs with role matrix

**Non-goals (explicit exclusions):**
- No new app features
- No Budget math changes
- No `budget_transactions` changes unless audit proves a policy is wrong and change is explicitly approved

**Gate:** 5E-6 must pass before any of 5F-0, 5F-1, 5F-2, 5G, 5H, 5I, or 5J begins.

**Do not start until 5E-5 browser smoke passes.**

---

### Phase 5E-7 — 7/1 Wendy Operating Readiness (PLANNED, NOT STARTED)
Confirm the system is operationally ready for Wendy to use as of July 1.

**Scope:**
- July budget sanity check (totals, balance, key rows)
- Wendy workflow smoke: transaction entry, cleared toggle, Budget view
- Budget edit workflow verified (Edit/Archive tested against real July data)
- Transaction entry verified (add, edit, delete manual rows)
- Reconciliation transition note visible and accurate
- Known limitations documented (no splits, no transfers, no imports, no reconciliation yet)
- No major new feature build unless a readiness blocker is found during this phase

**Gate:** Unblocked after 5E-6 passes. No code changes expected unless a blocker surfaces.

---

### Phase 5E-8 — Category Registry Admin (DEFERRED)
New category creation UI (keys not in `BUDGET_CATEGORY_REGISTRY`). Deferred unless a 7/1 blocker is found from missing registry keys.

**If triggered:** adds a Category Registry Admin panel to create new leaf keys and register them in the JS `BUDGET_CATEGORY_REGISTRY`. Scope TBD at that time.

---

### Phase 5F-0 — Needs Attention / Dashboard Usefulness (PLANNED, NOT STARTED)
Lightweight actionable summary panel — not a full dashboard redesign.

**Scope:**
- Budget out-of-balance alert
- Over-budget / near-limit categories
- Pending/deferred items (if already supported by existing data)
- Unreconciled/uncleared items (if already supported by existing data — no reconciliation migration)

**Non-goals (explicit exclusions):**
- No reconciliation migration or new reconciliation workflow
- No broad dashboard redesign
- No new schema

**Gate:** Unblocked after 5E-6 passes. Does not require 5F-1 or 5F-2.

**Do not start until explicitly approved.**

---

## Phase 5E-3 — Production Enablement
**Status:** Complete
**Date:** 2026-06-27

### What shipped
- `showTransactionLedger` flipped to `true` as production default
- Register tab now live for all users on page load — no console JS required
- Live smoke passed: Adam add/edit/cleared/delete, Wendy add — all confirmed

---

## Phase 5E-2 — Transaction Writes
**Status:** Complete
**Date:** 2026-06-27
**Commit:** 40fdf28 + a8d2b19

### Final confirmed state (post-migration)
- Static regression: 773/773 passed
- Playwright E2E: 114/114 passed
- Supabase migration applied: 3 write policies, column grants, ALTER POLICY hardening
- VM1-VM12: all 12 passed (VM6/VM8 updated to verify RLS policy content vs. column grants)
- VM6/VM8 note: Supabase grants ALL to authenticated at table level by default; column-level
  grant restriction is not achievable — security enforced via RLS. INSERT policy hardened
  with user_id = auth.uid() check via ALTER POLICY on 2026-06-27.
- showTransactionLedger still default false — enable for live smoke only

### What was built
- DB: 3 write policies using `can_write_financials() AND source='manual'` (INSERT, UPDATE, DELETE)
- DB: Column-level grants — INSERT (8 cols, excludes user_id/notes/id/timestamps), UPDATE (6 mutable cols only), DELETE (table-level)
- UI: Add Transaction form (date, payee/memo, outflow/inflow mutual exclusion, category, cleared)
- UI: Edit Transaction — pre-populated form via `_openTxForm('edit', tx)`
- UI: Delete Transaction — inline confirmation strip per row
- UI: Cleared toggle — checkbox per manual row, fires PATCH immediately
- UI: Non-manual rows (source ≠ 'manual') show no edit/delete controls; cleared is read-only
- UI: One active action at a time (opening add/edit clears delete confirm and vice versa)
- UI: Three-way saving state (_txFormSaving, _txDeleteSaving, _txClearedSavingId) with finally blocks
- Topbar subtitle: "Adding transaction — [account]" / "Editing transaction — [account]" during write modes

### Files changed (pending commit)
- `index.html` — state vars, helper functions, `_saveTxForm`, `_deleteTxConfirm`, `_toggleTxCleared`, `_renderTxRegister` rewrite, topbar subtitle
- `test_regression.js` — 28 new tests (5E2-01 through 5E2-28)
- `e2e.js` — 16 new WR tests (WR-1 through WR-16); RG-7b, RG-11, RG-15 updated for 5E-2 behavior
- `docs/phase-5e-2-preflight.sql` — VP1–VP5 + can_write_financials() source inspection
- `docs/phase-5e-2-migration.sql` — 3 write policies, column grants, VM1–VM12 validation UNION ALL
- `docs/phase-5e-2-rollback.sql` — REVOKE mirroring grants + RB1–RB5 verification

### Next steps before enabling write UI
1. Commit this state
2. Run `docs/phase-5e-2-preflight.sql` in Supabase — all VP1–VP5 must pass
3. Run `docs/phase-5e-2-migration.sql` in Supabase
4. Run VM1–VM12 UNION ALL validation — all must return expected values
5. Live smoke: add, edit, cleared toggle, delete, Wendy insert, unauthenticated blocked, protected-column PATCH rejected
6. 5E-3: Wendy handoff / production enablement (showTransactionLedger=true by default)

### Write predicate decision
- `can_write_financials()` = owner (Adam) + household_admin (Wendy)
- `is_owner()` rejected — blocks Wendy
- `is_allowed_user()` rejected — too permissive for future viewer roles
- Policies named `financial_writer_*` (not `owner_*`) to match actual predicate

### Non-goals (explicit exclusions)
- No changes to runModel() or Budget math
- No changes to budget_transactions
- No reconciliation workflow
- No transaction_splits table
- No mobile layout changes
- No notes field UI (column exists; UI deferred)
- No import/migration rows editable via UI (source='manual' guard)

---

## Phase 5E-1 — SQL Foundation + Read-Only Register Shell
**Status:** Complete
**Date:** 2026-06-27
**Commit:** 1675548

### Final confirmed state
- Static regression: 733/733 passed
- Playwright E2E: 90/90 passed
- Preflight (P1–P7, P5a, P6a): all passed
- Migration: passed (fail-loud, no IF NOT EXISTS)
- Post-migration validations (V1–V10, V3a, V3b): all passed
- Live smoke on dashboard.herndons.us: passed
- `showTransactionLedger` returned to default `false` after smoke
- Production default behavior restored
- Working tree: clean

### What shipped
- `transactions` table live in production with RLS enabled
- `allow_read` SELECT-only policy using `is_allowed_user()`
- `GRANT SELECT` only — no write policies or grants
- `showTransactionLedger` feature flag (default `false`)
- Read-only Register shell: account selector, starting balance warning, empty/loading/error states, category label resolution, topbar subtitle
- 20 static regression tests (5E1-01 through 5E1-20)
- 17 Playwright E2E tests (RG-1 through RG-16 + RG-7b)
- `docs/phase-5e-preflight.sql`, `docs/phase-5e-migration.sql`, `docs/phase-5e-rollback.sql`

### Scope (5E-1 only)
- `transactions` table, indexes, constraints, RLS (1 SELECT policy — least privilege), trigger, `GRANT SELECT` only
- `showTransactionLedger` feature flag (default `false`)
- Register tab activates when `showTransactionLedger=true`; stays disabled span otherwise
- Account selector populated from `_accountsCache`
- Starting balance row: shows value or explicit "Starting balance not set — running balance starts from $0.00" warning
- Read-only transaction list (fetched via Supabase, 500-row query-level limit, deterministic sort)
- Loading / error / empty states
- Topbar subtitle for register sub-nav

### Not in 5E-1
- Add / edit / delete — Phase 5E-2
- Cleared toggle/write operation — Phase 5E-2 (cleared status is displayed read-only in 5E-1; the write toggle is deferred)
- `transaction_splits` table — deferred until split UI is scoped
- Transfer UI — deferred
- `reconciled` column surfaced — Phase 5F
- Starting balance editing
- Budget math changes — non-negotiable exclusion
- `budget_transactions` changes — non-negotiable exclusion
- Mobile layout — non-negotiable exclusion

### Files shipped (commit 1675548)
- `docs/phase-5e-preflight.sql` — 9 pre-checks (P1–P7 + P5a/P6a FK constraint validation)
- `docs/phase-5e-migration.sql` — table, indexes, 1 RLS policy (SELECT only), trigger, SELECT grant, 13 post-migration validation queries (V1–V10 + V3a/V3b policy name/expression checks)
- `docs/phase-5e-rollback.sql` — safe teardown with Phase 5F warning
- `index.html` — 8 edit points (flag, loadAll condition, nav logic, Register tab, routing, state vars, `_loadTxLedger`, `_renderTxRegister`, topbar subtitle)
- `test_regression.js` — 20 new tests (5E1-01 through 5E1-20)
- `e2e.js` — 16 new tests (RG-1 through RG-16, Section RG)

### Standing constraints (non-negotiable for all of Phase 5E)
- No changes to `runModel()` or any Budget math function
- No changes to `budget_transactions` table, schema, or queries
- No reconciliation workflow of any kind
- No migration or mapping between `budget_transactions` and `transactions`
- No default flag changes in production
- No mobile layout expansion
- No `transaction_splits` table until splits UI is explicitly scoped

---

## Phase 5D-2 Slice 1 — Read-Only Transactions Section
**Status:** Complete (pending your push after manual smoke)
**Date:** 2026-06-26

### What was built
- `FEATURE_FLAGS.showTransactionSection` — default `false`; all new UI hidden when off
- Supabase registry load condition updated: fires when `useSupabaseRegistries || showTransactionSection`
- Transactions nav item in sidebar only (desktop-only, Slice 1 decision — no `mob-bottom-nav` entry)
- `s-transactions` section div + `SECTION_TITLES.transactions`
- Topbar subtitle for Transactions section (accounts count / active category count)
- `renderTransactions()` — shell + sub-nav (Accounts | Categories | Register — Phase 5E | Reconciliation — Phase 5F)
- `_renderTxAccounts()` — read-only table: label, institution, type, lifecycle badge, in budget, in cashflow, starting balance ("Balance not set" for null), notes row
- `_renderTxCategories()` — read-only table: key, label, status, behavior, budget treatment, cashflow, budget_line_key, budget_group_key; lifecycle toggle (active-only default / show all); merged row badge with merged_into_key arrow
- `_txLifecycleBadge()` — inline badge for active/hidden/view_only/closed/excluded/archived/merged
- 26 new regression tests added to `test_regression.js` (5D2-01 through 5D2-26)
- 10 new Playwright E2E tests added to `e2e.js` (TX-1 through TX-10, Section TX)

### No DB changes
Phase 5D-2 Slice 1 is pure JS/HTML. No schema changes, no seeds, no migrations. Rollback = set `showTransactionSection: false` in console or revert `index.html`.

### Test results
- **Syntax check:** PASS
- **713/713 static regression tests passed** (687 pre-existing + 26 new 5D2 tests)
- **Production behavior unchanged:** both flags default false, no Supabase load fires, no Transactions nav visible
- **Playwright E2E (TX-1 through TX-10):** Added to `e2e.js` Section TX. Must run from your terminal (`node e2e.js`) — Chromium binaries not in sandbox. Tests use injected mock data; no Supabase connection required. Coverage: flag=false default gate, Accounts table 7-column render, "Balance not set" for null balances, lifecycle badge CSS vars, Categories active-only filter (merged row absent), show-all toggle (merged row visible with amberSoft badge + merged_into_key), 8-column categories table with budget_group_key, future disabled tabs with correct phase labels and cursor:not-allowed, flag reset behavior (nav hides + budget intact), desktop-only enforcement (no mob-nav-transactions).

### Manual smoke test
In console after login:
```js
FEATURE_FLAGS.showTransactionSection = true;
await _loadSupabaseRegistries();
renderApp();
setSection('transactions');
```

Expected:
- Accounts tab: 14 rows, Costco Visa = "hidden" badge, Fidelity = "view only" badge, all show "Balance not set"
- Categories tab active-only: 50 rows, `business.jabian_2026_dup` absent
- Categories tab "Show all lifecycle states": 51 rows, `business.jabian_2026_dup` visible with merged badge + `→ business.jabian_consulting_2026` arrow
- `health_fitness.flexible_spending_2026`: `reimbursable_expense`, `excluded`, `reimbursable`, no budget_line_key
- Register tab: disabled, labeled "Register — Phase 5E"
- Reconciliation tab: disabled, labeled "Reconciliation — Phase 5F"
- Switch back to `showTransactionSection=false`: Transactions nav disappears, no Supabase load on next page reload

### Mobile handling decision (Slice 1)
Transactions is desktop-only. The sidebar (containing `nav-transactions-wrap`) is hidden at ≤900px viewport via CSS; `mob-bottom-nav` has no Transactions entry. Mobile users cannot navigate to the section. This is intentional for Slice 1. Phase 5E or later should evaluate mobile-appropriate layout before adding a mob-nav entry.

---

## Phase 5D-1 — Supabase Registry Foundation
**Status:** Complete  
**Date:** 2026-06-26

### What was built
- `accounts` table (14 rows seeded: 12 active, 1 view_only, 1 hidden)
- `categories` table (51 rows seeded: 50 active, 1 merged)
- RLS policies on both tables using `is_allowed_user()` (SELECT) and `is_owner()` (INSERT/UPDATE/DELETE)
- `fn_set_updated_at()` trigger function + triggers on both tables
- `useSupabaseRegistries` feature flag (default `false`) in `index.html`
- Registry load helpers: `_loadSupabaseRegistries`, `_getActiveCategoryRegistry`, `_getPaymentAccountOptions`, `_rebuildBudgetCatByKey`, `_normalizeCatRow`
- All 8 `BUDGET_CATEGORY_REGISTRY` / `BUDGET_PAYMENT_ACCOUNTS` call sites replaced with flag-aware getters
- Preflight file: `docs/phase-5d-1-preflight.sql`
- Rollback file: `docs/phase-5d-1-rollback.sql`

### Migration execution — preflight findings and corrections
Two issues caught by preflight before the migration ran:

1. **Diablos/GLP rows already existed** in `budget_line_rules` before Phase 5D-1.  
   Migration's `WHERE NOT EXISTS` guards correctly skipped both inserts.  
   Rollback Step 3 changed to no-op — those rows pre-existed and must not be deleted on rollback.

2. **`get_my_role()` does not exist** in this project.  
   All existing write-guard policies use `is_owner()` (budget_line_rules, budget_transactions, etc.).  
   RLS policies corrected from `get_my_role() = 'owner'` → `is_owner()` before migration ran.

### Validation results
All V1–V15 queries passed post-migration.

### Test results
- **flag=false regression:** 687/687 passed. Production behavior unchanged.
- **flag=true Supabase smoke:**
  - 14 accounts loaded
  - 51 raw categories in DB
  - 50 active categories returned by `_getActiveCategoryRegistry()`
  - `business.jabian_2026_dup` (merged) excluded from active registry and dropdowns
  - Costco Visa exists as `hidden`; excluded from Supabase-powered payment dropdowns

### Rollback scope note
`docs/phase-5d-1-rollback.sql` is intended for **immediate Phase 5D-1 rollback only**, before any later phase adds FK references or application logic that depends on `accounts` or `categories`. Once Phase 5E or later is applied, the rollback file must be extended before use.

---

## Phase 5C — Architecture Design and Discovery
**Status:** Complete (design frozen, Phase 5D-1 built from this)

Design documents: `docs/phase-5c-architecture-design.md`, `docs/phase-5c-discovery-checklist.md`
