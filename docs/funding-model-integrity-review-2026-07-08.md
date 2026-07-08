# Funding Model Integrity Review — 2026-07-08

**Scope:** deep model-integrity review of the Funding Plan / goal-funding engine, triggered by Bailey 529 slipping to "Beyond 2026" after the Week 27 transfers and the $7,000→$7,500 IRA target correction (commit `1dcc686`). Read-only review; no code changed. Verified independently against the repo (line references below), against CODEX_STATUS production records, and by headless execution of the app's own `runModel()` under controlled scenarios (harness cloned from `test_regression.js`'s eval mechanism; scripts in session scratchpad: `model-scenarios.js`, `model-scenarios2.js`).

---

## 1. Executive summary

1. **The Bailey 529 symptom is NOT caused by the architecture issue the prior diagnostic identified. It is a discrete, reproducible waterfall bug — a permanent deadlock.** The $7,500 correction left Adam IRA with a **$61.06 remainder** ($7,438.94 funded of $7,500). Because Adam IRA is an AMEX-hold goal, its sweep must pass `maxSafeAmxSweep()` (index.html:1676-1686), which returns **0 for any amount below `MIN_XFR` ($100)** — and a 0 from that gate triggers `break`, killing the **entire waterfall for the week** (index.html:2460-2467). A sub-$100 remainder can never grow or clear, so from model week 6 onward **no goal receives another dollar all year**: Wendy IRA $0, all 529s $0, ~$16,000 of surplus strands in checking (headless run: checking ends Wk 53 at $22,574.82 with zero goal transfers prescribed after Cal Wk 27).
2. **The production dashboard's numbers match this exactly** — end-of-model timeline: Adam IRA 99%, Wendy/Bailey/Bryce/Preston 0%, Bailey "Beyond 2026", Adam IRA "$61.06 remaining". The screenshot is the deadlock's fingerprint.
3. **The prior diagnostic's central quantitative claim is wrong for production.** It claimed the dashboard models Adam IRA at ~$3,876 vs reality's ~$7,438.94 and "wastes ~$3,600 re-funding" it. In production (with reconciliation data), the Week 27 waterfall swept $3,562.56 + the $3,772.74 seed = **$7,438.94 — the model and reality agree to the cent** (also independently recorded in CODEX_STATUS 5G-1A: Week 27 goal transfers $11,662.56 = 7,000 + 600 + 500 + 3,562.56). The diagnostic's fallback-mode headless run (no `reconData`) produced different Week 27 surplus; its caveat that "current-week goalSaved matches production closely" was its load-bearing error. Its fallback *arithmetic* was faithful (I reproduced its tables exactly), but its production conclusions inherited the bad caveat.
4. **The architecture concern is nonetheless real — just latent, not the cause of this symptom.** Per-goal funded state (`goalSaved`) is pure simulation, re-derived every run from frozen constants (`START_AMX`, `RET_SAV_XFR`, `goalFundedAmounts`); weekly reconciliation re-anchors **account balances only, never goal attribution** (index.html:2537-2542). Today's agreement between model and reality is **coincidental** — it holds only because Adam executes exactly the model's prescribed transfers and the constants were calibrated at model start. There is no mechanism to detect or correct goal-attribution drift; even moving real money cannot fix the model (reconciling a corrected AMEX balance would not move `goalSaved`).
5. **The system sits on a knife edge.** In my production-approximate run that differed from the real anchor by only ~$218 of checking, Adam IRA landed at $7,657 (over target) instead of $7,438.94 (under) — and the entire year flipped: no deadlock, Bailey completes Cal Wk 49, Bryce/Preston fund. A ~$220 input wiggle swings ~$13,500 of downstream goal funding. That brittleness (cliff, not slope) is the strongest argument for the integrity phase.
6. **Recommended path:** (A) an immediate, surgical waterfall hotfix (requires an explicit Adam-approved exception to the runModel freeze; 5G-1A precedent) — restores Bailey to 2026 (Cal Wk 49 in the pinned run) and funds the entire stack by Cal Wk 53; then (B) a discrete phase — **week-anchored `goal_funding_snapshots`** mirroring the existing `reconData` overlay — making per-goal funded state durable, reconciled weekly, and auditable, before 5G-2 (whose Spoken For / Free to Use allocation view consumes exactly this attribution).

---

## 2. Verification evidence

