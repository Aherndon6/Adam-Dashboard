# 2027 Rollover Package B: year-neutral client hardening

| | |
|---|---|
| Governing specification | `docs/rollover-2027-spec.md`, frozen v2.1 (commit `9949225`) |
| Base | Package A, `8220621` |
| Contracts | T-SNAP-1 (C11), T-TR-4 (C23), T-TR-5 (C24), X-C18 (C18) |
| Scope | Client only (`index.html`, unprotected functions). No server, SQL, schema, RLS, grants or data. No protected function changed (49/49 pins match). The 2026 golden is unchanged. |
| OWNER HOLD | ON (`GOAL_FUNDING_OWNER_AUTHORITY` = `NOT_AUTHORIZED`, unchanged) |

## 1. Method

Each contract was written RED against the unchanged Package A product, then the smallest product change turned it green, and the registry entry was set ACTIVE with its `impl` reference. `node tools/rollover-contracts.js complete B` exits 0.

## 2. C11: complete or fail closed (T-SNAP-1)

**Loader.** `_c11LoadTable(h, table, select, label)` loads `goal_funding_snapshots` and `cash_commitments` for every plan year, the same way the Register ledger load does:

1. A fingerprint request takes the exact row count (Content-Range, `Prefer: count=exact`) and the newest `updated_at`.
2. Keyset pages (`id=gt.<cursor>`, `order=id.asc`) run until that count is loaded. A server row cap smaller than the request size just means more pages.
3. A second fingerprint must match the first.

The load fails closed if any of these happen:

| Condition | Status | Reason shown |
|---|---|---|
| A page or fingerprint returns HTTP error, a non-array body, or throws | `error` | `HTTP <status>` or the error |
| The exact count is missing | `incomplete` | the exact … count was not available |
| Fewer rows than the count, a duplicate or out-of-order id, or no forward progress | `incomplete` | loaded X of Y … / inconsistent … pagination |
| The fingerprint changes during the load (retried once) | `incomplete` | … changed while loading |
| The table is missing (404) | `unavailable` | … table is not available |

The protected `_txParseContentRangeTotal` is called, not changed.

**Snapshot rows.** Every row is kept in `goalSnapRows` with `id`, `model_year`, `week_num`, `goal_id`, `funded_amount`, `source`, `note` and `created_at`. Rows are keyed by (`model_year`, `week_num`, `goal_id`), so plan-2026 and plan-2027 rows at week 30 stay distinct. `source` keeps opening anchors, reconciliations and corrections apart. A malformed row, or two rows with one key, makes the whole load incomplete.

`goalSnapData`, the flat week-to-goal projection that the protected readers and `runModel` use, still holds `PLAN_YEAR` rows only. This is exactly what the old loader requested (`model_year=eq.PLAN_YEAR`), so 2026 model behavior is unchanged. Plan-scoped selection beyond this is Package D.

**Nothing partial.** On any failure, `goalSnapRows`, `goalSnapData` and `commitmentData` are cleared, including any earlier complete load, and the status and reason are set.

**Dependent surfaces (fail closed, reason shown):**

- **Goals.** Every Goals sub-tab shows the reason and no goal amounts when either load is incomplete.
- **Overview.** Both Next Dollar sites and the Capital Allocation Queue show the reason instead of goal-funding output when either load is incomplete.
- **Goal recommendations (G1).** `g1ResultForWeek` returns UNAVAILABLE (`goal_history_unavailable` or `commitments_unavailable`) when either load is incomplete. Every goal transfer then shows "Withhold: model check unavailable", and the write guard refuses it whatever the owner authority. Both are real dependencies: snapshots anchor each goal's funded amount in `runModel`, and commitments cap the goal sweep.
- **Closeout.** `canPersistReconNow` returns false and `reconSaveBlockedReason` gives the reason, whether snapshots or commitments failed to load.
- **Commitment visibility.** `renderCommitmentVisibility` states that commitments are unavailable.

**Not changed (outside B).** Commitment consumers keep their `PLAN_YEAR` filters; `isReservedAsOf` is protected and belongs to Package D (C9). `runModel` still runs when a load fails, but nothing that depends on the missing evidence is shown as a model answer (section 6, item 2).

## 3. C23 and C24 (T-TR-4, T-TR-5)

