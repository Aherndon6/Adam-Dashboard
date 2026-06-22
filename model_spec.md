# Herndon Family Cash Flow Model — Full Specification

**Version:** Phase 6A + Stabilization S1
**Date:** Cal Wk 25 (Jun 21, 2026)
**Test status:** 596 regression / 46 Playwright — all passing (`node test_regression.js && node e2e.js`)

---

## 1. Overview

Single-file HTML dashboard (`index.html`) running a 31-week forward-looking cash flow model from Cal Wk 23 (Jun 7, 2026) through Cal Wk 53 (Jan 9, 2027).

- **Vanilla JS, no frameworks, no build step** — everything in one `<script>` block inside `index.html`
- **Week-indexed** — model weeks 1–31 map to calendar weeks 23–53 (cal wk = model wk + 22)
- **Direct waterfall** — each week, surplus above the operating floor sweeps from Truist Checking to goals in priority order; no intermediate pool accounts
- **Supabase REST backend** — all persistent data stored in Supabase; app reads on load, writes on user action
- **GitHub Pages deployment** — live at https://dashboard.herndons.us

---

## 2. Account Structure

| Account | Starting Balance | Role |
|---|---|---|
| Truist Checking (`chk`) | $18,037.73 | Primary operating account. All inflows and outflows run through here. |
| Truist Savings (`sav`) | $3,772.77 | Alaska cruise savings staging. Sweeps to AMEX when Alaska fully funds. |
| AMEX Savings (`amx`) | $103.64 | IRA and 529 holding account. Receives savings seed on Alaska completion. |
| Vio Bank — Tax Reserve (`tax`) | $0.00 | Commission and income tax reserve. 40% of commission income routes here. |
| Lending Club / EF (`lc`) | $13,488.88 | Emergency fund. Static — no model transfers in or out. |

**Starting balances reflect completed Cal Wk 23 setup transfers:**
- $2,750 Truist Savings → Truist Checking
- $1,000 Lending Club → Truist Checking
- $2,250 Lending Club → Truist Checking (Option 1 correction)

---

## 3. Core Constants

```javascript
START_CHK    = 18037.73   // Truist Checking (post-setup)
START_SAV    =  3772.77   // Truist Savings (post-setup)
START_AMX    =   103.64   // AMEX Savings (initial IRA seed)
START_TAX    =     0.00   // Vio Bank Tax Reserve (empty at model start)
START_LC     = 13488.88   // Lending Club / EF (static)

OP_FL        =  6500.00   // Hard operating floor — mv() never pulls checking below this
MIN_XFR      =   100.00   // Minimum transfer; smaller amounts suppressed and carried forward
AK_START     =     5      // Model week waterfall begins (weeks 1–4 settle setup)
BASE_TAX     =   521.36   // Pre-existing tax liability — sweeps to Vio first eligible week
RET_SAV_XFR  =  3772.74   // One-time Truist Savings → AMEX when Alaska fully funds

COMM_TAX     =   707.18   // Commission: 40% of $1,767.94 → Vio Bank Tax Reserve (Cal Wk 28)
COMM_AK      =  1060.76   // Commission: 60% of $1,767.94 — routes via waterfall
```

---

## 4. Time Horizon

| Field | Value |
|---|---|
| Model weeks | 1–31 |
| Calendar weeks | 23–53 |
| Start | Jun 7, 2026 (Cal Wk 23) |
| End | Jan 9, 2027 (Cal Wk 53) |

---

## 5. Core Model Engine — `runModel(akGoal, rtGoal, flags)`

### 5.1 Signature

```javascript
runModel(akGoal, rtGoal, flags)
// akGoal: Alaska funded amount (from Supabase or override)
// rtGoal: retirement savings amount (AMEX balance)
// flags:  optional {isCpaCleared: bool}
// returns: array of 31 week objects
```

### 5.2 Week Object Shape

Each week object returned by `runModel()` includes:

