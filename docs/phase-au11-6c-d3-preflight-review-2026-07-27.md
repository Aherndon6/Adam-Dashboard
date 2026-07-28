# AU-11 Step 6C-D3 — Preflight Review (2026-07-27)

**Scope:** companion to `docs/phase-au11-6c-d3-staging-preflight.sql` (Step 7A). It explains *why* each preflight section exists, its *expected result shape*, *how the result feeds the D3 design*, and which items are **database facts** the preflight can settle vs **policy rulings** the owner must make (Step 7C).

**Boundary reminder:** D3 implementation has NOT started. No DDL, no composite RPC, no architecture ruling is authored or approved. The preflight is strictly read-only (SELECT + catalog). It is NOT executed in Step 7A — read-only execution is a separate Step 7B authorization. Production, engine, Wendy IRA, and all operational holds remain in force.

**Established idioms reused (so preflight output is comparable to D1/D2):** checksum = `md5(pg_get_functiondef(oid))` (never prints a body); signatures = `pg_get_function_identity_arguments(oid)` / `oidvectortypes(proargtypes)`; frozen md5 baselines `save_reconciliation_with_commitments = 1bfde751ac647c5e9a25ba168d08150c`, `save_goal_funding_snapshots = 154231b3f180349ec328f08ccbe77076`; authz helpers `can_write_financials()` / `is_owner()`.

---

## Execution gates (two passes, one file)

**PASS 1 — catalog-safe discovery.** Every statement reads ONLY `pg_catalog` / `information_schema` (plus `VALUES` lists). No PASS-1 statement directly references an uncertain relation or column as a FROM/subquery target, so it cannot error on a missing object. PASS 1 establishes relation existence (`P1_REL_existence`) and column existence (`P1_COL_existence`) FIRST, then the detailed catalog inspections.

**PASS 2 — aggregate data-quality.** Directly references real relations/columns. **Authorized only after** the named PASS-1 prerequisites confirm every required object exists. Each PASS-2 query header lists its REQUIRED relations + columns and the PASS-1 gate.

**PF0 split (required):** `to_regclass()` does not protect a *direct* reference to `public.app_environment` in the same statement, so PF0 is split:
- **PF0A (PASS 1):** catalog-only existence — `app_environment_exists`, `env_column_exists`.
- **PF0B (PASS 2):** row certification (`environment_rows`, `staging_rows`, `all_rows_are_staging`). **PF0B is NOT authorized to run unless PF0A returns `app_environment_exists = true` AND `env_column_exists = true`.**

**Uncertain until discovery confirms them:** `public.accounts`, `public.transactions`, `goal_registry.reservable`, `weekly_reconciliations.chk`, and all candidate `transactions` columns are treated as uncertain. They are referenced ONLY in PASS 2, each gated on `P1_REL_existence` / `P1_COL_existence`.

---

## Read-only proof — every non-operator function invoked, classified

| Function | Category |
|---|---|
| `to_regclass`, `pg_get_functiondef`, `pg_get_function_identity_arguments`, `pg_get_function_result`, `oidvectortypes`, `format_type`, `pg_get_userbyid`, `has_function_privilege`, `has_table_privilege`, `pg_get_constraintdef`, `pg_get_indexdef`, `pg_get_expr` | PostgreSQL catalog / introspection |
| `count`, `bool_or`, `string_agg`, `md5`, `coalesce`, `substring`, `position`, `length`, `replace`, `lower`, `count(*) FILTER`, `count(*) OVER` | aggregate / string / formatting built-in |
| — (none) | **application / business-function invocation → EMPTY** |

**No public business RPC is executed.** `save_weekly_closeout_with_snapshots`, `save_reconciliation_with_commitments`, `save_goal_funding_snapshots`, `repair_commitments_for_week`, `create_/mark_/void_…`, `can_write_financials`, `is_owner` appear ONLY as `proname` filter literals or as arguments to `pg_get_functiondef(...)`/`has_function_privilege(...)` — i.e. they are inspected via the catalog, never called. All statements are `SELECT`/`WITH`.

---

## Per-section rationale

**PF0A / PF0B — staging certification.** PF0A proves the relation and `env` column exist (catalog-only); PF0B certifies ≥1 row and every row `staging`. *Design effect:* nothing downstream is trusted unless PF0B is `all_rows_are_staging=true`, and PF0B may not run until PF0A passes. *Fact.*

