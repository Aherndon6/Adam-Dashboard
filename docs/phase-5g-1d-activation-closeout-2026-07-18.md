# Phase 5G-1D — PRODUCTION ACTIVATION CLOSEOUT + Option B remediation (2026-07-18)

**Status: ✅ 5G-1D PRODUCTION ACTIVATION COMPLETE + VERIFIED. Option B short-snapshot remediation
COMPLETE + VERIFIED.** Production closeout now runs through the atomic reconciliation-plus-nine-snapshot
wrapper; Gate C lockdown is active; the old direct write paths are revoked; Week 28 / model week 6 is
verified; rollback and audit evidence are recorded. This is the terminal completion record required by
operator package §11.

Governing artifacts: operator package `docs/phase-5g-1d-saturday-operator-package-2026-07-18.md` (v6,
§2/§7/§10/§11/§12/§14); Gate-B runbook `docs/phase-5g-1d-gateb-activation-runbook-2026-07-13.md`;
Gate-C register `docs/phase-5g-1d-gatec-register-2026-07-13.md`; incident records `…-gate4-hardstop-adam-ira-duplicate-2026-07-18.md`.
Claude executed **no** production SQL/RPC — Adam ran every production step in the Supabase SQL Editor /
authenticated REST and pasted back verbatim output, which Claude verified.

## 1. Pinned production state (as observed)

| Pin | Value |
|---|---|
| Production application commit (deployed `main`) | `bdcd1d7` |
| Live `BUILD_TS` (dashboard.herndons.us) | `2026-07-17T23:10:13` |
| Documentation HEAD at closeout draft | `35aaa9d754d54e0d524fa0a864de26b97b856097` (+14 unpushed docs commits; this closeout is a further docs commit) |
| `index.html` blob (unchanged all activation) | `cde5ed80bf3964dad24fb2dc489dfa30b063e63d` |
| Environment | production `usayoldrawwmjsmretin`, `system_identifier 7632885393857617092`, `app_environment` ABSENT |

## 2. Activation execution sequence (all PASSED, in order)

1. **Section A/B prechecks** — adjunct preflight (wk5 9/2/11; recon 5 rows wks 1–5; snaps@wk≥6=0); raw + consolidated `pre_phase_1` **17/17**; five-body MD5 captured (two pinned match; three unpinned captured).
2. **Phase-1 grants** (`activation-grants.sql`) — wrapper + Option B `authenticated` EXECUTE granted; old recon RPC still granted; owner=postgres unchanged; bodies byte-unchanged. Post-Phase-1 raw + consolidated **17/17** (only delta C-08/C-10 → EXECUTE=T).
3. **Gate-2 deploy** — `BUILD_TS 2026-07-17T23:10:13` (`bdcd1d7`); feature branch ff-merged to `origin/main`; GitHub Pages green; live BUILD_TS confirmed. Deploy fixed the active Week-28 open-window identity defect (the proper enabled `$425.68 commission_tax` task appeared).
4. **Week-28 / model week 6 closeout** — Gate-3 income-timing collision (Wendy `$1,752.26` extra BK pay, posted 07/17 in wk28) dispositioned **Option C / §2d PATH-B\*** (Fable-reviewed); AMEX Gold commitment created via **Phase-3 manual reconciliation** (§14.5); the atomic wrapper wrote **1 reconciliation + 9 `source=reconciliation` snapshots**. Durable-state verified 3 ways.
5. **Phase-2 revokes** (`activation-revokes.sql`, unmodified) — `LOCKDOWN REVOKES PASS`; old recon/repair/snapshot RPC `authenticated` EXECUTE revoked; table writes revoked; SELECT retained; wrapper + Option B retained.
6. **Final grant validation** — raw + consolidated `post_phase_2` **17/17** (`weekly_reconciliations`×anon raw-matrix false stop dispositioned per §14.7 — Supabase-default baseline, RLS-inert, C-13 scored; not a Phase-2 failure).
7. **Proof A**, **Proof B**, **Option B correction** — §§3–5 below.

## 3. Proof A — wrapper idempotency (NON-MUTATING; branch-F identity)

Authenticated owner re-submit of the exact persisted Week-6 payload (empty commitment/patched arrays;
`p_mode=normal_closeout`; `p_expected_count=9`).

- HTTP **200**; body `{ok:true, mode:normal_closeout, week_num:6, idempotent:true, snapshot_count:9}`
- pre/post non-mutation fingerprints **unchanged**: `recon_rows=1`, `snap_recon_rows=9`, `distinct_goals=9`, `adam_ira=7438.94`, `recon_fp=d6fa5d0e81303f897388378d2346a2a1`, `snaps_fp=e4b88fccd36fc7d9474be30996126cfb`

**Proves:** the wrapper still executes as the definer owner after the Phase-2 revoke, and is idempotent
with zero new mutation.

## 4. Proof B — legacy direct-RPC denial (EXPECTED-FAILURE; non-mutating)

Authenticated direct POST to the revoked `save_reconciliation_with_commitments` (all 11 named args, both
JSONB, `p_model_year=9999` sentinel).

- HTTP **403**; PostgreSQL code **42501**; message **permission denied for function save_reconciliation_with_commitments**
- **no 2xx; no production mutation** — reconciliation + snapshot fingerprints unchanged vs Proof A

