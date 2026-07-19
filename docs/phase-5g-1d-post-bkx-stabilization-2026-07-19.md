# Post-BKX Stabilization & Goal-Funding Validation — Execution Checkpoint

**Date:** 2026-07-19 · **Production:** `main` e4da0ff (RC-1b live; `BUILD_TS 2026-07-19T01:51:10`)
**Local (unpushed):** `a596826` — R1 BKX governance (`d059a9c`) + TX-1.2 backlog (`a596826`).
**Type:** Sequencing checkpoint (docs-only). Gates resumption of the canonical roadmap. **No code, SQL,
migration, schema, or production-data change is made by this record; nothing here authorizes execution.**

## Purpose
A single controlled sequence to run **immediately after the BKX remediation and before resuming the normal
roadmap**: finish BKX settlement, close the Week 23/24 historical-task anomaly, validate goal funding
post-5G-1D, fix any defects, finalize docs — then resume. Each step is **separately authorized**.

## Where we are (entry state)
- **RC-1 / RC-1b** activated to production (`48afc4c` / `e4da0ff`); OPEN commission-tax display normalized to the authorized amount.
- **S0–S1** complete; the authorized **$417.83** Week-29 (model wk 7) leg executed. Failed **S3** (Edit-Week entry of the Extra BK Pay) **fully rolled back**; production restored — pool `control_status = ok`, tracked remaining **$0**, legs **$425.68 / $417.83** intact, Week-28/Week-29 balance pins unchanged.
- **BKX remediation R1–R4:** governance recorded (`docs/phase-5g-1d-bkx-income-adjustment-2026-07-19.md`, `docs/decision-log.md`, `CODEX_STATUS.md`); R2 read-only duplicate-scan package authored; the interim Week-29 **off-pool** custom task **created** (`BKX-20260717`, $700.90) — **incomplete; the transfer is scheduled but not yet settled** (Vio; effective **2026-07-20**). It **must not be marked complete until settlement is confirmed**. No modeled cash event was created; the live commission-tax pool remains `control_status = ok` with **remaining $0**.

## Execution order (each step separately authorized)

### 1. Finish BKX settlement (R5–R7)
- The **$700.90** transfer is **scheduled** through Vio (effective **2026-07-20**), **not yet settled**. **Verify settlement** at the bank (confirmation number / evidence, owner-held; not committed).
- Complete the **BKX custom transfer task** — owner-only, and **only after settlement is confirmed** (do not mark complete on the scheduled state alone).
- Complete the **BKX action item** (the Week-29 checking-capacity mitigation item — see *Outstanding architectural risk*).
- **Final BKX verification + close the incident:** legs **$425.68 / $417.83** unchanged; pool `ok`, tracked remaining **$0** (BKX is off-pool by design); Week-28/Week-29 balance pins unchanged; **exactly one** BKX representation; conservation `425.68 + 417.83 + 700.90 = $1,544.41`. Then mark the incident record **CLOSED** and refresh the CODEX_STATUS note.

### 2. Week 23/24 historical-task investigation — **read-only**
- Read-only diagnosis of the previously-checked model wk 1 / wk 2 (Cal Wk 23 / 24) tasks now rendering unchecked.
- Determine **root cause** — confirm against the known **5G-1D-HIST-1** legacy null-identity / label-drift display class (per S0; `resolveWeekTransfers` tiering + the commission-tax exclusion from the "Executed earlier" fallback).
- **No production changes** during diagnosis. Use the approved read-only Baseline A/B + row-inventory queries in the owner session.

### 3. Week 23/24 repair
- Implement the **smallest safe repair** — display / identity-resolution scope only. **Never** a historical re-check (which would POST a new `weekly_tasks` row and violate the pre-anchor write-lock).
- Verify **no historical balances, snapshots, or commission-tax state change**: reconciled weeks 1–5 immutable; pool unchanged (`ok`, remaining $0, legs intact); no `goal_funding_snapshots` mutation.