**P1-REL / P1-COL — existence maps.** Establish, before any direct reference, which relations and uncertain columns exist. *Shape:* one boolean row per relation / candidate column (+ data type). *Design effect:* these are the gates that authorize each PASS-2 query. *Fact.*

**A1 / A2 — frozen wrapper contract (expanded).** A1 returns the full catalog identity of `save_weekly_closeout_with_snapshots`: `identity_arguments`, `in_arg_types`, `function_result`, `return_type`, `proretset`, `proallargtypes`, `proargmodes`, `proargnames`, `overload_count`, security/owner/config/ACLs, and `body_md5`. A2 does the same (minus a couple of purely-positional fields) for the three related frozen RPCs and boolean-checks the two pinned md5 baselines. *Shape:* A1 = one row per overload (`overload_count` makes overloading explicit); A2 = 3 rows, `matches_pinned_baseline` true/true/NULL. *Design effect:* pins the exact pass-through signature and result shape D3 must call and the md5 the final-state verifier enforces. *Fact.* Functions are inspected, never invoked.

**B1–B5 — reservation/batch schema.** B1 column metadata; B2 clear-transition column presence; B3 all constraints; B4 the status-CHECK textual heuristic; B5 indexes incl. the one-active-batch partial predicate. *Design effect:* decides whether D3 needs an additive schema checkpoint (columns and/or a widened `status` CHECK). *Fact.*

> **B4 caveat (required):** textual mention of a value in `pg_get_constraintdef()` is **only a heuristic** — the columns are named `definition_mentions_*`, not `admits_*`. A `definition_mentions_x = false` with `status_check_count > 0` is a strong hint a widening is needed, but **actual admissibility is unresolved** unless it is logically unambiguous from the complete constraint definition or is later proven with an approved non-persistent probe. `status_check_count = 0` means no DB CHECK on `status` (DB-level unconstrained).

**C1 / C2 / C3M1–C3M4 — Register evidence model + account-key discovery (redesigned).** C1/C2 = `transactions` column + index metadata. C3M1 = `accounts` columns; C3M2 = presence of candidate fields (key / active / status / type / institution / ledger-role); C3M3 = `accounts` constraints/indexes (key-uniqueness posture); C3M4 = the FK from `transactions.account_key` to `accounts`. *Design effect:* establishes the deterministic source-leg match model **without emitting any key value or row**, and does **not** assume `source_account='truist_checking'` equals `transactions.account_key`.

> **Account-key three-way distinction (required):**
> 1. **Literal-key equality** — PASS-2 `C3AGG.accounts_literal_key_match` counts rows where `accounts.key='truist_checking'` (0/1, no value emitted). This is *only* string equality, not proof of the mapping.
> 2. **Metadata-supported mapping** — C3M1–C3M4 (candidate fields, uniqueness, the transactions→accounts FK) show whether a *unique, well-typed* mapping is even derivable.
> 3. **Policy selection of the authoritative source account** — which account is the canonical checking ledger for evidence matching is an owner **ruling** (Step 7C), informed by 1 + 2, not decided by the preflight.

**D1 — Register data-quality aggregates (PASS 2).** Counts of `posted_date` / `cleared` / `reconciled` / `transfer_pair_id` and their cross-tabs. *Design effect:* resolves **U4** — if `reconciled_true ≈ 0`, the evidence predicate must rely on `cleared` + `posted_date` + in-week date span, not `reconciled`; the mismatch counts size the ambiguity surface. *Fact informs a Policy.* No amounts/rows emitted.

**E1–E3 — week-window source.** Calendar/mapping table, week→date resolver function, date columns on recon/snapshot. *Design effect:* resolves **U2** — whether the date window exists in the DB, is derivable, or must be a caller-supplied parameter to the composite. Parameter *shape* is not decided here. *Fact → Policy.*

