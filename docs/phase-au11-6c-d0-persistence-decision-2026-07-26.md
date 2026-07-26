# AU-11 Step 6C-D0 — Corrected persistence spec, repository grounding, and protected-schema exception (2026-07-26)

**Status:** specification + decision package only. NO executable DDL/RPC, no schema change, no
production, no deploy, no BUILD_TS change. Incorporates the Fable 6C-C verdict (APPROVE WITH CHANGES — 7/10).
Frozen surfaces (`runModel`, `authoritativeCurrentChk`, `getCashAvailabilityEngine`, `isReservedAsOf`,
`save_reconciliation_with_commitments`, `repair_commitments_for_week`, `save_weekly_closeout_with_snapshots`,
`correct_goal_funding_snapshot`) and the nine-goal closeout contract remain untouched. Operational hold
(incl. Wendy IRA) unchanged. Baseline HEAD `a3442bcb1db0d167c5cbd648c22bd0d1f41ad741`.

Balance-free per standing rule (goal targets $600/$500 are already-public registry values).

---

## Owner decisions (2026-07-26) — RECORDED

**1. Protected-schema exception — APPROVED (narrow scope).** The owner approved the §H exception,
authorizing **preparation and staging-only validation** of the additive AU-11 persistence architecture
because the reservation invariant cannot be met through the existing `cash_commitments` contract without
additive schema. **Covers only:** additive nullable reservation fields; the
`discretionary_reservation_batches` control table; `commitment_class`/`commitment_source` constraint
widening; reservation-shape constraints; reservation-specific indexes and FK relationships; staging RLS +
RPC-only write posture; staging preflight/validation/rollback artifacts. **Does NOT authorize:** production
DDL; production RPC installation or grants; client routing or live callers; AU-11 promotion; any
discretionary transfer; Wendy IRA execution; or any change to `runModel`, `authoritativeCurrentChk`,
`getCashAvailabilityEngine`, `isReservedAsOf`, the existing frozen RPCs, the frozen closeout wrapper, or the
nine-goal closeout contract. **Every 6C-D slice remains separately authorized.**

**2. Destination-account decision — `destination_account_ref TEXT` (v1).** Since `goal_registry.dest` is a
display label, not an `accounts.key`, AU-11 v1 uses a column named **`destination_account_ref`** (a
reference/label, *not* canonical account identity). Contract: server derives it from `goal_registry.dest`
at creation; a client-submitted reference is accepted **only** as a stale-client cross-check that must
exactly match the server-derived value; persisted **immutably** as historical authorization intent; **never
the sole evidence for retirement**; source-leg Register evidence remains **mandatory**; destination-leg /
transfer-pair evidence remains **advisory in v1**. A future nullable `destination_account_key` may be added
**only** once the Goal Registry has a canonical account-key mapping. A destination correction requires
disposition + re-creation; historical rows are never rewritten. (This resolves U3 for v1.)

---

## B. Repository grounding (read-only; facts, not guesses)

