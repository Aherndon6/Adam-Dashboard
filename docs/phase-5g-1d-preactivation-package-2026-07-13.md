# Phase 5G-1D — Pre-Activation Implementation Package (Slices 3–6, Gates B/C/D/E disposition prep)

**Status:** PLAN-ONLY / PROPOSED — NOT REVIEWED, NOT APPROVED, NOT IMPLEMENTED. No code, SQL,
schema, RPC, RLS, migration, seed, grant change, deployment, activation, or production action is
performed or authorized by this document.
**Date:** 2026-07-13
**Author:** Claude (session under Adam)
**Objective:** the implementation package needed to finish all remaining **pre-activation** 5G-1D
work. This package ends at **"Ready for Gate B production activation"** and stops there. It does
**not** perform production activation, change production grants, enable production behavior,
perform supervised closeout, execute Gate B, execute SQL against production, modify E1, or rerun E2.

> **UPDATE (2026-07-13, post-implementation):** The browser work this package planned is **DONE** —
> Slices 3/4/5 complete; local full E2E **142/0**, readiness fallbacks **0/0**; static **1486/0**
> (branch-held on `claude/herndon-5g-1d-preactivation-j428vn`, not merged). **⟶ SUPERSEDED
> 2026-07-13 by the independent pre-production corrections + final review: Adam-verified at commit
> `114b080` — static 1507/0, full `node e2e.js` 148/0/0, fallbacks 0/0; see
> `docs/phase-5g-1d-independent-preproduction-review-closeout-2026-07-13.md`.** **Gate D is DECIDED:
> Option A (pre-freeze), Adam-approved 2026-07-13.** The Gate C brief (§3), **the Gate D timing
> decision card (§4) — Gate D is DECIDED, so its "both options / not chosen here" framing is
> superseded** — the Slice 6 checklist (§5), and the execution plan (§7) below are **superseded for
> execution** by the finalized packages:
> `docs/phase-5g-1d-gatec-register-2026-07-13.md` (Gate C register + grant SQL),
> `docs/phase-5g-1d-slice6-deploy-runbook-2026-07-13.md` (Slice 6), and
> `docs/phase-5g-1d-gateb-activation-runbook-2026-07-13.md` (Gate B). This document is retained as
> the pre-activation analysis of record. **Still nothing executed:** Gate C decisions, Slice 6
> deploy, and Gate B activation all remain unauthorized.

**Subordinate to (all cleared; none edited by this document):**
1. `docs/phase-5g-1c-2-e2-runbook.md` (`c439d68`) — E2 first-anchor seed gate (E2 is COMPLETE).
2. `docs/phase-5g-1d-plan-2026-07-09.md` (`6de4614`) — cleared write-through plan.
3. `docs/phase-5g-1d-snapshot-correction-procedure-2026-07-10.md` (`f005263`) — correction /
   reopen / remediation companion spec.
4. `docs/phase-5g-1d-implementation-readiness-2026-07-10.md` (`a55d899`) — implementation-readiness
   package (slice numbering 0–7 used throughout this document).
5. The three companion amendments — `docs/phase-5g-1d-amendment-2026-07-11.md` (`0c10784`),
   `docs/phase-5g-1d-amendment-2-2026-07-11.md`, `docs/phase-5g-1d-amendment-3-2026-07-11.md` —
   which **control for implementation where stricter** than the cleared artifacts.
6. `docs/phase-5g-1d-slice2-proposed-2026-07-11.md` (Rev 8) — the Slice-2 implementation spec the
   committed SQL package encodes.

**Roadmap context (advisory):** `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md` (P0
"complete 5G-1D"; C9/§11 D4 Gate D) and
`docs/post-5g-1d-roadmap-amendment-calc-core-extraction-2026-07-13.md` (extraction defers closeout
builders until 5G-1D is complete — §3.7).

**Privacy:** balance-free. No household balances, custodian figures, or per-goal E2 values appear
here. The only dollar figures cited (`wewe_rccl` 600 / `wewe_dcl` 500 targets; synthetic staging
fixture values 100–900) are already committed in `CODEX_STATUS.md` / the Gate-2 package and are
targets/synthetic fixtures, not household balances.

**Proposed-vs-current convention (per the readiness package):** every touchpoint is tagged
**[CURRENT]** (exists in the working tree now, grounded to file:line at HEAD `ea5a7c9`) or
**[PROPOSED]** (does not exist yet).

---

## 1. Current-state verification (grounded at HEAD `ea5a7c9`, 2026-07-13)

Verified against the working tree and git history. HEAD is four docs-only commits past `aff220c`
(the commit the `CODEX_STATUS.md` banner was verified at): `ed62978` (canonical roadmap adoption +
currency banners), `36c9020` (retained Fable reviews), `ca1efd3` (calc-core amendment), `ea5a7c9`
(5F-1.5 governance artifacts). None touched code or SQL.

### 1.1 Completed (with evidence)

| Item | Status | Evidence |
|---|---|---|
| E1 production DDL (`goal_funding_snapshots` + `save_goal_funding_snapshots`) | **COMPLETE (2026-07-09), immutable** | `CODEX_STATUS.md` "5G-1C-2 E1 COMPLETE"; runbook `docs/phase-5g-1c-2-e1-runbook.md` |
| E2 first-anchor production seed (nine `opening_anchor` rows, wk 5) | **COMPLETE + GREEN (2026-07-11)** | `docs/phase-5g-1c-2-e2-closeout-2026-07-11.md` |
| 5G-1C-2.1 post-anchor coherence hotfix (Leg 1 code + Leg 2 two wk-5 `correction` rows) | **COMPLETE (2026-07-11)** — production wk-5 = 11 rows (9 anchor + 2 correction) | `CODEX_STATUS.md` "5G-1C-2.1 COMPLETE"; `docs/phase-5g-1c-2.1-hotfix.md` |
| **Gate 0** (E2 completion) | **CLOSED (2026-07-11)** | E2 closeout doc; readiness §2 Gate 0 evidence list satisfied |
| **Gate A** (`is_owner()` identity) | **CLOSED (2026-07-11)** | `docs/phase-5g-1d-slice2-proposed-2026-07-11.md` §0 |
| Decisions **D1–D3** (Option A bridge / Option B in Slice 2 / anchor keeps `opening_anchor`) | **APPROVED (2026-07-10)** | readiness §1 |
| **Slice 0** (baseline & E2-dependency verification) | **Substantively satisfied** — grounding facts verified at `ff80971` (Gate-2 runbook §0); golden-master identity gate captured (`e0be9dc`, `fixtures/runmodel-golden-pre-1c-2.json`); QA-1 smoke+full green. The **production** RPC md5 byte-baselines are captured by the Slice-6 preflight at execution time (`docs/phase-5g-1d-preflight.sql`), so the byte-unchanged proof recurs there. | Gate-2 runbook §0; `docs/phase-5g-1d-preflight.sql` |
| **Slice 1** — client payload builder (plan §10.6 numbering) | **SHIPPED INERT** (`57bc9c1`): `SNAPSHOT_ELIGIBLE_GOAL_IDS` `index.html:2839`, `buildCloseoutSnapshotRows` `index.html:2857` — **zero call sites**; 17 static tests `5G1D-01…17` (`test_regression.js:12213`) | verified this pass |
| **Slice 1** — core orchestration RPC (readiness numbering): `save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)` | **STAGING-ACCEPTED (2026-07-13)** | `docs/phase-5g-1d-migration.sql:66`; Gate-2 matrix (below) |
| **Slice 2** — Option B `correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)` + reopen/retry/GFA01 controls | **STAGING-ACCEPTED (2026-07-13)** — full real-caller matrix **G2-1…G2-20b PASSED** on staging `pkwotgqivgaapwuqgwqb`; teardown/restore/ungrant/validation passed; both functions returned to inert (anon/authenticated EXECUTE = none); production untouched | `CODEX_STATUS.md` "5G-1D SLICE 2 … GATE 2 STAGING EXECUTION COMPLETE"; `docs/phase-5g-1d-gate2-runbook.md` §4 |
| Slice-2 SQL package committed (preflight / migration / validation / rollback / staging-grant / ungrant + fixtures) | **COMMITTED** (`17b8d1f`…`ff80971`, `5cb8039`) | `docs/phase-5g-1d-*.sql`, `docs/phase-5g-1d-gate2-*` |
| Test baselines at HEAD | **Static 1460/0 (run this pass, 2026-07-13).** E2E full last verified **135/0** at `db2704f`; e2e must be re-verified by Adam from Terminal (sandbox constraint, `AGENTS.md` Session Constraints) | this pass |

