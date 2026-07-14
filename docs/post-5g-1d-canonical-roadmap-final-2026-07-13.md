# Herndon Financial OS — Post-5G-1D Canonical Roadmap (FINAL)

**Date:** 2026-07-13 (currency-refreshed 2026-07-14 to the Saturday activation boundary)
**Type:** The canonical, decisive post-5G-1D execution sequence. Finalizes and supersedes-for-sequencing
`docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md` (retained for its full review reconciliation
and provenance); refreshes that synthesis's stale 5G-1D baseline (it predated this session's Slice 6 +
Gate B work) and resolves its two open hedges (Gate D; restore-point currency).
**Standing:** **Advisory. Docs only. No implementation authority.** `AGENTS.md`, `CODEX_STATUS.md`,
`docs/phase-status.md`, cleared 5G-1D scope, the Do-Not-Touch list, and Wendy-confirmed workflow win on
any conflict. This document amends no cleared scope, gate, contract, SQL, RPC, or execution step.

## 0. Currency & conflict resolution (authoritative repo facts vs advisory carry-forward)

| # | Conflict | Resolution (repo fact wins) |
|---|---|---|
| CR-1 | The 2026-07-13 synthesis baselines 5G-1D as "Slice 3/6/7 remain; Gates C/D/E OPEN." | **Stale.** Current (HEAD `a952560`): Slices 3/4/5 COMPLETE + Adam-verified (**static 1507/0, e2e 148/0/0, fallbacks 0/0**); Slice 6 inert prod deploy COMPLETE + GREEN; Gate C APPROVED (all 11); Gate D DECIDED; Gate B is at the **Saturday 2026-07-18 activation sitting** (operator package `docs/phase-5g-1d-saturday-operator-package-2026-07-18.md`; adjunct preflight + pre-Phase-1 validation PASS). 5G-1D is one controlled sitting from done. The synthesis's *sequencing* stands; only its 5G-1D baseline is refreshed. |
| CR-2 | Synthesis C9/D4: "Gate D activation timing — neither branch canonical." | **Resolved.** **Gate D DECIDED = Option A (pre-freeze), Adam 2026-07-13.** 5G-1D activates **before Jul 24** (Saturday ~Jul 18). Half-close gap repair is therefore **minimal/none** — the first closeout is model week 6 (calendar Week 28); there are no freeze-period half-closes to repair. |
| CR-3 | Synthesis §2.6: "last full-data restore point 2026-07-09 (predates E2/2.1/Wk-5)." | **Partially closed.** A fresh **2026-07-13** public-schema restore point exists (Slice-6 Gate 2; verified restorable; encrypted off-device; sha `e3d24dfa…`). The acute "no recent restore point" gap is mitigated; the recovery **floor** (cadence, MFA, backup owner, runbook, restore rehearsal) remains the #1 immediate operational item. |
| CR-4 | Stale phase names / test counts / "Week 26" calendar labels in older docs. | Not carried forward. This doc uses the verified gate (1507/0, 148/0/0) and the confirmed mapping **model `week_num=6` = calendar Week 28** (`getCalWeek(6)=28`). Historical docs are **not** rewritten here; targeted status updates are recommended in §K, not applied. |

---

## A. Current-state baseline

