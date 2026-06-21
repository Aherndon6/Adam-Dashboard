# Herndon Financial OS — Budget Rules Pre-Build Package

**Date:** June 21, 2026  
**Status:** Awaiting Adam's approval before any code is written  
**Companion file:** `budget-rules-spec-v3.1.md` (Draft 3.1 spec — already complete)

---

## Output 2: Wishlist Reconciliation Summary

### Items Made Obsolete / Absorbed by Budget Rules

| ID | Current Title | Action | Rationale |
|---|---|---|---|
| 40 | "Create a variables page so that there aren't hard coded values driving the model" | **Rename + re-phase** → "Budget Rules admin UI" → Phase 6, planned | Budget Rules IS the variables mechanism. The Supabase table replaces the concept of a variables page. The admin UI for managing rules is the natural Phase 6 follow-on. |
| 49 | "How do I deal with the monthly phone accrual?" | **Convert to data task** — add a Budget Rule row after build | This is no longer a feature design question. Budget Rules provides the mechanism; the phone accrual becomes a production row in the `budget_rules` table. |

### Items Partially Addressed (Keep, No Change)

| ID | Title | Note |
|---|---|---|
| 31 | Add in timing for when to ask credit card companies to move due dates | Budget Rules models impact of existing due dates; the "when to ask" advice is a separate planning question. Keep as-is. |
| 48 | Think about getting Truist transactions from website | Related to Phase 6 account connections, not Budget Rules. Keep. |

### Items Unaffected (No Change)

All other existing items remain as-is:
- Phase 5 goal features (ids 21–24, 32–33, 37–38): separate track
- Phase 6 auth + account connections (ids 25–28): separate track
- Phase 7 account reconciliation (ids 29–30): separate track
- Backlog ideas (ids 35, 39, 50–54): separate track

### New Items to Add

**Phase 5 (this build):**

| Title | Type | Notes |
|---|---|---|
| Budget Rules — create `budget_rules` Supabase table | feature | SQL schema from spec §4 |
| Budget Rules — delta-mode engine (validation, occurrence gen, week mapping, audit trail) | feature | Core Phase 1 implementation |
| Budget Rules — load-failure warning banner | feature | `budgetRulesLoadStatus` = 'failed' state |
| Budget Rules — first production rules (rent increase, medical bill, baseball payment) | feature | Data entry + visual verification |

**Phase 6 (future):**

| Title | Type | Notes |
|---|---|---|
| Budget Rules — admin UI (add/edit/deactivate/preview) | feature | Absorbs and replaces id 40 |
| Budget Rules — preview affected weeks on add/edit | feature | Show week numbers before saving |
| Budget Rules — absolute mode with baseline_match_key | feature | Phase 2 of spec; requires WD metadata first |
| WD migration — add category/match_key metadata to WD events | feature | Code change only, no model behavior change |
| WD migration — first migration: Kia payment | feature | Lowest risk; isolated, fixed amount |

**Phase 7 (future):**

| Title | Type | Notes |
|---|---|---|
| WD migration — gradual migration by category | feature | Medical → sports → insurance → utilities |
| WD migration — full migration (rent, credit cards last) | feature | Highest risk; rent spans weeks |

---

## Output 3: Updated Phase Mapping

Phases 1–4 are complete as of June 21, 2026 (457 regression tests passing). Budget Rules work begins Phase 5.

| OS Phase | Status | Key Deliverables |
|---|---|---|
| **Phase 1** | Done | App shell, Overview, Weekly Model, Goals, History & Assumptions |
| **Phase 2** | Done | Required actions, Floor panel, Reconciliation drawer, Edit-week, History filters, Supabase live writes, Wishlist UI |
| **Phase 3** | Done | Scenario sandbox, Commission/Expense/Inflow scenarios, Calendar dates on cash flows, Wishlist CRUD, AI Q&A |
| **Phase 4** | Done | Overview redesign, Required action move/update/delete, Override system, IRA/529/AMEX lookahead |
| **Phase 5** | **Active — next** | Budget Rules delta foundation + goal registry enhancements + wishlist UX improvements |
| **Phase 6** | Planned | Budget Rules admin UI + absolute mode + authentication + account connections (OAuth) |
| **Phase 7** | Planned | WD migration to Budget Rules (Kia → categories → rent/cards) + account reconciliation breakdown |

### Budget Rules Feature Mapping to OS Phases

| Budget Rules Work | OS Phase | Spec Reference |
|---|---|---|
| `budget_rules` table + delta engine + audit trail | **Phase 5** | Spec §5, §6, §7, §8, §9 |
| First production rules (rent, medical, baseball) | **Phase 5** | Spec §10 |
| Admin UI with preview | **Phase 6** | Spec §11 |
| Absolute mode + baseline_match_key | **Phase 6** | Spec §4 (blocked in Phase 5) |
| WD metadata (category, match_key) | **Phase 6** | Spec §4 |
| WD migration — Kia first | **Phase 6** | Spec §14 |
| WD migration — full | **Phase 7** | Spec §14 |

---

## Output 4: Implementation + Test Sequence

### Pre-Build Checklist (Required Before First Line of Code)

- [x] Draft 3.1 spec finalized (`budget-rules-spec-v3.1.md`)
- [x] Wishlist reconciliation complete (Output 2 above)
- [x] Phase mapping confirmed (Output 3 above)
- [x] Implementation sequence defined (this document)
- [ ] **Adam approval** ← BLOCKED HERE

### Build Sequence

**Step 1 — Supabase: Create `budget_rules` table**
- Run SQL from spec §5 in Supabase SQL Editor
- Verify table visible in Table Editor
- No code changes yet

