> **Advisory source review — not implementation authority.** Superseded for sequencing decisions by
> `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md`. Retained for provenance and architectural detail.

# Architecture Review: Cash Planning + Goal Funding, 5-10 Year Horizon

**Date:** 2026-07-12
**Type:** Plan/specification review only. No code reviewed for style or correctness, no SQL executed, no implementation proposed for current phases.
**Frozen inputs treated as given:** 5G-1D (in execution, frozen), the weekly funding engine (runModel waterfall), the reconciliation model (5F-1 + weekly_reconciliations), and the snapshot architecture (5G-1C-2, live with the Week-5 anchor).
**Question under review:** can the planned architecture carry 5-10 years of evolution without a major redesign?
**Sources:** AGENTS.md, CODEX_STATUS.md, docs/phase-status.md, the funding-model integrity review (2026-07-08), the 5G-1C plan + Fable review, the full 5G-1D governance stack (plan, correction spec, readiness package, amendments 1-3, Slice-2 proposal), phase-5g-1-spec v1.4 (planned_outflows), phase-6a-goal-registry-spec v1.1, phase-5f-1-spec v3.12, the Wendy 5G mockup spec v1.2, the June legacy specs (dynamic goal registry, waterfall calculator, wishlist v2, recurring adjustments, 5C architecture, stabilization roadmap), and AI Context 05/08.

---

## 0. Verdict

The architecture is directionally right and unusually well-governed for a household system. The anchor-overlay pattern (observed reality overwrites simulation at reconciled weeks, now applied uniformly to account balances and goal attribution), the append-only/derived-view doctrine, and the gate/golden-master discipline are genuine long-term assets. Nothing in the current plan requires abandonment.

It is not yet a multi-year architecture. Three structural facts will force redesign inside roughly 12 months if they are not addressed as design work at named points:

