# Step 8 — Baseline E: Independent Fable Micro-Confirmation Prompt

## DRAFT / NOT AUTHORIZED / NOT EXECUTABLE (rev-8)

Standalone prompt for an **independent Fable reviewer** (model `fable`, separate subagent) to run a **final
micro-confirmation** of the Baseline E design — and, at the later gate, the **built artifacts** — **before**
any execution, capacity calculation, or transfer decision. Fable reviews design and artifacts, never a
result — no capacity number exists.

Two invocation modes:
- **Mode 1 — rev-8 final micro-confirmation** (this document set only): confirm test 79 directly proves
  disposition G's accepting branch (+ fail-closed twin), the §17 A–H coverage map now points G to 79, test
  counts/references are consistent, and no regression was introduced.
- **Mode 2 — pre-freeze artifact review** (rev-8 + pure adapter + `baseline-E-calc.mjs` + tests + freeze-time
  snapshot + budget-rules extract + manifest schema + parity harness + the concrete RLS visibility-proof,
  `events_json` JSON-number canonicalization, §5c candidate-generation, and `confirmed_matches[]`
  implementations).

---

### Prompt to Fable

> You are an independent adversarial reviewer running a **final micro-confirmation** of rev-8. The rev-7
> review confirmed the design sound; the only residue was that disposition G's *accepting* branch (a valid
> explicit one-transaction→multiple-events allocation) had no direct numbered test — it was implied by
> 69/70/71. rev-8 adds **test 79** (accepting branch + fail-closed twin) and repoints the §17 A–H map so
> **G → 79**, count 78→79. **This is a micro-confirmation — do not re-open any rev-4…rev-7 control without a
> concrete regression.**
>
> **rev-8 changes:**
> 1. **Test 79 — disposition G accepting branch + fail-closed twin (§17).** Passing branch: one capture-week
>    posted transaction (in the opening basis) allocated across ≥2 plausible retained forward events with
>    authoritative evidence; `confirmed_matches[]` records one entry per allocated event (with `event_id`,
>    `event_content_digest`, `allocated_amount_cents`, `allocation_reason`, expected week/date, disposition,
>    `reflected_component_id`?, `remaining_forward_component_id`?); Σ allocated = adjudicated posted **exactly**;
>    each allocated event excluded/reduced/split **exactly once**; reflected + remaining = original amount
>    **exactly**; distinct content-bound identities; explicit allocation graph binds the one txn to all events;
>    no event in another reconciliation outside the same approved graph; each cash effect in the retained
>    projection **exactly once**; invariant holds ⇒ accepted G. Fail-closed twin: $0.01 imbalance (either
>    conservation equation), an allocated event also in another reconciliation without an explicit graph, a
>    missing digest/component identity, a fully-reflected effect still retained in schedule, or incomplete/
>    contradictory evidence ⇒ **FAIL-STOP**; no rounding tolerance, no prose waiver, ordinary HOLD insufficient
>    once a contradictory/imbalanced allocation is presented for acceptance; acceptance requires exact
>    integer-cent conservation.
> 2. **A–H map corrected (§17):** A→67/68 (+§5b 53); B→71; C→69; D→76; E→77; F→70; **G→79**; H→73. 69/70/71 are
>    no longer claimed as the accepting-branch proof for G.
> 3. **Count 78→79.**
>
> Everything else is unchanged and confirmed — **do not re-litigate it.**
>
> **Confirm each; state adequate / not-adequate with the exact failure:**
> 1. **Test 79 accepting branch** — does it directly and unambiguously prove a valid explicit
>    one-transaction→multiple-events allocation (one `confirmed_matches[]` entry per allocated event, exact
>    conservation, distinct content-bound identities, explicit allocation graph, each cash effect once)?
> 2. **Fail-closed twin** — does it prove that a **$0.01** imbalance (Σ allocated vs posted, and reflected +
>    remaining vs original), an unexplained allocation-graph multiplicity, a missing digest/identity, a
>    retained-after-reflected effect, or contradictory evidence each ⇒ **FAIL-STOP**, with no tolerance/waiver/
>    ordinary-HOLD escape?
> 3. **A–H mapping accuracy** — does §17 now map **G→79** (not 69/70/71), with A–F and H unchanged and correct?
> 4. **Counts & references** — is the enumerated total **79** everywhere it is stated, and are all references
>    internally consistent across the three documents?
> 5. **No regression** — did rev-8 introduce any executable-semantics ambiguity or reopen a settled control?
>
> **Return exactly these sections:**
> 1. **Test 79 sufficiency.**
> 2. **Corrected A–H coverage matrix.**
> 3. **Cross-document consistency.**
> 4. **New defects, if any.**
> 5. **Final verdict** — exactly one of **APPROVE** / **APPROVE WITH REQUIRED CHANGES** / **REJECT**.
>
> **Decision standard — APPROVE only if:** disposition G's accepting branch is directly and unambiguously
> tested; exact integer-cent conservation is required; a one-cent imbalance ⇒ FAIL-STOP; unexplained
> allocation-graph multiplicity ⇒ FAIL-STOP; every allocated/resulting component has content-bound identity +
> digest coverage; the global no-double-count invariant is explicitly asserted; the §17 A–H map points G→79;
> the total count is correct; the three documents are consistent; and rev-8 introduces no new
> executable-semantics ambiguity. Do not calculate a capacity number, recommend a transfer, or soften the
> verdict.

---

**Governance:** running this review does not execute Baseline E, calculate capacity, decide the Wendy IRA, or
authorize any transfer. A future PASS-SAFE result would not satisfy the CPA-clearance gate or lift the
operational HOLD. The HOLD remains active.
