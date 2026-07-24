# Alaska Interim Operating Decision — Interim Goal Ledger, Lifecycle Rules, Operating Controls

**Date:** 2026-07-23 · **Authorization:** AU-6 of the frozen Step 6B Revision 2.1 execution package
**Type:** Operating decision + interim goal ledger. **Documentation only** — no code, schema, SQL,
production-data, or financial change is made by this record.
**Governing authority:** Step 6B Revision 2.1 execution package (frozen 2026-07-23), §AU-6.
**Evidence discipline:** **balance-free** (canonical roadmap §4 item 7; `execution-ledger.md` /
`decision-log.md` headers). Goal, obligation, transfer, and statement amounts appear here per the
`CODEX_STATUS.md` precedent. **Account balances do not appear in this record** — they live only in the
local execution package, outside the repository, and are referenced by name.

---

## 1. Why this record exists

The Alaska reimbursement is **not a cash movement**. Truist Savings is the `alaska` goal's destination
account (`goal_registry.alaska.dest`), so moving money out of it is a **goal disbursement** — an economic
event the system has no way to represent. `goal_funding_snapshots.source` admits only
`opening_anchor | reconciliation | correction`; there is no `disbursement`, so a deliberate spend-down is
arithmetically indistinguishable from underfunding.

Both available handlings were probed against the deployed model on live production state and **both are
wrong**:

- **Reduce the `alaska` snapshot** → the waterfall immediately re-emits an actionable
  **$770.95 Truist Checking → Truist Savings** re-funding at Cal Wk 31, clawing the reimbursement
  straight back out of checking.
- **Leave the snapshot alone** → the goal reports its full funded value while the cash behind it has
  partly left, and the modeled Cal Wk 37 Alaska draw renders **BLOCKED** because its `sav >= 7,000`
  guard is not met.

This record adopts the second handling **deliberately**, because it is the one that preserves the
funding-monotonicity invariant, and it makes the resulting week-15 consequence an explicit, expiring
accepted variance rather than a surprise.

**Long-term ownership:** the goal-disbursement lifecycle belongs to **5G-1B**, whose release lifecycle
must be generalized from RCCL/DCL to **release-bearing goals** (Alaska is one of the eligible nine and
therefore has no owning phase today). The durable home for consumption and release events is the **L3
domain event ledger that rides 1B** (canonical roadmap §4 item 2, branch (b)). **This interim ledger is a
migration source for that work, not a throwaway.**

---

## 2. Interim Alaska Goal Ledger

**Goal:** `alaska` · **Funded (monotonic, never reduced):** **$7,000.00**

| # | origin_id | type | amount | economic date (statement close) | cash date | **state** |
|---|---|---|---|---|---|---|
| 1 | `ALASKA-STMT-2026-06-24` | consumption | **$770.95** | ~2026-06-24 — prior cycle, **closed** | — | **SETTLED** |
| 2 | `ALASKA-STMT-2026-07-24` | consumption | **$607.10** | 2026-07-24 — cycle **OPEN** as of this record | — | **PROVISIONAL / OBSERVED** |
| 3 | `ALASKA-REL-2026-07-23` | release | **$770.95** | — | *pending* | **SCHEDULED** |

### 2.1 Row 2 itemisation (required by lifecycle rule 1)

| charge date | payee | amount | category |
|---|---|---|---|
| 2026-07-12 | NCL | **$489.86** | `trips.seattle_alaska_2026` |
| 2026-07-18 | Alaska Fishing Licenses | **$30.00** | `trips.seattle_alaska_2026` |
| 2026-07-19 | AMC Seattle | **$87.24** | `trips.seattle_alaska_2026` |
| | **total** | **$607.10** | |

> **Row 2 is PROVISIONAL and must not be called settled.** The 2026-07-24 AMEX Gold cycle has not closed
> as of this record; further Alaska charges may still post. The owner confirmation establishes that these
> three charges **are** Alaska-goal spending — it does **not** establish that the statement is final.
> AMC Seattle (2026-07-19) is intentionally Alaska-goal spending (owner-confirmed).

