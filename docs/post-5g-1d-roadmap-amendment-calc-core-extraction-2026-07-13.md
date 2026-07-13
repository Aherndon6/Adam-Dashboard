# Herndon Financial OS — Calc-Core Extraction and Module Posture Amendment

**Date:** 2026-07-13
**Type:** Docs-only amendment to the canonical post-5G-1D roadmap. **No implementation authority.**
**Amends:** `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md` (the canonical roadmap) — narrowly, at the calc-core extraction phase (P6), the 2027 rollover phase (P7), the merged architecture-hardening track (P8), the test-posture direction (§7-adjacent), and the decision register (§11). It does **not** reopen the broader roadmap synthesis.
**Source review:** `docs/reviews/application-modularization-review-2026-07-13.md` (advisory; not implementation authority; retained for provenance and architectural detail).
**Standing:** Advisory; adopt per Adam approval. If anything here conflicts with `AGENTS.md`, `CODEX_STATUS.md`, `docs/phase-status.md`, cleared 5G-1D scope, the Do Not Touch list, or Wendy-confirmed workflow, those controls win. This amendment authorizes no code, SQL, schema, migration, RLS, RPC, test, `index.html`, `BUILD_TS`, or production/staging change.

**Objective:** Clarify and **widen the existing calc-core extraction phase**. **Do not add a broad 2026 application-modularization phase.** Broader Register/Budget/view-layer modernization stays deferred to after the 2027 rollover under the existing merged architecture-hardening label, trigger-based.

---

## 1. Architectural verdict (adopted)

- **`index.html` is a material and rising maintainability / change-safety risk.** This is accepted as the architectural finding.
- **The primary risk is concentrated in:** the financial engine; implicit global inputs (direct reads from mutable globals); freeze-exception accretion (repeated in-body edits to frozen internals); and test coupling to source shape (source-pattern tests that assert against `index.html` text).
- **File size and the current immediate-mode rendering architecture are NOT, by themselves, reasons for a rewrite.** A large file and immediate-mode rendering are not defects to be re-platformed away; the risk is the concentration of *engine + implicit inputs + freeze exceptions + test coupling*, not line count or render style.

## 2. Roadmap disposition (adopted)

- **Keep the existing calc-core extraction slot** (canonical roadmap P6, re-slotted legacy 5G-2.5). Do not create a new broad modularization phase.
- **Widen its charter** (per §3 below) rather than spawn a parallel phase.
- **Keep broader Register / Budget / view-layer modernization deferred** until *after* the 2027 rollover, under the existing **merged architecture-hardening label** (canonical roadmap P8 — the merged 5L / 5I-4 modernization track). It remains **trigger-based**, not scheduled.
- **New 5G code must continue to land as ES modules** in separate files, per the existing standing rule — it must not enlarge the inline `index.html` script body.

## 3. Calc-core extraction scope (widened charter)

The future extraction **specification** (authored when the phase is scheduled) must cover:

1. **Shared pure utilities** the engine needs (formatting, rounding, week/date arithmetic, small predicates) — extracted as pure functions.
2. **Explicit model-input construction** — the engine reads an explicitly constructed input object, **not** direct reads from mutable globals. Implicit global inputs become a named, constructed contract.
3. **Explicit engine outputs, including `ruleAudit`** — outputs (transfers, allocations, `goalSaved`, balances, `ruleAudit`, variance signals) are returned explicitly rather than left as ambient side effects.
4. **Goal-registry and budget-rule domain logic** — the target/status/flag and budget-rule resolution logic that currently interleaves with rendering.
5. **Cash Availability / AMEX-lookahead logic under behavioral identity** — the `maxSafeAmxSweep` / 5-week-lookahead / floor logic extracted with golden-master behavioral identity held.
6. **`runModel` and `reconEffectiveWD`** — the waterfall core and the override-aware effective-WD resolver.
7. **Reconciliation payload and closeout builders — only after 5G-1D is complete and stable.** These are sequenced *behind* 5G-1D completion (activation + Slice 7); extraction must not touch the 5G-1D closeout builders until 5G-1D's own scope is done and stable.
8. **Constants / configuration as the controlled seam for Plan Period / rollover** — OP_FL, MIN_XFR, lookahead depth, seed thresholds, START_* and PAYCHECK_WKS and the WD literals externalized to a versioned configuration read at model init, so year-scoped rollover changes have a bounded seam.
9. **Test-harness migration needed to support modules** — the harness changes (module loading, HTTP-based E2E, golden-master expansion) that modules require (see §4).

