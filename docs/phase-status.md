# Herndon Financial OS — Phase Status

## Roadmap Sequence (as of 2026-07-06)

| Phase | Name | Status |
|-------|------|--------|
| 5E-1 | SQL Foundation + Read-Only Register Shell | Complete |
| 5E-2 | Transaction Writes | Complete |
| 5E-3 | Register Live by Default | Complete |
| 5E-4 | Budget Correctness + Display Fixes | Complete |
| 5E-5 | Budget Line Admin (required before 7/1) | Complete |
| 5E-6 | Monthly Entertainment Buckets | Complete |
| 5E-7 | Role Enforcement / Security Maturity Gate | Complete — live P8/V12 verified (2026-06-30) |
| 5E-8 | 7/1 Wendy Operating Readiness | Smoke passed — conditionally ready pending 7/1 starting balance setup (2026-06-30) |
| 5E-9 | Category Registry Admin | Deferred (unless 7/1 blocker found) |
| 5F-0 | Needs Attention / Dashboard Usefulness | Planned, not started |
| 5F-1 | Reconciliation + Cash Availability Engine | Complete through Phase 4; Week 26 closeout proven in prod 2026-07-04; 2 deferrals (below) |
| 5F-1.5 | Gate A: Wendy July usability | Live (2026-07-05/06); A4 done |
| 5F-2 | (former) Reconciliation Writes | Absorbed into 5F-1 (writes shipped via save_reconciliation_with_commitments RPC) |
| 5G | Cash Planning + Allocation | Next major phase; 5G-0 complete (2026-07-07); 5G-1 staging DB/security layer validated (2026-07-08), prod DDL + app build not started |
| 5H | Register capture speed + mobile quick-add | Not started |
| 5I | Splits (was 5G) | Not started |
| 5J | Month-end close hardening + minimal goal editing | Not started |
| 5K | Transfers (was 5H) | Not started |
| 5L | Architecture hardening / broader modularization | Not started |

**5F-1 deferrals (neither blocks forward closeout):** (1) dashboard Review Required verdict-text rendering; (2) historical repair mode via `repair_commitments_for_week`. Cash Availability Engine is live; `cash_commitments` exists and is part of the architecture. Verified repo baseline: static 1332/0, E2E 130/0.

**Later / unlettered backlog (not yet lettered):**

- Import Readiness (former 5I)
- Budget Integration / Actuals (former 5J); A2 income actuals remains a specific gate before 5G-3
- Old 5G Splits and 5H Transfers are relettered to 5I and 5K above, not dropped.
- **TX-1 — Transaction Category Integrity + Income Taxonomy + Budget Attribution** (future candidate, not sequenced, NOT UX-0.5). Register data-quality workstream: source-accurate BKCPA Extra Pay income category (`income.bkcpa_extra_pay` / `commission_income` / `display_only`), reimbursement/offset categories, required-category + save validation for manual transactions, uncategorized review/filter + cleanup list, and budget-period attribution/carryover ("covered by June" vs current-month Extra). Coordinates with the 5F-3 month-boundary/carryover backlog item but is distinct (funding-period of a correctly-dated, correctly-categorized charge). No Weekly Model cash-math changes unless explicitly required; no duplicate inflow/tax rule/goal allocation. Full definition + three motivating examples: `docs/tx-1-candidate.md`.

### Phase 5G: Cash Planning + Allocation (NEXT MAJOR PHASE — 5G-0 COMPLETE; 5G-1 STAGING DB/SECURITY LAYER VALIDATED 2026-07-08; PROD DDL + APP BUILD NOT STARTED)

Locked scope. Supersedes the earlier 5G = Splits assignment. One backend entity (`planned_outflows`) and one append-only event table (`outflow_events`). Upcoming Spend and Save-Up Bills are Wendy-facing groupings of `planned_outflows`, not separate backend systems. The Cash Allocation view is derived (Spoken For / Free to Use), never a manually maintained ledger. No fake Budget Clearance account, no fake Register transactions. Register stays source of truth for actual spend; Budget stays plan / spent / remaining / reporting. `misc.goal_sweep` key does not change. Full domain/funding taxonomy is canonical in AI Context 05; this section is the phase/gate map.

| Sub | Name | Timing | Status |
|-----|------|--------|--------|
| 5G-0 | Roadmap/label cleanup; rename "Extra Pay Going to Spreadsheet" to "Available for Goals"; no logic change | Pre-Alaska | Complete (2026-07-07); static 1332/0, e2e 131/0 |
| 5G-1 | planned_outflows + outflow_events schema; seed Mint Mobile; append-only Set Aside / Paid / Adjust; opening adjustment from dated snapshot on posted balances; Mint rows transfer_funded to AMEX Savings; auto_renew=false | Pre-Alaska | Staging DB/security layer validated (rehearsal + RLS smoke + `app_environment` hardening, 2026-07-08; `eeee4cb`/`7f0d0a0`); prod DDL + app build not started |
| 5G-2 | Derived Account Allocation view (Spoken For / Free to Use); no stored allocation balances | Pre-Alaska | Not started |
| 5G-2.5 | Calculation Core Extraction / Characterization under golden-master tests; no framework, no UI refactor, no build step | Post-Alaska | Not started |
| 5G-3 | Budget identity change; Available for Goals becomes derived; hand-balancing retired; budgeted income lines only; variable income stays model-side under tax lock/waterfall | Post-Alaska; gated on Wendy feedback + A2 income actuals | Not started |
| 5G-4a | Set-aside transfer recommendations + shortfall warnings; Checking-to-AMEX must pass AMEX lookahead / max-safe-sweep gate; deferred set-asides derived (accrued minus funded), not stored | Post-Alaska | Not started |
| 5G-4b | Earmark-funded adapter into 5F-1 Cash Availability Engine; input layer only; no engine internals modified; zero-outflow identity gate as committed automated test | Post-Alaska | Not started |
| 5G-5 | Spreadsheet retirement after one clean parallel month | Post-Alaska | Not started |

**5G-0 complete (2026-07-07):** Label/docs cleanup only. "Available for Goals" visible rename done (`misc.goal_sweep` key unchanged); SYS-1 (Budget block retitled "Statement check", user-facing phase strings stripped), SYS-4 (exact-string plain-language: Clr→Cleared, Model→Planned / Transfer→Custom chips, Budget Rule→Budget Line, "registry keys"→"categories", register reconciliation hint reworded), and WK-6 (banner pluralization) complete. No Budget identity, model/runModel, reconciliation-engine, schema/RLS/RPC, or Cash Planning changes. Tests: static regression 1332/0, e2e 131/0. BUD-1/BUD-2/SYS-3 remain routed to UX-0 (not 5G-0). Full detail in CODEX_STATUS.md "5G-0 CLOSED".

