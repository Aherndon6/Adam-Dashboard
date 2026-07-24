# Step 6A — Production Evidence and Cash-Event Integrity Validation (balance-free record)

**Date:** 2026-07-23 · **Repo at validation:** `main` == `origin/main` == `e072d6c`
**Deployed:** `5af688e` (code `21c6fc5`), `BUILD_TS 2026-07-23T00:12:07`
**Production:** `usayoldrawwmjsmretin`, authenticated as owner
**Access:** read-only. Every `/rest/v1` call was an HTTP **GET** (PostgREST GET == SELECT). The only
non-GET was the Supabase auth token endpoint. No production write, correction, schema change, code
change, commit, push, `BUILD_TS` change, financial action, or Step 7 work was performed.

> **BALANCE-FREE RECORD.** Per the standing evidence discipline (canonical roadmap §4 item 7;
> `execution-ledger.md` / `decision-log.md` headers), **no account balances appear in this document.**
> Reconciled account balances, the week-7 cash bridge, and all probe balance outputs live in the
> **valued execution package**, outside this repository:
> `~/Documents/Herndon Financial OS/Execution Packages/Post-BKX Stabilization/valued-evidence/`
> → `EP-01-step6a-production-evidence-VALUED.md` (this document's valued twin; section numbering matches).
> Obligation, transfer, goal, and statement amounts appear here per the `CODEX_STATUS.md` precedent.

---

## A. Executive summary

**The production Financial OS is not currently reliable enough to govern spending, checking capacity, or
transfer timing. It is reliable for goal-funding arithmetic and for the commission-tax obligation
ledger.**

Two hard gates carried from the Step 6 engine validation **CLOSE** with live evidence:

- **Week-6 `adam_ira` snapshot = $7,500.00** (`source = correction`, written 2026-07-18T18:31:24).
- **Post-week-6 `goal_adam_ira` recommendations = 0**, computed by the deployed model on live production
  state. The Adam IRA duplicate is **proven suppressed**, not presumed.
- **Commission-tax pool: `ok`, total $2,272.43, remaining $0.00**, with the pre-anchor attestation
  independently corroborated against live reconciled tax-reserve deltas.

But the Step 6A question — does production represent every material cash event exactly once, in the
right amount, direction, account, week and lifecycle state — is answered **no**, and the consequence is
live: **the app recommends a Wendy IRA sweep whose execution would breach the $6,500 operating floor.
The row renders `normal`. Nothing blocks it, and nothing warns.**

The root cause is not arithmetic. The modeled week-7 opening position is materially stale, and the entire
variance is explained by cash events that settled in week 7 while being modeled in week 6 or not modeled
at all. **The model's internal arithmetic is correct on inputs that no longer describe reality.**

Separately, the **Alaska reimbursement is not a cash movement — it is a goal disbursement**, and the
system has no concept of one.

---

## B. Live production baseline (structural facts; values in EP-01 §B)

| store | count | note |
|---|---|---|
| `weekly_reconciliations` | **6 rows, weeks 1–6** | balances → EP-01 §B1. Weeks 1–3 carry `balance_basis = null`; week 6 uses `available_balance` |
| `goal_funding_snapshots` | **20 rows** | week 5 = 9 `opening_anchor` + 2 `correction`; week 6 = 9, of which `adam_ira` is `correction` |
| `weekly_tasks` | **16 rows** | the sixteenth is `7_1` — see §B3 |
| `custom_tasks` | **16 rows** | week 7 carries the BKX, BKX-verification, Alaska-reimbursement, Costco-era and Jabian-reminder items |
| `cash_commitments` | **6 rows** | five resolved; one live reserve (AMEX Gold, `status = initiated`, `reflected_model_week = null`) |
| `goal_registry` | **13 rows** | `adam_ira` / `wendy_ira` target $7,500; `alaska` $7,000, status `funding` |
| `model_week_overrides` | weeks 2, 3, 4, 6, 7, 8 | week 11 has no override; `WD` carries the modeled AMEX Gold estimate |

**Goal-funding baseline (goal quantities — permitted):**

| goal | wk5 | wk6 |
|---|---|---|
| `adam_ira` | 7,438.94 | **7,500.00** *(correction)* |
| `alaska` | 7,000.00 | 7,000.00 |
| `wendy_ira` | 0.00 | 0.00 |
| `wendy_sep` | 17,859.21 | 17,859.21 |
| `bailey_529` / `bryce_529` / `preston_529` / `bryce_vehicle` / `christmas_cruise` | 0.00 | 0.00 |
| `wewe_rccl` / `wewe_dcl` | 600 / 500 | *(correctly excluded from the eligible nine)* |

**Snapshot continuity** through the latest reconciled week is **intact**. Weeks 1–4 are reconciled with
no snapshot — by design; week 5 is the opening anchor.

### B3 · The sixteenth `weekly_tasks` row, identified

Row **`7_1`** — `action_key = goal_adam_ira`, `completed = false`, no amount, no label, no timestamp. It
is the **residue of the Adam IRA duplicate that the Step 6 engine validation predicted**: before the
18:31 correction the week-6 snapshot read 7,438.94 and the model emitted a $61.06 Adam IRA row at week 7
index 1. **The risk materialised in production, was caught, and the correction closed it — the orphan row
remains.** Calculation-inert (verified): the resolver excludes incomplete rows, `_hasOpenCredit` requires
`completed`, history counts are correct, and `_resolveWriteTarget` allocates a fresh index rather than
clobbering it.

### B4 · Register coverage is partial

`transactions` covers **4 of 14 accounts**: `truist_checking`, `amex_gold`, `amex_platinum`,
`chase_disney_visa`. **`truist_savings`, `vio_tax_reserve`, `amex_savings`, `lending_club_ef`, and
`vio_emergency_savings` have zero Register rows** — their positions exist only as manually-entered
reconciliation figures. This is what makes the Alaska disbursement hard to detect.

### B5 · Commission-tax pool (live)

```
control_status = ok · total_obligation $2,272.43 · executed_total $1,654.82 · remaining $0.00
origins: wk2 993.29 pre_anchor settled 993.29 | wk4 435.63 pre_anchor settled 435.63
         wk6 843.51 post_anchor settled 843.51 (FIFO legs: wk6 425.68 + wk7 417.83)
legs: 2_0 375.68 · 4_0 435.63 · 6_1 425.68 · 7_0 417.83
```

**Correction to the Step 6 engine report:** origins are wk2 / wk4 / **wk6 (843.51)** — 425.68 and 417.83
are *legs*, not origins. Total and remaining unchanged.

**The pre-anchor attestation is independently corroborated** by live reconciled tax-reserve deltas
(delta values in EP-01 §B8): the wk1→2, wk2→3, wk3→4 and wk4→5 movements match the attestation's claimed
obligation, its "reconciled taskless carry" identity, its recorded residue note, and its wk4 origin
**exactly**. This was previously a reviewed assertion; it is now verified evidence.

---

## C. Material cash event inventory (summary; full table in EP-01 §C)

Twelve material events traced end-to-end through: real-world obligation → bank → Register → weekly model
→ task state → goal ledger → snapshot → recommendation engine → checking capacity → history.

**Confirmed represented exactly once:** the AMEX Gold payment, both commission-tax legs, and the Wendy
Extra BK Pay (whose deliberate absence from the model is correct — the cash is inherited through the
reconciled week-6 close).

**Confirmed omitted from cash and goal calculations — four events:**

| event | amount | why invisible |
|---|---|---|
| BKX tax reserve | $700.90 | custom-task-only; settled at the bank; never a modeled cash event |
| Jabian "Extra" receipt | $22.26 | received; in no model event |
| **Alaska reimbursement** | **$770.95** | custom-task-only; **and economically mis-typed** — recorded as a transfer when it is a goal disbursement |
| household misc (Greenlight / Venmo / Lively) | net small | in the Register, in no model event |

**Structural proof:** `customTaskData` is referenced **zero** times between `index.html:2280` (`runModel`)
and `:3760` (end of netting); the only mention in that band is the comment at `:3212` confirming it is
intentionally not scanned. `custom_tasks` carries no amount, direction, source account, destination
account, or status — financial identity exists only inside free text.

**Lifecycle defect observed across three events:** task completion preceded bank settlement by 2–3 days
for both commission-tax legs and for BKX. The BKX case contradicts the standing guardrail *"do not mark
BKX complete before settlement is confirmed."* The economic outcome was correct; the control was not
honoured.

---

## D. Cash reconciliation — week 7 (structure; all values in EP-01 §D)

The week-7 bridge was reconstructed from the Register and reconciles **with $0.00 unexplained**, but only
after itemisation. The variance is entirely composed of:

1. the **AMEX Gold payment**, settled in week 7 but modeled in week 6;
2. **both commission-tax legs**, settled in week 7 but modeled in week 6;
3. **BKX**, settled in week 7 and never modeled;
4. small unmodeled household inflows and outflows;
5. two immaterial modeled-vs-actual deltas (Adam paycheck, Jabian reimbursement).

**Acceptance criterion result:** actual and modeled cash **do** reconcile after timing differences with
zero unexplained residual — **but the timing differences are not benign.** A material block of outflows
sits in the wrong week and the model has no mechanism to notice.

**Capacity consequence:** the modeled deployable-for-sweep figure exceeds the reality-based figure, and
executing the recommended Wendy IRA sweep at face value **breaches the $6,500 operating floor**. Even if
the Alaska release lands first, it remains short. Worked figures: EP-01 §D.

---

## E. Goal reconciliation

Conservation identity applied per goal: `opening funded + valid inflows − valid disbursements = current`.

**Every active goal conserves exactly. Zero unexplained goal variance.** `adam_ira` closes to the cent
(7,438.94 + 61.06 = 7,500.00). `wendy_ira`'s three scheduled sweeps sum exactly to its $7,500 target.
Open-week completed-transfer credits: **none** — which is why `computeGoalTransferNetting` returns an
empty disposition map. That is correct, not a malfunction.

### E2 · Alaska — the disbursement determination

Truist Savings **is** the `alaska` goal's destination account. The pending $770.95 movement is therefore
**not** a cash movement. It is (a) a **goal disbursement** and (b) a **reimbursement of checking**, which
fronted the Alaska charges inside the already-paid AMEX Gold statement.

It requires cash movement **and** a reduction of the Alaska funded position **and** a reconciled record
distinguishing a deliberate spend-down from underfunding. **The third does not exist.** Both handlings
were probed against the deployed model on live state:

- **Reduce the snapshot** → the waterfall emits an **actionable $770.95 re-funding at Cal Wk 31**,
  nullifying the reimbursement.
- **Leave the snapshot** → the goal reports full funding while its cash has partly left, and the modeled
  **Cal Wk 37 Alaska draw renders BLOCKED** on its `sav >= 7,000` guard.

**Both are wrong.** `goal_funding_snapshots.source ∈ {opening_anchor, reconciliation, correction}` — there
is no `disbursement`.

---

## F. Findings register (severity · defect type · disposition)

| ID | Sev | Type | Finding | Disposition |
|---|---|---|---|---|
| **C-1** | Critical | calculation + architecture + observability | Checking capacity overstated; the app recommends a floor-breaching Wendy IRA sweep, disposition `normal`, no block and no warning | **controlled + deferred** — operational hold; full-horizon floor guard deferred behind DR-1 |
| **C-2** | Critical | architecture | Alaska goal disbursement unrepresentable; both handlings produce a wrong outcome | **controlled + deferred** — interim ledger + snapshot-hold; owned by 5G-1B |
| **H-1** | High | operating-process + observability | Material week-7 variance from wrong-week placement of settled outflows | **fixed at the week-7 reconciliation** |
| **H-2** | High | architecture | Material cash events have no first-class representation or stable financial identity | **controlled + deferred** — `cash_commitments` interim; TX-1.2 / L3 |
| **H-3** | High | operating-process | Task completion is not a settlement proxy — three documented instances | **controlled** — settlement-not-completion rule |
| **M-1** | Medium | production-data | Stale `cash_commitments` reserve; the AMEX Gold row remains `initiated` after clearing | **fixed inside the week-7 reconciliation** — *never standalone* |
| **M-2** | Medium | calculation / observability | Phantom deferred `commission_tax` row rendered on a fully-settled pool | **controlled — fails closed** (`_ctWriteGuard` refuses: `no_actionable_allocation_this_week`) |
| **M-3** | Medium | production-data | Orphan `weekly_tasks` row `7_1` | **controlled** — inert; evidence-controlled cleanup under D-11 |
| **M-4** | Medium | production-data / process | Jabian modeled amount differs from the received amount; a companion receipt is unmodelled | **fixed at the week-7 Edit-Week correction** |
| **L-1** | Low | observability | Register covers 4 of 14 accounts | **accepted + deferred** |
| **L-2** | Low | production-data | Weeks 1–3 carry `balance_basis = null` | **accepted** — historical, immutable |
| **L-3** | Low | documentation / control | Activation, closeout, revoke and correction records absent from the ledger and decision log | **open** — this document set begins closing it |
| **L-4** | Low | production-data | The Alaska goal-funding transfer is categorized as trip spending, inflating apparent consumption | **open** — recategorization authorized separately |

**Observations.** `goalFlags.ira_cpa_cleared = false` yet `goal_wendy_ira` is recommended — deliberate:
`_amxHold` goals bypass the `needsFlag` gate because the destination is AMEX Savings *holding*, not an
IRA contribution. `wendy_sep` has a persisted snapshot but no `goalSaved` key — correct for a
`status = executed` goal. Positively: the commission-tax attestation is now corroborated against live
reconciled data, and the Adam IRA duplicate is proven suppressed.

---

## G. Readiness at time of validation

| item | answer | risk |
|---|---|---|
| Alaska reimbursement | **NO** *(subsequently: proceed only under the interim operating decision)* | High |
| Wendy IRA transfer | **NO** | High |
| Closing Step 6 | **NO** — 8 criteria met, 1 partial, 4 failed | — |
| Proceeding to Step 7 | **YES WITH CONDITIONS** — scoped to C-1 and C-2 first | Moderate |

---

## H. Method and reproducibility

Evidence was produced by (a) read-only production queries; (b) deterministic execution of the **deployed**
`index.html` against live production inputs, replicating `loadAll()`'s wiring exactly; and (c) the local
gates — static regression **1618 / 0** and full `node e2e.js` **162 / 0 / 0**, readiness fallbacks 0 / 0.
Frozen calculation surfaces were re-proven byte-identical: `runModel` `5181b79cbba47e68` ·
`computeGoalTransferNetting` `4670447ce489dd8b` · `resolveWeekTransfers` `20d17438996ac8ba`.

Probe scripts and their valued outputs are retained in the execution package outside this repository.

---

## Cross-references

- Interim Alaska operating decision: `docs/phase-5g-1d-alaska-interim-operating-decision-2026-07-23.md`
- Step 6B canonical plan: `docs/phase-5g-1d-step6b-canonical-plan-2026-07-23.md`
- Independent architecture review: `docs/phase-5g-1d-step6b-architecture-review-2026-07-23.md`
- Stabilization sequence: `docs/phase-5g-1d-post-bkx-stabilization-2026-07-19.md`
- Valued evidence: execution package `EP-01` (outside this repository)
