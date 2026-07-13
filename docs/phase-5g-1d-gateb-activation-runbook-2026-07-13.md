# Phase 5G-1D — Gate B Production Activation Runbook (Slice 7)

**Status:** RUNBOOK — NOT EXECUTED, NOT AUTHORIZED. Turns the combined closeout **on** in
production: activation grants → browser deploy (merge) → verify → write-surface lockdown → old-RPC
revoke → first supervised Week-6 closeout. **Every step is separately Adam-approved.** Nothing here
is performed by this document; no grant, merge, deploy, or activation happens until Adam runs each
step. Gate B is closed only by the activation approval + a green first closeout.
**Date:** 2026-07-13
**Author:** Claude (session under Adam)
**Gate D:** **Option A (pre-freeze) — APPROVED.** Target window: activation + first closeout
complete **before Jul 24** (freeze Jul 24 – Aug 10). Realistic go/no-go **≈ Jul 16–17**; first
supervised Week-6 closeout **≈ Sat Jul 18**.
**Target:** PRODUCTION Adam-Dashboard (`usayoldrawwmjsmretin`).
**Depends on:** Slice 6 inert deploy DONE (`docs/phase-5g-1d-slice6-deploy-runbook-2026-07-13.md`);
Gate C dispositions recorded (`docs/phase-5g-1d-gatec-register-2026-07-13.md`); Gate A CLOSED.
**Grant SQL:** `docs/phase-5g-1d-activation-grants.sql` (Phase 1), `-activation-revokes.sql`
(Phase 2), `-activation-grants-rollback.sql`, `-activation-grants-validation.sql`.
**Privacy:** balance-free.

---

## 0. Hard gates before ANY activation step (all must be green)

- ☐ **Gate D decided** = Option A (✓).
- ☐ **Slice 6 done:** wrapper + Option B live INERT in production; E1 + recon RPC byte-unchanged;
  Slice-6 evidence recorded.
- ☐ **Gate C dispositions recorded** (per-surface retain/wrap/restrict/revoke) + the `deleteRecon`
  product decision; the approved posture matches `-activation-revokes.sql` (blocks commented out
  where not approved).
- ☐ **Gate A CLOSED** (`public.is_owner()`), ✓.
- ☐ **Browser complete + verified:** local full `node e2e.js` **142/0**, readiness fallbacks
  **0/0**; static **1486/0**.
- ☐ **Staging fully green** for the wrapper/Option B (Gate-2 matrix, ✓).
- ☐ **Rollback separately approved + prepared:** `-activation-grants-rollback.sql` (grants) AND the
  browser-revert commit (index.html) both ready.
- ☐ **No Alaska-freeze violation:** the whole activation + first closeout completes before Jul 24;
  if the go/no-go date slips, **default to post-freeze** (do not compress controls).
- ☐ **In-session activation approval** given for each step below.

---

## 1. Production preflight

Run `docs/phase-5g-1d-activation-grants-validation.sql` (READ ONLY) to capture the **pre-activation
grant baseline** + function-body md5s, and confirm:
- ☐ environment = production (`system_identifier 7632885393857617092`, `app_environment` ABSENT);
- ☐ the two new functions exist **inert** (no anon/authenticated EXECUTE);
- ☐ old recon RPC, repair RPC, snapshot RPC all still `authenticated`-EXECUTE granted;
  `goal_funding_snapshots` = SELECT/INSERT/UPDATE; `weekly_reconciliations` write = Supabase
  default (record the exact `has_table_privilege` values — this is the rollback reference);
- ☐ E1 + reconciliation RPC body md5s == the Slice-6 preflight baseline (byte-unchanged);
- ☐ Week-5 anchor still nine `opening_anchor` + two `wewe_*` correction rows;
- ☐ latest reconciled week + latest complete snapshot week are consistent with a **Week-6** next
  closeout (the wrapper computes next = 6 + complete-count; confirm no gap).

**Hard stop** on any mismatch.

---

## 2. Required grants (the two phases)