### 2.2 Row 3 — the release is scheduled, not settled

The **$770.95** Truist Savings → Truist Checking movement has **not been executed**. It is the settlement
of checking's advance for already-consumed Alaska spending — checking bore those charges when the prior
AMEX Gold statement was paid. **It is a return of an advance, not new surplus, and it creates no headroom
for any other goal.** It transitions to `SETTLED` only under AU-8's six-surface verification.

---

## 3. Consumption-row lifecycle rules (binding — recorded exactly as frozen)

1. **Tonight:** record the three confirmed charges (NCL $489.86 · Alaska Fishing Licenses $30.00 ·
   AMC Seattle $87.24 = **$607.10**) as **provisional / observed** consumption, itemised per charge so
   any later change is attributable.
2. **The row must not be identified as a final closed-statement obligation, and must not be marked
   `settled`, until the 2026-07-24 statement closes and the final transaction set is verified.**
3. **AU-3 carries the verification** (execution-package sequence step 9): confirm the Alaska subset on
   the closed statement, then transition the row **`provisional → settled`**, stamping the verification
   date.
4. **If additional Alaska charges appear before close:** amend under the ledger's identity and amendment
   rules — keep `ALASKA-STMT-2026-07-24` as the origin identity and add the new charge as an itemised
   line with its own date. **Never silently overwrite a settled row.**
5. **If the closed statement excludes or adjusts one of the three charges:** preserve the audit trail —
   record an explicit correction line (original amount, corrected amount, reason, date). The original
   line is never deleted or edited in place.
6. **Nothing downstream may treat row 2 as authoritative while it is provisional.**

---

## 4. Operating controls (all six — binding)

1. **Never reduce the `alaska` snapshot.** Funded is monotonic and must not fall because money was spent.
   *(Mechanically reinforced: the closeout confirmation view prefills each goal at its prior snapshot —
   the monotonic floor, never an observed balance — and the wrapper rejects a decrease server-side.)*
2. **Task completion means confirmed settlement.** A financial task is checked only once the bank shows
   the movement; no reconciliation is recorded between "marked complete" and "settled."
3. **Any material off-model outflow gets a `cash_commitments` row before it is scheduled.** This is the
   existing, proven reserve mechanism and the interim substitute for first-class pending-event
   representation.
4. **Capacity is non-authoritative while any known material event is unconfirmed** — in amount, in week
   placement, or in settlement state.
5. **Alaska draw sizing rule.** Any future Alaska draw or release executes at the **authoritative Custody
   balance computed at the moment of execution**:
   `Custody = Funded − Σ(settled releases) + Σ(settled reversals/refunds credited back)`,
   bounded by `min(Custody, outstanding Alaska obligation at that date)`, accounting for every statement
   reimbursement not yet released, subsequent Alaska spending, refunds/reversals, and any terminal
   residual disposition. **No future amount is fixed in advance** — it is computed at execution and
   recorded here.
6. **The accepted variance for the Cal Wk 37 blocked draw is in force** (§5), with expiry tied to 5G-1B.

---

## 5. Accepted variance — Cal Wk 37 (model week 15) Alaska draw

**Statement.** From the moment the $770.95 release settles, the modeled **$7,000 Truist Savings → Truist
Checking** Alaska draw at **model week 15 / Cal Wk 37** will render **BLOCKED**, because its `sav >= 7,000`
guard will no longer be met. The draw amount is **hardcoded in the model** (`mvS(7000,'chk')`); only its
label is overridable, so there is no configuration workaround.

**This is the model telling the truth, not a defect.** The savings really will be short — because
$770.95 of it arrived in checking early. What is missing is the *explanation*, not the arithmetic.

