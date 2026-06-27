# Herndon Financial OS — Pre-Build Discovery Checklist
_Phase 5C v3.5 | Sections 1, 2, 8 COMPLETE | Architecture Frozen — June 26, 2026_
_For: Adam + Wendy_

---

## Priority Guide

| Section | Required before | Blocker? |
|---------|----------------|---------|
| 1 — Accounts (names, types, scope) | Phase 5D-1 | YES |
| 2 — Categories (full list, hierarchy, cleanup) | Phase 5D-1 | YES |
| 8 — Adam-only architecture decisions | Phase 5D-1 | YES |
| 3 — Transaction entry workflow | Phase 5E | Useful now |
| 4 — Reconciliation workflow | Phase 5F | Useful now |
| 5 — Goal-linked spending | Phase 5H | Useful now |
| 6 — Starting balances | July 1, 2026 | Capture at go-live — NOT now |
| 7 — Import expectations | Phase 5J | Not needed yet |

**Sections 1, 2, and 8 are confirmed complete as of June 26, 2026. Phase 5D-1 build may proceed.**

---

## Section 1 — Accounts
_COMPLETE — June 26, 2026_

### 1.1 — Confirmed Account List

| OS label | Quicken name | Type | Institution | OS scope | Notes |
|----------|-------------|------|-------------|---------|-------|
| Truist Checking | SunTrust Checking | checking | Truist | Full entry | |
| Truist Savings | Suntrust Savings 2 | savings | Truist | Full entry | |
| Blue AMEX | AMEX2 | credit_card | American Express | Full entry | Blue Cash Everyday; low volume; kept open for credit score |
| BOA Visa | BOA VISA | credit_card | Bank of America | Full entry | Low volume; kept open for credit score |
| Chase Disney Visa | Chase Disney Visa | credit_card | Chase | Full entry | |
| Gold AMEX | Gold AMEX | credit_card | American Express | Full entry | |
| Platinum AMEX | Platinum AMEX | credit_card | American Express | Full entry | |
| Truist Mastercard | Suntrust Mastercard | credit_card | Truist | Full entry | Low volume; kept open for credit score |
| AMEX Savings | AMEX Savings | savings | American Express | Full entry | IRA/529 holding account |
| Vio Bank Emergency Savings | — (*3588) | savings | Vio Bank | Full entry | $25,072 as of 6/26/26 |
| Vio Bank Tax Reserve Savings | — (*2449) | savings | Vio Bank | Full entry | $897 as of 6/26/26 |
| Lending Club (EF) | — | savings | Lending Club | Full entry | Already in Weekly Model; $13,489; monthly $250 inflow from Vio Tax Reserve |
| Fidelity Joint WROS-TOD | — | investment | Fidelity | View-only | FZFXX money market ~$92,771; no transaction entry; balance updated manually |
| Bailey's Capital One Checking | — | checking | Capital One | Excluded | Adam assists but not household account |
| Bailey's Capital One Savings | — | savings | Capital One | Excluded | Same |
| Bailey's UTMA (Fidelity) | — | investment | Fidelity | Excluded | $37.65; not active |
| Investing / Property & Debt / Empower | Various | various | Various | Excluded | Not active in Quicken; out of scope for now |

### 1.2 — Clarification items

- [x] All items resolved. See confirmed account list above.

### 1.3 — Starting balances (DO NOT FILL IN NOW)

Starting balances will be captured on or immediately before July 1, 2026. Leave this section blank. Filling it in now will produce stale numbers.

_Planned go-live balance capture date: _____________ (must be on or before 7/1/26)_

When the time comes, for each in-scope account capture:
- Balance (wallet-perspective: checking/savings = positive; credit card balance owed = negative)
- As-of date
- Source (Quicken / online account / statement / manual)
- Optional note

---

## Section 2 — Categories
_COMPLETE (core classification) — June 26, 2026_
_Full Quicken export not required: confirmed the existing OS category list plus yellow-highlighted additions covers Wendy's usage._

