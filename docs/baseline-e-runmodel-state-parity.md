# Baseline E — runModel & Application-State-Resolution Parity

**Status: LOCAL, UNCOMMITTED. Read-only. No live system touched. No capacity number computed.**
**Gate verdict (owner-ruled 2026-07-29): STATE PARITY PASS WITH BLOCKING BEFORE-LIVE CONDITIONS.**

> **Owner ruling (2026-07-29).** The state-parity evidence is accepted. On **S-1 the owner chose option (b)**: a
> flag-and-out-of-band handoff is a valid *detection* control but is **not sufficient** to permit a checking-capacity
> calculation. Before any capacity number, **every material off-model obligation must be converted into an
> authoritative capacity deduction** — either **(A)** promoted into an authoritative `cash_commitment`, or **(B)**
> included as an explicit Baseline E capacity adjustment carrying: stable synthetic/persisted identity, source
> account, amount, obligation type, effective date/interval, evidence reference, disposition, proof it is not already
> represented elsewhere, and deterministic inclusion in the reservation total. No material obligation may remain
> flag-only when capacity is calculated; Baseline E must **fail-stop or HOLD** if a material off-model obligation is
> detected but not converted; **no silent auto-promote/auto-reserve**. **Key distinction the owner drew:** *parity of
> the reservation LOGIC* (proven here) is separate from *completeness of the obligation INPUT SET* (not yet proven).
> The gate is reclassified to **STATE PARITY PASS WITH BLOCKING BEFORE-LIVE CONDITIONS** — safe to proceed to
> independent review and before-live-control design; **not** safe for capacity calculation. Baseline E was not changed;
> the controls live in the Baseline E live-input adapter + preflight layer and require no index.html change.

*(Pre-ruling recommendation was verdict 4 — FAIL-STOP for owner decision; the owner has now made that decision and set
the blocking before-live controls S-1..S-5 below.)*

> **Harness revision (owner-authorized 2026-07-30) — Fable D-1..D-4 REMEDIATED; S-6/S-7 ADOPTED.** The corpus grew to
> **88 fixtures**; the mutation suite is now **14 executable probes** (each runs through `runStateDifferential`); the
> reservation cross-product (6,912 cases, 0 mismatches) is **embedded** in the suite; the **unreconciled-branch
> commitment prefilter** (`index.html:3159-3172`) is **modeled** with the verbatim `isReservedAsOf` and covered by
> SP-59..SP-68; `chk:null` vs `chk`-missing are distinguished (SP-03 vs SP-69). Two new **blocking** controls were
> adopted: **S-6** obligation-set completeness attestation and **S-7** reserve-release clearing evidence. Full suite
> **197/197**. `capacity_calculation_eligible` remains **false**.

---

## 1. Starting-state verification (all PASS)
repo Adam-Dashboard · branch main · HEAD `36065ae96bc6d1f5a3084a95ae328199b01e7c18` · local==origin/main · tree clean ·
existing suite 150/150 · full suite 170/170 (pre-gate) · placement fingerprint `b856e74d…500e24` ·
index.html SHA-256 `162f4caa…20309c` · frozen A/B/C/D SQL unchanged · baseline-E/src unchanged · rev-6.1 unchanged.
No starting-state hard-stop.

## 2. Complete application dependency map (Phase 1)

### Capacity-input resolution surface (EXTRACTED + executed verbatim by the oracle)
| Function | index.html | Input shape | Output | Globals | Notes |
|---|---|---|---|---|---|
| `isWeekReconciled(weekNum)` | `:1043` | week int | bool | `reconData` | `!!(reconData[w] && chk!==undefined)` |
| `authoritativeCurrentChk(num, projectedChk)` | `:1756-1759` | week, projected | number | `reconData` | `rec.chk!=null ? rec.chk : projectedChk` |
| `isReservedAsOf(c, weekNum)` | `:2438-2451` | commitment, week | bool | `PLAN_YEAR` | 9-clause reservation predicate |
| `getCashAvailabilityEngine(actualCents, floorCents, commitments, source, week)` | `:2453-2463` | cents+list | `{raw,reserved,adjustedAvail,adjustedDeployable}` | — | source-filtered reserve sum |
| consts `OP_FL=6500,MIN_XFR=100` `:896` · `PLAN_YEAR=2026` `:902` · `START_*` `:889` | — | — | — | — | verbatim |

