# Phase 5G-1D — Implementation-Readiness Package: Approved Decisions & Gate Register

**Status:** PLAN-ONLY. **Not started, not implemented, not activated.** No code, SQL,
schema, RPC, RLS, migration, seed, grant change, or test written or run this pass. No
Supabase access. E2 has **not** executed; `goal_funding_snapshots` is **EMPTY**; the
5G-1D wrapper does **not** exist yet.
**Author:** Claude (session under Adam)
**Date:** 2026-07-10

**Purpose.** Record the Adam decisions approved now, and the unresolved future decision
gates (with explicit trigger points), that the 5G-1D implementation-readiness work must
carry. This is the **decision/gate spine** of the readiness package; it precedes and
frames the fuller slice-implementation drafting, and does not duplicate the cleared 5G-1D
plan's slice sequence.

**Subordinate to — and consistent with, not a replacement for (all cleared; do NOT edit
any of them):**
- `docs/phase-5g-1d-plan-2026-07-09.md` — cleared 5G-1D write-through plan (authoritative
  slice sequence + wrapper modes).
- `docs/phase-5g-1c-2-e2-runbook.md` — cleared E2 first-anchor seed gate.
- `docs/phase-5g-1d-snapshot-correction-procedure-2026-07-10.md` — cleared correction /
  reopen / remediation companion spec (merged to `main` at `f005263`); its §17 acceptance
  criteria are the source of the requirements referenced below.

**Deferred status-doc updates.** The `CODEX_STATUS.md` / `docs/phase-status.md` pointers
are updated **only after this readiness package is itself reviewed and cleared** — not in
this pass. This file records that intent; it does not perform it.

---

## 1. Decisions approved now (Adam, 2026-07-10)

These three decisions are **approved** and are load-bearing inputs to 5G-1D
implementation. They resolve open items previously flagged in the correction spec (§4.2,
§8.0, §19).

### D1 — Option A is a temporary bridge only

- The supervised **guarded-SQL correction path (Option A)** is **not** the steady-state
  operating model.
- It exists to make a rare correction executable *before* Option B ships.
- **It retires for post-anchor corrections the moment Option B is deployed.** After that,
  post-anchor `source='correction'` fixes go through Option B, never hand-authored SQL.
- (Week-5 opening-anchor amendments are the sole exception — they stay on the guarded-SQL
  path, per D3, because they preserve `source='opening_anchor'`.)
- Resolves correction spec §19 item 1 (mechanism) and §4.2.

### D2 — Option B will be built in 5G-1D Slice 2

- The **owner-only correction wrapper** (`public.correct_goal_funding_snapshot(...)`) is
  part of the planned **Slice-2 staging package** (the same slice as the closeout
  orchestration wrapper — 5G-1D plan §10 checklist, Slice 2).
- It is an additive SECURITY DEFINER **call-through** wrapper and **must enforce**:
  - **target-row existence** — a missing `(model_year, week_num, goal_id)` natural key is
    a hard stop (no backfill through the correction path);
  - **nearest-existing monotonicity bounds** — `≥` nearest existing lower-week row and `≤`
    nearest existing higher-week row for that goal (correction spec §7.0);
  - **internal `public.is_owner()`** as its first action;
  - **`household_admin` (Wendy) rejection** inside the function body (grant is routing,
    `is_owner()` is authorization — correction spec §13);
  - **call-through to the deployed `public.save_goal_funding_snapshots(...)`** as the write
    primitive — it does **not** reproduce that RPC's validation/write logic and does
    **not** write the table directly;
  - one post-anchor row with **`source='correction'`**, post-call returned-row validation,
    and full exception propagation.
- Resolves correction spec §19 item 1 (B-in-Slice-2) and §4.1.

### D3 — Week-5 opening-anchor amendments preserve `source='opening_anchor'`

- A value amendment to an existing Week-5 opening-anchor row **keeps
  `source='opening_anchor'`** — the row source is **not** changed to `correction`.
- The **external evidence records the amendment** (plus the row `note`); the change is not
  encoded by flipping `source`.
