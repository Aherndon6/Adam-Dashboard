# PKG-TAX-1 — Goal-Transfer Taxonomy Remediation · CLOSEOUT (Step 6A finding L-4)

**Date:** 2026-07-23 · **Target:** production `usayoldrawwmjsmretin`
**Venue:** Supabase SQL Editor — one session, one transaction (required for multi-row atomicity)
**Artifact:** `docs/phase-5g-1d-taxonomy-remediation-pkg-tax-1-2026-07-23.sql` — a **post-execution
archival copy**, **not** byte-identical to the text executed (see *Artifact provenance* below).
**Governance:** executed under the RESTRICTED disposition recorded in
`docs/phase-5g-1d-categories-write-surface-disposition-2026-07-23.md` (committed + pushed at `8c23006`).
**Balance-free:** no account balances appear in this record.

---

## Result: SUCCESS

| stage | outcome |
|---|---|
| §1 preflight | **P0 = `EXPECTED_PRE_STATE`**; P1–P6 all PASS |
| §2 execution | committed — Supabase returned *"Success. No rows returned."* |
| §3 + §4 validation and blast radius | **27 / 27 PASS** |
| application validation | **A1–A8 PASS** (owner-verified after a hard refresh) |

---

## What executed

**2 category INSERTs** — `transfers.goal_funding` ("Goal Funding Transfer") and
`transfers.goal_disbursement` ("Goal Disbursement Transfer"). Both: `parent_key = transfers`,
`is_leaf = true`, `behavior_class = transfer`, `budget_treatment = excluded`,
`cashflow_treatment = excluded`, `lifecycle_status = active`, `is_system = false`,
`display_order` 12020 / 12030.

**4 transaction recategorizations** — three goal-funding legs (2026-07-08 Alaska funding;
2026-07-09 week-5 sweep block; 2026-07-15 Adam IRA top-up) to `transfers.goal_funding`; the
2026-07-21 orphan commission-tax leg to `taxes.vio_transfer_2026`.

**Nothing else.** No schema, code, application, model, deployment, or financial change.

---

## Verification

### §3 validation

| check | result |
|---|---|
| **V1** both categories, all 8 approved fields | PASS — `assignable_in_register = true` for both |
| **V2** Seattle/Alaska category | **3 rows / −607.10** |
| **V3** genuine Alaska charges survive | NCL · Alaska Fishing Licenses · AMC Seattle, all `amex_gold` |
| **V4** goal-funding legs | **3 rows / −11,723.62** |
| **V5** tax-transfer family | **4 rows**, including the recovered orphan |
| **V6** `transfers.goal_disbursement` | **0 rows** — correct; the category is pre-provisioned and **no goal release has been recorded** |

### §4 blast radius

**B1** — the fingerprint over all **57** pre-existing category rows is **IDENTICAL** before and after
(`681a7bc3a791a7c4d817ad06fe73d4fc`). Byte-level proof, not a count.

**B2 — Register integrity aggregate: 197 rows / −$7,527.79, unchanged.** This is a
row-count-and-sum fingerprint over `public.transactions` proving no `amount` was mutated. **It is not
an account balance, cash position, available balance, or spending total.**

**B3–B10** — `weekly_reconciliations` 6 (week 7 open) · `goal_funding_snapshots` 20 ·
`weekly_tasks` 16 · `custom_tasks` 17 · `cash_commitments` 6 · `accounts` 14 ·
`costco_visa` active / null starting balance · `model_week_overrides` weeks [2,3,4,6,7,8] with week-7
`ct = 0`, `ca = 0` and both prior corrections intact.

### Independent effect proofs

- **Model — unaffected.** The deployed model was re-run on live state after execution; the week-7
  reserve-adjusted sweep figure is byte-identical to its pre-execution value. Structurally guaranteed
  too: `transactions` is not among `loadAll()`'s model inputs, so the Register cannot feed the model.
- **Budget — unaffected.** Both new categories return `false` from `_isCountableBudgetSpend` **and**
  `_isCountableBudgetIncome`.
- **Balances — unaffected.** No `amount` was touched; Register balances derive from `amount`, never
  from category.
- **Goal positions — unaffected.** `goal_funding_snapshots` unchanged; every Funded value untouched.

---

## Application evidence (A1–A8 PASS, owner-verified after hard refresh)

| # | check | result |
|---|---|---|
| A1 | both categories in the Register category picker | PASS |
| A2 | both appear under **Transfers** | PASS |
| A3 | neither appears in the July Budget as spending or income | PASS |
| A4 | Seattle/Alaska contains exactly the three genuine charges | PASS |
| A5 | Seattle/Alaska totals exactly **$607.10** | PASS |
| A6 | Goal Funding Transfer contains exactly the three historical funding legs, **$11,723.62** | PASS |
| A7 | Taxes 2026 contains all four tax-transfer rows, including **−$425.68** | PASS |
| A8 | console clean — `[5D-1] Registries loaded: 14 accounts, 59 categories`; no registry-load failure | PASS |