### 2.1 Headless scenario runs (app's own runModel, controlled inputs)

| Scenario | Inputs | Adam IRA @ now | Wendy IRA ends | Bailey ends | Bailey completes |
|---|---|---|---|---|---|
| S0 — fallback, no recon, targets $7,500 | diagnostic's setup | 3,876.38 | 7,500 (Wk 53) | 2,950.40 | never |
| S0b — fallback, no recon, targets $7,000 | pre-correction | 3,876.38 | 7,000 (Wk 51) | 3,500 | Cal Wk 53 |
| **P1 — production-pinned, targets $7,500** | wk-26 recon anchor tuned so wk-27 sweep = **$3,562.56** (the recorded production value) | **7,438.94 (99%)** | **0.00 (0%)** | **0.00 (0%)** | **never** |
| **P2 — P1 + completion bypass in the AMEX gate** | same | 7,438.94 → completes Cal Wk 29 | 7,500 (Cal Wk 40) | 3,500 (**Cal Wk 49**) | **Cal Wk 49**; Bryce & Preston complete Cal Wk 53 |

S0/S0b reproduce the prior diagnostic's §5 tables to the cent (validates its fallback math). P1 reproduces the live dashboard exactly. In P1, the transfer log shows `Adam IRA deferred — 5-wk lookahead: floor risk` on every eligible week from mw7 through mw31 and **zero goal transfers executed after Cal Wk 27**; final checking balloons to $22,574.82. In P2 final checking is $6,935.63 with the full stack funded.

### 2.2 Screenshot fingerprint (production, Jul 8 build 15:27 = commit `1dcc686`)

| Screenshot fact | Deadlock model (P1) | No-deadlock model would show |
|---|---|---|
| Timeline right-edge (end-of-model fill, index.html:4707-4709): Adam 99% | 99% ✓ | 100% |
| Wendy IRA right-edge 0% | 0% ✓ | 100% |
| Bailey right-edge 0% / "Beyond 2026" | 0%, never ✓ | ~84–100% |
| Adam IRA remaining $61.06 / 99% row | 7,438.94 of 7,500 ✓ | — |
| Overall 2026 Progress "$45,647.60 of $84,459.00" | denominator = Σ non-stretch targets = 84,459.00 ✓ | — |

### 2.3 Independent corroboration
- CODEX_STATUS 5G-1A (written Jul 7, pre-correction): Week 27 goal transfers **$11,662.56**, ending checking **$8,298.08** → implies the Adam IRA waterfall sweep was **$3,562.56**; 103.64 + 3,562.56 + 3,772.74 = **7,438.94**, equal to the stated real funded amount. The Week 27 sweep was lookahead-constrained, not target-constrained, so the $7,500 correction did not change Week 27 at all — the damage begins Week 28.
- Pre-correction (target $7,000): 7,438.94 ≥ 7,000 → Adam IRA read complete → **no deadlock** → Wendy funded → Bailey completed in 2026. Post-correction: remainder $61.06 → deadlock. This cleanly explains "Bailey moved from end-of-2026 to Beyond 2026" with **no other change**.

### 2.4 The bug mechanism (code)
- index.html:2460-2467 — `_amxHold` goals: `proposed=sm(chk,rem0,effFl)`; `safeAmt=maxSafeAmxSweep(...)`; `if(safeAmt<=0){ _amxDeferredThisWeek=true; …'defer'…; break; }` — the `break` stops the whole waterfall.
- index.html:1677 & 1685 — both return paths of `maxSafeAmxSweep` clamp `>= MIN_XFR ? amt : 0`; any proposal < $100 returns 0 **even when fully floor-safe across the 5-week lookahead**.
- index.html:2476-2477 — `allowFin = rem0 < MIN_XFR*2` exists precisely to let sub-$100 *completion* sweeps through `mv()` — but for AMEX-hold goals the gate breaks first; `allowFin` is unreachable. The gate lacks the carve-out `mv()` already has. (Related: the break-on-defer semantic is also implicated in the known WC-3 What-If non-monotonicity.)
- The defer note's wording ("floor risk") is wrong in this case — there is no floor risk; the amount is simply below `MIN_XFR`. That mislabel would have sent any human debugging session down the wrong path.
- No data-only workaround exists: even if Adam moves $61.06 in reality, reconciliation only overrides `chk/sav/amx/tax/lc` — `goalSaved` never changes, so the model still deadlocks. (Setting `adam_ira` status to `funded` in `goal_registry` would unblock the waterfall but breaks the display: complete goals read `goalFundedAmounts['adam_ira']` = **0**.) A code fix is required.

