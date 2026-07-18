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

---

# PART II — Bounded investigations A/B/C + deterministic scenarios (added 2026-07-18)

**These three investigations (A/B/C) are kept SEPARATE from the waterfall conclusions (Part I / §D).**
Financial values appear here deliberately (this audit is the value-bearing home; the status/ledger docs
stay balance-free). All analysis below is read-only from committed code + committed evidence + the
LOCAL before-image (`~/Herndon-FOS-DB-Backups/…/week6-pre-freeze-before-image-2026-07-18.txt`). Where a
determination needs current production rows, the exact authorized read-only query is named — **no
production read was run.**

## 8. Investigation A — Week 23/24 lost task-completion state

**Model↔calendar mapping** (`getCalWeek`, `index.html:2723`): Cal Wk = model wk + 22 → **Cal Wk 23 = model
wk 1, Cal Wk 24 = model wk 2** (legacy pre-anchor weeks; the wrapper rejects closeout for wk 1–4,
`docs/phase-5g-1d-migration.sql:240`). These are reconciled legacy weeks under the §13 write-lock.

**Durable source of task completion.** `weekly_tasks` rows keyed `(week_num, task_idx)`, columns
`completed`, `completed_at`, `completed_amount`, `action_key`, `completed_label` (write path
`index.html:3520–3537`). Completion is **not** stored on the model row; the UI RESOLVES persisted
`weekly_tasks` rows against freshly re-derived model rows every render.

**Mechanism (grounded).** `resolveWeekTransfers` (`index.html:3203–3251`) binds a completed row to a
current model row through four identity tiers and **explicitly has NO positional fallback** (Tier 4,
`:3237` — *"legacy exact-label (null-key records), 1:1 unambiguous only; NO positional fallback"*):
- Tier 1 (`:3214`) exact `action_key` + exact `completed_label`;
- Tier 2/3 (`:3220`,`:3227`) unique / concordant `action_key`;
- Tier 4 (`:3237`) legacy null-`action_key` rows match **only** by exact `completed_label`, and **only**
  when exactly one current row and one record share that label.
A legacy Week 23/24 completion binds **only** if its `completed_label` still exactly equals a current
model-row label. The 5G-1D deploy (`bdcd1d7`) shipped the identity-strict resolver + open-window netting,
which **re-derive** the weekly model rows; if a Week 23/24 row's amount/label changed (or the legacy row
has a null/blank `completed_label`, `:3248` `kind:'legacy-executed'`), it no longer binds → the current
row renders **unchecked/actionable** and the completion drops to `executedHistory` as "legacy-executed".

**Is anything mutated?** `resolveWeekTransfers` is a pure read-only projection (returns a view object,
no fetch/write). The only 5G-1B write paths that PATCH `weekly_tasks` (`autoBackfillCompletedAmount`
`:3675`, `autoBackfillGoal` `:3726`) are **scoped to the edited week** (`week_num=eq.<weekNum>`), so a
Week-28 edit cannot alter Week 23/24 rows. No 5G-1D/Option-B path writes to weeks 1–2.

**Classification: IDENTITY / RESOLUTION DEFECT (display-layer).** This is the already-recorded
**5G-1D-HIST-1** regression (operator package §13; memory `open-week-duplicate-transfer-defect`).
Durable `weekly_tasks` rows are presumed **intact** (no write path targets weeks 1–2; the resolver is
read-only). It presents as unchecked because the identity-strict resolver cannot bind the legacy rows —
NOT because completion data was erased.

**To upgrade "presumed intact" → proven (authorized read-only query, NOT run):**
```sql
-- weeks 1 & 2 durable task state — compare to any before-image / prior capture
SELECT week_num, task_idx, completed, completed_amount, action_key, completed_label, completed_at
FROM public.weekly_tasks WHERE week_num IN (1,2) ORDER BY week_num, task_idx;
```
- If `completed=true` rows are present with intact `completed_label` → **DISPLAY / RESOLUTION DEFECT**,
  **zero rows require restoration** (fix is HIST-1: non-actionable rendering for reconciled weeks; never
  fabricate `action_key`; no backfill).
