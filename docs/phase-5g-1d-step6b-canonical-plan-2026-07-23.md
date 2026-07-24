# Step 6B — Canonical Plan and Execution Package (balance-free record of Revision 2.1)

**Date:** 2026-07-23 · **Status:** **FROZEN** 2026-07-23. Governing document for post-BKX stabilization
execution. No further architectural or planning revision unless execution exposes a genuine defect.
**Type:** plan of record. Documentation only — no code, schema, SQL, production-data, or financial change.

> **BALANCE-FREE RECORD.** This is the **plan of record**. The **valued operator copy** — the one to
> execute from, carrying every balance, worked capacity figure, and probe output — lives outside this
> repository at
> `~/Documents/Herndon Financial OS/Execution Packages/Post-BKX Stabilization/valued-evidence/`
> → `EP-02-step6b-execution-package-rev2.1-VALUED.md`. **Section numbering matches**, so any reference
> below resolves directly. Earlier revisions are retained as `EP-03` (Rev 1) and `EP-04` (Rev 2).

---

## 1. Architecture adopted

### 1.1 Domain model — four quantities, three stored concepts

| quantity | stored or derived | home |
|---|---|---|
| **Funded** | stored — **already exists** | `goal_funding_snapshots.funded_amount`; monotonic |
| **Consumed** | stored as **events** | L3 ledger (interim: the operational Goal Ledger) |
| **Released** | **derived** — aggregate over release events | L3 ledger |
| **Spendable** = Funded − Consumed | derived, never stored | computed |
| **Custody** = Funded − Released | derived, never stored | computed |

**One new durable concept — the goal-scoped domain event — carrying two event types.** Not two new
balance columns. `Released` as a stored field would drift from the events producing it; as an aggregate
it cannot.

**The monotonicity invariant is already canonical law:** roadmap §4 item 1 requires the 1B spec to treat
`funded_amount` as *cumulative progress* — *"payout does not reset progress."*

**Why the model matters in both directions:** it prevents the re-funding failure (reducing Funded makes
the waterfall re-fund an already-funded goal) **and** it fixes the dependent-draw failure, because a draw
sized from **Custody** simply fires at the right amount instead of blocking on a hardcoded constant.

### 1.2 Authority partition (binding — no second system of record)

| domain | authoritative owner | status |
|---|---|---|
| actual account transactions / spending | `transactions` (Register) | exists |
| Funded history (monotonic appropriations) | `goal_funding_snapshots` | exists |
| account positions at week close | `weekly_reconciliations` | exists |
| pending checking exposure (capacity reserve) | `cash_commitments` | exists — **specialized projection input, NOT a universal registry** |
| goal consumption · release · refunds · reversals | **L3 event ledger** | new — rides 5G-1B |
| external reimbursements (Jabian-class) | Register + `model_week_overrides`; **no goal linkage** | exists |
| cross-account custody | **derived** (Funded − Σ releases) | derived |
| Spendable · Spoken-For · Free-to-Use | **derived**; authority is 5G-3 | Q1 2027 |

Whether `cash_commitments` remains specialized, is generalized, or is subsumed into an append-only
domain-event architecture is **deferred to the 5G-1B spec** (roadmap §4 item 2 P0 write-surface decision).

**The temptation to guard against:** the Register covers 4 of 14 accounts. The obvious-but-wrong fix is
to let the Goal Ledger carry savings activity. The correct fix is Register coverage — or an explicit,
documented decision to accept position-level evidence for those accounts — never ledger scope creep.

### 1.3 One registry, two gates

Completeness and staleness must **fail independently**. A completeness-only gate passes the dominant
residual case — settled-but-unreconciled cash — and still ships an unsafe recommendation.

- **NON-AUTHORITATIVE** (banner + explicit acknowledgement; work continues): any known material event
  lacks a confirmed amount or week placement · any `cash_commitments` row is stale versus the Register ·
  the current week is unreconciled with un-itemised variance · any modeled card obligation inside the
  projection is known-wrong.
- **HARD REFUSAL:** projected checking below the operating floor at **any week in the remaining
  projection** after the proposed transfer.

**Full-horizon, not five weeks.** With the week-11 card obligation corrected, a floor breach appears at
week 13 — one week outside the existing `AMX_SWEEP_LOOKAHEAD_WEEKS = 5` window. A 5-week-scoped guard
reproduces the blind spot it is meant to close.

