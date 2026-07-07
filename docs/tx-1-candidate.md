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
