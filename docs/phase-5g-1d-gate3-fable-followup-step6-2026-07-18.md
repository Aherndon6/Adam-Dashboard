# Phase 5G-1D — Fable follow-up: Option-C Step-6 HARD STOP (2026-07-18)

**Context.** Option C (PROCEED WITH CONDITIONS) is in supervised execution, one operator step at a time.
Steps 1–5 passed. **Step 6 (atomic balance/payment-state capture) hit a HARD STOP; reconciliation is
blocked.** Full record: `docs/phase-5g-1d-option-c-operator-script-2026-07-18.md` §F; operator package
§14.2/§14.3; decision-log 2026-07-18. **No production mutation beyond the recorded Step-3 outflow-only AMEX
edit and Step-5 AMEX bank submission. Week 28 is OPEN; nothing pushed.**

## What happened

The Step-3 outflow-only AMEX correction (`$5,718.52 → $5,666.01`, −`$52.51`) is SQL-proven safe on the
completed rows (commission_tax `425.68` and goal_adam_ira `61.06` unchanged; no backfill; no drift). **But
it had two side effects the Option-C verdict did not model:**

1. **Variance does not decompose.** Step-6 capture: `A` (Truist available) = `14,505.40`, `M` (Week-28
   projected) = `6,500.00`, `V = A − M = 8,005.40`. The recorded §C components (income `1,752.26` + AMEX
   `5,666.01` + commission-tax `425.68` = `7,843.95`) leave an **unexplained residual of `161.45`** — the
   §C decomposition omitted the modeled-but-unsettled **Week-28 goal-funding transfers**, and the model's
   tax outflow is now `478.19`, not `425.68`. Fails the ≤ `$0.01` control as written.
2. **Commission-tax re-split.** The `$52.51` freed by the AMEX reduction was absorbed into the Week-28 tax
   allocation: the model now shows Week-28 tax = `478.19` and carry-forward = `365.32` (was `425.68` /
   `417.83`). Executed reality is still `425.68`, so the correct remaining Deep-South obligation is
   `417.83` (= `843.51 − 425.68`), **not** `365.32`. Booking `365.32` in Week 29 would underfund the
   `843.51` obligation by `52.51`.

Both are model-projection effects — no executed transfer or persisted row changed.

## Requested disposition

**A. Full Step-6 variance decomposition.** Confirm the complete set of Week-28 variance components,
**including every modeled-but-unsettled Week-28 transfer** (AMEX `5,666.01`, commission-tax [`425.68`
executed vs `478.19` modeled — which basis?], all goal-funding sweeps, unmodeled income `1,752.26`, less
any modeled inflow not yet posted). What is the exact expected decomposition so the residual closes to ≤
`$0.01`, and does the control operate on the raw `A − M` or on deployable/adjusted cash?

**B. The `52.51` tax re-split divergence.** Is the model's `478.19`/`365.32` re-split acceptable to leave
as a display projection, or must it be corrected? How is the executed `425.68` reconciled against the
model's `478.19` Week-28 recommendation without stranding or double-counting the `52.51`?

**C. PATH-B\* amendment for the Week-29 Deep-South leg.** Should PATH-B\* be explicitly amended so Week 29
preserves the **`417.83`** Deep-South leg (executed basis) regardless of the model displaying `365.32` —
i.e., the operator books `417.83 + 700.90`, ignoring the model's carry-forward figure? Confirm the exact
Week-29 legs and the guardrail against booking `365.32`.

**D. Operator-side control vs code correction.** Is an operator-side control sufficient (documented
enumeration of the variance components + a fixed `417.83` Week-29 leg), or does the re-split behavior
(surplus-driven reallocation of an already-executed tax obligation) require a **code correction** before
activation can proceed — i.e., must activation remain blocked pending code?

## Constraints (unchanged)
No reconciliation, wrapper, commitment creation, Phase 2, deploy, revoke, or push. No Week-28 Extra BK Pay
entry (§2d). No Weeks 1–5 edits (§13). Baseline A/B (`4/4·2/2·0/0·1/1·5/5`; `15/14/1`) and the executed
`425.68` @ `2026-07-18 03:20:38.457+00` must remain unchanged. Gate 3 HARD-STOPPED pending this disposition
+ Adam authorization.

---

## FABLE DISPOSITION (2026-07-18) — ADOPTED (owner); authoritative record: operator package §14.4

**A. Variance decomposition.** The control was **mis-specified**; production state is correct. The gate
operates on **raw `V = A − M`** (never deployable/adjusted cash), captured with the full enumeration in
**one atomic observation window**. The commission-tax component enters at **model basis** as the
**dual-basis line `478.19 (model) = 425.68 (executed) + 52.51 (known re-split artifact)`**. Every
modeled-but-unsettled Week-28 **goal-funding leg** must be enumerated by **name/obligation · modeled
amount · executed status · bank-settlement status** and total **exactly `$108.94`** in-window (known
member: Adam IRA `$61.06`, executed-unsettled) — **an approximate or unnamed residual leg is not
sufficient evidence.** Recorded-capture closure: `1,752.26 + 5,666.01 + 478.19 + 108.94 = 8,005.40 = V`
exactly; the prior `161.45` residual = `52.51` (basis error) + `108.94` (omitted legs).

**B. `$52.51` re-split.** A **real defect** (B1 class: surplus-driven reallocation of an executed tax
obligation), demonstrated by a cash-side edit; on this build its blast radius is **display/projection
only** (backfill fires only on a positive taxable-income delta — SQL-proven rows unchanged; the closeout
reads no tasks; commission_tax is outside netting; the `425.68` row is identity-bound). **No hand
correction; no compensating Edit-Week entries.** Folded into B1 with added scope: completed legs anchored
by `completed_amount`; carry = total obligation − Σ completed executed legs; cash-side edits must never
re-split an executed leg; the `$5,718.52 → $5,666.01` case becomes a B1 regression fixture.

**C. PATH-B\*.** Amended: Week-28 `425.68` immutable; Deep-South remainder **pinned `417.83`**; Extra BK
Pay tax **pinned `700.90`**; Week-29 combined total **`1,118.73`** (two legs); **`365.32` never
executed**; **B1 required before the `417.83` leg** (fixed build must display `417.83`; escalation if B1
slips past ~Jul 23). Conservation: `425.68 + 417.83 + 700.90 = 1,544.41` = combined `1,544.42` within
≤ `$0.01`, checked at every §14.1 rerun.

**D. Activation.** **Operator-side control is SUFFICIENT for activation** (nothing persisted embeds
`478.19`/`365.32`; the wrapper consumes actual balances, persisted-snapshot priors, and the Phase-2 AMEX
commitment only). **Gate 3 RESUMES** on: corrected §C control + fresh atomic capture closing ≤ `$0.01` +
PATH-B\*/step-9 amendments recorded + **Week-28 Edit-Week closed for the sitting** + Adam's per-step
authorization. **B1 remains mandatory before the Week-29 Deep-South execution** — a code gate on that
step, not on activation.
