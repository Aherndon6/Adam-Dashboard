# 5G-1D — Wendy Extra BK Pay (BKX) Off-Model Income Adjustment — Incident & Interim Design Record

**Date:** 2026-07-19 · **Production:** `main` e4da0ff · `BUILD_TS` 2026-07-19T01:51:10 · RC-1b live
**Status:** DESIGN / DOCUMENTATION (R1). No code, SQL, migration, schema, or production-data change. The
$700.90 task is **not** created or executed by this record.
**Controlling verdict:** Fable — **PROCEED WITH CONDITIONS** (interim off-pool custom task).
**Source identity:** `BKX-20260717`.

> **Balance-free note.** Per standing law (balance-free committed docs), the reconciled Week-28 ending
> Truist Checking actual and the Week-29 beginning value are referenced here as **pins** only; the literal
> balance figure is held in owner/local evidence, not committed. All amounts below are commission-tax
> obligation / transfer / deposit amounts, not account balances.

## 1. Incident chronology
- **S0** (read-only classification) and **S1** completed. S1 executed the authorized **$417.83** Week-29
  (model wk 7) commission-tax transfer (Truist Checking → Vio Bank – Tax Reserve) and marked only the
  matching Week-29 task complete. Week-28 (model wk 6) already carried the completed **$425.68** leg.
- **S3** (attempted, then rolled back): to represent the real-world **Wendy Extra BK Pay $1,752.26**
  (posted 7/17/2026, taxable), the inflow was added through **Week-28 Edit Week** with the TAX flag and
  Save & Recalculate. This is the confirmed-unsafe path.

## 2. Failed S3 behavior (root-caused, read-only)
Adding the taxable inflow to reconciled Week 28 (`ct = Σ taxable × 0.40`, index.html:3916-3917):
- raised the Week-6 commission obligation to **$1,544.42** (one merged origin — the pool builds exactly
  one origin per `ct`-week, index.html:3372-3373 / 3387-3398);
- left **$700.91** authorized remaining (`1544.42 − 843.51`);
- **orphaned the completed Week-29 $417.83 row from the UI** — the added inflow inflated the *within-week*
  modeled checking that the commission `mv()` reads (index.html:2313 vs 2644), so the model moved the full
  obligation at Week 6, Week 7 emitted **no** commission-tax recommendation, and the durable completed row
  lost its render anchor (commission-tax is excluded from the legacy "Executed earlier" fallback,
  index.html:5256). The persisted `weekly_tasks` row was **not** deleted or amount-changed (the B1
  commission delta-PATCH is removed, index.html:3944) — display orphaning only, no data loss;
- left the **$700.91 unslotted** (no open commission week to place it in, index.html:3473-3482);
- created an actionable **$624.97 Wendy IRA** task in reconciled Week 28 (goal-sweep delta artifact of the
  60% share increasing the modeled surplus).

## 3. Rollback evidence
S3 was **fully rolled back** (the Week-28 override edit reversed), restoring the pre-S3 / post-S1 state.

## 4. Confirmed restored production state (verified)
- commission pool `control_status = ok`; **total tracked obligation = $2,272.43**; **pool remaining = $0.00**
- Week 2: obligation $993.29 / settled $993.29 / remaining $0 · Week 4: $435.63 / $435.63 / $0 ·
  Week 6: **$843.51 / settled $843.51 / remaining $0**
- completed commission-tax legs intact and visible: **Week 28 = $425.68**, **Week 29 = $417.83**
- Week 28 reconciled Truist Checking actual = **[reconciled pin — value in owner/local evidence]**
- Week 29 beginning Truist Checking = **[same reconciled pin]**
- no $624.97 Wendy IRA artifact; no duplicate commission-tax task

## 5. Standing NO-CASH-EVENT prohibition (controlling law)
The **$1,752.26 must never be added as a model cash event** in Week 28, Week 29, or any other week. The
cash is already inherited through the reconciled Week-28 ending balance. Adding it anywhere as an inflow
double-counts the cash and (in a reconciled week) redistributes the commission recommendation, orphaning a
completed leg (§2). **Only the tax-reserve obligation is represented operationally — never the cash.**

## 6. Exact $700.90 rounding basis
Standalone authority = `round(1752.26 × 0.40) = round(700.904) = ` **$700.90** — computed on the Extra BK
Pay's own gross (matches the model formula `Math.round(taxableGross*0.40*100)/100`, index.html:3917). The
transient **$700.91** was a *merge artifact* — 40% of the summed gross minus the rounded Week-6 leg
(`round(3861.04×0.40) − 843.51 = 1544.42 − 843.51 = 700.91`), i.e. rounding the sum rather than each origin
on its own gross. Because BKX is a **separate obligation**, its authority is **$700.90**. $700.91 is discarded.

## 7. Four distinct concepts (do not conflate)
| Concept | What it is | Where it lives |
|---|---|---|
| **Reconciled cash truth** | The $1,752.26 cash already sits inside the reconciled Week-28 ending checking balance. | `weekly_reconciliations` (already persisted). **Immutable; never re-add.** |
| **Future income classification** | A display/reporting label "Wendy Extra BK Pay" for the income. | **TX-1.1** (future; §11). Must NOT retrigger tax or cash placement. |
| **Interim tax obligation** | The operational $700.90 tax-reserve transfer to execute. | One off-pool **Week-29 custom task**, `BKX-20260717` (§8). |
| **Long-term ledger origin** | The durable, pool-integrated representation of the obligation. | Future **`source_id`** historical-taxable-income mechanism (§10). |

