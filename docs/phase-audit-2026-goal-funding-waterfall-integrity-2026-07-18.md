# 2026 Goal-Funding Projection and Waterfall Integrity Audit (2026-07-18)

**Status: 📋 AUDIT PLAN — READ-ONLY. No fixes implemented, no production writes, no SQL executed, no
model recalculation changed.** Separate phase; **not** part of the completed 5G-1D activation
(`docs/phase-5g-1d-activation-closeout-2026-07-18.md`). WIP=1: the 5G-1D closeout draft is complete;
this artifact is the audit scope + initial repository-grounded findings only.

**Trigger.** After the Option B adam_ira correction (`7438.94 → 7500.00`), the Funding Plan now projects
more 2026 completions — specifically **Bailey 529**, previously "close but not fully funded in 2026,"
now appears to reach 100%. This must be traced causally and mathematically, not accepted because the UI
shows it.

**Method.** Trace the actual implementation and data flow (`index.html` runModel + waterfall; the
deployed snapshot RPCs). Every claim cites file + line. UI is evidence to be explained, never the source
of truth.

---

## 0. Repository state at audit open (verify before relying on this)

- Production app commit `bdcd1d7`; docs HEAD `35aaa9d…` (+ unpushed docs incl. the 5G-1D closeout draft);
  `index.html` blob `cde5ed80…`; `BUILD_TS 2026-07-17T23:10:13`.
- **STOP-and-report if any of these differ** from the committed state above before running the audit.
- All line numbers below are against `index.html` blob `cde5ed80…`. Re-anchor if the blob changes.

## 1. Grounded architecture map (the surfaces the audit must trace)

| Concern | Location | Note |
|---|---|---|
| Goal registry (target, priority, `startsAfter`, `needsFlag`, `stretch`, `auto`, `complete`) | `index.html:1582–1594` | targets/priorities below |
| Waterfall constants | `index.html:896` | `OP_FL=6500`, `MIN_XFR=100`, `AK_START=5` |
| Active-waterfall build (filter + priority sort) | `index.html:1679–1690` | excludes `auto`, `complete`, `stretch`, `paused`, `archived` |
| `goalSaved` init + adam_ira AMEX seed | `index.html:2256–2258` | seed `= START_AMX` |
| **Snapshot overlay (durable funded overwrite)** | `index.html:2624–2637` | `goalSaved[gid]=_gsnap[gid]` — the correction feeds here |
| `startsAfter` dependency gate | `index.html:2482–2486` | skip until prereq at target |
| **`_amxHold` set + defer/`break`** | `index.html:2491`, `2510–2536` | **the cascade-block mechanism** |
| complete-skip (`rem0<0.005 continue`) | `index.html:2497` | a completed goal drops out |
| `allowFin` tiny final contribution | `index.html:2549–2551` | `rem0<MIN_XFR*2` |
| adam_ira remaining tracker | `index.html:2688` | `retRem` |
| Identity-strict transfer resolver | `index.html:3203` | `resolveWeekTransfers` |
| **Open-window executed-transfer netting** | `index.html:3280`, credit only for unreconciled weeks `:3349` | `computeGoalTransferNetting` |
| Snapshot = monotonic floor, never projected `goalSaved` | `index.html:2829` | |
| Snapshot load status gate | `index.html:953`, `2974` | `_goalSnapLoadStatus` |
| Option B correction RPC (in-place upsert `source=correction`) | `docs/phase-5g-1d-migration.sql:365` | natural key `(model_year,week_num,goal_id)` |

**2026 active waterfall (priority order), from the registry:**

| Pri | Goal | id | Target | startsAfter | needsFlag | In `_amxHold`? |
|---|---|---|---|---|---|---|
| 1 | Alaska Cruise | `alaska` | 7000 | — | — | no (→ Truist Savings) |
| 2 | Wewe RCCL | `wewe_rccl` | 600 | alaska | — | no (holding→amx) |
| 3 | Wewe DCL | `wewe_dcl` | 500 | alaska | — | no (holding→amx) |
| 4 | **Adam IRA** | `adam_ira` | **7500** | wewe_dcl | ira_cpa_cleared | **yes** |
| 5 | Wendy IRA | `wendy_ira` | 7500 | — | ira_cpa_cleared | yes |
| 6 | **Bailey 529** | `bailey_529` | 3500 | — | — | yes |
| 7 | Bryce 529 | `bryce_529` | 1500 | — | — | yes |
| 8 | Preston 529 | `preston_529` | 1000 | — | — | yes |
| 9 | Bryce Vehicle | `bryce_vehicle` | 8000 | — | — | no |
| 10 | Christmas Cruise | `christmas_cruise` | 5000 | — | — | no |
| 11 | Taxable ETF | `taxable_etf` | 4999.79 | — | — | **excluded (`stretch`)** |