| Phase | File | Blocks | Effect | When |
|---|---|---|---|---|
| **Phase 1 — activate** | `phase-5g-1d-activation-grants.sql` | G-10, G-11 | GRANT `authenticated` EXECUTE on wrapper + Option B | **before** browser deploy |
| **Phase 2 — lock down** | `phase-5g-1d-activation-revokes.sql` | G-01…G-08 | REVOKE old recon RPC + repair RPC + direct snapshot RPC + table INSERT/UPDATE/(DELETE) | **after** browser deploy + Week-6 verify |

Each phase: separate Adam approval + `-validation.sql` before/after matrix. Anon EXECUTE stays
false throughout; SELECT stays granted on both tables.

---

## 3. Feature-branch merge timing

- The browser (Slices 3/4/5) lives on `claude/herndon-5g-1d-preactivation-j428vn` (pushed;
  **not merged**). **Merging to `main` auto-deploys via GitHub Pages** — that merge **is** the
  browser deployment and must happen **only inside the activation window**, in this order:
  **Slice 6 done → Phase 1 grants → merge → verify → Phase 2 revokes.**
- ☐ Before the merge, **stamp `BUILD_TS`** (normal code-deploy behavior; the feature-branch commits
  intentionally left it unchanged) so the live build timestamp advances.
