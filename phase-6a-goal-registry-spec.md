# Herndon Financial OS — Phase 6A: Dynamic Goal Registry (Read-Only Migration)
**Version:** 1.1 — Revised per ChatGPT review  
**Date:** June 21, 2026  
**Status:** Awaiting ChatGPT final approval — DO NOT BUILD until approved

---

## Overview

Phase 6A is a read-only migration. The 13 goals currently hardcoded in `GOALS_REGISTRY` move to a Supabase table named `goal_registry`. The model loads them on startup. If the load fails or validation fails, a live hardcoded fallback takes over instantly — the model never waits or breaks. No CRUD UI. No write access. No schema changes to any other table.

Goal: identical model output after migration. If GR-A1 fails (fallback-loaded vs DB-mapped goals produce different output), the migration does not proceed.

---

## 1. Supabase Schema

### Table: `goal_registry`

```sql
CREATE TABLE goal_registry (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  tier          TEXT NOT NULL,
  target        NUMERIC(12,2) NOT NULL CHECK (target >= 0),
  priority      INTEGER NOT NULL CHECK (priority > 0),
  status        TEXT NOT NULL DEFAULT 'planned'
                  CHECK (status IN ('planned','funding','funded','executed','paused','archived')),
  notes         TEXT,
  starts_after  TEXT,
  due_week      INTEGER,
  needs_flag    TEXT,
  milestone     NUMERIC(12,2),
  stretch       BOOLEAN NOT NULL DEFAULT false,
  auto          BOOLEAN NOT NULL DEFAULT false,
  from_model    TEXT,
  src           TEXT,
  dest          TEXT,
  color         TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);
```

**Allowed status values and semantics:**

| Status | Meaning | Active waterfall candidate? | complete computed? |
|---|---|---|---|
| `planned` | Queued, not yet funding | Yes | No |
| `funding` | Actively receiving surplus | Yes | No |
| `funded` | Target reached; cruise/asset not yet executed | No — complete=true | Yes |
| `executed` | Completed and deployed | No — complete=true | Yes |
| `paused` | Temporarily halted; visible in UI | No | No |
| `archived` | Hidden from UI and model | No | No |

**What is NOT in the schema:**
- No `complete` column — computed in JS from `status` (see Section 5)
- No write policies — anon key is SELECT only (see Section 2)
- No foreign key on `starts_after` — validated in JS before it drives the model (see Section 6)

---

## 2. RLS Policy — Read-Only

```sql
ALTER TABLE goal_registry ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_read_goal_registry"
  ON goal_registry
  FOR SELECT
  TO anon
  USING (true);
```

No INSERT, UPDATE, or DELETE policies for anon. Goal CRUD requires auth — deferred to Phase 6B.

---

## 3. Seed Data

Seed all 13 current `GOALS_REGISTRY` rows exactly as currently defined.

**Status correction applied here:** `alaska` changes from `status='funded'` to `status='funding'`. The current hardcoded array has `complete:false` on alaska, which is correct model behavior — the model tracks `goalSaved.alaska >= akTarget` dynamically. Per the `status` semantics in Section 1, `funded` means complete, which would exclude alaska from the waterfall. Since alaska is still an active waterfall goal tracked by the model, it must have `status='funding'`. This is corrected in both the seed data below and in `HARDCODED_GOALS_FALLBACK` (Section 4).

