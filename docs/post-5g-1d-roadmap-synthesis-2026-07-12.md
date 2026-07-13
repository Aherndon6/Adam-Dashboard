> **SUPERSEDED (2026-07-13).** This prior-session draft is replaced by the canonical
> `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md`. It is retained for provenance
> and traceability only. Its operating conclusion that **Quicken had been canceled was correct** —
> Adam confirmed that operating state on 2026-07-13 (Quicken retired; the Financial OS is the sole
> live system of record; historical Quicken data retained as archive only). This draft remains
> superseded **not** because of that conclusion but because its **5G-1D execution status** ("Gate 2
> paused after Sub-phase 5; resume Sub-phase 6") and its **roadmap reconciliation** are now outdated:
> 5G-1D is staging-accepted at the RPC layer, with Slice 3 / Slice 6 / Gate B production activation /
> Slice 7 and Gates C/D/E still outstanding, and activation timing (Gate D) remains an open owner
> decision. Do not cite this draft as current; use the 2026-07-13 canonical synthesis.

# Post-5G-1D Roadmap Synthesis

**Date:** 2026-07-12
**Author:** Claude Code (local synthesis agent)
**Type:** Decision-ready synthesis of three 2026-07-12 Fable architecture reviews, grounded against the repository and authoritative status. **Docs only. No implementation authority.**
**Standing:** Advisory. If anything here conflicts with `AGENTS.md`, `CODEX_STATUS.md`, `docs/phase-status.md`, cleared 5G-1D scope, the Do Not Touch list, or Wendy-confirmed workflow, those controls win. This document does not amend any cleared scope, gate, contract, SQL, RPC, or execution step.

---

## 1. Grounding and authority

### 1.1 Repository state at synthesis time

- **HEAD:** `5cb80395b89d3d14435099be2a638330b787b0e5` — `docs(5G-1D): add Gate-2 staging execution package`.
- **Branch:** `main`; **in sync with `origin/main`** (both at `5cb8039`).
- **Working tree:** clean of tracked-file modifications. Only untracked files are present, including the three review artifacts and several AMEX-Gold / phase-5f-1.5 docs. This synthesis adds exactly one new untracked file.
- **Recent history confirms 5G-1D is actively executing** its staging gate stack (`5cb8039`, `ff80971` Gate-1 JWT claims, `4811990`/`aba36b4`/`04fc0a8` grant/registry/snapshot guards, `17b8d1f` cleared Slice-2 staging SQL package).

### 1.2 Authoritative sources used

- `AGENTS.md` — standing law: architecture, Do Not Touch, schema/migration conventions, role model, test gates.
- `CODEX_STATUS.md` — active phase pointer and gate history.
- `docs/phase-status.md` — the authoritative 5G sub-phase map (2026-07-08 renumber) and gate details.
- The three review artifacts named in §8.
- Cited in-repo evidence: the 5G-1D governance stack, `phase-5g-1-spec` v1.4, 5G-1C-2 E1/E2 closeouts, the 5G-1C-2.1 hotfix record, the AMEX-Gold register audits.

### 1.3 Current authoritative facts that override the reviews' framing

The three reviews were authored as a snapshot and lag the live state on two load-bearing points. **Where they diverge, the following facts govern this synthesis:**

- **5G-1D is frozen and actively executing.** Its **Gate 2 is paused after Sub-phase 5**; **Sub-phases 3, 4, and 5 passed**; **the next execution action is Gate 2, Sub-phase 6.** No roadmap-derived work in this document may interrupt, reorder, or alter 5G-1D. (Note: `CODEX_STATUS.md` prose still reads "implementation NOT STARTED" in places; that prose is stale against the live gate execution shown in git history. This synthesis does **not** edit `CODEX_STATUS.md`; the currency correction is flagged in §7 as a future owner-approved patch.)
- **Quicken is already cancelled.** The reviews' "make backup/restore a precondition to Quicken cancellation" language is obsolete. The retained Quicken data is a historical archive / comparison source; bank-feed functionality was not a material dependency. Backup/restore readiness is therefore an **immediate remediation item**, not a pre-cancellation gate. The retained archive must **not** be assumed usable until operationally verified. Full rewrite in §3.B.

### 1.4 The four evidence tiers (how to read every claim below)

- **(a) Current repository fact** — verifiable in the tree or authoritative docs. Example: `weekly_reconciliations` has no `model_year` column; `goal_funding_snapshots` carries `CHECK (week_num BETWEEN 1 AND 31)`.
- **(b) Fable recommendation** — an advisory input from one of the three reviews. Carries no build authority.
- **(c) Claude Code synthesis / inference** — my reconciliation, sequencing, or interpretation. Labeled **[inference]** wherever it is not a direct restatement of (a) or (b).
- **(d) Requires Adam's approval** — a decision reserved to the owner; collected in the §5 decision register.

**The three reviews are advisory inputs, not implementation authority.** Nothing in them — and nothing in this synthesis — authorizes code, SQL, schema, migration, RLS, RPC, test, or production/staging change. Every future build step retains its own gates and approvals.

---

## 2. Cross-review agreement matrix

Reviews are abbreviated: **RM** = `roadmap-architecture-review`, **OM** = `operating-model-control-review`, **AR** = `architecture-review-cash-planning-goal-funding`.

Disposition vocabulary: **Approve** (roadmap principle, no schema commitment), **Approve-mod** (approve with the modification noted), **Defer**, **Reject**, **Spec-required** (needs a dedicated specification before any approval).

| # | Recommendation | Reviews | Agreement / conflict | Repository evidence | Disposition | Confidence | Calendar / dependency driver |
|---|---|---|---|---|---|---|---|
| 1 | **Plan Period / 2027 rollover** as first-class design | RM (P0), AR (R1/MC-1), OM (#9/P4) | Strong agreement; no conflict | No `model_year` on `weekly_reconciliations`; snapshot `CHECK week_num 1..31`; 5G-1D wrapper rejects `model_year<>2026`; `cash_commitments` RLS `WITH CHECK model_year=2026`; WD = 31 literals; window ends 2027-01-09 | **Spec-required** (design in 2026; execute as re-baseline) | High | Model window exhaustion ~26 wks out; hard calendar deadline |
| 2 | **Register Data Quality + Entry bundle** (TX-1 + reimbursement home + 5E-11 entry speed + REG-4) pulled before 5G-2 | RM (P0), OM (#8, exception catalog), AR (CP-3-adjacent) | Agreement on need; RM sequences it, OM ties it to data-quality certification | TX-1 candidate doc; Jabian reimbursement homeless since 5E-10; 5E-11 deferrals; `budget_line_rules.category_key`→`categories` FK gap (wishlist 39) | **Approve** (as a bundle principle); scope/schema **Spec-required** for the TX-1 taxonomy slice | High | Formerly served the Sep parallel-month verdict; **repurposed** (§3.B) to data-integrity, not a cancellation gate |
| 3 | **5G-1B (holding releases) before 5G-1E** | RM (P0), OM (§11.4/§11.6), AR (R-seq #3, MC-4) | Unanimous; the current map (1E before/without 1B) is called wrong on its own terms | phase-status.md: 1E "consumes 5G-1B releases," yet 1B is "Deferred" and 1E is sequenced; 5G-1C-2.1 set `funded_amount` = cumulative progress ≠ cash held | **Approve** (resequence principle); release-event shape **Spec-required** | High | RCCL payout ~Cal Wk 30 (inside Alaska freeze); DCL ~Cal Wk 41 |
| 4 | **Monthly Close v1** (repeatable close, file-based first) | OM (§2–§3, primary), RM (reframe 5G-1F, P1) | Agreement; OM supplies the full design, RM the slot | 5G-1F "Audit Minimum Viable Close" reserved, empty; E2-closeout template exists as the pattern | **Approve** (file-based v1 as roadmap principle) | High | First formal close = July 2026 data, post-freeze |
| 5 | **Certify-and-detect-divergence vs hard locks** | OM (§2.2, §3, primary), RM (close/lock, §2.1/§5), AR (SM-5) | Agreement; OM argues certify-don't-lock explicitly; RM wants "closed-period edit detection"; no conflict | Register rows + BLR editable in closed periods, no detection; `posted_date`/5F-3 attribution design; standing rule against fixing month boundaries via `starting_balance` | **Approve** (certify + divergence detection; narrow locks only) | High | Feeds first formal close; before dual-actuals hardening |
| 6 | **Backup / restore remediation** | OM (§8, headline; P0), RM (P0), AR (MC-9/R6) | Unanimous, highest-severity/lowest-cost | Free plan, no PITR; last full restore point 2026-07-09 predates E2 seed + 2.1 correction + Wk-5 recon + all Register entry since; single-laptop `pg_dump`; no MFA, no backup owner | **Approve** (immediate remediation — **not** a Quicken gate; §3.B) | High | **Immediate** — Quicken already cancelled removes the redundant replica |
| 7 | **Calc-core extraction** given an explicit slot; re-pin freeze language | RM (P1, §2.3), AR (R3/FE-1, house-law), OM (implicit via L2 sequencing) | Agreement it must precede 5G-4 / Budget-identity / rollover execution | AGENTS.md "runModel frozen through 5G-2" now ambiguous post-renumber; 5G-1A.5 / 1C-1 / C3 all landed as in-body freeze exceptions; legacy 5G-2.5 gate unmapped | **Approve** (slot + freeze re-pin principle); extraction spec + test-migration **Spec-required** | High on need; medium on exact slot | Gates 5G-4, Budget identity, rollover safety |
| 8 | **Split 5G-4 into 4a (goal data-model, read-side) / 4b (write capability)** | RM (§1.6, P1), AR (R2/SO-1) | Agreement; mirrors 6A/6B pattern | 5G-4 "Dynamic Goal Management" is one undifferentiated slot; goal-target triplication (registry / hardcoded fallback / `goalFundedAmounts` / retRem constants); `ira_cpa_cleared` session-only | **Approve** (split principle); the 4a data-model contract **Spec-required** | High | Before any 5G-5 Goal Admin UI |
| 9 | **Goals vs planned_outflows** — logical unification | AR (SO-1/R2, primary), RM (obligations §2.4/6.3), OM (indirect) | Agreement on *logical* domain fault; **physical** unification is AR's proposal alone | RCCL/DCL: bills-with-due-dates modeled as goals → AMEX holding hack (5G-1A) → excluded-from-snapshots → 5G-1C-2.1 emergency SQL bypass | **Spec-required** — logical taxonomy approvable now; a single **physical** funding-target entity is **not** approved now (§3.D) | High (logical); medium (physical shape) | 5G-4 is "last cheap venue" (AR); product-forced by next new goal |
| 10 | **Obligation taxonomy one-pager** | RM (§2.4/6.3 decision 2), AR (CP-3/R7) | Agreement; cheap, high-leverage | Four representations coexist: WD/budget_rules, `cash_commitments`, `planned_outflows`, goals-with-dueWeeks; ownership rules are tribal | **Approve** (docs-only one-pager + end-state *direction*; end-state *owner* decision is §5.d) | High | Before 5G-2 app build |
| 11 | **`financial_audit_log` (row-level mutation history)** | OM (L2, §4.3, primary), RM (audit §4/§5 sec-16), AR (part of MC-2) | Agreement on eventual need; OM scopes it precisely as L2 trigger table | Security backlog item 16; commitments fully attributed, `weekly_reconciliations` has no attribution, Register edits unlogged | **Spec-required** (staging-first, own gate); **Defer** build to 5J unless pull-forward trigger fires | High (content); medium (timing) | OM pull-forward: 3rd owner correction/quarter (Quicken-cancellation trigger already **moot** — see §3.C) |
| 12 | **Domain funding-event ledger (business-intent / execution events)** | AR (MC-2/SO-3/R4, primary), RM (event-ledger convention §2.4), OM (L3, §4.3) | Agreement it is a distinct concept; **OM says build L3 only on demonstrated need**, AR wants a convergence *commitment* | `weekly_tasks` positionally keyed; 5G-1B resolver is an adapter; Option C ledger acknowledged, unscheduled | **Spec-required**; **Defer** build. Do **not** collapse with #11 (§3.C) | Medium | Payout-forced ~Cal Wk 30 (1B releases); rides 1B/1E |
| 13 | **Goal lifecycle / history / scope-change governance** | AR (GM-1..GM-5, MC-3/MC-10, primary), RM (§1.6 5G-4a, wishlist-34), OM (correction matrix §5.1) | Agreement; AR most detailed | No legal-transition matrix (verified absent in 6A/5G docs); registry has no history (TD-10 missing `updated_at`); wrapper hard-stops on eligible-nine drift; wishlist 34 queued | **Spec-required** (transition matrix + registry history + scope-change runbook, packaged with 4a) | High | Product-forced by first new goal (wishlist 34) |
| 14 | **Roadmap-numbering cleanup** (retire 5J/5L dupes; resolve legacy-gate fold-in) | RM (§1.5/§6.3 decision 3, primary), AR (CP-2/R5/A6) | Agreement; docs-only, cheap | Four numbering generations coexist; 5J ≈ 5G-5+5G-6; 5L ≈ 5I-4; phase-status.md itself flags the fold-in as unresolved | **Approve** (docs-only; **[inference]** do it as an owner-approved patch, §7) | High | Before load-bearing gates get silently lost |
| 15 | **Run-time visibility trio** (load-failure banner, Review-Required verdict render, snapshot-gap nag) | OM (§10 #3, M9, primary), RM (health surface §5 #7), AR (MC-8 variance/exception ledger) | Agreement; all three already specified in prior phases — "finishing, not designing" | loadAll sets connected badge green regardless of per-table failure; `_reviewRequired` computed but unrendered (5F-1 deferral) | **Approve** (small display-lane slices, post-freeze) | High | Post-freeze; before first certified close ideally |
| 16 | **Quicken archive posture** | OM (§8.3 Quicken-as-recovery-control), RM (cancellation precondition), AR (SM-4/MC-9) | **Reviews are stale**: all treat cancellation as future | Authoritative fact (§1.3): Quicken **already cancelled**; archive retained, usability unverified | **Approve-mod** (rewrite per §3.B: archive = historical reference, statements+backups = reconstruction foundation) | High | Immediate — see §3.B |

Additional agreements outside the mandatory list, carried into later sections: RM's "two-lane process (money-path vs display-path)" (§6.4 velocity), the migration-kit template and RPC/grant inventory (RM §2.3/§5, OM §9), AR's money-representation standard (MC-6) and liquidity-reserve entity (MC-5), OM's weekly-recon accountability + Gate C resolution (M6/M8).

---

## 3. Conflict resolution

### 3.A First-close timing — reconcile OM's file-based July rehearsal with RM's Register-bundle pull-forward

**The two are not in conflict; they serve different gates and run in parallel.** [inference]

- **OM** recommends the **first formal month-end close** (July 2026 data) be executed **file-based** (checklist + evidence pack + committed certification record, zero new code), in the window immediately after 5G-1D's post-freeze activation and half-close gap repair. Its purpose is to exercise the *close ritual* and produce the *certification + basis watermark* primitive.
- **RM** recommends pulling the **Register Data Quality + Entry bundle** earlier so data quality is sound before downstream phases. Its original stated purpose — serving the September Quicken-cancellation verdict — is **obsolete** (Quicken already cancelled). The bundle's *residual* purpose (data integrity for a system that is now the primary record) remains valid and, if anything, more urgent.

**Distinction the synthesis draws between three close grades** [inference, building on OM's model]:

1. **Rehearsal close** — the *first* file-based execution of the July checklist. Goal: prove the ritual, surface checklist defects, produce the first certification record. Expect one recalibration of exception severities afterward (OM §11.8). Not decision-grade; it is a dress rehearsal that happens to produce a real certification.
2. **Second-iteration close** — the August close (~early September). The checklist is now stable; the operator has one recalibration behind them. This is where statement-attestation mechanics settle.
3. **Decision-grade close** — a close whose certified aggregates are trusted as the authoritative period record. With Quicken already gone, **there is no longer a parallel replica to cross-check against**, so a close reaches decision-grade only when (i) the ritual has stabilized (≥ the second iteration), (ii) the backup/restore floor exists (§3.B), and (iii) the surfacing trio (§2 #15) is live so the operator can trust that what they certified is what actually loaded.

**Resolution:** run OM's July file-based **rehearsal close** first (no code), and land the Register bundle's data-quality work **in parallel** during the same post-freeze window so the *second-iteration* close is over clean data. Neither blocks the other; both depend only on 5G-1D post-freeze activation and Adam's time. **[inference]**

### 3.B Quicken — rewrite all recommendations to post-cancellation reality

**Governing fact:** Quicken is already cancelled. Historical data is retained as an archive / comparison source; bank-feed functionality was never a material dependency; the archive's usability is **unverified**.

Consequences for the reviews' recommendations:

- **Remove all "gate cancellation" / "precondition to cancellation" language.** OM §8.3 ("Quicken is a recovery control," "add a recovery-readiness gate to cancellation"), RM top-move #4 ("make backup/restore maturity a precondition to Quicken cancellation"), and RM §5 item 2 are **superseded**. The decision they gate has already been made.
- **Backup/restore becomes immediate recovery remediation, not a gate.** Because cancellation already removed the redundant replica, the OS is *already* the sole live system of record. The backup floor (scheduled dumps, offsite encrypted copy, tested restore, backup owner, MFA) is now an **open exposure to close now** (§9), not a checklist item to satisfy before a future event.
- **The retained Quicken archive is a historical reference, not a live replica.** It can inform reconstruction and historical comparison but must not be treated as an authoritative second copy. **Do not assume it opens or exports until that is operationally verified** (§9, item V1–V2).
- **Statements and backups are the current reconstruction foundation.** With no live parallel system, the missing-transaction detector during any given month is the **bank/card statement diff** plus fresh **production backups** — not a Quicken comparison. The month-end close checklist's P4 (missing-transaction sweep) must read "statement diff is the primary detector" without the "Quicken comparison is the second" clause the reviews assumed.

**[inference]** The reviews' underlying *technical* recommendations (cadence, offsite copy, rehearsed restore, MFA, backup owner) are correct and become *more* urgent under cancellation; only their *framing as a cancellation gate* is void.

### 3.C Audit log vs funding-event ledger — keep them distinct

Two different primitives, repeatedly at risk of being collapsed into one:

- **`financial_audit_log` (row-level mutation history)** — OM's **L2**: one generic `financial_audit_log(table_name, row_pk, action, old_row jsonb, new_row jsonb, actor, at)` populated by AFTER triggers on `transactions`, `weekly_reconciliations`, `goal_funding_snapshots`, `budget_line_rules`. Answers *who changed which row, from what, to what, when*. It is table-agnostic, trigger-driven, read-only, and does not model business meaning.
- **Domain funding-event ledger (business-intent / execution events)** — AR's **MC-2 / Option C**: an append-only ledger asserting *intent and execution* — a transfer was decided, a holding was released, a set-aside accrued. It carries semantics (event type, custodian, provenance) that a row-diff cannot express, and is the durable identity `weekly_tasks` positional keying lacks.

**Are both needed, and when?** [inference, reconciling OM and AR]:

- **Both are needed, at different phases, for different questions.** The audit log answers auditability ("what changed since close"); the event ledger answers funding semantics ("why did this money move, and did the intended transfer execute").
- **Audit log:** design as L2, **staging-first with its own gate, targeted at 5J** (or pulled forward on OM's trigger — noting the "Quicken cancellation" trigger is already moot, so the live trigger is "third owner correction in a quarter"). Additive, sits on frozen-adjacent tables.
- **Event ledger:** its **first forcing function is 5G-1B holding releases** (~Cal Wk 30 payout). AR's convergence point is right: schedule it so that transfer identity, release events, and correction audit-grain land as **one** ledger, not three partial stores — but build only when 1B actually needs it (OM's "L3 only on demonstrated need" restraint applies to speculative build, not to the 1B-forced slice).

**Do not collapse them into one table without evidence.** A trigger-fed row-diff cannot carry event semantics; an intent ledger should not be burdened with cosmetic-edit noise. Keep two primitives; let them share the *append-only + provenance + RLS-revoked-writes* convention (RM's "one event-table convention, instantiated per domain").

### 3.D Goals vs planned_outflows — logical unification vs physical table unification

- **Logical/domain unification is approvable now as direction.** [inference] The taxonomy fault is real and evidenced (RCCL/DCL broke production twice). A **one-page obligation taxonomy** (§2 #10) that declares which system owns which obligation class and names the migration events is docs-only, cheap, and prevents recurrence. Approve the *taxonomy artifact*; approve the *recognition* that goals and `planned_outflows` are one domain with different policies.
- **A single physical funding-target entity is NOT approved now.** AR's SO-1 (collapse goals + `planned_outflows` into one physical entity with type/policy fields) is a deep schema change touching the waterfall's registry source, the snapshot contract, and the eligible-nine set the 5G-1D wrapper freezes. It requires a **dedicated 5G-4 architecture specification** and must not be inferred from taxonomy approval.
- **Venue and timing:** AR is right that 5G-4 is the last cheap venue (unifying after both subsystems have independent UIs/ledgers/habits roughly doubles the cost). But "cheap venue" is an argument for *specifying it at 5G-4*, not for approving the physical merge today. The 4a data-model slice (§2 #8) is where the entity shape gets designed under review.

**Resolution:** approve the logical taxonomy one-pager and the direction; route the physical entity to a dedicated 5G-4a specification; do not touch the registry/snapshot contract in the interim. **[inference + AR R2]**

### 3.E Rollover vs Plan Period — minimum 2027 scope vs reusable abstraction

Two scopes, and the risk is overbuilding a multi-scenario planning platform when a one-year re-baseline is what the calendar demands. [inference, reconciling RM and AR]:

- **Minimum 2027 implementation scope (what the deadline forces):** the ability to represent and operate a second plan year — `model_year` as a real dimension on `weekly_reconciliations`; per-year relaxation of the snapshot `week_num` CHECK (2027 is a full year, not the 31-week mid-year artifact); RPC/wrapper year-pins parameterized off `2026`; WD/opening-balance/calendar-offset/current-week-clamp constants sourced per year; a 2027 opening-anchor procedure (the E2 Value-Card pattern, generalized). This is the **non-negotiable** deliverable.
- **Broader reusable Plan Period abstraction (AR's MC-1):** a first-class period entity (id, start date, week count, opening anchors, parameter set, week-numbering rules) of which every year-pin becomes an instance value. This is the *elegant* form and the right long-term target.

**Resolution:** design the **Plan Period abstraction on paper** (AR R1) so 2027 is implemented as its *first instance* rather than a bespoke migration — but scope the *2027 execution* to exactly the minimum above. Do **not** build multi-scenario / what-if plan variation, multiple concurrent horizons, or configurable planning platforms as part of the rollover. The abstraction earns its keep by making year three trivial; it does not justify platform features 2027 does not need. **[inference]**

### 3.F Close certification vs locks — what is immutable, what stays correctable, what is narrowly restricted

Following OM's certify-don't-lock doctrine, with the specific record dispositions: [OM §4.2, §5.1 + inference]

- **Immutable (append-only, never edited/deleted):** certification records; reopen records; the opening anchor (already guarded — nine-row guard); evidence artifacts (hash-pinned); terminal commitment audit fields (already enforced). Certifications are immutable; **the data they certify is not.**
- **Correctable underlying data (must stay editable):** Register rows (Wendy's daily flow), BLR plan lines (already history-preserving via interval close+insert), weekly balances via the sanctioned paths, snapshot values via the governed correction paths. Weekly re-save is a *feature* for same-day slips; register editability is the daily workflow. The control for these in closed periods is **divergence detection**, not prevention.
- **Narrow preventive restrictions still required** (the parts where OM does want a hard edge):
  - **`deleteRecon` restricted for anchored weeks** — a direct REST DELETE against the close basis (`weekly_reconciliations`) must be blocked once a week is anchored. (5G-1D posture register #9.)
  - **Direct-write revokes on `weekly_reconciliations`** — the close basis is currently silently overwritable by upsert re-save with no attribution; revoke direct writes and funnel through the RPC (posture register #4–#8). This is a **mandatory pre-close control**, not optional hardening.
  - **`repair_commitments_for_week` posture (Gate C)** — REST-callable by any financial writer today, able to mutate terminal rows and `balance_basis` for closed weeks; OM recommends into Gate C: **wrap or restrict to owner, supervised, evidence-backed.** (This is a 5G-1D-internal open decision the review *feeds*; it does not reopen 5G-1D scope.)
  - **No hard deletes in certified months** — prefer reversal/offsetting entries over edit/delete for certified scope until the audit log (L2) exists.

**Anchored-reconciliation deletion / direct-write posture:** the anchored recon row is the close basis; its deletion or unattributed overwrite is the single sharpest control gap OM identifies. The narrow restrictions above are the resolution — immutability of the *certification*, correctability of the *data* through governed paths, and a hard block only on *direct destructive/unattributed writes to the anchored basis*.

---

## 4. Recommended authoritative roadmap

**Sequencing philosophy** [inference]: the macro shape (integrity → planned outflows → allocation → goal management → close hardening) is sound and not inverted. The changes are at the seams: resequence 1B before 1E, give extraction and the rollover explicit slots, split 5G-4, and treat backup/restore + the Register data-quality bundle as **immediate** work (no longer Quicken-gated).

**Date discipline:** the only repository-anchored calendar facts are the **Alaska freeze (Jul 24 – Aug 10, no 5G merges)**, the **model window end (2027-01-09)**, and the **dated cruise payouts (RCCL ~Cal Wk 30, DCL ~Cal Wk 41)**. Month names below (Oct/Nov/Dec) are **Fable-recommended planning targets**, not repository facts; where a date depends on the freeze or an unresolved Gate D posture, the assumption is stated and only relative sequencing is asserted. **[inference on all ordering]**

Per-item legend: **Pred** = predecessor dependencies · **∥Plan** = can planning run in parallel · **ImplRisk** / **ProdRisk** · **Cal** = calendar driver · **Decision** = required decision/spec · **Frozen?** = touches runModel or frozen-adjacent surfaces.

### 4.0 In-flight (do not disturb)

- **Complete 5G-1D Gate 2 + remaining activation work.** Purpose: finish the frozen weekly-closeout state machine. **Pred:** its own gates (Gate 2 resumes at Sub-phase 6; Gates A–E). **∥Plan:** yes — all specification work below may proceed in parallel *as docs*. **ImplRisk:** managed by its own gate register. **ProdRisk:** high if disturbed — hence frozen. **Cal:** Gate D activation-timing decision (pre- vs post-freeze; readiness default = post-freeze). **Decision:** Gate C/D (5G-1D-internal; this synthesis only feeds them). **Frozen?** — it *is* the frozen surface.

### 4.1 Immediate, non-code (start now, in parallel with 5G-1D)

- **Recovery remediation floor.** Purpose: close the sole-system-of-record exposure created by Quicken cancellation. **Pred:** none. **∥Plan:** yes. **ImplRisk:** none (ops). **ProdRisk:** none to build; **removes** an unrecoverable-loss scenario. **Cal:** immediate. **Decision:** §5.A (approve the cadence). **Frozen?** No. (Detail in §9; charter in §6.)
- **Roadmap docs cleanup** (numbering + legacy-gate fold-in). Purpose: stop load-bearing gates from being lost. **Pred:** none. **∥Plan:** yes. **Risk:** none. **Cal:** before the extraction/Budget-identity gates are needed; **[inference]** ideally soon, since 5G-1D is executing and its freeze-language references the ambiguous numbering. **Decision:** §5.A (approve as owner patch, §7). **Frozen?** Docs only.
- **Obligation taxonomy one-pager** + D1 scope clarification. Purpose: prevent the RCCL/DCL misfiling class. **Pred:** none. **∥Plan:** yes. **Risk:** none. **Cal:** before 5G-2 app build. **Decision:** §5.A (artifact); end-state owner = §5.B. **Frozen?** Docs only.

### 4.2 Freeze window (Jul 24 – Aug 10): specification only, no merges

- **Prepare specs:** 5G-1B release events; Register Data Quality + Entry bundle scope; Monthly Close v1 checklist; Plan Period design doc kickoff. Purpose: use the freeze for paper. **Pred:** none. **∥Plan:** the window *is* the parallel-planning window. **Risk:** none. **Cal:** freeze rule. **Frozen?** No code.

### 4.3 Post-freeze activation & repair

- **5G-1D post-freeze activation + sequential half-close gap repair.** Purpose: activate the wrapper, repair freeze-period half-closes (~weeks 6–9). **Pred:** 5G-1D Gate 2 complete; Gate D decision. **∥Plan:** n/a. **ImplRisk:** medium (sequential repair). **ProdRisk:** medium. **Cal:** Gate D post-freeze default. **Frozen?** Yes — 5G-1D's own surface.
- **Register Data Quality + Entry bundle** (TX-1 taxonomy/validation/cleanup, reimbursement home, 5E-11 typeahead/payee/ABC, REG-4 uncategorized count). Purpose: data integrity for the primary record. **Pred:** none hard; ideally before the second-iteration close. **∥Plan:** yes. **ImplRisk:** low-medium (mostly display/validation; TX-1 adds a small owner-executed category surface). **ProdRisk:** low. **Cal:** before the August close ideally. **Decision:** TX-1 taxonomy = §5.B (spec). **Frozen?** No (Register schema is Do-Not-Touch for *fake* rows; TX-1 category additions are owner-executed additive).
- **Diablos/GLP WD baseline correction** + golden-master recapture. Purpose: projections are knowingly understated (WD array gap). **Pred:** none. **∥Plan:** yes. **ImplRisk:** low (input-data correction) but **touches WD** — must recapture golden masters. **ProdRisk:** low. **Cal:** before 5G-1B and later planning features want a correct baseline. **Decision:** golden-master recapture needs Adam approval (never edit expected outputs without it). **Frozen?** WD is Do-Not-Touch-adjacent; correction is data, not `runModel` logic — confirm scope in the slice spec.

### 4.4 Holding lifecycle → hard invariant

- **5G-1B holding→payout release semantics.** Purpose: model the cruise-deposit releases so the AMEX invariant can become true. **Pred:** Diablos/GLP baseline (for clean recapture); its own release-event spec. **∥Plan:** spec during freeze. **ImplRisk:** high — a runModel freeze exception with real-money release-vs-cumulative-progress semantics that must reconcile with snapshot meaning; scope it tightly like 1A.5. **ProdRisk:** medium-high. **Cal:** **before Cal Wk 41 (DCL); RCCL divergence clock starts ~Cal Wk 30** (inside freeze). **Decision:** §5.B (release-event shape spec) + runModel freeze exception (§5.A-adjacent, Adam). **Frozen?** **Yes** — runModel change.
- **5G-1E invariant hardening** (AMEX attribution advisory → hard). Purpose: promote the one-sided advisory to a hard two-sided gate. **Pred:** **5G-1B (hard dependency)** + the 5G-1D RPC-side auto/holding exclusion guard rider. **∥Plan:** spec after 1B shape known. **ImplRisk:** medium. **ProdRisk:** medium. **Cal:** after 1B releases exist. **Frozen?** Frozen-adjacent (consumes snapshot/holding state).

### 4.5 Close, visibility, allocation foundation

- **Monthly Close v1** (reframed 5G-1F, file-based). Purpose: repeatable certification + basis watermark + closed-period divergence detection. **Pred:** 5G-1D post-freeze activation (fully-closed predicate). **∥Plan:** checklist authored pre-freeze. **ImplRisk:** low (file-based, no code for v1). **ProdRisk:** low. **Cal:** first close = July data, post-freeze; second = August (~early Sep). **Decision:** §5.A (adopt the operating model) + Gate C posture feed. **Frozen?** No (composes weekly primitives).
- **Run-time visibility trio** (load-failure banner, Review-Required verdict text, snapshot-gap nag). Purpose: you cannot certify what you cannot see fail. **Pred:** none. **∥Plan:** yes. **ImplRisk:** low (display-lane). **ProdRisk:** low. **Cal:** before decision-grade closes. **Frozen?** No.
- **5G-2 Planned Outflows Foundation** (prod DDL + app build; Mint seed). Purpose: the sinking-fund/save-up-bill system. **Pred:** obligation taxonomy end-state direction; Mint vendor/amount/date confirmation (external); `showCashPlanning` enablement; ES-module + static-server workflow. Staging DB/security layer already validated (2026-07-08). **∥Plan:** yes. **ImplRisk:** medium. **ProdRisk:** medium (first new prod table since snapshots). **Cal:** hold until Register bundle + 1B land; late-Sep/Oct realistic. **Decision:** prod DDL approval (Adam). **Frozen?** No (new tables, conforming policies).

### 4.6 Allocation, extraction, goal governance

- **5G-3 Cash Allocation** (derived Spoken For / Free to Use). Purpose: derived allocation view. **Pred:** 5G-2; **defined relationship to the 5F-1 Cash Availability Engine** (avoid two "available cash" numbers); balance-source rule + Protected enumeration decisions; 1B for AMEX Spoken-For correctness. **∥Plan:** spec in Oct alongside rollover. **ImplRisk:** medium. **ProdRisk:** low (derived, no stored balances). **Cal:** post-5G-2. **Decision:** §5.B (5G-3 spec must answer the CAE relationship). **Frozen?** Consumes engine outputs; no runModel change if kept derived.
- **Calc-core extraction** (re-slotted legacy 5G-2.5). Purpose: convert freeze exceptions into module changes; give the rollover a place to change constants; give 5G-4 a testable waterfall API. Reify FE-1's four seams (eligible set / capacity / allocation policy / decision emission); decide skip-vs-break deliberately under golden masters; externalize constants (MC-7). **Pred:** golden masters (exist); the test-migration plan (1,400+ source-pattern tests will need rewriting). **∥Plan:** spec earlier; execute here. **ImplRisk:** high (large mechanical diff + hidden test-suite migration). **ProdRisk:** medium (bounded by golden masters). **Cal:** before 5G-4 and before rollover execution. **Decision:** §5.B (extraction + test-migration spec); re-pin freeze language (§5.A/§7). **Frozen?** **Yes** — move-only under golden-master identity; this is the phase that *un*-freezes runModel per spec.
- **5G-4a goal / funding-target data-model governance** (read-side). Purpose: single source of truth for targets/status/flags; `ira_cpa_cleared` persisted; generalize the eligible-set contract; registry history (MC-3); transition matrix (GM-1); scope-change runbook (MC-10); wishlist-34 goals executed under the new contract; decide whether the physical funding-target unification (§3.D) lands here. **Pred:** extraction (for a testable waterfall API); the 5G-1D nine-goal snapshot scope-change contract. **∥Plan:** spec during Sep-Oct. **ImplRisk:** medium-high. **ProdRisk:** medium (touches registry beneath the governed snapshot layer). **Cal:** before any 5G-5 UI; before the first new goal ideally. **Decision:** §5.B (the 4a data-model + physical-entity spec). **Frozen?** Frozen-adjacent (registry feeds the waterfall).
- **5G-4b write capability.** Purpose: goal CRUD + reprioritization with GR-A1-class identity gates and confirmation flows; the zero-outflow identity committed test (legacy 5G-4b); earmark adapter into the 5F-1 engine (input layer only, one reservation contract per SO-2). **Pred:** 5G-4a (data model must stabilize first); extraction. **∥Plan:** spec after 4a. **ImplRisk:** **highest in the roadmap** — mutates waterfall inputs on a live model. **ProdRisk:** high (wrong waterfall prescribes wrong real transfers under live Wendy operation). **Cal:** 2027 Q1 realistic. **Decision:** §5.B. **Frozen?** **Yes** — waterfall-input writes.
- **Goal Admin UI** (5G-5). Purpose: owner UI over 4b writes. **Pred:** 4b stable; transition matrix enforceable (else a click reproduces the IRA deadlock class). **∥Plan:** after 4b. **ImplRisk:** medium. **ProdRisk:** medium. **Cal:** after 4b. **Decision:** none new beyond 4a/4b specs. **Frozen?** No (UI over governed writes).

### 4.7 Plan Period / 2027 rollover

- **Plan Period specification** (AR R1). Purpose: design the period abstraction so 2027 is its first instance (§3.E). **Pred:** understanding of every year-pin (schema/RPC/engine/constants). **∥Plan:** yes, Sep-Oct target. **ImplRisk:** design-only. **Cal:** approved before November (Fable target). **Decision:** §5.B. **Frozen?** Design touches frozen objects on paper only.
- **Staging rehearsal** of the rollover. Purpose: prove the migration across reconciliation/commitments/snapshots/wrapper before December. **Pred:** the spec; staging Supabase. **ImplRisk:** medium. **ProdRisk:** none (staging). **Cal:** November (Fable target). **Frozen?** Amends objects the 5G-1D contract froze — **needs migration authority over frozen objects, resolved on paper first.**
- **Production execution.** Purpose: cut over to 2027. **Pred:** rehearsed staging pass. **ImplRisk:** high. **ProdRisk:** **highest operational** — a failed rollover halts weekly operations (reconciliation writes reject/collide). **Cal:** late Dec / before 2027-01-09 (hard deadline). **Decision:** §5.A (execute) + prod DDL approval. **Frozen?** Yes.
- **2027 opening anchor.** Purpose: seed the new year's opening anchor via the generalized E2 Value-Card pattern. **Pred:** production execution. **Cal:** at/after cutover. **Frozen?** Yes (anchor seed, owner-run).

### 4.8 Audit tiers and later hardening

- **`financial_audit_log`** (L2 row-mutation history). Purpose: mechanical "what changed since close." **Pred:** 5G-1D shipped (sits on frozen-adjacent tables). **∥Plan:** yes. **ImplRisk:** low-medium (trigger table). **ProdRisk:** low (additive, no grants). **Cal:** 5J, or pull-forward on the live trigger (3rd owner correction/quarter). **Decision:** §5.B (staging-first spec + gate). **Frozen?** Frozen-adjacent (triggers on frozen tables).
- **Domain funding-event ledger** (L3 / Option C). Purpose: durable transfer identity + release + intent/execution semantics. **Pred:** 5G-1B (its first forcing function). **∥Plan:** spec with 1B. **ImplRisk:** medium. **ProdRisk:** low-medium. **Cal:** rides 1B/1E; not later than the first phase that would otherwise create a second event store. **Decision:** §5.B. **Frozen?** No (new append-only table). **Do not build speculatively** (§3.C).
- **Later close hardening** (5G-6, absorbs 5J remainder). Purpose: promote the file-based close to schema; mechanical divergence; read-only close card. **Pred:** stable close ritual (≥3 iterations) or Quicken-retirement trigger (already fired). **Cal:** Oct-Nov+. **Frozen?** No.
- **Splits (5I)**, **Transfers (5K)**, **Import readiness** (unlettered, last). Purpose: data-feature ladder. **Pred:** splits before transfers before import; import also needs posted_date rules (former 5F-3), TX-1 validation, dedup design. **Cal:** 2027. **Decision:** 5K charter now even if built later (RM §5 #6). **Frozen?** No.
- **5H Register capture speed + mobile quick-add.** Purpose: entry friction relief. **Pred:** **reversal of the 5D-2 "Transactions is desktop-only" decision** (hidden dependency — mobile nav has no Transactions entry). **Cal:** 2027. **Frozen?** No. Note: the cheap 5E-11 display wins are pulled into the Register bundle (§4.3), leaving 5H's expensive mobile-layout part for later.

---

## 5. Decision register

### 5.A — Recommended for Adam to approve **now** (roadmap principles only; conservative; no schema commitments)

1. **Backup/restore recovery remediation is immediate work** (not a Quicken gate): scheduled dumps, offsite encrypted copy, backup owner, MFA, drafted restore runbook, one staging rehearsal. (§9)
2. **Resequence 5G-1B before 5G-1E**, complete before Cal Wk 41. (Principle; shapes are spec-gated.)
3. **Reframe 5G-1F as Monthly Close v1**, file-based first, certify-and-detect-divergence (not hard locks). Run the July file-based rehearsal close post-freeze.
4. **Split 5G-4 into 4a (data-model, read) / 4b (write)** as a roadmap principle.
5. **Give calc-core extraction an explicit slot** before 5G-4 / Budget-identity / rollover execution, and **re-pin the runModel freeze language** against the current numbering.
6. **Adopt the obligation taxonomy one-pager** and the **roadmap numbering + legacy-gate fold-in cleanup** as owner-approved docs patches (§7).
7. **Ship the run-time visibility trio** as small display-lane slices post-freeze.
8. **Adopt the Plan Period *design* target** (design in 2026; execute as the 2027 re-baseline) with **2027 execution scoped to the minimum** (§3.E) — no multi-scenario platform.
9. **Register Data Quality + Entry bundle** proceeds as immediate data-integrity work (its TX-1 schema slice is spec-gated under 5.B).

### 5.B — Requires a dedicated specification before approval

1. **5G-1B release-event shape** (release vs cumulative-progress; decrement-vs-annotate snapshots; AMEX invariant formula with releases; terminal treatment of the Week-5 wewe_* correction rows).
2. **Plan Period schema + rollover migration plan** (year-scope `weekly_reconciliations`; per-period week CHECK relaxation; generalized opening-anchor seeding; parameterized constants; golden-master strategy per model year; migration authority over 5G-1D-frozen objects).
3. **Calc-core extraction + test-suite migration** (four seams; skip-vs-break decision; constants externalization; source-pattern-test rewrite plan).
4. **5G-4a goal / funding-target data-model** (single-source-of-truth targets/flags; registry history; transition matrix; scope-change runbook; **whether a single physical funding-target entity is adopted** — §3.D).
5. **5G-4b write capability** (GR-A1 identity gates; zero-outflow identity committed test; earmark reservation contract per SO-2).
6. **`financial_audit_log` (L2)** — staging-first trigger table on frozen-adjacent tables, own gate.
7. **Domain funding-event ledger (L3 / Option C)** — scheduled to 5G-1B's first forcing function; kept distinct from #6.
8. **5G-3 allocation spec** — must define the Cash Availability Engine relationship and the balance-source/Protected-enumeration decisions.
9. **TX-1 taxonomy slice** (income/offset categories; required-category validation; reimbursement home).
10. **Obligations end-state owner** — which system owns dated obligations long-term (see 5.D).

### 5.C — Explicitly deferred

1. **Physical funding-target unification build** — deferred to the 5G-4a spec outcome; not approved now.
2. **Domain event-ledger build** beyond the 1B-forced slice — build only on demonstrated need.
3. **Close schema/UI** (5G-6) — after ≥3 stable file-based close iterations.
4. **5H mobile quick-add** — after the 5D-2 desktop-only decision is deliberately reversed.
5. **Splits / Transfers / Import readiness** — 2027 data-feature ladder; charter 5K now, build later.
6. **Budget-identity change (legacy 5G-3)** — gated on A2 income actuals + Wendy inputs; **should not land before the audit log (L2) exists** (OM §11.6). With Quicken gone there is no parallel month to validate the new identity against, so its verdict basis needs redefinition [inference].
7. **PITR-class paid tier / event-sourcing / close cockpit / alerting** — OM's explicit non-needs now.

### 5.D — Rejected or materially modified review recommendations

1. **"Backup/restore as a precondition to Quicken cancellation" (RM #4, OM §8.3)** — **rejected as framed** (cancellation already occurred); **retained as immediate remediation** (§3.B).
2. **"Quicken parallel run as the September verdict instrument / recovery replica" (RM, OM §8.3)** — **rejected** (moot); the missing-transaction detector is now statement-diff + backups.
3. **"Reviews may treat 5G-1D as pre-implementation / not started"** — **modified**: 5G-1D is executing (Gate 2 paused after Sub-phase 5; next Sub-phase 6); treat as frozen-in-execution.
4. **AR SO-1 physical single-entity "at 5G-4"** — **modified**: approved as *direction/venue* only; physical merge is §5.B spec-gated, not a now-approval.
5. **OM's implication that the audit log's Quicken-cancellation pull-forward trigger is pending** — **modified**: that trigger has already fired; the live pull-forward trigger is "3rd owner correction in a quarter."
6. **RM's Sep-verdict rationale for the Register bundle** — **modified**: the bundle is retained on *data-integrity* grounds, not the (obsolete) cancellation-verdict grounds.

---

## 6. Recommended phase definitions (proposed charters only — not authoritative phase changes)

### 6.1 Register Data Quality + Entry
- **Objective:** make the primary actuals record clean and low-friction to maintain now that it is the sole live system.
- **In scope:** TX-1 income/offset taxonomy (`income.bkcpa_extra_pay` etc.), required-category + save validation, uncategorized review/filter + cleanup list, reimbursement-status home decision, 5E-11 category typeahead / payee memory / account ABC ordering, REG-4 uncategorized count.
- **Out of scope:** Weekly Model cash-math changes; duplicate inflow/tax/goal allocation; mobile layout (5H); Register write-path schema beyond additive categories.
- **Entry:** post-freeze; TX-1 taxonomy spec cleared.
- **Exit:** uncategorized count dispositioned; reimbursement path decided; validation live; golden masters green.
- **Primary risks:** accidental Budget cash-math coupling; category additions that miss the `categories` FK-sync guard.

### 6.2 Monthly Close v1
- **Objective:** a repeatable, file-based month-end certification composed over the weekly primitives.
- **In scope:** P1–P9 checklist; certification record (`docs/closes/<YYYY-MM>-close.md`); basis watermark + certified-aggregates blob (hash-committed, values local); accepted-variance register; reopen/reason-code vocabulary; closed-period divergence detection (manual v1).
- **Out of scope:** close schema/UI; hard period locks; any new Wendy obligation; automatic reopen.
- **Entry:** 5G-1D post-freeze activation (fully-closed predicate available); checklist authored.
- **Exit:** July rehearsal close certified file-based; exception severities recalibrated once.
- **Primary risks:** statement-cycle mechanics need one iteration; certifying over un-surfaced load failures (mitigated by the visibility trio).

### 6.3 Plan Period / 2027 Rollover
- **Objective:** represent and operate a second plan year; make year rollover a seeding procedure, not a crisis.
- **In scope (design):** period entity (id, start, week count, opening anchors, parameter set, week-numbering); `model_year` on `weekly_reconciliations`; per-period week CHECK; parameterized RPC/wrapper/engine constants; generalized E2 opening-anchor procedure; per-year golden-master strategy; migration authority over 5G-1D-frozen objects.
- **Out of scope:** multi-scenario/what-if planning; concurrent horizons; configurable planning platform.
- **Entry:** spec approved (Fable target: before November).
- **Exit:** staging-rehearsed migration; production cutover before 2027-01-09; 2027 opening anchor seeded.
- **Primary risks:** touches every persistence layer + constants; a hot/late execution halts weekly ops; frozen-object amendment.

### 6.4 Calc-core extraction
- **Objective:** move the simulation core out of index.html under behavioral identity, ending freeze-exception accretion.
- **In scope:** reify eligible-set / capacity / allocation-policy / decision-emission seams; externalize constants (OP_FL, MIN_XFR, lookahead depth, seed thresholds) to versioned config; decide skip-vs-break under golden masters; migrate source-pattern tests to behavioral fixtures; declare the module target posture.
- **Out of scope:** waterfall *policy* changes beyond the deliberate skip-vs-break decision; framework/bundler/build step; UI refactor.
- **Entry:** golden masters captured and green; test-migration plan approved.
- **Exit:** core in modules; golden-master identity held; freeze language re-pinned; constants in config.
- **Primary risks:** hidden test-suite migration doubles the estimate; any behavioral drift under the identity gate is a stop.

### 6.5 5G-4a (goal / funding-target data-model governance)
- **Objective:** a governed, single-source goal/funding-target data model beneath the already-governed snapshot layer.
- **In scope:** consolidate target/status/flag provenance; persist `ira_cpa_cleared`; registry history (interval-dated or change-event); legal-transition matrix; scope-change runbook; generalized eligible-set contract; wishlist-34 goal additions; decide physical funding-target entity shape (§3.D).
- **Out of scope:** write UI (5G-5); waterfall write capability (4b); speculative dependency algebra.
- **Entry:** extraction done (testable waterfall API); snapshot scope-change contract understood.
- **Exit:** transition matrix enforceable; registry history queryable; scope changes runbook-governed.
- **Primary risks:** registry sits under the waterfall — a wrong model ripples (the IRA-target-correction deadlock class).

### 6.6 5G-4b (goal write capability)
- **Objective:** safe goal CRUD + reprioritization on a live model.
- **In scope:** GR-A1-class identity gates; confirmation flows; zero-outflow identity committed test; earmark reservation contract (SO-2) as one interface with two producers.
- **Out of scope:** admin UI polish (5G-5); anon RLS (never); stored complete flag / stretch-goal handling from the stale dynamic-goal-registry draft.
- **Entry:** 4a data model stable; extraction done.
- **Exit:** writes gated + confirmation-flowed; zero-outflow identity test green; earmark adapter input-layer-only.
- **Primary risks:** highest-risk build — waterfall-input mutation under live Wendy operation.

### 6.7 Recovery remediation
- **Objective:** eliminate the single-copy / no-recovery exposure now that the OS is the sole live record.
- **In scope:** weekly + pre-close + pre-correction `pg_dump` cadence; offsite encrypted copy; retention (8 weekly / 6 monthly); backup owner account; owner-login MFA; restore runbook; one staging restore rehearsal; off-device copy of the local evidence directory.
- **Out of scope:** paid PITR tier (until stakes/volume justify); alerting; automated backup infra.
- **Entry:** immediate (no code, no freeze conflict).
- **Exit:** cadence live ≥4 weeks; restore rehearsed once; MFA + backup owner in place; runbook committed.
- **Primary risks:** the retained Quicken archive assumed usable without verification (§9 V1–V2); backups that are never restore-tested.

### 6.8 Audit-log tier (`financial_audit_log`, L2)
- **Objective:** mechanical who/what/before/after across the four financial tables.
- **In scope:** one generic trigger table; AFTER triggers on `transactions`, `weekly_reconciliations`, `goal_funding_snapshots`, `budget_line_rules`; trigger-only writes; read-only to authenticated.
- **Out of scope:** business-intent semantics (that is the event ledger, §6.9); event sourcing; UI.
- **Entry:** 5G-1D shipped; pull-forward trigger fired or 5J reached.
- **Exit:** staging-validated; triggers live; read path proven; no write grants.
- **Primary risks:** sits on frozen-adjacent tables — staging-first with its own gate.

### 6.9 Funding-event-ledger tier (domain events, L3 / Option C)
- **Objective:** durable funding intent/execution identity — transfers decided, holdings released, set-asides accrued.
- **In scope:** append-only event ledger with provenance/custodian/type; absorbs `weekly_tasks` completion identity, 1B releases, correction event-grain; snapshots remain weekly observation checkpoints.
- **Out of scope:** replacing snapshots; row-diff mutation logging (that is L2); speculative build ahead of a real consumer.
- **Entry:** 5G-1B needs release identity (first forcing function).
- **Exit:** one ledger (not three partial stores); 1B releases recorded; transfer identity durable.
- **Primary risks:** premature build; collapsing with L2; fossilized Week-5 wewe_* rows if terminal treatment unspecified.

---

## 7. Canonical-document patch plan (recommendations only — apply nothing; each depends on Adam approval)

| Target | Section / heading | Old concept | Recommended replacement | Rationale | Approval |
|---|---|---|---|---|---|
| `AGENTS.md` | Do Not Touch → "runModel internals: frozen through 5G-2" | Freeze boundary keyed to a phase label that changed meaning in the renumber | "runModel frozen until the calc-core extraction phase; move-only during extraction under golden-master identity; modifiable per spec after" | Post-renumber, "5G-2" now nominally unfreezes runModel during Cash Allocation, which was never the intent | Required |
| `CODEX_STATUS.md` | 5G-1D status prose | "5G-1D implementation NOT STARTED" | Reflect live execution: Gate 2 paused after Sub-phase 5; Sub-phases 3–5 passed; next action Gate 2 Sub-phase 6 | Prose is stale against the executing gate stack (git history) | Required |
| `CODEX_STATUS.md` | Next milestone / Quicken | "Quicken cancellation only after one clean parallel month…" | Quicken cancelled; retained data is unverified historical archive; backup/restore is immediate remediation | Cancellation already occurred; the milestone language is obsolete | Required |
| `docs/phase-status.md` | Authoritative 5G table + legacy fold-in note | Legacy gates "fold-in TBD"; 5J/5L duplicate 5G-5/6 and 5I-4 | Re-home extraction (5G-2.5), Budget-identity (legacy-5G-3), set-aside/earmark (4a/4b), spreadsheet-retirement into the authoritative table; retire 5J/5L into merged tracks; add explicit 5G-1B-before-1E ordering | Load-bearing gates get lost in the numbering churn (AR A6) | Required |
| `docs/phase-status.md` | 5G-1F row | "July Month-End Close / Audit Minimum Viable Close" (empty) | "Monthly Close v1 — file-based certify-and-detect-divergence; first exercised on July data post-freeze" | Names the deliverable; avoids single-month scope anchoring | Required |
| Strategic roadmap (`strategic-roadmap-future-horizons.md`) | 5I-0/5I-3/5I-4 lettering | Collides with 5I = Splits | Rename modernization items; retire old labels; note Horizon B rides extraction, A rides Import Readiness | Numbering collision (RM §1.5) | Required |
| Stabilization roadmap (`stabilization-roadmap-spec.md`) | Budget-identity "high risk" note | Sequenced without audit-log dependency | Add: Budget-identity change should not land before `financial_audit_log` (L2) exists; redefine its verdict basis (no parallel Quicken month) | OM §11.6 + Quicken-gone [inference] | Required |
| Security / backlog (`security-brittleness-backlog.md`) | Backup assumption; items 8/9/16/18; P4 | "Supabase Pro daily backups"; audit log "before shared write" | Correct to Free-plan/no-PITR reality; mark MFA(8)/backup-owner(9) due now; audit-log(16) trigger already met; elevate 2027 re-baseline (P4) to a scheduled design; backup/DR(18) is immediate, not a Quicken gate | Stale Pro-plan assumption (OM §12.7) | Required |
| AI Context (update notes only — **do not rewrite canonical files**) | 05 financial-os-context / 08 open-items | Quicken parallel-run + cancellation-gate framing; 5G-1D "not started" | Patch note into `~/AI-Context/_system/patches/proposed/`: Quicken cancelled; 5G-1D executing; obligation-taxonomy end-state; Plan Period design target | Keep context from re-staling (AGENTS.md Definition of Done) | Required |

**Ordering of patches** (§10): apply the two currency corrections (`CODEX_STATUS.md` 5G-1D + Quicken) first, then the `AGENTS.md` freeze re-pin, then the `docs/phase-status.md` fold-in/numbering + 5G-1F rename, then the strategic/stabilization/security patches, then the AI-Context patch note last. Do none of these without Adam's approval, and none while they would touch the active 5G-1D execution surface.

---

## 8. Review-artifact disposition

| File | Recommended disposition |
|---|---|
| `docs/reviews/roadmap-architecture-review-2026-07-12.md` | **Supersede-with-synthesis but preserve for provenance.** Already under `reviews/`. Keep as the sequencing/numbering source of record; non-authoritative. |
| `docs/operating-model-control-review-2026-07-12.md` | **Move under `docs/reviews/`**, then supersede-with-synthesis + preserve. It is the close/control design of record. |
| `docs/architecture-review-cash-planning-goal-funding-2026-07-12.md` | **Move under `docs/reviews/`**, then supersede-with-synthesis + preserve. It is the 5-10 year architecture source. |

**Recommendation** [inference]: commit all three under `docs/reviews/` (co-located with the existing review artifacts) **as supporting analysis**, and let **this synthesis become the primary decision artifact**. The three originals remain **non-authoritative references** — cited for their evidence and detail, never as build authority. This mirrors the house convention for review artifacts (triage inputs; controls win on conflict). Do not discard: their per-item evidence (schema pins, incident histories, exception catalog) is the substrate the synthesis compresses. Committing is docs-only; if Adam prefers, they may remain uncommitted until the synthesis is accepted, but co-locating them under `reviews/` before commit is the cleaner provenance path.

---

## 9. Immediate non-code operating actions

Prioritized. **"Now"** = safe to do today, in parallel with 5G-1D, no freeze conflict, no code. **"After Gate 2"** = wait until 5G-1D Gate 2 (Sub-phase 6 onward) completes so the action captures the settled state.

| # | Action | Timing | Note |
|---|---|---|---|
| V1 | **Verify the retained Quicken file opens** | Now | Archive usability is unverified (§3.B); do not assume until proven. |
| V2 | **Verify export capability + capture the final transaction date** | Now | Establishes what the archive can/can't reconstruct; records the cancellation boundary. |
| B1 | **Create a second encrypted Quicken archive copy** | Now | Off the origin machine; the archive is currently single-copy. |
| B2 | **Take a fresh production `pg_dump`** | **After Gate 2** | The last restore point (2026-07-09) predates E2 + 2.1 + Wk-5 recon + all Register entry since; a fresh dump should capture the post-Gate-2 settled state (waiting avoids an immediately-stale dump). A pre-Gate-2 interim dump *now* is also prudent as a floor. |
| B3 | **Create an encrypted off-device backup** of B2 | After Gate 2 | Offsite copy; metadata-only note in `exports/` per the E1 pattern. |
| B4 | **Protect the local evidence directory off-device** | Now | `~/Herndon-FOS-DB-Backups` is currently single-machine; a laptop loss deletes both audit trail and recovery baseline (AR SM-4). |
| R1 | **Draft the restore runbook** (`docs/restore-runbook.md`) | Now | Destructive full-replace-from-dump procedure; document the Pages Builds API deploy fallback. |
| R2 | **Rehearse restore into staging** | After Gate 2 | Once, on staging, before relying on backups as the recovery floor; quarterly thereafter. An untested backup is a hypothesis. |
| S1 | **Enable MFA on the owner Supabase login** | Now | ~15 min; the SQL editor under that login is the god path. |
| S2 | **Establish a backup-owner / recovery access account** | Now | ~15 min; single-owner lockout is currently unrecoverable (Wendy cannot recover). |
| C1 | **Define retention cadence** | Now | 8 weekly + 6 monthly; weekly post-closeout dump + mandatory pre-close/pre-correction dumps. |

**[inference]** V1/V2/B1/B4/R1/S1/S2/C1 have no dependency on 5G-1D and should start immediately — they are the highest-severity, lowest-cost items on the board and the Quicken cancellation already removed the redundancy they replace. B2/B3/R2 benefit from waiting until Gate 2 settles so they capture a coherent state, with an interim pre-Gate-2 dump as a floor.

---

## 10. Final recommendation

- **Next implementation action:** **resume 5G-1D Gate 2 at Sub-phase 6** and complete its remaining gate stack. Nothing in this synthesis interrupts, reorders, or amends it.
- **Next planning / specification action:** during the freeze, draft the **5G-1B release-event spec**, the **Monthly Close v1 checklist**, the **Register bundle / TX-1 taxonomy scope**, and kick off the **Plan Period design doc** — all docs-only, all parallel to 5G-1D.
- **Next non-code operational action:** start the **recovery remediation floor now** — V1/V2 (verify the Quicken archive), S1/S2 (MFA + backup owner), B1/B4 (second archive copy + off-device evidence), R1/C1 (restore runbook + retention). These are immediate because Quicken cancellation already removed the redundant replica.
- **Decisions Adam should make first** (in order): (1) approve the **recovery remediation** as immediate work; (2) confirm **5G-1B before 5G-1E**; (3) approve the **docs-only cleanups** (numbering/fold-in, freeze re-pin, obligation taxonomy) as owner patches; (4) approve the **Monthly Close v1 file-based operating model**; (5) confirm the **Plan Period design target** with minimum-scope 2027 execution; (6) set the **obligations end-state owner** direction. Items 1–3 unblock the most downstream work at the lowest cost.
- **Treatment of the three Fable artifacts:** co-locate all three under `docs/reviews/` as **supporting, non-authoritative analysis**; let **this synthesis be the primary decision artifact**; preserve the originals for provenance and evidence.
- **Order of any later authoritative roadmap patches** (§7, none without approval, none touching the active 5G-1D surface): (1) `CODEX_STATUS.md` currency — 5G-1D execution state, then Quicken; (2) `AGENTS.md` freeze re-pin; (3) `docs/phase-status.md` fold-in + numbering + 5G-1F rename; (4) strategic / stabilization / security backlog patches; (5) AI-Context patch note into `~/AI-Context/_system/patches/proposed/` last.

### Unresolved questions requiring Adam's decision

1. **Obligations end-state owner** — (a) budget_rules absolute-mode migration (WD → generated seed), (b) model reads dated obligations derived from `planned_outflows` via an explicit adapter, or (c) WD stays hand-maintained (reject consciously if chosen). The 2027 rollover is cheaper under (a) or (b).
2. **Physical funding-target unification** — adopt a single physical entity at 5G-4a, or keep goals and `planned_outflows` physically separate with a shared logical taxonomy? (§3.D — spec-gated either way.)
3. **Gate D activation timing** — pre-freeze vs post-freeze 5G-1D activation (readiness default = post-freeze); needed to fix the calendar. (5G-1D-internal; this synthesis only feeds it.)
4. **Gate C posture** on `repair_commitments_for_week` — retain / wrap / restrict-to-owner / revoke. (5G-1D-internal; OM recommends wrap-or-restrict-to-owner.)
5. **Budget-identity change verdict basis** — with no parallel Quicken month, how is the new "Available for Goals derived" identity validated before it goes live under Wendy?
6. **Quicken archive reconstruction role** — once V1/V2 verify usability, is the archive an accepted historical reference only, or a periodic reconciliation source? (Do not assume usable until verified.)
7. **Audit-log pull-forward** — build `financial_audit_log` at 5J, or now (the "3rd owner correction in a quarter" trigger) given the OS is already the sole record?

---

*Synthesis only. No code, SQL, schema, migration, RLS, RPC, test, or production/staging change. No BUILD_TS change. No authoritative document modified. Not committed or pushed. The three reviews are advisory inputs; 5G-1D remains frozen and authoritative for its own scope; nothing here amends it.*
