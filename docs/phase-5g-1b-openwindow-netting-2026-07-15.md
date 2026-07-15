# 5G-1B (rider) — Open-Window Executed-Transfer Netting / Suppression Control

**Date:** 2026-07-15 · **Class:** Mandatory 5G-1D **Gate B activation blocker** correction · **Type:** adapter / projection + write-guard only. **No `runModel`, waterfall, `goalSaved`, snapshot SQL/schema, wrapper, reconciliation, reopen, grant, or production-data change.** **Balance-free.**
**Owner:** Adam (design decisions §D) · **Implementer:** Claude Code (local) · **Review:** independent pass pending (§E).
**Supersedes for the reported symptom:** the display-only half of `docs/5g-1b-defect-reconciled-transfer-history-2026-07-11.md` (that fix preserved executed history; it did **not** stop a satisfied obligation re-presenting as a NEW executable PLANNED row).

---

## A. Root cause (confirmed in code + persisted rows)

The weekly model recomputes per-goal funding (`goalSaved`) from scratch on every recalc and pins it to reality only for weeks carrying a `goal_funding_snapshots` anchor (today: model wk 5 only). For the current open week and every future week the residual-to-target is re-derived (`index.html` waterfall + `retRem`) and the transfer re-emitted. An executed transfer is durably persisted in `weekly_tasks` (`action_key` + `completed_amount`) but **never feeds back into `goalSaved`**, so a recalc (e.g. editing the Wendy commission) re-emits an already-satisfied obligation as a fresh executable PLANNED row; the 5-week AMEX lookahead can also shift where the residual lands, so it can appear in more than one open week. Because both household writers can execute transfers, "don't click the duplicate" is not an adequate control.

## B. Design — one pure cumulative-netting function

`computeGoalTransferNetting(weeks, opts)` (adjacent to `resolveWeekTransfers` in `index.html`) is a pure projection over durable persisted state (`weekly_tasks` completions, `goal_funding_snapshots` baseline gated on `_goalSnapLoadStatus==='loaded'`, `GOALS_REGISTRY` targets). It nets by **durable obligation identity**, not volatile recommendation-row identity, cumulatively across the **full open/unreconciled horizon after the latest authoritative snapshot boundary**.

- **Obligation key / attribution:** goal id + direction (encoded by `action_key`) + funding cycle (`model_year`, bounded below by the latest reconciled+snapshotted week) + completion state + `completed_amount` (recovered from `completed_label` only if absent) + already-funded baseline (snapshot). Direction is cross-checked against the registry destination.
- **Classes:** `target_accumulation` (the nine snapshot-eligible goals) and `fixed_once` (`goal_adam_ira_seed`, which **never cross-nets** with adam_ira). All other actions (commission tax, tax base, setup, LC boosts, Alaska draws, custom tasks) are out of scope — **no amount-only, no cross-goal matching.**
- **Engagement gate (the key safety property):** netting engages for an obligation **only when it has ≥1 completed transfer in an open (unreconciled) week** — i.e. there is an executed transfer a recalc could duplicate. With no such completion the recommendation stays `normal` (a legitimate fresh transfer is never touched).
- **Math:** `keepBudget = max(0, (target − baseline) − creditedOpen)` distributed over the uncompleted candidate rows in `(week, idx)` order (each keeps `min(remaining, amount)`): fully covered → **suppressed**; clipped → **partial (net remaining)**; full → **normal**. `fixed_once` uses the analogous single-obligation budget.
- **Dispositions:** `normal` · `partial` · `suppressed` · `blocked`.
- **Fail-closed → `blocked`:** snapshot baseline not loaded/authoritative; missing/undefined goal target; unrecoverable completed amount; unparseable recommendation amount; executed credits exceed the modeled remaining obligation beyond tolerance ($1.00); completed-transfer direction inconsistent; `fixed_once` executed >1×; any internal error. Blocked rows are **visible, non-executable, with the exact reason** — never silently suppressed.

## C. Integration (smallest inline-adjacent surface)

