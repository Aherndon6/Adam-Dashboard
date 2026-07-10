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
7b. **Complete retry identity + two supervised modes (§2.3.1, §5.8).** An "identical
   retry" means exact equality across **both** halves (reconciliation *and* snapshots),
   re-read from both persisted records; a changed value is never an idempotent retry. The
   wrapper has two mechanically separate modes: `normal_closeout` (ordinary UX) and
   owner-only `approved_reopen` (DB-enforced via `public.is_owner()`, latest completed
   week only, separate Adam approval) for reconciliation fixes. Snapshot value fixes are
   a separate owner-only `source='correction'` in-place upsert with adjacent-week
   monotonicity checks — never combined with a reopen under one approval.
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
- **before offering or accepting an automatic retry, re-read BOTH persisted halves** —
  the persisted **weekly reconciliation record** *and* the persisted **nine-row snapshot
  set** (`reloadReconAndCommitments` + the `goal_funding_snapshots` loader) — and compare
  the submitted payload against **both**;
- **allow automatic retry only on complete combined-closeout identity** (§2.3.1) —
  matching snapshot values alone is **not** sufficient;
- **route any changed-value same-week attempt to the approved reopen/correction process**
  (§5.8/§6) — never the ordinary retry. **The normal retry button must never update
  changed reconciliation or snapshot values.**

#### 2.3.1 Complete retry identity (across both halves)

An "identical retry" means **exact equality across the entire combined closeout**, not
just the snapshot amounts:

- model year and target week;
- **every** reconciliation actual;
- **every** reconciliation commitment;
- every other persisted reconciliation input or flag;
- the exact **nine** snapshot goal IDs;
- **all nine** funded amounts;
- any other server-persisted closeout field that affects the resulting records.

**Required outcomes** (after re-reading both persisted halves and comparing the payload
against each):

- **Both halves absent** → ordinary new-closeout rules apply (§6.1).
- **Reconciliation and snapshots both present and exactly identical** → return/confirm
  **idempotent success without changing any values.**
- **Reconciliation present but snapshots absent** → treat as a **half-closed week**; the
  fresh wrapper repairs that same week atomically (§6.3).
- **Snapshots present but reconciliation absent** → **hard stop** as an
  impossible/corrupt state (never auto-"repaired").
- **Either half present with any changed value** → **not** an automatic retry; route to
  the approved **reopen** (reconciliation change, §5.8) or **snapshot-correction**
  (amount change, §3.5/§6.4) process.

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
  **snapshot-correction path**, which requires **explicit Adam approval;
  `source='correction'`; documented before/after values and rationale; separate
  evidence; and no destructive rollback of the completed reconciliation** (the
  reconciliation stays).
