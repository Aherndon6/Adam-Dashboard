# TX-1 (future candidate) — Transaction Category Integrity + Income Taxonomy + Budget Attribution

**Status:** Future phase candidate. Capture only — not scheduled, not scoped for build, not started. **Explicitly not UX-0.5.**
**Captured:** 2026-07-07 (from live-use questions during UX-0 / post-5G-1A). Authoritative definition per Adam 2026-07-07.
**Nature:** Register (`public.transactions`) classification, income taxonomy, reimbursement/offset handling, uncategorized review, and budget-period attribution. Display/workflow + light data-model (new categories, save validation). **Not** Weekly Model cash math.

> Naming note: "TX-1" here is a **future Transactions workstream**, unrelated to the `TX-1…TX-10` Playwright e2e test IDs in `e2e.js` (Section TX). Different namespace.

## Context

We found multiple Register transactions where Category is blank, or where the category is technically present but the business meaning depends on **memo / funding-source context** the system does not formally understand. This is broader than a simple "make Category required" rule. TX-1 addresses transaction classification, income taxonomy, reimbursements/offsets, uncategorized review, and budget-period attribution / carryover treatment.

## Motivating examples

### Example 1 — BKCPA Extra Pay / blank category

- 2026-07-03, BKCPA inflow **$1,089.08**, memo "Extra amount."
- Already accounted for in the **Weekly Model** in Week 26 as "Wendy Extra BK Pay." The 40% tax reserve transfer is already modeled as **$435.63** to Vio Bank - Tax Reserve.
- **Must not** create a duplicate inflow, duplicate tax rule, or duplicate goal allocation. (Register and the Weekly Model are separate systems; Register categories are display/reporting only and do not feed `runModel`, tax rules, or goal allocations.)
- Current taxonomy has **no source-accurate BKCPA Extra Pay category**. The only income leaves are `income.net_salary`, `income.net_salary_spouse`, `income.deep_south_commissions` (`docs/phase-5d-1-migration.sql:280-282`).
- Behavior-correct existing category is **Deep South Commissions / `income.deep_south_commissions`** (behavior_class `commission_income`, matching the 40/60 commission/BK-bonus treatment — see `index.html:2838, 5223, 5300`), but the **label is source-wrong** for a BK CPA payment.
- **Decision (2026-07-07):** leaving this row's category **blank for now** rather than assigning Deep South Commissions.
- **Future desired category:** `BKCPA Extra Pay` (or `Wendy BKCPA Extra Pay`) / `income.bkcpa_extra_pay` / behavior_class `commission_income` / budget_treatment `display_only`.
- This monthly BKCPA extra pay recurs regularly and is accounted for in the Weekly Model.

### Example 2 — Bailey car repair reimbursement / blank category

- AMEX Gold: Bailey car repair reimbursement / shared repair repayment.
- Adam paid for Bailey's car repair; Bailey owed half. The repayment is a reimbursement/offset, **not** ordinary income or ordinary spending.
- Should **not** remain blank long-term. Likely needs a **reimbursement / offset category** distinct from income and from expense.

### Example 3 — Mr Tire / prior-month budget coverage

Two rows, both correctly dated 2026-07-04, both correctly categorized **Extra**:

- 2026-07-04, Mr Tire **$277.00**, memo "Covered by June," category **Extra**
- 2026-07-04, Mr Tire **$664.35**, memo "Rest of Yukon work," category **Extra**

**Business meaning:** leftover **June** Misc/Extra budget covered **$277.00** of the repair; the remaining **$664.35** was applied against **July** Misc/Extra.

**Implication:** the category is technically present, but the memo carries **budget-period / funding-source logic** the system does not formally understand. A category-required rule does nothing here. TX-1 should consider budget attribution / carryover for transactions funded by prior-month leftover money or split across budget periods.

## Desired TX-1 scope (future — do not implement now)

1. **Add a proper BKCPA Extra Pay income category:** label `BKCPA Extra Pay` (or `Wendy BKCPA Extra Pay`); category_key `income.bkcpa_extra_pay`; behavior_class `commission_income`; budget_treatment `display_only`.
2. **Decide/create reimbursement/offset categories** for family reimbursements and shared-expense repayments (Example 2).
3. **Make Category required** for new manual transactions and edits where appropriate.
4. **Add save validation** so manual saves cannot leave Category blank unless there is an explicit allowed exception.
5. **Add/improve an Uncategorized review/filter** path for existing blank-category rows (overlaps REG-4, currently charted to 5H).
6. **Produce a cleanup list** for existing blank-category transactions.
7. **Consider budget-period attribution / carryover** treatment for cases like "covered by June" vs current-month Extra (Example 3). Coordinate with the existing 5F-3 "month-boundary / carryover charge treatment" backlog item.
8. **Avoid changing Weekly Model cash-flow math** unless explicitly required.
9. **Avoid duplicate tax rules or duplicate goal allocations.**
10. **Keep out of UX-0.5** unless there is a tiny display-only reminder/count that fits naturally later.

