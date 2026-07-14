# Fable Challenge Prompt — Post-5G-1D Canonical Roadmap (FINAL)

**Target document:** `docs/post-5g-1d-canonical-roadmap-final-2026-07-13.md`
**Supporting context (read for provenance, not as competing roadmaps):**
`docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md`,
`docs/post-5g-1d-roadmap-amendment-calc-core-extraction-2026-07-13.md`,
the three 2026-07-12 Fable reviews (roadmap RM / architecture AR / operating-model OM),
`AGENTS.md`, `CODEX_STATUS.md`, `docs/phase-status.md`,
`docs/phase-5g-1d-saturday-operator-package-2026-07-18.md`.
**Type:** Independent adversarial challenge. Governance/planning only. No code, SQL, or execution is in scope.
**Your role:** You are the independent reviewer of record. Assume the author is over-confident. Your job is to *break* the sequence, not to ratify it.

---

## 0. What this document is

The target is the FINAL canonical post-5G-1D execution sequence. It reconciles six prior inputs (roadmap,
architecture, modularization, calculation-core, operating-model, product-priority) into ONE ordered plan:

- **§0** refreshes the stale 5G-1D baseline and resolves two open hedges (Gate D = Option A pre-freeze; a fresh
  2026-07-13 restore point partially closes the DR gap).
- **§A/B** state the current-state baseline and the eight ranked decision principles.
- **§C** is the canonical sequence P0–P8.
- **§D/E/F** are the pre-freeze / freeze / post-freeze splits.
- **§G** is the strict dependency graph; **§H** is the three parallel lanes.
- **§I** names the single recommended next implementation phase: **Monthly Close v1 (file-based)**.
- **§J** is the deferred list; **§K** is the unresolved owner-decision register; **§L** points here.

Load-bearing constraints the plan must respect (all are current repo facts, not proposals):
- 5G-1D is at the **Saturday 2026-07-18 activation boundary** — pre-activation work is done and Adam-verified
  (**static 1507/0, e2e 148/0/0, readiness fallbacks 0/0**; Slice-6 inert prod deploy COMPLETE + GREEN; Gate C
  APPROVED; Gate D DECIDED = Option A). The only remaining 5G-1D action is the controlled Saturday sitting.
- **Alaska freeze Jul 24 – Aug 10** — no 5G phase-code merges in-window.
- **Cruise payouts:** RCCL ~Cal Wk 30, DCL ~Cal Wk 41 (forces 5G-1B).
- **Model window ends 2027-01-09** (forces the Plan Period / rollover).
- The Financial OS is the **sole live system of record** (Quicken retired).
- `weekly_reconciliations` is keyed **only by `week_num`** (P2-2) — a rollover blocker.
- Model **`week_num=6` = calendar Week 28** (`getCalWeek(6)=28`); first closeout persists `week_num=6`.

---

## 1. Your mandate

Adversarially challenge the roadmap. Do **not** grade prose. Attack the plan's structure. Specifically, you must
challenge each of the following and state, for each, whether the document is right, wrong, or unproven:

1. **The canonical sequence (§C P0–P8).** Is the ordering defensible? Is any phase mis-placed by more than one slot?
   Is any ordering asserted without a real dependency behind it (ordering-by-preference dressed as ordering-by-dependency)?
2. **Dependency assumptions (§G).** Is every "must precede" edge real? Name any edge that is actually a soft
   preference, any missing edge, and any cycle. Specifically test: extraction→5G-4; extraction→rollover (preferred,
   not mandatory — is that right?); 5G-3 depends on 5G-2 **not** extraction; Close v1 depends on 5G-1D **not** 5G-3;
   TX-1 independent of 5G-2/5G-3.
3. **The freeze boundary (§D/E/F; Jul 24 – Aug 10).** Is the pre/freeze/post partition correct? Is anything labeled
   "freeze-safe" that actually mutates production behavior, schema, grants, or the cash model? Is anything labeled
   post-freeze that could (and should) safely happen during the freeze? Is the "specs only" freeze rule too strict
   or too loose?
4. **Parallelization (§H, three lanes).** Are the three lanes genuinely independent, or do they share hidden state
   / the same single-file `index.html` merge surface / the same reviewer-and-operator (one person)? Are the marked
   synchronization points sufficient? Is three lanes realistic for a one-owner operation, or is it optimistic
   throughput that will actually serialize?
5. **Architecture-debt timing.** Is calc-core extraction correctly placed (gates 5G-4; preferred-prereq to rollover;
   post-5G-1D-stable)? Is deferring **broad** application modularization to **post-2027-rollover** correct, or does
   that let `index.html` (~730KB, single file) harden past the point of cheap extraction? Is the extraction's
   embedded test-harness migration correctly treated as a **prerequisite** rather than cleanup?
6. **Operational-urgency ranking (§B principle 1; §I).** The plan ranks the **recovery-remediation floor** (DR: MFA,
   backup owner, dump cadence, restore rehearsal, runbook) as the #1 immediate priority but classifies it as
   ops/DR that runs in parallel — **not** the "next phase." Is that the right call, or is the DR floor being
   quietly demoted by putting a *build* phase (Close v1) in the headline slot? Given the sole-live-record posture,
   is a partially-closed DR gap (07-13 dump exists; floor unbuilt) an acceptable state to enter the freeze in?
