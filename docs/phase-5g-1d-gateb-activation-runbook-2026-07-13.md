# Phase 5G-1D — Gate B Production Activation Runbook (Slice 7)

**Status:** RUNBOOK — NOT EXECUTED, NOT AUTHORIZED. Turns the combined closeout **on** in
production, in this order: activation grants → browser deploy (merge) → pre-revoke verify → **first
supervised Week-6 closeout through the wrapper (old RPC still granted as a fallback)** → write-surface
lockdown (old-RPC revoke) → **two non-mutating post-revoke proofs**. **Every step is separately
Adam-approved.** Nothing here is performed by this document; no grant, merge, deploy, or activation
happens until Adam runs each step. Gate B is closed only by the activation approval + a green first
closeout + the post-revoke proofs.

> **P0-1 activation-order correction (2026-07-13):** the first real Week-6 closeout now happens
> **before** the Phase-2 revokes, so the highest-risk first write keeps the old RPC as a fallback.
> "The wrapper is the sole write path" is then proven **after** the revoke by two NON-MUTATING probes
> (§4 steps 8–9), not by risking the first real write with no fallback. This supersedes the earlier
> "revoke-then-first-write" ordering.
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
- ☐ **Gate C dispositions APPROVED** (Adam, 2026-07-13 — `docs/phase-5g-1d-gatec-register-2026-07-13.md`
  §7): all 11 surfaces approved as recommended (rows 1–8 REVOKE, row 9 RESTRICT anchored weeks +
  owner-only cleanup path, rows 10–11 GRANT with Option B owner-gated). The approved posture matches
  `-activation-revokes.sql` exactly (no blocks commented out). **Row 9 requires a browser guard in
  the activation browser BEFORE the merge — see §4a.**
- ☐ **Gate A CLOSED** (`public.is_owner()`), ✓.
- ☐ **Browser complete + verified** (incl. the P0-4 row-9 `deleteRecon` guard AND the P1-1
  wrapper-response/persisted-state validation — both on the activation branch): **Adam-verified at
  commit `114b080f411fe68bfe377c902668677dd99f1710`:** static **1507/0**, local full `node e2e.js`
  **148/0/0**, readiness fallbacks **openApp 0 / clickNav 0**. *(Supersedes the pre-correction
  1486/0 and 142/0.)*
- ☐ **SECURITY DEFINER owner pinned (P0-3):** the Slice-6 preflight captured the trusted definer
  owner; migration pinned wrapper + Option B to it; validation proved it. `-activation-grants.sql`
  and `-activation-revokes.sql` re-assert owner-unchanged before acting.
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
- ☐ **SECURITY DEFINER owner (P0-3):** the `fn-owner` matrix shows wrapper + Option B owned by the
  trusted definer owner (== recon/snapshot RPC owner), SECURITY DEFINER = true; owner UNCHANGED
  since the Slice-6 capture (`-activation-grants-validation.sql` `fn-owner` == the preflight
  `definer-owner-baseline`);
- ☐ Week-5 anchor still nine `opening_anchor` + two `wewe_*` correction rows;
- ☐ latest reconciled week + latest complete snapshot week are consistent with a **Week-6** next
  closeout (the wrapper computes next = 6 + complete-count; confirm no gap).
- ☐ **ADJUNCT PREFLIGHT (Fable P2-1) — run `docs/phase-5g-1d-gateb-adjunct-preflight.sql` (READ
  ONLY) immediately before Phase 1.** It hard-stops unless: Week-5 partition = **9 `opening_anchor` +
  2 `correction` = 11 total**; `weekly_reconciliations` = **5 rows, weeks 1–5 only, latest = 5**; and
  **0 `goal_funding_snapshots` at `week_num ≥ 6`**. This proves the first supervised closeout will
  land cleanly at `week_num = 6` (calendar Week 28). **Any different result is a HARD STOP before
  Phase 1.**

**Hard stop** on any mismatch.

---

## 2. Required grants (the two phases)

| Phase | File | Blocks | Effect | When |
|---|---|---|---|---|
| **Phase 1 — activate** | `phase-5g-1d-activation-grants.sql` | G-10, G-11 | GRANT `authenticated` EXECUTE on wrapper + Option B | **before** browser deploy |
| **Phase 2 — lock down** | `phase-5g-1d-activation-revokes.sql` | G-01…G-08 | REVOKE old recon RPC + repair RPC + direct snapshot RPC + table INSERT/UPDATE/(DELETE) | **after the first Week-6 closeout is durably complete** (§4 step 6) |

Each phase: separate Adam approval + `-validation.sql` before/after matrix. Anon EXECUTE stays
false throughout; SELECT stays granted on both tables.