### Application projection logic (NOT extracted — documented boundary)
`runModel()` `:2967` is a forward WD cash-flow simulation over `reconEffectiveWD()` `:2949` (override-aware `WD`),
depending on dozens of globals (`WD`, `overrideData`, `budgetRules`, `GOALS_REGISTRY`, waterfalls, `actionOverrides`,
`PAYCHECK_WKS`, …). It produces the **projected checking** for unreconciled weeks. The capacity path reads it at:
- `:3156` `var _isReconciled=!!(reconData[num]);`  ← **engine reconciled-gate (object existence only)**
- `:3157` `var _actualChkForEngine=_isReconciled?reconData[num].chk:chk;`  ← **capacity actual-balance input**
- **`:3159-3172` commitment prefilter — TWO branches (D-3 MODELED):** the RECONCILED branch passes all
  source-matched `isReservedAsOf` commitments; the **UNRECONCILED** branch additionally requires
  `c.origin_model_week<num` (strict) AND (`_reconciledWeekNums[c.origin_model_week]` OR
  `c.commitment_source==='historical_repair'`) — the carry-forward/double-reserve guard (`_reconciledWeekNums`
  built at `:3006-3007`). The adapter now models **both** branches (`prefilter()` in `state-adapter.mjs`), calling
  the **verbatim extracted `isReservedAsOf`** as the reservation core; SP-59..SP-68 cover origin-reconciled /
  unreconciled / historical_repair / strict-origin / model_year / mixed / voided / not-affects. app==be over the
  unreconciled branch on all of them, so `modeled_surface_parity=true` now spans both branches. (The branch wrapper
  is modeled once from the verbatim source — it is loop-body code, not a standalone function, so exact function
  extraction is infeasible; the reservation core it calls IS verbatim, and the app-vs-BE independence is the
  reservation predicate.)
- `:3173-3176` engine call; `:3177` `adjustedAvailableForSweep=_cae.adjustedDeployableSurplusCents/100`
- `:3178-3185` review flags (`_reviewRequired = _hasActiveReserves && (_balanceBasisUnknown || _hasBankPendingReserve)`)
- `:3337-3342` a SEPARATE later block sets *displayed* balances (`chk=rec.chk…`) — display/carry-forward, NOT the engine.

### Reconciled-truth overrides
`reconData` `:944`, loaded from `weekly_reconciliations` (`:3492/3497`, `:9856/9872`) as
`{week_num:{chk,sav,amx,tax,lc,balance_basis,date}}`. `balance_basis ∈ {posted_current_balance, available_balance,
unknown, null}` (`:2593`). Reconciled `chk` overrides projected for the engine's actual-balance input.

### UI-only / non-capacity (proven, agent-verified)
- **Register transactions** (`_txLedgerCache` `:7498`, `transactions` table): **display/persistence only** — never read by
  `runModel`/`getCashAvailabilityEngine`/`authoritativeCurrentChk`/reconciliation. Cleared/uncleared aggregation exists
  only in `_computeLedgerBalances` for the on-screen balance column. No `transfer_pair_id` anywhere. No dedup.
- **customTaskData** (`:1366`, `custom_tasks` table): task-list + persistence only; `:3899` "customTaskData is
  intentionally NOT scanned here". Never a capacity input.
- Week immutability: `_weekIsImmutable(n)` `:4448-4451` = `isWeekReconciled(n) || n <= _anchorBoundaryWeek()`
  (boundary = 5, `:4041`); 7 write-guards; owner-only `deleteRecon` `:3731` (gated by `canDeleteRecon` `:3714`).

### Obligations ABSENT from runModel
- Off-model custom-task obligations (e.g. BKX-style tax reserve) — **not reserved**.
- Uncleared Register obligations — **not a capacity input**.
- Transfer-leg linkage — **no `transfer_pair_id`**, no pairing, no double-entry into capacity.

**No guessing required; the dependency graph isolates cleanly. No Phase-1 hard-stop.**

## 3. Application precedence rules (Phase 2)
- **A. Checking used by the model:** engine actual-balance = `reconData[num].chk` if `!!(reconData[num])` else projected
  `chk` (`:3156-3157`). **Caveat (grounded):** the engine gate `!!(reconData[num])` is *looser* than `isWeekReconciled`
  (`chk!==undefined`) and than display guards (`chk!=null`) — a `chk:null` row is engine-reconciled and yields
  `round(null*100)=0` → capacity zeroed. [explicit application behavior / **known gap**]
- **B. Transactions:** Register is display-only; not aggregated into capacity; single signed `amount`; account = selected
  `account_key`; no transfer-pair; no dedup. [explicit application behavior]
- **C. Reconciliations:** reconciled overrides projection for the engine input; sole required field = present `chk`;
  duplicate `week_num` → silent last-write-wins (`:3497`); `balance_basis='unknown'` raises review **only** with active
  reserves (`:3185`). [explicit application behavior; last-write-wins & null-chk = **known gaps**]