**Consequences accepted:**
- The Cal Wk 37 row renders as a blocked draw with a savings-insufficiency reason.
- The real draw must be executed **manually at the then-current Custody figure** (operating control 5),
  never at the hardcoded $7,000 and never at a figure fixed today.
- From Cal Wk 37 onward the modeled projection **understates checking** by up to the unexecuted draw
  amount, because the model does not know the manual draw occurred.

**Expiry:** this variance retires when **5G-1B**'s release lifecycle ships and dependent draws are sized
from **Custody** rather than a hardcoded constant.

**Required operator action:** a Week-15 pre-check note is carried on the operator continuity card so this
is not rediscovered in September.

---

## 6. Position totals — T-1 … T-5

**These five quantities are stated separately and must never be merged.**

| # | quantity | amount | status |
|---|---|---|---|
| **T-1** | **Settled prior-cycle consumption** | **$770.95** | **SETTLED** |
| **T-2** | **Provisional current-cycle consumption** | **$607.10** | **PROVISIONAL — NOT AUTHORITATIVE** |
| **T-3** | **Settled releases** | **$0.00** | **SETTLED** *(becomes $770.95 after AU-8)* |
| **T-4** | **Custody** = Funded − T-3 | **$7,000.00** | **AUTHORITATIVE** *(becomes $6,229.05 after AU-8)* |
| **T-5** | **Provisional Spendable** = Funded − (T-1 + T-2) | **$5,621.95** | **PROVISIONAL — NOT AUTHORITATIVE** |

**Only T-4 (Custody) is authoritative in this record**, because it depends solely on *settled* releases.

- **T-2 is provisional** and stays provisional until AU-3 verifies the closed statement.
- **T-5 is provisional** and **must not be presented as final authoritative goal capacity.**
- Draw sizing that uses **Custody** may proceed under operating control 5. Draw sizing that uses
  **Spendable** must wait for T-2 to settle.

**Conservation identity (for the record):**
`Funded 7,000.00 − Σ settled releases 0.00 = Custody 7,000.00` (authoritative) ·
`Σ consumption 1,378.05 = 770.95 settled + 607.10 provisional` ·
`Provisional Spendable 5,621.95` (not authoritative).

**Custody-to-cash reconciliation** is recorded in the local execution package (outside this repository)
per the balance-free policy; the residual between Custody and the holding account is accumulated
interest. **No account balance is stated here.**

---

## 7. Scope and non-actions

This record makes **no** production-data change, moves **no** money, and modifies **no** code, schema, or
model input. Specifically **not done here**:

- the $770.95 release itself (**AU-8**, separately authorized, subject to its six-check duplicate guard);
- any `goal_funding_snapshots` write — the `alaska` snapshot is unchanged and must stay unchanged;
- the week-7 reconciliation (**AU-9**, Saturday 2026-07-25 or later);
- the `docs/decision-log.md` governance row and the remaining canonical documentation homes (**AU-7**);
- any code change (**AU-11**, deferred behind DR-1).

**Standing hold, unchanged:** no goal transfer of any kind — including Wendy IRA — until authoritative
capacity is recomputed after AU-9 → AU-10.

---

## 8. Cross-references

- Frozen execution package: Step 6B Revision 2.1 (local execution package; canonical repo home assigned
  under AU-7).
- Goal-disbursement lifecycle ownership: canonical roadmap **§4** (5G-1B reframing), item 1
  (release semantics / *"payout does not reset progress"*), item 2 (write surface — L3 ledger branch),
  item 6 (corrections by reversing event, never editing history).
- Progress-plane identity gap: `docs/roadmap/amendment-2026-07-15-progress-plane-transfer-identity.md`
  (`holding_events` covers RCCL/DCL only and **excludes** the eligible nine).
- Structured custom-task metadata: `docs/tx-1-candidate.md` §TX-1.2.
- Post-BKX stabilization sequence: `docs/phase-5g-1d-post-bkx-stabilization-2026-07-19.md`.