```sql
INSERT INTO goal_registry
  (id, name, tier, target, priority, status, notes, starts_after, due_week, needs_flag, milestone, stretch, auto, from_model, src, dest, color)
VALUES
  ('adam_401k',       'Adam 401(k)',      'Retirement', 24500.00,  0, 'funding',  'Auto-funded via payroll',                        null,        null, null,              null,    false, true,  null,  'Payroll (auto-deduction)',        'Empower 401(k)',               null      ),
  ('wendy_sep',       'Wendy SEP',        'Retirement', 17859.00,  0, 'executed', 'Completed — 2025 SE income',                     null,        null, null,              null,    false, false, null,  'Wendy SE income',                 'Ascensus / BK CPA',            null      ),
  ('alaska',          'Alaska Cruise',    'Travel',      7000.00,  1, 'funding',  'Funded Cal Wk 27 — cruise Sep 2026',             null,        null, null,              null,    false, false, 'ak',  'Truist Checking (weekly surplus)', 'Truist Savings',              '#0369a1' ),
  ('wewe_rccl',       'Wewe RCCL',        'Travel',       600.00,  2, 'funding',  'Due end of July (Cal Wk 30)',                    'alaska',    8,    null,              null,    false, false, null,  'Truist Checking',                 'RCCL payment',                '#be185d' ),
  ('wewe_dcl',        'Wewe DCL',         'Travel',       500.00,  3, 'funding',  'Due first week of October (Cal Wk 41)',          'alaska',    19,   null,              null,    false, false, null,  'Truist Checking',                 'DCL payment',                 '#9333ea' ),
  ('adam_ira',        'Adam IRA',         'Retirement',  7000.00,  4, 'planned',  'Backdoor Roth — pending CPA clearance',         'wewe_dcl',  null, 'ira_cpa_cleared', null,    false, false, null,  'Truist Checking (weekly surplus)', 'AMEX Savings (IRA Holding)', '#6d28d9' ),
  ('wendy_ira',       'Wendy IRA',        'Retirement',  7000.00,  5, 'planned',  'Pending CPA clearance',                         null,        null, 'ira_cpa_cleared', null,    false, false, null,  'Truist Checking (weekly surplus)', 'AMEX Savings (IRA Holding)', '#7c3aed' ),
  ('bailey_529',      'Bailey 529',       'Education',   3500.00,  6, 'planned',  'Highest priority 529',                          null,        null, null,              null,    false, false, null,  'Truist Checking (weekly surplus)', 'AMEX Savings (529 Holding)', '#0e7490' ),
  ('bryce_529',       'Bryce 529',        'Education',   1500.00,  7, 'planned',  '',                                              null,        null, null,              null,    false, false, null,  'Truist Checking (weekly surplus)', 'AMEX Savings (529 Holding)', '#0891b2' ),
  ('preston_529',     'Preston 529',      'Education',   1000.00,  8, 'planned',  '',                                              null,        null, null,              null,    false, false, null,  'Truist Checking (weekly surplus)', 'AMEX Savings (529 Holding)', '#0284c7' ),
  ('bryce_vehicle',   'Bryce Vehicle',    'Emerging',    8000.00,  9, 'planned',  'Evaluate September 2026',                       null,        null, null,              null,    false, false, null,  'Truist Checking',                 'Truist Checking (hold)',      '#b45309' ),
  ('christmas_cruise','Christmas Cruise', 'Travel',      5000.00, 10, 'planned',  'Interim milestone $2,500 — full target $5,000', null,        null, null,              2500.00, false, false, null,  'Truist Checking',                 'Truist Savings (earmarked)',  '#4d7c0f' ),
  ('taxable_etf',     'Taxable ETF',      'Stretch',     4999.79, 11, 'planned',  '2027 restart — after all other goals funded',   null,        null, null,              null,    true,  false, null,  'Truist Checking surplus',         'Brokerage (Fidelity)',        '#94a3b8' )
ON CONFLICT (id) DO NOTHING;
```

Seed runs once. `ON CONFLICT DO NOTHING` makes it safe to re-run. After seeding, verify row count = 13 in Supabase dashboard before proceeding.

**Note on priority=0 for auto goals:** `adam_401k` and `wendy_sep` are `auto:true`. They are never in the waterfall arrays regardless of priority. Priority=0 is used for display sorting only. The `priority > 0` CHECK constraint on the schema does NOT apply to auto goals — auto goals should use priority=0. To accommodate this, either remove the CHECK constraint's lower bound, or set `priority > -1`. **Recommended: remove the `> 0` check from the schema and enforce `priority >= 0`.**

```sql
-- Corrected constraint for priority:
priority  INTEGER NOT NULL CHECK (priority >= 0),
```