### 4. Post-activation goal-funding deep dive — **validation report**
Compare **pre/post 5G-1D** behavior and verify:
- **Goal-funding conservation** — sums reconcile; no goal over/under-funded vs the model.
- **Open-week recommendations** — correct sweeps at open weeks; no stale or duplicated recommendations.
- **Duplicate suppression** — the open-week executed-vs-recommended netting gate holds (no re-surfaced executed transfers; ref `docs/phase-5g-1b-openwindow-netting-2026-07-15.md`).
- **Snapshot integrity** — `goal_funding_snapshots` anchor + corrections intact (nine `opening_anchor` rows; the Option-B `adam_ira` correction).
- **Checking-floor behavior** — the **$6,500** floor is respected across sweeps; no breach.
- Produce a **written validation report** (docs). Coordinate with / subsume the **queued** Stage-2 "2026 goal-funding & waterfall-integrity" audit (queued — not yet committed to the repo) as appropriate.

### 5. Fix any defects discovered by the deep dive
- Scope, review, and (on approval) implement the **smallest correct fix** for any defect. Full static + e2e test bar; byte-identity re-proven on the frozen surfaces (`runModel` / `computeGoalTransferNetting` / `resolveWeekTransfers`); its own commit; **not** folded into unrelated work.

### 6. Finalize documentation
- Commit remaining documentation. **Push only after approval.**

### 7. Resume the canonical roadmap
- Only after steps 1–6 close, resume `docs/roadmap/canonical-roadmap.md` (P3b-1 onward).

## Outstanding architectural risk (carried)
The BKX incident demonstrated that **custom transfer tasks do not reserve modeled cash capacity** — the
pool and goal waterfall never read `customTaskData` (`index.html:3326`), so a **$700.90** custom transfer is
invisible to the model's floor / sweep math until it is executed and reconciled. The **Week-29
checking-capacity action item** mitigates this **operationally** (confirms checking has room for the pending
$700.90 before other sweeps consume it), but a **permanent architectural solution remains deferred to the
TX-1.x workstream** — specifically **TX-1.2** (structured custom-transfer task metadata,
`docs/tx-1-candidate.md`) and the incident **§10 `source_id`** mechanism
(`docs/phase-5g-1d-bkx-income-adjustment-2026-07-19.md`). Until one of those ships, any off-pool custom
transfer of material size requires the operational capacity check.

## Guardrails
- **Remaining hold is narrow.** The ordinary commission-tax pool is **fully settled** (`control_status = ok`,
  remaining **$0**) — there is no general commission-tax execution hold left. The only open holds are:
  (a) **do not mark BKX complete before settlement is confirmed**; and (b) **do not execute the Wendy IRA
  transfer until BKX settlement and checking capacity are verified**.
- Steps **2** and **4** are **read-only**; step **3** is display / identity scope only; step **5** is code
  only under its own approval + full test bar.
- **No** historical re-check, **no** snapshot / reconciliation / balance mutation, and **no** `runModel` /
  waterfall / `commission_tax` / write-guard change except where a step explicitly scopes it and it is
  separately approved.
- **Push only after approval** (step 6). Local `main` currently holds unpushed docs commits; `origin/main`
  stays `e4da0ff` until an authorized push.

## Cross-references
- BKX incident / interim design: `docs/phase-5g-1d-bkx-income-adjustment-2026-07-19.md`
- TX-1.2 structured custom-transfer task metadata: `docs/tx-1-candidate.md`
- Goal-funding / waterfall integrity — **queued audit, not yet committed** (to be its own dated `docs/phase-audit-…` record); related prior review: `docs/funding-model-integrity-review-2026-07-08.md`
- Open-week duplicate-transfer / netting control: `docs/phase-5g-1b-openwindow-netting-2026-07-15.md`
- Canonical roadmap (resume target): `docs/roadmap/canonical-roadmap.md`
