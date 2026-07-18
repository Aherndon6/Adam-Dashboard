# Phase 5G-1D — Step-8 reconciliation discrepancy: activation HARD STOP (2026-07-18)

**Status: 🛑 ACTIVATION HARD STOP — docs-only record. No code/SQL/migration/production-data/Week-28 change.
Reconciliation was CANCELED without save. Awaiting Fable + owner disposition.** Companions: operator package
§14.2/§14.3/§14.4 (@ `07739bc`); option-C operator script §D step 8; decision-log 2026-07-18.

## 1. Incident note (code-grounded)

During Option-C supervised execution, the Week-6 reconciliation was opened (Step 7) and observed:
- **Phase 1:** no prior unresolved commitments.
- **Phase 2:** a single candidate — **"Commission tax reserve (Vio Bank) — $843.51 (due 2026-07-12)"**.
- **No AMEX Gold protected-obligation prompt.**

This **contradicts** the committed operator package (`07739bc`), whose §14.2 "Required closeout entry",
§14.4 amended step-8, and option-C script step 8 direct the operator to **confirm the AMEX Gold commitment
via the standard Phase-2 path** and state **"No separate $425.68 commitment"** — while making **no mention**
of an $843.51 tax-transfer commitment.

**Root cause A — AMEX Gold has `eid = null`, so Phase 2 filters it out.**
`getPhase2WDCandidates` (index.html:1897–1905) surfaces a candidate only if
`ev.eid && ev.rod==='protected_required' && !existing[ev.eid]` (filter at :1903). `tagProtectedWDEvent`
(:1816–1834) derives the eid **from a due date parsed out of the event *label***
(`_wdExtractDueMD(ev.l)`, :1820) — `eid: dueDateStr ? buildExpectedItemId(…) : null` (:1827). The persisted
Week-28 AMEX Gold label is **"AMEX Gold Payment Due"** (confirmed in the Step-3 drawer), which contains
**neither** a `due M/D` **nor** a `(M/D` pattern, so `_wdExtractDueMD` returns null → `dueDateStr = null` →
**`eid = null`** → the AMEX Gold event is excluded from Phase-2 candidates. The structured date field
(`ev.d = "Sat Jul 18"`) is **not** consulted for the eid. *(The original hardcoded label
`"AMEX Gold ~$5,500 due 7/17 (first statement)"` did carry a parseable due date; a prior operator relabel
dropped it.)*

**Root cause B — the $843.51 tax-transfer candidate is synthetic and expected.**
`getTaggedWD` (:1842–1858) appends a **synthetic tax-transfer event to any week with `ct > 0`**. Week 28
has `ct = 843.51`, so the appended event is: `a = −843.51`, `eid = buildExpectedItemId(…, 'tax_transfer_vio',
weekStartDate)` (:1851), `cc:'tax_transfer'`, `rod:'protected_required'`, `displayLabel:'Commission tax
reserve (Vio Bank)'`, `due_date =` week start `2026-07-12` (:1856–1857). It always receives an eid (week-start
proxy) and therefore always surfaces. This matches the live prompt exactly (amount = full `ct` = $843.51).

**Conflict with operator package `07739bc`:** the package's Phase-2 plan is **not executable as written** —
AMEX Gold does not appear, and the $843.51 tax-transfer commitment (undocumented) does. The $843.51 (full
`ct`) also collides with the executed `$425.68` / deferred `$417.83` split and the recorded `$52.51`
re-split artifact (§14.4): reserving the full `$843.51` in Week 28 double-counts against the already-executed
`$425.68`. **Additional constraint:** restoring a parseable AMEX label would require a Week-28 Edit-Week save,
which **§14.4(7) has CLOSED for the sitting** — so the documented path cannot be made to work without
violating an adopted constraint.

**Reconciliation canceled without save.** No commitment was created; no `weekly_reconciliations` row or
`goal_funding_snapshots` were written; no wrapper was submitted. **Week 28 remains OPEN.** Executed
`commission_tax = 425.68` @ `2026-07-18 03:20:38.457+00` and `goal_adam_ira = 61.06` are unchanged; Baseline
A/B (`4/4·2/2·0/0·1/1·5/5`; `15/14/1`) unchanged.

## 2. Candidate correction approaches (exact functions — NOT implemented; for Fable/owner)

- **C-1 — Source the eid due-date from structured event data.** In `tagProtectedWDEvent` (:1816–1834),
  prefer the structured event date (`ev.d`) when present, falling back to `_wdExtractDueMD(ev.l)`; feed it
  through `_wdDueDateStr`/`buildExpectedItemId` (:1808/:1811). Gives AMEX Gold a stable eid regardless of
  label text. (Also review `_wdExtractDueMD` semantics.)