### 1.2 Remaining inside 5G-1D (corrected register)

Using the readiness package's slice numbering (its §4.0 re-groups plan §10.6 — see the stale-assumption
corrections below):

| Item | Status | Notes |
|---|---|---|
| **Slice 3 — browser closeout workflow** (wrapper wiring + confirmation view + in-flight/ambiguous state machine) | **NOT STARTED** | only the inert Slice-1 builder + a comment marker exist (`index.html:2830`) |
| **Slice 4 — closeout-complete predicate & repair states** | **NOT STARTED** | joint Slice-3/Slice-4 UI gate before Slice 5 |
| **Slice 5 — staging integration & failure injection** | **DB-level program ALREADY EXECUTED** by the Gate-2 matrix (all wrapper/Option-B paths, forced-failure atomicity, monotonicity, half-close repairs, blocked-advance, anon/unauth — G2-1…G2-20b). **Browser-level residue remains OPEN:** in-flight disable / double-submit, ambiguous-timeout re-read, changed-value routing, loader/overlay identity, state-transition e2e, stale-browser behavior — these require Slices 3/4 to exist first. | Gate-2 runbook §4; readiness §4 Slice 5 |
| **Slice 6 — production inert deployment** | **NOT STARTED** — SQL package is authored, committed, and production-ready (§5 below) | `docs/phase-5g-1d-migration.sql` (env-guarded) |
| **Gate B** — Option B activation gate | **OPEN** — technical precondition (Option B deployed + validated) is met on staging and will be met in production by Slice 6; the gate itself closes only with the activation approval | readiness §2 |
| **Gate C** — write-surface posture | **OPEN** — caller/dependency audit complete (§3 below); posture register drafted (amendment §G); **decision is Adam's** | amendment 1 §G |
| **Gate D** — activation timing | **OPEN — Adam decision** (§4 below) | readiness §7; synthesis C9 |
| **Gate E** — historical multi-week remediation | **OPEN-WHEN-TRIGGERED; never triggered** (§6 below) | readiness §2 Gate E |
| Gate B execution + **Slice 7** (browser deploy, activation grants, old-RPC revocation, Gate-C posture actions, Week-6 supervised smoke) | **OUT OF SCOPE for this package** — begins only after "Ready for Gate B production activation" and its own approvals | readiness §4 Slice 7 |

### 1.3 Blockers

- **No technical blocker** for Slice 3/4 start other than **its own explicit Adam implementation
  approval** (standing rule: no approval inferred; the Gate-2 record explicitly authorizes no
  browser work).
- **Gate D (activation timing) must be decided before implementation sequencing is finalized**
  (readiness §2 Gate D trigger). Slice-3 build content is identical under both options; the
  **merge/deploy sequencing and the test window are not** (§4, §7).
- Calendar: **Alaska freeze Jul 24 – Aug 10 (no 5G merges)** begins in 11 days.

### 1.4 Stale assumptions corrected (repository evidence)

