# Step 8 — Actual Checking Capacity Baseline — Execution Record (2026-07-28)

**Canonical name:** Post-BKX Stabilization Step 8 — **Actual Checking Capacity Baseline**
(namespace `step8-actual-checking-capacity`). This is **not** the canonical AU-11 / 6C-D4
lifecycle work, which retains its own scope (authenticated end-to-end reservation lifecycle,
client routing, disposition, role matrix) and is untouched here.

## Status

*Updated 2026-07-28: Baselines A, B, and C all executed by the owner under the controlled read-only
procedure against production. Baseline C (frozen `8b4169726b81…`, 330 lines) executed
statement-by-statement and PASSED (C4.OVERALL = C_PREREQ_PASS). No production mutation occurred;
operational result remains HOLD; checking capacity is NOT yet established.*

| Field | Value |
|---|---|
| A/B design review status | **APPROVED / FROZEN** |
| Baseline A execution | **EXECUTED** (owner-run, read-only, production `usayoldrawwmjsmretin`) |
| Baseline B execution | **EXECUTED — PASS WITH DOCUMENTED OWNER-REVIEWED EXCEPTIONS** (owner-run, read-only; see Execution evidence) |
| Baseline C status | **APPROVED / FROZEN / EXECUTED — PASS** (owner-run, read-only; C4.OVERALL = C_PREREQ_PASS; see Baseline C execution evidence) |
| Baseline D status | **APPROVED / FROZEN — NOT EXECUTED** (owner-approved rev-3 after Fable review; frozen at the hash below; no capacity calculated) |
| Production mutation status | **NONE** |
| A/B execution parameters | **ADOPTED for the A/B run** — `cutoff_ts=2026-07-28 18:00:00-04:00`, `cutoff_business_date=2026-07-28`, `inspection_start_date=2026-06-30` (see Execution evidence) |
| Live-bank snapshot (Baseline F) | **NOT CAPTURED** — the final synchronized capacity cutoff (SQL cutoff paired with a live bank snapshot) is therefore **not yet finalized** |
| Operational result | **HOLD** |

## Stored artifacts

| Artifact | Path | SHA-256 | Status |
|---|---|---|---|
| Baseline A — Environment & Schema Safety (read-only) | `docs/step8-actual-checking-capacity-A-environment-schema-safety.sql` | `43e97e8c048c76473da561d3977b026859d3b6f3e96fb5d97cb0b609e9a13b9b` | **FROZEN · EXECUTED** |
| Baseline B — Checking Account & Register State (read-only) | `docs/step8-actual-checking-capacity-B-checking-register-state.sql` | `df9962ceb10ea3c16b8b70d55a0d1a27e9f173750b99c77bc98abcca515796da` | **FROZEN · EXECUTED (pass w/ documented exceptions)** |
| Baseline C — Reconciliation & Week State (read-only) | `docs/step8-actual-checking-capacity-C-reconciliation-week-state.sql` | `8b4169726b81b7b63185734399b969f5b83a4d965a8728ed07f5a3a3460996fb` | **APPROVED / FROZEN / EXECUTED — PASS** (owner-approved + owner-executed 2026-07-28; C4.OVERALL = C_PREREQ_PASS; pre-review draft was `59240e54…aed5db`) |
| Baseline D — Obligations & Inflows (read-only) | `docs/step8-actual-checking-capacity-D-obligations-inflows.sql` | `6de0f8e554cb1a961f362229fa61d27ffa102a2d8240e4604aaeb1de75d8b893` | **APPROVED / FROZEN — NOT EXECUTED** (owner-approved rev-3 after Fable review; F5 fully applied + uncleared handoff tightened; rev-2 `9d2569c4…df235`; rev-1 `b3d3c97f…ded14c`) |

- Baseline A: 167 lines / 19,071 bytes / 5 statements (A0 session metadata, A1 required tables,
  A2 required columns, A3 AU-11 production-absence, A4 phased gates).
- Baseline B: 367 lines / 32,339 bytes / 13 statements (B1a target gate, B1b plausible candidates,
  B1c application ledger cap, B2 anchor integrity, B3 register aggregates, B4 recent transactions,
  B5_PRIMARY duplicate candidates, B5_FULL_HISTORY duplicate candidates, B6a transfer-pair populated,
  B6b transfer candidates heuristic, B7a post-cutoff drift counts, B7b post-cutoff drift detail,
  B8 sign reference classes).
