# Phase 5E-7 Smoke Checklist — Role Enforcement / Security Maturity Gate

Run this checklist after applying all 5E-7 code changes and before marking 5E-7 complete.
Requires two browser sessions: one as Adam (owner) and one as Wendy (household_admin).
If Wendy account is not yet active, use a viewer test account or verify role assignment in app_users.

---

## SQL Audit Pass (run first, in Supabase SQL Editor)

- [ ] **SA-1** Run `docs/phase-5e-7-preflight.sql` — all P1 through P8 checks reviewed.
  - P1: 3 helper functions exist (is_allowed_user, can_write_financials, is_owner)
  - P2: adam=owner, wherndon22=household_admin
  - P3: RLS enabled on all app tables
  - P4: Full policy listing reviewed — no surprises
  - P5: No write policies use is_allowed_user() — zero FAIL rows
  - P6: All write policies classified as can_write_financials() or is_owner()
  - P7: Note any tables missing DELETE policies (expected: weekly_reconciliations, weekly_tasks, weekly_notes may be missing DELETE)
  - **P8 STOP CONDITION**: budget_line_rules write policies
    - If FAIL (is_owner): do not proceed to 5E-8 without SQL migration. Report: table=budget_line_rules, current=is_owner(), expected=can_write_financials(), impact=Wendy cannot manage budget lines.
    - If PASS (can_write_financials): continue.

- [ ] **SA-2** Run `docs/phase-5e-7-validation.sql` — all V1–V15 checks reviewed.
  - V1/V1a: transactions write policies use can_write_financials() + source='manual'
  - V2: budget_transactions write policies use can_write_financials()
  - V3: accounts write policies are is_owner() only
  - V4: categories write policies are is_owner() only
  - V5a/V5b: goals row-qualified split confirmed
  - V6–V11: weekly/overrides/wishlist/custom use can_write_financials()
  - V12: budget_line_rules — PASS=can_write_financials, FAIL=stop (see P8)
  - V13: SELECT policies use is_allowed_user()
  - V14: budget_rules and goal_registry have no write policies

---

## App-Side Guard Smoke (browser test)

### As Adam (owner)

- [ ] **AC-1** Weekly view: "Edit week" button visible. Click — drawer opens. Add an event, save — no errors.
- [ ] **AC-2** Weekly view: "Reconcile" button visible. Click — recon form opens. Enter values, save — actuals saved.
- [ ] **AC-3** Weekly view: Task checkbox — clickable. Toggle a task — completes/uncompletes.
- [ ] **AC-4** Weekly view: Notes textarea — editable. Type and blur — "Saving..." appears then clears.
- [ ] **AC-5** Current Register: "+ Add Transaction" button visible. Click — form opens. Save a manual transaction.
- [ ] **AC-6** Current Register: manual transaction row shows Edit (✎) and Delete (✕) buttons. Click Edit — form opens with existing values.
- [ ] **AC-7** Current Register: Cleared checkbox is interactive (not disabled). Toggle — updates.
- [ ] **AC-8** Budget tab: "Add Transaction" button visible. Add a budget transaction.
- [ ] **AC-9** Budget tab: Cleared checkbox on budget transactions is interactive. Edit and Delete buttons visible for manual rows.
- [ ] **AC-10** Budget Line Admin: "Manage Lines" button visible (canWriteFinancials gate). Add, Edit, Archive all work.
- [ ] **AC-11** Goals tab: Goal target scenario — Commit button visible. Commit saves.
- [ ] **AC-12** Ask Claude tab: API key input visible (isOwnerUser). Save key — saves to Supabase.
- [ ] **AC-13** Wishlist/Roadmap: Add, Edit, Move, Delete, Done controls visible. Test each.
- [ ] **AC-14** Custom tasks: Add, flip type, delete, dismiss auto-reminder — all work.
- [ ] **AC-15** Scenario section: Commit button visible when scenario is active.

### As Wendy (household_admin)