- ☐ Merge `claude/herndon-5g-1d-preactivation-j428vn` → `main` (Adam's push gate). Confirm the
  Pages `pages-build-deployment` succeeds and `BUILD_TS` on dashboard.herndons.us reflects the new
  build.
- ☐ **Do not merge before Phase 1 grants exist** — a deployed wrapper-caller with no EXECUTE grant
  fails closed (closeout-blocking). Phase 1 first guarantees the wrapper is callable the instant
  the new browser loads.
- **Under Option A this merge is pre-freeze.** No 5G merge occurs during Jul 24 – Aug 10 under any
  circumstance.

---

## 4. Application activation sequence (ordered; each separately approved)

1. ☐ **Phase 1 grants** — run `-activation-grants.sql`; `-validation.sql` confirms wrapper +
   Option B now `authenticated`-EXECUTE (anon none); old RPC still granted. Old browser unaffected.
2. ☐ **Stamp BUILD_TS + merge → deploy browser** (§3). Pages build green.
3. ☐ **New-browser verification (pre-lockdown):** on a fresh production session, confirm the
   Register/Budget/weekly render unchanged; the recon panel shows the Slice-4 closeout-state badges;
   opening a week's closeout shows the confirmation view (do **not** submit yet). Console clean.
4. ☐ **Phase 2 lockdown** — run `-activation-revokes.sql` (old recon RPC revoke G-01 + G-02…G-08 per
   the approved Gate C postures); `-validation.sql` confirms the RPC-only end state (§6 expected
   matrix). Execute the Gate-C `repair_commitments_for_week` posture action here (G-02).
5. ☐ **Stale-browser verification:** a cached OLD browser tab (still calling the old RPC directly)
   now **fails before reconciliation persistence** (grant-layer denial) — it can no longer
   half-close; it must be refreshed.
6. ☐ **Fresh-browser verification:** a refreshed browser drives the wrapper end to end (proceed to
   §5, the first supervised closeout).

**Ordering rationale:** activation grant (1) before deploy (2) → no broken window; lockdown (4)
after deploy+verify (3) → the ordinary closeout is already on the wrapper before the old path is
removed; the first REAL write (§5) happens with the old RPC already revoked, so it proves the
wrapper is the sole path.

---

## 5. Supervised first production closeout (Slice 7 Week-6 writer smoke)

Under Option A (pre-freeze), the "Week-6 supervised smoke" **is the ordinary Week-6 combined
closeout** through the wrapper (readiness Slice 7, pre-freeze interpretation) — the first real
`reconciliation` + nine-snapshot write.

- ☐ Adam performs the Week-6 weekly closeout in the live app: enter balances → **Save actuals —
  review & close** → confirm the nine funded values in the confirmation view → **Confirm & close
  week**.
- ☐ The wrapper returns `{ok:true, mode:'normal_closeout', week_num:6, snapshot_count:9}`.
- ☐ **Verify the write, three ways** before declaring 5G-1D active:
  1. the returned `snapshot_count` = 9;
  2. REST/console read: `goal_funding_snapshots?model_year=eq.2026&week_num=eq.6` returns the
     **nine** eligible rows, `source='reconciliation'`, monotonic ≥ the Week-5 anchor;
  3. the live overlay agrees — the recon panel shows Week 6 **"Closeout complete · goal funding
     anchored"** (green badge); the Funding Plan reflects the anchored week.
- ☐ Confirm **no half-close**: `weekly_reconciliations` has the Week-6 row **and** the nine
  snapshots (atomic); no partial state.
- ☐ Capture balance-free evidence (returned JSON, nine-row id/source dump, badge screenshot).

**If the Week-6 closeout fails:** do **not** retry blindly. The old RPC is revoked (no fallback by
design); either (a) diagnose + re-submit through the wrapper if the failure is a correctable input,
or (b) invoke the pre-approved rollback (§7) to restore the old-RPC grant + revert the browser, then
re-plan. The wrapper was Gate-2-proven on staging, so a hard failure here is unlikely but the
rollback is one step away.

---

## 6. Post-activation verification (expected end state)

- ☐ **Grant matrix** (`-validation.sql`): authenticated EXECUTE — wrapper=T, Option B=T, old recon
  RPC=F, repair RPC=F, direct snapshot RPC=F; `goal_funding_snapshots` INS/UPD=F, SELECT=T;
  `weekly_reconciliations` INS/UPD/DEL=F, SELECT=T; anon all=F.
- ☐ **Bodies byte-unchanged:** E1 RPC + reconciliation RPC md5s == the pre-activation baseline
  (grants changed, bodies did not).
- ☐ **Wrapper-succeeds / bypass-fails proof pair recorded:** §5 proves the wrapper succeeds as
  definer-owner after the old-RPC revoke; §4.5 proves a direct/stale caller is denied before any
  persistence.
- ☐ **Week 6 fully closed** (reconciled ∧ nine snapshots); overlay + badge agree.
- ☐ **BUILD_TS** on dashboard.herndons.us = the new activation build.
- ☐ Ordinary weekly closeout now runs through the wrapper for both Adam and Wendy
  (`can_write_financials()`); reopen/correction remain owner-only, supervised, out of the ordinary UI.
- ☐ Update `CODEX_STATUS.md` / `docs/phase-status.md`: 5G-1D **production-live**; Gate B CLOSED;
  Slice 7 complete; first Week-6 closeout evidenced.

---

## 7. Rollback boundary (Gate B / activation)

Two independent, pre-approved rollbacks — apply the narrowest that resolves the problem:

1. **Grant rollback** — `-activation-grants-rollback.sql`: re-grant the old recon RPC (+ repair /
   snapshot RPC / table writes), revoke wrapper + Option B back to inert. Restores the
   pre-activation write paths. Separate approval.
2. **Browser rollback** — revert the merge on `main` (redeploy the pre-activation `index.html`); the
   old browser uses the old RPC (re-granted by rollback #1).

- **Boundary:** activation rollback restores the pre-activation grant posture **and** the
  pre-activation browser. It does **NOT** delete approved historical snapshots or undo completed
  reconciliation — **wrong values use the correction path (Option B), never a drop** (plan §9). The
  Week-5 anchor and any Week-6 rows already written stay; a rollback simply returns the write path
  to the old RPC.
- The Slice-6 restore-point dump remains the disaster floor beneath both.
- **Reopen/correction never restore direct old-RPC access** — the §4 revoke stands; both go through
  the wrapper's owner-only branches (plan §6.2).

---

## 8. Exact Adam approvals required (Gate B)

1. **Activation approval** (turn the combined closeout on) — gates the whole runbook.
2. **Phase 1 grants** execution (`-activation-grants.sql`).
3. **BUILD_TS stamp + merge → main** (browser deploy; Adam's push gate).
4. **Phase 2 revokes** execution (`-activation-revokes.sql`) incl. the old-RPC revoke (G-01) and the
   Gate-C `repair_commitments_for_week` posture (G-02).
5. **First Week-6 supervised closeout** (Adam performs it).
6. **Rollback approval** (held ready; used only on failure).
7. **Status-doc update** recording production-live + Gate B closed.

**No approval is inferred from another.** Gate B is closed only after §5 is green and §6 is recorded.
