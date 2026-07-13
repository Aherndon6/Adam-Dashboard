> **Advisory source review — not implementation authority.** Superseded for sequencing decisions by
> `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md`. Retained for provenance and architectural detail.

# Herndon Financial OS: Post-5G-1D Roadmap Architecture and Sequencing Review

**Date:** 2026-07-12
**Status:** Review artifact. Docs only. No build authority; nothing here authorizes implementation, SQL, or scope changes. Triage input in the same sense as prior reviews: Adam decides what becomes roadmap.
**Scope:** Everything after 5G-1D. 5G-1D is frozen and in execution; this review treats its plan, gate register (Gates A-E), and contracts as fixed constraints. Completed phases are constraints unless a future dependency exposes a structural problem.
**Inputs:** AGENTS.md, CODEX_STATUS.md, docs/phase-status.md, strategic-roadmap-future-horizons.md, funding-model-integrity-review-2026-07-08.md, 5G-1D plan/readiness/slice-2 stack, stabilization-roadmap-spec.md, security-brittleness-backlog.md, tx-1-candidate.md, budget-rules-spec-v3.1.md, waterfall-calculator-spec.md, recurring-adjustments-spec.md, spec-actions-redesign.md, wishlist-v2-spec.md, phase-6a-goal-registry-spec.md, dynamic-goal-registry-spec.md, phase-5c-architecture-design.md, phase-5g-1-spec-2026-07-07.md, wendy-5g-budget-mockup-spec, ui-flow-review-triage, 5g-1c plan + review, AI Context 00/02/05/08.

---

## 0. Executive Summary

The 5G-1 funding-integrity track was the right call, and the execution discipline (staging-first, gate registers, identity gates, balance-free repo) is stronger than most production teams achieve. The problems in the remaining roadmap are structural, not procedural:

1. **The roadmap is optimized for goal-funding correctness while the two hard calendar deadlines are served by work that is unsequenced or absent.** The September Quicken-cancellation verdict depends on category totals matching, card totals reconciling, and reimbursables tracking cleanly. All three are Register data-quality concerns (TX-1, the homeless Jabian reimbursement workflow, transfer entities), none of which has a slot. The January 2027 model expiry requires a re-baseline that currently exists only as backlog item P4 in the security doc, while the persistence layer is provably year-pinned at the DB level.
2. **Four numbering generations left duplicates and orphans.** The 5C design's 5D-5J map, the letter track (5G..5L), the legacy 5G sub-map (5G-1/2/2.5/3/4a/4b/5), and the authoritative 2026-07-08 map (5G-1A..1F, 5G-2..5G-6) all coexist in the docs. 5J duplicates 5G-5 + 5G-6. 5L duplicates 5I-4. Five legacy gates (calc-core extraction, Budget identity change, set-aside recommendations, earmark adapter, spreadsheet retirement) have no home in the new map; phase-status.md itself flags this fold-in as unresolved. Several 5C commitments were silently orphaned in the churn, including transaction_audit_log and reconciled locking (both designed, promised for the original 5F, never rescoped anywhere). The runModel freeze boundary ("frozen through 5G-2") is now ambiguous because 5G-2 changed meaning in the renumber.
3. **Recurring obligations live in three parallel systems with a wall between them and no declared end state.** The hardcoded WD array (weekly model), budget_rules (delta overlay), and planned_outflows (5G-2, with events) all represent bills. The Budget Rules v3.1 spec carried an explicit WD-migration end state (WD becomes generated seed data); that roadmap fell off the map when 5G was re-scoped, and the Do Not Touch rule ("do not inject planned outflows into WD/effectiveWD") freezes the split without naming a destination. The Diablos/GLP projection gap is this debt surfacing as a live defect.

**Top five moves:**

| # | Move | Why |
|---|------|-----|
| 1 | Insert **2027 Model Rollover** as a first-class phase: spec in October, staging in November, execute late December | weekly_reconciliations has no model_year and upserts on bare week_num; the 5F-1 RPC hard-rejects model_year <> 2026; cash_commitments RLS literally checks model_year = 2026; snapshots CHECK week_num 1..31. The model window ends 2027-01-09. This is the single largest unscheduled risk on the board. |
| 2 | Pull a **Register Data Quality + Entry bundle** (TX-1, reimbursement home, 5E-11 entry speed, REG-4) ahead of 5G-2, landing in the Aug 10-31 window | It is the only work that directly serves the September parallel-month verdict. Goal-funding and allocation phases do not move that gate. |
| 3 | Resequence **5G-1B (holding releases) before 5G-1E**, complete before Cal Wk 41 | 5G-1E's hard AMEX invariant is structurally violated by the first real cruise payout without release semantics. RCCL leaves during the freeze; DCL leaves ~Cal Wk 41. 1E before 1B is a broken order. |
| 4 | Make **backup/restore maturity a precondition to Quicken cancellation** | After cancellation, a Free-plan Supabase with a manual pg_dump on one laptop is the sole copy of the household's financial record. Tested restore + offsite copy + cadence is a week of work; losing the record is unrecoverable. |
| 5 | Give **calc-core extraction** an explicit slot before 5G-4 and before the rollover, and re-pin the freeze language | Every phase that touches runModel is currently doing freeze-exception surgery inside index.html. Extraction is the enabling investment for goal management, Budget identity, the rollover, and eventually the AI assistant horizon. Unmapped, it will keep sliding. |

