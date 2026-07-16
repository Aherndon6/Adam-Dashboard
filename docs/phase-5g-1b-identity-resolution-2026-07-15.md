# 5G-1B (rider) — Identity-Resolved Completion Normalization (commission-tax task restoration)

**Date:** 2026-07-15 · **Class:** Mandatory 5G-1D **Gate B activation blocker** correction (second) · **Type:** adapter/render + write-ctx only. **No `runModel`, waterfall, `goalSaved`, snapshot SQL/schema, snapshot payload, wrapper, grants/RLS, reconciliation, or reopen change.** **Balance-free.** **Commit:** `fd5d7a1`.
**Owner:** Adam · **Implementer:** Claude Code (local) · **Review:** independent Fable re-review requested (this doc is the review package).
**Relationship:** follows the open-window netting correction (`15b372f`, `docs/phase-5g-1b-openwindow-netting-2026-07-15.md`). Same positional-`task_idx` defect family that `db2704f` fixed in the resolver. **This commit (`fd5d7a1`) closes only the `applyCompletionSnapshots` / `_trAmts` render stragglers — it does NOT by itself fully close the positional-identity class.** The Edit-Week **write-path** backfills (B1 commission-tax, B2 goal-sweep, which could rewrite a foreign completed row's `action_key`) and the remaining **read-path** completion sites (B3: `_modelRowOpen`, `buildDashboardViewModel` modelActs, Overview `cwDone`, History open-counts) are closed by the **follow-on correction `4ce6aff`** (`docs/phase-5g-1b-identity-writepath-2026-07-15.md`). The positional-identity class is considered closed only with B1–B3 complete; `runModel.doneTasks` remains a dormant positional counter (documented, not consumed).

## A. Root cause (proven in code + confirmed against production rows)

`applyCompletionSnapshots` (index.html) — called on the **canonical** weeks in `renderApp` — and the `_trAmts` narrative normalizer both read completions **positionally** (`taskData[week+'_'+i]`, display index used as `task_idx`) and substitute that row's label/amount onto `realActs[i]` / the narrative line, **ignoring the persisted row's `action_key`**. Production (Scenario-E queries) confirmed the executed **Adam IRA `$61.06` completion at wk6/`task_idx 0`** collides with the commission-tax recommendation's display index 0, so `applyCompletionSnapshots` **overwrote the `$425.68 … commission 40%` label with `$61.06 … Adam IRA`** (key left `commission_tax`) — erasing the clickable `$425.68` task and feeding the corruption to the executable panel, resolver, and netting. The `commission_tax` write amount used `w.ct`, which is **not present** on the week object (`undefined`), so a completion would have persisted `completed_amount = null`.

Sandbox proof: before fix `realActs[0] → "$61.06 … Adam IRA"` (key `commission_tax`); after fix `realActs[0]` stays `"$425.68 … commission 40%"`. `applyCompletionSnapshots` is byte-identical on `main` and the pre-fix activation branch — pre-existing, unchanged by 5G-1D or the netting correction.

## B. Correction (adapter-only; three coordinated changes)

1. **`applyCompletionSnapshots` → identity-resolved.** Resolve each recommendation to its completion via the resolver's `matchTaskIdx` (`action_key` identity); only normalize `realActs[i]` when a completion's `action_key === realActKeys[i]`. An Adam IRA completion can never overwrite a `commission_tax` label. Correctly-matched completions still normalize (unchanged behavior).
2. **`_trAmts` narrative → identity-resolved** (same rule): the Week-28 narrative retains `Commission 40% $425.68 … — $417.83 carries forward` (never `$61.06`).
3. **commission-tax write amount** parsed from the identity-resolved recommendation label (not `w.ct`): checking the Week-28 task persists `action_key=commission_tax`, `completed_amount=425.68`, correct label/state.

## C. Preserved (verified byte-identical / green)

`runModel`, waterfall, commission-tax calculation, `resolveWeekTransfers`, `computeGoalTransferNetting`, snapshot payload, wrapper, grants/RLS, reconciliation/reopen — all unchanged. Correctly-matched same-action completions still normalize (`5G1B-IDENT-2/3`). Adam IRA netting, resolver identity tiers, Week-29 `$417.83` all preserved.

## D. Verification

- **Static** `5G1B-IDENT-1…7`: collision preserves `$425.68`; matched commission_tax normalizes; matched goal normalizes; different-action at same index does not overwrite; no-completion unchanged; resolver leaves commission_tax open + Adam IRA as executed-history; write amount parses to `425.68` (+ proof `w.ct` is undefined). **Static 1533 / 0.**
- **E2E** `5G1B-IDENT-E1/E2`: Week 28 shows exactly one enabled `$425.68` commission_tax checkbox; narrative `$425.68`/`$417.83 carries forward` (not `$61.06`); Adam IRA `$61.06` separate/non-executable; write ctx `commission_tax / 425.68 / Vio Tax Reserve label`; Week 29 exactly one `$417.83`. **E2E 153 / 0 / 0 (rerun; initial 151/2 were headless `clickNav` load flakes, cleared with no code change), readiness 0/0.**
- **Frozen-surface proof:** `runModel`/`resolveWeekTransfers`/`computeGoalTransferNetting`/commission-tax calc byte-identical; 0 `.sql`; working-tree app diff = `index.html` (3 adapter sites) + `test_regression.js` + `e2e.js` only.

## E. Pins

Commit `fd5d7a1`; `index.html` blob `6804711de4b520389fdca3dbbd52b7462ebc2279`; `BUILD_TS 2026-07-15T19:51:00`; static 1533/0; e2e 153/0/0; readiness 0/0. Operator package repinned to v3.

## F. Production data disposition

**No data correction required (Scenario E).** The `$61.06` is cleanly persisted under `goal_adam_ira` (wk6/task_idx 0); no `commission_tax` row carries `$61.06` or an Adam IRA label. The fix is purely adapter-level.

## G. Files changed

- `index.html` — `applyCompletionSnapshots` (identity), `_trAmts` (identity), commission-tax `_amtVal` (label parse).
- `test_regression.js` — Section 5G-1B-IDENT (7).
- `e2e.js` — Section 5G-1B-IDENT (E1/E2).
- Docs: this record; `docs/decision-log.md`; `CODEX_STATUS.md`; operator package v3 repin.
