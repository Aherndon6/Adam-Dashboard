# Independent Architecture Review of the Step 6A Findings — record

**Date received:** 2026-07-23 · **Reviewer:** independent architecture review (ChatGPT adversarial
challenge + conformance check — the substitute review chain under canonical roadmap §11.2, Fable access
having ended 2026-07-19)
**Subject:** the Step 6A production evidence and cash-event integrity findings
**Type:** review record. Documentation only — no code, schema, SQL, production-data, or financial change.
**Balance-free:** this record contains no account balances.

> **Provenance note.** This is the review as delivered to the owner and relayed into the planning
> session, recorded here so the Step 6B plan's inputs are auditable. The Step 6B canonical plan
> (`docs/phase-5g-1d-step6b-canonical-plan-2026-07-23.md`) records, recommendation by recommendation,
> where the plan agreed, partially agreed, or disagreed — including one figure where independent
> re-derivation from the Register disagreed with the review and the owner subsequently confirmed the
> plan's figure.

---

## Executive verdict

**Proceed with changes.** The Critical findings are valid, but several architectural refinements should
be adopted before implementation.

---

## Primary conclusions

### 1. C-1 and C-2 are really one architectural problem
The Capacity Completeness Gate and the Goal Disbursement Lifecycle should not be designed independently.
A completeness gate is only as good as the registry of pending financial events it evaluates. Treat them
as one architectural capability rather than two unrelated features.

### 2. The proposed Funding vs Available model is incomplete
Instead of only distinguishing Goal Funding from Goal Available Balance, the recommended domain model
contains four quantities:

- **Funded** — historical appropriations; monotonic and never decreases
- **Consumed** — economic spending committed
- **Released** — cash actually reimbursed or transferred
- **Derived values:**
  - `Spendable = Funded − Consumed`
  - `Custody = Funded − Released`

**The critical invariant:** funding is historical achievement and must never decrease because of
spending. If spending ever reduces Funding, the waterfall will incorrectly recommend re-funding goals
that have already been successfully funded.

### 3. Goal consumption occurs before reimbursement
For Alaska: goal funding already occurred; spending already occurred; the AMEX Gold statement has already
been paid; the remaining action is reimbursing checking from the Alaska funds. **Therefore reimbursement
is not the consumption event.** Consumption occurred when the purchases were made. The reimbursement is
the settlement of checking's temporary advance.

### 4. The Goal Ledger should NOT become a second system of record
Authority should remain partitioned. The Goal Ledger should own only what nothing else currently owns. It
must not become authoritative for funding, Register transactions, or derived balances. The Register
remains authoritative for actual spending; goal funding snapshots remain authoritative for funding
history; derived balances remain derived. **Avoid creating "Quicken II."**

### 5. The existing roadmap already contains most of the required architecture
This work naturally belongs within **5G-1B**, **TX-1.2**, **D-11**, the **L3 Domain Event Ledger**,
**Identity Conventions**, and **Account Composition**. Extend those planned components rather than
introducing a parallel subsystem.

### 6. Capacity Completeness Gate
The gate is agreed, with refinements: enforce at recommendation/write time rather than merely suppressing
display; define explicit materiality thresholds; drive the gate from a durable event registry; avoid
unnecessary operator blackout where possible.

### 7. Exactly-once identity
Agreed, with recommendations: origin-based identity; support for reversals and refunds; enforcement at
write boundaries; conservation validation. Identity should be universal; state machines may differ by
object type.

### 8. Interim Alaska operating model
**Do NOT build temporary production architecture solely to process Alaska.** Continue using
statement-level reimbursements, a manual Goal Ledger, and existing operating controls. Implement the
long-term architecture later within the approved roadmap.

---

## Owner operating decisions recorded alongside the review

- Alaska reimbursement is **statement-level**.
- The Alaska charges have already been paid through the July AMEX Gold statement.
- The remaining action is reimbursing checking from the Alaska funds in Truist Savings.
- The Jabian "Extra" receipt remains ordinary checking cash and will be swept naturally by the normal
  waterfall.
- Per-charge reimbursement logic is intentionally avoided.

---

## Disposition

Adopted as the controlling architectural direction for Step 6B, subject to the modifications recorded in
`docs/phase-5g-1d-step6b-canonical-plan-2026-07-23.md` §Agreement/Disagreement. The plan's final
recommendation was **B — proceed with modifications**.
