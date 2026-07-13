# Phase 5G-1D — Independent Pre-Production Review: Corrections Closeout

**Date:** 2026-07-13
**Author:** Claude (session under Adam)
**Branch:** `claude/herndon-5g-1d-preactivation-j428vn` (feature branch; **not merged** — `main`
auto-deploys via GitHub Pages and the wrapper has no production grant until Gate B).
**Scope of this session:** correction / testing / planning reconciliation ONLY. **No SQL executed;
production and staging untouched; no merge to `main`; `BUILD_TS` NOT stamped; Slice 6 and Gate B NOT
begun.**
**Privacy:** balance-free.

An independent pre-production review (ChatGPT) assessed the 5G-1D pre-activation package and returned:
**core design sound; Slice 6 conditional; Gate B NOT yet ready**, with findings **P0-1…P0-4, P1-1…P1-3,
P2**. This document records each finding, its root disposition, the files changed, the tests added, the
SQL/browser semantic changes, unresolved owner decisions, and the updated Slice 6 / Gate B verdicts.

---

## 1. Findings → dispositions (summary)

| ID | Area | Disposition | Primary artifacts |
|---|---|---|---|
| **P0-1** | Activation order contradiction | **Fixed** — first Week-6 closeout **before** Phase-2 revokes; two NON-MUTATING post-revoke proofs | Gate B runbook §3/§4/§5/§6/§7/§8; Gate C register §4/§7.2; `-activation-revokes.sql` |
| **P0-2** | Rollback over-broad / "restores exactly" | **Fixed** — split into (A) operational-continuity + (B) exact-restore; claims corrected | `-activation-grants-rollback.sql`; Gate B runbook §7; Gate C register §4/§5 |
| **P0-3** | SECURITY DEFINER owner unvalidated | **Fixed** — capture (preflight) → pin (migration) → prove (validation + activation matrix) | `-preflight.sql`, `-migration.sql`, `-validation.sql`, `-activation-grants-validation.sql`, `-activation-grants.sql`, `-activation-revokes.sql`; both runbooks |
| **P0-4** | Row-9 `deleteRecon` guard missing | **Implemented (browser)** — `canDeleteRecon(n)` + defense-in-depth + no optimistic drop + message | `index.html`; `test_regression.js` (16); `e2e.js` (3) |
| **P1-1** | 2xx trusted without validation | **Implemented (browser)** — validate wrapper contract + persisted end-state before success | `index.html`; `test_regression.js` (5); `e2e.js` (3 + 2 updated) |
| **P1-2** | Slice-6 restore point under-specified | **Fixed** — hardened dump procedure + owner capture | Slice-6 deploy runbook §2/§3/§4/§7 |
| **P1-3** | Activation-script preconditions weak | **Fixed** — hard-stop/resume, pre-lockdown asserts, owner/Week-6 guards | `-activation-grants.sql`, `-activation-revokes.sql` |
| **P2** | Doc inconsistency | **Fixed** — status docs reconciled | `CODEX_STATUS.md`, `docs/phase-status.md` |

---

## 2. Browser semantic changes (`index.html`)

### P0-4 — row-9 `deleteRecon` guard
- New `_goalSnapLoadStatus` (`'unknown'|'unavailable'|'error'|'loaded'`) set by the `loadAll` snapshot
  loader and `reloadGoalSnapshots` — only `'loaded'` (a real 200 that parsed) proves a week is
  snapshot-free.
- New pure predicates `_anySnapshotAt(n)`, `canDeleteRecon(n)`, `deleteReconBlockedReason(n)`.
  Deletion is offered **only** for a legacy pre-anchor week (1–4) that bears **no** snapshots with a
  known-good load; it **fails closed** on any uncertain load; anchor (5), `complete`, `half_closed`,
  `corrupt`, and any snapshot-bearing week are never deletable.
- `deleteRecon(n)` re-checks `canDeleteRecon` (defense in depth), deletes local `reconData[n]` **only**
  inside the `if(r.ok)` branch (no optimistic drop on a denied/failed DELETE), and records a
  week-scoped `_reconDeleteError` operator message. The "Remove reconciliation" control render is
  gated on `w.reconciled && canDeleteRecon(w.num)`.
