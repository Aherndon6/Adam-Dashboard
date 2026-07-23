# Week 1/2 Legacy Task-Binding Repair — Design + Evidence Record (Step 5)

**Date:** 2026-07-21 · **Branch:** `claude/week1-2-legacy-binding-repair` (off `main d41da89`)
**Status:** Implemented + tested locally; **NOT pushed, NOT deployed.** Awaiting owner deploy gate.
Fable architecture/control review APPROVED; owner authorized implementation.

## 1. Defect (confirmed)
Legacy completed `weekly_tasks` rows in model weeks 1/2 (Cal Wk 23/24) carry **null `action_key`** and insufficient row-level identity. They persist, but `resolveWeekTransfers` cannot bind them to current recommendations, so settled historical actions render as **unchecked, toggleable** controls — a display defect that also exposes a **historical-write hazard** (no mechanical week-based write guard on the toggle path). Not data loss. Commission-tax pool independently clean (`ok`, remaining $0; wk-2/4/6 origins settled).

## 2. Git-era reconstruction (read-only, attests week-level class only)
- Identity persistence introduced at **`5e8949a`** (Phase 4) / **`8dd1972`,`e7d0b1d`** ("goal sweep action keys + completedLabel snapshot"). The wk-1/2 completions **predate** these → null-key.
- **Week 1 → 4 recommendations** ([index.html] wk-1 SETUP block + Costco): `setup_sav_2750`, `setup_lc_1000`, `setup_lc_2250`, `costco_visa` (`ACTION_DEFAULT_WEEKS.costco_visa=1`).
- **Week 2 → 2 recommendations**: `tax_base` (`ACTION_DEFAULT_WEEKS.tax_base=2`, "Vio not active Wk 1") + the durable `commission_tax` wk-2 leg.
- Cardinality (4 / 2) is stable in the current generators and matches the S0 Baseline pins (wk1 4/4, wk2 2/2). **Uncertainty:** code attests cardinality/types only; production row count + null-key state come from the owner Baseline-A/B probe. Used to attest the **week** class, never to fabricate row identity.

## 3. Design (as implemented)
- **Immutable-week rule (Option B):** `_weekIsImmutable(n) = isWeekReconciled(n) || n <= CT_ATTESTATION.anchor_boundary_week`. Grounded in `isWeekReconciled` (the closed-week signal) + the anchor boundary, documented in code as *"the §13 write-locked legacy weeks."*
- **Post-resolver adapter `_legacyClassifyWeek(w)`** (pure; does **not** modify `resolveWeekTransfers`/`runModel`/`computeGoalTransferNetting`). Classifies each **non-commission** model row (commission_tax stays pool-owned). Week-scoped, **cardinality-gated**, **no per-row identity**:
  - `completed` — resolver-bound.
  - `completed_legacy` — immutable week, `#legacy-null-key-completions == #unbound-recs`.
  - `review_required` — immutable week, legacy present but cardinality mismatch (never auto-bound/executable).
  - `open` — unbound, no legacy attestation (mutable actionable, or immutable past-open).
  - Only **completed** null-key rows attest (`completed=false` ignored).
- **Counts:** legacy/review excluded from open-action counts (`_modelRowOpen`, `buildDashboardViewModel.openActions`) but rendered as distinct read-only states.
- **Render:** four distinct states (Completed / Completed (legacy) / Legacy history — review required / Executed history) — never flattened.
- **Bidirectional guard:** at the top of `toggleTransfer` **and** `toggleCustomTask`, `_weekIsImmutable` rejects **both** check and uncheck **before** any state mutation or network — `_immutableWeekRefusal` shows a week-scoped message, fires no upsert, no request.
- **Week 5 control:** durable keyed rows never enter the legacy path → unchanged (regression control).

## 4. Files changed (this branch)
- `index.html` (+84/−3): adapter + immutable rule + guard + render states + count exclusion. **No edits to `runModel`/`computeGoalTransferNetting`/`resolveWeekTransfers`.** BUILD_TS unchanged.
- `test_regression.js` (+74): S5-IMM-1/2, S5-WK1, S5-WK2, S5-MISMATCH, S5-INCOMPLETE, S5-MUTABLE, S5-WK5-CONTROL, S5-FROZEN.
- `e2e.js` (+63): 5G-S5-1 (wk1 legacy render + 0 open), 5G-S5-2 (bidirectional guard zero-network/zero-mutation), 5G-S5-3 (wk5 control unchanged).
- (this doc) design/evidence record.

