# Phase 5G-1D — Weekly Closeout Snapshot Write-Through: Plan & Execution Spec

**Status:** PLAN-ONLY. **Not started, not implemented, not activated.** No code, SQL,
schema, RPC, RLS, migration, seed, or test written this pass. This document is the
implementation-ready specification and execution plan for review (ChatGPT/Fable →
Adam). **Fable's REVISE verdict is accepted; the stricter resolutions (direct-call
wrapper, no swallowed errors, server-derived exact nine-set enforcement, opening-anchor
guard, explicit sequence semantics, source pinning, monotonic invariant, hard-stop
goal-scope drift, stale-client activation protection, wrapper security/grant
normalization) are folded in below.**
**Date:** 2026-07-09
**Author:** Claude (session under Adam)
**Predecessors:** 5G-1C-2 C3 overlay (SHIPPED + DEPLOYED, `c6fbb32`, live); E1
production DDL (COMPLETE + GREEN — `goal_funding_snapshots` +
`save_goal_funding_snapshots` exist, schema-only/EMPTY).
**Hard dependency:** **E2 first-anchor seed** (see `docs/phase-5g-1c-2-e2-runbook.md`,
cleared at `c439d68`). **5G-1D may not be implemented or activated until E2 has
successfully created and validated the first anchor.**
**Authoritative inputs read:** `index.html` (`saveRecon` 2729–2804,
`reloadReconAndCommitments` 2716–2728, C3 overlay 2571–2588, `getGoalFunded`
4341–4366, `goalCompletion` STAYS-COMPLETE 3131–3148, `goalSnapData` loader 7843–7859,
`getAuthHeaders` 7729–7734, `isWeekReconciled` 1000–1001); the deployed
`save_goal_funding_snapshots` migration (`docs/phase-5g-1c-2-prod-migration.sql`); the
5G-1C plan + Fable review; `AGENTS.md` (Do Not Touch, schema/migration conventions,
test gates); `CODEX_STATUS.md`; `docs/phase-status.md`; the E1/E2 runbooks; the
5G-QA-1 tag-based e2e runner.

---

## 0. TL;DR for the review gate

1. **Objective.** Automatically write `goal_funding_snapshots` rows
   (`source='reconciliation'`) during **supervised weekly reconciliation closeout**,
   so each reconciled week durably anchors per-goal funded reality — turning today's
   *coincidental* model/reality agreement into a reconciled cadence.
2. **The load-bearing decision (§5).** Two sequential client RPCs (reconciliation
   then snapshots) **do** create an unacceptable partial-state window: a
   reconciled-but-unsnapshotted "half-closed" week. **Required design: a single
   SECURITY DEFINER orchestration RPC** (`save_weekly_closeout_with_snapshots`) that,
   in **one PostgREST-driven transaction**, calls the deployed
   `public.save_reconciliation_with_commitments(...)` **then**
   `public.save_goal_funding_snapshots(...)` **directly** — never reproducing,
   copying, forking, or partially inlining either. **Both deployed functions stay
   byte-unchanged.** SQL is NOT written this pass.
3. **Straight-line, all-or-nothing.** No `EXCEPTION` handler swallows an inner error;
   any exception from wrapper validation, reconciliation persistence, snapshot
   persistence, or the post-call assertions **propagates and aborts the whole
   transaction** (§5.4).
4. **Server-derived exact nine-set is the integrity control (§4, §5.5).** The wrapper
   derives the authoritative eligible goal-ID set **server-side** (initial 5G-1D scope
   = exactly the nine E2-approved goals) and rejects+rolls back on any missing/extra/
   duplicate goal, count ≠ 9, eligible-set ≠ approved-nine, or a returned snapshot
   count/ID-set that differs. A client `p_expected_count` is a UI cross-check only and
   **never controls transaction acceptance.**
5. **Opening-anchor guard (§5.6).** Before any write, the wrapper mechanically verifies
   the E2 opening anchor exists and is complete (Week 5; `source='opening_anchor'`;
   exactly the nine approved IDs; all in one anchor week; no mixed/incomplete set) or
   it raises and writes nothing. 5G-1D never creates/repairs/replaces/reinterprets the
   anchor.
6. **Exact sequence + monotonicity (§6).** Normal path targets exactly the next
   sequential week after the latest complete snapshot week, with every prior post-
   anchor week already complete; no skip/jump/past-week write; `funded_amount` is
   monotonic non-decreasing for `source='reconciliation'`; a decrease or changed-value
   same-week retry hard-stops into the separately approved **correction** path.
7. **Source is server-pinned (§3.4).** The browser never supplies `source`; the wrapper
   pins `source='reconciliation'` and can never emit `opening_anchor`/`correction`.
8. **Goal-scope drift is a hard stop (§4).** The eligible set is the exact approved
   nine; any added/removed/archived goal or changed exclusion makes the wrapper raise;
   the closeout UI cannot override it. No new goal silently receives a first snapshot.
9. **Stale-client activation is engineered, not tolerated (§7).** A cached old browser
   calling `save_reconciliation_with_commitments` directly would recreate the
   half-closed state; the activation plan revokes direct `authenticated` EXECUTE on
   that RPC at a separate approval gate so a stale browser **fails before reconciliation
   persistence** and must refresh.
10. **No write on load/render.** Snapshot persistence happens **only** at an explicit,
    human-confirmed closeout action — never on page load, model calc, ordinary render,
    or passive refresh.

