# Codex Status: Herndon Financial OS

## CURRENT-STATUS CORRECTION (2026-07-13)

*This dated banner reflects the verified current state. It does not rewrite any historical dated entry below; where older sections (e.g. the 2026-07-10/11 handoffs) still read "5G-1D implementation NOT STARTED," that language is historical and is corrected here.*

**Operating state (Adam-confirmed 2026-07-13):** Quicken parallel operation has **ended**; the Quicken subscription is **canceled**; the historical Quicken data is retained as a **historical archive/reference only**; the **Herndon Financial OS is now the sole live system of record.** Quicken is not an active operational system, parallel ledger, or independent live recovery replica. Any "parallel run through Aug–Sep / cancel only after one clean parallel month" language elsewhere in this file, `AGENTS.md`, or `docs/phase-status.md` is **stale** and superseded by this note. Consequence: scheduled restore-tested backups (off-device, encrypted, named backup owner, MFA) are an **immediate production/disaster-recovery requirement**, not a future cancellation prerequisite.

**5G-1D execution state (verified at HEAD `aff220c`):**
- **Slice 1** (`save_weekly_closeout_with_snapshots`) and **Slice 2** (Option B `correct_goal_funding_snapshot` wrapper) RPC layers are **staging-accepted** — the Gate-2 real-caller acceptance matrix **G2-1 … G2-20b PASSED** on staging (`pkwotgqivgaapwuqgwqb`, 2026-07-13); teardown/restore/ungrant/validation passed.
- Both new functions were **returned to inert grants** after testing (anon/authenticated EXECUTE = false/false); production DDL/data untouched.
- **Gate 0 (E2 completion)** and **Gate A (`is_owner()` identity)** are **CLOSED**.
- **Still outstanding:** Slice 3 (browser closeout UI + state machine), Slice 6 (prod inert deploy + inert checks), **Gate B (production activation)**, Slice 7 (Week-6 writer smoke + old-RPC grant revoke); **Gates C, D, E remain OPEN.** Gate D (pre- vs post-freeze activation timing) is an unresolved owner decision.
- **5G-1D is NOT production-live and is NOT complete.**

**Canonical post-5G-1D roadmap:** `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md` (advisory; adopt per Adam approval).

## 5G-1D BROWSER COMPLETE + GATE D DECIDED — Option A pre-freeze (2026-07-13)

**Supersedes the "remaining: Slice 3 … Gates C/D/E" line in the banner above for the browser and Gate D items.** Two owner-facing advances on 2026-07-13:

- **Gate D — DECIDED: Option A (pre-freeze activation), Adam-approved 2026-07-13.** Timing decision only; it does **not** authorize production deployment, production SQL, grant changes, merge to `main`, or Gate B activation. Target: activation + first Week-6 closeout complete **before Jul 24** (freeze Jul 24–Aug 10); realistic go/no-go ≈ Jul 16–17; first supervised Week-6 closeout ≈ Sat Jul 18.
- **Slices 3/4/5 — COMPLETE (browser closeout).** The weekly closeout now runs as a two-step atomic combined write through `save_weekly_closeout_with_snapshots` (confirmation view freezes the nine-row payload; drops the optimistic reconData write; state machine handles in-flight / GFA01-adjudication / domain-reject / ambiguous-re-read / half-close repair). Slice 4a/4b add `closeoutState(n)` + the reconciled-vs-fully-closed badges. Implemented in-place in `index.html` under the standing freeze exception; **branch-held on `claude/herndon-5g-1d-preactivation-j428vn` (pushed), NOT merged to `main` — `main` auto-deploys, and the wrapper has no production grant until Gate B.** `origin/main` holds docs only (`5bd6c69`).
  - **Local verification (Adam machine):** full `node e2e.js` **142 passed / 0 failed / 0 skipped**; readiness fallbacks **openApp 0 / clickNav 0**; runtime ~5 min. Static regression **1486/0**. `BUILD_TS` intentionally unchanged (branch-held, not deployed). **⟶ SUPERSEDED 2026-07-13 by the independent pre-production corrections (P0-4 row-9 guard + P1-1 response validation added): Adam-verified at commit `114b080` — static 1507/0; local full `node e2e.js` 148/0/0; readiness fallbacks openApp 0 / clickNav 0. See "## 5G-1D INDEPENDENT PRE-PRODUCTION REVIEW CORRECTIONS".**
  - The E2E run added six closeout tests (`5G1D-CO-1…6`, CO-1 smoke-tagged), consolidated onto one shared page. The earlier 4-failure run (LEDGER-1/A6-1/A9-1/A9-2) was root-caused to **pre-existing headless readiness/timing flakiness, not this branch** (all four run before the CO block; the index.html diff touches zero Register/auth/load symbols; load time is identical to `main`); the count 142 = 136 baseline (129 `await test(` source lines + the Section-A 8-tab loop) + 6.

- **Remaining pre-activation planning — DELIVERED (2026-07-13, this session; PLANS ONLY, nothing executed):**
  - **Gate C decision register:** `docs/phase-5g-1d-gatec-register-2026-07-13.md` — 11 write surfaces, current grant posture, recommended retain/wrap/restrict/revoke, required SQL, rollback, exact Adam approvals. **⟶ UPDATE 2026-07-13: all 11 dispositions APPROVED as recommended (Adam) — APPROVED, NOT EXECUTED; execution is Gate B.**
  - **Activation grant SQL package (authored, env-guarded, NOT executed):** `docs/phase-5g-1d-activation-grants.sql` (Phase 1 grants G-10/G-11), `-activation-revokes.sql` (Phase 2 lockdown G-01…G-08), `-activation-grants-rollback.sql`, `-activation-grants-validation.sql`.
  - **Slice 6 inert deploy runbook:** `docs/phase-5g-1d-slice6-deploy-runbook-2026-07-13.md` (preflight / restore point / deploy / validate / inert end state / rollback boundary / evidence). Uses the committed `docs/phase-5g-1d-{preflight,migration,validation,rollback}.sql`.
  - **Gate B activation runbook:** `docs/phase-5g-1d-gateb-activation-runbook-2026-07-13.md` (preflight / grants two-phase / merge timing / activation sequence / first Week-6 supervised closeout / old-RPC revoke / post-activation verification / rollback boundary).

- **Still OUTSTANDING (all require their own explicit Adam approval; none executed):** Gate C per-surface dispositions; Slice 6 inert prod deploy; **Gate B production activation** (Phase-1 grants → BUILD_TS stamp + merge `main` → Phase-2 revokes/old-RPC revoke → first Week-6 supervised closeout); Gate E remains OPEN-when-triggered (never triggered). **No production DDL, grant change, merge, or activation has occurred.**

## 5G-1D INDEPENDENT PRE-PRODUCTION REVIEW CORRECTIONS (2026-07-13)

An independent pre-production review (ChatGPT) returned "core sound; Slice 6 conditional; Gate B not
yet ready" with findings P0-1…P2. All are addressed on `claude/herndon-5g-1d-preactivation-j428vn`
(correction/testing/planning only — **no SQL executed, no production/staging touched, no merge, no
BUILD_TS stamp, Slice 6 and Gate B NOT begun**). Full closeout:
`docs/phase-5g-1d-independent-preproduction-review-closeout-2026-07-13.md`.

- **P0-4 (browser, IMPLEMENTED):** row-9 `deleteRecon` guard — `canDeleteRecon(n)` offers deletion
  only for a legacy pre-anchor (wk1–4), snapshot-free week with a known-good snapshot load; fails
  closed on uncertain load; anchor/complete/half_closed/corrupt/snapshot-bearing blocked; defense-in-
  depth re-check in `deleteRecon`; no optimistic local removal on a denied DELETE; week-scoped
  operator message. Tests `5G1D-P04-01…16` (static) + `5G1D-DEL-1…3` (e2e).
- **P1-1 (browser, IMPLEMENTED):** `submitCloseout` no longer trusts a bare 2xx — it validates the
  wrapper contract (`ok`/`mode`/`week_num`/`snapshot_count===9`), reloads BOTH halves, and requires
  the persisted end-state to be `closeoutState==='complete'` with the nine snapshots matching, else
  routes to the unknown/review path (staging preserved). Tests `P1-1a…e` (static) + `5G1D-CO-7/8/9`
  (e2e).
- **P0-1 (activation order):** the first supervised Week-6 closeout now runs **before** the Phase-2
  revokes (old RPC retained as a fallback); "wrapper is the sole path" is proven **after** by two
  NON-MUTATING post-revoke probes (idempotent branch-F re-submit; invalid-input old-RPC bypass probe).
  Unified across the Gate B runbook, the Gate C register, and `-activation-revokes.sql` (pre-lockdown
  asserts, incl. Week-6-durably-complete).
- **P0-2 (rollback):** `-activation-grants-rollback.sql` split into (A) operational-continuity
  (default — re-grant the old recon RPC only) and (B) exact-restore (exceptional, from the captured
  matrix); "restores exactly" and the old-RPC-restore contradiction corrected.
- **P0-3 (SECURITY DEFINER owner):** preflight captures the trusted owner; migration pins the two new
  functions to it; validation + the activation-grant matrix prove owner==inner-RPC-owner (non-client),
  unchanged across activation.
- **P1-2 (Slice-6 restore point):** hardened to a custom-format restorable `pg_dump`
  (`-Fc --no-owner --no-acl`, public-schema), SHA-256, `pg_restore --list` verify, chmod 600,
  encrypted off-device copy, metadata-only committed, no credentials in evidence.
- **P1-3 (activation preconditions):** grants hard-stop on an unexpected pre-grant (documented
  `c_resume`); revokes assert wrapper-granted + old-RPC-still-granted + Week-6-complete + owner-
  unchanged + a row-9-guard-build reminder.
- **P2 (doc consistency):** this section + `docs/phase-status.md` reconciled to Gate C
  approved-not-executed, Gate D Option A, the two browser corrections (superseding 1486/0 & 142/0 →
  Adam-verified 1507/0 static + 148/0/0 e2e @ commit 114b080), Slice 6 unexecuted, Gate B unapproved,
  Gate E untriggered.

**Verification (Adam-verified at commit `114b080f411fe68bfe377c902668677dd99f1710`):** static
regression **1507 / 0**; full `node e2e.js` **148 / 0 / 0**; readiness fallbacks **openApp 0 /
clickNav 0**. **Final independent production-readiness review (ChatGPT) accepted the browser at this
gate; three narrow final corrections F1–F3 (test-count refresh, restore-point boundary, Phase-2
durable-closeout precondition) applied — see
`docs/phase-5g-1d-independent-preproduction-review-closeout-2026-07-13.md` §F.** Slice 6 conditionally
ready; Gate B not authorized. **Awaiting Adam authorization to commit and proceed to Slice 6.**

## Current Phase

Phase 5B complete.
Budget Module v1 live.
5F-1 complete through Phase 4 and proven in a real weekly closeout (Week 26, 2026-07-04).
5F-1.5 Gate A (Wendy July usability) UI shipped and live (2026-07-05/06), including the Register Quicken-style ledger hotfix (historical Balance) and the Register CL/reconciliation default view (commit 8d48b04, Wendy-confirmed and live-smoked on dashboard.herndons.us). A4 (AMEX Gold starting-balance correction) is DONE (executed and verified 2026-07-06).
Wendy Budget-tab live use in progress (target July 1, 2026).

Next major phase: 5G Cash Planning + Allocation (locked). 5G-0 (label/docs cleanup) is CLOSED — see "## 5G-0 CLOSED". 5G-1A (Weekly Transfer Routing + Readiness) is SHIPPED (commit `c8613bc`) — see "## 5G-1A SHIPPED". UX-0 (display-only Budget row treatment: BUD-1/BUD-2/SYS-3) is SHIPPED (commit `c5873fb`) — see "## UX-0 SHIPPED". UX-0.5 (Wendy visual polish, display-only: B1–B4, R1–R2) is SHIPPED (commit `739567b`) — see "## UX-0.5 SHIPPED". 5G-1 is the first schema/build sub-phase; its **staging DB/security layer is validated** (schema rehearsal + real-caller RLS smoke + `app_environment` hardening, 2026-07-08; commits `eeee4cb`/`7f0d0a0`, pushed) — the **production DDL and app-side build remain gated**. See `docs/phase-status.md` for the 5G-0 through 5G-5 map, gates, and the pre/post-Alaska split.
5G-1A.5 (AMEX Hold Sub-MIN_XFR Deadlock Hotfix) is SHIPPED and pushed (commit `f307db7`, production-verified 2026-07-08) — resolves the AMEX-hold sub-`MIN_XFR` waterfall completion deadlock surfaced by the 2026-07-08 funding-model integrity review (`docs/funding-model-integrity-review-2026-07-08.md`); runModel freeze exception approved by Adam. See "## 5G-1A.5 SHIPPED".
5G-1C-1 (Funding Plan Projection Semantics) is SHIPPED and pushed (commit `de4e3c0`, production-verified 2026-07-08) — display-only Funding Plan "When"-column labels that distinguish current-week funded from projected year-end funded (retires the misleading "Beyond 2026"). See "## 5G-1C-1 SHIPPED". The larger 5G-1C plan (week-anchored `goal_funding_snapshots`) split into two slices: 1C-1 shipped; **5G-1C-2 C2 (the staging SQL package for `goal_funding_snapshots`) is staging-validated and committed+pushed** (`5bbcab2`); **C3 (the app-side overlay) is SHIPPED + DEPLOYED** (`c6fbb32`, live on dashboard.herndons.us `BUILD_TS 2026-07-09T08:51:21`; inert until snapshot rows exist). See "## 5G-1C-2 C3 SHIPPED + DEPLOYED" and "## 5G-1C-2 C2 STAGING-VALIDATED". Plan + Fable review: `docs/phase-5g-1c-plan-2026-07-08.md`, `docs/phase-5g-1c-plan-review-2026-07-08.md`.
5G-QA-1 (E2E Runner Speed / tag-based Smoke Gate) is COMPLETE and pushed — a test-infra-only, two-slice change to `e2e.js`: Slice A (opt-in tag-based smoke mode, `05a5558`) and Slice B (deterministic openApp/clickNav waits, `d8e21a0`). Full mode (`node e2e.js`) remains the permanent default and release gate at 133/0, Skipped 0; runtime 538.45s → 415.77s. Smoke is a developer accelerator only (19/0, Skipped 114, ~44–50s). `readinessFallbackHits` 0/0. No index.html/BUILD_TS, `push_to_github.sh`, `test_regression.js`, or SQL change. See "## 5G-QA-1 SHIPPED".
5G-1C-2 PRODUCTION SQL PACKAGE is CREATED and pushed (commit `3061644`) — the six production-only SQL files for `goal_funding_snapshots`, scoped to **Adam-Dashboard (usayoldrawwmjsmretin)** and marked never-run in **herndon-fos-staging (pkwotgqivgaapwuqgwqb)**. Docs/SQL-only; no index.html/BUILD_TS/app/test/push change. See "## 5G-1C-2 PRODUCTION SQL PACKAGE COMMITTED".
**5G-1C-2 E1 (production DDL) is COMPLETE and GREEN (2026-07-09)** — the E1 runbook `docs/phase-5g-1c-2-e1-runbook.md` (Fable-cleared @ `e1b9252`, Free-plan restore-point mechanism) was executed in one sitting against Adam-Dashboard (usayoldrawwmjsmretin): preflight PASS → migration PASS (M-table=1, M-rpc=1) → validation PASS (all V true, table empty, exact grants, RPC gate proven) → post-migration inert live check PASS. **Production now holds `public.goal_funding_snapshots` + `public.save_goal_funding_snapshots`, schema-only and EMPTY; app is behavior-inert (loader 404→200-empty only).** No seed, no rollback. **E2 (first-anchor seed) remains a separate explicit in-session approval gate and was NOT run; 5G-1D not started.** See "## 5G-1C-2 E1 COMPLETE". **UPDATE (2026-07-10):** the 5G-1D **planning stack is now CLEARED** (plan + correction/reopen/remediation companion spec + implementation-readiness package, all on `main`); **5G-1D IMPLEMENTATION remains NOT STARTED; Gate 0 (E2) is now SATISFIED — E2 COMPLETE + GREEN 2026-07-11 (see "## 5G-1C-2 E2 COMPLETE") — so 5G-1D may proceed under its own implementation approval + Gates A–E** — see "## 5G-1D READINESS CLEARED — E2 / GATE 0 BLOCKING (2026-07-10)".
**5G-1C-2.1 (Post-Anchor Model Coherence Hotfix) is COMPLETE + GREEN (2026-07-11).** A post-E2 regression surfaced when the Week-5 anchor went live (duplicate Adam-IRA seed + RCCL/DCL re-funding); fixed in two legs — Leg 1 application code (`c0a3476`) restoring the post-anchor IRA seed latch, and Leg 2 two guarded Week-5 holding-state correction snapshots (`wewe_rccl=600`, `wewe_dcl=500`, executed **once** in production, the nine opening-anchor rows proven unchanged). 5G-1D is now unblocked from the snapshot-anchor/correction dependency but remains **NOT STARTED** (own approval + Gates A–E; writes subsequent weekly closeout snapshots, not the opening anchor). See "## 5G-1C-2.1 COMPLETE".

