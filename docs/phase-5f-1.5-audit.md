> **Historical governance artifact — provenance only.** 5F-1.5 Gate A shipped and is live (2026-07-05/06; see CODEX_STATUS.md under the 5F-1.5 Gate A shipped record). This document is the original audit or plan and is not current implementation authority. Where it differs from shipped behavior, committed code, tests, AGENTS.md, and CODEX_STATUS.md govern. Retained for provenance and audit traceability.

# Phase 5F-1.5 Audit — Wendy Feedback / July Usability Pass

Date: 2026-07-05. Audit only. No code changed, nothing committed. Audited against live working tree at `4a4e3ab`.

Architecture verdict up front: there is NO existing transaction filter/report helper anywhere in the app. Register fetches per-account chronological rows (`_loadTxLedger`), Budget fetches per-month category/amount tuples (`_budgetLoadRegisterSpend`), and neither is reusable for reporting. 5F-1.5 should introduce one small helper pair (filtered fetch + summarize) and power items 3, 4, 7, and 8 off it. The `sc-modal` overlay + slot-div pattern (`blr-modal-slot`, `scenario-modal-slot`) is the established modal mechanism and should be reused for the drill-through modal.

---

## Item 1 — Budget income actual/spent column

- **Current behavior:** Income rows and the Total Income row hardcode `—` in both Spent and Remaining (index.html ~6494-6505). Income actuals are never computed anywhere.
- **Root cause:** Two independent exclusions. (a) The `budget_transactions` pass only counts `transaction_type==='household_expense'`. (b) The Register pass drops all inflows (`if(!(amt<0))return`) and `_isCountableBudgetSpend` returns false for every income behavior_class. Income actuals were simply never built; the Spent column for income is a placeholder.
- **Status:** Missing.
- **Classification:** Correctness (drives the "out of balance" perception).
- **Proposed steps:** Add an `incomeByKey` pass over `_budgetRegisterSpendCache` (already fetched month-scoped, includes inflows): sum `amount>0` rows whose category is income-class, keyed by category_key. Render per-row actual in Spent and `budget − actual` in Remaining for income rows; total row sums displayed rows. No new fetch needed.
- **Tests:** Static: income row renders actual not `—`; inflow to income key counted; outflow to income key not counted as income. e2e: extend BUD-6-style injection with a Net Salary inflow, assert income actual renders.
- **Risk:** Medium. Touches `renderBudget` aggregation; display convention for income needs a decision (see open questions).
- **Order:** 2nd commit.
- **5F-1.5:** Yes.

## Item 2 — Budget credits against categories

- **Current behavior:** A +$50.00 RESY credit categorized to Wewe's Lunches is fetched into `_budgetRegisterSpendCache` but discarded at line ~6476: `if(!(amt<0))return;`. Category spend is gross, never net.
- **Root cause:** The 5E-9 Register pass was deliberately outflow-only. Credits/refunds to countable expense categories vanish.
- **Status:** Missing.
- **Classification:** Correctness.
- **Proposed steps:** In the Register pass, for countable categories accumulate `spentByKey[k] += -amt` (outflow adds, inflow subtracts) instead of `Math.abs` on outflows only. Adjust row render so a negative net Spent displays (currently `s>0?f(s):'—'` hides it); parent and grand totals already flow through. `budget_transactions` pass unchanged (positive-magnitude convention, no credits exist there).
- **Tests:** Static: RESY case (−spend +credit nets), credit-only category renders negative, income inflows still excluded. e2e: add a +$50 credit to the BUD-6 injection set, assert net.
- **Risk:** Low-medium. Two-line aggregation change plus one render condition. Highest trust-per-line item in the pass.
- **Order:** 1st commit.
- **5F-1.5:** Yes.

## Item 3 — Budget category drill-through modal (Jabian monthly report)