- **D. Commitments:** reserved iff `isReservedAsOf` (model_year=PLAN_YEAR; origin≤week; affects_deployable_cash;
  not voided-status; not voided/paid_from_other_account resolution; not reflected≤week; resolved null or >week) AND
  `source_account===source`. [explicit application behavior — Baseline E matches exactly on the reservation
  PREDICATE] **Projected-branch guard (D-3 MODELED):** on an UNRECONCILED week runModel ALSO requires
  `origin_model_week<num` (strict) AND (origin week reconciled OR `commitment_source==='historical_repair'`)
  before a commitment enters the reserve set (`:3159-3172`) — a carry-forward/double-reserve guard now modeled by
  the adapter's `prefilter()` and covered by SP-59..SP-68 (including `commitment_source==='historical_repair'`).
- **E. Custom tasks / off-model:** **not** in runModel; do **not** reserve capacity; become modeled only if promoted to a
  `cash_commitment`. BKX-style reserves live only in `custom_tasks`. [**known gap / intentional difference**]
- **F. Retained horizon:** model band weeks 1..31; obligations with `origin_model_week>week` excluded by the reservation
  origin-gate; incomplete/non-exhaustive historical evidence is **not** represented in runModel. [**known gap**]

## 4. Oracle design
`baseline-E/state-parity/app-state-oracle.mjs` — reads index.html, **fail-closed-enforces the pinned hash** (reuses
`assertIndexHtmlIntegrity`), then brace-matches and executes the four verbatim resolvers + verbatim constant lines via
`new Function('PLAN_YEAR','reconData', …)` bound per-fixture. No network/Supabase/writes/clock/timezone. The full WD
projection is intentionally **not** re-derived; projected checking is an explicit input (matching how runModel passes
`chk` into the engine) — the gate tests state RESOLUTION, not projection.

## 5. Adapter design
`baseline-E/state-parity/state-adapter.mjs` — canonical synthetic fixture → (A) app resolvers and (B) an **independent**
Baseline-E-side (`beIsReserved` reimplemented from scratch + rev-6.1 fail-closed dispositions). Deterministic rejection
of malformed/incomplete/duplicate/ambiguous structure. No real ids/UUIDs/balances.

## 6. Fixture inventory — 88 synthetic `SP-01..SP-88`
- **SP-01..SP-50** resolution corpus (reconciliation precedence & basis, cleared/uncleared, transfers, commitment
  matrix, custom-task/off-model, floor boundary, immutability, horizon, duplicate/conflict, malformed, week-31, combined).
- **SP-51..SP-58 (D-2):** reservation-clause coverage — model_year mismatch, resolution_type voided /
  paid_from_other_account, resolved>week / resolved≤week, reflected>week / reflected==week / reflected<week.
- **SP-59..SP-68 (D-3):** unreconciled-branch prefilter — origin reconciled / unreconciled / historical_repair /
  strict-origin-equal / model_year mismatch / mixed / multiple reconciled origins / admitted-but-voided /
  historical_repair-not-affects / no-commitments.
- **SP-69 (D-4):** reconciliation row with the `chk` key ABSENT (distinct from SP-03 `chk:null`).
- **SP-70..SP-78 (S-6):** obligation-set attestation — complete / verified_empty / failed_fetch / partial / malformed /
  silent_empty / unattested / rls_filtered / schema_mismatch.
- **SP-79..SP-88 (S-7):** reserve-release evidence (modeled reflected/resolved paths) — reflected-no-evidence /
  valid-linkage / cleared-before-reflect / duplicate-linkage / amount-mismatch / source-mismatch /
  paid_from_other+evidence / voided+evidence / stale / one-txn-multi-obligation.
- **SP-89..SP-100 (C-1 terminal-resolution S-7):** voided-res-no-evidence / voided-status-no-evidence /
  voided-valid-evidence / paid_from_other-no-evidence / paid_from_other-valid-evidence / wrong-evidence-type /
  stale-terminal / duplicate-terminal-evidence / contradictory-status-resolution / both-weeks-null-valid-evidence /
  release-week-present-same-rule / one-evidence-multi-commitment.
- **SP-101..SP-107 (S-7 evidence-TYPE hardening):** voided evidence type-absent / blank-type / unsupported-type;
  paid_from_other type-absent / unsupported-type; valid-typed-void; valid-typed-alternate-payment.