**Proves:** the old direct write path is closed for `authenticated` after the revoke (behavioral
confirmation of step-13 C-02=F). Grant-layer denial occurred before the function body ran.

## 5. Option B — Gate-4 short-snapshot remediation (MUTATING; single authorized correction)

Root cause (dispositioned in `…-gate4-hardstop-adam-ira-duplicate-2026-07-18.md` + operator package
§14.6, owner decisions D1–D7): the executed open-window **`$61.06`** Adam-IRA transfer was not absorbed
into the wk6 durable snapshot (short `7438.94` vs target `7500.00`), which surfaced a clickable Week-29
duplicate Adam-IRA recommendation. Correction via the owner-only `correct_goal_funding_snapshot` RPC
(authenticated owner path), run **once**, after Proof B, per the D1 exceptional recovery ordering.

- Call: `correct_goal_funding_snapshot(2026, 6, 'adam_ira', 7500.00, 7438.94, <note citing Gate-4 incident + D1–D7>)`
- Response: HTTP **200**; `{ok:true, corrected:true, model_year:2026, week_num:6, goal_id:adam_ira}`
- adam_ira wk6 durable snapshot corrected **7438.94 → 7500.00** (delta exactly **`61.06`**)

**Post-verification (D6 8+1 partition; D4 Amendment A):**
`total_wk6=9`, `distinct_goals=9`, `recon_source=8`, `correction_source=1`, `surprise_source=0`,
`adam_ira_amt=7500.00`, `adam_ira_source=correction`, `recon_fp=d6fa5d0e81303f897388378d2346a2a1`
(unchanged), `other8_fp=ddcce19d508845b3f362e09dc17ed0fb` (the eight untouched goals byte-unchanged).

**BINDING (§14.6):** the original frozen payload must never be resubmitted for wk6; Proof A must not be
re-run (persisted adam_ira is now `7500.00`).

## 6. Application-level verification (post-correction, fresh browser)

- Week 29 no longer shows the duplicate Adam-IRA **`$61.06`** recommendation (§2b POST-CLOSE: zero
  later-week Adam-IRA recommendation — **now PASS**).
- Week 28 retains the **executed** Adam-IRA `$61.06` transfer as historical evidence (unchanged).
- Adam IRA shows **100% funded / $0.00 remaining**; **Wendy IRA** remains the valid next IRA recommendation.
- No unrelated visible Week-29 recommendations were altered.

## 7. Week 6 — reconciled + immutable; activation execution window closed

**Week 6 remains reconciled and immutable under the approved owner-only reopen control.** The §7
activation execution-window freeze held byte-identical through Proof A and Proof B (both fingerprints
stable) and is now closed; the **single** authorized Option B correction was applied within it. No
further Week-6 mutation. Post-correction durable Week-6 state is the terminal state of record. **Week 6 is
not open, unfrozen, or reopened** — any future change to it requires the approved owner-only
`approved_reopen` control (a separate, gated action).

## 8. Completion statement (operator package §11)

> **5G-1D COMPLETE + GREEN.** Production closeout now uses the atomic reconciliation-plus-nine-snapshot
> wrapper; Gate C lockdown is active; old direct write paths are revoked; Week 28 / model week 6 is
> verified; rollback and audit evidence are recorded. Option B short-snapshot remediation is COMPLETE +
> VERIFIED.

## 9. Execution evidence vs. PENDING FUTURE WORK (distinct — not part of this completed phase)

The following are recorded, still-open items; none is required for 5G-1D completion and none is done here:

- **B1 correction code** (before the Week-7 closeout; §14.6 D5): eid from structured event date not label;
  incorporate executed open-window transfers into cumulative funded prefill/credit; pre-submit
  warning/block. Amendment A (D4) + §2b remain compensating controls until it ships.
- **Push** of the local docs commits (14 + this closeout) — **owner-authorized only; not done.**
- **`weekly_reconciliations` 2026/2027 re-key** (Fable P2-2) before the first 2027 closeout.
- **`weekly_reconciliations` anon grant normalization** — post-activation backlog (operator package §12.5).
- **5G-1D-HIST-1** legacy-completion display regression (roadmap P3b-1; §13.6).
- **TX-1.1** register income category for `Wendy Extra BK Pay` (post-activation; roadmap P3b-1).
- **Week-29 two-leg tax** (`$417.83` Deep-South deferral + `$700.90` Extra BK Pay) — booked in Week 29
  after B1 ships; the `$365.32` display artifact is not executable.
- **NEW — Stage-2 audit (separate phase):** "2026 Goal-Funding Projection and Waterfall Integrity Audit"
  — triggered by the post-correction Funding Plan now projecting **Bailey 529** to reach 100% in 2026.
  Read-only; must not be folded into this completed 5G-1D phase. Artifact:
  `docs/phase-audit-2026-goal-funding-waterfall-integrity-2026-07-18.md`.

*Balance-free except the already-committed adam_ira correction pair (`7438.94`/`7500.00`/`$61.06`, per
§14.6) and non-secret fingerprints. No reconciliation balances, tokens, or the other eight goal values
appear here.*