**5G-1D Slice 2 (Option B) — Gate 2 staging execution is COMPLETE + GREEN (2026-07-13).** The full real-caller acceptance matrix **G2-1 … G2-20b PASSED** on staging herndon-fos-staging (`pkwotgqivgaapwuqgwqb`), followed by teardown/restore, ungrant (both new functions returned to inert), and validation (deployed RPCs byte-unchanged). Week-5 opening anchor restored to the exact nine; Weeks 6–10 synthetic test state removed; **production DDL/data untouched**. Local execution artifacts under `~/.gate2-sp3.BSeaeh/` are local-only. 5G-1D Slice 2 is **staging-accepted**; **Gate B (production activation) remains OPEN**. See "## 5G-1D SLICE 2 (Option B) — GATE 2 STAGING EXECUTION COMPLETE (2026-07-13)".

## 5G-1D READINESS CLEARED — E2 / GATE 0 BLOCKING (2026-07-10)

> **SUPERSEDED IN PART (2026-07-11): E2 is now COMPLETE + GREEN and Gate 0 is SATISFIED — see "## 5G-1C-2 E2 COMPLETE". The "E2 remains UNEXECUTED / Gate 0 OPEN/BLOCKING / 5G-1D blocked" statements in this dated 2026-07-10 section are historical.**

Docs-only handoff of the cleared 5G-1D planning stack into the frontier. **No implementation, SQL, Supabase, E2, or grant action occurred. E2 remains UNEXECUTED; `goal_funding_snapshots` is EMPTY; 5G-1D implementation has NOT started.** *(As of 2026-07-10; superseded — see banner above.)* Full detail lives in the governing artifacts below — this section is the visible summary; it does not restate their designs.

**Current phase state:**
- 5G-QA-1: **COMPLETE**
- E1 production DDL: **COMPLETE** (schema-only, EMPTY; immutable)
- E2 runbook: **CLEARED**
- E2 execution: **COMPLETE + GREEN (2026-07-11)** — see "## 5G-1C-2 E2 COMPLETE"
- 5G-1D implementation plan: **CLEARED**
- 5G-1D correction / reopen / remediation companion spec: **CLEARED**
- 5G-1D implementation-readiness package: **CLEARED**
- 5G-1D implementation: **NOT STARTED / BLOCKED BY GATE 0**

**Cleared artifact references (paths + cleared commits):**
- E2 runbook — `docs/phase-5g-1c-2-e2-runbook.md` @ `c439d684349544ac0bc57295c82aafa83a7c202f`.
- 5G-1D implementation plan — `docs/phase-5g-1d-plan-2026-07-09.md` @ `6de4614f5c0a64c253f948fa8ee4dcce34d7ef61`.
- Correction / reopen / remediation companion spec — `docs/phase-5g-1d-snapshot-correction-procedure-2026-07-10.md` @ `f0052636ee987224a1acc1e686f250559a46366a`; SHA-256 `503d82a828ca8b8fefb72f196ab0ffc0c8f361df733c76f3f1945ac1ff335b53`.
- Implementation-readiness package (authoritative gate register + slice plan) — `docs/phase-5g-1d-implementation-readiness-2026-07-10.md` @ `a55d899e6979827cf553c21492a4e3eec57acf57`; SHA-256 `bae1799b70837f96757847293153083b3328a1bc0003ec8c9f0430100a4e7139`.

**Approved decisions (settled — see the readiness package §1 and the correction spec for detail):**
- **D1 — Option A is a temporary bridge only.** The supervised guarded-SQL correction path is not the steady-state path; it retires for post-anchor corrections when Option B deploys.
- **D2 — Option B is built in 5G-1D Slice 2.** Owner-only correction wrapper: internal `public.is_owner()` enforcement; Wendy/household_admin rejection; existing-row requirement; nearest-existing monotonicity bounds; call-through to the deployed snapshot RPC; **no Week-5 anchor amendments through Option B**.
- **D3 — Week-5 opening-anchor amendments preserve `source='opening_anchor'`.** Evidence records the amendment; the nine-row opening-anchor guard must continue to pass.

**Gate register summary (concise; the full register is in the readiness package §3):**

| Gate | Status | Trigger | Evidence (one-line) | Hard stop |
|---|---|---|---|---|
| 0 — E2 completion | **CLOSED / SATISFIED (2026-07-11)** | before Slice 0 | completed Week-5 reconciliation, approved Value Card, successful E2 seed/validation, nine opening-anchor rows, live verification, closeout evidence | no 5G-1D implementation until closed; a missed Week-5 window requires a new Value Card + re-review |
| A — `public.is_owner()` identity | **CLOSED (2026-07-11)** | before staging acceptance of owner-only functionality | exactly one active owner row; Adam true; Wendy false; real-login mapping verified | no owner-only reopen/correction acceptance until proven |
| B — Option B activation gate | OPEN | before production activation | Option B deployed + validated, or an Adam-approved dated deferral (rationale, owner, expiry/review, interim controls) | no activation otherwise |
| C — `repair_commitments_for_week` posture | OPEN | before activation grant changes | caller/dependency audit + explicit retain/wrap/restrict/revoke decision | no activation grant changes without disposition |
| D — activation timing | OPEN | before implementation sequencing is finalized | explicit Adam decision between safe pre-freeze activation and post-freeze activation with a gap-repair plan | no 5G merges during the Alaska freeze; a missed pre-freeze go/no-go defaults to post-freeze |
| E — historical multi-week remediation | CONDITIONAL / OPEN WHEN TRIGGERED | when a correction would change later weeks or create historical rows | separate reviewed remediation plan + Adam approval | no cascade/backfill under an ordinary correction approval |

**Current sequencing (active):** (1) Week-5 reconciliation → (2) E2 Value Card → (3) E2 local execution artifacts → (4) fresh in-session E2 clearance → (5) explicit Adam seed approval → (6) E2 execution and validation → (7) E2 closeout → (8) separate 5G-1D implementation approval → (9) Slice 0 onward under the cleared readiness package. **Saturday is reserved for Week-5 reconciliation and E2.** **No 5G-1D implementation before Gate 0 closes. No 5G merge during the Alaska freeze (Jul 24–Aug 10).**

**Non-authorization (explicit):** clearing and recording these artifacts **does not authorize implementation**. **E2 remains unexecuted.** All future implementation, deployment, activation, correction, reopen, remediation, grant change, rollback, and production actions **require their own gates and approvals**; no approval is inferred from another.

## 5G-1D SLICE 2 (Option B) — GATE 2 STAGING EXECUTION COMPLETE (2026-07-13)

**Gate 2 (real Auth→JWT→PostgREST acceptance matrix) for 5G-1D Slice 2 is COMPLETE + GREEN on staging herndon-fos-staging (`pkwotgqivgaapwuqgwqb`, `system_identifier 7656985631720456337`).** The cleared Gate-2 package (`docs/phase-5g-1d-gate2-*`, committed `5cb8039`) was executed exactly as written, one operator-gated sub-phase at a time; execution produced **no repository change** (committed artifacts were run, not modified). **Balance-free** — every value synthetic (opening-anchor fixtures 100–900, Option-B correction 120, atomic sentinel 424242.42); no household balances.

**Full executable matrix G2-1 … G2-20b PASSED.** anon/unauthorized grant-layer + `42501` authz rejects; new closeout + identity/`GFA01` idempotency; reopen branch matrix (approved_reopen, changed-recon re-stamp, branch-E commitment reject, older-week reject); Option B correction (in-bounds 100→120 `source=correction`, stale-prior, below-preceding and above-following monotonic bounds, Wendy `42501`); monotonicity rejects (anchor / reconciliation / correction priors + broken-chain anchor-incomplete); half-close repairs (one-missing + zero-snapshot) each with the mandatory wk10 blocked-advance; and atomic rollback of both a commitment CREATE (G2-20a) and PATCH (G2-20b) via a temporary staging trigger. **All expected reject phrases matched verbatim.** Every mutation/repair passed its whole-state FP-3 fingerprint + integrity assertions.

**Teardown + restore + ungrant + validation (Sub-phase 10) PASSED.** `GATE-2 TEARDOWN PASS` — footprint gate OK; **Weeks 6–10 synthetic test state removed**; **Week-5 opening anchor restored to the exact nine** (100–900, `opening_anchor`, `[STAGING-FIXTURE]`); no scaffolding/backup remains. `UNGRANT PASS: 0 EXECUTE` — the **temporary `authenticated` EXECUTE grants** on `save_weekly_closeout_with_snapshots` + `correct_goal_funding_snapshot` were **revoked**; both new functions are back to the **intended inert post-test grant state** (anon/authenticated EXECUTE = false/false) — this was **staging execution and did not alter any production grant**. `VALIDATION PASS` — the **staging deployed RPC definitions are byte-identical to the approved baselines** (`save_reconciliation_with_commitments` md5 `1bfde751ac647c5e9a25ba168d08150c`; `save_goal_funding_snapshots` md5 `154231b3f180349ec328f08ccbe77076`); structural/mutex/namespace asserts hold; the **old `save_reconciliation_with_commitments` authenticated grant remains intact** (a Slice-7 action, not now).

**Scope / safety.** **Production DDL and production data were NOT modified** — staging-only, enforced by the `system_identifier` + `app_environment` guard on every mutating block. The two Adam/Wendy staging `auth`/`app_users` fixtures are **intentionally retained** for a separately-approved cleanup step (not deleted here). Mid-run staging JWT expiries were handled by the approved narrow in-place credential rotation and the approved emergency trigger cleanup, leaving no residue.

**Local-only artifacts (NEVER commit).** All filled execution copies, access tokens/anon key, owner/Wendy UUIDs, the captured `PATCH_ID`, and `.bak` rotation backups live under `~/.gate2-sp3.BSeaeh/` (chmod 600, **outside the repository working tree**); the committed `docs/phase-5g-1d-gate2-*` templates remain placeholder-only. No household values, tokens, or UUIDs are committed.

**Disposition.** 5G-1D Slice 2 (Option B owner-only correction wrapper) is **staging-accepted** via the Gate-2 matrix. This advances but does **not** close **Gate B (production activation)** — activation remains a separate approval. No 5G-1D production/activation/grant action is authorized by this record.

## 5G-1C-2 E2 COMPLETE (2026-07-11): first opening_anchor seeded, C3 overlay live

**E2 (first-anchor seed) is COMPLETE + GREEN.** Executed by Adam in the Supabase SQL Editor against PRODUCTION Adam-Dashboard (`usayoldrawwmjsmretin`), one authorized gate at a time; Claude ran no SQL. Independent review of the two local value-filled execution copies returned PASS before authorization.

**Result:** nine `opening_anchor` rows at `model_year=2026, week_num=5`, `source=opening_anchor` (goals: adam_ira, wendy_ira, wendy_sep, alaska, bailey_529, bryce_529, preston_529, bryce_vehicle, christmas_cruise). No excluded goal seeded. The shipped C3 overlay is now **live** (loader HTTP 200, nine rows; funded values match the approved Value Card; excluded goals unchanged; Adam IRA still CPA-pending, Alaska complete, Adam 401(k) Auto·Payroll).

**Gates (all PASS):** Gate 1 read-only precheck (recweeks {1–5}, latest reconciled 5, snapshots 0, sysid match); Gate 2 seed (9 rows, run once); Gate 3 validation (**SA-PROD PASS**; **SA8 advisory PASS — expected under-attribution from the excluded RCCL/DCL holdings + account interest, no over-attribution**; SA9 nine-row dump matches the card); Gate 4a live verification.

**Privacy:** no household balances or SA8 dollar amounts are committed. The nine values live in the approved Value Card + local execution artifacts only; the committed sentinel templates retain their nine `-1` value sentinels. Full closeout evidence + local-artifact hashes: `docs/phase-5g-1c-2-e2-closeout-2026-07-11.md`.

**Downstream: Gate 0 (E2 completion) for 5G-1D is SATISFIED (2026-07-11).** 5G-1D implementation may proceed under its own implementation approval + Gates A–E (no approval inferred). E1 DDL was not rerun or mutated.

## 5G-1C-2.1 COMPLETE (2026-07-11): post-anchor model coherence hotfix (Leg 1 code + Leg 2 holding correction)

**COMPLETE + GREEN in production.** Emergency two-leg hotfix for a post-E2 planning regression exposed when the Week-5 opening anchor went live. Leg 1 (application code) shipped at `c0a3476`; the Leg 2 (guarded Week-5 holding-state correction) SQL templates were committed at `b863266` and executed **once** by Adam in the Supabase SQL Editor against PRODUCTION Adam-Dashboard (`usayoldrawwmjsmretin`). Claude ran no SQL. **This section is balance-free** (standing rule): the nine opening-anchor dollar values and the derived Adam-IRA residual live only in the approved Value Card + local execution artifacts, never committed. Full record: `docs/phase-5g-1c-2.1-hotfix.md`.

**Root cause.** Reconciled Week 5 could not fully reconstruct post-transfer goal state from account balances alone: (1) E2 seeded only the nine eligible opening-anchor goals and **omitted the RCCL/DCL holding-state facts**, so the waterfall re-derived and re-funded them; and (2) the snapshot overlay restored `goalSaved` without restoring the **run-local Adam-IRA seed latch (`rtSavSwept`)**, so the one-time IRA seed re-fired post-anchor. Together these produced a duplicate IRA seed, RCCL/DCL re-funding, a blocked Alaska $7,000 draw, a suppressed IRA residual-to-target, and added flight-path breaches.

**Resolution.**
- **Leg 1 (code, `c0a3476`)** restored post-anchor IRA seed coherence: a named `IRA_SEED_EMBEDDED_THRESHOLD` latch placed immediately before the seed-eligibility gate sets `rtSavSwept` when the current-week `adam_ira` snapshot already embeds the seed, suppressing the seed in that week and all later weeks. The end-of-week `goalSaved` overlay was left unchanged (goalVariance timing preserved).
- **Leg 2 (SQL, `b863266` templates)** added **two guarded Week-5 correction snapshots** — `wewe_rccl = 600` and `wewe_dcl = 500`, `source='correction'`. `funded_amount` is **cumulative funded PROGRESS, not current cash held**; payout does **not** reset funded progress to zero (releases are a later lifecycle layer, 5G-1B).