---

## 1. Sequencing

### 1.1 Assessment of the planned order

Planned: 5G-1E → 5G-1F → 5G-2 → 5G-3 → 5G-4 → 5G-5 → 5G-6, then 5H → 5I → 5J → 5K → 5L, with 5G-1B "deferred," TX-1 "not sequenced," and the legacy gates unmapped.

The macro shape (integrity → planned outflows → allocation → goal management → close) is defensible and I am not proposing to invert it. The defects are at the seams:

- **5G-1E before 5G-1B is wrong on its own terms.** The phase table says 1E "consumes 5G-1B releases," yet 1B is deferred and unsequenced while 1E is sequenced. An advisory-to-hard promotion of the AMEX invariant cannot land while known, dated cash movements (cruise payouts) make the invariant false by design. The snapshot semantics decision in 5G-1C-2.1 (funded_amount is cumulative progress, not cash held) makes this concrete: after the RCCL payment leaves AMEX (~Cal Wk 30, during the freeze), Σ(AMEX-held snapshots) diverges from reconciled amx by exactly the released amount, permanently, until release semantics exist.
- **5G-1F is calendar-mislabeled.** "July Month-End Close" sequenced post-1E means the July close happens retroactively in mid-to-late August at best. That is fine, but say so: the deliverable is a repeatable Monthly Close v1 first exercised on July/August data, and the close that actually matters for the Quicken verdict is August/September. Naming it "July close" invites scope anchoring to one month.
- **The September gate has no serving work.** Everything sequenced between now and September is goal/allocation plumbing. The verdict criteria are Register-side. This is the largest pure-sequencing miss.
- **5H after the whole 5G stack undervalues entry friction.** Wendy is entering every transaction manually through Aug-Sep. The 5E-11 deferrals (category typeahead, payee memory, ABC ordering) are cheap display-layer wins that reduce the daily cost of the parallel run and the chance of entry-quality failures that would spoil the verdict. They do not need to wait for 5H's full charter (mobile quick-add is the expensive part; see 1.4).
- **5G-6 as a separate terminal phase is a duplicate.** See merges.

### 1.2 Move earlier

| Item | From | To | Rationale |
|------|------|-----|-----------|
| 5G-1B holding→payout releases | Deferred, unsequenced | Immediately post-freeze (Aug 10+), before 5G-1E, complete before Cal Wk 41 | 1E depends on it; DCL payout is a dated deadline; it is also a runModel change requiring a freeze exception, so it should be its own tightly-scoped slice like 1A.5 was. Design the release event to also decrement/annotate the goal snapshot layer, per the funding review §5 Option C compatibility note. |
| TX-1 + reimbursement home + 5E-11 entry speed + REG-4 | Not sequenced / 5H | One bundle, Aug 10-31 | Serves the September verdict directly. TX-1's schema surface (new income/offset categories) is small and owner-executed; the rest is display/validation. The Jabian reimbursement decision (Register field vs side-channel) has been open since 5E-10 and is one of the three cancellation criteria. |
| Backup/DR maturity (security 18) + MFA (8) + backup owner (9) | Backlog | Before Quicken cancellation; MFA/backup-owner now (zero code) | See §5. Items 8 and 9 are dashboard/SQL actions with no code. |
| Diablos/GLP WD fix + baseline recapture | "Separate task," gate before legacy-5G-4a | Post-freeze, before 5G-1B | Projections are knowingly understated in production. It is input-data correction, small, and both 1B and later planning features want a correct baseline first. Recapture golden masters after. |
| 2027 Model Rollover (P4) | Security backlog line item | First-class phase: spec Oct, staging Nov, execute late Dec | Evidence: weekly_reconciliations upserts on bare week_num with no model_year column; save_reconciliation_with_commitments raises on model_year <> 2026; cash_commitments RLS policies WITH CHECK model_year = 2026; goal_funding_snapshots CHECK week_num BETWEEN 1 AND 31; getCurrentWeek clamps at 31; START_* and PAYCHECK_WKS constants. A 2027 week-1 reconciliation would collide with 2026 week 1 today. The 5G-1D wrapper inherits all of this and its inner RPCs are declared immutable, so the rollover needs its own migration authority over objects the 5G-1D contract froze. That tension must be resolved on paper, not in December. |
| Calc-core extraction (legacy 5G-2.5) | Unmapped | Explicit phase after 5G-3, before 5G-4 and before rollover execution | See §2.3. Also re-pin the freeze rule: "frozen through 5G-2" written under the old numbering now nominally unfreezes runModel during Cash Allocation, which was not the intent. |
| Goal additions for Wendy trips / December trip (wishlist 34) | Wishlist | Fold into 5G-4a scope | Any goal-set change collides with the 5G-1D nine-goal snapshot contract, which requires a separately reviewed scope-change design. Do it once, deliberately, in the phase that owns the goal data model. |