- **Correction is an IN-PLACE natural-key replacement, not an appended row.** Under the
  deployed unique key `(model_year, week_num, goal_id)`, a correction **upserts the
  existing natural-key row in place**: it **replaces `funded_amount`**, **changes or pins
  `source='correction'`**, **does not create a duplicate row**, and **leaves the table
  with exactly one row** for that model_year/week/goal. (The phrase "corrected
  additively" is retired — there is no second row.)
- **Because the write is in-place, the DB row is NOT a complete history ledger** after a
  correction. **External correction evidence is therefore MANDATORY and captured BEFORE
  the write:** original value; corrected value; original source; corrected source;
  reason; approving Adam decision; timestamp; target week and goal; execution evidence
  and the resulting row.
- **Adjacent-week monotonicity is validated (§6.4.1).**
- **Correction UX is deferred.** Within 5G-1D, executing a correction is a **supervised
  manual database/RPC action after separate approval** — not a button in the ordinary
  closeout flow, and mechanically separate from the reconciliation-reopen mode (§5.8).

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

### 3.7 Correction effectivity, roll-forward, and "effective prior snapshot"

- **"Effective prior snapshot"** is defined consistently throughout this plan as **the
  latest applicable natural-key row for a goal after any approved in-place correction** —
  i.e. the current `(model_year, week_num, goal_id)` row value, regardless of its
  `source`. All prior-value comparisons (monotonicity, next-week close) use this.
- **A corrected natural-key row becomes the effective snapshot for that week**, and
  subsequent behavior uses it transparently:
  - the **C3 overlay reads the corrected value**, because its lookup is by model_year /
    week / goal — **not** by `source`;
  - the **next ordinary weekly closeout uses the corrected amount as the effective prior
    value**;
  - **future monotonicity checks compare against the corrected value**;
  - **`source='correction'` does not make the row invisible** to overlay or sequence
    logic — it remains the effective row for its week and goal.

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
> p_snapshot_rows JSONB, p_mode TEXT DEFAULT 'normal_closeout', p_expected_count INT
> DEFAULT NULL)`** that, in **one transaction** (one PostgREST RPC call), **calls the
> deployed functions directly** (`p_mode` selects the mechanically separate operation
> mode — `normal_closeout` or `approved_reopen`, §5.8; the ordinary browser may pass
> only `normal_closeout`):
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

**Exact-signature discipline (all grant operations).** Every `REVOKE`, `GRANT`,
validation, and restoration — for both the wrapper and the old reconciliation RPC — must
target the **exact deployed function signature** (name **and** the full ordered argument
type list), **never the function name alone.** Postgres identifies a function by its
signature; relying on the bare name risks hitting or missing an overload. The validation
suite records the exact resolved signatures it acted on.

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

### 5.8 Two mechanically separate wrapper modes — `normal_closeout` and `approved_reopen`

The wrapper exposes **two mechanically separate modes** via `p_mode`:

- **`normal_closeout`** — the ordinary weekly-closeout write. **The browser's ordinary
  weekly-closeout workflow may invoke ONLY `normal_closeout`.**
- **`approved_reopen`** — exists **solely to correct reconciliation actuals,
  commitments, or other reconciliation inputs for an already completed week**. It is
  **not** reachable through the ordinary retry button or normal weekly-closeout UX.

**`approved_reopen` requires ALL of the following:**

- **explicit Adam approval for that specific week and correction;**
- **owner-only authorization enforced in the DATABASE, not merely an operator note** —
  grounded in the repo's actual owner predicate **`public.is_owner()`**
  (`docs/phase-5a-role-enforcement.sql`: SECURITY DEFINER, `app_users.role='owner'` +
  `active` + `auth.uid()`). The wrapper's `approved_reopen` branch **calls
  `public.is_owner()`** and raises if false. (Preflight must confirm `is_owner()` is
  deployed in production before this mode ships.) The client `isOwnerUser()`
  (`USER_ROLE==='owner'`, index.html:7786) is UI-only and is **not** the enforcement.
- **an explicit operation mode supplied to the wrapper** (`p_mode='approved_reopen'`);
- **no access through the ordinary retry button or normal weekly-closeout UX;**
- **supervised manual execution;**
- **before/after reconciliation values and rationale captured as evidence;**
- **the target week already has a complete reconciliation AND a complete nine-row
  snapshot set;**
- **the target week is the latest completed closeout week.**

**An authenticated household writer who is NOT the owner must be rejected from
`approved_reopen`, even though `can_write_financials()` ordinarily permits weekly
closeout.** (Wendy/`household_admin` can `normal_closeout`, but cannot `approved_reopen`.)

**Scope limit (initial 5G-1D):** `approved_reopen` **may not modify an older week after
later weeks have closed** — only the latest completed closeout week. Modifying an older
week (downstream reconciliation states may depend on it) requires a **separately
reviewed historical-repair plan** and explicit Adam approval.

#### 5.8.1 Atomic reopen behavior

For an approved reconciliation reopen, in one wrapper transaction:

1. The wrapper **validates owner-only authorization (`public.is_owner()`) and the
   approved-reopen state** (latest completed week; complete existing reconciliation +
   nine-row snapshot).
2. It **calls the deployed reconciliation RPC with the corrected reconciliation values.**
3. It **calls the deployed snapshot RPC with the exact already-approved nine snapshot
   amounts** — **unless a separate snapshot correction has been approved.**
4. The **snapshot call remains idempotent for those unchanged values** (natural-key
   upsert, no change).
5. **All in-transaction set, sequence, source, and returned-row assertions still run**
   (§5.5).
6. **Any error rolls back both calls** (§5.4, straight-line).

The wrapper **continues to pin `source='reconciliation'`** in `approved_reopen`. The
reopen mode **may not submit `source='correction'` and may not silently change snapshot
amounts.** If the snapshot amounts also require correction, that is a **separate
snapshot-correction gate and operation** (§6.4) — **do not combine an unapproved
snapshot-value change with a reconciliation reopen.**

#### 5.8.2 Reconciliation reopen vs snapshot correction (two distinct operations)

| | **Reconciliation reopen** | **Snapshot correction** |
|---|---|---|
| Changes | reconciliation actuals / commitments / related fields | one or more `funded_amount`s in existing natural-key rows |
| Mode / mechanism | wrapper owner-only `approved_reopen` | supervised owner-only correction (`source='correction'`) |
| Snapshot values | resubmits existing nine **unchanged** | replaces value(s) in place (§3.5) |
| Reconciliation | changed, atomic across both calls | **not** automatically altered or rolled back |
| Approval | explicit Adam approval (that week/correction) | **separate** explicit Adam approval |
| Validation | set/sequence/source/returned-row assertions | adjacent-week monotonicity (§6.4.1) |
| Evidence | before/after reconciliation values + rationale | mandatory before/after (§3.5) |

**If both are needed for one week, require two separately identified approvals and an
explicit execution order.** One approval **does not** implicitly authorize the other.

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

### 6.2 Target week already has a complete snapshot — normal-path hard stop

For `normal_closeout`:

- An **exact combined-identity same-value retry** (§2.3.1) may be treated as
  **idempotent** (natural-key upsert, no change).
- An **already-completed same week with changed reconciliation values must raise.**
- An **already-completed same week with changed snapshot values must raise.**
- **Changed values may not be treated as idempotent.**
- The **client must route the operator to the supervised reopen (§5.8, reconciliation
  change) or snapshot-correction (§3.5/§6.4, amount change) process.**
- **No ordinary UI acknowledgment or checkbox may bypass this rule.**
- Because the **direct authenticated reconciliation RPC remains revoked after
  activation** (§7), the supervised reopen **must execute through the wrapper's
  owner-only `approved_reopen` branch — not by restoring ordinary direct access** to the
  old RPC.

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
  `created_by_user_id`, `created_at`, `updated_at`, but an in-place correction is **not**
  a complete history ledger — so the **external before/after evidence (§3.5) is
  mandatory.** A dedicated append-only correction/audit ledger is Option-C / 5G-1E+
  (rider §10.9), out of scope.

#### 6.4.1 Adjacent-week monotonicity during a snapshot correction

A historical snapshot correction must preserve the cumulative sequence **in both
directions**. For a corrected week and goal, require:

- **corrected amount ≥ the immediately preceding effective snapshot amount**, if one
  exists (§3.7 "effective prior snapshot");
- **corrected amount ≤ the immediately following effective snapshot amount**, if one
  exists.

If either condition fails, **hard stop.** **Do not silently cascade or rewrite later
snapshots.** A correction that would require changes to later weeks needs a **separately
reviewed multi-week remediation plan and explicit Adam approval** (§9). For a correction
of the **latest completed week**, only the preceding-value check applies until a later
snapshot exists.

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
   on the old reconciliation RPC**, targeting its **exact deployed function signature**
   (name + full ordered argument type list, **not the name alone** — §5.3), so an
   overload is neither missed nor hit by accident.
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

**Complete retry identity (R1)**
- **complete retry identity across reconciliation and snapshots** (full combined
  equality, §2.3.1);
- **same snapshots but changed reconciliation actuals** → not idempotent → route;
- **same snapshots but changed commitments** → not idempotent → route;
- **same reconciliation but changed snapshot amount** → not idempotent → route;
- **half-closed reconciliation-only state repaired through the wrapper** (§6.3);
- **impossible snapshots-without-reconciliation state rejected** (hard stop);
- **ordinary mode rejects changed same-week input** (no idempotent overwrite).

**Reconciliation reopen (R2)**
- **owner-approved reopen of the latest completed week succeeds atomically**;
- **non-owner authenticated household writer cannot invoke reopen mode** (rejected by
  `is_owner()` even though `can_write_financials()` is true);
- **ordinary browser cannot invoke reopen mode** (`p_mode` restricted to
  `normal_closeout` in the ordinary UX);
- **reopen failure rolls back both the corrected reconciliation and the snapshot call**;
- **reopen resubmits unchanged snapshot values idempotently**;
- **reopen attempt on an older, non-latest week is rejected**;
- **direct old reconciliation RPC remains unavailable after activation** (reopen must go
  through the wrapper owner-only branch, not direct access).

**Snapshot correction & adjacent-week monotonicity**
- **snapshot correction replaces one natural-key row rather than appending**;
- **row count remains unchanged after correction** (one row per year/week/goal);
- **`source` becomes `correction`**;
- **C3 overlay resolves the corrected value** (lookup by year/week/goal, not source);
- **next-week monotonicity uses the corrected value** (effective prior, §3.7);
- **correction below the preceding effective value is rejected** (§6.4.1);
- **correction above an existing following effective value is rejected** (§6.4.1);
- **a correction requiring downstream rewrites hard-stops** (no silent cascade);
- **before/after correction evidence is required** (§3.5).

**Contract non-regression**
- **unchanged deployed reconciliation function definition**;
- **unchanged E1 snapshot RPC/table/RLS contract**;
- **existing reconciliation regression** suite green.

**For every forced failure, assert that no unauthorized or partial state persisted**
(neither half of the combined closeout committed; no reopen/correction by an
unauthorized caller). Golden-master identity still holds for zero-snapshot runs.

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
10. **Future scope-change approval** — any change to the eligible nine (§4) needs a
    separately reviewed scope-change design + Adam approval before closeout resumes.

**Operation-level gates (each distinct; none implies another):**

- **Ordinary closeout** (`normal_closeout`, §5.8) — the standing weekly write path.
- **Automatic identical retry** — permitted only on complete combined-identity re-read
  match (§2.3.1); no approval beyond the original closeout, but strictly gated on
  identity.
- **Half-closed-week repair** — the fresh wrapper completing a reconciled-but-
  unsnapshotted week (§6.3); atomic, blocks advancing until repaired.
- **Reconciliation reopen** — owner-only `approved_reopen` (§5.8); its own explicit
  per-week Adam approval.
- **Snapshot correction** — owner-only `source='correction'` (§3.5/§6.4); its own
  separate explicit Adam approval.
- **Historical multi-week remediation** — any correction/reopen touching an older week
  after later weeks closed, or requiring downstream rewrites (§5.8/§6.4.1); a
  **separately reviewed** remediation plan + explicit Adam approval.

**Cross-authorization is prohibited:**

- **A reconciliation reopen does NOT authorize a snapshot correction.**
- **A snapshot correction does NOT authorize a reconciliation reopen.**
- **Neither operation restores direct `authenticated` access to the deployed
  reconciliation RPC** (the §7 revocation stands; both go through the wrapper).

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
   | Changed value slipped in as an "idempotent retry" | Complete combined retry identity across both halves; re-read both persisted records (§2.3.1) |
   | Non-owner (Wendy) performs a reconciliation reopen | DB-enforced `public.is_owner()` in `approved_reopen`; ordinary UX cannot pass `p_mode` (§5.8) |
   | Reopen silently changes snapshot amounts / bundles a correction | Reopen resubmits unchanged nine; `source='reconciliation'` pinned; correction is a separate gate (§5.8.1/§5.8.2) |
   | In-place correction erases history | Mandatory external before/after evidence; one row per natural key (§3.5) |
   | Correction breaks adjacent-week cumulative order | Two-sided adjacent-week monotonicity; hard-stop, no silent cascade (§6.4.1) |
   | Grant op targets bare name / wrong overload | Exact deployed function signature for every REVOKE/GRANT/validate/restore (§5.3, §7) |
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
   - **Changed-value retry through the normal path** (§6.2) → hard stop → reopen/correction.
   - **Snapshots-present-but-reconciliation-absent** (impossible/corrupt) (§2.3.1) → hard stop.
   - **Monotonic decrease through the normal path** (§3.5) → hard stop → correction.
   - **`approved_reopen` invoked by a non-owner** (fails `public.is_owner()`), **through
     the ordinary UX/retry**, or on a **non-latest week** (§5.8) → hard stop.
   - **Reopen attempting to change snapshot amounts**, or a **correction bundled into a
     reopen** without its own approval (§5.8.1/§5.8.2) → hard stop.
   - **Correction below the preceding, or above the following, effective value**
     (§6.4.1), or one **requiring downstream rewrites** → hard stop (→ multi-week
     remediation gate).
   - **Correction executed without the mandatory before/after evidence** (§3.5) → stop.
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
supervised correction only). **No new role logic for ordinary closeout** (both Adam and
Wendy write via `can_write_financials()`); the owner-only `approved_reopen` branch
**reuses the existing deployed `public.is_owner()` predicate**, not a newly invented
role. No `runModel` math change beyond the already-shipped C3 overlay. No name-prefix
e2e filtering. No write on load/calc/render/refresh. No newly added goal auto-flowing
into snapshots.

### 11.1 Previously-cleared controls preserved (unchanged by this R1/R2 revision)

This revision **adds** retry-identity and reopen/correction rigor and **weakens or
removes nothing** cleared at `949ee3f`: direct calls to the two deployed functions; no
copied/reproduced inner logic; no swallowed exceptions; the exact server-derived
nine-goal set; the complete Week-5 opening-anchor requirement; contiguous next-week
sequencing; source pinning; ordinary-path monotonicity; the goal-scope hard stop; the
stale-client grant revocation; wrapper grant normalization; separate activation and
rollback approvals; and E1 immutability.

---

*Plan-only. No 5G-1D code, SQL, schema, RPC, RLS, migration, seed, or test written this
pass. Implementation begins only after E2 succeeds and validates, and only on Adam's
explicit in-session go-ahead, behind the standing test gates + golden-master identity
gate, and outside the Alaska freeze window (Jul 24–Aug 10). Activation (and the old-RPC
grant revocation) is a further, separately approved gate.*