---

## 1. Dependency and boundaries

- **E2 must complete first.** 5G-1D is inert and undefined without a first
  `opening_anchor`. It **may not be implemented or activated until E2 has successfully
  created and validated the first anchor.** The first `reconciliation` snapshot rolls
  *forward* from the E2 Week-5 anchor.
- **Current planned E2 basis is reconciled Week 5.** 5G-1D writes the anchors for
  Week 6 and every subsequent reconciled week, one sequential week at a time.
- **5G-1D does NOT create, repair, or recreate the opening anchor.** If the E2 anchor
  is wrong, that is fixed via the E2/`correction` path, not by 5G-1D.
- **5G-1D must not modify or rerun E1 production DDL.** The table, RPC, RLS, and grants
  are deployed and immutable here. 5G-1D adds only a *caller* (client) and **one new
  additive** SECURITY DEFINER wrapper function that **calls the deployed functions
  directly** (§5.2):
  - the deployed `public.save_reconciliation_with_commitments(...)` **body and
    signature remain unchanged**;
  - the deployed E1 `public.save_goal_funding_snapshots(...)` **remains unchanged**;
  - the wrapper **does not write directly to `weekly_reconciliations`,
    `cash_commitments`, or `goal_funding_snapshots`** — it delegates entirely to the two
    inner RPCs;
  - the wrapper relies on **ordinary PostgreSQL transaction semantics** from **one**
    PostgREST RPC call (one statement = one implicit transaction).
- **Keep 5G-1E and later phases out of scope**, except a documented **compatibility
  rider** (§10.9): the C3 overlay auto/holding exclusion guard, the AMEX invariant
  advisory→hard promotion, and 5G-1B `release` rows. 5G-1D must not pre-empt those.

---

## 2. Trigger and UX

### 2.1 The exact closeout point where snapshot persistence occurs

Today `saveRecon(n)` (index.html:2729) is the sole reconciliation write. It gates on
`canWriteFinancials()` + `canSaveRecon(n)`; builds Phase-1/2/3 payloads; sets
`reconData[n]` optimistically; POSTs `save_reconciliation_with_commitments`; on success
clears staged state, `reloadReconAndCommitments()`, `renderApp()`; on failure rolls
`reconData[n]` back to `prevRecon`.

**Snapshot persistence occurs at exactly this closeout commit — bound to the same
user action ("Save actuals"), never a separate background step, and in the recommended
design the same DB transaction (§5).** The snapshot values are the operator-confirmed
observed cumulative funded per eligible goal, derived from the reconciled state (§3),
never from `runModel`.

### 2.2 Human confirmation and approval boundary (one explicit action authorizes the combined write)

- The existing "Save actuals" action, already gated by `canWriteFinancials()` (owner
  Adam / household_admin Wendy) and `canSaveRecon(n)`, is the single human
  authorization for the **combined** reconciliation + snapshot write. No new role
  logic; the 5E-7 matrix is untouched.
- **The confirmation view must show, at minimum:**
  - target week;
  - the reconciliation actuals and commitments about to persist;
  - the exact **nine** goal IDs;
  - each **confirmed funded amount**;
  - the **prior snapshot amount** for each goal (for change visibility);
  - any values that are **unchanged**;
  - the **expected nine-row count**;
  - an explicit **warning that reconciliation and snapshots will commit together** (one
    atomic closeout).

### 2.3 Client behavior (state machine)

The client must:

- **disable the closeout action while the request is in flight** (no double-submit);
- **not display reconciliation success before the wrapper succeeds** — there is no
  "reconciled" state shown until the single combined call returns success;
- **treat a timeout or lost response as ambiguous, not failed** — never assume either
  outcome from a dropped connection;
- **re-read reconciliation and snapshot state** (`reloadReconAndCommitments` + the
  `goal_funding_snapshots` loader) **before offering retry**;
- **allow automatic retry only when the persisted state or the resubmitted values are
  identical** (idempotent same-value path, §6);
- **route changed-value same-week attempts to the correction process** (§6/§3.5) — not
  the ordinary retry.

### 2.4 Success / warning / failure / retry / partial-failure

- **Success:** reconciliation + the nine snapshots persisted in one transaction; the
  week renders **fully closed** (reconciled **and** anchored).
- **Warning (non-blocking):** e.g. the SA8-style one-sided AMEX over-attribution
  advisory (§6/§10.9) or a large per-goal variance — surfaced, does not fail the write.
- **Failure (atomic):** the single transaction fails → **nothing** persists (neither
  reconciled nor snapshotted); `reconData[n]` rolls back to `prevRecon`; staged answers
  retained; error extracted from `message||hint||details` into `.recon-error`.
- **Retry:** re-invoking closeout re-runs the whole idempotent transaction; the snapshot
  upsert on `(model_year, week_num, goal_id)` makes an **identical-value** retry safe.
- **Partial-failure:** structurally impossible in the single-transaction design
  (all-or-nothing). This is the reason it is required, not optional.

### 2.5 Distinguishing saved-reconciliation from a fully-completed closeout