**Production proof (2026-07-11, balance-free).**
- **Preflight (all passed):** `current_user = session_user = postgres`; `system_identifier = 7632885393857617092`; `snapshots_total` before = **9**; `latest_reconciled_week = 5`; Week-5 RCCL/DCL rows before = **0**; `wewe_rccl` target `600.00` / auto `false`, `wewe_dcl` target `500.00` / auto `false`.
- **Correction:** committed **once**, producing exactly **11 Week-5 rows** = 9 `opening_anchor` + 2 `correction` (`wewe_rccl = 600.00`, `wewe_dcl = 500.00`). **The nine E2 opening-anchor rows were proven unchanged** (each row's id/source/exact funded amount asserted against its pin before the insert).
- **Validation:** the read-only `REPEATABLE READ` SA-COR block PASSED and returned the same exact 11-row partition; the SQL Editor showed the SA-COR result with no errors.
- **UI smoke (hard refresh, PASSED, qualitative):** RCCL 100% and DCL 100% funded; Alaska funded and complete; Adam IRA still short by its sub-$100 residual-to-target, scheduled **exactly once** in Week 28, with Wendy IRA advancing in Week 29; **no duplicate Adam-IRA seed**; no Week-28/29 RCCL/DCL transfer recommended; Week 27 retains its executed transfer-history rows; Funding Plan shows Alaska/RCCL/DCL funded; the Financial Flight Path no longer shows the duplicate-funding regression (next projected breach Week 35); the Capital Allocation Queue shows Alaska/RCCL/DCL done with Adam IRA next.

**Execution & privacy discipline.** The correction file was executed **once and must never be rerun** — plain INSERT with **no `ON CONFLICT`**, so a rerun raises the `UNIQUE(model_year,week_num,goal_id)` violation and fails loudly. The committed sentinel templates (`docs/phase-5g-1c-2.1-prod-holding-correction.sql`, `docs/phase-5g-1c-2.1-prod-holding-correction-validation.sql` @ `b863266`) remain **unfilled** — eleven `-1` pins each, **no household values**. The local value-filled execution copies remain **outside the repository** at `~/Herndon-FOS-DB-Backups/Adam-Dashboard/5G-1C-2.1/` (chmod 600), never committed.

**Gate disposition.**
- **5G-1C-2.1: COMPLETE** (both legs live and verified).
- **5G-1D:** now **unblocked from the snapshot-anchor / correction dependency** — the Week-5 opening anchor is coherent post-fix and the holding-state omission is corrected. **5G-1D implementation remains NOT STARTED** and still requires its own implementation approval + Gates A–E (no approval inferred). **5G-1D writes subsequent weekly closeout snapshots and does NOT create the opening anchor** — the Week-5 `opening_anchor` remains E2's and is not authored by 5G-1D.

**Repository integrity (this closeout).** Documentation-only: no new production DDL, no E1 DDL rerun or modification, no schema change, no migration, no application/test/UI change, and no household financial values added to any tracked file.

## Current Goal

Prepare the system for Wendy using the Budget tab in live household workflow while preserving platform stability, RLS security, and reconciliation accuracy. 5F-1 forward reconciliation is now live and proven; remaining 5F-1 sub-items (dashboard Review Required verdict rendering, historical repair mode) are deferred and do not block forward weekly closeout.

## Recent Verified State

- Static regression tests: 1374/0 passing (as of 5G-1C-1 Funding Plan projection semantics; 5G-1A.5 was 1359/0, UX-0.5 1350/0, UX-0 1344/0)
- E2E: 133/0 passing in FULL mode (`node e2e.js`, Skipped 0) — the permanent default and release gate; runtime improved 538.45s → 415.77s after 5G-QA-1 Slice B. A developer-only smoke mode (`node e2e.js --smoke` or `E2E_MODE=smoke node e2e.js`) runs the 19 smoke-tagged Wendy-critical + 5G-funding tests (19/0, Skipped 114, ~44–50s); `readinessFallbackHits` 0/0. Smoke is opt-in only and is NOT a gate. The earlier WC-3/BR-3 "known e2e failure" language is stale for this branch; do not re-cite it without re-verifying. Note: the balance-invariant e2e tests LEDGER-1 and A9-1 are intermittently flaky in the headless environment and clear on immediate re-run with no code change.
- Dashboard stable
- GitHub Pages deploys from main

## Do Not Break

- Adam/Wendy role model
- RLS protection
- Budget transactions
- Reimbursable behavior
- Reconciliation panel
- Existing Quicken parallel-run workflow

## Next Candidate Work

Active next-phase pointer: 5G-0 CLOSED, 5G-1A SHIPPED, UX-0 SHIPPED, UX-0.5 SHIPPED, 5G-1A.5 SHIPPED+pushed, **5G-1C-1 SHIPPED+pushed** (`de4e3c0`, production-verified 2026-07-08). **5G-1 staging DB/security layer is validated and pushed** (RLS smoke `eeee4cb`, `app_environment` hardening `7f0d0a0`); **production DDL and the app-side functional build remain gated**. IRA-goal correction ($7,000→$7,500, funded amounts preserved) is DONE (commit `1dcc686`); the AMEX sub-`MIN_XFR` waterfall deadlock it exposed is FIXED by 5G-1A.5 (commit `f307db7`, pushed — see "## 5G-1A.5 SHIPPED"). **5G-1C-2 — Goal Funding State Integrity** (review doc §5/§7 Phase B: week-anchored `goal_funding_snapshots` + runModel overlay): the plan doc was updated with Fable R1–R13 (`e1eac07`), the pre-snapshot golden-master identity gate was captured (`e0be9dc`), **C2 (the staging SQL package) is staging-validated + pushed** (`5bbcab2`), and **C3 (the app-side overlay) is SHIPPED + DEPLOYED** (`c6fbb32`, pushed; live `BUILD_TS 2026-07-09T08:51:21` on dashboard.herndons.us; static 1392/0, e2e 133/0; inert until snapshot rows exist — see "## 5G-1C-2 C3 SHIPPED + DEPLOYED"). **5G-QA-1 is COMPLETE and pushed** (Slice A `05a5558` tag-based smoke mode + Slice B `d8e21a0` deterministic waits; `e2e.js`-only; full 133/0 default gate preserved, runtime 538.45s→415.77s, smoke 19/0 opt-in ~44–50s, fallback 0/0 — see "## 5G-QA-1 SHIPPED"). **5G-1C-2 production SQL package is CREATED + PUSHED** (`3061644`; six `docs/phase-5g-1c-2-prod-*` files — see "## 5G-1C-2 PRODUCTION SQL PACKAGE COMMITTED"). **E1 (production DDL) is COMPLETE + GREEN (2026-07-09)** — preflight/migration/validation/inert-check all PASS against Adam-Dashboard (usayoldrawwmjsmretin) under runbook `e1b9252`; production now holds `goal_funding_snapshots` + `save_goal_funding_snapshots`, schema-only and EMPTY; app behavior-inert (see "## 5G-1C-2 E1 COMPLETE"). **Immediate next work item is E2 (first-anchor seed)** — manual Supabase in Adam-Dashboard (usayoldrawwmjsmretin), separate explicit in-session Adam go-ahead required; **do NOT start E2 without it.** **E2 reconfirm:** production's latest reconciled week is **4** (E1 preflight P6), so the First-Anchor Value Card must use the **wk-4 basis** or wait for a wk-5 reconciliation. No first-anchor seed has run. THEN 5G-1D write-through. Optional still-open: the capped pre-5G UX cleanup bundle (FLOW-2, FLOW-1, WK-1, REG-1, SYS-2; rider REG-2). Future candidate (not sequenced): TX-1 — see `docs/tx-1-candidate.md`. **SUPERSEDED (2026-07-10):** the "wk-4 basis or wait for wk-5" language above is superseded by the cleared E2 runbook §2 decision to **wait for the Week-5 reconciliation** (wk-4 basis not used). The 5G-1D planning stack (plan + correction spec + implementation-readiness package) is now **CLEARED and on main**; **E2 is Gate 0 (OPEN / BLOCKING)** and **5G-1D implementation is BLOCKED until Gate 0 closes** — see "## 5G-1D READINESS CLEARED — E2 / GATE 0 BLOCKING (2026-07-10)".

1. 5G-0: label/docs cleanup — DONE (static 1332/0, e2e 131/0). See "## 5G-0 CLOSED".
2. 5G-1A: Weekly Transfer Routing + Readiness — SHIPPED 2026-07-07, commit `c8613bc` (static 1339/0, e2e 131/0). RCCL/DCL reclassified to AMEX Savings holding (out of the `'goal'` sentinel), holding labels, paycheck-cleared readiness note. See "## 5G-1A SHIPPED".
3. **UX-0: BUD-1, BUD-2, SYS-3 — Budget row treatment, display-only — SHIPPED 2026-07-07 (static 1344/0, e2e 131/0).** Treatment authority: the Wendy 5G Budget mockup spec v1.2 (`docs/specs/wendy-5g-budget-mockup-spec-2026-07-07.md`). Desktop visual review passed (Adam, 2026-07-07). See "## UX-0 SHIPPED".
4. **UX-0.5: Wendy Visual Polish — SHIPPED 2026-07-07, commit `739567b` (static 1350/0, e2e 131/0).** Display-only presentation pass over Budget + Register (B1 legend, B2 attention strip, B3 section-header hierarchy, B4 "Over by" badge rhythm, R1 Register helper bar, R2 edit/delete affordance). Desktop visual review passed (Adam, 2026-07-07). R3 (uncleared-row treatment) deferred. See "## UX-0.5 SHIPPED".
5. 5G-1: planned_outflows + outflow_events schema; seed Mint Mobile; append-only events; opening adjustment from dated snapshot; Mint transfer_funded to AMEX Savings. **Staging DB/security layer validated** (rehearsal + real-caller RLS smoke + `app_environment` hardening, 2026-07-08; commits `eeee4cb`/`7f0d0a0`, pushed). **Production DDL and app-side build still GATED** on: Mint vendor/amount/date confirmation, prod DDL approval, app-side ES modules, and `showCashPlanning` enablement.
6. 5G-2: derived Account Allocation view (Spoken For / Free to Use).

Future candidate (not sequenced, NOT next, explicitly NOT UX-0.5): **TX-1 — Transaction Category Integrity + Income Taxonomy + Budget Attribution.** Register data-quality workstream: proper BKCPA Extra Pay income category (`income.bkcpa_extra_pay`, behavior_class `commission_income`, budget_treatment `display_only`), reimbursement/offset categories (e.g. Bailey shared-repair repayment), required-category + save validation for manual transactions, uncategorized review/filter + cleanup list, and budget-period attribution/carryover ("covered by June" vs current-month Extra). Guardrails: no Weekly Model cash-math changes unless explicitly required; no duplicate inflow/tax rule/goal allocation. Full definition + the three motivating examples: `docs/tx-1-candidate.md`.

Deferred (not next by default): **5G-1B — holding→payout lifecycle** for the RCCL/DCL cruise deposits (release event when the real cruise payments leave AMEX Savings, ~Cal Wk 30/41). Known accepted standing offset until then. See the 5G-1A section.

The 5G-1 DB/security layer is validated on staging (2026-07-08); do not start the **production DDL or the app-side build** until Adam gives the in-session go-ahead (staging Supabase + baseline export are already in place).

Active spec path: `docs/specs/phase-5g-1-spec-2026-07-07.md` (**v1.4** — **STAGING rehearsal + real-caller RLS smoke COMPLETE** on project `pkwotgqivgaapwuqgwqb` (confirmed ≠ prod `usayoldrawwmjsmretin`); production DDL still gated). v1.4 fixes a grant-normalization defect the staging rehearsal caught on 2026-07-08: the migration now `REVOKE ALL … FROM PUBLIC, anon, authenticated` before granting least-privilege (Supabase defaults had left `authenticated` with DELETE/UPDATE/TRUNCATE — and TRUNCATE bypasses RLS); validation adds V4h/V4i asserting the exact `authenticated` grant set. Rehearsal status: **COMPLETE and green on v1.4 (2026-07-08, project `pkwotgqivgaapwuqgwqb`).** Full sequence passed: marker → post-marker schema-only baseline → preflight → migration → validation (all V1–V10 including V4h/V4i exact-grant checks and the V8d/V9/V9b behavioral probes) → seed (2 NULL-amount `[STAGING]` Mint plans) → seed validation (S1/S3 true, S2 = the 2 expected unconfirmed rows) → rollback (RB1–RB4 clean) → post-rollback schema-only diff empty except pg_dump's per-run `\restrict`/`\unrestrict` random tokens (grep for 5G-1 objects = 0). The v1.4 grant-normalization fix is validated on a real database; staging left clean (baseline + retained sentinel). Still gated before production (RLS behavioral smoke now **COMPLETE** 2026-07-08 — see the RLS-smoke paragraph below): Mint vendor/amount/date confirmation (Mint vs US Mobile), prod DDL approval, app-side ES modules, and `showCashPlanning` enablement. v1.2 hardening: atomic marker, guard requires `amex_gold` to exist before the `-8248.50` fingerprint (closes NULL silent-pass), preflight `P4d` = amex_gold+amex_savings+truist_checking, immutable `planned_outflows` audit/identity columns (created_by_user_id/created_at/key) via guard trigger, `outflow_events.funding_account_key` NOT NULL, V9 reframed as trigger-layer proof (RLS append-only proven structurally). v1.3: seed validation split into `docs/phase-5g-1-seed-mint-staging-validation.sql`; added V8d constraint-behavior probe; documented that the SQL rehearsal proves structure but NOT RLS behavior (SQL editor bypasses RLS — separate live-smoke).

**RLS behavioral smoke — COMPLETE and green on staging `pkwotgqivgaapwuqgwqb` (2026-07-08).** The separate real-caller smoke (follow-on to the structural rehearsal) ran in two gates. **Gate 1** (SQL role-impersonation via `SET LOCAL ROLE` + `request.jwt.claims`, one rolled-back txn): passed after **correcting the smoke's mismatch model to the deployed `auth.uid()` model** — both `is_allowed_user()` and `can_write_financials()` key on `auth.uid()` (Phase 4B migrated `is_allowed_user()` off the mutable email claim; the `auth-v1` report's email-based body is stale). So M1 (email-match + wrong sub) = read+write **DENY** and M2 (sub-match + wrong email) = read+write **ALLOW**; the earlier "write-cannot-read" concern was an artifact of the stale model and is **void**. Gate 1 also re-asserts exact grants + no DELETE/TRUNCATE/REFERENCES/TRIGGER, append-only, and key/created_at immutability. **Gate 2** (real Auth→JWT→PostgREST via a throwaway `scratchpad/gate2-smoke.sh`, uncommitted): passed **18/18** across anon/unauthorized/viewer/writer (anon denied 401/42501; unauthorized read `[]` + write 403/42501; viewer read-yes/write-no + 0-row PATCH proven no-mutation; writer read/insert-yes, OE UPDATE/DELETE + PO DELETE 403/42501, key-immutability blocked). **FK-safe cleanup** completed (rollback drops `outflow_events`→`planned_outflows`, then delete test `app_users`, then delete W/V/U staging `auth.users`); staging **returned to clean baseline** — RB1–RB4 + post-cleanup checks all true, `app_environment` sentinel and `fn_set_updated_at()` retained, no 5G-1 objects, no test identities. Production untouched. RLS is now cleared at both the policy layer and the real API path. Artifacts committed (commit `eeee4cb`, pushed): `docs/phase-5g-1-rls-smoke-gate1.sql`, `docs/phase-5g-1-rls-smoke-gate2.md`, `docs/phase-5g-1-rls-smoke-cleanup.sql` (+ `scratchpad/` gitignored for local secrets). **`app_environment` RLS-hardening — DONE on staging (2026-07-08; commit `7f0d0a0`, pushed):** `docs/phase-5g-1-appenv-hardening.sql` ran green — `REVOKE ALL … FROM PUBLIC, anon, authenticated` + `ENABLE ROW LEVEL SECURITY` (no policies → default-deny for API roles); H1–H3 + ALL_PASS true (owner/service-role sentinel reads intact, RLS on, anon/authenticated zero grants). No app/runtime dependency on the sentinel (confirmed: no non-docs references); production has no `app_environment` (N/A there). `showCashPlanning` remains **off/absent**.