### 2.1 — Category source

Confirmed: the existing BUDGET_CATEGORY_REGISTRY (31 categories) plus the yellow-highlighted additions from the discovery workbook covers Wendy's current usage. No additional Quicken export needed before Phase 5D-1.

### 2.2 — Category hierarchy

- [x] Entertainment is a parent group (`is_leaf = false`). Wendy uses named subcategories: Birthday Dinner, Brunch, Big Dinner Out, Entertainment Other (catch-all). Transactions always go to a subcategory.
- [x] Other categories are mostly flat (no additional parent groups discovered beyond what is already in the OS).

### 2.3 — Confirmed category decisions

**Jabian:**
- [x] "jabian 2026" (lowercase) = same as Jabian Expenses 2026. Archive and merge.
- [x] Jabian Deposits 2026 is the paired reimbursement deposit category.

**Taxes:**
- [x] "Taxes 2026" = transfers to Vio Bank Tax Reserve only. behavior_class = transfer, budget_treatment = excluded, cashflow_treatment = tax_reserve. IRS payments from checking use a separate transaction.

**Flexible Spending:**
- [x] "Flexible Spending 2026" = FSA reimbursable. Both FSA expenses AND FSA reimbursement deposits use this same category. No separate paired deposit category. budget_treatment = excluded (net near-zero).

**Greenlight:**
- [x] Confirmed transfer to kids' Greenlight debit cards. behavior_class = transfer, budget_treatment = excluded.

**Entertainment subcategories:**
- [x] Birthday Dinner — active leaf (not archived); subcategory of Entertainment
- [x] Brunch — active leaf; subcategory of Entertainment
- [x] Big Dinner Out — active leaf; subcategory of Entertainment
- [x] Entertainment Other — catch-all leaf; subcategory of Entertainment

**Other:**
- [x] "Extra" — catch-all for miscellaneous one-off expenses. behavior_class = expense, budget_treatment = tracked.

### 2.4 — Category cleanup

- [x] jabian 2026 (lowercase) → Archive, merge into Jabian Expenses 2026
- [x] Birthday Dinner → Keep (active); moved to subcategory of Entertainment parent

### 2.5 — Category classification mapping
_Required before Phase 5D-1 seed SQL is written. The full category list alone is not enough — each category must be explicitly classified._

Claude cannot reliably infer `behavior_class`, `budget_treatment`, or goal linkage from a category name. Before the seed is written, every category needs the following confirmed. Work through this as a table — one row per category.

**Minimum required before Phase 5D-1 seed:** Action + behavior_class + budget_treatment. Other columns can be filled in a second pass.

**Columns to complete:**

| Column | Options |
|--------|---------|
| **Category label** | Exact name as it appears in Quicken |
| **Action** | `Keep (active)` \| `Archive` \| `Merge into [category name]` \| `New — add to OS` |
| **Parent group** | The display group (e.g., "Food & Dining", "Trips", "Business") |
| **behavior_class** | `expense` \| `income` \| `reimbursable_expense` \| `reimbursable_income` \| `goal_linked` \| `savings_allocation` \| `transfer` \| `commission_income` |
| **budget_treatment** | `tracked` \| `planned_allocation` \| `display_only` \| `excluded` |
| **cashflow_treatment** | `operating` \| `goal_funding` \| `goal_spending` \| `tax_reserve` \| `reimbursable` \| `excluded` |
| **budget_line_key** | Which `budget_line_rules` key this category rolls into (required if `tracked`) |
| **budget_group_key** | Display group in the budget printout (required if `tracked` or `display_only`) |
| **linked_goal** | Goal name it links to, if `goal_linked` (actual goal IDs confirmed later) |
| **Reimbursement pairing** | For `reimbursable_expense`: name the paired deposit category (and vice versa) |

**Confirmed category classification table:**

