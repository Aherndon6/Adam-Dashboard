# Herndon Financial OS — Recurring Adjustments Feature Spec

**Version:** Draft 1.0
**Date:** June 21, 2026
**Purpose:** Architecture review — prepared for independent review by ChatGPT

---

## 1. Problem Statement

The Herndon Financial OS runs a 31-week cash flow model (Cal Wk 23–53, Jun 7, 2026 – Jan 9, 2027). All weekly inflows and bills are currently hard-coded in a JavaScript array (`WD`) inside a single HTML file (`index.html`). There is no mechanism to add or modify recurring expenses without editing the source code directly.

Starting in July 2026, new recurring expenses will be introduced (rent increase, medical bill, baseball monthly payment, and others). These items:
- Start on specific calendar dates
- May be permanent or time-bounded
- Need to appear in the correct model week based on their exact due date
- Must propagate impact through the savings goal waterfall

The goal is to support adding and modifying recurring budget items without touching the source code, using a Supabase-backed configuration table.

---

## 2. Current Architecture (Relevant Context)

### 2.1 Tech Stack

- **Frontend:** Single file — `index.html` — all HTML, CSS, and JS inline. No framework, no build step.
- **Backend:** Supabase (PostgreSQL + REST API).
- **Hosting:** GitHub Pages, auto-deploys on push to main branch.
- **Model:** Pure client-side JavaScript. All projections recomputed on each render.

### 2.2 Existing Supabase Tables

| Table | Purpose |
|---|---|
| `weekly_reconciliations` | Actual end-of-week balances entered by user |
| `model_week_overrides` | Per-week event edits (add/change events for a single week) |
| `weekly_tasks` | Required action completion tracking |
| `weekly_notes` | User notes per week |
| `goals` | Goal registry + key-value config store (IRA flag, API key, etc.) |
| `wishlist_items` | Feature/bug backlog |

### 2.3 The WD Array

The core of the model is a `const WD` array with 31 entries, one per week. Each entry is:

```javascript
[weekNum, dateRange, [inflows], [bills], [events], commTax, commAK, calNote]
```

Example (Week 5, Jul 5–11):
```javascript
[5, 'Jul 5-11', [5816.5], [791], [
  {l: 'Adam paycheck (7/7)', t: 'in', a: 5816.5},
  {l: 'Kia payment (7/7)', t: 'ob', a: -791}
], 0, 0, '']
```

All inflows and bills are literal dollar values. Changing or adding a recurring item means editing every affected week individually.

### 2.4 Existing Override System

`model_week_overrides` allows editing one week at a time — it replaces or augments that week's event list. It does not support "apply this change to all weeks from X onward."

### 2.5 Model Output

`runModel()` returns a 31-week array. Per week:
- `chk` — Truist Checking ending balance
- `goalSaved` — cumulative funded amounts per goal
- `tr` — transfer log (displayed in week detail)
- `ac` — required action checklist
- Floor: `OP_FL = $6,500` — model never pulls checking below this

### 2.6 Test Harness

- `test_regression.js` — 457 tests, 0 failing (as of Jun 18, 2026)
- Run with: `node test_regression.js`

---

## 3. Proposed Solution

### 3.1 Core Concept

Add a new Supabase table (`recurring_adjustments`) that stores budget line items with a start date, optional end date, and frequency. At model runtime, the app:

1. Loads the table from Supabase
2. Expands each row into a list of specific occurrence dates
3. Maps each occurrence to its model week
4. Applies the amounts as additive deltas on top of the existing WD array

The WD array is never modified. All changes are additive overlays.

### 3.2 New Supabase Table: `recurring_adjustments`

```sql
CREATE TABLE recurring_adjustments (
  id            SERIAL PRIMARY KEY,
  label         TEXT NOT NULL,
  amount        NUMERIC(10,2) NOT NULL,
  frequency     TEXT NOT NULL CHECK (frequency IN ('one-time', 'weekly', 'biweekly', 'monthly')),
  start_date    DATE NOT NULL,
  end_date      DATE,
  day_of_month  INT CHECK (day_of_month BETWEEN 1 AND 31),
  notes         TEXT,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);
```

**Field definitions:**

| Field | Description |
|---|---|
| `label` | Display name: "Medical bill", "Rent increase", "Baseball payment" |
| `amount` | Dollar value. **Negative = expense, positive = inflow.** |
| `frequency` | How often it recurs within the date range |
| `start_date` | Date of first occurrence (exact calendar date) |
| `end_date` | Date of last occurrence — null means "through end of model" (Jan 9, 2027) |
| `day_of_month` | For monthly items: pin to this day of month on subsequent months. If null, uses same calendar day as `start_date`. |
| `active` | Toggle without deleting. False = excluded from model. |

