# B1 — Commission-Tax Obligation Netting — Design Record (2026-07-18)

**Status: 📐 AUTHORITATIVE DESIGN — ADOPTED from Fable review (verdict REVISE → PROCEED). DOCS-ONLY.
NOT implemented.** This is the single controlling home for the B1 commission-tax obligation-netting
remediation; the canonical roadmap, decision log, phase status, and operator package carry pointers +
sequencing only (no duplicated controlling requirements). Supersedes the scoping sketch in operator
package **§14.6 D5** (which now points here).

**Naming disambiguation (read first).** "B1" here = **the commission-tax obligation-netting remediation**
(the §14.6 D5 item). It is NOT: the holding-lifecycle phase **5G-1B**; the `4ce6aff` identity findings
B1–B4; or the operator-package activation step "B1 (adjunct preflight)". Where ambiguity is possible this
doc writes **"B1 (commission-tax netting)"**.

---

## 0. Verified facts (evidence + deterministic harness — the basis, not the design)

*Source: `docs/phase-audit-2026-goal-funding-waterfall-integrity-2026-07-18.md`; evidence artifact
`audit-evidence-2026-07-18.txt` (SHA-256 `bda0224b…`); read-only harness against `index.html` blob
`cde5ed80…`.*

- Week-6 durable tax semantics are **three distinct correct values**: total-obligation input
  `model_week_overrides.ct = 843.51`; executed `weekly_tasks.commission_tax = 425.68`;
  `weekly_reconciliations.tax = 1952.22` (**account/reserve STATE balance — never a transfer**).
- `843.51 = 40% × $2,108.78` (Deep South). `417.83, 365.32, 478.19, 52.51, 700.90` are **application-
  derived (not persisted)**.
- **Harness independently reproduced** (real `runModel`, `mv()` sweep = `min(ct, chk−floor)`): with AMEX
  `5666.01` → wk6 sweep **478.19** / wk7 carry **365.32**; with AMEX `5718.52` → **425.68 / 417.83**;
  **carry Δ = 52.51, constant across every partial-regime chk** ⇒ the future tax remainder is
  **cash-dependent** (defect). Correct remainder = `843.51 − 425.68 = 417.83`, not `365.32`.
- **D waterfall (faithful projection):** adam_ira `7500` (durable, correct); wendy_ira reaches `7500`
  before bailey_529 receives allocation; bailey_529 reaches **exactly `3500`** (no overfund); bailey
  durable = `0`, its "100%" is **projected year-end** (`fundedYE`, index.html:5559), a genuine 2026
  completion. **Expected behavior, not a defect.**

## 1. Architectural decision (CONCLUSION)

B1 is approved as a **narrowly scoped adapter / candidate-render / Edit-Week-replacement / write-guard**
remediation. **B1 MUST NOT:** modify `runModel`; modify the frozen calculation core; add schema or
migrations; create a durable obligation-lifecycle object; create tax `cash_commitments`; merge
commission-tax logic into goal-transfer netting; alter `weekly_reconciliations.tax` semantics; solve the
missing `model_year`/re-keying problem; implement reversal primitives. Those remain deferred (§14).

## 2. One shared computation (REQUIREMENT)

Define **one pure** commission-tax obligation-netting function, consumed by **all four** B1 surfaces.
Per obligation it returns: `total_obligation`, `valid_executed_legs`, `executed_total`,
`remaining_obligation`, `control_status`, `warning_review_state`.

```
remaining = max(0, total_obligation − sum(valid_executed_legs))
```

The four consumers — (1) weekly-task rendering/normalization; (2) synthetic reconciliation-candidate
generation; (3) Edit-Week replacement/backfill arithmetic; (4) completion write-guard — **must call this
one function.** There must be **no second implementation of "remaining."**

## 3. Obligation identity (REQUIREMENT + documented LIMITATION)

- **Obligation identity:** `obligation_type = commission_tax`; active cycle / model year from
  `PLAN_YEAR` context; **origin model week** from the applicable `ct` override.
- **Executed-leg class identity:** `action_key = commission_tax`.
- **Executed-leg durable-row identity:** `(week_num, task_idx)`; `completed_amount` is the executed value.
- **Display labels never participate in identity.** Source/destination account and commission source are
  **validation attributes, not identity**.