## Guardrails

- Register stays the source of truth for actuals; Budget stays plan / spent / remaining / reporting. Do not change `runModel` / WD / effectiveWD / waterfall / commission_tax as part of TX-1 unless a specific item explicitly requires it and it is separately approved (AGENTS.md "Do Not Touch").
- New income/offset categories are owner-only category creation, scoped and executed at build time (schema/RLS/RPC/SQL only when the phase formally starts). This capture changes no code or data.
- Do not solve budget-period cases by editing `starting_balance` (per the 5F-3 backlog note).
- Keep the future `income.bkcpa_extra_pay` distinct from `income.net_salary_spouse` (regular modeled spouse paycheck).

## Cross-references

- 5F-3 carryover backlog item: `docs/strategic-roadmap-future-horizons.md` ("Design backlog item — month-boundary / carryover charge treatment"). TX-1's Example 3 is related but distinct: 5F-3 is `posted_date` vs budget-month; TX-1 is which period's *funding* a correctly-dated, correctly-categorized charge draws from.
- REG-4 uncategorized surfacing (5H): `docs/reviews/ui-flow-review-triage-2026-07-07.md`.
- Income taxonomy seed: `docs/phase-5d-1-migration.sql:280-282`.
- BK-bonus / commission handling in the model: `index.html:2838, 5223, 5300`.

## Post-activation follow-up — TX-1.1: "Wendy Extra BK Pay" register-category alignment (2026-07-17)

**Status:** Post-activation backlog item; sub-item of TX-1, scheduled within roadmap **P3b-1 Data Integrity** (the post-5G-1D data-integrity lane). **Docs/backlog capture only — no code, SQL, category, budget-rule, transaction, or production-data change is made here.** Authoritative per Adam 2026-07-17.

**Decision — exact register category label.** The transaction-register income category MUST be named **exactly** `Wendy Extra BK Pay`, matching the weekly-model label verbatim to prevent terminology drift. This **refines/supersedes** the earlier tentative labels in "Desired TX-1 scope" item 1 / Example 1 (`BKCPA Extra Pay` / `Wendy BKCPA Extra Pay`). The `category_key` / `behavior_class` / `budget_treatment` (`income.bkcpa_extra_pay` / `commission_income` / `display_only`) are unchanged — only the display label is now pinned exact.

