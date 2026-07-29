# Step 8 — Actual Checking Capacity Baseline — Execution Record (2026-07-28)

**Canonical name:** Post-BKX Stabilization Step 8 — **Actual Checking Capacity Baseline**
(namespace `step8-actual-checking-capacity`). This is **not** the canonical AU-11 / 6C-D4
lifecycle work, which retains its own scope (authenticated end-to-end reservation lifecycle,
client routing, disposition, role matrix) and is untouched here.

## Status

*Updated 2026-07-28: Baselines A and B executed by the owner under the controlled read-only
procedure against production; Baseline C is APPROVED / FROZEN (owner-approved after independent
Fable review) — NOT executed. No production mutation occurred.*

| Field | Value |
|---|---|
| A/B design review status | **APPROVED / FROZEN** |
| Baseline A execution | **EXECUTED** (owner-run, read-only, production `usayoldrawwmjsmretin`) |
| Baseline B execution | **EXECUTED — PASS WITH DOCUMENTED OWNER-REVIEWED EXCEPTIONS** (owner-run, read-only; see Execution evidence) |
| Baseline C status | **APPROVED / FROZEN — NOT EXECUTED** (owner-approved after Fable review; frozen at the hash below) |
| Production mutation status | **NONE** |
| A/B execution parameters | **ADOPTED for the A/B run** — `cutoff_ts=2026-07-28 18:00:00-04:00`, `cutoff_business_date=2026-07-28`, `inspection_start_date=2026-06-30` (see Execution evidence) |
| Live-bank snapshot (Baseline F) | **NOT CAPTURED** — the final synchronized capacity cutoff (SQL cutoff paired with a live bank snapshot) is therefore **not yet finalized** |
| Operational result | **HOLD** |

## Stored artifacts

| Artifact | Path | SHA-256 | Status |
|---|---|---|---|
| Baseline A — Environment & Schema Safety (read-only) | `docs/step8-actual-checking-capacity-A-environment-schema-safety.sql` | `43e97e8c048c76473da561d3977b026859d3b6f3e96fb5d97cb0b609e9a13b9b` | **FROZEN · EXECUTED** |
| Baseline B — Checking Account & Register State (read-only) | `docs/step8-actual-checking-capacity-B-checking-register-state.sql` | `df9962ceb10ea3c16b8b70d55a0d1a27e9f173750b99c77bc98abcca515796da` | **FROZEN · EXECUTED (pass w/ documented exceptions)** |
| Baseline C — Reconciliation & Week State (read-only) | `docs/step8-actual-checking-capacity-C-reconciliation-week-state.sql` | `8b4169726b81b7b63185734399b969f5b83a4d965a8728ed07f5a3a3460996fb` | **APPROVED / FROZEN — NOT EXECUTED** (owner-approved after Fable review; frozen hash; pre-review draft was `59240e54…aed5db`) |

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
  hardening); see "Baseline C — independent (Fable) review".** **APPROVED / FROZEN** (owner-approved
  2026-07-28) at `8b4169726b81…` — **NOT executed**.
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

- Baseline C (reconciliation & week state) — **APPROVED / FROZEN; NOT executed** (owner-run execution pending; see Stored artifacts).
- Baseline D (obligations & inflows), Baseline E (model comparison & trough) — **not drafted**.
- Baseline F (owner-supplied live bank snapshot) — **not captured**.
- Final capacity calculation and final validation — **pending**, to be assembled in the external
  execution evidence package (values remain out of the repository per the balance-free policy).

## Governance

- Standing holds remain in force: engine hold, Wendy IRA hold, discretionary-transfer deferrals,
  controlled goal-funding/disbursement rules. **Baselines A and B were executed by the owner under the
  controlled read-only procedure against production (`usayoldrawwmjsmretin`); every statement is
  SELECT / read-only metadata inspection, so production mutation status remains NONE.** **Claude has
  executed no SQL against production or staging.** Baseline C has not been executed.

## Next authorized action

**Step 8 — Execute Baseline C (Reconciliation & Week State) under the controlled owner-run, read-only
production procedure** (owner-run; Claude runs no SQL). Baseline C is APPROVED / FROZEN at
`8b4169726b81b7b63185734399b969f5b83a4d965a8728ed07f5a3a3460996fb`. Baselines A and B are complete
(executed, read-only, zero production mutation, B pass-with-documented-exceptions); Baselines D, E, F,
the final capacity calculation, and final validation remain pending. Step 8 is **NOT complete**.
