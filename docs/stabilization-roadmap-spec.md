# Herndon Financial OS — Stabilization & Roadmap Spec

**Version:** 1.0  
**Date:** Cal Wk 25 (Jun 21, 2026)  
**Status:** For review — no build authorized until approved

---

## 1. Current System State

### Build baseline
- **Commit:** `9c9992a` (Build stamp fix, Jun 21 2026)
- **Prior commit:** `b82c9f6` (Phase 6A: Dynamic Goal Registry read-only foundation)
- **Deployed:** https://dashboard.herndons.us
- **Regression:** 584 / 0
- **Playwright:** 46 / 0
- **Architecture:** Single-file `index.html`, vanilla JS, no build step, GitHub Pages, Supabase REST backend

### Supabase tables (production)

| Table | Purpose | RLS |
|---|---|---|
| `goals` | KV store for model state (akFunded, ira flags, etc.) | anon read/write |
| `recon_notes` | Week-level reconciliation notes | anon read/write |
| `task_overrides` | Model week event overrides | anon read/write |
| `wishlist_items` | Feature wishlist (loaded but UI is read-only) | anon read/write |
| `custom_tasks` | User-created weekly tasks | anon read/write |
| `budget_items` | KV store for misc budget data | anon read/write |
| `budget_rules` | Recurring/one-time adjustment rules | anon read/write |
| `goal_registry` | Goal definitions (Phase 6A) | anon read-only (SELECT only) |

---

## 2. What Is Now Live and Stable

### Core model
- `runModel(akFunded, retSaved)` — 31-week forward cash flow, weeks 1–31 (Cal Wk 23–53)
- Direct waterfall: surplus above OP_FL sweeps to goals in `VARIABLE_WATERFALL` order each week
- Deferred-not-dropped transfers below MIN_XFR ($100)
- Commission split: 40% tax reserve / 60% waterfall
- Alaska draw: Wk 15 $7,000 pull from savings back to checking
- `REGULAR_WATERFALL` and `VARIABLE_WATERFALL` now dynamically built from `goal_registry` via `applyGoalsFromData()`

### Decision Engine
- Variable income path: tax split → waterfall allocation in priority order
- Regular surplus path: direct waterfall
- IRA gate: `needsFlag='ira_cpa_cleared'` blocks IRA steps until flag cleared

### Budget Rules (Phase 5)
- Recurring and one-time adjustments loaded from Supabase `budget_rules` table
- Applied per-week via `applyBudgetRulesForWeek()` before surplus calculation
- Bypassed (not dropped) when week has a `task_override`
- `budgetRulesLoadStatus` banner on load failure

### What-If Impact Calculator (Phase 5 / WC)
- Single inflow or outflow entry with date and amount
- Runs `diffModels()` comparing baseline vs scenario
- Shows week-by-week goal impact, floor breach weeks, bypassed override weeks
- Does not persist — session-only

### Goal Registry (Phase 6A)
- `goal_registry` table with 13 rows, SELECT-only RLS
- `HARDCODED_GOALS_FALLBACK` ensures model runs before Supabase load completes
- `validateLoadedGoals()`: 9 validation rules (required fields, status enum, duplicate priorities, starts_after chain integrity)
- `goalsLoadStatus`: `'not_configured' | 'loaded' | 'loaded_fallback' | 'failed_validation'`
- Fallback banner on `loaded_fallback` or `failed_validation`
- GR-A1 gate test: DB-mapped goals produce identical model output to fallback

### UI surfaces stable
- Overview tab: deployable surplus, next-dollar decision, model confidence, financial flight path chart
- Weekly Model tab: week-by-week inflows, bills, transfers, actions, reconciliation drawer
- Goals tab: Savings Goals, Priorities, Funding Plan, What-If Impact, Waterfall/Scenarios
- History tab: reconciled and open weeks, filters
- Assumptions tab: model constants
- Wishlist tab: planned/done kanban (read-only)
- Mobile viewport: all tabs reachable without horizontal overflow

---

## 3. Known Risks and Technical Debt

### High priority

**TD-1: model_spec.md is stale**  
Still says "Phase 4 production, 310 tests, Jun 14 2026." Does not cover Budget Rules, What-If Calculator, or Goal Registry. This is the primary source-of-truth document for ChatGPT reviews and it's four phases behind.

**TD-2: No authentication**  
The Supabase anon key is embedded in `index.html` and the deployed URL is public. Anyone who finds the URL can read all financial data. The `goals`, `recon_notes`, `task_overrides`, `budget_rules` tables have anon write access. `goal_registry` is read-only, but the rest are open. This is the highest-risk item before any sensitive data expansion.

**TD-3: Budget rules have no UI management**  
Rules must be inserted/edited directly in Supabase. There is no in-app add/edit/deactivate flow. Adding a recurring rule requires knowledge of the DB schema.

**TD-4: BUILD_TS requires manual update**  
`push_to_github.sh` does not stamp BUILD_TS automatically. It was missed on the Phase 6A push and required a separate fix commit. This will recur on every push unless automated.