**Intent (Adam 2026-07-17).**
- Irregular supplemental income from **Barfield and Kinkeade (BK)**.
- Sits **outside** the recurring monthly budget. *(Refines Example 1's earlier "recurs regularly" framing for categorization purposes: treat as supplemental, not a recurring monthly baseline line.)*
- Must **not** be categorized as `Net Salary Spouse` (`income.net_salary_spouse`).
- Must **not** increase or distort budgeted salary actuals.
- Should remain available for goal funding and/or budget-month overages **through the weekly model**.
- Register category label matches the weekly-model label exactly (drift guard).

**Acceptance criteria.**
1. Create or confirm a register income category named exactly `Wendy Extra BK Pay`.
2. Confirm the category is **not** mapped to the recurring monthly budget baseline (`budget_treatment='display_only'`; excluded from salary budget-vs-actual rollups).
3. Confirm transactions categorized `Wendy Extra BK Pay`:
   - appear in income / register reporting;
   - remain **distinct** from `Net Salary Spouse`;
   - remain **distinct** from `Deep South Commissions`;
   - do **not** alter recurring salary budget-vs-actual reporting;
   - do **not** independently trigger the tax rule from the register category (Register categories are display/reporting only; they never feed `runModel`, tax rules, or goal allocations — see Example 1).
4. Preserve the existing operating treatment: the taxable-income flag and 40/60 handling come from the **weekly-model Edit Week** workflow (the "Tax?" split → `commission_tax`; operator package §2d). The register category is for classification and reporting only.
5. After the category exists, update the **2026-07-17 Barfield and Kinkeade inflow of $1,752.26** from **No Category** → `Wendy Extra BK Pay`. *(This is a distinct instance from Example 1's 2026-07-03 $1,089.08 BK inflow.)*
6. **Activation-sitting exclusion:** do **not** perform the category creation or the transaction recategorization during the 5G-1D production activation sitting **unless** it is explicitly added to an approved post-activation section **after all activation gates, closeout, revokes, proofs, and validation are complete**.
7. Recorded in the roadmap P3b-1 phase + the decision log so it cannot be lost.

**Dependency on existing category / budget architecture.**
- **Income taxonomy:** adds a **fourth** income leaf alongside `income.net_salary` / `income.net_salary_spouse` / `income.deep_south_commissions` (`docs/phase-5d-1-migration.sql:280-282`). Owner-only category creation executed at P3b-1 build time (schema/RLS/RPC/SQL only when that phase formally starts — this capture executes nothing).
- **Budget isolation:** relies on `budget_treatment='display_only'` to keep the category out of the recurring monthly budget baseline and salary actuals (same mechanism already used for `income.deep_south_commissions`).
- **Tax path:** the weekly-model Edit Week "Tax?" 40/60 → `commission_tax` (operator package §2d) is the sole tax trigger; the Register category never re-triggers it (no duplicate inflow / tax rule / goal allocation).
- **Do Not Touch:** no `runModel` / WD / effectiveWD / waterfall / `commission_tax` change (AGENTS.md).

## Post-activation follow-up — TX-1.2: Structured custom-transfer task metadata (2026-07-19)

**Status:** Post-activation backlog item; sub-item of TX-1 (operational-controls lane), scheduled within roadmap **P3b-1 Data Integrity** (the post-5G-1D data-integrity / operational-controls lane). **Docs/backlog capture only — no code, schema, UI, migration, or test change is made here.** **DEFERRED; NOT required for the current `BKX-20260717` remediation**, which is represented by the now-created Week-29 free-text interim custom task (present once; **incomplete**; bank transfer **unexecuted**) defined under `docs/phase-5g-1d-bkx-income-adjustment-2026-07-19.md` §8. Authoritative per Adam 2026-07-19.

**Problem (what the BKX remediation exposed).** `custom_tasks` supports only a free-text `label` (columns today: `id, week_num, label, completed, created_at`). Operational transfer tasks must therefore encode the **amount, source account, destination account, purpose, and incident/source identity** inside the label string — e.g. the BKX interim task label:
`Transfer $700.90 from Truist Checking to Vio Bank – Tax Reserve (Wendy Extra BK Pay commission tax; income posted 7/17/2026; BKX-20260717)`.
This is brittle: no machine-checkable amount or account references, no stable identity for duplicate prevention, and audit/reporting must parse free text. `BKX-20260717` made the limitation concrete.

**Future capability (design only — do not implement now).**
- **Optional structured `amount`** (numeric), separate from the label.
- **Optional `source_account`** reference (key into `accounts`).
- **Optional `destination_account`** reference (key into `accounts`).
- **Optional stable `source_id` / incident identity** (e.g. `BKX-20260717`) for dedup and cross-referencing.
- **Preserve the existing free-text `label`** (human-readable; semantics unchanged).
- **Owner-only creation rules** preserved (same `canWriteFinancials` / owner gate as today; Wendy no-touch where an item requires it).
- **Duplicate prevention or warning** keyed on the stable `source_id` — a built-in pre-create scan / uniqueness check (the manual triple-table scan in the BKX incident §8 becomes native behavior).
- **Backward compatibility** with existing custom tasks — all new fields optional/nullable; legacy free-text rows render and behave unchanged.
- **Completion evidence + audit behavior** for transfer tasks defined: completion records the executed amount and a settlement/confirmation reference, with who/when/amount/`source_id` captured (mind the existing "no `updated_at` on write tables" platform gap, `index.html:10485`).

**Hard invariants (binding on any future implementation).**
1. Structured metadata **must NOT** convert a custom task into a **modeled cash event** — it never feeds `runModel` / WD / effectiveWD / a taxable-gross, and never adds cash to any week (a custom transfer moves *existing* checking; e.g. the BKX cash is already inside the reconciled Week-28 balance).
2. Structured metadata **must NOT** convert a custom task into a **commission-tax pool obligation** — `custom_tasks` stays off-pool (`computeCommissionTaxPool` never reads `customTaskData`, `index.html:3326`); a structured `amount`/`source_id` creates no durable-origin origin and no `weekly_tasks` `commission_tax` leg.
3. **Backward/interop safety** — a future migration must not retroactively reinterpret an existing free-text custom task (including the BKX interim task) as a structured obligation.

**Cross-references.**
- **BKX incident / interim design:** `docs/phase-5g-1d-bkx-income-adjustment-2026-07-19.md` (source identity **`BKX-20260717`**; §8 interim controls; §10 long-term `source_id` mechanism). TX-1.2 is the **custom-task-metadata** half (enriches operator tasks); the incident §10 `source_id` historical-taxable-income mechanism is the **commission-tax-ledger** half (integrates an off-model obligation into the durable pool) — related but distinct workstreams.
- **Do not** modify the already-created Week-29 `BKX-20260717` interim task as part of this backlog item.
- **Do Not Touch:** no `runModel` / WD / effectiveWD / waterfall / `commission_tax` change (AGENTS.md).
