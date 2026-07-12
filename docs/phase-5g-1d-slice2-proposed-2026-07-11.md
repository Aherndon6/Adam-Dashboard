# Phase 5G-1D Slice 2 — Proposed Implementation Package (PLAN/SPEC-FIRST, rev 8)

> **Rev 8 — SQL-authoring corrections (ChatGPT + own analysis; uncommitted, pending Fable):**
> (1) **Staging deployability** — the migration/rollback/preflight now use a **dual-environment
> guard** (production sysid + no `app_environment`, OR staging sysid + `app_environment`; unknown
> hard-stops). Single-file body ⇒ staging and production bodies are identical by construction.
> (2) **Monotonic non-decrease is now enforced IN THE WRAPPER** (the deployed snapshot RPC does
> not enforce it) — each submitted `funded_amount ≥ the latest effective prior (any source)`;
> a decrease hard-stops → correction path (branches E and G, under the locks).
> (3) **`p_expected_count` is now ENFORCED** (`IS DISTINCT FROM 9 → raise`) — no longer an ignored
> integrity-looking param; the server-derived nine-set still governs which goals/values.
> (4) **`approved_reopen` requires EMPTY commitment arrays** — a genuine reopen corrects
> reconciliation actuals only; commitment ops route to a separate supervised commitment-repair
> path (re-applying commitment creates through the deployed RPC is not duplicate-safe). Branch G
> half-close repair now explicitly covers the **0-snapshot** legacy state. These narrow §8.1/§8.3
> and the `p_expected_count` framing; recorded elsewhere in this doc + the SQL package.

**Status:** Rev 7 is **committed** (`c858205`/`6959bab`); **Rev 8 corrections are UNCOMMITTED and
PENDING FABLE REVIEW**. The **eight Slice-2 SQL/supporting artifacts are AUTHORED but UNEXECUTED**
(untracked; no SQL run, no grant changed, no browser wired, no staging/production action). The
grounding contract stands: the deployed `save_reconciliation_with_commitments` RPC **ignores
`p_recorded_at` and always stamps `recorded_at = NOW()`** (`docs/phase-5f-1-migration.sql`
L520/L537/L544/L552), so a genuine `approved_reopen` **re-stamps `recorded_at = NOW()`** (Companion
Amendment 3); only the no-op/identity/repair/adjudication paths (which never call the RPC) leave it
unchanged; the original is retained in the supervised before/after reopen evidence. `p_recorded_at`
is a **required compatibility/signal parameter whose supplied value the deployed RPC discards**;
the public wrapper does **not** expose it. **Next step: Fable review of the Rev-8 package + the
authored SQL, then staging execution under separate approval.**
**Date:** 2026-07-11
**Author:** Claude (session under Adam)

**Controls in force:** cleared plan (`6de4614`), correction spec (`f005263`), readiness
(`a55d899`), the committed first amendment (`0c10784`), **companion amendment 2**
(`docs/phase-5g-1d-amendment-2-2026-07-11.md`, empty-array automatic-identity narrowing of §B.1),
and **companion amendment 3** (`docs/phase-5g-1d-amendment-3-2026-07-11.md`, genuine-reopen
`recorded_at` re-stamp). Slice-1 builder committed inert (`57bc9c1`). **Gate A CLOSED.**
Gates B–E open.

**PRIVACY: balance-free.** No household balances, funded amounts, goal targets, or custodian
figures appear here or in any future committed SQL. Production is fingerprinted by
**non-financial structural signals only** (§2.1). Balance-based fingerprints, if ever wanted,
live only in an **operator-local, non-committed execution copy** (E1/E2/Leg-2 pattern).

---

## 0. Gate A — CLOSED (2026-07-11), evidence recorded

Read-only production preflight (Adam-run; no data change): `active_owner_count=1`; Adam's
real login (`aherndon6@gmail.com`, `role='owner'`, active; `auth_user_id` joins `auth.users`)
→ **`is_owner()=true`**; Wendy (`wherndon22@gmail.com`, `household_admin`) → **false**; anon →
**false**. Adam's real login — **not** the `adam@herndons.us` seed identity — maps to the
owner row. All five conditions met; **no `app_users` correction needed.** Owner-only paths may
rely on `public.is_owner()`.

---

## 1. Resolved exact signatures (§G.1 TBDs closed; `p_recorded_at` removed — correction 8)

**Design decisions:** (a) **no parameter defaults** on either function — resolves the
PostgreSQL default-ordering rule and enforces strict `p_mode` (client always sends every arg
by name via PostgREST); (b) **`p_recorded_at` is removed from the wrapper** — the wrapper
supplies a **server-controlled** timestamp to the inner RPC (correction 8, §8.3), so a client
can never backdate the audit timestamp. Both functions `RETURNS JSONB`.

### 1.1 Wrapper (register row 10) — EXACT (13 params)
```
public.save_weekly_closeout_with_snapshots(
  p_week_num        INT,
  p_model_year      INT,
  p_chk             NUMERIC,
  p_sav             NUMERIC,
  p_amx             NUMERIC,
  p_tax             NUMERIC,
  p_lc              NUMERIC,
  p_balance_basis   TEXT,
  p_new_commitments JSONB,
  p_patched         JSONB,
  p_snapshot_rows   JSONB,
  p_mode            TEXT,
  p_expected_count  INT
) RETURNS JSONB
```
**Exact ordered type list (every REVOKE/GRANT/validation):**
`save_weekly_closeout_with_snapshots(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB, JSONB, JSONB, TEXT, INT)`

### 1.2 Option B correction (register row 11) — EXACT (6 params)
```
public.correct_goal_funding_snapshot(
  p_model_year        INT,
  p_week_num          INT,
  p_goal_id           TEXT,
  p_new_funded_amount NUMERIC,
  p_expected_prior    NUMERIC,
  p_note              TEXT
) RETURNS JSONB
```
**Exact ordered type list:** `correct_goal_funding_snapshot(INT, INT, TEXT, NUMERIC, NUMERIC, TEXT)`

**§G.1 status:** both TBDs **RESOLVED**. When this package is cleared, the amendment register
rows 10/11 bind to these exact signatures (recorded per the amendment's "recorded here first"
rule; the committed amendment file is unchanged).

---

## 2. Proposed Slice-2 SQL package (DRAFT — no committed `.sql` files yet)

Staging-first; loud PRODUCTION/STAGING headers; **non-financial** production fingerprint;
exact-signature grants; byte-unchanged proofs for the two deployed RPCs.

### 2.1 `phase-5g-1d-preflight.sql` (read-only) — NON-FINANCIAL fingerprint (Rev 8)
Resolves the environment to **exactly one of two known clusters** (else hard-stop), using
**structural, non-financial** signals only, and applies **environment-specific** checks:
- **PRODUCTION** requires: **`system_identifier = 7632885393857617092` AND `public.app_environment`
  ABSENT** — plus the **production-only transaction-count floor** (`>= 40`; a structural volume gate,
  a count, not an amount).
- **STAGING** requires: **`system_identifier = c_staging_sysid` (pinned via the read-only query in
  the header — sentinel `0` until filled) AND `public.app_environment` present with EXACTLY one row,
  `env='staging'`, no other rows/values** — plus the **staging synthetic Week-5 fixture** (the
  eligible-nine `opening_anchor` set, every row carrying the `[STAGING-FIXTURE]` note marker, with
  **no** eligible wk5 `opening_anchor` row left unmarked). Staging does **NOT** require production
  transaction volume.
