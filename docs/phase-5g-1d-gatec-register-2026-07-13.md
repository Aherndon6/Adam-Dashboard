# Phase 5G-1D — Gate C Write-Surface Decision Register (FINAL — APPROVED)

**Status:** **DECISIONS APPROVED (Adam, 2026-07-13) — NOT EXECUTED.** All 11 write-surface
dispositions are approved as recommended (see §7 for the approved decisions + clarifications).
**Approval settles the posture; it does NOT authorize SQL execution, grant changes, deployment,
merge, or activation.** Every approved change executes only through the Slice 6 / Gate B sequence,
each with its own separate execution approval. **No grant is changed and no SQL is executed by this
document; nothing here modifies production grants or Supabase.**
**Date:** 2026-07-13
**Author:** Claude (session under Adam)
**Gate D:** **Option A (pre-freeze activation) — APPROVED (Adam, 2026-07-13).** Timing only; does
not authorize any grant change, deployment, merge, or activation.
**Browser implementation:** Slices 3/4/5 **COMPLETE** — local full E2E **142 passed / 0 failed /
0 skipped**, readiness fallbacks **openApp 0 / clickNav 0**, runtime ~5 min (Adam-verified).

**Authoritative sources (win on conflict):** `AGENTS.md`; `CODEX_STATUS.md`; the cleared 5G-1D
plan (`docs/phase-5g-1d-plan-2026-07-09.md` §7/§9), readiness package
(`docs/phase-5g-1d-implementation-readiness-2026-07-10.md` §2 Gate C / §4 Slice 7), and
**amendment 1 §G** (`docs/phase-5g-1d-amendment-2026-07-11.md`) — the 11-surface register this
document finalizes. Grant SQL: `docs/phase-5g-1d-activation-grants.sql` (+ `-rollback.sql` /
`-validation.sql`), authored alongside this register, **NOT executed**.

**Privacy:** balance-free. No household values.

---

## 1. What Gate C is (and is not)

Gate C is the **write-surface posture decision**: for every path by which an authenticated client
can write reconciliation or goal-funding state, decide **retain / wrap / restrict / revoke**, so
that after activation those writes go **only through the audited wrapper/Option-B RPCs** and no
stale or side-channel writer can recreate a half-closed or unmonotonic state.

- **Gate C decides posture; it does not execute.** Every posture change is a **separately approved,
  exact-signature grant operation** executed at the **Slice-7 activation step** (bundled with Gate
  B), each with staging rehearsal + before/after grant matrix + rollback + the wrapper-succeeds /
  bypass-fails proof pair.
- **Gate C's required audit is COMPLETE** (readiness §2 Gate C): `repair_commitments_for_week` has
  **zero runtime callers** (verified this pass — `index.html` never references it; the
  `test_regression.js` hits are SQL-source assertions; `e2e.js`/`scripts/`/`tools/` clean). It is
  the never-wired 5F-1 "historical repair mode." Revoking/restricting it breaks **no shipped
  behavior**.

---

## 2. Exact-signature reference (grounded in deployed SQL)

| Object | Exact signature / target | Deployed at |
|---|---|---|
| Old reconciliation RPC | `public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)` | `docs/phase-5f-1-migration.sql:454` (REVOKE `:961`, GRANT `:964`) |
| Historical repair RPC | `public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)` | `docs/phase-5f-1-migration.sql:997` (REVOKE `:1337`, GRANT `:1338`) |
| Snapshot RPC (E1) | `public.save_goal_funding_snapshots(INT, INT, JSONB)` | `docs/phase-5g-1c-2-prod-migration.sql:160` (REVOKE `:282`, GRANT `:283`) |
| Snapshot table (E1) | `public.goal_funding_snapshots` | grants `docs/phase-5g-1c-2-prod-migration.sql:280-281` (`SELECT,INSERT,UPDATE`, no DELETE) |
| Reconciliation table | `public.weekly_reconciliations` | **no explicit grant in repo** — Supabase default role grants, RLS-gated (capture exact at preflight) |
| Closeout wrapper (NEW) | `public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)` | `docs/phase-5g-1d-migration.sql:66` — **inert** after Slice 6 |
| Option B correction (NEW) | `public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)` | `docs/phase-5g-1d-migration.sql:365` — **inert** after Slice 6 |
| `deleteRecon` (client) | `index.html` `deleteRecon(n)` → `DELETE /rest/v1/weekly_reconciliations?week_num=eq.N` | product behavior over the reconciliation table |

---

## 3. The decision register — 11 surfaces