**TD-5: e2e cannot run in sandbox**  
`push_to_github.sh` calls `node e2e.js`, which requires Playwright browser deps not available in the sandbox. The sandbox commit + local push pattern means the sandbox's regression run cannot substitute for local e2e. The current workaround (run e2e manually before pushing) is fragile.

### Medium priority

**TD-6: index.html file size**  
The file is now very large (5,000+ lines, single script block). No split is possible without a build step, but the file has become difficult to navigate and the risk of an edit clobbering an unrelated section is growing.

**TD-7: Floor breach projection in live view**  
The Financial Flight Path chart shows red dips below the $6,500 floor in weeks 35–51 on the live app. These are model projections based on goal funding pressure, not bugs. But they are alarming with no explanation in the UI. Users (or reviewers) may mistake a model projection warning for a system error.

**TD-8: START_CHK / START_SAV are hardcoded**  
The model uses fixed starting balances (`START_CHK = 18037.73`, `START_SAV = 3772.77`). These are not updated from the reconciliation data in Supabase. As weeks are reconciled, the model starting point drifts from reality unless the constants are manually updated in the code.

**TD-9: goalsLoadStatus initial state**  
`goalsLoadStatus` starts as `'not_configured'` at page load. The fallback banner logic checks for `loaded_fallback` or `failed_validation`, so `not_configured` produces no banner. But `not_configured` is a fourth state that nothing currently alerts on. If `loadAll()` never fires (e.g., script error before that line), the app silently runs on fallback without any banner.

**TD-10: goal_registry has no updated_at trigger**  
The `updated_at` column exists but has no `BEFORE UPDATE` trigger to auto-stamp it. Manual edits via Supabase dashboard won't update the timestamp.

### Low priority

**TD-11: Wishlist items out of sync with build reality**  
The wishlist `status` values in `index.html` (hardcoded array, not loaded from Supabase) do not reflect Phase 5/6A completions. "Dynamic goal registry" still shows as planned with no distinction between 6A (done) and 6B (future).

**TD-12: No JS error boundary**  
A runtime exception in `renderApp()` produces a blank panel with no user-facing error message. There is no try/catch around the render path with a fallback display.

**TD-13: What-If Calculator has no date validation feedback**  
`dateToModelWeek()` returns null for dates outside the 31-week window, and the UI returns an error state, but the error message is generic. Users don't know whether their date was before or after the model window.

---

## 4. Wishlist / Roadmap Cleanup Recommendations

### Items to re-status

| Current title | Current status | Recommended update |
|---|---|---|
| Dynamic goal registry | planned | Split into: "Goal Registry foundation (6A) — done" and "Goal Registry CRUD (6B) — planned" |
| Goal funding source & destination account | done | Notes are correct; no change |
| Feature wishlist page | done | Correct |
| Scenario preview sandbox | planned | Remains planned — high value, pre-req for commission scenario |
| Commission scenario | planned | Remains planned — high value next major feature |

### Items to add

| New item | Phase | Rationale |
|---|---|---|
| Authentication (Supabase Auth) | Phase 5 | Currently listed as planned; should be moved ahead of account connections |
| Build stamp automation | Stabilization | Automate BUILD_TS in push_to_github.sh |
| Budget rule UI management | Phase 6B | Add/deactivate rules without touching Supabase directly |
| Floor breach explanation overlay | UX | Show tooltip/annotation on red chart regions explaining the projection |
| model_spec.md refresh | Stabilization | Bring documentation current through Phase 6A |

### Phase numbering note
The wishlist uses Phase 3–7 labeling that no longer maps cleanly to the actual build sequence (Phase 5 = Budget Rules, Phase 6A = Goal Registry). Recommend keeping wishlist phase labels as relative priority bands (Now / Soon / Later / Someday) rather than exact phase numbers going forward, since the actual build order has diverged from the original plan.

---

## 5. Recommended Next 3 Phases in Priority Order

### Phase S1 — Stabilization (recommended next)
**Scope:** No model changes. No new features.

1. Update `model_spec.md` to Phase 6A state (584 tests, current architecture, Budget Rules, WC, Goal Registry sections)
2. Automate `BUILD_TS` in `push_to_github.sh` — inject current local timestamp before committing
3. Add `updated_at` trigger to `goal_registry` in Supabase
4. Add `not_configured` guard to fallback banner (TD-9)
5. Add JS error boundary around `renderApp()` with minimal fallback display (TD-12)
6. Update wishlist items in `index.html` to reflect Phase 5/6A completions
7. Add regression tests for reconciliation write path (currently untested at unit level)

**Risk:** Near zero. No model changes, no new Supabase tables, all changes are documentation, tooling, or defensive code.

---

### Phase 6B — Goal Registry Write Capability
**Scope:** Adds write path to `goal_registry`. Model-affecting (waterfall changes when goals are added, paused, archived, or reprioritized).