**F1–F3 — authorization & RLS (sanitized).** F1 = authz-helper identity/md5/ACLs. F3 = table RLS enablement + `authenticated` INSERT/UPDATE/SELECT posture. **F2 is sanitized:** it emits policy metadata, `qual_present` / `with_check_present` booleans, `md5(qual)` / `md5(with_check)`, and booleans indicating whether each expression references `can_write_financials` / `is_owner` / `auth.uid` / `auth.role`. **Raw `qual` / `with_check` are never emitted** — they may contain identity-bearing literals; a separate safety review must prove they are literal-free before any raw expression is surfaced. *Design effect:* separates what the DB permits, what D2 enforces (owner-only RPC writes), and the **policy** question of the composite's authz posture (`can_write_financials()` vs owner-only). *Fact + Policy.*

**G1 — locking (partial evidence).** Establishes the advisory-lock function used, the **exact advisory-key expression** (a single extracted expression via `substring`, **not** a body), and the `FOR UPDATE` count. It also returns positional offsets (advisory-lock, first `FOR UPDATE`, first `UPDATE`/`INSERT` statement) as **supporting** evidence.

> **Lock-order caveat (required):** G1 does **not** establish full lock order. Positional offsets are *supporting, not definitive* (a substring position is not a control-flow proof). **Full lock order must be resolved through sanitized repository-source analysis of the D2 RPC bodies and, later, a concurrency proof.** The load-bearing design fact G1 fixes is the **exact as-built advisory key** (`au11_disc:'||model_year||':'||source_account`) that D3 must reuse; D3 must reuse it and a compatible acquire-first order unless an approved migration changes ALL lifecycle RPCs together.

**H1 / H2 — current staging residue.** H1 = batch/fixture/reservable counts. H2 = `au11_reservation` commitments as **explicit per-expected-state counts** (`scheduled`, `initiated`, `bank_pending`, `stale_review`, `cleared`, `voided`, `null_status`, `other_status`) — no arbitrary status text is emitted. *Design effect:* confirms a clean baseline (expected zero fixture residue post-D2 teardown) and reveals any pre-existing withholding rows the composite must handle. *Fact.*

**I1 / I2 / I3 — idempotency support (expanded to `transactions`).** I1 = all UNIQUE indexes on cash_commitments / batches / **transactions** / weekly_reconciliations / goal_funding_snapshots. I2 = the `weekly_reconciliations` PK/UNIQUE. I3 = heuristic booleans for whether `transfer_pair_id`, `bank_reference`, `batch_digest`, `expected_item_id`, and the `(batch,goal)` pair appear in any unique index. *Design effect:* determines which duplicate-invocation protections exist and where a duplicate composite call could still double-act — informing (not deciding) the retry policy. *Fact informs a Policy.* (I3 is a text heuristic; confirm exact key membership from the I1/C2 defs.)

---

## Decision matrix

