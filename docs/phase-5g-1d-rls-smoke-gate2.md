# Phase 5G-1D Slice 2 — RLS/RPC Smoke, Gate 2 (real Auth → JWT → PostgREST)

**STAGING ONLY** (`herndon-fos-staging`, `pkwotgqivgaapwuqgwqb`). Authored, **not executed**.
Follows the 5G-1/5G-1C-2 Gate-2 pattern: a real authenticated caller hits the wrapper and
Option B through PostgREST, so the actual grant/RLS/definer path is exercised (the SQL editor
bypasses RLS). Requires the staging temporary grant (`phase-5g-1d-staging-grant.sql`) applied,
and reverted (`phase-5g-1d-ungrant.sql`) afterward. **Balance-free** — no household amounts are
recorded here; use clearly-synthetic staging values.

## Execution package (authored, not executed)
The staging execution package that runs this cleared matrix is `docs/phase-5g-1d-gate2-runbook.md`
(orchestrator) plus `docs/phase-5g-1d-gate2-*.sql` (per-sub-phase capture/assert/mutation artifacts) and
`docs/phase-5g-1d-gate2-exec-template.sh` (the PostgREST call bodies, placeholder-only). The matrix below
is authoritative and unchanged; the runbook maps every row to its artifact, caller, week, and stop point.

## Preconditions
- Staging has a seeded, clearly-synthetic reconciled **Week-5 opening anchor** (nine eligible
  `opening_anchor` rows) — mirrors E2 structure with fake values.
- Throwaway staging identities: an **owner** (maps `is_owner()=true`) and a **household_admin**
  (Wendy-equivalent, `is_owner()=false`), plus **anon**.
- Temporary grant applied; base URL + anon key + each identity's access token available locally
  (never committed).

## Call shape
`POST {SUPA_URL}/rest/v1/rpc/save_weekly_closeout_with_snapshots` and
`.../rpc/correct_goal_funding_snapshot`, `Authorization: Bearer <token>`, JSON body of the
`p_*` named params. Parse `message||hint||details||code` from the response.

## Matrix (record pass/fail; balance-free)

| # | Caller | Call | Expected |
|---|---|---|---|
| G2-1 | anon | wrapper `normal_closeout` wk6 | 401/403 or `42501` (no anon path) |
| G2-2 | unauthorized (no app_users row) | wrapper wk6 | reject (`42501`) |
| G2-3 | owner | wrapper `normal_closeout` wk6, empty commit arrays, nine rows | **success**; 9 `reconciliation` rows at wk6; `recorded_at` server-stamped |
| G2-4 | owner | repeat G2-3 identical (empty arrays) | **idempotent success**, `idempotent:true`, no inner call, `recorded_at` **unchanged** |
| G2-5 | owner | repeat wk6 with a **non-empty** `p_new_commitments` | **`code=GFA01`**, `hint=REQUIRES_SUPERVISED_ADJUDICATION`; no state change (distinct from a generic failure) |
| G2-6 | owner | wrapper wk6 with a **changed** balance (empty arrays) | hard-stop (route to reopen/correction) |
| G2-7 | owner | wrapper `normal_closeout` wk8 (skip wk7) | hard-stop (non-contiguous) |
| G2-8 | household_admin | wrapper `normal_closeout` wk7 | **success** (Wendy may normal-close) |
| G2-9 | household_admin | wrapper `approved_reopen` wk7 | reject (`42501`, `is_owner()=false`) |
| G2-10 | owner | `approved_reopen` wk7 latest, **changed** recon, **empty** arrays | **genuine reopen** applies once; snapshot RPC not called; `recorded_at` **re-stamped NOW()** (later than before); original captured in the pre-reopen evidence |
| G2-10b | owner | `approved_reopen` wk7, changed recon, **non-empty** commitment array | **reject** — reopen may not carry commitment operations (route to supervised commitment-repair; item A). No state change. |
| G2-11 | owner | `approved_reopen` wk7, identical recon, empty arrays | idempotent reopen success, no inner call, `recorded_at` unchanged |
| G2-12 | owner | `approved_reopen` wk7, identical recon, **non-empty** arrays | `code=GFA01`, no inner call, no change |
| G2-13 | owner | `approved_reopen` on an **older** (non-latest) week | reject |
| G2-14 | owner | Option B: correct wk7 goal within bounds, valid `expected_prior` | **success**; one in-place `source='correction'` row |
| G2-15 | owner | Option B: **stale** `expected_prior` | reject (stale-prior) |
| G2-16 | owner | Option B: below preceding / above following bound | reject |
| G2-17 | household_admin | Option B any | reject (`42501`) |
| G2-18 | owner | half-close (1..8 present): remove one synthetic eligible row, re-run wrapper wk | **repair** completes only the missing row; `recorded_at` unchanged; later week blocked until repaired (see detailed procedure below) |
| G2-18b | owner | half-close **zero snapshots** (item B): reconciliation-only week with 0 eligible rows, run wrapper wk | **repair** writes all nine `reconciliation` rows; `recorded_at` unchanged; distinct from the branch-H corrupt (snapshots-without-recon) case |
| G2-19a | owner | monotonicity, prior = **`opening_anchor`** (Week-5 anchor is the latest prior): submit Week-6 goal **below** the anchor value | **reject**; equal/increase accepted |
| G2-19b | owner | monotonicity, prior = **`reconciliation`** (a closed earlier week is the latest prior): submit next week **below** that reconciliation value | **reject**; equal/increase accepted |
| G2-19c | owner | monotonicity, prior = **`correction`** (an Option-B–corrected earlier row is the latest effective prior): submit next week **below** the corrected value | **reject** (proves the check uses the effective row regardless of source); equal/increase accepted |
| G2-19d | owner | broken chain: remove a synthetic Week-5 **eligible anchor** row, then run the wrapper for a later week | **hard-stop, no state change** — the STEP-3 opening-anchor guard fires first ("anchor incomplete"); the wrapper's NULL-prior "broken snapshot chain" check is **deeper defense-in-depth and is UNREACHABLE in normal operation** (a complete Week-5 anchor means every eligible post-anchor goal always has a prior). *No "no-prior accepted" scenario exists — the anchor guarantees a prior.* |

