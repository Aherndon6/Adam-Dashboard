# Adam-Dashboard Project Instructions

## Project

Herndon Financial OS running at dashboard.herndons.us.

Primary purpose:
- Weekly cash flow management
- Savings goal tracking
- Household financial decisions
- Budget reconciliation

## Context Routing

Before Financial OS product/code work, read:

- `/Users/aherndon/AI-Context/00-README.md`
- `/Users/aherndon/AI-Context/02-working-style.md`
- `/Users/aherndon/AI-Context/05-financial-os-context.md`
- `/Users/aherndon/AI-Context/08-open-items.md`
- this repo's `AGENTS.md`
- this repo's `CODEX_STATUS.md`

Do not copy AI Context files into this repo.

## Architecture

Single-file app:
- `/Users/aherndon/Adam-Dashboard/index.html`
- all HTML, CSS, and JS in one file
- no framework
- no build step

Backend:
- Supabase project ID: `usayoldrawwmjsmretin`
- key tables include `weekly_reconciliations`, `weekly_tasks`, `model_week_overrides`, `goals`, `budget_transactions`, `budget_line_rules`, `wishlist_items`, `cash_commitments`
- `cash_commitments` (5F-1) is RLS SELECT-only for `authenticated`; all writes go through the SECURITY DEFINER `save_reconciliation_with_commitments` RPC, which the reconciliation form drives through three client-side paths: Phase 1 prior-commitment patches (`p_patched`), Phase 2 current-week WD protected inserts, and Phase 3 manual catch-all inserts (`commitment_source=manual_reconciliation`, `expected_item_id` = `manual_<uuid>`). Do not INSERT/UPDATE `cash_commitments` directly.

Hosting:
- GitHub Pages
- repo: `Aherndon6/Adam-Dashboard`
- auto-deploys on push to main

Push command from Adam's Terminal:
`bash push_to_github.sh "message"`

## Login / Role Model

App identities:
- `aherndon6@gmail.com` = Adam, owner
- `wherndon22@gmail.com` = Wendy, household_admin

Do not assume `adam@herndons.us` is the app login. It exists in auth.users for seed UUID purposes only, not app_users.

Access model:
- Adam owner: full financial + platform/admin access
- Wendy household_admin: full financial operating access, cannot write `anthropic_key` row
- unauthenticated: no access
- RLS enforced at DB level across all 11 tables

## Current State

Phase 5B complete.
Budget Module v1 live.
5F-1 complete through Phase 4. Forward reconciliation write path (Phase 0 basis, Phase 1 prior-commitment patches, Phase 2 current-week WD inserts, Phase 3 manual catch-all, Phase 4 balance entry) is live via the `save_reconciliation_with_commitments` RPC and proven in a real Week 26 closeout (2026-07-04): row saved correctly, three Tiffany Dye rents cleared/reflected at week 4, no Phase 3 duplicate for the $435.63 Vio transfer, production data verified clean.
Two 5F-1 sub-items remain deferred (NOT required for forward weekly closeout): dashboard Review Required verdict-text rendering (the `reviewRequired` flag is computed and tested; only the on-dashboard verdict string is unbuilt) and historical repair mode (`repair_commitments_for_week` wiring, past-week backfill only).
5F-1.5 Gate A (Wendy July usability) UI shipped and live (2026-07-05/06): A5 account-dropdown alphabetization, A8 weekly banner in header, A6 sortable Register columns, A9a Register search/type/status filters, A9b Register date filters, A7a read-only Category Report modal + picker, A7b Budget expense-row drill-through, plus the Register Quicken-style ledger hotfix (historical/as-of-transaction-date Balance, starting-balance row at bottom). Following Wendy's confirmation, the Register now defaults to the Quicken CL/reconciliation view — uncleared over cleared, newest-first within each group, Clr header activates it (commit 8d48b04) — superseding the earlier Clr-status-only default; Date/Payee/Category/Outflow/Inflow remain user-sortable. Display/read-only scope except the pre-existing Clr checkbox behavior, which was preserved unchanged; no new Register write path, schema/RLS/RPC, or Budget-calculation changes.
Static regression tests: 1332/0 passing (includes the Register CL/reconciliation default A10 suite).
E2E: 130/0 passing on this branch. The earlier WC-3/BR-3 "known e2e failure" language is stale here; do not re-cite without re-verifying.
Dashboard stable.

