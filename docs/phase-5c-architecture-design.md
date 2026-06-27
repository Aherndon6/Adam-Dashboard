# Herndon Financial OS — Phase 5C Architecture Design
_Status: DESIGN ONLY — no code written_
_Version: 3.5 (architecture freeze — consistency pass complete — June 26, 2026)_

---

## Purpose

Full architecture for the transaction, account, category, budget, reconciliation, goal-linked spending, and import layers of the Herndon Financial OS. Design input for Phases 5D through 5J. No code changes are made in this phase.

---

## Core Architectural Principles

1. **Transaction splits are the atomic unit.** Budget treatment, goal linkage, and reimbursable logic live at the split line. A single transaction may have multiple splits with different behaviors. Schema supports multiple splits from day one; UI starts with one.

2. **Categories drive behavior.** Users pick a category. The system derives form behavior, budget treatment, cashflow treatment, and goal linkage from the category definition. Users never see "transaction type."

3. **Three distinct concepts — category, budget line, budget group — must not be collapsed.** A category is Wendy's transaction classification. A budget line is a monthly planning/control unit. A budget group is a display/reporting grouping. Many categories may roll into one budget line; many budget lines may roll into one group. These are separate concerns.

4. **Transactions is the primary nav section; accounts are the left-side navigation within it.** The job-to-be-done is transaction management. Budget consumes transaction data; it does not own the transaction workflow.

5. **One transaction row, one or more split rows.** Normal transactions have one split. Multi-category transactions have multiple splits summing to the parent total.

6. **Budget reads from transactions (Phase 5G).** Until then, `budget_transactions` and `transactions` coexist. Migration is explicit, validated, and reversible.

7. **The 31-week cash flow model is untouched and protected by an explicit integration contract.** See the Cashflow Integration Contract section.

8. **Design for future bank connections.** Every transaction carries `import_source` and `external_id` from day one.

9. **No big-bang cutovers.** Feature flags gate each major capability change. Every phase has a clean rollback point.

10. **The OS must never become a data trap.** Export path is a first-class design concern.

---

## Sign Convention

The OS uses a **wallet-perspective** sign convention throughout: positive amounts increase the account balance; negative amounts decrease it.

| Scenario | Account | `total_amount` | Running balance effect |
|----------|---------|---------------|----------------------|
| Checking expense (groceries $50) | SunTrust Checking | -50.00 | Decreases |
| Checking deposit (paycheck $5,000) | SunTrust Checking | +5,000.00 | Increases |
| Credit card charge (Kroger $29.11) | Gold AMEX | -29.11 | Decreases (more owed) |
| Credit card payment ($2,500) | Gold AMEX | +2,500.00 | Increases (less owed) |
| Transfer: checking → savings ($500) | SunTrust Checking | -500.00 | Decreases |
| Transfer: savings receives ($500) | AMEX Savings | +500.00 | Increases |
| Reimbursement deposit received ($350) | SunTrust Checking | +350.00 | Increases |
| Goal spending on credit card ($80) | Gold AMEX | -80.00 | Decreases |
| Tax payment from checking ($2,500) | SunTrust Checking | -2,500.00 | Decreases |

**Running balance formula:**
`balance[n] = starting_balance + SUM(total_amount for all transactions through row n, ordered by transaction_date ASC, created_at ASC)`

**Credit card starting balance:** Negative value = amount owed. Gold AMEX at -$5,000 means $5,000 is owed on go-live date.

**Budget rollup inversion:** For display purposes, expense totals are shown as positive figures. The budget layer inverts the sign of negative (expense) amounts when computing "Spent." Income is shown as positive regardless. This inversion is display-layer only — raw data always uses wallet-perspective signs.

**Import sign convention:** Many bank CSV exports use institution-specific sign conventions (charges may be positive or negative depending on the institution). The import normalization layer is responsible for converting raw import amounts to wallet-perspective amounts before inserting into `transaction_splits`. See Import Normalization section.

---

## Date and Month-Boundary Rules

Financial grouping uses `transaction_date` as a local calendar date. Never use `created_at` or UTC timestamps for financial period logic.

| Concept | Rule |
|---------|------|
| Budget month | Calendar month of `transaction_date` (local date) |
| Reconciliation eligibility | `transaction_date <= statement_date` |
| Goal spending period | Calendar month of `transaction_date` |
| Running balance order | `transaction_date ASC, created_at ASC` (created_at breaks ties within same date) |
| `created_at` / `updated_at` | Audit metadata only; never used for financial period calculations |

**Why this matters:** A UTC timestamp for a 11 PM EST transaction is the next calendar day in UTC. Using `created_at` for month grouping would mis-assign transactions near month boundaries. This issue caused a real bug in Phase 5B (`_budgetToggleCleared` UTC shift). All date parsing in new code must use local date string splitting, not `new Date(isoString)`.

---

## Data Model

### Table: `accounts`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `name` | text NOT NULL | "Gold AMEX" |
| `institution` | text | "American Express" |
| `account_type` | text NOT NULL | `checking` \| `savings` \| `credit_card` \| `investment` \| `property` \| `loan` \| `cash` |
| `lifecycle_status` | text NOT NULL default `active` | See Account Lifecycle below |
| `display_order` | int default 0 | |
| `starting_balance` | numeric(12,2) | NULL until go-live setup |
| `starting_balance_as_of` | date | exact date balance was captured |
| `starting_balance_source` | text | `quicken` \| `online_account` \| `statement` \| `manual` |
| `starting_balance_note` | text | optional context |
| `include_in_budget` | bool default true | false for investment/property |
| `include_in_cashflow` | bool default true | future 31-week integration |
| `created_by` | uuid FK auth.users | |
| `updated_by` | uuid FK auth.users | updated on each save |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

#### Account Lifecycle States

| Status | Meaning | New transactions allowed? | Shown in register? | Shown in balance? |
|--------|---------|--------------------------|-------------------|------------------|
| `active` | In normal use | Yes | Yes | Yes |
| `closed` | Account closed; history retained | No | Yes (historical) | No (or $0) |
| `view_only` | Visible for balance/reporting; no entry | No | Yes | Yes |
| `hidden` | Not shown by default | No | No (toggle to reveal) | No |
| `excluded` | Fully outside OS scope | No | No | No |

**Rules:**
- `closed` accounts retain all history and show in reporting but cannot receive new transactions.
- `view_only` is for investment/property accounts where balance matters but transaction entry is not in scope.
- `hidden` is for dormant accounts the user wants to suppress without deleting.
- `excluded` is for accounts deliberately out of scope (e.g., old closed accounts fully cleaned up).

**RLS:** SELECT = `is_allowed_user()`, INSERT/UPDATE = `can_write_financials()`, DELETE = `is_owner()` only.

---

### Table: `categories`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `key` | text UNIQUE NOT NULL | slug, e.g. `food_dining.groceries`; preserved from existing registry |
| `label` | text NOT NULL | "Groceries" |
| `parent_id` | uuid FK categories.id | NULL = top-level group |
| `display_order` | int default 0 | |
| `behavior_class` | text | NULL when `is_leaf = false`; required when `is_leaf = true`. See CHECK constraint below. |
| `budget_treatment` | text | NULL when `is_leaf = false`; required when `is_leaf = true`. |
| `cashflow_treatment` | text | NULL when `is_leaf = false`; required when `is_leaf = true`. |
| `budget_line_key` | text | The budget planning/control line this category aggregates into (e.g., `food_dining`). May equal `key` or a parent's `key`. |
| `budget_group_key` | text | The display/reporting group (e.g., `food_dining` group in the printout). |
| `linked_goal_id` | uuid FK goals.id | NULL unless `goal_linked` |
| `reimbursement_pairing_key` | text | links expense category to matching deposit category |
| `is_leaf` | bool default true | false = parent/group; transactions cannot be assigned |
| `lifecycle_status` | text NOT NULL default `active` | See Category Lifecycle below |
| `merged_into_id` | uuid FK categories.id | NULL unless merged; historical transactions remain on original |
| `is_system` | bool default false | true = protected; key and behavior_class cannot be changed |
| `created_by` | uuid FK auth.users | NULL if system-seeded |
| `updated_by` | uuid FK auth.users | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**Leaf-category field enforcement (DB CHECK constraint):**
```sql
CONSTRAINT chk_leaf_behavior CHECK (
  is_leaf = false
  OR (
    behavior_class   IS NOT NULL AND
    budget_treatment IS NOT NULL AND
    cashflow_treatment IS NOT NULL
  )
)
```
Parent categories (`is_leaf = false`) may have NULL behavior/budget/cashflow fields — they are structural grouping only, not financial classifications. Leaf categories (`is_leaf = true`) must have all three fields populated; this is enforced at the DB level, not just the application layer.

#### Category vs Budget Line vs Budget Group

These are three separate concerns that must not be collapsed:

- **Category** (`categories.key`): Wendy's classification of a transaction. Granular. User-managed. E.g., `food_dining.groceries`, `food_dining.dining_out`, `trips.alaska_2026`.
- **Budget line** (`categories.budget_line_key`): The monthly planning and control unit. Multiple categories may share a budget line. E.g., all groceries and dining-out categories roll into budget line `food_dining`. The budget line is what has a monthly dollar target in `budget_line_rules`.
- **Budget group** (`categories.budget_group_key`): Display/reporting grouping in the budget printout. E.g., "Food & Dining" may contain budget lines for groceries, dining, and snacks. Groups have no dollar targets; they are purely organizational.

**Design rationale:** A separate `category_budget_line_mappings` table was considered and rejected. A `budget_line_key` field on `categories` is sufficient for the foreseeable complexity, avoids a join, and keeps category CRUD simple. If effective-dated budget line mappings become necessary, that is a future decision based on actual evidence.

#### Behavior Classes

| Value | Description | Example |
|-------|-------------|---------|
| `expense` | Standard household spending | Groceries, Rent, Gas |
| `income` | Money received | Net Salary, Wendy Salary |
| `reimbursable_expense` | Business expense paid personally | Jabian Expenses 2026 |
| `reimbursable_income` | Reimbursement deposit received | Jabian Deposits 2026 |
| `goal_linked` | Spending tracked against a saved goal | 2026 Seattle/Alaska |
| `savings_allocation` | Residual goal funding allocation — computed dynamically each month | Goal Funding Allocation |
| `transfer` | Account-to-account movement; card payments | Credit Card Payment, Greenlight |
| `commission_income` | Variable income; triggers tax reserve logic downstream | Deep South Commissions |

#### Budget Treatment Values

| Value | Description |
|-------|-------------|
| `tracked` | Counts against monthly budget line |
| `planned_allocation` | Planning target only; not driven by transactions; shows with overspend compression |
| `display_only` | Shows in income section; does not affect expense totals |
| `excluded` | Not in budget math (transfers, reimbursables, investment) |

#### Cashflow Treatment Values

| Value | Description |
|-------|-------------|
| `operating` | Normal expense; in scope for future 31-week actuals |
| `goal_funding` | Monthly allocation transfer to goal reserve (e.g., checking → AMEX Savings) |
| `goal_spending` | Actual trip/goal spending drawn from funded reserve; tracked in Goals section only; excluded from Budget section |
| `tax_reserve` | Tax reserve transfer to Vio Bank, or actual IRS payment drawn from reserve |
| `reimbursable` | Will be offset by a future deposit; net impact = zero |
| `excluded` | Transfers, investment moves |

#### Category Lifecycle States

`lifecycle_status` has three values only:

| Status | Meaning | Available in entry dropdown? | Historical transactions affected? |
|--------|---------|----------------------------|----------------------------------|
| `active` | Normal use | Yes | N/A |
| `archived` | Hidden from new entry; soft delete | No | Retained as-is |
| `merged` | Replaced by another category; `merged_into_id` set | No | Retained on original key |

**`is_system` is a separate boolean flag — not a lifecycle state.** A category can be `active` and `is_system = true` simultaneously. `is_system` protects `key`, `behavior_class`, `budget_treatment`, and `cashflow_treatment` from modification regardless of lifecycle_status. Label is always editable.

**Rules:**
- `archived` covers all variations of "hidden from entry," "deprecated," "inactive" — they are the same state. No additional statuses.
- `merged` sets `merged_into_id` pointing to the surviving category. Historical transactions remain on the original `category_id`. New entry attempts on a merged category redirect to the surviving category with a visible notice.
- To retire a category without merging: archive it. To replace it with a corrected version: archive + create new + reclassify historical transactions (deliberate, auditable action).

#### Category Behavior Change Rules