Legend: **Posture** = recommended disposition (Adam decides per row). **Now** = current grant.
**Breaks shipped behavior?** = does the recommended change remove any behavior in use today.
Every SQL op is **exact-signature** and lives in `docs/phase-5g-1d-activation-grants.sql`
(block IDs G-01…G-11).

| # | Write surface | Now (authenticated) | **Recommended posture** | SQL block | Breaks shipped behavior? |
|---|---|---|---|---|---|
| 1 | Old reconciliation RPC direct EXECUTE | **GRANTED** | **REVOKE** — the wrapper calls it as the SECURITY DEFINER owner; stale-client protection (plan §7) | G-01 (REVOKE) | Stale cached browsers only — **by design** (they must refresh; they can no longer half-close) |
| 2 | `repair_commitments_for_week` EXECUTE | **GRANTED** | **REVOKE** `authenticated` EXECUTE (audit: zero callers) | G-02 (REVOKE) | **No** (never wired). Future 5F-1 historical-repair mode, if ever built, re-grants or gets an owner-only wrapper — tracked, not dropped |
| 3 | `save_goal_funding_snapshots` direct EXECUTE | **GRANTED** | **REVOKE** — wrapper + Option B call it as definer owner; **mandatory** precondition for the per-goal serialization invariant (Slice-2 spec §4.2) | G-03 (REVOKE) | **No** (zero in-app callers; grep-confirmed) |
| 4 | `goal_funding_snapshots` table INSERT | **GRANTED** | **REVOKE** — snapshot writes become RPC-only | G-04 (REVOKE) | **No** (app reads snapshots only) |
| 5 | `goal_funding_snapshots` table UPDATE | **GRANTED** | **REVOKE** — RPC-only | G-05 (REVOKE) | **No** |
| 6 | `weekly_reconciliations` table INSERT | Supabase default (RLS-gated) | **REVOKE** — reconciliation writes RPC-only | G-06 (REVOKE) | **No** (inserts go via the RPC) |
| 7 | `weekly_reconciliations` table UPDATE | Supabase default (RLS-gated) | **REVOKE** — RPC-only | G-07 (REVOKE) | **No** (updates go via the RPC) |
| 8 | `weekly_reconciliations` table DELETE | Supabase default (RLS-gated) | **REVOKE** — closes the anchored-week delete hole | G-08 (REVOKE) | **Yes — breaks `deleteRecon` for ALL weeks.** Must be paired with #9 (product decision) |
| 9 | `deleteRecon` product behavior | active (any week deletable via UI) | **RESTRICT** — anchored/completed weeks not deletable via ordinary UI; needs an owner-supervised path for legitimate unanchored-week cleanup | client guard (Slice-4-style) + G-08 pairing | UI change; requires the paired decision on #8 |
| 10 | Wrapper `save_weekly_closeout_with_snapshots` EXECUTE | **none (inert)** | **GRANT** `authenticated` EXECUTE — this is the **activation** grant (Gate B) | G-10 (GRANT) | Activation itself (Gate B) |
| 11 | Option B `correct_goal_funding_snapshot` EXECUTE | **none (inert)** | **GRANT** `authenticated` EXECUTE — routing only; **owner-only enforced in-body** via `public.is_owner()` | G-11 (GRANT) | Activation itself (Gate B); owner-gated in the function body |

**Net recommended end state:** reconciliation + goal-snapshot writes are **RPC-only for
`authenticated`** (rows 1,3,4,5,6,7,8 revoked); anchored weeks are not deletable through the
ordinary UI (rows 8+9); the wrapper (row 10) and Option B (row 11) are the only granted write
entry points, Option B owner-gated in-body.

---

## 4. Required SQL (authored, NOT executed)

The grant changes are split into **two execution phases** so there is **no broken window**
(activate the wrapper before deploying the browser; **revoke the old surfaces only after the first
Week-6 closeout is durably complete** — P0-1, so the first real write keeps the old RPC as a
fallback). All files carry the migration's production/staging environment guard
(`system_identifier` + `app_environment`) and are **exact-signature**.

- **`docs/phase-5g-1d-activation-grants.sql`** — **Phase 1** (blocks **G-10, G-11**): GRANT
  `authenticated` EXECUTE on the wrapper + Option B (the activation grants). Run **before** the
  browser deploy; the old browser keeps working via the old RPC. Owner-pinned; hard-stops on an
  unexpected pre-grant unless `c_resume` (P1-3).
