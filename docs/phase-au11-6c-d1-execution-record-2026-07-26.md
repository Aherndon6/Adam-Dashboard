# AU-11 Step 6C-D1 — staging additive-DDL package + execution record (2026-07-26)

**Status:** staging DDL package **AUTHORED**; **NOT executed**. Per standing governance ("Claude ran no
SQL" — Claude authors migration/rollback/validation packages, **Adam executes** them in the Supabase SQL
Editor), and because this session has **no staging credentials/connection** (only prod
`usayoldrawwmjsmretin` is reachable, read-only; no `supabase` CLI; no service key; no local PGlite/pg
harness), the apply / validate / rollback-proof steps are **owner-executed on staging**. No production
work, no RPC, no client change, no BUILD_TS change, no deploy. Baseline HEAD `2666a8e`.

## Staging target proof
- Staging project = **`pkwotgqivgaapwuqgwqb`** (documented ≠ prod `usayoldrawwmjsmretin`;
  `docs/dr-exit-gate-2026-07.md:34`, `CODEX_STATUS.md:411`).
- The migration/rollback carry a **second-line guard**: they abort unless `public.app_environment.env='staging'`
  exists (the established staging sentinel; `docs/phase-5g-1-staging-env-marker.sql`). Adam still selects the
  target; the guard is defense-in-depth, not a substitute.

## Preflight findings (repo-grounded; live capture in the preflight SQL)
- **U1** checking `accounts.key` = **`truist_checking`** (`accounts` seed `phase-5d-1-migration.sql:200`;
  `cash_commitments.source_account` CHECK `('truist_checking')`).
- **U2** model-week → calendar-date span is **app-side** (`getCalWeek` + WD spans; no DB relation). Recorded
  as a **6C-D3** input (pass the date window to the composite); **not** a D1 schema dependency.
- **U3** **resolved** — `destination_account_ref` (label/reference from `goal_registry.dest`, not
  `accounts.key`). Preflight confirms `goal_registry` + `dest` exist and there is no dest-account-key column.
- **U4** `transactions.reconciled` is **reserved (unpopulated)** per schema comment
  (`phase-5e-migration.sql:63`); Register evidence relies on `cleared` + `posted_date` + date-span. Preflight
  quantifies actual usage.
- `cash_commitments.status` already permits `scheduled/initiated/bank_pending/stale_review/cleared/voided` →
  **no status-CHECK widening needed**.

## Package (authored, staging-only)
| file | purpose |
|---|---|
| `docs/phase-au11-6c-d1-staging-preflight.sql` | read-only capture of live constraint names/defs, columns, indexes, FK, RLS, grants, triggers, rowcount; U1/U3/U4 checks; D1 legality gates |
| `docs/phase-au11-6c-d1-staging-migration.sql` | additive columns; +1 class value; +1 source value (catalog-dynamic by captured name); bidirectional shape CHECK (NOT VALID → VALIDATE); batch table; FK (ON DELETE RESTRICT); `uix_one_active_batch`; `uix_au11_batch_goal`; `ix_au11_active`; batch RLS + grants; comments. Staging-guarded; one transaction |
| `docs/phase-au11-6c-d1-staging-validation.sql` | forward validation matrix V1–V14 + frozen-wrapper noninterference probe (rolled back) + planner EXPLAINs |
| `docs/phase-au11-6c-d1-staging-rollback.sql` | exact reverse; legal only while zero au11 rows/batches and no 6C-D2 RPC |

**Design conformance to 6C-D0:** additive nullable, no defaults, no table rewrite, no data backfill;
`destination_account_ref` (never `destination_account`/`_key`); exactly +1 class and +1 source value, all
existing values preserved; shape constraint makes it **impossible for the frozen wrapper to emit a
reservation row** (it never sets `commitment_source='au11_reservation'`); DB-enforced one-active-batch;
frozen CAE/RPCs/closeout wrapper and cash_commitments RLS untouched.

## Staging execution results (2026-07-26) — D1-1 … D1-7 COMPLETE + GREEN (Adam-executed, staging `pkwotgqivgaapwuqgwqb`)
Executed by Adam in the Supabase SQL Editor, one gate at a time; **Claude ran no SQL**. Package files were
corrected (uncommitted) between gates as staging surfaced schema-assumption defects (all read-only/no-DDL
fixes): preflight `app_environment.note→env,set_at`, `pg_policies.polname→policyname`,
`accounts.name/type→label/account_type/lifecycle_status`; migration gained fail-closed CHECK-def-drift
asserts; validation V6/V7 retargeted to exact `conname` (post-migration `chk_au11_reservation_shape` made the
ILIKE-on-def scalar subquery non-unique); validation V13 supplies a real `created_by` (SQL-Editor `auth.uid()`
is NULL) so the shape CHECK is the sole failure.

- **D1-1 Preflight — PASS.** env=staging; `GATE_no_au11_rows`/`_batch_table`/`_d2_rpc` all PASS;
  `cash_commitments` rowcount 0; U1 `truist_checking`=checking/active; `goal_registry.dest` is text with no
  account-key column (U3); `transactions` empty, `reconciled_true=0` (U4). Captured exact CHECK names:
  `cash_commitments_commitment_class_check` (7 values), `cash_commitments_commitment_source_check` (3 values).
- **D1-2 Forward migration — PASS.** Committed; no ERROR/HARD STOP; schema-cache reloaded.
- **D1-3 Forward validation — PASS.** V1–V4=0; V5 five nullable/no-default columns (uuid/text/text/text/timestamptz);
  V6/V7 PASS; V8/V9 `convalidated=true`; V10 three partial indexes with exact predicates; V11 RLS on batch table;
  V12 zero anon/authenticated write grants; V13 shape rejects a non-`au11_reservation` reservation-class insert +
  0 residue; V14 repair still rejects unknown class; AU-11 EXPLAIN → Index Scan `ix_au11_active`; existing-class
  EXPLAIN → Seq Scan (expected on empty table — no regression).
- **D1-4 Rollback — PASS.** Committed; schema-cache reloaded.
- **D1-5 Post-rollback validation — PASS.** PR1/PR3/PR4/PR9=0; PR2 PASS; PR5/PR6 PASS; PR7 rowcount 0; PR8
  CHECK defs restored to exactly the 7 class / 3 source values (`= ANY(ARRAY[...])` normalized form; byte-equivalent
  in content to the D1-1 capture). Exact pre-migration restoration proven.
- **D1-6 Reapply — PASS.** Migration re-run once; committed; schema-cache reloaded.
- **D1-7 Final validation — PASS.** Identical to D1-3 green result.

**Final staging state chosen: MIGRATION APPLIED (AU-11-ready).** Rationale: leaves staging in the state
6C-D2 (create/initiate/dispose RPCs) will build on; the full rollback+reapply cycle already proved exact
reversibility. Staging holds the additive schema; **production untouched.**

## Pending — Gate D1-8 (commit + push the package), owner-authorized only
This repo's D1 commit was gated on green staging forward/rollback/reapply — now satisfied. Commit scope = the
six D1 files (5 `.sql` + this record). Awaiting explicit Gate D1-8 authorization; no push/production change
without owner approval.

## Local (non-DB) gates this session
- `index.html` / `test_regression.js` **unmodified**; static suite and frozen hashes unchanged from
  `2666a8e` (recorded in the turn report). No BUILD_TS change.

## Confirmations
No production access; no RPC implementation; no client implementation; no deployment; no operational
transfer. AU-11 remains dormant, non-authoritative, unrendered, zero-caller. Step 6C-D2 NOT begun.
Operational hold (incl. Wendy IRA) unchanged.
