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
- key tables include `weekly_reconciliations`, `weekly_tasks`, `model_week_overrides`, `goals`, `budget_transactions`, `budget_line_rules`, `wishlist_items`

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
Regression tests: 687/0 passing.
E2E tests: 63/0 passing.
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
- Two entry points for the same real-world spend exist and are not reconciled: Budget's own "+ Add Transaction" form (writes `budget_transactions`, Phase 5B) and Register (writes `transactions`, Phase 5E-1+). As of Phase 5E-9, Budget's spent calculation sums both tables additively — safe today only because `budget_transactions` had 0 July 2026 rows (confirmed via live preflight). If the same purchase is ever logged in both places, it will double-count. Register should be treated as the actual-spend source of truth going forward; Budget's own manual entry form should be considered legacy/manual-only. Not yet enforced in code — no UI change made to hide or disable Budget's own form.

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