- **`docs/phase-5g-1d-activation-revokes.sql`** — **Phase 2** (blocks **G-01…G-08**): the
  write-surface lockdown (RPC-only). **Run only after the first Week-6 closeout is durably complete**
  — the script's pre-lockdown asserts hard-stop unless the wrapper is granted, the old RPC is still
  granted, Week-6 is complete (recon + nine snapshots), and the owner is unchanged (P0-1/P1-3). Each
  block is **independently includable** — comment out any surface Adam did not approve. Row 9 (the
  `deleteRecon` anchored-week UI guard) is an `index.html` change, not SQL.
- **`docs/phase-5g-1d-activation-grants-rollback.sql`** — **two clearly-scoped modes (P0-2):**
  **(A) operational-continuity** (default) — revoke wrapper + Option B to inert and re-grant **only**
  the old recon RPC to restore the ordinary closeout; **(B) exact-restore** (exceptional, separate
  approval) — reproduce the exact captured pre-activation matrix, each re-grant checked against the
  before-Phase-1 capture. Separate Adam approval.
- **`docs/phase-5g-1d-activation-grants-validation.sql`** — read-only **before/after grant
  matrix** (`has_function_privilege` / `has_table_privilege`) + function-body md5 (byte-unchanged
  proof) + the **owner invariant** (P0-3: wrapper/Option B owner == recon/snapshot owner, unchanged).
  Run before Phase 1, after Phase 1, and after Phase 2.

The **behavioral** proof pair — **wrapper still succeeds** (definer-owner path intact after
revocation) and **bypass fails** (a direct/stale caller denied, or rejected before any write) — is
run **after the Phase-2 revoke** as two **NON-MUTATING** probes (Gate B runbook §4 steps 8–9): an
idempotent branch-F re-submit that mutates nothing, and an invalid-input old-RPC probe rejected before
any write. Not pure SQL.

---

## 5. Rollback boundary (Gate C surfaces)

- Each posture change is reversible in `docs/phase-5g-1d-activation-grants-rollback.sql`, under
  **separate Adam approval**, in one of two scopes (P0-2): **(A) operational-continuity** restores a
  *working* closeout (re-grant the old recon RPC only); **(B) exact-restore** reproduces the exact
  captured pre-activation matrix. Apply the narrowest that resolves the problem.
- **No data is ever touched** by any Gate C op — these are grant changes only; function bodies,
  RLS policies, and all rows are unchanged.
- The `deleteRecon` client guard (row 9) rolls back by reverting its `index.html` commit.
- **Boundary:** an operational rollback restores a working write path (not necessarily the exact
  pre-activation matrix — use exact-restore, or the Slice-6 restore-point dump, for that). It does
  **not** undo the wrapper deployment (that is the Slice-6 rollback) or any reconciliation/snapshot
  data. In steady state the old RPC is never used; a rollback is the one deliberate exception that
  re-grants it.

---

## 6. Exact Adam approvals required (Gate C)

1. **Per-surface disposition** for rows 1–9 (retain/wrap/restrict/revoke). The recommendation is
   **revoke rows 1,3,4,5,6,7,8; revoke row 2; restrict rows 8+9 as a pair** — confirm or amend each.
