# Herndon Financial OS — Phase Status

## Roadmap Sequence (as of 2026-06-28)

| Phase  | Name                                           | Status             |
|--------|------------------------------------------------|--------------------|
| 5E-1   | SQL Foundation + Read-Only Register Shell      | Complete           |
| 5E-2   | Transaction Writes                             | Complete           |
| 5E-3   | Register Live by Default                       | Complete           |
| 5E-4   | Budget Correctness + Display Fixes             | Complete           |
| 5E-5   | Budget Line Admin (required before 7/1)        | Complete                         |
| 5E-6   | Monthly Entertainment Buckets                  | Complete                         |
| 5E-7   | Role Enforcement / Security Maturity Gate      | Complete — live P8/V12 verified (2026-06-30) |
| 5E-8   | 7/1 Wendy Operating Readiness                  | Smoke passed — conditionally ready pending 7/1 starting balance setup (2026-06-30) |
| 5E-9   | Category Registry Admin                        | Deferred (unless 7/1 blocker found) |
| 5F-0   | Needs Attention / Dashboard Usefulness         | Not started        |
| 5F-1   | Reconciliation Design + Read-Only Scaffold     | Not started        |
| 5F-2   | Reconciliation Writes                          | Not started        |
| 5G     | Splits                                         | Not started        |
| 5H     | Transfers                                      | Not started        |
| 5I     | Import Readiness                               | Not started        |
| 5J     | Budget Integration / Actuals                  | Not started        |

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