## 5. Frozen-surface hashes (baseline `191cda5` / `d41da89`)
`runModel` len 32840 / `5181b79cbba47e68`; `computeGoalTransferNetting` len 10309 / `4670447ce489dd8b`; `resolveWeekTransfers` len 5583 / `20d17438996ac8ba` — re-proven identical, and the adapter/guard tokens are asserted absent from those bodies (test S5-FROZEN).

## 6. Deploy + post-deploy probe procedure (proposed; not executed)
1. Activation BUILD_TS stamp (owner-gated), separate commit; rerun full static.
2. Push branch; fast-forward `main`; GitHub Pages build.
3. Post-deploy read-only probes: `weekly_tasks` **row-for-row unchanged** (before/after dump identical); commission-tax pool `ok`/remaining $0; `goal_funding_snapshots` unchanged; wk 1 renders 4 Completed (legacy)/0 open; wk 5 control unchanged; guard refuses check/uncheck with zero network (owner-observed). Balance-free evidence.

## 7. Backlog (D-11 / 2027 rollover)
- **Server-side immutability** for reconciled weeks (DDL/RLS), covering **both** insert/update directions incl. completed→uncompleted.
- **Evidence-controlled `weekly_tasks` re-key / backfill or terminal archival** of the null-key legacy rows.

## Interim operating control (in force until deploy)
**Weeks 1–2 (Cal Wk 23/24) contain a known historical-display defect (legacy null-key completions render as unchecked). Do not click, check, or uncheck any task in those weeks.** No data lost; pool `ok`/remaining $0.

---

## 8. Hardening round (2026-07-22) — F1/F2/F3 closure + residual-finding register

Second (final) commit on this branch, closing the three implementation findings from the independent
Step-5 implementation review. Approved architecture preserved: post-resolver adapter, no row-level
identity inference, no SQL/schema/production-data change, frozen surfaces byte-identical, no BUILD_TS.

### 8.1 F1 — Dormant-writer closure (CLOSED)
`toggleTask` (zero call sites; retained per direction) now carries the same first-line
`_weekIsImmutable` → `_immutableWeekRefusal` guard as every other task writer — before any optimistic
`taskData` mutation, auth acquisition, or `weekly_tasks` upsert. Static S5-F1 proves check+uncheck on an
immutable week produce zero refuted-path mutation and never reach auth (the sole route to fetch);
S5-F1b is the mutable-week positive control (guard passes; optimistic write occurs; auth reached).
E2E 5G-S5-2 additionally proves zero non-GET network for both directions in a real browser.

### 8.2 F2 — Legacy-era truth tightening (CLOSED)
`completed_legacy` is now reachable **only** for pre-anchor weeks (`num <= anchor_boundary_week`, via the
shared `_anchorBoundaryWeek()` helper). Post-anchor null-key completions are anomalies, never legacy:
reconciled → `review_required` with week-level `reviewReason='postanchor_nullkey'` (rendered with an
anomaly-specific explanation, distinct from the pre-anchor `cardinality_mismatch` message); unreconciled →
the week stays actionable (`open`). Rules table as implemented: pre-anchor exact match → `completed_legacy`;
pre-anchor mismatch → `review_required` (`cardinality_mismatch`); post-anchor null-key → never legacy
(reconciled → `review_required` `postanchor_nullkey`; unreconciled → `open`); keyed rows → normal
`completed` flow; `commission_tax` → excluded from legacy logic entirely (unchanged). Static S5-F2a/F2b/F2c;
Weeks 1/2/5 controls (S5-WK1/WK2/WK5-CONTROL, 5G-S5-1/3) remain green unchanged.

### 8.3 F3 — Immutable custom-task surface lockdown (CLOSED)
Complete custom-task writer inventory and guard coverage:

| Writer | Table(s) touched | Guard (immutable week) | Coverage |
|---|---|---|---|
| `toggleTransfer` | `weekly_tasks` | ✓ (first commit) | S5 e2e + netting suites |
| `toggleCustomTask` | `custom_tasks` | ✓ (first commit) | 5G-S5-2 |
| `toggleTask` (dormant) | `weekly_tasks` | ✓ **F1 (this round)** | S5-F1/F1b + 5G-S5-2 |
| `saveCustomTask` (create) | `custom_tasks` | ✓ **F3 (this round)** | S5-F3 + 5G-S5-2 |
| `deleteCustomTask` | `custom_tasks` | ✓ **F3 (this round)** | S5-F3 + 5G-S5-2 |
| `dismissAutoReminder` | `custom_tasks` + meta | ✓ **F3 (this round)** | S5-F3 + 5G-S5-2 |
| `flipCustomTaskType` | meta (`goals` KV) | ✓ **F3 (this round)** | S5-F3/F3b + 5G-S5-2 |
| `saveCustomTaskMeta` | `goals` KV (`custom_task_meta`) | shared persistence helper — deliberately unguarded; every user-action entry point above is guarded | covered transitively (meta writes watched in 5G-S5-2 via `/rest/v1/goals`) |
| `ensureAutoReminders` | none (in-memory only) | n/a — performs no network write; its persistence paths (toggle/dismiss) are guarded | inspected |
| Edit-Week backfill writers (`weekly_tasks` PATCH / `custom_tasks` POST) | both | **out of scope** — see residual F5 | n/a (D-11) |
| localStorage→Supabase one-time migration | `custom_tasks` | pre-existing infra path, unchanged | n/a |

UI lockdown (guards enforce; hiding removes the invitation): immutable weeks render **no** `+ Add task`,
**no** `+ Add transfer` (button or stale open form — `_adding*` flags are `_weekImm`-gated), **no**
delete/dismiss ✕, **no** type-flip control; custom-task checkboxes render `disabled`. Mutable weeks
expose all controls unchanged (positive control in 5G-S5-4). Note the deliberate narrowing: the previous
rule hid delete-only on reconciled weeks while leaving Dismiss exposed; the immutable rule now hides both.

### 8.4 Residual findings register (ACCEPTED — recorded, not fixed here)
- **F4 (accepted product decision):** `review_required` states are intentionally excluded from
  open-action counts and week-chip dots; the amber review row is visible only inside week detail.
  Zero review-state weeks exist in production today.
- **F5 (future home: D-11):** the Edit-Week historical correction writers remain outside this slice's
  mechanical lock, governed by the §2d-class operator controls and the recorded post-activation B1
  correction backlog.
- **F6 (future home: D-11):** reconciliation-derived **client** immutability fails open when
  reconciliation state is unavailable (pre-anchor weeks stay locked via the anchor constant — S5-IMM-1).
  The durable lock is server-side; the canonical roadmap **D-11 scope addition (2026-07-22)** now
  explicitly includes *server-authoritative historical-week immutability enforcement for reconciled and
  prior-period weeks, including privileged correction authority* (`docs/roadmap/canonical-roadmap.md` §12.1).
- **ALASKA_DRAW e2e venue (maintenance note):** the relocated 5G-1B write-path e2e test selects its venue
  by predicate and currently lands on the wk-15 `alaska_draw` row. Any future retirement/redesign of
  `ALASKA_DRAW` must preserve or intentionally replace that venue (the predicate has fallbacks, but the
  retirement change's checklist must re-verify the test still exercises a mutable resolver-bound row).

### 8.5 Verification (this round)
- Static regression: **1613 / 0** (was 1606; +7: S5-F1, S5-F1b, S5-F2a, S5-F2b, S5-F2c, S5-F3, S5-F3b).
- Full `node e2e.js`: **162 / 0 / 0**, readiness fallbacks 0/0 (was 161; 5G-S5-2 extended to all seven
  writer paths + `/rest/v1/goals` watch; new 5G-S5-4 UI-lockdown/positive-control test).
- Frozen surfaces byte-identical (working tree == `d41da89` == first-commit baseline):
  `runModel` 32840/`5181b79cbba47e68` · `computeGoalTransferNetting` 10309/`4670447ce489dd8b` ·
  `resolveWeekTransfers` 5583/`20d17438996ac8ba` (independent extraction + in-suite S5-FROZEN).
- `BUILD_TS` unchanged (`2026-07-19T01:51:10`; zero BUILD_TS lines in the branch diff). No SQL, no schema,
  no production data, no push, no deployment.