- [ ] **WC-1** Weekly view: "Edit week" button visible (canWriteFinancials = true for household_admin).
- [ ] **WC-2** Weekly view: "Reconcile" button visible. Recon form opens and saves.
- [ ] **WC-3** Weekly view: Task checkboxes clickable. Notes textarea editable.
- [ ] **WC-4** Current Register: "+ Add Transaction" button visible. Form opens. Save works.
- [ ] **WC-5** Current Register: Edit/Delete visible for manual rows. Cleared checkbox interactive.
- [ ] **WC-6** Budget tab: "Add Transaction" button visible. Edit/Delete/Cleared functional.
- [ ] **WC-7** Budget Line Admin: "Manage Lines" button visible (canWriteFinancials). Add/Edit/Archive work.
  - **If Manage Lines is NOT visible or throws "Permission denied" → P8 STOP CONDITION triggered. SQL migration required.**
- [ ] **WC-8** Wishlist: Add/Edit/Move/Delete/Done controls visible and functional.
- [ ] **WC-9** Scenario Commit button visible. Commit saves successfully.
- [ ] **WC-10** Goals: normal goal updates save (ak_goal, rt_goal).
- [ ] **WC-11** Ask Claude tab: API key input NOT visible (isOwnerUser = false for household_admin). Only "Ask the account owner" message shown.

### As viewer (future role / test with viewer account if available)

- [ ] **VC-1** Weekly view: "Edit week" button NOT visible. "Reconcile" button NOT visible.
- [ ] **VC-2** Weekly view: Task checkboxes disabled or non-functional (no local state change).
- [ ] **VC-3** Weekly view: Notes textarea readonly or non-functional.
- [ ] **VC-4** Current Register: "+ Add Transaction" button NOT visible.
- [ ] **VC-5** Current Register: Edit/Delete buttons NOT visible on any row. Cleared checkbox disabled.
- [ ] **VC-6** Budget tab: "Add Transaction" button NOT visible. Cleared/Edit/Delete controls absent or disabled.
- [ ] **VC-7** Budget Line Admin: "Manage Lines" button NOT visible.
- [ ] **VC-8** Wishlist: Add/Edit/Delete/Move/Done controls NOT visible. Cards render read-only.
- [ ] **VC-9** Scenario Commit button NOT visible.
- [ ] **VC-10** Ask Claude: API key input NOT visible.
- [ ] **VC-11** Confirm RLS blocks any direct API call: attempt a POST to /rest/v1/transactions as viewer session — expect 401/403.

---

## Missing DELETE Policy Report

The following tables may lack DELETE policies based on migration doc review.
Verify in SQL audit (P7) and record actual live state here before proceeding to 5E-8.

| Table | DELETE Policy Expected | Live Status (fill in after P7) | Notes |
|---|---|---|---|
| weekly_reconciliations | can_write_financials() | ____________ | App calls DELETE on week_num |
| weekly_tasks | can_write_financials() | ____________ | Not called directly by app — tasks upsert only |
| weekly_notes | can_write_financials() | ____________ | Not called directly by app — notes upsert only |
| model_week_overrides | can_write_financials() | ____________ | deleteWeekOverride() calls DELETE |
| wishlist_items | can_write_financials() | ____________ | deleteWishlistItem() calls DELETE |
| custom_tasks | can_write_financials() | ____________ | deleteCustomTask() calls DELETE |
| budget_transactions | can_write_financials() | ____________ | _budgetDeleteTransaction() calls DELETE |
| transactions | can_write_financials() | ____________ | _confirmTxDelete() calls DELETE |

**If weekly_reconciliations lacks DELETE policy:** `deleteRecon()` silently fails at DB level for all users.
This is a pre-existing gap, not introduced by 5E-7. Do not add DELETE policies without separate approval.

---

## 5E-7 Gate (required before marking complete)

- [ ] All SA checks reviewed; no unexpected FAILs
- [ ] P8 STOP CONDITION resolved (budget_line_rules matches product decision)
- [ ] All Adam AC checks pass
- [ ] All Wendy WC checks pass (or P8 blocker documented with migration plan)
- [ ] Regression suite: node test_regression.js — 0 failures, count >= 837 + 5E-7 new tests
- [ ] No console errors in browser during smoke

**Sign off:** _________________ Date: _________________
