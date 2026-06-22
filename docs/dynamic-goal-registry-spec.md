# Herndon Financial OS — Dynamic Goal Registry Spec
**Version:** 1.0 Draft  
**Date:** June 21, 2026  
**OS Phase:** Phase 6 (follows Waterfall Calculator)  
**Status:** Awaiting ChatGPT review before build

---

## 1. Purpose

Goals are currently hardcoded in `GOALS_REGISTRY` (a JS array in `index.html`). When Budget Rules shift your cash position, the model accurately projects goal ETA changes — but you cannot act on them without editing code.

The Dynamic Goal Registry moves goals to a Supabase table, enabling:

1. Add, edit, pause, archive, or reprioritize goals through a UI — no code changes
2. Goals become reactive to Budget Rule changes automatically (they already are in the model; this makes the data layer match)
3. The system can store and restore goal state (funded amounts, completion dates) without touching index.html

---

## 2. What Does Not Change

To keep scope tight, the following stays hardcoded in Phase 6:

- The waterfall engine (`runModel()` logic for how surplus flows through goals)
- `AK_START` week gate (alaska fund-up starts at Wk 5)
- `RET_SAV_XFR` constant ($3,772.74)
- `_amxHold` routing (IRA/529 goals sweep to AMEX Savings)
- The rendering logic for goal cards and tier display
- `goalFundedAmounts` seeding (completed goals remain hardcoded as starting amounts)
- The priority order of VARIABLE_WATERFALL and REGULAR_WATERFALL arrays — these become DB-driven in Phase 6 (see Section 6)

---

## 3. Supabase Schema

### Table: `goals`

```sql
CREATE TABLE goals (
  id            TEXT PRIMARY KEY,           -- matches existing IDs: 'alaska', 'adam_ira', etc.
  name          TEXT NOT NULL,
  tier          TEXT NOT NULL,              -- 'Retirement' | 'Travel' | 'Education' | 'Emerging' | 'Stretch'
  target        NUMERIC(10,2) NOT NULL,
  priority      INTEGER NOT NULL,           -- 1 = highest; drives VARIABLE_WATERFALL order
  status        TEXT NOT NULL DEFAULT 'planned',  -- 'planned' | 'funding' | 'funded' | 'executed' | 'paused' | 'archived'
  complete      BOOLEAN NOT NULL DEFAULT false,
  notes         TEXT,
  starts_after  TEXT REFERENCES goals(id),  -- dependency chain: null = no dependency
  due_week      INTEGER,                    -- model week number; null = no hard deadline
  needs_flag    TEXT,                       -- e.g., 'ira_cpa_cleared'; null = no flag dependency
  milestone     NUMERIC(10,2),             -- interim milestone target (e.g., christmas_cruise $2,500)
  stretch       BOOLEAN NOT NULL DEFAULT false,
  auto          BOOLEAN NOT NULL DEFAULT false,  -- true = model-calculated (adam_401k, wendy_sep)
  color         TEXT,                       -- hex color for waterfall chart
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- RLS: same pattern as budget_rules
ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_read_goals" ON goals FOR SELECT TO anon USING (true);
CREATE POLICY "anon_write_goals" ON goals FOR ALL TO anon USING (true);
```

**Note on `anon_write_goals`:** The app has no auth layer. Same approach as budget_rules — anon key has write access. This is acceptable for a private single-user tool. If Adam adds auth in a future phase, row-level user scoping can be added then.

### Seed Data

The initial seed populates all 10 current goals from `GOALS_REGISTRY` plus the 2 auto goals (`adam_401k`, `wendy_sep`). Seeds run once as an insert-ignore migration; the hardcoded array is kept as a fallback until migration is confirmed.

