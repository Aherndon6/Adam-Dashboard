# Phase 5G-1D — Implementation-Readiness Package (Slice-by-Slice)

**Status:** PLAN-ONLY. **Not started, not implemented, not activated.** No code, SQL,
schema, RPC, RLS, migration, seed, grant change, or test written or run this pass. No
Supabase access. E2 has **not** executed; `goal_funding_snapshots` is **EMPTY**; the
5G-1D wrapper does **not** exist yet.
**Author:** Claude (session under Adam)
**Date:** 2026-07-10

**Purpose (Fable B-1 option (a)).** This is the **full slice-by-slice
implementation-readiness package** for 5G-1D — expanded from the decision/gate spine so
it can **substitute for per-slice Fable implementation reviews after July 12**. It records
the approved Adam decisions, the blocking/future decision gates, a slice-by-slice
readiness layer (Slices 0–7), a grounded touchpoint inventory, a test-to-slice matrix, and
the activation decision card. It **operationalizes** the cleared artifacts; it does not
replace or override them.

**Subordinate to — and consistent with, not a replacement for (all cleared; do NOT edit
any of them):**
1. `docs/phase-5g-1c-2-e2-runbook.md` — cleared E2 first-anchor seed gate.
2. `docs/phase-5g-1d-plan-2026-07-09.md` — cleared 5G-1D write-through plan (authoritative
   slice sequence in **§10 item 6**, wrapper modes, contracts).
3. `docs/phase-5g-1d-snapshot-correction-procedure-2026-07-10.md` — cleared correction /
   reopen / remediation companion spec (merged to `main` at `f005263`); its §15 test
   matrix and §17 acceptance criteria are absorbed below.

**Hierarchy rule (§17 of the correction spec / this §17 below).** This package may
consolidate and operationalize the three cleared artifacts' requirements; it may **not**
override them. Where consolidation surfaced a divergence, it is **flagged in-line**, never
resolved silently. (One re-grouping note is flagged in §4.0.)

**Deferred status-doc updates.** `CODEX_STATUS.md` / `docs/phase-status.md` are updated
**only after this readiness package is reviewed and cleared** — not this pass. The exact
handoff content is specified in §8; this file does not perform it.

**Proposed-vs-current convention.** Every touchpoint below is tagged **[CURRENT]** (exists
in the repo now, grounded to file/line) or **[PROPOSED]** (a future artifact/object that
does not yet exist). No filename or function is invented as if current.

---

## 1. Decisions approved now (Adam, 2026-07-10) — preserved spine

Unchanged from the prior readiness draft; not weakened or reinterpreted.

### D1 — Option A is a temporary bridge only
- The supervised **guarded-SQL correction path (Option A)** is **not** the steady-state
  operating model.
- It exists to make a rare correction executable *before* Option B ships.
- **It retires for post-anchor corrections the moment Option B is deployed.**
- Week-5 opening-anchor amendments are the sole exception — they stay on the guarded-SQL
  path (D3), preserving `source='opening_anchor'`.
- Resolves correction spec §19 item 1 and §4.2.

### D2 — Option B built in 5G-1D Slice 2
- The **owner-only correction wrapper** (`public.correct_goal_funding_snapshot(...)`,
  **[PROPOSED]**) is part of the **Slice-2 staging package**.
- It must enforce: **target-row existence**; **nearest-existing monotonicity bounds**
  (correction spec §7.0); **internal `public.is_owner()`**; **`household_admin` (Wendy)
  rejection**; **call-through to the deployed `public.save_goal_funding_snapshots(...)`**
  (no reproduced logic, no direct table write); one **`source='correction'`** post-anchor
  row; post-call returned-row validation; full exception propagation.
- Resolves correction spec §19 item 1 and §4.1.

### D3 — Week-5 opening-anchor amendments preserve `source='opening_anchor'`
- A value amendment to an existing Week-5 anchor row **keeps `source='opening_anchor'`**;
  the row source is **not** changed to `correction`.
- The **external evidence records the amendment** (plus row `note`); the change is not
  encoded by flipping `source`.
- The **nine-row opening-anchor completeness guard must continue to pass** (5G-1D plan
  §5.6).
- Anchor amendments run on the **guarded-SQL path, not Option B** (correction spec §8.1).
- Resolves correction spec §19 item 5 and §8.0 (overrides the E2 runbook §8
  "`source='correction'` for a wrong seed" language **for the anchor case only**, without
  editing the cleared runbook).

---

## 2. Decision gates

Each is an explicit gate with a trigger point. **Gate 0 is new (B-2) and BLOCKING.**
Gates A–E are preserved and expanded.

### Gate 0 — E2 completion (NEW; BLOCKING) — B-2
- **Decision:** E2 production first-anchor seed must be **complete and validated before any
  5G-1D implementation begins.**
- **Status:** OPEN / BLOCKING.
- **Trigger:** before Slice 0 begins.
- **Required evidence:**
  - Week 5 reconciliation complete;
  - Week 5 remains the latest reconciled week at execution (`max(week_num)=5`);
  - approved First-Anchor Value Card;
  - E2 seed completed;
  - SA-PROD validation passed;
  - exactly nine Week-5 `opening_anchor` rows;
  - live browser verification completed (E2 runbook Step 7);
  - E2 closeout evidence recorded;
  - cleared runbook execution conditions satisfied (E2 runbook §0/§3 approval chain +
    freshness).
- **Approver:** Adam.
- **Hard stop:**
  - no Slice 0 work if E2 is incomplete;
  - **no silent adaptation if the Week-5 anchor window is missed** — a missed window
    requires a **new Value Card, explicit Adam approval, and re-review of every
    Week-5-pinned assumption** (E2 runbook §2.2 / §9).

### Gate A — `public.is_owner()` identity verification
- **Trigger:** before staging acceptance of any owner-only reopen or correction
  functionality. *(Non-blocking clarification, §9: the read-only preflight MAY be run
  earlier — before Slice-2 coding — as early de-risking, but staging acceptance remains
  the hard trigger.)*
- **Required proof (read-only production preflight; no role-data change):** exactly one
  active owner row (`role='owner' AND active=true`); Adam's real authenticated account
  maps to that owner row (the app login, not the `adam@herndons.us` seed identity); Adam's
  session returns `public.is_owner()=true`; Wendy's session returns `false`.
- **Approver:** Adam.
- **Hard stop:** ship any `is_owner()`-gated path before this proof → STOP. Correction spec
  Finding 8 / §19 item 2.

### Gate B — Option B activation gate
- **Default:** **5G-1D production activation REQUIRES Option B** deployed and tested.
- **Exception:** only by a **separate Adam approval of a dated deferral** containing
  **rationale, owner, expiration/review date, and interim controls** — never implicit or
  open-ended.
