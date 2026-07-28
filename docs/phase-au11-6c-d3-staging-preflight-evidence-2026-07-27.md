# AU-11 Step 6C-D3 — Preflight Evidence Record (Step 7B, sanitized) — 2026-07-27

Canonical repository record of the read-only D3 preflight executed on staging `pkwotgqivgaapwuqgwqb` (Adam-executed; Claude ran no SQL). Sanitized: no UUIDs, no identities, no balances, no production-sensitive values — counts, booleans, catalog metadata, and md5 digests only.

## Provenance
- **Repository HEAD at execution:** `c5934a189a534f5bdabcb5c44a23a98453a569c6` (`origin/main` synchronized).
- **Preflight SQL SHA-256:** `1487840ca05d36032aac2e8103cc5f95f5a5c8a4ba6976d08c238b2621710fc9` (`docs/phase-au11-6c-d3-staging-preflight.sql`, Step 7A-approved, unmodified).
- **Execution date:** 2026-07-27. **Model:** Adam executes in staging; Claude authors/validates.
- **Transport note:** the staging session returned a consolidated 19-row JSON plus separately-captured sections. Values below are transcribed from that evidence. Where a section's raw per-row catalog text (exact `pg_get_constraintdef` / `pg_get_indexdef` / policy rows) was reported as a consolidated fact rather than verbatim rows, it is labeled **[consolidated]**; the verbatim def text remains available in the staging result set and can be inlined on request.

## Staging certification
`app_environment_exists=true`, `env_column_exists=true`; `environment_rows=1`, `staging_rows=1`, `non_staging_rows=0`, **`all_rows_are_staging=true`**. Read-only; no writes; no production connection.

## PASS 1 — section-by-section (sanitized)

**P1_REL_existence** — all present (`true`): app_environment, cash_commitments, discretionary_reservation_batches, goal_registry, goal_funding_snapshots, weekly_reconciliations, transactions, accounts.

**P1_COL_existence** — present: `goal_registry.reservable`; `weekly_reconciliations.chk`; `cash_commitments.{status, commitment_source, cleared_date, reflected_model_week, resolved_model_week}`; `transactions.{account_key, amount, transaction_date, posted_date, cleared, reconciled, transfer_pair_id}`; `accounts.key`. (No candidate column reported absent.)

**A1_frozen_wrapper** — `save_weekly_closeout_with_snapshots`: **overload_count=1**; returns **jsonb** (not a set); **security_definer=true**; owner **postgres**; `proconfig=search_path=public, pg_temp`; anon_execute=false, authenticated_execute=false; **body_md5 `e2a112b376dc32c43e1615e4a4abf24a`**; full `identity_arguments` + `arg_names` captured [consolidated].

**A2_frozen_related** — `save_reconciliation_with_commitments` body_md5 == pinned `1bfde751ac647c5e9a25ba168d08150c` (**matches_pinned_baseline=true**); `save_goal_funding_snapshots` body_md5 == pinned `154231b3f180349ec328f08ccbe77076` (**true**); `repair_commitments_for_week` present, `matches_pinned_baseline=NULL` (no pinned md5 baseline — signature-authoritative).

**B1_cc_columns / B2_clear_cols_present** — `cash_commitments` has `cleared_date`, `reflected_model_week`, `resolved_model_week`, `resolved_at`, `resolved_by`, `resolution_type` (all `has_*=true`). Clear-transition columns fully present.

**B3_constraints** [consolidated] — CHECK/UNIQUE/FK on `cash_commitments` + `discretionary_reservation_batches` captured; key semantics in B4/B5/I-series below.

**B4_status_check** — `cash_commitments.status` is a **closed CHECK enumeration**: `planned, scheduled, initiated, bank_pending, cleared, voided, carried_unresolved, stale_review` (captured from `pg_get_constraintdef`, not a name-mention heuristic). `cleared` is admitted ⇒ no widening for D3.

**B5_indexes** [consolidated] — one-active-batch partial index on `(model_year, source_account) WHERE status='active'`; per-goal `(model_year, reservation_batch_id, goal_id)` uniqueness for discretionary rows; batch `(model_year, batch_digest)` uniqueness.