- The **nine-row opening-anchor completeness guard must continue to pass** (nine rows, one
  anchor week, all `opening_anchor` — 5G-1D plan §5.6).
- Anchor amendments run on the **guarded-SQL path, not Option B** (correction spec §8.1).
- Resolves correction spec §19 item 5 and §8.0 (and overrides the E2 runbook §8
  "`source='correction'` for a wrong seed" language **for the anchor case only**, without
  editing the cleared runbook).

---

## 2. Unresolved future decision gates (carry into the readiness package)

Each is an **explicit decision gate** with a **trigger point**. None is decided in this
pass. Each maps to a row in the §3 gate register.

### Gate A — `public.is_owner()` identity verification

- **Trigger:** before staging acceptance of **any** owner-only reopen or correction
  functionality.
- **Required proof (read-only production preflight; no role-data change):**
  - exactly **one active owner row** (`app_users.role='owner' AND active=true`);
  - **Adam's real authenticated account maps to that owner row** (the app login, not the
    `adam@herndons.us` seed identity);
  - **Adam's session returns `public.is_owner() = true`**;
  - **Wendy's session returns `false`**.
- **Hard stop:** ship any `is_owner()`-gated path before this proof → STOP (it could
  reject Adam himself). Correction spec Finding 8 / §19 item 2.

### Gate B — Option B activation gate

- **Default:** **5G-1D production activation REQUIRES Option B** deployed and tested.
- **Exception:** only by a **separate Adam approval of a dated deferral** containing
  **rationale, owner, expiration/review date, and interim controls**. A deferral is never
  implicit or open-ended.
- **Trigger:** before production activation approval.
- **Hard stop:** activate 5G-1D without Option B **and** without an approved dated
  deferral → STOP. Correction spec §4.2 / §19 item 1.

### Gate C — `repair_commitments_for_week` activation posture

- **Trigger:** before the activation grant changes (§7 of the 5G-1D plan).
- **Do not decide until the caller/dependency audit is complete** (confirm no supported
  browser path or feature needs its direct `authenticated` EXECUTE).
- **Required decision — choose and record exactly one posture:**
  - retain with documented restriction;
  - wrap behind an owner-only control;
  - revoke `authenticated` EXECUTE;
  - another explicitly reviewed posture.
- **Context:** deployed `repair_commitments_for_week(INT,INT,TEXT,JSONB,JSONB)` is
  `can_write_financials()`-gated and REST-callable by Wendy today; it can mutate a
  closed/anchored week's commitments and `weekly_reconciliations.balance_basis`
  (correction spec Finding 11 / §3.1).
- **Hard stop:** activate 5G-1D while this posture is **undecided/unreviewed** → STOP.
  Correction spec §17 item 10.

### Gate D — Pre-freeze vs post-freeze activation timing

- **Trigger:** implementation-readiness decision card.
- **Required output for the decision card:**
  - consequences of **activating before the Week-6 closeout** versus **after the Alaska
    freeze (Jul 24–Aug 10)**;
  - gap-remediation implications (e.g. any reconciled-but-unsnapshotted "half-closed"
    weeks that would accumulate in a delayed-activation window);
  - **explicit Adam decision**.
- **Hard stop:** merge/activate inside the Alaska freeze window without an explicit
  timing decision → STOP (no 5G merges Jul 24–Aug 10).

### Gate E — Any historical multi-week remediation

- **Trigger:** whenever a correction would require changing later weeks (or deliberately
  creating a missing historical row / backfill).
- **Required action:** a **separate remediation plan and explicit Adam approval** — never
  folded into a single-week correction approval; no silent cascade.
- **Hard stop:** cascade/backfill under an ordinary correction approval → STOP. Correction
  spec §10 / §7.0.

---

## 3. Gate register

Concise register the implementation-readiness package must carry and keep current.
(Status legend: **APPROVED** = decided now; **OPEN** = decision pending at its trigger.)

