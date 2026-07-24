# `public.categories` — Write-Surface Disposition (RESTRICTED)

**Date:** 2026-07-23 · **Type:** governance disposition.
**Documentation only — no code, schema, SQL, application, production-data, or financial change is made
by this record. It authorizes no execution.**
**Trigger:** Step 6A finding **L-4** (the Alaska goal-funding transfer categorized as trip spending)
required a taxonomy change, which revealed that `public.categories` is **not among the 11 write surfaces**
enumerated in `docs/phase-5g-1d-gatec-register-2026-07-13.md`. Its posture had never been dispositioned.

---

## 1. Verified current posture (read-only inspection, 2026-07-23)

### 1.1 Database tier — RLS

`public.categories` already carries four RLS policies. **All are owner-gated except read.**

| policy | operation | role | predicate |
|---|---|---|---|
| `categories_select` | **SELECT** | `authenticated` | `is_allowed_user()` — allowed authenticated users may read |
| `categories_insert_owner` | **INSERT** | `authenticated` | `is_owner()` — **owner only** |
| `categories_update_owner` | **UPDATE** | `authenticated` | `is_owner()` (USING and WITH CHECK) — **owner only** |
| `categories_delete_owner` | **DELETE** | `authenticated` | `is_owner() AND is_system = false` — **owner only, and limited to non-system rows** |

A `BEFORE UPDATE` trigger `trg_categories_updated_at` maintains `updated_at` via `fn_set_updated_at()`.

### 1.2 Application tier — no write path exists

- `index.html` references `/rest/v1/categories` **exactly once** (line 9352) — a `GET` inside
  `_loadSupabaseRegistries()`.
- **No mutation function exists**: no `addCategory`, `createCategory`, `saveCategory`, `editCategory`,
  or `archiveCategory`.
- The Categories view is read-only by design — *"Read-only Accounts and Categories views… **No
  add/edit/archive in Slice 1**"* (`index.html:6783`) — and sits behind
  `FEATURE_FLAGS.showTransactionSection`, which is `false` in production.
- `index.html:9700` states the boundary directly: *"New category creation deferred to Phase 5E-6 /
  Category Registry Admin."*
- **Category Registry Admin remains DEFERRED** — `docs/phase-status.md`, item **5E-9**.

---

## 2. Disposition: **RESTRICTED**

Taxonomy is low-frequency, high-blast-radius reference data feeding Budget classification and the
Register category picker. Until Category Registry Admin exists, every change is governed as a package:

1. **Owner-authorized package only** — no ad-hoc edits.
2. **Owner session** — `is_owner()` at the RLS tier; already enforced.
3. **Controlled SQL-editor (or equivalent owner-only) execution.** **The SQL Editor is required for
   multi-row atomic execution, not for permission.** PostgREST cannot wrap a multi-statement taxonomy
   change in a single transaction, so a mid-package failure could otherwise leave taxonomy half-applied.
4. **Mandatory** preflight, in-transaction assertions, validation, evidence capture, and a rollback
   path — all present in the package **before** execution.
5. **No general authenticated application grant** is added while 5E-9 is unbuilt.
6. **Revisit when 5E-9 (Category Registry Admin) is implemented**, at which point the disposition is
   expected to become *wrap* — a governed RPC or admin UI replacing the SQL-editor package.

### 2.1 What this disposition does and does not do

- **No new grant is being created.** All four policies already exist.
- **No existing permission is being broadened.** Nothing is added, relaxed, or widened in role scope.
- **Taxonomy mutations remain owner-authorized and package-governed.**
- This record **confirms and documents the existing owner-gated posture**; it weakens nothing.

---

## 3. Approved category definitions (recorded; created by PKG-TAX-1 under its own authorization)

Both are **owner-defined, assignable transfer categories**, excluded from Budget and from cash-flow
treatment.