| Field | Can Wendy edit freely? | Rule when transactions exist |
|-------|----------------------|------------------------------|
| `label` | Yes | Always editable; no data impact |
| `lifecycle_status` (archive/restore) | Yes | Always; history preserved |
| `display_order` | Yes | Always |
| `linked_goal_id` | Owner only | **Affects all reporting including historical.** Splits only store `category_id`, not a goal snapshot. If the category's `linked_goal_id` changes, every historical split through that category is re-attributed to the new goal in all reports. To change goal linkage without altering historical reporting, archive the category, create a new one with the correct `linked_goal_id`, and reclassify future transactions. Do not claim historical splits retain old linkage — they do not. |
| `budget_line_key` / `budget_group_key` | Owner only | Blocked if transactions exist unless owner explicitly confirms; historical budget rollups may change |
| `behavior_class` | **Blocked for all users** once transactions exist | No edit-form override. Correction path: archive old category, create new category with correct behavior, bulk-reclassify affected transactions. |
| `budget_treatment` | **Blocked for all users** once transactions exist | Same correction path. Historical budget totals would otherwise change silently. |
| `cashflow_treatment` | **Blocked for all users** once transactions exist | Same correction path. |
| `is_system` | System only | Never editable by any user |

**Effective-dated behavior history is not implemented.** Blocking behavior changes once transactions exist is the guardrail. If a behavior change is genuinely needed and approved, the correct path is: archive the old category, create a new category with the correct behavior, and bulk-reclassify affected transactions. This is a deliberate, auditable action — not an edit.

**RLS:** SELECT = `is_allowed_user()`, INSERT = `can_write_financials()`, UPDATE = governed by role-operation matrix, DELETE = `is_owner()` only.

---

### Table: `transactions`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `account_id` | uuid FK accounts.id NOT NULL | |
| `transaction_date` | date NOT NULL | local calendar date |
| `payee` | text NOT NULL | |
| `memo` | text | optional parent-level note |
| `total_amount` | numeric(12,2) NOT NULL | wallet-perspective sign |
| `transfer_group_id` | uuid | shared by both sides of a linked transfer; NULL if not a transfer or transfer is one-sided |
| `transfer_role` | text | `outflow` \| `inflow` \| `standalone`; NULL if not a transfer. See Transfer Pairing Model. |
| `is_cleared` | bool default false | |
| `cleared_date` | date | |
| `is_reconciled` | bool default false | locked once true |
| `reconciliation_id` | uuid FK reconciliations.id | |
| `import_source` | text default `manual` | `manual` \| `csv_import` \| `bank_sync` \| `migration` |
| `external_id` | text | bank-provided dedup key; NULL for manual |
| `created_by` | uuid FK auth.users | |
| `updated_by` | uuid FK auth.users | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

---

### Table: `transaction_splits`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `transaction_id` | uuid FK transactions.id ON DELETE CASCADE NOT NULL | |
| `category_id` | uuid FK categories.id NOT NULL | |
| `amount` | numeric(12,2) NOT NULL | portion of total_amount; same sign convention as parent |
| `memo` | text | split-level memo |
| `reimbursement_source` | text | `Jabian` \| other — only for `reimbursable_expense` splits |
| `reimbursement_status` | text | `pending` \| `submitted` \| `received` |
| `reimbursement_received_date` | date | |
| `display_order` | int default 0 | |
| `created_by` | uuid FK auth.users | |
| `updated_by` | uuid FK auth.users | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**Constraint:** `SUM(transaction_splits.amount WHERE transaction_id = X) = transactions.total_amount WHERE id = X`. Enforced in application logic AND by DB trigger — both added in Phase 5E when the tables are created. The ledger must not permit invalid split sums from the moment it exists; deferring to Phase 5F is not acceptable.

**Costco $300 example:**
```
transactions: account=Costco Visa, payee="Costco", total_amount=-300.00
transaction_splits:
  row 1: category=food_dining.groceries,   amount=-220.00
  row 2: category=trips.alaska_2026,       amount=-80.00
```
Budget sees Groceries +$220. Goal "Alaska" spent +$80. No double-counting.

---

### Table: `reconciliations`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `account_id` | uuid FK accounts.id NOT NULL | |
| `statement_date` | date NOT NULL | |
| `statement_ending_balance` | numeric(12,2) NOT NULL | wallet-perspective sign |
| `cleared_balance_snapshot` | numeric(12,2) | captured at completion |
| `difference_at_completion` | numeric(12,2) | statement - cleared at completion |
| `status` | text default `in_progress` | `in_progress` \| `completed` \| `abandoned` |
| `completed_at` | timestamptz | |
| `completed_by` | uuid FK auth.users | set explicitly when status → completed; not inferred from updated_by |
| `abandoned_by` | uuid FK auth.users | set explicitly when status → abandoned |
| `created_by` | uuid FK auth.users | |
| `updated_by` | uuid FK auth.users | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

---

### Table: `import_batches` (Phase 5J)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `account_id` | uuid FK accounts.id | |
| `import_source` | text | `csv` \| `ofx` \| `bank_sync` |
| `filename` | text | original uploaded filename |
| `institution` | text | "American Express" — determines sign convention |
| `row_count_raw` | int | total rows in file |
| `row_count_accepted` | int | rows accepted into transactions |
| `row_count_rejected` | int | |
| `row_count_duplicate` | int | |
| `status` | text | `pending_review` \| `completed` \| `abandoned` |
| `created_by` | uuid FK auth.users | |
| `updated_by` | uuid FK auth.users | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

---

### Table: `import_queue` (Phase 5J)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `batch_id` | uuid FK import_batches.id | |
| `account_id` | uuid FK accounts.id | |
| `raw_data` | jsonb | original import row; never modified |
| `transaction_date` | date | parsed from import |
| `payee_raw` | text | original payee string |
| `payee_normalized` | text | after normalization rules |
| `amount_raw` | numeric(12,2) | as it appeared in the import file |
| `amount_normalized` | numeric(12,2) | wallet-perspective after sign conversion |
| `normalization_rule` | text | which rule was applied; null if none |
| `suggested_category_id` | uuid FK categories.id | rule-based suggestion |
| `status` | text default `pending_review` | `pending_review` \| `accepted` \| `rejected` \| `duplicate` |
| `duplicate_of_transaction_id` | uuid FK transactions.id | if duplicate |
| `external_id` | text | bank-provided transaction ID |
| `accepted_transaction_id` | uuid FK transactions.id | set after accept |
| `reviewed_by` | uuid FK auth.users | who accepted or rejected this row; semantic substitute for `updated_by` on the key status-change event |
| `created_by` | uuid FK auth.users | who initiated the import batch |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`updated_by` intentionally omitted from `import_queue`.** The meaningful actor event is who reviewed (accepted or rejected) each row, captured by `reviewed_by`. Generic `updated_by` would duplicate this for the key event and add noise for routine field updates (e.g., normalization adjustments by the system). `reviewed_by` is the auditable field for this table.

---

### Table: `payee_rules` (Phase 5J)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `raw_payee_pattern` | text | substring or regex pattern to match against `payee_raw` |
| `normalized_payee` | text | clean display name |
| `suggested_category_id` | uuid FK categories.id | |
| `institution` | text | NULL = applies to all; set to scope to one institution |
| `match_count` | int | tracks usage for sorting |
| `created_by` | uuid FK auth.users | |
| `updated_by` | uuid FK auth.users | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

---

### Table: `transaction_audit_log` (future — design now, build when needed)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `transaction_id` | uuid | FK to transactions (or NULL if category/account change) |
| `entity_type` | text | `transaction` \| `split` \| `category` \| `account` \| `reconciliation` |
| `entity_id` | uuid | ID of the changed record |
| `changed_by` | uuid FK auth.users | |
| `changed_at` | timestamptz | |
| `change_type` | text | `create` \| `update` \| `delete` \| `unlock` \| `reconcile` \| `import_accept` \| `import_reject` |
| `before_json` | jsonb | snapshot before change |
| `after_json` | jsonb | snapshot after change |
| `reason` | text | required for unlock, adjustment, and behavior_class changes |

**Not built in Phase 5D-1.** Minimum audit coverage until then: `created_by`, `updated_by`, `created_at`, `updated_at` on all tables. Full audit log added when reconciliation unlock and category reclassification features exist.

---

## Transfer Pairing Model

A transfer is two linked account movements. The pairing mechanism is `transfer_group_id` — a shared UUID on both `transactions` rows.

**Why `transfer_group_id` over `linked_transaction_id`:**
- `linked_transaction_id` is brittle: deleting one side breaks the other's foreign key.
- `transfer_group_id` is nullable UUID with no FK constraint — both sides share it; neither depends on the other.
- Supports future N-sided transfers if needed.

**`transfer_role` values:**

| Value | Meaning |
|-------|---------|
| `outflow` | The source side of a transfer — money leaving this account |
| `inflow` | The destination side — money arriving in this account |
| `standalone` | A transfer with only one side entered (the other account is not in the OS, or pairing is pending) |

`transfer_role` is required on any transaction where `transfer_group_id` is set or where the split category has `behavior_class = 'transfer'`. It must be NULL for non-transfer transactions.

**Transfer types and their treatment:**

| Transfer type | Outflow side | Inflow side | Budget treatment | Cashflow treatment | Notes |
|---------------|-------------|------------|-----------------|-------------------|-------|
| Credit card payment | Checking -$2,500 (`outflow`) | Gold AMEX +$2,500 (`inflow`) | `excluded` on both | `excluded` | Reduces what you owe; not spending |
| Checking → AMEX Savings | Checking -$500 (`outflow`) | AMEX Savings +$500 (`inflow`) | `excluded` on both | `goal_funding` | Goal funding transfer |
| Greenlight funding | Checking -$X (`standalone`) | (Greenlight not in OS) | `excluded` | `excluded` | One-sided until Greenlight account added |
| Tax reserve transfer | Checking -$X (`outflow`) | Vio Bank +$X (`inflow`) | `excluded` on both | `tax_reserve` | Tax reserve logic in cashflow model |
| Goal funding transfer | Checking -$X (`outflow`) | AMEX Savings +$X (`inflow`) | `excluded` on both | `goal_funding` | See Goal Funding Source-of-Truth |

**Why `transfer_role` matters beyond budget exclusion:**
Budget treatment is already `excluded` on both sides of every transfer. `transfer_role` is needed for future cashflow and reserve reporting that must not double-count. A checking → Vio Bank tax reserve transfer moves $X. If `transfer_role` is unknown, a future report summing all tax reserve cashflow activity would count both the outflow ($X leaving checking) and the inflow ($X arriving at Vio) — double the real movement. `transfer_role = outflow` identifies the canonical "money moved" side for one-way reporting aggregations.

**One-sided transfers:**
When only one side of a transfer is entered or imported, `transfer_group_id` is still set on that transaction. The system shows a warning in the register: "This transfer has no matching entry — pair it or mark as standalone." The user can manually link the matching transaction or dismiss the warning.

**Import pairing:**
During CSV import, the system attempts to auto-pair transfers by matching: same `transfer_group_id` pattern if present, or same date + inverse amount across two accounts. Auto-pairing is suggested, not automatic — user confirms in the review queue.

---

## Reconciled Transaction Immutability

A reconciled transaction is locked history. This protects the integrity of past reconciliation sessions.

**Edit/delete rules:**

| Action | Unreconciled | Cleared (not reconciled) | Reconciled |
|--------|-------------|--------------------------|-----------|
| Edit amount/date/payee/account | `household_admin`: Yes | `household_admin`: Yes | Locked for all |
| Edit category/splits | `household_admin`: Yes | `household_admin`: Yes | Locked for all |
| Delete transaction | `household_admin`: Yes | **Phase 5E: Blocked for all. Phase 5F+: `owner` only, required reason, audit logged.** | Locked for all |
| Unlock for correction | N/A | N/A | `owner` only, with required reason |
| Create correcting transaction | Any authorized user | Any authorized user | Preferred correction path |

**Unlock process (owner only):**
1. Owner selects "Unlock for correction" on a reconciled transaction.
2. Required reason field must be completed.
3. Unlock is logged in `transaction_audit_log` with `change_type = 'unlock'`, before/after state, and reason.
4. Transaction reverts to `is_reconciled = false`, `is_cleared = true`.
5. Owner edits and re-clears manually.
6. Note in the register: "Previously reconciled — corrected [date]."

**Preferred correction path:** Create a new correcting transaction (e.g., a negative adjustment) rather than unlocking history. Unlocking should be the exception, not the routine.

**Wendy's permissions:** `household_admin` can view reconciled transactions but cannot unlock them. Unlock is `owner` only.

---

## Role-Operation Matrix

