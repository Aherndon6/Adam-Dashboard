# Phase 5G-1D — Gate C Write-Surface Decision Register (FINAL)

**Status:** DECISION-PREP — NOT EXECUTED, NOT APPROVED. This register records the current grant
posture, the recommended disposition per write surface, the exact-signature SQL that would
implement it, and the rollback. **No grant is changed and no SQL is executed by this document.**
Every disposition is **Adam's decision per surface** at the Gate C trigger; nothing here modifies
production grants or Supabase.
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
(activate the wrapper before deploying the browser; revoke the old surfaces only after the new
browser is verified). All files carry the migration's production/staging environment guard
(`system_identifier` + `app_environment`) and are **exact-signature**.

- **`docs/phase-5g-1d-activation-grants.sql`** — **Phase 1** (blocks **G-10, G-11**): GRANT
  `authenticated` EXECUTE on the wrapper + Option B (the activation grants). Run **before** the
  browser deploy; the old browser keeps working via the old RPC.
- **`docs/phase-5g-1d-activation-revokes.sql`** — **Phase 2** (blocks **G-01…G-08**): the
  write-surface lockdown (RPC-only). Run **only after** the new browser is deployed and the Week-6
  smoke passed. Each block is **independently includable** — comment out any surface Adam did not
  approve. Row 9 (the `deleteRecon` anchored-week UI guard) is an `index.html` change, not SQL.
- **`docs/phase-5g-1d-activation-grants-rollback.sql`** — restores the **pre-activation** grant
  state (revoke wrapper + Option B back to inert; re-grant old recon RPC, repair RPC, snapshot RPC,
  and the two table grant sets). Separate Adam approval.
- **`docs/phase-5g-1d-activation-grants-validation.sql`** — read-only **before/after grant
  matrix** (`has_function_privilege` / `has_table_privilege`) + function-body md5 (byte-unchanged
  proof). Run before Phase 1, after Phase 1, and after Phase 2.

The **behavioral** proof pair — **wrapper still succeeds** (definer-owner path intact after
revocation) and **bypass fails** (a direct/stale caller denied before any persistence) — is the
Slice-7 real-caller smoke (JWT→PostgREST), not pure SQL. See the Gate B runbook §7.

---

## 5. Rollback boundary (Gate C surfaces)

- Each posture change is reversible by its inverse grant in
  `docs/phase-5g-1d-activation-grants-rollback.sql` (re-grant / re-revoke, exact-signature), under
  **separate Adam approval**.
- **No data is ever touched** by any Gate C op — these are grant changes only; function bodies,
  RLS policies, and all rows are unchanged.
- The `deleteRecon` client guard (row 9) rolls back by reverting its `index.html` commit.
- **Boundary:** Gate C rollback restores the pre-activation grant posture exactly. It does **not**
  undo the wrapper deployment (that is the Slice-6 rollback) or any reconciliation/snapshot data.

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

**This register executes nothing.** Gate C is closed only when Adam records the per-surface
dispositions; the SQL then runs at Slice 7 under its own approval.