- **Trigger:** before production activation approval.
- **Approver:** Adam.
- **Hard stop:** activate 5G-1D without Option B **and** without an approved dated deferral
  → STOP. Correction spec §4.2 / §19 item 1.

### Gate C — `repair_commitments_for_week` activation posture
- **Trigger:** before the activation grant changes (5G-1D plan §7).
- **Do not decide until the caller/dependency audit is complete** (Slice 2 conducts it).
- **Required decision — choose and record exactly one posture:** retain with documented
  restriction; wrap behind an owner-only control; revoke `authenticated` EXECUTE; or
  another explicitly reviewed posture.
- **Context:** deployed `repair_commitments_for_week(INT,INT,TEXT,JSONB,JSONB)` is
  `can_write_financials()`-gated, REST-callable by Wendy, and can mutate a closed/anchored
  week's commitments and `weekly_reconciliations.balance_basis` (correction spec Finding
  11 / §3.1).
- **Approver:** Adam.
- **Hard stop:** activate 5G-1D while this posture is undecided/unreviewed → STOP.

### Gate D — Pre-freeze vs post-freeze activation timing
- **Trigger:** implementation-readiness decision card (§7 below).
- **Required output:** consequences of activating **before the Week-6 closeout** vs **after
  the Alaska freeze (Jul 24–Aug 10)**; gap-remediation implications; explicit Adam
  decision.
- **Approver:** Adam.
- **Hard stop:** merge/activate inside the Alaska freeze without an explicit timing
  decision → STOP (no 5G merges Jul 24–Aug 10; an explicit decision does not override the
  freeze).

### Gate E — Any historical multi-week remediation
- **Trigger:** whenever a correction would change later weeks (or deliberately create a
  missing historical row / backfill).
- **Required action:** a separate remediation plan + explicit Adam approval; no silent
  cascade; no backfill under an ordinary correction approval.
- **Approver:** Adam.
- **Hard stop:** cascade/backfill under an ordinary correction approval → STOP. Correction
  spec §10 / §7.0.

---

## 3. Consolidated gate register

Status legend: **APPROVED** = decided now; **OPEN** = pending at trigger; **BLOCKING** =
gates the start of implementation.

| # | Decision / gate | Status | Trigger point | Required evidence | Approver | Hard-stop condition |
|---|---|---|---|---|---|---|
| **0** | E2 completion | **OPEN / BLOCKING** | Before Slice 0 | Wk-5 recon complete + latest; approved Value Card; seed done; SA-PROD pass; nine `opening_anchor` rows; live verify; closeout evidence; runbook conditions met | Adam | Any Slice-0 work with E2 incomplete; silent adaptation on a missed Wk-5 window |
| **D1** | Option A temporary bridge only | **APPROVED** | Option B deployment | Option B live + tested; Option A disabled for post-anchor corrections | Adam | Option A used for a post-anchor correction after Option B ships |
| **D2** | Option B built in Slice 2 | **APPROVED** | Slice-2 staging build | Wrapper enforces row-existence, nearest-existing bounds, `is_owner()`, Wendy rejection, call-through; §15 tests green | Adam | Wrapper reproduces/writes table directly, or omits an enforced control |
| **D3** | Wk-5 anchor keeps `source='opening_anchor'` | **APPROVED** | Any anchor amendment | Nine-row `opening_anchor` guard passes; evidence records amendment | Adam | Anchor row flipped to `correction`, or guard fails |
| **A** | `is_owner()` identity verification | **OPEN** | Before staging acceptance of owner-only reopen/correction (may run earlier as de-risk) | One active owner row; Adam maps to it; Adam `is_owner()=true`; Wendy `false`; read-only | Adam | Ship an `is_owner()`-gated path before the proof |
| **B** | Option B activation gate | **OPEN** | Before production activation approval | Option B deployed+tested, or a dated Adam deferral (rationale/owner/expiry/controls) | Adam | Activate without Option B and without an approved dated deferral |
| **C** | `repair_commitments_for_week` posture | **OPEN** (blocked on audit) | Before activation grant changes | Completed caller/dependency audit + one recorded posture | Adam | Activate with the posture undecided/unreviewed |
| **D** | Pre-freeze vs post-freeze timing | **OPEN** | Readiness decision card | Before/after-freeze consequence analysis + gap-remediation + Adam decision | Adam | Merge/activate in Alaska freeze without an explicit decision |
| **E** | Historical multi-week remediation | **OPEN** (event-driven) | When a correction would change later weeks / backfill | Separate remediation plan + before/after matrix + explicit approval | Adam | Cascade/backfill under an ordinary correction approval |

---

## 4. Slice-by-slice readiness layer (Slices 0–7)

### 4.0 Slice-numbering note (flagged, not silent) — subordinate to plan §10 item 6

The cleared 5G-1D plan's execution checklist (**§10 item 6**) sequences: Slice 0
(read-only closeout-complete state) → Slice 1 (client payload builder) → Slice 2 (wrapper
RPC) → Slice 3 (confirmation view + state machine) → Slice 4 (test matrix) → Slice 5
(staging smoke) → Slice 6 (prod inert deploy + browser deploy + inert checks) →
**activation gate** → Slice 7 (Week-6 writer smoke). **This readiness package re-groups
those same steps** into eight review-substitutable slices (0 baseline; 1 core RPC; 2
retry/reopen/correction; 3 browser workflow; 4 closeout-complete + repair states; 5
staging + failure injection; 6 production inert deploy; 7 browser deploy + activation +
first live closeout). **This is an operational re-grouping for review, not an override of
the plan** — every plan step maps into a slice below, no plan requirement is dropped, and
the plan's contracts (wrapper modes, anchor contract, source pinning, direct-call-only,
monotonicity) are unchanged. Where a plan step moved slices, it is noted in that slice's
*dependencies*. No contradiction was found in the cleared artifacts during this
consolidation.

Each slice records the seventeen required elements. **"§15 tests"** everywhere means the
**correction companion spec §15**; **"plan §8"** means the cleared 5G-1D plan's testing
section.

---

### Slice 0 — Baseline & E2-dependency verification (implementation-start gate)

- **Objective:** prove the implementation may begin and capture the pre-implementation
  characterization baseline. It is the gate, not a feature.
- **Exact scope:** verification + baseline evidence only. **No implementation changes
  beyond approved characterization/test scaffolding (if any).**