| Operation | `owner` | `household_admin` | Notes |
|-----------|---------|------------------|-------|
| View all transactions | Yes | Yes | |
| Create transaction | Yes | Yes | |
| Edit unreconciled transaction | Yes | Yes | |
| Delete unreconciled transaction | Yes | Yes | |
| Edit cleared (not reconciled) transaction | Yes | Yes | |
| Delete cleared (not reconciled) transaction | Phase 5E: Blocked. Phase 5F+: Yes with required reason + audit log | Phase 5E: Blocked. Phase 5F+: No | Cleared deletes require audit trail; blocked until Phase 5F |
| Edit reconciled transaction | No (unlock first) | No | |
| Delete reconciled transaction | No (unlock first) | No | |
| Unlock reconciled transaction | Yes | No | Requires reason; audit logged |
| Create reconciliation | Yes | Yes | |
| Complete reconciliation | Yes | Yes | |
| Create reconciliation adjustment | Yes | Yes | Requires memo |
| Delete reconciliation adjustment | Yes | No | Owner only |
| View reconciliation history | Yes | Yes | |
| Add/edit category (label, display fields) | Yes | Yes | |
| Archive/restore category | Yes | Yes | |
| Change category behavior fields (behavior_class, budget_treatment, cashflow_treatment) | **Blocked for all users once transactions exist** | **Blocked** | No edit-form override, even for owner. Correct path is explicit reclassification workflow (see below). |
| Reclassify category (archive old + create new + bulk-reclassify transactions) | Yes | No | Explicit, auditable workflow only — not an edit-form action |
| Manage accounts (add/edit lifecycle) | Yes | Yes | |
| Set go-live starting balances | Yes | Yes | |
| Import transactions | Yes | Yes | subject to Phase 5J scope |
| Accept/reject imported transactions | Yes | Yes | |
| Manage payee rules | Yes | No | |
| Manage Anthropic key | Yes | No | Existing Phase 5A rule |
| Set feature flags | Yes | No | Owner controls staged rollout |

---

## Audit Trail Strategy

**Minimum audit coverage (every new table from Phase 5D-1):**
All new tables include: `created_by`, `updated_by`, `created_at`, `updated_at`.

**Phase-specific audit actions that require structured logging (when those features exist):**

| Event | Log when | Required fields |
|-------|----------|----------------|
| Reconciliation adjustment created | Phase 5F | transaction_id, created_by, reason, amount |
| Category behavior change | Phase 5D-2 | category_id, changed_by, before/after behavior fields |
| Transaction edited after clearing | Phase 5E | transaction_id, changed_by, before/after |
| Reconciled transaction unlocked | Phase 5F | transaction_id, unlocked_by, reason |
| Account starting balance set/changed | Phase 5E go-live | account_id, changed_by, before/after balance, source |
| Import batch accepted | Phase 5J | batch_id, accepted_by, row counts |
| Import transaction rejected | Phase 5J | import_queue_id, rejected_by, reason |

**Full `transaction_audit_log` table design is in the Data Model section.** It is not built in Phase 5D-1. Until it is built, `updated_by` + `updated_at` on each table is the minimum forensic trail.

---

## Future Cashflow Integration Contract

This section defines the permanent boundary between the 31-week cashflow model, the transaction ledger, the budget, and the goals system. Violating this boundary creates competing sources of truth.

**Source-of-truth assignments:**

| Domain | Source of truth | Read-only to other systems |
|--------|----------------|--------------------------|
| Weekly forecast (31 weeks) | 31-week model (hardcoded JS + `model_week_overrides`) | Yes |
| Waterfall sequencing and floors | 31-week model | Yes |
| Planned weekly actions and transfers | 31-week model | Yes |
| Actual posted transactions | `transactions` + `transaction_splits` | Read by Budget (Phase 5G), Goals (Phase 5H) |
| Monthly planned budget | `budget_line_rules` | Read by Budget section |
| Monthly actual budget | `transaction_splits` aggregated by `budget_line_key` (Phase 5G) | |
| Goal target and saved amounts | `goals` table (existing) | Read by Goal card |
| Goal actual spending | `transaction_splits` WHERE `category.linked_goal_id` (Phase 5H) | |

**Integration contract rules:**

1. Transaction actuals may inform budget variance reporting. They do not rewrite or override cashflow model logic.
2. Actual transactions do not auto-update weekly action completion status. (Actions are checked manually, as today.)
3. Actual transactions do not auto-update `model_week_overrides`. That table is for deliberate plan changes.
4. Goal actual spending (from `transaction_splits`) does not automatically reduce goal saved balances in the `goals` table. Saved and Spent are independent flows.
5. Future cashflow-to-actuals variance reporting (e.g., "You planned $X for groceries in Week 5; you actually spent $Y") is a display feature only. It does not feed back into the model.
6. Any integration that writes FROM transaction actuals INTO the cashflow model requires an explicit future phase design. It is never a side effect.

---

## Goal Funding Source-of-Truth

This section is explicit to prevent a future misunderstanding where "Spent reduces Saved" is accidentally implemented.

| Metric | Source | Computed how |
|--------|--------|-------------|
| **Target** | `goals.target_amount` | Set by user |
| **Saved** | `goals` table existing logic | Existing funding waterfall + manual updates; not automatically tied to account balances |
| **Spent** | `transaction_splits` WHERE `categories.linked_goal_id = goal.id` | SUM of split amounts (inverted for display) |
| **Funding Remaining** | Target - Saved | How much more needs to be saved |
| **Spend/Budget Remaining** | Target - Spent | How much of the total goal budget has been used |
| **Available Reserve** | Saved - Spent | Practical answer to "how much do we have left?" — recommended as primary display metric |

**Explicit constraints:**
- Saved is NOT automatically tied to account balances. A savings account balance and a goal's "Saved" amount are separate concepts until a future phase explicitly designs that linkage.
- Spent does NOT automatically reduce Saved. They are independent data flows.
- Available Reserve (Saved - Spent) is a display computation only. It does not mutate any stored value.
- Goal funding transfers (Checking → AMEX Savings) are currently excluded from budget math and manually reflected in `goals.saved_amount`. Future integration that auto-updates Saved from transfer transactions requires explicit design.

---

## Navigation Structure

| Current | New |
|---------|-----|
| Overview | Overview |
| Cash Flow | Cash Flow |
| Goals | Goals |
| Budget | **Transactions** ← new |
| Wishlist | Budget (evolved) |
| — | Wishlist |

**Sub-navigation within Transactions:**

| Sub-section | Phase | Description |
|-------------|-------|-------------|
| By Account | 5E | Account register view — primary workflow |
| All Transactions | 5E | Cross-account filtered view |
| Categories | 5D-2 | Category add/edit/archive |
| Reconciliation History | 5F | Read-only log of past sessions |
| Import / Review Queue | 5J | CSV import staging |

**Reconciliation is a contextual action, not a nav destination.** "Reconcile" is a button on the account register. The reconciliation flow is a modal triggered from within an account. "Reconciliation History" in the sub-nav is a read view of past sessions only.

---

## Go-Live Setup: Starting Balance Process

**Discovery phase (now):** Gather account names, types, lifecycle status, and in-scope decisions. Do NOT gather starting balance values — they will change before go-live.

**Go-live setup (on or immediately before July 1, 2026):** For each in-scope account, capture:
- `starting_balance`: wallet-perspective value on go-live date
- `starting_balance_as_of`: exact date captured
- `starting_balance_source`: `quicken` \| `online_account` \| `statement` \| `manual`
- `starting_balance_note`: optional context

Running balance computation begins from this anchor. Accounts with NULL `starting_balance` show "Balance not available — starting balance not set."

---

## UI Sections

### Transactions — By Account (Phase 5E)

**Left panel:** Account list with current balance (computed), uncleared count, lifecycle_status=active only. "Balance not set" state shown when starting_balance is NULL.

**Account register columns:** Date | Payee | Category | Memo | CLR | Amount | Balance
- Balance = running balance from `starting_balance` anchor
- CLR = checkbox (uncleared/cleared); reconciled transactions show lock icon
- Category: label for single-split; "Split (N)" with expand for multi-split
- Transfer transactions show "Transfer to/from [account]" if `transfer_group_id` links to a visible account

**Add/Edit Transaction Form:**
- Date, Payee, Account, Total Amount, Memo (parent)
- One or more split rows: Category + Amount + Memo (split)
- "Add Split" button (Phase 5I UI; schema ready from Phase 5E)
- Unallocated remainder shown in real time; must reach $0.00 to save
- Extra fields per behavior_class: reimbursable fields for `reimbursable_expense`; goal chip for `goal_linked`; transfer account for `transfer`
- Cleared checkbox

**Reconcile button:** Opens reconciliation modal. Not a nav item.

### Reconciliation Flow (Phase 5F)

**Modal triggered from account register:**

Step 1: Statement ending balance + statement date → creates `reconciliations` row.

Step 2: Three-number header (mirrors Quicken):
```
Statement Ending Balance    Difference    Cleared Balance
     -$6,884.05             $1,571.58      -$5,312.47
```
Uncleared transaction list with CLR checkboxes; live balance updates as items checked.

Controls: Mark All Cleared | Mark All Uncleared | Add Adjustment | Finish Later | Finish.

**Reconciliation Adjustment guardrails:**
- Required memo before save
- System category `reconciliation_adjustment` with `budget_treatment = 'excluded'`
- Visible ADJ badge in register; never hidden
- `created_by` always recorded
- `household_admin` can create; `owner` can delete

**Cleared vs Reconciled:**
- Cleared: confirmed on statement; `is_cleared = true`; toggleable
- Reconciled: part of completed session; `is_reconciled = true`; locked (lock icon)

### Categories (Phase 5D-2, under Transactions > Categories)

Category tree with add/edit/archive. Behavior fields locked on system categories. Change guardrails enforced per the Category Behavior Change Rules table. Merge path: archive old + create new + bulk-reclassify (future).

### Budget Section (evolved — Phase 5G)

Retained as own nav section. Becomes planning + actuals layer reading from `transaction_splits`. Until Phase 5G, continues reading from `budget_transactions`.

**Budget summary structure (Phase 5G):**
```
INCOME            [from display_only income categories]
EXPENSES          [from tracked categories, grouped by budget_group_key]
PLANNED GOAL FUNDING   [$2,300 planned_allocation; compresses under overspend]
TOTAL BUDGET      [Planned | Spent | Remaining]
```

---

## Month-Specific Budget Amounts

### Existing Capability (Already Live)

`budget_line_rules` is the source of truth for all monthly planned amounts. It already supports month-specific amounts via effective date ranges — this is not new design work. The table structure in production:

| Column | Type | Purpose |
|--------|------|---------|
| `category_key` | text | maps to `categories.key` |
| `amount` | numeric | planned monthly amount for this rule row |
| `start_month` | date (YYYY-MM-DD) | first month this row is active (inclusive) |
| `end_month` | date (YYYY-MM-DD) | last month this row is active (inclusive); NULL = indefinite |
| `is_active` | bool | global toggle for the row |

The existing `_getBudgetAmount(categoryKey, monthIso)` function in the OS already filters rows using `start_month <= monthIso AND (end_month IS NULL OR end_month >= monthIso)`. Multiple rows for the same `category_key` with non-overlapping date ranges produce the correct month-specific amount automatically.

**The categories table does not own planned amounts.** Categories own behavior class, budget treatment, and rollup keys. Planned monthly amounts are always in `budget_line_rules`. This separation must be preserved through all future phases.

### Known Scheduled Budget Changes

The following changes are modeled as `budget_line_rules` row operations — end-dating existing rows and inserting new ones. No schema change required.

**July 2026 — Rent increases:**

| Operation | category_key | amount | start_month | end_month |
|-----------|-------------|--------|-------------|----------|
| End-date existing row | `home.mortgage_rent` | [current amount] | [current start] | `2026-06-01` |
| Insert new row | `home.mortgage_rent` | [current amount + $100] | `2026-07-01` | null |

**July–December 2026 — Diablos (Preston):**

| Operation | category_key | amount | start_month | end_month |
|-----------|-------------|--------|-------------|----------|
| Insert new row | `health_fitness.diablos_preston_fee` | `750.00` | `2026-07-01` | `2026-12-01` |

Category already exists in the registry (`health_fitness.diablos_preston_fee`). It currently has no `budget_line_rules` row because it was not in the living expense total before July. Adding this row activates it in the budget printout for July–December only. It disappears automatically after December.

**August–December 2026 — Wendy GLP Meds:**

| Operation | category_key | amount | start_month | end_month |
|-----------|-------------|--------|-------------|----------|
| Insert new row | `health_fitness.wendy_glp_meds` | `404.00` | `2026-08-01` | `2026-12-01` |