### 1.3 Move later or hold

- **5G-2 production DDL + app build:** hold until the Register bundle and 5G-1B land. The staging validation does not expire. Mint vendor confirmation is an external dependency anyway. Late September/October is the realistic slot, and nothing before the allocation view (5G-3) consumes it.
- **5G-5 Goal Admin UI:** after the 5G-4 split (see 1.5); the write layer must stabilize before UI multiplies its reach.
- **5K Transfers:** keep late, but write its charter now (see §5, transfer entities), because "card totals reconcile" pressure will tempt ad-hoc transfer hacks in Register before 5K arrives. Its charter already has two committed pieces scattered in other docs: the transfer_group_id pairing model designed in 5C, and retiring the Cash Planning two-entry pattern by linking set-aside events to Register rows (mockup spec §8 assigns that to 5K).
- **Import Readiness:** keep unlettered and last among data features. It has unbuilt prerequisites: posted_date rules (the former 5F-3 item), TX-1 category validation, splits (5I), transfer entities (5K), and a dedup design. Sequencing it earlier than those would force all five decisions at once inside an import project.
- **Horizons A-D:** unchanged relative order (C before D stands). Note two dependencies: A (bank integration) sits behind Import Readiness; B (AI assistant) becomes materially cheaper and safer after extraction exposes a clean domain API, and the Ask Claude payload rebuild deferred by the funding review should ride whichever phase touches that surface first.

### 1.4 Hidden dependencies

| Phase | Hidden dependency | Consequence if missed |
|-------|-------------------|----------------------|
| 5G-1E | 5G-1B release semantics; also the RPC-side auto/holding exclusion guard rider from the 5G-1D plan | Hard invariant is false at first payout; guard rider silently forgotten |
| 5G-1F | Gate C posture on repair_commitments_for_week (a Wendy-callable RPC that can mutate a closed week); period-lock semantics that do not exist yet; Register rows remain editable after close | A "close" that nothing enforces; post-close edits silently change closed-month Budget history |
| 5G-2 app build | showCashPlanning flag, ES-module + static-server verification workflow, Mint confirmation (external) | Known, already documented; listed for completeness |
| 5G-3 | The open balance-source rule and Protected enumeration decision; 5G-1B (AMEX Spoken For correctness); a defined relationship to the 5F-1 Cash Availability Engine | Two competing "available cash" numbers in the product (see §2.4); rework |
| 5G-4 | The nine-goal snapshot scope-change contract (5G-1D plan §4); goal target triplication cleanup (registry vs hardcoded fallback vs goalFundedAmounts vs retRem-class constants); ira_cpa_cleared persistence; extraction; GR-A1/fallback strategy for a writable registry | Waterfall-mutating writes land on an unconsolidated data model; highest-risk phase gets harder |
| 5H | Reversal of the 5D-2 "Transactions is desktop-only" decision (mobile nav has no Transactions entry) | "Mobile quick-add" is scoped as a feature but is actually a layout-decision reversal plus a feature |
| Quicken cancellation | Reimbursement tracking home; backup/restore maturity; transfer-entity workaround discipline | Verdict criteria unmeetable or unsafe to act on |
| Spreadsheet retirement (legacy 5G-5) | Budget identity change + A2 income actuals + one clean parallel month on the new identity | December is a distorted month for a parallel run; if identity lands Nov, the verdict month is realistically January |
| 2027 Rollover | Migration authority over objects the 5G-1D contract declares immutable; a 2027 opening-anchor procedure (E2-pattern Value Card); week-count change (31-week window was a mid-year artifact; 2027 is a full year) | December scramble against a hard deadline |

### 1.5 Merge

- **5J into 5G-5 + 5G-6, as one "Close and Goal Administration" track.** 5J ("month-end close hardening + minimal goal editing") predates the 5G expansion and is now a near-duplicate of 5G-5 (Goal Admin UI) plus 5G-6 (Full Close/Audit Hardening). Keeping both invites double-specification. Recommendation: retire the 5J letter, or equivalently delete 5G-5/5G-6 and let 5J own them; one owner, one charter.
- **5L into 5I-4 (+ CSP item 14).** Both are "architecture modernization." The strategic doc's 5I-0/5I-3/5I-4 lettering already collides with 5I = Splits; resolve the collision by renaming the strategic items into the modernization phase and retiring the old labels.
- **Event/audit designs into one convention.** outflow_events (5G-2), the Option-C goal_funding_events idea (5G-1E+), "durable historical event logging" (deferred to 5J by the Slice-2 doc), and audit_log (security 16) are four sketches of the same primitive. Define one append-only event-table convention once (columns, provenance, RLS, grants) and instantiate it per domain. See §2.4.
- **TX-1 + 5E-11 + REG-4** into the single Register bundle described above.

