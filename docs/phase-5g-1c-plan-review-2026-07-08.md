# 5G-1C Plan Review (Fable) — 2026-07-08

**Reviewed:** `docs/phase-5g-1c-plan-2026-07-08.md` against the live repo at commit `1eb9e84` (5G-1A.5 shipped), `docs/funding-model-integrity-review-2026-07-08.md`, CODEX_STATUS.md, docs/phase-status.md, index.html (runModel/overlay/getGoalFunded/Funding Plan render), test_regression.js (incl. Section PHASE-A), e2e.js. Verification included re-running the pinned production scenario harness against the current build: the shipped 5G-1A.5 carve-out reproduces the reviewed P2 counterfactual exactly (Adam IRA completes Cal Wk 29; no deadlock weeks; Week 27 byte-identical).

**Verdict: architecture APPROVED — Option B (week-anchored cumulative `goal_funding_snapshots`, overwrite-at-anchor, applied at the reconData overlay site) is correct and better than the alternatives. Two-slice split approved. 13 required changes before implementation, none structural. GO for 5G-1C-1 immediately; CONDITIONAL GO for 5G-1C-2.**

---

## Answers to the 14 review questions (condensed — full reasoning in the session review)

1. **Two-slice split: correct.** 1C-1 is pure render (no runModel edit, no freeze exception); 1C-2 carries schema/RPC/overlay/first anchor. Sequence 1C-1 → golden-master capture → 1C-2. Weekly closeout writes stay in 5G-1D.
2. **Snapshots: right design.** Better than a `goal_registry.funded_amount` column (no as-of-week semantics under from-scratch re-simulation ⇒ structural double-count; no audit; doctrine violation). Better than a ledger *now* (heavier build, no added protection this quarter; you'd still need weekly observation checkpoints anyway). Ledger = later evolution (5G-1E releases / 5G-6 audit grain).
3. **Overwrite-at-anchor: correct and load-bearing.** End-of-week placement after the balance overlay (post-waterfall, post-seed) makes double-counting structurally impossible past an anchor; the re-fired RET_SAV_XFR seed is absorbed. Two guards required: overwrite only goal_ids already present in `goalSaved` (R1) and shape-stable week objects (R2).
4. **Zero-snapshot identity gate: sufficient only as sharpened (R3).** Must be defined as deep-equal including key sets, under fallback AND pinned-recon fixtures, plus the table-absent/fetch-error path, PLAN_YEAR filtering, and getGoalFunded outputs. Known edge cases: `goalVariance` key shape; 404 vs empty; e2e loading real prod rows; goalCompletion scan change (identity-safe only because stays-complete ≡ first-crossing under monotonic sims — prove by test).
5. **Completed goals:** completeness stays status-driven (registry `status`); snapshots become the *value* source. `getGoalFunded` complete-branch chain: latest snapshot ≤ currentW → `goalFundedAmounts` → 0. Include `wendy_sep` opening anchor. **Do not flip any goal's status to `funded` before the snapshot read lands** (complete goals currently read `goalFundedAmounts`, which is 0 for everything except 401k/SEP — the $0-display trap).
6. **First-anchor classification:** adam_ira snapshot (capture at seed time: 7,438.94 today; 7,500.00 if seeded after Cal Wk 29 executes); wendy_ira snapshot (0 today; ≈927+ after Cal Wk 29); bailey/bryce/preston snapshot 0 (Adam confirms); wendy_sep snapshot 17,859 (opening_anchor, complete); adam_401k EXCLUDE; alaska snapshot observed 7,000 (status stays `funding`); rccl/dcl EXCLUDE; bryce_vehicle/christmas_cruise snapshot 0 (confirm). **Values in the plan's §4.4 table are illustrative — the seed script must capture reality at seed time (R5).**
7. **adam_401k excluded: confirmed.** Payroll YTD on a paystub cadence, accrued in-model per paycheck; snapshotting it fights the accrual semantics and its getGoalFunded branch. Enforce the exclusion in the RPC (reject `auto` goals), not just by convention (R9). Stale 10,208 YTD remains a separately tracked gap.
8. **RCCL/DCL excluded: confirmed.** Holding-bucket lifecycle is 5G-1B/1E. Their in-sim 600/500 values feed the advisory invariant correctly until the real payouts. Note: the real RCCL payment (~Cal Wk 30) lands mid-phase ⇒ a KNOWN advisory variance appears then — expected, not a defect. Enforce exclusion in the RPC (R9).
9. **AMEX invariant: advisory-only in 5G-1C — confirmed, and make it one-sided (R11):** flag only over-attribution (Σ `_amxHold` snapshots + in-sim rccl/dcl holding − reconciled `amx` > $1 tolerance). Positive float is informational. A hard gate now would false-alarm within weeks (RCCL payout, unbuilt 5G-1B). Hard gate = 5G-1E.
10. **Scope-steal check: clean.** RPC in 1C-2 is justified (first anchor written the house way; table not write-dead). Keep variance display minimal (week-detail/console; closeout variance UX = 1D). No closeout UI, no bucket schema, no month-end artifacts. Approved as bounded.
11. **1C-1 safe before schema: yes** — pure render from existing vm (`fundedNow`, `fundedYE` = weeks[last].goalSaved, `comp`). Wording matrix is right EXCEPT the plan's row-1 semantics silently change current behavior (R7): today `isFunded = pct≥100 || complete`, so Alaska/RCCL/DCL (status `funding`, pct 100) show "✅ Funded", and a locked goal at 100% (Adam IRA from Cal Wk 29) shows "✅ Funded"; the plan's status-only row 1 would flip those to "Cal Wk 27" / "🔒 Awaiting CPA". Decide the isFunded × isLocked matrix explicitly — recommended: pct≥100 ∧ locked → "✅ Staged — awaiting CPA deploy"; pct≥100 ∧ ¬locked → "✅ Funded"; row 7 threshold uses an epsilon (fundedYE > 0.005). Projected-YE figures are volatile week-to-week (live Bailey 73% vs pinned-approximation completion — unknowable live overrides/BLR); label everything "projected".
12. **Safe before July close: yes**, with the freeze contingency: 1C-1 now; 1C-2 staging next week; prod go/no-go checkpoint ~Jul 21–22; if missed, 1C-2 lands after Aug 10 and the July close (5G-1F territory) proceeds without snapshots or with SQL-script-written anchors — the 5G-1A.5 hotfix keeps the plan correct through the freeze while reality follows it. Do NOT rush 5G-1D UI in before the freeze.
13. **Highest-risk failure modes:** (a) additive-instead-of-overwrite or pre-waterfall overlay placement → double-count (tests + placement pin); (b) stale single anchor between 1C-2 and 1D → age nag + variance at next anchor + July SQL path; (c) completed-goal $0 trap → R6 chain + status-flip guardrail; (d) account-vs-purpose drift → advisory-only + expected RCCL variance; (e) live/fallback drift → snapshots deliberately have NO hardcoded fallback; banner split (R10) + e2e injection hygiene (G2); (f) misleading labels → R7 matrix + "as of Wk N" captions; (g) rollback/identity → R2/R3 shape+404 rules, golden-master captured at the exact pre-1C-2 commit.
14. **Acceptance tests:** keep all proposed; additions and sharpenings in §Required tests below.

---

## Required changes to the plan (R1–R13, all pre-implementation)

- **R1** Overlay overwrites only ids already in `goalSaved` (active model-tracked goals). Complete-goal snapshots are consumed ONLY by `getGoalFunded` — never injected into `goalSaved` (prevents week-shape drift; keeps complete goals out of the simulation).
- **R2** `goalVariance` attaches to the week object only when an anchor applied (zero-snapshot week objects byte-identical, including key sets).
- **R3** Identity gate defined precisely: with `goalSnapData={}`, `runModel` weeks[] deep-equal (values + key sets) vs the golden master under (a) fallback inputs and (b) the pinned-recon fixture; `getGoalFunded` equal for every goal; table-absent/fetch-error ≡ zero rows; loader filters `model_year=eq.PLAN_YEAR`.
- **R4** Drop the `opening_anchor` exemption from the week-reconciled rule — ALL snapshot weeks must have a `weekly_reconciliations` row (weeks 4 and 5 both qualify by seed time).
- **R5** Seed values captured at seed time from the latest closeout + bank reality; the §4.4 table is illustrative, not the source of truth (post-Cal-Wk-29 seeding changes adam/wendy values).
- **R6** `getGoalFunded` edit scoped to the `g.complete` branch only. The plan's "complete/auto branch" wording is wrong — no auto branch exists; adding one would break 401(k) accrual display.
- **R7** Define the row-1 isFunded × isLocked matrix explicitly (see Q11) — the plan's tree as written silently regresses Alaska/RCCL/DCL and locked-at-100% displays. Adam picks wording.
- **R8** `goalCompletion` scan (index.html:3112) becomes stays-complete (first week ≥ target that remains ≥ target through wk 31) — identical under monotonic sims (identity-safe), correct under future downward anchors. Rescope the "monotonically non-decreasing goalSaved" regression test (test_regression.js:447-454) to zero-snapshot runs. What-If's own first-crossing ETA scans are unchanged this phase (baseline and scenario share anchors; accepted asymmetry — note in docs).
- **R9** RPC validation additions: reject `auto` goals and `HOLDING_TO_AMEX_GOALS` ids (policy enforced in one place); `p_week_num BETWEEN 1 AND 31`; sane `p_model_year`.
- **R10** Banner split: fetch-error/table-absent ⇒ warn banner; HTTP-ok zero rows ⇒ quiet "no anchors yet" info state (no wolf-crying pre-seed).
- **R11** Advisory AMEX invariant defined one-sided (over-attribution alarm only), $1 tolerance, rccl/dcl in-sim holding included; positive float informational.
- **R12** Schema doc consistency: DDL has UUID PK + UNIQUE(model_year,week_num,goal_id) while the notes claim a composite PK — keep the DDL, fix the note; document that upsert mutates the current observation (history grade arrives with the later ledger); optional nicety: DO UPDATE appends the prior value to `note`.
- **R13** Drop the ES-module gesture for the in-body seams: loader addition, overlay, `getGoalFunded` branch, and label tree land in-place under the freeze exception (classic-script body can't cleanly import module functions without new globals). State this explicitly to avoid implementer thrash.

## Implementation guardrails (G1–G7)

- **G1** Do not flip any goal's `goal_registry.status` to `funded`/`executed` before 1C-2's snapshot read lands.
- **G2** e2e runs against real Supabase — once prod rows exist, e2e must inject/clear `goalSnapData` via `page.evaluate`, never assume empty.
- **G3** Golden-master fixture: capture at the exact pre-1C-2 commit, runModel-output-only, committed file (recommend `fixtures/`); AGENTS.md never-edit-without-approval applies from day one.
- **G4** PHASE-A Week-27 golden tests (GOLD_TR/GOLD_AC) must stay green through all of 1C — any diff there is a stop-the-line signal.
- **G5** Freeze checkpoint ~Jul 21–22 for 1C-2 prod DDL; miss ⇒ post-Aug-10, July close runs on the SQL-script path or without snapshots.
- **G6** 1C-1 must update the whenTxt whitelist tests (test_regression.js:343-347, 782 family) deliberately — new labels added to the valid-forms list, old assertions revised in the same commit.
- **G7** Update the stale "not yet pushed" 5G-1A.5 language in CODEX_STATUS.md (it is pushed + production-verified) and reconcile the phase map (docs/phase-status.md 5G-2 vs the new 5G-1D/1E/1F + 5G-2-Planned-Outflows roadmap) in the 1C opening docs commit.

## Required tests (delta over the plan's list)

Keep everything in plan §6. Add: key-set shape identity (R2); table-absent/fetch-error identity; PLAN_YEAR filter; sparse-anchor passthrough (anchored goal pinned, others simulate on); downward-anchor behavior (goal re-opens, funds again, stays-complete completion correct, monotonicity test rescoped); RPC rejects auto/holding goals + unreconciled week (incl. opening_anchor post-R4) + idempotent re-upsert; getGoalFunded chain (snapshot → goalFundedAmounts → 0); label truth table including the isFunded × isLocked matrix and Alaska/RCCL/DCL regression rows + fundedYE epsilon; **hotfix × overlay composition** (anchor adam_ira at 7,438.94 via snapshot ⇒ carve-out still completes it Cal Wk 29); Week-27 golden green; e2e goalSnapData injection hygiene. Sharpen "AMEX-held snapshot variance" into (i) a one-sided invariant unit test and (ii) a variance sign-convention test (modeled − observed).

## Open decisions for Adam (D1–D8)

D1 R7 wording matrix ("✅ Staged — awaiting CPA deploy"?). D2 Anchor week: model wk 5 after Saturday's closeout (recommended) vs wk 4 now. D3 Confirm seed values at seed time (incl. 529s/vehicle/christmas = 0). D4 RPC ships in 1C-2 (recommended: yes). D5 Phase-map reconciliation (adopt brief roadmap; update phase-status.md). D6 Freeze/July-close contingency acceptance (G5). D7 Golden-master location + approval-rule acknowledgment. D8 New-label wording for rows 6–8 (plan §3.2).

## Go / no-go

- **5G-1C-1: GO now** (with R6/R7 folded in; D1/D8 wording picked at implementation).
- **5G-1C-2: CONDITIONAL GO** — conditions: R1–R13 folded into the plan doc; D1–D5 decided; staging rehearsal green (marker → baseline → preflight → migration → validation → seed → seed-validation → rollback → clean diff, plus real-caller RLS smoke per the 5G-1 pattern); freeze checkpoint respected (G5).

*Plan-review only; no code changed. Full reasoning in the review session; companion to `docs/funding-model-integrity-review-2026-07-08.md`.*
