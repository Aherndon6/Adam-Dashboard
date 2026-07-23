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