**C1_transactions_columns** — columns include `account_key, transaction_date, posted_date, amount, cleared, reconciled, transfer_pair_id, source` (+ payee, memo, category_key, notes, timestamps). Committed DDL (`phase-5e-migration.sql:28-56`): `cleared BOOLEAN NOT NULL DEFAULT FALSE`; `reconciled BOOLEAN NOT NULL DEFAULT FALSE`; `posted_date DATE` (nullable, no default); `transfer_pair_id UUID` (nullable, no default); `source TEXT NOT NULL DEFAULT 'manual'`; `amount NUMERIC(12,2) NOT NULL` CHECK(`<>0`).

**C2_transactions_indexes** [consolidated] — includes PK on `id`; partial index on `transfer_pair_id WHERE NOT NULL`.

**C3M1/C3M2/C3M3/C3M4** — `accounts.key` is UNIQUE; `transactions.account_key REFERENCES accounts(key) ON UPDATE CASCADE / ON DELETE RESTRICT`; account candidate fields captured [consolidated].

**E1_calendar_tables** — **empty result** (no `%week%`/`%calendar%`/`%model_week%` table).
**E2_week_date_functions** — **empty result** (no week→date resolver function).
**E3_recon_snapshot_date_cols** — `weekly_reconciliations` exposes `recorded_at` (timestamp); **no week-date-range columns**. ⇒ DB carries no week window.

**F1_authz_helpers** — `can_write_financials`, `is_owner` captured (identity + md5 + ACL posture) [consolidated].
**F2_rls_policies** [consolidated] — policy metadata + `qual_present`/`with_check_present` + md5 + helper-reference booleans for the five tables; **no raw expressions emitted**.
**F3_table_rls** [consolidated] — RLS enablement + `authenticated` INSERT/UPDATE/SELECT posture per table captured.

**G1_lock_contract** — all three D2 RPCs: `uses_advisory_xact_lock=true`; `advisory_lock_expr` uses namespace `au11_disc:<model_year>:<source_account>`; **`for_update_count=0`** (no `FOR UPDATE`); positional offsets captured (supporting). Exact acquisition order confirmed from committed source.

**I1_uniqueness / I2_recon_key / I3_idempotency_fields** — UNIQUE: reservation `batch_digest`; `expected_item_id`; reservation `(batch, goal)`; one active batch; `weekly_reconciliations` PK; goal snapshot `(year, week, goal)`. `transfer_pair_id` and `bank_reference` are **NOT unique** (`*_in_unique_index=false`).

## PASS 2 — aggregate outputs (verbatim)
- **P2_PF0B_staging_cert:** environment_rows=1, staging_rows=1, non_staging_rows=0, all_rows_are_staging=true.
- **P2_D1_txn_quality:** total_rows=0, posted_date_populated=0, cleared_true=0, reconciled_true=0, transfer_pair_populated=0, cleared_and_posted=0, posted_but_not_cleared=0, cleared_but_no_posted_date=0. *(All vacuous — empty table.)*
- **P2_C3AGG_account_key_candidates:** accounts_literal_key_match=1, distinct_account_keys=14, distinct_txn_account_keys=0.
- **P2_H1_residue:** active_batches=0, all_batches=0, fixture_goals=0, fixture_snapshots=0, fixture_reconciliation_rows=0, implicit_nonfixture_reservable_goals=0.
- **P2_H2_reservation_by_status:** scheduled=0, initiated=0, bank_pending=0, stale_review=0, cleared=0, voided=0, null_status=0, other_status=0.