## 7. Differential results (Phase 6) — TZ-invariant, repeatable
**88 fixtures: 59 EXACT_MATCH · 26 INTENTIONAL_CONTROL_DIFFERENCE · 3 APPLICATION_GAP (2 MATERIAL) · 0 BASELINE_E_DEFECT · 0 ADAPTER_DEFECT.**
The independent BE reservation predicate equals the verbatim app `isReservedAsOf` on **all 88** fixtures (reserved
cents, reserved-commitment lists, AND prefilter eligibility match everywhere). **Scope (D-2/D-3 remediated):** parity
is now proven over **both** the reconciled-week AND the unreconciled-week (prefilter) commitment surfaces; full-clause
parity is **embedded** (6,912-case cross-product, 0 mismatches). `modeled_surface_parity=true` now covers both branches.
(Total fixture count reflects 88; the earlier 50-fixture summary of 35/12/3 is superseded by 59/26/3.) Classification is byte-identical across UTC/America-New_York/Asia-Kolkata
(no date logic in the resolution surface) and repeatable. Machine-readable: `baseline-E/state-parity/state-parity-results.json`.

| Class | Fixtures |
|---|---|
| EXACT_MATCH (35) | SP-01,02,04,05,07,09,10,11,12,15,18,19,20,21,22,23,24,25,26,28,29,30,32,33,34,35,36,37,38,39,40,45,47,48,49 |
| INTENTIONAL_CONTROL_DIFFERENCE (12) | SP-03 (null-chk HOLD), SP-06 (unknown-basis review), SP-08 (uncleared informational), SP-13/14/16 (transfer no pair), SP-17 (transfer mismatch), SP-41 (horizon incomplete), SP-42 (unknown account fail-stop), SP-43 (duplicate recon fail-stop), SP-44 (conflicting recon fail-stop), SP-46 (malformed amount fail-stop) |
| APPLICATION_GAP (3) | SP-27 (off-model task), **SP-31 (MATERIAL — BKX-style)**, **SP-50 (MATERIAL — combined)** |

## 8/9. Exact mismatches, gaps, and classification
There are **no capacity-number mismatches** on the shared resolution surface. Every non-EXACT disposition is either
Baseline E being *safely stricter* (never understates an obligation, never overstates capacity) or the application
*omitting an off-model obligation*:
- **INTENTIONAL_CONTROL_DIFFERENCE** — source: *undocumented/uncontrolled application behavior* made safe by Baseline E.
  null-chk → BE HOLD (app zeroes); duplicate/conflicting recon → BE fail-stop (app last-write-wins); malformed/negative
  amount → BE fail-stop (app would inflate capacity via a negative reserve, SP-46); unknown account → BE fail-stop;
  unknown basis → BE review (app gates review on active reserves); uncleared register → BE informational (both exclude
  from capacity); transfer no-pair/mismatch → BE flag (app has no transfer-pair concept). Baseline E unchanged.
- **APPLICATION_GAP** — source: *application gap* (customTaskData excluded from runModel, `:3899`). SP-27 non-material;
  **SP-31 and SP-50 material** (BKX-style tax reserve). Baseline E flags them (`BE_OFF_MODEL_OBLIGATION_FLAG`) for
  out-of-band handoff — it does **not** silently omit — but it also does not auto-reserve them.

## 10. Reconciliation-precedence results
Reconciled overrides projected (SP-02/39); projected when unreconciled (SP-01); null-chk edge escalated (SP-03);
duplicate/conflict fail-stopped by BE (SP-43/44). **PASS** (with the null-chk / last-write-wins gaps registered).

## 11. Cleared/uncleared results
Register cleared *and* uncleared are excluded from capacity on both sides (SP-07..12); BE additionally flags uncleared
checking debits as informational (SP-08). **PASS** (shared exclusion; BE stricter flag).

## 12. Transfer results
No transfer-leg linkage or double-entry into capacity on either side; BE flags missing `transfer_pair_id` (SP-13/14/16)
and amount mismatch (SP-17); paired legs clean (SP-15/32). **PASS** (BE stricter).

## 13. Commitment results — clause coverage COMPLETE (D-2 remediated)
Reservation matrix EXACT over the fixture set; **all 9 `isReservedAsOf` clauses now have dedicated fixtures**
(SP-51..SP-58 add model_year mismatch, resolution voided / paid_from_other_account, resolved>week / resolved≤week,
reflected>week / reflected==week / reflected<week; SP-19 affects-false; SP-24 source mismatch). A **6,912-case
cross-product** parity test (`beIsReserved` vs the verbatim extracted `isReservedAsOf`, **0 mismatches**) is now
**embedded and executed in the suite** (repository proof; the earlier Fable 6,912/0 result is independent
corroboration). Independent predicate == verbatim `isReservedAsOf` on all 88 fixtures. **PASS (full-clause parity,
executable).**