- **Current behavior:** No drill-through exists. Budget rows have Edit/Archive buttons only. No report modal, no category-filtered transaction view anywhere.
- **Root cause:** Never built.
- **Status:** Missing.
- **Classification:** Reporting (must-have).
- **One structural finding that changes the design:** production Budget renders the fixed 31-line `BUDGET_CATEGORY_REGISTRY` (`useSupabaseRegistries:false`), which does NOT contain `business.jabian_expenses_2026`. A drill-through launched only from Budget rows can never reach Jabian. The modal must accept any active category key, and item 4's category-picker entry point is what actually satisfies the Jabian monthly report. This is why items 3 and 4 should ship as one slice on one engine.
- **Proposed steps:**
  1. `_txReportFetch({dateFrom, dateTo, categoryKeys, accountKeys})` — one PostgREST query against `/rest/v1/transactions` with full columns (`id, transaction_date, account_key, payee, memo, category_key, amount, cleared`), ordered date asc. Arrays supported from day one; UI exposes single category + single budget month in v1.
  2. `_txReportSummarize(rows)` — pure function returning `{spend, credits, net, count}` (spend = sum of negatives, credits = sum of positives, net = spend + credits). Pure so it gets direct static-test coverage.
  3. `_txReportModal` state + `report-modal-slot` div + renderer following the `_blrModal` pattern exactly: summary strip (Total Spending / Credits-Reimbursements / Net / Count), transaction table (Date, Account label via `_accountsCache`, Payee, Amount signed with credits visually distinct, Cleared), category label via `_getRegisterCategoryLabel` month-aware.
  4. Entry point A: Budget category rows get a clickable Spent cell (or row-label affordance) → opens modal for that key + selected budget month.
  5. Entry point B (item 4 v1): a "Category Report" control on the Transactions tab (or Budget toolbar) with a category `<select>` over all active leaf categories including Jabian, plus month picker → same modal.
- **Explicitly not in v1:** balance column (running balance is per-account chronological; in a category-filtered cross-account view it is not "safely available" — omit rather than mislead), export, multi-category UI, typeahead, arbitrary day-range UI (helper takes ranges; UI offers months).
- **Tests:** Static: `_txReportSummarize` pure-function cases (spend only, credits only, mixed, empty); source-pattern for query construction and modal wiring. e2e: seed known rows, open modal, assert totals and credit styling.
- **Risk:** Medium. All new read-only code, no write path, no schema. Main risk is scope creep — hold the v1 line.
- **Order:** 3rd commit (after correctness fixes).
- **5F-1.5:** Yes (must-have).

## Item 4 — Category report / filtered register view