1. **"Remaining work = Slice 3, Gate C, Gate D, Slice 6, Gate E" is incomplete.** The readiness
   package's slice register also carries **Slice 4** (closeout-complete predicate & repair states)
   and **Slice 5** (staging integration). Slice 4 is real remaining browser work (the readiness
   package's joint Slice-3/Slice-4 UI exit gate). Slice 5's **DB-level** program was executed early
   and in full by the Gate-2 acceptance matrix; its **browser-level** residue remains. The
   `CODEX_STATUS.md` banner's shorthand ("Slice 3 … Slice 6 … Gate B … Slice 7") folds Slice 4 into
   "Slice 3 (browser closeout UI + state machine)" and Slice 5 into the Gate-2 record — workable
   shorthand, but this package tracks them explicitly so no exit criterion is dropped.
2. **"5G-1D implementation NOT STARTED" is stale wherever it still appears.** True in the dated
   2026-07-10/11 sections of `CODEX_STATUS.md` / `docs/phase-status.md` (marked historical by the
   2026-07-13 banners) and in the `docs/phase-status.md` 5G-1D table row (the top-of-file pointer
   note corrects it). Reality: Slices 0–2 done (staging-accepted), Slice-1 client builder shipped
   inert, browser work not started.
3. **Readiness-package touchpoint line numbers have drifted** (Slice-1 builder insertion + the
   5G-1B-rider fix `db2704f`). Verified current positions: `saveRecon(n)` `index.html:2740` (was
   :2729), old-RPC POST `:2769`, optimistic `reconData[n]` write `:2765`, `reloadReconAndCommitments`
   `:2727`, `canPersistReconNow`/`canSaveRecon` `:3933`/`:3942`, `isWeekReconciled` `:1004`,
   `getAuthHeaders` `:7976`, C3 overlay `:2582–2599`, IRA seed latch `:868`/`:2546`, snapshot loader `:8090`
   (in `loadAll`), `getGoalFunded`/`_latestGoalSnapshot` `:4547–4571`, `deleteRecon` `:2816`.
   Functions and contracts are unchanged; only line pins moved.
4. **Test-count citations are stale in several places:** `AGENTS.md` "Current State" (1332/130),
   `CODEX_STATUS.md` "Recent Verified State" (1374/133). Verified now: **static 1460/0 at HEAD**;
   e2e full last verified **135/0** at `db2704f` (no code change since `57bc9c1`; re-verify from
   Terminal before relying on it).
5. **The wrapper takes no `p_recorded_at`** (removed Rev 4; Companion Amendment 3) — the current
   `saveRecon` payload still sends it to the old RPC (`index.html:2774`); Slice 3 must not carry it
   over.
6. **Gate C has widened.** It began as the `repair_commitments_for_week` posture; amendment 1 §G
   expands it to an **11-surface write-posture register** (old recon RPC, repair RPC, direct
   snapshot RPC EXECUTE, table INSERT/UPDATE/DELETE grants, `deleteRecon` UI behavior, wrapper +
   Option B activation grants). A "Gate C = one function" framing is stale (§3).
7. **Quicken parallel-run language is superseded** everywhere it survives (e.g. `CODEX_STATUS.md`
   "Do Not Break: Existing Quicken parallel-run workflow") — the OS is the sole live system of
   record (Adam-confirmed 2026-07-13); banners in all three status docs already govern.
8. **Staging is not in a virgin state:** it retains the synthetic nine-row wk-5 `opening_anchor`
   fixture (values 100–900, `[STAGING-FIXTURE]`) and the two retained Adam/Wendy auth fixtures
   (cleanup separately approved, not done); both new functions exist there with **inert grants**.
   Browser-level staging testing (if approved) re-grants via `phase-5g-1d-staging-grant.sql` and
   must end with `-ungrant.sql` + validation (§2.7).

---

## 2. Slice 3 implementation plan (browser closeout workflow) — with Slice 4 and the Slice-5 browser residue

### 2.1 Implementation status

**Not started.** Verified this pass: the only executable-code reference to
`save_weekly_closeout_with_snapshots` outside `docs/` is a comment (`index.html:2830`);
`correct_goal_funding_snapshot` appears nowhere outside `docs/`; there is no confirmation view, no
closeout-specific state machine (only the generic `reconSaving`/`reconOpen` flags), no
closeout-complete predicate, and no e2e coverage of the closeout write path. The Slice-1 payload
builder is present, tested, and inert.

### 2.2 Authoritative requirements (consolidated; amendments control)

- Cleared plan §2.2 (confirmation view contents), §2.3/§2.3.1 (state machine + retry identity),
  §2.5 (reconciled vs fully-closed distinct), §2.6 (no write on load/calc/render/refresh), §3.1/§3.6
  (operator-confirmed values; never from projected `goalSaved`), §6 (sequence semantics).
- Readiness §4 Slice 3 (narrow diff; no broad UI refactor; loader/overlay preserved) and Slice 4
  (state model; half-close repair one-at-a-time; no advance past incomplete prior week).
- Amendment 1 §F (**controls**): remove the optimistic `reconData[n]` assignment from the wrapper
  flow; update local reconciled state only after successful server completion **and** reload;
  re-read snapshots immediately before rendering the confirmation view; **freeze the exact
  nine-row payload at confirmation render — display that frozen object and submit that exact same
  object; no re-derivation at click time**; disable duplicate submission in flight;
  completeness scoping (weeks 1–4 legacy, never flagged/repaired; week 5 anchor; weeks 6+ complete
  only when all nine eligible IDs exist, any source).
- Amendment 2: automatic idempotency is **empty-commitment-arrays only**; non-empty ambiguous
  resubmission returns `GFA01` / `REQUIRES_SUPERVISED_ADJUDICATION` — the client surfaces this as a
  supervised-adjudication instruction, never auto-resolves it.
- Amendment 3: no `p_recorded_at` in the POST body; a genuine reopen re-stamps `recorded_at`
  (owner-supervised path, not ordinary UI).

### 2.3 The deployed wrapper contract the client codes against ([CURRENT], staging-accepted)

**Call:** `POST /rest/v1/rpc/save_weekly_closeout_with_snapshots` with exactly:
`p_week_num, p_model_year (=PLAN_YEAR=2026), p_chk, p_sav, p_amx, p_tax, p_lc, p_balance_basis,
p_new_commitments (JSON array), p_patched (JSON array), p_snapshot_rows (exactly 9 rows of
{goal_id, funded_amount} — no `source` key), p_mode ('normal_closeout' from ordinary UI),
p_expected_count (9)`. Reuses `getAuthHeaders()` (`index.html:7976`; no `Prefer` header).

**Success responses (JSONB):**
- new closeout — `{ok:true, mode:'normal_closeout', week_num, snapshot_count:9}`
- identical idempotent retry — adds `idempotent:true`
- half-close repair — adds `repaired:true`
- (owner-only reopen adds `reopened:true` — not reachable from ordinary UI)

**Rejects the client must map (from `docs/phase-5g-1d-migration.sql`, verified verbatim in Gate 2):**
- `42501` — not authorized (`can_write_financials()`); reopen without owner
- `22023` — invalid `p_mode`
- `GFA01` + hint `REQUIRES_SUPERVISED_ADJUDICATION` — fully-closed week resubmitted with non-empty
  commitment arrays → **re-read + supervised adjudication**, never auto-retry
- domain phrases (verbatim): `not the next contiguous closeout week`, `already fully closed with
  different values`, `monotonic violation`, `opening anchor incomplete at week 5`,
  `corrupt state: snapshots without reconciliation`, `earlier post-anchor week incomplete — repair
  the earliest gap first`, `half-close repair requires empty commitment arrays`, `half-close
  repair: submitted reconciliation differs from persisted`, `week … is legacy pre-anchor…`,
  `week 5 is the opening anchor…`, input-validation raises (finiteness, arrays, nine-row shape).

**Server-side sequencing the client mirrors (never replaces):** the next new-closeout week is
`6 + (count of nine-complete post-anchor weeks)`; a half-close repair must target the **earliest**
incomplete post-anchor week, submit **balances equal to persisted**, **empty commitment arrays**,
and equal amounts for any already-present eligible rows.

### 2.4 Required browser/UI changes ([PROPOSED]; `index.html` closeout path only, narrow diff)

1. **Closeout-complete predicate helper (Slice 4, pure):** `closeoutState(n)` derived from
   `reconData` + `goalSnapData` + `SNAPSHOT_ELIGIBLE_GOAL_IDS` →
   `legacy_pre_anchor (n≤4) | anchor (n=5) | open | blocked_prior_incomplete | half_closed
   (reconciled ∧ <9 eligible ids) | complete (reconciled ∧ 9 eligible ids, any source) | corrupt
   (eligible snapshots ∧ no reconciliation → hard-stop badge, never auto-repaired)`.
   No loader change needed: `goalSnapData[week][goal_id]` already holds all rows for the model
   year (`index.html:8090`; source is deliberately not fetched — completeness ignores source per
   amendment §A).
2. **Distinct week states rendered (Slice 4):** "Reconciled" vs "Closed (anchored)" badges + a
   visible half-closed/corrupt anomaly state; weeks 1–5 keep today's rendering (legacy/anchor
   scoping per amendment §F).
3. **Confirmation view (Slice 3):** a pre-submit step inside the existing recon form flow showing —
   target week; the five balances + `balance_basis`; commitment operation summary (Phase 1/2/3
   counts from the already-built arrays); the exact nine goal IDs with **prior effective snapshot
   value** (from `goalSnapData`, latest week < target, any source), **proposed funded value**,
   unchanged markers; the **expected row count (exactly nine)**; and the **joint-commit warning**
   (reconciliation + snapshots commit together, one atomic closeout). The nine-row payload is
   built once via `buildCloseoutSnapshotRows` **when the view renders, frozen, displayed, and
   submitted as that exact object** (amendment §F).