## 8. Interim custom-task controls (mandatory)
- **Unique source identity:** `BKX-20260717`.
- **Exact task label:** `Transfer $700.90 from Truist Checking to Vio Bank – Tax Reserve (Wendy Extra BK Pay commission tax; income posted 7/17/2026; BKX-20260717)`
- **Placement:** a single `custom_tasks` transfer task in **Week 29** (current open operational week).
  Off-pool by construction — the pool never reads `customTaskData` (index.html:3326), so it cannot merge
  with the Week-6 origin, orphan a leg, or trigger a `runModel` recompute.
- **Owner-only** creation and completion. **Wendy no-touch** for this item.
- **Pre-create duplicate scan** (read-only) across `custom_tasks`, `weekly_tasks`, and `cash_commitments`
  for: `BKX-20260717`, `Wendy Extra BK Pay`, and `700.90`. Abort creation on any hit.
- **No second representation** — this item must NOT also appear via a Phase-3 manual reconciliation entry
  or any closeout snapshot. Exactly one BKX representation exists.
- **Week-29 closeout variance pre-declaration:** Truist Checking **−$700.90**; Vio Tax Reserve **+$700.90**
  (deltas only; balances unchanged elsewhere).
- **Completion only after bank settlement**, with a **confirmation number / evidence** captured (in owner
  evidence, not committed).
- **Post-execution verification (all must hold):**
  - $425.68 and $417.83 legs unchanged;
  - pool `control_status = ok`; **tracked pool remaining = $0.00** (BKX is off-pool by design);
  - Week-28 and Week-29 balance pins unchanged;
  - exactly one BKX representation exists;
  - **conservation:** `425.68 + 417.83 + 700.90 = $1,544.41`, within $0.01 of the prohibited merged-basis
    **$1,544.42** (the $0.01 is the per-origin vs summed-gross rounding difference; $1,544.41 is correct
    because each origin is taxed on its own gross).

## 9. Rollback procedure (interim)
The custom task is fully isolated. To reverse: `DELETE FROM custom_tasks WHERE id = '<the BKX task id>'`
(and drop it from `customTaskData`). This touches no leg, balance, override, reconciliation, or pool.
If executed before this reversal, do **not** attempt an automated unwind — record and reconcile manually.

## 10. Long-term `source_id` architecture (remediation; NOT implemented here)
A dedicated **historical/off-model taxable-income adjustment** mechanism that:
- injects a commission-tax obligation with its own **`source_id`** identity (e.g. `BKX-20260717`), **never**
  keyed to a `week_num` that already holds a commission origin or a completed leg (so it can never merge
  with the Week-6 origin);
- carries **posting-date metadata** (7/17/2026) without adding a cash event and without rerunning cash
  placement;
- slots its authority to the current open week under the normal exact-match write guard and RC-1b display;
- is **staging-tested and reviewed** before any production use. Requires code and a lightweight persisted
  record for the historical income.

### Migration / attestation rule (binding on the long-term mechanism)
When the `source_id` mechanism ships, it **must adopt the interim BKX completion as already-settled and
never re-emit it.** Specifically: the migration must recognize the executed interim custom task
(`BKX-20260717`, $700.90) as the durable settlement of the BKX obligation — mapping it into the new ledger
as `settled`, analogous to the era-partition attestation for pre-anchor origins — so the pool shows the BKX
obligation **closed**, not a fresh actionable $700.90. Re-emitting BKX as a new actionable transfer is a
hard defect.

## 11. TX-1.1 linkage (future; do not implement now)
The income-classification requirement is deferred to **TX-1.1**:
- exact classification label: **Wendy Extra BK Pay**;
- **display/reporting only**;
- **must not** retrigger tax computation or cash placement (the cash is reconciled; the tax obligation is
  represented via `BKX-20260717`);
- do **not** implement TX-1.1 as part of this remediation.

## 12. PATH-B* supersession
The prior operator-package **PATH-B\*** instruction — to enter the Extra BK Pay in **Week 29** (or any model
week) as its own commission origin — is **SUPERSEDED and PROHIBITED**. Entering this income as a cash event
in Week 29 or any model week is not permitted: the cash is already represented through the reconciled
Week-28 ending balance, and only the **obligation** is represented operationally (via `BKX-20260717`).

## 13. Hard-stop conditions
Stop and do not proceed (or, if mid-flight, stop and report) on any of:
- any attempt to add the $1,752.26 as a cash/inflow event in any week;
- either completed leg's `completed_amount` deviating from $425.68 / $417.83;
- pool `control_status ≠ ok` or **tracked pool remaining ≠ $0.00** attributable to a BKX write;
- more than one BKX representation across `custom_tasks` / `weekly_tasks` / `cash_commitments`;
- the Week-28 or Week-29 balance pin changing;
- any attempt to record BKX in `docs/execution-ledger.md` before an executed production SQL statement exists
  (§14);
- the long-term mechanism re-emitting BKX as a fresh actionable transfer (§10 migration rule).

## 14. Governance
This pending **operational** item is **not** recorded in `docs/execution-ledger.md` (that ledger is reserved
for **executed production SQL**). BKX governance lives in: this incident record, the `docs/decision-log.md`
row, and the `CODEX_STATUS.md` currency note.

## 15. Sequencing
R1 (this record) → **R2 duplicate scan** (next authorized operational step) → controlled Week-29 custom-task
creation → owner execution after bank settlement → post-execution verification (§8). The long-term `source_id`
mechanism (§10) is a separate, later, code phase and must precede any pool-integrated re-representation.