## Verbatim committed definitions (Fable S6 — cited from committed source)
**`cash_commitments` primary key** (`phase-5f-1-migration.sql:49`): `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`. This is the immutable, database-unique retirement-entry identity (`p_retire.commitment_id`). `commitment_source` is `TEXT NOT NULL DEFAULT 'wd_reconciliation'` (:52). Clear-transition audit columns: `resolved_at TIMESTAMPTZ` (:106), `resolved_by UUID REFERENCES auth.users(id)` (:107), `resolution_type TEXT` (:118) — server-derived; terminal-immutable once set.
**One-active-batch partial unique index** (`phase-au11-6c-d1-staging-migration.sql:148-150`):
```sql
CREATE UNIQUE INDEX uix_one_active_batch
  ON public.discretionary_reservation_batches (model_year, source_account)
  WHERE status = 'active';
```
**Per-goal uniqueness** (:153-155): `CREATE UNIQUE INDEX uix_au11_batch_goal ON public.cash_commitments (model_year, reservation_batch_id, goal_id) WHERE commitment_class = 'discretionary_goal_transfer';`  **Batch digest** (:138): `UNIQUE (model_year, batch_digest)` on `discretionary_reservation_batches`. (⇒ `batch_digest+goal_id` is not a cash-side uniqueness key; the `cash_commitments.id` PK is used instead.)
**D1 reservation-shape CHECK** (`phase-au11-6c-d1-staging-migration.sql:106-118`):
```sql
ADD CONSTRAINT chk_au11_reservation_shape CHECK (
  (commitment_class = 'discretionary_goal_transfer'
     AND commitment_source = 'au11_reservation'
     AND reservation_batch_id IS NOT NULL AND goal_id IS NOT NULL
     AND destination_account_ref IS NOT NULL
     AND required_or_discretionary = 'discretionary_deployment'
     AND source_account = 'truist_checking')
  OR
  (commitment_class <> 'discretionary_goal_transfer'
     AND commitment_source <> 'au11_reservation'
     AND reservation_batch_id IS NULL AND goal_id IS NULL
     AND destination_account_ref IS NULL AND bank_reference IS NULL AND bank_submitted_at IS NULL)
) NOT VALID;
```
It does **not** reference `cleared_transaction_id` → the new attribution CHECK is complementary (D1 untouched).
**Frozen wrapper return branches** (`phase-5g-1d-migration.sql`): p_mode gate ∈ `{normal_closeout, approved_reopen}` else RAISE 22023 (:104); `normal_closeout` first close `{ok,mode,week_num,snapshot_count:9}` (:294); idempotent replay `{…,idempotent:true,…}` **only with empty arrays + matching recon** (:308); repaired `{…,repaired:true,…}` (:358); GFA01 RAISE `ERRCODE='GFA01' HINT='REQUIRES_SUPERVISED_ADJUDICATION'` on a closed week + non-empty commitments (:311); `approved_reopen` `{…}` (:207/:234).
**Wrapper baseline:** md5 `e2a112b376dc32c43e1615e4a4abf24a` is the **first formally pinned D3 baseline** of the frozen wrapper (a pinned contract, not merely an observation).

## Source-to-fact mapping
| Fact | Evidence source |
|---|---|
| Staging certified | PF0A + P2_PF0B |
| Frozen wrapper identity/md5/overload | A1 |
| Pinned checksums match | A2 |
| Clear-transition columns present | B1/B2 + P1_COL |
| status enum incl. `cleared` (no widening) | B4 |
| Reservation/batch uniqueness & FK | B3/B5/I1/I2/I3 |
| account_key→accounts FK, key unique, 1 truist_checking | C3M1–M4 + P2_C3AGG |
| transactions column defaults/nullability | C1 + committed `phase-5e-migration.sql:28-56` |
| No DB week window | E1/E2/E3 (E1/E2 empty; E3 no date-range cols) |
| Advisory key + no FOR UPDATE + order | G1 + committed `phase-au11-6c-d2-staging-rpcs.sql:85-94` |
| Client writer omits reconciled/posted_date/transfer_pair_id | committed `index.html:8204` |
| No live reservation routing | committed `index.html` (AU-11 dormant) |
| Empty staging transactions | P2_D1 |
| Zero residue baseline | P2_H1/H2 |

## Interpretation
- Staging `transactions` empty → Register-evidence path requires a writer-contract-faithful synthetic fixture (a D3 test-fixture requirement, not a design blocker).
- `reconciled` persists **FALSE** (NOT NULL default); no committed path sets it true, and a legitimate newly-created cleared debit can remain `reconciled=false`, so `reconciled` **cannot be mandatory evidence** and is **advisory only** (regardless of any future workflow). `posted_date` NULL (client-omitted) ⇒ advisory. `cleared` (client-set) + `transaction_date` are the reliable evidence signals.
- **Attribution gap (design finding):** no durable matched-transaction attribution exists — `bank_reference` is free TEXT (not unique), and no `cash_commitments` column references `transactions(id)`. ⇒ D3 must add a narrowly-scoped `cleared_transaction_id UUID` FK + partial unique index (design addendum §E / decision D-9) so one transaction can never retire two commitments.
