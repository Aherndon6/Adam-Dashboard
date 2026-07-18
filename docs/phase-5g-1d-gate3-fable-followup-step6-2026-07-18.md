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