---

## 4. Live Hardcoded Fallback

The current `const GOALS_REGISTRY=[...]` is REPLACED by `HARDCODED_GOALS_FALLBACK`. `GOALS_REGISTRY` becomes a `var` populated from Supabase or from the fallback. The fallback is never removed, never commented out.

**Key correction from v1.0:** alaska is `status:'funding'` (not `'funded'`) and `complete:false`. This matches the active waterfall behavior.

```javascript
// ── GOALS_REGISTRY fallback — live at all times, never commented out ──────
// Activated on Supabase load failure or validation failure.
const HARDCODED_GOALS_FALLBACK = [
  {id:'adam_401k',      name:'Adam 401(k)',      tier:'Retirement', target:24500,   priority:0,  status:'funding',  notes:'Auto-funded via payroll',                       auto:true,  stretch:false, complete:false, startsAfter:null,       dueWeek:null, needsFlag:null,              milestone:null,  fromModel:null, src:'Payroll (auto-deduction)',        dest:'Empower 401(k)',               color:null     },
  {id:'wendy_sep',      name:'Wendy SEP',        tier:'Retirement', target:17859,   priority:0,  status:'executed', notes:'Completed — 2025 SE income',                    auto:false, stretch:false, complete:true,  startsAfter:null,       dueWeek:null, needsFlag:null,              milestone:null,  fromModel:null, src:'Wendy SE income',                 dest:'Ascensus / BK CPA',           color:null     },
  {id:'alaska',         name:'Alaska Cruise',    tier:'Travel',     target:7000,    priority:1,  status:'funding',  notes:'Funded Cal Wk 27 — cruise Sep 2026',            auto:false, stretch:false, complete:false, startsAfter:null,       dueWeek:null, needsFlag:null,              milestone:null,  fromModel:'ak', src:'Truist Checking (weekly surplus)',dest:'Truist Savings',              color:'#0369a1'},
  {id:'wewe_rccl',      name:'Wewe RCCL',        tier:'Travel',     target:600,     priority:2,  status:'funding',  notes:'Due end of July (Cal Wk 30)',                    auto:false, stretch:false, complete:false, startsAfter:'alaska',   dueWeek:8,    needsFlag:null,              milestone:null,  fromModel:null, src:'Truist Checking',                 dest:'RCCL payment',                color:'#be185d'},
  {id:'wewe_dcl',       name:'Wewe DCL',         tier:'Travel',     target:500,     priority:3,  status:'funding',  notes:'Due first week of October (Cal Wk 41)',          auto:false, stretch:false, complete:false, startsAfter:'alaska',   dueWeek:19,   needsFlag:null,              milestone:null,  fromModel:null, src:'Truist Checking',                 dest:'DCL payment',                 color:'#9333ea'},
  {id:'adam_ira',       name:'Adam IRA',         tier:'Retirement', target:7000,    priority:4,  status:'planned',  notes:'Backdoor Roth — pending CPA clearance',         auto:false, stretch:false, complete:false, startsAfter:'wewe_dcl', dueWeek:null, needsFlag:'ira_cpa_cleared', milestone:null,  fromModel:null, src:'Truist Checking (weekly surplus)',dest:'AMEX Savings (IRA Holding)', color:'#6d28d9'},
  {id:'wendy_ira',      name:'Wendy IRA',        tier:'Retirement', target:7000,    priority:5,  status:'planned',  notes:'Pending CPA clearance',                         auto:false, stretch:false, complete:false, startsAfter:null,       dueWeek:null, needsFlag:'ira_cpa_cleared', milestone:null,  fromModel:null, src:'Truist Checking (weekly surplus)',dest:'AMEX Savings (IRA Holding)', color:'#7c3aed'},
  {id:'bailey_529',     name:'Bailey 529',       tier:'Education',  target:3500,    priority:6,  status:'planned',  notes:'Highest priority 529',                          auto:false, stretch:false, complete:false, startsAfter:null,       dueWeek:null, needsFlag:null,              milestone:null,  fromModel:null, src:'Truist Checking (weekly surplus)',dest:'AMEX Savings (529 Holding)', color:'#0e7490'},
  {id:'bryce_529',      name:'Bryce 529',        tier:'Education',  target:1500,    priority:7,  status:'planned',  notes:'',                                              auto:false, stretch:false, complete:false, startsAfter:null,       dueWeek:null, needsFlag:null,              milestone:null,  fromModel:null, src:'Truist Checking (weekly surplus)',dest:'AMEX Savings (529 Holding)', color:'#0891b2'},
  {id:'preston_529',    name:'Preston 529',       tier:'Education',  target:1000,    priority:8,  status:'planned',  notes:'',                                              auto:false, stretch:false, complete:false, startsAfter:null,       dueWeek:null, needsFlag:null,              milestone:null,  fromModel:null, src:'Truist Checking (weekly surplus)',dest:'AMEX Savings (529 Holding)', color:'#0284c7'},
  {id:'bryce_vehicle',  name:'Bryce Vehicle',    tier:'Emerging',   target:8000,    priority:9,  status:'planned',  notes:'Evaluate September 2026',                       auto:false, stretch:false, complete:false, startsAfter:null,       dueWeek:null, needsFlag:null,              milestone:null,  fromModel:null, src:'Truist Checking',                 dest:'Truist Checking (hold)',      color:'#b45309'},
  {id:'christmas_cruise',name:'Christmas Cruise', tier:'Travel',     target:5000,    priority:10, status:'planned',  notes:'Interim milestone $2,500 — full target $5,000', auto:false, stretch:false, complete:false, startsAfter:null,       dueWeek:null, needsFlag:null,              milestone:2500,  fromModel:null, src:'Truist Checking',                 dest:'Truist Savings (earmarked)',  color:'#4d7c0f'},
  {id:'taxable_etf',    name:'Taxable ETF',      tier:'Stretch',    target:4999.79, priority:11, status:'planned',  notes:'2027 restart — after all other goals funded',   auto:false, stretch:true,  complete:false, startsAfter:null,       dueWeek:null, needsFlag:null,              milestone:null,  fromModel:null, src:'Truist Checking surplus',         dest:'Brokerage (Fidelity)',        color:'#94a3b8'},
];
```