## 14. Custom-task & off-model-obligation results
runModel omits customTaskData entirely; BE flags off-model obligations. SP-27 (non-material), **SP-31/SP-50 (material)**.
→ **Phase-7 HARD STOP: application omits a material obligation.**

## 15. Retained-horizon results
Origin-gate excludes `origin_model_week>week` (SP-26); after-horizon evidence excluded both sides (SP-49); BE flags
incomplete retained horizon (SP-41). **PASS** (BE stricter on completeness).

## 16. Operating-floor boundary results
Exact floor → 0 (SP-34); one cent below → 0 (SP-35); one cent above → 1 cent (SP-36). **EXACT both sides.**

## 17. Mutation results (Phase 8) — 14 EXECUTABLE probes (D-1 remediated)
Each mutation now injects a real control break via the adapter's `mut` hook and runs THROUGH `runStateDifferential`;
each produces a deterministic degraded classification (or state-resolution field divergence for M14), verified
repeatable. Baseline → mutated:
| # | Control broken | Fixture | base → mutated |
|---|---|---|---|
| M1 | remove off-model detection | SP-31 | APPLICATION_GAP → EXACT_MATCH |
| M2 | auto-model custom task | SP-31 | APPLICATION_GAP → BASELINE_E_DEFECT |
| M3 | incomplete horizon → exhaustive | SP-41 | INTENTIONAL → EXACT_MATCH |
| M4 | allow duplicate recon | SP-43 | INTENTIONAL → EXACT_MATCH |
| M5 | allow conflicting recon | SP-44 | INTENTIONAL → EXACT_MATCH |
| M6 | unknown basis authoritative | SP-06 | INTENTIONAL → EXACT_MATCH |
| M7 | bypass reconciliation precedence | SP-02 | EXACT_MATCH → BASELINE_E_DEFECT |
| M8 | incorrect uncleared handling (fold into reserve) | SP-08 | INTENTIONAL → BASELINE_E_DEFECT |
| M9 | double-count transfer | SP-15 | EXACT_MATCH → BASELINE_E_DEFECT |
| M10 | ignore open commitment | SP-18 | EXACT_MATCH → BASELINE_E_DEFECT |
| M11 | include voided commitment | SP-22 | EXACT_MATCH → BASELINE_E_DEFECT |
| M12 | wrong source account | SP-24 | EXACT_MATCH → BASELINE_E_DEFECT |
| M13 | cross the operating floor by one cent | SP-34 | EXACT_MATCH → BASELINE_E_DEFECT |
| M14 | immutable week → mutable | SP-37 | week_immutable true → false |
| M15 | restore C-1 escape (terminal release without evidence) | SP-89 | INTENTIONAL → EXACT_MATCH |
| M16 | restore untyped-evidence escape (terminal evidence w/o a type) | SP-101 | INTENTIONAL → EXACT_MATCH |
`executable_mutation_coverage_complete = true` in the machine-readable result. The four **extracted verbatim
resolvers** (the app oracle) are never mutated (ground truth); mutations break the Baseline-E side or a shared
control. M14 mutates `app.weekImmutable`, which is an **adapter-modeled** field (documented rule `isWeekReconciled(n)
|| n≤5`, anchor boundary 5 per `index.html:4041`) — not one of the extracted resolvers — producing a state-resolution
field divergence the differential surfaces.

## 18. Test totals (after D-1..D-4 + S-6/S-7 + C-1 closure + evidence-type hardening)
Existing 150/150 (unchanged) · placement-parity 20/20 · **state-parity 31/31** (107 fixtures; embedded 6,912-case
cross-product; 16 executable mutations incl. the C-1 terminal-resolution escape and the untyped-evidence escape) ·
combined **201/201**, 0 fail/skip/todo. Differential: **65 EXACT · 39 INTENTIONAL_CONTROL_DIFFERENCE · 3 APPLICATION_GAP
(2 MATERIAL) · 0 defects**; TZ-invariant + repeatable.

## 19. Files created (all local, uncommitted)
`baseline-E/state-parity/{app-state-oracle,state-adapter,state-fixtures,state-differential,run-state-parity}.mjs` +
`state-parity-results.json`; `baseline-E/test/state-parity-differential.test.mjs`; `docs/baseline-e-runmodel-state-parity.md`.

## 20. Working-tree status
Only the above untracked (plus this doc). Nothing staged/committed/pushed. index.html/frozen SQL/baseline-E/src/rev-6.1 unchanged.