**Inherited constraint (TX-1.2 hard invariant 1):** structured event metadata must never convert a custom
task into a modeled cash event. The gate therefore **marks capacity non-authoritative — it never silently
adjusts the number.** And per roadmap §9's "one available cash number" rule, the gate **annotates** the
Cash Availability Engine's output; it never forks a second availability figure.

### 1.4 Goal-disbursement lifecycle

```
Funded (monotonic — NEVER decreases)
  ├─► consumption event   dated to the ECONOMIC event (statement close), not the transfer
  │     └─► Spendable = Funded − Σ consumption      ← what the waterfall compares to target
  └─► release event       dated to the CASH movement
        └─► Custody = Funded − Σ release            ← what must reconcile to holding-account cash
```

Corrections follow roadmap §4 item 6: **append a reversing event; never edit history.**

### 1.5 Event identity

One universal identity shape; per-type state machines. `origin_id` · `model_year` / funding cycle ·
`event_type` · `goal_id` · amount · direction · source account · destination account ·
`reverses_event_id`. Financial state machine: **`scheduled → initiated → settled`**, `reversed` terminal —
distinct from task `completed`, whose conflation is finding H-3. Write-boundary uniqueness on
`(origin_id, event_type, model_year)`. Conservation assertions promoted from audit to runtime.

### 1.6 Roadmap placement

| capability | owning phase |
|---|---|
| L3 event ledger (consumption + release) | **5G-1B**, branch (b) |
| **Release lifecycle generalized to release-bearing goals** | **5G-1B scope extension** — *the one genuinely new roadmap change* |
| Exactly-once identity conventions | Data-Extension & Identity Conventions (freeze window) |
| Structured custom-task metadata | TX-1.2 (P3b-1) |
| Server-authoritative write enforcement | D-11 |
| Capacity completeness + staleness gate | new slice on 1B |
| Spendable / Custody display | Account Composition Visibility Rider (§18) |
| Authoritative Spoken-For / Free-to-Use | 5G-3 |

**Why the 1B extension is required:** roadmap §4 scopes the release lifecycle to RCCL/DCL and explicitly
excludes the eligible nine. Alaska **is** one of the nine, so its release lifecycle has **no owning phase
today**. §4 item 3 already anticipates the distinction — it simply assumed the two sets were identical.

---

## 2. Authorization units

Twelve units, each with preconditions, exact action, expected outcome, verification, abort criteria,
rollback, and a recalculation flag. **Full runbook text: EP-02 §2.**

| AU | type | scope | gate |
|---|---|---|---|
| AU-1 | data | week-7 Jabian inflow correction | ready |
| AU-2 | data | week-7 Disney Visa confirm/correct | ready (conditional on the statement) |
| AU-3 | data | week-11 card obligation → **actual closed statement balance** | **blocked** until the cycle closes and the statement is displayed |
| AU-4 | data | activate the Costco Visa account | ready |
| AU-5 | data | durable Costco capture reminder (week 7) | ready — **one unit with AU-4** |
| AU-6 | docs | interim Alaska Goal Ledger + controls + accepted variance | **✔ COMPLETE 2026-07-23** |
| AU-7 | docs | canonical documentation homes + balance-free split | **✔ this document** |
| AU-8 | **financial** | Alaska release | ready — subject to the duplicate-execution guard |
| AU-9 | data | **week-7 reconciliation** | **blocked** until the week closes |
| AU-10 | data | resolve the stale card commitment | **same sitting as AU-9, after it succeeds** |
| AU-11 | code | full-horizon floor-safety guard | **deferred** behind DR-1 + an owner ruling |
| AU-12 | data | recategorize the goal-funding transfer (L-4) | ready |

### 2.1 AU-9 / AU-10 coupling — non-atomic

> **AU-9 and AU-10 are one indivisible authorization sequence executed in the same controlled sitting,
> but they are separate technical transactions and are not atomic.** AU-9 goes through the application
> closeout wrapper; AU-10 is a separate RPC call or manually executed SQL. **No database transaction
> spans both.**

**Before AU-9 begins:** the repair function's grant / callable status must be verified, or the supervised
SQL substitute authored and validated; and **the exact AU-10 statement must be written out and held
ready.** Authoring the repair after the one-way door has been passed is prohibited.