**Structure is illustrative, not locked.** This amendment **does not lock the final filenames or the physical module tree.** The Fable review's proposed structure is recorded as **illustrative input** to the later extraction specification; the specification decides the actual module boundaries and names under review.

## 4. Test posture (standing direction, adopted)

- **New tests should assert behavior rather than source-text shape whenever feasible.**
- **Source-shape tests are permitted only where implementation shape is itself a required contract** (e.g. a security guard whose exact form is the contract), **with the reason documented** at the test.
- **Test-harness adaptation, HTTP-based E2E module loading, and expanded golden-master coverage are extraction PREREQUISITES, not post-extraction cleanup.** They are scoped into the extraction spec and done first, not deferred.
- **Existing golden-master values may not be changed merely to make an extraction pass** (reinforces the existing standing rule: never edit golden-master expected outputs to make a test pass without Adam approval).

## 5. Module / API posture (adopted)

- **No framework, bundler, build step, TypeScript, or replatform is approved.**
- **ES modules remain the target mechanism.**
- **A future explicit `window` compatibility bridge** may expose **only** the names required for inline event handlers, bootstrapping, or test compatibility. It is **transitional** and **must not make internal domain functions globally public.**
- **A shared data-access wrapper should be used by new code first;** legacy `fetch` calls migrate only when their feature is touched (no bulk migration — see §7).
- **Any relocation of the staging write-block or other environment-safety control requires explicit characterization and validation** (it is not an incidental move during extraction).

## 6. Rollover relationship (adopted, with the calendar-risk gate)

- **Extraction is the *preferred* prerequisite to 2027 rollover implementation** because it creates a bounded constants/input seam and avoids another high-risk edit inside the frozen monolith.
- **Extraction does not automatically delay rollover under all circumstances.** The 2027 operating deadline (model window ends 2027-01-09) is the hard constraint.
- **Calendar-risk decision gate (requires Adam):** if extraction timing threatens the 2027 operating deadline, Adam must approve **either**
  - **(a)** completing extraction before rollover, **or**
  - **(b)** executing a **narrowly scoped rollover against the existing engine** with enhanced characterization and rollback controls.
- **A partially completed extraction must never become the rollover base.** (If extraction is mid-flight at the decision point, the choice is (a) finish it first or (b) roll over against the *existing* engine — never against a half-extracted core.)

## 7. Explicit non-scope (rejected for this phase)

None of the following is in the calc-core extraction charter; each stays deferred to the post-rollover, trigger-based merged architecture-hardening track:

- Register extraction
- Budget extraction
- reconciliation UI extraction
- render-system rewrite
- modal / navigation rewrite
- replacement of inline event handlers
- bulk migration of legacy `fetch` calls
- CSS / HTML splitting
- framework or build-tool adoption

---

## 8. Disposition of the Fable review (adopted / modified / deferred / rejected)

*Attribution reconciled against the verbatim review `docs/reviews/application-modularization-review-2026-07-13.md` (its section numbers cited as "review §N").*

- **Adopted (directly from the review):**
  - The architectural verdict — `index.html` is a material and rising risk, but the risk is **not file size**; it concentrates in the frozen calc core's freeze-exception accretion, the test suite's coupling to source shape, and engine I/O through ~15 mutable globals (review §1–§2).
  - **No distinct broad application-modularization phase — instead widen the existing calc-core extraction charter (P6).** This is the review's own headline conclusion (review §1, §8), not an Adam-imposed narrowing.
  - The four riders (shared-utility module; the `buildModelInputs()` engine-input adapter retiring preview-by-global-mutation; window-bridge + e2e-over-HTTP infrastructure; the already-mandated test migration) and the extraction scope/slice content (review §1, §3–§4).
  - The test posture — new tests assert behavior over source text; harness repoint / HTTP-E2E / golden-master expansion are extraction preconditions; golden-master expectations are never edited to pass (review §7).
  - The module/API posture — ES modules only; the `window` bridge as a *documented* contract (not making internal domain functions public); shared `js/data/api.js` for new code with **opportunistic** legacy-`fetch` migration (review §3, §6, §7).
  - Extraction as the rollover prerequisite with `constants.js` as the per-year seam that makes the rollover a bounded change (review §5, §8). *(Note: the review attaches the module **infrastructure** — e2e-over-HTTP, `js/data/api.js` — to 5G-2, feeding extraction as a precondition; this amendment carries it as an extraction prerequisite, a compatible framing.)*