| Category label | Action | Parent group | behavior_class | budget_treatment | cashflow_treatment | Notes |
|---------------|--------|-------------|---------------|-----------------|-------------------|-------|
| Groceries | Keep | Food & Dining | expense | tracked | operating | |
| 2026 Seattle/Alaska | Keep | Trips | goal_linked | excluded | goal_spending | Trip spending from reserve; Goals section only; does not compress monthly allocation |
| 2026 RCCL Girls Trip | Keep | Trips | goal_linked | excluded | goal_spending | Same |
| 2026 DCL Trip | Keep | Trips | goal_linked | excluded | goal_spending | Same |
| 2026 RCCL Christmas Cruise | Keep | Trips | goal_linked | excluded | goal_spending | Same |
| Jabian Expenses 2026 | Keep | Business | reimbursable_expense | excluded | reimbursable | pairs with Jabian Deposits 2026 |
| Jabian Deposits 2026 | Keep | Business | reimbursable_income | display_only | reimbursable | pairs with Jabian Expenses 2026 |
| Deep South Commissions | Keep | Income | commission_income | display_only | operating | |
| Flexible Spending 2026 | Keep | Health | reimbursable_expense | excluded | reimbursable | Both FSA expenses and FSA deposits use this category. No separate paired category. Net ~zero. |
| Taxes 2026 | Keep | — | transfer | excluded | tax_reserve | Vio Bank Tax Reserve transfers only. Not for IRS payments. |
| taxes.actual_tax_payment | New | Taxes | expense | excluded | tax_reserve | Actual IRS/state tax payments from checking. Large, irregular; excluded from monthly budget. Label: "Tax Payment." |
| Greenlight | Keep | — | transfer | excluded | excluded | Kids' Greenlight card funding. One-sided (Greenlight not an OS account). |
| Entertainment | Keep (parent only) | Entertainment | — | — | — | is_leaf = false. Never used directly for transactions. |
| Birthday Dinner | Keep | Entertainment | expense | tracked | operating | Subcategory of Entertainment. Active. |
| Brunch | Keep | Entertainment | expense | tracked | operating | Subcategory of Entertainment. |
| Big Dinner Out | Keep | Entertainment | expense | tracked | operating | Subcategory of Entertainment. |
| Entertainment Other | Keep | Entertainment | expense | tracked | operating | Subcategory of Entertainment. Catch-all. |
| Extra | Keep | Misc | expense | tracked | operating | Catch-all for one-off miscellaneous expenses. |
| jabian 2026 (lowercase) | Archive + merge | Business | — | — | — | Confirmed duplicate of Jabian Expenses 2026. |

---

## Section 3 — Transaction Entry Workflow
_Useful to complete now; required before Phase 5E build._

- [ ] When does Wendy typically enter transactions?
  - (A) Same day or next day as the purchase
  - (B) Weekly batch (sits down once a week and catches up)
  - (C) When she reconciles — entry and reconciliation happen together
  - (D) Mix of the above
- [ ] When entering, does she work account by account (all Gold AMEX, then all Disney Visa) or chronologically across all cards?
- [ ] How often does a single purchase span more than one category (split transaction)?
  - Examples: Costco split between Groceries and a trip category; Amazon order split between household and a work expense
  - Rough frequency: daily / a few times a week / monthly / rarely
- [ ] Does she enter transactions on Mac desktop, iPhone, or both?
- [ ] When she enters a transaction, does she usually know the exact amount, or does she sometimes enter an estimate and fix it later?

---

## Section 4 — Reconciliation Workflow
_Useful to complete now; required before Phase 5F build._

- [ ] How often does Wendy reconcile?
  - (A) Monthly when each card statement closes
  - (B) Weekly
  - (C) No set schedule — when she gets to it
- [ ] Does she reconcile one full account at a time before moving to the next?
- [ ] Does she reconcile against:
  - (A) The online account or app balance
  - (B) A paper or PDF statement
  - (C) A combination
- [ ] Does she care about seeing reconciliation history (a log of past sessions per account)?
- [ ] Has she ever used Quicken's "Add Adjustment" feature when she couldn't get the balance to zero? How often?