## Half-close repair — detailed procedure (item D)
1. **Pre-state capture:** record the full wk-N reconciliation row (all balances + `recorded_at`),
   the wk-N `cash_commitments` rows, and the wk-N eligible snapshot rows (goal_id/funded/source/note).
2. **Induce the half-close:** remove exactly ONE synthetic eligible snapshot row (for G2-18) or all
   nine (for G2-18b) — a deliberate, recorded synthetic deletion of a known row.
3. **Execute repair:** run the wrapper for wk-N with the same reconciliation values + full nine-row
   snapshot payload, empty commitment arrays.
4. **Assert restore:** the removed row(s) are re-created with the **correct value and
   `source='reconciliation'`**; the complete eligible nine is present.
5. **Assert no unrelated change:** the wk-N reconciliation balances + **`recorded_at` unchanged**;
   wk-N `cash_commitments` unchanged; all OTHER eligible rows (and the two `wewe_*` rows) unchanged;
   no other week touched.
6. **Blocked-advance:** confirm wk-(N+1) cannot close until wk-N is fully repaired.

## Timestamp assertions (Rev-7 / Companion Amendment 3)
- New closeout (G2-3): `recorded_at` is a server value (`NOW()`), not client-supplied.
- Genuine reopen (G2-10): `recorded_at` is **strictly later** than the pre-reopen value; the
  original is retained only in the supervised before/after evidence.
- Identity retry (G2-4/G2-11), GFA01 (G2-5/G2-12), reopen-with-commitments reject (G2-10b),
  half-close repair (G2-18/G2-18b), and monotonic reject (G2-19): `recorded_at` **unchanged**
  (recon RPC not called, or the call is rejected before it runs).
- The suite never asserts that passing an old timestamp controls the inner RPC — the deployed
  RPC ignores the argument and stamps `NOW()`.

## Atomicity (classification depends on the starting state)
- **Existing-state changed-value failures / adjudications** — the week was **already closed** by a
  prior test, so assert **NO persisted state changed**: pre-call reconciliation balances,
  **`recorded_at`**, `cash_commitments` rows, and snapshot rows (values/source/note) all
  byte-for-byte identical after the failed/adjudicated call. **Includes G2-6** (a changed-balance
  resubmit of the already-closed Week 6 from G2-3 → hard-stop route-to-reopen; it is **NOT** a
  new-closeout failure), plus G2-5, G2-10b, G2-12, G2-13, G2-15, G2-16, G2-19.
- **Pre-write rejections** (G2-7 skip, G2-1/G2-2 auth, strict-input rejects) hard-stop **before any
  inner call** → nothing was ever attempted; assert no row created for the target week.
- **GFA01** (G2-5/G2-12): raised before any inner call → capture pre-state, catch `code=GFA01`,
  diff = unchanged.