- If `completed` was flipped to false / `completed_label` nulled → **DATA MUTATION DEFECT**; the exact
  rows to restore would be enumerated from the diff (no before-image of weeks 1–2 exists locally, so this
  branch is currently **INSUFFICIENT EVIDENCE** without the read).

**Minimal proposed repair (NOT executed):** none to data under the display branch; ship HIST-1
(reconciled-week rows rendered non-actionable, completion shown from durable truth, open counts
corrected). Interim control already in force: §13 reconciled-week write-lock (do not check/uncheck weeks
1–5).

## 9. Investigation B — Week-28 "$843.51" Vio tax-reserve value

**Where `$843.51` is derived.** `getTaggedWD` (`index.html:1842–1863`) appends a **synthetic** event per
week when `ct>0` (`:1846`): `{ l:'Commission tax transfer — Vio Bank Tax Reserve (projected)', a:-ct,
cc:'tax_transfer', synthetic:true, eid: buildExpectedItemId(…'tax_transfer_vio'…) }` (`:1850`). Here
`ct = wd[5]` (`:1844`) = the model's **full projected Week-28 commission tax** = `40% × $2,108.78 (Deep
South) = $843.51`. It surfaces as a **Phase-2 reconciliation candidate** via `getPhase2WDCandidates`
(the `2026mw6_tax_transfer_vio_…` item recorded in `docs/phase-5g-1d-step8-reconciliation-discrepancy-…md`).

**Did a bank transfer of $843.51 occur? NO.** The executed Week-28 transfer is the completed
`commission_tax` task = **$425.68** (settles Mon 2026-07-20; closeout §5 / decision-log). Per operator
package **§14.5(A)** the `$843.51` synthetic candidate was **left UNANSWERED and NOT persisted** — the
frozen closeout payload carried **zero tax commitments** (one AMEX commitment only). So `$843.51` exists
**only** as a UI/model reconciliation candidate; it is neither a durable `cash_commitments` row, a durable
`weekly_tasks` amount, nor a bank movement.

**Components of $843.51.** `843.51 = 425.68 (executed) + 417.83 (correct Week-29 deferred remainder)` —
i.e., the full-week 40% projection. The candidate is "wrong" only in that it shows the **whole-week
projection** instead of the **unfunded remainder**; it does not represent a real or intended $843.51 move.

**Classification: MODEL / UI reconciliation candidate — durable state is CORRECT (no data defect).**
Downstream durable effect on Week-28 ending checking, Vio funded balance, Week-29 opening, and the goal
waterfall: **none** (nothing was persisted). The authoritative Week-28 tax reserve = the executed
**$425.68**.

**Confirming read-only queries (NOT run):**
```sql
SELECT week_num, tax FROM public.weekly_reconciliations WHERE week_num = 6;        -- Vio reserve balance captured at closeout
SELECT * FROM public.cash_commitments WHERE origin_model_week = 6 AND commitment_class LIKE '%tax%'; -- expect ZERO tax commitments
```
**Minimal fix (NOT executed):** B1 (§14.6 D5) — the synthetic tax candidate should read **total tax −
Σ completed executed legs** (→ show `$417.83` remainder, not `$843.51`), and derive `eid` from a
structured event date, not the label. No production repair required (nothing durable is wrong).

## 10. Investigation C — Week-29 "$365.32" tax-reserve transfer

**Formula + inputs producing $365.32.** The model sweeps commission tax **opportunistically** against
available surplus: `mv(ct,'tax')` / `mv(commTaxPending,'tax')` (`index.html:2367,2388–2396`), carrying
any unswept remainder forward as `commTaxPending` (`:2272,2373,2377`). Reducing the AMEX Gold outflow
`$5,718.52 → $5,666.01` (−$52.51) **freed $52.51 of Week-28 checking surplus**, so the Week-28 tax sweep
absorbed $52.51 more:
- Week-28 model tax `478.19 = 425.68 + 52.51` (the dual-basis line, operator package **§14.4**);
- Week-29 carry `843.51 − 478.19 = 365.32` (`= 417.83 − 52.51`).

**Authoritative obligation.** Total Deep-South commission tax = `40% × $2,108.78 = $843.51` (a fixed
40% rule; the obligation is **independent of cash/AMEX**). Executed Week-28 leg = `$425.68` (immutable).
**Correct Week-29 Deep-South remainder = `843.51 − 425.68 = $417.83`** — NOT `$365.32`, and NOT `$425.68`.

**Did the AMEX reduction change the obligation or only timing/derivation?** The **obligation is
unchanged** (`$843.51`). But the **scheduled Week-29 transfer** changed (`417.83 → 365.32`) because the
model **re-derives** the carry-forward from current surplus instead of anchoring it to the executed leg
(`total − Σ executed`). The AMEX cash change therefore perturbs a real projected tax transfer.

**Permitted-case test:**
- (a) obligation legitimately changed → **NO** (40% × fixed commission is unchanged).
- (b) obligation is `$425.68` and `$60.36` was pre-funded → **NO.** The `$60.36 = 425.68 − 365.32`
  framing compares the Week-29 display to the **Week-28 executed** amount; the correct Week-29 baseline is
  `$417.83`, so the real gap is **`$52.51` (= 417.83 − 365.32)**, exactly the AMEX reduction — not a
  pre-funding.
- (c) only `$365.32` is transferable due to a liquidity cap, `$60.36` carried forward → **NO.** `$365.32`
  is emitted as the *complete* re-derived remainder, not a liquidity-capped partial; the `$52.51` is
  **not** carried — it is silently dropped by the re-split.

**Classification: DEFECT (projection / carry-forward derivation) — FLAGGED per your criterion 5.** AMEX
payment size (available cash) directly changed the *scheduled tax transfer* via the opportunistic sweep;
the carry-forward is not anchored to the executed leg. This is the **B1-class** defect (§14.4: *"cash-side
edits never re-split an executed leg; carry = total − Σ completed executed legs"*). **Unpaid remainder:
YES — `$52.51` of Deep-South tax would be under-reserved and is not carried into a later week** if
`$365.32` executes as the sole Week-29 Deep-South leg.

**Quantified effect of B + C on the downstream waterfall.** B ($843.51): **zero durable effect**
(never persisted). C ($365.32): affects the **projection**, not durable data — a wrongly-low Week-29 tax
transfer **frees ~$52.51 more projected checking surplus** into the Week-29 goal waterfall (mildly
inflating projected goal funding), while leaving the tax reserve `$52.51` short. Correct treatment
(`$417.83` Deep-South + `$700.90` Extra BK Pay = `$1,118.73`, §14.5) removes `$52.51` of surplus from the
Week-29+ waterfall vs the current projection. **Minimal fix (NOT executed):** B1 — anchor the carry to
`total − Σ executed legs`; do not let a cash/AMEX edit re-split an executed tax leg.

## 11. Investigation D — deterministic scenarios S0–S3

### 11.1 Durable wk6 baseline (from the LOCAL before-image — the only material S0/S1 input delta)
Nine `goal_funding_snapshots` at model wk6 (source=reconciliation), funded amounts:

| goal | target | wk6 funded (S0) | wk6 funded (S1, post-Option-B) |
|---|---|---|---|
| alaska | 7000 | 7000.00 (complete) | 7000.00 |
| wendy_sep | 17859 | 17859.21 (complete) | 17859.21 |
| **adam_ira** | 7500 | **7438.94 (short 61.06)** | **7500.00 (complete)** |
| wendy_ira | 7500 | 0.00 | 0.00 |
| bailey_529 | 3500 | 0.00 | 0.00 |
| bryce_529 | 1500 | 0.00 | 0.00 |
| preston_529 | 1000 | 0.00 | 0.00 |
| bryce_vehicle | 8000 | 0.00 | 0.00 |
| christmas_cruise | 5000 | 0.00 | 0.00 |

(RCCL/DCL holding goals are tracked via the wk5 correction rows `600/500`, not in the nine.) **S0 and S1
differ only in adam_ira** — confirmed by the closeout `other8_fp=ddcce19d…` invariance.

### 11.2 Deterministic structural finding (no model run needed)
The active waterfall priority (§1) is `alaska(1) → rccl(2) → dcl(3) → adam_ira(4) → wendy_ira(5) →
bailey_529(6) → bryce_529(7) → preston_529(8) → bryce_vehicle(9) → christmas_cruise(10)`; `taxable_etf`
is `stretch`-excluded. Surplus cascades strictly top-down and, for `_amxHold` goals, a non-floor-safe
sub-MIN_XFR sweep **`break`s the whole chain** (`index.html:2510–2536`).

**Consequence — a hard ordering constraint the audit must check:** **bailey_529 (p6) cannot reach 100%
unless wendy_ira (p5) reaches 100% first.** So if S1 shows bailey_529 at 100% year-end, S1 **must** also
show wendy_ira at 100% year-end. Yet the app verification recorded *"Wendy IRA remains the valid next IRA
recommendation"* (i.e., wendy_ira is the CURRENT-week next, still funding). These reconcile **only** if
"100%" is a **year-end projection** (wendy_ira completes first at some wk X, bailey_529 later at wk Y≤
end-2026), not a current-week state. **If the projection shows bailey_529 = 100% year-end while wendy_ira
< 100% year-end, that is a PRIORITY-INVERSION DEFECT.** This is the single most important check in the
S0→S1 diff and is not yet proven.

### 11.3 Scenario definitions
- **S0** — recorded pre-Option-B state: adam_ira wk6 = `7438.94`.
- **S1** — current post-Option-B state: adam_ira wk6 = `7500.00`; everything else equal.
- **S2** — S1 with Week-28 tax reserve "corrected to $425.68." **Note:** the durable state already reflects
  `$425.68` (the `$843.51` was never persisted — §9), so **S2 ≡ S1 durably**; S2 differs from S1 only if
  one also corrects the model's *projected* Week-28 tax to `$425.68` (removing the §10 re-split), which is
  really the S3 concern.
- **S3** — S2 with the correct Week-29 tax treatment from §10: Deep-South leg `$417.83` (not `$365.32`) +
  Extra BK Pay `$700.90`, carry anchored to `total − Σ executed`. Effect vs S1/S2: **removes ~$52.51 of
  projected Week-29 surplus** from the goal waterfall.

### 11.4 What each scenario needs to be filled numerically (NOT yet produced)
The per-week table you requested (available cash · tax obligation · tax transfer · floor result · amount
into waterfall · per-goal allocation · completion week · year-end %) is a **deterministic function of
`runModel`** (`index.html` ~1755–2700) given the loaded inputs. It is **not producible without one of**:
1. **Authorized read-only production reads** of the current inputs `runModel` consumes — `goal_funding_
   snapshots` (all weeks), `weekly_reconciliations`, `weekly_tasks`, `cash_commitments` — then run the
   deployed model against S0/S1/S2/S3 input sets; **or**
2. a **validated local harness** that extracts `runModel` with those inputs injected (the model's weekly
   income/outflow schedule is hardcoded and deterministic, but the cash-availability engine also consumes
   loaded `cash_commitments` (`isReservedAsOf`, `:1738`), so before-image snapshots alone are
   insufficient).

**No fabricated numbers are recorded here.** The framework, inputs, and exact code path are fixed above so
the numeric fill is a mechanical next step once (1) or (2) is authorized. The **S0→S1 cascade mechanism**
(§2/F1/F2 + §11.2) is established; the **magnitude and the wendy_ira-before-bailey_529 ordering** are the
quantities to confirm.

## 12. Consolidated answers (report map)

1. **Week 23/24 unchecked tasks** — IDENTITY/RESOLUTION DEFECT (display-layer); the identity-strict
   resolver (no positional fallback, `:3237`) cannot bind legacy null-key/relabeled completions after the
   5G-1D deploy re-derived the rows; durable rows presumed intact (read-only resolver; no write path to
   weeks 1–2). Confirm intact vs mutated with the §8 query. = **5G-1D-HIST-1.**
2. **Week-28 $843.51** — the synthetic `getTaggedWD` projected commission-tax candidate (`:1850`) =
   `40% × $2,108.78`; never persisted (§14.5), no bank transfer; executed reality = `$425.68`. No durable
   defect; fix is cosmetic (B1).
3. **Week-29 $365.32** — **DEFECT, not correct and not a legitimate deferral.** AMEX `−$52.51` was
   opportunistically re-swept into Week-28 tax; correct Week-29 Deep-South leg = `$417.83`; `$52.51`
   silently under-reserved. B1-class.
4. **S0–S3** — framework + the durable baseline established; S2 ≡ S1 durably; numeric per-week fill needs
   authorized reads or a validated harness (§11.4); the wendy_ira→bailey_529 ordering is the key open
   quantity.
5. **Minimal fixes, execution order (NONE executed):** (i) confirm A durable-intact via the §8 read →
   ship **HIST-1** display fix (no data repair if intact); (ii) **B1** carry-forward + synthetic-tax fix
   (fixes both B display and the C `$365.32` defect) **before** the Week-29 tax legs are booked; (iii)
   no production data repair is indicated by B; C needs no *durable* repair (projection-only) but B1 must
   land before Week-29 executes to avoid the `$52.51` under-reserve.
6. **Tests required before any repair:** resolver fixture reproducing a legacy null-key/relabeled Week-1/2
   completion (A); a commission-tax fixture where an AMEX/cash edit must NOT change the executed-leg split
   (C, the §14.4 regression case named in D5); a deterministic S0-vs-S1 waterfall fixture that asserts
   wendy_ira completes before bailey_529 and both by year-end (D); a "no goal exceeds target / exact-final
   transfer" assertion across the cascade.
7. **Fable:** route A/B/C findings + the S0→S1 diff to Fable **before** any B1/HIST-1 implementation —
   same subsystem, and the priority-inversion check (§11.2) plus the C defect are exactly the adversarial
   questions an independent reviewer should confirm.

---

## 13. Evidence-collection log (read-only)

- **Evidence query authored:** `docs/phase-audit-2026-goal-funding-evidence-queries-2026-07-18.sql`
  (single-JSON, `BEGIN READ ONLY`). No evidence result has been produced yet.
- **v3 run attempt (2026-07-18) — FAILED SAFELY; NOT an evidence run.** The approved v3 read
  (SHA-256 `c541d8dc…5fc49`) errored at parse/analysis: `ERROR 42703: column "deleted" does not exist`.
  **Root cause = a schema-validation false assumption:** v3 referenced `model_week_overrides.deleted`
  as a physical column, inferred from `ov.deleted` reads in `index.html`. That inference was invalid —
  a JS `ov.<key>` read returns `undefined` for an absent key and therefore does **not** prove a physical
  column. No rows returned; **no write, no RPC, no evidence artifact, no evidence timestamp** (nothing to
  record — the transaction produced no result).
- **Correction — v4.** Verified the physical `model_week_overrides` columns from the **write payload**
  (`index.html:3641`: `week_num, events_json, ct, ca, is_custom, updated_at, dates`; `deleted` is not
  written and not physical). v4 references the verified columns directly and accesses `deleted`/`created_at`
  schema-tolerantly via `to_jsonb(m)->>'…'`. v4 SHA-256 `b328a09f728ad11d5488dd567a527bf296fab411fc454fbfc5983c1aca9c9ff8`.
- **Lesson recorded:** application field reads are not schema proof; physical columns are established only
  from DDL or the write payload (or `information_schema`), or accessed via null-safe `to_jsonb` extraction.
- **v4 run attempt (2026-07-18) — FAILED SAFELY; NOT an evidence run.** v4 (SHA `b328a09f…`) errored at
  analysis: `ERROR 42883: operator does not exist: text = text[]` — `goal_id = ANY((SELECT snap11 FROM sg))`
  treated the array-valued subquery as a set of `text[]` rows. Type-validation false assumption (an
  array CTE column is not a scalar set for `ANY`). No rows, no write/RPC/DDL, **no evidence artifact or
  timestamp**. Corrected in **v5**: `= ANY((SELECT array_col FROM cte))` → `IN (SELECT unnest(array_col)
  FROM cte)` at `snap_latest` + `reg`; the `comp_tasks` predicate already used the correct
  `IN (SELECT unnest(all12) …)` form. v5 SHA-256 recorded in the evidence message.

---

## 14. Remediation pointer (B1)

The Investigation-C calculation defect and the Investigation-D characterization requirements are carried
into remediation by **B1 — Commission-Tax Obligation Netting** (Fable REVISE → PROCEED 2026-07-18).
Authoritative design + regression matrix: `docs/phase-5g-1d-b1-commission-tax-netting-design-2026-07-18.md`.
This audit remains the read-only evidence/analysis home; B1 is the (not-yet-implemented) remediation home.
