# Herndon Financial OS — Phase Status

## Phase 5E-1 — SQL Foundation + Read-Only Register Shell
**Status:** Draft — pending approval and execution
**Date:** 2026-06-26

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

### Draft files (review only — not yet executed or committed)
- `docs/phase-5e-preflight.sql` — 9 pre-checks (P1–P7 + P5a/P6a FK constraint validation)
- `docs/phase-5e-migration.sql` — table, indexes, 1 RLS policy (SELECT only), trigger, SELECT grant, 13 post-migration validation queries (V1–V10 + V3a/V3b policy name/expression checks)
- `docs/phase-5e-rollback.sql` — safe teardown with Phase 5F warning
- `index.html` — 8 edit points (flag, loadAll condition, nav logic, Register tab, routing, state vars, `_loadTxLedger`, `_renderTxRegister`, topbar subtitle)
- `test_regression.js` — 20 new tests (5E1-01 through 5E1-20)
- `e2e.js` — 16 new tests (RG-1 through RG-16, Section RG)

### Execution gate (ordered — do not skip steps)
1. Run `docs/phase-5e-preflight.sql` — all P1–P7, P5a, P6a must return expected values
2. Run `docs/phase-5e-migration.sql` — migration is intentionally fail-loud (no IF NOT EXISTS)
3. Confirm all V1–V10, V3a, V3b return expected values
4. Only after all validations pass: enable flag in console for smoke test (do not change default)
5. Run manual smoke test below
6. Commit/push only after smoke is clean

**Do not enable `showTransactionLedger=true` in the live app (console or code) until steps 1–3 above are complete.**

### Manual smoke test (after migration + validations confirmed)
```js
FEATURE_FLAGS.showTransactionLedger = true;
await _loadSupabaseRegistries();
_rebuildBudgetCatByKey();
renderApp();
setSection('transactions');
setTxSubNav('register');
```
Expected: Transactions nav visible, Register tab active, account selector shows active accounts, empty state (no transactions yet), starting balance warning if null.

### Release gates (non-negotiable for all of Phase 5E)
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