- **Current behavior:** Nothing exists.
- **Status:** Missing.
- **Classification:** Reporting.
- **Verdict:** Same engine, confirmed. Ships as entry point B of item 3 (category picker + month). Account filter and date-range UI are helper-ready but UI-deferred; typeahead and multi-select deferred (multi-select is not trivial in the current no-framework select pattern).
- **5F-1.5:** v1 yes (inside item 3's commit); expansion deferred.

## Item 5 — AMEX Gold starting balance

- **Current behavior:** `accounts.starting_balance` in Supabase is the single source (read by `_renderTxRegister` and `_renderTxAccounts`; no code constant, no edit UI). A prior correction on 2026-07-01 (`docs/2026-07-01-amex-gold-starting-balance-correction.sql`) set it to **−8248.07**.
- **Root cause:** Data/config only. No code change involved.
- **Status:** Partially done — and there is a real discrepancy to resolve: Wendy says $8,248.50, the 7/1 correction set 8,248.07 (negative, credit-card sign convention). 43-cent delta and sign need confirmation before touching production data.
- **Classification:** Data/config.
- **Proposed steps:** Confirm authoritative value with Wendy (statement). Then a data-only UPDATE following the existing 7/1 SQL doc pattern (preflight, guarded update, validation), Adam runs it. Per guardrail this is SQL, so: **asking first — see open questions. No SQL until you approve.**
- **Tests:** None (data). Validation query in the SQL doc.
- **Risk:** Low technically; medium if the wrong value goes in (register balances shift).
- **Order:** Anytime after value confirmed; independent of all code commits.
- **5F-1.5:** Yes.

## Item 6 — Goals Funding Plan now marker

- **Current behavior:** Marker pinned at Cal Wk 23.
- **Root cause:** Confirmed bug, two occurrences in `_renderGoalsFunding` (~lines 4659 and 4670): `nowIdx = clamp(currentW - 23)`. `currentW` is the MODEL week (1-31, currently 5), not a calendar week. 5−23 = −18, clamps to 0, index 0 = Cal Wk 23. Every sibling computation in the same function maps model→calendar as `calWk = 22 + w.num`, so the correct index is `currentW - 1` (model wk 5 → Cal Wk 27 → index 4).
- **Status:** Broken.
- **Classification:** Correctness.
- **Proposed steps:** Change `currentW-23` to `currentW-1` in both spots.
- **Tests:** Static source-pattern: assert `currentW-1` present / `currentW-23` absent in `_renderGoalsFunding`; optionally a computed-index unit case.
- **Risk:** Low. Display only, two characters each.
- **Order:** 4th commit (trivial, standalone).
- **5F-1.5:** Yes.

## Item 7 — Register layout/filter/search (Quicken-inspired)

- **Current behavior:** `_renderTxRegister` has an account `<select>`, Add button, inline add/edit form, and a fixed table (Date, Payee, Memo, Category, Outflow, Inflow, Clr, Balance, actions). No search, no date/type/status filter row, no account title header, no Transactions/Spending/Income views, 500-row cap in chronological order.
- **Status:** Partial (functional ledger exists; none of the requested UX layer does).
- **Classification:** Usability.
- **Proposed scoped pass (not a redesign):**
  1. Account context header: selected account label, institution, type badge above the table (data already in `_accountsCache`).
  2. Search input (top right): client-side substring match on payee/memo/category label over the already-fetched rows.
  3. Filter row: All Dates (month options), Any Type (outflow/inflow), Any Status (cleared/uncleared) — client-side predicates over fetched rows; the helper's predicate shapes from item 3 reused where sensible.
  4. Filtering happens AFTER balance attachment (same two-pass principle as 5E-10): balances stay chronologically true, filtered rows display their real running balance.
  5. Skip the Transactions/Spending/Income tab structure for 5F-1.5 — that is the report modal's job; adding a third view axis to Register now is redesign territory.
- **Tests:** Static source-pattern for search/filter wiring and the filter-after-balance order; e2e: filter to uncleared, assert subset and untouched balances.
- **Risk:** Medium. Largest render-function change of the pass; client-side only, no fetch or write changes.
- **Order:** 6th commit.
- **5F-1.5:** Yes, scoped as above.

## Item 8 — Register sortable columns

- **Current behavior:** Fixed uncleared-above-cleared display sort (5E-10). Headers are static `<th>`.
- **Status:** Missing (and 5E-10's fixed rule is explicitly superseded by Wendy's clarification).
- **Classification:** Usability.
- **Proposed steps:** Sort state `{col, dir}`; clickable headers (Date, Payee, Category, Clr, Outflow/Inflow amount, Balance) cycling asc/desc with an arrow indicator. Critically reuses the proven 5E-10 two-pass pattern: balances computed chronologically first, sort applied to the display copy only, precomputed balances rendered. Default sort: chronological date asc (matches running-balance semantics); the fixed uncleared-first rule is retired — Wendy gets it on demand by clicking Clr. Existing 5E-10 tests asserting fixed uncleared-first ordering (e.g. RG-12) will need updating to assert the new default + sort behavior, not deleting.
- **Tests:** Static: sort-state wiring, balance-before-sort order preserved. e2e: click Clr header → uncleared on top with correct balances; click Date → chronological restored.
- **Risk:** Medium. The balance-integrity pattern is already proven; the risk is test churn on 5E-10 assertions.
- **Order:** 7th commit (same session as item 7, separate commit).
- **5F-1.5:** Yes.

## Item 9 — Account dropdown alphabetical

- **Current behavior:** Dropdown renders `_accountsCache` in fetch order (`display_order.asc,label.asc,key.asc`), so display_order wins.
- **Root cause:** Known, and 5E-10 deferred this deliberately because naive sorting changes the default account (`activeAccounts[0].key` on first load).
- **Status:** Missing (consciously deferred).
- **Classification:** Usability.
- **Proposed steps:** Sort a display copy by label for the `<option>` list only; keep default-account selection reading the unsorted (display_order) array. Resolves the exact concern that caused the 5E-10 deferral.
- **Tests:** Static: options alphabetical, default-selection source unchanged.
- **Risk:** Low.
- **Order:** 5th commit (small, independent).
- **5F-1.5:** Yes.

## Item 10 — Weekly announcement placement

- **Current behavior:** The Alaska/Week-1 banners are appended at the very END of `renderWeekDetail` (~lines 4185-4188), below reconciliation, so the insight lands at the bottom of the week view. The header card (`wk-header-card`, ~3869) holds title/dates/badges and has room.
- **Root cause:** Banner block was written as a footer append; never integrated into the header card.
- **Status:** Partial (content exists, placement wrong).
- **Classification:** Usability.
- **Proposed steps:** Extract the banner selection (week 1 / Alaska-funded week / Alaska-funded-continuing) into a small `weekAnnouncement(w,weeks)` helper returning `{cls,text}|null`. Render it inside `wk-header-card` under the badge row; delete the bottom render (no duplication, per instruction). Coexists with `alertStrip` (warnings stay on top, announcement below badges).
- **Tests:** Static: announcement markup inside header card, absent at document end; helper returns correct branch per week.
- **Risk:** Low. Display move only; no model logic.
- **Order:** 8th commit (last).
- **5F-1.5:** Yes.

---

## Recommended commit plan and bundling

| # | Commit | Items | Size | Risk |
|---|--------|-------|------|------|
| 1 | Budget credits net into category actuals | 2 | Small | Low-med |
| 2 | Budget income actuals | 1 | Small-med | Med |
| 3 | Transaction report helper + drill-through modal + category report entry | 3 + 4 v1 | Medium | Med |
| 4 | Goals now-marker fix | 6 | Tiny | Low |
| 5 | Account dropdown alphabetical | 9 | Tiny | Low |
| 6 | Register header/search/filter row | 7 | Medium | Med |
| 7 | Register sortable columns | 8 | Small-med | Med |
| 8 | Weekly announcement into header | 10 | Small | Low |
| — | AMEX Gold data UPDATE (SQL doc, Adam runs) | 5 | Data only | Pending approval |

Bundling rules: 1 and 2 touch the same aggregation block but land separately so a credits regression is bisectable from an income-actuals regression. 3+4 are one engine, one commit. 6 and 7 both rewrite parts of `_renderTxRegister`; do them in sequence, never merged into one commit. 4, 5, 8 are safe singles.

## Stop conditions

- Any item turning out to need schema/RLS/SQL beyond the item 5 data UPDATE → stop and ask (specifically: if Jabian reporting is expected to show pending/submitted/reimbursed status, that needs a Register column and is out of 5F-1.5 unless approved).
- Item 5 value/sign not confirmed → no SQL runs.
- Any register sort/filter change that cannot keep the two-pass balance integrity provable in tests → drop the column, do not approximate.
- No touching: 5F-1 reconciliation internals, Review Required rendering, repair mode, WC-3, 5F-2+.
- Static regression baseline (1219) must stay green each commit; e2e delta limited to WC-3/BR-3 knowns.

## Open questions (need answers before commits 2, 3, and the data update)

1. **AMEX Gold (blocks data update):** 7/1 correction set −8,248.07; Wendy says 8,248.50. Which value is authoritative, and confirm the negative (amount-owed) convention is what she expects the register to show.
2. **Income display convention (blocks commit 2):** For income rows, Spent = amount received that month, Remaining = budget − received? And do income categories outside the 31-line registry (e.g. Deep South Commissions) roll into Total Income actuals, or only the displayed salary rows? Recommend displayed-rows-only for v1 with a footnote total if mismatch is confusing.
3. **Jabian status tracking (blocks nothing, sets expectations):** The modal will show Jabian spend, credits/deposits, net, and count for the month. It cannot show submitted/reimbursed status — that field has no home since 5E-10 (known gap). OK to ship the report without it, or does Wendy's "turned in and reimbursed" requirement force the status-column decision into 5F-1.5? (That would be schema → ask-first.)
4. **Modal balance column:** omit in v1 (not safely computable in a category-filtered cross-account view) — confirm.
5. **Default register sort:** confirm retiring the 5E-10 fixed uncleared-first default in favor of chronological + sortable Clr column.
6. **Drill-through entry:** clickable Spent cell on Budget rows acceptable as the click target? (Row labels already carry Edit/Archive buttons.)