| # | Decision / gate | Current status | Trigger point | Required evidence | Approver | Hard-stop condition |
|---|---|---|---|---|---|---|
| **D1** | Option A is temporary bridge only | **APPROVED** (2026-07-10) | Option B deployment | Option B live + tested; Option A disabled for post-anchor corrections | Adam | Option A used for a post-anchor correction after Option B ships |
| **D2** | Option B built in 5G-1D Slice 2 | **APPROVED** (2026-07-10) | Slice-2 staging build | Wrapper enforces row-existence, nearest-existing bounds, `is_owner()`, Wendy rejection, call-through to deployed RPC; §15 tests green | Adam | Wrapper reproduces/writes table directly, or omits any enforced control |
| **D3** | Week-5 anchor amendments keep `source='opening_anchor'` | **APPROVED** (2026-07-10) | Any anchor amendment | Nine-row `opening_anchor` completeness guard passes; external evidence records the amendment | Adam | Anchor row flipped to `source='correction'`, or completeness guard fails |
| **A** | `is_owner()` identity verification | **OPEN** | Before staging acceptance of any owner-only reopen/correction | One active owner row; Adam's account maps to it; Adam session `is_owner()=true`; Wendy `false`; read-only, no role change | Adam | Ship an `is_owner()`-gated path before the proof |
| **B** | Option B activation gate | **OPEN** | Before production activation approval | Option B deployed + tested, **or** a dated Adam deferral (rationale, owner, expiry/review, interim controls) | Adam | Activate 5G-1D without Option B and without an approved dated deferral |
| **C** | `repair_commitments_for_week` activation posture | **OPEN** (blocked on caller/dependency audit) | Before activation grant changes | Completed caller/dependency audit + one recorded posture (retain-restricted / wrap / revoke / other reviewed) | Adam | Activate 5G-1D with the posture undecided/unreviewed |
| **D** | Pre-freeze vs post-freeze activation timing | **OPEN** | Implementation-readiness decision card | Before/after-freeze consequence analysis + gap-remediation implications + Adam decision | Adam | Merge/activate inside Alaska freeze (Jul 24–Aug 10) without an explicit timing decision |
| **E** | Historical multi-week remediation | **OPEN** (event-driven) | Whenever a correction would change later weeks / backfill | Separate remediation plan + full before/after matrix + explicit approval | Adam | Cascade or backfill under an ordinary correction approval |

---

## 4. Acceptance criteria absorbed from the cleared correction spec (reference, not restated)

The readiness package inherits the correction spec's §17 handoff acceptance criteria
verbatim (owner-only DB-enforced reopen; in-place single-row owner-only correction not via
the `can_write_financials()` RPC; the Option A/B mechanism decision — now settled by
D1/D2; two-sided nearest-existing monotonicity; opening-anchor special path — now settled
by D3; distinct approval gates with no cross-authorization; mandatory evidence + local
artifact privacy model; the `is_owner()` production preflight — Gate A; contract
non-regression; and the `repair_commitments_for_week` posture — Gate C). These are cited,
not duplicated; the cleared spec at `f005263` is the source of truth.

---

## 5. Scope boundary

This package **may**: record approved decisions, define future decision gates with
triggers, and hand exact acceptance criteria to the slice-implementation drafting. It
**must not**: rewrite the cleared 5G-1D slice sequence, alter the cleared wrapper modes
(`normal_closeout` / `approved_reopen`), modify the Week-5 anchor contract, edit any
cleared artifact, or authorize SQL, Supabase access, grant changes, E2 execution, or
5G-1D implementation.

**Status/frontier document updates** (`CODEX_STATUS.md`, `docs/phase-status.md`) are made
**only after** this readiness package is reviewed and cleared — not in this pass.

---

*Plan-only. No code, SQL, schema, RPC, RLS, migration, seed, grant change, or test written
or run this pass. Subordinate to the cleared 5G-1D plan, E2 runbook, and correction
companion spec, all unchanged. Every gate above is an explicit Adam decision at its trigger
point; no approval is inferred from another. Nothing here authorizes implementation or any
production action.*