- **No production-facing behavior change today** (branch-held). Post-activation, weeks that carry
  closeout state simply no longer offer the raw delete; the governed owner-only cleanup path (an
  owner-gated RPC or supervised guarded-SQL runbook) is a separate design + approval.

### P1-1 — closeout response + persisted-state validation
- `submitCloseout` success path no longer treats any 2xx as success. It now:
  1. parses the wrapper JSON and requires the contract `ok===true && mode==='normal_closeout' &&
     week_num===n && snapshot_count===9`;
  2. re-reads **both** persisted halves (`reloadReconAndCommitments` + `reloadGoalSnapshots`);
  3. requires the durable end-state to be `isWeekReconciled(n) && closeoutState(n)==='complete' &&
     _persistedSnapshotsMatch(n,_closeout.funded)`;
  4. clears staging **only** when the contract AND the persisted state both confirm; otherwise treats
     the outcome as **unknown** (not failed, not done) — keeps the confirmation open with staging
     intact and an explanatory message, never silently reporting success.
- Fail-closed direction: a genuinely-landed write whose response was mangled shows "verify the week
  state" rather than a false success; a false success is never emitted.

---

## 3. SQL semantic changes (all AUTHORED, NOT executed)

- **P0-3 owner pinning** — `-preflight.sql` captures the trusted owner (recon/snapshot RPC + `is_owner`
  + `can_write_financials`) and hard-stops unless they share one non-client owner; `-migration.sql`
  asserts the two new functions were created owned by that exact trusted owner (hard-stop on drift or
  a client-role owner); `-validation.sql` re-proves owner==trusted in the structural loop + emits a
  `definer-owner` evidence row; `-activation-grants-validation.sql` adds an `fn-owner` matrix + owner
  invariant.
- **P0-1 pre-lockdown order** — `-activation-revokes.sql` now asserts, before any REVOKE: wrapper
  granted; **old recon RPC still granted**; **first Week-6 closeout durably complete** (recon row + 9
  eligible snapshots); owner unchanged; plus a manual row-9-guard-build reminder NOTICE.
- **P1-3 preconditions** — `-activation-grants.sql` hard-stops on an unexpected pre-existing grant
  (documented `c_resume` for a deliberate idempotent re-run) and asserts owner before granting;
  `-activation-revokes.sql` adds the `c_resume` resume mode for an interrupted Phase 2.
- **P0-2 rollback** — `-activation-grants-rollback.sql` rewritten into **(A) operational-continuity**
  (executable default: revoke wrapper + Option B to inert; re-grant **only** the old recon RPC — its
  SECURITY DEFINER EXECUTE restores the reconciliation write path without any table grant) and
  **(B) exact-restore** (a fenced, non-executing template applied against the captured pre-activation
  matrix under separate approval). The "restores exactly" claim and the "old RPC never restored"
  contradiction are corrected: steady state never uses the old RPC; a rollback is the one deliberate
  exception that re-grants it.
- **No function body, RLS policy, or row is touched by any grant script.** All remain env-guarded
  (production or approved staging).

---

## 4. Documentation changes

- **Gate B activation runbook** (`-gateb-activation-runbook-2026-07-13.md`): the 12-step ordered
  sequence (first Week-6 closeout before Phase-2 revokes; Proof A = idempotent branch-F re-submit,
  non-mutating; Proof B = invalid-`model_year` old-RPC bypass probe, rejected before any write —
  grounded at `docs/phase-5f-1-migration.sql:510`); revised ordering rationale; §5 fallback language;
  §6 proof-pair; §7 two-scope rollback + steady-state-vs-rollback; §8 approvals; §0/§1 owner + test
  numbers.
- **Gate C register** (`-gatec-register-2026-07-13.md`): §4 sequence + rollback scopes + owner
  invariant + non-mutating proofs; §5 boundary; §7.1 row-9 note updated to IMPLEMENTED; §7.2
  preconditions (Week-6 before revoke; two-scope rollback).