- **LIMITATION (documented, not solved):** `weekly_tasks` lacks a durable obligation-origin identity and
  lacks `model_year`. **B1 scopes to the active cycle only.** Durable resolution belongs to the existing
  **P2-2 re-keying** and **5G-1B** lifecycle work (§14).

## 4. Required controls (CONTROL — fail closed)

**Block the actionable candidate and fail closed** for: ambiguous obligation identity; duplicate
executed-leg identity; missing/invalid obligation input; unparseable amounts; un-decomposable merged
obligations; label-derived identity; over-credit beyond tolerance; **any inability to determine
`remaining` deterministically.** **Never guess, position-match, or label-match.**

Over-credit tolerance (existing convention):
- **within $1.00:** `remaining = 0`; no actionable candidate; informational note.
- **beyond $1.00:** block; visible **review-required** warning; no candidate; **no automatic correction
  or refund.**

## 5. Multiple obligations (REQUIREMENT)

Multiple live commission-tax obligations remain **separate by origin**. Known example (forward-looking):
prior-origin remaining **`417.83`** + new-origin **`700.90`** → **two separate candidates**. If a
generated/model surface merges obligations and B1 cannot decompose by origin, **fail closed → owner
review**. **Do not infer allocation between obligations.**

*Clarification (verified): today only the `417.83` obligation exists (one `ct` override at wk6). The
`700.90` (Extra BK Pay tax) has no `ct` override yet — it becomes a separate origin only when the Extra
BK Pay is entered in its posting week (Week 29 per §14.3 PATH-B\*). B1's multi-obligation handling is the
control for that entry.*

## 6. Candidate presentation (REQUIREMENT)

For a partial obligation, display all three distinctly and make **only `remaining` executable**:

```
Obligation: 843.51    Executed: 425.68    Remaining: 417.83  ← actionable
```

Completed legs remain **read-only execution history**. `weekly_reconciliations.tax` remains an
account/reserve state balance and **must never be interpreted or displayed as a transfer**.

## 7. Write-time invariant (REQUIREMENT + CONTROL)

At commission-tax completion time: **recompute `remaining` from durable truth** (do not trust the rendered
amount or cached state); **refuse** a write exceeding `remaining + tolerance`; **refuse** ambiguous or
duplicate identity; **refuse** missing obligation input; **persist `completed_amount` as the actual
executed amount**; **never PATCH an existing non-null `completed_amount`.**
- A valid completion of `417.83` persists **exactly `417.83`**.
- An attempted completion of `365.32` for the current obligation is **refused** (≠ authoritative
  `remaining`).

## 8. Edit-Week behavior (REQUIREMENT — retires §2d)

**Remove the completed-row delta-PATCH behavior from B1 scope.** After a taxable-input edit:

```
new_remaining = new_total_obligation − sum(existing durable executed legs)
```

Existing `completed_amount` values remain **unchanged**. This is the **required condition for retiring
the operator package §2d prohibited-sequence restriction** (and the never-answer control, §10).

## 9. Projection-skew disclosure (DEFERRED-architecture disclosure)

- `runModel`'s internal cash projection **remains surplus-derived**; **B1 does not alter that frozen
  calculation.**
- Projected future cash balances **may remain skewed** by the executed-vs-surplus delta; **in this
  incident the bound is `52.51`.**
- The skew **self-heals at the next weekly reconciliation anchor.**
- **Actionable tax obligations and writes are nevertheless correct under B1** (they read durable truth,
  §2/§7).
- The internal projection issue is **deferred to Calc-Core Extraction** (§14).

## 10. Existing subsystem boundaries (REQUIREMENT)

- The synthetic candidate **`eid` remains stable**; **only its amount basis changes** (total → remaining).
- **No tax `cash_commitment` records are created.**
- `commission_tax` **remains excluded from `computeGoalTransferNetting`.** B1 may **share fail-closed
  vocabulary and tolerance conventions** with goal netting but **not its obligation-specific code path.**