**If AU-9 succeeds and AU-10 fails** — an *interrupted authorization sequence*, not grounds to roll back
AU-9: do not undo the closeout; stop under the STOP/ABORT protocol; preserve evidence; **keep the stale
commitment in place** (conservative over-reservation is the failure-safe direction); mark capacity
NON-AUTHORITATIVE; maintain the transfer prohibition; execute only the pre-prepared repair; re-read both
objects; recalculate only after verification passes; resume from a newly documented checkpoint.

**Capacity does not become authoritative merely because AU-9 succeeded.**

### 2.2 AU-9 is a one-way door

`canDeleteRecon` requires a pre-anchor, snapshot-free week. Week 7 is post-anchor and will bear nine
snapshots on close. **There is no in-app undo**; correction requires the owner-only supervised path. A
fresh database dump and a pre-submit read-back of every balance and every funded value are hard
preconditions.

### 2.3 AU-8 duplicate-execution guard

Six checks (**D-1…D-6**) across the Register, the Goal Ledger, custom tasks, `weekly_tasks`, bank activity
including pending and scheduled transfers, and custody arithmetic — all must return CLEAR before the
transfer is initiated, with a recorded operator confirmation. **A suspected duplicate is never resolved
by transferring again**; a prior release executed but never recorded is a documentation defect, repaired
by recording it.

Post-transfer, six verifications (**V-1…V-6**) must prove **exactly one** reimbursement exists and is
consistently represented across bank, Register, Goal Ledger, task state, week placement, and the
goal-funding surfaces.

---

## 3. Failure-mode review

**Nineteen execution failure modes** enumerated with consequence, likelihood, existing control, and
recommended additional control (full table: EP-02 §3). The four that could produce an unsafe financial
outcome:

| FM | mode | control |
|---|---|---|
| **FM-1** | the commitment repair executed standalone or before the reconciliation | one indivisible sequence; refuse unless the closeout is verified complete |
| **FM-1b** | the reconciliation succeeds and the repair fails — the non-atomic gap | interrupted-sequence recovery; prerequisite and pre-authored statement required first |
| **FM-2** | wrong closeout value submitted through a one-way door | fresh dump + pre-submit read-back as hard preconditions |
| **FM-6** | double-count: the card obligation reserved *and* already inside the reconciled position | the repair is a required member of the sequence; until it completes capacity stays NON-AUTHORITATIVE — the double-count is disclosed, never silently applied |
| **FM-16** | no restore point before the irreversible step | dump is a precondition independent of DR-1 |

Also carried: concurrent-writer risk (the household-admin role can complete tasks and submit a closeout);
completion-precedes-settlement; forgotten capture reminders; stale browser sessions; and rollback attempts
after the one-way door.

---

## 4. Interim Alaska operating model

**Proceed manually.** Building a disbursement lifecycle to process a single event would be an
unauthorized architecture phase under roadmap §8, is gated behind an open DR-1, and would precede the 1B
spec that must govern it.

The binding interim controls, the consumption-row lifecycle rules, the provisional-versus-settled
boundary, the position totals, and the accepted variance are recorded in
**`docs/phase-5g-1d-alaska-interim-operating-decision-2026-07-23.md`** (AU-6), which is the governing
operating-decision record.

**Operational system of record:** the Google Sheet **“Herndon Financial OS — Goal Ledger”** is the interim
system of record for goal consumption, releases, custody, and amendments until the 5G-1B L3 domain event
ledger ships. It is a **migration source**, not a throwaway. Import-ready structure and instructions are
held in the execution package (`goal-ledger-import/`), outside this repository.

---

## 5. Execution calendar

| when | work |
|---|---|
| **Thursday 2026-07-23** | documentation first (AU-6 → AU-7); then data (AU-1, AU-2, AU-4+AU-5, AU-12); then the financial action (AU-8). Capacity computed afterwards as a **NON-AUTHORITATIVE** baseline. |
| **Friday 2026-07-24** — statement-close day | AU-3 **only once the closed statement is displayed** (no assumption about the hour); AU-3 addendum verifying the Alaska subset and settling the provisional consumption row; grant/callable verification; pre-author the repair statement; fresh dump. |
| **Saturday 2026-07-25 or later** | Register sweep; confirm no other writer; confirm the prerequisite is closed and the statement prepared; **AU-9 → AU-10**; authoritative capacity recalculation **after the repair verifies**; only then re-evaluate the Wendy IRA against the full-horizon floor test. |
| deferred | AU-11 after DR-1 · 1B spec extension · Identity Conventions · gate spec · TX-1.2 · D-11 · §18 rider · 5G-3 |