- **Slice-6 deploy runbook** (`-slice6-deploy-runbook-2026-07-13.md`): §2 hardened restore point
  (`pg_dump -Fc --no-owner --no-acl` public-schema, SHA-256, `pg_restore --list` verify, chmod 600,
  encrypted off-device, metadata-only committed, no credentials; public-schema-vs-platform clarified)
  + owner capture; §3/§4/§7 owner steps.
- **Status docs** (`CODEX_STATUS.md`, `docs/phase-status.md`): a new dated corrections section; the
  superseded 1486/0 & 142/0 numbers annotated → 1507/0 static + 148/0 expected e2e; Gate C
  approved-not-executed; Gate D Option A; Slice 6 unexecuted; Gate B unapproved; Gate E untriggered.

---

## 5. Tests added / updated

- **Static (`test_regression.js`), +21:** `5G1D-P04-01…16` (row-9 guard: deletable legacy week;
  anchor/complete/half_closed/zero-snapshot/snapshot-bearing/non-eligible-snapshot blocked; fail-closed
  on uncertain load; non-owner; non-reconciled; blocked-reason messages; guard-fail keeps state; +
  source invariants for guard-before-fetch, delete-only-on-r.ok, render gating, loader status).
  `P1-1a…e` (parse + contract; persisted-complete requirement; reload-before-check ordering;
  clear-only-in-gate; unconfirmed-2xx keeps `_closeout`).
- **E2E (`e2e.js`), +6 new / 2 updated:** `5G1D-CO-1` and `5G1D-CO-6` updated to supply a
  persisted-complete reload (the success path now verifies it); the wrapper mock echoes the posted
  week and gained a `badcontract` scenario. New `5G1D-CO-7` (2xx, empty reload → stays on confirm),
  `5G1D-CO-8` (2xx, `snapshot_count≠9` → not trusted), `5G1D-CO-9` (2xx, persisted≠confirmed → not
  trusted); `5G1D-DEL-1` (denied 403 DELETE keeps `reconData`), `5G1D-DEL-2` (allowed legacy delete
  removes it), `5G1D-DEL-3` (uncertain load → no DELETE issued, fail closed).

---

## 6. Verification

- **Static regression:** `node test_regression.js` → **1507 / 0** (sandbox-run; was 1486/0).
- **E2E:** the sandbox cannot initialize Supabase (CDN blocked → `AUTH_STATE` never terminal), so the
  full `node e2e.js` is **Adam's machine gate**. **Subsequently Adam-verified 148 / 0 / 0** at commit
  `114b080` (+3 CO + 3 DEL vs the prior 142), readiness fallbacks **openApp 0 / clickNav 0** — see §F.
  `node --check e2e.js` and `node --check test_regression.js` pass.
- `BUILD_TS` intentionally unchanged.

---

## 7. Unresolved / owner decisions