2. **The `deleteRecon` product decision (rows 8+9 paired):** approve the anchored-week delete
   restriction + the owner-supervised cleanup path for unanchored weeks (or retain #8 and drop #9).
3. **Timing confirmation:** all approved posture changes execute at the **Slice-7 activation step**
   (bundled with Gate B), each with staging rehearsal + before/after matrix + rollback + the
   wrapper-succeeds/bypass-fails proof pair. None execute at Slice 6 (inert deploy).
4. **The fate of the never-wired 5F-1 historical-repair mode** (the only future consumer of #2):
   deferred-with-owner-path, or dropped from the backlog.
5. **Separate approval to execute** `docs/phase-5g-1d-activation-grants.sql` (and its rollback) —
   this register prepares the decision; it does not authorize execution.

**This register executes nothing.** Gate C's per-surface dispositions are now **recorded and
approved** (§7); the SQL still runs only at the Gate B / Slice-7 step under its own separate
execution approval.

---

## 7. Owner decisions — APPROVED (Adam, 2026-07-13)

All 11 dispositions approved **as recommended**, subject to execution **only** through the approved
Slice 6 / Gate B sequence. Approved clarifications recorded verbatim below.

| # | Surface | **Approved disposition** | Executes at |
|---|---|---|---|
| 1 | Old `save_reconciliation_with_commitments` EXECUTE | **REVOKE** `authenticated` EXECUTE **during Gate B Phase 2, after the new browser path is deployed and verified.** The wrapper retains internal call access under its approved definer contract. | Gate B Phase 2 (G-01) |
| 2 | `repair_commitments_for_week` EXECUTE | **REVOKE** `authenticated` EXECUTE. Zero runtime callers; must not remain an externally callable closed-week mutation path. **The deferred 5F-1 historical-repair mode is FORMALLY RETIRED from the live API surface unless separately redesigned and reapproved later.** | Gate B Phase 2 (G-02) |
| 3 | Direct `save_goal_funding_snapshots` EXECUTE | **REVOKE** during Gate B Phase 2. Snapshot writes occur **only** through the weekly-closeout wrapper or the owner-only correction wrapper. | Gate B Phase 2 (G-03) |
| 4–5 | `goal_funding_snapshots` INSERT / UPDATE | **REVOKE** authenticated direct-write. Snapshot mutations become RPC-only. | Gate B Phase 2 (G-04/G-05) |
| 6–8 | `weekly_reconciliations` INSERT / UPDATE / DELETE | **REVOKE** authenticated direct-write. Reconciliation writes become RPC-only. | Gate B Phase 2 (G-06/G-07/G-08) |
| 9 | `deleteRecon` product behavior | **RESTRICT.** **Do not allow ordinary browser deletion of a reconciliation week that has opening-anchor, reconciliation, or correction snapshot state.** **Preserve a separately governed owner-only cleanup/remediation path for exceptional cases.** **Deletion is NOT a correction mechanism** (wrong values use Option B). | Gate B Phase 2 (G-08) + a browser guard shipped in the activation browser (see below) |
| 10 | `save_weekly_closeout_with_snapshots` EXECUTE | **GRANT** `authenticated` EXECUTE during **Gate B Phase 1**. | Gate B Phase 1 (G-10) |
| 11 | `correct_goal_funding_snapshot` EXECUTE | **GRANT** `authenticated` EXECUTE during **Gate B Phase 1**; **retain in-function owner-only enforcement — Wendy/household_admin remains rejected** via `public.is_owner()`. | Gate B Phase 1 (G-11) |

### 7.1 Row-9 implementation note (deleteRecon)

Two parts, both **before** the Gate B activation completes:
- **Server (G-08):** `REVOKE DELETE ON public.weekly_reconciliations FROM authenticated` (Phase 2) —
  after this, the current `deleteRecon` direct DELETE is denied for **every** week (fail-closed).
- **Browser guard (activation branch — IMPLEMENTED, P0-4 2026-07-13):** `canDeleteRecon(n)` offers
  reconciliation deletion **only** for a legacy pre-anchor week (1–4) that bears **no** snapshots and
  only when the snapshot load is known-good (`_goalSnapLoadStatus==='loaded'`); it **fails closed** on
  any uncertain snapshot state. Anchor (5), `complete`, `half_closed`, `corrupt`, and any
  snapshot-bearing week are never deletable. `deleteRecon` re-checks the guard (defense in depth),
  does **not** optimistically drop local state on a denied server DELETE, and surfaces a week-scoped
  operator message. Covered by static tests (`5G1D-P04-01…16`) + e2e (`5G1D-DEL-1…3`). The
  exceptional owner-only cleanup path (an owner-gated RPC or a supervised guarded-SQL runbook) is a
  **separate design + approval** — deletion is never a correction.

### 7.2 Execution constraints (approved, binding)

- These decisions **do not authorize immediate SQL execution.**
- **Phase 2 revokes are NOT applied until (P0-1):** Slice 6 inert deployment is complete + green;
  Phase 1 grants are applied; the browser (incl. the row-9 guard + response validation) is deployed
  and verified; **the first supervised Week-6 closeout is durably complete through the wrapper**
  (recon row + nine snapshots) with the old RPC still granted as a fallback; rollback remains ready.
- **No broken interval** in which neither the old nor the new production path works is permitted.
- **Any failure before Phase 2 revokes is a HARD STOP** — and the old RPC is still granted, so the
  ordinary path is intact.
- **Any failure after Phase 2 revokes follows the approved rollback (P0-2):** the
  operational-continuity rollback (re-grant the old recon RPC only) restores the ordinary closeout,
  or exact-restore under its own approval; revert the browser deployment; **do not delete persisted
  reconciliation or snapshot rows.**

**SQL impact of these approvals:** none — the authored grant files already implement exactly the
approved postures (`-activation-grants.sql` = G-10/G-11; `-activation-revokes.sql` = G-01…G-08;
`-activation-grants-rollback.sql`; `-activation-grants-validation.sql`). No SQL file is edited by
this approval. Row 9's browser guard is an `index.html` change (Gate B / Slice 7), not SQL.