- **Exact point:** 5G-1D at the **Gate B production-activation boundary** — all pre-activation work done and verified; the only remaining 5G-1D action is the Saturday sitting (Phase 1 grants → BUILD_TS+merge+deploy → Week-6/Week-28 closeout → Phase 2 revokes → two non-mutating proofs). "Post-5G-1D" work begins only once that sitting closes Gates B/C/D/E.
- **System-of-record posture:** the Financial OS is the **sole live system of record**; Quicken is retired (historical archive/reference only — not a parallel ledger or recovery replica).
- **Freeze window:** **Alaska freeze Jul 24 – Aug 10** — no 5G phase-code merges. 5G-1D activation is **pre-freeze** (Option A).
- **Confirmed dependencies / active blockers:** DR exposure (Supabase Free plan, no PITR; single-laptop dumps; no owner MFA/backup-owner) — mitigated by the 07-13 dump but the floor is unbuilt; cruise payouts (**RCCL ~Cal Wk 30**, **DCL ~Cal Wk 41**) force 5G-1B; the **2027-01-09** model-window end forces the rollover; `weekly_reconciliations` is keyed **only by `week_num`** (P2-2) — must be re-keyed/archived before the first 2027 closeout.
- **Item taxonomy:** **Shipped** = 5B/5E Budget+Register, 5F-1 weekly reconciliation + Cash Availability Engine, 5G-1A/1A.5/1C-1 hotfixes, 5G-1C-2 E1/E2 + C3 overlay, and (this session) the 5G-1D browser + Slice-6 inert deploy. **Planned/validated-not-live:** 5G-2 Planned Outflows (staging DB layer validated 2026-07-08). **Named-but-empty:** 5G-1E, 5G-1F, 5G-2..5G-6, 5H/5I/5J/5K/5L. **Advisory:** the three 2026-07-12 Fable reviews, the calc-core amendment, and the synthesis (inputs, not approved roadmaps).

---

## B. Decision principles (work is ranked on these, in this priority order)

1. **Production risk / operational urgency** — protect the sole live record; anything that can lose or corrupt data outranks everything.
2. **Calendar-forced deadlines** — cruise payouts (5G-1B) and the 2027 rollover are immovable.
3. **Dependency unlocking** — items that gate the critical path (extraction; 5G-4a) come before their dependents.
4. **User value** — Wendy/Adam workflow quality (Register bundle, Goal Admin, mobile).
5. **Architecture leverage** — one-time cheap venues (5G-4 taxonomy, extraction seams) taken before they harden.
6. **Reversibility** — file-tier/docs-first before schema; certify-don't-lock; staging-first.
7. **Implementation size** — prefer small, high-certainty slices; never bundle a hidden second project (e.g., test-suite migration inside extraction) without scoping it.
8. **Freeze compatibility** — docs/spec/test/review work is freeze-safe; 5G merges and cash-model behavior changes are not.

---

## C. Canonical sequence

Per phase: **Obj · Why here · Prereqs · Blocking deps · Outputs · Window (pre/freeze/post) · Freeze-work allowed?**

**P0 — Complete 5G-1D (in-flight; do not disturb).** *Obj:* activate the atomic reconciliation-plus-nine-snapshot closeout in production. *Why here:* it gates every post-5G-1D item. *Prereqs:* the operator package + read-only checks (done). *Deps:* its own Gates B/C/D/E. *Outputs:* wrapper live+granted; Week-6 closeout evidenced; old direct write paths revoked; proofs recorded. *Window:* **pre-freeze (Sat Jul 18).** *Freeze-work:* n/a — completes before the freeze.

**P1 — Recovery-remediation floor (non-code; START NOW, parallel to P0).** *Obj:* close the sole-live-record DR exposure. *Scope:* owner-login MFA; a backup-owner/recovery-access account; weekly + pre-close + pre-correction `pg_dump` cadence with encrypted off-device copies; retention (8 weekly / 6 monthly); `docs/restore-runbook.md`; one staging restore rehearsal after Gate B settles. *Deps:* none. *Outputs:* restore-tested backups + runbook. *Window:* now / any. *Freeze-work:* **yes** (ops + docs).

**P1b — Docs-only currency + fold-in (non-code, owner-approved).** *Obj:* prevent load-bearing gates from being lost. *Scope:* roadmap numbering + legacy-gate fold-in in `docs/phase-status.md`; runModel freeze-language re-pin against the extraction phase; obligation-taxonomy one-pager; `CODEX_STATUS.md`/`AGENTS.md` currency. *Deps:* Adam approval (§K D-STATUS). *Window:* now / freeze. *Freeze-work:* **yes.**