- **Any other state (ambiguous sysid/marker) hard-stops.** `public.app_environment` is only queried
  inside an explicit `IF v_has_appenv THEN` guard (never a bare `EXISTS` under a boolean AND, which
  errors on production where the table is absent).
- **13 canonical goal *ids* present** in `goal_registry` (ids, not targets/amounts; both environments);
- **both deployed RPCs exist** with the exact signatures §1 lists; capture their
  `pg_get_functiondef` hashes for the byte-unchanged proof;
- **`public.is_owner()` / `public.can_write_financials()` exist** (Gate A closed);
- **wrapper + Option B do NOT already exist** (fresh deploy);
- **complete Week-5 anchor by ID:** exactly the nine eligible `opening_anchor` goal *ids*
  present; the two non-eligible `wewe_rccl`/`wewe_dcl` correction rows tolerated (§A) — **all
  by id, no amounts.**

> Any balance-based fingerprint (e.g. a specific account starting balance or goal target)
> is **NOT committed**; if an operator wants a stronger financial cross-check it is added
> only to a **local, non-committed execution copy**, exactly as E1/E2/Leg-2 handled it.

### 2.2 `phase-5g-1d-migration.sql` (additive; BEGIN/COMMIT) — deploys INERT (correction 1)
Creates **exactly two** functions and **no others** (the §8.4 finiteness predicate and the
§4.1 per-goal mutex are **inlined** in each — no helper function). SECURITY DEFINER,
`SET search_path = public, pg_temp`, fully schema-qualified, no dynamic SQL, no `EXCEPTION`
handler. **No table DDL, no edit to any deployed function, no E1 rerun.**

**Grant posture in the committed production migration = GENUINELY INERT:**
```sql
REVOKE ALL ON FUNCTION public.save_weekly_closeout_with_snapshots(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.correct_goal_funding_snapshot(
  INT,INT,TEXT,NUMERIC,NUMERIC,TEXT
) FROM PUBLIC, anon, authenticated;
-- NO GRANT TO authenticated in the inert production migration.
-- authenticated EXECUTE is granted ONLY at the Slice-7 activation gate (§3, Gate C).
```
Because an authenticated client can call any PostgREST RPC it has EXECUTE on **without** any
browser change, inert must mean **no `authenticated` EXECUTE at all** until activation. The
functions exist but are callable only by the definer owner / service role until then.

### 2.3 `phase-5g-1d-validation.sql` — §9. ### 2.4 `phase-5g-1d-rollback.sql` — §10.
### 2.5 `phase-5g-1d-staging-grant.sql` / `-ungrant.sql` — the staging-only temporary-grant
package (§3). ### 2.6 `phase-5g-1d-rls-smoke-gate*.{sql,md}` — real-caller matrix (§12).

---

## 3. Inert grant lifecycle (correction 1) — the authoritative posture sequence

| Phase | `authenticated` EXECUTE on wrapper / Option B | Mechanism |
|---|---|---|
| **Production inert deploy (Slice 6)** | **NONE** (REVOKE ALL) | `phase-5g-1d-migration.sql` — no GRANT |
| **Staging real-caller test (Slice 5)** | **temporary** | `phase-5g-1d-staging-grant.sql` (STAGING-ONLY, guarded to reject production by fingerprint) grants EXECUTE → run the real-caller matrix → `phase-5g-1d-ungrant.sql` REVOKEs it |
| **Staging post-test** | **NONE** | after `-ungrant.sql`, prove the **final staging grant state == the intended inert production state** (both: PUBLIC/anon/authenticated = no EXECUTE) |
| **Production activation (Slice 7)** | **GRANTED** | exact-signature `GRANT EXECUTE … TO authenticated`, **only** with the Gate C posture package + browser-activation approval |

- The **staging temporary grant is a separately identified package** and must be reverted in
  the same session; validation asserts the reverted state.
- **Activation grant** (production) is a Slice-7 action with its own approval; it is **not**
  part of the Slice-2/Slice-6 committed migration.
- Owner-only for Option B is enforced **in-body** (`is_owner()`) as defense-in-depth; the
  outer gate is still the grant (absent until activation).

Validation (§9) and rollback (§10) are updated to this lifecycle.

---

## 4. Shared concurrency & serialization contract (correction 3)

Every snapshot write path uses **TWO** transaction-scoped locks, always acquired in this order
**after caller/mode/owner authorization and pure-input validation, but before any
state-dependent read:** (1) the **per-`(year,week)` advisory lock** (weekly-closeout state);
then (2) the **per-goal snapshot-mutation mutex** (cross-week same-goal serialization, §4.1).
Both auto-release at transaction end, so no explicit unlock and no leak on error.

**Full lock-acquisition order (ChatGPT ordering D), for BOTH functions:**
1. authorization + pure-input validation (no state reads);
2. **`pg_advisory_xact_lock(1734501000, p_model_year*100 + p_week_num)`** — year/week advisory;
3. **per-goal mutex** — `goal_registry` row `FOR UPDATE` in canonical `ORDER BY id` (§4.1)
   (wrapper: all nine eligible goals; Option B: its one `p_goal_id`);
4. snapshot neighbourhood / state reads;
5. snapshot-row `FOR UPDATE` where still useful (belt-and-suspenders, §8.2);
6. validations and writes.

**Namespace registration (scan evidence, decision 3).** Repo-wide scan (2026-07-11) of
`*.sql`/`*.html`/`*.js`/`*.md` for `pg_advisory_lock` / `pg_advisory_xact_lock` /
`pg_try_advisory` and of all deployed `docs/*.sql` function definitions found **zero advisory
locks anywhere** (the only "advisory" hits are the SA8 over-attribution *business advisory
flag*, unrelated). The literal `1734501000` appears **nowhere else**. It is therefore
**registered as the reserved advisory namespace for 5G-1D weekly closeout AND snapshot
correction** — no other advisory-lock user in the app may reuse it; validation (§9) re-asserts
this.

**Key derivation (deterministic, documented collision domain):** both functions call the
**exact** expression
```
pg_advisory_xact_lock(1734501000, p_model_year * 100 + p_week_num)
```
(documented equivalently as `v_lock_ns CONSTANT int := 1734501000;
PERFORM pg_advisory_xact_lock(v_lock_ns, p_model_year*100 + p_week_num);`).
- **Collision domain:** two callers targeting the same `(year, week)` serialize; different
  weeks proceed in parallel. `year*100+week` is unique for `week ≤ 31 < 100`. Namespace
  `1734501000` is reserved (above).
- **Wrapper:** every branch (new closeout, identity retry, half-close repair, approved reopen)
  acquires the **same** `(year,week)` lock.
- **Option B (deadlock-safe, corrected):** acquires the **same** `(year,week)` advisory lock
  for its target week first, **then in ONE deterministic step identifies the nearest preceding
  row, the target row, and the nearest following row for the goal and `FOR UPDATE`-locks all of
  them together in a single `SELECT … WHERE week_num IN (prev,target,next) … ORDER BY week_num
  FOR UPDATE`** — i.e. **all identified rows are locked in ascending `week_num` order, and the
  target is NOT locked separately/first.** Only after all locks are held does it compare
  `p_expected_prior` and evaluate the monotonic bounds (§8.2).