| item | finding | source |
|---|---|---|
| **A. wrapper failure semantics** | `save_weekly_closeout_with_snapshots` **RAISEs** on every failure (no `ok:false` branch). Success returns `jsonb_build_object('ok',true,'mode','normal_closeout','week_num',p_week_num,'snapshot_count',9)` (idempotent/repaired variants add flags). Composite must verify `ok=true ∧ mode='normal_closeout' ∧ week_num=p_week_num ∧ snapshot_count=9`; rely on RAISE→rollback otherwise. | docs/phase-5g-1d-migration.sql:294,308,358 |
| **A. GFA01** | fully-closed week + commitment change → RAISE `GFA01`/`REQUIRES_SUPERVISED_ADJUDICATION` (client routes to adjudication). Composite must not swallow it. | index.html:3452 |
| **B. repair class filter** | `repair_commitments_for_week` rejects any class outside the **seven** (`RAISE 'repair: invalid commitment_class'`); authz `can_write_financials()`; `GRANT EXECUTE … authenticated`. → never touches `discretionary_goal_transfer`. | phase-5f-1-migration.sql:1087,1036,1338 |
| **C/7. status writes** | `cash_commitments` INSERT/UPDATE **revoked** from authenticated (RPC-only; `GRANT SELECT` only). Status transitions occur ONLY inside `save_reconciliation_with_commitments` / `repair_commitments_for_week` / closeout wrapper — all class-locked to the seven. **No path today can transition a `discretionary_goal_transfer` row.** A new `scheduled→initiated` RPC is therefore required. | phase-5f-1-migration.sql:219-224 |
| **D. closeout operator** | normal closeout authz = **`can_write_financials()`** (household financial writer); `is_owner()` only for `approved_reopen`. | phase-5g-1d-migration.sql:114,110 |
| **E. goal_registry** | real server relation (read-only; no write policies). Columns (via `mapGoalFromDB`): id, name, tier, target, priority, status, notes, starts_after, due_week, needs_flag, from_model, milestone, stretch, auto, **src**, **dest**, color. **`dest` is a display LABEL** (e.g. `'AMEX Savings (holding)'`), **NOT an `accounts.key`.** No canonical destination account-key column evident. | index.html:1616-1636; phase-5e-7-validation.sql V14; phase-5g-1c-2-migration.sql:46 |
| **F. Register (`public.transactions`)** | columns: id, user_id, `account_key` (FK `accounts.key`), `transaction_date`, `posted_date`, payee, memo, `amount NUMERIC(12,2)` (**+ = inflow, − = outflow, nonzero**), category_key, **`cleared BOOLEAN`**, **`reconciled BOOLEAN`** (comment: "reserved for Phase 5F"), **`transfer_pair_id UUID`** (comment: "reserved for transfer linking" — dormant). No model-week column. | docs/phase-5e-migration.sql:27-56 |

**Grounded consequences**
- Register source-leg evidence = a `transactions` row with `account_key` = the checking key, `amount = −(reservation dollars)`, `cleared=true` (and/or `posted_date` set), `transaction_date` within the reconciled week's date span. **Mandatory.**
- Destination-leg / transfer-pair evidence is **advisory in v1** — *justified*: `transfer_pair_id` is dormant and unlinked, and `goal_registry.dest` is a label with no `accounts.key`, so a canonical destination-leg match is not currently derivable.
- **Unresolved → preflight (do not guess):**
  - (U1) checking `accounts.key` exact value (`'truist_checking'` used as `source_account`, but confirm the `accounts.key` for the Register checking ledger).
  - (U2) model-week → `transaction_date` span mapping used for evidence windowing (WD dates; confirm canonical source).
  - (U3) canonical destination account-key: `goal_registry` has only a `dest` **label** — **RESOLVED for v1** (owner decision 2026-07-26): use `destination_account_ref` (label/reference, not identity); destination-leg matching stays advisory; a canonical `destination_account_key` is deferred until the registry has an `accounts.key` mapping.
  - (U4) `transactions.reconciled` population status ("reserved for 5F" — confirm whether it is actually set at closeout, else rely on `cleared`+`posted_date`+date span).

---

## C. Corrected schema proposal (non-executable)

### Fable corrections folded in
1. **Initial status = `scheduled`** (not `initiated`). `scheduled` withholds capacity, no bank submission yet.
2. **New `commitment_source = 'au11_reservation'`**; bidirectional shape: `commitment_class='discretionary_goal_transfer' ⇔ commitment_source='au11_reservation'` — proves the frozen wrapper (which sets `commitment_source ∈ {wd_reconciliation, manual_reconciliation}`) can never emit a reservation row.
3. **`discretionary_reservation_batches` control table** with DB-enforced one-active-batch and an FK from reservation rows.
4. **basis-week precondition** = latest *fully closed* reconciliation (recon + nine snapshots), not "origin week appears anywhere."