---

## 5. `complete` Field — Status as Source of Truth

`complete` is NOT stored in the DB. It is computed in JS inside `mapGoalFromDB()`:

```javascript
g.complete = ['funded', 'executed'].includes(g.status);
```

The hardcoded fallback pre-computes `complete` for each entry so the constant is self-contained and human-readable.

**Status-to-complete mapping for all 13 goals:**

| Goal | Status | complete |
|---|---|---|
| adam_401k | funding | false |
| wendy_sep | executed | **true** |
| alaska | funding | false |
| wewe_rccl | funding | false |
| wewe_dcl | funding | false |
| adam_ira | planned | false |
| wendy_ira | planned | false |
| bailey_529 | planned | false |
| bryce_529 | planned | false |
| preston_529 | planned | false |
| bryce_vehicle | planned | false |
| christmas_cruise | planned | false |
| taxable_etf | planned | false |

`wendy_sep` is the only goal where `complete:true`. Alaska is `status:'funding'` and `complete:false`. No contradiction.

---

## 6. Validation Rules

Validation runs after DB load, before DB data replaces `GOALS_REGISTRY`. Any failure rejects the entire load — `HARDCODED_GOALS_FALLBACK` is used.

```javascript
var ALLOWED_STATUSES = ['planned','funding','funded','executed','paused','archived'];

function validateLoadedGoals(goals) {
  var errors = [];
  var ids = goals.map(function(g) { return g.id; });
  // Active = not archived; used for duplicate priority check and circular chain check
  var activeGoals = goals.filter(function(g) { return g.status !== 'archived'; });

  // Required field checks (all goals)
  goals.forEach(function(g) {
    if (!g.id)                                       errors.push('Missing id on a goal row');
    if (!g.name)                                     errors.push((g.id||'?') + ': missing name');
    if (!g.tier)                                     errors.push((g.id||'?') + ': missing tier');
    if (g.target === null || g.target === undefined || isNaN(g.target) || g.target < 0)
                                                     errors.push((g.id||'?') + ': target must be numeric >= 0');
    if (g.priority === null || g.priority === undefined || isNaN(g.priority))
                                                     errors.push((g.id||'?') + ': priority must be numeric');
    if (ALLOWED_STATUSES.indexOf(g.status) < 0)      errors.push((g.id||'?') + ': invalid status "' + g.status + '"');
  });

  // No duplicate priorities among active goals (auto goals use priority=0; allow duplicate 0 for auto goals only)
  var seen = {};
  activeGoals.filter(function(g) { return !g.auto; }).forEach(function(g) {
    if (seen[g.priority]) errors.push('Duplicate priority ' + g.priority + ' on non-auto goals');
    seen[g.priority] = true;
  });

  // starts_after must reference an existing id
  activeGoals.forEach(function(g) {
    if (g.startsAfter && ids.indexOf(g.startsAfter) < 0) {
      errors.push(g.id + ': starts_after references missing id "' + g.startsAfter + '"');
    }
  });

  // No self-reference
  activeGoals.forEach(function(g) {
    if (g.startsAfter === g.id) {
      errors.push(g.id + ': starts_after references itself');
    }
  });

  // No circular starts_after chains (depth-limited walk)
  activeGoals.forEach(function(g) {
    var visited = {};
    var current = g.id;
    visited[current] = true;
    for (var i = 0; i < goals.length + 1; i++) {
      var node = goals.find(function(x) { return x.id === current; });
      if (!node || !node.startsAfter) break;
      if (visited[node.startsAfter]) {
        errors.push('Circular starts_after chain involving ' + g.id);
        break;
      }
      visited[node.startsAfter] = true;
      current = node.startsAfter;
    }
  });

  return errors;
}
```