---

## Section 5 — Goal-Linked Spending
_Useful to complete now; required before Phase 5H build._

- [ ] When Wendy logs a trip expense (e.g., $80 at a restaurant during Alaska trip), how does she think about it?
  - (A) It reduces what she still has available to spend on the trip (saved minus spent)
  - (B) It's separate — spending is spending, savings is savings
  - (C) It should reduce what's in the "trip fund"
- [ ] For a trip goal, what is the most useful number to see?
  - (A) How much we've saved vs. the target
  - (B) How much we've already spent
  - (C) How much is left to spend (saved minus spent) — the "available reserve"
  - (D) All of the above
- [ ] Does Wendy split trip spending across multiple cards (e.g., flights on AMEX Platinum, hotels on Gold AMEX) under the same category?

---

## Section 6 — Starting Balances
_Capture at go-live (7/1/26). Do NOT fill in now._

When ready (on or immediately before July 1, 2026), gather for each in-scope account:

| Account | Balance | As-of Date | Source | Note |
|---------|---------|------------|--------|------|
| SunTrust Checking | | | | |
| Gold AMEX | | | | |
| _(etc.)_ | | | | |

**Sign reminder:** Credit card balance owed = negative (e.g., Gold AMEX with $5,438.39 owed → enter -5438.39). Checking/savings = positive.

**Source options:** Quicken balance | Online account app | Statement | Manual

---

## Section 7 — Import Expectations
_Not needed until Phase 5J. Gather when Phase 5J is on deck._

- [ ] Does Wendy export CSV files from any bank or card website?
- [ ] Which institutions offer export: SunTrust, AMEX, Chase?
- [ ] Would imports be used by Wendy, Adam, or both?
- [ ] Is the goal to replace manual entry with imports, or use imports as a spot-check / supplement?

---

## Section 8 — Adam-Only Architecture Decisions
_COMPLETE — June 26, 2026_

- [x] **Planned goal funding:** Variable — computed dynamically as `monthly_budget_target - sum(all tracked lines for that month)`. NOT stored as a fixed $2,300 in budget_line_rules. Current baseline ~$2,300; compresses automatically when tracked lines are added (e.g., Diablos July).

- [x] **Pre-migration budget months:** Option A — show migrated `budget_transactions` data as historical actuals. Provides continuity in the budget view.

- [x] **Goal card primary metric:** Confirmed — Available Reserve (Saved minus Spent) is the primary display metric. Funding Remaining is secondary.

- [x] **Investment/property accounts:** Excluded from OS scope for now.

- [x] **Starting balance capture process:** Confirmed — captured at go-live (7/1/26). Not gathered during discovery.

- [x] **Feature flags:** Confirmed — staged rollout approach approved.

- [x] **Wendy's role:** Confirmed — `household_admin`. Full financial entry; cannot unlock reconciled transactions, cannot change category behavior fields, cannot manage payee/import rules.

---

## Completion Tracker

| Section | Owner | Status | Required before |
|---------|-------|--------|----------------|
| 1 — Accounts (names/types/scope) | Adam + Wendy | ✅ Complete 6/26 | **Phase 5D-1** |
| 2 — Categories (full list) | Adam + Wendy | ✅ Complete 6/26 | **Phase 5D-1** |
| 8 — Adam-only decisions | Adam | ✅ Complete 6/26 | **Phase 5D-1** |
| 3 — Transaction entry workflow | Adam + Wendy | ☐ | Phase 5E |
| 4 — Reconciliation workflow | Adam + Wendy | ☐ | Phase 5F |
| 5 — Goal-linked spending | Adam + Wendy | ☐ | Phase 5H |
| 6 — Starting balances | Adam + Wendy | Capture at 7/1/26 | 7/1/26 |
| 7 — Import expectations | Adam | ☐ | Phase 5J |

---

_Sections 1, 2, and 8 complete as of June 26, 2026. Phase 5D-1 build planning may begin._