```sql
-- Example seed rows (abbreviated)
INSERT INTO goals (id, name, tier, target, priority, status, complete, notes, starts_after, due_week, needs_flag, stretch, auto, color)
VALUES
  ('adam_401k',       'Adam 401k',        'Retirement', 24500, 0,  'executed', true,  'Auto-calculated from payroll',                    null,        null, null,              false, true,  null),
  ('wendy_sep',       'Wendy SEP',        'Retirement', 17859, 0,  'executed', true,  'Completed — 2025 SE income',                      null,        null, null,              false, true,  null),
  ('alaska',          'Alaska Cruise',    'Travel',     7000,  1,  'funded',   false, 'Funded Cal Wk 27 — cruise Sep 2026',              null,        null, null,              false, false, '#0369a1'),
  ('wewe_rccl',       'Wewe RCCL',        'Travel',     600,   2,  'funding',  false, 'Due end of July (Cal Wk 30)',                     'alaska',    8,    null,              false, false, '#be185d'),
  ('wewe_dcl',        'Wewe DCL',         'Travel',     500,   3,  'funding',  false, 'Due first week of October (Cal Wk 41)',           'alaska',    19,   null,              false, false, '#9333ea'),
  ('adam_ira',        'Adam IRA',         'Retirement', 7000,  4,  'planned',  false, 'Backdoor Roth — pending CPA clearance',           'wewe_dcl',  null, 'ira_cpa_cleared', false, false, '#6d28d9'),
  ('wendy_ira',       'Wendy IRA',        'Retirement', 7000,  5,  'planned',  false, 'Pending CPA clearance',                          null,        null, 'ira_cpa_cleared', false, false, '#7c3aed'),
  ('bailey_529',      'Bailey 529',       'Education',  3500,  6,  'planned',  false, 'Highest priority 529',                           null,        null, null,              false, false, '#0e7490'),
  ('bryce_529',       'Bryce 529',        'Education',  1500,  7,  'planned',  false, '',                                               null,        null, null,              false, false, '#0891b2'),
  ('preston_529',     'Preston 529',      'Education',  1000,  8,  'planned',  false, '',                                               null,        null, null,              false, false, '#0284c7'),
  ('bryce_vehicle',   'Bryce Vehicle',    'Emerging',   8000,  9,  'planned',  false, 'Evaluate September 2026',                        null,        null, null,              false, false, '#b45309'),
  ('christmas_cruise','Christmas Cruise', 'Travel',     5000,  10, 'planned',  false, 'Interim milestone $2,500 — full target $5,000',  null,        null, null,              false, false, '#4d7c0f'),
  ('taxable_etf',     'Taxable ETF',      'Stretch',    4999.79,11,'planned',  false, '2027 restart — after all other goals funded',    null,        null, null,              true,  false, '#94a3b8')
ON CONFLICT (id) DO NOTHING;
```

---

## 4. Model Integration

### Current (hardcoded)

```javascript
const GOALS_REGISTRY = [...]; // static array
const VARIABLE_WATERFALL = ['alaska', 'wewe_rccl', ...]; // static order
```

### After Phase 6

`loadGoals()` replaces the static array. It fires once on page load alongside `loadBudgetRules()`.

```javascript
var GOALS_REGISTRY = [];  // populated from Supabase; no longer const
var VARIABLE_WATERFALL = [];
var REGULAR_WATERFALL = [];
var goalsLoadStatus = 'not_configured'; // 'not_configured' | 'loaded' | 'failed'

async function loadGoals() {
  try {
    var res = await fetch(SB_URL + '/rest/v1/goals?order=priority.asc&status=neq.archived', {
      headers: { 'apikey': SB_KEY, 'Authorization': 'Bearer ' + SB_KEY }
    });
    var data = await res.json();
    GOALS_REGISTRY = data;
    // Rebuild waterfall arrays from priority-ordered DB data
    VARIABLE_WATERFALL = data.filter(g => !g.auto && !g.complete).map(g => g.id);
    REGULAR_WATERFALL = VARIABLE_WATERFALL.slice();
    goalsLoadStatus = 'loaded';
  } catch(e) {
    goalsLoadStatus = 'failed';
    // Fall back to hardcoded GOALS_REGISTRY (keeps the model running)
    console.warn('Goals load failed, using hardcoded fallback');
  }
}
```