---

## 3. Root-cause assessment

**Layer 1 — the symptom (Bailey "Beyond 2026"): waterfall completion deadlock.** Deterministic interaction bug: target correction ⇒ sub-`MIN_XFR` remainder on an AMEX-hold goal ⇒ `maxSafeAmxSweep`→0 ⇒ defer+`break` every week ⇒ all lower-priority goals starve permanently. Severity: **critical** — the Weekly Model (the operational transfer plan) currently prescribes *no goal transfers for the rest of 2026*, and the forecast for four goals is wrong.

**Layer 2 — the system (the prior diagnostic's concern, reframed): goal attribution is simulation-only and never reconciled.**
- `goalSaved` re-derives every run from frozen constants: `goalSaved['adam_ira']=START_AMX` (2207), `goalSaved['adam_401k']=goalFundedAmounts['adam_401k']` (2208, a stale-by-design YTD), everything else $0; plus the uncapped one-time `RET_SAV_XFR` seed (2511-2519; `mvS` at 2280 has no savings-availability guard — savings can go negative if calibration is disturbed).
- Reconciliation overlays balances only (2537-2542). There is deliberately no goal-level reconciliation, no variance concept for attribution, no invariant tying Σ(AMEX-held goal attributions) to the reconciled AMEX balance.
- Consequence: model/reality agreement is **execution-coincidental**. Any real-world divergence — a partial transfer, an extra contribution, the RCCL/DCL payouts leaving AMEX (Cal Wk 30/41, the accepted 5G-1B offset), an IRA custodian purchase after CPA clearance, a next-paycheck 401(k) YTD — drifts silently and is uncorrectable by any existing data layer.
- The knife-edge finding (§1.5) shows the two layers compound: simulation-only attribution + cliff-shaped gate semantics = tiny input error → catastrophic plan flip, with a green "Model live" badge throughout.

**What the prior diagnostic got right vs wrong:** Right — the architecture facts (§4 of the brief: no funded-amount column, `mapGoalFromDB` reads none, pure forward simulation), the fallback-mode arithmetic, the retRem-7000 note. Wrong — "current-week goalSaved matches production closely" (production Wk-27 sweep differs massively with recon data); therefore wrong that the dashboard shows $3,876 (it shows $7,438.94, matching reality); therefore wrong that ~$3,600 of future surplus is being wasted re-funding Adam IRA (future Adam IRA demand is $61.06); and it missed the deadlock, which its own fallback run couldn't trigger (fallback Adam IRA never lands within $100 below target).

---

## 4. Answers to the decision questions

1. **Is this truly a model-state architecture issue?** The Bailey symptom: no — it's the completion deadlock (Layer 1). The system: yes — attribution is unreconciled simulation and correctness is coincidental (Layer 2). Both need fixing, on different clocks.
2. **Where should durable per-goal funded state live?** A new week-anchored **`goal_funding_snapshots`** table (Option B below) applied in `runModel` exactly like `reconData` — not a mutable `funded_amount` column on `goal_registry`.
3. **Should the Funding Plan show actual funded-to-date plus projected future funding?** Yes. With snapshots, "funded" becomes *anchored-at-last-reconciliation + modeled-since*, exactly like account balances today, and future weeks stay projections. Label the split; today several surfaces present simulation with actual-implying language (§6, table).
4. **Discrete phase before more 5G cash-planning work?** The deadlock hotfix: immediately (it's an operational outage of the transfer plan). The snapshot phase: yes, as its own gated phase before **5G-2** — the allocation view derives "Spoken For" from precisely this attribution; building it on unreconciled simulation would bake the false-premise class into 5G.
5. **Lowest-risk implementation path:** hotfix first (≤10 lines, characterization-gated, no schema); snapshots second (additive schema + additive overlay with an identity gate proving zero-rows ≡ current behavior; staging-first per house rules; rollback = drop table/RPC, app reverts to constants).
6. **Tests that prove it and prevent recurrence:** §8 — headline items: a **no-permanent-starvation invariant** over all 31 weeks, sub-$100-remainder completion tests, the zero-snapshot identity gate, the AMEX-holding data-quality invariant, and characterization capture before/after the hotfix.

---

## 5. Architecture recommendation

### Rejected: Option A — `goal_registry.funded_amount` (mutable stored balance)
Violates the house doctrine the 5G specs already established (derived views; no stored allocation balances; append-only events; `weekly_reconciliations` stores *observations*, not running balances). More fundamentally it has **no as-of-week semantics**: `runModel` re-simulates all 31 weeks from scratch each run, so a "funded as of today" number cannot be safely combined with re-simulated past flows — seeding it at week 1 double-counts the seed/waterfall flows that are already inside the number. No audit trail; a silently-editable balance is the disease we're treating.

### Recommended: Option B — `goal_funding_snapshots`, week-anchored, applied like `reconData`
One row per (model_year, week_num, goal_id): observed cumulative funded amount at that reconciled week's end, plus provenance (`source`: reconciliation | opening_anchor | correction; `entered_by`, `created_at`, optional note). `runModel` integration is ~8 lines at the existing recon-override site (2537-2542): after `chk=rec.chk;…`, apply `goalSaved[id]=snap[num][id]` for snapshotted goals and capture per-goal variance (modeled vs observed) for display.

Why this shape wins:
- **Same mental model as the proven reconciliation architecture.** Accounts re-anchor weekly; goals re-anchor weekly. One cadence, one UI moment (the closeout), one variance concept.
- **Solves re-simulation semantics exactly.** Re-simulated past weeks (including the re-fired `RET_SAV_XFR` seed) get overwritten at each anchor, so double-counting is structurally impossible past an anchor. This is the only semantics compatible with a from-scratch weekly re-simulation.
- **Kills the constant-drift class gradually and safely.** `START_AMX`/`RET_SAV_XFR`/`goalFundedAmounts` remain as pre-first-anchor seeds only; after the first snapshot they're overridden weekly, so their staleness stops mattering. (`goalFundedAmounts` for complete/auto goals — 401(k) YTD, Wendy SEP — is replaced by reading the latest snapshot ≤ current week, with the hardcoded object as final fallback.) Absorbs wishlist TD-8's goal-side twin.
- **Enables the missing invariant** (data-quality check): at any snapshotted week, Σ(AMEX-held goal snapshots) + non-goal AMEX float ≈ reconciled `amx` (tolerance; holding-release-aware once 5G-1B lands). First check that can *detect* attribution drift instead of silently absorbing it.
- **Fits the constraint set:** `goal_registry` stays SELECT-only; reconciliation RPC/state machine untouched (a separate additive SECURITY DEFINER RPC `save_goal_funding_snapshots`, `can_write_financials()` policies, `TO authenticated`, anon revoked — 5G-1 conventions); waterfall ordering and `ira_cpa_cleared` untouched.

### Compatible later evolution: Option C — append-only `goal_funding_events` ledger (5G-1 `outflow_events` style)
Event-grain audit (contribution / release / adjustment / opening anchor) is the right end-state if 5G-1B payout releases and custodian moves need first-class history. Snapshots don't block it: events can be added later with snapshots as the weekly checkpoint (you want the observation layer anyway — events assert intent; snapshots verify reality). Do not build C first; it's heavier UI/discipline for no additional protection this quarter.

### Interaction review (requested objective 4)
- **Reconciled weekly balances:** snapshots ride the same weeks; a goal snapshot without that week's balance recon is disallowed (validation).
- **Account balances:** unchanged; goal overlay runs after the balance overlay at the same site.
- **AMEX holding buckets:** become derivable = per-goal snapshot amounts for `_amxHold` + `HOLDING_TO_AMEX_GOALS` goals; the DQ invariant above formalizes it (feeds 5G-2 directly).
- **Completed/executed goals:** snapshot at completion week freezes their value; `getGoalFunded` complete-goal branch reads snapshots instead of `goalFundedAmounts` (fixes Wendy SEP/401(k) hardcoding).
- **startsAfter dependencies:** unchanged — gates read `goalSaved`, which is now anchored; a snapshot showing a prerequisite complete correctly unblocks dependents even where the pure simulation would disagree.
- **AMEX 5-week lookahead:** unchanged by snapshots (it's checking-floor math); fixed separately by the hotfix.
- **Current week vs future projection:** weeks ≤ last snapshot are anchored history; current week = anchor + modeled deltas; future = projection. UI labels should say so (§6).
- **Fallback vs production data:** snapshots are DB-only, deliberately no hardcoded fallback — absent rows ⇒ behavior identical to today (identity gate). Extend the existing goals fallback banner pattern: "goal funding running from model seeds — no snapshots loaded."

---

## 6. Risk assessment (false-premise sweep results)

Confirmed high-priority (beyond the deadlock):

| # | Risk | Where | Severity / note |
|---|---|---|---|
| 1 | `retRem` hardcoded to 7000 vs real target 7500 | 2590; consumers 3069 (`retirementCompletion`), 3144, 3881-3883, 9591/9609/9648 (Ask Claude payload) | Retirement reads "complete" ~$500 early; **under the deadlock, Ask Claude is told "Ret rem $0.00 / Funded Cal Wk 27" while the Funding Plan shows $61.06 remaining and deadlock** — three surfaces, three stories. Three conflicting retirement bases exist: 7000 (retRem), 7500 (registry), 7694.87 (`goalRt`, whose own fallback is inconsistently 7690.98 at 7742 vs 7694.87 at 1272). |
| 2 | `goalFundedAmounts` frozen actuals | 1279; reads 2208, 4284-4289 | 401(k) YTD 10,208 goes stale every paycheck (model accrues from a frozen base); never DB-written. Wendy SEP 17,859 duplicated vs registry target. |
| 3 | Uncapped seed + unguarded `mvS` | 2511-2519, 2280 | Seed adds full $3,772.74 regardless of target (observed +$157 overshoot in the S1 run) and can drive savings negative if `START_SAV`/ak-target calibration shifts. Alaska draw (2286) is guarded; the seed is not. |
| 4 | Silent partial fallback | `loadAll` 7717-7849; `_supaConnected` set true at 7834 regardless of per-table failures | `reconData`/commitments/tasks/overrides failing individually = silent (console only) while the badge shows green "Model live" (3020-3025). Goals have a banner (7444-7452); nothing else does. |
| 5 | Fallback↔DB drift undetectable | GR-A1 (test_regression.js:3978-4030) round-trips the fallback against itself; **no test or runtime check compares fallback to live `goal_registry`** | Concrete instance: `docs/phase-6a-goal-registry-spec.md` seed SQL still says IRA targets 7000 while fallback/commit say 7500 (doc drift). Also verify live `goal_registry` RLS during the phase preflight: the 6A spec says anon SELECT; current context says authenticated-only post-4B. |
| 6 | `ira_cpa_cleared` is session-only | 1278; toggle 4297; no persistence | When CPA actually clears, the toggle resets on every reload — "Awaiting CPA" forever until a code/DB change. (Display-only for AMEX goals, but it drives lock UI and engine scenarios.) |
| 7 | Simulated values wearing actual language | Full inventory from the UI sweep: Savings/Priorities "Funded" columns (4374, 4550), Funding Plan "✅ Funded" (4737), Overall 2026 Progress (4660-4673, blends static actuals + simulation), Overview "Account Integrity / IRA Staging" (3443-3446), topbar "Alaska X% funded" (7469), weekly "funded!" rows (2489), Ask Claude "Saved/Funded" (9607-9611) | Copy fix rides the snapshot phase ("as of last reconciliation" framing). |
| 8 | Knife-edge plan flips | §1.5 | ~$220 input delta flips 4 goals' year; snapshots + hotfix + starvation-invariant test collectively de-cliff it. |
| 9 | Cross-year staleness | `getCurrentWeek` clamps at 31 (2622); START_* constants; re-baseline already tracked at 9167 | Out of scope; noted for the 2027 re-baseline. |

Hotfix-specific risks: it changes modeled output from Wk 28 forward by design (Bailey/Wendy/Bryce/Preston forecasts move; next weekend's prescribed transfers change — expect "Adam IRA $61.06" and a Wendy IRA sweep around Cal Wk 29). Freeze exception must be explicit; characterization tests pin everything else byte-identical. Snapshot-phase risks: wrong first-anchor values would anchor the model to a wrong reality — mitigated by Adam confirming the seed numbers (constraints already state Adam IRA ≈ 7,438.94, Wendy/529s $0) and by the AMEX invariant check; non-atomicity between recon save and snapshot save (separate RPCs) mitigated by UI sequencing + a "snapshot missing for reconciled week" nag + DQ check.

---

## 7. Phase plan

### Phase 0 — live confirmation (today, no code)
Adam, on dashboard.herndons.us: Weekly Model → any week Cal Wk 29+ → expect `Adam IRA deferred — 5-wk lookahead: floor risk` and **no goal-transfer actions**; Goals → Funding Plan → timeline right-edge 99/0/0/0/0. Confirms the deadlock live. (Reconciling Wk 27 on Saturday neither fixes nor worsens it — recon never touches `goalSaved`.)

### Phase A — waterfall completion hotfix (immediate; single session; requires explicit freeze-exception approval)
- **Change (call-site, ~6 lines, index.html `_amxHold` branch 2460-2468):** before calling `maxSafeAmxSweep`, if `rem0 < MIN_XFR*2 && proposed > 0 && amxSweepKeepsFloor(proposed, …)` then accept `proposed` — mirroring the existing `allowFin` completion rule, with the full 5-week floor-safety check retained. (Validated in P2 with an equivalent helper-level patch; final form to be pinned by characterization tests.)
- **Also:** make the defer note's reason accurate (distinguish "below $100 minimum" from genuine floor risk), and fix `retRem`'s hardcoded 7000 → registry target (or explicitly defer retRem to Phase B — decision #6 below).
- **Not in scope:** priority order, targets, Week 27 data (verified unchanged: P1 vs P2 week-5 outputs are identical), seed cap, schema.
- **Gates:** characterization capture of current outputs *before* the fix; full static regression (seed-sensitive families listed in §8 reviewed deliberately); e2e incl. WC-3 re-check; Adam approves the changed expected outputs per the golden-master rule; manual live smoke after deploy (Wk 29 shows the $61.06 + Wendy sweeps; Bailey leaves "Beyond 2026").
- **Rollback:** revert commit (display/model only, no schema).

### Phase B — 5G-1C "Goal Funding State Integrity" (staging-first; before 5G-2; schedule around the Alaska freeze Jul 24–Aug 10)
1. **Schema migration** (staging rehearsal → prod, 5G-1 SQL-package pattern: env marker, preflight, migration, validation, seed, rollback, post-rollback diff): `goal_funding_snapshots(model_year, week_num, goal_id, funded_amount, source, note, created_by_user_id, created_at)`, PK (model_year, week_num, goal_id), FK goal_id → goal_registry, CHECK funded_amount ≥ 0, RLS `TO authenticated` SELECT + writes only via new SECURITY DEFINER RPC `save_goal_funding_snapshots` (`can_write_financials()`, grants normalized per the 5G-1 v1.4 lesson: REVOKE ALL from PUBLIC/anon/authenticated first).
2. **Seed / preflight script:** first anchor at the latest reconciled week, values confirmed by Adam (per constraints: adam_ira 7,438.94; wendy_ira 0; 529s 0; adam_401k from paystub YTD; wendy_sep 17,859; alaska/rccl/dcl at target). Preflight asserts the week is reconciled and the AMEX invariant holds.
3. **Model initialization changes** (runModel, same overlay site as recon, behind the identity gate): apply snapshot overrides per week; per-goal variance capture; `getGoalFunded` provenance (anchored vs modeled); complete-goal reads via snapshots.
4. **UI:** closeout attribution step (prefilled from the model's values — one confirm click when reality matched the plan), per-goal variance display, Funding Plan copy ("anchored to weekly reconciliation; future weeks are projections"), snapshot-missing banner, minimal fixes to the §6-7 actuals-implying labels.
5. **Data-quality checks:** SQL + JS: AMEX invariant, snapshot⊆registry, no snapshots for archived goals, snapshot-week-is-reconciled, monotonicity exceptions only via `source='correction'`.
6. **Rollback:** drop RPC + table; app identity-gate guarantees reversion to exact pre-phase behavior.
7. **Explicitly deferred:** 5G-1B payout releases (design them as snapshot decrements/`release` source rows when picked up), Ask Claude payload rebuild, seed/`mvS` guard + target cap, `ira_cpa_cleared` persistence, goalAk/goalRt fallback tidy-up (7690.98 vs 7694.87), full copy sweep.

### Sequencing
Phase A this week (unblocks the operational transfer plan). Phase B staging rehearsal next week; prod DDL + app build before Jul 24 if gates pass, else after Aug 10 — Phase A alone keeps the model correct through the freeze provided reality keeps following the plan. 5G-2 remains gated on Phase B.

---

## 8. Test plan

**Phase A (hotfix):**
- New behavioral tests (harness = existing eval mechanism): (i) AMEX-hold goal with remainder < $100 and floor-safe surplus → completes; waterfall proceeds to the next goal the same week; (ii) same but genuinely floor-unsafe → still defers+breaks (safety preserved); (iii) remainder ≥ $100 paths byte-identical to captured characterization; (iv) **no-permanent-starvation invariant**: across all 31 weeks, never (surplus above lookahead floor ∧ unfunded active AMEX goal with floor-safe proposal ∧ zero sweeps); (v) pinned-anchor regression reproducing P1→P2 (deadlock absent, Bailey completes within model).
- Review/update the seed-sensitive families the coverage survey flagged: test_regression.js:456-462, 492-498, 505-533, 997-1018, 1314-1325 (Mutation B), 1382-1399 (Mutation F), GR-A1 3978-4030. Re-run WC-3/WC-4 (break-semantics adjacency).
- e2e: Funding Plan no longer shows Bailey "Beyond 2026" under injected near-target state; Weekly Model Wk 29 shows the completion sweep.

**Phase B (snapshots):**
- **Identity gate (the freeze-safety proof):** zero snapshot rows ⇒ `runModel` output deep-equals current behavior (GR-A1 pattern, all 31 weeks × all goals × balances).
- Overlay behavior: seed-from-anchor, mid-model re-anchor, re-fired seed absorbed by a later anchor (no double-count), variance math, complete-goal reads, missing-week passthrough.
- DQ: SQL validation suite in the migration package + a JS assertion mirroring the AMEX invariant.
- e2e: closeout writes snapshot via RPC; Funding Plan shows anchored labels; snapshot-missing banner.
- Golden-master: capture the Phase-B fixture as the first real stored `runModel` fixture (none exists today — begins the 5G-2.5 convention early, per AGENTS.md's standing rule).

**Manual verification before deploy (both phases):** run the two scenario scripts against the working tree; Adam eyeballs Wk 29's prescribed transfers and the Funding Plan tab; after Wk-27/28 closeouts, confirm per-goal variance reads $0.00 while reality follows the plan.

---

## 9. Open questions / decisions needed from Adam

1. **Approve the runModel freeze exception for the Phase A hotfix?** (Without it, the transfer plan stays halted through 5G-2; recommended: yes, 5G-1A precedent.)
2. **Hotfix scope:** include the defer-reason label fix and the `retRem` 7000→registry-target correction, or keep the hotfix waterfall-only? (Recommended: include both; tiny and display-adjacent.)
3. **Confirm first-anchor values** for the snapshot seed (adam_ira 7,438.94 as of the Wk-27 closeout; wendy_ira 0; 529s 0; adam_401k YTD from the 7/7 paystub; wendy_sep 17,859).
4. **Closeout UX:** one prefilled confirm step for goal attribution at each weekly closeout — acceptable? (Alternatives — silent auto-write (rejected: re-introduces silent drift) or optional-with-nag.)
5. **Phase naming/sequencing:** run Phase B as 5G-1C after the 5G-1 prod DDL, or as an independent phase first? Pre- or post-Alaska-freeze?
6. **5G-1B interaction:** fold RCCL/DCL payout releases into the snapshot model when 5G-1B lands (release rows), per §5?
7. **Seed hardening** (cap `RET_SAV_XFR` at target remaining + guard `mvS` against negative savings): Phase B or its own later item? (Not currently manifesting; changes prescribed real transfers, so it needs its own review.)
8. **`ira_cpa_cleared` persistence** (DB-backed flag so CPA clearance survives reload): fold into Phase B or defer?

---

*Methodology: all code claims verified by direct reads of index.html at the cited lines (working tree = commit `1dcc686`); data-layer, UI-surface, constants, and test-coverage sweeps run repo-wide; scenario runs executed via the app's own script block under Node with the test_regression.js stub, production state pinned to the CODEX_STATUS Week-26 closeout balances and the recorded Week-27 sweep. Fidelity note: exact future completion weeks in P2 will shift with live `model_week_overrides`/`budget_rules` rows (not readable from the repo); the deadlock mechanism and Week-27 numbers are exact.*
