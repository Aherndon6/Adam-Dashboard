# AU-11 Step 6C-D3 — Design Addendum (Step 7C) — 2026-07-27

Authored on the Step 7B preflight evidence (`phase-au11-6c-d3-staging-preflight-evidence-2026-07-27.md`) + committed repository-source inspection. **No DDL/RPC authored here; no implementation.** Rulings marked **[OWNER DECISION]** require an explicit owner ruling before D3 authoring. Frozen surfaces are untouched; the composite *wraps* the closeout. Production, engine, and Wendy IRA holds remain in force. D3 is **staging-only**; production install is a separate later phase (6C-G).

## Repository-source confirmations (facts, not recommendations)
- **RC-1 Register writer contract** (`index.html:8204` write body; `phase-5e-migration.sql:28-56` DDL). On create the client sends `transaction_date, payee, memo, amount (signed), category_key, cleared (bool)`, and on insert `account_key, source='manual'`. Column reality:
  - `cleared BOOLEAN NOT NULL DEFAULT FALSE` — **client-set** (true/false); persisted = the client value.
  - `reconciled BOOLEAN NOT NULL DEFAULT FALSE` — **omitted by the client**; persisted = **FALSE** (NOT NULL, never NULL). The client has no path that sets it true.
  - `posted_date DATE` (nullable, no default) — **omitted**; persisted = **NULL**.
  - `transfer_pair_id UUID` (nullable, no default) — **omitted**; persisted = **NULL** (dormant).
  - `source TEXT NOT NULL DEFAULT 'manual'` — set `'manual'`.
  - `amount NUMERIC(12,2) NOT NULL` CHECK(`amount <> 0`) — signed, exactly 2 decimals.
  ⇒ Positive evidence signals available on real rows: **`cleared`** (client-settable true) and **`transaction_date`**. **`reconciled` cannot be mandatory evidence**: the create/edit body omits it and every committed writer leaves it FALSE (migrations seed it FALSE; no committed path sets `transactions.reconciled=true` — the `reconciled` variable at `index.html:3336` is *week*-reconciliation state, not the column), so a legitimate newly-created, cleared Register debit can remain `reconciled=false`, and requiring `reconciled=true` would reject valid evidence. `reconciled` is therefore **advisory only**, regardless of whether some later workflow ever sets it true. `posted_date`/`transfer_pair_id` are NULL. The predicate uses `account_key`+`amount`+`cleared`+`transaction_date` only.
- **RC-2 Week calc** (`getCalWeek:3444`; `WD:909`): `Cal = 22 + model_week`; model wk 1 = 2026-06-07; 7-day weeks. WD `dates` are **hand-authored display strings**; `runModel` operates on week *numbers*. No machine week→date function exists in the client, and **no calendar/week table or resolver exists in the DB** (E1/E2 empty; `weekly_reconciliations` has only `recorded_at`, no week-date columns).
- **RC-3 Frozen wrapper** (`index.html:3588`): `save_weekly_closeout_with_snapshots(p_week_num,p_model_year,p_chk,p_sav,p_amx,p_tax,p_lc,p_balance_basis,p_new_commitments,p_patched,p_snapshot_rows,p_mode,p_expected_count)`; success = `ok=true ∧ mode='normal_closeout' ∧ week_num=n ∧ snapshot_count=9`. `GFA01`/`REQUIRES_SUPERVISED_ADJUDICATION` guards re-closeout of a fully-closed week (supervised, never auto-retry). Body md5 `e2a112b376dc32c43e1615e4a4abf24a`; SECURITY DEFINER; owner postgres; `search_path=public, pg_temp`; staging EXECUTE anon/authenticated = false.
- **RC-4 D2 lock order** (`staging-rpcs.sql:85→94`): authz (`is_owner()`) → pure-parameter validation → **acquire `au11_disc:` advisory lock** → all table reads/writes. **D2 uses no row locks**; the D3 composite adds evidence-row `SELECT … FOR UPDATE` as a narrow carve-out (§S3(a)/§D) — this RC-4 statement describes D2 only.
- **RC-5 No live reservation routing**: AU-11 dormant, zero live callers; the client does not read `discretionary_reservation_batches` or block on active reservations. ⇒ Client routing is **D4**.
- **RC-6 Schema sufficiency (corrected)**: clear-transition columns and the `status` enum (incl. `cleared`) already exist ⇒ no widening for the clear transition itself. **However, the schema has NO durable matched-transaction attribution**: `bank_reference` is free TEXT (not a FK, not unique — I3), and **no `cash_commitments` column references `transactions(id)`** (grep: no `REFERENCES public.transactions`). ⇒ D3 **DOES** need a narrowly-scoped additive attribution column + unique index (§E, decision **D-9**) — **Checkpoint A is non-empty**.

---

## A. D3 scope boundary
**RULING:** D3 = the composite closeout RPC `close_week_with_reservations_v1` that, in one transaction, (1) **calls and captures the result of** the **unmodified** frozen wrapper — passing the caller's real `p_new_commitments`/`p_patched` through unchanged (§S4) — (2) retires `initiated`/`bank_pending` reservations that have **mandatory, exact, unambiguous** Register evidence (`→ cleared`), (3) **carries forward** unposted active reservations unchanged, (4) **BLOCKs** on ambiguous/partial evidence, (5) retires the batch to `retired` when all rows terminal. D3 also introduces the additive **`cash_commitments.cleared_transaction_id`** attribution column + partial unique index (D-9) that makes one-transaction-one-commitment durable. **Deferred to D4:** client wiring/routing (RC-5); `mark_bank_pending`/`stale_review` producers; disposition of `initiated` reservations that will not clear (cancelled-at-bank / paid-from-other) **[OWNER DECISION D-3]**. Default: defer disposition + producers to D4.

## B. Composite function contract
- **Name:** `close_week_with_reservations_v1`.
- **Arguments:** the frozen wrapper's exact params **passed through unchanged** (RC-3: `p_week_num, p_model_year, p_chk, p_sav, p_amx, p_tax, p_lc, p_balance_basis, p_new_commitments, p_patched, p_snapshot_rows, p_mode, p_expected_count` — the composite applies **no** filtering/rewriting/defaulting/suppression) **+** `p_retire JSONB` = an array of `{commitment_id UUID (required), transaction_id UUID (optional/nullable)}` objects (identity proof + full type in **§S1**). The caller supplies real commitment arrays on a first closeout and empty arrays on a retirement-only replay (§S4). **No caller-supplied date bounds** — the composite derives the week window internally from `p_week_num` via the pinned epoch (§F).
- **Return (jsonb):** `{ ok, mode, week_num, snapshot_count, retired:[{commitment_id,goal_id}], carried:[{commitment_id,reason}], blocked:[], batch_status, replayed:boolean }`. `blocked` is a **stable response-shape field that is structurally empty (`[]`) on every successful return** — all blocking conditions are exception paths (RAISE), never a populated success field (contract A).
- **Frozen-wrapper capture + verify:** `v_wrapper_result := public.save_weekly_closeout_with_snapshots(<caller-supplied pass-through, arrays unchanged>);` then verify the **captured** result (`ok=true ∧ mode='normal_closeout' ∧ week_num=p_week_num ∧ snapshot_count=9`); any deviation → RAISE (whole txn rolls back); GFA01 propagated (§S2). Wrapper byte-unchanged (md5 `e2a112b376…`).
- **Replay/idempotency:** see §H.