### 1.6 Split

- **5G-4 into 5G-4a (goal data-model consolidation, read-side) and 5G-4b (write capability).** This mirrors the 6A/6B pattern that already worked. 4a: single source of truth for targets/status/flags, ira_cpa_cleared persisted, snapshot scope-set contract generalized, fallback strategy decided (a writable registry makes a hardcoded fallback progressively more wrong), wishlist-34 goal additions executed under the new contract. 4b: CRUD + reprioritization with GR-A1-class identity gates and confirmation flows. The stale dynamic-goal-registry draft's CRUD intent is the requirements source; its anon-write RLS, stored complete flag, and stretch-goal handling must not survive contact with 6A's decisions.
- **5G-1F into "Monthly Close v1" (repeatable close: checklist, close artifact/export, closed-period edit detection) now, and fold the audit-hardening remainder into the merged Close track later.** A minimal close that does not address post-close mutability is a report, not a close.

---

## 2. Architecture

### 2.1 Weaknesses

1. **Year-pinned persistence layer** (evidence in §1.2). Deliberate and documented at each step, but the aggregate is a hard 2027 wall across reconciliation, commitments RLS, snapshots, and the 5G-1D wrapper's sequencing rules.
2. **Three obligation systems.** WD array (hardcoded, hand-maintained, drifts: Diablos/GLP), budget_rules (delta overlay on the model, no management UI, TD-3 still true), planned_outflows (5G-2, well-designed, events, deliberately outside the model). The precise shape of the problem: the weekly model's obligations live in WD + budget_rules; cash planning's obligations live in planned_outflows; the Do Not Touch rule forbids the model reading planned_outflows. The Budget Rules v3.1 §11 end state (WD demoted to generated seed data behind absolute-mode rules) was never carried into the 5G map, so the model's own obligation source has no declared future at all: WD-forever is the implicit answer, and it is the worst one. Every year of delay adds hand-maintenance (the 2027 rollover will otherwise re-hand-author WD for a full year, and every vendor change is a code edit).
3. **Simulation core still in-body, growing by exception.** The ES-module rule protects new feature areas only. 5G-1A.5, 1C-1, the C3 overlay, and the coming Slice-3 closeout UI all landed inside index.html because they touch frozen internals. Each freeze exception is well-controlled individually; collectively they are the strongest argument that extraction is late, not early.
4. **Goal state fragmentation.** Registry targets, hardcoded fallback, goalFundedAmounts frozen actuals, and display constants have already produced three conflicting retirement numbers (funding review risk 1). Snapshots fixed funded-state provenance; target/status/flag provenance is still fragmented. ira_cpa_cleared is session-only and resets on reload.
5. **Two availability engines by 5G-3.** The 5F-1 Cash Availability Engine computes deployable cash from commitments; 5G-3's Free to Use computes uncommitted balances from allocations. If their relationship is not defined in the 5G-3 spec, the product will show two different "how much can I spend" numbers with different blind spots.
6. **Silent partial degradation.** loadAll sets the connected badge green regardless of per-table failures; only goals has a fallback banner (funding review risk 4). As table count grows each phase, the probability of a silently stale surface rises.
7. **Close without lock.** Weekly reconciliation anchors balances and snapshots anchor goal attribution, but Register rows and budget lines remain editable in closed periods with no detection. Fine pre-close-discipline; not fine once monthly closes and a cancelled Quicken make this the system of record.
8. **Operational bus factor.** Owner-only corrections, guarded SQL, local push gate, backups on one laptop. Acceptable at household scale only if the backup owner (security 9) and restore procedure exist.

### 2.2 Debt magnets (where debt will accrue if untouched)