---

## 7. Field Mapping — DB snake_case to Model camelCase

```javascript
function mapGoalFromDB(g) {
  return {
    id:           g.id,
    name:         g.name,
    tier:         g.tier,
    target:       parseFloat(g.target),
    priority:     parseInt(g.priority, 10),
    status:       g.status,
    notes:        g.notes || '',
    startsAfter:  g.starts_after  || null,   // snake_case → camelCase
    dueWeek:      g.due_week      || null,   // snake_case → camelCase
    needsFlag:    g.needs_flag    || null,   // snake_case → camelCase
    fromModel:    g.from_model    || null,   // snake_case → camelCase
    milestone:    g.milestone ? parseFloat(g.milestone) : null,
    stretch:      !!g.stretch,
    auto:         !!g.auto,
    src:          g.src  || null,
    dest:         g.dest || null,
    color:        g.color || null,
    complete:     ['funded','executed'].includes(g.status)  // computed, not stored
  };
}
```

No model engine changes. Zero changes to `runModel()`, `mv()`, waterfall, AMEX lookahead, `applyBudgetRulesForWeek`, or `diffModels`.

---

## 8. goalsLoadStatus — Normalized State Model

```javascript
var goalsLoadStatus = 'not_configured';
// States:
//   'not_configured'   — page load has not started yet
//   'loaded'           — Supabase loaded, mapped, and passed validation
//   'loaded_fallback'  — Supabase failed (HTTP error / empty / parse error); fallback active
//   'failed_validation'— Supabase loaded but rejected by validateLoadedGoals(); fallback active
```

The `'failed'` state from v1.0 is removed. All Supabase fetch/parse/empty failures set `'loaded_fallback'`. Only validation failures (data loaded but invalid) set `'failed_validation'`. Both fallback states keep the model running normally on `HARDCODED_GOALS_FALLBACK`.

---

## 9. Load Function and Fallback Behavior