**5G-1A shipped (2026-07-07, commit `c8613bc`):** narrow surgical hotfix between 5G-0 and 5G-1 (not a formal roadmap sub-phase). Wewe RCCL ($600) / Wewe DCL ($500) reclassified from the untracked `'goal'` sentinel to AMEX Savings holding — same waterfall funding decision and checking deduction, modeled AMEX Savings +$1,100 in Week 27; holding labels + paycheck-cleared readiness note. No schema/RLS/RPC/SQL; IRA/529, Alaska, LC boost, floors, `_amxHold` unchanged. Static 1339/0, e2e 131/0. Holding→payout lifecycle deferred to 5G-1B. Full detail in CODEX_STATUS.md "5G-1A SHIPPED".

**5G-1A.5 committed (2026-07-08, commit `f307db7`, local `main` — NOT yet pushed): AMEX Hold Sub-MIN_XFR Deadlock Hotfix.** Phase A of the 2026-07-08 funding-model integrity review (`docs/funding-model-integrity-review-2026-07-08.md`); runModel freeze exception approved by Adam. An `_amxHold` goal left with a sub-`MIN_XFR` (<$100) remainder passed through `maxSafeAmxSweep()` (which floors any amount below MIN_XFR to 0) before `mv()`; the 0 triggered defer+`break`, permanently starving every lower-priority goal (Adam IRA stuck 7438.94/7500 = 99% after the `1dcc686` IRA correction; Wendy IRA + all 529s $0 from Cal Wk 28, Bailey "Beyond 2026"). Fix: completion carve-out at the `_amxHold` call site mirroring the existing `mv()` `allowFin` rule, gated by the existing 5-week `amxSweepKeepsFloor` check (floor-unsafe sub-$100 sweeps still defer); defer-label accuracy (below-$100-minimum vs genuine floor risk); `retRem` sourced from the registry Adam IRA target ($7,500), not hardcoded 7000. runModel freeze exception approved. `index.html` + `test_regression.js` only; no schema/RLS/RPC/SQL, no priority/target/reconciliation changes; Week 27 transfer outputs byte-identical. Static **1359/0**, e2e **131/0**; Adam live-smoked the local build (Adam IRA completes Cal Wk 29, Wendy IRA continuation, Week 27 unchanged, floor-risk label preserved). Bailey 529 reaching 73% with the stale "Beyond 2026" row label is a live-surplus/projection-semantics property → **5G-1C follow-up, not a blocker**. Full detail in CODEX_STATUS.md "## 5G-1A.5 SHIPPED". Next: **5G-1C — Goal Funding State Integrity + Funding Plan Projection Semantics** (review doc §5/§7 Phase B: week-anchored `goal_funding_snapshots`).

**UX-0 shipped (2026-07-07):** display-only Budget row treatment (BUD-1/BUD-2/SYS-3), not a formal roadmap sub-phase. New `_budgetRowState` drives per-row red/amber/neutral Remaining semantics (near-limit only for Budget ≥ $100 lines at ≥ 90% spent AND ≤ $100 remaining; sub-$100 lines never amber); expense-leaf over-budget shows a red value + "Over by $X" badge (parents/total: value treatment only, no badge); income Remaining is muted "expected" (amount preserved), never red/amber/green; BUD-2 empty-state explanatory copy + live Open Register link; SYS-3 retires red from Archive/Delete/Confirm controls (amber-dark confirms). Green "Budget balanced" check unchanged. `index.html` + `test_regression.js` only; no schema/RLS/RPC/SQL, no `runModel`, no reconciliation/account-routing. Static **1344/0**, e2e **131/0**; desktop visual review passed. Full detail in CODEX_STATUS.md "## UX-0 SHIPPED".

**UX-0.5 shipped (2026-07-07, commit `739567b`):** Wendy visual polish, display-only, not a formal roadmap sub-phase. Budget: B1 color/status legend, B2 attention summary strip (over/near line counts tallied inside the expense-leaf loop so the strip matches the grid; Income expected clamped to ≥ 0; Planned remaining = `totalRem`), B3 stronger section-header hierarchy, B4 "Over by $X" badge rhythm. Register: R1 cleaner reconcile helper bar (trimmed reconcile-against-bank hint), R2 edit/delete affordance (larger targets, tooltips, aria-labels). New UX-0.5 borders use the defined `--line` token, not the undefined `--border`. No UX-0 semantics changed (thresholds, red/amber/neutral, "Over by", income "expected"). `index.html` + `test_regression.js` + `e2e.js` (R1 caption wording only); no schema/RLS/RPC/SQL, no `runModel`, no reconciliation/account-routing, no transaction workflow changes. R3 (uncleared-row treatment) deferred. Static **1350/0**, e2e **131/0**; desktop visual review passed. BUILD_TS stamped to `2026-07-07T18:22:06` (pre-commit hook, normal code-commit behavior). Next candidate is **5G-1** behind existing gates. Full detail in CODEX_STATUS.md "## UX-0.5 SHIPPED".

**5G-1 staging DB validation complete (2026-07-08):** the 5G-1 **DB/security layer** was validated on staging `pkwotgqivgaapwuqgwqb` and pushed — **NOT** a full 5G-1 ship. Schema rehearsal (marker → preflight → migration → validation V1–V10 incl. V4h/V4i grant checks → seed → rollback, staging clean) plus the real-caller **RLS behavioral smoke**: **Gate 1** (SQL role-impersonation) passed after correcting the smoke model to the deployed `auth.uid()` gate (both `is_allowed_user()` and `can_write_financials()` key on `auth.uid()`; Phase 4B migrated off email); **Gate 2** (real Auth→JWT→PostgREST) passed **18/18** across anon/unauthorized/viewer/writer; **FK-safe cleanup** returned staging to clean baseline. `app_environment` RLS-hardening (REVOKE ALL from anon/authenticated + ENABLE RLS, no policies) validated on staging. Commits: RLS smoke `eeee4cb`, hardening `7f0d0a0` (both pushed). **Production untouched; `showCashPlanning` remains off/absent.** Still gated before any production/app work: Mint vendor/amount/date confirmation, prod DDL approval, app-side ES modules, `showCashPlanning` enablement. Precise status: **5G-1 staging DB/security layer validated; production DDL and app build still gated.** Detail in CODEX_STATUS.md RLS-smoke paragraph.

**Pre / post-Alaska:** 5G-0 through 5G-2 are pre-Alaska candidates. Only 5G-0 is safe to start before a staging Supabase exists; 5G-1 requires a staging Supabase plus a baseline export via `scripts/export-ai-review-pack.sh` (both now in place; the 5G-1 staging DB schema + RLS were validated 2026-07-08 and torn down clean). 5G-2.5, 5G-3, 5G-4a, 5G-4b, 5G-5 are post-Alaska unless explicitly pulled forward after review. 5G-3+ also gates on Wendy feedback. Freeze window: **July 24 through August 10** (no 5G merges in that window).

**Gates:**

