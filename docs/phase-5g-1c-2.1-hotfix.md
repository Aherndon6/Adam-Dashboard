# Phase 5G-1C-2.1 — Post-Anchor Model Coherence Hotfix

**Emergency hotfix** for a post-E2 planning regression exposed when the Week-5 opening anchor went
live. **Two legs, both COMPLETE + GREEN in production (2026-07-11).** **Leg 1 (code)** restored
post-anchor IRA seed coherence (`c0a3476`). **Leg 2 (Week-5 holding correction)** added two guarded
`correction` snapshots, executed **once** in production against Adam-Dashboard (`usayoldrawwmjsmretin`)
by Adam in the Supabase SQL Editor; Claude ran no SQL. No schema change; the nine validated E2
`opening_anchor` values are unchanged (proven row-by-row before the correction insert).

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

## Leg 2 — Week-5 holding correction (COMPLETE + GREEN in production, 2026-07-11)

Two guarded Week-5 `correction` snapshots were added — **`wewe_rccl = 600`, `wewe_dcl = 500`** — via
the committed sentinel templates (`docs/phase-5g-1c-2.1-prod-holding-correction.sql`,
`docs/phase-5g-1c-2.1-prod-holding-correction-validation.sql` @ `b863266`), value-filled LOCAL-only
and executed **once** by Adam in the Supabase SQL Editor. Snapshot semantic: `funded_amount` =
cumulative funded PROGRESS, not cash held; payout ≠ zeroing; releases are a later lifecycle layer
(5G-1B).

- **Preflight (passed):** `current_user`/`session_user` = `postgres`; `system_identifier` =
  `7632885393857617092`; `snapshots_total` before = 9; `latest_reconciled_week` = 5; Week-5 RCCL/DCL
  rows before = 0; `wewe_rccl` target 600.00 / auto false, `wewe_dcl` target 500.00 / auto false.
- **Correction (committed once):** exactly **11 Week-5 rows** = 9 `opening_anchor` + 2 `correction`
  (RCCL 600.00, DCL 500.00). The **nine E2 `opening_anchor` rows were proven unchanged** (each
  id/source/exact funded amount asserted against its pin pre-insert).
- **Validation:** the read-only **REPEATABLE READ** SA-COR block PASSED and returned the same
  11-row partition, no errors.
- **UI smoke (hard refresh, passed, balance-free):** RCCL/DCL 100% complete; Alaska complete; the
  Adam-IRA residual-to-target scheduled **exactly once** in Week 28, then Wendy IRA in Week 29; no
  duplicate IRA seed; no Week-28/29 RCCL/DCL recommendation; Week 27 executed history retained; next
  projected flight-path breach Week 35.

**Execution discipline.** Plain INSERT, **no `ON CONFLICT`** — the correction was run **once and must
never be rerun** (a rerun raises the `UNIQUE(model_year,week_num,goal_id)` violation and fails
loudly). The committed templates remain **unfilled** (eleven `-1` pins each, **no household
values**); the local value-filled copies remain **outside the repo** at
`~/Herndon-FOS-DB-Backups/Adam-Dashboard/5G-1C-2.1/` (chmod 600), never committed.

**Downstream.** 5G-1D is now **unblocked from the snapshot-anchor/correction dependency**; it remains
**NOT STARTED** (its own implementation approval + Gates A–E, no approval inferred) and **writes
subsequent weekly closeout snapshots without creating the opening anchor** (the Week-5
`opening_anchor` remains E2's).