- **Render (`renderWeekDetail`):** suppressed → read-only "**Satisfied by completed transfer**" row (checked, disabled, **no write context**); partial → executable at the **net** amount with an explicit "⚠ Partial — only $Y remains … confirm before executing" annotation (write amount = net; `completed_label` stays the model recommendation so the resolver still matches); blocked → amber "**Review required**" non-executable row with the reason; normal → unchanged. Executable total excludes suppressed and blocked.
- **Badges/counts:** a shared `_modelRowOpen()` predicate excludes suppressed rows from every open/badge/count site (`getWeekChipClass`, Overview `openActions`, History "Open Actions" filter/label/card).
- **Write-guard (defense in depth, `toggleTransfer`):** on a checked write it **recomputes the netting disposition** from the canonical model and **rejects** suppressed/blocked obligations before any optimistic state or persistence — a stale UI cannot bypass the control. Unchecking is always allowed.
- **Render-pass view:** refreshed once per pass (`_refreshTransferNet` in `renderApp`, and in `renderHistory` for the direct filter path).

## D. Owner decisions (Adam, 2026-07-15)

1. Mandatory pre-activation; Saturday production activation **slips** if it cannot meet the verification bar + reissue + local Adam verification. No fallback to the old package.
2. Implemented entirely in the adapter/projection + write-guard layers; frozen surfaces untouched.
3. `target_accumulation` = the nine; `fixed_once` = `goal_adam_ira_seed` (no cross-net).
4. Dispositions `normal/partial/suppressed/blocked` with the stated behaviors; completed history stays visible/unchanged.
5. Fail-closed on the six ambiguity conditions.
6. Render disable **and** independent write-path revalidation.
7. Smallest inline-adjacent implementation beside the resolver; **no ES-module extraction this week** — recorded standing exception, modularization roadmap preserved.

## E. Verification

- **Static:** `test_regression.js` Section **5G-1B-NET** (`5G1B-NET-1…19`): full satisfaction, cross-week placement shift, partial, multi-week ordered allocation, different-goal isolation, seed-vs-sweep separation, per-occurrence exclusion, null-amount / unparseable / over-credit / snapshot-uncertainty / direction-mismatch / seed-double blocks, no-credit-normal (uncheck), Edit-Week delta (no double-net), boundary-move-after-close, no-mutation, helper/count integrity, write-guard parity.
- **E2E:** `e2e.js` Section **5G-1B-NET** (`5G1B-NET-E1…E3`): incident reproduction (no enabled Adam IRA checkbox; row shows "Satisfied"); post-close no later-week recommendation; stale-UI write-guard rejection (no optimistic state).
- **Frozen-surface proof:** `.sql` files changed = **0**; `runModel`/waterfall/lookahead/latch/wrapper/row-9-guard/`submitCloseout` markers intact; golden-master + existing resolver + 5G-1D P0-4/P1-1 suites green; working-tree diff = `index.html` + `test_regression.js` + `e2e.js` only.
- **Counts / pins:** captured at commit — see the reissued Saturday operator package.

## F. Relationship to 5G-1D and 5G-1B (complementary, not a substitute)

- **5G-1D snapshots remain the authoritative funded-state mechanism after reconciliation.** After a week closes, its executed credit is absorbed into the snapshot anchor (reconciled → no longer "open"), the boundary advances, and this control steps back — the snapshot overlay prevents any later-week re-recommendation. This control fixes the **pre-close open-window** gap that snapshots alone do not.
- **This is an adapter-level netting control, not durable structured identity.** The 5G-1B `holding_events` ledger is scoped to RCCL/DCL and explicitly excludes Adam IRA, so it cannot serve as the durable identity solution for this class today — see the roadmap amendment `docs/roadmap/amendment-2026-07-15-progress-plane-transfer-identity.md`.

## G. Files changed

- `index.html` — `computeGoalTransferNetting` + helpers (`_refreshTransferNet`, `_xfrNetInfo`, `_xfrRowSuppressed/Blocked/Partial`, `_modelRowOpen`); `renderWeekDetail` render + counts; open-detection predicates; `toggleTransfer` write-guard.
- `test_regression.js` — Section 5G-1B-NET (19 tests).
- `e2e.js` — Section 5G-1B-NET (3 tests).
- Docs: this record; `docs/decision-log.md`; `docs/roadmap/amendment-2026-07-15-progress-plane-transfer-identity.md`; reissued `docs/phase-5g-1d-saturday-operator-package-2026-07-18.md`; defect cross-link in `docs/5g-1b-defect-reconciled-transfer-history-2026-07-11.md`.