Two states remain visually distinct: **Reconciled** (balances saved) vs **Fully closed
/ anchored** (reconciled **and** a `reconciliation` snapshot row for each of the nine
eligible goals at that week). 5G-1D adds a derived **closeout-complete** predicate
(reconciled ∧ complete nine-row snapshot set at that week) and a distinct badge. In the
atomic design the two coincide; the distinct state exists to make any anomaly (a
reconciled week with no complete snapshot — only reachable via a legacy pre-1D/half-
closed week) **visible and repair-gated** (§6), never silent.

### 2.6 Why no snapshot write may occur on load/calc/render/refresh

- `runModel` re-simulates all 31 weeks on every call and is a **pure** read → writing
  from it would persist *simulation*, not reconciled reality, and fire on every render.
- `loadAll` / passive refresh / `reloadReconAndCommitments` / the C3 loader (7843) are
  **read** paths by design.
- A write on render would fire repeatedly, race with model recalcs, and violate the
  "reconciliation is the source" rule (§3).
- **Rule:** snapshot writes occur **only** inside the explicit, human-confirmed
  closeout transaction — one write per deliberate closeout, never a side effect of
  viewing or recomputing.

---

## 3. Snapshot semantics

- **Cumulative observed funded amount as of the reconciled week.** Each `funded_amount`
  is the observed cumulative funded for that goal at the reconciled week's end (matches
  the deployed table comment + E2 anchor semantics). Not a delta.
- **One row per eligible goal per `(model_year, week_num)`**, enforced by the deployed
  `UNIQUE (model_year, week_num, goal_id)`.
- **Reconciliation is the source** (§3.1); values never come from `runModel`'s projected
  `goalSaved`.
- **Idempotent retry:** the deployed RPC upserts `ON CONFLICT DO UPDATE`; re-closing a
  week with the **same** values overwrites the same natural-key rows (§6).
- **No historical replay / no incremental double counting / no duplicate rows.**
  Overwrite-at-anchor + natural-key upsert make double counting structurally impossible
  past an anchor; 5G-1D writes only the *current sequential* reconciled week, never
  back-fills prior weeks from current observed values.

### 3.1 Values are derived from reconciliation, not projected model output

The observed cumulative funded per goal at closeout is the operator-confirmed
reconciled reality (§3.5 explains why operator-confirmed) — from the reconciliation
inputs / confirmed custodian-and-held state — **not** from `getGoalFunded`'s projected
branch or `runModel`'s `goalSaved`. Invariant: **reconciled input in, snapshot out —
model output is never the source.**

### 3.4 Source pinning — the wrapper owns `source`

- The **browser does not provide `source`.**
- If the input structure **contains a `source` field, the wrapper rejects it**
  (raise + rollback) — the client must not attempt to set it.
- The wrapper **constructs or normalizes** the per-row snapshot payload with
  `source='reconciliation'` before calling the snapshot RPC.
- The wrapper **can never submit `source='opening_anchor'` or `source='correction'`.**
  `opening_anchor` belongs to E2; `correction` belongs to the separately approved
  correction path (§3.5/§6).

### 3.5 Monotonic cumulative-funded invariant (decided now)

- For **`source='reconciliation'`**, each goal's `funded_amount` **must be ≥ its
  immediately prior snapshot amount** for that goal. The wrapper checks this
  server-side (against the latest prior snapshot for the goal) before/at the snapshot
  step.
- **A lower value raises and rolls back the complete closeout** (both reconciliation and
  snapshot persistence).
- A **legitimate historical reduction or correction** must use the supervised
  **correction path**, which requires: **explicit Adam approval; `source='correction'`;
  documented before/after values and rationale; separate evidence; and no destructive
  rollback of the completed reconciliation** (the reconciliation stays; only the
  snapshot value is corrected additively).
- **Correction UX is deferred.** Within 5G-1D, executing a correction is a **supervised
  manual database/RPC action after separate approval** — not a button in the ordinary
  closeout flow.

### 3.6 Why per-goal values remain operator-confirmed (not fully server-derived)

The server **can** derive and validate: the **eligible goal IDs**, the **counts**, the
**sequence** (which week is next), the **prior snapshots**, the **source**, the
**monotonicity** relation, and the **reconciliation state**. It **cannot currently
derive the actual per-goal funded balances**, because the database does not yet contain
authoritative per-goal transfer events or custodian balances (that is a later phase).
Therefore **operator-confirmed, client-supplied per-goal amounts under strict
server-side validation are the necessary design for 5G-1D — not merely a UI
convenience.** Everything *about* those amounts (which goals, how many, what order,
never-decreasing, correct source) is server-enforced; only the amounts themselves are
human-supplied.

---

## 4. Goal eligibility — the exact approved nine (server-derived; hard-stop on drift)

**Eligible (written each closeout) — exactly these nine, matching E2:** `adam_ira`,
`wendy_ira`, `wendy_sep`, `alaska`, `bailey_529`, `bryce_529`, `preston_529`,
`bryce_vehicle`, `christmas_cruise`.

**The wrapper derives this eligible set server-side and enforces it (§5.5).** For the
initial 5G-1D scope the server-derived set must equal **exactly these nine**. This is
the integrity control — **not** a client-supplied count.

**Excluded — DB-enforced by the deployed RPC (authority), client-mirrored (convenience
only):**

- **Auto:** `adam_401k` — the deployed RPC rejects `g.auto = true`. Never snapshotted.
- **Holding/deferred:** `wewe_rccl`, `wewe_dcl`, `taxable_etf` — the deployed RPC
  `v_excluded` array rejects them.