```javascript
var GOALS_REGISTRY = [];
var VARIABLE_WATERFALL = [];
var REGULAR_WATERFALL = [];
var PRIORITY_TIERS = [];

async function loadGoalRegistry() {
  try {
    var res = await fetch(
      SUPA_URL + '/rest/v1/goal_registry?order=priority.asc',
      { headers: { 'apikey': SUPA_KEY, 'Authorization': 'Bearer ' + SUPA_KEY } }
    );
    if (!res.ok) throw new Error('HTTP ' + res.status);
    var data = await res.json();
    if (!Array.isArray(data) || data.length === 0) throw new Error('Empty or invalid response');

    var mapped = data.map(mapGoalFromDB);
    var errors = validateLoadedGoals(mapped);
    if (errors.length > 0) {
      console.warn('[GoalRegistry] Validation failed:', errors);
      goalsLoadStatus = 'failed_validation';
      applyGoalsFallback();
      return;
    }

    applyGoalsFromData(mapped);
    goalsLoadStatus = 'loaded';
    console.log('[GoalRegistry] Loaded ' + mapped.length + ' goals from Supabase');

  } catch (e) {
    console.warn('[GoalRegistry] Load failed:', e.message, '— using hardcoded fallback');
    goalsLoadStatus = 'loaded_fallback';
    applyGoalsFallback();
  }
}

function applyGoalsFallback() {
  applyGoalsFromData(HARDCODED_GOALS_FALLBACK.slice());
}
```

**`initApp()` change — load both in parallel:**

```javascript
async function initApp() {
  await Promise.all([loadBudgetRules(), loadGoalRegistry()]);
  runModel(akGoal, rtGoal);
  renderAll();
}
```

---

## 10. Active Waterfall Inclusion Rules

`VARIABLE_WATERFALL` and `REGULAR_WATERFALL` include only goals where ALL of the following are true:

```
auto     !== true
complete !== true   (i.e., status is not 'funded' or 'executed')
stretch  !== true
status   !== 'paused'
status   !== 'archived'
```

Then sort ascending by `priority`.

**Stretch goal exclusion confirmed:** `taxable_etf` has `stretch:true` and is NOT in the current hardcoded `VARIABLE_WATERFALL` or `REGULAR_WATERFALL`. This behavior is preserved exactly. Stretch goals are excluded in Phase 6A — they are not appended last, they are not in the waterfall at all.

```javascript
function applyGoalsFromData(goals) {
  GOALS_REGISTRY = goals;

  var waterfallGoals = goals
    .filter(function(g) {
      return !g.auto
          && !g.complete
          && !g.stretch
          && g.status !== 'paused'
          && g.status !== 'archived';
    })
    .sort(function(a, b) { return a.priority - b.priority; })
    .map(function(g) { return g.id; });

  VARIABLE_WATERFALL = waterfallGoals.slice();
  REGULAR_WATERFALL  = waterfallGoals.slice();

  // Rebuild PRIORITY_TIERS for display (non-auto goals, priority order)
  PRIORITY_TIERS = goals
    .filter(function(g) { return !g.auto; })
    .sort(function(a, b) { return a.priority - b.priority; })
    .map(function(g, i) {
      return { num: i + 1, name: g.name, goals: [g.id], color: g.color || '#94a3b8' };
    });
}
```

---

## 11. Gate Test — GR-A1 (Expanded)

GR-A1 is the migration gate. If it fails, Phase 6A does not ship.

GR-A1 compares fallback-loaded model output to DB-mapped model output across five dimensions:

```javascript
test('GR-A1: DB-mapped goals produce identical model output to hardcoded fallback', function() {
  // Step 1: Run with hardcoded fallback
  applyGoalsFromData(HARDCODED_GOALS_FALLBACK.slice());
  var fbWeeks = runModel(7000, 7694.87);
  var fbFinal = fbWeeks[fbWeeks.length - 1].goalSaved;
  var fbMinChk = Math.min.apply(null, fbWeeks.map(function(w) { return w.mChk; }));
  var fbVW  = VARIABLE_WATERFALL.slice();
  var fbRW  = REGULAR_WATERFALL.slice();

  // Step 2: Simulate DB load — convert fallback to snake_case and run through mapGoalFromDB
  var simulatedDB = HARDCODED_GOALS_FALLBACK.map(function(g) {
    return {
      id: g.id, name: g.name, tier: g.tier, target: g.target,
      priority: g.priority, status: g.status, notes: g.notes,
      starts_after: g.startsAfter, due_week: g.dueWeek,
      needs_flag: g.needsFlag, from_model: g.fromModel,
      milestone: g.milestone, stretch: g.stretch, auto: g.auto,
      src: g.src, dest: g.dest, color: g.color
    };
  });
  applyGoalsFromData(simulatedDB.map(mapGoalFromDB));
  var dbWeeks = runModel(7000, 7694.87);
  var dbFinal = dbWeeks[dbWeeks.length - 1].goalSaved;
  var dbMinChk = Math.min.apply(null, dbWeeks.map(function(w) { return w.mChk; }));
  var dbVW  = VARIABLE_WATERFALL.slice();
  var dbRW  = REGULAR_WATERFALL.slice();

  // Gate check 1: final goalSaved by id (within $0.01)
  var tracked = ['alaska','wewe_rccl','wewe_dcl','adam_ira','wendy_ira',
                 'bailey_529','bryce_529','preston_529','bryce_vehicle',
                 'christmas_cruise','taxable_etf','adam_401k'];
  tracked.forEach(function(id) {
    var fb = fbFinal[id] || 0;
    var db = dbFinal[id] || 0;
    assertApprox(fb, db, 'GR-A1 goalSaved[' + id + ']: fallback=' + fb + ' db=' + db, 0.01);
  });

  // Gate check 2: VARIABLE_WATERFALL order must match
  assert(JSON.stringify(fbVW) === JSON.stringify(dbVW),
    'GR-A1 VARIABLE_WATERFALL mismatch: fallback=' + JSON.stringify(fbVW) + ' db=' + JSON.stringify(dbVW));

  // Gate check 3: REGULAR_WATERFALL order must match
  assert(JSON.stringify(fbRW) === JSON.stringify(dbRW),
    'GR-A1 REGULAR_WATERFALL mismatch');

  // Gate check 4: lowest checking week value (within $0.01)
  assertApprox(fbMinChk, dbMinChk, 'GR-A1 minChk: fallback=' + fbMinChk + ' db=' + dbMinChk, 0.01);

  // Gate check 5: goal ETA for key waterfall goals (within 1 week)
  ['wewe_rccl','adam_ira','bailey_529'].forEach(function(id) {
    var gdef = GOALS_REGISTRY.find(function(g) { return g.id === id; });
    var tgt  = gdef ? gdef.target : 0;
    var fbETA = null, dbETA = null;
    for (var i = 0; i < fbWeeks.length; i++) { if ((fbWeeks[i].goalSaved[id]||0) >= tgt - 0.01) { fbETA = fbWeeks[i].num; break; } }
    for (var j = 0; j < dbWeeks.length; j++) { if ((dbWeeks[j].goalSaved[id]||0) >= tgt - 0.01) { dbETA = dbWeeks[j].num; break; } }
    if (fbETA !== null && dbETA !== null) {
      assert(Math.abs(fbETA - dbETA) <= 1, 'GR-A1 ETA[' + id + ']: fallback=' + fbETA + ' db=' + dbETA);
    }
  });

  // Restore
  applyGoalsFromData(HARDCODED_GOALS_FALLBACK.slice());
});
```

---

## 12. Regression Test Plan

New section GR-A through GR-E in `test_regression.js`:

| Test | Assertion |
|---|---|
| GR-A1 | Gate test — 5 checks: goalSaved, VARIABLE_WATERFALL, REGULAR_WATERFALL, minChk, ETAs |
| GR-A2 | VARIABLE_WATERFALL order matches priority sort after applyGoalsFromData |
| GR-A3 | startsAfter mapping: wewe_rccl.startsAfter === 'alaska' after mapGoalFromDB |
| GR-A4 | needsFlag mapping: adam_ira.needsFlag === 'ira_cpa_cleared' after mapGoalFromDB |
| GR-A5 | complete computed: wendy_sep.complete === true (status='executed'), alaska.complete === false (status='funding') |
| GR-B1 | Duplicate priority on non-auto goals → validateLoadedGoals returns errors |
| GR-B2 | Missing startsAfter reference → validateLoadedGoals returns errors |
| GR-B3 | Self-referencing startsAfter → validateLoadedGoals returns errors |
| GR-B4 | Circular startsAfter chain → validateLoadedGoals returns errors |
| GR-B5 | Missing required field (name=null) → validateLoadedGoals returns errors |
| GR-B6 | Invalid status value → validateLoadedGoals returns errors |
| GR-B7 | Negative target → validateLoadedGoals returns errors |
| GR-B8 | Empty DB response (data.length===0) → applyGoalsFallback runs, goalsLoadStatus='loaded_fallback' |
| GR-C1 | goalsLoadStatus === 'loaded_fallback' after fetch failure |
| GR-C2 | goalsLoadStatus === 'failed_validation' after validation failure |
| GR-D1 | auto, complete, stretch, paused, archived goals excluded from VARIABLE_WATERFALL |
| GR-D2 | VARIABLE_WATERFALL and REGULAR_WATERFALL are identical after load |
| GR-E1 | All GR tests restore GOALS_REGISTRY to fallback state before exit |

---

## 13. Playwright Test Plan

New section GR in `e2e.js`:

| Test | Assertion |
|---|---|
| GR-1 | Goals tab renders correctly after applyGoalsFromData (DB-simulated load) |
| GR-2 | Savings Goals sub-tab shows all active goals from DB-loaded registry |
| GR-3 | Fallback banner appears when goalsLoadStatus is 'loaded_fallback' |
| GR-4 | No fallback banner when goalsLoadStatus is 'loaded' |
| GR-5 | Goal count in UI matches GOALS_REGISTRY.length after simulated DB load |

---

## 14. Rollback Plan

**Layer 1 — Automatic, zero downtime:**
Any load failure, HTTP error, empty response, or validation error → `applyGoalsFallback()` fires immediately, `HARDCODED_GOALS_FALLBACK` takes over. No user impact.

**Layer 2 — UI signal:**
`goalsLoadStatus` drives a banner on the Goals tab:
- `'loaded'` → no banner
- `'loaded_fallback'` → amber: "Goals running from local fallback — Supabase unavailable"
- `'failed_validation'` → amber: "Goals failed validation — using local fallback. Check console for details."

**Layer 3 — Code rollback:**
`HARDCODED_GOALS_FALLBACK` is never removed. Reverting the commit restores prior behavior exactly. The `goal_registry` table has no write policies — no data can have been mutated. Rollback is clean.

---

## 15. What Does Not Change in Phase 6A

| Item | Stays hardcoded | Reason |
|---|---|---|
| `AK_START = 5` | Yes | Model constant |
| `RET_SAV_XFR = $3,772.74` | Yes | Model constant |
| `_amxHold` list | Yes | Matches goal IDs by convention; no model change needed |
| `goalFlags.ira_cpa_cleared` | Yes | Toggle state, not a goal property |
| `goalFundedAmounts` | Yes | YTD seeding amounts |
| Balance constants | Yes | START_AMX, START_CHK, etc. |
| All model engine logic | Yes | runModel, mv, waterfall, lookahead, applyBudgetRulesForWeek, diffModels |
| CRUD UI | Deferred | Phase 6B/6C |
| Write access | Deferred | Phase 6B |
| Drag-and-drop priority reorder | Deferred | Phase 6C |

---

*Version 1.1 — corrects status/complete contradiction (alaska: funding not funded), normalizes goalsLoadStatus (removes 'failed' state), adds explicit waterfall inclusion rules with stretch exclusion confirmed, adds SQL CHECK constraints and code-level required-field validation, expands GR-A1 to five gate checks, and corrects seed wording.*

*Do not build until ChatGPT approves.*