## 21. Verdict (owner-ruled)
**STATE PARITY PASS WITH BLOCKING BEFORE-LIVE CONDITIONS.** The capacity-resolution surface Baseline E relies on —
reconciled-vs-projected precedence, the commitment reservation predicate, deployable-surplus math, and the floor
boundary — is in **full parity** (59 EXACT of 88; reservation predicate + prefilter identical on all 88, both branches,
0 defects), and Baseline E is *safely stricter* on every edge case (HOLD/fail-stop/flag) without ever understating an
obligation. **Parity of the reservation LOGIC is proven; completeness of the obligation INPUT SET is NOT.** Per the
owner ruling (S-1 option b), live capacity is prohibited until the blocking before-live controls §BLOCKING (S-1..S-7)
are proven against LIVE evidence in the Baseline E live-input adapter + preflight layer. `modeled_surface_parity=true`, `obligation_set_complete=false`,
`capacity_calculation_eligible=false`. This verdict is safe to proceed to independent review and before-live-control
design; it authorizes nothing operationally — no production/staging, no live Baseline E, no capacity calculation, no
Wendy-IRA determination, no transfer. Operational HOLD remains active.

## §BLOCKING. Mandatory before-live controls (owner-set 2026-07-29) — all must be proven before any live capacity result
- **S-1 Off-model obligations (option b):** every material off-model obligation converted into an authoritative capacity
  deduction — (A) promote to `cash_commitment`, or (B) explicit Baseline E capacity adjustment with stable identity +
  source account + amount + obligation type + effective date/interval + evidence reference + disposition +
  not-already-represented proof + deterministic inclusion in the reservation total. Flag-only insufficient; Baseline E
  fail-stops/HOLDs on detected-but-unconverted; no silent auto-promote/auto-reserve.
- **S-2 Null checking reconciliation:** a `chk` that is null/missing/malformed/non-finite must never be authoritative —
  fail-closed or explicit unresolved-evidence HOLD; must NOT silently produce a zero actual balance.
- **S-3 Duplicate/conflicting reconciliation rows:** detect multiple rows per model week; identical duplicates explicitly
  classified; conflicting values fail-stop; last-write-wins unacceptable for Baseline E capacity evidence.
- **S-4 Invalid commitment amounts:** reject negative/malformed/non-finite/unsupported; zero-dollar explicitly classified
  and capacity-neutral; no negative reservation may increase deployable surplus.
- **S-5 Uncleared Register items:** material uncleared checking debits/credits reconciled against posted balance /
  available balance (if available) / pending-bank evidence / duplication with commitments-or-transfers before capacity;
  no silent ignore or double-count; unresolved material uncleared debits require HOLD.
- **S-6 Obligation-set completeness attestation (adopted 2026-07-30):** before capacity, positively attest the
  obligation input is complete and successfully loaded. No fetch/parse failure may default to an authoritative empty
  set; console warning insufficient; empty set requires affirmative attestation. Distinguishes verified-empty /
  complete (proceed) from failed_fetch / partial / malformed / rls_filtered / schema_mismatch / silent_empty /
  unattested (→ HOLD). `obligation_set_complete` + `capacity_calculation_eligible` stay false until it passes. Load
  source, row count, query scope, identity/visibility proof, integrity result recorded. Fixtures SP-70..SP-78;
  contract in `state-adapter.mjs:obligationSetAttestation`.
- **S-7 Reserve-release clearing evidence (adopted 2026-07-30; C-1 escape closed):** a reserve must not be released
  by ANY path — `reflected_model_week`, `resolved_model_week`, OR a **terminal-resolution exclusion**
  (`status='voided'` / `resolution_type ∈ {voided, paid_from_other_account}`, even with both release weeks null) —
  without durable, consistent supporting evidence. Non-overlapping paths: durable `cleared_transaction_id` (amount+source
  metadata required), paid_from_other_account with `alternate_payment` evidence, or voided with `void_cancellation`
  evidence. **Terminal-resolution evidence requires BOTH a non-empty `resolution_evidence` AND an explicit supported,
  consistent `resolution_evidence_type` — untyped evidence is NOT accepted** (absent/blank type →
  `S7_TERMINAL_EVIDENCE_TYPE_MISSING`; unsupported/inconsistent → `S7_TERMINAL_EVIDENCE_WRONG_TYPE`). Missing / stale /
  duplicate / contradictory evidence, or amount/source mismatch → HOLD; one evidence item must not release multiple
  commitments. A terminal status/resolution field ALONE never bypasses the check. Fixtures SP-79..SP-107; contract in
  `state-adapter.mjs:reserveReleaseEvidence`.

These controls are implemented in the Baseline E live-input adapter and preflight layer; no index.html change required.

