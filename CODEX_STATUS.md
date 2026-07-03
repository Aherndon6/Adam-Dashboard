# Codex Status: Herndon Financial OS

## Current Phase

Phase 5B complete.
Budget Module v1 live.
Wendy live-use target: July 1, 2026.

## Current Goal

Prepare the system for Wendy using the Budget tab in live household workflow while preserving platform stability, RLS security, and reconciliation accuracy.

## Recent Verified State

- Regression tests: 687/0 passing
- E2E tests: 63/0 passing
- Dashboard stable
- GitHub Pages deploys from main

## Do Not Break

- Adam/Wendy role model
- RLS protection
- Budget transactions
- Reimbursable behavior
- Reconciliation panel
- Existing Quicken parallel-run workflow

## Next Candidate Work

1. Finish Phase 5E-7.
2. Prepare Phase 5E-8.
3. Resolve or quarantine BR-3.
4. Add Diablos/GLP into WD cash-flow projection.
5. Improve Wendy usability only after core logic is safe.

## 5E-8 CLOSED: Register Category Sync (2026-07-02)

Live-use bug: Register's Add Transaction category dropdown/row display didn't match Budget's categories (Wendy-facing, reported live). Root-caused and resolved across three rounds:

1. **Code fix** (commit 238b245, confirmed live at the 10:00 AM build) — Register sources categories from live `_categoriesCache` (normalized via `_normalizeCatRow`) with month-aware label resolution via new `_getRegisterCategoryLabel()`, deliberately NOT `_getActiveCategoryRegistry()`/`BUDGET_CATEGORY_REGISTRY` (that registry is scoped to Budget's fixed 31 lines and gated behind `FEATURE_FLAGS.useSupabaseRegistries`, false in production). Also: `transaction_date` field now triggers a re-render (dropdown labels are month-derived; date input switched `oninput`→`onchange`).
2. **Root cause of the remaining live gap** — a DATA gap, not code. `entertainment.event_1/event_2/week_1-4` were seeded into `budget_line_rules` for July (`docs/phase-5e-6-migration.sql`) but never inserted into `categories` (`docs/phase-5d-1-migration.sql` only seeded 4 static Entertainment leaves — birthday_dinner/brunch/big_dinner_out/entertainment_other). Register can only offer categories that exist in `categories`.
3. **Data-only correction — EXECUTED AND VALIDATED (2026-07-02)**: `docs/2026-07-02-register-budget-category-sync.sql` (preflight → preview → guarded INSERT, entertainment-pattern-scoped, `ON CONFLICT DO NOTHING` only, no UPDATE/DELETE/schema/RLS). Adam ran preflight + insert + validation in production. Confirmed results: `still_missing=0`; all 6 new rows `leaf=true`/`active`/`assignable=true`; parent/group rows remain non-assignable; no duplicate/near-duplicate keys; `entertainment.*` now shows 10 active child rows. Live Register dropdown for a July 2 AMEX Gold transaction confirmed showing Seattle / Wewe's Lunches / Entertainment Week 1-4, alongside the original 4 real Entertainment categories and other existing live categories (Net Salary, Deep South Commissions, Auto Payment, Gas & Fuel), with "Entertainment" itself correctly not selectable.

Reusable future guard drafted (not applied to anything today): `docs/validation-blr-category-sync.sql` — copy-paste template for future budget/category migrations to run as their last step, encoding the rule "any active `budget_line_rules.category_key` for an operating month must exist in `categories` first." Also logged in `AGENTS.md` Known Gaps + Wishlist ID 39 (FK from `budget_line_rules.category_key`→`categories.key` considered but NOT added — needs a historical/legacy BLR row audit first).

Test status: static regression 1039/1039 passing. `5E8-R1`–`R20`, `R22` all reflect the confirmed post-fix production state (temporary diagnostic tests `5E8-R18`/`R19` and e2e `RG-7c`, which previously asserted the pre-fix data-gap-limited state on purpose, are now flipped to assert Seattle/Wewe's Lunches/Week 1-4 resolve, existing categories are preserved, and parent/group rows stay non-assignable). New end-to-end test `5E8-R22` calls `_renderTxRegister()` directly and reproduces Adam's exact confirmed live result. e2e.js Reconciliation selector was also widened this round (unrelated pre-existing gap, not a Register regression) — pending Adam's e2e re-run for final confirmation.

5E-8 is fully closed pending Adam's e2e.js re-run. 5F-1 remains gated behind 5E-7 and 5E-8 per the existing rule below — with 5E-8 now closed (contingent on e2e confirmation), that gate condition is satisfied, but 5F-1 should not resume without Adam's explicit go-ahead in a future session.

## 5E-9 CLOSED: Budget/Register Spend Integration (2026-07-02)

Live-use bug: July AMEX Gold transactions were entered and categorized correctly in Register, but Budget's "Spent" column showed $0.00 across every category. Root cause: `public.transactions` (Register, Phase 5E-1+) and `public.budget_transactions` (Budget's own CRUD, Phase 5B) are two fully disconnected tables. `renderBudget()`'s `spentByKey` aggregation only ever read `_budgetTransactions` (sourced from `budget_transactions`) — no code path anywhere read Register's data into Budget. This was a missing aggregation path left over from when Register was built as a new module, not a regression from 5E-8.

Audit findings (full 9-point audit run before any code changed, per Adam's instruction):
- No double-count risk today — confirmed via live preflight, `budget_transactions` has 0 July 2026 rows. Ongoing risk flagged: Budget's own "+ Add Transaction" form is still live: Register should be treated as the actual-spend source of truth going forward; that form should be considered legacy/manual-entry-only to avoid future double-entry (documented, not yet enforced in code).
- Month/date logic: reused `_budgetLoadTransactions`'s exact local-date month-boundary math (avoids known UTC-shift bug) rather than reinventing it.
- Uncleared transactions count toward spent — matches `budget_transactions`' own existing behavior (no `cleared` check there either).
- Account-agnostic — no account_key filtering, matching `budget_transactions` (which has no account concept at all).
- Category filter (`_isCountableBudgetSpend`, new helper near `_normalizeCatRow`): active leaf categories only; excludes `behavior_class` IN (income, commission_income, reimbursable_income, transfer, savings_allocation) and `budget_treatment` IN (excluded, display_only, planned_allocation) or null. Verified against real confirmed live category data: `business.jabian_expenses_2026` (reimbursable_expense/excluded — does NOT count), `business.jabian_deposits_2026` (reimbursable_income/display_only — does not count), `taxes.actual_tax_payment` (expense/excluded — does not count), `taxes.vio_transfer_2026` "Taxes 2026" (transfer/excluded — does not count), `transfers.greenlight` (transfer/excluded — does not count), `business.jabian_2026_dup` (lifecycle_status=merged — does not count).

Fix (index.html only, no schema/RLS/reconciliation changes):
- New `_budgetRegisterSpendCache`/`_budgetRegisterSpendLoadStatus` state + `_budgetLoadRegisterSpend(monthIso)` loader, querying `/rest/v1/transactions` for the selected month.
- `renderBudget()`'s loading gate now awaits both `_budgetTransLoadStatus` and `_budgetRegisterSpendLoadStatus` before computing `spentByKey`.
- `spentByKey` gets a second accumulation pass over `_budgetRegisterSpendCache`: outflow only (`amount<0`), category gated through `_isCountableBudgetSpend`, summed as `Math.abs(amount)` (converts Register's signed convention to `budget_transactions`' positive-magnitude convention).
- Refresh: `_budgetChangeMonth` resets the new cache/status on month switch; `setSection('budget')` resets `_budgetRegisterSpendLoadStatus` on every Budget tab entry, so a Register edit made from a different tab isn't shown stale (`budget_transactions` itself already refreshes correctly — its own CRUD reloads it directly).

Test status: static regression 1059/1059 passing (20 new tests, `5E9-01`–`5E9-20`: pure-function coverage of `_isCountableBudgetSpend` against real confirmed live category data, plus source-pattern coverage of the loader/merge/refresh wiring; two pre-existing tests, `5B-15` and `5E8-R20`, had their fixed-offset slice windows widened after the new code pushed target strings further into `renderBudget()`/`_setTxFormField`, no assertions changed). New e2e test `BUD-6` (Playwright) exercises the real merge end-to-end: injects Adam's actual July 2 example (Fandango $40.00 + Barn $32.68 + mend coffee $12.98 = $85.66 tagged `entertainment.week_1`), a same-category inflow that must not count, and a Jabian Expenses / Greenlight outflow that must not count — asserts the rendered Budget grid shows exactly $85.66 for Entertainment Week 1 and never surfaces the excluded $7.17.

Post-deploy triage: first e2e run showed 2 failures (`BUD-4`, `BUD-5`) — both pre-existing tests that inject `_budgetTransLoadStatus='loaded'` directly but never touched the new `_budgetRegisterSpendLoadStatus`, which the new dual-precondition loading gate also requires. Confirmed stale-test-only (no app regression, gate behaving as designed) via full grep of every `_budgetTransLoadStatus='loaded'` occurrence in e2e.js. Fixed by adding the matching `_budgetRegisterSpendLoadStatus`/`_budgetRegisterSpendCache` setup+teardown to both tests, mirroring their existing pattern. No index.html changes for this round; static regression re-confirmed 1059/1059 unaffected.

**Confirmed closed 2026-07-02**: static regression 1059/1059, e2e 116/116, commit `f0dbe1d`, Pages deploy green and live (footer confirms Jul 2 5:08 PM build). Live production check confirmed: Entertainment $85.66 spent (Week 1 $85.66 spent / $164.34 remaining), Groceries $8.00, Diablos (Preston) Fee $750.00 spent / $0.00 remaining, Google $33.60 spent / $0.40 remaining, Total Planned Budget $877.26 spent, Jabian Expenses 2026 correctly excluded from spend. Register dropdown fix (5E-8) still live. Reconciliation still shows $0.00 — expected, intentionally out of scope, deferred to 5F-1/5F-2.

Not done in this pass, still open: Budget's own manual "Add Transaction" form was not hidden or disabled — the double-entry risk this creates is documented in AGENTS.md Known Gaps, not resolved. Reconciliation panel was explicitly left untouched (still `budget_transactions`-only, per existing 5F-1/5F-2 migration plan).

Do not reopen 5E-8 or 5E-9 unless Wendy finds another live-use issue.

## 5E-10 IN PROGRESS: Budget/Register Source-of-Truth + Entry Safety (2026-07-02)

Scoped from Wendy's initial live-use feedback (5 items). Included in 5E-10: payee required (#3), uncleared-above-cleared row sort (#4). Deferred to 5E-11: category typeahead/ABC ordering (#1), payee memory/autofill (#2), account dropdown ABC ordering (#5 — originally considered in-scope, deferred after the audit found it changes Register's default account on first load via `activeAccounts[0].key`, a real behavior change not just display polish).

Changes (index.html + tests only, no schema/RLS/reconciliation logic):
- **Budget manual entry disabled, not hidden.** `renderBudget()`'s "+ Add Transaction" button now renders `disabled` with a tooltip and adjacent helper text: "Actual spending is now entered in Transactions → Register." Register is now the actual-spend source of truth — prevents the double-entry risk flagged in AGENTS.md Known Gaps (5E-9 entry) between `budget_transactions` and `transactions`. "Manage Lines" (Budget Line Admin, `_blrOpenAdd`) is untouched — separate control, still fully active.
- **Budget help panel rewritten** for the two sections that instructed Wendy to use the now-disabled button ("Adding a transaction" → "Entering a transaction"; "Logging a Jabian reimbursable" → "Logging a Jabian expense"). New copy points to Register and the `business.jabian_expenses_2026` category, and **honestly discloses a real capability gap**: Register has no `transaction_type`/`reimbursement_status` field, so the old pending → submitted → reimbursed tracking workflow has no equivalent yet — flagged in the help text as "flag any Jabian expense to Adam separately until that is added," and logged below as an open item. Reconciliation and "Reading the budget printout" help sections are untouched.
- **Register payee is now required** (`_saveTxForm`) — validated before the Supabase call, same pattern as the existing date/amount/account checks. Input placeholder changed from "Optional" to "Required", label shows `Payee *`.
- **Register rows: uncleared display above cleared**, running balance preserved correctly. Two-pass approach in `_renderTxRegister()`: pass 1 (`rowsWithBalance`) walks the original chronological fetch order and attaches each transaction's correct running balance; pass 2 (`displayRows`) builds a stable-sorted display copy (uncleared first, cleared second — `Array.prototype.sort` stability preserves chronological order within each group) and renders using the precomputed balance, never recomputing after the sort. Matches the existing non-mutating `.slice().sort()` convention already used by `_renderTxAccounts`.

Known gap surfaced by this change (not resolved here, logged for 5E-11 or later): Jabian reimbursement status tracking (pending/submitted/reimbursed) has no home now that Budget's own entry form is disabled — `transactions` table has no equivalent field. Needs a decision: add the field to Register, or keep it as a manual side-channel to Adam for now.

Test status: static regression 1070/1070 passing (11 new tests, `5E10-01`–`5E10-11`, source-pattern coverage of the disabled button, help panel copy, payee validation, and the balance-then-sort sequence — one test, `5E10-03`, needed its own false-positive fix mid-pass: a broad nearby-text regex matched the word "disabled" inside an unrelated comment, tightened to check the Manage Lines `<button>` tag itself). New e2e tests: `WR-6b`/`WR-6c` (blank payee rejected / non-blank payee not blocked), `RG-12` (uncleared-first display order with exact balance values verified: Fandango $-150.00, Kroger $-100.00, Paycheck $1850.00 — proving the balance is chronologically correct despite the reordered display), `BUD-7` (disabled button + tooltip, Manage Lines unaffected, help panel no longer references the old button, reconciliation help copy unchanged). Confirmed all 5E-9 tests remain green in the same run.

Pending Adam's e2e.js run before commit.

## 5F-1 Handoff (next session)

This section previously said "5F-1 v3.12 is build-ready but NOT started" — that is stale. 5F-1 is in progress, not started, as of this update.

Landed so far (3 commits): `f3402c1` DB + cash availability engine foundation, `be584c1` WD event tagging foundation, `6d5c8b5` reconciliation Phase 0/1 UI (staged-answer state machine, not yet persisted).

Production DB validation (`docs/phase-5f-1-preflight.sql`, `docs/phase-5f-1-validation.sql`) confirmed clean: `cash_commitments` (28/28 columns, 7/7 CHECK constraints, RLS SELECT-only for `authenticated`), `weekly_reconciliations.balance_basis`, `save_reconciliation_with_commitments` (11-param, SECURITY DEFINER, search_path pinned, correct grants), `repair_commitments_for_week` and `validate_commitment_state` all match the migration spec in production. V1-V17 PASS, V18-V19 informational REVIEW as designed. No `budget_transactions` coupling anywhere in the 5F-1 SQL or JS.

**5F-1 RPC persistence bridge slice (this update):** `saveRecon()` now calls `save_reconciliation_with_commitments` instead of writing `weekly_reconciliations` directly, sending staged Phase 1 answers (`buildPhase1PatchArray()`) as `p_patched`. `canPersistReconNow()`/`canSaveRecon()` no longer require zero Phase 1 rows — a fully-answered week is now saveable. `p_new_commitments` is always `[]` this slice (new-commitment insertion is WD-tagging/Phase 2 territory, not this slice). On RPC failure, staged Phase 0/1 answers and the open recon form survive for retry; on success, `reconData`/`commitmentData` reload from Supabase rather than being faked locally. Files touched: `index.html`, `test_regression.js`, this file. `e2e.js` was deliberately NOT touched — seeding `commitmentData` with a real prior-unresolved commitment through the existing harness was judged not worth the added risk for this slice; covered instead by static source-pattern tests plus a manual live Supabase smoke test after deploy.

AC accounting: 22 of 33 JS-engine-layer ACs now fully unblocked (13 engine-layer, no persistence involved, Section 5F1-K; plus the 9 that were PARTIAL — AC-77,78,79,80,88,89,90,91,92 — now confirmed both logically correct, Section 5F1-M, and wired to a real persistence path, Section 5F1-RPC-BRIDGE). 0 ACs remain PARTIAL. 11 ACs remain BLOCKED (AC-15,18,21,28,96,97,101,105,106,107,108) pending Phase 2/3/4 of the reconciliation form, dashboard verdict-text rendering, and historical repair mode — none of that exists yet. AC-76 is a process-check, not a runtime assertion.

Still not started: Phase 2 (current-week WD obligation prompts), Phase 3 (generic catch-all), Phase 4 UI polish, dashboard Review Required verdict rendering, `repair_commitments_for_week` wiring (historical repair mode), new-commitment insertion via `p_new_commitments`.

- Use the re-grepped regression baseline per AC-76, not any stale count.
- Prose spec stays frozen unless implementation surfaces an actual failing AC or a cash-safety defect.
- UI carryover: Phase 2 current-week protected WD prompts have no hard completion gate (ignored prompts rely on backfill detection). Do not redesign. Make protected prompts hard to miss and make backfill / Review Required warnings prominent.

## Post-5F-1 Build Path & Strategic Horizons

See `docs/strategic-roadmap-future-horizons.md` for the agreed post-5F-1 build order (5F-2, 5G-1, 5I-3, 5G-2, 5F-3, 5G-3, 5F-4) and the longer-term Strategic Roadmap (bank integration, AI assistant, financial planning/retirement layer, household OS expansion — documentation only, not build-authorized). Guardrail: no bank import, AI assistant, forecast integration, or household OS expansion work until one clean July operating week with Wendy is complete.

## Codex Operating Rule

Before editing, Codex should perform a read-only orientation against:
- `/Users/aherndon/AI-Context/00-README.md`
- `/Users/aherndon/AI-Context/02-working-style.md`
- `/Users/aherndon/AI-Context/05-financial-os-context.md`
- `/Users/aherndon/AI-Context/08-open-items.md`
- `AGENTS.md`
- `CODEX_STATUS.md`

Codex should not change files until it confirms the active goal, affected files/functions, intended tests, and risk areas.