- Baseline C: **330 lines / 21,984 bytes / 5 statements** (C0 schema preflight [self-gate for the
  goal_funding_snapshots + weekly_reconciliations columns A did not hard-validate], C1 reconciliation
  inventory, C2 week-state matrix, C3 ledger coverage by week, C4 reconciliation prerequisites).
  Read-only; balance-free (presence flags / counts / states / enum labels only — never a chk/sav/amx/
  tax/lc or funded_amount value); no DDL/DML/RPC; one result set per block. Depends on A4 gate C
  (and gate B + Baseline B's B1a=TARGET_OK for C3) plus its own C0 self-gate; the AU-11 global stop and
  manual project confirmation still apply. **Revised per the Fable review (F1/F2 required + F3–F8
  hardening); see "Baseline C — independent (Fable) review".** **APPROVED / FROZEN / EXECUTED — PASS**
  (owner-approved + owner-executed 2026-07-28) at `8b4169726b81…`; see "Baseline C — execution evidence".
- SHA-256 computed via `shasum -a 256 <file>` on the stored files.

## Execution evidence (Baselines A + B)

*Balance-free record. Actual balances and result values remain in the external execution evidence package,
not in this repository.*

| Field | Value |
|---|---|
| Owner / operator | Adam (owner; `aherndon6@gmail.com`), Supabase SQL Editor, owner session |
| Production project ID | `usayoldrawwmjsmretin` (project-selector visually confirmed = `A0_OPERATOR_PROJECT_CONFIRMATION`) |
| Execution date | 2026-07-28 |
| Execution mode | Read-only (SELECT / read-only metadata inspection); **Claude ran no SQL** |
| Parameters used (B) | `cutoff_ts=2026-07-28 18:00:00-04:00` · `cutoff_business_date=2026-07-28` · `inspection_start_date=2026-06-30` |
| No-mutation confirmation | **NONE** — no INSERT/UPDATE/DELETE/DDL/DML/RPC ran; production byte-state unchanged |

**Baseline A — verdict: PASS.** Environment/schema gates evaluated; AU-11 objects absent (global stop not
triggered); manual project confirmation recorded. (Per-gate verdicts captured in the external package.)

**Baseline B — verdict: PASS WITH DOCUMENTED OWNER-REVIEWED EXCEPTIONS.** Result-set findings and dispositions:

| Result set | Finding | Owner disposition |
|---|---|---|
| B1a / B1c | Truist Checking uniquely identified; application ledger cap evaluated | Accepted |
| B2 / B3 | **July 1 anchor-date overlap** — the starting-balance anchor snapshot (captured the morning of July 1) overlaps the **July 1 $2,000 rent** transaction on the anchor date | Reviewed and understood; historical as-of-cutoff figure treated per the anchor-overlap review path (provisional/owner-reconciled), not FINAL — **owner-reviewed exception** |
| B4 | Recent-transaction window inspected; incl. **one uncleared +$15 transaction from Bailey** | Reviewed; legitimate pending inflow — **owner-reviewed exception** |
| B5_PRIMARY | **Two duplicate candidates** surfaced | Both **owner-resolved as legitimate** (not duplicates) |
| B5_FULL_HISTORY | **No rows** returned | Clean |
| B6a | **No populated `transfer_pair_id` rows** | Consistent with app (column unpopulated) — clean |
| B6b | **15 single-candidate heuristic transfer pairs; zero ambiguous** | All **owner-reviewed**; heuristic-only, not confirmed pairings |
| B7a / B7b | **Zero post-cutoff drift** (no created-after / edited-after / backdated / posted-after rows) | Clean |
| B8 | **One `PAYMENT_LIKE_BUT_POSITIVE` candidate** | **Owner-resolved as expected** (legitimate) |

**No B result is checking capacity or transfer authorization.** All figures/values were retained in the
external evidence package; operational result remains **HOLD**.

## Baseline C — independent (Fable) review

**Verdict: APPROVE-WITH-REQUIRED-CHANGES.** Read-only, balance-free, deterministic, no capacity-authorization
surface, and no B/D/E overlap were all confirmed. Two required fidelity/operability fixes (F1, F2) and six
recommended hardening items (F3–F8) were raised; **all eight applied** in the revised artifact
(`8b4169726b81…`). **Owner-approved 2026-07-28 → Baseline C is APPROVED / FROZEN at that hash — NOT executed.**

| ID | Sev | Finding | Disposition (applied) |
|---|---|---|---|
| F1 | MAJOR (req) | C2 closeout CASE could not emit the app's `corrupt` hard-stop state and mislabeled unreconciled-with-snapshots and reconciled-with-0-snapshots | C2 CASE made **total + app-faithful**: added `corrupt_db_derived` (¬reconciled ∧ ≥1) and `half_closed_db_derived` for reconciled ∧ <9 (incl 0); renamed `open`→`open_or_blocked_db_derived` (F6) |
| F2 | MAJOR (req) | C4.5 counted **all** reconciled weeks with NULL basis while its own expected-text called legacy NULLs legitimate → could permanently pin OVERALL at REVIEW | C4.5 **scoped to post-anchor (≥6)** and fed to OVERALL; legacy NULL basis moved to **C4.11 INFO (excluded from OVERALL)** |
| F3 | MINOR | `reconciled` defined as `chk IS NOT NULL` is stricter than the deployed predicate (row-existence) → could under-report immutability | `reconciled` redefined as **row-existence** across C2/C3/C4 (matches `isWeekReconciled`/engine); NULL-chk rows surfaced by new **C4.9** and C1.chk_present |
| F4 | MINOR | C4.9 (recorded_at monotonic) was "informational" yet gated OVERALL → owner-approved historical corrections would pin REVIEW | Moved to **C4.12 INFO, excluded from OVERALL** |
| F5 | MINOR | C4.4 used `count(*)`; duplicates could mask a prefix hole | Uses **`count(DISTINCT week_num)`** |
| F6 | MINOR | C2 `open` conflated app `open` and `blocked_prior_incomplete` | Relabeled **`open_or_blocked_db_derived`** (folded into F1) |
| F7 | MINOR | No named control for snapshots on pre-anchor weeks / unreconciled anchor | Added **C4.10** (no 2026 snapshots on weeks ≤4 or on an unreconciled week 5) |
| F8 | NIT | C3 all-zero counts indistinguishable from a missing checking account | Added **`checking_account_present`** column + B1a=TARGET_OK precondition |

Fable-confirmed CORRECT (no change): Week-5 anchor treatment (#3), nine-goal completeness `DISTINCT eligible ≥9 ≡ =9` (#4), epoch date arithmetic with no off-by-one and DST-safe within the horizon (#6), and PostgreSQL syntactic validity of all constructs.

## Baseline C — execution evidence (PASS)

*Owner-run, read-only, statement-by-statement in the Supabase SQL Editor against production
`usayoldrawwmjsmretin`, 2026-07-28. Frozen artifact `8b4169726b81b7b63185734399b969f5b83a4d965a8728ed07f5a3a3460996fb`
(330 lines). Claude ran no SQL. No production mutation. Balance-free record — counts/states only; no balances.*

- **C0 — environment / schema gate: PASS** (`C_GATE_PASS`). All 19 required table/column checks present:
  `weekly_reconciliations` {week_num, chk, sav, amx, tax, lc, balance_basis, recorded_at};
  `goal_funding_snapshots` {model_year, week_num, goal_id, source}; `transactions` {account_key,
  transaction_date}; `accounts` {key}.
- **C1 — reconciliation inventory: PASS.** Reconciliation rows exist for **weeks 1–7 only**; every row is
  within domain 1..31 and has all five balances present (chk/sav/amx/tax/lc). `balance_basis`: weeks 1–3
  NULL (legacy informational — not a gating defect), weeks 4–5 `posted_current_balance`, weeks 6–7
  `available_balance`.
- **C2 — week-state matrix: PASS.** Weeks 1–4 `legacy_pre_anchor` (reconciled, immutable, no snapshots);
  week 5 `anchor` (reconciled, immutable, 9 distinct eligible / 11 total snapshot rows); weeks 6–7
  `complete_db_derived` (reconciled, immutable, 9 distinct eligible / 9 total each); weeks 8–31
  `open_or_blocked_db_derived` (unreconciled, not immutable, no snapshots). **No `half_closed` and no
  `corrupt` state appeared.**
- **C3 — checking ledger coverage (INFERRED spans): PASS.** `checking_account_present = 1` for all rows.
  Checking transaction counts by inferred model-week span: wk1 0, wk2 0, wk3 0, wk4 8, wk5 12, wk6 9,
  wk7 18; weeks 8–31 unreconciled, 0. Weeks 1–3 zero-activity is compatible with the Register's ~July-1
  operational start (not a defect). No future-week activity. Spans inferred from epoch 2026-06-07; not
  stored week boundaries.
- **C4 — reconciliation prerequisite gate: `C4.OVERALL = C_PREREQ_PASS`.** All ten gating checks PASS —
  C4.1 no duplicate week_num (0); C4.2 weeks in 1..31 (0 violations); C4.3 anchor week 5 reconciled (1);
  C4.4 contiguous reconciled prefix (true); C4.5 post-anchor (≥6) non-NULL balance_basis (0 violations);
  C4.6 post-anchor closeouts 9 distinct eligible (0 violations); C4.7 no snapshots on unreconciled ≥6 (0);
  C4.8 snapshot weeks in 1..31 (0 violations); C4.9 no NULL-chk rows (0); C4.10 no snapshots on pre-anchor
  ≤4 / unreconciled anchor 5 (0). **Informational (excluded from OVERALL):** C4.11 = 3 legacy (≤5) rows
  with NULL balance_basis (matches the weeks 1–3 NULL basis); C4.12 = 0 recorded_at inversions.

**Interpretation.** The reconciliation/closeout ledger is internally consistent through week 7: a clean
contiguous reconciled prefix (weeks 1–7), a valid reconciled anchor (week 5), and complete post-anchor
closeouts (weeks 6–7). **This is a reconciliation/week-state integrity pass only — it establishes NO
checking-capacity figure and authorizes no transfer.** Operational result remains **HOLD**.

## Baseline D — design (APPROVED / FROZEN — NOT EXECUTED)

*`docs/step8-actual-checking-capacity-D-obligations-inflows.sql` — **APPROVED / FROZEN** (owner-approved 2026-07-28)
at SHA-256 `6de0f8e554cb1a961f362229fa61d27ffa102a2d8240e4604aaeb1de75d8b893`, **658 lines**, **11** read-only
result sets (D0, D1, D2, D2B, D3, D4, D5, D6, D7, D8, D9). **NOT executed** — no capacity calculated, no transfer
authorized, operational HOLD remains. Independently Fable-reviewed (**APPROVE-WITH-REQUIRED-CHANGES**); rev-2 applied
F1/F2 + accuracy F3/F4/F6/F8; rev-3 (owner-required) fully applies **F5** and tightens the uncleared-Register handoff.
Rev-2 `9d2569c4…df235`; rev-1 `b3d3c97f…ded14c`.*

- **Fable review (APPROVE-WITH-REQUIRED-CHANGES), dispositions:** **F1 (MAJOR, applied)** — the engine's reserve
  set for an UNRECONCILED as-of week uses a stricter *projected branch* (`index.html:3166-3171`: `origin<w` +
  origin-reconciled-or-`historical_repair`), not plain `isReservedAsOf`; D3/D7 now compute a branch-correct
  `is_engine_reserved` and D9's E-contract states which branch applied so E does not double-count the WD base
  schedule. **F2 (MAJOR, applied)** — added **D2B** enumerating uncleared `truist_checking` Register debits (a DB
  obligation class D otherwise missed) + a `uncleared_register_items_count` in D9, so E cannot silently overstate
  capacity. **F3 (applied)** — `as_of_model_week` echoed in D3/D5/D7/D9/D1. **F4 (applied)** — FSA cited to
  `phase-5d-1-migration.sql:401,412`; "reminder-only" restricted to Jabian. **F6 (applied)** — amount-exposure
  header corrected (D4 is amount-bearing for owner-review). **F8 (applied)** — D4 `direction` enum fixed; goal-snapshot
  rows relabeled as context, not obligations. **F5 / F7 (DEFERRED, owner call)** — broaden BKX/near-amount dedup to
  `$700.91` + payee match (F5); D6 class-1 grouping tidy (F7, moot under the UNIQUE constraint). Fable confirmed:
  read-only, deterministic, SQL-valid, no capacity number, no transfer authorization, inflows not overstated.
- **Rev-3 (owner-required, applied):** **F5 fully applied** — BKX evidence (amount `70090/70091` ±1¢, or payee/notes
  `%bkx%`/`%extra bk%`) and commission-tax overlap (`commitment_class='tax_transfer'` with a completed `commission_tax`
  leg within ±1 model week of origin/reflected OR ±1¢ of amount — catches carry-forward, partial-same-week, rounding)
  are flagged in D3, **routed to `owner_review_required`, and EXCLUDED from the D7 authoritative total**; D6 classes
  broadened + limitations documented; D9 emits `D_HANDOFF_FAIL_STOP` while any engine-reserved overlap candidate
  exists. **Uncleared-Register handoff tightened** — D2B classifies each item `uncleared_class ∈ {valid_candidate,
  overlap_owner_review, malformed}`; D9 fails on any malformed/overlap uncleared item and hands E the deterministic
  `valid_candidate` set (not a bare count). **F7 stays DEFERRED** — operationally immaterial: `expected_item_id` is
  UNIQUE (`phase-5f-1-migration.sql:50`), so D6 class-1's extra GROUP BY keys cannot mask a true duplicate and D9's
  eid-only grouping is the authoritative duplicate gate.

- **Purpose.** Establish the authoritative DB-representable near-term checking **obligations** and **inflows** that
  must feed the actual-checking-capacity calculation (Baseline E / final). Baseline D computes **no capacity
  figure** and authorizes **no transfer**.
- **Authoritative obligation source (grounded).** `cash_commitments` (Phase 5F-1). The deployed Cash Availability
  Engine (`index.html:2453-2463`) withholds capacity for `source_account='truist_checking'` rows where
  `isReservedAsOf(c, weekN)` (`index.html:2438-2448`) is true; that predicate is encoded **verbatim** in D3/D5/D7/D9.
  Floor `OP_FL=6500` (`index.html:896`) is handed to E, not applied here.
- **Headline limitation (grounded).** The base modeled inflows/obligations — paychecks, rent, **all card payments**,
  Kia, and the wk15 Alaska $7,000 draw — are **hardcoded in JS** (`WD` array, `index.html:909-941`; Alaska draw
  `:3056-3068`) and are **invisible to SQL**. Baseline D inventories only the DB overlays and hands the code-side
  base schedule + forward modeled inflows to E as **out-of-band** inputs (D1, D8, D9).
- **Horizon & cutoff (derived, not assumed).** Horizon = **31 model weeks** = `WD` length (`index.html:909-941`);
  wk1 = 2026-06-07 (`index.html:3441`) → wk31 ≈ 2027-01-09 (calendar spans INFERRED). Cutoff = the **model-week
  integer** as-of (`getCurrentWeek`, `index.html:3441`) + `model_year=2026`; `due_date`/card-close dates are
  descriptive-only and never gating. `transaction_date` is used only for the Register overlay (D2/D5) and never
  mixed with the model-week cutoff. `p_as_of_model_week` is a parameter (illustrative default 8; owner-set at capture).
- **Amount-exposure rationale.** D validates obligations/inflows, which are inherently amount-bearing. Amount-bearing
  sets: **D2** (inflow magnitudes), **D3** (`amount_cents` reserve magnitudes — the exact values the engine sums),
  **D6** (amounts used only to match duplicate candidates), **D7** (aggregated authoritative totals for the E handoff).
  Amounts are minimized to obligation/inflow magnitude only; **no account balances** are exposed (balances are
  Baseline B/C), no raw ledger dumps, and each amount is labeled modeled/posted/completed/cleared/inferred.
  `custom_tasks` has **no amount column** (BKX $700.90 in label text) so D4 exposes no amount and routes to owner-review.
- **Known unresolved review items (D8, must stay OUTSIDE the capacity calc until resolved).** Code-side WD base
  schedule not in DB; forward modeled inflows code-side; **BKX $700.90** amount in `custom_tasks.label` text;
  `custom_tasks` not read by the model (pre-AU-11 gap); `weekly_tasks` has no `model_year`; commission-tax **obligation
  total** is client-side (only executed legs are in DB); Alaska reimbursement is a scheduled `goal_disbursement` not yet
  recorded; Jabian & FSA reimbursements excluded (net-zero, reminder-only); Baseline B uncleared **+$15** Bailey inflow;
  Baseline B `PAYMENT_LIKE_BUT_POSITIVE` (owner-resolved); Baseline C future weeks 8–31 zero checking txns (expected);
  production is pre-AU-11 (discretionary reservations not represented).
- **Operational HOLD remains.** No D result is a capacity figure or transfer authorization; engine + Wendy IRA + all
  discretionary-transfer holds remain in force.

## Binding notes

- **Cutoff status (reconciled).** The three cutoff parameters carried in the SQL artifacts as illustrative
  literals — `cutoff_ts=2026-07-28 18:00:00-04:00`, `cutoff_business_date=2026-07-28`,
  `inspection_start_date=2026-06-30` — were **adopted by the owner as the operative parameters for the A/B
  production run** and are the values Baseline B actually executed against. They remain editable literals in
  the reusable SQL text (not hard-frozen constants). Separately, **no live bank snapshot (Baseline F) was
  captured**, so the *final synchronized capacity cutoff* (the SQL cutoff paired with a live bank balance)
  is **not yet finalized** and no live-bank balance is claimed to exist. This resolves the earlier
  "executed but cutoff not set" inconsistency: A/B ran with adopted parameters; the capacity cutoff /
  Baseline F remain open.
- **No A/B/C result is checking capacity or transfer authorization.** The full-DB aggregate is the
  complete database-derived ledger calculation, subject to starting-balance-anchor validation,
  duplicate review, transfer review, cutoff integrity, and reconciliation to the live bank snapshot,
  which remains the **primary actual-balance truth**. Baseline C validates reconciliation/closeout
  integrity and week state only (balance-free); it computes no capacity and makes no live-balance
  assumption. No figure produced by A, B, or C authorizes any transfer, and the operational result
  stays **HOLD**.
- **Environment identity is a two-part control.** `A0_OPERATOR_PROJECT_CONFIRMATION` (operator visually
  confirms the Supabase SQL-Editor project selector = `usayoldrawwmjsmretin`) is external and cannot be
  proven by SQL; `A1`–`A4` provide the SQL-side fingerprint and per-gate verdicts. Baseline B statements
  run only when their gate = `GATE_PASS` (B; B6 for B6a; B6+BCAT for B6b; BCAT for B8) **and** the manual
  project confirmation is recorded. Any AU-11 object present is a global stop.
- **Target environment:** production Supabase `usayoldrawwmjsmretin` (read-only). Staging
  `pkwotgqivgaapwuqgwqb` and the AU-11 D1/D2/D3 objects are out of scope; A3 confirms their absence.

## Pending (NOT started)

- Baseline D (obligations & inflows) — **APPROVED / FROZEN; NOT executed** (owner-run execution pending; see "Baseline D — design").
- Baseline E (model comparison & trough) — **not drafted**.
- Baseline F (owner-supplied live bank snapshot) — **not captured**.
- Final capacity calculation and final validation — **pending**, to be assembled in the external
  execution evidence package (values remain out of the repository per the balance-free policy).
- (Baselines A, B, and C are executed — see Stored artifacts / execution-evidence sections.)

## Governance

- Standing holds remain in force: engine hold, Wendy IRA hold, discretionary-transfer deferrals,
  controlled goal-funding/disbursement rules. **Baselines A, B, and C were executed by the owner under the
  controlled read-only procedure against production (`usayoldrawwmjsmretin`); every statement is
  SELECT / read-only metadata inspection, so production mutation status remains NONE.** **Claude has
  executed no SQL against production or staging.** No capacity figure has been established; no transfer is
  authorized; the operational result remains **HOLD**.

## Next authorized action

**Step 8 — Design Baseline D (obligations & inflows), obtain independent (Fable) review, freeze it, and
only then seek authorization to execute it** (owner-run; Claude runs no SQL). Baselines A, B, and C are
complete (executed, read-only, zero production mutation; C passed `C4.OVERALL = C_PREREQ_PASS`).
**Checking capacity has NOT been established** — Baselines D and E, the Baseline F live-bank snapshot, the
final capacity calculation, and final validation all remain pending, and **no transfer is authorized**.
Operational result remains **HOLD**. Step 8 is **NOT complete**.