```sql
-- 6C additive DDL — PROPOSAL ONLY (not executed). Additive nullable cols, no defaults; NOT VALID + VALIDATE.
-- (1) reservation columns on cash_commitments
ALTER TABLE cash_commitments
  ADD COLUMN reservation_batch_pk  UUID,     -- FK -> discretionary_reservation_batches.id
  ADD COLUMN reservation_batch_id  TEXT,     -- Step-6B deterministic digest (denormalized, audit)
  ADD COLUMN goal_id               TEXT,     -- registry goal id
  ADD COLUMN destination_account_ref   TEXT,     -- persisted display label = goal_registry.dest at authorization time (immutable)
  ADD COLUMN bank_reference        TEXT,     -- confirmation/cancellation reference (evidence; NULL until initiated/disposed)
  ADD COLUMN bank_submitted_at     TIMESTAMPTZ; -- scheduled->initiated timestamp

-- (2) widen class CHECK (+1 value); (3) widen source CHECK (+1 value); use replace-constraint discipline
ALTER TABLE cash_commitments DROP CONSTRAINT cash_commitments_commitment_class_check;
ALTER TABLE cash_commitments ADD  CONSTRAINT cash_commitments_commitment_class_check
  CHECK (commitment_class IN ('credit_card_payment','rent','bill_payment','tax_transfer',
                              'savings_transfer','manual_hold','other_transfer',
                              'discretionary_goal_transfer'));                 -- NEW
ALTER TABLE cash_commitments DROP CONSTRAINT cash_commitments_commitment_source_check;
ALTER TABLE cash_commitments ADD  CONSTRAINT cash_commitments_commitment_source_check
  CHECK (commitment_source IN ('wd_reconciliation','manual_reconciliation','historical_repair',
                               'au11_reservation'));                           -- NEW

-- (4) bidirectional reservation-shape (NOT VALID first, VALIDATE separately)
ALTER TABLE cash_commitments ADD CONSTRAINT chk_au11_reservation_shape CHECK (
  (commitment_class = 'discretionary_goal_transfer'
     AND commitment_source = 'au11_reservation'
     AND reservation_batch_pk IS NOT NULL AND reservation_batch_id IS NOT NULL
     AND goal_id IS NOT NULL AND destination_account_ref IS NOT NULL
     AND required_or_discretionary = 'discretionary_deployment'
     AND source_account = 'truist_checking')
  OR
  (commitment_class <> 'discretionary_goal_transfer'
     AND commitment_source <> 'au11_reservation'
     AND reservation_batch_pk IS NULL AND reservation_batch_id IS NULL
     AND goal_id IS NULL AND destination_account_ref IS NULL)
) NOT VALID;
-- ALTER TABLE cash_commitments VALIDATE CONSTRAINT chk_au11_reservation_shape;

-- (5) per-batch/per-goal uniqueness
CREATE UNIQUE INDEX uix_au11_batch_goal ON cash_commitments (reservation_batch_pk, goal_id)
  WHERE commitment_class = 'discretionary_goal_transfer';

-- (F) batch control table
CREATE TABLE discretionary_reservation_batches (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_digest      TEXT NOT NULL,          -- Step-6B deterministic digest
  model_year        INT  NOT NULL DEFAULT 2026,
  source_account    TEXT NOT NULL DEFAULT 'truist_checking' CHECK (source_account = 'truist_checking'),
  basis_model_week  INT  NOT NULL,          -- latest fully-closed reconciliation week at authorization
  status            TEXT NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active','retired','voided')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by        UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  resolved_at       TIMESTAMPTZ,
  resolved_by       UUID REFERENCES auth.users(id),
  resolution_notes  TEXT,
  UNIQUE (model_year, batch_digest)
);
-- (G) DB-enforced ONE ACTIVE BATCH per (model_year, source_account)
CREATE UNIQUE INDEX uix_one_active_batch
  ON discretionary_reservation_batches (model_year, source_account) WHERE status = 'active';

-- (H) FK reservation rows -> batch
ALTER TABLE cash_commitments
  ADD CONSTRAINT fk_au11_batch FOREIGN KEY (reservation_batch_pk)
      REFERENCES discretionary_reservation_batches(id);

-- (I) RLS/grants: SELECT to authenticated (read); NO INSERT/UPDATE/DELETE grant (RPC-only), mirroring cash_commitments.
ALTER TABLE discretionary_reservation_batches ENABLE ROW LEVEL SECURITY;
CREATE POLICY drb_select ON discretionary_reservation_batches FOR SELECT USING (is_allowed_user());
REVOKE ALL ON discretionary_reservation_batches FROM PUBLIC, anon, authenticated;
GRANT SELECT ON discretionary_reservation_batches TO authenticated;
```
```sql
-- (J) Rollback (only while zero au11 rows/batches exist):
DROP INDEX IF EXISTS uix_one_active_batch;
DROP TABLE IF EXISTS discretionary_reservation_batches;         -- (drop FK first)
ALTER TABLE cash_commitments DROP CONSTRAINT IF EXISTS fk_au11_batch;
DROP INDEX IF EXISTS uix_au11_batch_goal;
ALTER TABLE cash_commitments DROP CONSTRAINT IF EXISTS chk_au11_reservation_shape;
-- restore 7-value class CHECK + 3-value source CHECK (verbatim captured names);
ALTER TABLE cash_commitments
  DROP COLUMN bank_submitted_at, DROP COLUMN bank_reference, DROP COLUMN destination_account_ref,
  DROP COLUMN goal_id, DROP COLUMN reservation_batch_id, DROP COLUMN reservation_batch_pk;
```
**Constraint-migration discipline:** exact live constraint names must be **captured from a staging preflight** (the July-7 export may have drifted); additive columns are nullable **without defaults**; CHECK replacements use DROP+ADD with the captured name; the shape CHECK is added `NOT VALID` then `VALIDATE CONSTRAINT` in a separate low-lock step; lock analysis: `ADD COLUMN … (nullable, no default)` and `ADD CONSTRAINT … NOT VALID` take brief `ACCESS EXCLUSIVE` only for catalog update (no table rewrite); `VALIDATE CONSTRAINT` takes `SHARE UPDATE EXCLUSIVE` (concurrent reads OK). Rollback captured from the same preflight.