---

## 3. Feature-branch merge timing

- The browser (Slices 3/4/5 + the P0-4 row-9 guard + the P1-1 response validation) lives on
  `claude/herndon-5g-1d-preactivation-j428vn` (pushed; **not merged**). **Merging to `main`
  auto-deploys via GitHub Pages** — that merge **is** the browser deployment and must happen
  **only inside the activation window**, in this order:
  **Slice 6 done → Phase 1 grants → merge → pre-revoke verify → first supervised Week-6 closeout
  → Phase 2 revokes → post-revoke proofs.**
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

## 4. Application activation sequence (12 ordered steps; each separately approved where noted)

**The first real Week-6 closeout (step 4) happens BEFORE the Phase-2 revokes (step 6).** The old RPC
stays granted through the first write as a fallback; the "wrapper is the sole path" property is
proven AFTER the revoke by two NON-MUTATING probes (steps 8–9).

1. ☐ **Phase 1 grants** — run `-activation-grants.sql` (owner-pinned; hard-stops on an unexpected
   pre-grant unless `c_resume`); `-activation-grants-validation.sql` confirms wrapper + Option B now
   `authenticated`-EXECUTE (anon none), **old RPC still granted**, owner unchanged. Old browser
   unaffected.
2. ☐ **Stamp BUILD_TS + merge → deploy browser** (§3) — the branch includes the **row-9 guard
   (§4a)** and the P1-1 response validation. Pages build green; BUILD_TS advances on
   dashboard.herndons.us.
3. ☐ **New-browser verification (PRE-revoke, no write):** on a fresh production session, confirm
   Register/Budget/weekly render unchanged; the recon panel shows the Slice-4 closeout-state badges;
   opening a week's closeout shows the confirmation view (do **not** submit yet). Console clean.
   *(Old RPC still granted → a stale tab still works; no broken window.)*
4. ☐ **FIRST supervised Week-6 closeout THROUGH THE WRAPPER** (§5) — the first real reconciliation +
   nine-snapshot write. **The old recon RPC is still granted**, so this highest-risk step retains a
   fallback: a wrapper hard-failure on a correctable input does not strand the operator, and the
   browser-revert rollback needs no grant change. Verify the write three ways (§5). **Do not proceed
   to step 6 until Week-6 is durably complete.**
5. ☐ **Record the exact Week-6 wrapper payload + capture a LOCAL balance-bearing before-image.**
   Committed evidence stays balance-free (`week_num`, `p_mode`, the nine `goal_id`s,
   `snapshot_count`). Separately, **local-only (never committed — same discipline as the restore
   point):** capture the persisted Week-6 reconciliation **balances + `balance_basis`**, the **nine
   persisted round-2 snapshot values**, and the recon row + nine snapshot rows as the before-image.
   Proof A (step 8) replays these EXACTLY, and the non-mutation check compares against them.

> **▲ BINDING — Week-6 state freeze (Fable P1-1).** From the successful first closeout (step 4)
> **through completion of BOTH post-revoke proofs (steps 8–9): NO Option B correction of model week
> 6, and NO `approved_reopen` of model week 6.** A value issue discovered during this interval
> **waits until after Proof B** — do not touch week 6. If an owner mutation is genuinely unavoidable
> before the proofs complete: **(a) do NOT edit or weaken the revoke SQL; (b) re-capture the payload
> and before-image (step 5); (c) STOP and re-plan Phase 2.** Both proofs assume the Week-6 state is
> byte-identical to the step-5 before-image; any mutation in the interval invalidates them.

6. ☐ **Phase 2 lockdown** — run `-activation-revokes.sql`. Its pre-lockdown asserts hard-stop unless:
   wrapper granted, **old recon RPC still granted**, **owner unchanged**, and the **Week-6 closeout is
   a durable SUPERVISED-WRAPPER closeout** — **exactly one** Week-6 reconciliation row **and exactly
   nine** distinct eligible goal snapshots each `model_year=2026`, `week_num=6`,
   **`source='reconciliation'`** (with no other reconciliation-source rows at Week-6). **Phase 2 does
   NOT proceed merely because nine arbitrary snapshot rows exist** — they must be the
   reconciliation-source rows the wrapper wrote (F3); the script hard-stops on a source-qualified
   count ≠ 9. Revokes G-01…G-08 per the approved Gate C postures; execute the Gate-C
   `repair_commitments_for_week` posture here (G-02).