- **Source-pattern static tests (1,400+)** assert against index.html source strings. The extraction will invalidate large swaths regardless of behavior. Plan the test migration as part of extraction (golden-master behavioral fixtures carry the correctness burden; pattern tests get rewritten against modules), or the extraction estimate will be badly low.
- **Per-phase hand-authored SQL packages.** The discipline is excellent; the authoring cost is high and the guard patterns keep evolving (v1.4 grant normalization, dual-environment guard in Slice-2 rev 8). Without a canonical template, each phase re-derives the state of the art and older packages silently embody superseded patterns.
- **RPC and grant surface.** Five-plus RPCs with exact-signature grants after 5G-1D, more coming (close RPC, Option B, rollover). Two sanctioned security patterns now coexist: 5C mandates SECURITY INVOKER for the splits RPC and explicitly rejects DEFINER, while 5F-1/5G-1C use SECURITY DEFINER with in-function authorization, deliberately. Both are defensible; neither is written down as the rule, and the 5G-1 rehearsal already caught one grant-normalization defect class. There is no single inventory of RPCs, signatures, security modes, grants, and callers.
- **Module strategy has three documented postures.** 5C: single file, HOS.* namespaces, no module system. AGENTS.md/5G specs: new feature code as ES modules in separate files. 5G-1C R13: edits to frozen internals stay in-place in the script body. The de facto hybrid (new surfaces = modules, frozen-body edits = in-place) works today but is nowhere stated as the target; the extraction phase is where one posture must be declared (this is exactly the "document a target architecture" step 5I-4 already prescribes).
- **weekly_tasks positional identity.** The resolver adapter (db2704f) contains it; durable identity is deferred. 5K and any future task features inherit the adapter's complexity.
- **Documentation currency.** model_spec.md is stamped "Phase 6A + Stabilization S1" (June 21) and is now 8+ phases behind while being framed as a review input. The repo's supersession-banner convention is good; it needs to be applied here or the doc retired. AGENTS.md's Current State section also lags CODEX_STATUS; two current-state pointers will keep diverging.

### 2.3 Simplification opportunities

- **Extraction is the one investment that simplifies everything after it.** It converts freeze exceptions into module changes, gives the rollover a place to change constants without surgery, gives 5G-4 a testable waterfall API, halves the risk of Budget identity work, and is the substrate the AI-assistant horizon needs. Slot it; stop treating it as a floating gate.
- **Name the anchor/overlay pattern and reuse it.** Balances re-anchor weekly (reconData); goal attribution re-anchors weekly (snapshots). This is the house architecture and it is good. Future state layers (holding buckets, planned-outflow funded state) should be explicitly designed as "derived from events, verified by weekly anchors" rather than re-litigating stored-vs-derived per phase.
- **Standardize the migration kit.** One template package (env guard, preflight, migration, validation, rollback, smoke) with the current-best guard patterns, versioned, so each phase instantiates rather than re-authors.
- **Ops runbook index.** The runbooks exist per phase; a single OPERATIONS.md index (correction path, reopen path, anchor amendment, restore, rollover, e2e gates) turns tribal navigation into lookup. Cheap, high leverage for future-Adam and any future operator.

### 2.4 Duplicated concepts that should become shared infrastructure

| Concept | Current instances | Recommendation |
|---|---|---|
| Append-only event ledger | outflow_events (5G-2), Option-C goal funding events (5G-1E+), 5J durable history, audit_log (sec 16) | One convention, defined once, instantiated per domain |
| Availability / free cash | 5F-1 CAE deployable cash; 5G-3 Free to Use | 5G-3 spec must define the relationship (one consumes the other, or one number with two views) |
| Obligations | WD array; budget_rules; planned_outflows | Decision memo before 5G-2 app build: declare the end-state owner (recommendation: planned_outflows becomes the system of record for dated obligations over a multi-phase WD demotion, reviving the v3.1 §11 intent under the new schema) |
| Monthly close | 5G-1F; 5G-6; 5J | One Close track (v1 then hardening) |
| Goal editing | 5J "minimal goal editing"; 5G-4/5G-5 | One Goal Administration track |
| Architecture modernization | 5L; 5I-4; legacy 5G-2.5 | Extraction now; modernization plan later; one label |
| Weekly anchor overlay | reconData balances; goal_funding_snapshots | Codify as the named pattern (see 2.3) |
| Guarded SQL execution | Per-phase bespoke packages | Migration kit template |

### 2.5 Foundational capabilities before higher-level features

In order: (1) model_year as a first-class dimension + rollover mechanism; (2) calc-core extraction; (3) Monthly Close v1 with closed-period edit detection; (4) event-ledger convention; (5) tested backup/restore; (6) load-status/health surface; (7) goal scope-change contract. Items 1-3 gate specific scheduled phases; 4-7 are cheap relative to the rework they prevent.

---

## 3. Risk

### 3.1 Highest implementation risk (hardest to build correctly)

1. **5G-4b goal writes.** Mutates waterfall inputs on a live model; interacts with snapshots' scope contract, fallback strategy, and priority validation. Mitigations exist (GR-A1 pattern, confirmation gates) but this is the deepest water.
2. **Budget identity change (legacy 5G-3 content).** Retires hand-balancing that the household actively uses; changes Budget semantics under live Wendy operation; gated on A2 income actuals that do not exist yet.
3. **2027 Rollover.** Touches every persistence layer plus constants; must amend objects the 5G-1D contract froze; has a fixed deadline.
4. **Calc-core extraction.** Large mechanical diff; risk is well-bounded by golden masters but the test-suite migration is a second project hiding inside it.
5. **5G-1B.** Small code, but it is a runModel freeze exception with real-money semantics (release vs cumulative-progress) that must reconcile with snapshot meaning.