4. **Wrapper wiring (Slice 3):** `saveRecon(n)` gains a confirmation stage and then POSTs the
   wrapper instead of `save_reconciliation_with_commitments` — same Phase-1/2/3 payload builders
   (`index.html:2757–2764`), **plus** `p_snapshot_rows`, `p_mode:'normal_closeout'`,
   `p_expected_count:9`, **minus** `p_recorded_at`. **Delete the optimistic `reconData[n]`
   assignment (`index.html:2765`)** — local state updates only after server success +
   `reloadReconAndCommitments()` + snapshot re-read.
5. **Client state machine (Slice 3):**
   `idle → confirm_open (frozen payload) → in_flight (action disabled; no premature success)
   → success (reload both halves; render Closed) | rejected (mapped error; staged answers retained)
   | adjudication_required (GFA01 → supervised instruction) | ambiguous (timeout / dropped
   response → re-read BOTH halves via reloadReconAndCommitments + snapshot refetch; identical
   persisted state or identical resubmission → offer idempotent retry; anything changed → route to
   supervised reopen/correction message)`. Timeout is **ambiguous, not failed**. The normal retry
   never updates changed values. **No reopen/correction buttons** — those paths remain supervised
   and outside ordinary UX (readiness Slice 3 "Does NOT authorize").
6. **Half-close repair variant (Slice 4 UI over wrapper branch G):** when `closeoutState(n) ===
   'half_closed'` (the post-freeze gap-week case under Gate D Option B, or an anomaly), the
   confirmation view renders in **repair mode**: balances shown read-only equal to persisted;
   commitment phases suppressed (arrays sent empty); nine values operator-confirmed with
   already-present rows pinned to their persisted amounts; earliest-gap-first ordering mirrored
   client-side. One week at a time; the next week stays blocked until repaired.
7. **Prefill of the nine proposed values — decision needed at slice review (Adam):**
   - **(a) Recommended:** prefill each goal with its **prior effective snapshot value** (latest
     `goalSnapData` week < target), operator confirms/edits each; render the current week's
     **executed-transfer completions** (via the shipped `resolveWeekTransfers` adapter /
     `weekly_tasks` `completed_amount`, `db2704f`) alongside as a **read-only reference** so the
     operator has the observed movements in view. Keeps plan §3.1 unambiguous (no value ever
     derived from projected `goalSaved`), zero new derivation logic, honest "operator-confirmed".
   - (b) Prefill prior + sum of that goal's checked executed-transfer `completed_amount`s.
     Closer to "one-click", but requires an `action_key`→goal mapping (incl. `goal_adam_ira_seed`
     → `adam_ira`) and inherits weekly-tasks identity edge cases — more logic in the trust path.
   - Never (c) prefill from `runModel` `goalSaved` — prohibited (plan §3.1).
8. **Preserved unchanged (hard constraints):** loader/overlay semantics (`goalSnapData` loader,
   C3 overlay `index.html:2582`, `getGoalFunded`, `_latestGoalSnapshot`, IRA seed latch), the
   Phase-1/2/3 commitment builders and their gates, `runModel` internals, golden-master outputs,
   the 5E-7 role matrix (no new role logic — `canWriteFinancials()` still gates the action), and
   `deleteRecon` behavior (its restriction is a Gate C decision, not a Slice-3 change — §3).

### 2.5 State-machine changes (summary of what exists → what changes)

Today: `reconOpen` / `reconSaving` / staged `_reconBasis`,`_reconPhase1Answers`,`_reconPhase2Answers`,
`_reconPhase3Items`; optimistic `reconData[n]` write before POST; success clears staging + narrow
reload; failure rolls back `reconData[n]`, keeps staging, shows `.recon-error` (conflict sub-branch
reloads). Slice 3 keeps the staging model and gates, **adds** `confirm_open / in_flight /
ambiguous / adjudication_required` states and the frozen-payload rule, **removes** the optimistic
write, and **re-targets** the POST at the wrapper. The existing error-body extraction
(`message||hint||details`, `index.html:2780`-region) is reused, extended with `code` mapping
(`42501` / `GFA01` / `22023` / domain phrases).

### 2.6 Interactions with existing workflows

- **Register / Budget:** none. The closeout writes only through the wrapper; no Register
  (`transactions`) or Budget write paths are touched; Budget identity math untouched (Do Not
  Touch). The Register CL/reconciliation default view is unaffected.
- **Reconciliation workflow:** Phase 0–4 flow, gates, and commitment builders unchanged; what
  changes is the final commit step (confirmation + one atomic wrapper call) and post-success state
  handling. `weekly_tasks` transfer check-off flow unchanged (optionally read for the prefill
  reference display, §2.4.7a).
- **C3 overlay / Funding Plan:** unchanged; after a successful closeout the reloaded
  `goalSnapData` anchors the new week exactly as E2/2.1 rows do today.
- **`deleteRecon` (`index.html:2816`):** today it can DELETE any week's `weekly_reconciliations`
  row via the UI — deleting an anchored (snapshotted) week would fabricate the corrupt
  "snapshots-without-reconciliation" state client-side on next save attempt (wrapper hard-stops).
  Restriction is Gate C rows 8/9 (§3); Slice 3/4 should at minimum render the corrupt state
  distinctly (already in §2.4.1–2) and MAY add a client-side guard against deleting `complete`
  weeks — flagged as a Gate-C-adjacent slice-review decision, default: client guard in Slice 4
  (display-layer only, no grant change).

### 2.7 Required tests

**Static (`test_regression.js`; new section 5G-1D Slice 3/4):**
- wrapper wiring: `saveRecon` posts the wrapper with the 13-key payload, no `p_recorded_at`, no
  `source` keys, `p_expected_count:9`, `p_mode:'normal_closeout'` (source-shape test — the wiring
  IS the contract; reason documented per the calc-core amendment §4 test posture);
- optimistic-write removal (no `reconData[n]` assignment before the POST);
- frozen-payload identity (rendered object === submitted object; no click-time re-derivation);
- `closeoutState(n)` truth table (all seven states incl. weeks 1–4/5 scoping);
- repair-mode payload (empty arrays; persisted-equal balances; present-row pinning);
- error-code mapping (42501/GFA01/22023/domain phrases → distinct UX states);
- **update the `5F1-RPC-BRIDGE` family** (`test_regression.js:10528`-region): re-point the
  saveRecon-wiring assertions at the wrapper (the old-RPC SQL-source assertions against
  `docs/phase-5f-1-migration.sql` stay — the deployed function is unchanged);
- golden-master zero-snapshot identity stays green (Slice-0 gate re-asserted).