**Staging rehearsal execution order (spec §16; STAGING ONLY, on ref confirmation):** (0) confirm project ref ≠ prod → (1) `phase-5g-1-staging-env-marker.sql` → (2) schema-only `pg_dump` baseline → (3) `phase-5g-1-preflight.sql` → (4) `phase-5g-1-migration.sql` → (5) `phase-5g-1-validation.sql` (pre-seed) → (6) `phase-5g-1-seed-mint-staging.sql` → (7) `phase-5g-1-seed-mint-staging-validation.sql` → (8) `phase-5g-1-rollback.sql` → (9) post-rollback schema-only diff vs the step-2 baseline. RLS behavioral smoke (real authenticated/anon) is **COMPLETE** (see the RLS-smoke paragraph above; commit `eeee4cb`, pushed). Accompanying gate/SQL package (**run on staging as the rehearsal + smoke, then rolled back — staging left clean; NOT run against production**): `docs/phase-5g-1-staging-env-marker.sql`, `docs/phase-5g-1-preflight.sql`, `docs/phase-5g-1-migration.sql` (schema-only, `BEGIN/COMMIT`), `docs/phase-5g-1-seed-mint-staging.sql` (staging test seed; production seed deferred), `docs/phase-5g-1-validation.sql`, `docs/phase-5g-1-rollback.sql`. The spec defines the SQL-enforceable staging gate (project-ref proof primary + sentinel `app_environment` + prod data-fingerprint hard-stop; prod ref `usayoldrawwmjsmretin`), the DB baseline artifact (pg_dump schema-only, post-marker/pre-migration, distinct from the code-only AI review pack), the `planned_outflows`/`outflow_events` model (append-only events with DB-level sign/memo CHECKs, no stored balance, nullable `created_by_user_id`, RLS `TO authenticated` + anon revoked, no plan hard-delete), Mint seed amounts+vendor TBD (Mint vs US Mobile), the `showCashPlanning` feature flag (default false), and acceptance tests AT-1..AT-10. v1.1 resolved the 11-point SQL review (auth.uid nullability, V9 fail-propagation, TO authenticated, txn-wrapping, CREATE FUNCTION, sign/memo checks, no-delete, funding constraints, staging prereqs, baseline timing, seed split). **Nothing migrated to production yet; the staging DB/security layer (schema + RLS + `app_environment` hardening) is validated and torn down clean.**

Known gates and pre-reqs live in `docs/phase-status.md` (Phase 5G gates) and `AGENTS.md` (Do Not Touch, schema/migration conventions). Key blockers: Wendy feedback on Available for Goals; A2 income actuals before 5G-3; Diablos/GLP WD fix + WC-3 disposition + baseline weekly-model recapture before 5G-4a; zero-outflow identity automated test before 5G-4b; calculation-core extraction (5G-2.5) before 5G-3 / 5G-4a. Alaska freeze window: July 24 through August 10 (no 5G merges).

### UI/Flow Review v2 (2026-07-07) — planning note [FINAL 2026-07-07, all decisions confirmed]

UI/Flow Review v2 completed 2026-07-07 (`docs/reviews/ui-flow-review-triage-2026-07-07.md`; triage input only, not implementation authority; Wendy-confirmed workflow overrides). Do not treat all 24 findings as immediate work. See `docs/phase-status.md` "UI & Flow Review Inputs" for the full breakdown.

**Sequencing decision: RESOLVED 2026-07-07 (option a executed).** The Wendy 5G Budget mockup spec is final and fully confirmed: `docs/specs/wendy-5g-budget-mockup-spec-2026-07-07.md` (v1.2). It is the treatment authority for BUD-1, BUD-2, SYS-3, and the 5G mock frames.

**5G-0 scope: LOCKED.** Label/docs cleanup only: "Available for Goals" rename, SYS-1 (Statement check retitle, strip phase strings), SYS-4 (exact strings only), WK-6 (pluralization). No Budget row treatment work in 5G-0.

**UX-0 slice: DEFINED.** BUD-1, BUD-2, SYS-3. Display-only, no schema/RLS/logic. Lands immediately after 5G-0, before 5G-1, or inside the pre-5G bundle if that ships first. Treatment authority is the mockup spec. BUD-1/BUD-2/SYS-3 route to UX-0, not 5G-0.

**Pre-5G UX cleanup bundle: unchanged** (FLOW-2, FLOW-1, WK-1, REG-1, SYS-2; rider REG-2 per the triage cap rule).

**Recommended pre-freeze order:** (a) decide whether to run the capped pre-5G bundle, then (b) 5G-0, then (c) UX-0, then (d) 5G-1 behind existing gates (staging DB/security layer now validated 2026-07-08; remaining gates: prod DDL approval + Mint confirmation + app-side ES modules + `showCashPlanning`; Alaska freeze July 24 through August 10 unchanged).

**Confirmed decisions (full log in the spec, Section 9):**

- Near-limit amber, final: lines >= $100 amber when Spent >= 90% of Budget AND Remaining <= $100; lines under $100 have no amber state (neutral until over, then red). Red = over budget on actuals only, rendered as red value plus "Over by $X" badge, no row tint. No pacing logic. Intended behavior: the $34 Google line stays neutral at $33.60 spent and only changes state if it goes over.
- Income Remaining: muted "expected," never red, no late-income signal.
- Confirms: amber-dark for Archive and Register delete; red fully retired from controls.
- Set Aside writes, final: Adam records events in v1 by soft household convention; Wendy views. No isOwnerUser gate, no new owner-only role logic for Cash Planning writes; 5E-7 role matrix untouched. Help copy notes Adam handles set-aside entries for now. Revisit only if usage shows a need.
- Upcoming Spend horizon: 6 weeks.
- Two-entry pattern for transfer-funded set-asides accepted for v1 and disclosed to Wendy plainly (spec Section 1).
- Cash Planning nav item visible to Wendy at 5G-1, bills only, purpose line explicit; allocation placeholder line in position until 5G-2.
- 5G-2 allocation frame added to the mock set, annotated "Arrives after the first Cash Planning release."

**Next action:** build the four static mock frames (5G-0, 5G-1 set, 5G-2 allocation, 5G-3 before/after) from the spec for the Wendy walkthrough.

## 5G-1A.5 SHIPPED (2026-07-08): AMEX Hold Sub-MIN_XFR Deadlock Hotfix

**SHIPPED and pushed at `f307db7` (production-verified 2026-07-08). Static 1359/0, e2e 131/0.** Phase A of the 2026-07-08 funding-model integrity review (`docs/funding-model-integrity-review-2026-07-08.md`); runModel freeze exception explicitly approved by Adam (5G-1A precedent).

**Root cause:** an `_amxHold` goal left with a sub-`MIN_XFR` (<$100) remainder passed through `maxSafeAmxSweep()` — which floors any amount below `MIN_XFR` to 0 — before reaching `mv()`; a 0 from that gate triggered defer+`break`, halting the **entire** waterfall for the week, every week. After the $7,000→$7,500 IRA target correction (`1dcc686`) Adam IRA sat at **$7,438.94 of $7,500 (99%, $61.06 remainder)**, so from Cal Wk 28 on **no goal received another dollar** (Wendy IRA + all 529s $0; Bailey "Beyond 2026"). The `allowFin` completion carve-out already at `mv()` was unreachable because the AMEX gate broke first.

**Fix (index.html, runModel only — Edits A/B/C):**
- **A — completion carve-out** at the `_amxHold` call site: `(rem0 < MIN_XFR*2 && amxSweepKeepsFloor(proposed,…)) ? proposed : maxSafeAmxSweep(…)`, mirroring `mv()`'s `allowFin` rule. The 5-week `amxSweepKeepsFloor` safety check is retained — a floor-unsafe sub-$100 sweep still defers+breaks.
- **B — defer-label accuracy:** distinguishes a floor-safe-but-below-$100-minimum surplus ("surplus below $100 minimum transfer") from a genuine floor risk (original "5-wk lookahead: floor risk" wording byte-identical).
- **C — retRem** sourced from the registry Adam IRA target ($7,500) via a hoisted `adamIraTarget`, not the stale hardcoded 7000 (retirement no longer reads complete ~$500 early).

**Scope guardrails honored:** no schema/RLS/RPC/SQL; no priority, target, or reconciliation-logic changes; no broader model refactor; Phase B (`goal_funding_snapshots`) NOT started. **Week 27 transfer outputs byte-identical** (tr/ac/goalSaved/balances pinned by test).

**Tests (test_regression.js, +9 — Section PHASE-A):** pinned-production reproduction of the 99% deadlock; Week-27 byte-identity; deadlock-resolved (Adam IRA completes, Wendy IRA funds); no-permanent-starvation; all-five-goals-complete; carve-out predicate (floor-safe rescued); safety predicate + full-model safety (floor-unsafe sub-$100 still defers); retRem-from-registry. Pre-fix deadlock signature documented as constants.

**Live smoke — PASSED (Adam, local build 2026-07-08):** Adam IRA completes at Cal Wk 29 ($61.06 → AMEX Savings, "Adam IRA funded"); Wendy IRA continuation confirmed; Week 27 transfer stack unchanged; genuine floor-risk labeling preserved.

