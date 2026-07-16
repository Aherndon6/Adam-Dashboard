# 5G-1B (rider) — Positional-Identity Closure: write-path backfills (B1/B2), read sites (B3), posting gate (B4)

**Date:** 2026-07-15 · **Class:** Mandatory 5G-1D Gate B activation blocker (third round; Fable delta-review findings B1–B4) · **Type:** adapter/render + write-ctx + operator-doc only. **No `runModel`, waterfall, commission-tax calc, `resolveWeekTransfers` tiers, `computeGoalTransferNetting`, wrapper, snapshot payload, reconciliation/reopen, SQL/schema, grants/RLS, or production-data change.** **Balance-free.** **App commit:** `4ce6aff` · **Docs commit:** (this round's v4 docs). Completes the positional-identity class begun by `fd5d7a1` (render stragglers) — see `docs/phase-5g-1b-identity-resolution-2026-07-15.md`.

## Findings fixed (Fable delta review)

**B1 — Edit-Week commission-tax backfill writer.** The backfill selected the completed row **positionally** (`taskData[weekNum+'_'+_ctIdx]`, `_ctIdx`=display index) and set its `action_key=commission_tax` — so a foreign completed row (the Adam IRA `$61.06` at the commission display index) could be **silently rewritten into `commission_tax`**, re-arming the original duplicate on a later Week-28 edit. **Fix:** select by persisted identity — `_taskRowsForWeek(weekNum).filter(r => r.completed && r.actionKey === commission_tax)`; patch only on exactly one match; `0`/`>1`/null-key → **skip + `console.warn`, no patch, no `action_key` rewrite**. The correctly-keyed backfill (+ the additional-income tracking task) is preserved.

**B2 — Edit-Week goal-sweep backfill writer.** Same positional defect for `goal_*` deltas. **Fix:** identity-select `r.completed && r.actionKey === aKey`; skip + warn on `>1` or a foreign-at-index case; silent skip when the goal was simply not executed. A commission-tax / other-goal / unrelated row can never be rewritten into a `goal_*` action.

**B3 — positional completion reads (Overview / chips / History).** `_modelRowOpen`, `buildDashboardViewModel` modelActs, Overview `cwDone`, and History open-counts determined completion via `taskData[week+'_'+displayIndex].completed` — so a foreign completion at the index could **hide** the real open `$425.68` commission-tax task. **Fix:** completion derived from `resolveWeekTransfers` identity (`currentRows[i].completed` via a per-week memoized `_weekResolved(w)` / `_modelRowDone(w,i)`); `_modelRowOpen(w,i)` now takes the week object. Dormant `runModel.doneTasks` left unchanged (documented only, per Fable).

**B4 — commission-posting operational gate.** Operator package **v4 §2c**: a hard gate requiring the `$2,108.78` commission to be **posted/available** in Truist Checking before the `$425.68` transfer or the Week-28 closeout; "processed/pending" does not count; hard-stop if unposted (delay covered by the contingency annex).

## Verification

- **Static** `5G1B-WRITE-1…7` + `5G1B-B3-1…3`: commission/goal backfill foreign-row no-select (protected), correct-row select by identity, null-key skip, source-structure guard (identity filter present; positional selector + `action_key` rewrite removed); `_modelRowDone`/`_modelRowOpen` identity under the collision; matched-completion still done. **Static 1543 / 0** (from 1533; +10).
- **E2E** `5G1B-IDENT-E3` (Overview/chip/History count the open `$425.68`; Adam IRA isolated) + `5G1B-IDENT-E4` (drives `saveWeekEdits(6)` with a `fetch` spy: the Adam IRA row's `action_key` is **not** rewritten and **no PATCH** targets it as commission_tax). **E2E 155 / 0 / 0, readiness 0/0** (from 153; +2; clean first run).
- **Frozen-surface proof:** `runModel`, `resolveWeekTransfers`, `computeGoalTransferNetting`, commission-tax calc byte-identical `801c832 ↔ 4ce6aff`; 0 `.sql`; app diff = `index.html` (B1/B2/B3 sites) + `test_regression.js` + `e2e.js`.

## Pins

App `4ce6aff`; `index.html` blob `a4c458af2c9c53a67ceb621dd4d8c9c48d6343a2`; `BUILD_TS 2026-07-15T20:52:49`; static 1543/0; e2e 155/0/0; readiness 0/0. Operator package repinned **v4**.

## Production data

No data correction (Scenario E confirmed clean earlier; B1 is forward-looking protection against a *future* edit corrupting the clean row).

## Fable delta-review package

This doc + `git show 4ce6aff` (B1/B2/B3 diff) + tests `5G1B-WRITE-1…7`, `5G1B-B3-1…3` (static) and `5G1B-IDENT-E3/E4` (e2e) + the frozen-surface byte-identity proof + package v4 §2c posting gate. Scope: confirm identity selection is correct and never targets a foreign row; the resolver-based reads are correct; frozen surfaces unchanged; the posting gate is explicit.

## Files changed

- `index.html` — B1 commission backfill, B2 goal backfill, B3 `_weekResolved`/`_modelRowDone`/`_modelRowOpen` + callers + modelActs + cwDone.
- `test_regression.js` — Section 5G-1B-WRITE-B3 (10); NET-18 updated to the `_modelRowOpen(w,i)` signature.
- `e2e.js` — `5G1B-IDENT-E3`, `E4`.
- Docs: this record; operator package v4 (§2c gate + repin); gateb runbook wording; identity-resolution doc correction; decision-log; CODEX_STATUS.
