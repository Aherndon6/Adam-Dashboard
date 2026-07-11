# Phase 5G-1C-2.1 — Post-Anchor Model Coherence Hotfix

**Emergency hotfix** for a post-E2 planning regression exposed when the Week-5 opening anchor went
live. **Two legs.** **Leg 1 (code) implemented here; Leg 2 (Week-5 holding correction) is
planning-only** (sentinel SQL + revised validation; not drafted/executed). No production SQL, no
schema change, no change to the nine validated E2 opening_anchor values.

> **Privacy:** this record is **balance-free**. Exact household balances (custodian figures,
> projected savings, screenshots) are retained **local** to Adam's machine, not committed.

## Accepted diagnosis (Fable-confirmed)

- **RC1 — IRA seed re-fires after the anchor.** The Week-5 anchor's `adam_ira` funded amount already
  embeds the one-time `RET_SAV_XFR` ($3,772.74) seed, but the snapshot overlay restored `goalSaved`
  without restoring the **run-local `rtSavSwept` latch**. So the seed sweep re-fired post-anchor,
  double-debiting Truist Savings, blocking the later $7,000 Alaska draw, suppressing the legitimate
  small residual-to-target IRA completion, and adding projected floor breaches.
- **RC2 — RCCL/DCL re-funded.** They were executed in Week 5 but **excluded from snapshots**, so the
  waterfall re-derives and re-funds their full $600 / $500 targets. (Fixed by **Leg 2**.)
- **db2704f (5G-1B) is not causal** and its Week-27 executed-history behavior is unchanged.

## Leg 1 — code change (implemented)

**Scope:** `index.html` seed threshold + latch, `test_regression.js`. No waterfall, `mv`/`mvS`, CAE,
reconciliation, snapshot loader, RPC, SQL, schema, 5G-1B resolver, or `weekly_tasks` change.

1. **Named threshold** (uses the model's `r()` rounding — no new convention):
   `IRA_SEED_EMBEDDED_THRESHOLD = r(START_AMX + RET_SAV_XFR)` (= 3876.38). An `adam_ira` snapshot at
   or above this proves the seed is embedded.
2. **Latch placed immediately BEFORE the seed-eligibility gate** (`akNowComplete && !rtSavSwept`):
   the current week's `adam_ira` snapshot is normalized (`Number` + `Number.isFinite`, rounded via
   `r`) and, if `>= threshold - 0.01`, sets `rtSavSwept = true` **before** eligibility — suppressing
   `goal_adam_ira_seed` **in that week and all later weeks**.
3. **The end-of-week `goalSaved` snapshot overlay is unchanged**, so `goalVariance` timing is
   unaffected.

**Invariants (all tested):** no snapshot → Leg 1 inert, byte-identical; anchor **below** threshold →
seed still fires once; anchor **at/above** threshold → seed suppressed permanently, including the
**same-anchor-week** case where Alaska is already complete before the overlay; residual-to-target is
funded exactly once; final `adam_ira` reaches target and never exceeds it.

> **Test note:** `C3-08` (goalVariance sign convention) was retargeted from `adam_ira` to `alaska`.
> Leg 1 legitimately changes the modeled `adam_ira` when an anchor ≥ threshold is present (its old
> `+100` case crossed the threshold); the sign convention is goal-agnostic and `alaska` is unaffected
> by the latch. The `adam_ira` seed behavior is covered by the new Section 5G-1C-2.1 tests.

## Local production-equivalent before/after (reconciled wk1–5 fixture; balance-free)

| Scenario | seed emissions | RCCL acts | DCL acts | residual→target | final Adam IRA |
|---|---|---|---|---|---|
| nine-row anchor (current, BROKEN) | re-fires | re-funded | re-funded | 0 | 149% (double-seeded) |
| nine-row anchor + Leg 1 | **none** | re-funded | re-funded | **×1** | **100% (target)** |
| **eleven-row anchor + Leg 1 (with Leg 2)** | **none** | **none** | **none** | **×1** | **100% (target)** |

Both legs are required together; Leg 1 alone still leaves RCCL/DCL re-funding (RC2 → Leg 2).

## Pre-fix evidence

A **deployed-code, production-equivalent** reconciled-plus-anchor trace (git HEAD, pre-Leg-1; saved
locally, balance-free) reproduced the **duplicate IRA seed, duplicate holding-goal (RCCL/DCL)
funding, blocked Alaska $7,000 draw, and added floor breaches**. **Authenticated production
screenshots separately confirmed** the duplicate recommendations and the expanded flight-path
breaches. Balance-bearing screenshots and exact figures are retained local to Adam; this record is
balance-free.

## Verification (Leg 1)

- Static regression: **1442/0** (Section 5G-1C-2.1: 11 cases; C3 suite green incl. retargeted C3-08).
- Smoke / full e2e / browser console: recorded at commit time.

## Leg 2 — planning only (not drafted/executed)

Committed **sentinel** correction (`-1`) + revised **sentinel** validation, two-row Value Card,
plain guarded INSERT with hard-stop preconditions (whole-table count = 9, no wk5 RCCL/DCL, nine
opening_anchor unchanged, week 5 reconciled, production fingerprint), assert ROW_COUNT = 2, no
`ON CONFLICT` (rerun fails on the unique key). Snapshot semantic: `funded_amount` = cumulative
funded progress, not cash held; payout ≠ zeroing; releases are a later lifecycle layer (5G-1B).
**5G-1D remains blocked until both legs are live and verified.**