- Before 5G-3: Wendy response on Budget / Available for Goals workflow; A2 income-actuals sequencing; calculation-core extraction (5G-2.5) complete.
- Before 5G-4a: Diablos/GLP WD gap fixed as a separate task; WC-3 disposition resolved or formally quarantined; fresh baseline weekly-model output captured after the WD fix; safe-sweep gate inside the extracted calculation/recommendation layer and characterization-covered.
- Before 5G-4b: zero-outflow identity gate exists as an automated committed test; reserve/commitment precedence rule added to the closeout checklist (if an actual payment enters reconciliation as a Phase 3 manual commitment in a due week, the outflow release is recorded in the same closeout so reserve and commitment never overlap).

**Funding modes:** `transfer_funded` (money moves to the funding account; allocation sits against that account; no checking reserve adapter) vs `earmark_funded` (money stays in checking, becomes reserve-shaped adapter records for the Cash Availability Engine). Mint v1 is `transfer_funded` to AMEX Savings.

**Out-of-window planned_outflows:** not `model_year`-pinned; real `due_date`, may fall outside the weekly model window ending 2027-01-09. Adam Mint due 2027-02-01 and Bailey Mint due 2027-05-23 accrue set-asides and show in allocation views but produce no in-window release event.

**Architecture:** stay vanilla JS + GitHub Pages; no framework, no build step, no replatform before 5G. New 5G code lands as ES modules in separate files (data / domain / view separation), not appended to the index.html script body; 5G-0 exempt (label/docs only). index.html limited to minimal mount/import points; local verification needs a static server, not file://. Extract the calculation core under golden-master / characterization tests before 5G-3 / 5G-4.

**Do not touch during 5G-0 through 5G-2:** runModel, WD/effectiveWD, cash_commitments internals, reconciliation RPCs. Full list in AGENTS.md "Do Not Touch".

**Stale spec warning:** `docs/dynamic-goal-registry-spec.md` (June 21 draft) is NOT implementation authority. Shipped reality is `goal_registry`, authenticated SELECT-only, hardcoded fallback, GR-A1 identity gate. New 5G tables must not inherit anon RLS patterns.

### UI & Flow Review Inputs (2026-07-07 v2)

The 2026-07-07 UI/flow review (`docs/reviews/ui-flow-review-triage-2026-07-07.md`) is a **triage input, not implementation authority.** Its 24 findings are hypotheses; **Wendy-confirmed workflow overrides them.** It does **not** change 5G scope, architecture, gates, or the Do Not Touch list above. Do not treat all 24 findings as immediate work.

**5G-0 fold-ins** (in-charter label/docs cleanup; must land before 5G-1 introduces Spoken For / Free to Use):

- SYS-1: reconciliation naming cleanup (rename Budget block to "Statement check", strip leaked phase strings, reserve "Reconcile" for the weekly flow)
- SYS-4: plain-language string sweep — exact strings only, no logic change
- WK-6: pluralization fix ("1 current-week protected obligation…")

**Pre-5G UX cleanup candidate** (display/routing only; no schema, model math, reconciliation engine, Register schema, Budget identity, or nav grouping. Hard cap — do not let it grow into a phase; cut the rider first):

