# Herndon Financial OS — Phase Status

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

### No DB changes
Phase 5D-2 Slice 1 is pure JS/HTML. No schema changes, no seeds, no migrations. Rollback = set `showTransactionSection: false` in console or revert `index.html`.

### Test results
- **Syntax check:** PASS
- **713/713 regression tests passed** (687 pre-existing + 26 new 5D2 tests)
- **Production behavior unchanged:** both flags default false, no Supabase load fires, no Transactions nav visible

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