`adam_401k` (auto) and `wendy_sep` (complete) are excluded. **Taxable ETF is `stretch` → excluded from
the 2026 waterfall** (`index.html:1680`; 2027 restart) — audit item 2 must confirm it does not participate.

## 2. LEADING CAUSAL HYPOTHESIS (initial finding — to be confirmed by the audit, NOT a conclusion)

**Three distinct epistemic levels — do not collapse them:** (a) **documented code behavior** — the
control flow and the verbatim comments below are established facts about the deployed build; (b) **a
hypothesized causal explanation** — that this behavior is *why* Bailey 529 changed; plausible and
strongly grounded, but not yet demonstrated end-to-end; (c) **deterministic mathematical proof** — the
before/after projection diff + goal-by-goal trace (§3.7), **still to be produced.** Nothing here is a
completed audit conclusion, and the Bailey 529 result must NOT be recorded `VERIFIED CORRECT` until (c) is
done.

**Hypothesis:** the Bailey 529 change *appears* to be a valid waterfall consequence of unblocking a
documented `_amxHold` cascade break — i.e., the pre-correction projection may have been the artifact — but
this is a hypothesis to be proven, not assumed.

Grounded chain:
1. The snapshot overlay writes the durable funded value into `goalSaved['adam_ira']` (`index.html:2637`).
   Pre-correction that was **7438.94** (short by **61.06** vs target 7500) — the Gate-4 defect (the
   executed open-window `$61.06` was never absorbed into the durable snapshot).
2. adam_ira is in `_amxHold` (`index.html:2491`). Its remaining `61.06 < MIN_XFR (100)`. Per the
   verbatim carve-out comment (`index.html:2513–2520`): a sub-$100 final sweep on an `_amxHold` goal that
   is **not floor-safe** yields `safeAmt<=0 → defer → break` (`index.html:2531–2536`), which **stops the
   entire waterfall**, "starving every lower-priority goal all year." Lower-priority = wendy_ira (5),
   **bailey_529 (6)**, bryce_529 (7), preston_529 (8), …
3. Post-correction the durable snapshot is **7500.00** → `goalSaved['adam_ira']` starts complete →
   `rem0<0.005 → continue` (`index.html:2497`); adam_ira no longer sweeps or breaks → the cascade
   proceeds to wendy_ira / bailey_529 / … → **bailey_529 can now reach its 3500 target within 2026.**

**Therefore the audit's central question is not "why did Bailey 529 change" (mechanism identified) but
"is the RELEASE correct and bounded":** was the pre-correction block truly caused by the short snapshot
(and only that); is the released capacity real (no double-count with the open-window credit); does
bailey_529 reach exactly 3500 with no overfund; and did no other goal's completion week move
incorrectly. Classification for §9 pending that confirmation: **AMBIGUOUS / REQUIRES DECISION** (a
completed conclusion — and any `VERIFIED CORRECT` label — requires the §3.7 before/after diff + goal-by-
goal trace first).

## 3. Required audit scope

### 3.1 Baseline and causality
- Reconstruct pre- and post-correction model inputs. Confirm the **only material durable-input delta is
  adam_ira `7438.94 → 7500.00`** at wk6 (other eight wk6 snapshots byte-unchanged — closeout `other8_fp`).
- Quantify released capacity: is it just the 61.06 (single-week reallocation) or a **whole-cascade
  release** (the `break` at `index.html:2536`)? The trigger symptom (bailey_529 to 100%, target 3500 ≫ 61.06)
  implies a cascade release — confirm via the projected transfer log, week by week.
- Trace which week(s) changed and each dollar through the downstream waterfall (`index.html:2482–2560`).

