# B1-W7 — Week-7 durable-origin amount-authority hotfix (2026-07-19)

**Status:** implemented + locally verified on `claude/b1-week7-durable-amount-hotfix` (branched from the
deployed `191cda5`). **NOT merged, NOT pushed, NOT deployed. The commission-tax execution hold remains
absolute until this fix is reviewed, deployed, and verified live.** Design authority: Fable final
determination 2026-07-19 (**APPROVE WITH REQUIRED CHANGES** — era partition; exact-match guard; no
runtime reconciliation reads) atop the Fable Week-7 amount-authority review (hybrid authority model).
Governing operator amounts unchanged: **$417.83** (Deep-South remainder) / future **$700.90** / **never
$365.32**. Balance-free except committed-precedent amounts.

## 1. Defect corrected

The deployed B1 schedule allocated open-week actionable amounts from the **label-parsed runModel
schedule** (`cumModel − cumReserved`), demoting the durable ct obligations to an aggregate cap. After
the Week-6 closeout re-anchored the model (wk6 model = 425.68 = executed), the schedule detected no
carry and surfaced the raw model **$365.32** at Week 7. The durable-correct amount is
`843.51 − 425.68 = $417.83`. Root cause class: modeled amounts in the authority path.

## 2. Era-partitioned durable-origin ledger (implemented)

Exactly **one evidence source per origin**; the runtime **never reads the weekly-reconciliation
reserve table**:

- **Pre-anchor origins (`origin_week ≤ 5`)** — closed ONLY by the reviewed, cycle-scoped
  **legacy-settlement attestation** (`CT_ATTESTATION`, version **2026-ATT-1**): wk2 obligation
  **993.29** = task leg 375.68 + reconciled taskless carry **617.61** (wk2→3 reserve delta; exact
  identity `993.29 − 375.68 = 617.61`; wk1→2 delta 897.04 = 375.68 + base tax 521.36 cross-check);
  wk4 obligation **435.63** settled exactly (wk4→5 delta). The **wk3→4 $1.94** is recorded as an
  **unattributed residue** (probable interest/adjustment pending statement confirmation) — assigned
  to no origin; no closure depends on it. Any pre-anchor origin not exactly closed → **fail closed**.
  Attestation evidence was verified at review time from read-only reconciliation deltas; it is pinned
  as reviewed constants (the same pattern as the MD5/expected-matrix pins).
- **Post-anchor origins (`origin_week ≥ 6`)** — governed ONLY by structured completed `commission_tax`
  `weekly_tasks` legs (B1 sole completion authority makes them the complete durable record),
  FIFO-attributed oldest-open-first; pre-anchor legs are **subsumed** by the attestation and never
  separately settlement-counted → double counting is **structurally impossible**.

**Invariants (tested):** pre-anchor `obligation = attested settlement` (remaining exactly 0);
post-anchor `obligation = Σ legs + authorized remaining`; ledger
`Σ per-origin authorized remaining = Σ matured obligations − Σ disjoint settlement` (violation → fail
closed). **Current expected ledger:** wk2 → 0, wk4 → 0, wk6 → 843.51 − 425.68 = **417.83**; matured
aggregate remaining **417.83** (supersedes the deployed 1,035.44 cap).

## 3. Function-level changes (`index.html` only; all inside the B1 engine/wiring)

- **NEW `CT_ATTESTATION` + `_ctAttFp`** — the attestation record + fingerprint (version in every
  candidate context).
- **`computeCommissionTaxPool`** — extended into the per-origin ledger: attestation self-checks
  (mismatch / missing entry / structure → fail closed), era partition, FIFO leg attribution with the
  ±$1.00 over-credit tolerance (within-tolerance overage never counts as settlement), agreement
  invariant, `origins[]` output, `remaining` = Σ per-origin authorized remaining.
- **`computeCommissionTaxSchedule`** — cumulative-model allocation **replaced** by per-origin slice
  emission: one independent row per matured actionable origin at its earliest open schedule week
  ≥ origin_week (future origins never early); completed weeks stay immutable durable history; model
  amounts attach as display context only. NEW `_ctWeekSlices`; `_ctWeekRow` kept as first-row compat.
- **`_ctWriteGuard`** — partial-tolerant rule **replaced by exact match**: submitted ==
  slice-authorized ±$0.01, slice selected by fresh `candidate_context`; fresh **365.32 → refused
  `amount_mismatch_authorized`** (by amount, not staleness); partials refused (floor-constrained
  partial execution is **not writable through the app** — supervised owner decision + separately
  reviewed design only); overwrite/fail-closed refusals retained.
- **Synthetic reconciliation candidate** — amount re-based to the origin's **authorized remaining**
  (never the raw ct); suppressed at remaining ≤ tol; **eid unchanged**.
- **Weekly render** — authorized amount owns display + write context; model-projection note
  ("Authorized $X … model projects $Y: known projection skew, deferred to Calc-Core"); additional
  matured origins render as **separate slices** with independent contexts.
- **Frozen surfaces untouched:** `runModel`, `computeGoalTransferNetting`, `resolveWeekTransfers`
  byte-identical (verified below). No schema, no migrations, no production writes.

## 4. Known/accepted notes

- Overview/History open-action labels still display model-context amounts (display-only summary
  surfaces; the actionable weekly rows + write path carry the authorized amounts). Cosmetic
  follow-up candidate.
- `runModel`'s internal cash projection remains surplus-derived (frozen): projected balances may skew
  by the executed-vs-surplus delta (**$52.51** here) until the next weekly anchor; deferred to
  Calc-Core per the standing decision.
- The pre-execution rendering of an un-executed obligation now shows the **full authorized remaining**
  (e.g., 843.51), not the model floor-split leg — the recorded §7 consequence of exact-match authority.

## 5. Verification (local)

- Static regression: **1585 / 0** (revised + new B1 suites: POOL/ATT/AGG/ERA/MERGE/LBL/B-guard/SCHED).
- Full `node e2e.js`: recorded in the hotfix commit report (IDENT-E1 revised to authorized 843.51;
  IDENT-E2 revised to the live-equivalent durable-leg fixture → authorized 417.83).
- Byte-identity: `runModel` / `computeGoalTransferNetting` / `resolveWeekTransfers` extracted and
  diffed vs `191cda5` — identical. `BUILD_TS` unchanged (`2026-07-18T22:06:29`).