Next milestone:
- Wendy's Budget tab live use starting July 1, 2026
- parallel run with Quicken through August-September
- Quicken cancellation only after one full parallel month where category totals match, card totals reconcile, and reimbursables track cleanly

## Budget Module

Current functionality:
- Budget nav tab
- full printout UI
- Spent / Budget / Remaining
- parent/child category hierarchy
- Transactions add/edit/delete
- reimbursables integrated into main Transactions table
- REIMB badge, status, cleared checkbox
- reconciliation panel with cleared totals vs statement balance
- `BUDGET_CATEGORY_REGISTRY` hardcoded with 31 entries
- `_getBudgetLivingExpenses()` reads from Supabase `budget_line_rules` with monthIso-based JS fallback
- reimbursable defaults: source=Jabian, status=pending
- payment account required before save

## Known Gaps

- BR-3 e2e exception: pre-existing Budget Rules override behavior failure, predates Phase 5B, tracked separately
- Diablos/GLP are in `budget_line_rules` but not in 31-week cash-flow projection; projections understated July onward; separate task to update WD array
- auto-reminder label changes require manual Supabase cleanup if label text changes in code
- mobile sync: custom tasks added before June 2026 still only exist in localStorage on originating device
- `budget_line_rules.category_key` has no DB-level FK to `categories.key`. A month can go "operating" with active BLR rows whose category_key was never inserted into `categories` — Register silently can't resolve or save those categories even though Budget displays them fine (this is exactly what caused the 2026-07-02 live-use bug, data-corrected via `docs/2026-07-02-register-budget-category-sync.sql`). Reusable guard/template for future budget/category migrations: `docs/validation-blr-category-sync.sql` — copy its DO block into any migration that activates BLR rows for a new month, run as the last step. A real FK is the eventual fix but is NOT added yet — needs an audit of historical/legacy BLR rows first (see file for detail); track as its own future task, not folded into 5E-8.
- Two entry points for the same real-world spend existed and were not reconciled: Budget's own "+ Add Transaction" form (writes `budget_transactions`, Phase 5B) and Register (writes `transactions`, Phase 5E-1+). As of Phase 5E-9, Budget's spent calculation sums both tables additively. **As of Phase 5E-10, Budget's own Add Transaction path is disabled** (not removed) with helper copy pointing to Register — this closes the double-entry risk for new spend going forward. Any pre-existing `budget_transactions` rows (there were 0 as of the July 2026 preflight) remain readable/editable via Budget's existing edit/delete/cleared controls, just not creatable through that form anymore.
- Jabian reimbursement status tracking (pending → submitted → reimbursed) has no home as of Phase 5E-10. That workflow lived entirely in Budget's own form/`budget_transactions` (`transaction_type='reimbursable_expense'`, `reimbursement_source`, `reimbursement_status` columns), which is now disabled for new entries. Register's `transactions` table has no equivalent columns. Jabian expenses are still correctly excluded from Budget spend (`business.jabian_expenses_2026` has `budget_treatment='excluded'`), but there is no way to track submission/reimbursement status going forward — Budget's help panel flags this and tells Wendy to loop in Adam manually. Needs a decision for 5E-11 or later: add status tracking to Register, or keep a manual side-channel.
- `WC-3` e2e (What-If outflow monotonicity) is a pre-existing failure from `runModel`'s waterfall discrete sweep/completion triggers under the current `budget_line_rules`; it is NOT caused by 5F-1 Phase 2 (proven: `runModel` output is behavior-identical to `0923135` via computed WC-3 scenario, diff hunk map, and VM-sandboxed week-by-week comparison). Disposition is its own task: either reclassify the assertion (assert valid `diffModels` output, as `WC-4` does) or treat the non-monotonicity as a model bug and fix `runModel`. NOTE: the current branch e2e is 130/0, so WC-3/BR-3 are not currently failing here; re-verify before re-citing them as known failures or using `--skip-e2e`.
- A4 (AMEX Gold starting-balance correction) is DONE (executed 2026-07-06; verified in DB postflight and in the live Register). `accounts.starting_balance` for AMEX Gold was corrected from -8248.07 to -8248.50 (credit-card negative convention). Corrected anchor: -8248.50 is the cleared balance as of end of 2026-06-29; the 2026-06-30 Foxtail -$7.17 remains the first ledger row (order transaction_date asc, created_at asc, id asc), giving a Foxtail running balance of -$8,255.67. Only `accounts.starting_balance` changed: no transactions edited, AMEX Gold tx_count (51) and last_created_at/last_updated_at unchanged, no Budget/Register/schema/RLS/RPC changes (this value is Register-ledger-display-only; it does not affect Budget spend, cashflow, or reconciliation). Executed via `docs/2026-07-06-amex-gold-starting-balance-A4.sql` (key-pinned to `amex_gold`, first-ledger-row Foxtail proof, postflight assertions inside the transaction). The prior draft `docs/2026-07-05-amex-gold-starting-balance.sql` is superseded (positive-value guards plus a 2026-07-01 baseline guard that wrongly blocked the legitimate 6/30 Foxtail row). Unrelated: the 5F-1.5 Register default-sort question is now RESOLVED — Wendy confirmed the Quicken CL/reconciliation view, shipped live in commit 8d48b04 (see the Register CL/reconciliation default note below).
- Register CL/reconciliation default (live since commit 8d48b04, Wendy-confirmed) is the current default Register view: `_txLedgerSortCol='reconcile'` — uncleared rows on top, cleared below, newest-first (chronIdx desc: transaction_date asc, created_at asc, id asc) within each group; cleared===true only (null/undefined counts as uncleared); starting-balance row at the bottom; full-ledger historical balances never recomputed after sort/filter. The Clr header activates reconcile (idempotent) and shows an active indicator; the old generic cleared comparator was REMOVED from `_sortTxRows`. Date entry is uniform desc-first then toggles asc; Payee/Category/Outflow/Inflow remain sortable; Balance is non-sortable; the Clr checkbox (`_toggleTxCleared`) is unchanged. Display/read-only: no Register write path, schema/RLS/RPC, or Budget-calculation changes. Do NOT reintroduce a generic cleared asc/desc header sort — reconcile is the intended cleared-aware order.