- **C23.** While owner authority is not `AUTHORIZED`, both rendered Next Dollar sites in `renderOverview` carry `(modeled, not authorized)` from `modelSweepCaveat()`. `getNextDollarRec` is unchanged (pin `6a3b9678…`).
- **C24.** `_renderEngineOutput` adds "Informational only. Not authorized while OWNER HOLD is on (before Gate F)." while authority is not `AUTHORIZED`, and labels the tax step "(Legacy 40% rule, not current household tax policy)". `runEngine` is unchanged; T-TR-5 compares its steps and amounts with the base commit. Correcting the 40% rule is follow-on F-1.

## 4. C18 (X-C18)

Frozen v2.1 defines C18 as: pin the current week in the clock-dependent test; test only.

The product label logic (`_fundingWhenLabel`) is pure and never reads the clock. The failure came from the `5G1C1-12` fixture: it built its funding data from `getCurrentWeek()`, so from 2027-01-03 (week 31) it held no projected funding and the label assertion failed on correct output.

`5G1C1-12` now uses `const _cw=18;`. X-C18 runs the legacy suite at 2026-12-27, 2027-01-02, 2027-01-03 and 2027-01-10. `PKGA-CLOCK-4` is converted from reproducing the defect to proving its closure: the label renders at every boundary date, `_fundingWhenLabel` reads no clock, and the old week-31 fixture had no projected funding.

## 5. Test changes outside the four contracts

- **Legacy harness load state.** `test_regression.js` sets `_goalSnapLoadStatus` and `_commitmentLoadStatus` to `loaded`, which represents completed zero-row loads. Without it, five legacy tests ran in the never-loaded state that C11 now gates.
- **Two intentional C11 expectation changes** in `test_regression.js`:
  - the `reloadReconAndCommitments` source test now expects the all-years C11 load;
  - `5G1D-P04-16` now checks the C11 status mapping and apply behavior.
- **`test_a1b.js` G8 (Package A harness repair).** The Package A clock stub binds the product's `Date` in the suite's scope. G8 replaced only `global.Date`, so at the default 2026-10-07 pin it passed only because the pinned month happened to be October, and it failed from 2026-12-27. G8 now sets both bindings, and snap/restore saves both. It passes at every boundary date because the test, not the pin, controls the clock.
- **e2e closeout fixture (`5G1D-CO-*`).** The two reload stubs returned one body for every query, with no count header and no row ids, so the C11 loader correctly refused them (CO-1, CO-5 and CO-6 failed). They now answer like PostgREST: exact count, keyset pages, the fingerprint query, and the stored columns the real table always has. The scenario rows and every assertion are unchanged, and the negative scenarios (CO-7, CO-8, CO-9) still hold.
- **`PKGA-DONE-6`** derives the expected completion state from the registry.

## 6. Findings for owner review

1. **Completion gate.** `complete <PKG>` checks registry status and test definitions, not test results; the pre-push hook enforces green. Owner ruling 2026-10-07: no change.
2. **Model under a failed load (resolved, owner-approved B3).** With a $3,000 reservation loaded, the $7,500 Wendy IRA transfer is withheld (it would breach the floor). With the commitment load failed, the model swept that $3,000 into goals and G1 returned NO_MODEL_OBJECTION. With the snapshot load failed, the model forgot a funded goal and G1 approved funding it again. Goals, Overview and G1 are now unavailable in both cases (T-SNAP-1 (f) and (g)). Projected Checking is not gated: it is not more optimistic than the loaded answer.
3. **Fingerprint residual.** The change check is the row count plus the newest `updated_at`, the same as the accepted ledger pattern. Both tables set `updated_at` on every write by trigger. An undetected change would need a delete plus a back-dated insert in the same pass.
4. **C18 wording.** Owner ruling 2026-10-07: approved as test-only. Frozen v2.1 says test only, and the product logic is already clock-independent.

## 7. Package A record

`docs/rollover-package-a.md` is left as the record of Package A at its completion. Package B supersedes three of its statements:

- the C18 note and the section 4 row: `PKGA-CLOCK-4` no longer reproduces the defect; it proves the closure (section 4 above);
- the section 2 current-state line: Package B is COMPLETE, and `PKGA-DONE-6` derives the expected state from the registry.