**Known follow-up (NOT a blocker):** in the live UI Bailey 529 reaches **73%** and its row still reads "Beyond 2026". Analysis (two headless demonstrations) shows this is a **live-surplus/forecast property**, not a hotfix defect: the waterfall now correctly flows through Adam→Wendy→Bailey, and downstream 2026 completion depends on total annual deployable surplus (live `budget_rules`/`model_week_overrides`/reconciled balances, tighter than the review's synthetic pinned anchor) plus the AMEX 5-week lookahead conservatism. The stale "Beyond 2026" row label is a projection-semantics issue. Both are folded into **5G-1C — Goal Funding State Integrity + Funding Plan Projection Semantics** (next phase).

**Follow-up: 5G-1C.** The Bailey "Beyond 2026" projection-label issue is resolved by **5G-1C-1 (shipped, `de4e3c0`)** — see below. The durable per-goal funded state (`goal_funding_snapshots`) is **5G-1C-2**, which remains HOLD. Shipped and pushed; production live smoke passed 2026-07-08 (Adam IRA completes Cal Wk 29, Wendy IRA continuation, Week 27 unchanged).

## 5G-1C-1 SHIPPED (2026-07-08): Funding Plan Projection Semantics

**SHIPPED and pushed at `de4e3c0` (production-verified 2026-07-08 on dashboard.herndons.us, BUILD_TS `2026-07-08T19:18:39`). Static 1374/0, e2e 132/0.** Slice 1 of the two-slice 5G-1C plan (`docs/phase-5g-1c-plan-2026-07-08.md`), architecture-approved by Fable (`docs/phase-5g-1c-plan-review-2026-07-08.md`, "5G-1C-1: GO now"). **Display-only** — no runModel/waterfall/getGoalFunded/goalCompletion/balances/schema/RPC/RLS changes; no runModel freeze exception needed.

**Problem:** the Funding Plan "When" column keyed off *current-week* funded state, so a goal with $0 funded now that receives *projected* partial funding by year-end (Bailey 529, ~73%) but never completes in-horizon fell through to the misleading **"Beyond 2026"** — while the Funding Timeline (which reads the final model week) showed the 73%. The row and the timeline read different weeks.

**Fix (index.html `_renderGoalsFunding` only):**
- **New pure display helper `_fundingWhenLabel(item)`** owns the whole label matrix (testable in isolation, no model/data access).
- **items map** adds read-only `fundedYE`/`pctYE` = the final model week's `goalSaved[id]` snapshot (projected year-end funded). No new model run; `sortKey` unchanged so rows do not move.
- **Approved wording matrix:** fully funded + unlocked → `✅ Funded`; fully funded + locked → `✅ Staged — awaiting CPA clearance`; completes in-horizon → `Cal Wk XX`; current funded but never completes → `In Progress · Continues in 2027`; $0 now + projected partial (fundedYE > 0.005) → `Partial in 2026 · Continues in 2027`; $0 now + no projected funding → `No 2026 funding projected`. "Beyond 2026" retired. In Progress / Partial rows carry a `Projected YE $X · $Y left (Z%)` sub-line (remaining clamped ≥ 0). Precedence: a locked-but-still-accumulating goal (Adam IRA 99%) shows its projected completion `Cal Wk 29`, not a bare lock; the 🔒 lock is still conveyed via the name prefix + `ft-locked-row`.

**Tests (test_regression.js, +15 net — Section 10a-2 `5G1C1-01..15`):** pure `_fundingWhenLabel` truth table (all 8 matrix rows incl. isFunded × isLocked, EPS noise guard, locked-incomplete precedence, auto/stretch non-regression), full-render Bailey "Partial" + Bryce/Preston "No 2026" (deterministic synthetic vm), live-fixture "no Beyond 2026" + funded-row no-regression. Three prior tests repointed (Awaiting-CPA text → ft-locked-row / Staged; whitelist token set). **PHASE-A Week-27 golden stayed green** (proves model output byte-identical). e2e (+1): resilient Goals › Funding "no Beyond 2026 / When column renders" (`132/0`).

**Production smoke — PASSED (Adam, 2026-07-08):** no "Beyond 2026" labels; Bailey 529 `Partial in 2026 · Continues in 2027` + Projected YE (73%); Adam IRA `Cal Wk 29` (locked via name/icon); Wendy IRA `Cal Wk 42`; Bryce/Preston `No 2026 funding projected`; Alaska/Wewe RCCL/Wewe DCL/Wendy SEP `✅ Funded`; Adam 401(k) `Auto · Payroll`.

**5G-1C-2** plan doc was updated with Fable R1–R13/G1–G7/D1–D8 (`e1eac07`) and the pre-snapshot golden-master identity gate was captured (`e0be9dc`). **C2 (the staging SQL package) is now staging-validated and committed** — see "## 5G-1C-2 C2 STAGING-VALIDATED". **C3 (the app overlay) is SHIPPED + DEPLOYED** — see "## 5G-1C-2 C3 SHIPPED + DEPLOYED".

## 5G-1C-2 PRODUCTION SQL PACKAGE COMMITTED (2026-07-09): prod goal_funding_snapshots gate (PRE-EXECUTION)

**COMMITTED and PUSHED to `origin/main` at `3061644` (6 files, 1247 insertions). Docs/SQL only — NO index.html/BUILD_TS, no e2e.js/test_regression.js, no push_to_github.sh, no app/runtime change** (`--no-verify` used to keep `index.html`/BUILD_TS untouched). This is the production-only counterpart to the staging-validated C2 package (`5bbcab2`), authored and Fable-corrected (RC-1…RC-6) under production-execution discipline. **File creation only — nothing has been executed.**

**Six production SQL files (all `docs/phase-5g-1c-2-prod-*`):**
- `preflight.sql` — read-only prod gate (object-names-unused, deps+columns, hard gates: 9 seeded IDs, IRA targets=7500, `adam_401k.auto=true`, 4 excluded present; P6-env replaced by `P6-sysid`+`P6-txcount`).
- `migration.sql` — table + RPC + RLS + grant normalization + empty-proof; body byte-identical to staging under the prod guard.
- `validation.sql` — pre-seed V1–V9; executable body byte-identical to staging (RPC-coverage comment corrected: authorized writer path deferred to first supervised 5G-1D closeout).
- `seed-anchor.sql` — first `opening_anchor`; **nine `-1` Value-Card sentinels**; Guard A requires `v_anchor_week = max(week_num)`.
- `seed-anchor-validation.sql` — authoritative SA-PROD block: **nine `-1` pins** (hard-stop if unset), exact card-value pinning, `count(*)=9`, SA-complete, table-wide exclusions.
- `rollback.sql` — production-specific break-glass; preserves destructive sequence only (BEGIN/COMMIT, DROP RPC → DROP TABLE, no CASCADE) + non-empty-table refusal via `v_confirm_export_done` + export instructions.

**Environment identity.** Production target: **Adam-Dashboard (usayoldrawwmjsmretin)**. Staging never-run target: **herndon-fos-staging (pkwotgqivgaapwuqgwqb)**. Loud PRODUCTION headers on all six name both.

**Probe evidence (read-only, run in Adam-Dashboard (usayoldrawwmjsmretin) 2026-07-09).** `system_identifier = 7632885393857617092` (hardcoded into all six `PRODUCTION GUARD` blocks as the strongest positive fingerprint); `transaction_count = 95`; committed **transaction floor literal `>= 40`**. Guards also require `app_environment` absent, `amex_gold` starting_balance `-8248.50`, canonical 13-ID `goal_registry` check, and IRA targets `= 7500`. `app_users` exact-identity assertion is deterministically OMITTED (schema unverified; documented in each header) — `system_identifier` equality already uniquely identifies production.

**Safety posture (updated 2026-07-09).** E1 production DDL has RUN and is GREEN (schema-only; table EMPTY — see "## 5G-1C-2 E1 COMPLETE"). **No first-anchor seed has run; no data rows written.** E2 remains a **separate explicit approval gate**; 5G-1D has not started.

**Seed-template state.** `seed-anchor.sql` and `seed-anchor-validation.sql` still contain **nine Value-Card sentinels** and HARD-STOP until the E2 Value-Card step fills all nine values. The **final seed-value SQL must be committed before seed execution** unless explicitly overridden (alternate: save the exact executed SQL + output to `exports/` and commit immediately after).

**Next gates:**
- **E1 — production DDL execution gate:** confirm **Adam-Dashboard (usayoldrawwmjsmretin)** → pg_dump schema-only baseline → `scripts/export-ai-review-pack.sh` → PITR/backup check → preflight → migration → validation → post-migration inert live check (behavior-inert but security-surface-live). **Explicit in-session approval required.**
- **E2 — first-anchor seed gate:** latest-reconciled-week basis → First-Anchor Value Card approval → fill all nine values in seed + seed-validation → value-only diff → commit final seed SQL → seed → seed-validation → REST/console + display verification. **Separate explicit in-session approval required.**

**Timing (RESOLVED 2026-07-11).** Week 5 reconciled **2026-07-11**; E2 executed the same day on the wk-5 basis (Guard A confirmed `max(week_num)=5`). The earlier "**Jul 12–17** window" was a planning estimate, not a technical guard, and is now moot (E2 COMPLETE). The wk-6 re-anchor / Alaska-freeze-deferral paths did not fire.

**Deferred follow-up.** The C3 overlay **auto/holding exclusion guard** remains a named follow-up (5G-1D rider or post-freeze wishlist) — the overlay does not itself guard auto goals; the prod seed-validation table-wide exclusion assertions are the DDL-gate defense. NOT part of the production DDL gate; no `index.html` edit.

Plan + Fable review: `docs/phase-5g-1c-plan-2026-07-08.md`, `docs/phase-5g-1c-plan-review-2026-07-08.md`.

## 5G-1B rider RESOLVED (2026-07-11): reconciled-week transfer history

**RESOLVED in commit `db2704f`** — adapter/UI only; no runModel/reconciliation/snapshot/schema/SQL change. Identity resolver (`resolveWeekTransfers`, position-independent, tiered duplicate-key handling) + resolver-aware write (`_resolveWriteTarget`: matched `task_idx` on uncheck, unused index on fresh check, never overwrites a different action). Executed completions render read-only ("Executed earlier"); Weekly X/Y current-only + separate "Executed earlier: N"; History count and text export reuse the resolver. **Final verification: static 1431/0, full e2e 135/0, smoke 19/0, browser console clean.** Full record: `docs/5g-1b-defect-reconciled-transfer-history-2026-07-11.md`.

Original defect (logged 2026-07-11). After Week-5 reconciliation, executed transfer rows (Alaska, Wewe RCCL, Wewe DCL, and both Adam IRA actions) disappeared from "Transfers to execute" — rows are re-derived from `runModel`; completion persists in `public.weekly_tasks` keyed positionally by `(week_num, task_idx)` (orphaned, overwrite-vulnerable). **No financial/reconciliation/completion-row loss; Week-5 reconciliation valid; NOT an E2 blocker** (E2 uses observed balances; nine eligible goals exclude RCCL/DCL). Classification: **5G-1B rider — stable executed-transfer identity and history preservation**, applying to all model-generated transfers; cross-refs 5G-1D / 5G-1E / reconcile→re-render test coverage. **Controlling sequence (2026-07-11): E2 COMPLETE + GREEN on the wk-5 basis → commit E2 closeout → commit this defect doc + stale timing-comment correction → minimum safe transfer-history fix → full verification → begin 5G-1D.** 5G-1D Gate 0 (E2 completion) SATISFIED 2026-07-11. No committed household amounts, timestamps, populated results, or evidence hashes. Full record: `docs/5g-1b-defect-reconciled-transfer-history-2026-07-11.md`.

## 5G-1C-2 E1 COMPLETE (2026-07-09): production DDL executed, schema-only + EMPTY

**E1 (production DDL execution gate) is COMPLETE and GREEN.** Executed by Adam in the Supabase SQL Editor against **PRODUCTION Adam-Dashboard (usayoldrawwmjsmretin)** in a single sitting, under the Fable-cleared runbook `docs/phase-5g-1c-2-e1-runbook.md` @ `e1b9252` (the Free-plan restore-point revision). Claude ran no SQL and did not touch Supabase — it saved every output verbatim and interpreted the gates.

**Result:** `public.goal_funding_snapshots` (table) + `public.save_goal_funding_snapshots` (RPC) now exist in production, **schema-only and EMPTY** (no seed). The app is **behavior-inert**: the only change is the C3 snapshot loader request going 404→200-empty; all rendered labels/tabs unchanged vs the pre-migration baseline.

**Steps (all PASS):**
- **Step 7 Preflight** — guard OK; P1–P5 all true; `P6-sysid = 7632885393857617092`; `P6-txcount = 95`; **latest reconciled week = 4**; `P6-excluded` exactly `adam_401k, wewe_rccl, wewe_dcl, taxable_etf`. Output: `exports/db-baseline-5G-1C-2-prod-preflight-20260709-193110.txt`.
- **Step 8 Migration** — guard OK; ran through `COMMIT`; `M-table = 1`, `M-rpc = 1`. Output: `exports/db-migration-5G-1C-2-prod-20260709-193922.txt`.
- **Step 9 Validation** — all V-checks true; `V7` empty (re-confirmed post-probe); `V4f` grant exactly `{INSERT,SELECT,UPDATE}`; `V8e`/`V9f` PASS (no exception; unauthenticated caller rejected, zero rows). Output: `exports/db-baseline-5G-1C-2-prod-validation-20260709-195258.txt`.
- **Step 10 Inert live check** — BUILD_TS unchanged (`2026-07-09T08:51:21`); `goal_funding_snapshots` 200-quiet; no console errors; all labels/tabs match baseline.

**Restore point (Free-plan mechanism, replaces Backup/PITR):** full public-schema `pg_dump` (schema + DATA) captured same-sitting, stored **OUTSIDE the repo** at `~/Herndon-FOS-DB-Backups/Adam-Dashboard/db-restorepoint-5G-1C-2-prod-20260709-185216.sql` — **never committed**. Repo holds **metadata only** (`exports/db-restorepoint-5G-1C-2-prod-metadata-20260709-185216.md`: size 205,435 bytes, sha256 `defa14e2…046c`) plus the committable schema-only diff baseline `exports/db-baseline-5G-1C-2-prod-pre-20260709-185216.sql`. Full E1 evidence scaffold: `exports/e1-prep-evidence-5G-1C-2-20260709-181719.md`.

**Not run / still gated:** no seed, no rollback. **E2 (first-anchor seed) remains a separate explicit in-session approval gate.** **E2 reconfirm:** latest reconciled week is **4**, so the First-Anchor Value Card must be built on the **wk-4 basis** (or wait for a wk-5 reconciliation) — the earlier wk-5/wk-6 timing assumption is superseded by the live P6 evidence. 5G-1D not started.

## 5G-1C-2 C2 STAGING-VALIDATED (2026-07-09): goal_funding_snapshots SQL package

**COMMITTED to local `main` at `5bbcab2` — NOT yet pushed.** C2 of 5G-1C-2 (Goal Funding State Integrity): the additive, staging-first SQL package for the week-anchored per-goal funded state. **Docs/SQL only — NO app/runtime/`index.html` changes and NO test changes; `BUILD_TS` unchanged (`2026-07-08T19:18:39`).** (The pre-commit `BUILD_TS` hook was bypassed with `--no-verify` so `index.html` stayed untouched.)

**Package (8 files, all `docs/phase-5g-1c-2-*`):** `preflight.sql`, `migration.sql` (table `public.goal_funding_snapshots` + RPC `save_goal_funding_snapshots` + RLS + grant normalization), `validation.sql`, `seed-anchor.sql` (staging-draft; values captured at seed time via UNSET sentinels, never hardcoded), `seed-anchor-validation.sql`, `rollback.sql`, `rls-smoke-gate1.sql`, `rls-smoke-gate2.md`.

**Design (as committed):** surrogate UUID PK; `UNIQUE(model_year, week_num, goal_id)`; `funded_amount >= 0`; `source IN (opening_anchor|reconciliation|correction)`; `week_num 1..31`; reuses `fn_set_updated_at()`. RPC is `SECURITY DEFINER SET search_path=public`, authorized via `can_write_financials()` (not delegated to RLS), validates in order (auth → model_year → week_num → null/non-array/EMPTY `p_rows` → **reconciled-week by `week_num` only** — inherited from 5F-1, safe under the single 31-week 2026 model → per-row) and idempotent-upserts on the natural key. Rejects: unauthorized caller, bad/null model_year, week outside 1..31, unreconciled week, invalid/missing goal_id, negative amount, invalid source, auto goals (`adam_401k`), holding/deferred goals (`wewe_rccl`/`wewe_dcl`/`taxable_etf`). RLS: `allow_read` (is_allowed_user), `financial_writer_insert`/`_update` (can_write_financials), **no DELETE policy**; grants normalized to exactly `{SELECT,INSERT,UPDATE}` for `authenticated`.

**Staging rehearsal — PASSED and torn down CLEAN** on staging `pkwotgqivgaapwuqgwqb` (confirmed ≠ prod `usayoldrawwmjsmretin`), 2026-07-09. Full sequence: preflight → staging-data prep (canonical `goal_registry` definitions, IRA targets corrected to 7500 per `1dcc686`, + one clearly-synthetic wk-5 reconciliation row) → migration → validation (V1–V9 incl. V8e constraint-behavior + V9f RPC-auth-reject) → seed-anchor (9 eligible goals) → seed-anchor-validation (SA1–SA7 true; SA8 one-sided AMEX advisory) → identity prep (throwaway writer/viewer `auth.users` + `app_users`) → **Gate 1 SQL-impersonation RLS+RPC smoke (`G1-clean = true`)** → rollback (table + RPC dropped; `fn_set_updated_at` and `app_environment` retained) → staging-data cleanup → identity cleanup → final verify (all C2 objects + test data gone, `env=staging`, shared helper retained). Two Gate 1 source fixes were folded into the committed file: `max(created_by_user_id::text)::uuid` (Postgres has no `max(uuid)`) and a `G1-clean` post-rollback check (9 committed seed rows survive; no probe-row leakage). The prep/cleanup/identity scripts and the run-order runbook were **scratch-only, outside the repo** (never committed).

**Gate 2 (real Auth→JWT→PostgREST smoke) — DEFERRED/SKIPPED** this pass: no real staging anon key / test-user passwords were used. The audit matrix + procedure are prepared in `docs/phase-5g-1c-2-rls-smoke-gate2.md` for a later run when credentials are available.

**No production DDL has run.** Production holds none of these objects. **C3** — the app-side overlay — is **SHIPPED + DEPLOYED** (`c6fbb32`; see "## 5G-1C-2 C3 SHIPPED + DEPLOYED"). Production DDL / first-anchor remains a separate, later gate (after 5G-QA-1).

## 5G-1C-2 C3 SHIPPED + DEPLOYED (2026-07-09): goal funding snapshot overlay

**SHIPPED and pushed at `c6fbb32`; DEPLOYED and live** on dashboard.herndons.us (`BUILD_TS 2026-07-09T08:51:21`, HTTP 200). Static regression **1392/0**, e2e **133/0**. The app/runtime overlay that consumes `goal_funding_snapshots` — the "C3" slice of 5G-1C-2. Runtime-freeze exception approved by Adam (narrow overlay, not a runModel rewrite).

**Five in-body `index.html` seams (approved, only these):**
- New `goalSnapData` global; **loader** in `loadAll` fetches `goal_funding_snapshots?model_year=eq.PLAN_YEAR`, parses to `goalSnapData[week_num][goal_id]=funded_amount`, **quiet** on relation-absent 404 / zero rows (non-blocking `console.warn` only on a real error).
- **runModel overlay** after the reconciliation balance overlay, before `gSnap` capture: **absolute anchor** — overwrites (never adds) `goalSaved[gid]` for model-tracked goals only; records `goalVariance[gid]=modeled_before−observed` (attached only when an anchor applied); skips complete/unknown ids (no new keys); auto goals untouched.
- **`getGoalFunded`** complete/manual branch → latest snapshot (week ≤ currentW) → `goalFundedAmounts` → 0; active goals unchanged (anchored via the overlay); `adam_401k`/auto path untouched.
- **`goalCompletion`** first-crossing → **stays-complete** (identical under monotonic/no-snapshot; corrects under a downward anchor).

**Identity gate held:** with `goalSnapData={}` the C1 golden (`fixtures/runmodel-golden-pre-1c-2.json`) stays byte-identical incl. key sets; PHASE-A Week-27 golden + GR-A1 green. **The overlay is INERT until snapshot rows exist** — so C3 is production-safe even though the production `goal_funding_snapshots` table does not exist yet (loader 404s quietly). New coverage (+13 static `C3-04..14`, +1 e2e): empty-state identity, anchor overwrite, mid-model re-anchor, no double-count (RET_SAV_XFR absorbed), `goalVariance` sign, complete-goal fallback chain, `adam_401k` unchanged, stays-complete both directions, Funding Plan↔timeline agreement.

**Deploy note:** a GitHub Actions incident ("Delays starting Actions runs", critical, 2026-07-09 04:34–13:52 UTC) blocked the `pages-build-deployment` deploy job twice (runner-not-acquired, then an OIDC 503) and left runs `29014230908`/`29019614559` wedged (uncancellable/un-rerunnable). After the incident resolved, the deploy was completed via the legacy Pages Builds API (`POST /repos/…/pages/builds`) — a fresh build of `c6fbb32`, `status: built`, no code change.

**No SQL/schema/RLS change, no production DDL, no first-anchor seed, no weekly closeout write-through.** Next per the approved roadmap: 5G-QA-1 (e2e smoke gate) → 5G-1C-2 production DDL / first-anchor (manual, approval-gated) → 5G-1D write-through.

## 5G-QA-1 SHIPPED (2026-07-09): E2E Runner Speed / tag-based Smoke Gate

**COMPLETE and pushed. Test-infrastructure only — `e2e.js` is the ONLY file changed across both slices; no `index.html`/`BUILD_TS`, no `push_to_github.sh`, no `test_regression.js`, no SQL/schema/RLS, no app/runtime change, no production data.** Purpose: speed e2e validation for future 5G phases without weakening the full suite. Delivered as two separable, independently-revertible commits.

**Slice A — tag-based opt-in smoke mode (`05a5558`, pushed):**
- `test(name, fn)` extended to `test(name, fn, opts = {})`; `opts.tags` is an explicit per-test array (no name-prefix filtering, no section-level implicit inclusion).
- Mode parse: **full is the permanent default** (`node e2e.js`, tags ignored, entire suite runs); smoke is **opt-in only** via `node e2e.js --smoke` or `E2E_MODE=smoke node e2e.js` (runs only `smoke`-tagged tests). Start banner + `Mode`/`Skipped` lines added.
- Smoke membership = **19 runtime tests** (Wendy-critical + 5G funding): app-load/console sanity (overview/weekly/goals/budget tabs + console-error check), reconciliation entry (weekly recon + BUD-3 Statement check), Budget/Register live path (RG-1/RG-2/RG-9, BUD-6 spend rollup, BUD-7 add-disabled, BUD-8 income actuals, one deterministic mocked WR-8 write-path), goals/funding (GR-1, GR-5, Funding Plan "no Beyond 2026" + When, C3 injected-snapshot-anchor↔timeline agreement), and one engine/waterfall-routing smoke (test 185). No net-new test was needed — existing test 796 already covers the full injected-`goalSnapData`→overlay→`getGoalFunded`→timeline chain in one pass.

**Slice B — deterministic wait optimization (`d8e21a0`, pushed):**
- `openApp`'s fixed 1000ms settle → `waitForFunction` on a terminal `AUTH_STATE` (`ready|unauthenticated|unauthorized|session_expired|auth_error`), **cap 1500ms**.
- `clickNav`'s fixed 300ms → `waitForFunction` on `activeSection===id && #nav-${id}.active && #s-${id}.active`, **cap 750ms**.
- Both use **existing app-state globals** — no `index.html` change, no `window.__hfosReady`, no `body.innerText` heuristic.
- `readinessFallbackHits = { openApp, clickNav }` added and printed in every mode; a run with ANY fallback hit is explicitly NOT clean green (readiness condition inadequate → review, don't accept).

**Verified results (headless):**
- FULL (`node e2e.js`): **133/0, Skipped 0**, `readinessFallbackHits` **0/0**; runtime **538.45s → 415.77s** (−22.8%). This remains the release/default gate.
- SMOKE (`--smoke` and `E2E_MODE=smoke`): **19/0, Skipped 114**, `readinessFallbackHits` **0/0**; runtime **~65–67s → ~44–50s**.

**Guardrails held:** `push_to_github.sh` unchanged and still runs full e2e; full mode remains the permanent default; smoke is developer-only and cannot become the gate without a separate approved change. Both commits were `git add e2e.js` + `--no-verify` (e2e-only, no BUILD_TS/index.html stamp). Reverting Slice B restores the prior timing while preserving Slice A's smoke tagging; reverting Slice A restores the original full-only runner. **No production DDL, no first-anchor seed.** Next: 5G-1C-2 production DDL / first-anchor gate as PLAN/REVIEW ONLY.

## 5G-0 CLOSED: label/docs cleanup (2026-07-07)

Scope was LOCKED to label/docs cleanup only, display strings, no logic, no schema/RLS/RPC. Shipped in the working tree; static regression **1332/0** (unchanged count — modified existing assertions, added no new tests). Changes (index.html + matching test updates in test_regression.js/e2e.js):

- "Available for Goals" rename: `misc.goal_sweep` label + Budget help copy + out-of-balance hint no longer say "Extra Pay Going to Spreadsheet".
- SYS-1: Budget "Reconciliation" panel retitled "Statement check"; phase strings stripped from tab labels ("Reconciliation — Phase 5F" → "Reconciliation"; "Phase 5D-2" footers removed). "Register — Phase 5E" disabled label intentionally retained (Register-not-enabled state).
- SYS-4 exact-string edits: "Budget Rule" → "Budget Line" (Edit/Add/Archive titles, buttons, body copy); "registry keys" → "categories"; Transfers "Model" badge → "Planned"; custom "Transfer" badge → "Custom"; Register "Clr" column/header/form label + Category Report "Clr" → "Cleared".
- WK-6 pluralization: Phase 2 recon banner reads "1 current-week protected obligation not yet recorded." (singular) when count === 1.

Not in 5G-0 (correctly deferred): no Budget row treatment (UX-0), no transfer routing / account-reconciliation / runModel change. The two Weekly Model issues Adam raised on 2026-07-07 were captured as findings and routed OUT of 5G-0 — see `docs/5g-0-finding-weekly-model-transfer-issues.md` and "## 5G-1A CANDIDATE" below.

e2e run and green: **131/0** (`node e2e.js`; assertions updated for the Reconciliation tab label, Register/Category-Report "Cleared" column, the reconcile caption wording, and the BUD-3 "Statement check" panel — RG/LEDGER/BUD/5D2 families; no new tests added, assertion-only edits). One-off LEDGER-1 balance-assertion flake cleared on an immediate re-run with no code change; no WC-3/BR-3 failures on this branch. (Observed suite size is 131; the previously-recorded 130 baseline appears off by one — no tests were added here.)

## 5G-1A SHIPPED (2026-07-07): Weekly Transfer Routing + Readiness

**SHIPPED and pushed 2026-07-07, commit `c8613bc` (origin/main). Static 1339/0, e2e 131/0.** Narrow surgical hotfix promoted from the 5G-0 finding (`docs/5g-0-finding-weekly-model-transfer-issues.md`). Wewe RCCL ($600) and Wewe DCL ($500) remain fully funded by the existing waterfall/checking deduction, but now route to AMEX Savings holding (`dst 'goal'→'amx'` via a new `HOLDING_TO_AMEX_GOALS` constant, deliberately OUTSIDE `_amxHold` so no 5-week lookahead re-adjudication); AMEX Savings projects +$1,100 in Week 27 with checking/Goal-Transfers total unchanged. Adds "AMEX Savings (holding)" labels (incl. a load-path `dest` force so the label holds in production, which is Supabase-sourced) and the paycheck-cleared readiness note (gated on the hoisted module-scope `PAYCHECK_WKS`). No schema/RLS/RPC/SQL; IRA/529, Alaska, LC boost, floors, and `_amxHold` behavior unchanged. Holding→payout lifecycle deferred to 5G-1B (see below).

**Real-world execution (Adam, 2026-07-07):** Adam executes the Week 27 Wewe RCCL $600 and Wewe DCL $500 transfers to AMEX Savings manually after the 7/7 paycheck clears. With 5G-1A shipped the model now routes these to AMEX Savings holding, so the modeled AMEX Savings balance already includes the +$1,100 — the earlier "known variance until the model is fixed" no longer applies for the deposit itself. (The remaining known offset is the later payout, deferred to 5G-1B — see below.)

**Historical framing (pre-implementation analysis, retained for rationale):** the paragraphs below were written before the code change to confirm the reclassification was safe; they remain accurate as the design record.

**Verified framing (2026-07-07, confirmed against runModel code — no code changed):** RCCL $600 and DCL $500 are ALREADY funded out of Truist Checking in the Week 27 waterfall (priority 2/3, immediately after Alaska; `src` Truist Checking). Mechanism confirmed: `mv(amt,'goal',…)` unconditionally debits checking (`chk-=m`, `index.html:2258`) but credits no model account for `dst='goal'` (`index.html:2262` — "deducted from checking; external destination — no model account tracked"). The displayed "Goal Transfers" figure is a derived residual (`goalTransfers = totalChkDelta − billsOut`, `index.html:4021-4026`), so those debits are already inside the Week 27 **$11,662.56** total and the Week 27 ending checking (**$8,298.08**) already reflects the $1,100 leaving. **So 5G-1A is a destination reclassification, NOT a new outflow:** keep the identical checking deduction and the same $8,298.08 ending checking; change only `dst` from `'goal'` to `'amx'` (at the `index.html:2434` ternary) so AMEX Savings rises $1,100. Because `mv()` computes the moved amount independent of `dst`, the checking delta — and thus the Goal Transfers total — stays identical; only `amx` gains $1,100. Do NOT route RCCL/DCL through the `_amxHold` branch: that would newly subject already-funded transfers to the 5-week `maxSafeAmxSweep` lookahead/throttle and break-on-defer semantics (`index.html:2437`), re-adjudicating them as new IRA/529 AMEX funding. Land them in `amx` via a separate routing that skips that gate. No new throttling unless a transfer was not actually funded.

**Readiness note:** Paycheck-funded transfers should be executed after the paycheck clears. Adam's operational intent (2026-07-07): wait for the 7/7 paycheck to clear in checking before executing any Week 27 transfers.

**Holding→payout lifecycle — DEFERRED to 5G-1B (decided 2026-07-07):** routing RCCL/DCL to `amx` parks $1,100 in AMEX Savings with no modeled payout when the real cruise payments land (RCCL ~end July / Cal Wk 30, DCL ~October / Cal Wk 41). 5G-1A deliberately does NOT model the release — so once those payments actually leave, modeled AMEX Savings will overstate by the held amount until a release event is added. This is a known, accepted standing offset for 5G-1A; modeling the holding→payout lifecycle is deferred to 5G-1B. A code comment at the `HOLDING_TO_AMEX_GOALS` definition records the same deferral.

**Desired scope:**
1. Route Week 27 `wewe_rccl` ($600) and `wewe_dcl` ($500) to AMEX Savings as holding transfers, not the `'goal'` sentinel. Today the routing ternary at `index.html:2434` sends every non-Alaska, non-`_amxHold` goal to `dst='goal'` (leaves checking, no destination account tracked — `index.html:2262`); RCCL/DCL currently fall here.
2. AMEX Savings projected balance (`amx` / modeled `mAmx`) increases by $1,100 in and after the funding weeks.
3. UI labels them as holding transfers, not final vendor payments (today `dest` = "RCCL payment" / "DCL payment" — display string only, `index.html:1526-1527`, used at `index.html:2460`, `4358`, `4728`).
4. Add/adjust regression coverage proving the Week 27 AMEX Savings projection includes the $1,100.
5. Do NOT disturb IRA/529 AMEX-holding behavior, Alaska savings behavior, LC boost, floors, or unrelated runModel logic. Caveat to design around: `_amxHold` (`index.html:2425`) also drives the 5-week AMEX-sweep lookahead gate (`index.html:2437-2445`) and the `needsFlag` bypass (`index.html:2426`) — simply adding RCCL/DCL to `_amxHold` changes their gating semantics, not just their destination account. Prefer a routing that lands them in `amx` without inheriting the full `_amxHold` gating, unless the lookahead gate is explicitly wanted.
6. Transfer readiness / paycheck-cleared labeling ("After Adam paycheck clears — target Jul 7"): fold into 5G-1A ONLY if low-risk; otherwise defer to 5G-1B. Note there is no per-transfer readiness field today — actions carry label/key/result/reason only, and the shown date is the week-start `getWeekDate(w.num)` (`index.html:4112`, `7759`); paydays are modeled at week granularity only (`PAYCHECK_WKS`, `index.html:2194`). Delivering it well is net-new structured data, which argues for 5G-1B.

## UX-0 SHIPPED (2026-07-07): display-only Budget row treatment (BUD-1 / BUD-2 / SYS-3)

Display-only presentation slice; treatment authority is the Wendy 5G Budget mockup spec v1.2 (`docs/specs/wendy-5g-budget-mockup-spec-2026-07-07.md`). No schema/RLS/RPC/SQL, no `runModel`, no reconciliation/account-routing, no transaction workflow changes. Files: `index.html` + `test_regression.js` only (`e2e.js` untouched). Static regression **1344/0**, e2e **131/0**. Desktop visual review passed (Adam, 2026-07-07); approved for showing Wendy.

- **BUD-1 (color semantics):** new `_budgetRowState(spent,budget)` → `over | near | neutral`. Near-limit rule (decision 1): lines with Budget ≥ $100 go amber when Spent ≥ 90% AND Remaining ≤ $100; lines under $100 never go amber (neutral until over, then red) — the $34 Google line stays neutral at $33.60. Expense **leaf** rows: over = red value **plus an "Over by $X" badge**, near = amber value, under-with-spend = default ink, idle/nothing-spent = muted. **No row tint.** **Parent section headers and Total Planned Budget** apply the same red/amber/neutral value treatment to their own totals but show **no "Over by" badge**. **Income** rows (per-row + Total Income) render muted with an "expected" suffix (amount preserved), never red/amber/green (decision 2). The legacy income amber/green Remaining ternary is removed.
- **BUD-2 (empty state):** the Budget bottom Transactions panel replaces "No transactions for this period" with "No Budget-entered transactions for [Month]. Actual spending is entered in Register and is already counted in Spent above." plus a live **Open Register** link (`setSection('transactions')`, FLOW-1 pattern).
- **SYS-3 (row-action controls — red retired):** Budget row **Archive** button → neutral (matches Edit); Archive **confirm** modal button → amber-dark; Register manual-row **delete trigger ✕** → amber; Register **delete confirm strip + Confirm button** → amber-dark; Budget legacy-tx **Del / Delete? / Yes** confirm → amber-dark. Existing **green "Budget balanced" check is unchanged.** Red remains only on over-budget value/badge (status), money-display amounts, and error text — not on any Archive/Delete/Confirm control.
- **Help copy:** the Budget "Remaining" help line was updated to describe the new neutral / amber / red("Over by" badge) / income-"expected" language.
- **Tests:** widened three fixed-offset slice windows (`5B-24`, `5F15-A1-07`, `5F15-A2-09`) that the added lines pushed past; rewrote `5F15-A2-09`'s income-coloring assertion to expect the muted "expected" treatment; added `UX0-01…05` (the `_budgetRowState` truth table incl. the Google $34 and $2000-line cases, leaf-only "Over by" badge, SYS-3 control colors, and the BUD-2 empty-state copy/link).

Not in UX-0 (deferred to UX-0.5, planning only): legend, attention summary strip, section-header hierarchy polish, Remaining-column/badge spacing rhythm, Register reconciliation helper-bar rewrite, edit/delete affordance, uncleared-row visual treatment. UX-0.5 is display-only and must not change UX-0 behavior, data, math, schema, reconciliation, routing, or workflows.

## UX-0.5 SHIPPED (2026-07-07): Wendy visual polish (Budget B1–B4, Register R1–R2)

**SHIPPED, commit `739567b` (local `main`, not yet pushed at time of writing). Static 1350/0, e2e 131/0. Desktop visual review passed (Adam, 2026-07-07).** Display-only presentation pass; no UX-0 semantics changed (thresholds, red/amber/neutral, "Over by" text, income "expected" all intact). Files: `index.html`, `test_regression.js`, `e2e.js` only. No schema/RLS/RPC/SQL, no `runModel`, no reconciliation/account-routing, no transaction workflow changes. `e2e.js` was touched only for the R1 caption wording. BUILD_TS was stamped to `2026-07-07T18:22:06` by the pre-commit hook (normal code-commit behavior).

- **B1 — color/status legend:** compact key under the Budget title (Within budget / Near limit / Over budget "Over by $X" / Income "expected"), reusing UX-0 color tokens.
- **B2 — attention summary strip:** slim strip under the legend, above the grid — Over budget (N lines), Near limit (N lines), Planned remaining, Income expected. Over/near counts are tallied **inside the expense-leaf render loop** from the same `_budgetRowState` the grid renders (single source of truth — no parallel computation, cannot drift). Injected into a slot via `split/join` (literal `$` safe). Income expected is clamped `Math.max(0,_iTotRem)` so it never shows a positive figure once income is fully/over-received; Planned remaining = `totalRem` (red only if the total is actually over).
- **B3 — section-header hierarchy:** parent group headers get a 2px top rule and uppercase small-caps labels for easier scanning.
- **B4 — "Over by $X" badge rhythm:** badge spacing/alignment improved (margin-left 8px + vertical-align); text, colors, and threshold logic unchanged.
- **R1 — Register helper bar:** the long italic reconcile paragraph replaced with a cleaner non-italic helper bar (same `tx-bal-caption` class), copy: "Uncleared transactions appear first. Balance reflects the full account ledger, not just visible rows. The newest cleared row should match your bank balance." (trimmed reconcile-against-bank hint retained per Adam decision A).
- **R2 — Register edit/delete affordance:** ✎/✕ get larger click targets, clearer tooltips, and aria-labels; UX-0 SYS-3 colors preserved (✎ neutral/muted, ✕ amber).
- **Token hygiene:** new UX-0.5 borders (B2 strip, B3 rule, R1 bar) use the defined `--line` token, not the undefined `--border`. No global `--border` cleanup performed (pre-existing usages left untouched; that would be a separate pass).
- **R3 (uncleared-row visual treatment) — DEFERRED**, not implemented. It touches reconciliation-sensitive Register semantics (CL/reconcile default sort + full-ledger balance invariant).
- **Tests:** updated the R1 reconcile-caption assertions (static `A10-9`; e2e caption references); added `UX0.5-B1..R2` covering the legend, the strip wiring (slot placement, in-loop tally, clamp, `--line` borders), header hierarchy, badge rhythm, helper-bar copy, and action affordance. Note the balance-invariant e2e tests LEDGER-1/A9-1 are intermittently flaky and clear on re-run with no code change.

## 5E-8 CLOSED: Register Category Sync (2026-07-02)

Live-use bug: Register's Add Transaction category dropdown/row display didn't match Budget's categories (Wendy-facing, reported live). Root-caused and resolved across three rounds:

1. **Code fix** (commit 238b245, confirmed live at the 10:00 AM build) — Register sources categories from live `_categoriesCache` (normalized via `_normalizeCatRow`) with month-aware label resolution via new `_getRegisterCategoryLabel()`, deliberately NOT `_getActiveCategoryRegistry()`/`BUDGET_CATEGORY_REGISTRY` (that registry is scoped to Budget's fixed 31 lines and gated behind `FEATURE_FLAGS.useSupabaseRegistries`, false in production). Also: `transaction_date` field now triggers a re-render (dropdown labels are month-derived; date input switched `oninput`→`onchange`).
2. **Root cause of the remaining live gap** — a DATA gap, not code. `entertainment.event_1/event_2/week_1-4` were seeded into `budget_line_rules` for July (`docs/phase-5e-6-migration.sql`) but never inserted into `categories` (`docs/phase-5d-1-migration.sql` only seeded 4 static Entertainment leaves — birthday_dinner/brunch/big_dinner_out/entertainment_other). Register can only offer categories that exist in `categories`.
3. **Data-only correction — EXECUTED AND VALIDATED (2026-07-02)**: `docs/2026-07-02-register-budget-category-sync.sql` (preflight → preview → guarded INSERT, entertainment-pattern-scoped, `ON CONFLICT DO NOTHING` only, no UPDATE/DELETE/schema/RLS). Adam ran preflight + insert + validation in production. Confirmed results: `still_missing=0`; all 6 new rows `leaf=true`/`active`/`assignable=true`; parent/group rows remain non-assignable; no duplicate/near-duplicate keys; `entertainment.*` now shows 10 active child rows. Live Register dropdown for a July 2 AMEX Gold transaction confirmed showing Seattle / Wewe's Lunches / Entertainment Week 1-4, alongside the original 4 real Entertainment categories and other existing live categories (Net Salary, Deep South Commissions, Auto Payment, Gas & Fuel), with "Entertainment" itself correctly not selectable.

Reusable future guard drafted (not applied to anything today): `docs/validation-blr-category-sync.sql` — copy-paste template for future budget/category migrations to run as their last step, encoding the rule "any active `budget_line_rules.category_key` for an operating month must exist in `categories` first." Also logged in `AGENTS.md` Known Gaps + Wishlist ID 39 (FK from `budget_line_rules.category_key`→`categories.key` considered but NOT added — needs a historical/legacy BLR row audit first).

Test status: static regression 1039/1039 passing. `5E8-R1`–`R20`, `R22` all reflect the confirmed post-fix production state (temporary diagnostic tests `5E8-R18`/`R19` and e2e `RG-7c`, which previously asserted the pre-fix data-gap-limited state on purpose, are now flipped to assert Seattle/Wewe's Lunches/Week 1-4 resolve, existing categories are preserved, and parent/group rows stay non-assignable). New end-to-end test `5E8-R22` calls `_renderTxRegister()` directly and reproduces Adam's exact confirmed live result. e2e.js Reconciliation selector was also widened this round (unrelated pre-existing gap, not a Register regression) — pending Adam's e2e re-run for final confirmation.

5E-8 is fully closed pending Adam's e2e.js re-run. 5F-1 remains gated behind 5E-7 and 5E-8 per the existing rule below — with 5E-8 now closed (contingent on e2e confirmation), that gate condition is satisfied, but 5F-1 should not resume without Adam's explicit go-ahead in a future session.

## 5E-9 CLOSED: Budget/Register Spend Integration (2026-07-02)

Live-use bug: July AMEX Gold transactions were entered and categorized correctly in Register, but Budget's "Spent" column showed $0.00 across every category. Root cause: `public.transactions` (Register, Phase 5E-1+) and `public.budget_transactions` (Budget's own CRUD, Phase 5B) are two fully disconnected tables. `renderBudget()`'s `spentByKey` aggregation only ever read `_budgetTransactions` (sourced from `budget_transactions`) — no code path anywhere read Register's data into Budget. This was a missing aggregation path left over from when Register was built as a new module, not a regression from 5E-8.

Audit findings (full 9-point audit run before any code changed, per Adam's instruction):
- No double-count risk today — confirmed via live preflight, `budget_transactions` has 0 July 2026 rows. Ongoing risk flagged: Budget's own "+ Add Transaction" form is still live: Register should be treated as the actual-spend source of truth going forward; that form should be considered legacy/manual-entry-only to avoid future double-entry (documented, not yet enforced in code).
- Month/date logic: reused `_budgetLoadTransactions`'s exact local-date month-boundary math (avoids known UTC-shift bug) rather than reinventing it.
- Uncleared transactions count toward spent — matches `budget_transactions`' own existing behavior (no `cleared` check there either).
- Account-agnostic — no account_key filtering, matching `budget_transactions` (which has no account concept at all).
- Category filter (`_isCountableBudgetSpend`, new helper near `_normalizeCatRow`): active leaf categories only; excludes `behavior_class` IN (income, commission_income, reimbursable_income, transfer, savings_allocation) and `budget_treatment` IN (excluded, display_only, planned_allocation) or null. Verified against real confirmed live category data: `business.jabian_expenses_2026` (reimbursable_expense/excluded — does NOT count), `business.jabian_deposits_2026` (reimbursable_income/display_only — does not count), `taxes.actual_tax_payment` (expense/excluded — does not count), `taxes.vio_transfer_2026` "Taxes 2026" (transfer/excluded — does not count), `transfers.greenlight` (transfer/excluded — does not count), `business.jabian_2026_dup` (lifecycle_status=merged — does not count).

Fix (index.html only, no schema/RLS/reconciliation changes):
- New `_budgetRegisterSpendCache`/`_budgetRegisterSpendLoadStatus` state + `_budgetLoadRegisterSpend(monthIso)` loader, querying `/rest/v1/transactions` for the selected month.
- `renderBudget()`'s loading gate now awaits both `_budgetTransLoadStatus` and `_budgetRegisterSpendLoadStatus` before computing `spentByKey`.
- `spentByKey` gets a second accumulation pass over `_budgetRegisterSpendCache`: outflow only (`amount<0`), category gated through `_isCountableBudgetSpend`, summed as `Math.abs(amount)` (converts Register's signed convention to `budget_transactions`' positive-magnitude convention).
- Refresh: `_budgetChangeMonth` resets the new cache/status on month switch; `setSection('budget')` resets `_budgetRegisterSpendLoadStatus` on every Budget tab entry, so a Register edit made from a different tab isn't shown stale (`budget_transactions` itself already refreshes correctly — its own CRUD reloads it directly).

Test status: static regression 1059/1059 passing (20 new tests, `5E9-01`–`5E9-20`: pure-function coverage of `_isCountableBudgetSpend` against real confirmed live category data, plus source-pattern coverage of the loader/merge/refresh wiring; two pre-existing tests, `5B-15` and `5E8-R20`, had their fixed-offset slice windows widened after the new code pushed target strings further into `renderBudget()`/`_setTxFormField`, no assertions changed). New e2e test `BUD-6` (Playwright) exercises the real merge end-to-end: injects Adam's actual July 2 example (Fandango $40.00 + Barn $32.68 + mend coffee $12.98 = $85.66 tagged `entertainment.week_1`), a same-category inflow that must not count, and a Jabian Expenses / Greenlight outflow that must not count — asserts the rendered Budget grid shows exactly $85.66 for Entertainment Week 1 and never surfaces the excluded $7.17.

Post-deploy triage: first e2e run showed 2 failures (`BUD-4`, `BUD-5`) — both pre-existing tests that inject `_budgetTransLoadStatus='loaded'` directly but never touched the new `_budgetRegisterSpendLoadStatus`, which the new dual-precondition loading gate also requires. Confirmed stale-test-only (no app regression, gate behaving as designed) via full grep of every `_budgetTransLoadStatus='loaded'` occurrence in e2e.js. Fixed by adding the matching `_budgetRegisterSpendLoadStatus`/`_budgetRegisterSpendCache` setup+teardown to both tests, mirroring their existing pattern. No index.html changes for this round; static regression re-confirmed 1059/1059 unaffected.

**Confirmed closed 2026-07-02**: static regression 1059/1059, e2e 116/116, commit `f0dbe1d`, Pages deploy green and live (footer confirms Jul 2 5:08 PM build). Live production check confirmed: Entertainment $85.66 spent (Week 1 $85.66 spent / $164.34 remaining), Groceries $8.00, Diablos (Preston) Fee $750.00 spent / $0.00 remaining, Google $33.60 spent / $0.40 remaining, Total Planned Budget $877.26 spent, Jabian Expenses 2026 correctly excluded from spend. Register dropdown fix (5E-8) still live. Reconciliation still shows $0.00 — expected, intentionally out of scope, deferred to 5F-1/5F-2.

Not done in this pass, still open: Budget's own manual "Add Transaction" form was not hidden or disabled — the double-entry risk this creates is documented in AGENTS.md Known Gaps, not resolved. Reconciliation panel was explicitly left untouched (still `budget_transactions`-only, per existing 5F-1/5F-2 migration plan).

Do not reopen 5E-8 or 5E-9 unless Wendy finds another live-use issue.

## 5E-10 IN PROGRESS: Budget/Register Source-of-Truth + Entry Safety (2026-07-02)

Scoped from Wendy's initial live-use feedback (5 items). Included in 5E-10: payee required (#3), uncleared-above-cleared row sort (#4). Deferred to 5E-11: category typeahead/ABC ordering (#1), payee memory/autofill (#2), account dropdown ABC ordering (#5 — originally considered in-scope, deferred after the audit found it changes Register's default account on first load via `activeAccounts[0].key`, a real behavior change not just display polish).

Changes (index.html + tests only, no schema/RLS/reconciliation logic):
- **Budget manual entry disabled, not hidden.** `renderBudget()`'s "+ Add Transaction" button now renders `disabled` with a tooltip and adjacent helper text: "Actual spending is now entered in Transactions → Register." Register is now the actual-spend source of truth — prevents the double-entry risk flagged in AGENTS.md Known Gaps (5E-9 entry) between `budget_transactions` and `transactions`. "Manage Lines" (Budget Line Admin, `_blrOpenAdd`) is untouched — separate control, still fully active.
- **Budget help panel rewritten** for the two sections that instructed Wendy to use the now-disabled button ("Adding a transaction" → "Entering a transaction"; "Logging a Jabian reimbursable" → "Logging a Jabian expense"). New copy points to Register and the `business.jabian_expenses_2026` category, and **honestly discloses a real capability gap**: Register has no `transaction_type`/`reimbursement_status` field, so the old pending → submitted → reimbursed tracking workflow has no equivalent yet — flagged in the help text as "flag any Jabian expense to Adam separately until that is added," and logged below as an open item. Reconciliation and "Reading the budget printout" help sections are untouched.
- **Register payee is now required** (`_saveTxForm`) — validated before the Supabase call, same pattern as the existing date/amount/account checks. Input placeholder changed from "Optional" to "Required", label shows `Payee *`.
- **Register rows: uncleared display above cleared**, running balance preserved correctly. Two-pass approach in `_renderTxRegister()`: pass 1 (`rowsWithBalance`) walks the original chronological fetch order and attaches each transaction's correct running balance; pass 2 (`displayRows`) builds a stable-sorted display copy (uncleared first, cleared second — `Array.prototype.sort` stability preserves chronological order within each group) and renders using the precomputed balance, never recomputing after the sort. Matches the existing non-mutating `.slice().sort()` convention already used by `_renderTxAccounts`.

Known gap surfaced by this change (not resolved here, logged for 5E-11 or later): Jabian reimbursement status tracking (pending/submitted/reimbursed) has no home now that Budget's own entry form is disabled — `transactions` table has no equivalent field. Needs a decision: add the field to Register, or keep it as a manual side-channel to Adam for now.

Test status: static regression 1070/1070 passing (11 new tests, `5E10-01`–`5E10-11`, source-pattern coverage of the disabled button, help panel copy, payee validation, and the balance-then-sort sequence — one test, `5E10-03`, needed its own false-positive fix mid-pass: a broad nearby-text regex matched the word "disabled" inside an unrelated comment, tightened to check the Manage Lines `<button>` tag itself). New e2e tests: `WR-6b`/`WR-6c` (blank payee rejected / non-blank payee not blocked), `RG-12` (uncleared-first display order with exact balance values verified: Fandango $-150.00, Kroger $-100.00, Paycheck $1850.00 — proving the balance is chronologically correct despite the reordered display), `BUD-7` (disabled button + tooltip, Manage Lines unaffected, help panel no longer references the old button, reconciliation help copy unchanged). Confirmed all 5E-9 tests remain green in the same run.

Pending Adam's e2e.js run before commit.

## 5F-1 Handoff (next session)

This section previously said "5F-1 v3.12 is build-ready but NOT started" — that is stale. 5F-1 is in progress, not started, as of this update.

Landed so far (3 commits): `f3402c1` DB + cash availability engine foundation, `be584c1` WD event tagging foundation, `6d5c8b5` reconciliation Phase 0/1 UI (staged-answer state machine, not yet persisted).

Production DB validation (`docs/phase-5f-1-preflight.sql`, `docs/phase-5f-1-validation.sql`) confirmed clean: `cash_commitments` (28/28 columns, 7/7 CHECK constraints, RLS SELECT-only for `authenticated`), `weekly_reconciliations.balance_basis`, `save_reconciliation_with_commitments` (11-param, SECURITY DEFINER, search_path pinned, correct grants), `repair_commitments_for_week` and `validate_commitment_state` all match the migration spec in production. V1-V17 PASS, V18-V19 informational REVIEW as designed. No `budget_transactions` coupling anywhere in the 5F-1 SQL or JS.

**5F-1 RPC persistence bridge slice (this update):** `saveRecon()` now calls `save_reconciliation_with_commitments` instead of writing `weekly_reconciliations` directly, sending staged Phase 1 answers (`buildPhase1PatchArray()`) as `p_patched`. `canPersistReconNow()`/`canSaveRecon()` no longer require zero Phase 1 rows — a fully-answered week is now saveable. `p_new_commitments` is always `[]` this slice (new-commitment insertion is WD-tagging/Phase 2 territory, not this slice). On RPC failure, staged Phase 0/1 answers and the open recon form survive for retry; on success, `reconData`/`commitmentData` reload from Supabase rather than being faked locally. Files touched: `index.html`, `test_regression.js`, this file. `e2e.js` was deliberately NOT touched — seeding `commitmentData` with a real prior-unresolved commitment through the existing harness was judged not worth the added risk for this slice; covered instead by static source-pattern tests plus a manual live Supabase smoke test after deploy.

AC accounting: 22 of 33 JS-engine-layer ACs now fully unblocked (13 engine-layer, no persistence involved, Section 5F1-K; plus the 9 that were PARTIAL — AC-77,78,79,80,88,89,90,91,92 — now confirmed both logically correct, Section 5F1-M, and wired to a real persistence path, Section 5F1-RPC-BRIDGE). 0 ACs remain PARTIAL. 11 ACs remain BLOCKED (AC-15,18,21,28,96,97,101,105,106,107,108) pending Phase 2/3/4 of the reconciliation form, dashboard verdict-text rendering, and historical repair mode — none of that exists yet. AC-76 is a process-check, not a runtime assertion.

Still not started: Phase 2 (current-week WD obligation prompts), Phase 3 (generic catch-all), Phase 4 UI polish, dashboard Review Required verdict rendering, `repair_commitments_for_week` wiring (historical repair mode), new-commitment insertion via `p_new_commitments`.

- Use the re-grepped regression baseline per AC-76, not any stale count.
- Prose spec stays frozen unless implementation surfaces an actual failing AC or a cash-safety defect.
- UI carryover: Phase 2 current-week protected WD prompts have no hard completion gate (ignored prompts rely on backfill detection). Do not redesign. Make protected prompts hard to miss and make backfill / Review Required warnings prominent.

## 5F-1 Phase 2 SHIPPED (2026-07-03)

Current-week WD obligation prompts + `p_new_commitments` are live. `saveRecon` sends `buildPhase2NewCommitments(...)`; prompt UI in `renderReconPhase01` (seven-branch response select, amount/notes/reflection inputs, Clear control); count-gated in-form banner ("N current-week protected obligations not yet recorded", renders only when N>0); the save gate composes answered-row completeness (Phase 0 basis + all Phase 1 rows + every *answered* Phase 2 row internally complete; unanswered prompts never block); conflict routing (a case-insensitive `commitment already exists` error reloads commitments and routes the user to Phase 1). Deployed at build-stamp `2363501`; live-smoke passed: one real `cash_commitments` row created for `2026mw4_tax_transfer_vio_2026_06_28` (status planned, source_account truist_checking, commitment_source wd_reconciliation, amount_cents 43563), deduped on reopen, banner dropped 4 to 3, and the tax transfer surfaces under Transfers to Execute as a planned transfer. Static regression 1163/1163. e2e 119/120: the sole failure `WC-3` is a pre-existing waterfall non-monotonicity issue, not Phase 2 (see AGENTS.md Known Gaps). `reconEffectiveWD()` was extracted from `runModel` as the single source of override-aware weeks (behavior-preserving, all model tests green). Next: Phase 3 (generic catch-all), not started.

## 5F-1 Phase 3 SHIPPED (2026-07-04)

Generic Catch-All (manual, non-WD reconciliation items) is live. `saveRecon` concatenates `buildPhase3NewCommitments(_reconPhase3Items, _reconBasis, n)` onto the Phase 2 rows into `newCommitmentsAll` and sends it as `p_new_commitments`; `p_patched` and the Phase 0/1/2 paths are unchanged. UI: a "Phase 3: Other reconciliation items" section in `renderReconPhase01` with an Add item control, per-item label/amount inputs, a 5-branch response select (`not_paid_yet`, `paid_initiated`, `bank_pending`, `cleared_reflected`, `paid_other_account`; no `amount_changed` or `wd_mismatch`), a conditional reflection select (`available_balance` + `paid_initiated`/`bank_pending`), and a Remove control, all wired to `_reconPhase3Items` setters (`addPhase3Item`/`setPhase3ItemField`/`removePhase3Item`; item `id` = `manual_<uuid>` generated at add-time, doubling as `expected_item_id`). Gate: `canCompleteReconPhase3` composes into `canPersistReconNow` after Phase 2 (blank section never blocks; a started-but-incomplete item blocks before the RPC; blocked-reason order basis, Phase 1, answered Phase 2, started Phase 3). Rows are `commitment_source=manual_reconciliation`, `commitment_class=other_transfer`, `required_or_discretionary=protected_required`, `affects_deployable_cash=true`, `source_account` defaulted to `truist_checking`, `original_amount_cents`/`due_date`/`resolution_notes` null. No schema/RLS/SQL change (the RPC already accepts `manual_reconciliation`). Deployed build-stamp `f282ab8` (Pages #134). Live-smoke passed: one `manual_reconciliation` row created for a $1.00 "P3 smoke test" planned item, verified field-by-field, then rolled back clean (throwaway; production left clean, `weekly_reconciliations` intact). Static regression 1213/1213. e2e run pre-push showed only the known `WC-3` (and `BR-3`) failures, so `--skip-e2e` was used per the documented condition. Next: Phase 4.

## 5F-1 Phase 4 SHIPPED + real closeout PROVEN (2026-07-04)

Phase 4 (Balance Entry) is complete. The 5-field balance form, pre-fill, save flow, and RPC balance fields already existed; the one spec gap was the unknown-basis warning. P4-1 added: a non-blocking amber warning under the Phase 0 basis radios gated on `_reconBasis==='unknown'` (styled with repo `--amberSoft`/`--amber`, independent of the unbuilt dashboard Review Required verdict, unknown stays a valid saveable basis); and a basis-aware `reconBalanceGuidance(basis)` helper replacing the static posted-only note (distinct posted/available/unknown copy, de-duplicated from the amber wording, safe default when unselected). No runModel/reviewRequired change, no dashboard verdict rendering, no new save gating, no balance-validation change, no schema/RLS/SQL. Deployed at commit `dbcae6a` (functional commit `b1be6c8`), footer build Jul 4 2:34 PM; live visual check confirmed the amber warning shows only under "Not sure" and the guidance copy switches by basis. Static regression 1219/1219.

Real Week 26 closeout completed and read-only verified in production (stored week_num 4 / displayed Week 26):
- `weekly_reconciliations` row saved correctly, `balance_basis=posted_current_balance`, balances chk 14935.14 / sav 3772.81 / amx 103.64 / tax 1516.59 / lc 13774.76.
- Three Tiffany Dye rent obligations resolved cleanly: all `status=cleared`, `reflected_model_week=4`, `resolved_model_week=4`, `resolution_type=cleared`.
- No Phase 3 duplicate for the $435.63 Vio tax transfer. The only 43563-cent row is the legitimate `wd_reconciliation` row `2026mw4_tax_transfer_vio_2026_06_28` (status planned). The scheduled 07/06 transfer was captured in Week Notes (Vio confirmation 202618513554465, flagged not-yet-reflected), not as a new commitment, which is correct.
- Jul 4 commitment activity is exactly 3 cleared rent rows + 1 planned Vio transfer row. Duplicate `expected_item_id` = 0, smoke/test leftovers = 0. Distribution: wd_reconciliation/cleared = 3, wd_reconciliation/planned = 1.

Conclusion: 5F-1 forward reconciliation is proven in real use and production data is clean. Two 5F-1 sub-items remain deliberately deferred and are not required for forward weekly closeout: dashboard Review Required verdict-text rendering (AC-15/18; the reviewRequired flag itself is computed and tested) and historical repair mode (AC-21; `repair_commitments_for_week` wiring, backfill of past un-tagged weeks only). Blocked-AC tracker trimmed accordingly to AC-15/18/21 (Section 5F1-NOTSTARTED).

## 5F-1.5 Gate A UI SHIPPED + Register Quicken ledger hotfix LIVE (2026-07-05/06)

Wendy July usability pass, display/read-only scope except the pre-existing Clr checkbox behavior, which was preserved unchanged. No new Register write path, schema/RLS/RPC, or Budget-calculation changes. Live on the custom domain (footer Jul 6 2026 1:11 AM after a forced Pages redeploy). Static 1322/0, e2e 130/0.

Seven UI gates (pushed as the stack A5, A8, A6, A9a, A9b, A7a, A7b; deploy #141):
- e99e24b A5: account dropdowns alphabetized (payment pickers + Register selector), Cash/Other pinned last, default account preserved.
- fb7a0d2 A8: weekly milestone/guidance banner moved from the bottom of the week into the header card.
- 7419b31 A6: Register columns user-sortable; Balance non-sortable; chronological running-balance invariant (two-pass: compute -> filter -> sort, bal never recomputed).
- 17e9d19 A9a: Register search (payee/memo/resolved category) + Type/Status filters + Clear + filtered empty state + full-ledger caption.
- e22af6e A9b: Register inclusive Date From/To filters (lexical YYYY-MM-DD) + selected-account context label.
- 833a0e9 A7a: read-only Category Report modal + picker reaching excluded/income categories (incl. Jabian Expenses/Deposits); legacy budget_transactions count-only notice; 1000-row truncation warning; stale-fetch guard; no Balance column.
- 2040245 A7b: Budget expense leaf rows (label + Spent cell) drill through to the A7a report; goal_sweep/parent/income excluded; row label escaped.

Register ledger hotfix (two follow-on commits, both live):
- 6736d42: default Register sort is Date descending (Quicken newest-first); each row's Balance is the historical/as-of-transaction-date running balance from accounts.starting_balance; starting-balance row moves to the bottom in newest-first view; extracted the _computeLedgerBalances row-builder for testability; caption hides for any date sort.
- f12596f (redeploy forced by empty commit 77ecc0f): Clr is a status-only column, non-sortable header (no sort arrow), the row checkbox stays editable via _toggleTxCleared; uncleared review is the Status = Uncleared filter (which preserves date/desc order and full-ledger balances). The _sortTxRows cleared comparator remains as dormant/defensive code, not user-facing. This matches Quicken: the register is ledger-first and can no longer be reordered into a status-grouped table. [SUPERSEDED by 8d48b04 below.]

Register CL/reconciliation default (2026-07-06, live-smoked on dashboard.herndons.us):
- 8d48b04: the Register now DEFAULTS to the Quicken CL/reconciliation view (`_txLedgerSortCol='reconcile'`), superseding the f12596f Clr-status-only default per Wendy's confirmation. Uncleared rows on top, cleared below, newest-first (chronIdx desc: transaction_date asc, created_at asc, id asc) within each group; cleared===true only (null/undefined counts as uncleared); starting-balance row at the bottom; full-ledger historical balances never recomputed after sort/filter. The Clr header activates reconcile (idempotent) and shows an active indicator; the old generic cleared comparator was removed from _sortTxRows. Date entry is uniform desc-first then toggles asc; Payee/Category/Outflow/Inflow remain sortable; Balance is non-sortable; the Clr checkbox (_toggleTxCleared) is unchanged. Display/read-only scope: no Register write path, schema/RLS/RPC, or Budget-calculation changes. Static 1332/0; affected e2e (LEDGER-1/2, A6-1, A9-1/2, RG-12) verified in a real browser; live-confirmed by Wendy's daily-reconcile workflow.

### A4 DONE (AMEX Gold starting-balance correction)
Executed 2026-07-06; verified in DB (postflight) and in the live Register. `accounts.starting_balance` for AMEX Gold corrected from -8248.07 to -8248.50 via `docs/2026-07-06-amex-gold-starting-balance-A4.sql`, run as one execution (single guarded transaction with COMMIT included). Corrected accounting anchor: -8248.50 is the cleared balance as of end of 2026-06-29, before the 2026-06-30 Foxtail -$7.17; Foxtail remains the first ledger row (order transaction_date asc, created_at asc, id asc) with a running balance of -$8,255.67. Only accounts.starting_balance changed: no transactions inserted/updated/deleted, Foxtail date/amount/updated_at unchanged, AMEX Gold tx_count = 51 unchanged, last_created_at/last_updated_at unchanged, no Budget/Register/schema/RLS/RPC changes. Postflight confirmed value_ok=true and ledger_at_foxtail_ok=true. The 2026-07-05 draft (`docs/2026-07-05-amex-gold-starting-balance.sql`) is superseded (positive-value guards plus a 2026-07-01 baseline guard that blocked the legitimate 6/30 Foxtail row). Unrelated: the 5F-1.5 Register default-sort question is now RESOLVED — Wendy confirmed the Quicken CL/reconciliation view, shipped live in commit 8d48b04 (see the Register CL/reconciliation default entry above). accounts.starting_balance is Register-ledger-display-only (does not affect Budget spend, cashflow, or reconciliation).

## Post-5F-1 Build Path & Strategic Horizons

AUTHORITATIVE PHASE MAP: `docs/phase-status.md` is now the source of truth for the locked 5G+ scheme (5G Cash Planning + Allocation, 5H Register capture speed + mobile quick-add, 5I Splits, 5J Month-end close + minimal goal editing, 5K Transfers, 5L Architecture hardening). The sub-lettering in `docs/strategic-roadmap-future-horizons.md` (its 5G-1/5G-2/5G-3, 5F-2/5F-3/5F-4) is SUPERSEDED for naming and must not be used as the current phase map. That doc is retained for its longer-horizon content (bank integration, AI assistant, planning/retirement layer, household OS) only, and will be reconciled in a later pass.

Guardrail unchanged: no bank import, AI assistant, forecast integration, or household OS expansion work until one clean July operating week with Wendy is complete.

### Stale spec warning

`docs/dynamic-goal-registry-spec.md` (June 21 draft) is NOT implementation authority. It references a goals table and anon read/write policies that do not match shipped 6A. Shipped reality: goal_registry, authenticated SELECT-only, hardcoded fallback, GR-A1 identity gate. New 5G tables must not inherit anon RLS patterns.

### Do Not Touch

See AGENTS.md "Do Not Touch" for the authoritative list (WD/effectiveWD, runModel internals frozen through 5G-2, cash_commitments, 5F-1 engine internals, reconciliation RPCs, Register schema, misc.goal_sweep, Budget identity math before 5G-3, RLS/anthropic_key, goal waterfall + ira_cpa_cleared, prod DDL, index.html script body/globals for new code, Quicken parallel data, golden-master expected outputs).

## Codex Operating Rule

Before editing, Codex should perform a read-only orientation against:
- `/Users/aherndon/AI-Context/00-README.md`
- `/Users/aherndon/AI-Context/02-working-style.md`
- `/Users/aherndon/AI-Context/05-financial-os-context.md`
- `/Users/aherndon/AI-Context/08-open-items.md`
- `AGENTS.md`
- `CODEX_STATUS.md`

Codex should not change files until it confirms the active goal, affected files/functions, intended tests, and risk areas.

Claude Code follows the same read-only orientation and the "Claude Code Session Protocol" in AGENTS.md before implementation.