- **Deadlock avoidance:** every Option B transaction locks its identified rows under one
  ascending-`week_num` `SELECT … FOR UPDATE`. Two corrections on adjacent weeks that share a
  row therefore request locks in the **same global order** (lower `week_num` first), so a
  wait-cycle is impossible — they queue, they do not deadlock. (Target-first locking, which
  Rev 3 wrongly implied in §8.2, is removed: A locks N then N+1 while B locks N+1 then N would
  deadlock.)

### 4.1 Per-goal snapshot-mutation mutex (cross-week phantom fix — selected mechanism)

**Why the year/week advisory lock is insufficient.** It serializes only the **same** `(year,
week)`. Option B on week N (advisory key `…N`) and a normal closeout / half-close repair / other
Option B on week N+1 (advisory key `…N+1`) do **not** serialize. Under READ COMMITTED, a
`FOR UPDATE` on the neighbour rows cannot lock a **not-yet-existing** row, so after Option B's
neighbourhood read another transaction can **insert a same-goal snapshot on an adjacent week
that violates the corrected amount's monotonic bound** and commit — a phantom-bound violation.
The neighbourhood re-confirm closes only **identify-to-lock drift within one transaction**, NOT
this post-recheck phantom.

**Selected mechanism (ChatGPT preferred): `goal_registry` row `FOR UPDATE`.** Every function
that can write `goal_funding_snapshots` must first take a `FOR UPDATE` lock on the **stable
`goal_registry` row(s)** for the goal(s) it will touch:
- **`save_weekly_closeout_with_snapshots`** — before any snapshot-state read or write, lock **all
  nine eligible** `goal_registry` rows in one statement, canonical `ORDER BY id`:
  `PERFORM 1 FROM public.goal_registry WHERE id = ANY(<eligible nine>) ORDER BY id FOR UPDATE;`
  (applies to normal closeout, identity retry, half-close repair, and reopen);
- **`correct_goal_funding_snapshot`** — before neighbour discovery, lock its one row:
  `PERFORM 1 FROM public.goal_registry WHERE id = p_goal_id FOR UPDATE;`
- **any future snapshot correction/write path uses the same contract** (documented invariant).

Because **any** same-goal snapshot writer must hold that goal's `goal_registry` `FOR UPDATE`
first, a concurrent phantom insert on an adjacent week for the same goal **cannot occur while
Option B (or a wrapper) holds the lock** — the second writer blocks until the first commits, at
which point it re-reads the now-committed neighbourhood.

**Grounding + collision-safety (verified this pass):**
- **One stable row per eligible goal:** `goal_registry.id` is `TEXT` and is the FK-referenced
  key (`goal_funding_snapshots.goal_id … REFERENCES public.goal_registry(id)`), i.e. UNIQUE/PK —
  exactly one row per goal id. Preflight re-asserts the nine eligible ids exist.
- **No conflicting lock order:** a repo scan found **no existing `FOR UPDATE` on
  `goal_registry` anywhere**; the deployed RPCs only **plain-read** it (counts, target lookups,
  `to_regclass`), which does not conflict with `FOR UPDATE` under MVCC. So the only writers that
  take `goal_registry FOR UPDATE` are these snapshot paths, all in canonical `ORDER BY id`.

**Deadlock-freedom of the two-lock scheme.** Advisory locks are per-`(year,week)` (disjoint
across weeks); registry `FOR UPDATE` is always acquired in `ORDER BY id`. A wrapper (nine rows)
and an Option B (one row, trivially in order) request the shared registry rows in the **same
global order**, and no transaction waits for an advisory key it does not target — so no
wait-cycle exists across either lock type. Two wrappers on different weeks serialize on the
registry set (both need all nine, same order) — acceptable: closeouts are low-frequency,
supervised writes. Different goals via Option B remain independent (disjoint registry rows).
*(Alternative considered and NOT selected: a second advisory namespace with a documented
goal→int CASE map; the registry-row mechanism is preferred because it locks real, FK-guaranteed
rows and needs no new magic key.)*

**Concurrency matrix (tests, §12):**

| Scenario | Required outcome |
|---|---|
| Double-submit same week (two normal closeouts) | exactly one writes; the second sees state and takes identity/repair/hard-stop — no duplicate, no lost update |
| Normal closeout racing Option B (same week) | serialized by the week lock; one completes, the other re-evaluates against committed state |
| Approved reopen racing Option B (same week) | serialized; no interleaved partial state |
| Two Option B corrections, same `expected_prior` | first commits; second's `FOR UPDATE` re-read sees the new value ≠ its `expected_prior` → hard-stop (no lost update) |
| Half-close repair racing an identity retry (same week) | serialized; repair completes missing rows, retry then sees nine-complete → identity |

### 4.2 Mutex invariant & Gate C dependency (assertion 2 — the guarantee has a precondition)

The `goal_registry` row-lock protocol serializes snapshot writes **only if every reachable
snapshot writer follows it.** The deployed `save_goal_funding_snapshots` RPC does **not** itself
acquire the mutex, so the **global per-goal serialization invariant is conditional**:
- **Slice-2 inert deployment:** the two new functions have **no `authenticated` EXECUTE** — no
  household client can call them; nothing to race yet.
- **Controlled staging tests:** **direct legacy `save_goal_funding_snapshots` EXECUTE is a known
  bypass** of the mutex; it must **not** be used as an approved concurrent writer **except in
  deliberate bypass tests** that demonstrate the gap (never as a baseline concurrent path).
- **Slice-7 activation:** **revocation of direct `authenticated` EXECUTE on
  `save_goal_funding_snapshots` (register row 3) is a MANDATORY precondition** for claiming the
  global per-goal serialization invariant for household clients. Until that revocation, the
  invariant holds only for callers that go through the wrapper/Option B.
- **Wrapper call-through is safe:** the wrapper/Option B already **hold the `goal_registry`
  mutex** when they invoke the legacy RPC, so their call-through never bypasses it.
- **Service-role / owner administrative bypass remains privileged** and is **outside the
  household-client concurrency guarantee** (an owner running SQL directly is trusted, supervised,
  and not part of the modeled concurrent-client set).

---

## 5. Wrapper control flow (corrections 5 & 6 applied)

Straight-line, **no `EXCEPTION` handler** (any error aborts the single implicit transaction).
**Owner boundary is early (correction 5); sequence rules are branch-specific (correction 6).**