```javascript
{
  num,          // model week number (1–31)
  dates,        // display string e.g. "Jun 7-13"
  startChk, startSav, startAmx, startTax, startLc,  // opening balances
  endChk, endSav, endAmx, endTax, endLc,            // closing balances
  mChk, mSav, mAmx, mTax, mLc,                     // model balances (before recon override)
  inflows, bills, surplus,                           // weekly cash flow
  tr,           // transfer log array (strings)
  ac, acKeys,   // all actions + parallel key array
  realActs, realActKeys,  // filtered actions (no sentinel) + keys
  goalSaved,    // {goalId: amount} — per-goal funded totals at end of week
  akSaved,      // alaska funded total (dedicated tracker)
  reconciled, actualBals, variance,  // recon state
  doneTasks, totalTasks,             // action completion counts
  calNote, recActs, ruleAudit        // calendar note, recommended actions, audit log
}
```

### 5.3 Waterfall Mechanics

Each week (starting model week AK_START = 5):

1. Calculate net surplus: `inflows − bills − budgetRuleDeltas`
2. If surplus < OP_FL buffer: defer (not drop) minimum transfers
3. Sweep surplus above OP_FL to `VARIABLE_WATERFALL` goals in priority order
4. `mv(amount, from, to, label)` — core transfer function; never pulls checking below OP_FL
5. Commission weeks: 40% to tax reserve, 60% routes through waterfall

### 5.4 Alaska Draw

Model week 15 (Cal Wk 37): Alaska fully funds. `RET_SAV_XFR = $3,772.74` moves Truist Savings → AMEX Savings (IRA holding seed).

---

## 6. Goal Registry — Phase 6A

### 6.1 State Variables

```javascript
const HARDCODED_GOALS_FALLBACK = [...];  // 13 goals — always-live fallback
var goalsLoadStatus = 'not_configured';  // 4-state machine
var GOALS_REGISTRY  = [];
var VARIABLE_WATERFALL = [];
var REGULAR_WATERFALL  = [];
var PRIORITY_TIERS = [];
```

### 6.2 Initialization Order

1. `applyGoalsFallback()` called at module level — GOALS_REGISTRY populated before first render
2. `loadAll()` fetches `goal_registry` from Supabase (9th fetch in Promise.all)
3. On success: `mapGoalFromDB()` → `validateLoadedGoals()` → if valid, `applyGoalsFromData()` → `goalsLoadStatus = 'loaded'`
4. On any failure: `applyGoalsFallback()` → `goalsLoadStatus = 'loaded_fallback'` or `'failed_validation'`
5. Post-`loadAll()` guard: if `goalsLoadStatus` is still `'not_configured'`, forces `'loaded_fallback'`

### 6.3 goalsLoadStatus State Machine

| State | Meaning | Banner |
|---|---|---|
| `'not_configured'` | Before loadAll() completes | None (loading) |
| `'loaded'` | Supabase data valid and applied | None |
| `'loaded_fallback'` | Fetch error, empty response, or HTTP failure | Amber warning |
| `'failed_validation'` | Data loaded but failed validateLoadedGoals() | Amber warning (validation) |

### 6.4 Waterfall Construction

```javascript
// VARIABLE_WATERFALL and REGULAR_WATERFALL (identical)
goals.filter(g => !g.auto && !g.complete && !g.stretch
                  && g.status !== 'paused' && g.status !== 'archived')
     .sort((a,b) => a.priority - b.priority)
     .map(g => g.id)

// PRIORITY_TIERS (display — non-auto, non-complete, priority order)
goals.filter(g => !g.auto && !g.complete)
     .sort((a,b) => a.priority - b.priority)
```

### 6.5 Current GOALS_REGISTRY (13 goals)

| ID | Name | Priority | Status | Auto | Stretch | complete |
|---|---|---|---|---|---|---|
| adam_401k | Adam 401(k) | 0 | funding | true | false | false |
| wendy_sep | Wendy SEP | 0 | executed | false | false | **true** |
| alaska | Alaska Cruise | 1 | funding | false | false | false |
| wewe_rccl | Wewe RCCL | 2 | funding | false | false | false |
| wewe_dcl | Wewe DCL | 3 | funding | false | false | false |
| adam_ira | Adam IRA | 4 | planned | false | false | false |
| wendy_ira | Wendy IRA | 5 | planned | false | false | false |
| bailey_529 | Bailey 529 | 6 | planned | false | false | false |
| bryce_529 | Bryce 529 | 7 | planned | false | false | false |
| preston_529 | Preston 529 | 8 | planned | false | false | false |
| bryce_vehicle | Bryce Vehicle | 9 | planned | false | false | false |
| christmas_cruise | Christmas Cruise | 10 | planned | false | false | false |
| taxable_etf | Taxable ETF | 11 | planned | false | **true** | false |

