# Herndon Financial OS — Canonical Roadmap (living)

**Document role:** This is the **Plan** document in the four-document authority model (Law = `AGENTS.md`; State = `CODEX_STATUS.md`; History = append-only closeouts + `docs/execution-ledger.md` + `docs/decision-log.md`; Plan = *this file*). It is **revised in place** — git history is its changelog. It is the single living canonical roadmap; there is no superseding roadmap layer above it. Prior roadmap layers are archived for provenance in `docs/roadmap/archive-index.md`.

**Standing:** **Advisory. Docs only. No implementation authority.** `AGENTS.md`, `CODEX_STATUS.md`, `docs/phase-status.md`, cleared 5G-1D scope, the Do-Not-Touch list, and Wendy-confirmed workflow win on any conflict. This document amends no cleared scope, gate, contract, SQL, RPC, or execution step. Repository facts remain authoritative for implemented functionality. Committed content here is **balance-free** — no household account balances or dollar amounts.

**Adoption provenance:** Adopted per Adam decision **A1 (2026-07-14)** on the controlling external input `Fable — Post-5G-1D Roadmap Adoption Review (2026-07-14)` (verdict **APPROVED — controlling**, converting the 2026-07-13 challenge's "APPROVE WITH REQUIRED CHANGES"). This living roadmap folds in: the FINAL roadmap (`post-5g-1d-canonical-roadmap-final-2026-07-13.md`, planning branch `docs/post-5g-1d-canonical-roadmap` @ `dbc1aee`), the calc-core extraction amendment, the Fable review's R1–R15 revisions and AF-1…AF-10 / SR-1…SR-5 architect's addendum, and Adam's decision set A1–A19 of 2026-07-14. See `docs/roadmap/archive-index.md` for the full provenance chain.

---

## 0. Currency & charter facts

**Verified 5G-1D state (repository @ local `7f0f47d`; remote tip `a952560` = local + the Saturday operator package; `origin/main` docs-only):**
- Browser Slices 3/4/5 **COMPLETE + Adam-verified** — static **1507/0**, full `node e2e.js` **148/0/0**, readiness fallbacks openApp 0 / clickNav 0 (@ `114b080`).
- **Slice 6 inert production deployment COMPLETE + GREEN (2026-07-13)** — wrapper + Option B live in production Adam-Dashboard (`usayoldrawwmjsmretin`), INERT (zero API-role EXECUTE; bodies byte-unchanged; DR restore point captured).
- **Gate C** all 11 dispositions **APPROVED, not executed**. **Gate D DECIDED = Option A (pre-freeze activation).** **Gate B** is at the **Saturday 2026-07-18 activation sitting**. **Gate E** untriggered.
- The Week-5 anchor holds 11 rows (9 `opening_anchor` + 2 `correction`). 5G-1D writes *subsequent* weekly closeout snapshots only; it does not author the opening anchor.
- **5G-1D is NOT production-live and is NOT complete** until the Saturday sitting closes Gates B/C/D/E.

**Two charter facts that supersede the repository's older planning assumptions:**
1. **The repository freeze is `Jul 29 – Aug 10, 2026`** (corrected from the stale "Jul 24 – Aug 10" in older docs). It is a controlled **repository-stability period**, not a total personal-work blackout — see §11.3. Gate D's "activation before Jul 24" survives as the *activation target*; Jul 25–28 is contingency margin, not new scope.
2. **Fable independent-review access ends `Jul 19, 2026`.** Nothing after Jul 19 may depend on Fable. The 1B spec review baseline (§4 verbatim), the DR gate, the contingency annex, and the taxonomy are front-loaded here for exactly this reason; the substitute review chain is in §11.2.

**Model-week arithmetic (confirmed; `getCalWeek(model)=model+22`):** persisted `week_num` is the **model week** (epoch Jun 7 2026). Model wk 6 = **Cal Wk 28**, first supervised closeout Sat **Jul 18**; wk 7 = Sat **Jul 25** (at home, pre-freeze); wk 8 = Cal Wk 30 = Sat **Aug 1** (inside freeze); wk 9 = Sat **Aug 8** (inside freeze); wk 10 = Sat **Aug 15**. RCCL payout ~Cal Wk 30 (~Aug 1, mid-trip); DCL ~Cal Wk 41 (~Oct 17). Model window ends **2027-01-09**. `weekly_reconciliations` has **no `model_year` column** and upserts on bare `week_num` — see §14 (AF-2) and §12 (D-11).

**Active execution pointer (2026-07-19) — this roadmap is PAUSED until it clears.** Before the normal roadmap resumes, the controlling sequence is **Post-BKX Stabilization & Goal-Funding Validation** — `docs/phase-5g-1d-post-bkx-stabilization-2026-07-19.md` (State detail in `CODEX_STATUS.md`): (1) finish BKX settlement + R5–R7 verification → (2) Week 23/24 read-only diagnosis → (3) smallest-safe Week 23/24 repair → (4) pre/post goal-funding deep dive → (5) fix any defects → (6) finalize/push docs (after approval) → (7) **then** resume this roadmap. Advisory; balance-free.

---

## 1. Current-state baseline

- **Exact point:** 5G-1D at the **Gate B production-activation boundary** — all pre-activation work done and verified; the only remaining 5G-1D action is the Saturday sitting (Phase-1 grants → BUILD_TS stamp + merge/deploy → pre-revoke browser verification → first supervised Week-6/Cal-Wk-28 closeout through the wrapper while the old RPC remains granted as a fallback → Phase-2 revokes → two non-mutating post-revoke proofs). "Post-5G-1D" work begins only once that sitting closes Gates B/C/D/E.
- **System-of-record posture:** the Financial OS is the **sole live system of record**; Quicken is retired (historical archive/reference only — not a parallel ledger or recovery replica). Backup/restore maturity is therefore an **immediate production-operability requirement** (→ DR-1, §5).
- **Freeze window:** `Jul 29 – Aug 10` — no routine `main` pushes and no 5G phase-code merges (two named exception classes, §11.3). 5G-1D activation is **pre-freeze** (Option A).
- **Confirmed calendar-forced deadlines / active blockers:** DR exposure (Supabase Free plan, no PITR; single-operator; auth-schema not in the public dump — §14 AF-1) → DR-1; cruise payouts (**RCCL ~Cal Wk 30**, **DCL ~Cal Wk 41**) force **5G-1B**; the **2027-01-09** model-window end forces the **rollover**; `weekly_reconciliations` bare-`week_num` keying (P2-2) plus six more `week_num`-keyed objects (§14 AF-2) must be re-keyed/archived before the first 2027 closeout.
- **Item taxonomy:** **Shipped** = 5B/5E Budget+Register, 5F-1 weekly reconciliation + Cash Availability Engine, 5G-1A/1A.5/1C-1 hotfixes, 5G-1C-2 E1/E2 + C3 overlay + 2.1 coherence hotfix, and the 5G-1D browser + Slice-6 inert deploy. **Planned/validated-not-live:** 5G-2 Planned Outflows (staging DB layer validated 2026-07-08). **Named-but-empty:** 5G-1E, Monthly Close v1 (reframed 5G-1F), 5G-2…5G-6, 5H/5I/5J/5K/5L. **Advisory inputs (not approved roadmaps):** the three 2026-07-12 Fable reviews, the calc-core amendment, the synthesis, the FINAL roadmap, and the 2026-07-14 adoption review — all folded here and archived in `archive-index.md`.

---

## 2. Decision principles (work is ranked on these, in priority order)

1. **Production risk / operational urgency** — protect the sole live record; anything that can lose or corrupt data outranks everything.
2. **Calendar-forced deadlines** — cruise payouts (5G-1B) and the 2027 rollover are immovable.
3. **Dependency unlocking** — items that gate the critical path (extraction; 5G-4a) come before their dependents.
4. **User value** — Wendy/Adam workflow quality (Register bundle, Goal Admin, mobile).
5. **Architecture leverage** — one-time cheap venues (5G-4 taxonomy, extraction seams) taken before they harden.
6. **Reversibility** — file-tier/docs-first before schema; certify-don't-lock; staging-first.
7. **Implementation size** — prefer small, high-certainty slices; never bundle a hidden second project (e.g., test-suite migration inside extraction) without scoping it.
8. **Freeze compatibility** — docs/spec/test/review work is freeze-safe; 5G merges and cash-model behavior changes are not.

---

## 3. Canonical implementation sequence (P0–P8)

No P0–P8 slot changes vs the FINAL roadmap; deltas are gates, dates, and intra-step order. **WIP = 1 for code-bearing phases** (§8). Dates reflect the corrected freeze (`Jul 29 – Aug 10`) and the Fable-access-end (`Jul 19`).

### 3.0 Corrected sequence & dates (Targeted Sequencing amendment T-1…T-6, 2026-07-14 — CONTROLLING)

*Adopts the Fable Targeted Sequencing Review + Boundary Clarifications (Amendment 1) + Account Composition Scope (Amendment 2), all 2026-07-14 (provenance: `docs/roadmap/archive-index.md`). This table is the controlling order; the P-block narrative below is annotated where a T-decision changes it. **Two structural guarantees:** (1) the **DCL chain** (1B build start ≤ Sep 14; complete before DCL ~Oct 17) and the **rollover chain** (spec ~Nov 1 → D10+D-11 ~Nov 15 → rehearsal mid-Dec → execution ≤ Dec 28, hard 2027-01-09) are **dated, calendar-forced chains that preempt every discretionary item** — nothing in this amendment displaces either. (2) **No separate "Architecture Enablement" code phase exists** — "Stage 1A" is dissolved (T-3): its paper is freeze docs, its seams are Calc-Core Extraction Stage 1 (late Nov), its tests ride D7. Pre-1B preparation is documentation + test-only per the §8 bright line.*

| # | When | Item | Notes |
|---|---|---|---|
| 1 | Sat Jul 18 | 5G-1D activation (P0) | Operator package; contingency annex live |
| 2 | ≤ Jul 28 | DR-1 sign-off | Hard gate; blocks all post-5G-1D implementation |
| 3 | Jul 29–Aug 10 | Freeze: specs only — **1B spec first**, then **TX-SPLIT spec**, **Data-Extension & Identity Conventions** (durable-ID ADRs + transaction-extension contract + append-only event conventions + model I/O inventory), P3b-1/TX-1 spec **incl. P3b-1.MX**, Plan Period kickoff (AF-2 inventory) | Close v1 spec already done (`3e6d43b`); pre-1B prep boundary = §8 bright line |
| 4 | Aug 11–17 | Catch-up closeouts (wk 8, 9) → **first July close** | Monthly Close v1 |
| 5 | Aug 17–24 | Diablos/GLP baseline + golden-master recapture (D7) | First post-freeze code merge |
| 6 | Sep 1 → ≤ Oct 10 | **5G-1B Holding→Allocation→Payout** (+1B-S4 valve) | Build start drop-dead Sep 14; **DCL bound ~Oct 17 — protected** |
| 7 | Oct (~2–3 wks) | **P3b-1 Register & Budget Data Integrity — incl. P3b-1.MX (Misc/Extra Envelope v1)** **[T-2]** | P3b-2 ergonomics sheds/interleaves; feeds Oct/Nov closes |
| 8 | Nov (~3–4 wks) | **5G-2 Planned Outflows & Accruals** (Mint ID 49; annual renewals; sinking funds; December-trip entry at launch) — **November default [T-1]** | Carries the ES-module infra tax by design; D6 ≤ Oct 1; A13 fallback stays live |
| 9 | Nov (paper, parallel) | Plan Period spec (~Nov 1) → **D10 + D-11 (~Nov 15)** | Calendar-forced; preempts discretionary work |
| 10 | Late Nov (~2–3 wks) | **Calc-Core Extraction Stage 1** (input construction · constants/config seam · explicit outputs, under golden masters) **[T-3]** | = the code remnant of "Stage 1A"; common prefix of D10 (a) and (c) |
| 11 | Dec | Rollover rehearsal (mid-Dec) → **production rollover + 2027 anchor ≤ Dec 28** (hard 2027-01-09) | **December is code-free — rollover owns the operator; protected** |
| 12 | Jan 2027 | **TX-SPLIT — Split Transaction Foundation** (spec'd in freeze; **first post-rollover build, default [T-1]**) | Sidecar `transaction_splits`; **conditional Nov swap branch** (T-1 preconditions) |
| 13 | Q1 2027 | **5G-3 Account Cash Allocation** ("what makes up this balance?"; Spoken-For / Free-to-Use; Checking composition) | Zero-engine-change proof per the re-pin; Stage-1 outputs make it honest |
| 14 | Q1–Q2 2027 | Extraction **Stage 2** (core move) → **5G-4a** → **5G-4b Dynamic Goal Registry** → **5G-5 Goal Intelligence & Timeline** **[T-4/T-5]** | Honest 2027 dates (no scope change) |
| 15 | ongoing / WIP=1 gaps | Interleave-class display riders, **at most one per gap**, never ahead of a calendar-forced or data-integrity item: **Account Composition Visibility Rider** (§18, T-6) · **GT-R read-only Goal Timeline/History** (T-4) · Roadmap UI Lite (§17, W-8) · P3b-2 | — |
| 16 | post-rollover | Edge Function enabler (early 2027, SR-4) → L2 on trigger → Transfers (5K) → Import Readiness → Horizons; 5H; modularization trigger-based | Unchanged |

**Conditional T-1 swap (decide ≤ Oct 1 with D6):** TX-SPLIT may take the **November** slot (5G-2 → Jan/Feb 2027) **iff all four** hold by Oct 1: (a) 1B accepted with ≥1 wk margin (≤ ~Sep 27); (b) P3b-1 on track ≤ ~Oct 18; (c) the TX-SPLIT freeze spec passed review **and** Wendy confirmed the split-editor workflow; (d) Adam accepts the 5G-2 displacement costs in writing (decision-log entry). **A December squeeze is never the trigger** — December is not a build slot. **Default: 5G-2 November, TX-SPLIT January.**

**P0 — Complete 5G-1D (in-flight; do not disturb). Window: pre-freeze, Sat Jul 18.**
Activate the atomic reconciliation-plus-nine-snapshot closeout in production per the operator package — with the **§7 contingency annex adopted first** and the **§6 Alaska skip posture decided**. Gates B/C/D/E. Output: wrapper live+granted; Week-6/Cal-Wk-28 closeout evidenced; old direct write paths revoked; two non-mutating proofs recorded.

**P1 — Recovery-remediation floor = DR-1 gate (non-code; START NOW, parallel to P0). Window: now → Jul 28 (hard gate).**
Close the sole-live-record DR exposure. Full item set and blocking effect in §5. Sign-off ≤ **Jul 28** in `docs/dr-exit-gate-2026-07.md`. **DR-1 failure blocks all post-5G-1D implementation work.**

**P1b — Docs-only currency + fold-in (non-code, owner-approved). Window: now → freeze.**
Roadmap numbering + legacy-gate fold-in in `docs/phase-status.md`; the `runModel` freeze-language **re-pin** against the extraction phase (§9; blocking prerequisite to 5G-3); obligation-taxonomy one-pager; `CODEX_STATUS.md` / `AGENTS.md` currency (freeze dates, Gate-D target-vs-margin, pointer to this roadmap, Do-Not-Touch categorization). Owner-approved patch (A6).

**Sat Jul 25 (at home) — week-7 closeout (normal).** Also the natural **activation-retry sitting** if the Saturday Jul 18 sitting hard-stopped (§7).

**P2 — Freeze window (`Jul 29 – Aug 10`): SPECS ONLY.**
Agent-drafted, branch-held, **1B spec first** (§4). Also: Register Data-Quality + Entry / TX-1 taxonomy scope (P3b-1/P3b-2 split, §13 SR-1); Monthly Close v1 P1–P9 checklist + certification template incl. the **grant-matrix P-item** (F-09); Plan Period design-doc kickoff (incl. the §14 AF-2 seven-object inventory); obligations end-state memo; CSP feasibility note. **Zero pushes to `main` except the two named exception classes (§11.3).** Optional Adam-discretion branch-held build: the load-failure banner (F-12). Weeks 8–9 closeouts **skipped** per §6.

**P3 — First implementation phase after 5G-1D: Monthly Close v1 (file-based; reframed 5G-1F). Window: post-activation (spec-able in freeze; first July close executable Aug 11–17).**
Repeatable certification + basis watermark + closed-period divergence detection; the primary period-integrity control now that Quicken is retired. Zero-code by design. Prereq: 5G-1D activated (fully-closed predicate) **and wk-8 fully closed** (so July is complete after trip catch-up). Output: `docs/closes/2026-07-close.md`; 3-fact state model (certification + reopen records; OPEN/CERTIFIED/REOPENED/DIVERGED derived). First close notes the late-`recorded_at` watermark nuance for catch-up rows (§6). **No Fable review needed — the operating-model control review is its spec; the substitute chain (§11.2) applies to the spec if challenged.** **Implementation-ready spec + operator runbook (drafted 2026-07-14):** `docs/monthly-close-v1-spec-2026-07-14.md`, `docs/monthly-close-v1-operator-runbook-2026-07-14.md`.

**P3b — Register Data-Quality + Entry bundle (first CODE phase; parallel to Close v1's 2nd iteration; WIP=1). Split per SR-1 (§13):**
- **P3b-1 Data Integrity** — TX-1 taxonomy (income/offset categories) + required-category + save validation + uncategorized cleanup; `budget_line_rules.category_key`→`categories` FK audit (**AGENTS.md Near-Term Wishlist ID 39** / `docs/validation-blr-category-sync.sql` / `docs/2026-07-02-register-budget-category-sync.sql` — **not** live `wishlist_items` ID 39, which is mobile usability → 5H; see Appendix B.3); reimbursement-status home decision (Register status columns vs manual side-channel). Includes **TX-1.1** — the register income category must be labeled **exactly** `Wendy Extra BK Pay` (weekly-model match, drift guard; `income.bkcpa_extra_pay` / `commission_income` / `display_only`) and recategorize the 2026-07-17 BK $1,752.26 inflow (No Category → `Wendy Extra BK Pay`); **post-activation only**, register-classification/reporting only, no tax-rule/goal duplication (`docs/tx-1-candidate.md` §TX-1.1). *Feeds close quality; sheds last.*
  - **P3b-1.MX — Misc/Extra Envelope v1 [T-2; resolves W-3].** A first-class Misc/Extra budget category (namespace-checked vs `misc.goal_sweep` [Do-Not-Touch]) + a monthly BLR envelope line; actuals **solely via the standard Budget spend join point** (split-ready by construction — adopts TX-SPLIT automatically later, zero change); month-attribution memo convention ("covered by June") **display-only**; carryover shown as prior-month **context only — no carryover accounting, no Available-for-Goals derivation, no Extra-to-goals allocation** (all gated in the Budget-Identity Change). Close reporting = one **balance-free attestation line** ("Extra envelope reviewed: within budget / variance-noted"). **Zero new tables, zero cash-math, zero runModel/WD/income coupling**; a static test asserts the module derives no "Available"/"Free" figure. **Wendy confirms the Budget-surface changes before build.** The identity 20% (OS *derives* Available-for-Goals / replaces the hand-balanced spreadsheet) **stays the gated Budget-Identity Change (legacy 5G-3)** — extraction + L2 + A2 actuals + Wendy inputs.
- **P3b-2 Entry Ergonomics + Display** — 5E-11 category typeahead / payee memory / account ordering; REG-4 uncategorized count/filter; the UX rider set (FLOW-2/FLOW-1/WK-1/REG-1/SYS-2; rider REG-2). *True shed-first slice.*
- Same WIP=1 `index.html` lane. Non-scope: Weekly-Model cash-math; mobile layout (5H). Deps: TX-1 taxonomy spec cleared. Light spec review of the taxonomy slice. The **visibility trio** rides the first post-freeze slice (F-12).

**P3c — Diablos/GLP WD baseline correction + golden-master recapture = FIRST post-freeze code merge.**
Correct knowingly-understated projections (data, not `runModel` logic). Dep: golden-master recapture approval (D7 / A7). Head of the calendar-forced chain. Window: Aug 17–24.

**P4 — Holding lifecycle → hard invariant. 5G-1B (reframed, §4) → 5G-1E (folded as 1B-S4, SR-2).**
5G-1B holding→allocation→payout release lifecycle so the AMEX invariant can become two-sided. Deps: Diablos/GLP baseline (D7); the §4 release-event spec cleared per RG-1…RG-3; a **runModel freeze exception** (Adam). Calendar: **build start ≤ ~Sep 14 (Cal Wk 37); complete before DCL ~Cal Wk 41 (~Oct 17)**; miss-penalty graceful and documented (F-07). 5G-1E invariant hardening folds in as **1B-S4** with a demote-back valve (SR-2, §13). Window: post-freeze. **Review? Yes** (substitute chain, §11.2). **No pre-1B code phase precedes this [T-3]:** 1B consumes none of "Stage 1A"'s seams (its engine touch is a 1A.5-style carve-out at the release integration seam; its identity needs are the L3 ledger design *inside the 1B spec*). "Stage 1A" is dissolved — paper → freeze (Data-Extension & Identity Conventions); seams → Calc-Core Extraction Stage 1 (late Nov); tests → ride D7. Pre-1B prep is documentation + net-new green test scaffolding only (§8 bright line).

**P5 — Visibility + allocation foundation.**
Run-time visibility trio finishes already-specified items (rides the first P3b slice). **5G-2 Planned Outflows & Accruals** (prod DDL + app build; Mint seed) — **November default [T-1]** (after P3b-1; carries the ES-module infrastructure tax by design). Deps: obligation-taxonomy direction (D6/A8, ≤ Oct 1); Mint vendor/amount/date confirmation (external; the Mint Mobile monthly accrual = live wishlist ID 49); `showCashPlanning`; ES-module workflow. Charter now explicitly includes **annual renewals + sinking funds + the December-trip entry at launch**. **Dated-trip outflow routing** (the residual architectural concern behind the *completed* live wishlist item 34 — Appendix B): future/recurring dated trips route here as `planned_outflows`, **not** new registry goals (pre-4a registry goals trip the GM-3 eligible-set hard stop). Soft floor ~end Oct (F-10 / A13); with November placement the December-trip runway is ~4–5 weeks (thinner than A13's end-Oct floor), so **the A13 fallback (accepted 2026 miss, manual tracking, never a WD hand-edit) stays live**. Planned outflows are **never injected into WD/effectiveWD** (Do-Not-Touch; AT-2 no-Register-write posture); the legacy-5G-4a lookahead-gate language folds into the 5G-2 spec as display/advisory only. AF-6 version-skew guard becomes a 5G-2 day-one standard. **Conditional T-1 swap:** TX-SPLIT may take November (5G-2 → Jan/Feb 2027) under the four §3.0 preconditions. Window: post-freeze.

**P6 — Allocation, extraction, goal governance (critical-path back half). Honest 2027 dates [T-5].**
**Calc-Core Extraction Stage 1** (input construction · constants/config seam · explicit outputs, under golden masters) is scheduled **late Nov 2026** (§3.0 #10) — the code remnant of the dissolved "Stage 1A", and the common prefix of D10 (a)/(c). **Everything else in P6 is 2027:** **5G-3 Account Cash Allocation** (Q1 2027; derived Spoken-For / Free-to-Use **and Checking composition**) — spec **must define the relationship to the 5F-1 Cash Availability Engine** (one "available cash" number — the RM R20 trap); **blocked until the re-pin is standing law and the 5G-3 spec proves zero engine change** (§9), which Stage 1's explicit outputs make a real proof (5G-3 consumes named outputs, never reaches into `runModel`). Deps: 5G-2; 1B. **5G-3 is the authority for Spoken-For, Free-to-Use, and Truist Checking composition** — the Account Composition Visibility Rider (§18) is an *early read-only* down payment, never a substitute. → **Extraction Stage 2** (core move; Q1–Q2 2027) → **5G-4a** goal/funding-target data-model governance (read-side; registry history, transition matrix, scope-change runbook; D5/A11) → **5G-4b Dynamic Goal Registry** goal write capability (**highest-risk build**; waterfall-input writes; zero-outflow identity test) → **5G-5 Goal Intelligence & Timeline** (goal admin + management intelligence; renamed [T-4] — Fable proposed "Goal Admin & Intelligence"; adopted name per Adam is **Goal Intelligence & Timeline**). **Early read-only trajectory carve-out — GT-R (Goal Timeline/History) [T-4]:** projection-vs-actual drift, funded-progress trajectory, ETA movement over `goal_funding_snapshots` — display-only ES-module rider with **no registry writes, no engine change, no GM-3 eligible-set interaction**; plan-period-filtered from day one; ships as an interleave-class rider once enough history exists (realistically Q1 2027, earlier only in a genuine WIP=1 gap). Goal *management* intelligence (edits/reprioritization/what-if) needs 4a/4b and stays in 2027. **Review? Yes** for 5G-3, extraction, 5G-4a, 5G-4b.

**P7 — Plan Period / 2027 rollover (calendar-forced, parallel chain).**
Plan Period spec (design so 2027 is the first instance) → staging rehearsal → **production execution before 2027-01-09** (target ≤ Dec 28) → 2027 opening anchor via the generalized E2 pattern. **Minimum 2027 execution scope** now includes the full **seven-object `week_num` inventory** (§14 AF-2), per-period week-CHECK relaxation, parameterized year-pins, per-year engine constants. **Extraction is the preferred prerequisite** (§9); the **extraction-vs-rollover calendar-risk gate D10** (with **option (c)** pending A16, §13 SR-3) decides if extraction must complete first. AF-10 staging-fixture cleanup + schema re-sync attaches to the rehearsal prep. **Review? Yes** (highest blast radius).

**P8 — Audit tiers, later hardening, data-feature ladder.**
`financial_audit_log` (L2, trigger-driven) at 5J or pull-forward on the third owner correction/quarter (D8/A10) → gates the **Budget-Identity Change (legacy 5G-3)**. **L3 domain event ledger — rides 5G-1B** (likely *delivered by* 1B branch (b), §4); not speculative. Merged Close/Goal-Admin hardening (file→schema) after ≥3 stable closes (5G-6). **Broad application modernization (Register/Budget/view-layer modularization) — post-2027-rollover, trigger-based** (§9); not a 2026 phase. **Edge Function / server-side mediation layer** — elevated to the **first post-rollover platform-enablement item (early 2027)**, before OAuth / auto-balance ingestion / server-mediated AI (SR-4 / A17; §13). **TX-SPLIT (Split Transaction Foundation) is pulled OUT of the old 5I ladder position** and is now the **first post-rollover build (Jan 2027, §3.0 #12 [T-1])** — sidecar `transaction_splits` (no `transactions` DDL; Do-Not-Touch preserved), sum-of-splits invariant, Register split editor (Wendy-confirmed), splits-else-parent at the single Budget join point, parent-level Clr/balance, REIMB excluded v1, certified-month edits bound to the correction-evidence discipline, staging gate + prod DDL package. **December is never a build slot** (rollover corridor). Transfers (5K) → Import Readiness (splits land before it by construction) → Horizons. **5H mobile quick-add + mobile usability** (live `wishlist_items` ID 39 "make the mobile version better"; FLOW-4/REG-5) after the 5D-2 "Transactions desktop-only" reversal.

---

## 4. 5G-1B reframing (controlling definition)

*Reproduced from Fable review §4.1 (the review baseline that substitutes for an in-freeze Fable review — §11.2). Dollar figures are neutralized here per the balance-free rule; the correction-row values live in the approved Value Card and local execution copies only.*

**Phase name:** **5G-1B — Holding → Allocation → Payout Event Lifecycle.**
**One-sentence objective:** make a holding-funded obligation's full life — funded progress accumulation, held allocation, release/payout, and post-payout state — first-class, durable, and reconcilable, so the AMEX holding invariant can become two-sided (1B-S4 / legacy 5G-1E) and the accepted AMEX offset variance can expire.

**Why the old scoping is wrong (F-01, now executed posture):** after Saturday's Phase-2 revokes there is *no* sanctioned write path for release records: snapshot table INS/UPD revoked; direct snapshot RPC revoked; the wrapper writes only the server-derived eligible nine at closeout (`source='reconciliation'`); Option B validates against the eligible nine and rejects excluded goals — and `wewe_rccl` / `wewe_dcl` are excluded. The Week-5 `wewe_*` correction rows are otherwise permanent fossils every future validator special-cases.

**Specification scope (the freeze-window spec must define):**
1. **Release-event semantics** — what a release *is* (intent vs execution), its relation to `funded_amount` as *cumulative progress* (payout does **not** reset progress — 5G-1C-2.1's explicit doctrine), and the terminal treatment of the Week-5 `wewe_*` correction rows.
2. **The write surface (the P0 decision), choosing explicitly:**
   - **(a) a new governed write surface** — e.g. an owner-only `record_holding_release` SECURITY DEFINER RPC + release table/columns (DDL + grant slice amending the post-Gate-C posture under its own staging gate), or
   - **(b) the L3 domain funding-event ledger** — releases recorded as append-only domain events; snapshot rows untouched; the ledger the roadmap says "rides 1B" gets its forcing function.
   - **Recommendation to the spec author: branch (b)** — it matches the one-append-only-convention doctrine (C2), gives the durable transfer identity the `weekly_tasks` positional-keying defect already demonstrated (resolved cosmetically at `db2704f`; identity still positional), avoids re-opening the just-locked snapshot grant matrix, and leaves the wrapper contract byte-stable. Branch (a) is acceptable only if the spec shows the ledger cannot serve reconciliation needs. Either branch: the spec must show the post-Gate-C grant matrix before/after.
3. **Eligible-set / monotonicity boundary** — pre-declare that release-bearing (excluded) goals never enter the wrapper's eligible nine; the wrapper's non-decrease rule stays a wrapper policy (AR A3), *never* hardened into a table constraint the release path would violate.
4. **Model/engine interaction** — how releases surface in the weekly model (holding balance drawdown, "Transfers to execute" treatment, Funding Plan display), sized as a **runModel freeze exception** with named call sites (1A.5 pattern: carve-out at the integration seam, not internal rewrites).
5. **Reconciliation & close interaction** — release events vs the weekly closeout (releases are not closeout writes); accepted-variance register entry expiry; statement attestation tie-in for the AMEX card.
6. **Corrections & lifecycle management** — how a wrong release is corrected (append a reversing event; never edit history), reopen interaction (none — releases are not certification records), and Gate E posture if a release correction would cascade.
7. **Operational controls** — owner-only writes; RLS/grant matrix; evidence discipline (balance-free committed artifacts; values in local execution copies); runbook for the two real payouts (RCCL ~Cal Wk 30 — retroactive by the time 1B lands, mid-trip; DCL ~Cal Wk 41 — the live deadline).
8. **Downstream contracts** — exactly what 1B-S4 / 5G-1E consumes (a queryable release state making the AMEX invariant two-sided) and what 5G-3 reads for Spoken-For on the AMEX holding.

**Implementation scope:** the chosen write surface (DDL/RPC/grants staging-first with preflight/validation/rollback + a real-caller staging matrix in the Gate-2 mold), the engine seam under the approved freeze exception, UI surfacing (holding rows show held → released), retroactive RCCL release entry, DCL live entry, golden-master recapture *only* if engine outputs change (Adam approval required), tests (static + e2e for the release path).

**Prerequisites (hard):** 5G-1D complete incl. Phase-2 revokes + proofs; Diablos/GLP WD baseline corrected + golden masters recaptured (D7) so 1B's masters are captured once, on a correct baseline; the 1B spec cleared per the review gate below; runModel freeze-exception approval (Adam); **DR-1 closed** (blocks all post-5G-1D implementation).

**Non-goals:** general goal CRUD/reprioritization (5G-4b); physical funding-target unification (4a spec outcome); the L2 row-mutation audit log (D8; distinct tier — do not conflate with the L3 ledger); any change to the Week-5 opening anchor; hard AMEX invariant enforcement (that is 1B-S4 / 5G-1E, consuming 1B); Budget-identity change; any 5G-2 planned-outflows build.

**Review gates:**
- **RG-1 (spec):** drafted during the freeze (first in queue) → ChatGPT adversarial challenge + conformance check against this §4 (Aug 11–17) → Adam approval. *Fable review is not available (access ends Jul 19); do not hold the phase for it. If access resumes, a Fable pass may be added without moving build start.*
- **RG-2 (staging):** real-caller acceptance matrix (grant rejects, owner-only, correction/reversal, idempotency, atomicity) green on staging; teardown/ungrant/validation.
- **RG-3 (production):** own Adam-gated activation sitting (preflight / restore point / migrate / validate / grant), operator-package style.

**Acceptance boundaries (phase complete when):** DCL payout recorded through the new path with reconciled AMEX statement attestation; RCCL retroactively recorded; the accepted AMEX-offset variance entry is expired from the register; the Week-5 `wewe_*` rows have their documented terminal disposition; 1B-S4 / 5G-1E is unblocked with a queryable release state; no snapshot-layer grant weakened; wrapper/Option B contracts byte-unchanged unless the spec explicitly amended them under review.

**Sizing honesty:** schema + grant + engine + ops slice with three gates — deliberately *not* "tightly, like 1A.5." Calendar: build start ≤ ~Sep 14 (Cal Wk 37); complete before DCL ~Cal Wk 41 (~Oct 17); miss-penalty graceful and documented (F-07), never solved by an unreviewed rush fix.

**Open — progress-plane transfer identity (pointer, 2026-07-15):** see `docs/roadmap/amendment-2026-07-15-progress-plane-transfer-identity.md`.
- The **immediate adapter-level open-window goal-transfer netting/suppression control is IMPLEMENTED** (`15b372f`; `docs/phase-5g-1b-openwindow-netting-2026-07-15.md`) and complements 5G-1D snapshots.
- **Durable progress-plane obligation/execution identity remains OPEN.** The current correction is an adapter/projection guard, **NOT** an event-ledger solution — do not claim otherwise.
- The current **5G-1B `holding_events` scope covers RCCL/DCL only and does NOT include Adam IRA** (or any of the eligible nine), so it cannot serve as the progress-plane durable identity today.
- Future ownership **must include funding-cycle / `model_year` identity before the 2027 rollover**; **event identity, idempotency, and reversal linkage remain future work** (candidate: the L3 ledger that rides 1B, §8/P8).

---

## 5. Disaster Recovery Exit Gate — DR-1 (mandatory, pre-freeze)

**Mandatory pre-freeze exit gate.** The OS is the sole live system of record on a Free-plan database with no PITR, one operator, and (until this gate) a single-laptop backup+evidence posture entering an 18-day absence. **Deadline:** all items evidenced + signed by **Jul 28 EOD** (day before freeze). **Sign-off:** Adam, dated, in the committed balance-free gate record `docs/dr-exit-gate-2026-07.md`. **Blocking effect:** DR-1 failure **blocks all post-5G-1D implementation work** (no Register bundle, no 1B build, no 5G-2, no extraction) until closed; if items slip, closing DR-1 is the first Aug-11 action, before any code. It does **not** retro-block the Jul 18 activation sitting (own restore point + rollback tree) and does not block specs, planning, or Wendy's operational use.

| # | Domain | Required items (summary) |
|---|---|---|
| 1 | **Database recovery** | Fresh production `pg_dump` (custom-format, `--no-owner --no-acl`, public schema) after the last pre-freeze closeout (post-Wk-6 Jul 18; refresh post-Wk-7 Jul 25); `pg_restore --list` verified; chmod 600; SHA-256 recorded; **two encrypted off-device copies** (cloud + second physical device); retention cadence (8 weekly / 6 monthly + pre-close/pre-correction). **AF-4:** add a periodic `git bundle` of all branches to the same cadence + off-device set (removes GitHub as a single point for source recovery). |
| 2 | **Source recovery** | Post-merge `origin/main` == deployed build; activation branch pushed; repo cloneable from a second machine; the `git bundle` (AF-4); local evidence directory copied off-device encrypted. Pages loss is tolerable (static app; any host can serve `index.html`) — bundle + DNS manifest is a complete source-recovery floor. |
| 3 | **Environment / configuration recovery** | The secrets-free `docs/environment-manifest.md`: Supabase project refs (prod `usayoldrawwmjsmretin`, staging `pkwotgqivgaapwuqgwqb`) + `system_identifier`s; GitHub Pages + CNAME (`dashboard.herndons.us`) + DNS provider pointer; the final post-Phase-2 grant matrix (operator package §4) as the restore target; RLS role-model pointer; BUILD_TS convention; anon-key rotation procedure pointer. |
| 4 | **Credential recovery** | Owner MFA enrolled (**after the Jul 18 sitting, before departure — never mid-trip**) + recovery codes in two locations; backup-owner account created, login + role posture verified (financial write yes, `anthropic_key` no); Supabase org recovery email verified; password manager holds Supabase / GitHub / DSN / backup-encryption / domain entries. Gate-record lines carry no secrets. |
| 5 | **Operational runbooks** | `docs/restore-runbook.md` drafted: DB restore, source redeploy, environment restore from manifest, credential recovery, **the AF-1 full-project-loss auth re-link procedure**, **the AF-3 / A19 Supabase inactivity-pause unpause step**, derived-vs-observed doctrine; **one tabletop walkthrough** completed. |
| 6 | **Accepted variance** | Trip-window posture recorded: no dumps `Jul 29 – Aug 10` (unless remote-capable), expiry Aug 11; full staging **restore rehearsal** scheduled Aug 11–17 (may slide out of the gate, not out of the calendar). |

Absorbed wishlist items: 8 (owner MFA), 9 (backup owner), 18 (export & backup plan), P6 (anon-key rotation → runbook appendix). See the templates: `docs/dr-exit-gate-2026-07.md`, `docs/environment-manifest.md`, `docs/restore-runbook.md`.

---

## 6. Alaska operating model — deliberate skip with sequential catch-up

**Adopted posture (A4):** **deliberate skip with sequential catch-up.** Under the `Jul 29 – Aug 10` freeze, exactly **two** closeouts fall in-window: wk 8 (Sat Aug 1) and wk 9 (Sat Aug 8). Wk 7 (Sat Jul 25) closes at home, pre-freeze; catch-up depth is **2 weeks**, not 3.

- **Integrity:** skip-and-catch-up is the state 5G-1D was designed to handle — sequential, contiguity-enforced catch-up closeouts through the atomic wrapper, monotonic guards intact. A skipped week cannot half-close; it does not exist until closed. Remote closeouts exercise a two-week-old write path from untrusted networks with no supervised-correction ability (Option B is owner-only SQL-Editor work; mid-trip DB surgery violates the control posture).
- **Recovery complexity:** skip = zero during the trip; on return, one sitting (Aug 11–15) closes wk 8 then wk 9 sequentially from statement-reconstructed as-of-Saturday balances, then wk 10 closes normally Sat Aug 15.
- **Reopen implications:** none structural. Catch-up rows carry August `recorded_at` on earlier `week_num`s — benign under server-owned stamps; the first Close v1 record notes it (F-03).
- **Dependency on 5G-1D:** catch-up-through-the-wrapper assumes activation completed (P0). If activation slipped to post-freeze (§7 worst case), the same skip posture holds and the weeks close during the §7 recovery runway — the recommendation is stable across both worlds.
- **RCCL payout (~Aug 1, mid-trip):** cash leaves AMEX during the skip window; the wk-8 catch-up closeout captures it; the divergence is a standing accepted-variance entry that 1B expires.

**Trip rules (adopt with the posture):** no Option B corrections, no reopens, no Supabase dashboard writes from the road; read-only balance checks fine; Register data entry batches on return (desktop-only anyway); **if anything looks wrong from the road, write it down, don't touch it.**

**Catch-up sequence (Aug 11–15):** wk 8 closeout → wk 9 closeout (sequential, from statement-reconstructed as-of-Saturday balances) → wk 10 normal Sat Aug 15 → first **Monthly Close v1 (July data)** once wk 8 is durably closed (Aug 11–17).

**If Adam overrides to remote closeouts** (decision by Jul 25): preconditions = laptop + ≥1 hr reliable connectivity per sitting; bank balance access; **abort-to-skip on any anomaly** (never troubleshoot remotely); still no corrections/reopens mid-trip.

---

## 7. 5G-1D activation contingency annex (assume the Saturday sitting hard-stops)

*Reproduced from Fable review §8. Adopted before the Jul 18 sitting (A5).* Design fact that makes every branch operable: **at every stop point exactly one closeout write path remains available** — pre-merge stops leave the old RPC + old browser; post-merge stops leave the wrapper live with the old RPC still granted as fallback. No stop state strands the household without a weekly closeout path. Keyed to the operator package's rollback tree:

| Stop point (package steps) | Safe operating mode | Week-6 reconciliation approach | Retry requirement |
|---|---|---|---|
| **Before Phase 1** (1–3: re-ground/preflight/validation fails) | Status quo ante — nothing granted, nothing written; old path fully live | **Defer the wk-6 closeout up to ~3 days** for a quick retry (late closeout of a completed week is operationally fine); past ~Jul 22, close wk 6 via the old RPC and accept wrapper repair post-activation (zero-snapshot repair is a tested G2 branch) | Full sitting re-run: re-ground, fresh adjunct preflight + 17/17 validation, MD5s, owner check, all four approval gates |
| **After Phase 1, before merge** (4–5) | Grant rollback A (wrapper/Option B → inert); old path live | Same as above | Same, from step 3 |
| **After merge/deploy, before closeout** (6–8: Pages failure, BUILD_TS wrong, browser error) | Grant rollback A + browser revert (revert merge on `main` → redeploy pre-activation build); old path live | Same as above | Same + fresh deploy verification (step 6–7) |
| **After closeout, before Phase 2** (9–11) — *most delicate* | **Wrapper live + granted; Week-6 written through it; old RPC still granted as fallback.** Operate normally on the wrapper. **Week-6 freeze box holds** (no Option B / reopen / mutation of wk-6) until the retry completes Proofs A+B. The Gate-C lockdown is absent → the F-09 close-basis exposure exists: record as an accepted variance until Phase 2 completes | Week 6 is closed; wk 7 closes normally Jul 25 through the wrapper | **Short supervised sitting (~30–60 min), steps 12–18 only** (revokes + validation + browser verify + proofs), any day Jul 19–28; before-image freshness re-verified |
| **After Phase 2** (12–17: proof failure, stale-write anomaly) | Per the hard-stop matrix: investigate; grant rollback A + browser revert restores old-RPC operation if needed; a stale write post-revoke escalates (should be impossible) | Week 6 closed; corrections wait for a clean proof pass | Root-cause first; re-run steps 13–17 |

**Retry windows:** Jul 19–23 weekday evening (short sitting for post-closeout stops; full re-run for early stops) · **Sat Jul 25 — the natural combined sitting** (complete/redo activation + wk-6 catch-up if deferred + wk-7 closeout) · final go/no-go **Jul 27–28**. The Jul-29 freeze start (vs the stale Jul 24) is what makes this runway exist — five extra working days of contingency margin.

**Hard fallback (no retry succeeds by Jul 28):** activation defers post-freeze per the readiness package's standing default. Pre-freeze plan collapses to DR-1 + specs (DR-1 still signs Jul 28 — the dump captures whatever the last pre-freeze state is). Weeks 6–10 accumulate (old-RPC closeouts where taken; skipped otherwise) and close/repair sequentially at post-freeze activation. Post-freeze order rewrites to: **activation + catch-up/repair first (Aug 11–16)** → July close slides ~1 week (≈Aug 18–24) → Diablos/GLP → **1B (drop-dead Sep 14 unchanged — the buffer thins; the Register bundle sheds first)**. Close v1 remains the next phase in every branch.

**Work that stops on a hard-stop:** Phase-2 revokes + proofs (until retry); Gate-C-dependent posture assertions; any post-5G-1D phase start. **Work that continues:** DR-1, all P2 specs, docs/governance, Wendy's Register/Budget use, weekly closeouts via the surviving path.

**Documentation required on a hard-stop:** a dated hard-stop record (stop step; matrix row triggered; verbatim evidence; rollback actions; retry plan + window), committed balance-free; CODEX_STATUS banner updated same day; this roadmap's P0 annotated "Gate D decided; execution pending retry"; a line appended to `docs/execution-ledger.md`.

**Roadmap effects, quantified:** each week of activation slip past Jul 25 pushes the first close ~1 week; 1B is unaffected until activation slips past ~Aug 20, after which discretionary work sheds in order (Register bundle → visibility trio → 5G-2 prep). No slip scenario reaches the DCL bound before shedding absorbs it.

---

## 8. WIP guidance

**WIP = 1 for code-bearing phases — standing policy.** A code-bearing phase is anything that merges application/SQL behavior to `main` (Register bundle, visibility trio, 1B, 5G-2+, extraction slices). One in flight at a time; "lanes" (§10) are dependency groupings, not concurrent tracks. The **`index.html` collision set** is named: Register bundle · visibility trio · 1B browser surfaces · closeout-builder extraction — never two in flight; the calendar-forced chain (Diablos/GLP → 1B → 1B-S4) always outranks discretionary members, which shed first (Register bundle first; within it, P3b-2 before P3b-1 — SR-1).

**Proceeds in parallel, always (non-code):** specification drafting and reviews; architecture/design docs; Close v1 checklist *runs* (zero-code by design); DR-1/recovery operations (dumps, MFA, runbooks, rehearsals); independent reviews; evidence/closeout documentation; Wendy's operational use; owner decisions.
**Parallel with cautions:** test-infrastructure groundwork (harness migration prep, golden-master tooling — no behavior change; branch-held during freeze; merges queue behind the active code phase); staging-only rehearsals *belonging to the active phase* (a staging rehearsal for a queued phase is spec validation only, never a build head start); one-time OP items interleave only when the active phase is between merges.
**Explicitly not parallel:** two `index.html`-touching phases; any 5G merge during the freeze; spec *approval* treated as build authorization (separate gates, per standing law).

**Pre-1B preparation boundary (bright line; adopted verbatim, T-3 / Amendment 1 §2):**
> **Pre-1B preparation may produce only artifacts that (1) change no file the application loads at runtime — `index.html`, any loaded module, or SQL applied to any environment — and (2) change no test's expected output. Documents and net-new green test scaffolding are inside the line; every edit to production-loaded code, however mechanical or "safe," is outside it and belongs to a gated phase (1B's carve-out, TX-SPLIT, or Calc-Core Extraction Stage 1). If a preparation task cannot proceed without touching production-loaded code, the task stops and the need is recorded in the relevant spec instead.**

Corollaries: prep artifacts confer **no build authorization** (specs ≠ approval); prep never displaces the calendar chain; if prep grows beyond documents + fixtures, that growth **is** the signal it has become an unauthorized architecture phase — stop and re-gate. This is why **there is no separate "Architecture Enablement" code phase**: the paper is freeze docs (Data-Extension & Identity Conventions), the seams are Calc-Core Extraction Stage 1 (late Nov), the tests ride D7.

---

## 9. Calculation-core taxonomy & extraction charter (canonical vocabulary + folded amendment)

**Naming rule:** new-numbering ordinals only for product phases; named phases carry no ordinal; legacy ordinals appear only as parenthetical provenance.

| Canonical term | Means | Retires / notes |
|---|---|---|
| **5G-2 Planned Outflows Foundation** | The `planned_outflows`/`outflow_events` product phase (staging-validated 2026-07-08) | legacy "5G-1" |
| **5G-3 Cash Allocation** | Derived Spoken-For / Free-to-Use (spec must define the CAE relationship) | legacy "5G-2" |
| **Calc-Core Extraction** | The extraction *phase* (canonical P6) | **"5G-2.5" retired** except as "(legacy 5G-2.5)" provenance |
| **Calculation core** | The extraction *target code surface*: `runModel` + `reconEffectiveWD`, explicit model-input construction, explicit outputs incl. `ruleAudit`, goal-registry/budget-rule domain logic, CAE/AMEX-lookahead, constants/config seam; closeout builders only post-5G-1D-stability | A code surface, never a phase name |
| **"Planning engine"** | **Retired.** Where it occurs in conversation it means the calculation core | Do not introduce into governance docs |
| **Budget-Identity Change (legacy 5G-3)** | The Available-for-Goals-becomes-derived change; P8-adjacent; gated on L2 + A2 income actuals + Wendy inputs + extraction | Always written with the "legacy" qualifier |
| **Monthly Close v1** (reframed 5G-1F) | File-based certify-and-detect-divergence close | Distinct from **5G-6 Close hardening** (schema-tier, after ≥3 stable closes) |
| **Modularization** | *Only* the post-2027-rollover, trigger-based Register/Budget/view-layer modernization (P8, merged 5L/5I-4 label) | **Never** used for the extraction |

**Legacy fold-in resolution (closes the phase-status open item):** legacy 5G-2.5 → Calc-Core Extraction (P6) · legacy 5G-3 → Budget-Identity Change (P8-adjacent, gates above) · legacy 5G-4a (AMEX-lookahead set-aside gate; derived-not-stored set-asides) → the gate language folds into the **5G-2 spec** (transfer-recommendation control) and the derived-not-stored rule into the **5G-3 spec** · legacy 5G-4b (zero-outflow identity test; earmark adapter into the 5F-1 engine, input layer only) → **new 5G-4b**, identity test capturable at extraction · legacy 5G-5 (spreadsheet/Quicken retirement) → residual = **D1 archival policy + docs cleanup**; no phase.

**AGENTS.md re-pin wording (the F-05 patch; blocking prerequisite to 5G-3; prepared in the A6 patch set):**
- Standing Rules bullet → "Before the **Budget-Identity Change (legacy 5G-3)** and before **5G-4a/4b** (goal data-model and write phases), complete the **Calc-Core Extraction** under golden-master / characterization tests. New-numbering **5G-3 Cash Allocation** may proceed pre-extraction **only if its spec proves zero engine change**."
- Do Not Touch bullet → "runModel internals: **frozen until the Calc-Core Extraction phase**; move-only during extraction under golden-master identity; modifiable after extraction per approved spec only. Freeze exceptions require explicit Adam approval per incident."

**Extraction charter (folded from the calc-core amendment — normative):**
- **Architectural verdict:** `index.html` is a material and rising maintainability / change-safety risk. The risk concentrates in the financial engine, implicit global inputs, freeze-exception accretion, and test coupling to source shape — **not** file size or immediate-mode rendering (neither is a rewrite driver).
- **Disposition:** keep the existing extraction slot (P6); widen its charter; do **not** create a broad 2026 modularization phase. New 5G code continues to land as ES modules in separate files.
- **Extraction spec must cover:** (1) shared pure utilities; (2) explicit model-input construction (no direct mutable-global reads — implicit inputs become a named constructed contract); (3) explicit engine outputs incl. `ruleAudit`; (4) goal-registry and budget-rule domain logic; (5) CAE/AMEX-lookahead under behavioral identity; (6) `runModel` + `reconEffectiveWD`; (7) reconciliation payload / closeout builders **only after 5G-1D is complete and stable**; (8) **constants/config as the controlled seam for Plan Period / rollover** (OP_FL, MIN_XFR, lookahead depth, seed thresholds, `START_*`, PAYCHECK_WKS, WD literals externalized to versioned config read at model init) — see §14 (TD-8/P1 verification: `START_CHK`/`START_SAV` remain hardcoded at `index.html:889`, so this seam is the live home for auto-derive/re-baseline); (9) test-harness migration (module loading, HTTP-based E2E, golden-master expansion) as a **prerequisite, not cleanup**. Structure is illustrative, not locked.
- **Internal staging (SR-3):** **Stage 1** = harness + seams (test-harness migration, golden-master expansion, explicit input construction, explicit outputs, the constants/config seam) → **Stage 2** = core move (`runModel`/`reconEffectiveWD`/CAE relocation). Stage 1 is exactly what the 2027 rollover needs. **Scheduling (T-3, 2026-07-14):** Stage 1 is scheduled **late Nov 2026** (§3.0 #10) — it is the code remnant of the dissolved "Stage 1A" and the common prefix of D10 (a) and (c), so scheduling it costs nothing regardless of the Nov 15 decision. **Stage 2 is Q1–Q2 2027.** There is **no separate "Architecture Enablement" code phase**; the paper half is the freeze-window **Data-Extension & Identity Conventions** document (durable-ID ADRs for goals/obligations/holding-events/allocations; the transaction-extension/sidecar contract TX-SPLIT instantiates first; append-only event conventions; the model inputs/outputs inventory) — zero code, feeding 1B's L3 ledger design and the 5G-2/TX-SPLIT contracts.
- **Test posture:** new tests assert behavior over source-text shape; source-shape tests only where implementation shape is itself a contract, reason documented at the test; golden-master expected outputs are never edited to pass without Adam approval.
- **Module/API posture:** no framework, bundler, build step, TypeScript, or replatform; ES modules only; a transitional `window` bridge may expose only names required for inline handlers / bootstrapping / test compatibility and must not make internal domain functions public; a shared data-access wrapper for new code first, opportunistic legacy-`fetch` migration; relocating any environment-safety control requires explicit characterization + validation.
- **Explicit non-scope (deferred to the post-rollover, trigger-based track):** Register / Budget / reconciliation-UI extraction; render-system rewrite; modal/nav rewrite; inline-handler replacement; bulk `fetch` migration; CSS/HTML splitting; framework/build-tool adoption.
- **Rollover relationship:** extraction is the *preferred* prerequisite to the 2027 rollover (bounded constants/input seam). The **calendar-risk gate D10** (§12) governs a timing collision: (a) finish extraction first, (b) narrowly-scoped rollover against the existing engine with enhanced characterization + rollback, or **(c) — pending A16** — rollover against a *completed, golden-master-verified Stage 1* with Stage 2 deferred. **A partially/mid-moved core must never become the rollover base** (that prohibition stands under all options, including (c)).

---

## 10. Dependency graph & parallel lanes

```
5G-1D (activation) ──┬─► Monthly Close v1 ──► merged Close hardening (5G-6)
                     ├─► 5G-2 Planned Outflows ──► 5G-3 Cash Allocation
                     └─► 5G-4a scope-change contract
Diablos/GLP WD fix ──► 5G-1B releases ──┬─► 1B-S4 / 5G-1E hard invariant
                                        └─► L3 event ledger (rides 1B)
Calc-Core Extraction ─┬─► 5G-4a ──► 5G-4b ──► 5G-5
   (Stage 1 → Stage 2)├─► Budget-identity (legacy 5G-3)   [also needs A2 + Wendy + L2]
                      └─► (preferred) 2027 rollover execution   [Stage-1 seam serves rollover]
Plan Period spec ──► rollover staging rehearsal ──► rollover prod exec ──► 2027 anchor  [< 2027-01-09]
L2 audit log ──► Budget-identity change
```
- **Extraction must precede 5G-4** (5G-4a/4b need the testable waterfall API) and is the **preferred** prerequisite to the rollover (D10 decides if mandatory; option (c) lets a verified Stage 1 suffice). It does **not** block **5G-3** (derived allocation over 5G-2).
- **Application modularization** is neither a prerequisite nor a 2026 phase — post-2027-rollover, trigger-based. Only the narrow calc-core extraction is on the 2026 path.
- **5G-1B is time-sensitive** — DCL ~Cal Wk 41 is the completion deadline; the RCCL ~Cal Wk 30 payout starts the AMEX divergence clock (inside the freeze).
- **Month-end close depends on 5G-1D** (fully-closed weekly predicate), not on account allocation (5G-3); Close v1 is file-based over weekly primitives.
- **TX-1 / Register data quality is independent** of 5G-2/5G-3 (data-integrity lane); it informs 5G-2's taxonomy but does not block it.

**Lanes (dependency taxonomy, NOT concurrent tracks — WIP=1, §8):**
1. **Operational cash-planning lane:** 5G-1D → Monthly Close v1 → 5G-2 → 5G-3 → 5G-4a/4b/5. *Sync:* must not advance past 5G-4 until extraction lands; 5G-3 waits on 5G-2.
2. **Data-integrity / workflow lane:** DR-1 floor → Register/TX-1 bundle (P3b-1/P3b-2) → Diablos/GLP WD fix → 5G-1B → 1B-S4 → L2 audit log → 5H. *Sync:* 1B needs the WD fix; 1B-S4 needs 1B; Budget-identity change needs L2.
3. **Architecture / test lane:** calc-core extraction (harness migration + golden masters + seams; Stage 1 → Stage 2) → Plan Period spec → 2027 rollover rehearsal/execution. *Sync (critical):* extraction gates 5G-4 (lane 1) and is the preferred gate for rollover; the rollover amends 5G-1D-frozen objects — that migration authority (D-11) must be resolved on paper before lane-3 touches lane-1's frozen contracts.

---

## 11. Schedule, freeze controls, and review chain

### 11.1 Milestones

| Milestone | Date | Notes |
|---|---|---|
| This review adopted; Claude Code revision task runs | **Jul 14–16** | While Fable is reachable (ends **Jul 19**) |
| Activation sitting (P0) | **Sat Jul 18** | Contingency annex (§7) + skip posture (§6) adopted first |
| DR-1 items execute; MFA post-sitting | Jul 18–27 | §5 |
| Wk-7 closeout; activation-retry slot if needed | **Sat Jul 25** | §7 |
| **DR-1 sign-off; docs patches landed (re-pin, freeze dates); final pre-freeze push** | **Jul 28** | Hard gate |
| Freeze (specs only; 1B spec first; zero routine pushes) | **Jul 29 – Aug 10** | Weeks 8–9 skipped (§6) |
| Catch-up closeouts; spec approvals; 1B spec ChatGPT challenge + §4 conformance; restore rehearsal | **Aug 11–15** | |
| First Monthly Close v1 (July data) | **Aug 11–17** | After wk 8 durably closed |
| 5G-1B specification complete (approved) | **≤ Aug 17** | Drafted in freeze; approved on return |
| Diablos/GLP fix = first code merge (D7) | **Aug 17–24** | Head of the calendar chain |
| August close | ~Sep 1–7 | Second iteration, cleaner data |
| **5G-1B build start** | **target ~Sep 1; drop-dead Sep 14 (Cal Wk 37)** | Register bundle sheds first if contended |
| 5G-1B build completion (incl. staging gate + activation) | **≤ ~Oct 10; hard bound DCL ~Cal Wk 41 (~Oct 17)** | Then 1B-S4 |
| 5G-2 build (Mint confirmed; D6 decided; wishlist-34 routed) | **~Oct, soft floor end-Oct** | |
| Plan Period spec approved | **~Nov 1** | |
| D10 + D-11 decided (rollover authority over frozen objects) | **~Nov 15** | The "2027 rollover authority" milestone |
| Rollover staging rehearsal | **~mid-Dec** | AF-10 fixture cleanup + schema re-sync attaches here |
| Rollover production execution + 2027 anchor | **≤ Dec 28 target; hard 2027-01-09** | |

### 11.2 Fable-availability constraint & substitute review chain

Nothing after **Jul 19** may depend on Fable. Front-loaded here: the 1B review baseline (§4), the DR gate (§5), the contingency annex (§7), the taxonomy (§9). **Substitute chain for later reviews (1B spec, 5G-3 CAE relationship, extraction spec):** ChatGPT adversarial challenge + conformance against the acceptance boundaries this document fixes + Adam approval (A14). If Fable access resumes, reviews may be added opportunistically **without moving any date**.

### 11.3 Freeze controls (`Jul 29 – Aug 10`)

The freeze is a **controlled repository-stability period, not a total personal-work blackout**:
- **No routine pushes or merges to `main`.** Operationalized as **zero pushes to `main` except two named exception classes**, each with a documented reason + post-push live smoke: (1) an **emergency production fix** (explicit justification, its own gate, post-push live smoke); (2) an **Adam-discretion low-risk item that passed its own gate** (non-5G; no schema/grant/cash-model/workflow-cutover change; **branch-held by default**; WIP=1 still applies — the load-failure banner is the canonical example). Rationale: `main` auto-deploys and the pre-commit hook stamps `BUILD_TS` unless `--no-verify`, so even a docs push is a deploy event.
- **Local and feature-branch work is permitted.** Docs, planning, architecture review, and research are **encouraged** — the freeze *is* the P2 spec-drafting window.
- **Specs are agent-drafted during the freeze; owner approval is an Aug-11 activity** (F-13). Spec approval is never build authorization.
- Normal merges resume Aug 11 unless a documented exception. The freeze governs the **repository, not operations** — Wendy's live use and (if chosen) remote closeouts are unaffected by freeze rules.

---

## 12. Decision register & Adam decision list

**Adoption is not blocked by any open decision.** The roadmap's own adoption is **D-ADOPT → Resolved (A1, 2026-07-14)**; every other decision below governs a *downstream* phase, not the adoption of this Plan. Each decision carries one of four states:
- **Adopted now** — decided; in force (e.g. A1, A2, A4, A5, A13, A14, A15, A17, A18).
- **Pending (decide-by)** — awaiting Adam by a dated deadline; a **default applies if undecided** (e.g. A6 ≤ Jul 28, A7 ≤ Aug 11, A8/A13 ≤ Oct 1, A19 ≤ Jul 25).
- **Future decision gate** — deliberately deferred to a later point with **no binding default** (e.g. A9 = D10 + D-11 ~Nov 15; A16 option (c) authorized-but-not-selected; the W-decisions in Appendix B.5).
- **Default applies if undecided** — the roadmap proceeds on the stated default until Adam rules (marked in the tables).

No unresolved A-list or W-list item is a precondition for committing or adopting this documentation package. Where a decision blocks a *downstream phase* (e.g. A3/DR-1 blocks post-5G-1D implementation, A7 blocks the first post-freeze code merge), that block is on the phase, not on the roadmap.

### 12.1 Decision register (§K — unresolved owner decisions)

- **D-ADOPT:** adopt this living roadmap as the canonical post-5G-1D plan. **Resolved — A1, 2026-07-14.**
- **D-STATUS / P1b:** apply the docs-only currency/fold-in patch set (re-pin, freeze dates, fold-in table, CODEX_STATUS currency). Prepared under **A6**; awaiting Adam approval before commit/push.
- **D1 — Quicken archival policy** (verify clean export; retention/storage off-device encrypted; one-time-reference vs periodic source). Decide-by year-end; default archive untouched.
- **D5 — Physical funding-target unification** at 5G-4a (single entity vs shared-taxonomy separate) — spec-gated either way. Decide-by ~Nov–Dec (A11).
- **D6 — Obligations end-state** (`budget_rules` absolute-mode migration / dated-obligation adapter / WD hand-maintained). Decide-by ≤ Oct 1 (A8); default WD hand-maintained blocks the 5G-2 build.
- **D7 — Golden-master recapture approval** for the Diablos/GLP WD baseline correction. Decide-by ≤ Aug 11 (A7); blocks the first post-freeze code merge.
- **D8 — L2 audit-log timing** (5J vs pull-forward on the third correction/quarter). On trigger (A10).
- **D10 — Extraction-vs-rollover calendar-risk gate.** Options (a) extraction-first, (b) narrowly-scoped rollover against the existing engine, **(c) rollover against a completed golden-master-verified Stage 1 with Stage 2 deferred — available only if A16 adopts it**. No default; a partial/mid-moved core may never be the rollover base. Decide-by ~Nov 15 (A9).
- **D-11 (new) — Migration authority over 5G-1D-frozen objects.** Explicit authority to, at rollover: re-key `weekly_reconciliations` (add `model_year`), raise the wrapper's `model_year=2026` pin, relax the snapshot week-CHECK, and re-key/archive the full seven-object `week_num` inventory (§14 AF-2). Decide-by ~Nov 15 with D10 (A9). No default — must be resolved on paper before lane-3 touches lane-1's frozen contracts. **Scope addition (2026-07-22, per the Step-5 independent implementation review):** D-11 explicitly includes *"design and implement server-authoritative historical-week immutability enforcement for reconciled and prior-period weeks, including privileged correction authority."* Rationale: the Step-5 client-side immutable-week guard is accident-protection only — it derives reconciliation state from the loaded client dataset (fails open if reconciliation data is unavailable) and cannot bind non-browser writers; the durable lock belongs at the database tier, alongside the same migration that re-keys the `week_num` surface. Documented only — NOT implemented in Step 5; the Step-5 evidence record (`docs/phase-5g-1d-week1-2-legacy-binding-2026-07-21.md`) carries the residual-finding register (F5/F6) that this scope addition closes.

### 12.2 Adam decision list (consolidated; decide-by; defaults)

| # | Decision | Decide by | Default | Status |
|---|---|---|---|---|
| A1 | Adopt the FINAL roadmap as amended (→ APPROVED — controlling); authorize the revision task | Jul 16 | none | **ADOPTED 2026-07-14** |
| A2 | Confirm freeze dates `Jul 29 – Aug 10` + travel dates | Jul 16 | charter dates | **CONFIRMED 2026-07-14** |
| A3 | DR-1 gate: adopt + execute + sign | Jul 28 | none (hard gate) | **ADOPTED** (execute by Jul 28) |
| A4 | Alaska closeout posture | Jul 25 | skip + sequential catch-up | **ADOPTED (skip + catch-up)** |
| A5 | Adopt the §7 contingency annex | Jul 17 | annex as written | **ADOPTED** |
| A6 | Approve the docs patch set (re-pin, freeze dates, fold-in table, CODEX_STATUS currency) | Jul 28 or first Aug-11 action | re-pin still blocks 5G-3 | **PREPARED — awaiting approval** |
| A7 | (D7) Golden-master recapture for Diablos/GLP | ≤ Aug 11 | blocks first post-freeze merge | Open |
| A8 | (D6) Obligations end-state | ≤ Oct 1 | blocks 5G-2 build | Open |
| A9 | (D10 + **D-11**) extraction-vs-rollover gate + migration authority over frozen objects | ~Nov 15 | none by design | Open |
| A10 | (D8) L2 audit-log timing | on trigger | 5J unless 3rd-correction/quarter | Open |
| A11 | (D5) physical funding-target unification | at 4a spec (~Nov–Dec) | spec-gated | Open |
| A12 | (D1) Quicken archival policy | before year-end | archive untouched | Open |
| A13 | Dated-trip outflow routing — the *residual* concern behind the **completed** live item 34 (recurring/future dated trips → 5G-2 planned-outflow vs accepted 2026 miss; live item 34 stays DONE, not reopened) | ≤ Oct 1 | route residual to 5G-2 | **ADOPTED (route residual to 5G-2; do not reopen 34)** |
| A14 | 1B reviewer designation in Fable's absence | ≤ Aug 11 | ChatGPT challenge + §4 conformance | **ADOPTED** |
| A15 | (SR-1/SR-2) split Register bundle P3b-1/P3b-2; fold 5G-1E into 1B as demotable 1B-S4 | ≤ Aug 11 | adopt both | **ADOPTED** |
| A16 | (SR-3) add D10 option (c) — rollover against a completed verified Stage 1 | with D10 (~Nov 15) | not available unless adopted | **OPTION AUTHORIZED; decision deferred** |
| A17 | (SR-4) elevate Edge Function layer to first post-rollover early-2027 enabler | year-end planning | keep parked | **ADOPTED (placement)** |
| A18 | (DOC-1) single living roadmap now; DOC-2/DOC-3 later | Jul 16 / Aug 11 | adopt DOC-1 | **ADOPTED (DOC-1 now)** |
| A19 | (AF-3) verify Supabase inactivity-pause policy vs both projects; document unpause in runbook | ≤ Jul 25 | verify + document (no upgrade implied) | **ADOPTED — verification pending** |

**Wishlist-surfaced decisions (W-1 … W-8)** live in **Appendix B.5** — eight open owner decisions from the live-export reconciliation and the Roadmap UI Lite enhancement (W-8). They are part of this decision register by reference; no default is binding until Adam rules.

### 12.3 Targeted Sequencing decisions (T-1 … T-6, adopted 2026-07-14)

*Adopted from the Fable Targeted Sequencing Review + Amendment 1 (Boundary Clarifications) + Amendment 2 (Account Composition Scope), all 2026-07-14 (provenance: `docs/roadmap/archive-index.md`; decision-log entries recorded). These amend the sequence/§3.0, not the DCL or rollover chains.*

| # | Decision | Decide by | State |
|---|---|---|---|
| T-1 | TX-SPLIT placement — **default: 5G-2 November, TX-SPLIT January 2027 (first post-rollover build)**; conditional **November swap** (5G-2 → Jan/Feb) iff all four preconditions hold + decision-log entry (§3.0) | ≤ Oct 1 (with D6) | **Adopted (default); swap is a Future gate ≤ Oct 1** |
| T-2 | Fold **BUD-MX-lite → P3b-1.MX** (Misc/Extra Envelope v1; §3 P3b-1 + Amendment 1 §3); hard boundary vs the gated Budget-Identity Change. **Resolves W-3.** | ≤ Aug 11 (P3b-1 spec) | **Adopted** |
| T-3 | **Dissolve "Stage 1A"** — no separate Architecture Enablement code phase; paper → freeze (Data-Extension & Identity Conventions), seams → Calc-Core Extraction Stage 1 (late Nov), tests → D7; §8 bright line governs pre-1B prep | Now (freeze queue) | **Adopted** |
| T-4 | **5G-5 renamed "Goal Intelligence & Timeline"** (Fable proposed "Goal Admin & Intelligence"; Adam's adopted name governs) + **GT-R** early read-only Goal Timeline/History carve-out (interleave-class, plan-period-filtered, no registry writes) | Low urgency | **Adopted; GT-R rides a genuine WIP=1 gap only** |
| T-5 | Re-date **5G-4a / 5G-4b / full 5G-5 to 2027** explicitly (honesty change; no scope change) | With T-1 | **Adopted** |
| T-6 | Adopt the **Account Composition Visibility Rider** (§18) — visibility-rider naming (not `5G-3A`), AMEX Savings + Truist Savings supported, Truist Checking deferred to 5G-3, evidence classes, displayed equation + signed residual, durable/modeled labels, prohibited vocabulary, Accounts-drawer placement, post-1B earliest | Before any build of the card | **Adopted (as amended by Amendment 2)** |

**Protected chains (unchanged by T-1…T-6):** the DCL chain (1B ≤ Oct 17) and the rollover chain (execution ≤ Dec 28, hard 2027-01-09) remain calendar-forced and preempt every discretionary item; **no code-bearing architecture phase was introduced** (T-3).

---

## 13. Roadmap-structure changes (SR-1 … SR-5)

- **SR-1 (ADOPTED, A15) — Split the Register bundle (P3b).** P3b-1 Data Integrity (TX-1 categories/validation/uncategorized cleanup, FK audit 39, reimbursement decision) feeds close quality and **sheds last**; P3b-2 Entry Ergonomics + Display (5E-11 typeahead/payee/account-order, REG-4, UX rider set) is the **true shed-first slice**. Same WIP=1 lane; better shed economics. (See §3 P3b.)
- **SR-2 (ADOPTED, A15) — Fold 5G-1E into 5G-1B as final slice 1B-S4 "invariant hardening", with a demote-back valve.** Once §4's acceptance produces a queryable release state, promoting the AMEX advisory to a two-sided hard gate is a small same-context slice. **Valve:** if 1B runs long against the DCL bound, 1B-S4 demotes back to a separate fast-follow without holding the core 1B lifecycle phase open (the advisory posture is graceful over winter).
- **SR-3 (OPTION AUTHORIZED, A16; decision deferred to ~Nov 15) — Stage extraction internally + give D10 option (c).** Stage 1 (harness + seams incl. constants/config) before Stage 2 (core move). A completed, golden-master-verified Stage 1 is **not** the "partially completed extraction" the prohibition forbids. **Do not select option (c) now** — record it as an available November decision only; preserve the prohibition against a partially-moved core. (Amends the calc-core amendment's D10 option set.)
- **SR-4 (ADOPTED as placement, A17) — Elevate the Edge Function / server-side mediation layer** from indefinite backlog to the **first post-rollover platform-enablement item (early 2027)**, before OAuth (26), auto-balance ingestion (27), or server-mediated AI. It fixes the stored-key debt (AF-7) and is the precondition for any bank-data or AI integration. **Do not implement or specify it in this task.** (See §3 P8.)
- **SR-5 — Confirmations (no further changes):** the 5G-4a/4b split (write capability trails the data model); Monthly Close v1 as zero-code; 5J/5L merges; 5G-6 close hardening stays trigger-based (≥3 stable closes); 5H stays behind the 5D-2 reversal. Macro shape needs no third restructuring.

---

## 14. Recovery / rollover findings folded into the plan (AF-1 … AF-10)

- **AF-1 (P0 runbook content; zero code) — Auth re-link on restore.** DR restore points are **public-schema only**; Supabase's `auth` schema (auth.users, identities) is not captured, and authorization keys on `app_users.auth_user_id = auth.uid()`. In a full-project-loss scenario the rebuilt project issues **new auth UUIDs**; a successful data restore still produces **total lockout**. The restore runbook (DR-1 item 5) carries the re-link procedure (recreate authorized auth users → capture new UUIDs → `UPDATE app_users SET auth_user_id …` via SQL-editor/service-role, which bypasses RLS → verify `is_allowed_user()` and `is_owner()` true(Adam)/false(Wendy) → verify Wendy's role posture and the owner-only secret carve-out). Committed materials stay secrets-free. See `docs/restore-runbook.md`.
- **AF-2 (P1; Plan Period spec scope) — The rollover's `week_num` surface is larger than the roadmap said, and the failure mode is silent.** Verified seven-object bare/keyed `week_num` inventory (the four from synthesis §2.4 + three newly found):

  | Object | Current keying | Silent-overwrite risk | Required rollover disposition |
  |---|---|---|---|
  | `weekly_reconciliations` | **bare `week_num`** (no `model_year`) | **Yes** — 2027 wk-1 collides with 2026 wk-1 | Add `model_year`; re-key/archive |
  | `weekly_tasks` | **bare `week_num`**, PostgREST `merge-duplicates` write | **Yes — silent overwrite** of the 2026 row | Year-key / archive / replace |
  | `weekly_notes` | **bare `week_num`**, `merge-duplicates` write | **Yes — silent overwrite** | Year-key / archive / replace |
  | `model_week_overrides` | **bare `week_num`**, `merge-duplicates` write | **Yes — silent overwrite** | Year-key / archive / replace |
  | `cash_commitments` | `model_year` (DEFAULT 2026; RLS `WITH CHECK model_year=2026`) | No (pinned) — but 2027 needs the pin raised | Raise/parameterize the year pin |
  | `goal_funding_snapshots` | `UNIQUE(model_year, week_num, goal_id)`; `CHECK (week_num BETWEEN 1 AND 31)` | No — but the 31-week CHECK breaks a full 2027 year | Relax the week-CHECK per period |
  | `save_reconciliation_with_commitments` RPC | `p_model_year` param; raises on `model_year <> 2026` | No — but raises for 2027 | Parameterize the year pin |

  Every affected object requires a **year-keying, archival, or replacement disposition before rollover authorization** (D-11). The four bare/merge-duplicates objects are the silent-overwrite surface — a 2027 write would **not** collide loudly. The rollover rehearsal must **diff row counts per table**, not just the reconciliation path.
- **AF-3 (P1 to verify; A19) — Supabase Free-plan inactivity pause vs an 18-day absence.** Both projects are Free plan (no PITR). Free-tier projects have historically been **paused after ~1 week of API inactivity**; under the §6 skip posture with both operators traveling, production may see near-zero traffic Jul 29–Aug 10 and be paused on Aug 11 (recoverable via dashboard unpause, but the wrong catch-up-day surprise). **Verify the current pause policy against both prod and staging before departure; document the unpause step in `docs/restore-runbook.md`; do not represent the policy as verified until supported by current evidence; no plan upgrade is implied.**
- **AF-4 (P2; DR-1 refinement) — Source recovery single-account dependency.** Add a periodic `git bundle` of the repo (all branches) to the weekly dump cadence + off-device set (§5 item 1/2). Pages loss is tolerable; bundle + DNS manifest is a complete source-recovery floor.
- **AF-5 (P2; one page) — Operator-continuity card.** A balance-free `docs/operator-continuity-card.md` stored with the off-device backups: what the system is, where backups and passwords live, how to read current balances without operating the model, and who to contact (CPA / named technical contact). Rides DR-1 or the first close.
- **AF-6 (P2; rides existing work) — Stale-tab version skew.** A small version-skew guard (compare a fetched `BUILD_TS` on visibility/focus; show a "new version — reload" banner) joins the **visibility-trio slice** and becomes a **5G-2 day-one standard** for new write surfaces. No urgency before 5G-2's schema-bearing writes.
- **AF-7 (P3; annotation now) — `goals` table doubles as a KV store carrying a secret.** The Anthropic API key and `custom_task_meta` are stored as rows in `goals` (same pattern as the `misc.goal_sweep` Do-Not-Touch key), protected by a dedicated RLS carve-out. Recorded as named architectural debt; remediation rides **SR-4 / item 12** (Edge Function removes the key from the client) or a future owner-only `app_settings` table. Do not spend a 2026 slot on it.
- **AF-8 (P2; freeze-window docs work) — Production-execution ledger + never-rerun quarantine.** `docs/execution-ledger.md` — one appended line per SQL artifact ever run against production (date, file, commit, evidence link, rerunnable? yes/no). The DR operator's "what has touched prod" index and the close/audit tier's missing spine. The DOC-3 reorg later moves executed one-shots under `docs/sql/executed/` so the quarantine becomes structural.
- **AF-9 (P2; cheap) — Decision log.** `docs/decision-log.md` — append-only; date, decision, approver, evidence link — one line per **made** decision (registers track only *open* ones), seeded from the A-list as it resolves. Completes the audit ladder: L2 = row mutations, L3 = domain events, decision log = governance events.
- **AF-10 (P3) — Staging drift and retained fixtures.** Attach the Gate-2 retained Adam/Wendy staging fixture cleanup and a **"re-sync staging from prod schema baseline"** step to the **rollover rehearsal prep (P7)** so the rehearsal rehearses reality.

**Verified fact carried into the plan (TD-8 / P1, per §13.3 of the review):** `START_CHK` / `START_SAV` are **still hardcoded constants** (`index.html:889`) and remain the model base (`index.html:2268`); `reconEffectiveWD()` governs WD, not starting balances. The wishlist's "likely superseded by the 5F-1 reconciliation basis" hypothesis is **not** borne out — every reconciled week drifts the constants from reality. **TD-8/P1 remains a live item**, dispositioned into the extraction **constants/config seam** (§9 item 8) and the 2027 **re-baseline** (Plan Period). It is **not** closed as superseded. (Wishlist row updated accordingly — Appendix B.)

---

## 15. Deferred / non-sequenced (must not crowd out the canonical sequence)

Goal creation/editing & reprioritization (→ 5G-4b); recurring/multi-period goals (→ `planned_outflows`, not the registry); scenario/what-if & long-range forecasting (Horizon C, aspirational); AI recommendations (Horizon B, post-extraction, behind the Edge Function enabler); physical funding-target unification *build* (→ 5G-4a spec outcome); close schema/UI (→ after ≥3 file-based closes); L3 ledger speculative build (rides 5G-1B only); PITR/paid tier/alerting/close cockpit (explicit non-needs at current scale); broad application modernization (→ post-rollover); multi-currency/invoicing/multi-tenant/native-app (excluded). Security-hardening pass (backlog 13/14/15 CDN-SRI / CSP-XSS / token policy) parked before any Horizon A/B external integration; a CSP feasibility study is good freeze-window docs work. **None of these may pre-empt P0–P7.**

---

## 16. Documentation architecture (DOC-1 … DOC-4)

**Problem class:** operating state has lived in ≥3 hand-synchronized places (`AGENTS.md` "Current State", `CODEX_STATUS.md` banners + long dated supersedes-chains, `docs/phase-status.md`) and the roadmap spanned four layered "superseding-for-sequencing" documents. The Quicken staleness incident is what that architecture *does* under state change, not an editing lapse.

**Target model — four documents, one job each:**
1. **Law — `AGENTS.md`:** stable rules only (architecture, conventions, Do-Not-Touch, gates). Its volatile "Current State" section moves out over time (a pointer remains). **DOC-4:** structure the Do-Not-Touch list into *frozen code* / *protected data* / *protected process* categories so additions land with the right review reflex (prepared in the A6 patch set).
2. **State — `CODEX_STATUS.md`:** operating state, active phase + gate table, verified test baseline, next actions, and a history index (date → one line → closeout link). **DOC-2 slim-down** (target ≤ ~80 lines; the dated narrative sections duplicate the closeout docs) is adopted **at Adam's pace** (≤ Aug 11) — this task adds a currency banner + pointer, not a destructive rewrite, to avoid losing load-bearing content pre-review.
3. **History — the append-only evidence layer:** per-phase closeout docs (already working) + the AF-8 execution ledger (`docs/execution-ledger.md`) + the AF-9 decision log (`docs/decision-log.md`).
4. **Plan — one living canonical roadmap:** *this file*, revised in place, git history as changelog, prior layers archived (`docs/roadmap/archive-index.md`). **DOC-1 (A18) adopted now** — the revision produces the living document, **not** a fifth layer.

**DOC-3 — `docs/` physical reorg (post-5G-1D action; recorded, not executed here).** ~180 flat files mixing five artifact classes → `docs/{sql/{executed,},specs,runbooks,closeouts,reviews,roadmap}/`. **Do not move anything until 5G-1D closes** — the operator package references current paths. Execute Aug 11–17 (spec it during the freeze) with a path-redirect index for load-bearing cross-references. *Per A18, this task does not physically reorganize the docs/ tree; DOC-3 is recorded here as a post-5G-1D documentation-maintenance action.*

---

## 17. Roadmap UI Lite — Roadmap & Ideas (new future candidate; not authorized for implementation)

**One-sentence objective:** replace the current in-app Wishlist page with a significantly more useful **Roadmap & Ideas** experience — a lightweight first implementation that surfaces the roadmap for at-a-glance answers ("what's happening now, next, and why"), while preserving a path to a richer portfolio-management capability later.

**Architectural rule (non-negotiable):** `docs/roadmap/canonical-roadmap.md` remains the **single authoritative roadmap.** The application UI is a **presentation/read layer over that document — not an independently maintained roadmap.** The UI must derive its content from the living roadmap (parsed/generated), never fork it into an app-owned copy that can drift (this is exactly the staleness class the four-document model, §16, exists to prevent).

**Initial objectives (Lite scope — display/read-only):** current phase · next authorized phase · a 6–12-month roadmap view · phase status · dependencies · gates · Adam decision points · target dates · search · filtering · completed phases · deferred phases. **Retain the existing Wishlist as the Ideas / Backlog portion** of the same experience (the `wishlist_items` table stays the backlog store; Roadmap = the derived plan view, Ideas = the wishlist view).

**Recommended roadmap placement:** a **deferred future candidate**, **post-5G-1B / post-close-stability**. The Lite version is a **display-only ES-module slice** (visibility-trio pattern — no schema, no cash-model, no write path) that may interleave under **WIP=1** only once the calendar-forced chain (Diablos/GLP → 1B → 1B-S4) and the Register bundle (P3b) are clear. It is **never** ahead of a calendar-forced or data-integrity item. Not a 2026-critical item; no target date is assigned — placement/priority is a future Adam call (**W-8**, Appendix B.5).

**Dependencies:** (1) a **stable, machine-legible living roadmap** — this Lite view is only as good as the document's structure, so a light structural convention (phase headings, status/gate/decision fields) in `canonical-roadmap.md` is the real prerequisite; (2) no DB or auth dependency (read-only display); (3) sits behind the same WIP=1 `index.html` collision discipline (§8).

**Future Roadmap & Portfolio UI expansion (Horizon; explicitly not now):** the richer capability — editable portfolio management, cross-phase scheduling, effort/priority modeling, decision-log integration, burn-down/target-date tracking — is a **post-2027-rollover Horizon item**, trigger-based, behind the platform-enablement work (Edge Function SR-4). Roadmap UI Lite deliberately does **not** attempt this; it is the value-now floor under it.

**Relationship to Wishlist items 32, 33, 54:**
- **32 (reorder wishlist columns)** and **33 (drop a completed phase from the wishlist dropdown)** are **subsumed** by Roadmap UI Lite — the Wishlist-page redesign replaces those standalone tweaks; they should be delivered *inside* the Roadmap & Ideas experience rather than as isolated edits to the page being replaced (Appendix B updated).
- **54 (challenge the technical architecture)** is **related but distinct** — it is the recurring architecture-review governance trigger (Appendix B, W-5), not a feature of this UI; a Roadmap/Portfolio UI would *surface* governance/review state but does not perform the review.

**Status (W-8):** **APPROVED as a roadmap candidate and specification target** — **specification work may occur Friday as already planned.** It is **not authorized for implementation.** Its exact build placement **remains subject to WIP=1 and the post-5G-1D sequence** (never ahead of a calendar-forced or data-integrity item). This section records the candidate, its placement, dependencies, the Lite/Portfolio split, and the Wishlist relationships only.

---

## 18. Account Composition Visibility Rider (T-6; interleave-class; not authorized for implementation)

*Adopts the amended T-6 contract (Fable Amendment 2 — Account Composition Scope, 2026-07-14, which amended §1/T-6 of Amendment 1). **Name: "Account Composition Visibility Rider" — do NOT call it `5G-3A`** (an ordinal invites availability scope and brands it as the allocation phase). It is a **read-only visibility capability** and **does not establish authoritative allocation or availability semantics.** It joins the visibility-trio family: display-only, zero-write, close-supporting.*

**What it answers:** *"what makes up this balance"* for a **savings** account, pinned to one **closed-week basis** — never *"what can I spend."* It is an early read-only down payment on 5G-3; **full 5G-3 remains the authority** for Spoken-For, Free-to-Use, and Checking composition, and later replaces/expands the drawer interior with authoritative semantics.

**Displayed reconciliation equation (must be rendered, not just satisfied — no plug values):**
> **reconciled account balance (as of Week N closeout) = Σ displayed durable components + Σ displayed modeled components + signed residual**

Every line carries an evidence tag rendered per line (**`durable`** or **`modeled`**); **no line is shown without explicit account-routing evidence** — no inference; ambiguous/unsupported amounts fall into the residual. Cumulative `funded_amount` is **not** proof of current cash location (5G-1C-2.1 doctrine); **only release/holding evidence may establish a durable held amount.**

### Supported accounts & evidence classes (early rider)

**AMEX Savings (holding).** Permitted evidence: reconciled balance from the **same closed week**; closed-week funding snapshots (`goal_funding_snapshots`); **5G-1B release/holding events**; explicit routing metadata (5G-1A holding-label source); (post-5G-2) `outflow_events` set-aside sums as an additive component. Rules: **durable** = `wewe_*` holds/releases (post-1B) and, post-5G-2, plan set-asides; **modeled** = IRA/529 sweep accumulation (`_amxHold` mechanics, no durable deployment record). Residual label: **"Unattributed (timing/interest)"** — expected **near zero**; a breach shows a **"review at next close"** flag (the same number Monthly Close attests, never a new one). *Builds post-1B because only 1B makes "still held vs paid out" durable.*

**Truist Savings.** Included in the early rider (it is the account the original product ask named — live wishlist **ID 30** "what exactly makes up this $X in **Truist Savings**"). Permitted evidence: reconciled balance from the **same closed week**; closed-week snapshot amounts; **registry or model routing metadata that explicitly identifies Truist Savings as the destination**. Rules: **every named Truist Savings component is labeled `modeled` in v1** (no release/deployment record exists for savings exits — 1B's durable lifecycle covers the AMEX holding, not Truist Savings); **do not infer purposes** from context, transfer descriptions, or operator memory; ambiguous/unsupported amounts fall into the residual; **do not create an operator-attestation write path, new allocation table, or proto-allocation record** (attested purposes are exactly 5G-3's allocation layer). Residual label: **"Unattributed (purposes not yet modeled)"** — expected **large and unflagged** (the EF and any un-modeled purpose live here by design until 5G-3). **A large residual is acceptable and is not a defect in the rider.**

**Truist Checking (operating): NO early composition breakdown — categorically deferred to full 5G-3.** *Proof:* a displayed balancing residual on the operating account *is, by construction, the available-cash figure* (reconciled balance − floor − committed near-term outflows − pending transfers − uncleared activity) — a competing availability/planning-headroom number that conflicts with the 5F-1 Cash Availability Engine (which already owns this computation) and the 5G-3 CAE-relationship mandate (RM R20). The account-detail drawer shows only: **reconciled balance; as-of week/date; a pointer to the authoritative Weekly Model / Cash Availability view; a statement that full composition is deferred to 5G-3.**

### Prohibited terminology (before full 5G-3)
On all rider surfaces: **"Allocated", "Unallocated", "Free", "Available", "Spendable", "Safe to move"** (plus "Spoken For"/"Free to Use", reserved as 5G-3's branded pair) and **any transfer suggestion/recommendation**. A static test asserts the module contains none of these and **derives no availability figure**; no CAE reads; no new tables, RPCs, grants, or writes.

### UI placement
**Primary surface: Accounts page → account-detail drawer** — the stable long-term UI socket. The rider supplies the first read-only interior; **full 5G-3 later replaces/expands that interior** with authoritative Spoken-For / Free-to-Use semantics **without moving the surface**. Overview may carry **only a compact summary + drill-through link** (no composition content — numbers would detach from their evidence tags). The **Goals page may link** to relevant account composition but is **not the primary home** (the question is account-anchored). Register unchanged. Other accounts (Vio/LC tax-reserve class) render balance-only until a future class contract exists.

### Earliest safe timing
**After 5G-1B acceptance** (release state + `wewe_*` terminal disposition exist; both supported accounts ship together — Truist Savings has no 1B dependency but no earlier WIP=1 slot exists since Sep is the DCL chain); **only in a genuine WIP=1 gap** (realistically the Oct P3b window at the earliest); **must not delay 5G-2, the rollover, or any calendar-forced phase.** Gains the AMEX set-aside component after 5G-2. If no gap ever opens, it folds into 5G-3 with zero loss. **Not authorized for implementation** — this section records the contract only.

---

## Appendix A — F-01 … F-13 disposition record

All thirteen findings **Adopted (A)** or **Adopted with Modification (AwM)** — none Deferred, Rejected, or Open. Acceptance criteria carried per row. (Source: Fable review §2.)

| ID | Summary | Disp. | Roadmap change | Acceptance criteria | Pre-Alaska? |
|---|---|---|---|---|---|
| F-01 | 5G-1B under-scoped: Gate-C lockdown removes every snapshot write path release semantics could use | **A** | §4 reframing; review venue = §4 baseline + ChatGPT (F-07) | 1B spec explicitly chooses write-surface branch (a) vs (b); states the eligible-nine/monotonicity boundary; sized with staging gate | Adopt §4 by Jul 19; later freeze-exception + DDL approvals |
| F-02 | DR floor had priorities but no completion gate; trip is worst-case window | **AwM** | DR-1 gate (§5); deadline Jul 23→**Jul 28**; MFA after the sitting, before departure | All §5 items evidenced + Adam sign-off ≤ Jul 28; trip-window posture recorded as accepted variance expiring Aug 11 | **Yes (hard gate)** |
| F-03 | "July close runs at activation" false; skipped-week catch-up hidden | **AwM** | §3 P3 corrected; wk 7 closes at home; catch-up depth 3→**2** (§6) | Close v1 §I corrected; first-close record notes late-`recorded_at` watermark | Posture decision by Jul 25 |
| F-04 | No contingency if the Saturday sitting hard-stops | **A** | Contingency annex (§7); Jul 19–28 retry window incl. Sat Jul 25 | Annex adopted before Jul 18; every stop-state has a named safe mode + retry requirement | **Yes** (before the sitting) |
| F-05 | "Extraction doesn't block 5G-3" contradicts AGENTS.md standing law | **A** | Re-pin = blocking prereq to 5G-3 (§9); land pre-freeze | AGENTS.md carries the §9 wording; 5G-3 spec gate references it; patch lands pre-freeze push or first Aug-11 action | Yes (preferred) |
| F-06 | Three lanes overstate one-owner throughput; WIP=1 needed | **A** | WIP=1 (§8); lanes = dependency taxonomy; Diablos/GLP first | WIP=1 recorded; collision set named; Diablos/GLP first post-freeze code | Governance adoption now |
| F-07 | 1B runway had no dates; needs drop-dead + graceful-miss record | **AwM** | §4 dates + substitute review chain (§11.2) | Dates in roadmap; miss-penalty sentence in §3 P4; reviewer designation decided (A14) | Spec queue set pre-freeze |
| F-08 | Blocking decisions undated; rollover frozen-object authority missing | **A** | Add **D-11** (§12); decide-by dates | §12 carries D-11 + dates: D7 ≤ Aug 11; D6 ≤ Oct 1; Plan Period ~Nov 1; D10+D-11 ~Nov 15 | No |
| F-09 | Close v1 must assert the post-Phase-2 grant posture, not bare "activation" | **A** | Close v1 grant-matrix P-item | Close v1 P-item: wrapper/Option B = T; old recon / repair / direct snapshot RPC = F; table INS/UPD(/DEL) = F before any certification | No (checklist authored in freeze) |
| F-10 | Wishlist-34 December trip mis-parked; taxonomically a planned-outflow | **A** | Route the *residual* dated-trip concern to 5G-2 `planned_outflows`; no registry goals pre-4a (§3 P5). **Live item 34 is DONE — the routing is the residual follow-on, not a reopen (Appendix B.2/B.3).** | §3 P5 + Appendix B carry the routing line; live item 34 retained done | No (A13) |
| F-11 | Freeze rule should be zero pushes to main, not just "no 5G merges" | **AwM** | Zero pushes except two named exception classes (§11.3); correct all "Jul 24–Aug 10" → **Jul 29–Aug 10** | Freeze controls rewritten; repo dates updated; branch-held discipline stated | Yes (docs patch pre-freeze; A2) |
| F-12 | Visibility trio is a close-integrity control; ride the first post-freeze slice | **AwM** | Load-failure banner may be branch-built in freeze; merged Aug 11 with the first slice | Banner + verdict text + nag live before the second close (August); compensation step in Close v1 checklist v1 | No (optional freeze build) |
| F-13 | Freeze "parallel-planning" capacity assumed, not established | **A** | Freeze spec-load model (§11.3); 1B spec first | Roadmap states the drafting/approval model; 1B spec first | No |

---

## Appendix B — Wishlist disposition record (reconciled against the live production export, 2026-07-14)

**Reconciliation basis:** the production `wishlist_items` export (project `usayoldrawwmjsmretin`) is **authoritative for live IDs, titles, and statuses.** Rows were reconciled by title / description / repository evidence / functional intent — **not** by assuming Fable's numbers match production PKs. Balance-free; no household values.

**ID-namespace correction (critical):** Fable's low "wishlist" numbers were **not** live `wishlist_items` PKs — they were `docs/security-brittleness-backlog.md` item numbers and `docs/stabilization-roadmap-spec.md` TD-numbers. In production those live as rows 80–102 (each carrying a `"Tracked in docs/security-brittleness-backlog.md item N"` note). Crosswalk (Fable → live PK): 8→99 · 9→101 · 10→86(done) · 11→95(done) · 13→97 · 14→96 · 15→80 · 16→93 · 17→100 · 18→90 · 19→91 · 20→81 · 21→102 · 22→88 · 23→89 · 24→87(done) · 25→98 · P1/TD-8→92 · P2→82 · P3→94 · P4→84 · P5→85 · P6→83.

### B.1 Full disposition — every `planned` / `idea` row (one disposition each)

Legend: **MAP** existing phase · **NEW** new named candidate · **OP** operational procedure · **CTRL** control/defect · **DEFER** parked w/ trigger · **SUP** superseded · **ADAM** requires Adam decision.

| PK | Title (live) | Status | Disp. | Home / trigger |
|---|---|---|---|---|
| 21 | Dynamic goal registry (add/edit/pause/archive/reprioritize) | planned | MAP | **5G-4b** (write capability) + **5G-5** Goal Admin UI |
| 22 | Goal dependency chain | planned | MAP | 5G-4b / 5G-5 |
| 23 | Goal progress from checked actions | planned | MAP | 5G-4b / 5G-5 |
| 24 | Goal funding source & destination account | planned | MAP | **5G-4a** (data model) + 5G-4b |
| 26 | Account connections (OAuth) | planned | MAP | **Horizon A**, behind the Edge Function enabler (SR-4) + Import Readiness |
| 27 | Auto balance pre-fill | planned | MAP | Horizon A, behind Import Readiness + Edge Function |
| 28 | Last synced badge per account | planned | MAP | Horizon A (with 26/27) |
| 29 | Account reconciliation breakdown | planned | MAP | **Early: Account Composition Visibility Rider (§18, T-6)** — read-only composition for AMEX Savings + Truist Savings (post-1B WIP=1 gap). **Full breakdown → 5G-3 Cash Allocation** (authoritative Spoken-For/Free-to-Use + Checking). |
| 30 | "What is this balance?" view | planned | MAP | **Originally described Truist Savings** (`index.html:9810`). **Early: Account Composition Visibility Rider (§18, T-6)** — Truist Savings, read-only, all-`modeled`, "Unattributed (purposes not yet modeled)" residual. **Truist Checking composition + full authority → 5G-3.** |
| 31 | CC due-date timing moves | planned | OP+MAP | OP now (owner-run WD/obligation edit); structural home **5G-2 / D6** |
| 32 | Reorder wishlist columns | planned | MAP | **Subsumed by Roadmap UI Lite (§17)** — delivered inside the Roadmap & Ideas redesign, not as a standalone tweak |
| 33 | Drop a completed phase from the wishlist dropdown | planned | MAP | **Subsumed by Roadmap UI Lite (§17)** |
| 35 | Show/hide left nav (collapsible) | idea | DEFER | Small display UI; trigger = Wendy-usage signal / WIP=1 interleave |
| 37 | Configure git identity on the machine | planned | OP | One-time operator setup — **not a phase** |
| 38 | Add a required action to a defined future week | planned | CTRL/verify | Verify current `CustomTask` any-week behavior; if a real gap, small `weekly_tasks` UI → **5H** or WIP=1 interleave |
| 39 | **Make the mobile version better** | idea | MAP | **5H** (mobile usability/quick-add), behind the 5D-2 desktop-only reversal — **this is the real ID 39, NOT the BLR FK audit** |
| 40 | Variables page (retire hard-coded model values) | idea | ADAM | Internal seam = extraction constants/config (§9 item 8); a **user-facing Variables page is distinct** — decide whether to build it (W-1) |
| 48 | Import Truist transactions into the model | idea | MAP | **Import Readiness / OAuth ladder** (Horizon A), behind the Edge Function enabler |
| 49 | Monthly phone accrual (Mint Mobile) | idea | MAP | **5G-2 `planned_outflows`** (the Mint seed) / D6 obligations; needs an accrual-model spec |
| 50 | Credit-card strategy in the OS | idea | NEW/ADAM | **Decompose** → card-strategy advice · statement ingestion (behind Edge Function + Import Readiness) · rewards tracking · overview page; Horizon-level; requires Adam decomposition + placement (W-2) |
| 51 | Build the Misc/Extra spreadsheet into the OS | idea | ADAM | Scope decision: fold into TX-1 income taxonomy vs a new Budget bucket vs park (W-3) |
| 52 | Replace Quicken + the budget it holds | idea | SUP | Budget module is live; Quicken is retired → residual = **Budget-Identity Change (legacy 5G-3)** + **D1** archival; largely superseded |
| 53 | Add retirement / 529 / EF **accounts** | idea | MAP/ADAM | **Horizon C** net-worth / asset-account roadmap; reconcile with the goal registry (5G-4) — scope confirm (W-4) |
| 54 | Challenge the technical architecture | idea | CTRL | Substantially addressed by the Fable arch review + calc-core amendment; **retain as a recurring architecture-review (ARR) governance trigger**, not a one-time close (W-5) |
| 80 | Session/token policy review (backlog 15) | planned | DEFER | Security-hardening pass (before Horizon A/B) |
| 81 | User invite flow (backlog 20) | planned | DEFER | Real third user |
| 82 | Write debouncing on toggleTask/saveNote (P2) | planned | DEFER | Next incidental `index.html` slice / WIP=1 interleave |
| 83 | Anon-key rotation procedure (P6) | planned | OP | **restore-runbook appendix** (DR-1 doc set) |
| 84 | 2027 model re-baseline (P4) | planned | MAP | **P7 Plan Period / 2027 rollover** — related to 92 but distinct (rollover procedure vs starting-balance derivation) |
| 85 | `updated_at` triggers on write tables (P5) | planned | MAP | **P8** mutation-metadata; subsumed by the L2 audit-log trigger design (D8) — **distinct from 93** |
| 88 | Read-only viewer dashboard (backlog 22) | planned | DEFER | CPA engagement / role need (Close v1 artifacts may serve CPA first) |
| 89 | CPA / advisor access mode (backlog 23) | planned | DEFER | CPA engagement |
| 90 | Data export & backup plan (backlog 18) | planned | MAP | **DR-1** (§5) |
| 91 | In-app user management UI (backlog 19) | planned | DEFER | Real third user |
| 92 | Auto-derive starting balances / TD-8 (P1) | planned | MAP | **Calc-Core Extraction constants/config seam (§9)** + P7 re-baseline; **VERIFIED STILL LIVE** (constants hardcoded at `index.html:889`) — distinct-but-related to 84 |
| 93 | Supabase audit & access logging (backlog 16) | planned | MAP | **P8 L2 `financial_audit_log`** (D8) — **distinct from 85** |
| 94 | Input validation on write paths (P3) | planned | CTRL | Reconciliation path superseded (RPC-side validation + wrapper contract + P1-1); Register residual → **P3b-1**; `toggleTask`/`saveNote` residual → DEFER |
| 96 | CSP / XSS hardening (backlog 14) | planned | DEFER | Security-hardening pass; CSP feasibility study = good freeze docs work |
| 97 | CDN/SRI hardening (backlog 13) | planned | DEFER | Security-hardening pass |
| 98 | Role-aware UI suppression (backlog 25) | planned | DEFER | Next auth-adjacent slice |
| 99 | MFA for owner Supabase account (backlog 8) | planned | MAP | **DR-1** (§5) |
| 100 | Formal versioned SQL migration scripts (backlog 17) | planned | CTRL | **Largely done-by-practice** — 87 committed `docs/phase-*.sql` with staging-first + preflight/validation/rollback; the premise ("managed via dashboard SQL editor") is stale. Residual = **DOC-3** physical org (`docs/sql/executed/`) + the execution ledger. Close-by-practice-with-DOC-3-residual vs retain (W-6) |
| 101 | Backup owner account (backlog 9) | planned | MAP | **DR-1** (§5) |
| 102 | Forgot-password UI (backlog 21) | planned | DEFER | Real third user |

### B.2 Verification — roadmap-relevant `done` rows (live status retained; residuals separated, not reopened)

| PK | Title | Repo support | Residual follow-on (separate; not a reopen) |
|---|---|---|---|
| 25 | Authentication (Auth v1) | ✓ Phase 4 auth live (`is_allowed_user()`/`is_owner()`) | none |
| **34** | **Wendy's trips + December trip added to goals/logic** | ✓ early/manual impl; `christmas_cruise` + `alaska` are in the Week-5 eligible-nine anchor | **RESIDUAL (F-10/A13): "Dated-trip outflow routing"** — future/recurring dated trips must route through **5G-2 `planned_outflows`**, NOT new registry goals (pre-4a registry goals trip the GM-3 eligible-set hard stop). **Do NOT reopen 34.** Named follow-on concern only. |
| 36 | EF injection assumption update | ✓ | none |
| 41 | Desktop→mobile required-action sync fix (wk 26) | ✓ | **RESIDUAL OP:** pre-June-2026 custom tasks still localStorage-only on the originating device (AGENTS Known Gap) → one-time export/merge OP |
| 43 | Fidelity call-outs corrected | ✓ | Re-verify Fidelity mapping stays correct as asset accounts expand (ID 53) |
| 47 | IRA/529 AMEX 5-week lookahead | ✓ `maxSafeAmxSweep` + 5-week lookahead live; hardened by 5G-1A.5 | none |
| 86 | RLS → `auth.uid()` migration (backlog 10) | ✓ Phase 4B/5A | none — **closes Fable's "10"** |
| 87 | Wendy access mode (backlog 24) | ✓ Phase 4C/5B | none — **closes Fable's "24"** |
| 95 | Role enforcement (backlog 11) | ✓ Phase 4C/5A | none — **closes Fable's "11"** |

*Foundational `done` rows (retain done; no roadmap action): 1–20 (app shell, overview, weekly model, goals, history, reconciliation drawers, scenarios, AI Q&A, wishlist CRUD), 42 (defect classification), 44 (overview usability), 45/46 (required-action override system).*

### B.3 Corrections to Fable's assumed identifiers / statuses

1. **Live item 34 is `done`, not open.** Fable treated "wishlist-34" as open and routed it to 5G-2. Correction: **retain done**; the planned_outflows routing is a **named residual architectural concern** ("Dated-trip outflow routing"), decoupled from the completed item. **34 is not reopened.**
2. **BLR `category_key` FK audit ≠ live ID 39.** Live `wishlist_items` **ID 39 = "Make the mobile version better"** (→ 5H). The BLR FK audit's real home is **AGENTS.md Near-Term Wishlist ID 39** + `docs/validation-blr-category-sync.sql` (reusable guard) + `docs/2026-07-02-register-budget-category-sync.sql` (the data-correction that motivated it) + the AGENTS Known-Gap `budget_line_rules.category_key` no-FK note. It maps to **P3b-1** as a control item, cited by those artifacts — **not** attributed to live ID 39.
3. **Fable's low IDs were backlog/TD numbers, not live PKs** — see the crosswalk above (B header).

### B.4 Roadmap sequencing changes caused by the live export

1. **Wishlist-34 correction** — A13 is re-expressed as governing the *residual* dated-trip routing (→ 5G-2), not a reopen; §3 P5, §12.2 A13, and Appendix A F-10 updated accordingly.
2. **BLR FK audit re-cited** to AGENTS Near-Term ID 39 / `validation-blr-category-sync.sql`; **mobile (live 39) added to 5H**; §3 P3b-1 updated.
3. **NEW — ID 50 credit-card strategy** is a genuinely new Horizon-level capability cluster the roadmap did not carry; it needs decomposition (card strategy · statement ingestion · rewards · overview). Statement ingestion sits behind the Edge Function enabler (SR-4) + Import Readiness. **Requires Adam decision (W-2).**
4. **NEW consideration — ID 40 Variables page** distinguishes a *user-facing* config page from the *internal* constants/config extraction seam (§9). If wanted, it is a small post-extraction feature. **Requires Adam decision (W-1).**
5. **ID 49 monthly phone accrual = Mint Mobile** confirms the 5G-2 Mint seed is a live household need — reinforces 5G-2 (no new phase).
6. **ID 100** confirms versioned SQL is done-by-practice; the residual is the DOC-3 `docs/sql/executed/` reorg — reinforces the already-recorded post-5G-1D DOC-3 action.
7. No other live row creates or reorders a phase; 21–24 confirm 5G-4a/4b/5 content, 26–30 confirm Horizon A / 5G-3, 80–102 map to DR-1 / P8 / security-hardening / Auth+.

### B.5 Items requiring Adam decision (new, surfaced by the live export)

| # | Decision | Recommendation |
|---|---|---|
| W-1 | ID 40 — build a user-facing Variables page, or rely solely on the extraction constants/config seam? | Rely on the seam first; defer a UI to post-extraction |
| W-2 | ID 50 — approve the credit-card-strategy decomposition + Horizon placement | Decompose; park behind Edge Function + Import Readiness |
| W-3 | ID 51 — Misc/Extra spreadsheet: TX-1 taxonomy vs new Budget bucket vs park | **RESOLVED by T-2** — lite 80% folds into **P3b-1.MX** (Misc/Extra Envelope v1); the identity 20% stays the gated Budget-Identity Change |
| W-4 | ID 53 — retirement/529/EF as asset accounts: Horizon C net-worth scope | Horizon C; reconcile with goal registry, don't duplicate |
| W-5 | ID 54 — recurring ARR governance trigger vs close | Retain as recurring trigger (mostly addressed, not closeable) |
| W-6 | ID 100 — close-by-practice (+ DOC-3 residual) vs retain planned | Close-by-practice; carry the DOC-3 residual |
| W-7 | ID 34 residual — confirm the "Dated-trip outflow routing" follow-on name; 34 stays done | Adopt as written (A13 governs the recurrence) |
| W-8 | Roadmap UI Lite (§17) — **APPROVED as a roadmap candidate + specification target** (spec work may occur Friday as planned). **Not authorized for implementation.** Exact build placement remains subject to WIP=1 and the post-5G-1D sequence. Items 32/33 delivered inside it. | **Adopted as candidate/spec-target; build placement is a future gate** |

### B.6 Close / remove (data recommendations for Adam — not unilateral edits)

10 (→86) auth.uid() migration → **DONE**; 11 (→95) role enforcement → **DONE**; 24 (→87) Wendy access mode → **DONE**; 17 (→100) versioned SQL migrations → **done-by-practice**, DOC-3 residual (W-6); **P1/TD-8 (→92) auto-derive START_* → VERIFIED STILL LIVE, not superseded** (extraction constants seam + P7); seed "Date-based model internals" → **remove; record as rejected direction** (Plan Period P7 is the adopted alternative); 12 Anthropic key → vault/Edge Function → **keep, re-noted** (RLS + role carve-out constrain it; remediation rides SR-4 / AF-7).

**Live-table reconciliation: COMPLETE.** Every `planned`/`idea` row (21–24, 26–33, 35, 37–40, 48–54, 80–85, 88–94, 96–102) carries exactly one disposition (B.1); every roadmap-relevant `done` row is verified with residuals separated (B.2); no live row is silently absorbed. Open items are the eight W-decisions (B.5). **Roadmap enhancement (2026-07-14):** items 32/33 are re-dispositioned as **subsumed by Roadmap UI Lite (§17)**, and Roadmap UI Lite is recorded as a new future candidate (W-8) — the Wishlist page is superseded by the Roadmap & Ideas experience, with `wishlist_items` retained as the Ideas/Backlog store.

---

*Living Plan document. No code, SQL, schema, migration, RLS, RPC, test, `BUILD_TS`, or production/staging change is authorized or implied by this file. Revised in place; adopt changes per Adam approval. 5G-1D remains frozen and authoritative for its own scope.*