- **Modified / narrowed (by Adam):**
  - The review proposes a **specific physical module tree** (review §3) and a **numbered slice sequence 0–6** (review §4). This amendment records both as **illustrative input only; filenames and the physical module tree are not locked** and are decided in the later extraction spec (amendment §3). *(This is the narrowing — not the "no broad phase" decision, which is adopted straight from the review.)*
  - On a rollover-timing collision the review's stance is stronger: **"extraction wins the collision … the rollover executed against an un-extracted engine is the single worst-case scenario"** (review §5, §8). This amendment instead installs an **owner decision gate** (amendment §6 / canonical §11 D10) that permits, as **option (b)**, a *narrowly scoped rollover against the existing engine with enhanced characterization + rollback* — a deliberate softening of the review's "extraction always wins," bounded by "a partially completed extraction must never become the rollover base."
- **Deferred (per the review):** broader Register / Budget / view-layer / render / modal-nav modernization → **post-2027-rollover, trigger-based**, under the merged 5L / 5I-4 architecture-hardening label (review §5, §6, §8; amendment §2, §7).
- **Rejected as rewrite drivers (per the review):** **file size** ("the risk is not '10,000 lines' as such") and the **immediate-mode rendering architecture** ("conceptually clean … it is not the problem") as reasons for a rewrite (review §1–§2); plus the review's own explicit non-goals — **framework / bundler / build step / TypeScript / replatform**, view-layer rewrite, event-delegation conversion of the inline handlers, Register/Budget/recon-UI extraction in 2026, big-bang `fetch` migration, CSS/HTML splitting, and any behavior change under the extraction flag (review §6, §7).

## 9. Decisions still requiring Adam

- **Calendar-risk gate (§6):** if extraction timing threatens the 2027 deadline, choose (a) extraction-before-rollover or (b) a narrowly scoped rollover against the existing engine with enhanced characterization + rollback. (No default is set; a partially completed extraction may never be the rollover base.)
- **Adoption of this amendment** into the canonical roadmap (the canonical synthesis already carries narrow pointers to it; formal adoption is Adam's per the synthesis §11 D2/D9 pattern).

## 10. Relationship to the canonical roadmap

This amendment amends the canonical roadmap `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md` at (canonical section labels; amendment sections cited as "amendment §N"):
- **canonical P6 (calc-core extraction)** — charter widened per amendment §3; test-migration prerequisites per amendment §4; module/API posture per amendment §5.
- **canonical P7 (Plan Period / 2027 rollover)** — extraction is the preferred prerequisite; the calendar-risk gate (amendment §6) governs the timing conflict.
- **canonical P8 (merged architecture-hardening / data-feature ladder)** — broader Register/Budget/view-layer modernization confirmed post-rollover and trigger-based (amendment §2, §7).
- **canonical §7 (month-end close / operating model) and the engineering direction** — the behavior-over-source-shape test posture (amendment §4).
- **canonical §11 (decision register)** — the calendar-risk gate D10 (amendment §9).

It does **not** alter any other phase, the month-end close/audit operating model, the parked backlog, or the Quicken/operating-state facts, and it does **not** apply the broader canonical §7 / 2026-07-12-draft §7 documentation patch plan.

---

*Amendment only. No code, SQL, schema, migration, RLS, RPC, test, `index.html`, `BUILD_TS`, or production/staging change. The source review is advisory; the canonical roadmap remains authoritative for sequencing (as amended here, pending Adam adoption); 5G-1D remains frozen and authoritative for its own scope.*