| # | Question | Database evidence required | Preflight query/section | Possible outcomes | Design consequence | DB fact or policy ruling | Blocking for implementation? |
|---|---|---|---|---|---|---|---|
| 1 | Exact frozen-wrapper contract | identity args, result, proretset, argmodes/names, secdef, owner, search_path, ACLs, md5, overload count | A1 | single sig / overloaded / md5 value | Pins the pass-through call + the md5 the verifier enforces | **DB fact** | Yes |
| 2 | Composite RPC signature | wrapper params (1) + week-window inputs (3) + `p_retire` shape | A1 + E1–E3 | derivable vs caller-supplied window | Determines the composite parameter list | **Policy** (informed by facts) | Yes |
| 3 | Week-window inputs | calendar table / resolver fn / date columns | E1, E2, E3 | in-DB / derivable / caller-supplied | Whether the composite takes date-window params (U2) | **DB fact → Policy (shape)** | Yes |
| 4 | Deterministic Register matching | txn columns/indexes, account-key metadata, quality counts | C1, C2, C3M1–M4, D1 | unique mapping? reconciled populated? | Fixes the mandatory source-leg predicate (U1/U4) | **DB fact → Policy (predicate)** | Yes |
| 5 | Duplicate / ambiguous evidence | cross-tabs of cleared/posted/reconciled/transfer_pair | D1 | ambiguity present / absent | Sizes the "ambiguous ⇒ BLOCK" path (§F) | **DB fact → Policy** | Partially |
| 6 | Clear-transition columns | presence of cleared_date / reflected_model_week / resolved_model_week | B1, B2, P1-COL | present / missing | Whether D3 needs an additive-column checkpoint | **DB fact** | Yes (gates Checkpoint A) |
| 7 | Status CHECK compatibility | is status CHECK-constrained; does the def mention `cleared` | B4 (heuristic) | no check / mentions / must widen | Whether a replace-constraint widening is needed | **DB fact (heuristic → confirm)** | Yes (gates Checkpoint A) |
| 8 | Batch terminal-state rules | batch status + resolution_type CHECKs | B3, B5 | admits `retired`/`voided` | Confirms batch→`retired` on full clear is legal | **DB fact** | Yes |
| 9 | Partial posting | per-goal uniqueness + row-level state model | B5, I1, I3 | supported / not | Retire only posted rows; leave others active | **DB fact → Policy** | Partially |
| 10 | Idempotency / retry semantics | UNIQUE keys across 5 tables; recon key; targeted fields | I1, I2, I3 | protections exist / gaps | Shapes the retry/replay guard (not decided here) | **DB fact → Policy** | No (design-time) |
| 11 | Advisory-lock key & lock order | advisory key + FOR UPDATE count + offsets (partial) | G1 (+ later source/concurrency) | `au11_disc:` confirmed; order pending | D3 reuses as-built key + order | **DB fact (key) → Policy (order/change)** | Yes (key) / design-time (order) |
| 12 | Authorization posture | authz helpers + sanitized RLS + write grants | F1, F2, F3 | owner-only vs can_write_financials() | Who may run the composite (Wendy?) | **Policy** (informed by facts) | Yes |
| 13 | Result contract | (design) shape of `{ok, mode, week_num, snapshot_count, retired[…]}` | — (informed by A1) | — | Fixes the composite return + verifier | **Policy** | Yes |
| 14 | Rollback classification | additive-only vs constraint changes | B3, B5, I1 | bare-drop safe / needs care | Rollback valid only while zero AU-11 rows | **DB fact → Policy** | No (design-time) |
| 15 | Disposition of initiated cancelled-at-bank / paid-from-other | state model + evidence columns | B1, B3, H2 | fold into composite / separate RPC / defer | Where the removed-from-D2 dispositions live | **Policy** | Yes (scope boundary) |
| 16 | `bank_pending` / `stale_review` producer scope | no producer in D2 (state model) | B4, H2 | D3 produces / deferred to D4 | Whether D3 adds `mark_bank_pending`/stale detection | **Policy** | Yes (scope boundary) |
| 17 | D3 vs D4 boundary | slice plan (D0 §I) + items 15/16 | — | composite-only vs broader | Defines exactly what D3 ships vs D4 | **Policy** | Yes |

**Facts the preflight settles:** 1, 3 (existence), 4 (existence/metadata), 6, 7 (heuristic, then confirm), 8, 11 (key, as-built), and the residue baseline (H). **Policy rulings reserved for the owner (Step 7C):** 2, 12, 13, 15, 16, 17, plus the final predicate/parameter shapes on 3/4/5/9/10/14 and lock-order on 11. No fact here is a decision.

---

## Execution order for later Step 7B (read-only)
**PASS 1 first (always safe):** P1_PF0A → P1_REL_existence → P1_COL_existence → A1 → A2 → B1 → B2 → B3 → B4 → B5 → C1 → C2 → C3M1 → C3M2 → C3M3 → C3M4 → E1 → E2 → E3 → F1 → F2 → F3 → G1 → I1 → I2 → I3.
**Then PASS 2 (only after gates confirm):** PF0B (iff PF0A passed) → D1 (iff transactions + 4 cols exist) → C3AGG (iff accounts.key + transactions.account_key exist) → H1 (iff batches/goal_registry.reservable/snapshots/weekly_reconciliations.chk exist) → H2 (iff cash_commitments.commitment_source + status exist).
If a PASS-2 prerequisite is not confirmed by PASS 1, **do not run that PASS-2 query** — report the missing object and stop for mapping correction. Claude runs no SQL; Adam executes and returns the evidence.

## Not decided here (explicit)
No composite RPC signature, no evidence predicate, no lock/authz/result/rollback ruling, no D3-vs-D4 boundary, no producer scope, no authoritative source-account selection. **D3 is not implementation-ready and will not be described as such until Step 7C is complete and approved.**