**Goal-scope drift is a HARD STOP — no ordinary bypass.** Resolving the earlier
"dynamic registry" language in favor of the stop:

- The eligible set for initial 5G-1D is the **exact approved nine**.
- **Any added goal, removed goal, archived goal, changed exclusion, or other
  eligibility drift causes the wrapper to raise** (and write nothing).
- **The normal closeout UI cannot override this** through a checkbox or ordinary
  confirmation.
- **No new goal silently receives its first snapshot.**
- A future goal-scope change requires a **separately reviewed scope-change design and
  explicit Adam approval** before closeout can resume. **Newly added goals do NOT
  automatically flow into 5G-1D.**

**Per-case treatment (all subordinate to the hard stop above):**

- **Completed goals** (`wendy_sep`, `alaska`): still written each closeout with their
  observed funded value (freezes the value; `getGoalFunded` reads it for complete
  goals). No status flip.
- **Eligible goals with a legitimate zero-funded value** (529s, `bryce_vehicle`,
  `christmas_cruise` while unfunded): written as an explicit `0` — a real value, never
  dropped (else the nine-row set would be incomplete and the wrapper would raise).
- **Archived / inactive / newly added goals:** trigger the drift hard stop above; they
  are **not** silently added or silently dropped from the required nine.

**C3 overlay guard (compatibility rider — §10.9).** The deployed RPC and the wrapper
guarantee no excluded id ever gets a `reconciliation` row via the write path. The C3
*overlay itself* still does not independently guard auto/holding goals; promoting that
overlay-side guard is the named 5G-1E/1D rider — **do not rely only on client-side
filtering; the DB RPC exclusion is the enforcement.**

---

## 5. The orchestration wrapper — authorization, atomicity, direct calls, guards

### 5.1 Ground truth — the deployed `save_goal_funding_snapshots` contract