- **Genuine new-closeout mid-transaction rollback (G2-20a create / G2-20b patch)** is the real
  all-or-nothing proof — the reconciliation RPC runs (persisting a synthetic commitment create or
  patch) and the snapshot step then fails; the transaction must roll back **both** halves.

### G2-20 — genuine new-closeout atomic rollback injection (Issue 3)
Proves that when the snapshot step fails **after** the reconciliation RPC has run, the single wrapper
transaction rolls back the reconciliation row **and** the commitment mutation, leaving **no** snapshot
rows. Split into **G2-20a (commitment CREATE)** and **G2-20b (commitment PATCH)** so each commitment
effect is proven non-vacuously. Safe synthetic failure mechanism — a temporary trigger on the staging
`goal_funding_snapshots` table; **no deployed RPC is modified.**

**Shared setup (each sub-test; owner session):**
- **Pre-setup existence gate:** assert `public._gf_atomic_test_fail` and `_gf_atomic_test_fail_trg`
  do **not** already exist (`to_regproc`/`pg_trigger`); if either exists, **STOP the suite** — never
  continue while a test object is present.
- Install the fail trigger:
  ```sql
  CREATE FUNCTION public._gf_atomic_test_fail() RETURNS trigger LANGUAGE plpgsql AS $f$
  BEGIN IF NEW.funded_amount = 424242.42 THEN RAISE EXCEPTION 'ATOMIC-TEST synthetic failure'; END IF; RETURN NEW; END $f$;
  CREATE TRIGGER _gf_atomic_test_fail_trg BEFORE INSERT ON public.goal_funding_snapshots
    FOR EACH ROW EXECUTE FUNCTION public._gf_atomic_test_fail();
  ```
- The wrapper call always carries the nine snapshot rows with **one eligible goal's
  `funded_amount = 424242.42`** (synthetic sentinel; passes validation + monotonicity as an
  increase), so the snapshot INSERT fires the trigger AFTER the reconciliation RPC has run.

**Shared teardown (ordered, each sub-test):**
1. `DROP TRIGGER IF EXISTS _gf_atomic_test_fail_trg ON public.goal_funding_snapshots;` (trigger first)
2. `DROP FUNCTION IF EXISTS public._gf_atomic_test_fail();` (helper second)
3. **Assert both absent** (`to_regproc('public._gf_atomic_test_fail') IS NULL`; trigger gone from
   `pg_trigger`); also remove the G2-20b pre-seeded synthetic commitment.
- **Emergency cleanup** (operator disconnect mid-test): re-run the two idempotent `DROP … IF EXISTS`
  as owner before anything else. Staging test scaffolding only; no deployed/production object touched.

#### G2-20a — commitment CREATE rollback
- **Pre-state:** fresh post-anchor week **N** (no recon, no snapshots); capture `cash_commitments`
  (the create target `expected_item_id='__ATOMIC_TEST_WD__'` must be **absent**).
- **Call:** new closeout wk **N** with the sentinel snapshot row **AND** a non-empty
  `p_new_commitments` containing one clearly-synthetic **create** (`__ATOMIC_TEST_WD__`). Recon RPC
  creates the recon row + the synthetic commitment; the snapshot INSERT then trips the trigger → abort.
- **Assert:** no wk-N `weekly_reconciliations` row; no wk-N snapshots; **`__ATOMIC_TEST_WD__` still
  absent** (create rolled back); no unrelated `cash_commitments`/other-week change vs pre-state.

#### G2-20b — commitment PATCH rollback
- **Pre-seed** a single clearly-synthetic committed row `__ATOMIC_TEST_PATCH__` at a fresh week **N**
  (owner insert, recorded); capture its exact pre-state field values.
- **Call:** new closeout wk **N** with the sentinel snapshot row **AND** a non-empty `p_patched`
  that **modifies** `__ATOMIC_TEST_PATCH__` (e.g. amount/status change). Recon RPC applies the patch;
  the snapshot INSERT then trips the trigger → abort.
- **Assert:** no wk-N `weekly_reconciliations` change; no wk-N snapshots; **`__ATOMIC_TEST_PATCH__`
  fields identical to pre-state** (patch rolled back); no unrelated change.

## Teardown
Run `phase-5g-1d-ungrant.sql`; re-run `phase-5g-1d-validation.sql` to prove the restored inert
grant state equals the intended production inert state; remove throwaway identities; leave
staging clean. **Production untouched.**