Same pattern as Diablos. Category already exists. Budget row activates it for August–December only at $404/month.

**January 2027 — both Diablos and GLP Meds lines expire:**
No action required if `end_month = '2026-12-01'` is set correctly. Both rows will return $0 for January onward unless a new row is explicitly added. The budget printout will not show these lines in January unless extended.

### Implications for Phase 5D-1 Seed Validation

The budget-line validation gate must account for date-ranged rows:

- A `budget_line_key` that resolves in June 2026 may not resolve in January 2027 if the underlying rule has `end_month`. This is correct behavior, not an error.
- The REG-BL-2 validation ("every `budget_line_key` resolves to a `budget_line_rules` key") should be scoped to the current month, not all time.
- The seed must include the Diablos and GLP Meds `budget_line_rules` rows with correct start/end months, not permanent rows.

### Phase 5G Actuals — Month-Specific Planned Amount Lookup

When Phase 5G switches budget actuals to `transaction_splits`, the variance calculation is:

```
For each budget_line_key in a given monthIso:
  planned  = SUM(budget_line_rules.amount WHERE category_key matches
              AND start_month <= monthIso AND (end_month IS NULL OR end_month >= monthIso))
  actual   = SUM(transaction_splits.amount) WHERE category.budget_line_key matches
              AND transactions.transaction_date falls within monthIso
              AND budget_treatment = 'tracked'
  variance = planned - ABS(actual)   [negative actual amounts; ABS for display]
```

This preserves the existing `_getBudgetAmount()` logic and extends it to cover actuals from the new transaction system. No change to the underlying `budget_line_rules` table or query pattern is required.

### Test Coverage

| Test | Description |
|------|-------------|
| REG-BL-MONTH-1 | Diablos budget line returns $750 for July 2026; returns $0 for January 2027 |
| REG-BL-MONTH-2 | GLP Meds budget line returns $404 for August 2026; returns $0 for January 2027 |
| REG-BL-MONTH-3 | Rent budget line returns increased amount starting July 2026 |
| REG-BL-MONTH-4 | Monthly total changes correctly across the June/July boundary |
| REG-BL-MONTH-5 | No ghost lines appear in January 2027 for expired rules |

---

## The Planned Goal Funding Allocation

Category `misc.goal_sweep` gets `budget_treatment = 'planned_allocation'`.

**The allocation amount is NOT a stored value.** It is computed dynamically each month as:

```
planned_allocation = monthly_budget_target - SUM(budget_line_rules.amount for tracked lines that month)
```

`monthly_budget_target` is a stored constant (JS budget constant for Phase 5D-1; migrated to `budget_settings` table in a future phase). The current baseline produces approximately $2,300 in residual allocation. This is a target, not a hard floor.

**Why dynamic, not stored:** When a new tracked budget line is added (e.g., Diablos at $750 starting July 2026), the planned_allocation automatically compresses by $750 without any manual update to a stored "goal funding" row. Storing $2,300 as a static `budget_line_rules` entry would require manual maintenance every time tracked expenses change.

**Behavior:**
- Included in Total Budget: `total = sum(tracked lines) + planned_allocation`
- Not driven by transactions — it is a planning target only
- Overspend compression: if actual tracked spend exceeds planned by $N in a given month, effective available allocation = `planned_allocation - $N`
- Amber warning when allocation is compressed by overspend; red when fully compressed
- Real cash transfers remain in the 31-week cashflow model. No fake transactions created.

**Month-by-month example:**
- June 2026 baseline tracked lines → ~$2,300 residual
- July 2026: Diablos $750 added → residual drops to ~$1,550 automatically
- August 2026: GLP Meds $404 added → residual drops to ~$1,146 automatically
- January 2027: both lines expire → residual returns to ~$2,300 automatically

---

## Balance Computation Strategy

**Phase 5E (go-live through foreseeable future):**
Live computation from `starting_balance` anchor: `starting_balance + SUM(total_amount ORDER BY transaction_date ASC, created_at ASC)`.

**Scale assessment:** Starting July 2026, a typical household account generates 50-150 transactions/month. At 24 months, that is 1,200-3,600 rows per account. Live computation over this dataset is milliseconds in Supabase. Snapshots are not needed for years.

**Future escape hatch (not designed now, not needed soon):**
If register performance degrades, the path is:
1. `account_balance_snapshots` table: one row per account per month-end with verified balance
2. Register computes: `snapshot.balance + SUM(transactions since snapshot.as_of_date)`
3. Reconciliation sessions naturally provide verified balance anchors

Reconciliation completion already snapshots `cleared_balance_snapshot`. This doubles as a natural periodic anchor. Future balance snapshot design can build on this without schema changes.

---

## Import Normalization and Dedup Strategy (Phase 5J)

**Sign normalization:** Bank CSV exports use institution-specific conventions. AMEX exports charges as positive; Chase may export them as negative. The `import_batches.institution` field determines which sign conversion rule applies. Conversion is applied during import parsing, stored as `amount_normalized` (wallet-perspective). `amount_raw` is preserved unchanged for audit.

**Payee normalization:** Raw payee strings from banks are often noise ("KROGER #0427 ATL GA 12345"). The `payee_rules` table maps patterns to clean names and suggested categories. Normalization is stored as `payee_normalized`; `payee_raw` is preserved.

**Duplicate detection — ordered by specificity:**
1. Exact match on `external_id` + `account_id` — definitive duplicate; auto-flag as `duplicate`
2. Match on `account_id` + `transaction_date` + `amount_normalized` + `payee_normalized` — probable duplicate; flag for review
3. Match on `account_id` + `transaction_date` + `amount_normalized` within ±1 day — possible duplicate; flag for review

User confirms or dismisses duplicate flags in the review queue. No auto-accept.

**Transfer matching in imports:**
When both sides of a transfer are imported (from two separate account CSV files), the system suggests pairing by: same `transfer_group_id` if present in export data, or inverse amount + same date across two accounts. Pairing is suggested in the review queue; user confirms before `transfer_group_id` is set.

**Pending vs posted:**
Bank exports may include pending transactions. Pending transactions should be importable but flagged. Field: add `transaction_status` to `import_queue`: `pending` \| `posted`. Only `posted` transactions should be accepted into `transactions`. Pending can be viewed but not committed.

---

## Service Layer Structure

The OS is a single HTML file with vanilla JS calling Supabase REST directly. There is no build step and no module system. Service layer means **JS namespace objects** — not classes, not imports, not a framework.

**Proposed namespace organization within `index.html`:**

```javascript
var HOS = {
  accounts:       { getBalance, save, listActive, setStartingBalance },
  categories:     { loadAll, getByKey, canEdit, archive },
  transactions:   { save, delete, validateSplits, loadForAccount },
  splits:         { validate, buildBudgetRollup, buildGoalRollup },
  budget:         { getActuals, getPlanned, computeAllocation },
  reconciliation: { start, finish, lock, buildClearedBalance },
  goals:          { getSpent, getAvailableReserve },
  imports:        { normalize, deduplicate, buildReviewQueue },
  transfers:      { link, detectUnpaired }
};
```

**Rules for service functions:**
- Sign convention handling (wallet-perspective enforcement) lives in `HOS.transactions` and `HOS.splits`, not in UI render functions
- Split sum validation lives in `HOS.splits.validate`, called before every transaction save
- Budget treatment logic lives in `HOS.budget`, not in the budget printout render
- Category behavior derivation (which form fields to show) lives in `HOS.categories.getFormBehavior(categoryId)`
- Reconciliation lock checks live in `HOS.reconciliation`, not scattered in click handlers

This is not a refactor of existing code. New code written from Phase 5D-1 onward uses these namespaces. Existing functions are migrated opportunistically as phases touch them.

---

## Feature Flags / Staged Rollout

Feature flags are JS constants at the top of `index.html`, controlled by the `owner` role. No feature flag logic reaches the UI unless the flag is `true`.

```javascript
var FEATURE_FLAGS = {
  useSupabaseRegistries:              false,  // Phase 5D-1
  showTransactionSection:             false,  // Phase 5D-2 / 5E
  useNewTransactionsLedger:           false,  // Phase 5E
  enableReconciliationV2:             false,  // Phase 5F
  useTransactionSplitsForBudget:      false,  // Phase 5G
  enableGoalLinkedSpend:              false,  // Phase 5H
  enableSplitTransactionUI:           false,  // Phase 5I
  enableImportQueue:                  false,  // Phase 5J
};
```

**Rules:**
- Each flag defaults to `false`; set to `true` when the phase is ready to activate
- The old code path remains active when a flag is `false` — no big-bang cutover
- Flags are hardcoded in `index.html`; changing them requires a code push (intentional — no accidental activation)
- `owner` decides when to flip a flag; `household_admin` cannot change flags

---

## Performance and Indexing Plan

All indexes defined here are created in the same migration that creates the table — not added later.

**`transactions` table:**

| Index | Columns | Purpose |
|-------|---------|---------|
| `idx_transactions_account_date` | `(account_id, transaction_date)` | Account register load; budget actuals by account+month |
| `idx_transactions_account_cleared` | `(account_id, is_cleared, is_reconciled)` | Reconciliation uncleared list |
| `idx_transactions_external_id` | `(external_id)` WHERE `external_id IS NOT NULL` | Import dedup |
| `idx_transactions_transfer_group` | `(transfer_group_id)` WHERE `transfer_group_id IS NOT NULL` | Transfer pairing lookup |

**`transaction_splits` table:**

| Index | Columns | Purpose |
|-------|---------|---------|
| `idx_splits_transaction` | `(transaction_id)` | Fetch all splits for a transaction |
| `idx_splits_category` | `(category_id)` | Budget actuals rollup by category |
| `idx_splits_category_date` | Join via transaction: `(category_id, transaction.transaction_date)` — handled by query join | Goal spending and budget actuals |

**`categories` table:**

| Index | Columns | Purpose |
|-------|---------|---------|
| `idx_categories_goal` | `(linked_goal_id)` WHERE `linked_goal_id IS NOT NULL` | Goal-linked spending lookup |
| `idx_categories_budget_line` | `(budget_line_key)` | Budget rollup by budget line |

**`reconciliations` table:**

| Index | Columns | Purpose |
|-------|---------|---------|
| `idx_reconciliations_account` | `(account_id, statement_date DESC)` | Reconciliation history per account |

**Expected query patterns and critical paths:**

| Query | Tables touched | Index used |
|-------|---------------|-----------|
| Account register load | `transactions` LEFT JOIN `transaction_splits` LEFT JOIN `categories` | `idx_transactions_account_date` |
| Current account balance | `transactions` WHERE `account_id` | `idx_transactions_account_date` |
| Budget actuals for month | `transaction_splits` JOIN `transactions` JOIN `categories` | `idx_splits_category` + `idx_transactions_account_date` |
| Goal-linked spending | `transaction_splits` JOIN `categories` WHERE `linked_goal_id` | `idx_categories_goal` + `idx_splits_category` |
| Reimbursement tracking | `transaction_splits` WHERE `reimbursement_status = 'pending'` | `idx_splits_category` (category filter) |
| Reconciliation uncleared list | `transactions` WHERE `account_id AND NOT is_reconciled AND transaction_date <= statement_date` | `idx_transactions_account_cleared` |
| Import dedup | `transactions` WHERE `external_id = X` | `idx_transactions_external_id` |

---

## Migration Versioning and Rollback

Each schema phase has a corresponding SQL file in `docs/`. Structure:

```
docs/
  phase-5d-1-registry-migration.sql      -- forward
  phase-5d-1-registry-rollback.sql       -- rollback
  phase-5e-transactions-migration.sql    -- forward
  phase-5e-transactions-rollback.sql     -- rollback
  phase-5e-budget-transactions-migration.sql  -- budget_transactions → transactions
  ... etc.
```

**Required for each migration file:**

```sql
-- VERIFICATION QUERY (run before migration)
-- Expected: [N rows in source table]
SELECT COUNT(*) FROM budget_transactions;

-- FORWARD MIGRATION
-- [schema changes, data moves]

-- ROW COUNT VALIDATION (run after migration)
-- Expected: same count in new table
SELECT COUNT(*) FROM transactions WHERE import_source = 'migration';

-- SAMPLE VALIDATION
-- Spot-check 5 rows: original vs migrated
SELECT bt.id, bt.amount, t.total_amount
FROM budget_transactions bt
JOIN transactions t ON t.external_id = bt.id::text
LIMIT 5;

-- ROLLBACK (separate file)
-- [undo schema changes; restore data if needed]
```