- FLOW-2: default Transactions to Register
- FLOW-1: make the Budget helper a live Register link (button stays disabled per Wendy's confirmed flow)
- WK-1: fix transfer status vs task-check semantics (adopt existing Accounts status pills)
- REG-1: make the Register filtered state obvious
- SYS-2: standardize money formatting (separators, one negative convention)
- optional rider — REG-2: Uncleared/Cleared group labels, only if the Register table is already open (sort order untouched)

**Wendy 5G Budget mockup inputs** (settle in the mockup, not as pre-5G cleanup):

- BUD-1: red / over / near / under semantics — settle the income-red vs expense-red collision first
- BUD-2: Budget empty state and the "actuals reconcile through Register" story
- SYS-3: row-action (Archive/Edit) treatment so red is reserved for real money alerts

Mockup spec (treatment authority for BUD-1/BUD-2/SYS-3 and the 5G mock frames): `docs/specs/wendy-5g-budget-mockup-spec-2026-07-07.md` (v1.2, final). BUD-1/BUD-2/SYS-3 shipped as the display-only UX-0 slice on 2026-07-07 (static 1344/0, e2e 131/0; see CODEX_STATUS.md "## UX-0 SHIPPED"), after 5G-0 and not into it.

**5H candidates** (capture speed / entry assistance — 5H's charter; do not build early):

- REG-5: payee suggestions while typing
- REG-4: uncategorized surfacing (count + filter)
- FLOW-4: desktop quick-add

**Nav decision (confirmed):**

- No full left-nav regroup now.
- FLOW-2 is the minimal nav fix.
- 5G launches as one new "Cash Planning" item under Planning, next to Goals — nothing else moves.
- A broader regroup waits for a single later decision, triggered by 3+ weeks of Wendy's real 5G usage (top anchor Weekly Model / bottom anchor Transactions preserved).

---

### Phase 5E-5 — Budget Line Admin (COMPLETE + HARDENED, 2026-06-27 — browser smoke PASSED)
Minimal Budget Rule Admin UI inside the Budget tab.

**What shipped (base):**
- "Manage Lines" button in Budget header (write users only) — opens Add modal
- Inline "Edit" and "Archive" buttons on each budget line row (expense rows: both; income rows: Edit only)
- **Edit modal**: label + amount editable; scope locked to "from selected month forward" only
  - Closes prior active row at end of prior month (or deactivates if row started same month)
  - Inserts replacement row starting selected month, preserving original `end_month`
  - Income warning banner when editing income lines
  - Shows "Effective Range: From [month] through [end] / onward (open-ended)"
- **Add modal**: category key from existing `BUDGET_CATEGORY_REGISTRY` leaf keys only (no free-form keys)
  - Scope: one-time (start=end=month) or ongoing (start=month, end=null)
  - Keys with an active overlapping rule for selected month shown as disabled
- **Archive modal**: shows what will happen before confirming
  - Case A (has prior history): closes row at end of prior month, preserves all history
  - Case B (started this month): sets `is_active = false`
  - No hard delete under any circumstance
- After each save: reloads `budget_line_rules` cache from Supabase and re-renders Budget
- Total Income / Total Planned Budget / Budget Balance recalculate automatically after each change
- No auto-forcing rebalance — out-of-balance warning shown; Adam decides what to adjust
- `canWriteFinancials()` guards all `_blrOpen*` functions — Adam (owner) and Wendy (household_admin) both see and can use Manage Lines, Edit, and Archive; this is intentional — budget rule management is household operational work, not platform admin; unauthenticated users see no admin controls; future viewer role enforcement deferred to 5E-6

**Hardening patch (same commit session):**
- `_blrDupCheck` (point-in-time) replaced by `_blrHasOverlap` (full interval overlap)
  - Two intervals overlap when `new_start <= existing_end AND existing_start <= new_end`
  - Open-ended rows use FAR sentinel `9999-12-01` for comparison
  - One-time July add correctly does NOT conflict with an August-forward row
  - Ongoing July-forward add correctly IS blocked by an August-forward row
- `_blrSaveEdit`: replacement row now inherits `currentRow.end_month` (not hardcoded null)
- `_blrSaveEdit`: best-effort rollback — if replacement INSERT fails after the close/deactivate PATCH succeeds, attempts to restore the prior row to its original state; error message distinguishes clean rollback from double-failure
- `_blrSaveEdit`, `_blrSaveAdd`, `_blrSaveArchive`: all have direct `canWriteFinancials()` guards (defense-in-depth; RLS is the real gate)
- Add modal dropdown disable: updated to use `_blrHasOverlap` for point-in-month check
- Smoke checklist AC-10a added: edit a bounded row, confirm January (after end_month) stays clean

**Regression tests:**
- 18 base tests (5E5-01 through 5E5-18)
- 10 hardening tests (5E5-H01 through 5E5-H10)
- **28 total 5E-5 tests; 813/813 full suite passing**

**Explicit scope limitations (documented, deferred):**
- "Selected month only" edit (three-row split) NOT in 5E-5 — deferred to future phase
- New category creation (keys not in `BUDGET_CATEGORY_REGISTRY`) NOT in 5E-5
  - Any key not in BUDGET_CATEGORY_REGISTRY will not render in the Budget table
  - Full Category Registry Admin deferred to 5E-8 or later
- Entertainment sub-buckets (e.g. streaming, events) NOT in 5E-5
  - `entertainment` is currently a standalone leaf key with no parent/child structure
  - Adding sub-buckets requires converting it to a parent node + adding child keys in BUDGET_CATEGORY_REGISTRY + DB migration
  - Deferred to 5E-6 (Monthly Entertainment Buckets)

**No schema change.** All operations use existing `budget_line_rules` table and REST API.

**Browser smoke result (2026-06-27):** PASSED — AC-1 through AC-10a all passed.
Post-smoke state: Total Income $15,938, Total Planned $15,938, Balance $0, misc.goal_sweep $1,450, misc.extra $1,869, Diablos $750.

---

### Phase 5E-4 — Budget Correctness + Display Fixes (COMPLETE, 2026-06-27)
**What shipped:**
- Fixed Budget topbar subtitle (was bleeding Register account name)
- Removed `misc.goal_sweep` exclusion from totals — now included in Total Planned Budget
- Renamed "Monthly Living Expenses (excl. goal sweep)" to "Total Planned Budget"
- Budget balance row drives from `incomeTotal` (from budget lines), not hardcoded $15,938
- Out-of-balance warning: amber banner + explanation when plan ≠ income
- Balanced confirmation: green checkmark when plan = income
- `misc.goal_sweep` row annotated as "(flexible sweep line)"
- Help text updated: Extra Pay is the usual sweep line; Misc → Extra or other discretionary can also absorb changes
- Reconciliation section on Budget annotated with transitional note (moves to Transactions in 5F-2)
- July SQL patch: `docs/phase-5e-4-july-budget-patch.sql` — closes $2,300 goal_sweep at June, opens $1,450 for July+
- 12 new static regression tests (5E4-01 through 5E4-12); 785/785 passed
- Updated stale tests: 5B-24 (label change), 5E1-01 (flag now defaults true)

**Non-goals:** No `_getBudgetLivingExpenses()` changes (feeds runModel — untouched). No new schema. No Budget Line Admin UI (that's 5E-5).

---

### Phase 5E-6 — Monthly Entertainment Buckets (COMPLETE, 2026-06-27 — browser smoke PASSED)

Split the `entertainment` standalone leaf into 10 reusable monthly child slots for July 1 Wendy budget usability. Scoped narrowly — not full Category Registry Admin.

**What ships:**
- `entertainment` converted from `leaf:true, assignable:true` → `leaf:false, assignable:false` parent node in `BUDGET_CATEGORY_REGISTRY`
- 10 child slots added: `entertainment.event_1` through `entertainment.event_5`, `entertainment.week_1` through `entertainment.week_5`
- Registry-based selectable design: child keys selectable in dropdown regardless of BLR existence
- `_getCategoryDisplayLabel(key, monthIso)` — shared helper; returns BLR `line_label` when active, falls back to registry label
- `_txDateToMonthIso(dateStr)` — converts `'YYYY-MM-DD'` to `'YYYY-MM-01'`
- `_blrCheckEntertainmentDupLabel(...)` — interval-aware duplicate label guard for entertainment.* child keys
- Budget grid child rows use `_getCategoryDisplayLabel(c.key, monthIso)` — shows BLR label not registry key
- Transaction form dropdown uses date-aware month for label resolution; scoped div re-render on date change (no scroll regression)
- Transaction register displays category label keyed to transaction's own date (constraint 1 — non-negotiable)
- Legacy rollup: `spentByKey[parent.key]` and `_getBudgetAmount(parent.key, monthIso)` folded into group totals when `!isStandalone` — preserves June history after entertainment becomes a parent
- Legacy `entertainment` category_key shows as "(legacy — re-categorize)" option in edit form dropdown

**July 2026 activation plan (via SQL migration):**
| Child Key | Line Label | Amount |
|---|---|---|
| entertainment.event_1 | Seattle | $300 |
| entertainment.event_2 | Wewe's Lunches | $200 |
| entertainment.week_1 | Entertainment Week 1 | $250 |
| entertainment.week_2 | Entertainment Week 2 | $250 |
| entertainment.week_3 | Entertainment Week 3 | $250 |
| entertainment.week_4 | Entertainment Week 4 | $250 |
| **Total** | | **$1,500** |

event_3, event_4, event_5, week_5 remain inactive for July (no BLR rows). Budget Line Admin can activate them for any future month.

**Wendy operating convention — July 2026:**
- Week 1: July 1–7 | Week 2: July 8–14 | Week 3: July 15–21 | Week 4: July 22–31
- No date enforcement in app. Household convention: assign to the week when spending occurred.
- Event buckets (Seattle, Wewe's Lunches): assign to the event bucket, not weekly.

**SQL files (all in docs/):**
- `phase-5e-6-preflight.sql` — 10 read-only pre-migration checks
- `phase-5e-6-migration.sql` — 3 hard-stop DO/RAISE guards + close parent + 6 child inserts
- `phase-5e-6-validation.sql` — 11 read-only post-migration checks
- `phase-5e-6-rollback.sql` — restore parent rule + deactivate child rows

**Hardcoded hard-stop guards (migration):**
1. Exactly 1 active parent entertainment rule covering July must exist
2. No existing active July rows for 6 activated child keys
3. No existing active July rows for 4 inactive slots

**Legacy rollup safety:** Only parent key has direct BLR rows or transactions. All other groups in registry have no direct BLR rows, so rollup is a no-op outside entertainment.

**Explicit scope out (deferred):**
- No Category Registry Admin UI (free-form key creation)
- No week_5 activation for July (no Wendy use case)
- No entertainment.event_3/4/5 activation for July

**Expected July state (post-migration):**
- Entertainment group total: $1,500 (6 children)
- Overall July: Income $15,938, Planned $15,938, Balance $0
- June: Entertainment still shows $1,500 (legacy parent rule, closed at June)

**Regression tests:**
- 24 tests (5E6-01 through 5E6-24)
- **837/837 full suite passing (2026-06-27)**

**Smoke checklist:** `docs/phase-5e-6-smoke-checklist.md` — 12 ACs covering group render, July balance, June history, future months, label display, admin edit/add, transaction dropdown date-awareness, register display, legacy transactions, dup label guard, inactive slot visibility.

**Browser smoke result (2026-06-27):** PASSED — ACs 1–9, 11–12 passed; AC-10 N/A (no legacy entertainment transactions).
Post-smoke state: Entertainment group $1,500 budget, balanced at $0 for July. June history correct at $1,500. August intentionally empty (by design — Manage Lines for future months).

---

### Phase 5E-7 — Role Enforcement / Security Maturity Gate (COMPLETE — live verified 2026-06-30)
Absorbs deferred Phase 4C. Hardens and audits all write-path role enforcement before any 5F+ work begins.

**What shipped:**

**PASS A — SQL audit files (read-only, no mutations):**
- `docs/phase-5e-7-preflight.sql` — 8 checks (P1–P8) querying live `pg_policies`
- `docs/phase-5e-7-validation.sql` — 15 checks (V1–V15) for post-change validation
- `docs/phase-5e-7-smoke-checklist.md` — browser smoke script: SA-1/SA-2, AC-1–AC-15 (Adam), WC-1–WC-11 (Wendy), VC-1–VC-11 (viewer)
- P8/V12 = STOP CONDITION: `budget_line_rules` write policies — if live = `is_owner()`, migration required before 5E-8

**PASS B — App-side write-path guards (defense-in-depth; RLS is the real gate):**

*Current Register (`transactions`):*
- `_openTxForm`, `_saveTxForm`, `_confirmTxDelete`, `_toggleTxCleared` — all guarded with `canWriteFinancials()`
- Register "Add Transaction" button — gated on `canWriteFinancials()`
- Per-row cleared checkbox — `disabled` for non-writers; still visible as static indicator
- Per-row Edit/Delete buttons — hidden for non-writers (inside `if(isManual){if(canWriteFinancials())...}` — preserves test-compatible gate structure)

*Legacy Budget actuals (`budget_transactions`):*
- `_budgetOpenAddForm`, `_budgetSubmitForm`, `_budgetSaveTransaction`, `_budgetToggleCleared`, `_budgetDeleteTransaction`, `_budgetStartEdit` — all guarded
- Budget "Add Transaction" button — gated
- Budget per-row cleared/edit/delete controls — gated; shows read-only cleared indicator (`✓`) for non-writers

*Scenario commits:*
- `openScenarioCommit`, `commitScenario` — guarded; `commitScenario` checks `_csr.ok` before `overrideData` mutation
- `commitScenario` goal path — `goalAk`/`goalRt` NOT updated until both `saveGoal` calls return `true`; `clearScenario()` not called if either fails
- "Commit to live model" button in modal — hidden for non-writers; shows read-only message instead
- Commit button in scenario banner — gated via `canWriteFinancials()` ternary

*Goals:*
- `saveGoal` — returns `true/false` based on `r.ok`; callers that depend on success must check return value
- `saveGoal` split guard: `anthropic_key` → `isOwnerUser()`, all other keys → `canWriteFinancials()`
- `saveApiKey` — `isOwnerUser()` guard; key not cached in memory or localStorage unless Supabase returns 2xx
- `anthropicKey` variable initialized to `''`; populated only in `loadAll()` after `isOwnerUser()` check

*Ask Claude:*
- `renderAskClaude` — non-owner branch shows "available to account owner only" message; key input never shown
- `sendAsk` — guarded with `isOwnerUser()` return-early
- "Change key" button clears `anthropicKey` and `localStorage` on click

*Custom task UI gates and mutation ordering:*
- Type badge, checkbox, delete/dismiss buttons gated on `canWriteFinancials()` in render
- Add transfer / Add task buttons and inline forms gated on `canWriteFinancials()`
- `saveCustomTaskMeta` returns `bool`; `flipCustomTaskType`, `saveCustomTask`, `toggleCustomTask`, `deleteCustomTask`, `dismissAutoReminder` all snapshot-then-optimistic with rollback on `r.ok` failure
- `saveRecon`, `toggleTask`, `saveNote` — all snapshot-before-optimistic, roll back on `r.ok` failure
- `saveWeekEdits` `autoCustomTask`/`autoCustomTaskGoal` branches — await + `r.ok` checks; rollback on PATCH failure; local task added only if POST succeeds

*Action overrides:*
- `openActionEdit`, `saveActionOverride`, `deleteActionOverride`, `resetAllActionOverrides` — all guarded
- Override controls in week render — hidden for non-writers

*Legacy stubs:*
- `moveCustomTask`, `editCustomTaskLabel`, `editCustomTaskDate` — replaced with no-ops; warn only; no longer call Supabase

*loadAll migration:*
- `anthropicKey` from `goals` table: only loaded when `isOwnerUser()`; only cached to localStorage when `isOwnerUser()`
- `localStorage` migration of `custom_tasks` — guarded on `canWriteFinancials()`; `removeItem` only called if POST succeeds

*Wishlist/Roadmap:*
- `seedWishlist`, `mergeSeedWishlist`, `phaseMigrateWishlist` — skipped for non-writers inside `loadWishlist`
- `phaseMigrateWishlist` — every PATCH now captures `r`; local fields only mutated if `r.ok`
- `saveWishlistItem` PATCH path — `r.ok` check before updating `wishlistData`; returns early on failure
- `deleteWishlistItem` — local filter only runs after `r.ok`; leaves state intact on failure
- `moveWishlistItem` — captures PATCH `r`; local update and `renderApp()` only on `r.ok`; returns `bool`
- `_confirmDoneWishlist` — async; `wishlistDoneId` cleared only after `moveWishlistItem` returns `true`
- Add buttons (Planned column, Ideas column) — hidden for non-writers
- Add form — not rendered if `!canWriteFinancials()`, even if `wishlistAddOpen` state is stale
- `card(it,...)` render calls — `canWriteFinancials()` passed as editable flag; non-writers see read-only cards

*Weekly write paths (previously patched):*
- `toggleCustomTask`, `flipCustomTaskType`, `saveCustomTask`, `deleteCustomTask`, `dismissAutoReminder`, `saveCustomTaskMeta`
- `saveNote`, `toggleTask`, `openRecon`, `saveRecon`, `deleteRecon`, `confirmReconDelete`
- `openEdit`, `addEditEvent`, `saveWeekEdits`, `confirmEditDelete`, `deleteWeekOverride`
- Reconcile button, task checkboxes, notes textarea — all role-gated in render

*Optimistic mutation ordering fixed:*
- `deleteRecon` — `delete reconData[n]` now inside `if(r.ok)` (was running before network call)
- `deleteWeekOverride` — `delete overrideData[n]` now inside `if(r.ok)` (was running without capture)
- `_budgetDeleteTransaction` — `filter` now inside `if(r.ok)`
- `commitScenario` — `overrideData[payload.week_num]=payload` now inside `if(_csr.ok)`

**PASS C — Regression tests (see test_regression.js):**
- ROLE-C (5E7-C1–C6): `canWriteFinancials()` classification — owner/household_admin=true, viewer/empty/unknown=false
- ROLE-D (5E7-D1–D5): Register write-path guards
- ROLE-E (5E7-E1–E5): Budget write-path guards
- ROLE-F (5E7-F1–F3): `saveGoal` returns false on permission; split guard; `saveApiKey` owner guard
- ROLE-G (5E7-G1–G6): Wishlist write-path guards and r.ok ordering
- ROLE-H (5E7-H1–H3): Scenario commit guards and goal path ordering
- ROLE-I (5E7-I1–I3): Optimistic mutation ordering (`r.ok` before local delete)
- ROLE-J (5E7-J1–J6): SQL audit file existence and content
- ROLE-K (5E7-K1–K2): `is_allowed_user()` never used as write guard; smoke checklist P8 reference
- ROLE-L (5E7-L*): Action override guards, legacy stub no-ops, custom task UI gate strings, `anthropicKey` init
- ROLE-M (5E7-M*): Wishlist Add button gate strings, V13 per-row SQL format, P2/P3/P8 zero-policy SQL format, V5a negative condition
- Existing tests S30-4 and S30-6 updated: `USER_ROLE='owner'` set for the test duration
- **Full suite passing after all Items 1–11 applied — exact count updated in test_regression.js header**

**Final role matrix:**

| Role | `canWriteFinancials()` | `isOwnerUser()` | Household operational writes | Owner-only writes | Read |
|---|---|---|---|---|---|
| `owner` (Adam) | ✓ | ✓ | ✓ | ✓ | ✓ |
| `household_admin` (Wendy) | ✓ | ✗ | ✓ | ✗ | ✓ |
| `viewer` (future) | ✗ | ✗ | ✗ | ✗ | ✓ |

**Household operational writes:** Register transactions, cleared toggles, Budget actuals, Budget Line Admin, weekly tasks/notes/recon/overrides/custom tasks, scenario commits, normal goal targets, wishlist/roadmap management.

**Owner-only writes:** accounts, categories, category registry keys, `goals.anthropic_key`, RLS/policy/platform config, destructive admin actions.

**BLR RLS alignment (2026-06-30 — post-code surgical migration):**
Live P8 audit confirmed `budget_line_rules` write policies were using `is_owner()`, blocking Wendy (household_admin) from Budget Line Admin. A surgical RLS migration was applied:
- Dropped: `budget_line_rules_insert`, `budget_line_rules_update`, `budget_line_rules_delete` (all using `is_owner()`)
- Created: same three policies using `can_write_financials()` — grants INSERT/UPDATE/DELETE to owner AND household_admin
- SELECT policy (`is_allowed_user()`) untouched
- No schema changes. No data changes. No function changes.
- P8 PASS confirmed: 3 write policies, all `can_write_financials()`, zero `is_owner()` on writes
- V12 PASS confirmed (isolated query): `Write policies: 3 | Uses can_write_financials: true | Uses is_owner (blocks Wendy): false`
- Wendy (household_admin) is no longer blocked at RLS for Budget Line Admin
- Migration file: `docs/phase-5e-7-blr-rls-migration.sql`
- Validation file: `docs/phase-5e-7-blr-rls-validation.sql` (BM1–BM5 authoritative; BM4 NULL-handling false alarm documented)

**STOP CONDITION: CLEARED** — P8 and V12 both PASS. 5E-7 is fully live verified. 5E-8 unblocked.

**Non-goals (held):**
- No Budget math changes
- No `budget_transactions` schema/RLS changes
- No new DELETE policies (missing DELETE on `weekly_reconciliations`, `weekly_tasks`, `weekly_notes` is a pre-existing gap, not introduced here)

---

### Phase 5E-8 — 7/1 Wendy Operating Readiness (SMOKE PASSED — CONDITIONALLY READY, 2026-06-30)
Confirmed the system is operationally ready for Wendy to use as of July 1, with one manual owner data task outstanding.

**Scope:**
- July budget sanity check (totals, balance, key rows)
- Wendy workflow smoke: transaction entry, cleared toggle, Budget view
- Budget edit workflow verified (Edit/Archive tested against real July data)
- Transaction entry verified (add, edit, delete manual rows)
- Known limitations documented (no splits, no transfers, no imports, no reconciliation yet)
- No major new feature build unless a readiness blocker is found during this phase

**Gate:** CLEARED — 5E-7 code/tests complete and live P8/V12 audit passed (2026-06-30). BLR RLS aligned.

**Results (full detail: `docs/phase-5e-8-wendy-readiness.md`):**
- Wendy household_admin smoke: W1–W10 all PASS (login, Register CRUD + cleanup, Budget tab, Budget Line Admin, Ask Claude owner-gated, weekly task/notes)
- Adam owner smoke: A1–A4 all PASS (login, Ask Claude owner controls, Register, Budget Line Admin)
- July budget readiness: J1–J3 all PASS — Entertainment $1,500 total (Seattle $300, Wewe's Lunches $200, Weeks 1–4 = $250 each), June legacy Entertainment unchanged at $1,500, no double-count, budget balanced ($15,938 income = $15,938 planned)
- Deployment gap found and resolved during smoke: `origin/main` was 2 commits behind local (5E-7 + BLR RLS alignment unpushed), causing W9 to fail on first pass. Code was already correct; fix was `git push origin main` only — no code change, no new commit.
- Regression suite: `node test_regression.js` — 904 passed / 0 failed
- Outstanding: Register `starting_balance` not yet set for any of the 14 accounts (by design — captured at go-live per Phase 5C/5D-1 spec, not before). Budget and Transactions CRUD are unaffected. Register running balances anchor at $0.00 with an explicit "Starting balance not set" warning until this is done. Manual, owner-only SQL task (no UI exists for it), targeted for the morning of 7/1 before Wendy relies on register balances.

**Status: Conditionally ready.** Do not start 5F-1 until starting balances are set and Wendy's first live 7/1 session is confirmed clean.

---

### Phase 5E-9 — Category Registry Admin (DEFERRED)
New category creation UI (keys not in `BUDGET_CATEGORY_REGISTRY`). Deferred unless a 7/1 blocker is found from missing registry keys.

**If triggered:** adds a Category Registry Admin panel to create new leaf keys and register them in the JS `BUDGET_CATEGORY_REGISTRY`. Scope TBD at that time.

---

### Phase 5F-0 — Needs Attention / Dashboard Usefulness (PLANNED, NOT STARTED)
Lightweight actionable summary panel — not a full dashboard redesign.

**Scope:**
- Budget out-of-balance alert
- Over-budget / near-limit categories
- Pending/deferred items (if already supported by existing data)
- Unreconciled/uncleared items (if already supported by existing data — no reconciliation migration)

**Non-goals (explicit exclusions):**
- No reconciliation migration or new reconciliation workflow
- No broad dashboard redesign
- No new schema

**Gate:** Unblocked after 5E-7 passes (5E-7 is now complete). Does not require 5F-1 or 5F-2.

**Do not start until explicitly approved.**

---

## Phase 5E-3 — Production Enablement
**Status:** Complete
**Date:** 2026-06-27

### What shipped
- `showTransactionLedger` flipped to `true` as production default
- Register tab now live for all users on page load — no console JS required
- Live smoke passed: Adam add/edit/cleared/delete, Wendy add — all confirmed

---

## Phase 5E-2 — Transaction Writes
**Status:** Complete
**Date:** 2026-06-27
**Commit:** 40fdf28 + a8d2b19

### Final confirmed state (post-migration)
- Static regression: 773/773 passed
- Playwright E2E: 114/114 passed
- Supabase migration applied: 3 write policies, column grants, ALTER POLICY hardening
- VM1-VM12: all 12 passed (VM6/VM8 updated to verify RLS policy content vs. column grants)
- VM6/VM8 note: Supabase grants ALL to authenticated at table level by default; column-level
  grant restriction is not achievable — security enforced via RLS. INSERT policy hardened
  with user_id = auth.uid() check via ALTER POLICY on 2026-06-27.
- showTransactionLedger still default false — enable for live smoke only

### What was built
- DB: 3 write policies using `can_write_financials() AND source='manual'` (INSERT, UPDATE, DELETE)
- DB: Column-level grants — INSERT (8 cols, excludes user_id/notes/id/timestamps), UPDATE (6 mutable cols only), DELETE (table-level)
- UI: Add Transaction form (date, payee/memo, outflow/inflow mutual exclusion, category, cleared)
- UI: Edit Transaction — pre-populated form via `_openTxForm('edit', tx)`
- UI: Delete Transaction — inline confirmation strip per row
- UI: Cleared toggle — checkbox per manual row, fires PATCH immediately
- UI: Non-manual rows (source ≠ 'manual') show no edit/delete controls; cleared is read-only
- UI: One active action at a time (opening add/edit clears delete confirm and vice versa)
- UI: Three-way saving state (_txFormSaving, _txDeleteSaving, _txClearedSavingId) with finally blocks
- Topbar subtitle: "Adding transaction — [account]" / "Editing transaction — [account]" during write modes

### Files changed (pending commit)
- `index.html` — state vars, helper functions, `_saveTxForm`, `_deleteTxConfirm`, `_toggleTxCleared`, `_renderTxRegister` rewrite, topbar subtitle
- `test_regression.js` — 28 new tests (5E2-01 through 5E2-28)
- `e2e.js` — 16 new WR tests (WR-1 through WR-16); RG-7b, RG-11, RG-15 updated for 5E-2 behavior
- `docs/phase-5e-2-preflight.sql` — VP1–VP5 + can_write_financials() source inspection
- `docs/phase-5e-2-migration.sql` — 3 write policies, column grants, VM1–VM12 validation UNION ALL
- `docs/phase-5e-2-rollback.sql` — REVOKE mirroring grants + RB1–RB5 verification

### Next steps before enabling write UI
1. Commit this state
2. Run `docs/phase-5e-2-preflight.sql` in Supabase — all VP1–VP5 must pass
3. Run `docs/phase-5e-2-migration.sql` in Supabase
4. Run VM1–VM12 UNION ALL validation — all must return expected values
5. Live smoke: add, edit, cleared toggle, delete, Wendy insert, unauthenticated blocked, protected-column PATCH rejected
6. 5E-3: Wendy handoff / production enablement (showTransactionLedger=true by default)

### Write predicate decision
- `can_write_financials()` = owner (Adam) + household_admin (Wendy)
- `is_owner()` rejected — blocks Wendy
- `is_allowed_user()` rejected — too permissive for future viewer roles
- Policies named `financial_writer_*` (not `owner_*`) to match actual predicate

### Non-goals (explicit exclusions)
- No changes to runModel() or Budget math
- No changes to budget_transactions
- No reconciliation workflow
- No transaction_splits table
- No mobile layout changes
- No notes field UI (column exists; UI deferred)
- No import/migration rows editable via UI (source='manual' guard)

---

## Phase 5E-1 — SQL Foundation + Read-Only Register Shell
**Status:** Complete
**Date:** 2026-06-27
**Commit:** 1675548

### Final confirmed state
- Static regression: 733/733 passed
- Playwright E2E: 90/90 passed
- Preflight (P1–P7, P5a, P6a): all passed
- Migration: passed (fail-loud, no IF NOT EXISTS)
- Post-migration validations (V1–V10, V3a, V3b): all passed
- Live smoke on dashboard.herndons.us: passed
- `showTransactionLedger` returned to default `false` after smoke
- Production default behavior restored
- Working tree: clean

### What shipped
- `transactions` table live in production with RLS enabled
- `allow_read` SELECT-only policy using `is_allowed_user()`
- `GRANT SELECT` only — no write policies or grants
- `showTransactionLedger` feature flag (default `false`)
- Read-only Register shell: account selector, starting balance warning, empty/loading/error states, category label resolution, topbar subtitle
- 20 static regression tests (5E1-01 through 5E1-20)
- 17 Playwright E2E tests (RG-1 through RG-16 + RG-7b)
- `docs/phase-5e-preflight.sql`, `docs/phase-5e-migration.sql`, `docs/phase-5e-rollback.sql`

### Scope (5E-1 only)
- `transactions` table, indexes, constraints, RLS (1 SELECT policy — least privilege), trigger, `GRANT SELECT` only
- `showTransactionLedger` feature flag (default `false`)
- Register tab activates when `showTransactionLedger=true`; stays disabled span otherwise
- Account selector populated from `_accountsCache`
- Starting balance row: shows value or explicit "Starting balance not set — running balance starts from $0.00" warning
- Read-only transaction list (fetched via Supabase, 500-row query-level limit, deterministic sort)
- Loading / error / empty states
- Topbar subtitle for register sub-nav

### Not in 5E-1
- Add / edit / delete — Phase 5E-2
- Cleared toggle/write operation — Phase 5E-2 (cleared status is displayed read-only in 5E-1; the write toggle is deferred)
- `transaction_splits` table — deferred until split UI is scoped
- Transfer UI — deferred
- `reconciled` column surfaced — Phase 5F
- Starting balance editing
- Budget math changes — non-negotiable exclusion
- `budget_transactions` changes — non-negotiable exclusion
- Mobile layout — non-negotiable exclusion

### Files shipped (commit 1675548)
- `docs/phase-5e-preflight.sql` — 9 pre-checks (P1–P7 + P5a/P6a FK constraint validation)
- `docs/phase-5e-migration.sql` — table, indexes, 1 RLS policy (SELECT only), trigger, SELECT grant, 13 post-migration validation queries (V1–V10 + V3a/V3b policy name/expression checks)
- `docs/phase-5e-rollback.sql` — safe teardown with Phase 5F warning
- `index.html` — 8 edit points (flag, loadAll condition, nav logic, Register tab, routing, state vars, `_loadTxLedger`, `_renderTxRegister`, topbar subtitle)
- `test_regression.js` — 20 new tests (5E1-01 through 5E1-20)
- `e2e.js` — 16 new tests (RG-1 through RG-16, Section RG)

### Standing constraints (non-negotiable for all of Phase 5E)
- No changes to `runModel()` or any Budget math function
- No changes to `budget_transactions` table, schema, or queries
- No reconciliation workflow of any kind
- No migration or mapping between `budget_transactions` and `transactions`
- No default flag changes in production
- No mobile layout expansion
- No `transaction_splits` table until splits UI is explicitly scoped

---

## Phase 5D-2 Slice 1 — Read-Only Transactions Section
**Status:** Complete (pending your push after manual smoke)
**Date:** 2026-06-26

### What was built
- `FEATURE_FLAGS.showTransactionSection` — default `false`; all new UI hidden when off
- Supabase registry load condition updated: fires when `useSupabaseRegistries || showTransactionSection`
- Transactions nav item in sidebar only (desktop-only, Slice 1 decision — no `mob-bottom-nav` entry)
- `s-transactions` section div + `SECTION_TITLES.transactions`
- Topbar subtitle for Transactions section (accounts count / active category count)
- `renderTransactions()` — shell + sub-nav (Accounts | Categories | Register — Phase 5E | Reconciliation — Phase 5F)
- `_renderTxAccounts()` — read-only table: label, institution, type, lifecycle badge, in budget, in cashflow, starting balance ("Balance not set" for null), notes row
- `_renderTxCategories()` — read-only table: key, label, status, behavior, budget treatment, cashflow, budget_line_key, budget_group_key; lifecycle toggle (active-only default / show all); merged row badge with merged_into_key arrow
- `_txLifecycleBadge()` — inline badge for active/hidden/view_only/closed/excluded/archived/merged
- 26 new regression tests added to `test_regression.js` (5D2-01 through 5D2-26)
- 10 new Playwright E2E tests added to `e2e.js` (TX-1 through TX-10, Section TX)

### No DB changes
Phase 5D-2 Slice 1 is pure JS/HTML. No schema changes, no seeds, no migrations. Rollback = set `showTransactionSection: false` in console or revert `index.html`.

### Test results
- **Syntax check:** PASS
- **713/713 static regression tests passed** (687 pre-existing + 26 new 5D2 tests)
- **Production behavior unchanged:** both flags default false, no Supabase load fires, no Transactions nav visible
- **Playwright E2E (TX-1 through TX-10):** Added to `e2e.js` Section TX. Must run from your terminal (`node e2e.js`) — Chromium binaries not in sandbox. Tests use injected mock data; no Supabase connection required. Coverage: flag=false default gate, Accounts table 7-column render, "Balance not set" for null balances, lifecycle badge CSS vars, Categories active-only filter (merged row absent), show-all toggle (merged row visible with amberSoft badge + merged_into_key), 8-column categories table with budget_group_key, future disabled tabs with correct phase labels and cursor:not-allowed, flag reset behavior (nav hides + budget intact), desktop-only enforcement (no mob-nav-transactions).

### Manual smoke test
In console after login:
```js
FEATURE_FLAGS.showTransactionSection = true;
await _loadSupabaseRegistries();
renderApp();
setSection('transactions');
```

Expected:
- Accounts tab: 14 rows, Costco Visa = "hidden" badge, Fidelity = "view only" badge, all show "Balance not set"
- Categories tab active-only: 50 rows, `business.jabian_2026_dup` absent
- Categories tab "Show all lifecycle states": 51 rows, `business.jabian_2026_dup` visible with merged badge + `→ business.jabian_consulting_2026` arrow
- `health_fitness.flexible_spending_2026`: `reimbursable_expense`, `excluded`, `reimbursable`, no budget_line_key
- Register tab: disabled, labeled "Register — Phase 5E"
- Reconciliation tab: disabled, labeled "Reconciliation — Phase 5F"
- Switch back to `showTransactionSection=false`: Transactions nav disappears, no Supabase load on next page reload

### Mobile handling decision (Slice 1)
Transactions is desktop-only. The sidebar (containing `nav-transactions-wrap`) is hidden at ≤900px viewport via CSS; `mob-bottom-nav` has no Transactions entry. Mobile users cannot navigate to the section. This is intentional for Slice 1. Phase 5E or later should evaluate mobile-appropriate layout before adding a mob-nav entry.

---

## Phase 5D-1 — Supabase Registry Foundation
**Status:** Complete  
**Date:** 2026-06-26

### What was built
- `accounts` table (14 rows seeded: 12 active, 1 view_only, 1 hidden)
- `categories` table (51 rows seeded: 50 active, 1 merged)
- RLS policies on both tables using `is_allowed_user()` (SELECT) and `is_owner()` (INSERT/UPDATE/DELETE)
- `fn_set_updated_at()` trigger function + triggers on both tables
- `useSupabaseRegistries` feature flag (default `false`) in `index.html`
- Registry load helpers: `_loadSupabaseRegistries`, `_getActiveCategoryRegistry`, `_getPaymentAccountOptions`, `_rebuildBudgetCatByKey`, `_normalizeCatRow`
- All 8 `BUDGET_CATEGORY_REGISTRY` / `BUDGET_PAYMENT_ACCOUNTS` call sites replaced with flag-aware getters
- Preflight file: `docs/phase-5d-1-preflight.sql`
- Rollback file: `docs/phase-5d-1-rollback.sql`

### Migration execution — preflight findings and corrections
Two issues caught by preflight before the migration ran:

1. **Diablos/GLP rows already existed** in `budget_line_rules` before Phase 5D-1.  
   Migration's `WHERE NOT EXISTS` guards correctly skipped both inserts.  
   Rollback Step 3 changed to no-op — those rows pre-existed and must not be deleted on rollback.

2. **`get_my_role()` does not exist** in this project.  
   All existing write-guard policies use `is_owner()` (budget_line_rules, budget_transactions, etc.).  
   RLS policies corrected from `get_my_role() = 'owner'` → `is_owner()` before migration ran.

### Validation results
All V1–V15 queries passed post-migration.

### Test results
- **flag=false regression:** 687/687 passed. Production behavior unchanged.
- **flag=true Supabase smoke:**
  - 14 accounts loaded
  - 51 raw categories in DB
  - 50 active categories returned by `_getActiveCategoryRegistry()`
  - `business.jabian_2026_dup` (merged) excluded from active registry and dropdowns
  - Costco Visa exists as `hidden`; excluded from Supabase-powered payment dropdowns

### Rollback scope note
`docs/phase-5d-1-rollback.sql` is intended for **immediate Phase 5D-1 rollback only**, before any later phase adds FK references or application logic that depends on `accounts` or `categories`. Once Phase 5E or later is applied, the rollback file must be extended before use.

---

## Phase 5C — Architecture Design and Discovery
**Status:** Complete (design frozen, Phase 5D-1 built from this)

Design documents: `docs/phase-5c-architecture-design.md`, `docs/phase-5c-discovery-checklist.md`