**DR-1 (due 2026-07-28) outranks everything above** and gates the entire post-stabilization roadmap.

---

## 6. Standing holds in force

1. **No goal transfer of any kind — including Wendy IRA — until authoritative capacity is recomputed
   after AU-9 → AU-10.** On the evidence to date it will not clear then either.
2. **Never reduce the `alaska` snapshot.**
3. **Task completion means confirmed settlement.**
4. **Any material off-model outflow gets a `cash_commitments` row before it is scheduled.**
5. **The STOP / ABORT protocol (EP-02 §2) overrides every instruction.** A failed or aborted unit never
   authorizes proceeding to a later one.

---

## 7. Balance-free allowlist (governing — applies to every repository document)

**Prohibited in repository documents — no exceptions:** reconciled or observed **account balances** for
any account; `weekly_reconciliations` field values (`chk`, `sav`, `amx`, `tax`, `lc`); cash-bridge
account figures; probe outputs that disclose an account position; `available_balance` /
`posted_current_balance` figures.

**Permitted (allowlisted):**

| class | examples |
|---|---|
| obligation amounts | commission-tax legs; pool totals; the BKX tax obligation |
| transfer amounts | goal sweeps; the Alaska release; reimbursements |
| goal targets and Funded values | `alaska` $7,000.00 · `adam_ira` / `wendy_ira` $7,500.00 · snapshot funded values |
| **Custody** (= Funded − Σ settled releases) | **a derived GOAL quantity, not an account balance — explicitly allowlisted** |
| **Spendable** (= Funded − Σ consumption) | derived goal quantity — allowlisted, but must carry its provisional/authoritative status |
| consumption amounts | per-statement and per-charge Alaska consumption |
| card **statement** amounts | a closed statement balance is a card obligation, not an account balance |
| model constants | the operating floor; `MIN_XFR`; hardcoded draw amounts appearing in code expressions |

> **Custody is deliberately allowlisted and deliberately distinct from the holding account's balance.**
> They differ by whatever has accrued in the account (interest) and by any movement not represented as a
> release. A reviewer must not read a Custody figure as a balance leak — and must not treat a Custody
> figure as a substitute for reconciling the account.

**Verification method** — a single keyword scan is **insufficient** and must not be relied on: matching
the bare word *balance* produces false positives on legitimate prose (*balance-free*, *statement
balance*, *balance-level evidence*). Required: (a) scan for prohibited labels and schema field names;
(b) proximity scan for currency values adjacent to an account identifier; (c) **manual inspection of
every match**; (d) classification against this allowlist. The expressions must first be demonstrated to
flag a known prohibited example and **not** flag a known permitted one. **Automated scanning assists the
review; it does not replace a manual read before commit.**

---

## 8. Two limits that persist

- **Every guard in this system is a *recording* guard.** None of them can stop money moving at the bank.
  The operator is the last control.
- **The Register covers 4 of 14 accounts.** Savings, reserve, and holding positions remain
  position-level rather than transaction-level until reconciliation.

---

## Cross-references

- Production evidence: `docs/phase-5g-1d-step6a-production-evidence-2026-07-23.md`
- Independent architecture review: `docs/phase-5g-1d-step6b-architecture-review-2026-07-23.md`
- Interim Alaska operating decision (AU-6): `docs/phase-5g-1d-alaska-interim-operating-decision-2026-07-23.md`
- Stabilization sequence: `docs/phase-5g-1d-post-bkx-stabilization-2026-07-19.md`
- 5G-1B reframing: `docs/roadmap/canonical-roadmap.md` §4 · D-11: §12.1 · WIP bright line: §8
- Progress-plane identity gap: `docs/roadmap/amendment-2026-07-15-progress-plane-transfer-identity.md`
- TX-1.2: `docs/tx-1-candidate.md`
- Valued operator copy: execution package `EP-02` (outside this repository)
- **Reserved path, not yet created:** `docs/phase-5g-1d-post-bkx-stabilization-closure-2026-07-<dd>.md`
  — the stabilization closure record, authored when Step 6 actually closes.