**Phase 5D-1 migration specifically:**
Moving `BUDGET_CATEGORY_REGISTRY` from JS to Supabase is not a data migration — it is a seed. The JS array does not change. Supabase is seeded from the JS values. If Supabase load fails, JS fallback activates automatically. Rollback = set `FEATURE_FLAGS.useSupabaseRegistries = false`.

**Phase 5E budget_transactions migration:**
This is the highest-risk migration. Process:
1. Create `transactions` and `transaction_splits` tables
2. Run migration script: for each `budget_transactions` row, insert one `transactions` row and one `transaction_splits` row
3. Verify: `COUNT(budget_transactions) = COUNT(transactions WHERE import_source = 'migration')`
4. Do NOT delete `budget_transactions` — it is the rollback
5. Switch budget reads to new tables only in Phase 5G, after validation

---

## Expanded Test Strategy

All 687 existing regression tests must pass after every phase. New tests are additive.

**Phase 5D-1 tests:**

| Test | Description |
|------|-------------|
| REG-SUPABASE-1 | Supabase registry loads; category count matches JS fallback count |
| REG-SUPABASE-2 | JS fallback activates on Supabase registry miss |
| REG-SUPABASE-3 | All existing `budget_line_rules` keys resolve against Supabase registry |
| REG-RLS-ACCT | Unauthenticated user cannot SELECT from `accounts` |
| REG-RLS-CAT | `household_admin` cannot INSERT system category |
| REG-CAT-CRUD-1 | Add category → appears in dropdown |
| REG-CAT-CRUD-2 | Archive category → removed from dropdown; historical transactions unaffected |
| REG-CAT-GUARD-1 | `behavior_class` change blocked if transactions exist |
| REG-BL-1 | Every tracked leaf category has non-null `budget_line_key` |
| REG-BL-2 | Every tracked leaf category's `budget_line_key` resolves to an active `budget_line_rules` row for the **current validation month** — zero orphans for current month. Expired rows (e.g., Diablos after December 2026) returning $0 in future months is correct behavior, not a validation error. |
| REG-BL-3 | Every tracked/display_only category has non-null `budget_group_key` |
| REG-BL-4 | `excluded` categories may have NULL `budget_line_key` — test that this is allowed |
| REG-GOAL-LINK-1 | Changing `linked_goal_id` on a category with transactions is owner-only; `household_admin` blocked |

**Phase 5E tests:**

| Test | Description |
|------|-------------|
| REG-SIGN-1 | Checking expense: total_amount is negative |
| REG-SIGN-2 | Credit card payment: total_amount is positive |
| REG-SIGN-3 | Running balance formula: starting_balance + SUM(amounts) |
| REG-SPLIT-1 | App layer: split sum must equal total_amount; save blocked if not |
| REG-SPLIT-2 | DB layer: trigger rejects INSERT/UPDATE that would cause split sum != total_amount |
| REG-SPLIT-3 | Single-split transaction: split.amount = transaction.total_amount |
| REG-SPLIT-4 | Two splits: amounts sum to parent total |
| REG-MIGRATE-3 | Zero transactions with zero splits after migration |
| REG-MIGRATE-4 | Zero transactions with split sum != total_amount after migration |
| REG-FORM-1 | Reimbursable_expense category: Source/Status fields appear |
| REG-FORM-2 | Goal_linked category: goal chip appears; no extra fields |
| REG-FORM-3 | Transfer category: no budget fields |
| REG-MIGRATE-1 | budget_transactions row count = migrated transactions row count |
| REG-MIGRATE-2 | 5 sampled migrated rows: amounts match original |
| REG-DATE-1 | Transaction entered at 11 PM EST assigned correct calendar day |

**Phase 5F tests:**

| Test | Description |
|------|-------------|
| REG-RECON-1 | Cleared balance = SUM of cleared transaction amounts |
| REG-RECON-2 | Finish blocked until Difference = $0.00 |
| REG-RECON-3 | Reconciled transaction: edit/delete blocked for household_admin |
| REG-RECON-4 | Reconciled transaction: unlock requires owner + reason |
| REG-RECON-5 | Adjustment: required memo enforced |
| REG-RECON-6 | Adjustment: `budget_treatment = excluded`; not in budget totals |
| REG-RECON-7 | Finish Later: cleared state preserved on re-open |
| REG-LOCK-1 | Reconciled transaction: split sum re-check fails on edit attempt |

**Phase 5G tests:**

| Test | Description |
|------|-------------|
| REG-BUDACT-1 | Budget actuals match SUM(split amounts) by budget_line_key for month |
| REG-BUDACT-2 | Transfer splits excluded from budget actuals |
| REG-BUDACT-3 | Reimbursable splits excluded from budget actuals |
| REG-BUDACT-4 | `goal_linked` splits with `budget_treatment = excluded` do NOT appear in budget actuals |
| REG-ALLOC-1 | Planned allocation (computed): included in Total Budget = tracked lines + allocation |
| REG-ALLOC-2 | Adding Diablos $750 tracked line in July → allocation compresses by $750 automatically |
| REG-ALLOC-3 | Overspend in any tracked line by $N → effective available allocation = allocation - $N |
| REG-ALLOC-4 | Overspend exceeds allocation → allocation fully compressed; red warning |
| REG-PARALLEL | Phase 5G actuals match pre-migration budget_transactions totals |

**Phase 5H tests:**

| Test | Description |
|------|-------------|
| REG-GOAL-1 | Goal Spent = SUM of splits where category.linked_goal_id = goal.id |
| REG-GOAL-2 | Available Reserve = Saved - Spent (display computation only) |
| REG-GOAL-3 | Spent does not mutate goal.saved_amount |
| REG-GOAL-4 | Goal Spent aggregates splits with cashflow_treatment = goal_spending only |
| REG-GOAL-5 | A $500 Alaska trip charge in July does NOT reduce the July planned allocation |

---

## Multi-User Concurrency

Adam and Wendy may both use the OS simultaneously. Basic optimistic concurrency protection:

**Rules:**
- Before saving an edit, compare `updated_at` of the record as loaded vs current DB value
- If they differ, the save fails with a clear message: "This record was changed by someone else while you were editing. Please reload and try again."
- Reconciliation lock re-checked at save time: if a transaction was reconciled after the edit form opened, the save is rejected with "This transaction was reconciled while you were editing."
- No silent overwrites.

**Implementation:** On edit form open, cache the `updated_at` value. On save, include a PATCH with a filter: `id=eq.X&updated_at=eq.[cached_value]`. Supabase returns 0 rows if the record changed. Check response row count; if 0, surface the conflict message.

This is sufficient for a two-user household. Full conflict resolution (merge, diff) is not needed.

---

## Export and Recovery Path

The OS must never become a data trap. Export is a future safeguard, not a Phase 5D concern.

**Planned export scope (Phase 5J or later):**
- `accounts`: CSV or JSON
- `categories`: CSV or JSON (with full behavior fields)
- `transactions`: CSV with all fields
- `transaction_splits`: CSV
- `reconciliations`: CSV with session history
- `import_batches` and `import_queue`: if built

**Design constraint:** Every table must be queryable in full via Supabase REST API using the `owner` JWT. No data should be stored exclusively in JS constants or `localStorage` that is not also in Supabase (existing flags already migrate this way — `anthropic_key`, `is_ira_cleared`, etc.).

**Recovery path:** If the GitHub Pages app is unavailable, all financial data is in Supabase and queryable directly. The Supabase project (`usayoldrawwmjsmretin`) is the persistent data store, not the HTML file.

---

## Protect Current OS Behavior

| Area | Rule |
|------|------|
| 31-week cash flow model | Zero changes. Protected by Cashflow Integration Contract section. |
| Goals table / funding logic | Additive only (linked_goal_id reads); no changes to saved amounts or funding dates |
| Weekly reconciliations (`weekly_reconciliations`) | Distinct from account reconciliation; untouched |
| Weekly tasks, notes | No changes |
| Wishlist (`wishlist_items`, `custom_tasks`) | No changes |
| `budget_transactions` | Preserved until Phase 5G explicitly retires write path; all rows migrated before retirement |
| Budget printout + `_getBudgetLivingExpenses()` | Unchanged until Phase 5G; JS fallback covers transition |
| `BUDGET_CATEGORY_REGISTRY` JS | Preserved as fallback until Phase 5D-1 Supabase load confirmed stable |
| `BUDGET_PAYMENT_ACCOUNTS` JS | Same |
| RLS policies (Phase 5A) | Extended to new tables only; existing policies not weakened |
| Auth / sign-out / role enforcement | No changes |
| Regression tests (687 passing) | All must pass after every phase; none removed |
| BUILD_TS / push workflow | No changes |

---

## Phased Build Plan (Final)

### Phase 5C — Design (complete)
This document. No code.

### Phase 5D-1 — Supabase Registry Foundation
- Create `accounts` and `categories` tables with full schema including `budget_line_key`, `budget_group_key`, `lifecycle_status`, `updated_by`
- Seed from existing JS arrays + Wendy's confirmed category list [CONFIRM: required before build]
- JS arrays refactored to load from Supabase; JS values become fallback
- RLS on both tables per role-operation matrix
- Feature flag: `useSupabaseRegistries`
- All 687 existing tests pass; Phase 5D-1 tests added
- No UI changes visible to users

**Budget-line key validation (gate before seed is committed):**

The following must all be true before Phase 5D-1 ships. Validation queries run as part of the migration SQL:

1. Every leaf category with `budget_treatment = 'tracked'` has a non-null `budget_line_key`.
2. Every `budget_line_key` value resolves to an existing key in `budget_line_rules`. No orphan values.
3. Every category with `budget_treatment = 'tracked'` or `'display_only'` has a non-null `budget_group_key`.
4. `budget_treatment = 'excluded'` categories may have NULL on both fields — expected.
5. The `planned_allocation` category (`misc.goal_sweep`) has valid `budget_line_key` and `budget_group_key` values.

Validation queries are part of the Phase 5D-1 migration file and must return zero rows before the seed is accepted.

**Rollback point:** If Supabase load fails or registry mismatch detected, JS fallback activates automatically. No user impact.

### Phase 5D-2 — Account and Category Management UI
- Transactions nav section visible (skeleton sub-nav)
- Transactions > Categories: add/edit/archive UI with behavior change guardrails
- Account list visible; lifecycle_status filtering; "Balance not set" state
- Feature flag: `showTransactionSection`

### Phase 5E — Account-First Transaction Ledger
- Create `transactions`, `transaction_splits`, `reconciliations` (schema only) tables
- Split-sum DB trigger created with tables in Phase 5E — DEFERRABLE INITIALLY DEFERRED; not postponed to Phase 5F (ledger must be valid from day one)
- Account register with running balance, cleared checkbox, Add/Edit/Delete transaction
- Single split row per transaction in UI (schema supports multiple)
- Category behavior drives form fields
- Go-live starting balance setup UI (per account)
- Transfer pairing: `transfer_group_id` and `transfer_role` set when transfer category selected
- Migrate `budget_transactions` → `transactions` + `transaction_splits`
- Feature flag: `useNewTransactionsLedger`

**Migration validation (must pass before Phase 5E ships):**

Run as part of Phase 5E migration SQL. All four queries must return zero rows:

```sql
-- 1. Every migrated transaction has exactly one split
SELECT t.id FROM transactions t
LEFT JOIN transaction_splits s ON s.transaction_id = t.id
WHERE t.import_source = 'migration'
GROUP BY t.id HAVING COUNT(s.id) != 1;

-- 2. Split amount equals parent total_amount
SELECT t.id, t.total_amount, s.amount FROM transactions t
JOIN transaction_splits s ON s.transaction_id = t.id
WHERE t.import_source = 'migration'
AND t.total_amount != s.amount;

-- 3. No transaction exists with zero splits
SELECT t.id FROM transactions t
WHERE t.import_source = 'migration'
AND NOT EXISTS (SELECT 1 FROM transaction_splits s WHERE s.transaction_id = t.id);

-- 4. Row count matches source
-- Expected: both counts equal
SELECT COUNT(*) FROM budget_transactions;
SELECT COUNT(*) FROM transactions WHERE import_source = 'migration';
```

### Phase 5F — Reconciliation Upgrade
- Full reconciliation modal on account register
- Adjustment creation with memo + ADJ badge
- Reconciled transaction locking
- Reconciliation History sub-nav
- Feature flag: `enableReconciliationV2`
- Note: split-sum DB trigger is in Phase 5E, not here

### Phase 5G — Budget Integration + $2,300 Fix
- Budget actuals switch from `budget_transactions` to `transaction_splits`
- `planned_allocation` treatment for $2,300 line; inside budget math
- Parallel validation before cutover
- Retire `budget_transactions` as write target
- Feature flag: `useTransactionSplitsForBudget`