- **Owner-only cleanup/remediation path** (row-9's exceptional legitimate-deletion route) — still a
  separate design + approval; not required for activation.
- Everything gated remains gated: **Slice 6 inert deploy, Gate B activation, Gate C execution, the
  merge, the BUILD_TS stamp, and all production/Supabase actions each require their own explicit Adam
  approval.** No approval is inferred from another.

---

## 8. Updated verdicts

- **Slice 6 (inert prod deploy):** the review's conditions are now met on paper — owner capture/pin/
  prove (P0-3) and the hardened restore point (P1-2) are in the committed SQL + runbook. Slice 6
  remains **AUTHORED, NOT EXECUTED**; it is ready for its own execution approval + same-sitting
  restore point.
- **Gate B (production activation):** the P0-level blockers are resolved — activation order (P0-1),
  rollback scoping (P0-2), owner validation (P0-3), and the row-9 browser guard (P0-4) are in place,
  with P1-1/P1-3 hardening. Gate B remains **NOT READY TO EXECUTE** pending: Slice 6 done + green; the
  browser re-verified on Adam's full e2e (148/0, 0 fallbacks); and each Gate B approval in §8 of the
  runbook. The browser corrections **supersede** the prior 1486/0 and 142/0 gate results.

**Independent pre-production corrections complete. Awaiting Adam review before Slice 6 authorization.**

---

## §F. Addendum — Final independent production-readiness review (items F1–F3, 2026-07-13)

The independent final v2 review (ChatGPT, against feature-branch HEAD
`114b080f411fe68bfe377c902668677dd99f1710`) **accepted the browser** at the Adam-verified gate
(static **1507/0**, full `node e2e.js` **148/0/0**, readiness fallbacks **openApp 0 / clickNav 0**),
judged **Slice 6 conditionally ready** pending three narrow corrections, and **did not authorize Gate
B**. These are documentation + SQL comment/precondition changes only — **no application code
(`index.html`, `e2e.js`) changed; no SQL executed; nothing merged; `BUILD_TS` unchanged.**

| ID | Finding | Disposition | Files changed |
|---|---|---|---|
| **F1** | Current-facing docs still cited superseded / "expected" test counts | **Fixed.** All current-facing Slice 6 / Gate C / Gate B readiness statements now record the **Adam-verified** final gate at commit `114b080`: static **1507/0**, E2E **148/0/0**, fallbacks **0/0**. Historical counts retained only where explicitly marked superseded. | `slice6-deploy-runbook` (header + §1), `gatec-register` (header), `gateb-activation-runbook` (§0), `CODEX_STATUS.md` (corrections section + annotations), `phase-status.md` (pointer) |
| **F2** | The Slice-6 dump was described as a routine "exact grant restore" after Week-6 is written | **Fixed.** The dump was captured **before** Slice 6 and **before** the Week-6 closeout, so restoring it after any production write would revert that data. Binding posture recorded: **routine Gate B rollback** = operational-continuity grant rollback + browser revert + validation vs the captured privilege matrix, **never a dump restore**; **exact ACL restoration** = narrow GRANT/REVOKE generated **from the captured privilege matrix**, never a full schema/data restore; **the dump is the catastrophic DR floor only**, and after any post-dump write its restore is a separately-approved DR action requiring (1) DR approval, (2) restore-point-timestamp acknowledgement, (3) a post-dump-data preserve/replay-or-accept-loss plan, and (4) scope verification against later reconciliation/snapshot state. | `activation-grants-rollback.sql` (header ⚠ + (B) header + template comments), `gateb-activation-runbook` (§7), `gatec-register` (§5), `slice6-deploy-runbook` (§6) |
| **F3** | Phase-2 durable-closeout precondition accepted nine arbitrary snapshot rows | **Fixed.** `-activation-revokes.sql` precondition 3 now hard-stops unless there is **exactly one** Week-6 reconciliation row AND **exactly nine** distinct eligible goal snapshots each `model_year=2026`, `week_num=c_first_close_week`, **`source='reconciliation'`**, **and** the total `source='reconciliation'` row count at Week-6 is 9 (eligible-ids-only, no dupes/extras). Nine arbitrary snapshots no longer qualify — they must be the reconciliation-source rows the supervised wrapper wrote. | `activation-revokes.sql` (DECLARE `v_wk6_recon_rows`; precondition 3 logic + NOTICE), `gateb-activation-runbook` (§4 step 6) |

**SQL semantic change (F3, the only behavioral SQL change):** the Phase-2 hard-stop tightened from
`v_wk6_recon < 1 OR v_wk6_snaps <> 9` (any recon row + nine eligible snapshots of any source) to
`v_wk6_recon <> 1` **and** nine eligible `source='reconciliation'` snapshots **and** total
reconciliation-source rows = 9. F1/F2 are documentation + SQL-comment changes with no executable
effect.

**No application behavior changed.** `index.html` and `e2e.js` are untouched by F1–F3; the browser
gate (1507/0, 148/0/0) still stands at commit `114b080`.

**Final Slice 6 readiness verdict:** **conditionally ready → conditions met.** Owner
capture/pin/prove (P0-3) and the hardened restore point (P1-2) were already in the committed package;
F1–F3 close the final review's three narrow items. Slice 6 remains **AUTHORED, NOT EXECUTED**, pending
its own execution approval + a same-sitting restore point. **Gate B is not authorized by this work.**

**Final independent review corrections complete. Awaiting Adam authorization to commit and proceed to
Slice 6.**