- `remaining` must be **stable regardless of the week** in which the model surfaces the carry.
- The **never-answer control** (§14.5(A): leave the synthetic tax candidate unanswered) **remains active
  until the corrected build is deployed AND verified.**

## 11. Minimum regression matrix (REQUIREMENT — implementation acceptance criteria)

**Core arithmetic** — total 843.51 / executed 425.68 → **417.83**; AMEX 5718.52 **and** 5666.01 both →
**417.83**; fully executed → **no candidate**; two legit partial legs → total − Σlegs; remaining never
negative.
**Identity & failure** — duplicate executed-leg identity → fail closed; missing obligation input → fail
closed; ambiguous identity → fail closed; unparseable amount → fail closed; label changes do **not**
change identity/netting; candidate `eid` stable; recomputing twice → identical output.
**Multiple obligations** — 417.83 and 700.90 as separate origin-based candidates; merged/un-decomposable →
fail closed; carry-slide to a later surfaced week does **not** change `remaining`.
**Write guard** — completion at 365.32 refused; completion at 417.83 persists exactly; completion >
remaining + tolerance refused; `completed_amount` not overwritten.
**Edit-Week** — post-completion taxable increase leaves executed 425.68 unchanged; new obligation =
updated total − 425.68; existing completed rows never delta-patched.
**Semantic boundaries** — `weekly_reconciliations.tax` never treated as a transfer; no tax cash commitment
created; `remaining = 0` suppresses candidates at **both** task and reconciliation surfaces.

## 12. D waterfall characterization + presentation (REQUIREMENT)

**Named characterization tests (D):** higher-priority Wendy IRA reaches target **before** Bailey 529
receives allocation; same-week cascading begins **only after** Wendy reaches target; Wendy never exceeds
7500; Bailey never exceeds 3500; the Adam IRA correction may **unblock** downstream funding but **cannot
reorder priorities**; current durable funding and projected year-end funding come from **distinct
sources** (`getGoalFunded` vs final-week `goalSaved`).

**D presentation requirement (separate, small):** every surface rendering goal percentages must
distinguish **Funded to date** vs **Projected by year-end**. For Bailey: funded-to-date = `0`;
projected-by-year-end = `3500 / 100%`. **No standalone "100%" that can read as current durable funding.**
- **Recommendation (recorded, not implemented):** track the D-presentation as an **immediately adjacent
  display item (D-DISP)** in the Funding-Plan render (index.html:5546–5561), **not** folded into B1's
  commission-tax code path (preserves B1's narrow scope + testability). It **may co-deploy** with B1
  (same `BUILD_TS` stamp) but is a separate change with its own test. *(It refines the existing 5G-1C-1
  "Projected YE" labels rather than adding the concept from scratch.)*

## 13. Timing and freeze gate (OPERATIONAL)

- Target implementation completion: **July 23**; preferred landing **≤ July 25**; **hard pre-freeze
  cutoff July 28**; **freeze July 29 – August 10**. Operational need: **before the Week-7 / Cal Wk 29
  closeout.**
- **If B1 cannot safely complete + review before the cutoff:** do **not** land during the freeze; execute
  the supervised **`417.83`** transfer under existing operator controls; **retain the never-answer rule
  and §2d**; resume implementation **August 11+**. **Do not assume a freeze exception is authorized.**

## 14. Deferred architecture (pointers — not solved by B1)

- **Durable obligation-origin identity + `model_year` + obligation lifecycle** → **5G-1B** (holding →
  allocation → payout lifecycle / L3 event ledger) and **P2-2 re-keying** (canonical roadmap §3.0 / §14
  AF-2; phase-status 5G-1D row).
- **runModel surplus-derived projection skew** → **Calc-Core Extraction** (canonical roadmap §3.0 #10,
  late Nov 2026; runModel frozen until then).
- **Reversal primitives** → not in 2026 scope.

## 15. Legend

**Verified fact** = evidence/harness-proven (§0). **Architectural conclusion** = the scope decision (§1).
**Implementation requirement** = §§2–8, 10–12 (binding acceptance criteria). **Operational control** =
§§4, 7, 13 fail-closed/never-answer/freeze rules in force now. **Deferred architecture** = §§9, 14.