### Phase 5H — Goal-Linked Category Reporting
- `linked_goal_id` populated on goal categories (requires goal ID mapping)
- Goal card: Target | Saved | Spent | Available Reserve | Funding Remaining
- Feature flag: `enableGoalLinkedSpend`

### Phase 5I — Split Transaction UI
- Multi-split form: add/remove rows, live unallocated display, validation
- "Split (N)" expand in register
- Feature flag: `enableSplitTransactionUI`

### Phase 5J — Import Readiness
- `import_batches`, `import_queue`, `payee_rules` tables
- CSV upload, normalization, review queue, dedup
- Feature flag: `enableImportQueue`

---

## Phase 5D-1 Discovery Confirmations
_Complete as of June 26, 2026. These are the authoritative inputs for the Phase 5D-1 seed SQL._

### Confirmed Account List

| OS label | Quicken name | account_type | Institution | lifecycle_status |
|----------|-------------|-------------|-------------|----------------|
| Truist Checking | SunTrust Checking | checking | Truist | active |
| Truist Savings | Suntrust Savings 2 | savings | Truist | active |
| Blue AMEX | AMEX2 | credit_card | American Express | active (low volume) |
| BOA Visa | BOA VISA | credit_card | Bank of America | active (low volume) |
| Chase Disney Visa | Chase Disney Visa | credit_card | Chase | active |
| Gold AMEX | Gold AMEX | credit_card | American Express | active |
| Platinum AMEX | Platinum AMEX | credit_card | American Express | active |
| Truist Mastercard | Suntrust Mastercard | credit_card | Truist | active (low volume) |
| AMEX Savings | AMEX Savings | savings | American Express | active |
| Vio Bank Emergency Savings | Vio Bank *3588 | savings | Vio Bank | active |
| Vio Bank Tax Reserve Savings | Vio Bank *2449 | savings | Vio Bank | active |
| Lending Club (EF) | — (already in Weekly Model) | savings | Lending Club | active |
| Fidelity Joint WROS-TOD | — | investment | Fidelity | view_only |
| Bailey's Capital One Checking | — | checking | Capital One | excluded |
| Bailey's Capital One Savings | — | savings | Capital One | excluded |
| Bailey's UTMA (Fidelity) | — | investment | Fidelity | excluded |
| Investing / Property & Debt / Empower | Various | various | Various | excluded |

**Notes:**
- Blue AMEX (Blue Cash Everyday), BOA Visa, and Truist Mastercard are kept open for credit score purposes. Expect fewer than one transaction per month on each.
- Lending Club is already tracked in the OS Weekly Model as "Lending Club (EF)" ($13,488.88). Full entry because the $250/month transfer from Vio Bank Tax Reserve must be recorded as a paired transaction.
- Fidelity WROS-TOD holds FZFXX money market (~$92,771). No transaction entry; balance updated manually as needed. Joint account.
- Bailey's accounts: Adam assists with management but they are not household operating accounts. Nothing active for Bryce or Preston yet.
- Starting balances for all in-scope accounts: captured at go-live (7/1/26), not during discovery.

### Confirmed Category Classifications

| Category | behavior_class | budget_treatment | cashflow_treatment | is_leaf | Notes |
|----------|---------------|-----------------|-------------------|---------|-------|
| Taxes 2026 | transfer | excluded | tax_reserve | true | Transfers to Vio Bank Tax Reserve only. Not for IRS payments. |
| taxes.actual_tax_payment | expense | excluded | tax_reserve | true | **New category.** Actual IRS/state tax payments from checking, drawn from tax reserve. Excluded from monthly budget (large, irregular). Label: "Tax Payment." |
| Entertainment | — | — | — | **false** | Parent category. Transactions always go to a subcategory, never to Entertainment directly. |
| Birthday Dinner | expense | tracked | operating | true | Subcategory of Entertainment. Active — not archived. |
| Brunch | expense | tracked | operating | true | Subcategory of Entertainment. |
| Big Dinner Out | expense | tracked | operating | true | Subcategory of Entertainment. |
| Entertainment Other | expense | tracked | operating | true | Subcategory of Entertainment. Catch-all leaf. |
| Flexible Spending 2026 | reimbursable_expense | excluded | reimbursable | true | Both FSA expenses AND FSA reimbursement deposits use this same category. No paired category. Form fields conditioned on transaction direction (see Freeze Addendum). |
| Greenlight | transfer | excluded | excluded | true | Transfers to kids' Greenlight debit cards. One-sided (Greenlight not an OS account). |
| 2026 Seattle/Alaska | goal_linked | **excluded** | **goal_spending** | true | Trip spending, not goal funding. Appears in Goals section only; does not compress monthly budget allocation. |
| 2026 RCCL Girls Trip | goal_linked | **excluded** | **goal_spending** | true | Same as above. |
| 2026 DCL Trip | goal_linked | **excluded** | **goal_spending** | true | Same as above. |
| 2026 RCCL Christmas Cruise | goal_linked | **excluded** | **goal_spending** | true | Same as above. |
| jabian 2026 (lowercase) | — | — | — | — | Archive and merge into Jabian Expenses 2026. Confirmed duplicate. |

### Section 8 — Architecture Decisions (All Confirmed)

| Decision | Confirmed answer |
|----------|----------------|
| Planned goal funding amount | Variable. Computed dynamically as `monthly_budget_target - sum(tracked lines)`. Not a stored static value. Current baseline ~$2,300. See Planned Goal Funding section. |
| Pre-migration budget months | **Option A**: show migrated `budget_transactions` data as historical actuals. Provides continuity; no blank history. |
| Goal card primary metric | **Available Reserve (Saved - Spent)** is the primary display metric. Funding Remaining is secondary. |
| Investment / property / retirement accounts | Excluded from OS scope for now. |
| Starting balance capture | Confirmed at go-live (7/1/26). Not gathered during discovery. |
| Feature flag staged rollout | Confirmed. |
| Wendy's role | **household_admin**. Full financial entry; cannot unlock reconciled transactions, cannot change category behavior fields, cannot manage payee/import rules. |

---

## Open Questions

**Phase 5D-1 blockers — ALL RESOLVED.** See Phase 5D-1 Discovery Confirmations section.

- [x] Full Quicken account list: confirmed — see Discovery Confirmations
- [x] "jabian 2026" vs "Jabian Expenses 2026": confirmed duplicate — archive and merge
- [x] "Taxes 2026" treatment: confirmed transfer to Vio Bank Tax Reserve; excluded from budget
- [x] Category hierarchy: Entertainment is parent (is_leaf = false); named subcategories confirmed
- [x] Investment and property accounts: excluded
- [x] Is $2,300 fixed or variable: variable — computed dynamically (see Planned Goal Funding section)
- [x] Budget view for pre-migration months: Option A (historical actuals from migrated data)
- [x] Available Reserve as primary goal card metric: confirmed
- [x] Starting balance capture process: confirmed at go-live (7/1/26)
- [x] Feature flags staged rollout: confirmed
- [x] Wendy's role: confirmed household_admin

**Confirm before Phase 5E (useful to gather now):**
- [ ] Transaction entry workflow: real-time, weekly batch, or statement-based?
- [ ] Split transaction frequency: daily / weekly / monthly / rarely?
- [ ] Running balance: required in Phase 5E or later enhancement?
- [ ] Entry mode: desktop, mobile, or both?

**Confirm before Phase 5F:**
- [ ] Reconciliation workflow: monthly at statement close, weekly, or ad hoc?
- [ ] Reconciliation history: needed or just complete and move on?

**Not needed until go-live (7/1/26):**
- Starting balance values for each in-scope account

**Not needed until Phase 5J:**
- Import expectations, CSV export availability by institution

---

## Explicit Assumptions

| Assumption | Phase | Confirm before |
|------------|-------|---------------|
| Entry workflow is account-first (not date-first or category-first) | 5E UI | 5E |
| "Gold AMEX" in Quicken = "AMEX Gold" in OS | Account seed | 5D-1 |
| Investment/property accounts are view_only, not full entry | 5E scope | 5D-1 |
| 2026 Seattle/Alaska goal exists in `goals` table | Phase 5H linking | 5H |
| "Greenlight" is a transfer to kids' debit cards | behavior_class = transfer | 5D-1 |
| Planned goal allocation is computed dynamically (monthly_target - tracked lines), not stored as a fixed amount | 5G planned_allocation | — (confirmed 6/26) |
| "jabian 2026" and "Jabian Expenses 2026" are the same | Category dedup | 5D-1 |
| Wendy reconciles full statement cycles | Reconciliation model | 5F |
| Running balance required from Phase 5E | 5E register design | 5E |
| Split transactions are not dominant workflow (<once/week) | Phase 5I deferral | 5E |
| All `budget_transactions` data is valid and migratable | Phase 5E migration | 5E |
| Starting balances captured at go-live, not during discovery | 5D-1 account seed | 5D-1 |
| Balance snapshot optimization not needed for 2+ years | 5E balance computation | — |

---

---

## Architecture Freeze Addendum
_v3.3 — June 26, 2026 | Final hardening pass before Phase 5D-1 coding begins_
_18 items reviewed. 15 accepted, 3 modified (RPC security model, FSA behavior class, delete/void policy). No items deferred._

---

### 1. Atomic Transaction Save (Phase 5E)

All transaction + split saves use a single Supabase RPC function. No multi-call REST saves for parent + splits — a failed second call would leave orphaned split rows or a split-less parent.

**Function signature:**
```sql
CREATE FUNCTION save_transaction_with_splits(
  p_transaction jsonb,
  p_splits      jsonb[]
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER          -- see Item 2
SET search_path = public, auth;
```

**Function responsibilities (in order, fully atomic):**
1. Verify `auth.uid()` is non-null; reject immediately if unauthenticated
2. Look up caller's role (`owner` / `household_admin`)
3. Check reconciled-period lock (see Item 3): block household_admin from backdating into a completed reconciliation period
4. If updating: confirm `is_reconciled = false`, or caller is owner with required reason
5. Validate each split: `category.is_leaf = true` AND `category.lifecycle_status = 'active'`
6. Validate `SUM(splits.amount) = transaction.total_amount`
7. INSERT/UPDATE parent transaction row
8. DELETE existing split rows for that `transaction_id` (on update path)
9. INSERT all new split rows
10. Return saved transaction + splits as JSON
11. Any failure rolls back the entire block atomically

**DB trigger coexistence:** The split-sum trigger (created with the tables in Phase 5E) remains as a last-line-of-defense safeguard. The RPC validates first; the trigger catches anything that bypasses the RPC. Both are required. See Item 5 below for required trigger configuration to support multi-split saves.

---

### 1a. Split-Sum Trigger — Deferrable Constraint Required

The split-sum DB trigger (last-line-of-defense safeguard) must be a **DEFERRABLE INITIALLY DEFERRED** constraint trigger. A standard row-level AFTER trigger fires after each individual `INSERT` and will fail a multi-split save before all splits are written.

**The problem:**
```
Parent total_amount = -300
Insert split 1: amount = -220  → trigger fires → SUM(-220) ≠ -300 → FAILS ✗
Insert split 2: never reached
```

**The fix — DEFERRABLE constraint trigger (DELETE-safe final version):**
```sql
CREATE OR REPLACE FUNCTION fn_validate_split_sum()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_txn_id       uuid;
  v_parent_total numeric(12,2);
  v_splits_total numeric(12,2);
BEGIN
  -- Branch on operation: DELETE uses OLD (NEW is NULL on delete)
  v_txn_id := CASE TG_OP WHEN 'DELETE' THEN OLD.transaction_id ELSE NEW.transaction_id END;

  SELECT total_amount INTO v_parent_total FROM transactions WHERE id = v_txn_id;
  SELECT COALESCE(SUM(amount), 0) INTO v_splits_total
  FROM transaction_splits WHERE transaction_id = v_txn_id;

  IF v_splits_total != v_parent_total THEN
    RAISE EXCEPTION 'Split sum (%) != transaction total_amount (%) for transaction %',
      v_splits_total, v_parent_total, v_txn_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE CONSTRAINT TRIGGER trg_split_sum_check
  AFTER INSERT OR UPDATE OR DELETE ON transaction_splits
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION fn_validate_split_sum();
```