## 22. Independent Fable review — verdict 3 (REVISE), now REMEDIATED
First review completed 2026-07-29: verdict **3 — REVISE STATE-PARITY EVIDENCE OR CONTROLS** (substantive conclusions
endorsed; 6,912-case cross-product corroboration, 0 mismatches). **Owner-authorized remediation (2026-07-30) applied:**
- **D-1 REMEDIATED** — 14 executable mutations through `runStateDifferential` (§17); `executable_mutation_coverage_complete=true`.
- **D-2 REMEDIATED** — SP-51..SP-58 clause fixtures + embedded 6,912-case cross-product test (0 mismatches); `reservation_clause_coverage_complete=true`.
- **D-3 REMEDIATED** — unreconciled-branch prefilter modeled with verbatim `isReservedAsOf`; SP-59..SP-68; `unreconciled_prefilter_parity=true`.
- **D-4 REMEDIATED** — SP-69 chk-missing (NaN) distinct from SP-03 chk:null (0); both BE HOLD.
- **D-5 → S-6 ADOPTED; D-6 → S-7 ADOPTED** (blocking controls).
Focused Fable **re-review DONE (2026-07-30): verdict 2 — APPROVE WITH NON-BLOCKING CONDITIONS.** D-1..D-4 confirmed
genuinely remediated (mutations executable — independently spot-checked; 6,912-case cross-product re-run 6912/0;
prefilter faithful line-by-line to `:3159-3172`; chk:null vs missing correct); S-6 sufficient for the synthetic
harness with its residual disclosed. Three conditions, none blocking this evidence commit:
- **C-1 (Medium) — CLOSED (owner-authorized 2026-07-30).** The original escape: a commitment released purely by
  terminal resolution (`status='voided'` / `resolution_type ∈ {voided, paid_from_other_account}`) with
  `reflected_model_week` AND `resolved_model_week` both null skipped the evidence check (the `continue` in
  `reserveReleaseEvidence`), so a voided/paid commitment with no supporting evidence passed silently. **Enforcement
  added:** `reserveReleaseEvidence` now treats terminal-resolution exclusions as release events on ALL paths (even
  with both release weeks null) and REQUIRES consistent supporting evidence — `resolution_evidence` with a matching
  `resolution_evidence_type` (`void_cancellation` / `alternate_payment`); missing → `S7_TERMINAL_RESOLUTION_NO_EVIDENCE`,
  wrong type → `S7_TERMINAL_EVIDENCE_WRONG_TYPE`, stale → `S7_STALE_RESOLUTION`, contradictory status/resolution →
  `S7_CONTRADICTORY_STATUS_RESOLUTION`, one evidence item across multiple commitments → `S7_DUPLICATE_CLEARING_LINKAGE`;
  a bare `cleared_transaction_id` without amount+source metadata → `S7_CLEARING_METADATA_MISSING`. Fixtures SP-89..SP-100
  (SP-22/SP-52/SP-66 supplied valid evidence to remain clean predicate tests). Executable mutant **M15** (`c1Escape`)
  restores the escape and is caught deterministically (SP-89 INTENTIONAL→EXACT). `c1_terminal_resolution_escape_closed=true`.
- **C-2 (Low) — CORRECTED.** Stale passages fixed: §3.D (now MODELED), §7 headline (59/26/3), §21 (88/both-branches).
- **C-3 (Low/cosmetic) — CORRECTED.** §17 M14 wording clarified; `M10 dropAffects` noted as a decorated constant-false predicate.

### Focused C-1 re-glance residuals (post-CLOSED)
The C-1 re-glance (disposition **CLOSED**; adversarial 1,112-case second-escape hunt found none) disclosed two
non-blocking residuals:
- **Residual (a) — CLOSED (owner-authorized 2026-07-30): S-7 evidence-TYPE hardening.** Untyped `resolution_evidence`
  was accepted if an evidence item existed. Tightened: terminal-resolution evidence now requires a non-empty
  `resolution_evidence` **AND** a supported, consistent `resolution_evidence_type` (`void_cancellation` / `alternate_payment`),
  else HOLD (`S7_TERMINAL_EVIDENCE_TYPE_MISSING` / `S7_TERMINAL_EVIDENCE_WRONG_TYPE`). Fixtures SP-101..SP-107;
  executable mutant **M16** (`untypedEvidenceEscape`) restores the escape and is caught (SP-101 INTENTIONAL→EXACT).
  `s7_evidence_type_required=true`, `s7_untyped_evidence_escape_closed=true`. All shipped valid-release fixtures carry
  explicit supported types.
- **Residual (b) — DEFERRED (cosmetic, non-blocking).** The new S7 codes classify INTENTIONAL via the differential
  fall-through rather than being listed in `STRICTER`; no behavioral gap (SP-101 classifies INTENTIONAL correctly).