### 3.2 Highest production risk (worst blast radius if wrong)

1. **Quicken cancellation without backup/restore maturity.** Not a build risk; a decision risk. After cancellation there is no parallel record.
2. **2027 Rollover executed late or hot.** A failed January rollover halts weekly operations (reconciliation writes reject or collide).
3. **5G-4b / Budget identity** while Wendy operates live: wrong waterfall or budget math prescribes wrong real transfers.
4. **Close/lock absence during the parallel run:** silent post-close edits could invalidate the very comparison the Quicken verdict rests on. Cheap mitigation: closed-period edit detection lands with Close v1 before the September close.
5. **Grant/RPC surface growth** without an inventory: the failure mode is a quiet over-grant, which the v1.4 lesson showed is easy to author and hard to notice.

### 3.3 Needs additional specification before coding

| Phase | The spec must answer |
|---|---|
| 5G-1B | Release-event shape; how a release reconciles with snapshot cumulative-progress semantics; whether releases decrement snapshots or annotate them; AMEX invariant formula with releases |
| 5G-3 | Balance-source rule + Protected enumeration (already open decisions); the CAE relationship; what "Spoken For" reads for AMEX holdings pre/post 1B |
| 5G-1F Close v1 | Close definition (what is locked, what is detected); artifact contents; export format; interaction with Gate C repair posture |
| 5G-4a/4b | Scope-set contract replacing "the nine"; fallback strategy under writes; target consolidation; ira_cpa_cleared persistence design |
| 2027 Rollover | Full migration plan across reconciliation/commitments/snapshots/wrapper; week-numbering scheme for a full year; opening-anchor procedure for 2027; golden-master strategy per model year |
| Obligations end-state | Which system owns dated obligations long-term; WD demotion path; what budget_rules remains for |
| Import Readiness (later) | posted_date semantics (former 5F-3), dedup keys, source taxonomy; do not start before splits/transfers exist |

---

## 4. Long-Term Maintainability (3-5 year lens)

**Scalability.** Data volume is trivial at household scale indefinitely; the scaling dimension is *structural*: number of tables, RPCs, invariants, and hand procedures per year of operation. The annual rollover is the clearest recurring structural cost; productize it (year 1 builds the mechanism, later years run it).

**Maintainability.** The single-file core is the dominant term. The ES-module rule caps new-feature growth but the core keeps accreting by exception. Extraction plus the test migration converts the codebase from "one 10k-line file with string-matching tests" to "modules with behavioral fixtures," which is the difference between a system one person can safely modify in 2029 and one nobody can. Documentation supersession discipline is genuinely good; consolidate current-state to one pointer (CODEX_STATUS) and retire or refresh model_spec.md.

**Auditability.** Already strong on the write path (append-only events, provenance columns, balance-free repo, evidence artifacts). The gaps are UPDATE-capable surfaces (Register edits, budget lines) and the absence of period locks. The event-ledger convention plus Close v1 closes most of it. Add the RPC/grant inventory and a versioned migration ledger (security 17); docs/ already functions as one informally, so this is formalization, not new work.

**Extensibility.** planned_outflows (real due_date, not year-pinned, append-only events) is the best-designed schema in the system and should be the template. The snapshot overlay pattern generalizes. The Horizon C planning layer becomes a consumer of extracted domain APIs plus close artifacts; if extraction and Close v1 exist, Horizon C is mostly UI, not architecture.

**Operator usability.** Today's operating model (guarded SQL, Value Cards, Option A/B, local push) is safe but Adam-shaped. Over 3-5 years, the trajectory should be: Option B (built in 5G-1D) → correction/repair UI in the Close/Goal Admin track → an admin console that subsumes guarded SQL for routine operations, leaving SQL for break-glass only. The ops runbook index is the near-term step. Wendy-facing surfaces should never require knowing which week is "model week 5."

**Production support.** Add the load-status/health surface (per-table load state, last-anchor age, snapshot-missing nag) so degradation is visible instead of silent. Document the GitHub Pages deploy fallback (legacy builds API) discovered during the 2026-07-09 Actions incident as a runbook entry. Schedule a restore drill: an untested backup is a hypothesis.

**Future feature velocity.** The heaviest per-phase cost is the review pipeline itself (spec → ChatGPT → Fable → readiness → gates). That rigor is appropriate for money-moving code; it is over-weighted for display-only work. The UX-0/UX-0.5 pattern (display-only slices with narrow charters) is the right relief valve; formalize the two-lane distinction (money-path vs display-path) so display work stops paying money-path process tax. The readiness-package pattern (substituting for per-slice review) is the right amortization for the heavy lane; templatize it.

---

## 5. Missing Work