**Why this works:**
- `DEFERRABLE INITIALLY DEFERRED` means the trigger fires at **transaction COMMIT time**, not after each row
- Inside the RPC: delete old splits → insert split 1 → insert split 2 → all deferred, no trigger fires mid-transaction
- On COMMIT: trigger fires for each affected row; at that point all splits exist; SUM(-220 + -80) = -300 = parent total ✓
- If anything fails: the entire RPC rolls back atomically — no partial writes
- `TG_OP WHEN 'DELETE'` uses `OLD.transaction_id` because `NEW` is NULL on delete

**What this trigger covers:**
- INSERT of splits (multi-split safe via deferral) ✓
- UPDATE of split amounts ✓
- DELETE of a split (sum re-validated after deletion) ✓

**What this trigger does NOT cover:**
- Direct `UPDATE` of `transactions.total_amount` (a separate trigger on `transactions` would be required; see direct-write boundary section below)
- Direct `INSERT` of a transaction row with zero splits (no split row = no trigger fires; enforced by RPC pre-commit validation)

**Coexistence with RPC validation:** The RPC validates split sum at step 6 (before any writes). The trigger catches anything that bypasses the RPC. RPC = primary enforcement; trigger = safety net. Both fire in the correct order with deferral.

**Scope:** This trigger definition is included in the Phase 5E migration SQL when the `transaction_splits` table is created.

---

### 1b. RPC/Direct-Write Boundary

**Direct REST writes to `transactions` and `transaction_splits` are possible under SECURITY INVOKER + current RLS.** The UI always calls the RPC; it never writes directly to these tables. However, Supabase REST is a general interface and a client with a valid JWT could bypass the RPC.

**Explicit boundary definition:**

| Path | Who uses it | Invariants enforced by |
|------|------------|----------------------|
| RPC `save_transaction_with_splits` | UI (all normal saves) | RPC validation + DB trigger + RLS |
| Direct REST INSERT/UPDATE/DELETE on `transactions` | Not used by UI; possible via Supabase client | RLS only + DB trigger (partial) |
| Direct REST INSERT/UPDATE/DELETE on `transaction_splits` | Not used by UI; possible via Supabase client | RLS only + DB trigger (split sum) |

**DB-level invariants that hold even for direct writes:**
- Split sum = parent total_amount: enforced by the deferrable trigger on `transaction_splits` for INSERT/UPDATE/DELETE ✓
- Enum field validity: enforced by CHECK constraints ✓
- Leaf-category assignment: enforced by the categories CHECK constraint on `is_leaf` (UI filter) — but NOT by a FK constraint on `transaction_splits.category_id` (JOIN check would require a trigger) ✗

**Invariants only enforced by the RPC (not by DB):**
- Reconciled-period backdating lock
- Leaf-category enforcement on split category assignment
- Transfer role consistency rules
- Zero-splits transaction block

**Mitigation for direct-write gaps:** The risk surface is a two-person household where both users are known. The practical defense is RLS (only authenticated users can write; roles are enforced) plus the DB trigger for split sums. A future hardening option — not in Phase 5E — is a `BEFORE INSERT OR UPDATE` trigger on `transactions` that validates that at least one split exists (requires a `DEFERRABLE` approach or a two-step check). For now, document the boundary explicitly so it is not accidentally widened.

**`total_amount` direct UPDATE:** A direct `UPDATE transactions SET total_amount = X` would invalidate the split sum without the `transaction_splits` trigger firing. Mitigation: add a trigger on `transactions.total_amount` UPDATE in Phase 5E that re-validates the split sum for that transaction. SQL:

```sql
CREATE OR REPLACE FUNCTION fn_validate_total_amount_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_splits_total numeric(12,2);
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO v_splits_total
  FROM transaction_splits WHERE transaction_id = NEW.id;
  IF v_splits_total != NEW.total_amount THEN
    RAISE EXCEPTION 'Cannot update total_amount: existing split sum (%) != new total_amount (%)',
      v_splits_total, NEW.total_amount;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_total_amount_update_check
  BEFORE UPDATE OF total_amount ON transactions
  FOR EACH ROW EXECUTE FUNCTION fn_validate_total_amount_update();
```

This trigger does NOT need to be deferrable because it fires before the `total_amount` change is written, not after a set of split inserts.

---

### 2. RPC Security Model

**Decision: SECURITY INVOKER, not SECURITY DEFINER.**

| | SECURITY INVOKER | SECURITY DEFINER |
|--|-----------------|-----------------|
| Runs as | Authenticated Supabase user (calling JWT) | Function owner (typically `postgres`) |
| RLS evaluation | Automatic — all table policies apply | Bypassed unless manually re-checked inside function |
| Risk if a check is missed | None — RLS still enforces | Potential data access bypass |
| Manual role checks needed | Business logic only (reconciled-period lock, owner operations) | Every RLS rule must be re-implemented inside function |

**For this stack, INVOKER is the correct default.** DEFINER should only be used when privilege escalation is specifically required. No such requirement exists here.

**Required hardening for INVOKER:**
```sql
SET search_path = public, auth;  -- prevents search_path injection
```

**Two-layer security contract:**

| Layer | Mechanism | Responsibility |
|-------|-----------|---------------|
| Layer 1: Row access | RLS policies on all tables | Who can touch which rows at all |
| Layer 2: Ledger business rules | Checks inside the RPC function | Rules RLS cannot express |

Layer 2 rules enforced inside the RPC (additive to RLS, not replacements):

| Rule | Who it blocks |
|------|--------------|
| Reconciled-period backdating lock | `household_admin` blocked; `owner` allowed with required reason |
| Leaf-category enforcement | Both roles; parent categories rejected regardless of RLS |
| Split-sum validation | Both roles; invalid sums rejected before any writes |
| Transfer role consistency | Both roles; structural rules always enforced |
| Reconciled transaction edit/delete | All users; RPC rejects regardless of RLS |

**Test coverage requirement:** RPC tests must cover three caller types — unauthenticated (null `auth.uid()`), `household_admin`, and `owner` — for every operation. See expanded RLS test matrix (Item 18).

---

### 3. Reconciled-Period Backdating Lock

The existing design locks reconciled *transactions*. This addendum closes the gap: new transactions must also be blocked from backdating into a completed reconciliation period.

**Rule table:**

| Action | If transaction_date ≤ latest completed reconciliation.statement_date for that account | household_admin | owner |
|--------|--------------------------------------------------------------------------------------|----------------|-------|
| Create new transaction | Reconciled period | Blocked | Allowed with required reason |
| Edit existing transaction | Reconciled period | Blocked (existing rule) | Allowed via unlock with required reason |
| Delete existing transaction | Reconciled period | Blocked | Not allowed — correcting transaction is the path |

**RPC implementation:** Before saving, the function queries:
```sql
SELECT MAX(statement_date) FROM reconciliations
WHERE account_id = p_account_id AND status = 'completed'
```
If `transaction_date ≤ result` and caller is `household_admin`, reject with error.

**UI:** If the entered date falls in a reconciled period, warn before form submission: "This date falls within a completed reconciliation period. This transaction may affect a previously reconciled balance." The RPC enforces the final rule; the UI surfaces the warning early.

---

### 4. Single Active Reconciliation Per Account

Only one in-progress reconciliation may exist per account at a time.

**DB enforcement (Phase 5E, when reconciliations table is created schema-only):**
```sql
CREATE UNIQUE INDEX idx_reconciliations_one_active_per_account
ON reconciliations (account_id)
WHERE status = 'in_progress';
```
The `reconciliations` table is created in Phase 5E alongside `transactions` and `transaction_splits`. The partial unique index is created in the same Phase 5E migration — not deferred to Phase 5F. Phase 5F adds the reconciliation UI and workflow on top of the already-existing schema.

**Application behavior:** When starting a new reconciliation session, check for an existing in-progress session for that account. If found: offer to resume the existing session or abandon it (confirmation required). Abandon sets `status = 'abandoned'`, records `abandoned_by`, and logs the event.

---

### 5. Reconciliation Audit Fields

The `reconciliations` table schema has been updated (see Data Model section) to include:
- `updated_by` / `updated_at` — standard audit fields
- `completed_by` — set explicitly when `status → completed`; not inferred from `updated_by`
- `abandoned_by` — set explicitly when `status → abandoned`

**Rationale:** Reconciliation status changes are material ledger events. When a session is completed or abandoned, the person responsible must be explicitly recorded. Inferring it from `updated_by` + status creates ambiguity if any other field is also updated in the same operation.

---

### 6. Transfer Validation Rules

All rules enforced in the `save_transaction_with_splits` RPC and surfaced in the UI form.

| Rule | Type | Enforcement |
|------|------|-------------|
| `transfer_group_id` set → `transfer_role` required | Hard block | RPC rejects |
| `transfer_role` set → `category.behavior_class` must be `transfer` | Hard block | RPC rejects |
| `outflow` → `total_amount` should be negative | Soft warning | UI warns; user confirms |
| `inflow` → `total_amount` should be positive | Soft warning | UI warns; user confirms |
| Two in-scope rows sharing `transfer_group_id` → amounts should net to ≈$0 | Soft warning | Register shows pairing warning |
| `standalone` role → no pairing required | Allowed | No warning |

Sign mismatch for outflow/inflow is a warning, not a block. Legitimate edge cases (transfer reversals, corrections) may differ from the default convention. Hard blocks apply only to structural rules.

---

### 7. UI Amount-Entry and Sign Conversion

**Rule:** Users always enter positive dollar amounts. The system applies the wallet-perspective sign on save. No user ever types "−" in normal workflow.

**Conversion table:**

| Scenario | Stored sign | UI entry | Form signal |
|----------|------------|---------|-------------|
| Checking/savings expense | −$X | $X | Default for expense categories |
| Credit card charge | −$X | $X | Default for expense categories |
| Checking/savings deposit | +$X | $X | Default for income categories |
| Credit card payment (outflow from checking) | −$X | $X | Transfer outflow |
| Credit card payment (inflow to card) | +$X | $X | Transfer inflow |
| Transfer out | −$X | $X | Transfer outflow |
| Transfer in | +$X | $X | Transfer inflow |
| Reimbursable expense | −$X | $X | expense direction |
| Reimbursement received | +$X | $X | income direction |
| Refund / credit | +$X | $X | "Refund" toggle |
| Tax payment from checking | −$X | $X | expense direction |

**Direction logic:** Determined by the primary split's `behavior_class`:
- `expense`, `reimbursable_expense`, `goal_linked`, `savings_allocation` → negate
- `income`, `reimbursable_income`, `commission_income` → keep positive
- `transfer` → outflow = negate; inflow = keep positive
- Refund override: "Refund / Credit" toggle → keep positive regardless of category

**Refunds:** The form includes a "Refund / Credit" toggle for transactions on expense categories where money is coming back. When toggled, the stored amount is positive (balance increases). Budget display: positive amount offsets the expense total for that category in that month.

---

### 8. Flexible Spending 2026 — Same-Category Handling

**Decision:** `behavior_class = reimbursable_expense` is correct. No new behavior class needed.

The same category handles both the FSA expense (negative, money going out) and the FSA reimbursement deposit (positive, money coming back). Form behavior is conditioned on transaction direction:

| Transaction direction | Form fields shown | Stored sign |
|----------------------|------------------|------------|
| FSA medical charge (expense out) | Reimbursable Source, Reimbursement Status, Received Date | −$X |
| FSA reimbursement deposit (money in) | No extra fields | +$X |

**UI logic:** When Flexible Spending 2026 is selected and the transaction is entering money into a checking account (positive direction), suppress Source/Status fields — treat as reimbursement receipt side. If negative direction, show Source/Status fields normally.

`budget_treatment = excluded` and `cashflow_treatment = reimbursable` apply regardless of direction. No schema change required.

**Reporting and netting:** Reports and budget actuals that aggregate this category must handle both positive and negative amounts under the same category key. The net for the year is approximately $0. A "reimbursable tracking" report shows: total FSA expenses (sum of negative amounts), total FSA deposits received (sum of positive amounts), and net outstanding (expenses + deposits; should approach $0 by year-end). No special column or flag is needed on the split row — direction is determined by the sign of `amount`.

---

### 9. Goal-Linked Spending vs Goal Funding — Definitive Resolution

**This is a correction to the previously confirmed category table.** ChatGPT correctly identified that trip spending is not goal funding.

**Definitions:**
- **Goal funding** (`cashflow_treatment = goal_funding`): the monthly transfer from checking to AMEX Savings building the goal reserve. This is what the planned_allocation (~$2,300 residual) represents.
- **Goal spending** (`cashflow_treatment = goal_spending`): actual trip expenses paid while traveling (e.g., Alaska hotel on Gold AMEX). Money is drawn from the pre-funded reserve.