**VARIABLE_WATERFALL (10):** alaska → wewe_rccl → wewe_dcl → adam_ira → wendy_ira → bailey_529 → bryce_529 → preston_529 → bryce_vehicle → christmas_cruise

**Excluded:** adam_401k (auto), wendy_sep (complete), taxable_etf (stretch)

### 6.6 Validation Rules (9 checks)

1. `id` present on every row
2. `name` present
3. `tier` present
4. `target` numeric ≥ 0
5. `priority` numeric
6. `status` in `['planned','funding','funded','executed','paused','archived']`
7. No duplicate priorities among non-auto active goals
8. `starts_after` references an existing goal id (if set)
9. No self-reference or circular `starts_after` chains

### 6.7 `complete` Field

Computed, not stored: `['funded','executed'].includes(g.status)`. Derived by `mapGoalFromDB()` on load.

---

## 7. Budget Rules — Phase 5

### 7.1 Overview

Recurring and one-time cash flow adjustments loaded from Supabase `budget_rules` table. Applied per-week before surplus calculation. No in-app write UI — managed via Supabase dashboard.

### 7.2 Rule Shape

```javascript
{
  id, label, active,
  amount,       // always positive
  direction:    'inflow'|'outflow',
  frequency:    'one-time'|'weekly'|'biweekly'|'monthly',
  start_date:   'YYYY-MM-DD',
  end_date:     'YYYY-MM-DD'|null,
  rule_mode:    'delta',   // 'absolute' is blocked
  category, source, day_of_month
}
```

### 7.3 Application Logic

- `applyBudgetRulesForWeek(weekNum, weekStartDate, rules)` → `{delta, tr, audit}`
- Applied BEFORE surplus calculation in `runModel()`
- **Override bypass**: budget rules are bypassed (not dropped) when a `model_week_override` exists for that week; logged to audit with `action: 'bypassed_by_model_week_override'`
- `budgetRulesLoadStatus`: `'not_configured' | 'loaded' | 'failed'`
- `'failed'` shows red banner

---

## 8. What-If Impact Calculator — Phase 5 (WC)

Session-only scenario tool. Runs `diffModels(baseline, scenario, audit, akGoal)` and shows week-by-week goal impact, floor breach weeks, bypassed weeks, and caseType. Does not write to Supabase. `budgetRules` array is temporarily extended with a `what_if_temp` rule, then fully restored by `clearWhatIf()`.

**Key invariants:**
- What-If rule is bypassed in overridden weeks (same bypass logic as Budget Rules)
- Date outside model window returns null from `dateToModelWeek()` → error state in UI
- `caseType`: `'positive' | 'negative' | 'neutral'`

---

## 9. Supabase Tables and RLS Posture

| Table | Purpose | anon read | anon write |
|---|---|---|---|
| `goals` | KV store — akFunded, IRA flags, misc state | ✓ | ✓ |
| `weekly_reconciliations` | Per-week actual balances | ✓ | ✓ |
| `weekly_tasks` | Per-task completion state | ✓ | ✓ |
| `weekly_notes` | Per-week text notes | ✓ | ✓ |
| `model_week_overrides` | Custom week event overrides | ✓ | ✓ |
| `wishlist_items` | Feature wishlist (UI read-only) | ✓ | ✓ |
| `custom_tasks` | User-created weekly tasks | ✓ | ✓ |
| `budget_rules` | Recurring/one-time adjustments | ✓ | ✓ |
| `goal_registry` | Goal definitions — Phase 6A | ✓ | **✗ SELECT only** |

`goal_registry` has a BEFORE UPDATE trigger (`set_goal_registry_updated_at`) that auto-stamps `updated_at = NOW()` on any row update.

**Security note:** Anon key is embedded in `index.html`. App is public with no authentication. All tables except `goal_registry` have anon write access. Authentication is required before Phase 6B (goal registry writes) goes to production.

---

## 10. Write Paths (Reconciliation and Tasks)

### 10.1 `saveRecon(weekNum)` → POST `weekly_reconciliations`

```javascript
// Local state
reconData[n] = { chk, sav, amx, tax, lc, date }

// Supabase payload (merge-duplicates)
{ week_num: n, chk, sav, amx, tax, lc, recorded_at: ISO }
```