**Step 2 — Helpers: Date utilities**
- Add to `index.html` (before `runModel()`):
  - `isValidISODate(str)` — validates ISO date string format
  - `addMonthsToDateStr(dateStr, n)` — integer-math month addition (no `setMonth()` bug)
  - `pinnedMonthlyDateStr(startDateStr, n)` — anchored monthly recurrence (no drift)
- Unit test each function before proceeding

**Step 3 — Helpers: Rule validation**
- Add `validateBudgetRule(rule)` — returns array of error strings
- Must reject: missing required fields, end_date before start_date, absolute mode, amount ≤ 0

**Step 4 — Helpers: Occurrence generation and week mapping**
- Verify existing `dateToModelWeek()` matches spec signature; update if needed
- Add `generateOccurrenceDates(rule)` — returns array of ISO date strings
- Add `buildBudgetRuleContext(rules)` — returns `{ byWeek: {[weekNum]: [...]} }`
  - Must block all absolute-mode rules with ruleAudit entry, never apply or convert them
- Add `applyBudgetRulesForWeek(weekNum, weekRules, tr, ruleAudit)` — returns delta to add to `chk`

**Step 5 — Supabase load**
- Add `var budgetRules = [];` and `var budgetRulesLoadStatus = 'not_configured';` globals
- Add `loadBudgetRules()` to existing `loadData()` function
- On successful fetch (even zero active rules): set status to `'loaded'` — an empty active-rules table is a successful load, not a configuration gap
- On fetch error: set status to `'failed'`
- `'not_configured'` is the initial value only — before any load attempt

**Step 6 — Warning banner**
- Add UI element: visible only when `budgetRulesLoadStatus === 'failed'`
- Text: "Budget Rules could not be loaded. Model shows WD baseline only."

**Step 7 — runModel() integration**
```javascript
// Before week loop:
ruleAudit = [];
const ruleContext = buildBudgetRuleContext(budgetRules);

// Inside week loop, after WD + overrides, before waterfall:
chk += applyBudgetRulesForWeek(num, ruleContext.byWeek[num] || [], tr, ruleAudit);
```

**Step 8 — Regression tests (new section)**

Target: 30–40 focused new tests, 0 failing. All critical paths must be covered. Existing 457 tests must still pass.

Key test cases:

| Test | Assertion |
|---|---|
| `isValidISODate('2026-07-15')` | true |
| `isValidISODate('07/15/2026')` | false |
| `addMonthsToDateStr('2026-01-31', 1)` | `'2026-02-28'` |
| `addMonthsToDateStr('2026-01-31', 2)` | `'2026-03-31'` (no drift) |
| `addMonthsToDateStr('2026-12-31', 1)` | `'2027-01-31'` |
| `pinnedMonthlyDateStr(2026, 10, 15)` | `'2026-10-15'` |
| `pinnedMonthlyDateStr(2026, 2, 31)` | `'2026-02-28'` |
| `generateOccurrenceDates(oneTimeRule)` | Returns exactly 1 date |
| `generateOccurrenceDates(monthlyRule, end)` | Correct count, correct dates |
| `generateOccurrenceDates(weeklyRule)` | 7-day cadence |
| `generateOccurrenceDates(biweeklyRule)` | 14-day cadence |
| `validateBudgetRule({...valid...})` | Empty error array |
| `validateBudgetRule({rule_mode:'absolute'})` | Includes absolute-mode error |
| `validateBudgetRule({end_date before start_date})` | Includes date-order error |
| `buildBudgetRuleContext([absoluteRule])` | byWeek empty; ruleAudit has 1 entry |
| `applyBudgetRulesForWeek(5, [outflowRule], tr, audit)` | Returns negative delta; tr has 1 entry |
| `applyBudgetRulesForWeek(5, [], tr, audit)` | Returns 0; tr unchanged |
| Model integration: `budgetRules = []` | Week 5 chk identical to baseline |
| Model integration: rent increase | Weeks 10–31 each reduced by delta; weeks 1–9 unchanged |
| `budgetRulesLoadStatus` on fetch error | `'failed'` |

**Step 9 — Manual verification**
- Open dashboard, confirm rule-driven entries appear in transfer log with correct dates
- Confirm weeks outside rule date range are unaffected
- Confirm floor violations show correctly if rule pushes chk below OP_FL
- Confirm existing reconciled weeks are unaffected in their reconciliation drawer

**Step 10 — Insert first production rules**
- Rent increase: `{label: 'Rent increase', amount: 200.00, direction: 'outflow', frequency: 'monthly', start_date: '2026-08-01', rule_mode: 'delta'}`
- Medical bill: `{label: 'Medical bill payment', amount: 150.00, direction: 'outflow', frequency: 'monthly', start_date: '2026-07-15', end_date: '2026-12-15', rule_mode: 'delta'}`
- Baseball: `{label: 'Baseball monthly payment', amount: 125.00, direction: 'outflow', frequency: 'monthly', start_date: '2026-07-10', end_date: '2026-10-10', rule_mode: 'delta'}`
- Reload dashboard, verify all three appear in correct weeks

**Step 11 — Full regression run**
```
node test_regression.js
```
Expected: 487+ tests, 0 failing.

**Step 12 — Push to GitHub Pages**
```bash
./push_to_github.sh "Phase 5: Budget Rules delta foundation"
```

### Estimated Scope

| Work | Estimate |
|---|---|
| Supabase table creation | 15 min |
| Helper functions (Steps 2–4) | 2–3 hours |
| Load + integration (Steps 5–7) | 1 hour |
| Tests (Step 8) | 1.5–2 hours |
| Manual verification + production rules (Steps 9–10) | 45 min |
| **Total** | **5–7 hours** |

---

*End of pre-build package. Do not begin Step 1 until Adam approves.*