```
-- STEP 1  Input & authorization (no state reads yet)
1a. p_mode must be a non-null literal ∈ {'normal_closeout','approved_reopen'} else RAISE.   -- branch A
1b. IF p_mode='approved_reopen': public.is_owner() else RAISE.                               -- OWNER BOUNDARY, first
    ELSE (normal_closeout): public.can_write_financials() else RAISE.
    (can_write_financials MAY also be asserted for reopen, but never before/instead of is_owner().)
1c. Pure-input validation (no persisted-state reads): p_model_year = 2026 else RAISE;
    p_week_num in 1..31 else RAISE; **each of p_chk/p_sav/p_amx/p_tax/p_lc passes the canonical
    finite-numeric guard (§8.4) — non-null, not NaN/±Infinity — then round to cents (balances
    are NOT required nonnegative)**; **strict commitment-array guard (§8.5): p_new_commitments and
    p_patched are each a non-null JSON array (`… IS NOT NULL AND jsonb_typeof(…)='array'`) — SQL
    NULL / JSON null / object / string / number / boolean REJECTED, never coerced to `[]`**;
    p_snapshot_rows well-formed AND contains NO 'source' key AND goal_id set == the
    **function-local canonical eligible-nine CONSTANT array `c_eligible9`** (a literal in the
    function body — **NOT** a `goal_registry` query; assertion 1) AND **each funded_amount passes
    §8.4 AND is ≥ 0, rounded to cents** else RAISE; **`p_expected_count` is MANDATORY and must
    equal 9 — any NULL or non-9 value hard-stops (`p_expected_count IS DISTINCT FROM 9 → raise`).
    The server-derived exact eligible-nine set (`c_eligible9`) remains authoritative for row
    identity/content; `p_expected_count` is an additional mandatory count cross-check, not the
    integrity control.**

-- STEP 2  Serialize (both locks BEFORE any state-dependent read; §4)
2a. PERFORM pg_advisory_xact_lock(1734501000, p_model_year*100 + p_week_num).                -- year/week advisory
2b. PERFORM 1 FROM public.goal_registry WHERE id = ANY(c_eligible9) ORDER BY id FOR UPDATE.  -- per-goal mutex (§4.1), constant ids

-- STEP 3  Post-lock state reads (all under BOTH locks; assertion 1):
3a. Eligible-nine EXISTENCE/COUNT: assert every id in c_eligible9 exists in goal_registry
--   (count = 9) — this is a STATE READ, so it lives here (post-lock), never in STEP 1c.
3b. Opening-anchor guard (§A) — eligible-nine opening_anchor complete at wk 5 (tolerate
--   non-eligible rows) else RAISE.

-- STEP 4  Mode / week gates
4a. IF p_mode='approved_reopen' → REOPEN state machine (§8.1): target must be the LATEST
    completed week (else RAISE); then the identity / adjudication / apply sub-branches D/E/F
    (§8.1) — reopen does NOT blindly re-call the recon RPC. (owner already proven at 1b.)
4b. ELSE normal_closeout:
    IF p_week_num in {1,2,3,4} → RAISE 'legacy pre-anchor, out of scope'.                    -- branch B
    IF p_week_num = 5 → RAISE 'week 5 is the opening anchor; not a normal-closeout write'.   -- branch C

-- STEP 5  State branch (normal_closeout, week ≥ 6). Read has_recon, elig_snap_count.
5a. IF NOT has_recon AND elig_snap_count ≥ 1 → RAISE 'corrupt: snapshots without recon'.     -- branch H (any sequence)
5b. IF NOT has_recon AND elig_snap_count = 0 → NORMAL NEW CLOSEOUT (branch E): require
    p_week_num = next contiguous post-anchor week AND every earlier post-anchor week
    nine-complete, else RAISE. Then call recon RPC (server timestamp) → snapshot RPC
    ('reconciliation') → read-back assert (§7) → COMMIT.
5c. IF has_recon AND nine-complete → FULLY-CLOSED RETRY (branch F): identity (§6); target may
    be historical (NO next-week requirement). identical → idempotent success, no inner calls,
    no audit change; differ → RAISE.
5d. IF has_recon AND NOT nine-complete → HALF-CLOSE REPAIR (branch G, §7): require p_week_num
    is the EARLIEST incomplete reconciled post-anchor week (else RAISE — repair the earliest
    gap first); later weeks stay blocked until it completes.
```

**Exactly-one-branch proof.** After the mode/week gates (A/B/C) and the reopen short-circuit
(4a), the normal-closeout state is fully partitioned by `(has_recon ∈ {F,T}) ×
(elig_snap_count = 0 | ≥1-but-<9 | =9)`:
`¬recon∧≥1→H`; `¬recon∧0→E`; `recon∧9→F`; `recon∧(≥1∧<9 or 0)→G`. Every `(recon,count)`
pair maps to exactly one of E/F/G/H; the branch-specific sequence rule is applied *inside*
the selected branch, so sequence never re-routes a state. No input matches two branches.

---

## 6. Full-identity comparison — SELECTED design (correction 4)

**Non-contradiction (correction 4):** in **normal new-closeout (E)** and **approved reopen
(D)** the wrapper passes `p_new_commitments`/`p_patched` to the deployed recon RPC
**unchanged** and never inspects their internals. **Only the fully-closed identity branch (F)
inspects submitted operation objects, read-only**, to decide idempotency.

**Reconciliation identity** and **snapshot identity** are as the amendment §B.1 (cents-
normalized balances + `balance_basis`; eligible-nine `goal_id` set + cents; persisted
`source`/`note` untouched; non-eligible rows ignored/never mutated; `recorded_at` excluded
from compare and unchanged on success).

**Commitment identity — CONSERVATIVE FALLBACK, APPROVED (Adam decision 1; companion
amendment 2 `docs/phase-5g-1d-amendment-2-2026-07-11.md`).**

> **Rule:** automatic idempotent success for a fully-closed week is available **only when
> `p_new_commitments` is an empty JSON array AND `p_patched` is an empty JSON array** (both
> validated as real arrays per §8.5, `jsonb_array_length = 0`; JSON `null`/`{}`/scalars were
> already rejected in input validation, never coerced). In that
> empty-array case the wrapper still **compares reconciliation state and the eligible-nine
> snapshot state in-transaction**; if both are identical it returns **idempotent success
> without calling either inner RPC and without changing any audit field.** If **either
> commitment array is non-empty**, the wrapper **does not attempt to reproduce or project the
> deployed reconciliation RPC's commitment mutation semantics**, **does not blindly re-call
> the reconciliation RPC**, and routes to **supervised adjudication after a client re-read**.

**Why the fallback.** Proving "each submitted create's persisted fields equal the exact
canonical result the deployed RPC would have produced, and each patch already equals persisted
after the RPC's normalization/default rules" **cannot be done without reproducing the deployed
reconciliation RPC's material mutation logic** — its `original_amount_cents` auto-preservation
on amount change, its `status`/`cleared_date`/`resolution_type` transitions, and its column
defaulting (`docs/phase-5f-1-migration.sql` commitment-apply block). That reproduction is
forbidden (plan §5.2), so the fallback is the correct design, not a compromise.

**Supervised-adjudication signal (machine-distinguishable, decision 5).** For a fully-closed
week with a non-empty commitment array, the wrapper — **before any inner call, having written
nothing** — raises a **dedicated, reserved application error** so the client can tell it apart
from a definite failure:
```
RAISE EXCEPTION
  'Fully closed week %: automatic idempotency is unavailable for a non-empty commitment '
  'resubmission — re-read and use supervised adjudication.', p_week_num
  USING ERRCODE = 'GFA01', HINT = 'REQUIRES_SUPERVISED_ADJUDICATION';
```
- **`ERRCODE='GFA01'`** is the reserved 5G-1D "goal-funding adjudication" SQLSTATE; the
  `HINT` token `REQUIRES_SUPERVISED_ADJUDICATION` is the stable string surfaced through
  PostgREST `code`/`hint`. **The client maps this specific code/hint to the re-read +
  supervised-adjudication UX; every other error is a definite failure. Ordinary automatic
  retry is never attempted for this signal.**