## Near-Term Wishlist

- ID 26: Account connections via OAuth
- ID 27: Auto balance pre-fill
- ID 31: Timing for credit card due date moves
- ID 34: Add Wendy's trips and December trip to goals
- ID 38: Ability to add task to a defined future week
- ID 39: Audit historical/legacy `budget_line_rules` rows for category_key values missing from `categories`, then evaluate adding a DB-level FK (`budget_line_rules.category_key` → `categories.key`) so the operating-readiness guard in `docs/validation-blr-category-sync.sql` becomes unconditional instead of a manually-run check

## Session Constraints

Codex/Claude sandbox constraints:
- Cannot push to GitHub from sandbox
- Adam runs push from Terminal
- Playwright e2e may need to be run manually by Adam from Terminal: `node e2e.js`
- `push_to_github.sh` gates on both test suites and may fail in sandbox
- use git directly from Terminal when sandbox cannot run the full gate

## Coding Rules

Before changing code:
1. Inspect the current file.
2. Identify the smallest safe change.
3. Do not rewrite the full file unless explicitly required.
4. Preserve existing architecture.
5. Do not introduce frameworks or build tooling.
6. Maintain RLS and role guardrails.
7. Add or update regression coverage for behavior changes.
8. Call out any test that Adam must run manually.

## Definition of Done

A change is not done until:
- relevant regression tests are updated
- e2e impact is assessed
- role/RLS impact is assessed
- known gaps are not accidentally changed
- clear commit message is proposed
- manual test instructions are provided when Codex cannot run them

## Privacy / Repo Guardrail

Never copy `/Users/aherndon/AI-Context/` files into this repo.

Never commit personal context files to GitHub.