### `expected_item_id` (server-only, amount-free)
`disc-goal:v1:{model_year}:w{basis_model_week}:{batch_digest}:{goal_id}` — chars `[a-z0-9:_-]`, lowercased, server-constructed, clients never submit. **Four distinct identities:** (a) **DB batch-row identity** = `discretionary_reservation_batches.id` (UUID PK); (b) **Step-6B deterministic digest** = `batch_digest` (cycle fingerprint); (c) **per-goal reservation identity** = `(reservation_batch_pk, goal_id)`; (d) **`expected_item_id`** = the row idempotency string. Amount/destination/timestamp/order/randomness are never in any identity.

---

## D. Corrected RPC contracts (conceptual; no SQL authored)

All: owner `postgres`, `SECURITY DEFINER`, `SET search_path = public`, schema-qualified, `REVOKE PUBLIC/anon`, `GRANT EXECUTE authenticated` **only after staging**, in-body `assert is_owner()` (owner-only) EXCEPT the composite closeout (see §11).

1. **`create_discretionary_goal_reservation_v1(p_model_year, p_basis_model_week, p_batch_digest, p_source_account, p_expected_clear_date, p_rows JSONB)`** — owner-only. Advisory `pg_advisory_xact_lock(disc,model_year,source)`. Validate: source=truist; basis-week = latest fully-closed reconciliation (recon + nine snapshots for that week; no half-closed/inconsistent basis); each `goal_id` registry-eligible; `destination_account_ref` = current `goal_registry.dest`; `amount_cents` INT>0; conservation (Σ = supplied total); one-active-batch (INSERT the batch row → `uix_one_active_batch` enforces). INSERT batch row + one reservation row per goal (`status='scheduled'`, `commitment_source='au11_reservation'`, server `expected_item_id`). Idempotent replay (same key/amount/dest → no-op); amount/dest/source conflict → RAISE. **Never partial** (all-or-nothing). Returns `{ok, batch_pk, batch_digest, rows:[…]}`.
2. **`mark_discretionary_goal_reservation_initiated_v1(p_batch_digest, p_goal_ids[], p_bank_reference, p_bank_submitted_at, p_expected_clear_date?)`** — owner-only. `scheduled→initiated` only. Records `bank_submitted_at`, `bank_reference`, actor; optional new expected-clear date. Idempotent. This is the sanctioned status-write path (none exists today — grounded).
3. **`dispose_or_void_discretionary_goal_reservation_v1(p_batch_digest, p_goal_ids[], p_disposition, p_reason, p_bank_reference?)`** — owner-only. `p_disposition ∈ {void_scheduled, cancel_initiated, paid_other_account}`. `scheduled` → freely voidable with reason. `initiated|bank_pending|stale_review` → require `p_bank_reference` (cancellation/confirmation evidence) — a reason string alone is insufficient. A posted source leg → **never** voided to release capacity (record-reality; use `paid_other_account` disposition with the actual Register event, which does not falsely retire). Sets `status='voided'`, `resolution_type ∈ {voided, paid_from_other_account}`, `resolved_model_week`, `bank_reference`, `resolution_notes=p_reason`. Capacity releases immediately (fails `isReservedAsOf`).
4. **`close_week_with_reservations_v1(<frozen-wrapper params>, p_retire JSONB)`** — authz **`can_write_financials()`** (same posture as the existing closeout; retirement is evidence-driven, so a household writer cannot self-authorize new capacity — they can only retire owner-created rows that have posted evidence). Ordering in §F.