7. ☐ **Phase 2 validation** — `-activation-grants-validation.sql`: authenticated EXECUTE — old recon
   RPC=F, repair=F, snapshot RPC=F, wrapper=T, Option B=T; tables per §6; **owner invariant holds**
   and **all bodies byte-unchanged** vs the pre-activation capture.
8. ☐ **Post-revoke Proof A (NON-MUTATING) — wrapper idempotent re-submit.** Re-submit the EXACT
   Week-6 payload built from the step-5 local before-image (Fable P2-3): **the exact persisted Week-6
   reconciliation balances + `balance_basis`; empty `p_new_commitments` and `p_patched` arrays; the
   nine persisted round-2 snapshot values; `p_mode='normal_closeout'`; `p_expected_count=9`.** The
   wrapper → branch-F fully-closed identity returns
   `{ok:true, mode:'normal_closeout', idempotent:true, week_num:6, snapshot_count:9}`, makes **no
   inner-RPC write, mutates nothing**. Prove non-mutation: the Week-6 recon row + nine snapshots
   re-read equal to the step-5 before-image (no value/`updated_at` change). **Any drift from the
   before-image → re-read and retry; NEVER force the proof.** This proves the wrapper still works **as
   the definer owner after the revoke** AND is idempotent — with zero new mutation.
9. ☐ **Post-revoke Proof B (NON-MUTATING) — old-RPC bypass probe.** An authenticated direct POST to
   `/rest/v1/rpc/save_reconciliation_with_commitments` that **sends EVERY named argument of the 11-arg
   signature — including BOTH JSONB arguments (`p_new_commitments`, `p_patched`) — with
   `p_model_year = 9999`** (Fable P2-3). Sending the full argument set is required so PostgREST
   resolves the overload and the request reaches the **in-body validation rejection** (`invalid
   model_year: 9999`, before any write) rather than failing with a PostgREST signature-resolution
   (PGRST202/404) error that would prove nothing. Guaranteed non-mutating either way: (a) a
   grant-layer denial (401/403/404 — the revoke took), or (b) if the grant somehow persisted, the
   function's own first validation raises `invalid model_year: 9999` before any INSERT/UPDATE
   (grounded: `docs/phase-5f-1-migration.sql:510`, ahead of every write). Proves the bypass path is
   closed — or, worst case, still cannot write — without risking a real mutation. *(Optionally probe
   the direct table write / repair RPC / snapshot RPC the same non-mutating way.)*
10. ☐ **Stale-browser verification:** a cached OLD browser tab (calling the old RPC directly) now
    **fails before persistence** (grant-layer denial) — it must be refreshed.
11. ☐ **Fresh-browser verification:** a refreshed browser drives the wrapper end to end for the NEXT
    ordinary closeout.
12. ☐ **Post-activation verification + status update** (§6): expected end-state matrix; BUILD_TS;
    overlay/badge; update `CODEX_STATUS.md` / `docs/phase-status.md` → production-live, Gate B CLOSED.

