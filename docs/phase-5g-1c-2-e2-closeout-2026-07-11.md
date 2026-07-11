# Phase 5G-1C-2 — E2 First-Anchor Seed: Closeout Evidence

**Date:** 2026-07-11 · **Target:** PRODUCTION Adam-Dashboard (`usayoldrawwmjsmretin`) ·
**Status:** **E2 COMPLETE + GREEN.** First `opening_anchor` seeded at model Week 5 (Cal Wk 27).
**Gate 0 for 5G-1D is now SATISFIED.**

> **Privacy:** this committed record contains **no household balances and no SA8 dollar
> amounts.** The nine seeded values live only in the approved Value Card and the local
> execution artifacts (retained outside the repository). Goal IDs, row counts, and gate
> pass/fail are non-sensitive and recorded here.

## Execution summary

Executed by Adam in the Supabase SQL Editor against PRODUCTION Adam-Dashboard
(`usayoldrawwmjsmretin`), one gate at a time, under explicit per-gate authorization. Claude
ran no SQL and did not touch Supabase — it prepared the local value-filled copies, verified
the value-only diff, and interpreted each gate's output. Independent review of the two local
execution copies returned PASS before authorization.

## Gate results

- **Gate 1 — read-only pre-seed re-check: PASS.** `latest_reconciled_week = 5`;
  `reconciled_weeks = {1,2,3,4,5}`; `goal_funding_snapshots count = 0`;
  `system_identifier = 7632885393857617092`; snapshots table exists; not staging.
- **Gate 2 — seed (`opening_anchor`): PASS.** Nine rows written — `model_year = 2026`,
  `week_num = 5`, `source = opening_anchor` for every row. Goal IDs seeded (exactly nine):
  `adam_ira, wendy_ira, wendy_sep, alaska, bailey_529, bryce_529, preston_529, bryce_vehicle,
  christmas_cruise`. No excluded goal appeared. Run once; no rerun. (Values not recorded here.)
- **Gate 3 — seed-anchor validation: PASS.**
  - **SA-PROD PASS** — 9 rows at the single anchor week 5; all `source = opening_anchor`; no
    excluded ids table-wide; SA-complete (each of the nine ids present exactly once); row
    invariants (source / non-negative / registry membership / non-auto) hold; every
    `funded_amount` equals its approved Value-Card pin.
  - **SA8 (advisory) PASS** — expected **under-attribution**, fully explained by the excluded
    AMEX holdings (Wewe RCCL, Wewe DCL) and account interest; `is_over_attributed = false`,
    i.e. **no over-attribution**. (Dollar figures intentionally omitted; retained locally.)
    Hard two-sided gate is deferred to 5G-1E.
  - **SA9** — nine-row anchor dump matched the approved Value Card.
- **Gate 4a — live-site verification: PASS.** The C3 overlay is now live (no longer inert):
  the `goal_funding_snapshots` loader returned HTTP 200 with exactly nine rows, all
  `week_num = 5`, all nine IDs matching the card, no excluded goals. Rendered statuses correct
  — Adam IRA remains CPA-pending (still short of its $7,500 target), Alaska complete, Adam
  401(k) remains `Auto · Payroll`; Wewe RCCL / Wewe DCL remain outside E2 (see the separate
  transfer-history / holding-attribution defect). No console/overlay errors.

## Excluded goals (never seeded)

`adam_401k` (auto/payroll), `wewe_rccl`, `wewe_dcl` (AMEX holding → 5G-1B), `taxable_etf`
(deferred). Absence confirmed table-wide by SA-PROD.

## Local-only execution artifacts — metadata (files/outputs retained OUTSIDE the repo)

The value-filled execution copies and the seed/validation outputs contain household balances
and are **never committed** (both `scratchpad/` and `exports/` are gitignored). Repository
records **metadata + hashes only**:

| Artifact | Bytes | SHA-256 | Purpose |
|---|---|---|---|
| `e2-seed-anchor-FILLED-LOCAL.sql` | 14250 | `4f4ca91d4150432d7777585abb75efda57b739c9d8711c5299e21344d4a48d8b` | value-filled seed execution copy (local only) |
| `e2-seed-anchor-validation-FILLED-LOCAL.sql` | 13538 | `f4081f98bc01b6002f39293d4b9d5c2680290faa11535123133ff1d7791e00bc` | value-filled validation execution copy (local only) |
| Seed run output | — | (retained locally) | nine funded values written; balance-bearing |
| Validation output (SA-PROD / SA8 / SA9) | — | (retained locally) | SA9 nine-row dump + SA8 advisory; balance-bearing |

## Repository integrity

The committed sentinel templates `docs/phase-5g-1c-2-prod-seed-anchor.sql` and
`docs/phase-5g-1c-2-prod-seed-anchor-validation.sql` retain their nine `-1` **value**
sentinels — **no household values entered the repository**; the value-only fill happened only
in the local copies. (A separate post-hoc commit corrects a stale timing *comment* in the seed
template; the `-1` value sentinels and all guards/logic are untouched.) E1 production DDL was
**not** rerun or mutated.

## Downstream

- **Gate 0 (E2 completion) for 5G-1D: SATISFIED (2026-07-11).** 5G-1D implementation may now
  proceed under its own implementation approval and Gates A–E (no approval is inferred).
- The Week-5 "Transfers to execute" re-derivation behavior (Alaska/RCCL/DCL/IRA rows) is a
  **separate defect** — see `docs/5g-1b-defect-reconciled-transfer-history-2026-07-11.md`.