1. Goal Registry CRUD: add goal, edit name/target/notes, change status (pause/archive/reactivate)
2. Reprioritization: drag-to-reorder or up/down buttons with priority write-back to Supabase
3. `goal_registry` RLS update: add anon INSERT/UPDATE policy (or authenticated write if auth lands first)
4. Regression gate: GR-A1 gate must still pass after any write operation that changes waterfall
5. Confirmation modal before any write that changes waterfall order

**Risk:** High — waterfall is the core of the model. Any write to `goal_registry` that changes priorities, statuses, or starts_after chains directly changes model output. Must run full regression after each write operation type is added.

**Dependency:** Authentication (TD-2) should ideally precede write capability. Without auth, any goal edit is writable by anyone who finds the URL.

---

### Phase 7 — Commission Scenario + Scenario Sandbox
**Scope:** Interactive scenario modeling without committing to Supabase. Model-affecting (runs a second `runModel()` call with hypothetical inputs).

1. Scenario preview sandbox: architecture that runs a shadow model without writing to Supabase
2. Commission scenario: enter gross commission → see 40/60 split, goal impact, timing shift
3. Expense/Inflow scenario: add a one-time event to the model and preview impact
4. Scenario commit flow: if user wants to make a scenario real, commit to `budget_rules` or `task_overrides`

**Risk:** Medium. The shadow model run is isolated from the live model. Risk is in the commit path, which touches `budget_rules` and `task_overrides` (existing tables with existing write paths).

**Note:** The What-If Impact Calculator (Phase 5/WC) is already a lightweight version of this. Phase 7 would make it more structured and add the commission case specifically.

---

## 6. Safe UI-Only vs Model-Affecting Changes

### Safe UI-only (can build without ChatGPT gate review per change)
- `BUILD_TS` automation in `push_to_github.sh`
- `model_spec.md` documentation update
- Wishlist item status updates
- Floor breach explanation overlay / chart annotation
- JS error boundary around `renderApp()`
- `not_configured` banner guard
- `updated_at` DB trigger on `goal_registry`
- History tab filter additions (display only)
- Assumptions tab display improvements

### Model-affecting (require full spec + ChatGPT review before build)
- Any change to `runModel()`, `applyBudgetRulesForWeek()`, `diffModels()`, `decisionEngine()`
- Any change to waterfall construction (`applyGoalsFromData`, `VARIABLE_WATERFALL`, `REGULAR_WATERFALL`)
- Any new Supabase write path that modifies data `runModel()` reads at runtime
- `goal_registry` write capability (Phase 6B)
- Commission scenario (Phase 7)
- Authentication (changes how Supabase credentials work)
- `START_CHK` / `START_SAV` auto-update from reconciliation data

---

## 7. Tests to Add Before More Feature Work

### Currently untested at unit level
| Gap | Proposed test | Section |
|---|---|---|
| Reconciliation write path | Verify `recon_notes` and `task_overrides` Supabase writes produce correct data shape | REC-A |
| Budget rule add/deactivate UI | When a rule is toggled inactive, it is excluded from `applyBudgetRulesForWeek()` | BR-L |
| `not_configured` initial state | Confirm fallback banner does NOT show for `not_configured` (guards against silent fallback) | GR-F |
| `renderApp()` error boundary | Confirm a simulated render error produces fallback display, not blank panel | UI-A |
| `getGoalRemaining()` with DB-loaded goals | Round-trip from Supabase → `mapGoalFromDB` → `getGoalRemaining()` produces correct result | GR-F |
| Floor breach detection | Confirm `diffModels()` correctly identifies negative-cushion weeks in a known scenario | WC-E |

### E2E gaps
| Gap | Proposed test |
|---|---|
| Budget rule add via Supabase → reflected in UI on next load | BR-E2E (requires Supabase write in test setup) |
| `goalsLoadStatus` confirmed 'loaded' on fresh page load (live Supabase) | GR-E2E-6 |
| Reconciliation drawer saves and re-renders correctly | REC-E2E-1 |

---

## 8. Recommendation: What Should the Next Build Be?

**Recommendation: Phase S1 — Stabilization.**

Rationale:

1. `model_spec.md` is the primary artifact ChatGPT reviews before approving any build. It is four phases out of date. That is a structural risk — future spec reviews are being done against stale documentation.

2. `BUILD_TS` automation is a two-line fix that prevents a recurring manual error. Every future push carries the same risk of a missed timestamp until this is automated.

3. Phase 6B (write capability) and Phase 7 (scenarios) both carry meaningful model risk. Entering those with stale documentation, missing tests, and no authentication is a compounding risk that will be harder to unwind later.

4. The stabilization pass has near-zero regression risk and produces a cleaner baseline for the next major feature review.

**Proposed build sequence:**
1. Phase S1 (stabilization) — next build, low risk
2. Authentication — before any write capability goes to production
3. Phase 6B (goal registry writes) — after auth, with full spec review
4. Phase 7 (scenario sandbox) — after 6B stabilizes

**What Phase S1 is NOT:**
- Not a pause on feature development
- Not a rewrite of the architecture
- Not adding new tabs, views, or model behavior
- Just closing the documentation and tooling debt before the next model-affecting build

---

*For review. No build authorized until ChatGPT approves scope.*