**Fallback behavior:** If the DB load fails, the hardcoded array remains as the safety net. The model runs identically. A banner on the Goals tab shows: "Goals loaded from local fallback — check Supabase connection."

---

## 5. Goal CRUD UI

### Location

New sub-tab within the Goals tab: **"Manage Goals"** (alongside "What-If Calculator" from Waterfall Calculator spec).

### Views

**Goal List View (default)**

A table of all non-archived goals showing:
- Priority order (drag handle or up/down arrows for reordering)
- Name, Tier, Target, Status, Notes
- Actions: Edit | Pause | Archive

Paused goals remain in the registry but are skipped by the waterfall. Archived goals are hidden from all views.

**Add Goal Form**

Fields:
| Field | Type | Required |
|---|---|---|
| ID | Text (slug) | Yes — must be unique |
| Name | Text | Yes |
| Tier | Select | Yes |
| Target amount | Dollar | Yes |
| Notes | Text | No |
| Starts after | Select (existing goal IDs) | No |
| Due week | Number | No |
| Needs flag | Text | No |
| Milestone | Dollar | No |
| Stretch | Checkbox | No |

Priority is assigned as (current max priority + 1) on creation; user can reorder after.

**Edit Goal Form**

Same fields as Add. Editing `target` or `starts_after` triggers a model re-run on save to immediately reflect new ETAs.

### Reorder Priority

V1: Up/down arrow buttons per row. Swaps priority values between adjacent goals.  
V2: Drag-and-drop (deferred).

Priority changes immediately call `runModel()` and re-render goal ETAs — the waterfall is re-sequenced on the fly.

---

## 6. VARIABLE_WATERFALL and REGULAR_WATERFALL

Currently these are static arrays that drive the model's goal funding sequence. In Phase 6, they are rebuilt dynamically from the DB `priority` column each time goals are loaded or reordered.

Special rules that must survive the migration:
- `auto: true` goals (`adam_401k`, `wendy_sep`) are never in the waterfall arrays — they are calculated separately by the model
- `complete: true` goals are excluded from the waterfall
- `status: 'archived'` goals are excluded
- `stretch: true` goals are appended last regardless of priority value (stretch goals don't compete with funded goals)

---

## 7. Handling Special Goal Behaviors

Some goals have behaviors coded directly in `runModel()`. These must continue working after the hardcoded array is replaced:

| Goal | Special behavior | How it survives |
|---|---|---|
| `alaska` | Fund target is `akTarget` (from model_week_override), not `target` field | Model still reads `akTarget` separately; alaska goal just needs to exist in registry |
| `alaska` | `AK_START` week gate — funding doesn't start until Wk 5 | `AK_START` stays hardcoded (it's a model constant, not a goal property) |
| `adam_ira`, `wendy_ira` + 529s | Route to AMEX Savings bucket | `_amxHold` list stays hardcoded in model; matches goal IDs from DB |
| `adam_ira` | `needsFlag: 'ira_cpa_cleared'` blocks until flag set | `needs_flag` column in DB; model reads `gdef.needs_flag` already |
| `wewe_rccl`, `wewe_dcl` | `starts_after: 'alaska'` dependency | `starts_after` column in DB; model reads `gdef.startsAfter` (rename field mapping needed: DB uses `starts_after`, model expects `startsAfter`) |
| `taxable_etf` | `stretch: true` — goes last | `stretch` column in DB |

**Field name mapping:** DB uses snake_case (`starts_after`, `needs_flag`). The model currently uses camelCase (`startsAfter`, `needsFlag`). Options:
- Map in `loadGoals()`: transform snake_case → camelCase before assigning to `GOALS_REGISTRY`
- Update model to read snake_case fields (touches more code; higher risk)

**Recommendation:** Map in `loadGoals()`. One transformation on load, zero model changes.

---

## 8. flags and needsFlag

`flags` is a global object (e.g., `{ira_cpa_cleared: false}`) currently checked in `runModel()`. In Phase 6, flags remain hardcoded — they are toggled via the existing Action Items panel, not the goal registry. The `needsFlag` value on a goal just references the key. No schema change needed for flags.

