# Herndon Financial OS — Budget Rules Feature Spec

**Version:** Draft 3.1
**Date:** June 21, 2026
**Purpose:** Final pre-build architecture review — revised per ChatGPT feedback on Draft 3.0

---

## 1. Problem Statement

The Herndon Financial OS runs a 31-week cash flow model (Cal Wk 23–53, Jun 7, 2026 – Jan 9, 2027). All weekly inflows and bills are currently hard-coded in a JavaScript array (`WD`) inside a single HTML file (`index.html`). There is no mechanism to add or modify recurring expenses without editing source code directly.

Starting in July 2026, new recurring expenses will be introduced (rent increase, medical bill, baseball monthly payment, and others). The goal is not simply to patch these in — it is to establish a configurable **Budget Rules** layer that becomes the long-term foundation for how financial obligations and inflows are modeled, with WD eventually becoming generated seed data rather than permanent source of truth.

**Phase 1 (OS Phase 5) scope:** Delta-mode rules only. Absolute mode is schema-ready but explicitly blocked at runtime. Budget Rules logic is modular and isolated from `runModel()` internals.

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
| `model_week_overrides` | Per-week event edits (replaces/augments a single week's events) |
| `weekly_tasks` | Required action completion tracking |
| `weekly_notes` | User notes per week |
| `goals` | Goal registry + key-value config store |
| `wishlist_items` | Feature/bug backlog |

### 2.3 The WD Array

The core of the model is a `const WD` array with 31 entries, one per week. Each entry is:

```javascript
[weekNum, dateRange, [inflows], [bills], [events], commTax, commAK, calNote]
```

WD is the current baseline source of truth. Long-term, WD becomes generated seed data as Budget Rules matures and absolute-mode rules replace WD entries category by category.

### 2.4 Model Output

`runModel()` returns a 31-week array. Per week:
- `chk` — Truist Checking ending balance
- `goalSaved` — cumulative funded amounts per goal
- `tr` — transfer log (user-facing; stays clean — no skipped or suppressed rule entries)
- `ac` — required action checklist
- Floor: `OP_FL = $6,500`

### 2.5 Test Harness

- `test_regression.js` — 457 tests, 0 failing (as of Jun 18, 2026)
- Run with: `node test_regression.js`

---

## 3. Source-of-Truth Precedence Hierarchy

### Phase 1 / OS Phase 5 (this implementation)

| Priority | Layer | Behavior |
|---|---|---|
| 1 (highest) | `weekly_reconciliations` | Actuals replace projected ending balances as the cascade anchor for subsequent weeks. Budget Rules still render in the modeled week for planned-vs-actual visibility. Budget Rules are not modified by reconciliation. |
| 2 | `model_week_overrides` | If set for a specific week, replaces that week's event set entirely. Budget Rules are bypassed for that week only. Bypassed rules are logged to `ruleAudit`, not to `tr`. |
| 3 | `budget_rules` (delta mode only) | Applies additively on top of WD baseline. Applied after WD inflows/bills, before waterfall. |
| 4 (lowest) | `WD` array | Baseline seed data. Used as-is unless a higher-priority layer is active. |
| — | `budget_rules` (absolute mode) | **Blocked in Phase 1 / OS Phase 5.** Active absolute rules are skipped, not applied, not converted to delta, and logged to `ruleAudit` only. No `chk` impact. No `tr` entry. |

### Phase 2 / OS Phase 6–7 (future — not implemented here)

| Priority | Layer | Behavior |
|---|---|---|
| 1 | `weekly_reconciliations` | Same as Phase 1. |
| 2 | `model_week_overrides` | Same as Phase 1 — override wins for that specific week even if an absolute rule is active. |
| 3 | `budget_rules` (absolute mode) | Suppresses the matching WD entry identified by `category` + `baseline_match_key`. Absolute rule amount replaces the suppressed WD obligation. Both `category` and `baseline_match_key` are required for absolute rules. |
| 4 | `budget_rules` (delta mode) | Same as Phase 1. |
| 5 (lowest) | `WD` | Entries matching an active absolute rule's `category` + `baseline_match_key` are suppressed. All other WD entries apply normally. |

### Key invariants (both phases)

- Absolute rules never silently behave as delta. If Phase 2 suppression is not implemented, absolute rules are blocked entirely.
- Reconciliation does not modify Budget Rules. Reconciled actuals replace projected ending balances as the cascade anchor for subsequent weeks. Budget Rules still render in the modeled week for planned-vs-actual visibility.
- `tr` stays clean and user-facing. Skipped, suppressed, and blocked rules never appear in `tr`.
- `ruleAudit` is the diagnostic trail. All non-applied rule activity is logged there.

---

## 4. New Supabase Table: `budget_rules`

```sql
CREATE TABLE budget_rules (
  id                  SERIAL PRIMARY KEY,
  label               TEXT NOT NULL,
  amount              NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  direction           TEXT NOT NULL CHECK (direction IN ('inflow', 'outflow')),
  rule_mode           TEXT NOT NULL DEFAULT 'delta' CHECK (rule_mode IN ('delta', 'absolute')),
  category            TEXT,
  baseline_match_key  TEXT,
  frequency           TEXT NOT NULL CHECK (frequency IN ('one-time', 'weekly', 'biweekly', 'monthly')),
  start_date          DATE NOT NULL,
  end_date            DATE CHECK (end_date IS NULL OR end_date >= start_date),
  day_of_month        INT CHECK (day_of_month BETWEEN 1 AND 31),
  applies_to          TEXT,
  notes               TEXT,
  active              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER budget_rules_updated_at
BEFORE UPDATE ON budget_rules
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

### Field Definitions

| Field | Description |
|---|---|
| `label` | Display name: "Rent increase", "Medical bill", "Baseball payment" |
| `amount` | Always positive. Direction controlled by `direction`. |
| `direction` | `inflow` adds to checking; `outflow` subtracts. |
| `rule_mode` | `delta` = additive overlay (Phase 1 supported). `absolute` = replaces WD entry (Phase 2 only — blocked in Phase 1). |
| `category` | Semantic grouping. See approved values below. Required for absolute rules in Phase 2. |
| `baseline_match_key` | Precise key identifying which WD event to suppress in absolute mode. Example: `kia_payment`. Required alongside `category` for absolute rules in Phase 2. |
| `frequency` | `one-time`, `weekly`, `biweekly`, `monthly`. |
| `start_date` | Exact calendar date of first occurrence. Must be ISO `YYYY-MM-DD`. |
| `end_date` | Last occurrence (inclusive). Null = runs through end of model. Must be ISO `YYYY-MM-DD`. Database enforces `end_date >= start_date`. |
| `day_of_month` | For monthly rules: pin subsequent occurrences to this calendar day, clamped to last day of month. Null = use same day as `start_date`. |
| `applies_to` | Target account tag. See approved values below. |
| `active` | False = excluded from model entirely. |
| `updated_at` | Auto-updated on every row change. |

### Approved Category and Applies-To Constants

Not enforced by SQL CHECK — enforced by documentation and code-level warning. Add to both the spec and the JS constants block when expanding.

```javascript
const BUDGET_RULE_CATEGORIES = [
  'income','rent','auto','medical','sports','credit_card',
  'tax','savings','travel','education','insurance','utilities','other'
];

const BUDGET_RULE_APPLIES_TO = [
  'truist_checking','vio_tax','lending_club_ef','fidelity','amex_savings'
];
```

### Example Rows

| label | amount | direction | rule_mode | category | baseline_match_key | frequency | start_date | end_date | day_of_month |
|---|---|---|---|---|---|---|---|---|---|
| Rent increase | 200.00 | outflow | delta | rent | null | monthly | 2026-08-01 | null | 1 |
| Medical bill | 150.00 | outflow | delta | medical | null | monthly | 2026-07-15 | 2026-12-15 | 15 |
| Baseball monthly | 125.00 | outflow | delta | sports | null | monthly | 2026-07-10 | 2026-10-10 | 10 |
| Bonus inflow | 1500.00 | inflow | delta | income | null | one-time | 2026-09-01 | null | null |
| Kia (Phase 2 example only) | 791.00 | outflow | absolute | auto | kia_payment | monthly | 2027-02-01 | null | 7 |

---

## 5. Implementation Design

All Budget Rules logic lives in isolated helper functions. `runModel()` consumes prepared context — it does not own validation, occurrence generation, or audit logic.

### 5.1 Module Structure

```
isValidISODate(str)
validateBudgetRule(rule)
addMonthsToDateStr(dateStr, n)
pinnedMonthlyDateStr(year, month, pinDay)
dateToModelWeek(dateStr)
generateOccurrenceDates(rule)
buildBudgetRuleContext(rules)      → { byWeek, loadStatus }
applyBudgetRulesForWeek(weekNum, weekRules, tr, ruleAudit)  → chkDelta
```

`runModel()` calls `buildBudgetRuleContext()` once before the week loop and `applyBudgetRulesForWeek()` inside the week loop. Nothing else from this module leaks into `runModel()`.

### 5.2 Load Failure Handling

```javascript
var budgetRules = [];
var budgetRulesLoadStatus = 'not_configured'; // 'loaded' | 'failed' | 'not_configured'

async function loadBudgetRules() {
  try {
    var r = await fetch(
      SUPA_URL + '/rest/v1/budget_rules?active=eq.true&order=start_date.asc',
      { headers: SUPA_H }
    );
    if (r.ok) {
      budgetRules = await r.json();
      budgetRulesLoadStatus = 'loaded';
    } else {
      budgetRulesLoadStatus = 'failed';
      console.warn('[BudgetRules] Load failed: HTTP ' + r.status);
    }
  } catch (e) {
    budgetRulesLoadStatus = 'failed';
    console.warn('[BudgetRules] Load error:', e);
  }
}
```

When `budgetRulesLoadStatus === 'failed'`, a visible warning renders in the OS UI:

> "Budget Rules failed to load. Model is running from WD baseline only."

The model continues normally from WD. It does not throw or stall.

### 5.3 Date Validation

All date strings must be ISO `YYYY-MM-DD`. No timestamps. No `MM/DD/YYYY`. String comparison (`current <= endBoundary`) is safe only when this is guaranteed.

```javascript
function isValidISODate(str) {
  if (typeof str !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(str)) return false;
  const [y, m, d] = str.split('-').map(Number);
  const dt = new Date(y, m - 1, d);
  return dt.getFullYear() === y && dt.getMonth() === m - 1 && dt.getDate() === d;
}
```

### 5.4 Rule Validation

```javascript
function validateBudgetRule(rule) {
  const errors = [];
  if (typeof rule.amount !== 'number' || rule.amount <= 0)
    errors.push('amount must be numeric and > 0');
  if (!['inflow', 'outflow'].includes(rule.direction))
    errors.push('direction must be inflow or outflow');
  if (!['one-time', 'weekly', 'biweekly', 'monthly'].includes(rule.frequency))
    errors.push('unsupported frequency: ' + rule.frequency);
  if (!isValidISODate(rule.start_date))
    errors.push('start_date must be valid YYYY-MM-DD');
  if (rule.end_date !== null && rule.end_date !== undefined) {
    if (!isValidISODate(rule.end_date))
      errors.push('end_date must be valid YYYY-MM-DD');
    else if (rule.end_date < rule.start_date)
      errors.push('end_date must not be before start_date');
  }
  if (rule.rule_mode === 'absolute')
    errors.push('PHASE1_ABSOLUTE_BLOCKED: absolute mode not supported in Phase 1 / OS Phase 5');
  return errors;
}
```

### 5.5 Safe Monthly Date Arithmetic

**Do not use `setMonth()`.** It advances past short months without clamping (Jan 31 + 1 month = March 3). Operate on integer year/month/day components.

Monthly recurrence is always anchored to the original `start_date` day, not the prior occurrence. This produces correct behavior for short-month clamping:

```
Jan 31 → Feb 28 → Mar 31 → Apr 30 → May 31   ✓
```

Not the incorrect drift behavior:

```
Jan 31 → Feb 28 → Mar 28 → Apr 28             ✗
```

```javascript
function addMonthsToDateStr(dateStr, n) {
  // Always anchored to original dateStr day to prevent drift
  const [y, m, d] = dateStr.split('-').map(Number);
  const totalMonths = (y * 12 + (m - 1)) + n;
  const newYear  = Math.floor(totalMonths / 12);
  const newMonth = (totalMonths % 12) + 1; // 1-indexed
  const lastDay  = new Date(newYear, newMonth, 0).getDate();
  const clampedDay = Math.min(d, lastDay);
  return newYear + '-'
    + String(newMonth).padStart(2, '0') + '-'
    + String(clampedDay).padStart(2, '0');
}

function pinnedMonthlyDateStr(year, month, pinDay) {
  // Always clamp pinDay to last day of target month
  const lastDay = new Date(year, month, 0).getDate();
  return year + '-'
    + String(month).padStart(2, '0') + '-'
    + String(Math.min(pinDay, lastDay)).padStart(2, '0');
}
```

Edge cases handled:
- Jan 31 + 1 → Feb 28 (non-leap) / Feb 29 (leap)
- Aug 31 + 1 → Sep 30
- Feb 29 (leap) + 12 → Feb 28 (non-leap)
- `day_of_month = 31` in April → Apr 30

### 5.6 Date-to-Week Mapping

```javascript
const MODEL_START_DATE = new Date(2026, 5, 7, 12, 0, 0);   // Jun 7, 2026
const MODEL_END_DATE   = new Date(2027, 0, 9, 12, 0, 0);   // Jan 9, 2027

function dateToModelWeek(dateStr) {
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(y, m - 1, d, 12, 0, 0);
  if (dt < MODEL_START_DATE || dt > MODEL_END_DATE) return null;
  const daysDiff = Math.floor((dt - MODEL_START_DATE) / 86400000);
  return Math.floor(daysDiff / 7) + 1; // 1–31
}
```

### 5.7 Occurrence Date Generation

```javascript
function generateOccurrenceDates(rule) {
  const endBoundary = (rule.end_date && isValidISODate(rule.end_date))
    ? rule.end_date : '2027-01-09';
  const occurrences = [];

  if (rule.frequency === 'one-time') {
    if (rule.start_date <= endBoundary) occurrences.push(rule.start_date);
    return occurrences;
  }

  let current = rule.start_date;
  const pinDay = rule.day_of_month || null;
  let monthCount = 0;

  while (current <= endBoundary) {
    occurrences.push(current);

    if (rule.frequency === 'weekly') {
      const [y, m, d] = current.split('-').map(Number);
      const next = new Date(y, m - 1, d + 7, 12);
      current = next.getFullYear() + '-'
        + String(next.getMonth() + 1).padStart(2, '0') + '-'
        + String(next.getDate()).padStart(2, '0');
    } else if (rule.frequency === 'biweekly') {
      const [y, m, d] = current.split('-').map(Number);
      const next = new Date(y, m - 1, d + 14, 12);
      current = next.getFullYear() + '-'
        + String(next.getMonth() + 1).padStart(2, '0') + '-'
        + String(next.getDate()).padStart(2, '0');
    } else if (rule.frequency === 'monthly') {
      monthCount++;
      if (pinDay) {
        // Pin to explicit day — always derived from start_date's year/month + n months
        const base = addMonthsToDateStr(rule.start_date, monthCount);
        const [y, m] = base.split('-').map(Number);
        current = pinnedMonthlyDateStr(y, m, pinDay);
      } else {
        // Anchor to start_date's original day — no drift
        current = addMonthsToDateStr(rule.start_date, monthCount);
      }
    }
  }

  return occurrences;
}
```

### 5.8 Build Budget Rule Context

```javascript
var ruleAudit = []; // reset at start of each runModel() call

function buildBudgetRuleContext(rules) {
  const byWeek = {}; // { weekNum: [ruleOccurrence, ...] }

  for (const rule of rules) {
    if (!rule.active) continue;

    const errors = validateBudgetRule(rule);
    if (errors.length > 0) {
      const action = errors.some(e => e.startsWith('PHASE1_ABSOLUTE_BLOCKED'))
        ? 'skipped_unsupported_absolute_phase1'
        : 'skipped_validation_error';
      console.warn('[BudgetRules] Rule skipped — id:', rule.id, rule.label, errors);
      ruleAudit.push({ rule_id: rule.id, label: rule.label, mode: rule.rule_mode, action, errors });
      continue;
    }

    const dates = generateOccurrenceDates(rule);
    for (const dateStr of dates) {
      const wk = dateToModelWeek(dateStr);
      if (!wk) continue;
      if (!byWeek[wk]) byWeek[wk] = [];
      byWeek[wk].push({
        id:                 rule.id,
        label:              rule.label,
        amount:             rule.amount,
        direction:          rule.direction,
        rule_mode:          rule.rule_mode,
        category:           rule.category,
        baseline_match_key: rule.baseline_match_key,
        dateStr
      });
    }
  }

  return { byWeek };
}
```

### 5.9 Apply Budget Rules for Week

```javascript
function applyBudgetRulesForWeek(weekNum, weekRules, tr, ruleAudit) {
  // Returns chkDelta — caller adds this to chk
  // Phase 1: only delta rules reach this function (absolute blocked in buildBudgetRuleContext)
  let chkDelta = 0;
  for (const r of weekRules) {
    const signed = r.direction === 'inflow' ? r.amount : -r.amount;
    chkDelta += signed;

    // User-facing transfer log — applied rules only, clean
    tr.push({
      l: r.label + ' (' + r.dateStr + ') [budget rule]',
      r: r.direction === 'inflow' ? 'in' : 'ob',
      a: signed
    });

    // Diagnostic audit trail
    ruleAudit.push({
      week:      weekNum,
      rule_id:   r.id,
      label:     r.label,
      date:      r.dateStr,
      mode:      r.rule_mode,
      direction: r.direction,
      amount:    signed,
      action:    'applied'
    });
  }
  return chkDelta;
}
```

### 5.10 Integration into runModel()

`runModel()` consumes the prepared context. It does not own any Budget Rules logic.

```javascript
// Before week loop:
ruleAudit = [];
const ruleContext = buildBudgetRuleContext(budgetRules);

// Inside week loop, after WD inflows/bills, before waterfall:
chk += applyBudgetRulesForWeek(num, ruleContext.byWeek[num] || [], tr, ruleAudit);
```

---

## 6. Phase 1 Absolute Mode Guardrail — Exact Behavior

Active rules with `rule_mode = 'absolute'` in Phase 1 / OS Phase 5:

| Behavior | Phase 1 |
|---|---|
| `chk` impact | None |
| `tr` entry | None |
| `ruleAudit` entry | Yes — `action: 'skipped_unsupported_absolute_phase1'` |
| Silent conversion to delta | Never |
| Double-counting risk | None |
| `console.warn` | Yes |

This is enforced in `buildBudgetRuleContext()`, before any week-level processing.

---

## 7. Audit Trail

`ruleAudit` is a module-level array, reset at the top of each `runModel()` call. Not persisted to Supabase in Phase 1. Available in browser console for debugging.

**Logged actions:**

| action | When |
|---|---|
| `applied` | Delta rule applied to model |
| `skipped_unsupported_absolute_phase1` | Absolute rule blocked |
| `skipped_validation_error` | Rule failed field validation |

**Not logged (by design):**
- `active = false` rules — excluded before context is built
- Occurrences outside model window — silently skipped by `dateToModelWeek` returning null

**Future Phase 2 additions:**
- `suppressed_by_override` — rule occurrence in a week where `model_week_override` is active
- `applied_absolute_suppressed_wd` — absolute rule applied, WD entry suppressed

`tr` stays clean at all times. Only applied delta rules appear there.

---

## 8. What Changes, What Doesn't

### Changes

| Item | Change |
|---|---|
| Supabase | New table: `budget_rules` |
| `index.html` | ~220 lines added: 8 helper functions + load handling + model integration |
| `test_regression.js` | New section: 30–40 focused tests |
| `model_spec.md` | New section: table, precedence hierarchy, migration roadmap |

### Does Not Change

| Item | Status |
|---|---|
| `WD` array | Untouched |
| `model_week_overrides` system | Untouched |
| All other Supabase tables | Untouched |
| Goal waterfall, floor logic, IRA gate | Untouched |
| Push workflow | Untouched |
| `runModel()` output shape | Same fields |

---

## 9. Test Plan

**Critical language:** Existing 457 regression tests must pass when `budgetRules = []` or when budget rules are mocked as empty/inactive. New tests validate active rule impact separately and do not rely on existing balance assertions.

### Section A — Baseline equivalence

- `budgetRules = []`: all 31 weeks produce identical `chk` values to current model
- All rules `active = false`: identical output to empty rules
- `budgetRulesLoadStatus = 'failed'`: model runs from WD baseline, visible warning state set
- `ruleAudit` is empty when no rules processed

### Section B — `isValidISODate()`

- `'2026-07-15'` → true
- `'2027-01-09'` → true
- `'07/15/2026'` → false
- `'2026-7-5'` → false
- `'2026-02-30'` → false
- `'2026-07-15T00:00:00'` → false
- Non-string → false

### Section C — `validateBudgetRule()`

- Valid delta rule → no errors
- `amount = 0` → error
- `amount = -50` → error
- `direction = 'sideways'` → error
- `frequency = 'quarterly'` → error
- `start_date = '07/15/2026'` → error
- `end_date` before `start_date` → error
- `rule_mode = 'absolute'` → PHASE1_ABSOLUTE_BLOCKED error
- Valid rule with all optional fields null/undefined → no errors

### Section D — `dateToModelWeek()`

- Jun 7, 2026 → 1
- Jun 13, 2026 → 1
- Jun 14, 2026 → 2
- Jan 9, 2027 → 31
- Jun 6, 2026 → null
- Jan 10, 2027 → null
- Jul 7 (Kia payment) → week 5
- Aug 15 → week 10
- Dec 17 → week 28

### Section E — `addMonthsToDateStr()` — edge cases and drift prevention

- Jan 31 + 1 → Feb 28 (2026, non-leap)
- Jan 31 + 1 → Feb 29 (2028, leap)
- Jan 29 + 1 → Feb 28 (2026, non-leap)
- Aug 31 + 1 → Sep 30
- Sep 30 + 1 → Oct 30
- Dec 31 + 1 → Jan 31 (next year)
- Feb 29 (leap) + 12 → Feb 28 (non-leap)
- **Anchor test:** Jan 31, +1=Feb 28, +2=Mar 31, +3=Apr 30, +4=May 31 (no drift from Feb clamp)

### Section F — `pinnedMonthlyDateStr()`

- pin 31 in April → Apr 30
- pin 31 in Feb (non-leap) → Feb 28
- pin 31 in Feb (leap) → Feb 29
- pin 15 in any month → always the 15th
- pin 1 in any month → always the 1st

### Section G — `generateOccurrenceDates()`

- One-time: exactly 1 date
- Weekly: 7-day interval, correct count within window
- Biweekly: 14-day interval, correct count
- Monthly no pin: original day preserved with clamping, no drift
- Monthly with pin: all occurrences on pin day or last day of month
- `end_date` = exact occurrence date: included (inclusive)
- `start_date` before model start: `dateToModelWeek` returns null → excluded from context
- `end_date` after model end: occurrences past Jan 9 excluded

### Section H — `buildBudgetRuleContext()`

- `active = false` rule: excluded, no `ruleAudit` entry
- Valid delta rule: appears in correct weeks
- Single rule, 3 occurrences: appears in correct 3 weeks with `rule.id` preserved
- Two delta rules same week: both in week array, `rule.id` distinct
- Three stacked rules: all three present
- Occurrence outside window: not in output
- Absolute rule: in `ruleAudit` as `skipped_unsupported_absolute_phase1`, not in `byWeek`
- Validation-error rule: in `ruleAudit` as `skipped_validation_error`, not in `byWeek`

### Section I — Absolute mode Phase 1 guardrail

- Active absolute rule: `chk` unchanged
- Active absolute rule: not in `tr`
- Active absolute rule: `ruleAudit` entry with `action: 'skipped_unsupported_absolute_phase1'`
- Active absolute rule alongside active delta rule: delta applies, absolute blocked
- Active absolute rule: `console.warn` issued
- Inactive absolute rule: nothing in `ruleAudit`
- Absolute rule does not behave as delta under any condition

### Section J — `applyBudgetRulesForWeek()`

- `direction = outflow`: `chkDelta` is negative
- `direction = inflow`: `chkDelta` is positive
- Rule appears in `tr` with correct label, date, direction
- `ruleAudit` entry has correct `rule_id`, `label`, `date`, `mode`, `direction`, `amount`, `action: applied`
- Two stacked rules: `chkDelta` is sum of both; both in `tr` and `ruleAudit`
- Empty week rules: returns 0 delta, nothing in `tr` or `ruleAudit`

### Section K — Load failure

- `budgetRulesLoadStatus = 'failed'`: `budgetRules` stays empty, model runs from WD only
- `budgetRulesLoadStatus = 'failed'`: visible warning state renders
- `budgetRulesLoadStatus = 'loaded'` with 0 active rules: same as baseline

### Section L — Regression guard

- Full 457-test suite passes with `budgetRules = []`
- Full 457-test suite passes with 3 active delta rules on isolated weeks not covered by existing balance assertions

Total target: **30–40 focused tests** across new section. All critical paths above must be covered; not all combinations need exhaustive enumeration.

---

## 10. User Workflow (Config Mode)

1. Go to Supabase project `usayoldrawwmjsmretin` → Table Editor → `budget_rules`
2. Insert a row: `label`, `amount` (always positive), `direction` (inflow/outflow), `rule_mode` (delta only), `category` (from approved list), `frequency`, `start_date`, optionally `end_date` and `day_of_month`
3. Reload the OS — model picks it up immediately

To disable without deleting: set `active = false`.

Do not insert `rule_mode = absolute` rows until Phase 2 is implemented. They will be blocked and logged, but their presence creates audit noise.

---

## 11. WD Migration Roadmap

| Phase | OS Phase | Action |
|---|---|---|
| Budget Rules foundation | **OS Phase 5 (this build)** | Delta-mode rules. WD unchanged. New recurring expenses as delta rules. |
| WD metadata | **OS Phase 6** | Add `category` and `match_key` to WD event objects. Code change only — no model behavior change. |
| Absolute mode implementation | **OS Phase 6** | Implement `buildBudgetRuleContext` absolute suppression using `category` + `baseline_match_key`. |
| First absolute migration | **OS Phase 6** | Migrate **Kia payment** (`category: auto`, `baseline_match_key: kia_payment`). One payment, fixed amount ($791), fixed day (7th), monthly. Lowest risk. |
| Gradual migration | **OS Phase 7** | Migrate by category: medical → sports → insurance → utilities. |
| Full migration | **OS Phase 7** | Rent and credit cards last — highest impact, most complex (rent splits across weeks). |
| WD as legacy fallback | **OS Phase 7+** | WD becomes generated seed data or legacy reference. Budget Rules is the primary model input. |

**Do not migrate rent in OS Phase 5.** Rent is $2,000 + $2,000 + $1,300 across three Zelle transfers, sometimes split across two calendar weeks. Highest-risk WD entry to suppress.

---

## 12. Future Budget Rules UI (OS Phase 6)

Schema is designed to support this screen with no model changes required:

- List of all rules, sortable by category, frequency, start date, active status
- Add/edit form: label, amount, direction toggle, rule_mode toggle (delta/absolute), category dropdown, frequency, start/end dates, day_of_month pin, applies_to, notes
- Active toggle per rule
- Preview: "This rule affects weeks 5, 9, 13, 18, 22, 27" — computed from `generateOccurrenceDates()` + `dateToModelWeek()`
- Impact estimate: "Reduces goal funding by ~$X over model horizon"
- Audit log viewer per rule

---

## 13. Open Questions for Reviewer

1. **`ruleAudit` persistence:** Phase 1 keeps audit in memory only. Should it eventually write to Supabase for long-term model explainability?

2. **Validation warnings vs hard blocks:** Currently any validation error fully skips the rule. Should unrecognized `category` values warn but still apply?

3. **`model_week_override` + active rule (Phase 2):** Override wins for that week. Should suppressed rules appear in `ruleAudit` as `suppressed_by_override`?

4. **Phase 2 WD metadata timing:** Adding `category` and `match_key` to all 31 WD entries requires updating the array and regression tests. Should this be a tracked wishlist item now?

---

## 14. Implementation Sequence (OS Phase 5)

1. Create `budget_rules` table in Supabase (SQL in Section 4)
2. Add constants: `BUDGET_RULE_CATEGORIES`, `BUDGET_RULE_APPLIES_TO`
3. Add helpers: `isValidISODate()`, `validateBudgetRule()`
4. Add date helpers: `addMonthsToDateStr()`, `pinnedMonthlyDateStr()`, `dateToModelWeek()`, `generateOccurrenceDates()`
5. Add `buildBudgetRuleContext()` and `applyBudgetRulesForWeek()`
6. Add `loadBudgetRules()` with load-failure handling; call in `loadData()`
7. Add `budgetRulesLoadStatus` warning render to UI
8. Wire `runModel()` to consume `buildBudgetRuleContext()` and `applyBudgetRulesForWeek()` (~5 lines)
9. Write regression tests — baseline equivalence and absolute guardrail first
10. Insert first production rows: rent increase, medical bill, baseball payment (all delta)
11. Run full test suite: all 457 existing + new section must pass
12. Verify model output visually at dashboard.herndons.us
13. Push to GitHub Pages via `./push_to_github.sh "Phase 5: Budget Rules delta foundation"`

Estimated scope: 5–6 hours development, 2–3 hours testing.

---

*End of spec. Reference files: `index.html` (4,775 lines), `model_spec.md`, `test_regression.js`. WD baseline and all existing 457 regression tests are preserved unchanged.*