### 3.2 Goal-by-goal projection (all 2026 waterfall goals + Taxable ETF participation check)
For each of Alaska, Wewe RCCL, Wewe DCL, Adam IRA, Wendy SEP, Wendy IRA, Bailey 529, Bryce 529, Preston
529, Bryce Vehicle, Christmas Cruise, Taxable ETF — report: **target · durable funded baseline (latest
snapshot) · open-week completed credit (`computeGoalTransferNetting`) · remaining · projected transfer
weeks+amounts · projected completion week · completes-in-2026? · why it changed (or didn't).**
Present as a deterministic table (financial values permitted **here** — essential to validate the math;
keep them out of balance-free status docs unless the doc rules permit).

### 3.3 Waterfall priority + allocation correctness (`index.html:1679–1690`, `2482–2560`)
Verify: exact priority order; `target_accumulation` vs `fixed_once` (the adam_ira seed `fixed_once`,
`index.html:2258/2593`; RCCL/DCL holding routing `2503–2508`); floor protection (`OP_FL`/`effFl`,
`amxSweepKeepsFloor` `1701`); MIN_XFR handling; **exact-final-transfer below MIN_XFR** (`allowFin`
`2549`; `_amxHold` completion carve-out `2521`); no lower-priority goal funded ahead of an eligible
higher one; completed goals release capacity (`rem0<0.005 continue`); deferred goals deferred for the
correct reason (`2523–2530`); **no capacity lost/created between weeks** (`remainingAdjustedSweep`
decrement `2547`).
- **Flag for decision:** the `break`-on-defer semantic (`2536`) means one stuck higher-priority
  `_amxHold` goal starves ALL lower goals. Combined with the open-window credit gap (B1), an un-credited
  executed transfer can silently block the whole cascade. Audit whether this is the intended semantic or
  a fragility the B1 fix must also address.

### 3.4 No duplication / overfunding
Verify completed transfers credited exactly once; reconciled snapshots not double-counted with
`weekly_tasks`; **open-window completed transfers not double-counted** — critically, that the snapshot
correction (which now embeds the `$61.06`) and `computeGoalTransferNetting` (which credits open-window
completions only for **unreconciled** weeks, `index.html:3349`) do **not both** credit the same `$61.06`;
cross-week recommendation movement cannot recreate an executed obligation (`resolveWeekTransfers`
identity, `index.html:3203`); no goal exceeds target (`rem0=max(0,…)` `2497/2552`); no transfer after
target reached; partial final transfer equals the exact remaining.

### 3.5 Snapshot / model integration
Trace latest-reconciled-snapshot selection; **how `source=correction` supersedes `source=reconciliation`**
(Option B in-place upsert on natural key `(model_year,week_num,goal_id)`, `docs/phase-5g-1d-migration.sql:428–439`
→ one wk6 row per goal; audit confirms the loader selects that single corrected row); how the model
obtains funded state (overlay `2624–2637`); open-window netting (`3280`); recalculation → future
recommendations; edited-week downstream effect (`saveWeekEdits` `3615`); whether the **8+1 wk6 partition**
(8 `reconciliation` + 1 adam_ira `correction`) is interpreted correctly everywhere that reads snapshots.

### 3.6 2026 / model-year boundaries
Verify `model_year` filtering (`PLAN_YEAR`, `isReservedAsOf` `1745`); calendar vs model week
(`getCalWeek`, model wk6 = Cal Wk 28); end-of-2026 cutoff; goals intended to continue into 2027
(taxable_etf); **what the UI "100%" means** — funded by year-end vs eventually vs over the full modeled
horizon; whether any goal is mislabeled a 2026 completion.

### 3.7 Before-vs-after comparison (deterministic)
Produce a machine-readable diff: pre- vs post-correction projections; changed goals; changed transfer
amounts; changed completion weeks; changed year-end %; the direct reason for every difference. **Do not
assume Bailey 529's new 100% is correct because the UI shows it.** Recommended mechanism: run the model
(read-only, local) against the pre-correction snapshot set (adam_ira=7438.94) and the post-correction set
(adam_ira=7500.00), diff the projected transfer logs.

### 3.8 Testing assessment
Identify existing coverage (waterfall/runModel tests in `test_regression.js`; e2e `5G1D-CO-*`,
`5G1B-NET-*`); missing unit/integration/E2E; deterministic regression cases; **whether current fixtures
reproduce the adam_ira→bailey_529 cascade** (a sub-MIN_XFR `_amxHold` gap that breaks the waterfall, then
a correction that releases it); tests required before ANY model change is accepted.

### 3.9 Finding classification (per §9 below)
`VERIFIED CORRECT` · `DEFECT` · `AMBIGUOUS / REQUIRES DECISION` · `TEST COVERAGE GAP` · `DOCUMENTATION
GAP`. Every defect: root cause · affected code/data paths · production impact · recommended fix boundary
· sequencing/dependencies · urgency.

## 4. Initial factual findings (grounded now; read-only)

- **F1 — Candidate mechanism identified (documented code behavior — level (a), not a correctness
  verdict).** The adam_ira→bailey_529 linkage runs through the `_amxHold` defer/`break` cascade
  (`index.html:2491`, `2510–2536`), gated by the snapshot overlay (`2637`). The control flow and the
  verbatim comment establish that this path *can* produce the observed linkage; they do **not** by
  themselves prove the Bailey 529 result is correct (that is §3.7).
- **F2 — If this mechanism is the cause, the release is whole-cascade, not 61.06 (hypothesis — level
  (b)).** A `break` of the entire lower-priority chain could move bailey_529 (and possibly
  wendy_ira/bryce_529/preston_529) materially, which would be consistent with the observed 100% — but
  "consistent with" is not proof. **Requires the §3.7 diff to confirm the cause, quantify, and bound.**
- **F3 — Double-count risk is bounded but must be checked (AMBIGUOUS).** Netting credits only
  **unreconciled** weeks (`index.html:3349`); wk6 is reconciled, so the corrected snapshot (embedding the
  `$61.06`) should be the sole source for wk6 — but the audit must confirm no open-week path re-credits
  the same `$61.06` for adam_ira post-correction (the Week-29 duplicate is gone per app verify, which is
  supporting evidence).
- **F4 — Taxable ETF excluded (VERIFIED CORRECT).** `stretch:true` → filtered out of the 2026 waterfall
  (`index.html:1680`); it should show no 2026 funding. Confirm the UI matches.
- **F5 — Fragility to flag (AMBIGUOUS / REQUIRES DECISION).** The `break`-on-`_amxHold`-defer plus the B1
  open-window credit gap means any un-credited executed open-window transfer on an `_amxHold` goal can
  silently stall the whole downstream plan. This is the same root as the Gate-4 duplicate and B1 (§14.6
  D5). Decide whether B1 must also make the model credit executed open-window transfers into projected
  funded state so the block cannot spuriously fire.
- **F6 — No code defect proven yet.** Nothing here is a confirmed DEFECT; the behavior is consistent with
  documented design. The open question is correctness/bounding of the release + the F5 fragility.

## 5. Open questions / decisions

1. Is Bailey 529's 2026 completion **bounded and exact** (reaches 3500, no overfund, exact-final-transfer
   correct), and does it hold across the full horizon (§3.7 diff)?
