# Codex Status: Herndon Financial OS

## Current Phase

Phase 5B complete.
Budget Module v1 live.
5F-1 complete through Phase 4 and proven in a real weekly closeout (Week 26, 2026-07-04).
5F-1.5 Gate A (Wendy July usability) UI shipped and live (2026-07-05/06), including the Register Quicken-style ledger hotfix (historical Balance) and the Register CL/reconciliation default view (commit 8d48b04, Wendy-confirmed and live-smoked on dashboard.herndons.us). A4 (AMEX Gold starting-balance correction) is DONE (executed and verified 2026-07-06).
Wendy Budget-tab live use in progress (target July 1, 2026).

## Current Goal

Prepare the system for Wendy using the Budget tab in live household workflow while preserving platform stability, RLS security, and reconciliation accuracy. 5F-1 forward reconciliation is now live and proven; remaining 5F-1 sub-items (dashboard Review Required verdict rendering, historical repair mode) are deferred and do not block forward weekly closeout.

## Recent Verified State

- Static regression tests: 1332/0 passing (as of 5F-1.5 Gate A + Register ledger hotfix + Register CL reconciliation default)
- E2E: 130/0 passing on this branch. The earlier WC-3/BR-3 "known e2e failure" language is stale for this branch; do not re-cite it without re-verifying.
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

## 5F-1 Phase 2 SHIPPED (2026-07-03)

Current-week WD obligation prompts + `p_new_commitments` are live. `saveRecon` sends `buildPhase2NewCommitments(...)`; prompt UI in `renderReconPhase01` (seven-branch response select, amount/notes/reflection inputs, Clear control); count-gated in-form banner ("N current-week protected obligations not yet recorded", renders only when N>0); the save gate composes answered-row completeness (Phase 0 basis + all Phase 1 rows + every *answered* Phase 2 row internally complete; unanswered prompts never block); conflict routing (a case-insensitive `commitment already exists` error reloads commitments and routes the user to Phase 1). Deployed at build-stamp `2363501`; live-smoke passed: one real `cash_commitments` row created for `2026mw4_tax_transfer_vio_2026_06_28` (status planned, source_account truist_checking, commitment_source wd_reconciliation, amount_cents 43563), deduped on reopen, banner dropped 4 to 3, and the tax transfer surfaces under Transfers to Execute as a planned transfer. Static regression 1163/1163. e2e 119/120: the sole failure `WC-3` is a pre-existing waterfall non-monotonicity issue, not Phase 2 (see AGENTS.md Known Gaps). `reconEffectiveWD()` was extracted from `runModel` as the single source of override-aware weeks (behavior-preserving, all model tests green). Next: Phase 3 (generic catch-all), not started.

## 5F-1 Phase 3 SHIPPED (2026-07-04)