Evidence storage: `bank_reference` (dedicated column, not `resolution_notes` overload); `resolution_notes` carries the human reason. Justification for a dedicated column: evidence is a first-class, queryable audit field distinct from free-text notes.

---

## E. Corrected lifecycle state-transition table

| from | to | trigger | actor | evidence required |
|---|---|---|---|---|
| — | `scheduled` | create RPC | owner | reconciled basis + conservation |
| `scheduled` | `initiated` | mark-initiated RPC | owner | bank_reference + submitted_at |
| `scheduled` | `voided` | dispose (void_scheduled) | owner | reason only |
| `initiated` | `bank_pending` | ambiguity flag | owner/system | — (still withholds) |
| `initiated`/`bank_pending` | `cleared` | composite closeout | can_write_financials (in closeout txn) | **Register source-leg posted** |
| `initiated`/`bank_pending`/`stale_review` | `voided` | dispose (cancel_initiated / paid_other) | owner | bank_reference (cancellation) or accounted-elsewhere proof |
| `initiated`/`bank_pending` | `stale_review` | expected_clear + grace (7d), no posted match | system | — (still withholds) |
| `cleared`/`voided` | — | terminal | — | — |

Active (withholds): `scheduled, initiated, bank_pending, stale_review`. Partial (row-level) clear/void allowed. New batch blocked while any prior row is active (`uix_one_active_batch`).

---

## F. Corrected closeout-gate truth table + composite ordering

Per-reservation category (for the week being pinned):

| category | server predicate | closeout action |
|---|---|---|
| scheduled, not submitted | `status='scheduled'` | **carry forward**, stays active (NOT forced-void) |
| initiated, no posted source leg | `status IN('initiated','bank_pending')` ∧ no matching cleared checking debit | carry forward **iff** evidence confirms not reflected in the pinned balance |
| source leg posted & reflected | matching `transactions` row (checking, `−amount`, cleared/posted, in-week) | **must** be in the verified retirement set |
| bank_pending / ambiguous | `status='bank_pending'` ∧ ambiguous | **BLOCK closeout** until owner disposition |
| one posted, another not | per-row | retire posted row only; leave unposted active |

**No forced batch-wide void or false retirement.** Composite ordering (single txn):
1 acquire advisory lock → 2 load+lock batch and reservation rows → 3 validate the full proposed retirement set (identity/class/source/state/amount/dest/year/basis) → 4 validate **mandatory** Register source-leg evidence per row → 5 detect omitted posted-and-reflected rows (→ RAISE) → 6 detect ambiguous `bank_pending` (→ RAISE) → 7 fail before closeout on any invalid precondition → 8 `PERFORM save_weekly_closeout_with_snapshots(...)` (unmodified) → 9 verify `ok=true ∧ mode='normal_closeout' ∧ week_num ∧ snapshot_count=9` → 10 one guarded `UPDATE` retiring the exact verified rows (`status='cleared'`, `reflected_model_week=resolved_model_week=p_week_num`, `cleared_date`) → 11 `GET DIAGNOSTICS` updated-count == verified target count (else RAISE) → 12 update batch status (`retired` when all rows terminal) → 13 return authoritative composite result. **No exception handler swallows a wrapper/retirement error;** any failure rolls back the balance pin, snapshots, retirement, and batch transition together.

**Atomicity proof:** steps 2–12 are one transaction; `PERFORM` of the frozen wrapper does not commit (stock PostgreSQL has no autonomous transactions). Commit iff pin+snapshots+retirement+batch all succeed. ⇒ no committed state where (a) both pinned balance and an active reservation withhold (retirement sets `reflected_model_week` in the same txn), (b) neither accounts for the transfer (all-or-nothing), (c) only some of the required set retired (single guarded UPDATE + count check).

---