Foundational capabilities normal in mature financial software, absent from the roadmap. Deliberately excluding invented features (no multi-currency, no invoicing, no multi-tenant, no native mobile app; bank feeds and planning layer are already horizoned).

1. **Year-end close / annual rollover.** The single biggest absence. Covered throughout; must become a phase.
2. **Backup, restore, and retention.** Free plan has no PITR; restore points are manual local pg_dumps on one machine, chmod 600, never committed. Needed: scheduled export cadence, offsite encrypted copy, a tested restore procedure (drill), and a retention statement (financial records; multi-year). Precondition to Quicken cancellation.
3. **Period locking / closed-period change control.** Nothing prevents or detects edits to a closed month's rows. This is not new design work: 5C's original 5F scope included reconciled locking and a transaction_audit_log (schema designed), both dropped when 5F was re-scoped into the Cash Availability Engine and never re-homed. Revive the 5C design inside Close v1 (detection first, hard locks with the hardening pass) rather than re-inventing it.
4. **Reporting and export for the CPA/tax seam.** Category-year totals, reimbursable ledger, tax-reserve activity, close artifacts as files. "Never a data trap" with first-class export is literally one of 5C's ten core principles, deferred to its 5J-or-later and now unowned. The household has a CPA-sensitive workflow (ira_cpa_cleared, Wendy SEP) and no way to hand Jim Kinkead anything but screenshots. Small scope if it rides Close v1 artifacts.
5. **Reimbursement tracking home.** Open since 5E-10; one of the three Quicken-verdict criteria. A status field on Register rows or a tiny reimbursement ledger; decide and build in the Register bundle.
6. **Transfer entities in Register.** Two-sided transfers currently exist as excluded categories and convention. "Card totals reconcile" pressure will hit this during the parallel run. Charter 5K now even if built later, so interim convention is deliberate.
7. **Health/status surface.** Per-table load state and anchor freshness; kills the silent-partial-fallback class (funding review risk 4).
8. **Category governance.** TX-1's required-category validation plus an owner path for new categories (the 5E-9 "Category Registry Admin" deferral); plus the budget_line_rules→categories FK audit (wishlist 39) so the operating-month guard becomes structural instead of manual.
9. **RPC/grant inventory + migration ledger.** Formalize what docs/ already half-is.
10. **Admin console trajectory.** Not a near-term build; a stated direction so each correction/repair feature (Option B, half-close repair, reopen) is designed as a future console citizen rather than a one-off.

**Orphaned 5C commitments worth an explicit disposition** (adopt, re-home, or retire; do not leave silent): transaction_audit_log and reconciled locking (item 3 above); the transaction_splits schema + deferrable sum trigger (the ready-made basis for 5I); the import layer design (import_batches, import_queue, payee_rules, pending-vs-posted; the basis for Import Readiness); Budget-reads-from-splits plus the dynamically computed planned_allocation (the old "$2,300 fix," now floating as unlettered "Budget Integration / Actuals" and entangled with the A2 income-actuals gate); monthly_budget_target to a settings table; the budget_line_rules.category_key rename.

---

## 6. Prioritized Recommendations

### 6.1 Revised roadmap

Assumes Gate D resolves to post-freeze activation per the readiness package's own default rule ("if the pre-freeze path becomes unsafe, DEFAULT to post-freeze"). With 12 days to the freeze and Slices 2-7 plus a supervised first closeout outstanding, pre-freeze completion would compress controls; plan the calendar on the post-freeze path and treat pre-freeze completion, if it happens, as upside. That is a planning assumption, not a 5G-1D change.