Generic Catch-All (manual, non-WD reconciliation items) is live. `saveRecon` concatenates `buildPhase3NewCommitments(_reconPhase3Items, _reconBasis, n)` onto the Phase 2 rows into `newCommitmentsAll` and sends it as `p_new_commitments`; `p_patched` and the Phase 0/1/2 paths are unchanged. UI: a "Phase 3: Other reconciliation items" section in `renderReconPhase01` with an Add item control, per-item label/amount inputs, a 5-branch response select (`not_paid_yet`, `paid_initiated`, `bank_pending`, `cleared_reflected`, `paid_other_account`; no `amount_changed` or `wd_mismatch`), a conditional reflection select (`available_balance` + `paid_initiated`/`bank_pending`), and a Remove control, all wired to `_reconPhase3Items` setters (`addPhase3Item`/`setPhase3ItemField`/`removePhase3Item`; item `id` = `manual_<uuid>` generated at add-time, doubling as `expected_item_id`). Gate: `canCompleteReconPhase3` composes into `canPersistReconNow` after Phase 2 (blank section never blocks; a started-but-incomplete item blocks before the RPC; blocked-reason order basis, Phase 1, answered Phase 2, started Phase 3). Rows are `commitment_source=manual_reconciliation`, `commitment_class=other_transfer`, `required_or_discretionary=protected_required`, `affects_deployable_cash=true`, `source_account` defaulted to `truist_checking`, `original_amount_cents`/`due_date`/`resolution_notes` null. No schema/RLS/SQL change (the RPC already accepts `manual_reconciliation`). Deployed build-stamp `f282ab8` (Pages #134). Live-smoke passed: one `manual_reconciliation` row created for a $1.00 "P3 smoke test" planned item, verified field-by-field, then rolled back clean (throwaway; production left clean, `weekly_reconciliations` intact). Static regression 1213/1213. e2e run pre-push showed only the known `WC-3` (and `BR-3`) failures, so `--skip-e2e` was used per the documented condition. Next: Phase 4.

## 5F-1 Phase 4 SHIPPED + real closeout PROVEN (2026-07-04)

Phase 4 (Balance Entry) is complete. The 5-field balance form, pre-fill, save flow, and RPC balance fields already existed; the one spec gap was the unknown-basis warning. P4-1 added: a non-blocking amber warning under the Phase 0 basis radios gated on `_reconBasis==='unknown'` (styled with repo `--amberSoft`/`--amber`, independent of the unbuilt dashboard Review Required verdict, unknown stays a valid saveable basis); and a basis-aware `reconBalanceGuidance(basis)` helper replacing the static posted-only note (distinct posted/available/unknown copy, de-duplicated from the amber wording, safe default when unselected). No runModel/reviewRequired change, no dashboard verdict rendering, no new save gating, no balance-validation change, no schema/RLS/SQL. Deployed at commit `dbcae6a` (functional commit `b1be6c8`), footer build Jul 4 2:34 PM; live visual check confirmed the amber warning shows only under "Not sure" and the guidance copy switches by basis. Static regression 1219/1219.

Real Week 26 closeout completed and read-only verified in production (stored week_num 4 / displayed Week 26):
- `weekly_reconciliations` row saved correctly, `balance_basis=posted_current_balance`, balances chk 14935.14 / sav 3772.81 / amx 103.64 / tax 1516.59 / lc 13774.76.
- Three Tiffany Dye rent obligations resolved cleanly: all `status=cleared`, `reflected_model_week=4`, `resolved_model_week=4`, `resolution_type=cleared`.
- No Phase 3 duplicate for the $435.63 Vio tax transfer. The only 43563-cent row is the legitimate `wd_reconciliation` row `2026mw4_tax_transfer_vio_2026_06_28` (status planned). The scheduled 07/06 transfer was captured in Week Notes (Vio confirmation 202618513554465, flagged not-yet-reflected), not as a new commitment, which is correct.
- Jul 4 commitment activity is exactly 3 cleared rent rows + 1 planned Vio transfer row. Duplicate `expected_item_id` = 0, smoke/test leftovers = 0. Distribution: wd_reconciliation/cleared = 3, wd_reconciliation/planned = 1.

Conclusion: 5F-1 forward reconciliation is proven in real use and production data is clean. Two 5F-1 sub-items remain deliberately deferred and are not required for forward weekly closeout: dashboard Review Required verdict-text rendering (AC-15/18; the reviewRequired flag itself is computed and tested) and historical repair mode (AC-21; `repair_commitments_for_week` wiring, backfill of past un-tagged weeks only). Blocked-AC tracker trimmed accordingly to AC-15/18/21 (Section 5F1-NOTSTARTED).

## 5F-1.5 Gate A UI SHIPPED + Register Quicken ledger hotfix LIVE (2026-07-05/06)

Wendy July usability pass, display/read-only scope except the pre-existing Clr checkbox behavior, which was preserved unchanged. No new Register write path, schema/RLS/RPC, or Budget-calculation changes. Live on the custom domain (footer Jul 6 2026 1:11 AM after a forced Pages redeploy). Static 1322/0, e2e 130/0.

Seven UI gates (pushed as the stack A5, A8, A6, A9a, A9b, A7a, A7b; deploy #141):
- e99e24b A5: account dropdowns alphabetized (payment pickers + Register selector), Cash/Other pinned last, default account preserved.
- fb7a0d2 A8: weekly milestone/guidance banner moved from the bottom of the week into the header card.
- 7419b31 A6: Register columns user-sortable; Balance non-sortable; chronological running-balance invariant (two-pass: compute -> filter -> sort, bal never recomputed).
- 17e9d19 A9a: Register search (payee/memo/resolved category) + Type/Status filters + Clear + filtered empty state + full-ledger caption.
- e22af6e A9b: Register inclusive Date From/To filters (lexical YYYY-MM-DD) + selected-account context label.
- 833a0e9 A7a: read-only Category Report modal + picker reaching excluded/income categories (incl. Jabian Expenses/Deposits); legacy budget_transactions count-only notice; 1000-row truncation warning; stale-fetch guard; no Balance column.
- 2040245 A7b: Budget expense leaf rows (label + Spent cell) drill through to the A7a report; goal_sweep/parent/income excluded; row label escaped.

Register ledger hotfix (two follow-on commits, both live):
- 6736d42: default Register sort is Date descending (Quicken newest-first); each row's Balance is the historical/as-of-transaction-date running balance from accounts.starting_balance; starting-balance row moves to the bottom in newest-first view; extracted the _computeLedgerBalances row-builder for testability; caption hides for any date sort.
- f12596f (redeploy forced by empty commit 77ecc0f): Clr is a status-only column, non-sortable header (no sort arrow), the row checkbox stays editable via _toggleTxCleared; uncleared review is the Status = Uncleared filter (which preserves date/desc order and full-ledger balances). The _sortTxRows cleared comparator remains as dormant/defensive code, not user-facing. This matches Quicken: the register is ledger-first and can no longer be reordered into a status-grouped table. [SUPERSEDED by 8d48b04 below.]

Register CL/reconciliation default (2026-07-06, live-smoked on dashboard.herndons.us):
- 8d48b04: the Register now DEFAULTS to the Quicken CL/reconciliation view (`_txLedgerSortCol='reconcile'`), superseding the f12596f Clr-status-only default per Wendy's confirmation. Uncleared rows on top, cleared below, newest-first (chronIdx desc: transaction_date asc, created_at asc, id asc) within each group; cleared===true only (null/undefined counts as uncleared); starting-balance row at the bottom; full-ledger historical balances never recomputed after sort/filter. The Clr header activates reconcile (idempotent) and shows an active indicator; the old generic cleared comparator was removed from _sortTxRows. Date entry is uniform desc-first then toggles asc; Payee/Category/Outflow/Inflow remain sortable; Balance is non-sortable; the Clr checkbox (_toggleTxCleared) is unchanged. Display/read-only scope: no Register write path, schema/RLS/RPC, or Budget-calculation changes. Static 1332/0; affected e2e (LEDGER-1/2, A6-1, A9-1/2, RG-12) verified in a real browser; live-confirmed by Wendy's daily-reconcile workflow.

### A4 DONE (AMEX Gold starting-balance correction)
Executed 2026-07-06; verified in DB (postflight) and in the live Register. `accounts.starting_balance` for AMEX Gold corrected from -8248.07 to -8248.50 via `docs/2026-07-06-amex-gold-starting-balance-A4.sql`, run as one execution (single guarded transaction with COMMIT included). Corrected accounting anchor: -8248.50 is the cleared balance as of end of 2026-06-29, before the 2026-06-30 Foxtail -$7.17; Foxtail remains the first ledger row (order transaction_date asc, created_at asc, id asc) with a running balance of -$8,255.67. Only accounts.starting_balance changed: no transactions inserted/updated/deleted, Foxtail date/amount/updated_at unchanged, AMEX Gold tx_count = 51 unchanged, last_created_at/last_updated_at unchanged, no Budget/Register/schema/RLS/RPC changes. Postflight confirmed value_ok=true and ledger_at_foxtail_ok=true. The 2026-07-05 draft (`docs/2026-07-05-amex-gold-starting-balance.sql`) is superseded (positive-value guards plus a 2026-07-01 baseline guard that blocked the legitimate 6/30 Foxtail row). Unrelated: the 5F-1.5 Register default-sort question is now RESOLVED — Wendy confirmed the Quicken CL/reconciliation view, shipped live in commit 8d48b04 (see the Register CL/reconciliation default entry above). accounts.starting_balance is Register-ledger-display-only (does not affect Budget spend, cashflow, or reconciliation).

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
