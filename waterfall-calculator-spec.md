# Herndon Financial OS — Waterfall Calculator Spec
**Version:** 1.0 Draft  
**Date:** June 21, 2026  
**OS Phase:** Phase 5 (next build)  
**Status:** Awaiting ChatGPT review before build

---

## 1. Purpose

The Waterfall Calculator answers one question: **"If I add (or remove) a dollar amount on a given date, what happens to my goals?"**

Budget Rules let you model ongoing adjustments. The Waterfall Calculator shows their downstream impact — and works for any one-time or recurring amount, not just Budget Rules. You enter an amount and a date; the model runs with and without the change and shows the full goal-by-goal delta.

---

## 2. What This Is Not

- Not a replacement for the existing Scenario Builder (which operates on a specific week's events)
- Not a write operation — no saving, no overrides, no Supabase writes (read-only analysis only)
- Not a Budget Rule builder — it does not create rules in the DB
- Not goal CRUD (that is the Dynamic Goal Registry, separate spec)

---

## 3. User Stories

**Primary:**
> "I just added a $750/month baseball rule. I want to see how much it delays my IRA and 529 goals."

**Secondary:**
> "If I get a $3,000 bonus in September, which goals does it accelerate and by how much?"

> "This GLP medicine costs $404/month through December. What does that do to Bailey's 529 ETA?"

> "If I pay an extra $500 toward a goal this month, where does it land in the waterfall?"

---

## 4. Placement

New subsection within the **Goals tab**, below the existing goal cards. Tab label: **"What-If Calculator"** (reuses the existing goals tab infrastructure; no new nav item needed).

Alternatively a button on the Overview page: **"Run impact analysis"** — opens as a drawer. Recommended: Goals tab subsection to keep it discoverable without cluttering Overview.

---

## 5. Inputs

| Field | Type | Notes |
|---|---|---|
| Label | Text | Optional. Default: "What-if entry" |
| Amount | Dollar | Required. Positive number. |
| Direction | Toggle | Inflow / Outflow |
| Date | Date picker | ISO date. Converted to model week via `dateToModelWeek()` |
| Recurrence | Select | One-time / Monthly / Weekly / Biweekly |
| End date | Date picker | Optional. Only shown for recurring entries. |

If the entered date falls outside the WD window (Jun 7, 2026 – Jan 9, 2027), show a validation message: "Date is outside the model window. No weeks affected."

---

## 6. Calculation Engine

No new model infrastructure needed. The calculator:

1. Runs `runModel(ak, rt)` — baseline (current state, Budget Rules active)
2. Constructs a temporary in-memory `whatIfRules` array from the inputs, using the same `generateOccurrenceDates()` + `buildBudgetRuleContext()` pipeline already built for Budget Rules
3. Appends `whatIfRules` to `budgetRules`, re-runs `runModel()` — scenario
4. Diffs the two outputs

**Critical:** The what-if entries are never written to Supabase. They exist only in the function scope for the duration of the calculation.

```javascript
// Pseudocode — actual implementation
function runWhatIf(entry) {
  var g = getGoals();
  var baseline = runModel(g.ak, g.rt);

  var savedRules = budgetRules.slice();
  budgetRules = budgetRules.concat(buildWhatIfRule(entry));
  var scenario = runModel(g.ak, g.rt);
  budgetRules = savedRules;  // always restore

  return diffModels(baseline, scenario);
}
```

---

## 7. Output: Goal Impact Table

For each active (non-complete) goal, show:

| Goal | Baseline ETA | Scenario ETA | Shift | Funded % (baseline) | Funded % (scenario) |
|---|---|---|---|---|---|
| Alaska Cruise | Jul 5-11 (Wk 5) | Jul 5-11 (Wk 5) | None | 100% | 100% |
| Adam IRA | Wk 18 | Wk 19 | +1 week | 52% | 48% |
| Bailey 529 | Wk 24 | Wk 26 | +2 weeks | 0% | 0% |

**ETA definition:** The model week in which `goalSaved[id] >= target`. If not completed within the model window, show "Beyond model" for both columns.

**Shift color coding:**
- No change → neutral
- Scenario faster (inflow) → green
- Scenario slower (outflow) → amber/red based on weeks delayed

---

## 8. Output: Week-by-Week Checking Delta

A small bar/line chart showing the checking balance delta (scenario minus baseline) for each of the 31 model weeks. Weeks where the entry fires are marked. This lets Adam see the cash impact shape — a one-time hit vs. a monthly drain have very different profiles.

Optional for v1; required for v2. Flag as deferred if it adds significant build time.

---

## 9. Output: Summary Line

Above the table, a single-sentence summary:

- **Outflow:** "This outflow reduces total goal contributions by **$X** and delays your first impacted goal by **N weeks**."
- **Inflow:** "This inflow adds **$X** to goal contributions and accelerates **[goal name]** by **N weeks**."
- **No impact:** "No active goals are affected — the amount is absorbed into the operating floor buffer."

---

## 10. Edge Cases

| Case | Behavior |
|---|---|
| Entry lands in a week with a model_week_override | Apply same bypass rule as Budget Rules — what-if entry is bypassed for that week |
| Entry amount exceeds checking surplus | Model absorbs what it can; floor blocks the rest. Show "floor-limited" note. |
| Entry pushes checking below OP_FL ($6,500) | Show warning: "⚠️ This entry causes checking to fall below the $6,500 floor in Wk N." |
| Date outside model window | Validation error before running calculation |
| Multiple what-if entries | V1: single entry only. V2: stacking multiple entries (e.g., model two Budget Rules simultaneously). |

---

## 11. State Management

- What-if inputs do not persist between sessions (no localStorage, no Supabase)
- On tab switch, inputs reset
- "Clear" button resets all fields
- No auto-run — user clicks "Calculate" to trigger

---

## 12. Test Plan

**Regression tests (new section WC-A through WC-D in `test_regression.js`):**

| Test | Assertion |
|---|---|
| WC-A1: Baseline equals current model | `runWhatIf` with zero-amount entry produces no delta |
| WC-A2: Outflow reduces goal funded amount | $750 outflow in Wk 5 reduces downstream goalSaved |
| WC-A3: Inflow increases goal funded amount | $1,000 inflow in Wk 5 increases goalSaved for open goal |
| WC-A4: Entry outside model window produces no delta | Date 2027-06-01 → no affected weeks |
| WC-B1: Floor-limited outflow does not go negative | Outflow larger than surplus → checking floored, not negative |
| WC-B2: Override week bypasses what-if entry | Entry in overridden week → no delta for that week |
| WC-C1: ETA shift computed correctly | Known scenario: $X outflow in Wk N shifts goal ETA by expected weeks |
| WC-C2: Summary line reflects correct direction | Outflow → delay language, inflow → accelerate language |
| WC-D1: budgetRules restored after runWhatIf | Rule count before and after calculation is identical |

**Playwright e2e (new Section WC):**

| Test | Assertion |
|---|---|
| WC-1: Calculator renders in Goals tab | What-If Calculator section visible |
| WC-2: Outflow entry produces goal delay | Enter $750 outflow, click Calculate, verify at least one goal shows positive week shift |
| WC-3: Inflow entry produces goal acceleration | Enter $1,000 inflow, verify at least one goal shows negative (earlier) week shift |
| WC-4: Clear resets all fields | Click Clear, all inputs empty |
| WC-5: Date outside window shows validation message | Enter 2027-06-01, verify error message |

---

## 13. Out of Scope (Phase 5)

- Saving what-if scenarios to Supabase
- Stacking multiple what-if entries simultaneously
- Week-by-week chart (deferred to v2 unless low effort)
- Comparing what-if against a Budget Rule already in the DB (nice to have; requires UI to select existing rules)

---

## 14. Implementation Sequence

1. Add `runWhatIf(entry)` helper function — wraps model diff logic
2. Add `diffModels(baseline, scenario)` — returns goal ETA comparison object
3. Add UI panel in Goals tab (input form + results table)
4. Write regression tests (Section WC)
5. Write Playwright e2e tests (Section WC)
6. Run full suite, push

**Estimated scope:** 4–6 hours. No new Supabase tables. No schema changes. Pure JS + UI.

---

*Do not build until ChatGPT review is complete and Adam approves.*