2. Did any **other** goal's completion week/amount change, and is each change explained by the same
   cascade release (no unexplained deltas)?
3. Is the **`break`-on-defer** semantic (F5) intended, or should B1 credit executed open-window transfers
   to prevent spurious cascade blocks? (Sequencing vs the already-scoped B1 work, §14.6 D5.)
4. Does "100%" in the Funding Plan mean by-year-end, and is that consistent for goals that legitimately
   extend into 2027?
5. Are the durable inputs truly identical except adam_ira (confirm `other8_fp` invariance is sufficient,
   and that no reconciliation-row or commitment change also moved)?

## 6. Recommendation on Fable independent review

**YES — route to Fable before any remediation.** Rationale: (a) the trigger touches the funding
waterfall + snapshot integration, the same subsystem as the funding-model-integrity review and the
5G-1A.5 MIN_XFR deadlock; (b) the leading hypothesis (a correction that appears to release a whole cascade)
is exactly the kind of "plausible but must be proven" result that warrants an independent adversarial
check before it's blessed or any B1 change ships; (c) F5 is a design decision, not just a bug. Recommend
Fable review **after** the §3.7 deterministic before/after diff is produced (so the review has the
mathematical evidence), and **before** any code change. This audit remains read-only until then.

## 7. Constraints honored

Read-only analysis + documentation only; no production writes; no SQL executed; no code/model change; no
silent corrections; not folded into the completed 5G-1D phase; exact repo references throughout; STOP-and-
report if repo state differs from §0.