## C / §7 Authorization contract (complete)
- **SECURITY DEFINER:** yes. **Owner:** postgres. **search_path:** `''` (empty) — matches the D2 lifecycle RPCs, and is **stronger** than the frozen wrapper's `public, pg_temp`. Acceptable only because **every** referenced object is schema-qualified: `public.save_weekly_closeout_with_snapshots`, `public.cash_commitments`, `public.discretionary_reservation_batches`, `public.transactions`, `pg_catalog.pg_advisory_xact_lock`/`hashtextextended`, `auth.uid()`. `pg_catalog` remains implicitly searched first (built-ins available), so empty `search_path` prevents any `pg_temp`/`public` object **shadowing** a built-in or a qualified reference — the reason it is preferred over `public, pg_temp` here.
- **EXECUTE grants (staging):** `anon=false`; `authenticated=false` in the resting state — granted to `authenticated` only during the D3 test matrix, then revoked to inert (mirrors 5G-1D + matches the frozen wrapper's current staging posture, RC-3).
- **Authorization helper: [OWNER DECISION D-1]** `can_write_financials()` (default) vs `is_owner()`.
- **household_admin execution:** `can_write_financials()` admits both owner and household_admin (financial-writer role), so **under the default, Wendy (household_admin) could execute the composite** — but the evidence gate is the safety: she can only retire owner-created reservation rows that already carry an exact cleared Register debit; she cannot create capacity. Under `is_owner()`, household_admin is refused entirely.
- **RLS interaction:** the composite runs as its owner (postgres) under SECURITY DEFINER, so it bypasses RLS on `cash_commitments`/`transactions`/`discretionary_reservation_batches` for its *internal* reads/writes; the in-function authz gate (`can_write_financials()`/`is_owner()`) enforces caller authority. Client *direct* SELECTs remain governed by existing RLS (unchanged). The frozen wrapper it **invokes** also runs as its owner. **Security/attack-surface:** passing the commitment arrays through adds **no authority** beyond the existing frozen wrapper — the composite applies the same authorization posture before calling it, the frozen wrapper remains the **sole authority** for validating and applying its commitment inputs, and D3 does **not** reinterpret or mutate the nine-goal contract, commitment phases, or runModel-derived payload.
- **Direct frozen-wrapper invocation:** unchanged — staging EXECUTE for authenticated is false, so callers cannot invoke `save_weekly_closeout_with_snapshots` directly in staging; the composite reaches it via a captured call as owner. In prod the wrapper stays independently granted for normal closeout; the composite adds a second, retirement-aware entry that also runs it. No reduction of the wrapper's existing accessibility.
- **Future D4 client-routing requirement:** D4 must add client wiring to call the composite (not the plain closeout) when an active reservation batch exists, and to route/block the UI accordingly. Not in D3.

## D. Locking contract
- **Exact key:** `pg_advisory_xact_lock(hashtextextended('au11_disc:'||p_model_year||':'||p_source_account, 0))`, `p_source_account` fixed to `truist_checking` (only admissible key `au11_disc:2026:truist_checking`) — the as-built D2 key (RC-4); the stale D0 `disc_goal_reservation:` prefix is not used.
- **Order:** the advisory lock is acquired after authz + pure-parameter validation and strictly precedes all mutable reads/writes; the full step order is the single authority in **§ Canonical execution order**.
- **Two distinct lock kinds:** D2's lifecycle RPCs take **no** row locks; the **D3 composite additionally takes `SELECT … FOR UPDATE` on the selected evidence `transactions` rows** (§S3(a)) — a narrow D3 carve-out to prevent evidence mutation during attribution. The **advisory lock** provides single-flight serialization against `create`/`mark_initiated`/`void_scheduled` (identical `au11_disc:` key); the **transaction-row locks** provide evidence immutability. They serve different purposes and both are held for the transaction.

## E. Register evidence predicate (fully specified; RC-1)
For a reservation row `c` (`amount_cents` INT > 0, positive cents) being retired, a candidate `transactions` row `t` **matches** iff ALL hold:
1. **account key:** `t.account_key = <authoritative checking key>` **[OWNER DECISION D-2]** (default: the single `accounts.key='truist_checking'`).
2. **amount (canonical rule, §S5):** `t.amount < 0 AND c.amount_cents > 0 AND (t.amount * 100) = (- c.amount_cents::numeric)`. `t.amount` is `NUMERIC(12,2)` so `t.amount * 100` is an exact NUMERIC integer — **no floating-point, no rounding step, no tolerance, no approximate matching**; malformed/unsupported values fail closed.
3. **cleared:** `t.cleared = true` (required; the only client-reliable settled signal, RC-1).
4. **week window (inclusive both ends):** `t.transaction_date >= week_start AND t.transaction_date <= week_end`, where `[week_start, week_end]` is derived internally (§F).
5. **not previously attributed:** `t.id` is not already bound as the `cleared_transaction_id` of any existing `cleared` commitment (durable attribution, below) — a transaction attributed by a prior retirement is excluded from candidacy, and the **DB enforces this even if the query check is bypassed**.

**Fields deliberately NOT used in matching:** `posted_date` (NULL, RC-1), `reconciled` (advisory — a legit cleared debit can be `reconciled=false`, RC-1), `transfer_pair_id` (NULL/dormant), `category_key`, `payee`, `memo`, `source`. (`payee`/`category_key` may be surfaced as advisory display in the result, never as match criteria.)

**Durable attribution (ruling D-9 — the existing schema has NO matched-transaction attribution).** `bank_reference` is free TEXT (not a FK, not unique); no `cash_commitments` column references `transactions(id)`. An inferred query-only exclusion cannot prevent one transaction retiring two commitments across separate calls. **RULING A (adopted):**
- **Field:** `cash_commitments.cleared_transaction_id UUID` (nullable) + FK + a **new independent 3-part lifecycle CHECK** (`chk_au11_cleared_txn_attribution`) + partial unique index — **exact DDL, invariant, migration order, concurrency, amount rule, and rollback in §E2**. The committed **D1 reservation-shape CHECK is NOT modified**.
- **Transaction PK used:** `transactions.id` (UUID PK).
- **Transaction-side uniqueness:** partial UNIQUE index `uix_au11_cleared_txn ON cash_commitments(cleared_transaction_id) WHERE cleared_transaction_id IS NOT NULL` ⇒ one transaction attributes to **at most one** commitment, DB-enforced.
- **Atomic attribution write:** the retirement `UPDATE` sets `status='cleared'` **and** `cleared_transaction_id=t.id` together in one statement (same txn as the wrapper pin).
- **Replay:** a commitment already `cleared` with `cleared_transaction_id=t.id` → idempotent success (no re-UPDATE; matched by the §H replay classification).
- **Different-commitment attribution:** a second commitment attempting the same `t.id` → unique violation → deterministic hard-fail (`transaction_already_attributed`), full rollback.
- **Fixture/teardown coverage (§K):** seed one transaction, retire commitment A, attempt to retire commitment B with the same transaction → expect the unique-violation BLOCK; teardown clears the attribution with the fixture; the final-state verifier asserts the index during D3 and zero attribution residue after teardown.
**Ruling B (rejected):** narrowing D3 to avoid evidence-based clearing where reuse can't be prevented would remove D3's core purpose. **One Register transaction can never retire two separate commitments — the unique index is the durable guarantee, not the query condition.**

**Cardinality rules:**
- **One transaction ↔ at most one reservation:** a matched transaction is consumed and cannot satisfy a second reservation in the same or a later closeout (rule 5).
- **One reservation ↔ exactly one transaction:** a reservation is satisfied by a **single** exact debit. Aggregate/split matching is unsupported (§ partial-posting).
- **Zero candidates** → carry the reservation forward (still active; never force-void).
- **Exactly one candidate** → retire that reservation in one atomic UPDATE: `status='cleared'`, **`cleared_transaction_id=t.id`** (durable attribution), `cleared_date`, `reflected_model_week=resolved_model_week=p_week_num`, `resolution_type='cleared'`. The partial unique index makes a second call attributing the same `t.id` fail with a deterministic unique violation (`transaction_already_attributed`).
- **Multiple candidates** → **lawful resolution via §S1 nomination**: an optional `transaction_id` on the retirement entry *identifies* which candidate (never overrides the predicate). No nomination → `ambiguous_multiple_match`; nomination present exactly once in the composite-computed candidate set → use it; nomination absent from the set → `nominated_transaction_not_eligible`. A cleared-and-reflected debit for an active reservation omitted from `p_retire` → RAISE `omitted_cleared_row` (no silent skip). Full rules in **§S1**.

## Partial-posting rule (explicit)
**RULING (recommended default accepted):** one commitment requires **one exact, unambiguous Register debit**. Aggregate matching and partial clearing are **unsupported** in D3. Any partial, multi-transaction, or otherwise ambiguous candidate set returns **BLOCK** (RAISE). **No commitment splitting** occurs. (Alternative — aggregate/partial matching — is rejected for D3: it would require splitting a reservation's `amount_cents` across debits, a materially larger evidence and validation surface better suited to a later slice.)

## E2. Durable attribution — exact database & migration contract (ruling D-9)

**Attribution-state invariant (full 3-part).** Enforced by a NEW independent CHECK on `cash_commitments` (the committed D1 reservation-shape CHECK is untouched):
```sql
ALTER TABLE public.cash_commitments
  ADD CONSTRAINT chk_au11_cleared_txn_attribution CHECK (
    CASE
      WHEN commitment_source = 'au11_reservation' AND status = 'cleared'
        THEN cleared_transaction_id IS NOT NULL
      ELSE cleared_transaction_id IS NULL
    END
  ) NOT VALID;
```
- non-AU-11 rows → ELSE → `cleared_transaction_id IS NULL`.
- AU-11 `status='cleared'` → `cleared_transaction_id IS NOT NULL`.
- AU-11 in **every** non-cleared status → ELSE → `cleared_transaction_id IS NULL`.
NULL handling: the CASE always yields TRUE/FALSE (never UNKNOWN); a NULL `commitment_source` falls to ELSE (requires NULL attribution — fail-closed). It is **complementary** to the D1 shape CHECK (which governs `reservation_batch_id`/`goal_id`/`destination_account_ref`/`bank_reference`/`bank_submitted_at`) — the two never overlap on `cleared_transaction_id`, and the D1 constraint is not altered.

**FK contract.**
```sql
ADD CONSTRAINT fk_au11_cleared_txn FOREIGN KEY (cleared_transaction_id)
  REFERENCES public.transactions(id) ON UPDATE CASCADE ON DELETE RESTRICT NOT VALID
```
Referenced table/column: `public.transactions(id)` (stable UUID PK). **ON UPDATE CASCADE** (PK immutable in practice; matches the accounts-FK pattern). **ON DELETE RESTRICT** — deleting a transaction that is a reservation's cleared evidence would erase the settlement basis of a terminal `cleared` commitment, breaking the audit chain and the withhold↔settle invariant; RESTRICT forces the operator to resolve the reservation before removing its evidence. **NOT DEFERRABLE** — the constraint must fire at statement time so the composite maps the violation to a deterministic error and rolls back immediately (a deferred check would surface only at COMMIT).

**Partial unique index (intentionally global).**
```sql
CREATE UNIQUE INDEX uix_au11_cleared_txn
  ON public.cash_commitments (cleared_transaction_id)
  WHERE cleared_transaction_id IS NOT NULL;
```
Global by design: the lifecycle CHECK already prohibits any non-AU-11 row from carrying a non-null `cleared_transaction_id`, so this global partial index effectively scopes to AU-11 `cleared` rows while giving the strongest guarantee — one `transactions.id` attributes to **at most one** commitment, DB-enforced. `transactions.id` is the correct, stable UUID PK (`gen_random_uuid()`).

**Migration sequence (Checkpoint A) — each step fails closed.**
A. `ALTER TABLE cash_commitments ADD COLUMN cleared_transaction_id UUID;` — additive nullable, no default; brief ACCESS EXCLUSIVE, no table rewrite.
B. add FK **NOT VALID** — does not validate existing rows; brief lock.
C. add attribution CHECK **NOT VALID**.
D. `CREATE UNIQUE INDEX uix_au11_cleared_txn … WHERE …` — a partial unique index (no NOT VALID concept; errors on any duplicate — none exist).
E. `ALTER TABLE … VALIDATE CONSTRAINT fk_au11_cleared_txn;` — SHARE UPDATE EXCLUSIVE; **errors if any existing row violates** (all NULL → passes).
F. `ALTER TABLE … VALIDATE CONSTRAINT chk_au11_cleared_txn_attribution;` — **errors if any existing row violates** the invariant.
G. explicit invariant queries — all must return **0**: (i) non-AU-11 with `cleared_transaction_id IS NOT NULL`; (ii) AU-11 `cleared` with `cleared_transaction_id IS NULL`; (iii) AU-11 non-cleared with `cleared_transaction_id IS NOT NULL`; plus index present, FK `convalidated`, CHECK `convalidated`.
H. only then `CREATE OR REPLACE` the composite RPC.
**Fail-closed property:** if any of A–G errors, or G is nonzero, **H never runs** ⇒ no attribution/clearing path exists until the schema is provably correct.

**Concurrency-safe attribution (composite sequence).**
Focused view only — the single authoritative step order is §I, Canonical execution order, steps 1–15. This section adds only the attribution-conflict contract: on unique_violation, map the failure to transaction_already_attributed only when the violated object is uix_au11_cleared_txn; otherwise re-raise the original error. Roll back the full transaction on any attribution conflict. The shared au11_disc:<model_year>:<source_account> advisory-lock namespace serializes every attribution-capable AU-11 path, and the partial unique index remains the hard database backstop if that serialization is ever bypassed.

**Amount comparison (NUMERIC, no float).** A candidate `t` matches `c` on amount iff:
```
t.amount < 0                                          -- outflow (NUMERIC(12,2), CHECK <> 0)
AND c.amount_cents > 0                                -- positive cents (D2 guarantees 1..100000000)
AND (t.amount * 100) = (- c.amount_cents::numeric)    -- exact integer-cents equality; NO division
```
`t.amount * 100` is an exact NUMERIC (scale-0 value) because `amount` has scale 2; comparing to `-c.amount_cents::numeric` is exact — **no floating-point, no tolerance, no rounding ambiguity beyond `NUMERIC(12,2)`**. Malformed inputs fail closed: `t.amount=0` is impossible (CHECK); a positive `t.amount` fails `<0`; a non-integer product cannot equal an integer.

**Rollback classification (Checkpoint G) — dependency order (reverse of creation).**
1. DROP the composite RPC.
2. DROP the attribution CHECK `chk_au11_cleared_txn_attribution` (additive; nothing to restore — the D1 shape CHECK was never modified).
3. DROP the partial unique index `uix_au11_cleared_txn`.
4. DROP the FK `fk_au11_cleared_txn`.
5. `DROP COLUMN cleared_transaction_id`.
6. verify D1/D2/frozen definitions intact + zero residue.
**Fail-closed:** rollback must **ABORT** if any **non-fixture** row has `cleared_transaction_id IS NOT NULL` (live attribution present) — bare-dropping the column would erase real cleared evidence. Explicitly: **ordinary bare-drop rollback is safe only before any non-fixture attribution has occurred**; **after live attribution, rollback requires an evidence-preservation migration and separate approval.**

## F. Week-window contract (honest)
- **Authoritative week algorithm:** model epoch = **2026-06-07** (model wk 1 start), 7-day weeks; week N = `[epoch + 7*(N-1), epoch + 7*(N-1) + 6]`; `Cal = 22 + N`. This is documented in `getCalWeek` + encoded (as display strings) in `WD`.
- **Does the DB independently calculate the bounds? NO.** No calendar/week table, no resolver function, and `weekly_reconciliations` carries no week-date columns (RC-2). The DB cannot derive the window today.
- **Duplication/drift risk (stated plainly):** there is **no existing machine week→date algorithm** in either the client or the DB — WD holds hand-authored display strings and `runModel` uses week *numbers*. Therefore whatever D3 builds is the **first** machine implementation; I do **not** claim "no second algorithm." The real risks are (a) divergence between the D3 epoch constant and the hand-authored WD strings, and (b) future divergence if the client later grows its own window computation.
- **Equivalence proof (all 31 weeks):** a D3 validation artifact enumerates weeks 1..31, computes `[start,end]` from the pinned epoch, and asserts equality to the parsed WD display-string ranges for every week. This runs at authoring/validation time (not a runtime dependency).
- **RULING:** the composite derives the window **internally** from a **single pinned epoch constant** (`DATE '2026-06-07' + 7*(p_week_num-1)` … `+6`); the caller passes only `p_week_num` (already a wrapper param). No caller-supplied bounds ⇒ one authority, no caller drift. **A canonical shared helper** (`model_week_window(week_num)`) **should be created later** if/when the client needs machine windows, so both surfaces share one definition; until then the composite's pinned epoch, proven equivalent to WD across all 31 weeks, is the sole authority. **[OWNER DECISION D-6]** confirms internal-derivation-only vs any caller-supplied variant.
- **Model-year bound (ruling D-10):** the pinned epoch is the **2026 v6 model only**. The composite **requires `p_model_year = 2026`**; any other value → RAISE `unsupported_model_year` (deterministic; the 2026 epoch is **never** silently applied to another year). The 31-week equivalence proof applies only to 2026 v6; future model years require an explicitly approved canonical epoch mechanism (and likely the shared `model_week_window()` helper). This matches D2's existing `p_model_year=2026` guard.

## G. Reservation lifecycle & terminal/batch rules (precise)
- **Terminal statuses:** `cleared`, `voided`.
- **Active / withholding (non-terminal):** `scheduled`, `initiated`, `bank_pending`, `stale_review`. **Anomalies (D-5):** `planned` and `carried_unresolved` are **unsupported** on an AU-11 reservation row in D3 (D2 has no producer for either) → **hard-fail** unless a producer/transition contract is explicitly added.

| State | Composite behavior |
|---|---|
| `scheduled` | carry forward (not submitted); never force-void |
| `initiated` / `bank_pending` | `→ cleared` iff exactly-one-match evidence (§E/§S1); else carry forward |
| `bank_pending` ambiguous | **resolve via §S1 nomination**, else `ambiguous_multiple_match` |
| `stale_review` | carry forward; no D3 producer, no auto-clear |
| `planned` / `carried_unresolved` | **anomaly → hard-fail** (D-5); no D3 producer exists |
| `cleared` / `voided` | terminal; untouched |

**Batch retirement:**
- all commitments already terminal, batch `active` → **retire batch** (`→ retired`).
- batch already `retired`, all rows terminal (consistent) → **idempotent success / no-op** (replay).
- active batch with all commitments terminal → retire batch.
- `retired` batch with a non-terminal commitment → **INCONSISTENT → hard-fail (BLOCK)**, whole txn rolls back (must be impossible; treated as a controlled anomaly).
- partial retirement (some rows terminal, some active) → batch stays `active`; retire only the posted rows.
- any inconsistent batch/commitment state → hard-fail with diagnostic; atomic rollback.

## H. Replay contract — state matrix
| Scenario | Outcome |
|---|---|
| First successful execution | **success** (retire matched rows, retire batch if all terminal) |
| Exact replay after full success (same `p_retire`, rows already `cleared` w/ matching evidence, batch retired) | **idempotent success** (`replayed=true`, no error) |
| Wrapper completed but retirement not completed (impossible within one txn; only visible if a prior attempt aborted mid-way) — on retry, wrapper re-runs (or GFA01 adjudication) and retirement proceeds | **success** on the retry (single-txn atomicity means no committed half-state exists to reconcile) |
| Batch already retired **consistently** (all rows terminal) | **idempotent success** |
| Batch already retired **inconsistently** (a non-terminal row remains) | **hard failure** (BLOCK, anomaly) |
| No eligible rows (nothing to retire; all carry forward) | **success** with empty `retired[]` (closeout still pins the week) |
| Retirement count mismatch (guarded UPDATE affects fewer still-active rows than the verified target, not explained by prior clearance) | **hard failure** (RAISE `retirement_count_mismatch`, rollback) |
| Evidence changed between attempts (a debit that matched now missing/duplicated) | **BLOCK** (re-validation fails: zero → carry / multiple → ambiguous) |
| Duplicate closeout prevention (week already fully closed, resubmitted with changes) | **GFA01 supervised adjudication** (inherited from the frozen wrapper, RC-3) — never an auto-retry |

**Idempotent-replay definition:** `p_retire` equals exactly the already-`cleared` set for `(model_year, week_num)` with matching evidence. **Hard-abort conditions:** wrapper contract fail; evidence missing on a claimed retirement; ambiguous multiple-match; omitted cleared-and-reflected row; count mismatch not explained by prior clearance; week-window/epoch mismatch; unsupported model year; transaction already attributed; inconsistent batch state; not authorized; lock timeout.

## I. Canonical execution order + failure atomicity (single authority)
This is the **one authoritative order**; §A/§B/§D/§S2/§S3 reference it and do not restate a second version. Single transaction; the advisory lock and the evidence-row `FOR UPDATE` locks are both held to commit.
1. authorize caller (`can_write_financials()`/`is_owner()` per D-1);
2. validate pure scalar inputs (incl. `p_model_year=2026` else `unsupported_model_year`);
3. validate `p_new_commitments`/`p_patched` **only** for the frozen-wrapper input contract — **without modifying them** (they pass through unchanged);
4. validate the complete `p_retire` input set (duplicate commitments, duplicate transaction nominations, malformed UUIDs, unknown commitments, commitments outside the active batch — §S1);
5. derive + validate the supported model year + week window (pinned epoch, §F);
6. acquire the `au11_disc:2026:truist_checking` advisory lock;
7. load + validate the active reservation batch and commitment rows;
8. compute the eligible evidence candidate set (§E predicate);
9. resolve automatic or nominated evidence per commitment (§S1 matching table);
10. lock each selected `transactions` row with `SELECT … FOR UPDATE` in a **deterministic order** (by `transactions.id`) to avoid deadlock;
11. re-evaluate the complete §E predicate on the locked rows (`evidence_changed` on drift);
12. call the frozen wrapper with the **caller-supplied pass-through** commitment arrays (unchanged);
13. capture + verify the wrapper result (§S2), incl. GFA01 propagation;
14. atomically set `cleared_transaction_id` + transition each approved commitment (`status='cleared'`, `cleared_date`, `reflected/resolved_model_week`, `resolution_type='cleared'`, `resolved_by`/`resolved_at`);
15. verify exact affected-row counts (`GET DIAGNOSTICS` == target);
16. evaluate omitted/unclaimed reservation rules (`omitted_cleared_row`);
17. retire the batch only if its terminal-state contract is satisfied (§G);
18. run final invariants (S3(b) post-attribution consistency);
19. return the structured result.
**Ordering rationale (evidence locks before the wrapper — steps 10–11 before 12):** the frozen wrapper touches `weekly_reconciliations`/`goal_funding_snapshots`/`cash_commitments` but **not** the specific `transactions` rows locked in step 10, so holding those row locks across the wrapper call introduces no deadlock with the wrapper; the advisory lock already serializes concurrent composite calls. This keeps evidence validated-and-locked as one atomic decision spanning the wrapper. (Wrapper-before-locks was considered and **rejected**: it would validate evidence against an unlocked image a concurrent Register edit could change between the wrapper commit and attribution.)
**Atomicity:** the wrapper is a **captured call, not `PERFORM`**; it does **not** commit (stock PostgreSQL, no autonomous txn) ⇒ pin + snapshots + retirement + batch transition commit together or **roll back atomically**. No exception handler swallows a wrapper/retirement error. An injected failure after the wrapper call but before retirement rolls the wrapper's pin + snapshots back too. Verified by a D3 failure-injection checkpoint.

## J. Result and error contract
- **Success (deterministic):** `{ ok:true, mode:'normal_closeout', week_num, snapshot_count:9, retired:[…], carried:[…], blocked:[], batch_status, replayed:bool }`.
- **Errors via RAISE**, distinct ERRCODE + message per class: `not_authorized`, `unsupported_model_year`, `lock_timeout`, `week_window_mismatch`, `evidence_missing`, `nominated_transaction_not_eligible`, `ambiguous_multiple_match`, `omitted_cleared_row`, `duplicate_commitment_entry`, `duplicate_transaction_nomination`, `unknown_commitment`, `commitment_not_in_active_batch`, `evidence_changed`, `transaction_already_attributed`, `retirement_count_mismatch`, `inconsistent_batch_state`, `wrapper_contract_fail`. GFA01 is **not** in this list — it is propagated per §S2. No ambiguous silent success — a 2xx is not proof; the caller must check `ok` and re-read persisted state (mirrors RC-3).

## K. D3 staging fixture matrix
Writer-contract-faithful synthetic `transactions` (RC-1): `account_key`=checking, `amount` negative = reservation dollars (exact cents), `cleared=true`, `transaction_date` in-window, `payee`/`source='manual'`, **`posted_date` NULL / `reconciled` FALSE / `transfer_pair_id` NULL** (faithful to the client), all tagged `[STAGING-FIXTURE]`; plus a reconciled basis week + nine snapshots + a batch with `initiated`/`bank_pending` rows. **Candidate/nomination (§S1):** zero/one/multiple candidates without nomination; zero/one/multiple with nomination; valid selection from multiple; nominated id outside the candidate set; wrong-account nomination; amount mismatch; date-window mismatch; `cleared=false`; already attributed to the **same** commitment (idempotent); attributed to **another** commitment (`transaction_already_attributed`); duplicate commitment entries (`duplicate_commitment_entry`); duplicate transaction nomination across two commitments (`duplicate_transaction_nomination`); unknown commitment; commitment outside the active batch.
**Base predicate:** exact match; no match; wrong account; amount mismatch (±1 cent); outside week (inclusive-edge ±1 day); `reconciled=false` present but ignored; NULL `posted_date` proves non-requirement; each active state (`scheduled`/`initiated`/`bank_pending`/`stale_review`) and each anomaly (`planned`/`carried_unresolved` → hard-fail).
**Wrapper (§S2):** normal first success; idempotent replay (empty arrays); repaired; GFA01 non-ok (propagated, no retirement); incorrect mode; incorrect `week_num`; incorrect `snapshot_count`; missing key; wrong JSON type; null result; wrapper exception.
**Concurrency/immutability (§S3):** concurrent amount edit; date edit; account change; `cleared` true→false; delete before attribution; FK-RESTRICT deletion after attribution; predicate drift before the locked read (`evidence_changed`); post-attribution mismatch caught by the S3(b) invariant; an unrelated unique violation is **not** misclassified as `transaction_already_attributed`.
**Pass-through / replay (§R2):**
- **R2-1 first-closeout pass-through equivalence** — for identical authorized inputs, the frozen wrapper called **directly** vs **through the composite** produce field-equivalent commitment effects (patched commitments, newly inserted commitments, reserve commitments, snapshots, reconciliation outputs); the composite adds **only** the documented D3 evidence-attribution + retirement effects.
- **R2-2 lawful retirement-only replay** — week already closed; wrapper commitment arrays **empty**; pinned reconciliation inputs match; `p_retire` non-empty; wrapper returns the lawful idempotent result (L308); **no** duplicate snapshots/commitments; remaining eligible reservations retire atomically.
- **R2-3 invalid closed-week resubmission** — week already closed; at least one wrapper commitment array **non-empty**; wrapper raises **GFA01**; composite preserves the machine-readable GFA01 contract; **no** attribution/retirement/batch transition occurs.
Synthetic `transactions` are writer-contract-faithful (`cleared=true`, `transaction_date` in-window, `amount` negative exact cents, `posted_date` NULL / `reconciled` FALSE / `transfer_pair_id` NULL), tagged `[STAGING-FIXTURE]`. Ledger-tracked fixture creation + asserted teardown + final zero-residue (incl. zero attribution residue) verification (mirrors D2). Basis week / sentinel chosen to avoid collision with the removed D2 fixture.

## L. Production preflight requirements (gate 6C-G, later)
Before any production authorization: real prod `transactions` **quality checks** (prod is non-empty — validate the `cleared`+exact-amount+`transaction_date` predicate against real data, quantify multiple-match ambiguity, confirm `reconciled`/`posted_date` population in prod differs or not from staging); **confirm the authoritative account key** in prod; **function/hash drift checks** (frozen wrapper md5 `e2a112b376…` + pinned `1bfde751…`/`154231b3…`); zero-residue checks; **no deployment until all required production-read gates pass**. Production install stays a separate owner authorization.

---

## S1. Ambiguous-evidence resolution — p_retire identity + nomination
**Retirement-entry identity (approach A, proven unique):** the entry names the immutable **`cash_commitments.id`** — `id UUID PRIMARY KEY DEFAULT gen_random_uuid()` (`phase-5f-1-migration.sql:49`), so it is database-unique by definition. `batch_digest+goal_id` is **not** used (batch_digest lives on `discretionary_reservation_batches`, not on `cash_commitments`; the only cash-side reservation uniqueness is `uix_au11_batch_goal (model_year, reservation_batch_id, goal_id)`).
**Exact type:** `p_retire JSONB` = array of objects `{ "commitment_id": <uuid, required>, "transaction_id": <uuid, optional/nullable> }`. Missing/malformed `commitment_id` → validation error; `transaction_id` absent or JSON `null` = "no nomination".
**Matching rules (composite independently computes the full eligible candidate set; `transaction_id` is evidence *identification*, never a predicate override):**
| candidate count | no `transaction_id` | matching `transaction_id` | non-matching/absent `transaction_id` |
|---|---|---|---|
| 0 | `evidence_missing` | — | `nominated_transaction_not_eligible` |
| 1 | use the single candidate | use it | `nominated_transaction_not_eligible` |
| >1 | `ambiguous_multiple_match` | use the nominated candidate | `nominated_transaction_not_eligible` |
The nominated transaction must **independently** satisfy every §E predicate (authoritative account; exact negative cents amount; `cleared=true`; `transaction_date` in the canonical supported week; not attributed to another commitment; correct id/type). A transaction already attributed **to the same commitment** is idempotent only if every other terminal invariant agrees; attributed **to a different commitment** → hard-fail (`transaction_already_attributed`). Selection among multiple valid candidates is permitted under `can_write_financials()`; the final attribution persists `cleared_transaction_id`, the commitment id, and the **existing** audit columns `resolved_by=auth.uid()` + `resolved_at=now()` + `resolution_type='cleared'` (`phase-5f-1-migration.sql:106-118`; server-derived; no new audit fields invented).
**Input-set validation (deterministic errors before the wrapper/mutation; the unique index is only the final backstop):** reject duplicate commitment entries (`duplicate_commitment_entry`), the same commitment named twice, the same `transaction_id` nominated for two commitments (`duplicate_transaction_nomination`), malformed UUIDs, unknown commitments (`unknown_commitment`), commitments outside the active batch (`commitment_not_in_active_batch`), and nominations for commitments not eligible for retirement. This reconciles with `omitted_cleared_row`: ambiguity now has a lawful resolution path (nomination) **without** weakening the rule that a genuinely cleared-and-reflected reservation must be addressed.
**Nominated vs unclaimed (cross-reference):** §S1 governs commitments **present in `p_retire`** (automatic + nominated evidence resolution); the carry/omission rule (§E/§G) governs **active reservations not claimed in `p_retire`**. A valid-but-ambiguous posted reservation is **not permanently trapped** — it may be included in `p_retire` with an eligible `transaction_id`. **Omission is not a lawful substitute** for resolving known evidence: a cleared-and-reflected debit for an active reservation left out of `p_retire` → `omitted_cleared_row`.

## S2. Frozen-wrapper result capture + accepted-mode contract (from committed code)
The composite **captures** the result: `v_wrapper_result jsonb := public.save_weekly_closeout_with_snapshots(...)`, and validates the contract **before** any attribution/transition/retirement. Required: result is a JSON object; keys present with correct types; `ok=true`; `mode` ∈ the composite's accepted set; `week_num = p_week_num`; `snapshot_count = 9`.
**Wrapper return-branch matrix (committed `phase-5g-1d-migration.sql`):**
| Scenario | Committed behavior | Composite handling |
|---|---|---|
| first successful closeout | `{ok:true, mode:'normal_closeout', week_num, snapshot_count:9}` (L294) | accept → proceed to retirement |
| exact idempotent replay (identical recon, **empty** arrays) | `{ok:true, mode:'normal_closeout', idempotent:true, …, snapshot_count:9}` (L308) | accept → finish outstanding retirement |
| half-close repair | `{ok:true, mode:'normal_closeout', repaired:true, …, snapshot_count:9}` (L358) | accept |
| approved_reopen (idempotent/reopened) | `mode:'approved_reopen'` (L207/L234) | **not** expected — composite passes `p_mode='normal_closeout'`; a returned `approved_reopen` ⇒ `wrapper_contract_fail` |
| already-closed week + **non-empty** commitments | RAISE `ERRCODE='GFA01'` HINT `REQUIRES_SUPERVISED_ADJUDICATION` (L311) | propagate (see below) — the composite passes the caller's arrays through; a replay supplies **empty** arrays (idempotent branch), so GFA01 fires when a closed week is resubmitted with non-empty commitments (genuine adjudication) |
| malformed/contradictory/unexpected result | — | `wrapper_contract_fail` |
| wrapper raises (non-GFA01) | exception | propagate; full rollback |
The composite passes `p_mode='normal_closeout'`, so its **accepted set = `{normal_closeout}`** (with optional `idempotent`/`repaired` flags); `approved_reopen` is a different operation not invoked here. `normal_closeout` is therefore **not** assumed to be the wrapper's only mode — it is the only mode the composite's `normal_closeout` call may lawfully return.
**GFA01 propagation (ruling B):** on GFA01, the composite performs **no** attribution/transition/retirement, rolls back the full transaction, and re-raises preserving `ERRCODE='GFA01'` + HINT `REQUIRES_SUPERVISED_ADJUDICATION` (and the wrapper JSON in `DETAIL`) so the client's adjudication signal survives. `wrapper_contract_fail` is used **only** for malformed/contract-invalid responses, never for GFA01.
**approved_reopen is not a retirement-authorizing result:** D3 retirement is authorized **only** after a verified `normal_closeout` result. An `approved_reopen` returned from the composite's `normal_closeout` invocation is a `wrapper_contract_fail`. After a separate owner-approved reopen and re-pin has occurred, retirement may proceed **later** through a lawful identical `normal_closeout` replay (idempotent branch) — not via the reopen itself.

## S3. Evidence protection during & after attribution
**S3(a) locked candidate recheck (advisory lock ≠ Register row lock).** Sequence: authorization → pure validation → acquire `au11_disc:2026:truist_checking` → load+validate active batch/commitments → compute candidate set → identify auto/nominated candidate → **`SELECT … FROM public.transactions WHERE id = <chosen> FOR UPDATE`** → **re-evaluate the full §E predicate against the locked row** → verify unattributed (or idempotently attributed to the same commitment) → **[the frozen-wrapper capture+verify occurs here, per the canonical order steps 12–13]** → atomic `UPDATE cash_commitments SET status='cleared', cleared_transaction_id=t.id, resolved_by, resolved_at, resolution_type='cleared', …` → `GET DIAGNOSTICS` exactly one row. This is a focused view of canonical steps 1–15 (§I), not a competing order. Prefer a single locked SELECT that both identifies and validates. If the candidate changed before the locked read → deterministic `evidence_changed` / `nominated_transaction_not_eligible` + rollback.
**Phantom-insert posture (A — bounded residual, stated honestly):** `SELECT … FOR UPDATE` prevents update/delete of the chosen row but **does not** prevent a *new* matching transaction being inserted concurrently. Since the current Register writer does **not** share the AU-11 advisory lock, D3 adopts posture **A**: automatic matching is decided on the committed candidate set visible at the locked decision point; a later-inserted transaction does **not** invalidate the chosen transaction's evidence. This is recorded as an **explicit bounded residual**. (Posture B — a Register-side advisory lock / stronger isolation — is deferred as a separately approved protected-surface change.) **We do not claim `FOR UPDATE` alone prevents a new candidate from appearing.**
**Target-index-specific 23505:** on `unique_violation`, inspect the violated constraint/index name; map to `transaction_already_attributed` **only** when it is `uix_au11_cleared_txn`; re-raise any unrelated unique violation unchanged.
**S3(b) post-attribution consistency invariant.** The FK preserves transaction *identity*, not *content*. Added to Checkpoint-A validation, the D3 final-state verifier, fixture verification/teardown, and the 6C-G production preflight: for every attributed reservation assert `commitment_source='au11_reservation'` ∧ `status='cleared'` ∧ the transaction exists ∧ `account_key` authoritative ∧ `amount` still the exact inverse cents ∧ `cleared=true` ∧ `transaction_date` still inside the commitment's `resolved_model_week` window ∧ attributed to only that commitment. Any mismatch = **hard control failure**. **D3 detects but does not completely prevent** later Register content mutation (see D-11).

## S4. Partial-retirement / replay reconciliation (from committed wrapper behavior)
Resolved from the wrapper's committed idempotency (L308) + `(model_year,week_num,goal_id)` upsert, **not** policy:
| # | State | Outcome |
|---|---|---|
| 1 | week not closed, all requested retirements valid | wrapper closes (L294) → retire the set |
| 2 | week closes, all commitments retire | success; batch → `retired` |
| 3 | week closes, only a lawful subset has in-week evidence | success; retire the posted subset; batch stays `active` |
| 4 | replay, week already closed, batch still active | wrapper returns `normal_closeout, idempotent:true` (L308, identical recon + empty arrays) → **no duplicate snapshots** → finish any now-postable retirement |
| 5 | replay, all requested already terminal | idempotent success; no-op retirement |
| 6 | batch retired but wrapper state inconsistent | `inconsistent_batch_state` hard-fail |
| 7 | wrapper reports duplicate/already-closed with non-empty arrays | GFA01 → propagate (§S2) |
| 8 | wrapper GFA01 | propagate; no retirement |
| 9 | evidence changes between attempts | `evidence_changed` / re-validation (zero→carry, >1→ambiguous/nomination) |
**Three distinct invocation modes (canonical):**
1. **First closeout** — the caller supplies the **real** `p_new_commitments`/`p_patched`; the composite passes them through **unchanged**; the wrapper performs its normal closeout + commitment patch/insert phases; reservation retirement follows **only after** the captured wrapper result passes the D3 contract.
2. **Retirement-only replay** — the caller supplies **empty** `p_new_commitments`/`p_patched`; `p_retire` may still be non-empty (a separate D3 input); the pinned reconciliation/closeout inputs must match the existing closed state; the wrapper's committed idempotent branch (L308) proves the same week/recon and returns `normal_closeout, idempotent:true, snapshot_count=9` with **no duplicate snapshots** (goal-keyed upsert); the composite then processes remaining eligible retirements.
3. **Invalid resubmission** — **non-empty** arrays for an already-closed week follow the frozen wrapper's **GFA01** path; the composite preserves/propagates GFA01; **no** retirement occurs.
**Answers:** partial retirement **is** allowed (temporal — reservations clear in the week their debit's `transaction_date` falls; a batch may clear across successive weekly closeouts). `p_retire` must include **every** reservation whose matching cleared debit falls in **that** week (else `omitted_cleared_row`); reservations with no in-week debit carry. The batch **can** remain active after the wrapper commits. The composite **never simulates, bypasses, or replaces** the wrapper's replay rules — it always calls the wrapper and relies on the wrapper's idempotency as the sole authority for "already closed." The combination "wrapper returns `normal_closeout`" + "partial retirement completed on replay" is **demonstrably supported** by L308; no separate retirement-only mode is required for D3.

## S5. Canonical decision register (D-1 … D-11) + canonical invariants
| # | Title | Classification | Evidence basis | Recommended ruling | Alternative | Consequence | Owner action required? |
|---|---|---|---|---|---|---|---|
| D-1 | composite authorization | owner policy | F1/F3 helpers | `can_write_financials()` | `is_owner()` | can_write admits household_admin (Wendy), evidence-gated | **Yes** |
| D-2 | authoritative evidence account | resolved by evidence; ratify | C3M/P2_C3AGG | `accounts.key='truist_checking'` (1 row) | any of 14 keys | wrong key ⇒ all matches false-negative | Ratify |
| D-3 | producer/disposition scope | architectural scope | RC-5, D2 | defer new producers/disposition to D4 | fold into D3 | scope creep | **Yes** |
| D-4 | partial/aggregate evidence | design ruling | §E/partial-posting | exactly one full debit; no aggregation/split/partial | aggregate matching | larger evidence surface | confirm |
| D-5 | anomalous AU-11 states | design/control | B4 enum | `planned` **and** `carried_unresolved` are unsupported anomalies for AU-11 reservations in D3 → hard-fail unless a producer/transition contract is added | stamp/produce them | new lifecycle to validate | **Yes** |
| D-6 | week-window source | resolved architecture | RC-2/E1-3 | internal 2026-only derivation from pinned epoch | caller bounds | drift | confirm |
| D-7 | replay/idempotency | design ruling | §S2/§S4 (updated) | wrapper-idempotency-based; composite always calls wrapper; accept `normal_closeout` (idempotent/repaired); GFA01 propagated | separate retirement-only mode | not needed given L308 | confirm |
| D-8 | grants & fixture posture | design ruling | RC-3 | resting-inert grants; complete staging fixtures | — | — | confirm |
| D-9 | durable attribution | **scope-gating prerequisite** | §E2 | approve attribution + retain scope | reject → redesign narrowing evidence-clearing | D3 unsafe without it | **Yes (gating)** |
| D-10 | model-year support | owner bounded-scope | RC-2 / D2 guard | 2026 only; else `unsupported_model_year` | support other years | unproven epoch | **Yes** |
| D-11 | post-attribution immutability | residual-risk owner ruling | S3(b) | **detect** in D3; prohibit silent repair/reassign; defer Register edit/delete blocking (trigger/protected-surface) to D4; any detected mismatch = hard operational hold requiring evidence-preservation correction | add mutation-prevention now (expands into protected Register surface, separate approval) | detection-only residual | **Yes** |

**Canonical amount rule (everywhere):** `t.amount < 0 AND c.amount_cents > 0 AND (t.amount * 100) = (- c.amount_cents::numeric)`. `transactions.amount` is `NUMERIC(12,2)`; **no floating-point, no tolerance, no approximate/rounded matching**; malformed values hard-fail; `amount_cents` must be a positive integer within the supported range (D2 guarantees 1..100000000).
**Canonical lifecycle-attribution CHECK (always TRUE/FALSE, never UNKNOWN):** the §E2 CASE returns `x IS NULL` / `x IS NOT NULL` in both branches — both are two-valued (never UNKNOWN) — so the CHECK is total. **`commitment_source` is `NOT NULL`** (`phase-5f-1-migration.sql:52`), so no NULL-source row can exist; the ELSE branch (which requires `cleared_transaction_id IS NULL`) would in any case fail-close a hypothetical NULL-source row rather than admit it via three-valued logic. Invariant: non-AU-11 → NULL; AU-11 `cleared` → NOT NULL; AU-11 non-cleared → NULL.
**Cleared irreversibility:** `cleared` is **terminal and irreversible** in D3 (consistent with the 5F terminal-immutability guard). A mistaken attribution is **not** corrected by reverting `status`; correction requires an evidence-preservation migration or a separately approved correction operation.

## S6. Provenance / migration precision
**Wrapper baseline:** md5 `e2a112b376dc32c43e1615e4a4abf24a` is the **first formally pinned D3 baseline** for `save_weekly_closeout_with_snapshots` (a pinned contract, not merely an observation); the D3 final-state verifier and 6C-G preflight enforce it.
**CREATE INDEX method:** the partial unique index has **no NOT VALID phase**. **Staging:** plain `CREATE UNIQUE INDEX` (transactional, brief stronger lock; the table is small/zero AU-11 rows). **Production (6C-G, later):** the method (plain vs `CREATE INDEX CONCURRENTLY` — which **cannot** run inside a transaction block) is decided at the production preflight from the then-current `cash_commitments` row count + lock-risk evidence; plain `CREATE INDEX` in prod requires explicit small-table/lock-window evidence.
**AF-2 rollover inventory (add):** pinned 2026 epoch (2026-06-07, 7-day weeks); `unsupported_model_year` for `p_model_year<>2026`; the 31-week equivalence scope is 2026 v6 only; **a newly approved canonical epoch source is required before any 2027 support.**

## Proposed D3 checkpoint sequence (staging; mirrors D2)
Preflight (done 7A/7B) → **A schema (NON-EMPTY, D-9): the 8-step additive sequence in §E2 — add column → FK NOT VALID → attribution CHECK NOT VALID → partial unique index → VALIDATE FK → VALIDATE CHECK → invariant queries (=0) → then composite. The committed D1 shape CHECK is untouched. Bare-drop rollback valid only before any non-fixture attribution (§E2 rollback)** → B composite RPC (this contract) → C fixture (§K) → D functional matrix (§E/§G/§H truth table + 31-week window equivalence + failure injection) → E concurrency (composite vs create/void/composite on `au11_disc:`) → F asserted teardown → G rollback/reversibility → H clean reapply → I mechanically-enforced final-state verifier (D1+D2+D3 installed incl. `cleared_transaction_id` column + `fk_au11_cleared_txn` (valid) + `chk_au11_cleared_txn_attribution` (valid) + `uix_au11_cleared_txn` index, D1 shape-CHECK unchanged, frozen md5 intact incl. `e2a112b376…`, fixture absent, zero residue incl. zero attribution residue, **S3(b) post-attribution consistency invariant holds for every attributed reservation**, owner integrity-asserted, email-anchored, no UUID) → execution record → commit/push (owner-gated, UUID-hygiene from the start).

**D-9 is scope-gating, not an implementation preference:** either (a) **approve durable attribution and retain the proposed D3 evidence-clearing scope** (adds the §E2 contract), or (b) **reject it** — which requires a substantive D3 **redesign** that removes or sharply narrows evidence-based clearing (D3 cannot safely clear on evidence without the durable one-transaction-one-commitment guarantee).

**D3 is not implementation-ready** until the owner rulings (D-1…D-11, with D-9 scope-gating) are made, this addendum is re-reviewed, Fable reviews the evidence, and implementation is explicitly authorized.

## Owner Rulings Ledger (D-1 … D-11)
Additive record of owner decisions; does not alter any design contract above.
- **D-1 — composite authorization — APPROVED (Option A) 2026-07-27.** The composite `close_week_with_reservations_v1` authorizes via `can_write_financials()`. Retirement is evidence-driven: a household_admin may clear only an owner-created reservation supported by an exact qualifying cleared Register debit and cannot create capacity. The executing user remains durably attributable through `resolved_by`. Implementation-binding, not architecture-binding; reversible post-D3 via `CREATE OR REPLACE` without a data migration. Later-phase expectations: D4 presents the retirement-aware closeout consistently to authorized owner **and** household_admin users; any candidate nomination stays constrained to transactions satisfying the complete locked evidence predicate; the selected transaction and executing user remain visible in the audit trail.
- **D-2 — authoritative evidence account — APPROVED (Option A) 2026-07-27.** The authoritative Register evidence account is `accounts.key='truist_checking'`. The §E evidence predicate must require `t.account_key='truist_checking'`. Matches the D1/D2 pinned `source_account`, the confirmed accounts mapping, and the `au11_disc:2026:truist_checking` advisory-lock namespace. Implementation-binding; reversible via `CREATE OR REPLACE`, subject to evidence-preservation review if live attributions later exist.
- **D-3 — producer/disposition scope — APPROVED (Option A) 2026-07-27.** New lifecycle producers (`mark_bank_pending`, stale detection) and the disposition of initiated reservations that will not clear are deferred to D4. D3 is limited to evidence-clear, carry-forward, and block behavior. **Carry-forward is an outcome only:** a supported existing reservation remains unchanged, unresolved, and capacity-withholding; D3 does **not** produce, stamp, or transition a reservation to `carried_unresolved`.
- **D-4 — partial/aggregate evidence — APPROVED (Option A) 2026-07-27.** One commitment requires exactly one exact, unambiguous cleared Register debit. Aggregation, splitting, partial-amount matching, and commitment splitting are unsupported in D3; any unsupported aggregate/split/partial evidence condition returns the design-prescribed BLOCK outcome. A valid caller nomination may disambiguate multiple otherwise-qualifying exact candidates **only** under the verified nomination + locked-predicate contract (§S1); nomination does **not** authorize aggregate/split/partial matching.
- **D-5 — anomalous AU-11 states — APPROVED (Option A) 2026-07-27.** `planned` and `carried_unresolved` are unsupported lifecycle states for AU-11 reservation rows in D3 and hard-fail unless a separately approved producer and transition contract is introduced in a later slice. Consistent with D-3: carry-forward leaves a currently supported reservation unchanged and does **not** create `carried_unresolved`.
- **D-6 — week-window source — APPROVED (Option A) 2026-07-27.** The composite derives the model-week window internally from the pinned `2026-06-07` epoch using seven-day model weeks. The caller supplies only `p_week_num`. Equivalence to the authoritative weekly model must be proven across all 31 weeks. Caller-supplied date bounds are prohibited.
- **D-7 — replay/idempotency — APPROVED (Option A) 2026-07-27.** Replay is based on the frozen wrapper's existing idempotency contract. The composite always invokes and captures the frozen wrapper result. A first closeout passes through the caller's **real** commitment arrays; a lawful retirement-only replay uses the verified **empty-array** replay contract. Only a verified `normal_closeout` result (incl. a lawful `idempotent`/`repaired` result where applicable) authorizes retirement. GFA01 is propagated. No separate retirement-only RPC mode is introduced.
- **D-8 — grants & fixture posture — APPROVED (Option A) 2026-07-27.** D3 uses resting-inert EXECUTE grants on staging. EXECUTE may be granted to `authenticated` only during the authorized test matrix and must be revoked afterward. Every staging fixture must be ledger-tracked, completely torn down, and verified absent.
- **D-9 — durable attribution — APPROVED (Option A) 2026-07-27 — EXACT VERIFIED CONTRACT.** Approve durable attribution and retain the D3 evidence-clearing scope. This approval applies **only** to the exact §E2 D-9 contract verified by Fable, incorporated **by reference without modification**: the exact `cash_commitments.cleared_transaction_id` definition; the exact FK to `transactions(id)` incl. `ON DELETE RESTRICT` + `NOT DEFERRABLE`; the exact `uix_au11_cleared_txn` partial unique-index definition + predicate; the exact total lifecycle-attribution CHECK contract; the verified migration ordering + precondition assertions; atomic attribution only after wrapper-contract verification; targeted `SQLSTATE 23505 → transaction_already_attributed` mapping **only** when the violated object is `uix_au11_cleared_txn`; re-raising every unrelated unique violation; full-transaction rollback on attribution conflict; the pre-live-attribution bare-drop vs post-live-attribution evidence-preservation-migration distinction. No implementation may broaden, narrow, paraphrase, or alter those verified definitions without explicit owner approval and renewed independent review. **Caveat:** bare-drop rollback only while no non-fixture attribution exists; after live attribution, removal/material redesign requires an evidence-preservation migration, explicit owner approval, and independent architecture review.
- **D-10 — model-year support — APPROVED (Option A) 2026-07-27.** D3 supports model year 2026 only. Any `p_model_year` other than 2026 raises `unsupported_model_year`. Future model years require a separately approved canonical epoch, week-window contract, and equivalence validation.
- **D-11 — post-attribution immutability — APPROVED (Option A) 2026-07-27 — DETECT IN D3; PREVENT BEFORE PRODUCTION ATTRIBUTION.** D3 detects post-attribution evidence mutation through the verified S3(b) consistency invariant and prohibits silent repair, reassignment, or evidence substitution. Any detected inconsistency creates a hard operational hold requiring an evidence-preservation correction. Register edit/delete prevention for attributed evidence must be implemented in D4 or through another separately approved protected-surface change. **Production gate:** no non-fixture production attribution may occur until edit/delete protection for attributed Register evidence has been implemented and independently validated, unless the owner separately approves a documented residual-risk exception and compensating control.
- **Dependency ruling:** D-9 is the scope-gating decision; D-4, D-5, and D-11 are therefore valid and internally consistent. D-6 and D-10 are approved as a coupled 2026-only week-window contract. D-3 and D-5 are approved with the explicit distinction between an unchanged carry-forward **outcome** and the unsupported `carried_unresolved` **lifecycle state**. All D-1…D-11 approved Option A; no decision remains pending.