`save_goal_funding_snapshots(p_model_year INT, p_week_num INT, p_rows JSONB) RETURNS
INTEGER`, SECURITY DEFINER, `SET search_path=public`. Validates in order: **auth**
(`can_write_financials()` — not delegated to RLS) → model_year sanity → week 1..31 →
`p_rows` null/non-array/**empty** rejected → **week must be reconciled** (week_num-only
lookup) → per-row (goal_id present, funded_amount numeric ≥ 0, source ∈
{opening_anchor,reconciliation,correction}, goal in registry, **not auto**, **not in
holding/deferred exclusion set**) → idempotent upsert on `(model_year, week_num,
goal_id)`. Grants: `authenticated` = `{SELECT,INSERT,UPDATE}` (no DELETE); RLS
`allow_read`/`financial_writer_insert`/`_update`; no DELETE policy. **This contract is
unchanged by 5G-1D.**

### 5.2 The partial-state window — evaluated — and the required wrapper (direct calls only)

**Do two sequential client RPCs (reconciliation, then snapshots) create an unacceptable
partial-state window? YES.** If the client commits `save_reconciliation_with_commitments`
and *then* the snapshot RPC fails / transport interrupts, the week is
reconciled-but-unsnapshotted — a **"half-closed" week** that every "latest reconciled
week" consumer reads as reconciled while no per-goal anchor exists. Unacceptable for a
"fully closed" semantic, and worse in the natural client order (reconciliation first).

**Required design — a single additive SECURITY DEFINER orchestration RPC (SQL NOT
written this pass):**

> **`public.save_weekly_closeout_with_snapshots(<reconciliation params...>,
> p_snapshot_rows JSONB, p_expected_count INT DEFAULT NULL)`** that, in **one
> transaction** (one PostgREST RPC call), **calls the deployed functions directly**:
> 1. `public.save_reconciliation_with_commitments(...)` — reconciliation persistence;
> 2. `public.save_goal_funding_snapshots(...)` — snapshot persistence;
> ordered reconciliation→snapshots so the snapshot step's **in-transaction**
> reconciled-week check sees the just-inserted `weekly_reconciliations` row (uncommitted
> rows are visible within the same transaction), then the single implicit transaction
> COMMITs both together.

**Direct calls only (no reimplementation).** The wrapper:

- **calls both deployed functions directly** and is **prohibited from reproducing,
  copying, forking, or partially inlining** either function's logic;
- **does not write directly** to `weekly_reconciliations`, `cash_commitments`, or
  `goal_funding_snapshots`;
- leaves the **deployed reconciliation function body and signature unchanged** and the
  **deployed E1 snapshot RPC unchanged**;
- relies on **ordinary PostgreSQL transaction semantics** — nested SECURITY DEFINER
  calls run in the wrapper's single transaction, and `auth.uid()`/JWT claims propagate
  so each inner RPC's own `can_write_financials()` gate still evaluates the **real**
  caller.

**Atomic.** Either the week is reconciled **and** the nine snapshots persist, or neither
does. Partial failure is structurally impossible.

### 5.3 Wrapper security contract and grant normalization

The wrapper is:

- **`SECURITY DEFINER`** with a **fixed, safe `SET search_path`** (e.g.
  `SET search_path = public, pg_temp` per house convention);
- **fully schema-qualified** for both inner RPC calls and every non-`pg_catalog`
  object it references;
- **no dynamic SQL** (no `EXECUTE`/string-built statements);
- gated by an **explicit top-level `public.can_write_financials()` caller check** as its
  first action (in addition to — not instead of — the inner RPCs' own gates, which
  **remain intact**);
- **server-owned timestamps** (no client-supplied `created_at`/`updated_at`);
- **no broadening of any table grants**; **no anonymous invocation**.

**Grant normalization on the exact wrapper signature** (deployment step):

- `REVOKE ALL ON FUNCTION public.save_weekly_closeout_with_snapshots(...) FROM PUBLIC;`
- `... FROM anon;`
- `... FROM authenticated;`
- `GRANT EXECUTE ON FUNCTION public.save_weekly_closeout_with_snapshots(...) TO authenticated;`

**Validation must assert the exact final wrapper grant set** (`authenticated` = EXECUTE
only; PUBLIC/anon none) and **prove anonymous/unauthorized rejection**. Validation must
also separately assert that **direct `authenticated` EXECUTE on the old reconciliation
RPC is available *before* activation and revoked *after*** the approved activation step
(§7).

### 5.4 Exception behavior — straight-line, no swallowed errors

- The wrapper is **straight-line** with **no `EXCEPTION` handler wrapped around either
  inner call**.
- Any exception from **(a) wrapper validation, (b) reconciliation persistence, (c)
  snapshot persistence, or (d) the post-call transactional assertions** must
  **propagate and abort the entire transaction.**
- **Catch-and-continue is prohibited.** No handler may return success, downgrade an
  error to a warning, or continue execution.
- **Preferred: no exception handler at all.** If one is present for any reason, it may
  **only re-raise immediately** and must not otherwise alter control flow or the
  returned result.

### 5.5 Server-derived exact eligible-set enforcement (not a client count)

The wrapper is the integrity authority for *which* goals and *how many*:

- It **derives the authoritative eligible goal-ID set server-side** (initial scope =
  exactly the nine approved goals, §4) and **compares it with the submitted snapshot
  rows before calling the snapshot RPC.**
- **Reject and roll back** on any of: a **missing** eligible goal; an **extra** goal; a
  **duplicate** goal ID; **fewer or more than nine** submitted rows; **any server-
  derived eligible set other than the approved nine** (drift → §4 hard stop); or a
  **submitted-set ≠ server-derived-set** mismatch.
- **Post-snapshot assertion, inside the same transaction:** after
  `save_goal_funding_snapshots(...)` returns, the wrapper asserts the **returned count
  and the actually-written goal-ID set equal the authoritative server-derived set.**
  **Any mismatch raises and rolls back both** reconciliation and snapshot persistence.
- A client-supplied **`p_expected_count`** may remain as a **UI/human-confirmation
  cross-check** (echoed in the confirmation view, §2.2) but is **not sufficient and must
  not control transaction acceptance** — the server-derived set governs.

### 5.6 Opening-anchor guard (E2 must exist and be complete)

Before any 5G-1D write, the wrapper **mechanically verifies the E2 opening anchor
exists and is complete.** For the currently approved plan it requires:

- opening-anchor week = **Week 5**;
- **`source = 'opening_anchor'`**;
- **exactly the approved nine goal IDs**;
- **all nine rows belong to the same anchor week**;
- **no incomplete or mixed opening-anchor set** (no partial anchor, no stray extra id,
  no second anchor week).

**If this condition is not true, the wrapper raises and writes nothing.** 5G-1D **must
not create, repair, replace, reinterpret, or manufacture** the opening anchor. **Any
future re-anchor requires a revised plan, a new Value Card, and explicit Adam
approval** — the wrapper **must not silently adapt to a different anchor week.**

### 5.7 API behavior requirements

- **Real authenticated writer calls only.** House style (agent-confirmed):
  `getAuthHeaders()` (no `Prefer` header for an RPC), `POST /rest/v1/rpc/<fn>`, `p_*`
  JSON body, error extracted from `message||hint||details` (index.html:2757–2771).
- **Adam = owner, Wendy = household_admin** both authorized (both pass
  `can_write_financials()`), same as reconciliation writes.
- **No anonymous/unauthenticated writer path** (wrapper gate + inner gates + RLS +
  grants).
- **No ordinary direct table write from the app** — all writes go through the wrapper →
  the deployed RPCs.
- **Error-body handling** — parse `message||hint||details`; surface the specific
  rejection (e.g. "week X not sequential", "goal Y decreased", "anchor incomplete").
- **First supervised production writer smoke** — the first real `source='reconciliation'`
  write (the Week-6 closeout after E2) is a **supervised, approval-gated smoke**: verify
  the returned count, the written nine rows via REST/console, and the live overlay before
  treating 5G-1D as active.

---

## 6. Reconciliation consistency & exact sequence semantics

Replacing any "at or above the latest existing snapshot week" language with explicit,
mechanical normal-path rules.

**Snapshots only for a reconciled week; ordering reconciliation → snapshots in one
transaction (§5.2).**

### 6.1 Normal path — a new ordinary weekly closeout

- The **target week must be exactly the next sequential week after the latest complete
  snapshot week.**
- **Every prior post-anchor reconciliation week must already have a complete nine-row
  snapshot set.**
- **No skipped week may be bypassed.**
- **No future-week jump** is allowed.
- **No past-week snapshot may be created from current observed values.**

### 6.2 Target week already has a complete snapshot

- An **exact same-value retry** may be treated as **idempotent** (natural-key upsert,
  no change).
- A **changed-value retry is not an ordinary retry** and **must hard-stop into the
  separately approved correction path** (§3.5) — it never silently overwrites via the
  normal closeout.

### 6.3 Reconciled week with no snapshot (old client half-closed it)

- The **fresh wrapper may rerun that same week**.
- The **reconciliation upsert and the missing snapshot must complete atomically** in one
  wrapper transaction.
- **The following week cannot close until that gap is repaired** (the sequence rule in
  §6.1 blocks advancing past an incomplete prior week).

### 6.4 Monotonicity + correction distinction

- Ordinary same-week resave / next-week close writes `source='reconciliation'` and must
  satisfy the monotonic invariant (§3.5).
- A deliberate downward or historical fix is the **correction path**: explicit Adam
  approval, `source='correction'`, documented before/after + rationale, separate
  evidence, no destructive rollback of completed reconciliation. Correction UX is
  deferred (§3.5); execution is a supervised manual DB/RPC action.
- **Correction metadata:** the deployed table already carries `source`, `note`,
  `created_by_user_id`, `created_at`, `updated_at` — sufficient for 5G-1D. A dedicated
  append-only correction/audit ledger is Option-C / 5G-1E+ (rider §10.9), out of scope.

### 6.5 Retry after transport interruption / ambiguous response

The whole closeout is idempotent for identical values. On an ambiguous response the
client **re-reads** reconciliation + snapshot state before offering retry, and allows
automatic retry **only when the persisted state or resubmitted values are identical**
(§2.3); a changed-value same-week attempt routes to correction, never an auto-retry.

---

## 7. Activation & stale-client protection

**The problem.** After the wrapper and updated browser ship, a **cached old browser**
that still calls `public.save_reconciliation_with_commitments` **directly** would
commit reconciliation with **no** snapshot — recreating the half-closed state. **This is
not an acceptable production operating model, and "allow the stale client to half-close
and repair later" is explicitly NOT the recommended production choice.**

**Required activation approach (each a distinct, ordered step):**

1. **Deploy the new orchestration RPC and its tests** while the existing browser remains
   unchanged (DB support deploys inertly; nothing calls the wrapper yet).
2. **Deploy the updated browser** that calls the wrapper.
3. **Validate the new browser** in staging and in production inert checks.
4. **At the separately approved activation gate, revoke direct `authenticated` EXECUTE
   on `public.save_reconciliation_with_commitments`.**
5. **Keep that function's body and signature unchanged** (revocation is a grant change,
   not an edit).
6. **The wrapper continues to call it as the definer owner** (the wrapper's SECURITY
   DEFINER context retains access even after `authenticated` EXECUTE is revoked).
7. **A stale browser then fails *before* reconciliation persistence** (its direct call
   is denied) and **must be refreshed** — it can no longer half-close.
8. **Before revoking, verify no other supported browser path or application feature
   requires direct `authenticated` invocation** of the reconciliation RPC.

**The grant revocation is an activation change** — **not part of E1, and not an edit to
the reconciliation function body.** It **requires its own explicit Adam approval** (§9).

---

## 8. Testing and validation

Aligned with the **5G-QA-1 tag-based smoke/full runner** — smoke membership is an
explicit `opts.tags:['smoke', ...]` array per test; **no test-name-prefix filtering,
no section-level implicit inclusion.** Full mode (`node e2e.js`) stays the permanent
default and release gate.

**Wrapper structure & atomicity**
- wrapper **calls the deployed RPCs** rather than reproducing/inlining their logic;
- **snapshot failure aborts reconciliation** (nothing persists);
- **reconciliation failure writes no snapshot**;
- **exception propagation is not swallowed** (no catch-and-continue; re-raise only).

**Opening-anchor guard**
- missing or **incomplete Week-5 opening anchor** → raise, no write;
- opening-anchor **wrong week** → raise;
- opening-anchor **wrong source** → raise.

**Eligible-set / count integrity**
- **exact eligible-set mismatch** → reject+rollback;
- **missing goal**; **extra goal**; **duplicate goal ID**;
- **server-derived count mismatch**;
- **snapshot-RPC returned count or returned-ID mismatch** (post-assertion) → rollback.

**Sequence**
- successful **Week-6 first automated closeout** after the Week-5 anchor;
- **sequential next-week closeout**;
- **skipped-week rejection**; **future-week jump rejection**; **past-week rejection**;
- **identical same-week retry** (idempotent);
- **changed-value same-week retry rejection and correction routing**;
- **reconciled-but-unsnapshotted (half-closed) week repaired by the fresh wrapper**, and
  the **following week blocked until repaired**.

**Source & monotonicity**
- **normal-path monotonic decrease rejection**;
- **`source`-field injection rejection**;
- **wrapper source pinning to `reconciliation`** (never `opening_anchor`/`correction`).

**Concurrency & client**
- **concurrent submissions**; **double-click / in-flight disabling**;
- **ambiguous network response and state re-read**.

**Activation / auth**
- **stale browser before activation**; **stale browser after direct-RPC EXECUTE
  revocation** (fails before reconciliation); **fresh browser after activation**;
- **anonymous caller**; **authenticated-but-unauthorized caller**;
- **exact wrapper grants**; **old reconciliation RPC direct grant before and after
  activation**.

**Contract non-regression**
- **unchanged deployed reconciliation function definition**;
- **unchanged E1 snapshot RPC/table/RLS contract**;
- **existing reconciliation regression** suite green.

**For every forced wrapper failure, assert that neither half of the combined closeout
persisted** (week not reconciled AND no snapshot). Golden-master identity still holds for
zero-snapshot runs.

---

## 9. Deployment, activation, and rollback gates (explicitly separated)

Each is a distinct gate; none implies another:

1. **E2 completion and evidence** (opening anchor created + validated).
2. **Plan approval** (this document).
3. **Implementation approval** (begin coding slices).
4. **Staging migration** (wrapper + tests on staging).
5. **Production inert database deployment** (wrapper deployed; nothing calls it yet —
   DB support may deploy inertly before browser activation).
6. **Browser deployment** (updated client shipping the wrapper caller).
7. **Activation approval** (turn the combined closeout on).
8. **Revocation of direct `authenticated` access to the old reconciliation RPC** (§7) —
   its **own explicit Adam approval**.
9. **Rollback approval** — separate; wrapper rollback (drop the wrapper and/or restore
   grants) **requires explicit Adam approval.**
10. **Correction approval** — separate; each supervised correction (§3.5) is its own
    approval.
11. **Future scope-change approval** — any change to the eligible nine (§4) needs a
    separately reviewed scope-change design + Adam approval before closeout resumes.

**Rollback must not delete approved historical snapshots or undo completed reconciliation
data automatically.** Wrong *values* are corrected via the correction path, never dropped.

---

## 10. Deliverables

1. **Revised E2 runbook/package recommendation:** delivered — `docs/phase-5g-1c-2-e2-runbook.md`
   (cleared by Fable at `c439d68`). 5G-1D consumes E2's validated Week-5 anchor as its
   §5.6 precondition.
2. **Complete 5G-1D specification + execution plan:** this document (§0–§9, §11).
3. **Proposed files to change** (when implementation is approved — none changed now):
   - `index.html` (in-place, under the standing freeze exception): the closeout-complete
     predicate + "reconciled vs closed" UI state; the confirmation view (§2.2); the
     in-flight/ambiguous client state machine (§2.3); the snapshot payload builder wired
     into the `saveRecon` closeout path; the **single wrapper call** with error-body
     surfacing.
   - `docs/phase-5g-1d-*.sql` (staging-first package): preflight / migration (**additive
     wrapper only** — direct calls to the two deployed RPCs; no reimplementation) /
     validation (exact wrapper grants; anon/unauth rejection; old-RPC grant
     before/after; contract-unchanged proofs) / rollback / RLS-smoke — mirroring the
     5G-1C-2 package discipline; **deployed E1 objects and the reconciliation RPC
     untouched**.
   - `test_regression.js` + `e2e.js` (the §8 matrix; tag-based, no name-prefix filters).
   - `CODEX_STATUS.md` / `docs/phase-status.md` (pointers) at phase close.
4. **Acceptance criteria:** E2 complete + validated (§5.6 precondition); the wrapper
   **calls both deployed RPCs directly** with **no reimplementation** and **both
   contracts byte-unchanged**; **all-or-nothing** proven (neither half persists on any
   forced failure); **straight-line, no swallowed errors**; **server-derived exact
   nine-set** governs acceptance (client count is cross-check only); **opening-anchor
   guard** enforced; **exact sequence** (next-week-only, no skip/jump/past); **monotonic
   non-decrease** for `reconciliation`; **source server-pinned**; **goal-scope drift
   hard-stops**; **wrapper grants exactly `authenticated`-EXECUTE**, anon/unauth
   rejected; **stale-client activation** engineered and tested; a supervised Week-6
   writer smoke passes with evidence; static + e2e-full green; golden-master identity
   holds for zero-snapshot runs.
5. **Risk register:**
   | Risk | Mitigation |
   |---|---|
   | Half-closed week (recon commits, snapshot fails) | Single-transaction wrapper; **direct calls**; §7 stale-client revocation |
   | Swallowed inner error → false success | Straight-line, no `EXCEPTION` handler; re-raise only (§5.4) |
   | Client count trusted as integrity control | **Server-derived** nine-set + post-write ID/count assertion; client count is cross-check only (§5.5) |
   | Missing/incomplete/wrong opening anchor | §5.6 guard raises and writes nothing |
   | Skipped/future/past-week write | Exact sequence rules (§6); server-enforced |
   | Silent monotonic decrease | Reject+rollback; correction path only (§3.5) |
   | `source` spoofed by client | Wrapper pins `reconciliation`; rejects any `source` field (§3.4) |
   | New goal silently snapshotted | Goal-scope drift hard stop (§4); no UI override |
   | Reproducing/forking inner logic | Direct-call-only mandate; contract-unchanged tests (§5.2, §8) |
   | Stale cached browser half-closes | Engineered activation + direct-RPC EXECUTE revocation (§7) |
   | Grant broadening / anon path | Exact wrapper grant normalization + validation (§5.3) |
   | Freeze-window merge | No 5G merges Jul 24–Aug 10; sequence around it |
6. **Execution checklist:** E2 done + validated → Slice 0 (read-only closeout-complete
   state) → Slice 1 (pure client payload builder + unit tests) → Slice 2 (wrapper RPC
   staging-first; direct-call + contract-unchanged proofs; exact-grant validation) →
   Slice 3 (confirmation view + in-flight/ambiguous state machine + single wrapper call)
   → Slice 4 (the §8 test matrix) → Slice 5 (staging smoke) → Slice 6 (production inert
   DB deploy → browser deploy → inert checks) → **activation gate** (revoke old-RPC
   direct EXECUTE, separate Adam approval) → Slice 7 (supervised Week-6 writer smoke,
   evidence) → status update. Each slice: Fable → Code (green) → Adam.
7. **Rollback plan:** client — revert the `index.html` closeout-write commit (the
   read-only state + payload builder are inert without the wrapper call). DB — `DROP
   FUNCTION` the **wrapper** (additive; the E1 objects and the reconciliation RPC
   remain) and/or **restore the revoked reconciliation-RPC grant**, each under separate
   explicit Adam approval. **Rollback never deletes approved historical snapshots or
   undoes completed reconciliation automatically**; wrong values use the correction path.
8. **Stop conditions (hard):**
   - **E2 opening anchor absent or incomplete** (§5.6) → do not start / raise.
   - **Eligible set not exactly the approved nine** (§4) → hard stop.
   - **Target week not sequential** (skip/future/past) (§6.1) → hard stop.
   - **Any unclosed prior post-anchor snapshot week** (§6.1/§6.3) → hard stop until
     repaired.
   - **Changed-value retry through the normal path** (§6.2) → hard stop → correction.
   - **Monotonic decrease through the normal path** (§3.5) → hard stop → correction.
   - **Stale-client protection not approved or not testable** (§7) → do not activate.
   - **Wrapper grants broader than intended** (§5.3) → stop.
   - **Any need to change the deployed E1 snapshot RPC** → stop (out of scope).
   - **Any need to reproduce reconciliation or snapshot logic** (vs. direct call) → stop.
   - **Any inability to prove all-or-nothing failure behavior** → stop.
   - Also: deployed reconciliation/E1 contract not byte-unchanged; returned count/ID-set
     mismatch; write reachable from render/load path; freeze-window merge.
9. **Documented riders for later phases (out of 5G-1D scope):**
   - **C3 overlay auto/holding exclusion guard** — promote the overlay to independently
     refuse auto/holding ids (today it relies on clean writes). 5G-1D-rider / 5G-1E.
   - **AMEX invariant advisory → hard gate** — stays one-sided advisory in 5G-1D; hard
     two-sided gate is 5G-1E (after 5G-1B releases).
   - **`source='release'`** rows for RCCL/DCL holding payout — 5G-1B.
   - **Append-only correction/audit ledger** and **correction UX** — beyond the existing
     source/note/created_by/updated_at columns and the deferred manual correction path —
     is Option-C / 5G-1E+.
   - **Server-derived per-goal balances** (custodian/transfer-event sourcing) — a later
     phase; until then, operator-confirmed amounts under server validation stand (§3.6).
10. **Assumptions challenged / corrected after reviewing the actual repo:**
    - **A half-closed window is real, not hypothetical.** `saveRecon` commits
      reconciliation first and marks the week reconciled optimistically
      (index.html:2754); a following snapshot failure leaves a genuinely misleading
      reconciled-but-unanchored week → the atomic **direct-call** wrapper is required,
      not a two-RPC-plus-nag path.
    - **A client-supplied count cannot be the integrity control** — the wrapper must
      derive the eligible nine-set server-side and assert the written set post-hoc
      (§5.5).
    - **Exclusion is already DB-enforced; inclusion must be pinned.** The deployed RPC
      rejects auto/holding/deferred, but the *required nine* is a 5G-1D scope decision
      enforced by the wrapper + goal-scope hard stop — not "whatever the registry holds."
    - **`getGoalFunded` reads snapshots only for `complete` goals; active goals read the
      anchored `goalSaved`** — so the operator-confirmed value must be the observed
      cumulative, consistent for both branches.
    - **"Latest reconciled week" is recomputed inline everywhere** (no single variable)
      — the sequence/closeout-complete logic must derive it consistently, not assume a
      stored value.
    - **The write RPC caller does not exist yet** (grep confirms zero
      `save_goal_funding_snapshots` references in `index.html`) — 5G-1D is a genuinely
      new caller; the wrapper is the only write path.
    - **Server cannot yet derive per-goal funded balances** — no authoritative per-goal
      transfer events / custodian balances exist in the DB, so operator-confirmed amounts
      under strict server validation are necessary, not a convenience (§3.6).

---

## 11. Explicit non-goals (this phase)

No opening-anchor creation/repair/reinterpretation (E2 owns it). No E1 DDL
modification/rerun. No edit to the deployed reconciliation function body/signature (only
a grant revocation at the §7 activation gate, separately approved). No reproduction/
inlining of either inner RPC's logic. No 5G-1E account-purpose/holding-bucket hard gate.
No 5G-1B release rows. No append-only audit ledger and no in-flow correction UX (manual
supervised correction only). No new role logic. No `runModel` math change beyond the
already-shipped C3 overlay. No name-prefix e2e filtering. No write on load/calc/render/
refresh. No newly added goal auto-flowing into snapshots.

---

*Plan-only. No 5G-1D code, SQL, schema, RPC, RLS, migration, seed, or test written this
pass. Implementation begins only after E2 succeeds and validates, and only on Adam's
explicit in-session go-ahead, behind the standing test gates + golden-master identity
gate, and outside the Alaska freeze window (Jul 24–Aug 10). Activation (and the old-RPC
grant revocation) is a further, separately approved gate.*