`isWeekReconciled(n)` returns true when `reconData[n].chk !== undefined`.

### 10.2 `toggleTask(weekNum, taskIdx, checked, actionKey, amount)` → POST `weekly_tasks`

```javascript
// Local state key: weekNum+'_'+taskIdx
taskData[key] = { completed, completedAt, completedAmount, actionKey, completedLabel }

// Supabase payload (merge-duplicates)
{ week_num, task_idx, completed, completed_at, completed_amount, action_key, completed_label }
```

`applyCompletionSnapshots(weeks)` uses `taskData` to substitute `completedAmount` into action labels at render time.

### 10.3 `saveNote(weekNum, el)` → POST `weekly_notes`

```javascript
noteData[weekNum] = el.value
// Payload: { week_num: weekNum, note: el.value }
```

---

## 11. Defensive Behaviors (Phase S1)

### 11.1 renderApp() Error Boundary

`renderApp()` is wrapped in try/catch. On exception: logs to console, displays `#render-error-banner` with error message and stack trace. Banner is hidden on the next successful render.

### 11.2 goalsLoadStatus not_configured Guard

After `loadAll()` resolves, a `.then()` callback checks if `goalsLoadStatus` is still `'not_configured'`. If so: promotes to `'loaded_fallback'`, calls `applyGoalsFallback()`, re-renders. This catches cases where `loadAll()` threw before reaching the goal registry fetch.

---

## 12. Model Invariants (Review Gates)

These must hold after every build. All are regression-tested.

| Invariant | Test section |
|---|---|
| Week 1 startChk = $18,037.73 | Section 2 |
| OP_FL = $6,500 | Section 2 |
| No week has negative checking | Section 2 |
| Alaska fully funds by W31 at $7,000 | Section 2 |
| GOALS_REGISTRY has 13 entries | Section 3 |
| VARIABLE_WATERFALL has exactly 10 items | Section 3 |
| Waterfall order: alaska→rccl→dcl→adam_ira | Section 3 |
| PRIORITY_TIERS has 11 entries | Section 3 |
| taxable_etf NOT in either waterfall | Section 3 |
| GR-A1 gate: DB-mapped goals = identical model output to fallback | GR-A |
| Budget rule delta applied before surplus | BR-J |
| Budget rule bypassed in overridden week | BR-K |
| What-If rule cleared after diffModels | WC-D |
| reconData shape: {chk,sav,amx,tax,lc,date} | REC-A |
| taskData shape: {completed,completedAt,completedAmount,actionKey,completedLabel} | REC-A |

---

## 13. Test Suite

### 13.1 Regression (`node test_regression.js`) — 596 / 0

| Section | Covers |
|---|---|
| 1–9 | Helpers, core model, goals registry, decision engine, edge cases, rendering |
| Ph3/Ph4 | Phase 3/4 additions |
| BR-A through BR-K | Budget Rules — validation, generation, engine, integration, override bypass |
| WC-A through WC-D | What-If Calculator — entries, diffModels, floor breaches, restore |
| GR-A through GR-E | Goal Registry — gate test, field mapping, validation, waterfall, restore |
| REC-A | Reconciliation write path — data shapes and rehydration |

### 13.2 Playwright E2E (`node e2e.js`) — 46 / 0

Sections A–J (smoke, console, decision engine, IRA flag, edit week, recon, wishlist, XSS, offline, mobile) + BR (5 tests), WC (7 tests), GR (5 tests).

---

## 14. Build and Push Process

```bash
bash push_to_github.sh "Your commit message"
```

Steps: locate repo → `node test_regression.js` → `node e2e.js` → stamp BUILD_TS automatically → `git add -A` → commit → push.

**The push script must run from Adam's local machine.** The sandbox can run regression but not e2e (Playwright browser deps unavailable in sandbox).

---

## 15. Known Risks and Open Items

| ID | Item | Priority |
|---|---|---|
| TD-2 | No authentication — anon key embedded, app is public | High |
| TD-3 | Budget rules have no in-app management UI | Medium |
| TD-6 | index.html is 5,000+ lines, single file | Medium |
| TD-7 | Floor breach projection weeks 35–51 visible in chart, no explanation overlay | Medium |
| TD-8 | START_CHK / START_SAV hardcoded, not pulled from reconciliation | Medium |

---

*This spec is the review baseline for all future model-affecting build proposals.*