1. **The plan year is hardwired, not modeled.** `weekly_reconciliations` has no model_year column (the deployed snapshot RPC's own comment says its week-reconciled check is "safe only under the single 31-week 2026 model"). `goal_funding_snapshots` carries `CHECK (week_num BETWEEN 1 AND 31)`. The staged 5G-1D wrapper raises unless `model_year = 2026` and rejects weeks 1-4 as legacy. The WD array is 31 literal rows, calendar week is `22 + model week`, `getCurrentWeek()` clamps at 31, and the opening balances are constants. The model window ends 2027-01-09, about 26 weeks out. Year two is currently impossible to represent, not merely unplanned.
2. **Two parallel subsystems exist for "money set aside toward a future outflow":** goals (registry + waterfall + snapshots) and planned_outflows (events + set-asides + due dates). RCCL/DCL are the proof the boundary is wrong: they are bills with due dates that were modeled as goals, which forced the AMEX holding reclassification (5G-1A), then the excluded-from-snapshots rule, then the 5G-1C-2.1 emergency correction that had to bypass the snapshot RPC's own exclusion by direct SQL. That is a production incident caused by taxonomy, not by a bug.
3. **State is anchored; events are not.** Snapshots durably anchor per-goal state weekly, but the decisions and transfers that produce that state still have no durable identity (weekly_tasks is positionally keyed; the 5G-1B resolver is an adapter, not a model; the Option C event ledger is acknowledged but unscheduled). Long-horizon auditability currently reconstructs *what* the state was, not *why*.

All three have natural landing slots already on the roadmap (the 2027 re-baseline, 5G-4 Dynamic Goal Management, and the 5G-1B/1E/Option-C convergence). The risk is not the current build; it is letting those slots pass without the design work.

---

## 1. The system as reviewed (baseline facts)

- **Engine:** `runModel` re-simulates all 31 weeks from scratch on every run. Weekly deployable cash flows through a strict priority waterfall (VARIABLE/REGULAR_WATERFALL, built from goal_registry by filter + priority sort). Constraints: $6,500 operating floor, $100 MIN_XFR, AMEX 5-week lookahead for `_amxHold` goals, completion carve-outs (mv `allowFin`, 5G-1A.5), `startsAfter` dependencies, `ira_cpa_cleared` flag gate, 40/60 commission split on variable income.
- **Anchoring:** weekly_reconciliations overwrites the five modeled balances (chk/sav/amx/tax/lc) at reconciled weeks; cash_commitments reserve known outflows via `isReservedAsOf` and the Cash Availability Engine; goal_funding_snapshots overwrites `goalSaved` per goal at anchored weeks (overwrite, never add), with `goalVariance` captured. Zero snapshot rows is provably identical to pre-snapshot behavior (identity gate).
- **Goal model:** 13 registry goals, 9 snapshot-eligible, 4 excluded (auto adam_401k; holding wewe_rccl/wewe_dcl; deferred taxable_etf). Statuses: planned/funding/funded/executed/paused/archived; `complete` derived from status. Registry is SELECT-only from the app; all changes are manual SQL.
- **5G-1D (frozen):** one atomic closeout wrapper (recon RPC then snapshot RPC in one transaction), strict `p_mode`, server-derived eligible-nine set, monotonic non-decrease enforced in the wrapper, branch table A-I covering new closeout / idempotent retry / half-close repair / reopen / corrupt states, Option B owner-only correction RPC with neighbor bounds, Gate E for multi-week remediation.
- **Cash planning track (staged):** planned_outflows + append-only outflow_events (cents, real due dates, out-of-window allowed, derived set-aside balances), then derived Spoken For / Free to Use allocation, then Budget identity change (Available for Goals becomes derived), then set-aside recommendations and the earmark adapter into the availability engine.

---

## 2. Goal model

**GM-1. The lifecycle is a status enum, not a state machine.** Six statuses exist with waterfall-inclusion semantics, but no legal-transition matrix exists anywhere (verified: no transition rules in 6A or any 5G doc). Nothing defines whether `funded → funding` (target raised after completion), `executed → archived`, or `paused → funding` are legal, who may perform them, or what each does to snapshots and history. The one real lifecycle event so far (the IRA target correction, $7,000 to $7,500) was a raw UPDATE that triggered the production waterfall deadlock, and its only record is git/docs. Before 5G-5 ships a Goal Admin UI, the transition matrix must exist, or the UI will let a click reproduce the deadlock class. **Severity: high, clock = 5G-4/5G-5.**

**GM-2. Goal creation/edit/repriority are absent by design until 5G-4/5G-5, but the interim has no sanctioned procedure.** Registry changes today are manual SQL against a table with no history (the stabilization roadmap even flags the missing updated_at trigger, TD-10). Reprioritization semantics (unique priorities among active non-auto goals, renumber rules) are enforced only by client validation at load.

**GM-3. Mid-year goal-set changes are currently a closeout hard stop with no procedure.** The 5G-1D wrapper treats any change to the eligible-nine set (add, remove, archive, exclusion change) as goal-scope drift and raises; the eligible set is a function-local constant, deliberately not a live registry query. That is the correct conservative default, but there is no companion scope-change runbook. Wishlist item 34 ("Add Wendy's trips and December trip to goals") is already queued, so this hard stop will be hit in months, not years. **Severity: high, clock = first new goal.**

**GM-4. Pause is unusable in practice.** `paused` exists and the waterfall honors it, but: zero coverage in the snapshot specs (verified: no mention in the 1C plan, prod migration, or 1D plan), pausing an eligible goal changes the eligible set (GM-3 hard stop), and a paused goal drops out of the simulation, leaving its funded display undefined (the snapshot read chain covers complete goals only). Cancellation does not exist as a concept; `archived` conflates cancelled, hidden, and done-and-hidden. The 1C plan's "no snapshots for archived goals" data-quality rule did not carry into the deployed migration or validation SQL, and archive's effect on existing snapshot history is unspecified.

**GM-5. Goal history is half-built, by explicit choice.** Funded-amount history now exists at weekly grain via snapshots (good), but the snapshot upsert mutates the current observation (R12: "not history-grade"), and goal definitions (target, priority, status, dependencies) have no history at all. Consequence for a 10-year system: you cannot answer "what was the plan when week N was decided," which undermines both audit and any future retrospective analytics. See MC-3.

**GM-6. Dependencies are the most mature part of the model and are sufficient.** `startsAfter` (single predecessor, cycle-checked), `dueWeek` (soft), `needsFlag` (external gate). Two caveats: `ira_cpa_cleared` is still session-only (integrity review risk 6, explicitly deferred), so a real CPA clearance does not persist; and `dueWeek` is informational, see FE-2. No need for richer dependency algebra (AND/OR, date-based starts) at this scale; do not build it speculatively.

---

## 3. Funding engine

**Is the abstraction right?** The core abstraction is a deterministic, greedy, strict-priority waterfall replayed from scratch and re-anchored weekly. For a two-adult household with a weekly operating cadence, deterministic replay + anchoring is the right family of design: it is auditable, testable against golden masters, and matches how the operator actually behaves. The challenge is not replay; it is three things layered on top of it:

**FE-1. Eligibility, capacity, and allocation policy are interleaved in one pass, with break-on-defer as global control flow.** One blocked goal can halt the entire week's funding. This exact semantic produced the sub-MIN_XFR deadlock (fixed by carve-out), is implicated in the WC-3 What-If non-monotonicity (still open), and creates the knife-edge behavior the integrity review measured (a ~$220 input wiggle flipping ~$13,500 of downstream funding). The carve-outs (`allowFin`, the 5G-1A.5 call-site exception) are patches on gate ordering, which is the signature of a missing seam. The calculation-core extraction phase should reify four seams: eligible set, capacity constraints (floors, lookahead, reserves), allocation policy (ordering/split rules), and emitted decisions. Whether defer should skip-and-continue instead of break is a real design question with legitimate arguments both ways (break preserves strict priority integrity; skip avoids starvation cliffs); decide it deliberately under golden masters at extraction, not by accretion of carve-outs. **Severity: high, clock = extraction phase (see CP-6 for the roadmap problem).**

**FE-2. The engine is priority-greedy, not deadline-aware, and the deadline-aware system is the *other* subsystem.** `dueWeek` does not schedule anything; RCCL/DCL hit their due dates only because their priorities were manually placed. Meanwhile planned_outflows carries real due dates with accrue-toward-due semantics and (at legacy 5G-4a) shortfall warnings. Two scheduling semantics for the same underlying problem is the same taxonomy fault as GM/CP below. Post-unification, "fund by date" and "fund by priority" become policies on one entity rather than two subsystems.

**FE-3. Funding decisions are not first-class records.** Transfer recommendations are ephemeral model output; execution is recorded in weekly_tasks keyed by `(week_num, task_idx)`. The 5G-1B defect proved the failure mode (executed history vanishing on re-derivation), the resolver fix is an explicit adapter over the missing identity, and the defect doc's binding rule (stable action identity, uniqueness proven, additive migration later) is correct. Snapshots anchor state; they do not record intent vs execution. The Option C ledger is the roadmap's own answer; it needs a slot (see MC-2).

**FE-4. Category coverage, assessed against the requested list:**
- *Weekly decisions, priority handling, partial funding:* sound. Clamped sweeps against `remainingAdjustedSweep` handle partials correctly.
- *Deferred funding:* mechanically sound post-hotfix; deferral reasons are now labeled but not durably recorded (folds into FE-3).
- *Competing goals:* strict priority only. No proportional/ratio split exists, and none is needed now; make the policy pluggable at extraction rather than adding modes speculatively.
- *Recurring goals:* correctly not modeled as goals; recurrence lives in planned_outflows (`auto_renew`, logic deliberately deferred) and budget lines. Keep it there.
- *Sinking funds:* planned_outflows **is** the sinking-fund system. RCCL/DCL were sinking funds forced into the goal registry; the holding hack and the 2.1 incident are the cost. This is the strongest single piece of evidence for unification (SO-1).
- *Reserve goals:* absent. The only reserve machinery is the $6,500 floor constant and the AMEX lookahead. There is no emergency-fund entity, no reserve target, no reserve health tracking. For a household OS with a stated Horizon C (retirement/reserve planning), this is a missing concept (MC-5), not a missing feature.
- *Emergency overrides:* absent. There is no defined way to pull cash back out of a funded goal. Until 5G-1B releases exist, the only decrease path is a governance-heavy correction. An "unfund/redirect" concept should arrive with releases, not as another correction variant.
- *Manual overrides:* model_week_overrides, scenario commits, and the correction paths cover it; all are audit-light except corrections (see SM-5).

---

## 4. Cash planning

**CP-1. The doctrine is right and should be defended as law:** Register is the sole actuals ledger; Budget is plan/spent/remaining; planned money is never fake transactions; allocation views are derived, never stored; append-only events with compensating entries. The 5G-1 spec (v1.4) is the best table design in the system (cents, real due dates, out-of-window support, sign-constrained events, immutable identity columns, grant normalization). The two-entry wrinkle (real transfer in Register + planning event in Cash Planning) is honestly disclosed and is the correct v1 trade.

**CP-2. "Available for Goals" is still hand-balanced, and the phase that fixes it has no slot.** The Budget identity change (income minus planned = derived Available for Goals, hand-balancing retired) was legacy 5G-3. The 2026-07-08 roadmap reorganization explicitly left the legacy gates ("calc-core extraction 5G-2.5, set-aside safe-sweep 5G-4a, zero-outflow identity test 5G-4b, Budget identity legacy-5G-3, spreadsheet retirement legacy-5G-5") with "fold-in TBD" against the new 5G-2..5G-6 numbering. Until that mapping is resolved, the roadmap's authoritative table contains neither the Budget-identity change nor the extraction gate as first-class rows. This is a documentation defect with architectural consequences: gates that exist only in a superseded table get lost. **Fix is docs-only and cheap; do it before 5G-1D closes.**

**CP-3. Four representations of future obligations coexist:** WD/budget-rule outflows (model baseline), cash_commitments (initiated-but-uncleared reserves), planned_outflows (save-up bills), and goals-with-due-weeks. Each is individually justified, and 5F-1's reserve precedence rule (an actual payment entering reconciliation releases the reserve in the same closeout) shows the seams can be managed. But the ownership rules ("which system represents which obligation, and when does an item migrate between them") exist only as tribal knowledge across specs. A one-page obligation taxonomy (what goes where, with the migration events) would prevent the RCCL/DCL class of misfiling from recurring. **Cheap, high leverage.**

**CP-4. Reservation logic is about to fork.** The Cash Availability Engine consumes cash_commitments through `isReservedAsOf`. The earmark-funded adapter (legacy 5G-4b) will feed planned_outflow earmarks into the same engine as "reserve-shaped adapter records." The spec language is right (input layer only), but the shape should be literally the same reservation interface, not a parallel one: one reservation contract, two producers. Decide that at 4b design time (SO-2).

**CP-5. Forecasting and horizons.** The 31-week window with anchored history + projected future is coherent, and labels now distinguish the two (5G-1C-1). Long-horizon planning (Horizon C: retirement, 529 trajectories, coast-FI) is aspirational and correctly out of scope; the important architectural point is only that planned_outflows already proves the pattern for beyond-window items (real dates, accrue now, no model coupling). Multi-horizon planning should extend that pattern rather than stretching the weekly model's window.

**CP-6. Checking protection is constants-in-code.** OP_FL ($6,500), MIN_XFR ($100), the 5-week lookahead depth, seed amounts, and the IRA seed threshold are all code literals; two of them have already been implicated in incidents (MIN_XFR in the deadlock, the uncapped seed in the 2.1 regression). They belong in versioned configuration once the calc core is extracted (MC-7). Not urgent standalone; urgent as an extraction deliverable.

---

## 5. State machine

**SM-1. What exists is genuinely strong.** The 5G-1D branch table (A-I) with a proven partition, complete-retry identity across both halves, half-close repair targeting the earliest gap, an owner-only reopen sub-machine with commitment-array narrowing (AM2), neighbor-bounded corrections with existing-row requirements ("a correction is an amendment, never a backfill"), advisory locks + ordered row locks, and Gate E for anything multi-week. This is more rigorous than most commercial ledgers. The review found no missing branch within the single-year, fixed-goal-set frame.

**SM-2. The missing states are all at the frame boundaries:**
- *Goal-set change* (add/pause/archive/exclusion change): hard stop exists, procedure does not (GM-3).
- *Year rollover:* no branch, no procedure, structurally blocked by schema (verdict item 1). The E2 opening-anchor pattern is the proven mechanism a new plan period would need; it just is not generalized.
- *Holding release* (5G-1B): wewe_rccl/wewe_dcl now hold Week-5 `correction` rows stating funded progress (600/500) that will diverge from cash location when the real cruise payments leave AMEX (~Cal Wk 30 and 41; Wk 30 lands inside the Alaska freeze). This is a documented, accepted offset, and the one-sided advisory invariant will correctly stay quiet. But the 1B design must also specify the terminal treatment of those two Week-5 rows, or they become permanent fossils that every future validator must special-case (the anchor guard already had to be amended once to tolerate them, AM1 §A).
- *Post-Option-B holding corrections:* Option B validates `p_goal_id` against the eligible nine, and D1 retires Option A for post-anchor corrections once B deploys. Net effect: after activation, a wewe_* or any excluded-goal row has no sanctioned correction path except full Gate-E-style exceptional remediation. Probably acceptable; currently implicit. Name it in the Slice-2 review so it is a decision, not an accident.

**SM-3. Invalid transitions are well guarded on the snapshot side and unguarded on the registry side.** The wrapper prevents every identified snapshot misuse, but `repair_commitments_for_week` (REST-callable by both operators today, able to mutate closed weeks; Gate C open) and direct registry UPDATEs remain the two bypass surfaces. Gate C is already tracked; registry governance is not (GM-1/GM-2).

**SM-4. Recovery is designed for data errors, not for infrastructure loss.** Half-close repair, reopen, corrections, and Gate E cover state errors well. But the durable evidence layer (Value Cards, filled execution SQL, pre-write exports, artifact hashes) lives only in `~/Herndon-FOS-DB-Backups` on one machine by privacy design, and the database itself is on the Supabase Free plan with no PITR, with restore points being local pg_dumps. For a system whose correction discipline depends on pre-write exports as the "no automatic rollback" recovery baseline, a single laptop failure deletes both the audit trail and the recovery baseline. This is an architecture-level availability gap, not an ops detail (MC-9). **Cheap to fix; disproportionate downside if unfixed.**

**SM-5. Audit and historical reconstruction are asymmetric.** Reconstructible: per-goal funded state at every anchored week (snapshots), balance history (reconciliations), budget plan by month (budget_line_rules is properly interval-dated, the one existing SCD-style table). Not reconstructible: goal definitions as-of a week (mutable registry), why a transfer happened (FE-3), original recorded_at after a reopen (AM3 re-stamps; original survives only in local evidence), model constants as-of (git only). If long-horizon auditability is a requirement, and the governance stack's behavior says it is, then registry versioning and the event ledger are the two missing halves (MC-2, MC-3).

---

## 6. Extensibility (evaluate accommodation, not build)

| Capability | Verdict | Blocking coupling |
|---|---|---|
| Additional account types | **Blocked at the engine** | runModel models exactly five balances (chk/sav/amx/tax/lc) plus a `'goal'` sentinel meaning "external, untracked" (the sentinel is precisely how RCCL/DCL got lost pre-5G-1A). The DB layer is already account-generic (accounts table, FK'd planned_outflows). Generalizing model state to account-keyed balances belongs to the extraction phase; do not attempt before it. |
| Investment goals | **Accommodated only if monotonicity stays a policy, not a law** | Snapshots assume funded_amount changes by contributions (non-decreasing except corrections). Market-valued goals (taxable_etf is already parked in the exclusion set) violate that. The accommodation is a per-goal policy flag exempting valuation-bearing goals from the monotonic rule, plus a valuation observation distinct from contribution. Do not promote the monotonic rule into more hard invariants than 5G-1D already does. |
| Debt payoff strategies | **Accommodated at 5G-4 if goals gain a direction/type** | A payoff target is structurally a goal whose "funded" is principal reduction. Feasible on the current chassis; requires the unified funding-target entity to carry a type. No engine change needed beyond policy. |
| Recurring annual expenses | **Already designed** | planned_outflows + auto_renew (logic deferred deliberately). Right home; keep recurrence out of the goal registry. |
| User-defined funding strategies | **Blocked until extraction separates allocation policy** | Strategy today = hardcoded strict priority + constants, and the waterfall order is Do Not Touch. After FE-1's seams exist, strategies become data. Before that, any "strategy" feature would fork the engine. |
| Multiple planning horizons | **Blocked by the missing plan-period concept** | Same root as year rollover. A plan period entity (id, start date, week count, opening anchors, parameter set) unblocks both the 2027 rollover and any future horizon variation. WD-as-31-literals is the deepest coupling. |
| Configurable policies | **Cheap after extraction** | Constants to a versioned parameter table read at model init, changes audited. Prerequisite: extraction; otherwise it is config theater over hardcoded control flow. |

---

## 7. Missing concepts (ranked by structural leverage)

1. **MC-1: Plan Period.** A first-class period entity: identifier, start date, week range, opening anchors (the E2 pattern, generalized into the sanctioned seeding mechanism), parameter/constant set, and week-numbering rules. Every current year-pin (snapshots CHECK 1..31, wrapper model_year=2026, weekly_reconciliations week-only keying, WD literals, calendar offset, current-week clamp) becomes an instance value. Without it, every January is a hand-run migration crisis; with it, year rollover is a seeding procedure that already exists.
2. **MC-2: The funding event ledger (Option C) as a convergence commitment.** Four pressures already point at the same table: durable transfer identity (5G-1B defect's binding rule), holding releases (5G-1B), correction audit grain (R12's "history grade arrives with the later ledger"), and the 1E hard invariant. The concept is accepted in the docs; what is missing is the commitment that these arrive as **one** ledger rather than three partial stores. Snapshots stay the weekly observation checkpoints; events assert intent/execution.
3. **MC-3: Goal definition history.** Either interval-dated registry rows (the budget_line_rules pattern, already proven in-house) or a goal_change event table. Required before 5G-5 gives editing a UI; also what makes GM-1's transition matrix enforceable and SM-5's reconstruction possible.
4. **MC-4: Release/payout semantics** (5G-1B), including terminal disposition of the Week-5 wewe_* correction rows and the funded-progress vs cash-held distinction that 2.1 exposed. Prerequisite for the 1E hard invariant; currently deferred with no slot.
5. **MC-5: Liquidity reserve as an entity.** The operating floor and any future emergency fund are reserve targets with health states, not code constants. Fold into the unified target entity or the parameter set; do not leave the household's most important safety number as a literal.
6. **MC-6: A money-representation standard.** cents BIGINT (cash_commitments, planned_outflows) vs NUMERIC(12,2) dollars (goal_registry, goal_funding_snapshots) vs JS floats with `r()` rounding in the engine. Pick cents for everything new, document the boundary, convert old tables opportunistically. Cross-subsystem sums (the AMEX invariant, future allocation views) are where mixed units eventually bite.
7. **MC-7: Versioned policy/parameter configuration** (see CP-6, extensibility row 7).
8. **MC-8: A variance/exception ledger.** Balance variance, goalVariance, the one-sided AMEX advisory, SA8 under-attribution, and future shortfall warnings are each surfaced ad hoc. One exception stream with type/severity/acknowledgement would make "is the system healthy" a single query instead of a tour.
9. **MC-9: Durable off-machine evidence and backup posture.** Paid-tier PITR or scheduled encrypted off-site dumps for both the DB and the local evidence directory. The privacy discipline (balance-free repo) is right; the conclusion "therefore evidence lives on one laptop" does not follow.
10. **MC-10: A goal-scope-change procedure** (the sanctioned path through GM-3's hard stop): versioned eligible-set, wrapper reads version N as of week W, scope changes are events. This is the piece that makes the eligible-nine constant evolvable.

---

## 8. Simplification opportunities

**SO-1: One funding-target entity (the big one).** Goals and planned_outflows are the same concept with different policies: both have a target amount, cumulative progress, a funding account, optional due date, releases, and a lifecycle. Sinking funds, reserve goals, recurring annual bills, debt payoff, and today's registry goals become policy variants (funding source: waterfall-surplus vs scheduled set-aside; deadline-driven vs priority-driven; releasing vs terminal; monotonic vs valuation-bearing). The Wendy-facing groupings stay views, exactly as the 5G doctrine already insists for planned_outflows. Evidence this is the correct move rather than speculative generalization: RCCL/DCL live in both worlds today and broke production; FE-2's dual scheduling semantics; the four-way obligation split (CP-3). **5G-4 (Dynamic Goal Management Architecture) is the natural and last cheap venue.** Unifying after both subsystems have independent UIs, ledgers, and operator habits roughly doubles the cost.

**SO-2: One reservation interface** into the Cash Availability Engine (cash_commitments and 4b earmarks as two producers of one contract), instead of a second bespoke adapter shape. Decide at 4b design.

**SO-3: One event ledger** (MC-2) absorbing outflow_events' proven pattern, weekly_tasks completions, 1B releases, and correction evidence rows, instead of three partial event stores plus local-only evidence.

**SO-4: One correction discipline.** Option B's pattern (existing-row requirement, neighbor bounds, owner gate, evidence package, call-through to the standard write path) is generalizable to every future correctable store (registry changes, planned_outflow adjustments beyond `adjust`, period parameters). Write it once as the house correction pattern; stop re-deriving it per table.

**SO-5: Account-keyed engine state** replacing the five-balance tuple and the `'goal'` sentinel at extraction time (extensibility row 1).

**SO-6: Parameters to configuration** (MC-7) rather than accreting more named constants with per-constant hotfixes.

---

## 9. Final assessment

### 9.1 Major strengths

1. **The anchor-overlay unification.** Accounts and goals now re-anchor on the same weekly cadence with the same overwrite semantics and the same variance concept. This is the single most important architectural decision in the system and it is correct; it structurally eliminates re-simulation double-counting and turns "model agrees with reality" from a coincidence into a weekly property.
2. **Accounting doctrine.** Append-only events, compensating corrections, derived views, no stored balances, no fake transactions, single actuals ledger. The 5G-1 spec is a model of it.
3. **Verification and governance machinery.** Identity gates (GR-A1, zero-snapshot), golden masters, staging-first rehearsal with fingerprint guards, exact-grant validation, gate registers with explicit non-authorization language, privacy discipline. This is what makes incremental evolution credible at all.
4. **Honest failure handling.** Known offsets are documented as known (RCCL/DCL), advisory invariants are one-sided on purpose, defects get root-caused into binding rules (5G-1B), and wrong prior diagnostics get corrected in writing (integrity review §3).
5. **The 5G-1D state machine itself.** Branch partition proof, retry identity, half-close repair, neighbor-bounded corrections. Frozen as-is, it is a solid foundation.

### 9.2 Architectural weaknesses

Ranked: (1) single-year hardwiring across schema, RPCs, engine, and constants; (2) the dual goals/planned_outflows subsystems with a demonstrated incident cost; (3) missing durable event/decision identity; (4) unversioned, transition-rule-free goal registry beneath a heavily governed snapshot layer (rigor inversion: the observations are governed, the definitions are not); (5) scope-drift hard stop without a change procedure; (6) roadmap fold-in gap orphaning the extraction and Budget-identity gates; (7) policy constants in code; (8) single-machine evidence/backup posture; (9) mixed money representations.

### 9.3 Highest-risk assumptions (challenged)

- **A1: "2027 is a re-baseline task."** False as stated. It is schema (two CHECKs, a missing year column), RPC pins, engine constants, WD data, and week arithmetic. If design starts after the freeze-and-holidays sequence, January arrives with collision-prone week_num reuse in weekly_reconciliations as the forcing function. This is the most predictable major-redesign trigger in the system.
- **A2: "The goal set is stable within the year."** Already contradicted by the wishlist. The hard stop is correct; the absence of the procedure behind it converts a routine product request into a frozen closeout.
- **A3: "funded_amount is monotonic except corrections."** Only true for contribution-only goals before releases exist. Payouts (Wk 30/41) and any future valuation-bearing goal make the exception the rule. Keep monotonicity a wrapper policy; do not let it harden into more invariants.
- **A4: "Reality follows the plan between anchors."** Now bounded to one week by 1D, which is the right mitigation. Residual risk accepted.
- **A5: "Option A retires when Option B deploys" (D1).** Under-specified: B rejects excluded goals and week 5, so anchor amendments and holding-row fixes remain permanently on the manual path. Fine if named; today it reads as if the manual path disappears.
- **A6: "Gates survive roadmap renumbering."** The fold-in gap is exactly how a load-bearing gate (extraction before waterfall changes) gets silently lost.

### 9.4 Recommended redesigns, with confidence

| # | Recommendation | Confidence |
|---|---|---|
| R1 | **Plan Period design** (MC-1): design doc + rollover runbook targeting the 2027 boundary; includes the schema deltas (year-scope weekly_reconciliations, relax week CHECKs per period), generalized opening-anchor seeding, and parameterized constants. Design only in 2026; execute as the re-baseline. | High |
| R2 | **Funding-target unification at 5G-4** (SO-1), with goal type/policy fields, registry history (MC-3), the transition matrix (GM-1), and the scope-change procedure (MC-10) as the same package, all before any 5G-5 UI. | High on direction and venue; medium on final entity shape (needs its own spec round) |
| R3 | **Extraction with reified seams** (FE-1): eligibility / capacity / policy / decision emission, under the already-mandated golden masters; the skip-vs-break decision made there deliberately; constants externalized (MC-7) as part of it. | High that it must precede waterfall/Budget-identity changes (already house law; re-affirm through the fold-in fix); medium on skip-vs-break outcome |
| R4 | **Commit to Option C as the single event ledger** (MC-2/SO-3), scheduled where 1B releases land, absorbing transfer identity and correction audit grain. | Medium-high (timing flexible; singularity of the ledger is the point) |
| R5 | **Resolve the roadmap fold-in now, docs-only** (CP-2): re-home extraction, Budget-identity, 4a/4b gates, and spreadsheet retirement into the authoritative table. | High |
| R6 | **Backup/evidence durability** (MC-9): PITR-capable tier or scheduled off-site encrypted dumps + a second copy of the local evidence directory. | High (small cost, tail-risk elimination) |
| R7 | **Obligation taxonomy one-pager** (CP-3) and the D1 scope clarification (A5) folded into the Slice-2 review. | High |

### 9.5 Recommended sequencing

1. **Now, inside current constraints (docs-only, no 5G-1D disturbance):** R5 fold-in resolution; R7 taxonomy page + D1 clarification; R6 backup decision. None touch frozen code.
2. **5G-1D executes as planned.** Nothing in this review changes it; Slice 2's binding criteria (strict p_mode, owner-approved correction procedure) stand.
3. **Post-1D, pre-freeze or immediately post-freeze:** 5G-1B release design (MC-4), because the Wk-30 RCCL payout starts the divergence clock and 1E's hard invariant depends on it; include the Week-5 wewe_* terminal rule.
4. **September-October:** R1 Plan Period design doc (target: approved before November), in parallel with the 5G-2 planned_outflows build it does not touch.
5. **5G-4 becomes the unification + goal-governance phase** (R2), explicitly scoped as such before any 5G-5 UI work; extraction (R3) lands per its existing gate before waterfall or Budget-identity changes.
6. **Option C ledger** (R4) rides 1B/1E, not later than the first phase that would otherwise create a second event store.

### 9.6 Bottom line

Verdict against the stated objective ("internally consistent, auditable, extensible, maintainable over many years without major redesign"): **achievable on the current trajectory, conditional on three design commitments that have deadlines whether or not they are made** — the plan-period model (calendar-forced, ~26 weeks), goal-set governance + unification at 5G-4 (product-forced by the next new goal), and event-ledger convergence at 1B/1E (payout-forced starting ~Cal Wk 30). The system's governance culture is its best asset; the main failure mode to guard against is spending that rigor exclusively on the observation layer while the definition layer (registry, constants, roadmap mapping) stays informal.

---

*Review only. No code, SQL, schema, RPC, RLS, migration, or seed changes. 5G-1D remains frozen and authoritative for its scope; nothing here amends it. This document is a triage input for future phase planning, not implementation authority.*