- Because the raise happens **before** any inner RPC call, **no state changed and no inner RPC
  ran**; the transaction rolls back over nothing persisted (atomicity intact — the limit is
  on *automatic outcome adjudication*, not on transactional persistence).

**Amendment status:** this **narrows committed amendment §B.1** (non-empty intended-final-state
auto-identity). Rather than edit the cleared amendment in place, the narrowing is recorded in
**companion amendment 2** (`docs/phase-5g-1d-amendment-2-2026-07-11.md`), which controls.

On empty-array identity match: `RETURN jsonb_build_object('ok',true,'idempotent',true,
'week_num',p_week_num,'snapshot_count',9)` — no inner RPC call, no write, no audit change.

---

## 7. Snapshot write + read-back; half-close repair (under the §4 lock)

**Normal write (E) and repair (G)** end with an **in-transaction read-back SELECT** asserting
the eligible-nine `goal_id` set and exact cents values (snapshot RPC returns only a count),
else RAISE. **Half-close repair (branch G), ordered:**
```
1. read present eligible rows at (2026, wk) [under the week advisory lock];
2. FOR each present eligible row: assert funded_amount == submitted amount (cents) else RAISE
   'correction anomaly' (do NOT overwrite; preserve its source/note);
3. missing_ids := eligible_nine EXCEPT present;
4. build repair rows for missing_ids only, source pinned 'reconciliation';
5. assert p_new_commitments='[]' AND p_patched='[]' else RAISE;      -- empty-array requirement is §C-only
6. assert submitted p_chk/sav/amx/tax/lc + p_balance_basis == persisted recon else RAISE;
7. call save_goal_funding_snapshots(2026, wk, <missing rows>);        -- recon RPC NOT called
8. read-back assert complete eligible-nine set + values;
9. recorded_at unchanged; non-eligible rows (wewe_*) untouched.
```

---

## 8. approved_reopen, Option B, and `p_recorded_at` (corrections 5, 7, 8)

### 8.1 `approved_reopen` (wrapper) — retry/adjudication state machine (Rev-7)
**Owner boundary already enforced at STEP 1b** (is_owner() before any state read — correction 5);
both shared locks held (advisory + per-goal `goal_registry FOR UPDATE`, §4/§4.1). Then, in order:

- **A. Preconditions:** the target is the **latest completed week** with a **persisted
  reconciliation AND a complete eligible-nine snapshot set** else RAISE.
- **B. Snapshots are never changed by reopen:** the submitted snapshot amounts must **equal** the
  persisted eligible-nine amounts (cents) else RAISE; `source`/`note` are **preserved** and the
  snapshot RPC is **not** used to change them.
- **C. Compare submitted reconciliation state with persisted** (cents-normalized balances +
  `balance_basis`, `model_year`/`week_num`).