| field | `transfers.goal_funding` | `transfers.goal_disbursement` |
|---|---|---|
| `label` | **Goal Funding Transfer** | **Goal Disbursement Transfer** |
| `parent_key` | `transfers` | `transfers` |
| `is_leaf` | `true` | `true` |
| `behavior_class` | `transfer` | `transfer` |
| `budget_treatment` | `excluded` | `excluded` |
| `cashflow_treatment` | `excluded` | `excluded` |
| `lifecycle_status` | `active` | `active` |
| `is_system` | `false` | `false` |

### 3.1 Why these values

- **Assignable in Register.** `_normalizeCatRow` derives
  `assignable = is_leaf AND lifecycle_status='active' AND behavior_class <> 'savings_allocation' AND
  budget_treatment <> 'planned_allocation'`. Both rows satisfy it, so both appear in the Register
  category picker **with no code change** (`FEATURE_FLAGS.showTransactionLedger = true` runs
  `_loadSupabaseRegistries()`, and the picker filters `_categoriesCache` on `leaf && assignable`).
- **Excluded from Budget.** `_isCountableBudgetSpend` returns `false` on `behavior_class='transfer'`,
  and again on `budget_treatment='excluded'`. `_isCountableBudgetIncome` returns `false` because
  `transfer` is not an income class. Neither category can ever count as spending or income.
- **Excluded from cash-flow treatment.** `cashflow_treatment='excluded'` matches the working precedent
  `transfers.greenlight`.
- **`is_system = false` is load-bearing, not cosmetic.** `categories_delete_owner` requires
  `is_system = false`; a category created with `true` **could not be rolled back under RLS**.

### 3.2 Operating convention — funding and disbursement are distinct lifecycle events

**These are two different economic events and must not be merged into one category.**

| | `transfers.goal_funding` | `transfers.goal_disbursement` |
|---|---|---|
| direction | checking **→** goal holding account | goal holding account **→** checking |
| meaning | an **appropriation** — Funded increases | a **release** — cash leaves the goal for its purpose |
| four-quantity model | contributes to **Funded** (monotonic) | contributes to **Released**; reduces **Custody** |
| Register sign | outflow from checking (negative) | inflow to checking (positive) |

Funding is *historical achievement* and never decreases because money was spent; disbursement is the
settlement of a goal's purpose. Collapsing them into a single category would erase the distinction the
Step 6B domain model depends on — the same distinction whose absence produced Step 6A finding **C-2**.
The sign of the amount is **not** an adequate substitute, because a refund or reversal can invert it.

`transfers.goal_disbursement` is expected to hold **zero rows** until the first goal release is
recorded. An empty category is the correct state, not a defect.

---

## 4. Operational notes

- Rollback of a category creation is directly executable **only while no row references it**. Once
  dependants exist, rollback requires a **dependency scan and recategorization of every dependent row
  before deletion**.
- `updated_at` on any recategorized transaction advances via `set_transactions_updated_at` and is **not
  restorable**; a rollback restores `category_key`, not the original timestamp.

---

## 5. Scope and sequencing

This record dispositions a write surface. **It authorizes no execution.**

The first package to be executed under it is **PKG-TAX-1** (goal-transfer taxonomy remediation), which
carries its **own separate authorization**. The documentation change and the production SQL execution are
deliberately **not** combined into one approval.

`docs/execution-ledger.md` receives a row **only when PKG-TAX-1 actually runs** — that ledger records
SQL executed against production, and this record executes nothing.

---

## Cross-references

- Gate-C write-surface register: `docs/phase-5g-1d-gatec-register-2026-07-13.md`
- Step 6A production evidence (finding L-4): `docs/phase-5g-1d-step6a-production-evidence-2026-07-23.md`
- Step 6B canonical plan (balance-free allowlist, four-quantity model):
  `docs/phase-5g-1d-step6b-canonical-plan-2026-07-23.md`
- Alaska interim operating decision: `docs/phase-5g-1d-alaska-interim-operating-decision-2026-07-23.md`
- Category Registry Admin deferral: `docs/phase-status.md` (item 5E-9)