---

## 9. State Management and Load Timing

`loadGoals()` fires in `initApp()` alongside `loadBudgetRules()`. Both are async; `runModel()` is called only after both resolve (or fail with fallback).

```javascript
async function initApp() {
  await Promise.all([loadBudgetRules(), loadGoals()]);
  runModel(akInit, rtInit);
  renderAll();
}
```

If either load fails, the model runs with the hardcoded fallback for that data source.

---

## 10. Test Plan

**Regression tests (new section GR-A through GR-D):**

| Test | Assertion |
|---|---|
| GR-A1: Model unchanged after migration | GOALS_REGISTRY loaded from mock DB equals hardcoded fallback structure |
| GR-A2: Waterfall order matches priority column | Goals sorted by priority in DB produce identical VARIABLE_WATERFALL to hardcoded |
| GR-A3: startsAfter mapping preserved | `wewe_rccl.starts_after = 'alaska'` in DB → model correctly blocks funding until alaska complete |
| GR-A4: amxHold goals route to AMEX bucket | adam_ira, bailey_529, etc. still accumulate in `amx` balance |
| GR-B1: Paused goal skipped in waterfall | Goal with status='paused' receives zero funding |
| GR-B2: Priority reorder shifts goal ETA | Swap priorities of goals N and N+1 → ETA for N+1 moves earlier |
| GR-B3: Add goal appears in waterfall | New goal added with priority 5 → inserted between existing priority 4 and 6 goals |
| GR-C1: Fallback activates on load failure | Mock fetch failure → GOALS_REGISTRY equals hardcoded array |
| GR-C2: goalsLoadStatus reflects load result | Successful load → 'loaded'; failure → 'failed' |
| GR-D1: snake_case fields mapped to camelCase | DB `starts_after` → `gdef.startsAfter` accessible in model |

**Playwright e2e (new Section GR):**

| Test | Assertion |
|---|---|
| GR-1: Goals tab renders Manage Goals sub-tab | Sub-tab visible and clickable |
| GR-2: Goal list populates from DB | At least one goal row visible in manage view |
| GR-3: Add goal form submits successfully | Fill form, submit, new goal appears in list |
| GR-4: Edit goal updates target | Change target, save, model re-runs with new value |
| GR-5: Pause goal removes from active waterfall | Pause a planned goal, verify it is skipped in model |
| GR-6: Priority reorder updates ETA | Move a planned goal up in priority, verify its ETA moves earlier |
| GR-7: Fallback banner shows on load failure | Simulate offline Supabase → banner appears on Goals tab |

---

## 11. Migration Sequence

1. Create `goals` table in Supabase (schema above)
2. Add RLS policies
3. Run seed INSERT
4. Verify all 13 rows present in Supabase dashboard
5. Add `loadGoals()` to `index.html`
6. Add `goalsLoadStatus` to `budgetRulesLoadStatus` banner rendering
7. Update `initApp()` to await both loads
8. Remove hardcoded `GOALS_REGISTRY`, `VARIABLE_WATERFALL`, `REGULAR_WATERFALL` (keep as commented fallback until tests pass)
9. Add Manage Goals UI panel
10. Write regression tests GR-A through GR-D
11. Write Playwright e2e tests GR-1 through GR-7
12. Run full suite (555 regression + e2e), push

**Do not remove hardcoded fallback until GR-A1 passes cleanly.**

---

## 12. Out of Scope (Phase 6)

- Drag-and-drop priority reordering (V2)
- Goal-level comments or history log
- Per-goal funded amount history (tracked outside model; future phase)
- Goal sharing or export
- Completed goal archiving workflow (Phase 7)
- Multiple waterfall scenarios (Phase 7)

---

## 13. Dependency Note

The Dynamic Goal Registry does not depend on the Waterfall Calculator. They can be built in either order, but Waterfall Calculator is lower risk (no schema changes) and should go first.

---

*Do not build until ChatGPT review is complete and Adam approves.*