- **D. Persisted reconciliation ALREADY equals the submitted reopened result** (a
  commit-then-lost-response retry):
  - if **`p_new_commitments = '[]'::jsonb` AND `p_patched = '[]'::jsonb`** (both proven arrays,
    §8.5, length 0) → **return idempotent reopen success; call NEITHER inner RPC; preserve
    `recorded_at` and all audit fields.**
  - if **either commitment array is non-empty** → **raise the reserved
    `ERRCODE='GFA01'` / `HINT='REQUIRES_SUPERVISED_ADJUDICATION'` signal; call NEITHER inner RPC;
    change no state** (same fallback as §6 — the reopen's commitment effect cannot be proven a
    no-op without reproducing the recon RPC's mutation logic).
- **E. Persisted reconciliation DIFFERS from the submitted reopened result** (a genuine reopen):
  - **reopen requires EMPTY commitment arrays** (Rev-8 / item A) — a reopen corrects reconciliation
    actuals only; if `p_new_commitments` or `p_patched` is non-empty → **hard-stop** (route to the
    separate supervised commitment-repair path; re-applying commitment creates through the deployed
    RPC is not duplicate-safe).
  - **call `save_reconciliation_with_commitments(...)` exactly once** with the corrected recon
    values and **empty commitment arrays**. **The deployed RPC re-stamps
    `recorded_at = NOW()`** (it ignores its `p_recorded_at` argument, §8.3 / Companion Amendment
    3). The wrapper passes a **non-null server value (`now()`) for signature compatibility only**;
    it does **not** claim to preserve the original timestamp. The **original `recorded_at` is
    captured in the mandatory supervised before/after reopen evidence, before execution.**
  - **do NOT call the snapshot RPC** (snapshots unchanged, per B);
  - perform **post-call reconciliation read-back assertions**; atomic (roll back on any error).
- **F.** A non-identical request that is **not valid** under these approved-reopen rules (e.g.
  snapshot amounts differ from persisted, or preconditions unmet) → **hard-stop.**

The wrapper **may** return a **non-persisted** `reopened_at = clock_timestamp()` field for
operator feedback only — never written to any row, not durable audit history. The post-reopen
persisted `recorded_at` represents the **latest successful reconciliation write, NOT the original
closeout time**.

**Companion Amendment 2 governs this too:** its empty-array automatic-identity and non-empty
supervised-adjudication rules apply to ambiguous retries of **both** `normal_closeout` and
`approved_reopen` (CA2 clarification added this pass).

### 8.2 Option B `correct_goal_funding_snapshot` — COMPLETE validation (deadlock-safe lock order)
In order, in one transaction, with an exact lock sequence:
- **Steps 1–6:** authorization and pure-input validation (no state-dependent read);
- **Step 7:** acquire the year/week advisory lock;
- **Step 7b:** acquire the per-goal `goal_registry FOR UPDATE` mutex;
- **Step 8:** identify and lock the snapshot neighbourhood in deterministic ascending `week_num`
  order;
- **Step 9 onward:** perform the expected-prior / bound comparisons and writes only after **all**
  locks are held.
1. `public.is_owner()` else RAISE (Wendy/`household_admin` rejected);
2. `p_model_year = 2026` else RAISE;
3. `p_week_num` **post-anchor** (`≥ 6`) and `≤ 31` else RAISE; **`p_week_num = 5` → RAISE**
   (no Week-5 correction via Option B; anchor stays guarded-SQL, D3);
4. `p_goal_id` ∈ the eligible nine else RAISE;
5. `p_new_funded_amount` and `p_expected_prior`: apply the **canonical finite-numeric guard
   (§8.4)** — non-null, **not `NaN`/`Infinity`/`-Infinity`** — and require **≥ 0**; then
   `round(·,2)` to cents for all later comparisons/writes;
6. `p_note`: non-null, `btrim(p_note) <> ''` else RAISE (trimmed, non-empty);
7. `PERFORM pg_advisory_xact_lock(1734501000, p_model_year*100 + p_week_num)` (§4 exact key);
7b. **per-goal mutex (§4.1):** `PERFORM 1 FROM public.goal_registry WHERE id=p_goal_id FOR UPDATE`
    — taken **before** neighbour discovery, so no concurrent same-goal snapshot writer (any week)
    can insert a phantom neighbour while this correction runs;
8. **Single deterministic lock of the neighbourhood (Rev-4 deadlock fix):**
   ```sql
   -- identify prev/target/next week_num for this goal (read, not yet locking):
   v_prev := (SELECT max(week_num) FROM public.goal_funding_snapshots
              WHERE model_year=p_model_year AND goal_id=p_goal_id AND week_num < p_week_num);
   v_next := (SELECT min(week_num) FROM public.goal_funding_snapshots
              WHERE model_year=p_model_year AND goal_id=p_goal_id AND week_num > p_week_num);
   -- lock ALL identified rows in ONE statement, ascending week_num (target NOT locked first):
   -- (rows: v_prev if not null, p_week_num target, v_next if not null)
   PERFORM 1 FROM public.goal_funding_snapshots
     WHERE model_year=p_model_year AND goal_id=p_goal_id
       AND week_num IN (v_prev, p_week_num, v_next)   -- NULLs simply match nothing
     ORDER BY week_num
     FOR UPDATE;
   ```
9. **Only after all locks are held:** re-read under lock —
   - **target row must exist** at `(p_model_year, p_week_num, p_goal_id)` else RAISE (Option B
     never backfills a missing row);
   - **re-confirm neighbourhood unchanged (identify-to-lock drift ONLY):** no row exists for the
     goal strictly between `v_prev` and `p_week_num`, or between `p_week_num` and `v_next`, else
     RAISE (retry-safe). *(The cross-week phantom is already closed by the §4.1 per-goal
     `goal_registry FOR UPDATE` mutex held since step 7b — this re-confirm covers only drift
     between the step-8 identify read and the lock within THIS transaction, not a concurrent
     writer, which the mutex has excluded.)*
   - assert persisted target `funded_amount == p_expected_prior` at cents else RAISE (stale-prior);
   - assert `prev_amount ≤ p_new_funded_amount` (if `v_prev` exists) AND
     `p_new_funded_amount ≤ next_amount` (if `v_next` exists) at cents else RAISE (§6.4.1);
10. call-through `save_goal_funding_snapshots(p_model_year, p_week_num,
    [{goal_id, funded_amount:p_new_funded_amount, source:'correction', note:btrim(p_note)}])`
    — one in-place natural-key upsert; **no direct table write**;
11. read-back assert **exactly one** natural-key row now has the corrected amount,
    `source='correction'`, and the note; return JSONB.

### 8.3 `p_recorded_at` decision (Rev-7 grounding correction; Companion Amendment 3)
**Grounding fact.** The deployed recon RPC's `p_recorded_at TIMESTAMPTZ` is a **required
compatibility/signal parameter whose supplied VALUE the deployed RPC discards**: it validates
`p_recorded_at IS NOT NULL` (else RAISE) but then hardcodes `recorded_at = NOW()` on both the
INSERT and the `ON CONFLICT … UPDATE` (`docs/phase-5f-1-migration.sql` L520/L537/L544/L552).
`recorded_at` is **server-owned**; whenever the RPC runs, it becomes `NOW()`.

**Decision:** the public wrapper **does not expose `p_recorded_at`** (removed since Rev 4 — no
client backdating). When the wrapper calls the deployed RPC, it passes a **non-null
server-controlled compatibility value — prefer `now()` for clarity** — while documenting that the
**inner RPC owns and independently writes `recorded_at = NOW()`.** **Per-branch effect (correct):**

| Branch | Recon RPC called? | Effect on `recorded_at` |
|---|---|---|
| **New closeout (E)** | **yes** | RPC stamps **`NOW()`** — the intended initial closeout timestamp |
| **Normal-closeout identity retry (F)** | **no** | **UNCHANGED** (preserved) |
| **Half-close repair (G)** | **no** | **UNCHANGED** (preserved) |
| **Approved-reopen identity retry, empty arrays (D)** | **no** | **UNCHANGED** (preserved) |
| **Approved-reopen ambiguous retry, non-empty arrays** | **no** (GFA01 pre-call) | **UNCHANGED** (preserved) |
| **Genuine approved reopen (E)** | **yes** | RPC **re-stamps `NOW()`** — the latest reconciliation write, **NOT** the original closeout time; the original is captured in the mandatory supervised before/after evidence **before** execution |

**We do NOT claim that passing the persisted timestamp preserves it** — the deployed RPC ignores
the argument value. Preserving the original on a genuine reopen is infeasible without modifying
the deployed RPC or writing `weekly_reconciliations` directly, both prohibited (Companion
Amendment 3). Durable historical event logging is deferred to 5J.

Slice-3 client sends no `p_recorded_at` in the POST body.

### 8.4 Canonical NUMERIC finiteness predicate (Rev-4 defect fix; applies to EVERY amount)
**Grounding.** PostgreSQL `numeric` supports the special values `NaN`, `Infinity`, and
`-Infinity` (PG14+; Supabase is PG15). **`numeric` `NaN` compares EQUAL to itself** (unlike
IEEE float), so `v = v` is **TRUE** for `NaN` and **cannot** be used to detect it. There is no
built-in `isfinite(numeric)`. The canonical, text-free predicate is explicit inequality:

```sql
-- TRUE iff v is a finite, non-null numeric (rejects NULL, NaN, +Infinity, -Infinity).
-- `v = v` is deliberately NOT used: numeric NaN = NaN is TRUE in PostgreSQL.
v IS NOT NULL
  AND v <> 'NaN'::numeric            -- NaN <> NaN is FALSE  → NaN rejected
  AND v <> 'Infinity'::numeric       -- Inf <> Inf is FALSE  → +Inf rejected
  AND v <> '-Infinity'::numeric      -- -Inf <> -Inf is FALSE → -Inf rejected
```
*(For any finite `v`, each `<>` is TRUE; for `NaN`/`±Inf`, the matching clause is FALSE, so the
whole predicate is FALSE and the value is rejected. NULL short-circuits on the first clause.)*

**INLINED identically inside BOTH new functions — NO helper function is created** (Rev-5
decision). The migration still creates **exactly two** functions
(`save_weekly_closeout_with_snapshots`, `correct_goal_funding_snapshot`); rollback drops
**exactly those two**; there is no `_gf_is_finite_amount` (or any third object). Structural
validation (§9) inspects both function definitions and proves the explicit
`<> 'NaN'`/`<> 'Infinity'`/`<> '-Infinity'` rejection is present in **each**. **Cents
normalization** is `round(v, 2)` applied **after** the finiteness guard, before any comparison
or write.

**Applied consistently to every numeric entry surface:**
| Surface | non-null | not NaN/±Inf | nonnegative | cents |
|---|---|---|---|---|
| Wrapper `p_chk`,`p_sav`,`p_amx`,`p_tax`,`p_lc` | ✓ | ✓ | **no** (a balance may be negative, e.g. an AMEX liability) | ✓ |
| Each `funded_amount` parsed from `p_snapshot_rows` | ✓ | ✓ | **✓** (`goal_funding_snapshots.funded_amount ≥ 0`) | ✓ |
| Option B `p_new_funded_amount`, `p_expected_prior` | ✓ | ✓ | **✓** | ✓ |

The wrapper re-validates each `p_snapshot_rows.funded_amount` server-side (the Slice-1 client
builder is not the integrity control). Balances feed the deployed recon RPC (which does its own
checks); the wrapper's finiteness guard is defense-in-depth so a `NaN`/`±Inf` never reaches it.

### 8.5 Strict commitment-array input predicate (Rev-6; wrapper pure-input validation)
Both commitment parameters must be **actual, non-null JSON arrays** — evaluated in STEP 1c,
**before any lock or state read**, with **no coercion**:
```sql
p_new_commitments IS NOT NULL AND jsonb_typeof(p_new_commitments) = 'array'
AND p_patched      IS NOT NULL AND jsonb_typeof(p_patched)      = 'array'
```
**Rejected (RAISE, never coerced to `[]`):** SQL `NULL`; JSON `null` (`jsonb_typeof='null'`);
object (`'object'`); string (`'string'`); number (`'number'`); boolean (`'boolean'`). Only a
**literal valid JSON array** passes. Downstream, "empty" means `jsonb_array_length(x)=0` and
"non-empty" means `> 0`; **only a valid empty JSON array qualifies for empty-array identity**
(§6, §8.1 D). This closes the gap where JSON `null`/`{}`/scalar could be misread as "no
operations."

---

## 9. Validation plan (`phase-5g-1d-validation.sql`, staging-first) — inert-aware
- **Grant state = intended inert:** wrapper + Option B have **no** `authenticated`/anon/PUBLIC
  EXECUTE after the migration (and, on staging, after `-ungrant.sql`). Assert exactly that.
- After the staging temporary grant + matrix + ungrant: **prove final staging grant state ==
  intended inert production state.**
- **byte-unchanged proof** for both deployed RPCs (`pg_get_functiondef` == preflight hash);
  E1 table/RLS/grants unchanged.
- wrapper/Option B structural asserts: SECURITY DEFINER, `search_path` pinned, no dynamic SQL,
  no `EXCEPTION` handler; the reserved advisory namespace `1734501000` recorded;
- **exactly two new functions created** (assert no third/helper object added by the migration);
- **inlined finiteness proof:** inspect **each** function definition (`pg_get_functiondef`) and
  assert the explicit `<> 'NaN'`/`<> 'Infinity'`/`<> '-Infinity'` rejection text is present in
  **both** (no `_gf_is_finite_amount`);
- **per-goal mutex proof:** assert each write path contains the `goal_registry … FOR UPDATE`
  lock (wrapper: nine ids `ORDER BY id`; Option B: `id=p_goal_id`) acquired before snapshot
  state reads; and that no other object introduces a conflicting `goal_registry FOR UPDATE`.
- old reconciliation RPC direct `authenticated` EXECUTE **still present** at Slice-2 (its
  revocation is Slice-7/Gate C).

## 10. Rollback plan (`phase-5g-1d-rollback.sql`, separate approval)
- `DROP FUNCTION public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT);`
- `DROP FUNCTION public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT);`
- E1 objects + both deployed RPCs untouched; **no snapshot/recon data deleted** (wrong values
  use the correction path, never a drop). Additive rollback only. Because the inert migration
  grants nothing, rollback needs no grant restoration; if the staging temporary grant is still
  present, `-ungrant.sql` runs first.

## 11. Grant-posture dependencies (Gate C cross-reference)
Slice-2 deploys the two functions **inert (no `authenticated` EXECUTE)**. Every §G register
revocation (rows 1,3,4,5,6,7,8) and the two new-function activation grants (rows 10,11) are
**Slice-7 activation** actions, each with its own separately-approved exact-signature grant
change + staging rehearsal + before/after matrix + rollback + wrapper-succeeds + bypass-fails
proofs. Slice-2 also conducts the `repair_commitments_for_week` (row 2) caller/dependency
audit and drafts Gate C options — **no grant change to it in Slice 2.**

---

## 12. Test additions
**Static (`test_regression.js`):** none beyond the committed Slice-1 builder (wrapper logic is
server-side).

**DB smoke (`phase-5g-1d-rls-smoke-*`, staging):**
- wrapper calls (not inlines) both RPCs; snapshot failure aborts recon; recon failure writes
  no snapshot; exception not swallowed;
- opening-anchor missing/incomplete/wrong-week/wrong-source → raise; **tolerates
  wewe_rccl/wewe_dcl at wk5**;
- exact nine-set missing/extra/dup/count/returned-ID mismatch → rollback;
- **branch-specific sequence:** normal next-week / earlier-incomplete-blocks; repair targets
  **earliest** incomplete week / later blocked; reopen latest-week-only; fully-closed retry on
  a **historical** week allowed; **prove each state reaches exactly one branch**;
- source pinned; source-injection reject; monotonic decrease reject;
- **strict `p_mode`** NULL/unknown/extra → raise **pre-inner-call**;
- **owner ordering:** non-owner `approved_reopen` rejected **before** any anchor/recon/snapshot/
  sequence/payload-state read (correction 5);
- **identity (empty-array):** identical empty-array retry → idempotent success **with no inner
  RPC call and no audit-field change**; changed recon or snapshot value (empty arrays) →
  hard-stop;
- **non-empty ambiguous retry (fallback, §6) — must prove ALL of:** (a) **neither inner RPC is
  called**; (b) **no persisted state changes** (recon, commitments, snapshots, timestamps);
  (c) the wrapper raises the **specific `ERRCODE='GFA01'` / `HINT=REQUIRES_SUPERVISED_ADJUDICATION`**
  signal (not a generic error); (d) a harness assert that this result is **distinguishable from
  a definite failure** (different `code`); (e) **ordinary automatic retry is NOT attempted** —
  the path terminates in the adjudication signal;
- **approved_reopen retry/adjudication (§8.1):** (i) **first genuine reopen, empty commitments**
  → applies once (recon RPC called, snapshot RPC NOT called); (ii) **committed-response-lost retry,
  empty commitments** (persisted == submitted) → **idempotent reopen success, NO inner call**,
  `recorded_at` + audit unchanged; (iii) **committed-response-lost retry, non-empty commitments** →
  **`GFA01`, NO inner call, no state change**; (iv) **changed reopen request** (persisted ≠
  submitted) → treated as a genuine new reopen (recon RPC once), **not mistaken for identity**;
  (v) **snapshot `source`/`note` unchanged** in all reopen paths;
- **timestamp behaviour by branch (Rev-7, §8.3 / Companion Amendment 3) — must prove:** new
  closeout receives a **server-generated `recorded_at` (`NOW()`)**; a **genuine reopen produces a
  LATER server-generated `recorded_at`** (re-stamped `NOW()`, strictly greater than the original);
  the **original `recorded_at` is captured in the supervised pre-reopen evidence**; **empty-array
  identity retry, half-close repair, and GFA01 adjudication each leave `recorded_at` UNCHANGED**
  (no recon RPC call); and the suite **never claims or tests that passing the old timestamp
  controls the inner RPC** (the deployed RPC ignores the argument value);
- **strict commitment-array validation (Rev-6, §8.5) — for BOTH `p_new_commitments` and
  `p_patched`:** SQL `NULL` → reject; JSON `null` → reject; `{}` → reject; string → reject; number
  → reject; boolean → reject; `[]` → **accepted**; a valid **non-empty array** → **accepted on
  first execution**, but on an already-applied ambiguous retry follows the `GFA01` rule; **prove no
  value is coerced to `[]`**;
- **Option B:** success; missing-row reject; **anchor-week (wk5) reject**; wrong-year reject;
  non-eligible-goal reject; null/NaN/±Infinity/negative amount reject; empty/whitespace note
  reject; **stale `expected_prior` reject**; nearest lower/higher bound reject; call-through
  (no table write); in-place single row; source=correction;
- **concurrency matrix (§4):** double-submit same week; normal-closeout vs Option B; reopen vs
  correction; repair vs retry — **exactly one outcome, no lost update**;
- **Option B adjacent-week deadlock matrix (Rev-4):** (a) two Option B on the **same** week →
  serialize (advisory + per-goal mutex), second sees the new value ≠ its `expected_prior` →
  deterministic stale-prior hard-stop; (b) two Option B on **adjacent** weeks for the **same
  goal** (N and N+1) → **serialize on the per-goal `goal_registry` mutex; no deadlock**,
  deterministic bound outcome, no lost update; (c) two Option B on **non-adjacent** weeks, same
  goal → still serialize on the per-goal mutex (safe, low-frequency); different goals →
  independent;
- **cross-week per-goal serialization (Rev-5, §4.1) — must prove ALL:** (i) **Option B Week N
  racing a normal closeout Week N+1 for the same goal** → serialize on the goal's
  `goal_registry FOR UPDATE`; the later writer re-reads committed state; **no phantom-bound
  violation**; (ii) **Option B Week N racing a half-close repair Week N+1 for the same goal** →
  same serialization, no phantom, no lost update; (iii) a **new neighbouring row that would
  violate the corrected amount's bound** cannot be inserted concurrently (the mutex excludes it;
  after the first commits, the second's bound check sees it and hard-stops deterministically);
  (iv) **no deadlock** across advisory + registry locks; (v) **different goals remain
  independently executable** (disjoint registry rows);
- **advisory-lock behavior (decision 3):** two closeouts on **different** weeks do **not**
  block each other (both acquire distinct `year*100+week` keys and proceed); two operations on
  the **same** week **serialize** (the second waits on `pg_advisory_xact_lock(1734501000, …)`);
- **numeric-validation matrix (§8.4) — for EVERY numeric surface** (wrapper p_chk/p_sav/p_amx/
  p_tax/p_lc; each p_snapshot_rows funded_amount; Option B p_new_funded_amount/p_expected_prior):
  **NULL → reject; NaN → reject** (proves `v=v` would have wrongly passed it); **Infinity →
  reject; -Infinity → reject;** **negative →** reject for funded/Option-B amounts, **accept for
  balances** (a balance may be negative); **excess fractional precision → normalized to cents**
  (e.g. round-half behavior asserted) before compare/write;
- **recorded_at (Rev-7, §8.3):** new closeout stamps server `NOW()`; a **genuine reopen re-stamps
  `NOW()`** (deployed RPC ignores the argument); **identity retry, half-close repair, and GFA01
  adjudication leave it unchanged** (RPC not called); a returned `reopened_at` (if present) is
  never written to any row;
- **grant lifecycle:** inert state (no authenticated EXECUTE) after migration; staging
  temp-grant enables the matrix; post-ungrant state == intended inert; anon/unauth reject;
- **atomicity:** for every forced failure, assert **neither half persists**.

**E2E (`e2e.js`, `opts.tags`):** Slice-3 client behaviors — added in Slice 3, not Slice 2.

---

## 13. Decisions — RESOLVED (Adam, 2026-07-11)
1. **Commitment identity (§6): conservative fallback APPROVED.** Automatic idempotency is
   **empty-commitment-arrays only**; non-empty ambiguous retry → supervised adjudication via the
   `GFA01`/`REQUIRES_SUPERVISED_ADJUDICATION` signal; no inner RPC replayed automatically;
   atomicity intact. Recorded in **companion amendment 2** (narrows §B.1; the cleared amendment
   is not edited in place).
2. **Reopen `recorded_at` (§8.1/§8.3): superseded by decision 9 (Rev-7).** The deployed RPC
   ignores `p_recorded_at` and always stamps `NOW()`, so a genuine reopen **re-stamps `NOW()`**;
   only no-op/identity/repair/GFA01 paths (no RPC call) leave it unchanged. A non-persisted
   `reopened_at` may be returned for feedback only. See decision 9 + Companion Amendment 3.
3. **Advisory-lock namespace `1734501000`: REGISTERED** (repo scan clean, §4). Both functions
   call `pg_advisory_xact_lock(1734501000, p_model_year*100 + p_week_num)` before any
   state-dependent read; row locks ascending `week_num`.
4. **Option B `p_expected_prior`: REQUIRED** (non-default, non-null, finite, ≥0, cents),
   compared against the `FOR UPDATE`-locked target row at the same cents precision (§8.2).
5. **Per-goal snapshot-mutation mutex (Rev-5): `goal_registry` row `FOR UPDATE`** (preferred
   mechanism) — one stable FK-referenced row per goal, no conflicting lock order (verified);
   wrapper locks all nine `ORDER BY id`, Option B locks its one; closes the cross-week phantom.
6. **Finiteness predicate INLINED in both functions (Rev-5)** — no helper; migration creates
   exactly two functions; rollback drops exactly two; validation proves the rejection in each.
7. **`approved_reopen` retry/adjudication (§8.1):** reopen does not blindly re-call the
   recon RPC — empty-array identical retry → idempotent success (no inner call); non-empty
   ambiguous retry → `GFA01`; genuine change → apply once; snapshots never changed. CA2 clarified
   to cover both `normal_closeout` and `approved_reopen`.
8. **Strict commitment-array input guard (Rev-6, §8.5):** `p_new_commitments`/`p_patched` must be
   real non-null JSON arrays (`jsonb_typeof='array'`); no coercion of NULL/`null`/`{}`/scalars.
9. **Timestamp grounding correction (Rev-7, §8.3 / Companion Amendment 3):** the deployed recon
   RPC **ignores `p_recorded_at` and always stamps `recorded_at = NOW()`**; `p_recorded_at` is a
   **required compatibility/signal parameter whose supplied value is discarded**. The public
   wrapper does **not** expose it; it passes `now()` for signature compatibility only. A **genuine
   reopen RE-STAMPS `NOW()`** (original kept in supervised evidence); no-op/identity/repair/GFA01
   paths preserve `recorded_at` because the RPC is not called. The earlier "preserve on genuine
   reopen" requirement is narrowed accordingly.

---

## 14. Non-execution / stop
Executes nothing. The eight `docs/phase-5g-1d-*.sql` / `.md` artifacts are **AUTHORED but
UNEXECUTED and UNTRACKED** (Rev-8 corrections uncommitted, pending Fable); no SQL run, no grant
changed, no browser wiring, no push, no staging/production action. **Next step (gated on Adam
after Fable review):** pin the staging `system_identifier`, then the staging execution sequence
(§3.1) under separate approval; then the production inert deploy (Slice 6). E1 DDL immutable.
Gates B–E open. Prior commits `57bc9c1`/`0c10784`/`fbf37d3`/`c858205`/`6959bab` remain unpushed
and unmodified.