| # | Window | Phase | Contents | Rationale anchor |
|---|--------|-------|----------|------------------|
| 0 | Now → Jul 24 | 5G-1D (frozen) | Per its own gates; Gate D decision | Freeze Jul 24 |
| 1 | Freeze Jul 24 - Aug 10 | (no merges) | Prepare specs: 5G-1B, Register bundle, Close v1, obligations memo | Freeze rule |
| 2 | Aug 10-31 | 5G-1D activation + gap repair | Wrapper activation, Week-6+ sequential repairs per §6.3/§6.1 | Gate D post-freeze path |
| 3 | Aug 10-31 | **Register Data Quality + Entry bundle** (new; replaces "TX-1 unsequenced") | TX-1 taxonomy/validation/cleanup, reimbursement home, 5E-11 typeahead/payee/ABC, REG-4 uncategorized count | September verdict |
| 4 | Aug-early Sep | Diablos/GLP WD fix → **5G-1B releases** → **5G-1E** | WD correctness, then release events (freeze-exception slice), then hard invariant | DCL Cal Wk 41; 1E depends on 1B |
| 5 | Sep | **Close v1** (reframed 5G-1F) | Repeatable monthly close: checklist, artifact/export, closed-period edit detection; first exercised on Jul/Aug, live for Sep | September verdict; CPA seam |
| 6 | Sep (parallel) | Backup/DR gate | Export cadence, offsite copy, restore drill, MFA + backup owner | Precondition to cancellation |
| 7 | Oct | Quicken verdict; **5G-2** prod DDL + app build | After a clean September close; Mint confirmation | Verdict criteria met by 3+5 |
| 8 | Oct | **2027 Rollover spec** + **5G-3 spec** | Rollover migration plan; balance-source/Protected/CAE-relationship decisions | Deadline runway; spec-first list |
| 9 | Oct-Nov | **Calc-core extraction** (re-slotted legacy 5G-2.5) | Extraction under golden masters + test migration; re-pin freeze language | Gates 5G-4, Budget identity, rollover safety |
| 10 | Nov | **5G-3 build**; **5G-4a** goal data-model consolidation | Allocation view; targets/flags/scope-set/ira_cpa_cleared persistence; wishlist-34 goals | Post-extraction |
| 11 | Nov-Dec | **Budget identity change** (if A2 + Wendy inputs ready) | Available for Goals derived; hand-balancing retired | Gated; slips to Jan without A2 |
| 12 | Late Dec-early Jan | **2027 Rollover execution** | Staging-rehearsed; new opening anchor; window ends 2027-01-09 | Hard deadline |
| 13 | 2027 Q1 | **5G-4b + Goal Admin** (merged with 5J's goal editing); set-aside recommendations + earmark adapter (legacy 5G-4a/4b content); spreadsheet retirement after one clean identity month | The cash-planning payoff features, on extracted core | Legacy gates honored |
| 14 | 2027 | 5H (with mobile decision), 5I splits, 5K transfers, Close hardening (absorbs 5G-6/5J remainder), 5L/5I-4 modernization | Wendy-experience and data-feature ladder | |
| 15 | 2027+ | Import Readiness → Horizon A; Horizon C; Horizon B rides extraction; D last | Existing horizon order preserved | |

### 6.2 Change log with impact, priority, confidence

| Change | Impact | Priority | Confidence |
|---|---|---|---|
| Insert 2027 Rollover phase (spec Oct, execute Dec) | Prevents operational halt in January; converts a cliff into a project | P0 | High (schema evidence is direct) |
| Register bundle before 5G-2 | Directly serves the only near-term business gate; small scope | P0 | High |
| 5G-1B before 5G-1E, before Cal Wk 41 | Makes 1E's invariant achievable; closes a dated model-reality divergence | P0 | High |
| Backup/DR as cancellation precondition (+MFA/backup owner now) | Removes an unrecoverable-loss scenario | P0 | High |
| Extraction slotted Oct-Nov; freeze language re-pinned | Unlocks 5G-4/identity/rollover safely; ends exception accretion | P1 | High on need; Medium on the exact slot |
| Merge 5J↔5G-5/6; 5L↔5I-4; retire dual numbering | Removes double-specification risk | P1 | High |
| Split 5G-4 into 4a/4b | De-risks the highest-risk build | P1 | High |
| Reframe 5G-1F as Close v1 with edit detection + export | Turns a report into a control; feeds CPA seam | P1 | Medium-High |
| Obligations end-state memo before 5G-2 app build | Stops the three-system split from hardening further | P1 | Medium (direction), High (that a decision is needed) |
| Event-ledger convention, migration kit, RPC inventory, runbook index, health surface | Low-cost infrastructure whose payoff repeats every subsequent phase (each is days, not weeks) | P2 | High |
| Hold 5G-2 prod to late Sep/Oct | No downstream consumer before 5G-3; frees the Aug window | P2 | Medium |
| Two-lane process (money-path vs display-path) formalization | Velocity without safety loss | P2 | Medium |

### 6.3 Decisions this review puts to Adam

1. Approve the revised order in 6.1, or amend. The load-bearing changes are rows 3, 4, 6, 8, 9, 12.
2. Obligations end state: decide the weekly model's future obligation source. Options: (a) budget_rules absolute-mode migration per v3.1 §11 (WD demoted to generated seed data); (b) the model eventually reads dated obligations derived from planned_outflows through an explicit, separately designed adapter (respecting the no-side-effect boundary 5C set); (c) WD stays hand-maintained indefinitely (the current implicit choice; reject it consciously if chosen). A paragraph in phase-status.md ends the ambiguity; the 2027 rollover is cheaper under (a) or (b).
3. Numbering: retire 5J/5L into the merged tracks (or the reverse) so one map exists.
4. Confirm backup/restore as a hard precondition to Quicken cancellation.
5. Re-pin the runModel freeze boundary in AGENTS.md against the new numbering (recommended wording: frozen until the extraction phase; move-only during extraction; modifiable per spec after).
6. Confirm Gate D planning default (post-freeze) for calendar purposes, independent of the in-flight 5G-1D decision.

---

*Review only. No code, SQL, schema, or status-doc changes were made. This document is uncommitted; commit or discard at Adam's discretion.*
