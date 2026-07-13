# Herndon Financial OS — Post-5G-1D Canonical Roadmap and Architecture Synthesis

**Date:** 2026-07-13
**Author:** Claude Code (local synthesis agent)
**Type:** Canonical reconciliation of the three 2026-07-12 Fable architecture reviews into one post-5G-1D roadmap, grounded against current repository state (HEAD `aff220c`).
**Standing:** **Advisory. Docs only. No implementation authority.** If anything here conflicts with `AGENTS.md`, `CODEX_STATUS.md`, `docs/phase-status.md`, cleared 5G-1D scope, the Do Not Touch list, or Wendy-confirmed workflow, **those controls win.** This document does not amend any cleared scope, gate, contract, SQL, RPC, or execution step. The three reviews are advisory inputs, not independent approved roadmaps.

**Supersedes:** `docs/post-5g-1d-roadmap-synthesis-2026-07-12.md` (prior-session draft), which is retained for provenance but is **stale on its 5G-1D execution status (§2.3) and roadmap reconciliation**; its operating conclusion that Quicken was canceled was correct and is now confirmed (§2.6 / C1). This 2026-07-13 document is the canonical post-5G-1D roadmap.

---

## 1. Executive decision summary

The three reviews agree on the macro shape of the forward roadmap and diverge only at the seams. Reconciled against current repository evidence, the canonical decisions are:

1. **Finish 5G-1D first.** 5G-1D is *not* complete. As of 2026-07-13 its Slice-2 Gate-2 staging matrix passed (the two new RPCs are staging-accepted and returned to inert grants), but **Slice 3 (browser closeout UI), Slice 6 (prod inert deploy), Gate B production activation, and Slice 7 (Week-6 writer smoke) remain, and Gates C/D/E are OPEN.** Nothing in this roadmap interrupts, reorders, or amends 5G-1D.
2. **Backup / restore / recovery remediation is the single highest-severity, lowest-cost item on the board and starts now** — Free-plan Supabase (no PITR), a single-laptop `pg_dump` as the sole restore path, no owner-login MFA, no backup owner. All three reviews rank it top. With the Financial OS now the **sole live system of record** (decision 3), this is an **immediate production-operability and disaster-recovery requirement** — there is no parallel system to fall back on.
3. **The Financial OS is the sole live system of record; Quicken is retired.** Adam confirmed on 2026-07-13 that parallel operation with Quicken has stopped, the subscription is canceled, and the historical Quicken data is retained as a **historical archive / reference source only** — Quicken is **not** an active operational system, parallel ledger, or independent live recovery replica. This authoritative operating state supersedes the repo documentation that still described an active Aug–Sep parallel run. Roadmap items that assumed a pending cancellation (a "September Quicken verdict," "backup as a cancellation precondition") are reframed accordingly; the only residual Quicken decision is archival policy (§11 D1).
4. **Resequence 5G-1B (holding→payout releases) before 5G-1E,** completed before the DCL payout (~Cal Wk 41). The current map sequences 1E ("consumes 5G-1B releases") after 1D while 1B is "Deferred/unsequenced" — a broken order on its own terms.
5. **Reframe 5G-1F as Monthly Close v1: file-based, certify-and-detect-divergence, not hard locks.** First close on July data, run after 5G-1D activation and its half-close gap repair (**activation timing is Gate D — an open owner decision, not presumed post-freeze; see C9**). Narrow preventive controls only (`deleteRecon` restriction on anchored weeks; direct-write revoke on `weekly_reconciliations` — both feed 5G-1D Gate C).
6. **Give calc-core extraction an explicit slot** before 5G-4 / Budget-identity / rollover execution, and **re-pin the ambiguous runModel freeze language** (the "frozen through 5G-2" boundary changed meaning in the 2026-07-08 renumber).
7. **Split 5G-4 into 4a (goal/funding-target data-model, read-side) and 4b (write capability),** mirroring the 6A/6B pattern.
8. **Adopt the Plan Period *design* target** so 2027 is implemented as the first instance of a period abstraction — but **scope 2027 execution to the minimum re-baseline** (`model_year` on `weekly_reconciliations`, per-year week-CHECK relaxation, parameterized year-pins, generalized opening-anchor seed). No multi-scenario planning platform.
9. **Do cheap docs-only work now:** roadmap numbering + legacy-gate fold-in resolution, obligation-taxonomy one-pager, freeze-language re-pin, documentation-currency cleanup. These prevent load-bearing gates from being silently lost.
10. **Keep two distinct event/audit primitives** sharing one append-only convention: an `financial_audit_log` row-mutation tier (L2, trigger-driven) and a domain funding-event ledger (L3, forced by 5G-1B releases). **Do not build the L3 ledger speculatively.**

The next implementation action is **not** in this roadmap: it is to finish 5G-1D. The next *planning* actions are the freeze-window specs (§10). The next *operational* action is the recovery-remediation floor, which can start today.

---

## 2. Repository and production current state

### 2.1 Grounding

- **HEAD = `origin/main` = `aff220c`** ("docs(5G-1D): record Gate 2 staging completion"). Working tree clean of tracked-file modifications; only untracked docs present (the three reviews, the prior synthesis, AMEX-Gold and phase-5f-1.5 docs).
- **Authoritative sources:** `AGENTS.md` (standing law), `CODEX_STATUS.md` (active pointer + gate history), `docs/phase-status.md` (authoritative 5G sub-phase map, 2026-07-08 renumber). Cited in-repo evidence: the 5G-1D governance stack, `phase-5f-1-migration.sql`, the 5G-1C-2 E1/E2 closeouts, the 5G-1C-2.1 hotfix record.

### 2.2 Production-live capability (verified against repo)

- **Weekly reconciliation + Cash Availability Engine (5F-1):** live and proven in a real Week-26 closeout (2026-07-04); forward write path via `save_reconciliation_with_commitments` (Phases 0–4).
- **Budget + Register (5B / 5E):** live; Register is the actuals source of truth; Budget spend sums `budget_transactions` + `transactions`; Quicken CL/reconciliation Register default (Wendy-confirmed).
- **`goal_funding_snapshots` (5G-1C-2):** table + `save_goal_funding_snapshots` RPC production-live since E1 (2026-07-09, schema-only). **E2 first-anchor seed executed (2026-07-11): nine `opening_anchor` rows at model_year 2026, week 5.** 5G-1C-2.1 added two Week-5 `correction` rows (`wewe_rccl`=600, `wewe_dcl`=500), so the table holds **11 Week-5 rows**. C3 overlay live (inert absent snapshot rows; now active).
- **Funding-model hotfixes live:** 5G-1A (RCCL/DCL → AMEX Savings holding), 5G-1A.5 (sub-`MIN_XFR` deadlock carve-out), 5G-1C-1 (Funding Plan projection labels). The 5G-1B-rider reconciled-transfer-history defect is RESOLVED (`db2704f`, adapter/UI only).
- **Registry:** 13 goals; **9 snapshot-eligible; 4 excluded** (`adam_401k` auto; `wewe_rccl`/`wewe_dcl` holding; `taxable_etf` deferred). SELECT-only from the app; all changes are manual SQL.

### 2.3 5G-1D actual state (2026-07-13) — corrects both the reviews and the prior synthesis

The three reviews treat 5G-1D as "frozen, in execution." That remains accurate, but the current state is more advanced than the reviews knew and **less complete than the prior synthesis implied** (which said "Gate 2 paused after Sub-phase 5; resume Sub-phase 6"):

- **Slice 1 (`save_weekly_closeout_with_snapshots`) and Slice 2 (Option B `correct_goal_funding_snapshot` wrapper) are staging-accepted.** The full Gate-2 real-caller acceptance matrix **G2-1…G2-20b PASSED** on staging (`pkwotgqivgaapwuqgwqb`) on 2026-07-13; teardown/restore/ungrant/validation passed; both new functions returned to **inert post-test grants**; production DDL/data untouched.
- **Gate 0 (E2 completion) and Gate A (`is_owner()` identity) are CLOSED.**
- **Still outstanding inside 5G-1D:** Slice 3 (browser closeout workflow + state machine), Slice 6 (prod inert deploy + browser inert checks), **Gate B (production activation)**, Slice 7 (Week-6 writer smoke; revokes the old RPC grant). **Gates C, D, E remain OPEN.**
- **Net:** 5G-1D's RPC layer is staging-validated; it has **no browser UI and is not production-activated.** "Post-5G-1D" work begins only after activation + Slice 3/6/7 + Gate B close.