**Example rows:**

| label | amount | frequency | start_date | end_date | day_of_month | notes |
|---|---|---|---|---|---|---|
| Rent increase | -200.00 | monthly | 2026-08-01 | null | 1 | $200 delta on top of existing rent |
| Medical bill | -150.00 | monthly | 2026-07-15 | 2026-12-15 | 15 | 6-month payment plan |
| Baseball monthly | -125.00 | monthly | 2026-07-10 | 2026-10-10 | 10 | Fall season |
| Bonus inflow | 1500.00 | one-time | 2026-09-01 | null | null | Referral bonus |

---

## 4. Implementation Design

### 4.1 Date-to-Week Mapping

Model week 1 begins Jun 7, 2026 (Sunday). Each week is 7 days. Model week 31 ends Jan 9, 2027.

```javascript
const MODEL_START_DATE = new Date('2026-06-07T00:00:00');
const MODEL_END_DATE   = new Date('2027-01-09T23:59:59');

function dateToModelWeek(dateStr) {
  const d = new Date(dateStr + 'T12:00:00'); // noon to avoid DST edge cases
  if (d < MODEL_START_DATE || d > MODEL_END_DATE) return null;
  const daysDiff = Math.floor((d - MODEL_START_DATE) / (1000 * 60 * 60 * 24));
  return Math.floor(daysDiff / 7) + 1; // returns 1–31
}
```

### 4.2 Occurrence Date Generation

```javascript
function generateOccurrenceDates(adj) {
  const occurrences = [];
  const endBoundary = adj.end_date
    ? new Date(adj.end_date + 'T12:00:00')
    : MODEL_END_DATE;

  if (adj.frequency === 'one-time') {
    occurrences.push(adj.start_date);
    return occurrences;
  }

  let current = new Date(adj.start_date + 'T12:00:00');
  const pinDay = adj.day_of_month || null;

  while (current <= endBoundary) {
    occurrences.push(current.toISOString().split('T')[0]);

    if (adj.frequency === 'weekly') {
      current = new Date(current);
      current.setDate(current.getDate() + 7);
    } else if (adj.frequency === 'biweekly') {
      current = new Date(current);
      current.setDate(current.getDate() + 14);
    } else if (adj.frequency === 'monthly') {
      current = new Date(current);
      current.setMonth(current.getMonth() + 1);
      if (pinDay) {
        // Clamp to last day of month if pin day exceeds month length
        const lastDay = new Date(current.getFullYear(), current.getMonth() + 1, 0).getDate();
        current.setDate(Math.min(pinDay, lastDay));
      }
    }
  }

  return occurrences;
}
```

### 4.3 Precompute Adjustments by Week

Called once per render cycle, before `runModel()`:

```javascript
function buildAdjustmentsByWeek(adjustments) {
  const byWeek = {}; // { [weekNum]: [{label, amount, dateStr}] }

  for (const adj of adjustments) {
    if (!adj.active) continue;
    const dates = generateOccurrenceDates(adj);
    for (const dateStr of dates) {
      const wk = dateToModelWeek(dateStr);
      if (!wk) continue; // outside model window — skip
      if (!byWeek[wk]) byWeek[wk] = [];
      byWeek[wk].push({ label: adj.label, amount: adj.amount, dateStr });
    }
  }

  return byWeek;
}
```

### 4.4 Integration into runModel()

`runModel()` already has a per-week loop. Two changes:

**Before the loop** (after loading WD and overrides):
```javascript
const adjByWeek = buildAdjustmentsByWeek(recurringAdjustments);
```

**Inside the loop** (after applying WD inflows/bills, before waterfall):
```javascript
const weekAdjs = adjByWeek[num] || [];
for (const adj of weekAdjs) {
  chk += adj.amount; // positive adds to checking, negative subtracts
  tr.push({
    l: adj.label + ' (' + adj.dateStr + ')',
    r: adj.amount >= 0 ? 'in' : 'ob',
    a: adj.amount
  });
}
```

That's it for the model. The waterfall, floor logic, and goal allocation all run on the resulting `chk` value — no changes needed there.

### 4.5 Supabase Data Load

Added to the existing `loadData()` function alongside other table fetches:

```javascript
var recurringAdjustments = [];

async function loadRecurringAdjustments() {
  var r = await fetch(
    SUPA_URL + '/rest/v1/recurring_adjustments?active=eq.true&order=start_date.asc',
    { headers: SUPA_H }
  );
  if (r.ok) recurringAdjustments = await r.json();
}
```

---