## G. Concurrency / batch model
- Advisory key: `hashtextextended('disc_goal_reservation:'||model_year||':'||source_account, 0)`, held for the txn in create / initiate / dispose / composite-closeout.
- DB one-active-batch: `uix_one_active_batch` (partial unique on `status='active'`). Per-goal: `uix_au11_batch_goal` + `expected_item_id UNIQUE`.
- Active statuses (withhold): scheduled, initiated, bank_pending, stale_review. Isolation READ COMMITTED + advisory lock sufficient; no client-only checks are load-bearing.
- create-vs-create serialized → idempotent or conflict; create-vs-void / create-vs-closeout / void-vs-closeout serialized on the same lock.

---

## H. Protected-schema exception decision package (APPROVED 2026-07-26 — staging-only scope; see "Owner decisions")

**`cash_commitments` is Do-Not-Touch protected schema.** Prior "no new schema" assumptions are **no longer controlling** — 6C-A/6C-B/6C-C proved the AU-11 reservation invariant cannot be met without additive schema.

- **Why additive schema is unavoidable:** `discretionary_goal_transfer` is not a legal `commitment_class`; `au11_reservation` is not a legal `commitment_source`; there is no home for `batch`, `goal_id`, `destination_account_ref`, or evidence (`bank_reference`); and DB-level one-active-batch needs a control table. Overloading `payee`/`notes` or an existing class is prohibited (would collide with the CAE, reconciliation UI, and repair). A separate reservation table cannot be seen by the **frozen** CAE (it reads only `cash_commitments`).
- **Exact protected objects affected:** `cash_commitments` (additive columns + widened `commitment_class`/`commitment_source` CHECKs + new shape CHECK + indexes + FK) and a **new** table `discretionary_reservation_batches`. **Not touched:** `getCashAvailabilityEngine`, `isReservedAsOf`, `save_reconciliation_with_commitments` (md5 `1bfde751…`), `repair_commitments_for_week`, `save_weekly_closeout_with_snapshots`, `correct_goal_funding_snapshot`, `save_goal_funding_snapshots` (md5 `154231b3…`), `runModel`.
- **Why frozen CAE/RPCs stay untouched:** the CAE counts any `isReservedAsOf`-true row regardless of class → a legal `scheduled` reservation withholds automatically; the frozen commitment/closeout RPCs are never edited (the composite *wraps* the closeout; the new create/initiate/dispose RPCs are separate).
- **Data-loss / lock risk:** additive nullable columns + `NOT VALID` constraints take only brief catalog `ACCESS EXCLUSIVE`; `VALIDATE` uses `SHARE UPDATE EXCLUSIVE` (reads continue); no table rewrite; no existing-row migration; no backfill.
- **Preflight evidence required:** capture live constraint names/definitions; confirm zero pre-existing `discretionary_goal_transfer`/`au11_reservation` rows; snapshot row counts; U1–U4 resolved on staging.
- **Staging-first requirement:** all DDL + RPCs proven on staging (6C-D1…D4) before any production authorization.
- **Rollback:** §C(J), valid only while zero AU-11 rows exist.
- **Production-approval boundary:** **no executable DDL may be authored until the owner approves THIS exception package.** Production install (6C-G) is a separate, later authorization.

---

## I. Corrected staging-slice plan
- **6C-D0** (this): corrected spec + grounding + exception package. *No DDL.*
- **6C-D1:** staging DDL only (columns, constraints, indexes, batch table, RLS) — no RPC grants, no client.
- **6C-D2:** staging create / mark-initiated / dispose RPCs — role/idempotency/concurrency tests.
- **6C-D3:** staging composite closeout — prevalidation + mandatory Register evidence + failure injection + rollback proof.
- **6C-D4:** authenticated end-to-end lifecycle — carry-forward, partial posting, evidence disposition, role matrix.
- **6C-D5:** dormant client wrappers + routing inventory (no production grant, no actionability).
Each slice separately authorized.

## J. 6C-D1 readiness recommendation
**Both prerequisite owner decisions are now RECORDED** (see "Owner decisions (2026-07-26)"): the §H
protected-schema exception is **APPROVED (staging-only scope)**, and U3 is **resolved for v1** via
`destination_account_ref`. 6C-D1 (staging-only additive DDL) is therefore **ready to author under a separate
6C-D1 authorization**, subject to a staging preflight capturing **U1** (checking `accounts.key`), **U2**
(model-week→date-span mapping), and **U4** (`transactions.reconciled` population) and the live constraint
names/definitions. **6C-D1 was NOT authorized by these decisions** — it remains a separately authorized
slice; no executable DDL is authored in 6C-D0.