## Gap / mismatch register (now BLOCKING before-live controls per owner ruling)
| # | Item | Type | Owner-set disposition (mandatory before live capacity) |
|---|---|---|---|
| S-1 | customTaskData / BKX-style off-model obligation omitted from runModel | application gap (material) | **BLOCKING — convert to authoritative deduction (option b); fail-stop/HOLD if unconverted** |
| S-2 | Reconciled-gate `!!(reconData[num])` looser than `isWeekReconciled`. Two distinct cases (D-4): `chk:null` → `round(null*100)=0` (silent **zero** balance; note `isWeekReconciled` is *true* here since `null!==undefined`); `chk`-**missing** key → engine gate true but `round(undefined*100)=NaN` (BE typeof/finite check covers both) | undocumented app behavior | **BLOCKING — null/missing/malformed/non-finite chk never authoritative; fail-closed/HOLD; no silent zero or NaN balance** |
| S-3 | Duplicate/conflicting `weekly_reconciliations` rows → silent last-write-wins | undocumented app behavior | **BLOCKING — detect; duplicates classified, conflicts fail-stop; no last-write-wins** |
| S-4 | Negative/malformed commitment amount inflates capacity via negative reserve (SP-46) | undocumented app behavior | **BLOCKING — reject; zero-dollar capacity-neutral; no negative reservation** |
| S-5 | Uncleared Register obligations not a capacity input | intentional difference / shared exclusion | **BLOCKING — reconcile material uncleared vs bank/pending/commitments before capacity; HOLD on unresolved material debits** |
| S-6 | Silent empty/degenerate obligation load (`index.html:9891` `commitmentData=[]` + console.warn) | undocumented app behavior | **BLOCKING — affirmative completeness attestation; any uncertain load HOLDs (SP-70..78)** |
| S-7 | Premature reserve release on `reflected_model_week` without clearing evidence | modeled-state-vs-actual drift | **BLOCKING — durable clearing evidence or HOLD; no double-release (SP-79..88)** |

All seven are implemented in the Baseline E **live-input adapter + preflight layer** (no index.html change). The gate
proves reservation-LOGIC parity (both branches) + input-COMPLETENESS controls; capacity remains ineligible until they
are proven against LIVE evidence (a separate authorized gate). Fable D-1..D-4 remediated; S-6/S-7 adopted.

## Independent Fable review (2026-07-29) — verdict: 3 REVISE STATE-PARITY EVIDENCE OR CONTROLS
The state-parity evidence was independently reviewed (read-only). The reviewer **endorses the substantive
conclusions** — reservation-LOGIC parity (independently corroborated by a **6,912-case cross-product**, 0 mismatches),
the S-1 option-(b) ruling, `capacity_calculation_eligible=false`, and the SP-31/SP-50 material-omission escalation —
but returned **REVISE** on the evidence artifacts. Findings (doc-halves corrected above; code-halves pending owner
authorization):
- **D-1 (Medium):** 10 of 14 mutation probes are not executed mutants (MUT-8/9/10/13 tautological; MUT-1/2/3/4/7/14
  analytic). §17 corrected; rewrite pending authorization.
- **D-2 (Medium):** 4 of 9 reservation clauses lack dedicated fixtures. §13 corrected; add fixtures + embed the
  cross-product test.
- **D-3 (Medium):** unreconciled-branch commitment prefilter (`:3159-3172`) unmodeled. §2/§3.D/§7 corrected + claim
  scoped to the reconciled-week surface; model both branches + add fixtures.
- **D-4 (Low):** `chk:null` (→0) vs `chk`-missing (→NaN) distinction. S-2 register corrected; add a NaN fixture.

### Candidate additional before-live controls (OWNER DECISION — not yet adopted)
Two residual paths the reviewer flags as not fully closed by S-1..S-5:
- **S-6 (candidate) — obligation-set completeness attestation.** A silent empty/degenerate commitment load
  (`index.html:9891` sets `commitmentData=[]` with only a `console.warn` on fetch failure) would overstate capacity by
  the entire reserve total. Proposed: the preflight must positively attest the commitment/obligation input is complete
  and non-degenerate (row-count/coverage attestation; an empty set must be affirmatively attested, never defaulted).
- **S-7 (candidate) — premature `reflected_model_week` release.** A commitment with `reflected_model_week<=week` releases
  its reserve on the assumption the outflow already cleared; if it has not, capacity is overstated. Proposed: such a
  commitment must carry clearing evidence (e.g. the AU-11 durable `cleared_transaction_id`) or HOLD.
These are offered for the owner to adopt as S-6/S-7 or decline; Baseline E unchanged pending that decision.
