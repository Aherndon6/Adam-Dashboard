# Herndon Financial OS — Phase Status

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