## 5. What Changes, What Doesn't

### Changes

| Item | Change |
|---|---|
| Supabase | New table: `recurring_adjustments` |
| `index.html` | ~120 lines added: 3 helper functions + Supabase load + 8-line model integration |
| `test_regression.js` | New section: ~20–25 tests for helper functions and model integration |
| `model_spec.md` | New section documenting the table and integration |

### Does Not Change

| Item | Status |
|---|---|
| `WD` array | Untouched — baseline remains the same |
| All existing 457 regression tests | Still pass — model logic unchanged, only additive |
| `model_week_overrides` system | Untouched |
| All other Supabase tables | Untouched |
| Goal waterfall, floor logic, IRA gate | Untouched |
| Push workflow | Untouched |
| `runModel()` output shape | Untouched — same fields, just different `chk` values and additional `tr` entries |

---

## 6. Edge Cases

| Case | Handling |
|---|---|
| Date before model start (Jun 7) | `dateToModelWeek()` returns null — occurrence silently skipped |
| Date after model end (Jan 9, 2027) | Same — skipped |
| Monthly item on 31st in 30-day month | Clamped to last day of that month |
| `end_date` same day as occurrence | Included (boundary is inclusive) |
| Two adjustments for same label, same week | Both applied independently — additive, intentional |
| `active = false` | Excluded from `buildAdjustmentsByWeek()` — zero model impact |
| Adjustment pushes `chk` below `OP_FL` | Floor violation — same visual treatment as existing thin weeks (red badge) |
| Adjustment affects a reconciled week | Applied on top of actuals — user sees adjustment in transfer log; no conflict |

---

## 7. User Workflow (Config Mode)

Until a UI is built, adjustments are managed directly in Supabase:

1. Go to Supabase project `usayoldrawwmjsmretin` → Table Editor → `recurring_adjustments`
2. Insert a row: fill in label, amount (negative for expense), frequency, start_date, and optionally end_date and day_of_month
3. Reload the OS — the model picks it up immediately on next render

To temporarily disable an item without deleting it: set `active = false`.

---

## 8. Future UI (Phase 6)

When config becomes too burdensome, a "Budget Rules" tab can be added to the OS with:
- List view of all active adjustments
- Add form: label, amount, type (expense/income toggle), frequency, start date, end date, pin day
- Edit and delete/deactivate controls
- Preview: "This rule affects weeks 5, 9, 13, 18, 22, 27" shown on add

No model changes required for the UI phase — all logic already built.

---

## 9. Questions for Reviewer

The following are open questions where a second opinion is valued:

1. **Date handling:** The `day_of_month` pin is used to handle monthly items that should always hit on the same day (e.g., always the 15th). Is there a cleaner schema design that handles this without a separate column?

2. **Negative convention:** Using negative `amount` for expenses keeps the schema simple but requires the user to remember the sign convention. Alternative: separate `type` column ('expense'/'income') with always-positive `amount`. Trade-off: clarity vs. schema simplicity.

3. **Regression test coverage:** With 457 existing tests locked to specific `chk` balances by week, adding adjustments to the live model could cause test failures if adjustments are loaded before tests run. Proposed mitigation: tests run with `recurringAdjustments = []` (empty array, the default). Is there a cleaner pattern?

4. **Rent increase modeling:** The proposed approach adds a delta (e.g., +$200 rent increase) on top of existing rent in WD. This means the WD baseline is preserved. An alternative is to use `model_week_overrides` to replace the rent line items directly. The delta approach is cleaner for the data model but less readable when reviewing a single week — is the trade-off acceptable?

5. **Supabase vs. JSON config file:** The spec uses Supabase for persistence (consistent with all other OS data). An alternative is a `budget-adjustments.json` file committed to the repo. The Supabase approach allows changes without a git push; the JSON approach is more portable. Given the existing architecture is Supabase-first, is the table approach correct?

---

## 10. Implementation Sequence

If approved, implementation order:

1. Create `recurring_adjustments` table in Supabase (SQL in Section 3.2)
2. Add `dateToModelWeek()` and `generateOccurrenceDates()` helpers to `index.html`
3. Add `buildAdjustmentsByWeek()` and Supabase load to `index.html`
4. Integrate into `runModel()` (8 lines)
5. Write regression tests (new Section 29)
6. Insert first real rows: rent increase, medical bill, baseball payment
7. Verify model output visually and via tests
8. Push to GitHub Pages

Estimated scope: 3–4 hours of development, 1–2 hours of testing.

---

*End of spec. For implementation questions, reference `index.html` (4,775 lines), `model_spec.md`, and `test_regression.js` in the `Adam-Dashboard` repo.*