- **Dependencies:** Gate 0 CLOSED (E2 complete + validated). *(Maps plan §10.6 "E2 done +
  validated" + the read-only side of plan Slice 0.)*
- **Entry criteria:** Gate 0 evidence present; working tree clean; on the feature branch.
- **Exact repository touchpoints:**
  - **[CURRENT]** deployed reconciliation RPC — `save_reconciliation_with_commitments`
    (`docs/phase-5f-1-migration.sql:454`; grant `:964`).
  - **[CURRENT]** deployed E1 snapshot RPC/table —
    `public.save_goal_funding_snapshots` (`docs/phase-5g-1c-2-prod-migration.sql:160`;
    grant `:283`) + `public.goal_funding_snapshots` (`:120`).
  - **[CURRENT]** snapshot loader (`index.html:7843`), `_latestGoalSnapshot`
    (`index.html:4341`), C3 overlay (`index.html:2571`), `getGoalFunded`
    (`index.html:4349`), `goalCompletion` build (`index.html:3131`).
  - **[CURRENT]** reconciliation callers: `saveRecon` (`index.html:2729`),
    `reloadReconAndCommitments` (`index.html:2716`), `canPersistReconNow`
    (`index.html:3740`) / `canSaveRecon` (`:3749`), `isWeekReconciled` (`:1001`).
  - **[CURRENT]** `repair_commitments_for_week` (`docs/phase-5f-1-migration.sql:997`;
    grant `:1338`).
  - **[CURRENT]** owner predicates `public.can_write_financials()` / `public.is_owner()`
    (`docs/phase-5a-role-enforcement.sql:43`/`:64`); client `isOwnerUser()`
    (`index.html:7786`), `canWriteFinancials()` (`:7787`).
  - **[CURRENT]** 5G-QA-1 runner `e2e.js` (smoke tags `opts.tags:['smoke']`; strict mode
    parse).
- **Allowed files:** none edited (read-only). If characterization scaffolding is approved,
  `test_regression.js` / `e2e.js` only.
- **Prohibited files/contracts:** `index.html` runtime; any deployed SQL; the three cleared
  artifacts; golden-master expected outputs; `runModel` internals (frozen through 5G-2).
- **Database objects involved:** read-only inspection of the reconciliation RPC, E1 RPC +
  table + RLS + grants; `weekly_reconciliations`; `goal_registry`.
- **Application functions/modules:** the reconciliation + snapshot touchpoints above
  (read-only).
- **Required tests:** confirm 5G-QA-1 **smoke and full** gates green; capture golden-master
  identity baseline (zero-snapshot run byte-identical).
- **Failure-injection tests:** none (no runtime change).
- **Security/grant checks:** record current grants on the reconciliation RPC, E1 RPC,
  `repair_commitments_for_week`; confirm no unexpected caller path.
- **Required evidence:** byte hashes/definitions of the deployed reconciliation RPC and E1
  snapshot RPC captured; snapshot table + contracts confirmed against the cleared plan;
  complete Week-5 anchor confirmed (nine `opening_anchor`, one week); baseline evidence
  file (balance-free).
- **Exit criteria:** all of the above captured and green; the complete Week-5 anchor and
  the two deployed RPC baselines are pinned for the contract-unchanged proofs used in later
  slices.
- **Hard stop conditions:** E2 incomplete; Week-5 anchor incomplete or mixed-source;
  deployed RPC definitions differ from the cleared baseline; any current caller or grant
  path not understood.
- **Fable-style review checklist:** ☐ Gate 0 evidence complete ☐ anchor nine/one/all-
  opening_anchor ☐ RPC baselines hashed ☐ callers enumerated ☐ QA-1 green ☐ no runtime edit.
- **Does NOT authorize:** any wrapper, any DB write, any grant change, any browser change.

---

### Slice 1 — Core orchestration RPC (`save_weekly_closeout_with_snapshots`)

- **Objective:** the additive single-transaction weekly-closeout wrapper (`normal_closeout`
  path). *(Maps plan Slice 2 core + plan Slice 1 payload builder.)*
- **Exact scope:** the **[PROPOSED]** `public.save_weekly_closeout_with_snapshots(<recon
  params…>, p_snapshot_rows JSONB, p_mode TEXT DEFAULT 'normal_closeout', p_expected_count
  INT DEFAULT NULL)` (5G-1D plan §5.2) plus the pure client payload builder. **Staging
  first.**
- **Dependencies:** Slice 0 baselines.
- **Entry criteria:** Slice 0 exit met.
- **Required controls (all mandatory):**
  - direct call to `public.save_reconciliation_with_commitments(...)` **then**
    `public.save_goal_funding_snapshots(...)`;
  - **one PostgREST RPC call / one PostgreSQL transaction**;
  - **no reproduced inner logic**; **no direct table writes**; **no swallowed exceptions**;
  - top-level `public.can_write_financials()` authorization (in addition to inner gates);
  - **exact server-derived nine-goal set** (not a client count);
  - **complete Week-5 opening-anchor guard** before any write;
  - **contiguous next-week sequencing** (exact next week; no skip/jump/past);
  - **`source` pinned to `reconciliation`** (rejects any client `source` field);
  - ordinary-path **monotonic non-decrease** (nearest-existing prior, §7.0);
  - **pre-call and post-call set/count assertions** (returned nine IDs/count == server set);
  - **exact-signature grant normalization**; **anonymous and unauthorized rejection**.
- **Repository touchpoints:** **[PROPOSED]** `docs/phase-5g-1d-migration.sql` (wrapper),
  `docs/phase-5g-1d-validation.sql`, `docs/phase-5g-1d-preflight.sql`; **[CURRENT]** the two
  deployed RPCs (called, not edited); client builder in `index.html` (payload only).
- **Allowed files:** **[PROPOSED]** `docs/phase-5g-1d-*.sql`; `index.html` (pure payload
  builder only); `test_regression.js`.
- **Prohibited files/contracts:** deployed reconciliation RPC body/signature; deployed E1
  RPC/table/RLS; the cleared artifacts; `runModel` internals; golden-master outputs.
- **Database objects involved:** **[PROPOSED]** wrapper function; **[CURRENT]** both deployed
  RPCs, `weekly_reconciliations`, `goal_registry`, `goal_funding_snapshots`.
- **Application functions/modules:** **[PROPOSED]** client payload builder (pure); wired into
  the `saveRecon` path only in Slice 3.
- **Required tests (from plan §8 "Wrapper structure & atomicity", "Opening-anchor guard",
  "Eligible-set / count integrity", "Sequence", "Source & monotonicity"):** wrapper calls
  (not inlines) the RPCs; snapshot failure aborts reconciliation; reconciliation failure
  writes no snapshot; exception propagation not swallowed; missing/incomplete/wrong-week/
  wrong-source anchor → raise; exact-set mismatch/missing/extra/duplicate/count mismatch/
  returned-ID mismatch → rollback; Week-6 first closeout; sequential next-week;
  skip/future/past rejection; monotonic-decrease rejection; source-injection rejection;
  source pinning.
- **Failure-injection tests:** forced reconciliation failure; forced snapshot failure;
  post-call assertion failure — each asserts **neither half persists**.
- **Security/grant checks:** exact-signature `REVOKE ALL … FROM PUBLIC, anon,
  authenticated` then `GRANT EXECUTE … TO authenticated`; anon/unauth rejection proven;
  inner-RPC gates intact.
- **Required evidence:** staging migration/validation output; contract-unchanged proof for
  both deployed RPCs; exact wrapper grant set.
- **Exit criteria:** staging wrapper green on all the above; both deployed contracts
  byte-unchanged.
- **Hard stop conditions:** any reproduced inner logic; any direct table write; any
  swallowed exception; a client count trusted as integrity control; contract drift.
- **Fable-style review checklist:** ☐ direct calls only ☐ one txn ☐ no swallow ☐ server nine-set ☐ anchor guard ☐ sequencing ☐ source pinned ☐ monotonic ☐ exact grants ☐ anon/unauth reject.
- **Does NOT authorize:** browser activation; reopen/correction modes (Slice 2); any grant
  revocation on the old RPC (Slice 7).

---

### Slice 2 — Retry, reopen & correction controls (+ Option B)

- **Objective:** the exceptional-operation controls layered on the wrapper, and Option B.
  *(Absorbs the two binding criteria — strict `p_mode` validation and complete retry
  identity — explicitly.)*
- **Exact scope:** `p_mode` validation; complete retry identity; `approved_reopen`; Option
  B correction wrapper; `repair_commitments_for_week` caller/dependency audit +
  posture-decision prep.
- **Dependencies:** Slice 1 wrapper. *(Maps plan §5.8/§2.3.1 + plan Slice 2.)*
- **Strict `p_mode` validation:** only `normal_closeout` and `approved_reopen` accepted;
  **NULL, misspelled, unknown, or additional values raise before either inner RPC
  executes**; **no permissive default**.
- **Complete retry identity:** equality across reconciliation actuals, commitments, other
  persisted fields, target week, the nine IDs, and the nine funded amounts; **both halves
  re-read before any automatic retry**; a changed value is **not** an idempotent retry
  (route to reopen/correction).
- **`approved_reopen`:** latest completed week only; **DB-enforced `public.is_owner()`**;
  Wendy rejection; ordinary UI cannot invoke (`p_mode` restricted); snapshots resubmitted
  **unchanged** with `source='reconciliation'`; atomic failure (both calls roll back).
- **Option B owner-only correction wrapper (D2):** **[PROPOSED]**
  `public.correct_goal_funding_snapshot(...)` — `SECURITY DEFINER`; exact `authenticated`
  EXECUTE for routing; **internal `public.is_owner()` gate**; **target row must already
  exist**; **nearest-existing lower and higher bounds** (§7.0); **call-through to
  `public.save_goal_funding_snapshots(...)`**; one post-anchor `source='correction'` row;
  **no anchor amendments**; **no direct table writes**; **Option A retires** for
  post-anchor corrections when Option B deploys (D1).
- **`repair_commitments_for_week`:** conduct the **caller/dependency audit**; prepare the
  **Gate C activation-posture decision**; **do not alter grants yet** unless separately
  approved.
- **Repository touchpoints:** **[PROPOSED]** wrapper mode logic + Option B function in
  `docs/phase-5g-1d-migration.sql`; **[CURRENT]** `is_owner()`
  (`docs/phase-5a-role-enforcement.sql:64`), deployed snapshot RPC (called by Option B),
  `repair_commitments_for_week` (`docs/phase-5f-1-migration.sql:997`), client
  `isOwnerUser()` (`index.html:7786`, UI-only).
- **Allowed files:** **[PROPOSED]** `docs/phase-5g-1d-*.sql`; `test_regression.js`;
  `e2e.js`. **Prohibited:** deployed RPC bodies/signatures; cleared artifacts; grants on
  `repair_commitments_for_week` (audit only this slice).
- **Database objects involved:** **[PROPOSED]** wrapper (`approved_reopen`), Option B
  function; **[CURRENT]** deployed snapshot RPC, `is_owner()`, `goal_funding_snapshots`,
  `repair_commitments_for_week` (read/audit).
- **Application functions/modules:** none activated in the browser here (Slice 3 wires UI).
- **Required tests (correction spec §15 + plan §8 R1/R2 families):** strict `p_mode`
  reject (NULL/unknown/extra); complete retry identity across both halves; changed-value →
  route; `approved_reopen` owner success; Wendy reopen rejection; ordinary-UI cannot pass
  `p_mode`; reopen resubmits unchanged; older-week reopen rejection; direct old RPC stays
  revoked (asserted in Slice 7); Option B success; **Option B rejects a missing target
  row**; **Option B nearest-existing lower/higher bound violations rejected**; **Option B
  calls the deployed snapshot RPC (not a table write / not reproduced)**; correction
  in-place single row; `source` becomes `correction`; overlay resolves corrected value;
  next-week uses corrected effective prior; before/after evidence required; Option A
  retires post-B.
- **Failure-injection tests:** reopen failure rolls back both calls; correction post-call
  validation mismatch rolls back; concurrent correction serialized.
- **Security/grant checks:** Option B exact-signature grants (`authenticated` EXECUTE only,
  PUBLIC/anon none); in-body `is_owner()` rejects Wendy; no table-privilege broadening.
- **Required evidence:** caller/dependency audit of `repair_commitments_for_week` +
  drafted posture options for Gate C; Option B staging validation.
- **Exit criteria:** `p_mode`/retry/reopen/correction controls green on staging; Gate C
  audit complete and posture options drafted (decision itself is Adam's at Gate C).
- **Hard stop conditions:** permissive `p_mode` default; changed value accepted as retry;
  Wendy reaching reopen/correction; Option B backfilling a missing row; any grant change to
  `repair_commitments_for_week` without separate approval.
- **Fable-style review checklist:** ☐ strict p_mode ☐ full retry identity ☐ reopen owner-only ☐ Wendy rejected ☐ Option B row-exists ☐ nearest-existing bounds ☐ call-through ☐ no anchor amend ☐ repair audit done, grants untouched.
- **Does NOT authorize:** any `repair_commitments_for_week` grant change; anchor
  amendments via Option B; browser activation.

---

### Slice 3 — Browser closeout workflow

- **Objective:** wire the single wrapper call into the browser closeout with the confirmation
  view and the in-flight/ambiguous state machine. *(Maps plan Slice 3.)*
- **Exact scope:** `index.html` closeout path only — a **narrow** change, **no broad UI
  refactor.**
- **Dependencies:** Slice 1 wrapper (+ Slice 2 controls deployed inertly).
- **Exact repository touchpoints [CURRENT], verified this pass:**
  - existing reconciliation save function — `saveRecon(n)` (`index.html:2729`);
  - reload — `reloadReconAndCommitments()` (`index.html:2716`);
  - gates — `canPersistReconNow` (`:3740`) / `canSaveRecon` (`:3749`);
  - auth — `getAuthHeaders()` (`:7729`);
  - snapshot loader (`:7843`), `_latestGoalSnapshot` (`:4341`), C3 overlay (`:2571`),
    `getGoalFunded` (`:4349`) — **preserved unchanged** (read paths).
  - **[PROPOSED]** wrapper invocation point inside/next to `saveRecon`; the confirmation
    view; the closeout-complete predicate helper (Slice 4).
- **Confirmation view must show:** target week; reconciliation actuals + commitments; the
  exact nine goal IDs; prior and proposed funded values; unchanged values; the
  **joint-commit warning** (reconciliation + snapshots commit together).
- **Client state machine:** disable the action while in flight; **no premature
  reconciliation-success state**; **timeout treated as ambiguous** (not failed); **re-read
  both halves before retry**; route changed same-week values to reopen/correction; preserve
  current loader/overlay behavior.
- **Allowed files:** `index.html` (closeout path only); `test_regression.js`; `e2e.js`.
- **Prohibited files/contracts:** any deployed SQL; loader/overlay semantics; `runModel`
  internals; golden-master outputs; a **broad UI refactor** is explicitly disallowed.
- **Database objects involved:** none written from the browser except via the wrapper RPC.
- **Application functions/modules:** `saveRecon` (extended to call the wrapper), the
  confirmation view **[PROPOSED]**, the state machine **[PROPOSED]**.
- **Required tests (plan §8 client + correction spec §15 client rows):** in-flight disable /
  double-submit; no premature success; ambiguous-timeout re-read; changed same-week routing;
  loader/overlay unchanged; confirmation view contents.
- **Failure-injection tests:** dropped response (ambiguous) → re-read both halves; wrapper
  error surfaced from `message||hint||details`.
- **Security/grant checks:** real authenticated writer only; no anon path; no direct table
  write from the app.
- **Required evidence:** static + e2e green; golden-master identity for zero-snapshot runs.
- **Exit criteria:** browser closeout drives the wrapper; both states (reconciled vs fully
  closed) distinct; no loader/overlay regression.
- **Hard stop conditions:** premature reconciliation-success; a timeout treated as failed;
  changed value auto-retried; any broad UI refactor.
- **Fable-style review checklist:** ☐ single wrapper call ☐ confirmation contents complete ☐ in-flight disable ☐ ambiguous handling ☐ re-read both halves ☐ loader/overlay untouched ☐ narrow diff.
- **Does NOT authorize:** activation (Slice 7); grant revocation; reopen/correction UX
  buttons (reopen/correction stay supervised/manual).

---

### Slice 4 — Closeout-complete predicate & repair states

- **Objective:** the derived closeout-complete predicate and the explicit repair/anomaly
  state model. *(Maps plan Slice 0 read-only state + plan §2.5/§6.3.)*
- **Exact scope:** a read-only predicate + state rendering + the half-close repair rule; no
  new write path beyond the wrapper.
- **Dependencies:** Slice 1/3.
- **States to define:** **complete week** (reconciled ∧ nine-row snapshot set);
  **reconciliation-only half-close** (reconciled, no complete snapshot);
  **snapshots-without-reconciliation** (impossible/corrupt → hard stop); **exact retry**
  (idempotent); **changed-value state** (route to reopen/correction); **blocked future
  week** (prior incomplete); **one-week-at-a-time half-close repair**; **no advancement past
  an incomplete prior week**.
- **Repository touchpoints:** **[CURRENT]** `isWeekReconciled` (`index.html:1001`), the
  snapshot loader (`:7843`); **[PROPOSED]** closeout-complete predicate helper +
  distinct-state badge.
- **Allowed files:** `index.html` (predicate + rendering); `test_regression.js`; `e2e.js`.
  **Prohibited:** deployed SQL; loader/overlay semantics; `runModel`.
- **Map UI / domain / DB responsibilities:** UI renders the derived state; the domain
  predicate composes reconciled ∧ complete-nine-snapshot; the DB enforces the atomic write
  (so the two coincide except for legacy/half-closed weeks made visible here).
- **Required tests:** every state transition (complete; half-close; corrupt; exact retry;
  changed-value; blocked-future; half-close repair; no-advance-past-incomplete).
- **Failure-injection tests:** a reconciled-but-unsnapshotted week is repaired atomically by
  the fresh wrapper and the following week stays blocked until repaired (plan §6.3/§6.1).
- **Security/grant checks:** none new (read-only predicate + wrapper write).
- **Required evidence:** state-transition tests green; the distinct badge visible for a
  half-closed anomaly.
- **Exit criteria:** all states rendered and gated; no advancement past an incomplete prior
  week.
- **Hard stop conditions:** advancing past an incomplete prior week; auto-"repairing" a
  snapshots-without-reconciliation corrupt state.
- **Fable-style review checklist:** ☐ predicate correct ☐ all states covered ☐ half-close repair one-at-a-time ☐ no-advance rule ☐ corrupt state hard-stops.
- **Does NOT authorize:** any write outside the wrapper; activation.

---

### Slice 5 — Staging integration & failure injection

- **Objective:** the complete staging test program across all paths + failure modes. *(Maps
  plan Slice 5.)*
- **Exact scope:** staging-only integration; both smoke and full gates.
- **Dependencies:** Slices 1–4 on staging.
- **Complete staging test program:** success path; forced reconciliation failure; forced
  snapshot failure; post-call assertion failure; missing anchor; goal-set mismatch;
  duplicate goal; skipped week; past week; future jump; monotonic decrease; exact retry;
  changed retry; approved reopen; Wendy reopen rejection; Option B correction; missing
  correction target; nearest-existing bound violations; repair-RPC posture (audit assertion);
  anonymous and unauthorized callers; concurrent submissions; ambiguous network response;
  stale browser behavior.
- **Atomicity rule:** **for every forced database failure, assert neither half persists.**
- **Gate rule:** require **both smoke and full E2E gates**; **smoke does not replace full
  regression** (5G-QA-1: full is the release gate).
- **Repository touchpoints:** `e2e.js` (tagged tests, `opts.tags`), `test_regression.js`;
  **[PROPOSED]** `docs/phase-5g-1d-rls-smoke-*` for the real-caller matrix.
- **Allowed files:** `e2e.js`, `test_regression.js`, **[PROPOSED]** `docs/phase-5g-1d-*`.
  **Prohibited:** production SQL execution; deployed contracts; cleared artifacts.
- **Database objects involved:** staging copies of the wrapper + Option B + deployed RPCs.
- **Required/failure-injection tests:** the full list above (this slice *is* the failure
  program).
- **Security/grant checks:** anon/unauthorized/viewer/writer matrix; owner-only reopen +
  correction; exact grants.
- **Required evidence:** staging run logs (balance-free); atomicity assertions; smoke+full
  green.
- **Exit criteria:** entire program green on staging; every forced failure leaves no partial
  state.
- **Hard stop conditions:** any forced failure that persists a partial state; smoke used as
  a substitute for full regression.
- **Fable-style review checklist:** ☐ all paths run ☐ every forced failure atomic ☐ Wendy rejected ☐ Option B bounds ☐ concurrency ☐ ambiguous handled ☐ smoke+full both green.
- **Does NOT authorize:** any production deployment or activation.

---

### Slice 6 — Production inert deployment

- **Objective:** deploy the wrapper + Option B to production **inertly** (nothing calls
  them yet). *(Maps plan Slice 6 first half.)*
- **Exact scope:** DB deploy + grant normalization + validation; **no browser activation.**
- **Dependencies:** Slice 5 fully green; Gate A closed if any `is_owner()` path ships.
- **Inert deployment sequence:** preflight → backup/evidence → wrapper deployment → Option B
  deployment → grant normalization → **exact-signature validation** → **no browser
  activation** → existing browser remains on the old flow → inert browser + network checks →
  **byte-unchanged validation for E1 and the reconciliation RPCs** → **separate rollback
  approval**.
- **Repository touchpoints:** **[PROPOSED]** `docs/phase-5g-1d-preflight.sql`,
  `-migration.sql`, `-validation.sql`, `-rollback.sql`; **[CURRENT]** deployed RPCs (proven
  byte-unchanged, not edited).
- **Allowed files:** **[PROPOSED]** `docs/phase-5g-1d-*.sql` (authored; **no executable
  production SQL is included in this readiness document** — contract/sequence only).
  **Prohibited:** editing deployed RPC bodies; browser activation; grant revocation on the
  old RPC (Slice 7).
- **Database objects involved:** **[PROPOSED]** wrapper + Option B (created inert);
  **[CURRENT]** E1 RPC/table + reconciliation RPC (unchanged).
- **Required tests:** production inert checks (loader quiet; no rendered change); exact
  wrapper/Option B grants; E1 + reconciliation RPC definitions byte-unchanged.
- **Failure-injection tests:** rollback rehearsal on staging (break-glass; separate
  approval) — not run in production here.
- **Security/grant checks:** exact-signature grants for wrapper + Option B; anon/unauth
  none; no table-privilege broadening; old reconciliation RPC grant **still present**
  (revocation is Slice 7).
- **Required evidence:** preflight output; backup/restore-point metadata (local-only, E2
  model); validation output; byte-unchanged proofs.
- **Exit criteria:** wrapper + Option B live but inert; contracts unchanged; rollback
  prepared + separately approved.
- **Hard stop conditions:** any rendered/behavioral change at this step; any deployed
  contract drift; executing production SQL from this readiness doc.
- **Fable-style review checklist:** ☐ inert (no activation) ☐ exact grants ☐ E1+recon byte-unchanged ☐ backup captured ☐ rollback separately approved ☐ old-RPC grant intact.
- **Does NOT authorize:** activation; grant revocation; browser deployment sign-off.

---

### Slice 7 — Browser deployment, activation & first live closeout

- **Objective:** ship the browser, activate the combined closeout, revoke the old direct
  path, and run the first supervised live closeout. *(Maps plan Slice 6 second half +
  activation gate + plan Slice 7.)*
- **Exact scope:** each step is **separate and separately approved.**
- **Separated steps:** browser deployment → browser verification → **activation approval** →
  **old reconciliation RPC direct `authenticated` EXECUTE revocation** (exact signature) →
  **`repair_commitments_for_week` posture action** (per Gate C) → stale-browser verification
  → fresh-browser verification → **first supervised live closeout** (Week-6) → evidence +
  closeout.
- **Hard gates before activation:** Option B deployed (unless a **documented dated Adam
  deferral** exists, Gate B); **Gate A `is_owner()` verification closed**; **Gate C
  repair-RPC posture decided**; **Gate D activation timing decided**; **staging fully
  green**; **rollback separately approved and prepared**; **no Alaska-freeze violation**.
- **Repository touchpoints:** **[CURRENT]** `saveRecon` path (now calling the wrapper); old
  reconciliation RPC grant (`docs/phase-5f-1-migration.sql:964`) revoked by exact signature;
  `repair_commitments_for_week` grant (`:1338`) actioned per Gate C.
- **Allowed files:** `index.html` (deploy the Slice-3 client); **[PROPOSED]**
  `docs/phase-5g-1d-*.sql` for the grant revocation (exact signature). **Prohibited:** any
  edit to deployed RPC bodies (revocation is a grant change, not a body edit).
- **Database objects involved:** grant change on `save_reconciliation_with_commitments`
  (exact signature) and on `repair_commitments_for_week` (per Gate C).
- **Application functions/modules:** the Slice-3 closeout client; stale-browser path fails
  before reconciliation persistence after revocation.
- **Required tests (plan §8 activation/auth):** stale browser before activation; stale
  browser after revocation (fails before reconciliation); fresh browser after activation;
  anonymous caller; authenticated-but-unauthorized caller; exact wrapper grants; old
  reconciliation RPC direct grant before/after activation.
- **Failure-injection tests:** first live closeout supervised smoke — verify returned count,
  the nine rows via REST/console, and the live overlay before treating 5G-1D as active.
- **Security/grant checks:** exact-signature revocation; wrapper remains callable as definer
  owner; `repair_commitments_for_week` posture enforced.
- **Required evidence:** activation approval; revocation validation (before/after grant);
  Gate C posture action recorded; first-closeout evidence.
- **Exit criteria:** combined closeout active; stale browsers can no longer half-close;
  Week-6 supervised smoke passes with evidence.
- **Hard stop conditions:** activating with any hard gate open; revoking by bare function
  name (must be exact signature); an Alaska-freeze violation; a half-closed state after
  activation.
- **Fable-style review checklist:** ☐ Option B (or dated deferral) ☐ Gate A closed ☐ Gate C decided ☐ Gate D decided ☐ staging green ☐ rollback approved ☐ exact-signature revoke ☐ stale-browser fails ☐ first closeout evidenced ☐ no freeze violation.
- **Does NOT authorize:** any scope change to the eligible nine; any historical remediation;
  reuse of activation approval for a later week.

---

## 5. Consolidated touchpoint inventory (grounded this pass)

| Item | Current/Proposed | File | Function / object | Responsibility | Slice(s) | Do-not-touch constraint |
|---|---|---|---|---|---|---|
| Reconciliation save caller | CURRENT | `index.html:2729` | `saveRecon(n)` | drives reconciliation write | 0,3,7 | extend to call wrapper; no broad refactor |
| Reload after save | CURRENT | `index.html:2716` | `reloadReconAndCommitments()` | reload recon/commitments | 0,3 | read path; unchanged |
| Save gate | CURRENT | `index.html:3740`/`:3749` | `canPersistReconNow`/`canSaveRecon` | closeout gating | 0,3 | preserve semantics |
| Week-reconciled check | CURRENT | `index.html:1001` | `isWeekReconciled` | reconciled predicate | 0,4 | read path |
| Snapshot loader | CURRENT | `index.html:7843` | `goalSnapData` fetch | loads snapshots (source-blind) | 0,3,4 | preserve; source not fetched |
| Latest-snapshot resolver | CURRENT | `index.html:4341` | `_latestGoalSnapshot` | nearest ≤ wk snapshot | 0,3 | preserve |
| Goal-funded overlay | CURRENT | `index.html:2571` | C3 overlay block | overwrite `goalSaved` at anchor | 0,3 | preserve; frozen except approved overlay |
| Goal funded read | CURRENT | `index.html:4349` | `getGoalFunded` | funded read (snapshot/complete) | 0,3 | preserve |
| Goal completion | CURRENT | `index.html:3131` | `goalCompletion` build | completion/stays-complete | 0 | preserve |
| Auth headers | CURRENT | `index.html:7729` | `getAuthHeaders` | REST auth headers | 1,3 | reuse; no `Prefer` for RPC |
| Client owner flag | CURRENT | `index.html:7786` | `isOwnerUser()` | UI-only owner flag | 2 | **UI-only; not enforcement** |
| Client write flag | CURRENT | `index.html:7787` | `canWriteFinancials()` | UI-only write flag | 1 | UI-only |
| Deployed reconciliation RPC | CURRENT | `docs/phase-5f-1-migration.sql:454` (grant `:964`) | `save_reconciliation_with_commitments` | reconciliation write | 0,1,6,7 | **body/signature immutable**; grant revoked in Slice 7 only |
| Deployed snapshot RPC | CURRENT | `docs/phase-5g-1c-2-prod-migration.sql:160` (grant `:283`) | `save_goal_funding_snapshots` | snapshot write primitive | 0,1,2,6 | **immutable**; called, never edited |
| Snapshot table | CURRENT | `docs/phase-5g-1c-2-prod-migration.sql:120` | `goal_funding_snapshots` | anchored funded rows | 0,4 | immutable schema/RLS |
| Owner predicate | CURRENT | `docs/phase-5a-role-enforcement.sql:64` | `public.is_owner()` | owner-only gate | 2,7 | reused; not re-invented |
| Write predicate | CURRENT | `docs/phase-5a-role-enforcement.sql:43` | `public.can_write_financials()` | write gate | 1 | reused |
| Repair RPC | CURRENT | `docs/phase-5f-1-migration.sql:997` (grant `:1338`) | `repair_commitments_for_week` | historical repair (REST-callable, Wendy) | 2,7 | audit in Slice 2; grant actioned in Slice 7 per Gate C |
| E2E runner + smoke | CURRENT | `e2e.js` (`opts.tags:['smoke']`) | tag-based runner | test gate | 0,5 | full mode stays release gate |
| Grant SQL locations | CURRENT | `docs/phase-5f-1-migration.sql:964`/`:1338`, `docs/phase-5g-1c-2-prod-migration.sql:283`, `docs/phase-5a-role-enforcement.sql` | grants/policies | authorization | 1,2,6,7 | exact-signature ops only |
| Closeout wrapper | **PROPOSED** | `docs/phase-5g-1d-migration.sql` | `save_weekly_closeout_with_snapshots` | atomic combined closeout | 1,2,6,7 | direct-call only; no reimpl |
| Correction wrapper (Option B) | **PROPOSED** | `docs/phase-5g-1d-migration.sql` | `correct_goal_funding_snapshot` | owner-only in-place correction | 2,6 | call-through; is_owner(); no anchor amend |
| 5G-1D SQL package | **PROPOSED** | `docs/phase-5g-1d-preflight/validation/rollback/rls-smoke` | staging-first package | deploy/validate/rollback | 1,5,6,7 | staging first; no prod SQL in this doc |

*(Every CURRENT row above was verified against the working tree this pass.)*

---

## 6. Test-to-slice matrix

No load-bearing requirement remains only as an uncategorized cross-reference. "Level":
S=static (`test_regression.js`), E=e2e (`e2e.js`), DB=staging SQL smoke. "Atomicity" =
asserts neither half persists on failure. "Act-blocker" = a failing/absent proof blocks
activation.

| Test case | Slice introduced | Level | Expected result | Atomicity | Act-blocker |
|---|---|---|---|---|---|
| Wrapper calls (not inlines) both RPCs | 1 | S/DB | pass | – | Y |
| Snapshot failure aborts reconciliation | 1 | DB | neither persists | Y | Y |
| Reconciliation failure writes no snapshot | 1 | DB | neither persists | Y | Y |
| Exception not swallowed (re-raise only) | 1 | DB | raise propagates | Y | Y |
| Opening-anchor missing/incomplete/wrong week/source | 1 | DB | raise, no write | Y | Y |
| Exact nine-set: missing/extra/dup/count/returned-ID | 1 | DB | reject+rollback | Y | Y |
| Sequence: next-week; skip/future/past reject | 1 | DB | pass/reject | Y | Y |
| Source pinned `reconciliation`; injection reject | 1 | DB | pass/reject | Y | Y |
| Monotonic decrease reject (nearest-existing prior) | 1 | DB | reject | Y | Y |
| Exact wrapper grants; anon/unauth reject | 1 | DB | pass | – | Y |
| Strict `p_mode` (NULL/unknown/extra) reject pre-RPC | 2 | DB | raise pre-exec | Y | Y |
| Complete retry identity (both halves) | 2 | S/DB | idempotent only if identical | Y | Y |
| Changed-value → route to reopen/correction | 2 | S/DB | not a retry | Y | Y |
| `approved_reopen` owner success (latest week) | 2 | DB | atomic success | Y | Y |
| Wendy reopen rejection (`is_owner()`) | 2 | DB | reject | – | Y |
| Ordinary UI cannot pass `p_mode` | 2 | S/E | restricted | – | Y |
| Reopen resubmits nine unchanged, `source=reconciliation` | 2 | DB | idempotent | Y | Y |
| Older-week reopen rejection | 2 | DB | reject | – | Y |
| Option B: missing target row reject | 2 | DB | raise, no insert | Y | Y |
| Option B: nearest-existing lower/higher bound reject | 2 | DB | reject | Y | Y |
| Option B: calls deployed RPC (no table write/reimpl) | 2 | DB | pass | – | Y |
| Correction in-place single row; `source=correction` | 2 | DB | one row | Y | Y |
| Overlay resolves corrected value (source-blind) | 2/3 | E | corrected shown | – | N |
| Next-week uses corrected effective prior | 2 | DB | pass | – | N |
| Before/after correction evidence required | 2 | S | required | – | N |
| Option A retires post-Option-B | 2 | S | disabled | – | N |
| In-flight disable / double-submit | 3 | E | disabled | – | N |
| No premature reconciliation-success | 3 | E | pass | – | Y |
| Ambiguous timeout → re-read both halves | 3 | E | ambiguous handling | Y | Y |
| Loader/overlay unchanged (golden identity) | 3/0 | S | byte-identical | – | Y |
| State transitions (complete/half-close/corrupt/…) | 4 | S/E | correct | Y | Y |
| Half-close repair one-at-a-time; no advance | 4 | DB/E | blocked until repaired | Y | Y |
| Full staging failure-injection program | 5 | DB/E | neither half persists | Y | Y |
| Concurrent submissions; ambiguous response | 5 | DB/E | serialized/handled | Y | Y |
| Stale browser before/after revocation | 5/7 | E | fails before recon after revoke | Y | Y |
| Anonymous / unauthorized callers | 5/7 | DB | reject | – | Y |
| Production inert checks (no rendered change) | 6 | E | inert | – | Y |
| E1 + reconciliation RPC **byte-unchanged** | 0/1/6 | DB | unchanged | – | Y |
| Exact-signature old-RPC grant before/after activation | 7 | DB | revoked after | – | Y |
| `repair_commitments_for_week` posture validated | 2/7 | DB | posture enforced | – | Y |
| First supervised Week-6 live closeout smoke | 7 | E | 9 rows, overlay agrees | – | Y |
| 5G-QA-1 smoke gate green | 0/5 | E | green | – | N |
| 5G-QA-1 full gate green (release gate) | 0/5 | E | green | – | Y |

---

## 7. Activation decision card (Gate D expanded)

An explicit Adam decision is required **before implementation sequencing is finalized**.
**Do not silently choose an option.**

### Option 1 — pre-freeze activation
- Implementation, staging, inert deployment, browser deployment, activation, and the first
  live closeout **must all fit before the Alaska freeze (starts Jul 24).**
- Include: **testing/deployment compression risk**; **absence of Fable during
  implementation** (this package substitutes for per-slice review, raising the bar on it);
  **rollback readiness**; **effect on Week-6 closeout timing**; and the **latest safe
  go/no-go date** (the last date by which activation + first closeout can complete with full
  controls before Jul 24).

### Option 2 — post-freeze activation
- Ordinary reconciliations **continue without automated snapshots** during the gap.
- **Identify each reconciled-but-unsnapshotted week** that accrues.
- Plan **§6.3 repairs one week at a time**; plan **§6.1 blocks progression past an
  incomplete prior week**.
- **Define the exact repair sequence** (which gap week is snapshotted first, in order)
  before normal automated closeout resumes.
- Include **evidence and supervision requirements** for each gap-week repair.
- **Quantify the likely number of gap weeks** from the calendar: E2 anchors Week 5
  (Cal Wk 27); the freeze is Jul 24–Aug 10; resuming automated closeout after Aug 10 leaves
  roughly the **Week-6 through Week-8/9 closeouts (~3–4 weeks)** as reconciled-but-
  unsnapshotted gap weeks to repair in sequence — **confirm the exact count against the
  live reconciliation calendar at decision time.**

### Binding statements
- **No 5G merge is allowed during the Alaska freeze under either option.**
- **An explicit timing decision does not override the freeze.**
- **Adam must approve one option before implementation sequencing is finalized.**
- **If the pre-freeze path becomes unsafe or misses its go/no-go date, DEFAULT to
  post-freeze rather than compressing controls.**

---

## 8. Status-document handoff contents (applied only after clearance)

When this readiness package is reviewed and cleared, a **docs-only** update must add to
`CODEX_STATUS.md` and the applicable `docs/phase-status.md` section:

- the **D1–D3 approved decisions**;
- **Gate 0 and Gates A–E** with their **trigger points** and **current status**;
- the **readiness-package path** (`docs/phase-5g-1d-implementation-readiness-2026-07-10.md`),
  its **commit hash and SHA-256**;
- the **correction-spec path** and its **cleared hash** (`f005263`);
- an explicit statement that **no implementation is authorized**;
- an explicit statement that **E2 completion and per-gate approvals remain required**;
- **no household financial values.**

**Do not edit the status documents in this revision.**

---

## 9. Non-blocking clarifications resolved

- **Cleared-plan checklist citation:** the authoritative slice sequence is the cleared
  5G-1D plan **§10 item 6** (Deliverables → Execution checklist). Cited correctly
  throughout (§4.0).
- **Gate A early de-risking:** the read-only `is_owner()` preflight **may be run before
  Slice-2 coding** as early de-risking; **staging acceptance remains the hard trigger**
  (§2 Gate A).
- **Correction-spec §19 item 3 (sequencing):** **satisfied by this readiness artifact** —
  the correction/remediation procedure is folded into the 5G-1D readiness package as an
  acceptance-criteria + slice layer, rather than finalized as a standalone pre-implementation
  document.
- **Reopen scope:** **latest-completed-week-only reopen is recorded as a settled design
  confirmation** (correction spec §3/§19 item 4); older weeks route to historical
  remediation (Gate E).
- **"§15 tests":** every such reference means the **correction companion spec §15** matrix
  (qualified throughout).

---

## 10. Artifact hierarchy & scope boundary (§17)

This package remains **subordinate** to, in order: (1) the E2 runbook, (2) the cleared
5G-1D plan, (3) the cleared correction/reopen/remediation companion spec. It **may
consolidate and operationalize** their requirements (as done in §4–§8); it **may not
override** them. **If consolidation uncovers a contradiction in a cleared artifact, stop
and report it rather than resolving it silently** — none was found this pass; the only
divergence (slice re-grouping vs plan §10.6) is flagged transparently in §4.0 and changes
no plan contract.

This package **must not**: rewrite the cleared slice sequence's contracts, alter the
cleared wrapper modes (`normal_closeout` / `approved_reopen`), modify the Week-5 anchor
contract, edit any cleared artifact, or authorize SQL, Supabase access, grant changes, E2
execution, or 5G-1D implementation.

---

*Plan-only. No code, SQL, schema, RPC, RLS, migration, seed, grant change, or test written
or run this pass. Subordinate to the cleared E2 runbook, 5G-1D plan, and correction
companion spec, all unchanged. Every gate above is an explicit Adam decision at its trigger
point; no approval is inferred from another. E2 completion (Gate 0) is blocking. Nothing
here authorizes implementation or any production action.*