7. **The chosen immediate next phase (§I): Monthly Close v1 (file-based).** Is this correct? Argue the strongest case
   **against** it and **for** each alternative — Register/TX-1 data-quality bundle, 5G-1B releases, 5G-2 Planned
   Outflows. If Close v1 is wrong, name the phase that should be first and why. If it is right, name the one
   assumption that, if false, would flip the decision.
8. **Earlier/later moves.** Name anything that should move **earlier** (esp. anything calendar-forced that the plan
   parks post-freeze and could miss its window — test RCCL ~Cal Wk 30 and DCL ~Cal Wk 41 against the 5G-1B
   placement in P4/F). Name anything that should move **later** (over-eager pre-freeze or early-post-freeze work
   that raises blast radius on the freshly-activated 5G-1D contract).
9. **Hidden coupling with 5G-1D.** The plan asserts post-5G-1D phases are cleanly downstream of the activation. Find
   the coupling it under-states: the rollover amends 5G-1D-frozen objects (`weekly_reconciliations`, the closeout
   wrapper, the 9-snapshot contract, the `week_num`-only key); Close v1 composes over the fully-closed predicate;
   5G-1B's release events touch the same snapshot rows and the Week-5 `wewe_*` correction rows. Is the migration
   authority over those frozen contracts resolved on paper before any lane touches them, or is that gap real?
10. **Risk of doing too much before the freeze (§D).** The plan says pre-freeze = "finish 5G-1D + recovery floor +
    docs currency + draft specs, nothing more." Is that discipline correct, or is even *that* too much to safely
    land in the ~5 days between the Saturday activation and the Jul 24 freeze? Is there a case for doing **less**
    pre-freeze (e.g., activation + DR floor only, defer the docs/spec work into the freeze window)?

---

## 2. Additional pressure tests (answer each briefly)

- **§0 currency claims.** Are CR-1…CR-4 actually resolved, or does any of them still hide an open decision? In
  particular: does Gate D = Option A (pre-freeze activation) truly eliminate freeze-period half-closes, or is there
  a residual half-close/basis-watermark case the plan misses?
- **Principle ordering (§B).** Eight principles are ranked. Is "production risk / operational urgency" over
  "calendar-forced deadlines" the right top-two order? Construct the scenario where those two principles conflict
  (a calendar-forced 5G-1B build competing with an unbuilt DR floor) and say which the plan's ordering picks — and
  whether that pick is correct.
- **One-owner throughput.** Every lane, review, and operational step routes through one person (Adam), with Fable as
  the only independent reviewer. Does the plan's parallelism survive that constraint, or should it be re-drawn as a
  mostly-serial sequence with explicit "these can interleave" annotations?
- **Deferred list (§J).** Is anything on the deferred list actually load-bearing / calendar-forced and mis-deferred?
- **Decision register (§K).** Are all the genuinely-blocking owner decisions captured? Name any decision the plan
  makes silently (in prose) that should instead be an explicit `D-*` register entry awaiting Adam.
- **Single-file merge reality.** Every code phase edits one ~730KB `index.html`. Does the three-lane plan
  under-account for merge serialization and review load on that single surface?

---

## 3. Required output format

Produce your review in exactly this structure:

### Verdict (required, pick one)
**APPROVE** / **APPROVE WITH REQUIRED CHANGES** / **REJECT**
One paragraph justifying the verdict.

### Findings (required)
List every finding. For **each** finding provide:
- **ID** (F-01, F-02, …)
- **Severity:** **P0** (must fix before the tagged milestone; blocks) / **P1** (should fix; material) / **P2** (minor / nice-to-have)
- **Milestone tag (required, pick one):** `before freeze` / `during freeze` / `after freeze` / `before implementation of <named phase>`
- **Which mandate item(s)** it answers (§1.1–§1.10 and/or §2)
- **Claim** — what the roadmap says
- **Challenge** — why it may be wrong, with the concrete failure scenario or missed dependency/edge/window
- **Recommended change** — the specific edit to the sequence, dependency graph, freeze split, lane, or next-phase choice

### Direct answers to the ten mandate questions (required)
Answer §1.1 through §1.10 explicitly, one line to one paragraph each, even where you have no finding — a clean
"correct as written, because X" is a valid answer and is wanted.

### Sequence delta (required if verdict ≠ APPROVE)
If you would change the order, give the corrected P0–P8 sequence (or the specific swaps) and the corrected
pre-freeze / freeze / post-freeze split.

### The one assumption most likely to be wrong (required)
Name the single assumption in the roadmap whose failure would most damage the plan, and what to do about it.

---

## 4. Ground rules for your review

- **Do not** propose code, SQL, schema, migration, RLS, RPC, test, or BUILD_TS changes. This is a paper challenge to
  a paper plan.
- **Do not** re-open cleared 5G-1D scope, gates, contracts, or the Saturday activation mechanics — 5G-1D is treated
  as in-flight and correct. Challenge only what happens **after** it and the sequencing **into** it.
- **Do** treat every repo fact in §0/§1 of this prompt and in the target doc's §0/§A as authoritative; if you
  believe one is stale, flag it as a finding rather than assuming a different fact.
- **Do** prefer concrete failure scenarios (a specific window missed, a specific frozen object mutated, a specific
  lane collision) over general commentary.
- **Do** be willing to REJECT or to demand changes. A rubber-stamp is a failed review. If the plan is sound, say so
  and name its weakest load-bearing assumption anyway.

---

*Governance/planning artifact. Advisory. The roadmap is adopted only on Adam's approval plus disposition of this
challenge's required changes.*