> **Currency note (repository, not this document's authority to change):** `CODEX_STATUS.md` prose in the dated 2026-07-10/11 sections still reads "5G-1D implementation NOT STARTED" in places; that prose predates the Slice-1/Slice-2 staging execution recorded at HEAD. The correction is flagged in §11 as an owner-approved patch, not applied here.

### 2.4 The year-2026 pin (all three reviews correct; verified)

`weekly_reconciliations` has **no `model_year` column** and upserts on bare `week_num` (`phase-5f-1-migration.sql`). Year-scoping is uneven across the persistence layer:

| Object | Year dimension | Pin |
|---|---|---|
| `weekly_reconciliations` | **none** (bare `week_num`) | a 2027 week-1 row collides with 2026 week 1 |
| `cash_commitments` | `model_year INT NOT NULL DEFAULT 2026` | RLS `WITH CHECK (… AND model_year = 2026)` |
| `goal_funding_snapshots` | `UNIQUE(model_year, week_num, goal_id)` | `CHECK (week_num BETWEEN 1 AND 31)` |
| `save_reconciliation_with_commitments` | `p_model_year` param | raises on `model_year <> 2026` |
| runModel / engine | — | `getCurrentWeek` clamp 31; `START_*`, `PAYCHECK_WKS`, WD literals |

The model window ends **2027-01-09** (~26 weeks out). A 2027 re-baseline is therefore a schema + RPC-pin + engine-constant + week-arithmetic change, not a config toggle — all three reviews agree, and the evidence is direct.

### 2.5 Repository-only artifacts vs future design work

- **Repository-only (planned/validated, not production):** 5G-1 / new-5G-2 Planned Outflows (`planned_outflows` + `outflow_events`) — staging DB/security layer validated 2026-07-08; **prod DDL + app build gated** (Mint vendor confirmation, prod DDL approval, ES-module build, `showCashPlanning`).
- **Named-but-empty roadmap slots:** 5G-1E (Account Purpose / Holding integrity), 5G-1F (Month-End Close), 5G-2..5G-6, 5H/5I/5J/5K/5L.
- **Explicit OPEN roadmap decision (phase-status.md):** the legacy technical-gate fold-in — calc-core extraction (legacy 5G-2.5), set-aside AMEX-lookahead gate (legacy 5G-4a), zero-outflow identity test (legacy 5G-4b), Budget-identity change (legacy 5G-3), spreadsheet retirement (legacy 5G-5) — has "no obvious 1:1 slot" in the new numbering and is deferred to an Adam decision.

### 2.6 Operating state: sole live system of record + recovery exposure (Adam-confirmed 2026-07-13)

**The Herndon Financial OS is now the sole live system of record.** Parallel operation with Quicken has stopped and the Quicken subscription is canceled; the historical Quicken data is retained as a **historical archive / reference source only** and is **not** an active operational system, parallel ledger, or independent live recovery replica. This confirmed operating state supersedes the repository documentation (`AGENTS.md`, `docs/phase-status.md`, Do Not Touch list) that still described an active Aug–Sep parallel run.

Because there is no longer any parallel system, the recovery exposure is **acute and immediate**: Supabase **Free plan, no PITR**; last full-data restore point is **2026-07-09** (predates the E2 anchor seed, the 5G-1C-2.1 correction, the Week-5 reconciliation, and all Register entry since); restore points are manual `pg_dump`s on **one laptop** (`~/Herndon-FOS-DB-Backups`, chmod 600, never committed); no owner-login MFA (security backlog item 8); no backup owner (item 9); the durable evidence directory is single-machine. All three reviews rank this exposure highest — and with the OS as the sole live record it is now an immediate production-operability / disaster-recovery requirement, not a future cancellation prerequisite.

---

## 3. Review-by-review findings

Abbreviations: **RM** = `roadmap-architecture-review-2026-07-12`; **AR** = `architecture-review-cash-planning-goal-funding-2026-07-12`; **OM** = `operating-model-control-review-2026-07-12`.

### 3.1 RM — Roadmap Architecture and Sequencing

**Remit:** everything after 5G-1D; sequencing, numbering, structural seams. **Core thesis:** "The roadmap is optimized for goal-funding correctness while the two hard calendar deadlines [2027 rollover; cruise payouts] are served by work that is unsequenced or absent." Macro order (integrity → planned outflows → allocation → goal management → close) is *not* inverted; the defects are at the seams.

**Highest-leverage recommendations:** R1 2027 Model Rollover as a first-class phase (P0, "single largest unscheduled risk"); R2 Register Data Quality + Entry bundle pulled ahead of 5G-2 (P0); R3 resequence 5G-1B before 5G-1E (P0); R4 backup/restore maturity as a Quicken-cancellation precondition (P0); R5 explicit calc-core-extraction slot + freeze re-pin (P1); R17 split 5G-4 into 4a/4b (P1); R18 reframe 5G-1F as "Monthly Close v1" with closed-period edit detection (P1); R13/R14 merge 5J into 5G-5/5G-6 and 5L into 5I-4 (numbering); R19 obligations end-state memo before 5G-2 app build; R20 define the Cash-Availability-Engine ↔ "Free to Use" relationship in the 5G-3 spec; R15 one append-only event-table convention.

**Currency to correct:** RM asserts the "Diablos/GLP projection gap is a live defect" (true — WD array drift, known-understated projections). RM frames Quicken cancellation as a *future September verdict* — **overtaken by events: Adam confirmed on 2026-07-13 that Quicken is already retired** (§2.2 / C1), so RM R4's "backup as a cancellation precondition" is moot and the backup/restore work stands as immediate DR. RM correctly states `weekly_reconciliations` has no `model_year`.

### 3.2 AR — Cash Planning + Goal Funding (5–10 year horizon)

**Remit:** can the architecture carry 5–10 years without a major redesign? **Core thesis:** the current build needs no abandonment; three deadline-forced commitments dominate — (1) the plan-period model (calendar-forced, ~26 weeks), (2) goal-set governance + unification at 5G-4 (product-forced by the next new goal), (3) event-ledger convergence at 1B/1E (payout-forced ~Cal Wk 30).

**Highest-leverage recommendations:** R1 Plan Period design (MC-1, High); R2 funding-target unification at 5G-4 bundling registry history (MC-3), a legal-transition matrix (GM-1), and a scope-change procedure (MC-10) before any 5G-5 UI; R3 calc-core extraction with four reified seams (eligibility/capacity/policy/decision-emission) under golden masters, deciding skip-vs-break deliberately (FE-1); R4 commit to a single Option-C event ledger riding 1B/1E; R5 resolve roadmap fold-in now (docs-only); R6 backup/evidence durability; R7 obligation-taxonomy one-pager + D1 clarification into the Slice-2 review.

**Key structural findings:** the "rigor inversion" — a heavily-governed snapshot layer over an unversioned, transition-rule-free registry; goals and `planned_outflows` are two subsystems for one problem (RCCL/DCL are "a production incident caused by taxonomy, not a bug"); monotonicity of `funded_amount` is only true pre-releases (challenged assumption A3 — "keep it a wrapper policy; do not harden it into more invariants").

**Currency to correct:** AR states `weekly_reconciliations` "has no model_year column" — **correct** (verified). AR treats 5G-1D as "frozen, in execution" and the snapshot layer as live with the Week-5 anchor — accurate. AR's counts (13/9/4) verified.

### 3.3 OM — Operating Model & Control Design (close, corrections, auditability, recovery)

**Remit:** the missing design for the reserved-but-empty 5G-1F close slot, plus 5G-6/5J sequencing. **Core thesis:** "The week is the control moment; the month is a certification and review overlay." Month-end close is a **certification layer composed over the weekly primitives, not a second reconciliation machinery.** "Certify, don't lock."

**Highest-leverage recommendations:** R1 compose close over weekly primitives; R2 a 3-fact close model (append-only certification + reopen records; OPEN/CERTIFIED/REOPENED/DIVERGED derived) — **rejecting an 8-state lifecycle**; R3 fix the close-basis control asymmetry (`deleteRecon` restriction on anchored weeks + direct-write revoke on `weekly_reconciliations`) as a *mandatory pre-close control* feeding Gate C; R4/R5 recovery posture (scheduled dumps, restore runbook, rehearsal, backup owner, MFA); R6 the run-time "surfacing trio" (load-failure banner, Review-Required verdict text, snapshot-gap nag); R7 file-based certification record + basis watermark; R9 `financial_audit_log` (L2, trigger table); R17 recovery-readiness gate on Quicken cancellation; R27 legacy-5G-3 (Budget identity) must not land before the L2 audit log.

**Control philosophy (explicit):** checklists before software; file-tier before schema; certifications immutable, the data they certify stays correctable; narrow preventive controls only; **no dual approvals** (single-owner household — approval *is* closure; a separate approved state models a segregation of duties that does not exist); **do not build L3 speculatively**; defer the close dashboard.

**Currency to correct:** OM treats Quicken as the "de facto redundant system / only independent replica" whose cancellation is a *future* gated act — **overtaken by events: Quicken is already retired (Adam-confirmed 2026-07-13)**, so it is no longer an independent replica and OM R17's "recovery-readiness gate on cancellation" is moot; OM's underlying recovery posture (scheduled dumps, restore runbook, rehearsal, backup owner, MFA) stands and is now *more* urgent because the OS is the sole live record. OM's "last restore point 2026-07-09 predates E2/2.1/Wk-5" — verified. OM's "security backlog Pro-plan backup assumption is stale" — the exposure is real (Free plan).

### 3.4 Cross-review agreement (strong, no conflict)

| Theme | RM | AR | OM |
|---|---|---|---|
| 2027 rollover / Plan Period as first-class | R1 (P0) | R1 / MC-1 | R20 / P4 |
| Backup/restore/DR remediation (immediate; production DR for the sole live system of record) | R4 | R6 / MC-9 | R4/R5/R17 |
| 5G-1B before 5G-1E | R3 | MC-4 / seq | 5G-1E-after-1B |
| Monthly Close v1, file-based, certify-don't-lock | R18 | (SM section) | R1/R2/R7 (primary) |
| Calc-core extraction explicit slot + freeze re-pin | R5 | R3 / FE-1 | (implicit L2 ordering) |
| Split 5G-4 into 4a/4b | R17 | R2 / SO-1 | — |
| Roadmap fold-in / numbering cleanup (docs-only, now) | R13/R14/R32/R33 | R5 / CP-2 | numbering hazard §1.2 |
| Obligation-taxonomy one-pager | R19 | R7 / CP-3 | (taxonomy in P4/close scope) |
| Register Data Quality bundle / TX-1 | R2/R16/R26/R28 | (CP-3 adjacent) | R21 |
| One event-table convention; don't build L3 speculatively | R15 | R4 / MC-2 / Option C | R9 (L2) / R26 (L3 defer) |
| Run-time visibility / surfacing trio | R23 | MC-8 adjacent | R6 |

---

## 4. Conflict-resolution register

Each conflict gets one explicit decision, the reason it wins, and what is discarded/narrowed/deferred.

### C1 — Quicken status: stale repository documentation vs confirmed operating state
- **Competing inputs:** the repository documentation (`AGENTS.md`, `docs/phase-status.md`, the Do Not Touch list) and all three reviews described Quicken as an **active Aug–Sep parallel run and de-facto recovery replica** with cancellation as a *future* gated decision. The prior-session synthesis (2026-07-12) instead concluded **Quicken was already canceled** — the correct operating conclusion, though it lacked sufficient repository evidence at the time.
- **Resolution:** **Quicken is retired; the Financial OS is the sole live system of record.** Adam confirmed on 2026-07-13 that parallel operation stopped, the subscription is canceled, and the historical Quicken data is retained as a **historical archive / reference source only**. Quicken is **not** an operational system, parallel ledger, or independent live recovery replica.
- **Why it wins:** **Adam's confirmed operating state is authoritative and supersedes the stale repository documentation.** The repo docs and the reviews were snapshots that had not caught up to the operating decision; the July-12 synthesis reached the right operating conclusion ahead of the paper trail.
- **Consequences:** the "September Quicken-cancellation verdict," the "recovery-readiness gate on cancellation" (OM R17), and "backup as a cancellation precondition" (RM R4) are **removed** as roadmap dependencies — there is no pending cancellation to gate. Backup/restore/DR is **reframed as an immediate production-operability and disaster-recovery requirement** for the sole live system of record (it is now *more* urgent, not less). The repository documentation is corrected to the operating state (see the docs-only patch actions in §10–§11 and the pointer note applied to `docs/phase-status.md`). The only residual Quicken decision is archival policy (§11 D1).

### C2 — Audit log (row mutation) vs funding-event ledger (business intent) — keep distinct
- **Competing:** OM R9 wants a generic `financial_audit_log` (table-agnostic AFTER-trigger row-diff). AR R4/MC-2 wants a domain **Option-C event ledger** (intent/execution semantics — transfers decided, holdings released). RM R15 wants "one append-only event-table convention, instantiated per domain."
- **Resolution:** **Two primitives, one shared convention.** L2 `financial_audit_log` answers "who changed which row, from what, to what" (mechanical auditability); L3 domain event ledger answers "why did money move, did the intended transfer execute" (funding semantics + durable transfer identity `weekly_tasks` positional keying lacks). Both share append-only + provenance + RLS-revoked-writes.
- **Why it wins:** a trigger-fed row-diff cannot carry event semantics; an intent ledger should not carry cosmetic-edit noise. Collapsing them loses information in both directions.
- **Sequencing:** L2 → 5J (or pull-forward on OM's live trigger: "third owner correction in a quarter"). L3 → first forcing function is **5G-1B releases**; build only when 1B needs it. **Discarded:** speculative L3 build (OM R26; AR "do not build speculatively").

### C3 — Close: certify-and-detect-divergence vs hard period locks
- **Competing:** OM R1/R2 (primary): certify, don't lock; 3-fact model; data stays correctable; divergence is detected, not prevented. RM R18/R24: "closed-period edit detection," revive 5C's reconciled-locking + `transaction_audit_log`; "a close that does not address post-close mutability is a report, not a close."
- **Resolution:** **Certify + divergence detection, with narrow preventive controls only.** Immutable: certification records, reopen records, opening anchor (nine-row guard), evidence hashes, terminal commitment audit fields. Correctable through governed paths: Register rows, BLR lines, weekly balances, snapshot values. Narrow hard edges: (a) `deleteRecon` restricted on anchored weeks; (b) direct-write revoke on `weekly_reconciliations` (funnel through the RPC) — both feed **Gate C**; (c) no hard deletes in certified months until L2 exists.
- **Why it wins:** OM and RM agree on *detection-first*; they differ only on how much prevention. In a single-owner household, ceremony has low marginal value; the sharpest real gap is unattributed/destructive writes to the close basis, which the narrow controls close without freezing daily workflow. RM's "revive 5C reconciled-locking design" is honored as the *source* for the detection/locking mechanics, sequenced into the Close track's hardening pass, not v1.
- **Also resolved:** OM's rejection of an 8-state close lifecycle in favor of 3 persisted facts + derived predicates is **adopted** (mirrors 5G-1D's states-as-predicates doctrine).

### C4 — 5G-4: physical funding-target unification vs cautious data-model split
- **Competing:** AR SO-1/R2: collapse goals + `planned_outflows` into one physical entity with type/policy fields at 5G-4 ("the last cheap venue"). RM R17: split 5G-4 into 4a (read-side data-model consolidation) / 4b (write), mirroring 6A/6B.
- **Resolution:** **Approve the logical taxonomy + the 4a/4b split now; the physical single-entity is spec-gated at 4a, not approved now.** A one-page obligation taxonomy (which system owns which obligation class; the migration events) is docs-only and prevents the RCCL/DCL misfiling class. The physical merge touches the waterfall's registry source, the snapshot contract, and the eligible-nine set the 5G-1D wrapper freezes — it requires the dedicated 4a specification.
- **Why it wins:** AR is right that 5G-4 is the cheap venue for *specifying* unification; that is an argument for designing it under review at 4a, not approving a deep schema merge today. Recognition of the shared domain is free; the physical contract is not.
- **Deferred:** the physical funding-target unification *build* → 4a spec outcome (§11 D5).

### C5 — Rollover: minimum 2027 re-baseline vs reusable Plan Period abstraction
- **Competing:** RM R1 scopes a 2027 re-baseline migration. AR MC-1/R1 wants a first-class Plan Period entity (id, start, week count, opening anchors, parameter set, week-numbering).
- **Resolution:** **Design the Plan Period abstraction on paper so 2027 is its first instance; scope 2027 execution to the minimum.** Minimum (non-negotiable): `model_year` on `weekly_reconciliations`; per-period relaxation of the snapshot `week_num` CHECK (2027 is a full year, not the 31-week mid-year artifact); parameterized RPC/RLS year-pins; per-year engine constants; a generalized E2 opening-anchor procedure.
- **Why it wins:** the calendar forces the minimum; the abstraction earns its keep only by making year three trivial. **Discarded:** multi-scenario / what-if planning, concurrent horizons, configurable planning platform (AR explicitly out of scope).

### C6 — First-close timing: OM's July file-based rehearsal vs RM's Register-bundle pull-forward
- **Competing:** OM runs the first (file-based, zero-code) July close after 5G-1D activation. RM pulls the Register Data Quality bundle earlier so downstream data quality is sound.
- **Resolution:** **Not in conflict — run in parallel.** OM's July rehearsal close exercises the ritual and produces the first certification; the Register bundle lands data-quality work in the same window so the *second-iteration* (August, ~early September) close is over clean data. Both depend on 5G-1D activation (timing per Gate D — C9) and Adam's time.
- **Note:** with Quicken retired (C1), the OS is the sole record, so there is **no external replica to cross-check the close against** — which raises the value of the surfacing trio (§7.1) and statement attestation (§7.4), the controls that let the operator trust that what they certified is what actually loaded. The Register bundle's residual purpose is data integrity for the primary record (still valid, arguably more urgent), not a cancellation verdict.

### C7 — Budget-identity change (legacy 5G-3) ordering
- **Competing:** OM R27: must not land before the L2 audit log exists. RM row 11 sequences it Nov–Dec gated on A2 income actuals + Wendy inputs.
- **Resolution:** **Gate legacy-5G-3 behind (a) A2 income actuals, (b) Wendy inputs, (c) the L2 audit log.** With Quicken retired (C1) there is no parallel month to cross-check against, so the new "Available for Goals = income − planned" identity must be validated through the close-certification process itself — golden-master identity on the model side plus a certified month-end reconciliation and statement attestation — rather than a Quicken tie-out. This makes the L2 audit-log prerequisite (OM R27) more important, not less: the before/after of a Budget-identity change must be reconstructable from the OS alone.

### C8 — Numbering / fold-in: multiple competing maps
- **Competing:** RM documents four numbering generations with duplicates/orphans (5J ≈ 5G-5+5G-6; 5L ≈ 5I-4; strategic-doc 5I-0/5I-3/5I-4 collide with 5I=Splits; "frozen through 5G-2" ambiguous). AR CP-2 and OM §1.2 flag the same fold-in gap and numbering divergence.
- **Resolution:** **Resolve the fold-in in `docs/phase-status.md` as a docs-only pass (owner-approved):** re-home the five legacy technical gates into the new 5G-2..5G-6 table; retire 5J into a merged Close/Goal-Admin track and 5L into 5I-4; re-pin the runModel freeze language against the calc-core-extraction phase (not the ambiguous "5G-2"). No behavior change. This is the cheapest high-leverage item and prevents a load-bearing gate (extraction-before-waterfall-changes) from being lost.

### C9 — 5G-1D activation timing (Gate D) — an unresolved owner decision, not a settled fact
- **The situation:** "finish 5G-1D first" is a hard dependency (post-5G-1D phase merges need the activated wrapper). **When** 5G-1D activates is a separate, still-open owner decision — **Gate D** — and this roadmap must not presume it. Two legitimate branches:
  - **Option A — pre-freeze activation.** If Slice 3 (browser UI), Slice 6 (prod inert deploy), the readiness checks, and Gates B/C/D/E are **completed and separately approved before July 24**, 5G-1D may activate before the freeze. In that case post-5G-1D *planning and file-based* work is not held merely by the calendar — but note the Alaska freeze still bars **5G phase-code merges** during Jul 24 – Aug 10 regardless.
  - **Option B — post-freeze activation.** Otherwise, defer activation until after Aug 10, then run sequential half-close repair (~weeks 6–9) followed by the first Monthly Close v1.
- **Resolution:** **neither branch is canonical until Adam decides Gate D.** The readiness package's default rule ("if the pre-freeze path becomes unsafe, default to post-freeze") is a *fallback*, not a selection. Sequencing below is written to work under either branch; where a step assumes activation, it says "activation (timing per Gate D)."

**No unresolved parallel roadmaps remain.** Two owner decisions remain open by their nature (not resolvable from evidence): the residual Quicken **archival policy** (C1 / §11 D1) and the **Gate D activation timing** (C9 / §11 D4).

---

## 5. Canonical sequenced roadmap

**Sequencing philosophy:** the macro shape is sound; changes are at the seams — resequence 1B before 1E, give extraction and the rollover explicit slots, split 5G-4, and treat backup/restore + the Register bundle as immediate. **Date discipline:** the only repository-anchored calendar facts are the **Alaska freeze (Jul 24 – Aug 10, no 5G merges)**, the **model window end (2027-01-09)**, and the **cruise payouts (RCCL ~Cal Wk 30, DCL ~Cal Wk 41)**. Month targets (Oct/Nov/Dec) are Fable planning targets, not repository facts; where timing depends on the freeze or an open Gate D, only relative sequencing is asserted.

Legend per phase: **Deps** (hard/soft) · **Non-scope** · **Frozen?** (touches runModel / frozen-adjacent) · **Review?** (would an external architecture review add material value before implementation).

### P0 — In-flight: complete 5G-1D (do not disturb)
- **Objective / value:** finish the frozen weekly-closeout state machine and activate durable per-goal funded attribution at closeout.
- **Scope:** Slice 3 (browser closeout UI + state machine), Slice 6 (prod inert deploy + inert checks), Gate B production activation, Slice 7 (Week-6 writer smoke + old-RPC grant revoke).
- **Non-scope:** anything in this roadmap; opening-anchor authorship (E2's, not 5G-1D's).
- **Hard deps:** its own Gates B/C/D/E. **Gate D (activation timing) is an open owner decision — Option A pre-freeze (only if all remaining slices/UI/inert-deploy/readiness are completed and separately approved before July 24) or Option B post-freeze after Aug 10; neither is presumed here (see C9).**
- **Exit:** wrapper activated in production; first supervised closeout evidence recorded; Gates B/C/D/E dispositioned.
- **Frozen?** It *is* the frozen surface. **Review?** No — governed by its own cleared gate register; this synthesis only feeds Gates C/D.

### P1 — Immediate, non-code (start now, parallel to 5G-1D)
1. **Recovery-remediation floor.** Objective: close the sole-live-record exposure. Scope: weekly post-closeout + pre-close + pre-correction `pg_dump` cadence; offsite encrypted copy; retention (8 weekly / 6 monthly); owner-login MFA; backup-owner account; `docs/restore-runbook.md`; off-device copy of the evidence directory; one staging restore rehearsal (after Gate B settles). Non-scope: paid PITR tier, alerting, automated infra. Frozen? No. Review? No.
2. **Roadmap fold-in + numbering cleanup + freeze re-pin** (docs-only owner patch — see §10 step 3 and §11 D9). Non-scope: any behavior/scope change. Review? No.
3. **Obligation-taxonomy one-pager + D1 scope clarification** into the 5G-1D Slice-2 review record. Non-scope: physical schema change. Review? No.

### P2 — Freeze window (Jul 24 – Aug 10): specification only, no merges
- **Prepare specs:** 5G-1B release-event shape; Register Data Quality + Entry bundle scope (incl. TX-1 taxonomy); Monthly Close v1 checklist (P1–P9); Plan Period design doc kickoff; obligations end-state memo. **The window is the parallel-planning window.** No code, no merges.

### P3 — 5G-1D activation & repair (timing per Gate D)
- **5G-1D activation + sequential half-close gap repair** (~weeks 6–9 if activation is post-freeze). Hard dep: 5G-1D Gate 2 complete (done) + Gate D decision (C9). **Option A:** if all remaining 5G-1D work is completed and separately approved before July 24, activation may occur pre-freeze (half-close repair is then minimal/none). **Option B:** post-freeze activation after Aug 10, followed by the sequential half-close repair of the freeze-period weeks. Frozen? Yes (5G-1D's surface).
- **Register Data Quality + Entry bundle.** Objective: data integrity for the primary record (now the sole live system of record) ahead of the second-iteration close. Scope: TX-1 income/offset taxonomy + required-category + save validation + uncategorized review/cleanup; reimbursement-status home decision (open since 5E-10); 5E-11 category typeahead / payee memory / account ABC ordering; REG-4 uncategorized count; `budget_line_rules.category_key`→`categories` FK audit (wishlist 39). Non-scope: Weekly Model cash-math; duplicate inflow/tax/goal allocation; mobile layout (5H). Hard dep: TX-1 taxonomy spec cleared. Frozen? No. **Review? Optional** — a lightweight spec review of the TX-1 taxonomy slice adds value; the rest is display/validation.
- **Diablos/GLP WD baseline correction + golden-master recapture.** Objective: correct knowingly-understated projections. Frozen? WD is Do-Not-Touch-adjacent; the correction is *data*, not `runModel` logic — confirm scope in the slice spec; **golden-master recapture requires Adam approval** (never edit expected outputs without it).

### P4 — Holding lifecycle → hard invariant
- **5G-1B holding→payout release semantics.** Objective: model the cruise-deposit releases so the AMEX invariant can become true. Scope (tightly, like 1A.5): release-vs-cumulative-progress semantics reconciled with snapshot meaning; terminal treatment of the Week-5 `wewe_*` correction rows; decrement/annotate the snapshot layer per AR's Option-C compatibility note. Hard deps: Diablos/GLP baseline (clean recapture); its own release-event spec; a **runModel freeze exception** (Adam). Calendar: **before Cal Wk 41 (DCL); RCCL divergence clock starts ~Cal Wk 30 (inside the freeze).** Frozen? **Yes.** **Review? Yes** — a focused spec review of the release-event shape and its snapshot interaction materially reduces risk.
- **5G-1E invariant hardening** (AMEX attribution advisory → hard two-sided gate). Hard dep: **5G-1B** + the 5G-1D RPC-side auto/holding exclusion guard rider. Frozen? Frozen-adjacent. Review? Optional.

### P5 — Close, visibility, allocation foundation
- **Monthly Close v1** (reframed 5G-1F, file-based). Objective: repeatable certification + basis watermark + closed-period divergence detection + reason-code vocabulary + accepted-variance register + exception catalog (Blocker/Warning/Info). Scope: P1–P9 checklist; `docs/closes/<YYYY-MM>-close.md`; 3-fact state model. Non-scope: close schema/UI; hard period locks; any new Wendy obligation. Hard dep: 5G-1D post-freeze activation (fully-closed predicate). First close = July data (rehearsal); second = August (~early Sep). Frozen? No. **Review? No** — OM's design is the spec; a review would be redundant.
- **Run-time visibility trio** (load-failure banner, Review-Required verdict text, snapshot-gap nag). Objective: you cannot certify what you cannot see fail. Note: this *finishes* already-specified items (incl. the 5F-1 Review-Required deferral), not new design. Frozen? No. Review? No.
- **5G-2 Planned Outflows Foundation** (prod DDL + app build; Mint seed). Hard deps: obligation-taxonomy direction; Mint vendor/amount/date confirmation (external); `showCashPlanning`; ES-module + static-server workflow. Staging DB/security layer already validated (2026-07-08). Hold until the Register bundle + 1B land; target after a clean September month-end close (a data-quality milestone, not a Quicken gate). Frozen? No (new tables, conforming policies). Review? Optional (design is largely spec'd at v1.4).

### P6 — Allocation, extraction, goal governance
- **5G-3 Cash Allocation** (derived Spoken For / Free to Use). Hard dep: 5G-2; **the 5G-3 spec must define the relationship to the 5F-1 Cash Availability Engine** (avoid two "available cash" numbers — RM R20), the balance-source rule, and the Protected enumeration; 1B for AMEX Spoken-For correctness. Frozen? Derived, no runModel change. **Review? Yes** — the CAE-relationship decision is subtle and product-visible.
- **Calc-core extraction** (re-slotted legacy 5G-2.5). **Charter widened per the Calc-Core Extraction and Module Posture Amendment (`docs/post-5g-1d-roadmap-amendment-calc-core-extraction-2026-07-13.md`) — that amendment is authoritative for this phase's scope, test posture, module/API posture, and the rollover calendar-risk gate; the summary here is not exhaustive.** Objective: end freeze-exception accretion; give the rollover a bounded constants/input seam and 5G-4 a testable waterfall API. Scope (per the amendment §3): shared pure utilities; **explicit model-input construction (no direct reads from mutable globals)**; explicit engine outputs including `ruleAudit`; goal-registry + budget-rule domain logic; Cash-Availability / AMEX-lookahead under behavioral identity; `runModel` + `reconEffectiveWD`; **reconciliation payload / closeout builders only after 5G-1D is complete and stable**; constants/config as the Plan-Period/rollover seam; and the test-harness migration. Reify the four seams (eligible set / capacity / allocation policy / decision emission); decide skip-vs-break deliberately under golden masters. **Test posture (amendment §4): assert behavior over source-text shape; source-shape tests only where shape is itself a contract, reason documented; harness/HTTP-E2E/golden-master expansion are extraction *prerequisites*, not cleanup; existing golden-master values may not change to make extraction pass.** Module/API posture (amendment §5): ES modules only; **no framework/bundler/build/TypeScript/replatform**; a transitional `window` bridge exposes only names needed for inline handlers/bootstrapping/tests and must not make internal domain functions public; shared data-access wrapper for new code, legacy `fetch` migrates only when its feature is touched; staging-write-block relocation needs explicit characterization. **Structure is illustrative, not locked — filenames/module tree are decided in the extraction spec.** Hard deps: golden masters (exist); an approved test-migration plan; 5G-1D complete + stable (for the closeout-builder items). Frozen? **Yes** — move-only under golden-master identity; this is the phase that *un-freezes* runModel per spec. **Review? Yes.**
- **5G-4a goal / funding-target data-model governance** (read-side). Scope: single source of truth for targets/status/flags; persist `ira_cpa_cleared`; registry history (MC-3); legal-transition matrix (GM-1); scope-change runbook (MC-10); generalized eligible-set contract; wishlist-34 goals executed under the new contract; **decide whether the physical funding-target unification lands here** (C4). Hard deps: extraction (testable API); the 5G-1D nine-goal snapshot scope-change contract. Frozen? Frozen-adjacent (registry feeds the waterfall). **Review? Yes** — the physical-entity decision and transition matrix are architecture-grade.
- **5G-4b goal write capability.** Scope: goal CRUD + reprioritization with GR-A1-class identity gates + confirmation flows; the zero-outflow identity committed test (legacy 5G-4b); earmark adapter into the 5F-1 engine (input layer only, one reservation contract per SO-2). Hard deps: 4a stable; extraction. Frozen? **Yes** — waterfall-input writes; **highest-risk build in the roadmap.** **Review? Yes.**
- **Goal Admin UI** (5G-5). Hard dep: 4b stable; transition matrix enforceable. Frozen? No (UI over governed writes). Review? No.

### P7 — Plan Period / 2027 rollover
- **Extraction relationship (amendment §6):** calc-core extraction is the **preferred prerequisite** to rollover implementation (it creates a bounded constants/input seam and avoids another high-risk edit inside the frozen monolith) — but it does **not** automatically delay rollover in all cases. **Calendar-risk decision gate (requires Adam — §11 D10):** if extraction timing threatens the 2027 deadline, Adam approves either (a) complete extraction before rollover, or (b) a narrowly scoped rollover against the existing engine with enhanced characterization + rollback controls. **A partially completed extraction must never become the rollover base.**
- **Plan Period specification** (design so 2027 is the first instance). Hard dep: understanding of every year-pin (§2.4). Target: approved before November. Frozen? Design touches frozen objects on paper only. **Review? Yes** — highest operational blast radius.
- **Staging rehearsal** of the rollover migration (reconciliation/commitments/snapshots/wrapper). Prod risk: none (staging). **Amends objects the 5G-1D contract froze — migration authority over frozen objects must be resolved on paper first.**
- **Production execution.** Prod risk: **highest operational** — a failed rollover halts weekly operations (reconciliation writes reject/collide). Calendar: **before 2027-01-09 (hard deadline).** Requires prod DDL approval.
- **2027 opening anchor.** Seed via the generalized E2 Value-Card pattern; owner-run.

### P8 — Audit tiers, later hardening, data-feature ladder
- **`financial_audit_log`** (L2 row-mutation history) — AFTER triggers on `transactions`, `weekly_reconciliations`, `goal_funding_snapshots`, `budget_line_rules`; trigger-only writes; read-only. Target: 5J, or pull-forward on "third owner correction in a quarter." Frozen? Frozen-adjacent — staging-first, own gate. **Review? Optional.**
- **Domain funding-event ledger** (L3 / Option C) — durable transfer identity + release + intent/execution. First forcing function: **5G-1B.** **Do not build speculatively.** Frozen? No.
- **Merged Close/Goal-Admin hardening** (absorbs 5J + 5G-6): promote the file-based close to schema; mechanical divergence; read-only close card. After ≥3 stable file-based close iterations.
- **Splits (5I) → Transfers (5K) → Import Readiness** (last): data-feature ladder; import also needs posted_date rules (former 5F-3), TX-1 validation, dedup design. Charter 5K now (transfer_group_id from 5C; retire the Cash-Planning two-entry pattern) even if built later.
- **5H Register capture speed + mobile quick-add** — after the deliberate reversal of the 5D-2 "Transactions is desktop-only" decision (hidden dependency: mobile nav has no Transactions entry). The cheap 5E-11 wins are already pulled into the Register bundle (P3).
- **Horizons:** A (bank integration) behind Import Readiness; B (AI assistant) cheaper after extraction exposes a clean domain API; C (retirement / 529 trajectories) aspirational, out of scope; D last.
- **Broader application modernization (Register/Budget/view-layer)** — explicitly **post-2027-rollover and trigger-based**, under this merged architecture-hardening label; **not a broad 2026 modularization phase** (per the Calc-Core Extraction and Module Posture Amendment §2/§7). Its non-scope for the extraction phase: Register/Budget/reconciliation-UI extraction, render-system rewrite, modal/navigation rewrite, inline-event-handler replacement, bulk `fetch` migration, CSS/HTML splitting, framework/build-tool adoption.

---

## 6. Dependency graph and critical path

### 6.1 Linear recommended execution order
1. **Finish 5G-1D** (Slice 3 → Slice 6 → Gate B activation → Slice 7; Gates C/D/E) — **blocks all "post-5G-1D" work.**
2. **Now, in parallel (non-code):** recovery floor; docs fold-in/freeze re-pin; obligation taxonomy.
3. **Freeze (Jul 24 – Aug 10):** specs only (1B, Register bundle, Close v1, Plan Period, obligations memo).
4. **Post-freeze:** 5G-1D activation + half-close repair → Register bundle ∥ Diablos/GLP WD fix.
5. **Diablos/GLP WD fix → 5G-1B releases → 5G-1E.**
6. **Monthly Close v1** (July rehearsal → August) ∥ **visibility trio** ∥ **5G-2** (post-Register-bundle, Mint-confirmed).
7. **5G-3 spec (CAE relationship) → calc-core extraction → 5G-4a → 5G-4b → 5G-5.**
8. **Plan Period spec → staging rehearsal → production execution → 2027 opening anchor** (before 2027-01-09).
9. **L2 audit log** (≥3 corrections or 5J) · **L3 event ledger** (rides 1B) · merged Close hardening · Splits → Transfers → Import → Horizons.

### 6.2 Dependency graph (arrows = hard prerequisite)

```
5G-1D (activation) ──┬─► Monthly Close v1 ──► merged Close hardening (P8)
                     ├─► 5G-2 Planned Outflows ──► 5G-3 Cash Allocation
                     └─► 5G-4a scope-change contract
Recovery floor (immediate DR) ──► restore-tested backups for the sole live system of record
Diablos/GLP WD fix ──► 5G-1B releases ──┬─► 5G-1E hard invariant
                                        └─► L3 event ledger (Option C)
Calc-core extraction ──┬─► 5G-4a ──► 5G-4b ──► 5G-5 Goal Admin UI
                       ├─► Budget-identity change (legacy 5G-3)  [also needs A2 + Wendy + L2]
                       └─► 2027 rollover execution
Plan Period spec ──► rollover staging rehearsal ──► rollover prod execution ──► 2027 anchor
L2 audit log ──► Budget-identity change (legacy 5G-3)
5G-3 spec ──(defines)──► CAE ↔ Free-to-Use relationship
Splits (5I) ──► Transfers (5K) ──► Import Readiness ──► Horizon A
5D-2 desktop-only reversal ──► 5H mobile quick-add
```

### 6.3 Critical path (longest hard-dependency chain)
**5G-1D activation → calc-core extraction → 5G-4a → 5G-4b → 5G-5**, with **Plan Period spec → rollover rehearsal → rollover execution** as a parallel calendar-forced chain that must complete before **2027-01-09**. Extraction is the pinch point: it gates 5G-4, Budget-identity, and safe rollover execution, and it hides a second project (test-suite migration) — under-scoping it delays the entire back half.

### 6.4 Safe parallelism
- **Now:** recovery floor · docs cleanup · obligation taxonomy — all parallel to 5G-1D.
- **Freeze:** every spec in parallel (no merges).
- **Post-freeze:** Register bundle ∥ Diablos/GLP WD fix ∥ (5G-1D activation is serial on its own gates).
- **Mid-roadmap:** Monthly Close v1 ∥ visibility trio ∥ 5G-2 build; Plan Period spec ∥ 5G-3 spec.

### 6.5 Must-not-begin-until
- **No "post-5G-1D" phase merges until 5G-1D is activated and its Gates B/C/D/E dispositioned.**
- **No 5G merges during the Alaska freeze (Jul 24 – Aug 10).**
- **5G-1E must not begin until 5G-1B releases exist.**
- **5G-4b must not begin until 5G-4a data model stabilizes.**
- **Budget-identity change (legacy 5G-3) must not land until the L2 audit log exists** (plus A2 income actuals + Wendy inputs).
- **Rollover production execution must not run un-rehearsed on staging**, and its authority to amend 5G-1D-frozen objects must be resolved on paper first.

### 6.6 Production-data / reconciliation-cycle timing dependencies
- **Cruise payouts:** RCCL ~Cal Wk 30 (inside the freeze) starts the AMEX snapshot-vs-cash divergence clock; DCL ~Cal Wk 41 is the 5G-1B completion deadline.
- **Weekly closeout cadence:** the fully-closed predicate for a month's close depends on that month's weekly closeouts existing; freeze-period weeks accumulate as half-closes and are repaired sequentially at 5G-1D post-freeze activation before the July close can certify.
- **Model window:** 2027-01-09 is a hard reconciliation-cycle deadline — a 2027 week-1 reconciliation collides with 2026 week 1 until `model_year` exists.
- **Sole system of record:** with Quicken retired, the OS has no independent replica, so scheduled restore-tested backups are an immediate operability requirement (not a future gate), and the month-end close's surfacing/attestation controls carry the trust that a parallel ledger used to provide.

---

## 7. Month-end close and audit operating model

Adopts OM's design as the canonical operating model, reconciled with RM's detection/locking mechanics and AR's correction discipline.

### 7.1 What is automated in the application
- Weekly closeout state machine (5G-1D) — the atomic control unit.
- P1/P2 close prerequisites computed from 5G-1D predicates (week coverage; half-closes repaired).
- The run-time **surfacing trio** (load-failure banner, Review-Required verdict text, snapshot-gap nag) — you cannot certify what you cannot see fail.
- Detectors feeding the exception catalog (5G-1D branch detectors, SA8 under-attribution, goalVariance, validation SQL).

### 7.2 What is enforced through database controls
- **Narrow preventive controls (mandatory pre-close, via Gate C):** `deleteRecon` restricted on anchored weeks; direct-write revoke on `weekly_reconciliations` (funnel through the RPC); `repair_commitments_for_week` wrapped or restricted to owner (Gate C disposition).
- **`financial_audit_log` (L2)** trigger-driven row-mutation capture — additive, staging-first, own gate; targeted at 5J or pull-forward on the third owner correction in a quarter.
- Additive integrity constraints already conventioned: `budget_line_rules.category_key`→`categories` FK (wishlist 39, after legacy audit); hard AMEX invariant (5G-1E).

### 7.3 What is a supervised in-app workflow
- Owner-only reopen and correction (5G-1D Option B; reopen never mutates data, never edits the original certification; re-close appends certification v(n+1)).
- Later: the correction/repair surfaces evolve toward an admin console that subsumes guarded SQL for routine operations, leaving SQL for break-glass only (a *stated direction*, not a near-term build).

### 7.4 What stays a manual checklist / runbook (file-tier, no code)
- **Monthly Close v1:** the P1–P9 checklist; the committed certification record `docs/closes/<YYYY-MM>-close.md` (scope pinned, checklist results, exceptions accepted, basis watermark, evidence-pack SHA-256, certified-by).
- **3-fact close model:** persist only append-only certification + reopen records; derive OPEN/CERTIFIED/REOPENED; DIVERGED derived.
- **Reason-code vocabulary** (`late_statement`, `entry_error`, `duplicate`, `missed_transaction`, `bank_adjustment`, `model_correction`, `other`+note); extend correction-evidence discipline to any owner-path write touching a certified month.
- **Accepted-variance register** (AMEX holding offset → expires at 5G-1B; pre-anchor weeks recon-only, permanent; excluded goals absent from snapshots, policy).
- **Exception catalog + severity** (Blocker / Warning / Info); Blockers enforced manually via checklist.
- **Owner-action fixed list** (certification; reopening; corrections touching certified scope; out-of-class accepted variances).
- **Statement attestation** per card (three-total model from the AMEX audits; difference 0 or itemized).
- **Recovery runbook** + weekly/pre-close/pre-correction backup cadence + quarterly restore rehearsal + standing post-deploy smoke list.
- **Derived-vs-observed doctrine:** derived = regenerate; observed = restore or correct, never regenerate.

### 7.5 What is deferred until sufficient operating history exists
- Close **schema/UI** (5G-6) — after ≥3 stable file-based close iterations.
- L3 domain event ledger — until 5G-1B forces it; **not speculative.**
- Read-only "Close status" card (5G-6) and any richer needs-attention surface (5F-0) — deferred; the close cockpit fails the materiality test today.
- Dual-actuals retirement (`budget_transactions` vs `transactions`) — decision when triggered.

### 7.6 Governance posture (single-owner household)
- **Approval is closure** — no separate "approved" state, no dual approvals; a segregation-of-duties model does not fit a two-person household.
- Wendy: **zero new obligations** from the close design; her daily Register/Budget flow is untouched.
- Single-operator concentration is mitigated by **runbooks + the backup owner + MFA**, not role changes.
- **Never reopen to make numbers match; never correct late transactions via `starting_balance`; no hard deletes in certified months until L2 exists.**

---

## 8. Parked backlog

Parked items are explicitly **not** commitments in the active roadmap. Each: description · why parked · reconsideration trigger · earliest sensible position · dependencies · design-review need.

| Item | Why parked | Reconsideration trigger | Earliest position | Dependencies | Design review? |
|---|---|---|---|---|---|
| **Goal creation / editing** | Registry is SELECT-only by design; write path needs a stable governed data model first | The next real new goal (wishlist 34 already queued) | 5G-4b (write capability) | 5G-4a data model; extraction; GR-A1 identity gates | **Yes** |
| **Goal reprioritization** | Reprioritization semantics enforced only by client validation today; ripples the waterfall | Same as goal editing | 5G-4b | 5G-4a transition matrix; scope-change contract | **Yes** |
| **Recurring / multi-period goals** | Correctly *not* modeled as goals; recurrence belongs in `planned_outflows` (`auto_renew`) + budget lines | A concrete recurring-obligation need `planned_outflows` cannot express | 5G-2+ (in `planned_outflows`, not the goal registry) | 5G-2 Planned Outflows | No (keep out of goal registry) |
| **Scenario / what-if planning** | Out of scope; would overbuild the rollover into a multi-scenario platform | A demonstrated need for concurrent plan variants | Post-rollover, only if demanded | Plan Period abstraction | **Yes** if ever |
| **Long-range forecasting** (retirement, 529 trajectories, coast-FI) | Aspirational (Horizon C); correctly out of scope; do not stretch the weekly-model window | A deliberate Horizon-C initiation | Horizon C (2027+) | extends the `planned_outflows` beyond-window pattern | **Yes** |
| **AI-generated recommendations** (Ask Claude payload) | Horizon B; cheaper/safer after extraction exposes a clean domain API | Extraction complete; a decision to initiate Horizon B | Horizon B (post-extraction) | calc-core extraction | **Yes** |
| **Debt optimization** | Not raised by any review; no current data model or household need surfaced | An explicit Adam request with a defined use-case | Unscheduled | TBD | **Yes** |
| **Investment / retirement modeling** | Horizon C; aspirational; monotonic funded-amount rule must not harden into valuation invariants | Horizon-C initiation | Horizon C (2027+) | 5G-4 data model; do not promote monotonic rule | **Yes** |
| **Advanced reporting** (beyond CPA export) | CPA/tax export rides Close v1 artifacts; broader reporting is not yet needed | A concrete reporting demand past close artifacts | rides Close v1; broader later | Close v1 certification records | Optional |
| **Multi-user workflow expansion** | Single-owner household; no SoD to model; no dual approvals | A real third operator or a role-separation need | Unscheduled | RLS role model | **Yes** |
| **Physical funding-target unification (build)** | Approved as *direction* only (C4); a deep schema change under the frozen registry/snapshot contract | 5G-4a spec outcome adopting the single entity | 5G-4a | extraction; snapshot scope-change contract | **Yes** |
| **Close schema / UI (5G-6)** | Certify-don't-lock v1 is file-based; schema is premature | ≥3 stable file-based closes | 5G-6 (merged Close track) | stable close ritual | Optional |
| **L3 domain event ledger (speculative)** | All three reviews: do not build ahead of a real consumer | 5G-1B needs release identity | rides 5G-1B | 5G-1B releases | **Yes** (shape) |
| **PITR / paid Supabase tier, alerting, event-sourcing, close cockpit** | Explicit non-needs now (OM §10) | Stakes/volume growth | Unscheduled | — | No |
| **5H mobile quick-add** | Blocked by the 5D-2 "Transactions desktop-only" decision (mobile nav lacks a Transactions entry) | A deliberate reversal of 5D-2 | 5H (2027) | 5D-2 reversal | No |
| **Richer goal dependency algebra / proportional split modes** | AR: "do not build speculatively" at this scale | A concrete multi-goal dependency or split need | at/after extraction (pluggable policy) | extraction | No |
| **Multi-currency, invoicing, multi-tenant, native mobile app** | Explicitly excluded (RM §5) | — | Not planned | — | No |

---

## 9. Recommended next phase

**Recommended next phase is to complete 5G-1D** — specifically Slice 3 (browser closeout workflow + state machine), then Slice 6 (prod inert deploy), then **Gate B production activation** with the post-freeze half-close gap repair, then Slice 7. This is not a new roadmap phase; it is the precondition for *every* item in this synthesis. It proceeds under 5G-1D's own cleared gate register and approvals — **no approval is inferred from this document.**

The **first new phase after 5G-1D** is **Monthly Close v1 (reframed 5G-1F)**, file-based, run first on July data once 5G-1D is activated and its half-close gap repair is done (**activation timing per Gate D — C9; not presumed post-freeze**) — because it is zero-code, produces the certification/basis-watermark primitive the rest of the audit model depends on, and, with Quicken retired, is now the primary period-integrity control for the sole live system of record. The **Register Data Quality + Entry bundle** runs in parallel so the August close is over clean data.

Whether an external architecture review adds value before the next phase: **No for Monthly Close v1** (OM's review *is* its spec). **Yes** for 5G-1B release-event shape, calc-core extraction, 5G-4a/4b, the 5G-3 CAE relationship, and the Plan Period rollover — those are the architecture-grade decisions where a focused review pays off (§5 "Review?" tags).

---

## 10. Immediate next three execution steps

All three are **non-code, parallel to 5G-1D, no freeze conflict, no approval inferred:**

1. **Stand up the recovery-remediation floor** (highest-severity/lowest-cost, all three reviews). Today: enable owner-login MFA (~15 min); create a backup-owner/recovery-access account (~15 min); take a fresh production `pg_dump` (the last restore point predates E2/2.1/Wk-5); make an off-device encrypted copy of that dump and of `~/Herndon-FOS-DB-Backups`; draft `docs/restore-runbook.md`; define the retention cadence (8 weekly / 6 monthly + mandatory pre-close/pre-correction dumps). Rehearse a staging restore once after Gate B settles.
2. **Draft the freeze-window specs** (docs-only): 5G-1B release-event shape (incl. Week-5 `wewe_*` terminal treatment + snapshot interaction); the Monthly Close v1 P1–P9 checklist + certification-record template; the Register Data Quality + Entry / TX-1 taxonomy scope; the Plan Period design-doc kickoff; the obligations end-state memo.
3. **Prepare the docs-only owner patches** (the full patch-target table is retained in the superseded 2026-07-12 draft's §7 "Canonical-document patch plan"; enumerated here): roadmap numbering + legacy-gate fold-in in `docs/phase-status.md`; the runModel freeze-language re-pin in `AGENTS.md`; the obligation-taxonomy one-pager; the `CODEX_STATUS.md` currency correction (5G-1D Slice-1/2 staging-accepted). **This full patch set remains UNAPPLIED and requires Adam's approval before it is applied** (the narrow Quicken/5G-1D currency corrections already staged in `AGENTS.md`/`CODEX_STATUS.md`/`docs/phase-status.md` are separate, owner-directed, and not the broader §7 patch plan).

---

## 11. Decisions still requiring Adam's approval

1. **D1 — Quicken historical-data archival policy (narrow; the cancellation itself is settled).** Quicken is retired and the OS is the sole live system of record (Adam-confirmed 2026-07-13); this is no longer an open question. The residual decisions are operational: (a) verify the retained Quicken data exports cleanly and capture the final-transaction boundary; (b) set a long-term archival/retention policy and storage location for the historical Quicken file (off-device, encrypted); (c) decide whether the archive is a one-time historical reference only or a periodic reconciliation source. **Do not assume the archive opens or exports until operationally verified.**
2. **D2 — Adopt the canonical roadmap principles** (§1): finish-5G-1D-first; recovery floor now; 1B before 1E; Monthly Close v1 file-based certify-don't-lock; split 5G-4 into 4a/4b; explicit extraction slot + freeze re-pin; Plan Period design target with minimum 2027 execution; docs-only fold-in cleanup.
3. **D3 — Gate C posture** on `repair_commitments_for_week` (retain / wrap / restrict-to-owner / revoke). 5G-1D-internal; this synthesis recommends wrap-or-restrict-to-owner as a mandatory pre-close control.
4. **D4 — Gate D activation timing (unresolved owner decision — not yet an architectural fact; C9).** Two legitimate branches, neither canonical until Adam decides:
   - **Option A — pre-freeze:** complete all remaining 5G-1D work (Slice 3 UI, Slice 6 prod inert deploy, readiness checks, Gates B/C/D/E) and, if separately approved, **activate before July 24.** Post-5G-1D planning/file-based work then proceeds without waiting on the calendar (5G phase-code *merges* still pause Jul 24 – Aug 10).
   - **Option B — post-freeze:** defer activation until after Aug 10, then run sequential half-close repair and the first Monthly Close v1.
   The readiness package's "default to post-freeze if the pre-freeze path becomes unsafe" is a *fallback*, not a pre-made selection.
5. **D5 — Physical funding-target unification** — adopt a single physical entity at 5G-4a, or keep goals and `planned_outflows` physically separate under a shared logical taxonomy? (Spec-gated at 4a either way.)
6. **D6 — Obligations end-state owner** — (a) budget_rules absolute-mode migration (WD → generated seed), (b) model reads dated obligations derived from `planned_outflows` via an explicit adapter, or (c) WD stays hand-maintained (reject consciously if chosen). The 2027 rollover is cheaper under (a) or (b).
7. **D7 — Golden-master recapture approval** for the Diablos/GLP WD baseline correction (never edit expected outputs without approval).
8. **D8 — Audit-log (L2) timing** — build `financial_audit_log` at 5J, or pull forward now on the "third owner correction in a quarter" trigger given the OS is the sole live record.
9. **D9 — Apply the broader docs-only owner patch set** (enumerated in §10 step 3; full patch-target table in the 2026-07-12 draft §7) and adopt this document as the canonical post-5G-1D roadmap. The pointer in `docs/phase-status.md` and the `CODEX_STATUS.md` currency banner are already in place; the *broader* §7 patch plan (freeze re-pin, full numbering/fold-in rewrite, etc.) is **not yet applied** and awaits this approval.
10. **D10 — Extraction-vs-rollover calendar-risk gate** (Calc-Core Extraction and Module Posture Amendment §6): if calc-core extraction timing threatens the 2027 operating deadline (window ends 2027-01-09), approve either (a) complete extraction before rollover, or (b) a narrowly scoped rollover against the existing engine with enhanced characterization + rollback controls. No default; a partially completed extraction may never be the rollover base.

---

## 12. Source artifact index

**The three foundational reviews (advisory inputs; non-authoritative). All three are now co-located under `docs/reviews/`, superseded for sequencing by this synthesis, and retained for provenance and architectural detail:**
- `docs/reviews/roadmap-architecture-review-2026-07-12.md` — RM (sequencing/numbering/structure).
- `docs/reviews/architecture-review-cash-planning-goal-funding-2026-07-12.md` — AR (5–10 year architecture).
- `docs/reviews/operating-model-control-review-2026-07-12.md` — OM (close/audit/recovery/operating model).

**Targeted application-architecture review + its amendment (advisory; incorporated narrowly, not a reopening of this synthesis):**
- `docs/reviews/application-modularization-review-2026-07-13.md` — Fable targeted application-architecture / modularization review (advisory source; not implementation authority; retained for provenance and architectural detail).
- `docs/post-5g-1d-roadmap-amendment-calc-core-extraction-2026-07-13.md` — **Calc-Core Extraction and Module Posture Amendment.** Widens the calc-core extraction charter (P6), sets the extraction test/module posture, confirms broader Register/Budget/view-layer modernization as post-rollover and trigger-based (P8), and adds the extraction-vs-rollover calendar-risk gate (§11 D10). Advisory; adopt per Adam approval.

**Prior synthesis (superseded by this document):**
- `docs/post-5g-1d-roadmap-synthesis-2026-07-12.md` — reached the correct operating conclusion that Quicken was canceled (Adam confirmed that operating state on 2026-07-13); superseded because its 5G-1D execution status and roadmap reconciliation are now outdated. Retained for provenance.

**Authoritative controls (win on conflict):**
- `AGENTS.md`; `CODEX_STATUS.md`; `docs/phase-status.md`.

**Load-bearing evidence cited:**
- `docs/phase-5f-1-migration.sql` (`model_year` on `cash_commitments` line 51; `weekly_reconciliations` has none; RPC `model_year <> 2026` reject).
- 5G-1D governance stack: `docs/phase-5g-1d-plan-2026-07-09.md`, `docs/phase-5g-1d-implementation-readiness-2026-07-10.md`, `docs/phase-5g-1d-snapshot-correction-procedure-2026-07-10.md`, the Gate-2 package (`docs/phase-5g-1d-gate2-*`).
- `docs/phase-5g-1c-2-e2-closeout-2026-07-11.md`; `docs/phase-5g-1c-2.1-hotfix.md`; `docs/phase-5g-1-spec-2026-07-07.md` (v1.4, Planned Outflows).
- `docs/funding-model-integrity-review-2026-07-08.md` (the shared upstream "funding review" all three cite); `docs/tx-1-candidate.md`; `docs/reviews/ui-flow-review-triage-2026-07-07.md`.

---

*Synthesis only. No code, SQL, schema, migration, RLS, RPC, test, or production/staging change. No BUILD_TS change. The three reviews are advisory inputs, not independent approved roadmaps; 5G-1D remains frozen and authoritative for its own scope; nothing here amends it. Not committed or pushed.*