**Ordering rationale (P0-1):** activation grant (1) before deploy (2) → no broken window. The first
REAL write (4) happens with the **old RPC still granted**, so a fallback exists at the highest-risk
moment; the write is proven durable (verified in §5, asserted again by the revoke's precondition)
**before** the old path is removed. Lockdown (6) runs only after that. The "wrapper is the SOLE write
path" property is then established by the two NON-MUTATING post-revoke proofs (8, 9) — never by
gambling the first real write on a no-fallback revoke-first order.

### 4a. Gate C row 9 — `deleteRecon` guard (REQUIRED in the activation browser, before the merge)

Gate C row 9 (approved) restricts deletion of anchored weeks. After Phase 2 G-08 (`REVOKE DELETE ON
weekly_reconciliations`), the current `deleteRecon` direct DELETE is denied for **every** week
(fail-closed). Two required parts:

- ☐ **Browser guard (index.html) — IMPLEMENTED on the activation branch (P0-4, verified @ commit
  `114b080`).** `canDeleteRecon(n)` offers reconciliation deletion **only** for a legacy pre-anchor
  week (1–4) that bears no snapshots with a known-good snapshot load, and **fails closed** on any
  uncertain load; anchor (5), `complete`, `half_closed`, `corrupt`, and any snapshot-bearing week are
  never deletable. `deleteRecon` re-checks the guard (defense in depth), does not optimistically drop
  local state on a denied DELETE, and surfaces a week-scoped operator message. Covered by static
  (`5G1D-P04-01…16`) + e2e (`5G1D-DEL-1…3`); part of the verified gate (static 1507/0, e2e 148/0/0).
  **No further browser work is required for row 9 before the merge** — just confirm the deployed
  `BUILD_TS` carries this build.
- ☐ **Owner-only cleanup/remediation path (separate design + approval):** legitimate deletion of an
  unanchored/exceptional week — if ever needed — goes through an owner-gated RPC or a supervised
  guarded-SQL runbook, **never** the ordinary UI and **never** as a correction. Draft + approve
  separately; not required for activation, but the register records it as the governed path.

**The row-9 browser guard is already on the branch and re-verified (P0-4 @ `114b080`) — this
pre-merge condition is SATISFIED.** No SQL change — the server side is G-08, already in
`-activation-revokes.sql`.

---

## 5. Supervised first production closeout (Slice 7 Week-6 writer smoke)

Under Option A (pre-freeze), the "Week-6 supervised smoke" **is the ordinary Week-6 combined
closeout** through the wrapper (readiness Slice 7, pre-freeze interpretation) — the first real
`reconciliation` + nine-snapshot write.

> **Model/calendar mapping (Fable-resolved):** "Week-6" everywhere in this runbook and in
> `-activation-revokes.sql` is the **model `week_num = 6`** — `getCalWeek(6) = 28`, i.e. **calendar
> Week 28**. The first supervised production closeout therefore persists `week_num = 6` to both
> `weekly_reconciliations` and `goal_funding_snapshots`; the F3 precondition (`c_first_close_week =
> 6`) targets exactly that row. The adjunct preflight (§1) confirms `weekly_reconciliations` currently
> holds weeks 1–5 only, so week 6 is the clean next write.

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

**If the Week-6 closeout fails:** do **not** retry blindly — but note this step runs **before**
Phase-2 (§4 step 6), so the **old RPC is still granted** and a fallback exists. Either (a) diagnose +
re-submit through the wrapper if the failure is a correctable input, or (b) invoke the
operational-continuity rollback (§7 / `-activation-grants-rollback.sql` section A) — revert the
browser; because the old-RPC grant is still in place, restoring the ordinary path needs no grant
change beyond de-activating the two new functions. **Do not run the Phase-2 revokes until this
closeout is durably complete** — the revoke script itself hard-stops if Week-6 is not complete. The
wrapper was Gate-2-proven on staging, so a hard failure here is unlikely, but the fallback is intact.

> **▲ BINDING — Week-6 state freeze (Fable P1-1), repeated here.** Once the first closeout SUCCEEDS,
> model week 6 is **frozen through completion of both post-revoke proofs (§4 steps 8–9): NO Option B
> correction and NO `approved_reopen` of week 6.** A value issue found in that interval **waits until
> after Proof B.** If an owner mutation is genuinely unavoidable: **do NOT edit or weaken the revoke
> SQL; re-capture the payload + before-image (§4 step 5); STOP and re-plan Phase 2.** A mid-interval
> mutation invalidates the proofs' before-image and forces a re-plan.

---

## 6. Post-activation verification (expected end state)

- ☐ **Grant matrix** (`-validation.sql`): authenticated EXECUTE — wrapper=T, Option B=T, old recon
  RPC=F, repair RPC=F, direct snapshot RPC=F; `goal_funding_snapshots` INS/UPD=F, SELECT=T;
  `weekly_reconciliations` INS/UPD/DEL=F, SELECT=T; anon all=F.
- ☐ **Bodies byte-unchanged:** E1 RPC + reconciliation RPC md5s == the pre-activation baseline
  (grants changed, bodies did not).
- ☐ **Wrapper-succeeds / bypass-fails proof pair recorded (both NON-MUTATING, post-revoke):** §4
  step 8 (Proof A) proves the wrapper still succeeds as definer-owner after the old-RPC revoke via an
  idempotent branch-F re-submit that mutates nothing; §4 step 9 (Proof B) proves a direct/stale old-RPC
  caller is denied (or, worst case, rejected before any write) via an invalid-input probe. Capture
  both outcomes + the before/after non-mutation equality.
- ☐ **Week 6 fully closed** (reconciled ∧ nine snapshots); overlay + badge agree.
- ☐ **BUILD_TS** on dashboard.herndons.us = the new activation build.
- ☐ Ordinary weekly closeout now runs through the wrapper for both Adam and Wendy
  (`can_write_financials()`); reopen/correction remain owner-only, supervised, out of the ordinary UI.
- ☐ Update the **post-activation status-refresh list** — `CODEX_STATUS.md`, `docs/phase-status.md`,
  **and `AGENTS.md`** (Fable P2-4 hygiene; refresh at activation, not tonight): 5G-1D
  **production-live**; Gate B CLOSED; Slice 7 complete; first Week-6 closeout evidenced.
- ☐ **P2-2 (post-activation roadmap constraint, recorded — NOT a Gate B blocker):**
  `weekly_reconciliations` is keyed **only by `week_num`** (no `model_year`), so the 2026 model
  weeks 1–31 will collide with a 2027 cycle. **Before the first 2027 closeout,** `weekly_reconciliations`
  must be re-keyed (add `model_year` to the key), archived, or otherwise handled. Tracked as a 5G-1D
  post-activation follow-up; does not affect the 2026 activation.

---

## 7. Rollback boundary (Gate B / activation)

**Grant rollback has two clearly-scoped modes (P0-2) in `-activation-grants-rollback.sql` — apply the
narrowest that resolves the problem:**

1. **Operational-continuity rollback (section A — default):** revoke wrapper + Option B back to inert
   and **re-grant ONLY the old recon RPC** so the ordinary weekly closeout works again (it is SECURITY
   DEFINER — its EXECUTE alone restores the reconciliation write path). Deliberately does **not**
   re-grant the repair RPC, the direct snapshot RPC, snapshot INSERT/UPDATE, or
   weekly_reconciliations INSERT/UPDATE/DELETE — those are not needed for continuity and the row-9
   DELETE restriction stays. Restores a **working** closeout, not the exact pre-activation matrix.
2. **Exact ACL restoration (section B — exceptional, separate approval):** reproduce the EXACT
   captured pre-activation grant matrix by **generating narrow GRANT/REVOKE statements from the
   pre-Phase-1 `-activation-grants-validation.sql` capture** — each re-grant checked against that
   captured privilege matrix. **Do NOT use a full schema/data restore (the Slice-6 dump) merely to
   recreate grants:** after the Week-6 closeout has written, restoring the dump would also revert that
   post-dump production data (see the DR boundary below). Grants are restored from the captured
   matrix, never from the dump.
3. **Browser rollback (paired with either):** revert the merge on `main` (redeploy the
   pre-activation `index.html`); the reverted browser writes through the re-granted old recon RPC.

- **Boundary:** an activation rollback restores a write path **and** the pre-activation browser. It
  does **NOT** delete approved historical snapshots or undo completed reconciliation — **wrong values
  use the correction path (Option B), never a drop** (plan §9). The Week-5 anchor and any Week-6 rows
  already written stay.
- **The Slice-6 dump is the catastrophic DISASTER-RECOVERY floor ONLY — not a routine Gate B
  rollback.** It was captured **before** Slice 6 and **before** the supervised Week-6 closeout, so it
  predates the first production write. After ANY post-dump production write (the Week-6
  reconciliation + nine snapshots, or anything later), restoring it is a deliberate DR action that
  requires: (1) **separate disaster-recovery approval**; (2) **explicit acknowledgement of the
  restore-point timestamp**; (3) **a plan to preserve/replay the post-dump data, or explicit
  acceptance of its loss**; and (4) **verification that the restore scope will not unintentionally
  overwrite valid later reconciliation/snapshot state.** It is never used to "restore grants."
- **Steady-state vs rollback (resolves the earlier contradiction):** in normal operation after
  activation, reopen/correction go through the wrapper's owner-only branches and the **old RPC is
  never used** — the §4 revoke stands. A **rollback is the one deliberate exception**: the
  operational-continuity mode re-grants the old recon RPC *on purpose* to restore the ordinary path
  while the wrapper problem is diagnosed. "Never restored" describes steady state; a rollback is not
  steady state.

---

## 8. Exact Adam approvals required (Gate B)

1. **Activation approval** (turn the combined closeout on) — gates the whole runbook.
2. **Phase 1 grants** execution (`-activation-grants.sql`).
3. **BUILD_TS stamp + merge → main** (browser deploy incl. the row-9 guard + response validation;
   Adam's push gate).
4. **First Week-6 supervised closeout** (Adam performs it) — **BEFORE** the Phase-2 revokes, with the
   old RPC still granted as a fallback.
5. **Phase 2 revokes** execution (`-activation-revokes.sql`) incl. the old-RPC revoke (G-01) and the
   Gate-C `repair_commitments_for_week` posture (G-02) — only after step 4 is durably complete.
6. **Post-revoke proofs** (Adam runs Proof A + Proof B, §4 steps 8–9) — both non-mutating.
7. **Rollback approval** (held ready; used only on failure — operational-continuity by default,
   exact-restore only if explicitly needed).
8. **Status-doc update** recording production-live + Gate B closed.

**No approval is inferred from another.** Gate B is closed only after the first Week-6 closeout is
green, the Phase-2 revokes are applied, the two post-revoke proofs pass, and §6 is recorded.