**Goal Disbursement Transfer contains 0 transactions** — confirmed in the application.

---

## Production state after execution

| store | count |
|---|---|
| `categories` | **59** (was 57) |
| `transactions` | 197 *(Register integrity aggregate: 197 rows / −$7,527.79)* |
| `weekly_reconciliations` | 6 — **week 7 remains unreconciled** |
| `goal_funding_snapshots` | 20 |
| `weekly_tasks` | 16 |
| `custom_tasks` | 17 |
| `cash_commitments` | 6 |
| `accounts` | 14 |

---

## Repository, deployment, and commit state

No code change and no `BUILD_TS` change; **nothing deployed**. At execution the repository stood at
**`8c23006`** (DOC-TAX-1), working tree clean and synced with `origin/main`.

---

## Artifact provenance — the archived SQL is a post-execution copy

**`docs/phase-5g-1d-taxonomy-remediation-pkg-tax-1-2026-07-23.sql` is a post-execution archival copy
of the executed PKG-TAX-1 SQL package. It is NOT byte-identical to the text run in the SQL Editor,
and this record makes no claim that it is.**

**The pre-execution source was not preserved as a file.** It existed only in the execution package and
was overwritten twice after execution — first by the relabelling patch, then by a re-sync from the
stamped copy. It was never committed, so no git history exists for it either. The as-executed text
held alongside this artifact in the execution package is a **reconstruction derived from the recorded
post-execution edits**, not a preserved original.

### Exactly what changed after execution — four edits, three classes

| # | location | change |
|---|---|---|
| 1 | header block | **comment only** — replaced the "Prepared / NOT EXECUTED" banner with the execution stamp and this provenance note |
| 2 | §1 P2 (read-only preflight) | 3 comment lines added; SELECT output label `'P2 tx-global'` → `'P2 register-integrity-aggregate'`; SELECT reformatted onto two lines |
| 3 | §2 E5i (**inside the transaction**) | 1 comment line added; `RAISE EXCEPTION` message text relabelled |
| 4 | §4 B2 (read-only blast radius) | 1 comment line added; SELECT output label `'B2 tx-global'` → `'B2 register-integrity-aggregate'`; SELECT reformatted |

All four applied the owner-approved **"Register integrity aggregate"** label (ruling of 2026-07-23).

### What did NOT change

**No DDL or DML statement was altered.** The category `INSERT`, all four transaction `UPDATE`s, the
E0 idempotency gate, the temp-table before-image captures, and **every assertion condition** are
unchanged.

**The three altered string literals do not execute.** Two are SELECT *output labels* in the read-only
§1 and §4 sections, outside the transaction — they affect only the column header in a result grid.
The third is a `RAISE EXCEPTION` message inside §2 that **never fired**, because the assertion it
belongs to passed. **Executed behaviour is therefore unchanged**, even though the bytes are not.

> The precise characterization is: *header/comment metadata **and three non-executing SQL string
> literals** were changed after execution.* It would be inaccurate to say only documentation metadata
> changed — string literals inside SQL statements were touched, and this record says so.

**Rerun status: PROHIBITED.** The archival copy is a one-shot record. The E0 gate would raise
`ALREADY APPLIED` and mutate nothing, but the artifact must not be re-run.

**Full delta and the reconstructed as-executed text** are retained in the execution package outside
this repository (`PKG-TAX-1-post-execution-delta.diff` and
`PKG-TAX-1-AS-EXECUTED-reconstructed-2026-07-23.sql`).

---

## Scope boundary — no goal disbursement has begun

This package created the Register **vocabulary** for goal transfers. It did **not** perform, initiate,
schedule, or record any goal disbursement:

- **No bank transfer** was initiated, for Alaska or any other goal.
- **No Register row** was created for any release — `transfers.goal_disbursement` holds **0 rows**.
- **No Goal Ledger event** was created or advanced.
- **No `goal_funding_snapshots` row** was written; every goal's Funded position is unchanged.
- **AU-8 has not begun.** The Alaska release remains prepared and unexecuted under its own separate
  authorization.

---

## Disposition

**Step 6A finding L-4 is CLOSED.** The Seattle/Alaska trip category now reports genuine trip
consumption only ($607.10 across three charges), the three historical goal-funding legs are grouped
under a single durable category, and the orphaned commission-tax leg is filed with its siblings.

**Residual, unchanged by this package:** the goal-disbursement *lifecycle* — the ledger events that
make a release reduce Custody — remains owned by **5G-1B**. This package delivered the Register
vocabulary, not the lifecycle.

---

## Cross-references

- Governance disposition: `docs/phase-5g-1d-categories-write-surface-disposition-2026-07-23.md`
- Executed artifact: `docs/phase-5g-1d-taxonomy-remediation-pkg-tax-1-2026-07-23.sql`
- Finding L-4: `docs/phase-5g-1d-step6a-production-evidence-2026-07-23.md`
- Step 6B canonical plan: `docs/phase-5g-1d-step6b-canonical-plan-2026-07-23.md`
- Execution ledger row: `docs/execution-ledger.md`