**E2E (`e2e.js`, tag-based per 5G-QA-1; mocked wrapper responses per the WR-8 mocked-write
precedent):** confirmation-view contents (nine IDs, priors, count, joint warning); in-flight
disable / double-submit; no premature success; ambiguous timeout → re-read both halves → identical
→ idempotent retry offered; changed-value → supervised routing message; GFA01 → adjudication
state; half-close repair variant; loader/overlay unchanged; the two existing C3 e2e tests stay
green. Full mode remains the release gate (no smoke substitution).

**Supervised staging browser smoke (optional but recommended before Slice 6; requires separate
Adam approval + staging credentials):** one real Auth→JWT→PostgREST browser closeout on staging
against the synthetic fixture — staging-grant → wk-6 browser closeout + one ambiguous-retry probe +
one half-close repair → teardown to the fixture baseline → **ungrant → validation** (same
discipline as Gate 2; `docs/phase-5g-1d-staging-grant.sql` / `-ungrant.sql` / fixture packages are
already committed). This is the honest browser-level completion of readiness Slice 5; the
alternative (accept Gate-2 REST-level evidence + mocked e2e as sufficient) is an Adam call —
flagged, not decided here.

### 2.8 Implementation order (within Slice 3/4)

1. `closeoutState(n)` predicate + static truth-table tests (pure, inert — no rendering yet).
2. Week-state rendering (badges + anomaly states) + static/e2e render tests.
3. Confirmation view (frozen payload; prefill option per Adam's §2.4.7 choice) + tests.
4. Wrapper wiring + optimistic-write removal + error mapping + `5F1-RPC-BRIDGE` re-point + tests.
5. Ambiguous/retry/adjudication state machine + tests.
6. Half-close repair variant + tests.
7. Full static + full e2e green; golden-master identity; joint Slice-3/Slice-4 UI gate review.
8. (If approved) supervised staging browser smoke (§2.7) with grant/ungrant discipline.

Each step lands only with its tests; every step is index.html-narrow (closeout path only) + tests.

### 2.9 Architectural issues surfaced since the roadmap synthesis (disposition)

1. **ES-modules standing rule vs in-place `index.html` edits** — resolved by the artifact
   hierarchy: the cleared plan (§10.3) ships Slice 3 **in-place in `index.html`** under the
   standing freeze exception, and the calc-core amendment §3.7 explicitly sequences
   reconciliation/closeout-builder extraction **after 5G-1D is complete and stable**. Slice 3 is
   therefore in-place by design; no module scaffolding should be introduced for it.
2. **Test posture vs the existing `5F1-RPC-BRIDGE` source-shape tests** — the calc-core amendment
   §4 (behavior-over-shape) does not retire them; the wiring-shape here is itself the contract.
   Slice 3 updates them deliberately with the reason documented (§2.7).
3. **Auto-deploy-on-push vs inert production** — GitHub Pages deploys `main` on push, so the
   Slice-3 client **cannot merge to `main` before the activation window** (a deployed wrapper
   caller with no production EXECUTE grant fails closed — safe but closeout-blocking). Sequencing
   consequence in §7 (branch-hold; the merge is an activation-window step, freeze-respecting under
   both Gate D options). A dormant-flag alternative (ship dual-path code, flip at activation) is
   rejected: it keeps a reachable legacy write path in the client and still requires an activation
   push.
4. **Touchpoint line-drift** (§1.4.3) — cosmetic; re-pinned above.
5. **`deleteRecon` anchored-week deletability** (§2.6) — pre-existing surface whose risk rises the
   moment weeks are anchored; routed to Gate C rows 8/9 with a Slice-4 display-layer guard option.

---

## 3. Gate C — write-surface posture (decision brief; NOT decided here)

### 3.1 What Gate C now is

Originally the `repair_commitments_for_week` activation posture (readiness §2 Gate C); expanded by
amendment 1 §G into an **11-surface write-posture register**, one explicit retain/restrict/revoke
decision per surface, every change exact-signature with staging rehearsal, before/after grant
matrix, rollback SQL, wrapper-succeeds proof, and bypass-fails proof. Per the Slice-2 spec §11,
**every posture change executes at Slice 7 (activation)** — none in this pre-activation package.

### 3.2 Repository evidence (verified this pass)

- `repair_commitments_for_week(INT,INT,TEXT,JSONB,JSONB)` — deployed
  (`docs/phase-5f-1-migration.sql:997`, grant `:1338`), `can_write_financials()`-gated →
  **REST-callable by Wendy today**; can mutate a closed/anchored week's commitments and
  `weekly_reconciliations.balance_basis` (correction spec Finding 11).
- **Caller/dependency audit (Gate C's required evidence): COMPLETE.** Zero runtime callers —
  `index.html` never references it; the `test_regression.js` hits are SQL-source-text assertions
  against the 5F-1 migration file, not calls; `e2e.js`/`scripts/`/`tools/` clean. It was the
  deferred 5F-1 "historical repair mode" that was never wired into the app (`AGENTS.md` 5F-1
  deferral note). Revoking or restricting it breaks **no shipped behavior**.
- Direct `authenticated` EXECUTE on `save_goal_funding_snapshots(INT,INT,JSONB)`
  (`docs/phase-5g-1c-2-prod-migration.sql:283`) — a caller bypassing the wrapper also bypasses the
  `goal_registry` per-goal mutex; the Slice-2 spec §4.2 makes its revocation a **mandatory
  precondition** for claiming the global per-goal serialization invariant for household clients.
- Direct table grants on `goal_funding_snapshots` (`{SELECT,INSERT,UPDATE}` for `authenticated`,
  E1 validation V4f) and on `weekly_reconciliations` (the app itself uses direct DELETE via
  `deleteRecon`, `index.html:2816/2820`) — the only in-app **direct** writer of
  `weekly_reconciliations` is that DELETE; inserts/updates go through the 5F-1 RPC.
- The Gate-2 validation proved the old reconciliation RPC's `authenticated` grant **still intact**
  (a Slice-7 action, deliberately untouched).

### 3.3 Options per surface (register recap; recommended target posture = amendment §G, not a decision)

| # | Surface | Options | Recommended in §G | Breaks anything shipped? |
|---|---|---|---|---|
| 1 | old recon RPC direct EXECUTE | retain / revoke | **REVOKE** at activation (stale-client protection; wrapper calls it as definer) | stale cached browsers only — by design (plan §7) |
| 2 | `repair_commitments_for_week` | retain / wrap owner-only / restrict / revoke | **RESTRICT or revoke** (audit above: zero callers) | no (never wired); future 5F-1 historical-repair mode would need a re-grant or owner path |
| 3 | direct `save_goal_funding_snapshots` EXECUTE | retain / revoke | **REVOKE** (mutex-invariant precondition, §4.2) | no in-app caller (plan §10.10: zero references) |
| 4/5 | `goal_funding_snapshots` table INSERT/UPDATE | retain / revoke | **REVOKE** (RPC-only writes) | no (app reads only) |
| 6/7/8 | `weekly_reconciliations` table INSERT/UPDATE/DELETE | retain / revoke | **REVOKE** (RPC-only; DELETE removal kills the anchored-week delete hole) | **#8 breaks `deleteRecon`** for all weeks — needs the paired product decision (#9) |
| 9 | `deleteRecon` product behavior | keep / guard anchored weeks / remove | **RESTRICT** — anchored/completed weeks not deletable via ordinary UI | UI change (Slice 4 guard option, §2.6) |
| 10/11 | wrapper + Option B `authenticated` EXECUTE | grant at activation | **GRANT** (row 11 owner-enforced in-body) | activation itself |

### 3.4 Risks

- **Deciding late:** activation hard-stops with Gate C undecided (readiness Gate C hard stop) —
  under Gate D Option A this is on the critical path within days.
- **Under-restricting (retain #2/#3/#6-8):** post-activation, a Wendy-credentialed or stale caller
  can mutate anchored weeks around the wrapper's controls and mutex — exactly the classes the
  Gate-2 matrix proves the wrapper rejects.
- **Over-restricting (#8 without #9's UI pairing):** `deleteRecon` breaks silently for legitimate
  unanchored-week cleanup (it survived 5F-1 as a product behavior); pair the grant change with the
  UI guard and an owner-path statement.
- **Sequencing:** every revocation needs the wrapper-succeeds + bypass-fails proof pair on staging
  first (the staging environment currently holds both functions + fixtures for exactly this).

### 3.5 Exactly what requires Adam approval

1. One recorded posture per register surface (rows 1–9; rows 10/11 are the activation grants).
2. The `deleteRecon` product decision (#9) paired with #8.
3. Timing confirmation that all posture changes execute at Slice 7 under the activation approval
   (per Slice-2 spec §11), each with its own exact-signature SQL + staging rehearsal + before/after
   matrix + rollback + proof pair.
4. Whether the optional 5F-1 "historical repair mode" (the only future consumer of #2) is
   deferred-with-owner-path or dropped from the backlog.

**This package prepares the decision scaffold only; no posture is selected here.**

---

## 4. Gate D — activation timing decision card (both options; NOT chosen here)

**Grounding facts:** today is **Sun 2026-07-13**. Freeze: **Jul 24 – Aug 10, no 5G merges** (the
freeze bars merges, not weekly operations). Week 5 (Cal Wk 27) reconciled 2026-07-11; the weekly
cadence puts the **Week-6 closeout ≈ Sat Jul 18**, Week 7 ≈ Jul 25, Week 8 ≈ Aug 1, Week 9 ≈ Aug 8,
Week 10 ≈ Aug 15. Remaining engineering before any activation: Slices 3+4 (the full §2 program),
the Slice-5 browser residue, Slice 6, plus Gates B/C dispositions — every activation step
separately approved. Amendment 1 §H already **recommends** post-freeze activation ("do not
compress controls"); the readiness binding rule says a missed/unsafe pre-freeze path **defaults**
to post-freeze. The canonical synthesis C9 keeps both branches legitimate until Adam decides.

### Option A — complete and activate before July 24

- **Required calendar:** Slices 3+4 built and green ≈ Jul 16–17; Slice 6 (Adam SQL-Editor sitting)
  ≤ Jul 17; activation sitting (browser merge/deploy + grants + old-RPC revocation + Gate-C
  posture actions) Jul 17–18; **first supervised live closeout = the ordinary Week-6 closeout
  ≈ Sat Jul 18** (readiness Slice 7 pre-freeze interpretation). Realistic **go/no-go: ≈ Jul 16–17**
  — after that, activation + first closeout cannot complete "with full controls" before Jul 24.
- **Engineering implications:** ~3–4 working days for the entire §2 browser program + test matrix
  — severe compression against a state machine whose failure mode is a half-closed production
  week; the supervised staging browser smoke (§2.7) almost certainly gets cut (accepting REST-level
  Gate-2 evidence only); no Fable in the loop (the readiness package substitutes — §7 option 1);
  single live closeout (Week 6) before the freeze, then **weeks 7–9 close through the wrapper
  during the freeze with no merge window for a hotfix** — a closeout-blocking defect mid-freeze
  leaves only rollback-by-approval (old-RPC grant restore / wrapper drop) or supervised SQL;
  rollback and evidence obligations unchanged (compressed, not reduced).
- **What it buys:** durable snapshots from Week 6 forward — **zero gap weeks, no repair pass**;
  Monthly Close v1's July rehearsal gets a fully-closed July without waiting on repairs.

### Option B — activate after August 10

- **Required calendar:** build Slices 3+4 + browser-residue tests now → Slice 6 inert deploy
  (pre-freeze, or after Aug 10 — a supervised production sitting does not belong inside the freeze
  window even though it is not a git merge; Adam's call at Slice-6 approval); freeze window =
  spec/testing polish only, Slice-3 branch held unmerged;
  activation sitting after Aug 10; **first supervised production use = the Week-6 gap repair**
  (wrapper branch G, earliest-gap-first), then weeks 7/8/9 sequentially, then ordinary closeout
  resumes ≈ Week 10 (readiness Slice 7 post-freeze interpretation).
- **Engineering implications:** ~**4 gap weeks accrue (6–9; confirm against the live calendar at
  decision time)** — each reconciled via the old path, each repaired one-at-a-time under
  supervision with evidence (the repair UI variant in §2.4.6 becomes mandatory scope, which this
  package includes either way); no control compression; the staging browser smoke fits; the July
  Monthly Close v1 rehearsal waits for the repair pass; the old client (with its optimistic-write
  and no-snapshot behavior) remains the production write path ~4 more weeks — an accepted, known
  state, and the wrapper's branch G + blocked-advance semantics were built and Gate-2-proven for
  exactly this.
- **What it buys:** full test program including browser-level staging evidence; no freeze-window
  operational novelty; decision reversibility (a ready-but-unmerged branch).

**Binding statements (restated, both options):** no 5G merge during the freeze; an explicit timing
decision does not override the freeze; if the pre-freeze path becomes unsafe or misses go/no-go,
**default to post-freeze rather than compressing controls**. **Adam must choose; nothing here
presumes either option.**

---

## 5. Slice 6 — production inert deployment package

Everything below uses the committed, staging-accepted SQL package ([CURRENT]:
`docs/phase-5g-1d-preflight.sql`, `-migration.sql`, `-validation.sql`, `-rollback.sql`). The
migration/rollback environment guard resolves **production = `system_identifier
7632885393857617092` ∧ `app_environment` absent**; the unfilled staging placeholder
(`c_staging_sysid := 0`) only hard-stops staging runs — **no fill is needed for production**.
Execution model = the E1 discipline: Adam runs each step in the Supabase SQL Editor in one
sitting; Claude runs no SQL; outputs saved verbatim; value-bearing artifacts local-only.

**Preconditions (all must hold before the sitting):**
Slices 3+4 green (static + full e2e) and the joint UI gate passed; Slice-5 browser residue
dispositioned (staging smoke done, or Adam explicitly accepts Gate-2 REST-level evidence); Gate A
CLOSED (✓); **rollback separately pre-approved** (readiness Slice 6); a **fresh full-data restore
point** captured same-sitting (Free-plan `pg_dump` per the E1 model — the last known restore point,
2026-07-09, predates E2/2.1/Week-5; this is also the synthesis P1 recovery-floor item); no
freeze-window conflict per the Gate D decision; Slice-6 execution approval given in-session.

### 5.1 Deployment checklist (ordered; one sitting)

1. ☐ Confirm target project = Adam-Dashboard `usayoldrawwmjsmretin` (not staging).
2. ☐ **Preflight** (`phase-5g-1d-preflight.sql`, READ-ONLY): environment fingerprint
   (sysid + `app_environment` absent); baseline schema + E1 objects present; both deployed RPCs
   present at exact signatures; **capture their definition md5s** (the byte-unchanged baseline);
   `is_owner()`/`can_write_financials()` present; **both new functions absent**; Week-5 anchor
   complete by goal_id (nine eligible `opening_anchor`; the two `wewe_*` correction rows
   tolerated). Save output.
3. ☐ **Restore point**: full public-schema `pg_dump` (schema+data) → `~/Herndon-FOS-DB-Backups/…`
   (local-only, chmod 600); record size + sha256 in the closeout doc (metadata only committed).
4. ☐ **Migration** (`phase-5g-1d-migration.sql`): env guard resolves `production`; creates
   **exactly two** functions (13-param wrapper; 6-param Option B); ends with `REVOKE ALL … FROM
   PUBLIC, anon, authenticated` on both (inert). Runs `BEGIN…COMMIT`; save output.
5. ☐ **Validation** (`phase-5g-1d-validation.sql`, READ-ONLY; paste the step-2 md5s into
   `v_recon_md5`/`v_snap_md5` locally first). All asserts must pass (§5.2).
6. ☐ **Inert live checks** (§5.2 manual block).
7. ☐ Closeout evidence doc (balance-free) + status-doc pointer update proposal; **stop.**

**Hard stops:** any preflight assert fails; the migration guard resolves anything but
`production`; any validation assert fails; any rendered/behavioral change observed; any need to
touch E1 or the reconciliation RPC. On hard stop: nothing further; rollback only under its own
separate approval.

### 5.2 Validation checklist

From `phase-5g-1d-validation.sql` (all in one READ-ONLY transaction):
- ☐ both new functions exist at their **exact signatures**; no third/helper function
  (`_gf_is_finite_amount` absent — inlined by design);
- ☐ **inert grant state**: zero `anon`/`authenticated` EXECUTE on both; no explicit PUBLIC
  EXECUTE aclitem on either;
- ☐ **byte-unchanged proofs**: deployed `save_reconciliation_with_commitments` md5 == preflight
  baseline; deployed `save_goal_funding_snapshots` md5 == preflight baseline;
- ☐ structural asserts: SECURITY DEFINER + `search_path=public,pg_temp` on both; no dynamic SQL;
  no EXCEPTION handler; inlined finiteness rejection in both; per-goal `goal_registry FOR UPDATE`
  mutex in both; advisory-lock namespace `1734501000`;
- ☐ old reconciliation RPC `authenticated` EXECUTE **still present** (revocation is Slice 7).

Manual inert checks (same sitting):
- ☐ REST probe: authenticated POST to `/rest/v1/rpc/save_weekly_closeout_with_snapshots` →
  **grant-layer denial** (401/403/404 class; the Gate-2 `expect_anon_denied`/grant-layer classes) —
  proves not-callable, writes nothing;
- ☐ live browser (dashboard.herndons.us, hard refresh): BUILD_TS unchanged; snapshot loader still
  200 with the existing 11 wk-5 rows; weekly/recon/goals/budget render unchanged; console clean;
- ☐ `goal_funding_snapshots` row count unchanged (11); `weekly_reconciliations` untouched;
- ☐ next ordinary weekly closeout (old flow) unaffected — the production browser still calls
  `save_reconciliation_with_commitments` (Slice-3 client is deliberately not deployed).

### 5.3 Expected production state after Slice 6

- `public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)`
  and `public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)` exist, SECURITY
  DEFINER, **zero API-role EXECUTE** → not REST-callable by anon/authenticated/PUBLIC.
- E1 table + snapshot RPC, the reconciliation RPC (body, signature, **and its `authenticated`
  grant**), `repair_commitments_for_week`, all RLS, and all data **byte/state-unchanged** (wk-5
  snapshot rows still 11).
- The deployed browser is unchanged and still writes through the old RPC; nothing in the deployed
  app references the new functions (verified: comment-only at `index.html:2830`).
- **Production behavior is therefore inert after Slice 6** on three independent grounds:
  (1) grant-layer — no API role can EXECUTE either function; (2) caller-layer — no deployed code
  calls them; (3) proven-by-check — the §5.2 REST probe + live checks. Confirmed.

### 5.4 Rollback boundary (separate Adam approval; not part of deployment)

- `phase-5g-1d-rollback.sql` drops **exactly the two new functions** (env-guarded; staging-
  rehearsable) and proves E1 + the reconciliation RPC + the snapshot table survive. No grant
  restoration is needed (none was granted). **No data is ever deleted** — wrong values use the
  correction path, never a drop.
- **Boundary:** up to and including Slice 6, rollback = that DROP and nothing else; production
  data, deployed contracts, grants, and app behavior are exactly pre-Slice-6. Anything Slice 7
  later changes (activation grants, old-RPC revocation, Gate-C postures, browser deploy) carries
  its **own** per-surface rollback SQL inside the activation package — outside this boundary.
- The restore point (§5.1.3) is the disaster floor beneath the SQL rollback, per the E1 model.

---

## 6. Gate E — historical multi-week remediation (disposition)

**Does it still exist as an independent gate? Yes.** Readiness §2/§3 defines it as event-driven
("CONDITIONAL / OPEN WHEN TRIGGERED"): it fires **whenever a correction would change later weeks
or deliberately create a missing historical row / backfill**, and demands a separately reviewed
remediation plan + explicit Adam approval — no silent cascade, no backfill under an ordinary
correction approval. The plan (§6.4.1/§9) and the deployed SQL enforce its trigger mechanically:
Option B hard-stops on either adjacent bound (`below preceding` / `above following` — G2-16a/b),
and a correction needing downstream rewrites cannot proceed through any deployed path.

**Has it been satisfied? No — and it cannot be "satisfied" in advance.** It has **never been
triggered**: no multi-week remediation has occurred (the only production corrections — 5G-1C-2.1
Leg 2's two same-week wk-5 rows — ran under their own approval, pre-5G-1D, and changed no later
week; Gate-2's correction tests were synthetic staging state).

**Should it merge into another gate? No.** It guards a different event class than Gate C (grant
posture) or Gate B (activation), and merging it would erode the specific control it encodes ("an
ordinary correction approval never authorizes a cascade"). It also outlives activation — it
remains the standing control for the operating era (the synthesis §7 close/audit model leans on
it).

**One boundary clarification is warranted (documentation-only), to prevent mis-triggering:** the
**post-freeze sequential half-close gap repair is NOT a Gate-E event.** Gap repair is the wrapper's
defined branch G (plan §6.3; amendment §C): earliest-gap-first, empty commitment arrays,
persisted-equal balances, monotonic, blocked-advance — an ordinary supervised wrapper path,
Gate-2-proven (G2-18/18b). Gate E triggers only for corrections that would rewrite later weeks or
fabricate history **outside** that sequential path. Recommended status-doc sentence (§8) states
this so the Option-B repair pass is not blocked by a mis-read of Gate E, and so Gate E is not
diluted to cover it.

**Roadmap/status documentation change:** none required beyond that clarifying sentence and keeping
Gate E listed OPEN-when-triggered in the gate register. Its pre-activation disposition is exactly
this record: **exists, independent, untriggered, correctly scoped.**

---

## 7. Consolidated execution plan — finishing Phase 3 (pre-activation)

Ordered, implementation-ready; every stop point is a hard stop until its named approval exists.
"Static/full-e2e green" always means the full suites (full e2e is the release gate; smoke never
substitutes). No step executes SQL against production except Slice 6 (Adam-run). No step pushes
`index.html` wrapper wiring to `main` (auto-deploy) before the activation window.

| # | Step | Depends on | Approval required | Expected artifacts | Testing |
|---|---|---|---|---|---|
| 0 | **Review + adopt this package**; record corrections (§1.4) | — | **Adam** (package clearance) | this doc cleared; status-pointer patch staged (§8) | — |
| 1 | **Gate D decision** (§4 card) | 0 | **Adam** (Gate D) | dated decision record (option, go/no-go date if A) | — |
| 2 | **Slice-3/4 implementation approval** + prefill choice (§2.4.7) + staging-smoke disposition (§2.7) | 0 | **Adam** (implementation go) | approval note in-session | — |
| 3 | **Build Slice 3+4** on the feature branch per §2.8 (predicate → states → confirmation view → wiring → ambiguous machine → repair variant) | 2 | — (committed locally; **no push of wrapper wiring to `main`**) | index.html closeout-path diff + new static/e2e sections | static 1460+Δ/0; full e2e green at each §2.8 step; golden-master identity |
| 4 | **Slice-5 browser residue**: mocked-e2e matrix complete; if approved, supervised staging browser smoke with `staging-grant` → tests → `ungrant` → validation → fixture restore | 3 | **Adam** (staging credentials + grant cycle, if chosen) | staging evidence (balance-free); ungrant/validation output | the §2.7 e2e matrix; staging smoke results |
| 5 | **Gate C posture decisions** (§3.5 items 1–4) | 0 (info); before 7 | **Adam** (Gate C) | recorded posture per surface; Slice-7 grant-change SQL authored per surface (+ staging rehearsal plan, before/after matrix, rollback, proof pair) | staging rehearsal of each grant change (execution stays in Slice 7) |
| 6 | **Slice-6 execution approval** + rollback pre-approval + restore-point plan | 3, 4 | **Adam** (two separate approvals: run Slice 6; pre-approve rollback) | approval notes | — |
| 7 | **Slice 6 — production inert deploy** per §5.1–§5.2 (Adam runs; one sitting) | 6 | in-sitting per-step authorization | preflight/migration/validation outputs; restore-point metadata; closeout evidence doc | §5.2 validation + inert checks all pass |
| 8 | **Gate B disposition check**: Option B now deployed + validated in production (inert) — Gate B's technical precondition met; the gate itself closes with the activation approval (no dated deferral needed) | 7 | — (recorded; closure is Adam's at activation) | one-paragraph Gate-B status note | — |
| 9 | **Pre-activation verification sweep**: full static + full e2e at the activation-candidate commit (Adam runs e2e from Terminal); golden-master identity; evidence bundle assembled (Gate-2 record, Slice-3/4 test outputs, staging smoke, Slice-6 closeout, gate decisions D/C, rollback SQL set) | 7 | — | the assembled activation-readiness bundle | full suites green; `readinessFallbackHits 0/0` |
| 10 | **Status-doc updates staged** (§8) — proposed text only; applied on Adam's word | 9 | **Adam** (docs patch) | CODEX_STATUS/phase-status patch | — |

**Stopping points (hard):** after step 0 (package clearance); after step 1 (Gate D); before any
staging grant (step 4); before step 7 and before any rollback (separate approvals); before any
push of the Slice-3 client to `main`; and the terminal stop below. A failed test/validation at any
step stops that step; no compensating shortcut.

**Dependencies summary:** 3 → 4 → {6,7}; 5 is parallel after 0 but must close before activation;
1 (Gate D) gates the calendar shape of 3–7 (Option A compresses them pre-Jul-24; Option B runs 3–5
now, 6–7 at Adam's chosen time, activation after Aug 10). Under either option nothing merges to
`main` during Jul 24–Aug 10.

**Terminal state of this package:**

> **"Ready for Gate B production activation."**

**Stop.** Everything beyond — browser merge/deploy, `authenticated` EXECUTE grants on the wrapper
and Option B, old-RPC exact-signature revocation, Gate-C posture execution, stale/fresh-browser
verification, and the first supervised Week-6 closeout or gap repair (Slice 7) — is Gate
B/activation territory, each step separately Adam-approved, and is **not begun** by this package.

---

## 8. Recommended documentation updates (post-clearance; NOT applied in this pass)

Per readiness §8 discipline (status docs update only after review/clearance), staged as proposals:

1. `CODEX_STATUS.md` — banner/pointer refresh: Slice-1 client builder shipped inert (`57bc9c1`);
   Slices 1–2 staging-accepted (already recorded); **this package's path + clearance hash** as the
   active 5G-1D pre-activation pointer; verified test baseline **static 1460/0 (2026-07-13)**;
   the Gate-E boundary sentence: *"Post-freeze sequential half-close gap repair is the wrapper's
   ordinary branch-G path (plan §6.3 / amendment §C), not a Gate-E remediation; Gate E triggers
   only for corrections that would change later weeks or create history outside that sequential
   path."*
2. `docs/phase-status.md` — 5G-1D row: replace "Implementation NOT STARTED" with the §1.1/§1.2
   register (Slices 0–2 done/staging-accepted; Slice-1 builder inert in prod; 3/4/5-residue/6 +
   Gates B/C/D open; Gate E open-when-triggered); add the same Gate-E sentence.
3. `AGENTS.md` — "Current State" test-count refresh (static 1460/0; e2e 135/0 last verified at
   `db2704f`, re-verify from Terminal) and removal of the stale "Existing Quicken parallel-run
   workflow" Do-Not-Break line (superseded by the 2026-07-13 operating-state note). *(Part of the
   broader synthesis §10-step-3 patch set already awaiting Adam approval — not duplicated here.)*

None of these files is modified by this package.

---

*Plan-only. No code, SQL, schema, RPC, RLS, migration, seed, grant change, deployment, activation,
correction, reopen, remediation, or production action performed or authorized. Subordinate to the
cleared E2 runbook, 5G-1D plan, correction companion spec, readiness package, and the three
companion amendments (which control where stricter). Every gate above is an explicit Adam decision
at its trigger point; no approval is inferred from another. E1 remains immutable; E2 is complete
and is not rerun; production grants and behavior are unchanged by this document.*