**The budget double-count problem:** If goal-linked trip spending has `budget_treatment = tracked`, it appears as a living expense and compresses the monthly residual allocation. But the money was already earmarked via prior months' goal funding. Showing it as a current-month tracked expense creates the perception of double compression. The monthly budget should show: living expenses + planned allocation only.

**Corrected treatment for all goal-linked trip categories:**

| Category | budget_treatment | cashflow_treatment |
|----------|-----------------|-------------------|
| 2026 Seattle/Alaska | **excluded** ~~(was tracked)~~ | **goal_spending** ~~(was goal_funding)~~ |
| 2026 RCCL Girls Trip | **excluded** | **goal_spending** |
| 2026 DCL Trip | **excluded** | **goal_spending** |
| 2026 RCCL Christmas Cruise | **excluded** | **goal_spending** |

**Where goal spending appears:** Goals section only, via `transaction_splits WHERE category.linked_goal_id = goal.id`. Available Reserve (Saved − Spent) captures it. The Budget section does not show it and the monthly allocation compression formula does not include it.

**Flows this change must propagate through:**

| Area | Required update |
|------|----------------|
| Allowed `cashflow_treatment` values | `goal_spending` added ✓ |
| DB CHECK constraint on `categories.cashflow_treatment` | `goal_spending` included ✓ |
| Seed validation (Phase 5D-1) | Trip category `budget_line_key` is NULL (excluded); REG-BL-4 already allows NULL for excluded categories ✓ |
| Phase 5G budget actuals | `goal_linked` splits must be excluded from budget actuals aggregate (budget_treatment = excluded) |
| Phase 5H goal-spending tests | Goal Spent must sum `goal_spending` splits; Available Reserve must reflect them |
| Category classification tables | All four trip categories corrected ✓ |

**New tests required:**

| Test | Description |
|------|-------------|
| REG-BUDACT-4 | `goal_linked` split with `budget_treatment = excluded` does NOT appear in budget actuals for that month |
| REG-GOAL-4 | Goal Spent = SUM of splits where `category.linked_goal_id = goal.id` AND `cashflow_treatment = goal_spending` |
| REG-GOAL-5 | A $500 Alaska trip charge in July does not compress the July planned allocation |

---

### 10. Actual IRS/State Tax Payment Category

Added to Phase 5D-1 seed. Distinct from "Taxes 2026" (which is only the transfer to Vio Bank Tax Reserve).

| Field | Value |
|-------|-------|
| `key` | `taxes.actual_tax_payment` |
| `label` | "Tax Payment" |
| `behavior_class` | `expense` |
| `budget_treatment` | `excluded` |
| `cashflow_treatment` | `tax_reserve` |
| `is_leaf` | true |

**Rationale:** IRS/state payments are large, irregular outflows funded from the Vio Bank Tax Reserve — not from the monthly living budget. `budget_treatment = excluded` prevents them from compressing the monthly allocation. `cashflow_treatment = tax_reserve` links them to the tax reserve concept in the cashflow model.

**Why not a new `tax_payment` behavior class:** Form behavior is the same as any expense (Date, Payee, Amount). The cashflow_treatment is the distinguishing attribute.

---

### 11. Account-List UI Grouping

With 12 full-entry accounts + 1 view-only, the Transactions left rail is grouped by account type, not displayed as a flat list.

| Group | Accounts |
|-------|---------|
| Checking & Savings | Truist Checking, Truist Savings, AMEX Savings, Vio Bank Emergency Savings, Vio Bank Tax Reserve Savings, Lending Club (EF) |
| Credit Cards | Gold AMEX (1), Platinum AMEX (2), Chase Disney Visa (3), Truist Mastercard (10), Blue AMEX (11), BOA Visa (12) |
| View-Only | Fidelity Joint WROS-TOD |

Numbers indicate `display_order` seed values. No new schema column required — groups are derived from `account_type` + `lifecycle_status` in the UI render. Low-volume cards (Truist Mastercard, Blue AMEX, BOA Visa) appear at the bottom of the Credit Cards group via display_order, not hidden.

---

### 12. budget_line_rules.category_key Semantic Clarification

**`budget_line_rules.category_key` stores `budget_line_key` values, not `categories.key` values.** This is a legacy naming artifact predating the three-tier model.

The column name is preserved for compatibility with existing code (`_getBudgetAmount(categoryKey, monthIso)`). Any code comment referencing it must note: _"despite the column name, this stores a budget_line_key (a planning aggregate), not a single category key."_

**Phase 5G join pattern (correct):**
```sql
categories.budget_line_key = budget_line_rules.category_key
-- NOT: categories.key = budget_line_rules.category_key
```

**Future:** Rename the column to `budget_line_key` when the table is next touched in a migration.

---

### 13. Month-Aware Budget Validation and Overlap Prevention

**REG-BL-2 is explicitly month-scoped.** A tracked category with no active `budget_line_rules` row in a given month (because the row expired, e.g., Diablos after December 2026) is correct behavior, not a validation error. The validation runs against the current month only.

**New: overlap prevention query** (required to pass before any `budget_line_rules` seed is committed):
```sql
SELECT a.category_key, a.start_month, a.end_month,
       b.start_month AS b_start, b.end_month AS b_end
FROM budget_line_rules a
JOIN budget_line_rules b
  ON a.category_key = b.category_key
  AND a.id != b.id
  AND a.is_active = true
  AND b.is_active = true
  AND a.start_month <= COALESCE(b.end_month, '9999-01-01'::date)
  AND COALESCE(a.end_month, '9999-01-01'::date) >= b.start_month;
```
**Must return zero rows.** Catches the case where a rent-increase row is inserted for July 2026 without end-dating the prior open-ended row, which would cause double-counting.

**New test:**

| Test | Description |
|------|-------------|
| REG-BL-OVERLAP-1 | No overlapping active `budget_line_rules` rows exist for any `category_key` |

---

### 14. Database CHECK Constraints

All enum-like fields have DB-level CHECK constraints written into the CREATE TABLE statements. Application validation is not sufficient for ledger data.

| Table | Column | Allowed values |
|-------|--------|---------------|
| `accounts` | `account_type` | `checking`, `savings`, `credit_card`, `investment`, `property`, `loan`, `cash` |
| `accounts` | `lifecycle_status` | `active`, `closed`, `view_only`, `hidden`, `excluded` |
| `categories` | `behavior_class` | `expense`, `income`, `reimbursable_expense`, `reimbursable_income`, `goal_linked`, `savings_allocation`, `transfer`, `commission_income` |
| `categories` | `budget_treatment` | `tracked`, `planned_allocation`, `display_only`, `excluded` |
| `categories` | `cashflow_treatment` | `operating`, `goal_funding`, `goal_spending`, `tax_reserve`, `reimbursable`, `excluded` |
| `categories` | `lifecycle_status` | `active`, `archived`, `merged` |
| `transactions` | `transfer_role` | `outflow`, `inflow`, `standalone` (NULLable for non-transfers) |
| `transactions` | `import_source` | `manual`, `csv_import`, `bank_sync`, `migration` |
| `reconciliations` | `status` | `in_progress`, `completed`, `abandoned` |
| `import_queue` (Phase 5J) | `status` | `pending_review`, `accepted`, `rejected`, `duplicate` |

---

### 15. Leaf-Category Enforcement

Parent categories (`is_leaf = false`) cannot be assigned to transaction splits.

**Enforcement in `save_transaction_with_splits` RPC:** For each split's `category_id`, verify:
```sql
SELECT is_leaf, lifecycle_status FROM categories WHERE id = p_category_id;
-- Reject if is_leaf = false OR lifecycle_status != 'active'
```

**Why not a DB constraint:** The check requires joining `categories`; a simple CHECK constraint cannot do this. A trigger on `transaction_splits` is a valid alternative and can be added as a Phase 5E safety net if needed. The RPC is the primary enforcement point.

**UI:** Category dropdown filters to `is_leaf = true AND lifecycle_status = 'active'` only. Parent categories never appear as selectable options.

---

### 16. Transaction Delete Policy

**No soft-delete or void state in Phase 5E.** Void semantics add immediate UX questions (do voided transactions show in the register? affect the running balance? appear in budget actuals?) that are not worth answering before the core ledger exists. Hard delete with appropriate friction is correct for this phase.

| Status | Phase 5E | Phase 5F+ | Notes |
|--------|---------|----------|-------|
| Uncleared, manual entry | Hard delete allowed | Hard delete allowed | Never confirmed on a statement |
| Cleared (not reconciled) | **Delete blocked** | Owner-only; required reason; audit logged | Block lifted when `transaction_audit_log` ships in Phase 5F |
| Imported (any status) | **Delete blocked** | Owner-only; required reason; audit logged | Same policy as cleared |
| Reconciled | Locked — no delete | Locked — no delete | Create correcting transaction |

**Why block rather than warn for Phase 5E:** A warning dialog is not a sufficient guardrail for a cleared transaction. Cleared means the transaction has been confirmed against a bank statement. Hard-deleting it without an audit trail is a ledger integrity problem. Since the audit log ships in Phase 5F (the very next phase), the blocking period is short. Implementing a special-case minimal audit record outside the audit infrastructure in Phase 5E creates a one-off path that would need cleanup. Block in 5E; full policy in 5F.

Void semantics are a future decision once the audit log and UI behavior for voided transactions can be designed deliberately.

---

### 17. Starting Balance Mutation Policy

| Scenario | Phase 5E | Phase 5F+ |
|----------|---------|----------|
| Not yet set (no transactions) | owner or household_admin — no restriction | Same |
| Set; no transactions yet | owner or household_admin — no restriction | Same |
| Set; transactions exist | **Blocked for all users** | owner only; required reason; audit logged |

**Why block in Phase 5E:** `starting_balance` is the ledger anchor. Changing it after transactions exist silently alters every computed running balance for that account — a more impactful operation than deleting a cleared transaction. Allowing it without an audit trail (even with `updated_by`/`updated_at` alone) is insufficient for a ledger anchor. The audit log ships in Phase 5F. The go-live balance setup happens before any transactions exist, so this block does not affect the go-live workflow.

**Pre-anchor transaction dates:** If `transaction_date < starting_balance_as_of` for the account, the running balance computation is technically correct (anchor + all amounts from all dates) but the register display will show a balance before the anchor date that may confuse Wendy. Rule: surface a UI warning — "This date is before this account's starting balance date. The balance displayed before [date] may not be meaningful." Do not block the entry; legitimate initial-setup scenarios require it.

---

### 18. Expanded RLS Test Matrix

Added to Phase 5D-1 and Phase 5E test plans.

| Test | Operation | Expected result |
|------|-----------|----------------|
| REG-RLS-UNAUTH-1 | Unauthenticated INSERT into `accounts` | Rejected |
| REG-RLS-UNAUTH-2 | Unauthenticated INSERT into `categories` | Rejected |
| REG-RLS-UNAUTH-3 | Unauthenticated INSERT into `transactions` | Rejected |
| REG-RLS-UNAUTH-4 | Unauthenticated INSERT into `transaction_splits` | Rejected |
| REG-RLS-HA-1 | `household_admin` UPDATE `categories.behavior_class` | Rejected |
| REG-RLS-HA-2 | `household_admin` UPDATE `categories.budget_treatment` | Rejected |
| REG-RLS-HA-3 | `household_admin` UPDATE `categories.cashflow_treatment` | Rejected |
| REG-RLS-HA-4 | `household_admin` UPDATE `transactions.is_reconciled` directly | Rejected |
| REG-RLS-HA-5 | `household_admin` INSERT transaction in reconciled period | Rejected by RPC |
| REG-RLS-HA-6 | `household_admin` DELETE `payee_rule` | Rejected |
| REG-RLS-OWNER-1 | `owner` INSERT transaction in reconciled period with required reason | Allowed |
| REG-RLS-OWNER-2A | Phase 5E: `owner` change `starting_balance` after transactions exist | Rejected — blocked until audit log exists |
| REG-RLS-OWNER-2B | Phase 5F+: `owner` change `starting_balance` after transactions exist with required reason + audit log | Allowed |
| REG-RLS-RPC-1 | RPC call with null `auth.uid()` | Rejected immediately |
| REG-RLS-RPC-2 | RPC call by `household_admin` backdating into reconciled period | Rejected |
| REG-RLS-RPC-3 | RPC call with `SUM(splits.amount) ≠ total_amount` | Rejected |
| REG-RLS-RPC-4 | RPC call assigning parent category (`is_leaf = false`) to split | Rejected |

---

_End of Architecture Freeze Addendum_

---

_End of Phase 5C Architecture Design v3.5_
_Architecture frozen June 26, 2026. Consistency pass complete. Phase 5D-1 build may begin._