**P2 — Freeze window (Jul 24 – Aug 10): SPECS ONLY.** Prepare: 5G-1B release-event shape; Register Data-Quality + Entry / TX-1 taxonomy scope; Monthly Close v1 P1–P9 checklist + certification template; Plan Period design-doc kickoff; obligations end-state memo. **No code, no merges.** *Freeze-work:* the window *is* the parallel-planning window.

**P3 — First implementation phase after 5G-1D: Monthly Close v1 (file-based) — see §I.** *Obj:* repeatable certification + basis watermark + closed-period divergence detection. *Why here:* zero-code, produces the certification primitive the audit model composes over, and is the primary period-integrity control now that Quicken is retired. *Prereqs:* 5G-1D activated (fully-closed predicate). *Deps:* 5G-1D. *Outputs:* `docs/closes/2026-07-close.md`; 3-fact state model (certification + reopen records; OPEN/CERTIFIED/REOPENED/DIVERGED derived). *Window:* **post-activation (spec-able in freeze; first July close executable once activated).** *Freeze-work:* spec yes; the checklist run is zero-code (freeze-safe).

**P3b — Register Data-Quality + Entry bundle (first CODE phase; parallel to Close v1's 2nd iteration).** *Obj:* data integrity for the primary record. *Scope:* TX-1 taxonomy (income/offset categories) + required-category + save validation + uncategorized cleanup; 5E-11 category typeahead / payee memory / account ordering; REG-4 uncategorized count; `budget_line_rules.category_key`→`categories` FK audit. *Non-scope:* Weekly-Model cash-math; mobile layout (5H). *Deps:* TX-1 taxonomy spec cleared. *Window:* **post-freeze.** *Freeze-work:* spec only. *Review?* light spec review of the taxonomy slice.

**P3c — Diablos/GLP WD baseline correction + golden-master recapture.** *Obj:* correct knowingly-understated projections (data, not runModel logic). *Deps:* golden-master recapture approval (§K D7). *Window:* post-freeze. *Freeze-work:* spec/scoping only.

**P4 — Holding lifecycle → hard invariant.** **5G-1B holding→payout releases** — *Obj:* model cruise-deposit releases so the AMEX invariant can become true. *Deps:* Diablos/GLP baseline; its release-event spec; a **runModel freeze exception** (Adam). *Calendar:* **before DCL ~Cal Wk 41; RCCL divergence clock ~Cal Wk 30.** *Window:* post-freeze. *Freeze-work:* spec (this is the phase to spec during the freeze). **Review? Yes.** → then **5G-1E** invariant hardening (hard AMEX two-sided gate). *Deps:* 5G-1B. *Review?* optional.

**P5 — Visibility + allocation foundation.** **Run-time visibility trio** (load-failure banner, Review-Required verdict text, snapshot-gap nag) — finishes already-specified items. **5G-2 Planned Outflows** (prod DDL + app build; Mint seed) — *Deps:* obligation-taxonomy direction; Mint vendor/amount/date confirmation (external); `showCashPlanning`; ES-module workflow; hold until the Register bundle + 1B land. *Window:* post-freeze. *Review?* optional (spec'd at v1.4).

**P6 — Allocation, extraction, goal governance (the critical-path back half).** **5G-3 Cash Allocation** (derived Spoken-For / Free-to-Use) — the spec **must define the relationship to the 5F-1 Cash Availability Engine** (one "available cash" number). *Deps:* 5G-2; 1B. **Review? Yes.** **Calc-core extraction (legacy 5G-2.5)** — charter/posture per `docs/post-5g-1d-roadmap-amendment-calc-core-extraction-2026-07-13.md` (**authoritative**): reify the four seams; behavioral identity under golden masters; ES-modules only, no framework/bundler/TS; the closeout-builder items only after 5G-1D is stable; test-harness migration is a **prerequisite**, not cleanup. *Deps:* golden masters; an approved test-migration plan; 5G-1D complete+stable. **Review? Yes.** → **5G-4a** goal/funding-target data-model governance (read-side; registry history, transition matrix, scope-change runbook; the physical-unification decision, §K D5). **Review? Yes.** → **5G-4b** goal write capability (**highest-risk build**; waterfall-input writes; zero-outflow identity test). **Review? Yes.** → **5G-5** Goal Admin UI.

**P7 — Plan Period / 2027 rollover (calendar-forced, parallel chain).** Plan Period spec (design so 2027 is the first instance) → staging rehearsal → **production execution before 2027-01-09** → 2027 opening anchor. Minimum 2027 execution: `model_year` on `weekly_reconciliations` (P2-2), per-period week-CHECK relaxation, parameterized year-pins, per-year engine constants, generalized E2 anchor seed. **Extraction is the preferred prerequisite** (amendment §6); the **extraction-vs-rollover calendar-risk gate** (§K D10) decides if extraction must complete first. **Review? Yes** (highest blast radius).

**P8 — Audit tiers, later hardening, data-feature ladder.** `financial_audit_log` (L2, trigger-driven) at 5J or pull-forward on the third owner correction/quarter → gates the Budget-identity change (legacy 5G-3). L3 domain event ledger — rides 5G-1B; **not speculative.** Merged Close/Goal-Admin hardening (file→schema) after ≥3 stable closes. **Broader application modernization (Register/Budget/view-layer modularization)** — **post-2027-rollover, trigger-based** (amendment §2/§7); **not a 2026 modularization phase.** Splits (5I) → Transfers (5K) → Import Readiness → Horizons. **5H mobile quick-add** after the 5D-2 "Transactions desktop-only" reversal.

---

## D. Pre-freeze plan (before Jul 24) — do NOT overload the window

**Do exactly this before the freeze, nothing more:**
1. **Finish 5G-1D** — the Saturday activation sitting (P0). This is the one code/production event pre-freeze.
2. **Stand up the recovery-remediation floor** (P1) — non-code, start now, parallel.
3. **Docs-only currency/fold-in patches** (P1b) — owner-approved.
4. **Draft freeze-window specs** (P2 prep) — begin the 5G-1B / Register-bundle / Close-v1 / Plan-Period / obligations specs.

**Explicit:** beyond finishing 5G-1D and the recovery floor, **the correct pre-freeze answer is "planning and specs only."** No new 5G build phase starts pre-freeze. Do not attempt the Register bundle, 5G-1B, 5G-2, or extraction before the freeze.

---

## E. Freeze plan: Jul 24 – Aug 10

**Safe during the freeze:** documentation/specification; test-infrastructure work (harness migration groundwork, golden-master tooling — no behavior change); isolated non-production prototypes; architecture planning; independent (Fable) reviews; the recovery floor + restore rehearsal (ops).
**Prohibited during the freeze:** production merges affecting 5G; schema/grant changes; cash-model (runModel/waterfall) behavior changes; operational-workflow cutovers; any `main` merge of a 5G phase.

---

## F. Post-freeze execution order (after Aug 10)

1. **Monthly Close v1** (July rehearsal close) ∥ **Register Data-Quality + Entry bundle** ∥ **Diablos/GLP WD fix**.
2. **Diablos/GLP WD fix → 5G-1B releases → 5G-1E** (before DCL ~Cal Wk 41).
3. **Visibility trio** ∥ **5G-2 Planned Outflows** (Register-bundle + Mint-confirmed).
4. **5G-3 spec (CAE relationship) → calc-core extraction → 5G-4a → 5G-4b → 5G-5.**
5. **Plan Period spec → rollover staging rehearsal → rollover production execution → 2027 anchor** (before 2027-01-09) — parallel calendar-forced chain.
6. **L2 audit log** (≥3 corrections or 5J) → Budget-identity change; **L3 ledger** rides 1B; merged Close hardening; Splits → Transfers → Import → Horizons; 5H after 5D-2 reversal.

---

## G. Dependency graph (strict prerequisites → answers the specific coupling questions)

```
5G-1D (activation) ──┬─► Monthly Close v1 ──► merged Close hardening
                     ├─► 5G-2 Planned Outflows ──► 5G-3 Cash Allocation
                     └─► 5G-4a scope-change contract
Diablos/GLP WD fix ──► 5G-1B releases ──┬─► 5G-1E hard invariant
                                        └─► L3 event ledger
Calc-core extraction ──┬─► 5G-4a ──► 5G-4b ──► 5G-5
                       ├─► Budget-identity (legacy 5G-3)   [also needs A2 + Wendy + L2]
                       └─► (preferred) 2027 rollover execution
Plan Period spec ──► rollover staging rehearsal ──► rollover prod exec ──► 2027 anchor  [< 2027-01-09]
L2 audit log ──► Budget-identity change
```
- **Must 5G-2.5 (extraction) precede 5G-3/5G-4?** It **must precede 5G-4** (5G-4a/4b need the testable waterfall API) and is the **preferred prerequisite to the 2027 rollover** (§K D10 decides if mandatory). It does **not** block **5G-3** (5G-3 is derived allocation over 5G-2; it depends on 5G-2, not extraction).
- **Is application modularization a prerequisite or a parallel track?** **Neither pre-req nor a 2026 phase.** Broad Register/Budget/view-layer modularization is **post-2027-rollover, trigger-based** (amendment). Only the **calc-core extraction** (a narrow move-only-under-golden-masters slice) is on the 2026 path.
- **Is 5G-1B time-sensitive because of real cruise payouts?** **Yes** — DCL ~Cal Wk 41 is the completion deadline; the RCCL ~Cal Wk 30 payout starts the AMEX snapshot-vs-cash divergence clock (inside the freeze).
- **Does month-end close depend on 5G-1D and account allocation?** Depends on **5G-1D** (the fully-closed weekly predicate). Does **not** depend on account allocation (5G-3) — Close v1 is file-based over weekly primitives.
- **Is TX-1 independent of the cash-planning phases?** **Yes** — TX-1/Register data quality is independent of 5G-2/5G-3; it runs in the data-integrity lane. (It informs 5G-2's taxonomy but does not block it.)
- **Can mobile/Register work run independently?** The **Register data-quality bundle** runs independently (data-integrity lane). **5H mobile quick-add** is blocked only by the 5D-2 desktop-only reversal, otherwise independent.

---

## H. Parallel-work lanes (3; synchronization points marked)

1. **Operational cash-planning lane:** 5G-1D activation → Monthly Close v1 → 5G-2 → 5G-3 → 5G-4a/4b/5. **Sync:** must not advance past 5G-4 until **extraction** (Architecture lane) lands; 5G-3 waits on 5G-2.
2. **Data-integrity / workflow lane:** recovery floor → Register/TX-1 bundle → Diablos/GLP WD fix → 5G-1B → 5G-1E → L2 audit log → 5H. **Sync:** 5G-1B needs the WD fix; 5G-1E needs 5G-1B; the Budget-identity change (cash-planning-adjacent) needs L2.
3. **Architecture / test lane:** calc-core extraction (harness migration + golden masters + four seams) → Plan Period spec → 2027 rollover rehearsal/execution. **Sync (critical):** extraction gates 5G-4 (lane 1) and is the preferred gate for rollover execution; the rollover amends 5G-1D-frozen objects — that migration authority must be resolved on paper before lane-3 touches lane-1's frozen contracts.

---

## I. Recommended next phase (ONE)

**Monthly Close v1 (file-based; reframed 5G-1F).** It is the single primary next implementation phase after 5G-1D activation.

**Why it wins over the Register bundle, 5G-1B, and 5G-2:**
- **Zero-code and freeze-safe** — it is a checklist + committed certification record (`docs/closes/2026-07-close.md`) + a 3-fact state model; it can be specced during the freeze and its first (July) close **run the moment 5G-1D activates**, with no merge and no cash-model change.
- **It builds the foundational primitive the rest of the audit/close model composes over** — certification, basis watermark, divergence detection, reason-code vocabulary — which L2/L3, the Budget-identity change, and every later close depend on.
- **It is now the primary period-integrity control for the sole live record** — with Quicken retired there is no external replica to cross-check against, so the certify-and-detect-divergence ritual (plus statement attestation) *is* the trust layer.
- The **recovery floor (P1)** is a higher operational priority but is **ops/DR, not a build phase** — it runs in parallel starting now, not competing for the "next phase" slot. The **Register/TX-1 bundle (P3b)** is the strongest *code* contender and runs in **parallel** (lane 2), but Close v1 is chosen as the primary because it is the load-bearing control primitive and is cheaper and lower-risk.

**Next Fable review target (question 9):** **5G-1B release-event shape** — it is the next architecture-grade, calendar-forced build (payout-deadline), and its snapshot interaction (release-vs-cumulative-progress, terminal treatment of the Week-5 `wewe_*` correction rows) is exactly the kind of subtle contract a focused review de-risks. (Monthly Close v1 needs **no** review — OM's control review *is* its spec.)

---

## J. Deferred / non-sequenced (must not crowd out the canonical sequence)

Goal creation/editing & reprioritization (→ 5G-4b); recurring/multi-period goals (→ `planned_outflows`, not the registry); scenario/what-if & long-range forecasting (Horizon C, aspirational); AI recommendations (Horizon B, post-extraction); physical funding-target unification *build* (→ 5G-4a spec outcome); close schema/UI (→ after ≥3 file-based closes); L3 ledger speculative build (rides 5G-1B only); PITR/paid tier/alerting/close cockpit (explicit non-needs); broad application modularization (→ post-rollover); multi-currency/invoicing/multi-tenant/native-app (excluded). **None of these may pre-empt P1–P7.**

---

## K. Decision register (unresolved owner decisions requiring Adam)

- **D-ADOPT:** adopt this document as the canonical post-5G-1D roadmap (§B principles + §C sequence + §I next phase).
- **D-STATUS:** apply the docs-only currency/fold-in patch set (P1b) — numbering fold-in, freeze re-pin, obligation taxonomy — to `phase-status.md`/`AGENTS.md`/`CODEX_STATUS.md`. (Recommended separately; **not** applied in this task.)
- **D1 — Quicken archival policy** (narrow; cancellation settled): verify clean export, set retention/storage (off-device, encrypted), decide one-time-reference vs periodic source.
- **D3 — Gate C `repair_commitments_for_week` posture** (5G-1D-internal; recommend wrap/restrict-to-owner) — *approved this session; recorded for completeness.*
- **D5 — Physical funding-target unification** at 5G-4a (single entity vs shared-taxonomy separate) — spec-gated either way.
- **D6 — Obligations end-state** (budget_rules absolute-mode migration / dated-obligation adapter / WD hand-maintained).
- **D7 — Golden-master recapture approval** for the Diablos/GLP WD baseline correction.
- **D8 — L2 audit-log timing** (5J vs pull-forward on the third correction/quarter).
- **D10 — Extraction-vs-rollover calendar-risk gate** (extraction-before-rollover vs a narrowly-scoped rollover against the existing engine; no default; a partial extraction may never be the rollover base).

---

## L. Fable challenge package

The independent challenge prompt is `docs/post-5g-1d-canonical-roadmap-final-fable-prompt-2026-07-13.md`. It asks Fable to adversarially challenge the sequence, dependency assumptions, freeze boundary, parallelization, architecture-debt timing, operational-urgency ranking, the chosen next phase, earlier/later moves, hidden 5G-1D coupling, and the risk of doing too much before the freeze — with an explicit **APPROVE / APPROVE WITH REQUIRED CHANGES / REJECT** verdict and P0/P1/P2 findings tagged *before freeze / during freeze / after freeze / before implementation of named phase*.

---

*Docs-only synthesis. No code, SQL, schema, migration, RLS, RPC, test, or production/staging change; no BUILD_TS change; the 5G-1D activation branch is untouched. Advisory; adopt per Adam approval + Fable challenge.*