- **C-2 — Deterministic eid for protected events without a parseable due date.** In `getPhase2WDCandidates`
  (:1897–1905) / `buildExpectedItemId` (:1811), synthesize the eid from `normalized_payee + model_week +
  structured due date` so a bare label cannot null the eid. (Ensure it matches the `cash_commitments.
  expected_item_id` UNIQUE contract.)
- **C-3 — Base the synthetic tax-transfer commitment on the obligation NET of executed legs.** In
  `getTaggedWD` (:1846–1858) the synthetic amount is `−ct` (full `843.51`); a correction (B1 scope, §14.4(6))
  would compute it as `total obligation − Σ completed executed commission-tax legs` (`843.51 − 425.68 =
  417.83`) so no full-`$843.51` duplicate reservation is created and `$365.32` is never reservable/executable.
- **C-4 — Data/label normalization (post-sitting).** Restore a parseable AMEX Gold label — **barred now** by
  §14.4(7); would be a separate reviewed data correction.
- **C-5 — Documentation reconciliation.** Amend operator package §14.2/§14.4/step-8 to the *actual*
  implementation (whichever code path Fable selects), including how the AMEX `$5,666.01` commitment is
  created given it does not surface.

## 3. Proposed post-fix regression matrix (assertions; to be authored with the fix)

| # | Case | Expected assertion | Primary surface |
|---|---|---|---|
| R-1 | AMEX label WITHOUT an embedded due date ("AMEX Gold Payment Due") | AMEX Gold still receives an `eid` and **surfaces** in Phase 2 | `tagProtectedWDEvent` / `getPhase2WDCandidates` |
| R-2 | Due date sourced from **structured event data** (`ev.d`) | `eid` derived from `ev.d` when the label lacks a date; matches the UNIQUE eid contract | `tagProtectedWDEvent` / `buildExpectedItemId` |
| R-3 | Completed commission-tax anchoring | Commission-tax obligation anchors on `completed_amount = 425.68` (never `ct = 843.51`) | commission-tax commitment / B1 |
| R-4 | Carry after B1 correction | Displayed carry = `total − Σ executed = 843.51 − 425.68 = 417.83` | B1 carry logic |
| R-5 | `$365.32` projection artifact | **No** `$365.32` executable task or reservable commitment is ever produced | resolver / commitment builder |
| R-6 | No duplicate full-obligation commitment | **No** full `$843.51` tax-transfer commitment when `$425.68` is already executed (no double-reserve) | `getTaggedWD` synthetic (:1846–1858) |
| R-7 | Durable AMEX commitment | AMEX Gold commitment created at **`$5,666.01`** (payee AMEX Gold, `credit_card_payment`, `protected_required`, `truist_checking`, `affects_deployable_cash=true`) | Phase-2 commitment path |

## 4. Disposition — RESOLVED by Fable final Phase-2 disposition (2026-07-18; owner-authorized)

The discrepancy is dispositioned as the **binding revised Gate-3 sequence 7R–11R** in **operator package
§14.5**, which **supersedes** §14.2 "Required closeout entry" and Option-C script step 8. In summary:
- **Synthetic `$843.51` tax candidate (`2026mw6_tax_transfer_vio_2026_07_12`): LEAVE UNANSWERED** — no row
  persisted, saving not blocked; never persisted at `$843.51`, changed to `$417.83`, split, or represented
  as a commitment; applies to every reconciliation re-entry until the B1-class correction ships.
- **AMEX commitment: create via Phase 3 manual reconciliation** — label `AMEX Gold Payment Due 7/18
  (conf W3870)`, `$5,666.01`, response `paid_initiated`/`bank_pending`, reflected-in-balance **No**;
  persisted `commitment_source=manual_reconciliation`, `expected_item_id` like `manual_%`,
  `amount_cents=566601`, `required_or_discretionary=protected_required`, `affects_deployable_cash=true`,
  `origin_model_week=6`, `source_account=truist_checking`, `commitment_class=other_transfer`,
  `due_date=null`; **no tax-transfer commitment.**
- **B1 backlog additions:** protected-event eid must derive from **structured event date, not label
  parsing**; the synthetic tax candidate must compute **total obligation − completed executed legs**.

**No change to application code, SQL, migrations, production data, or Week-28 state.** Reconciliation resumes
under §14.5 (7R–11R) on owner authorization. Gate 3 HARD-STOPPED pending that authorization.
