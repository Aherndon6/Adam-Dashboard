# Step 8 — Actual Checking Capacity Baseline — Execution Record (2026-07-28)

**Canonical name:** Post-BKX Stabilization Step 8 — **Actual Checking Capacity Baseline**
(namespace `step8-actual-checking-capacity`). This is **not** the canonical AU-11 / 6C-D4
lifecycle work, which retains its own scope (authenticated end-to-end reservation lifecycle,
client routing, disposition, role matrix) and is untouched here.

## Status

| Field | Value |
|---|---|
| A/B design review status | **APPROVED / FROZEN** |
| Execution status | **NOT EXECUTED** |
| Production mutation status | **NONE** |
| Actual cutoff status | **NOT YET SET** (illustrative values in the SQL are placeholders) |
| Operational result | **HOLD** |

## Frozen artifacts

| Artifact | Path | SHA-256 |
|---|---|---|
| Baseline A — Environment & Schema Safety (read-only) | `docs/step8-actual-checking-capacity-A-environment-schema-safety.sql` | `43e97e8c048c76473da561d3977b026859d3b6f3e96fb5d97cb0b609e9a13b9b` |
| Baseline B — Checking Account & Register State (read-only) | `docs/step8-actual-checking-capacity-B-checking-register-state.sql` | `df9962ceb10ea3c16b8b70d55a0d1a27e9f173750b99c77bc98abcca515796da` |

- Baseline A: 167 lines / 19,071 bytes / 5 statements (A0 session metadata, A1 required tables,
  A2 required columns, A3 AU-11 production-absence, A4 phased gates).
- Baseline B: 367 lines / 32,339 bytes / 13 statements (B1a target gate, B1b plausible candidates,
  B1c application ledger cap, B2 anchor integrity, B3 register aggregates, B4 recent transactions,
  B5_PRIMARY duplicate candidates, B5_FULL_HISTORY duplicate candidates, B6a transfer-pair populated,
  B6b transfer candidates heuristic, B7a post-cutoff drift counts, B7b post-cutoff drift detail,
  B8 sign reference classes).
- SHA-256 computed via `shasum -a 256 <file>` on the stored files.

## Binding notes

- **Illustrative cutoff values remain placeholders.** `cutoff_ts` (`2026-07-28 18:00:00-04:00`),
  `cutoff_business_date` (`2026-07-28`), and `inspection_start_date` (`2026-06-30`) are examples only;
  the real values are set by the owner at live bank-snapshot capture (Baseline F) and are **NOT frozen**.
- **No A/B result is checking capacity or transfer authorization.** The full-DB aggregate is the
  complete database-derived ledger calculation, subject to starting-balance-anchor validation,
  duplicate review, transfer review, cutoff integrity, and reconciliation to the live bank snapshot,
  which remains the **primary actual-balance truth**. No figure produced by A or B authorizes any
  transfer, and the operational result stays **HOLD**.
- **Environment identity is a two-part control.** `A0_OPERATOR_PROJECT_CONFIRMATION` (operator visually
  confirms the Supabase SQL-Editor project selector = `usayoldrawwmjsmretin`) is external and cannot be
  proven by SQL; `A1`–`A4` provide the SQL-side fingerprint and per-gate verdicts. Baseline B statements
  run only when their gate = `GATE_PASS` (B; B6 for B6a; B6+BCAT for B6b; BCAT for B8) **and** the manual
  project confirmation is recorded. Any AU-11 object present is a global stop.
- **Target environment:** production Supabase `usayoldrawwmjsmretin` (read-only). Staging
  `pkwotgqivgaapwuqgwqb` and the AU-11 D1/D2/D3 objects are out of scope; A3 confirms their absence.

## Pending (NOT started)

- Baseline C (reconciliation & week state), Baseline D (obligations & inflows), Baseline E
  (model comparison & trough) — **not drafted**.
- Baseline F (owner-supplied live bank snapshot) — **not captured**.
- Final capacity calculation and final validation — **pending**, to be assembled in the external
  execution evidence package (values remain out of the repository per the balance-free policy).

## Governance

- Standing holds remain in force: engine hold, Wendy IRA hold, discretionary-transfer deferrals,
  controlled goal-funding/disbursement rules. Production is untouched. No SQL has been executed against
  production or staging by Claude.

## Next authorized action

**Step 8 — Execute Baseline A under controlled read-only procedure** (owner-run; Claude runs no SQL).
Step 8 is **NOT complete**.
