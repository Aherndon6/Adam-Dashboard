## ⟲ REISSUE v4 — 2026-07-15 (write-path + read-path identity closure + commission-posting gate; supersedes v3)

**Why:** Fable's delta review returned four more blocking findings, now fixed adapter-only at commit **`4ce6aff`**:
**B1** (Edit-Week commission-tax backfill) and **B2** (goal-sweep backfill) now select the completed row by
**persisted identity** (own `action_key`), never by display position, so a foreign completed row (e.g. Adam
IRA) can never be rewritten/re-armed; **B3** (Overview/chip/History completion reads) derive completion from
resolver identity, not positional `taskData` reads; **B4** adds an explicit commission-posting hard gate (§2c).
Frozen surfaces byte-unchanged (`runModel`, waterfall, commission-tax calc, `resolveWeekTransfers`,
`computeGoalTransferNetting`); 0 `.sql`.

**Repinned baseline (authoritative — supersedes v3 below):**
| Item | v4 (authoritative) |
|---|---|
| Activation-lineage anchor | correction commit **`4ce6affb113e9d8efa28a8c4b807bcd8547cc43f`** MUST be an ancestor of HEAD — `git merge-base --is-ancestor 4ce6aff HEAD`; **do NOT pin the final tip hash** |
| `index.html` identity gate | `git rev-parse HEAD:index.html` == **`a4c458af2c9c53a67ceb621dd4d8c9c48d6343a2`** |
| `BUILD_TS` (pre-activation) | **`2026-07-15T20:52:49`** |
| Static regression | **1543 / 0** |
| Full `node e2e.js` | **155 / 0 / 0** (readiness 0/0; clean first run) |
| Readiness fallbacks | **0 / 0** |
| `origin/main` | `5bd6c69787bee7a8fe26ee1fb2ceb0528526d6f1` (unchanged) |

The §1 table, §9 start block, step tables, and the **§2c commission-posting gate** below are updated to these
v4 pins. The v3/v2 banners are retained as history.

---

## ⟲ REISSUE v3 — 2026-07-15 (identity-resolution correction; supersedes v2 pins)

**Why:** a second preactivation blocker was fixed — the positional `applyCompletionSnapshots` / `_trAmts`
task_idx aliasing that erased the Week-28 **`$425.68`** commission-tax task (an executed Adam IRA `$61.06`
completion at the colliding task_idx). Fixed **adapter-only** (identity-resolved completion normalization
+ commission-tax write amount) at commit **`fd5d7a1`**. Frozen surfaces byte-unchanged (`runModel`,
`resolveWeekTransfers`, `computeGoalTransferNetting`, commission-tax calc); 0 `.sql`.

**Repinned baseline (authoritative — supersedes v2 below):**
| Item | v3 (authoritative) |
|---|---|
| Activation-lineage anchor | correction commit **`fd5d7a1e09864f16efb9e6be992b141f301f44a3`** MUST be an ancestor of HEAD — `git merge-base --is-ancestor fd5d7a1 HEAD`; **do NOT pin the final tip hash** |
| `index.html` identity gate | `git rev-parse HEAD:index.html` == **`6804711de4b520389fdca3dbbd52b7462ebc2279`** |
| `BUILD_TS` (pre-activation) | **`2026-07-15T19:51:00`** |
| Static regression | **1533 / 0** |
| Full `node e2e.js` | **153 / 0 / 0** (rerun; the initial run's 2 failures were headless `clickNav` flakes, cleared with no code change) |
| Readiness fallbacks | **0 / 0** |
| `origin/main` | `5bd6c69787bee7a8fe26ee1fb2ceb0528526d6f1` (unchanged) |

The §1 table, §9 start block, and step tables below are updated to these v3 pins. The v2 banner that
follows is retained as history (v1 → v2 → now v3).

---

## ⟲ REISSUE v2 — 2026-07-15 (supersedes the original pins below)

**Why:** the mandatory pre-activation **open-window executed-transfer netting/suppression control**
(`docs/phase-5g-1b-openwindow-netting-2026-07-15.md`) changed the app commit, so the original package
pins are stale and **must not be reused**. This banner is authoritative where it conflicts with the
v1 body below.

**Repinned baseline (authoritative):**
| Item | v1 (superseded) | **v2 (authoritative)** |
|---|---|---|
| Activation-lineage HEAD | `7f0f47d` | **`15b372fc94b35ac46a8b9af40375055a66ad1f7f`** (correction commit) |
| `BUILD_TS` (pre-activation) | `2026-07-11T17:26:14` | **`2026-07-15T13:01:24`** |
| Static regression | 1507 / 0 | **1526 / 0** |
| Full `node e2e.js` | 148 / 0 / 0 | **151 / 0 / 0** |
| Readiness fallbacks | 0 / 0 | **0 / 0** |
| `origin/main` | `5bd6c69` | `5bd6c69` (unchanged) |

**Branch reconciliation (Adam decision — REQUIRED before Saturday):** the correction commit `15b372f`
currently sits on `docs/canonical-roadmap-revision-2026-07-14` (a linear descendant of the preactivation
lineage; app code was byte-identical to `7f0f47d` before this commit). Before Saturday, the activation
branch `claude/herndon-5g-1d-preactivation-j428vn` must be advanced/reconciled to `15b372f` (fast-forward
or cherry-pick), and the §9 start block + §1 table's branch/HEAD/BUILD_TS `expect` values updated to the
v2 pins above. **Do not run §9 as written against the old remote tip.**

**Added pre-activation steps (v2) — see §2b for detail; they slot into the §2 checklist as noted:**
1. **PRODUCTION PRECHECK (read-only, before Approval Gate 1)** — confirm the open-window Adam IRA
   execution state (exactly one completed $61.06; no second duplicate; `action_key` + `completed_amount`
   populated; no ambiguous legacy row). **No production mutation.**
2. **PRE-CLOSE DUPLICATE SCAN (read-only, at step 7 live-browser verify)** — the deployed build must
   show **no enabled Adam IRA PLANNED checkbox** in any open week; the executed $61.06 shows "Satisfied
   by completed transfer" / "Executed earlier"; console clean.
3. **WEEK-6 CUMULATIVE VALUE (at step 8 frozen-payload review)** — the confirmed Adam IRA cumulative
   funded value **must include the executed $61.06** (i.e. reflects the real AMEX IRA-holding balance),
   so the wk6 snapshot anchors funded state correctly.
4. **POST-CLOSE VERIFICATION (at step 10 durable-state verify)** — after the wk6 closeout + reload,
   confirm **zero later-week Adam IRA recommendations** (the snapshot boundary advanced; the netting
   control steps back to the durable snapshot).

**Release condition (Adam, unchanged):** this control must be implemented, independently reviewed, and
fully green before the Saturday production baseline is authorized. If it cannot meet the bar in time,
**the affected Saturday activation slips** — do not silently revert to the v1 package.

---

# Phase 5G-1D — Saturday Gate B Operator Package (single-sitting execution)

**Purpose:** the one document to operate Gate B + 5G-1D completion from, end to end, in a single
controlled sitting. Everything needed is here; you should not have to reconstruct the sequence from
other files mid-execution. Authoritative detail lives in
`docs/phase-5g-1d-gateb-activation-runbook-2026-07-13.md` — this is its execution front-end.
**Balance-free. Nothing here is executed by reading it.**

---

## 1. Opening state verification (confirm ALL before doing anything)

| Item | Expected |
|---|---|
| Feature branch | `claude/herndon-5g-1d-preactivation-j428vn` (advanced to the final docs-only reconciliation commit via fast-forward) |
| Activation-lineage anchor | correction commit `4ce6aff` **MUST be an ancestor of HEAD** — `git merge-base --is-ancestor 4ce6aff HEAD`. **Do NOT pin the final tip hash**; the final tip is the docs-only reconciliation commit. |
| `index.html` identity gate | `git rev-parse HEAD:index.html` == `a4c458af2c9c53a67ceb621dd4d8c9c48d6343a2` |
| `origin/main` | `5bd6c69787bee7a8fe26ee1fb2ceb0528526d6f1` (must stay unchanged until the merge step) |
| Working tree | CLEAN (`git status --porcelain` empty) |
| `BUILD_TS` (pre-activation) | `2026-07-15T20:52:49` (unchanged until the deploy step) |
| Production project | **Adam-Dashboard**, ref **`usayoldrawwmjsmretin`**, `system_identifier 7632885393857617092`, `app_environment` ABSENT |
| Week mapping | **model `week_num = 6` = calendar Week 28** (`getCalWeek(6)=28`); the first closeout persists `week_num = 6` |

**Authoritative runbook + SQL files (all committed at HEAD above):**
- Runbook: `docs/phase-5g-1d-gateb-activation-runbook-2026-07-13.md`
- Read-only: `docs/phase-5g-1d-gateb-adjunct-preflight.sql`, `docs/phase-5g-1d-activation-grants-validation.sql`
- Mutating (grants): `docs/phase-5g-1d-activation-grants.sql` (Phase 1), `docs/phase-5g-1d-activation-revokes.sql` (Phase 2)
- Rollback: `docs/phase-5g-1d-activation-grants-rollback.sql` (grant rollback, two scopes), `docs/phase-5g-1d-rollback.sql` (Slice-6 DROP — not expected in Gate B)
- Browser: `index.html` (closeout + row-9 guard + response validation + open-window transfer netting + identity-resolved completion normalization + identity write-selection/read (B1–B3); verified gate static **1543/0**, e2e **155/0/0**, readiness **0/0**)
- DR floor: the Slice-6 restore point `5G-1D-slice6-restorepoint-20260713T222223Z.dump` (local + encrypted off-device). *The adjunct preflight (step 2) confirms production has not been written since 07-13, so this dump is still a valid pre-Week-6 DR floor. A fresh same-sitting `pg_dump` (Slice-6 runbook §2 procedure) is OPTIONAL belt-and-suspenders — recommended if any doubt.*

---

## 2. One-page execution checklist (in order — 🛑 = STOP for explicit Adam approval)

```
[ ]  1. RE-GROUND ............... §9 start block: branch, 4ce6aff is-ancestor + index.html blob a4c458a…, clean tree, origin/main, BUILD_TS 2026-07-15T20:52:49, files
[ ]  2. ADJUNCT PREFLIGHT (RO) .. gateb-adjunct-preflight.sql → wk5 9/2/11; recon 5 rows wks1-5; snaps@wk>=6 = 0
[ ]  3. PRE-PHASE-1 VALIDATION .. activation-grants-validation.sql (+ consolidated query) → 17/17 pass; inert; MD5s; owner
━━ 🛑 APPROVAL GATE 1 — Adam authorizes PHASE 1 GRANTS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[ ]  4. PHASE 1 GRANTS (MUTATING) activation-grants.sql → wrapper+Option B authenticated EXECUTE granted
[ ]  5. POST-GRANT VALIDATION ... activation-grants-validation.sql → wrapper/Option B authenticated=T, anon=F; owner unchanged; bodies unchanged
━━ 🛑 APPROVAL GATE 2 — Adam authorizes BUILD_TS STAMP + MERGE + DEPLOY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[ ]  6. BUILD_TS STAMP + MERGE → DEPLOY ... stamp BUILD_TS; merge feature → main; GitHub Pages build green; BUILD_TS advances live
[ ]  7. LIVE-BROWSER VERIFY (pre-write) ... fresh session renders; closeout-state badges; confirmation view opens; console clean; DO NOT submit
━━ 🛑 APPROVAL GATE 3 — Adam authorizes the REAL Week-6 (calendar Week 28) CLOSEOUT ━━━━━━━━━━━━━━━━━━
[ ]  8. FROZEN PAYLOAD REVIEW ... enter Week-28 actuals → confirmation view → confirm the nine funded values (frozen)
[ ]  9. WEEK-6 CLOSEOUT (WRITE) . "Confirm & close week" → wrapper returns {ok:true,mode:normal_closeout,week_num:6,snapshot_count:9}
[ ] 10. DURABLE-STATE VERIFY .... 3 ways (returned count=9; REST read 9 rows source=reconciliation; overlay "Closeout complete"); + capture LOCAL balance-bearing before-image (for Proof A; runbook §4 step 5)
[ ] 11. ▲▲▲ WEEK-6 FREEZE ACTIVE (see §7) — begins at closeout success, holds through Proof B ▲▲▲
━━ 🛑 APPROVAL GATE 4 — Adam authorizes PHASE 2 REVOKES (only after Week-6 durably complete) ━━━━━━━━━
[ ] 12. PHASE 2 REVOKES (MUTATING) activation-revokes.sql → hard-stops unless wrapper granted, old RPC still granted, owner unchanged, Week-6 = 1 recon + 9 source=reconciliation snaps
[ ] 13. FINAL GRANT VALIDATION .. activation-grants-validation.sql → wrapper/Option B=T; old recon/repair/snapshot RPC=F; tables INS/UPD/DEL=F, SELECT=T; anon all=F; owner+bodies unchanged
[ ] 14. POST-PHASE-2 BROWSER VERIFY (see §3a) — FRESH: new session shows new BUILD_TS, closeout uses the wrapper, tabs render, console clean, wrapper callable, Option B owner-gated | STALE: a cached/pre-deploy tab's old-RPC call FAILS CLOSED (denial), no false success, no optimistic state, ZERO rows/timestamps written, clear error/reload prompt
[ ] 15. PROOF A (NON-MUTATING) .. wrapper idempotent re-submit of exact Week-6 payload → branch-F identity; before/after equal; NEVER force
[ ] 16. PROOF B (NON-MUTATING) .. old-RPC probe, all named args incl. both JSONB, p_model_year=9999 → denial or "invalid model_year: 9999"
[ ] 17. ▲▲▲ RELEASE WEEK-6 FREEZE (only after BOTH proofs pass) ▲▲▲
[ ] 18. FINAL TEST SUITE (LOCAL)  node test_regression.js (1543/0) ; node e2e.js (155/0/0, fallbacks 0/0)
[ ] 19. CLOSEOUT EVIDENCE + STATUS updates (docs: CODEX_STATUS, phase-status, AGENTS refresh, activation closeout evidence)
[ ] 20. FINAL COMMIT + PUSH ..... docs-only --no-verify; feature branch; (merge to main already done in step 6)
```

---

## 2b. v2 ADDED PRE-ACTIVATION STEPS (2026-07-15) — netting-control gates

These are **additive** to the §2 checklist; run them at the slots named. All are read-only except the
normal closeout itself.

**PRECHECK (read-only; before 🛑 Approval Gate 1).** In the Supabase SQL Editor, production
Adam-Dashboard (`usayoldrawwmjsmretin`), run:
```sql
-- READ-ONLY. Open-window Adam IRA execution state (no mutation).
select week_num, task_idx, action_key, completed, completed_amount,
       (completed_label is not null) as has_label
from public.weekly_tasks
where action_key = 'goal_adam_ira' and completed = true and week_num > 5
order by week_num, task_idx;
```
- **Expect:** exactly **one** completed row; `completed_amount` **equals the executed Adam IRA residual**
  (the $61.06 top-up) and is **non-null**; `action_key` populated; `has_label = true`.
- **Hard stop** if: more than one completed row (a real second execution → investigate, do not close out
  over it); `completed_amount` null/unrecoverable, or a legacy row with null key/label affecting
  `goal_adam_ira` attribution (the control would BLOCK — resolve the row before activation, never force).
- **No mutation.** If the row set is unexpected, STOP and reconcile the data first.

**PRECHECK — unattributable-rows scan (read-only; same slot).** The Adam-IRA-specific query above cannot
detect a completed open-window row that has NO durable attribution. Also run:
```sql
select *
from public.weekly_tasks
where completed = true
  and week_num > 5
  and (
    action_key is null
    or completed_amount is null
  );
```
- **Expect: zero rows.** Any completed open-window row missing `action_key` or `completed_amount` is
  unattributable — the netting control would BLOCK (fail closed).
- **Hard stop** if any row is returned: STOP and **require investigation**. **Do NOT authorize cleanup or
  any mutation** from this package; resolve the row's provenance first, then re-run the precheck.

**PRE-CLOSE DUPLICATE SCAN (read-only; at step 7 live-browser verify, before Approval Gate 3).** On the
deployed build (new `BUILD_TS`), open the current + next open weeks (Cal Wk 28/29) and confirm:
- **No enabled Adam IRA PLANNED checkbox** in any open week (the executed residual renders as
  "Satisfied by completed transfer", and/or the completion shows under "Executed earlier");
- console clean; the executable "Transfers to execute X/Y" count does **not** include the satisfied row.
- **Hard stop** if any enabled Adam IRA duplicate checkbox appears, or a "Review required" (blocked) row
  is present → do not close out; investigate attribution.

**WEEK-6 CUMULATIVE VALUE (at step 8 frozen-payload review).** When confirming the nine funded values,
the **Adam IRA cumulative funded value must include the executed $61.06** — i.e. it reflects the real
AMEX IRA-holding balance after the top-up, so the wk6 snapshot anchors funded state at (≈) the $7,500
target. If the entered value omits the executed residual, **Go Back and correct** before submitting.

**POST-CLOSE VERIFICATION (at step 10 durable-state verify).** After the wk6 closeout succeeds and both
halves reload, confirm on the deployed build:
- the wk6 snapshot for `adam_ira` reflects the cumulative funded value (incl. the $61.06);
- **zero later-week (Cal Wk 29+) Adam IRA transfer recommendations** remain (the snapshot boundary
  advanced; the netting control has stepped back to the durable snapshot);
- no "Satisfied"/"Executed earlier" Adam IRA row is needed in future weeks (there is no recommendation to
  suppress).
- **Hard stop** if a later-week Adam IRA recommendation reappears → the anchor did not absorb the
  execution; do NOT run Phase 2 revokes; investigate.

## 2c. v4 COMMISSION-POSTING HARD GATE (2026-07-15) — before the $425.68 transfer and before closeout

**Trigger:** whenever a Week-28 commission-tax transfer or the Week-28 closeout is contemplated.

**HARD GATE — the Wendy Deep South commission ($2,108.78) must be POSTED and available in Truist Checking.**
- "Processed", "pending", or provisional does **NOT** count — confirm posted/cleared, available cash.
- **Do NOT execute the $425.68 commission-tax transfer** until the deposit is posted.
- **Do NOT perform the Week-28 closeout** until ALL of the following hold:
  1. the $2,108.78 commission is **posted** in Truist Checking;
  2. the **$425.68** Truist Checking → Vio Bank - Tax Reserve transfer has been **executed** against posted funds;
  3. the correct Week-28 **`commission_tax`** task is marked complete (persists `commission_tax / 425.68 / correct label`);
  4. the **$417.83** Week-29 remainder remains intact (exactly one deferred commission-tax task).
- **HARD STOP:** if the commission has **not** posted → do not transfer, do not close Week 28. Delaying the
  closeout is covered by the approved activation contingency annex (roadmap §7), **not** a new correction.

**Rationale (proven, balance-free):** the $843.51 obligation is preserved across a closeout via the persisted
Edit-Week override (`ct=843.51`) + the model's `commTaxPending` carry-forward — not lost, not reduced to
$417.83, not doubled; but closing before the deposit posts leaves a large first-anchor variance and a
past-week $425.68 execution. Wait for posted funds.

## 3. Exact file + command map (per step)

| # | Step | File / action | R/W | Runs in | Expected success | Hard-stop |
|---|---|---|---|---|---|---|
| 1 | Re-ground | §9 block | RO | Local terminal | `4ce6aff` is-ancestor of HEAD, `index.html` blob a4c458a…, tree clean, origin/main=5bd6c69, BUILD_TS 2026-07-15T20:52:49 | Any mismatch |
| 2 | Adjunct preflight | `gateb-adjunct-preflight.sql` | RO | Supabase SQL Editor | `ADJUNCT PREFLIGHT PASS`; 3 rows = §4 values | Any RAISE EXCEPTION / different row |
| 3 | Pre-Phase-1 validation | `activation-grants-validation.sql` + §consolidated query | RO | Supabase SQL Editor | 17/17 `pass=true`; inert; MD5s; owner postgres | Any `pass=false` |
| 4 | Phase 1 grants | `activation-grants.sql` | **WRITE (grants)** | Supabase SQL Editor | `ACTIVATION GRANTS PASS`; COMMIT | HARD STOP notice; env≠production; unexpected pre-grant (c_resume=false) |
| 5 | Post-grant validation | `activation-grants-validation.sql` | RO | Supabase SQL Editor | wrapper/Option B authenticated=T, anon=F; owner invariant; bodies unchanged | anon=T; owner drift; body md5 changed |
| 6 | BUILD_TS + merge → deploy | git + GitHub Pages | **WRITE (repo/deploy)** | Git/GitHub | `pages-build-deployment` green; live BUILD_TS advances | Pages build fails; BUILD_TS not advanced |
| 7 | Live-browser verify | dashboard.herndons.us | RO | Browser | render unchanged; badges; confirmation view opens; console clean | Any render/console error; guard build absent |
| 8 | Frozen payload review | app confirmation view | RO (pre-write) | Browser | nine funded values shown; expected-9; joint-commit warning | Invalid/NaN value; disabled Confirm |
| 9 | Week-6 closeout | wrapper POST | **WRITE (1 recon + 9 snaps, atomic)** | Browser | `{ok:true,mode:normal_closeout,week_num:6,snapshot_count:9}` | GFA01/adjudication; domain reject; ambiguous; unconfirmed 2xx (stays on confirm) |
| 10 | Durable-state verify | REST read + overlay | RO | Browser / SQL Editor | 9 rows `source=reconciliation` at wk6; badge "Closeout complete"; no half-close | count≠9; wrong source; partial/half-close |
| 12 | Phase 2 revokes | `activation-revokes.sql` | **WRITE (grants)** | Supabase SQL Editor | `LOCKDOWN REVOKES PASS`; COMMIT | Any pre-lockdown assert (wrapper not granted / old RPC already revoked / Week-6 not durable / owner drift) |
| 13 | Final grant validation | `activation-grants-validation.sql` | RO | Supabase SQL Editor | final matrix (§4 post-Phase-2); owner+bodies unchanged | Any deviation |
| 14a | Post-Phase-2 FRESH browser | dashboard.herndons.us (new session/hard refresh) | RO | Browser | new `BUILD_TS`; closeout uses wrapper; tabs render; console clean; wrapper callable; Option B owner-gated | old BUILD_TS; wrapper not callable; render/console error |
| 14b | Post-Phase-2 STALE browser | cached/pre-deploy tab (old direct-RPC path) | **NON-MUTATING** (fails closed) | Browser/REST | old-RPC call denied (401/403/404); no false success; no optimistic state; **ZERO** rows/timestamps written; clear error/reload | any 2xx; false success; optimistic state; ANY row/timestamp change |
| 15 | Proof A | wrapper re-submit (exact payload) | **NON-MUTATING** (branch-F identity) | Browser/REST | branch-F identity; before/after byte-equal | Any inner-RPC write / before-image drift → re-read, never force |
| 16 | Proof B | old-RPC probe (all args, p_model_year=9999) | **NON-MUTATING** (rejected pre-write) | REST | grant denial OR `invalid model_year: 9999` | PGRST202/404 signature-resolution (send ALL args incl. both JSONB) |
| 18 | Final tests | `node test_regression.js`; `node e2e.js` | RO | Local terminal | 1543/0; 155/0/0; fallbacks 0/0 (rerun once on a known headless `clickNav` flake) | Any real fail / any readiness fallback |
| 19–20 | Evidence + commit | docs | RO→commit | Local/Git | docs-only commit; push feature branch | app/test/exec-SQL/BUILD_TS touched |

### 3a. Post-Phase-2 browser verification (step 14) — detail

Run **after** Phase-2 revoke validation (step 13) and **before** Proof A/B. Both halves are
**non-mutating**; the stale half must prove the revoked old path writes nothing.

**FRESH browser/session** (a new session / hard refresh of the deployed build):
- ☐ the deployed build loads with the **new `BUILD_TS`** (advanced at step 6);
- ☐ the closeout UI drives the **wrapper path** (not the old direct RPC);
- ☐ Overview / Weekly / Goals / Budget / History render normally; **console clean**;
- ☐ the **wrapper remains callable** (open a week's confirmation view / a benign wrapper read succeeds);
- ☐ **Option B remains owner-gated** (a non-owner is rejected via `public.is_owner()`).

**STALE browser/session** (a pre-deploy tab or cached old build that still calls the old direct
reconciliation RPC):
- ☐ the old-RPC attempt **FAILS CLOSED** after the Phase-2 revoke — grant-layer denial (401/403/404);
- ☐ the UI **does not falsely report success**;
- ☐ **no optimistic reconciliation state remains** locally;
- ☐ **no reconciliation or snapshot rows are written** (verify counts/timestamps unchanged);
- ☐ the operator gets a **clear error / reload instruction** (refresh to the new build).

**Expected evidence to retain (step 14):**
- the **HTTP / PostgREST result** of the stale old-RPC attempt (expect 401/403/404 denial);
- confirmation of **no row-count or timestamp change** in `weekly_reconciliations` /
  `goal_funding_snapshots` after the stale attempt (re-run the wk6 counts: still 1 recon + 9 snaps);
- **fresh-browser wrapper availability** (callable; Option B owner-gated);
- **console result** (clean on fresh; graceful error on stale).

**Hard stops:** stale attempt returns any 2xx; false success or lingering optimistic state; **any**
row/timestamp change; or the fresh browser can't reach the wrapper. → STOP; force-refresh the stale
tab; investigate why the revoke didn't deny before proceeding to the proofs.

---

## 4. Expected-result table (exact known values)

**Adjunct preflight (step 2):**
| field | expected |
|---|---|
| `anchor9` (wk5 opening_anchor) | **9** |
| `corrections` (wk5) | **2** |
| Week-5 total | **11** |
| `latest_reconciled` | **5** |
| reconciliation `rows` | **5** |
| `only_weeks_1_to_5` | **true** |
| snapshots at `week_num >= 6` | **0** |

**Protected-RPC MD5 baselines (must stay unchanged all sitting):**
- `save_reconciliation_with_commitments` = `1bfde751ac647c5e9a25ba168d08150c`
- `save_goal_funding_snapshots` = `154231b3f180349ec328f08ccbe77076`

**Owner / grants:**
| stage | expected |
|---|---|
| Trusted owner (all definer fns) | **postgres** |
| Pre-Phase-1: wrapper + Option B (anon & authenticated EXECUTE) | **false** (all) |
| Post-Phase-1: wrapper + Option B authenticated EXECUTE | **true**; anon = **false** |
| Old recon RPC authenticated EXECUTE | **true** until Phase 2, **false** after |

**Week-6 closeout (step 9–10):**
- exactly **1** `weekly_reconciliations` row at `week_num=6`
- exactly **9** distinct eligible `goal_id` snapshots at wk6, each `model_year=2026`, `week_num=6`, `source='reconciliation'`
- exactly **9** total `source='reconciliation'` rows at wk6 (no dupes/extras)

**Post-Phase-2 final grant posture (authenticated EXECUTE / table privs; anon all false):**
- wrapper = **T**, Option B = **T**
- old recon RPC = **F**, repair RPC = **F**, direct snapshot RPC = **F**
- `goal_funding_snapshots`: INSERT/UPDATE = **F**, SELECT = **T**
- `weekly_reconciliations`: INSERT/UPDATE/DELETE = **F**, SELECT = **T**

---

## 5. Hard-stop matrix

| Condition | Detected at | Immediate action | Rollback? | Rollback scope | Saturday ends? |
|---|---|---|---|---|---|
| Environment mismatch (≠production) | any SQL | STOP; do not run | No | — | Yes |
| Branch/HEAD mismatch | step 1 | STOP; re-fetch/re-verify | No | — | Until resolved |
| Dirty working tree | step 1 | STOP; investigate; do not reset blindly | No | — | Until clean |
| Owner drift (≠postgres) | steps 2/3/5/13 | STOP | No (pre-P1) / **Yes** (post-P1) | operational grant rollback | Yes |
| Protected-RPC MD5 drift | steps 3/5/13 | STOP | No (pre-P1) / **Yes** (post-P1) | operational grant rollback | Yes |
| Unexpected pre-grant (wrapper/Option B already granted) | step 3/4 | STOP; investigate (do NOT set c_resume casually) | No | — | Until explained |
| Phase 1 grant mismatch (grant didn't take / anon=T) | step 5 | STOP | **Yes** | operational grant rollback | Yes |
| Pages deploy failure | step 6 | STOP; do not proceed to closeout | **Maybe** | browser revert (grants stay) | Until fixed |
| Wrong BUILD_TS (not advanced / guard build absent) | step 6/7 | STOP; do not close out | **Maybe** | browser revert | Until fixed |
| Live-browser error/regression | step 7 | STOP; do not close out | **Maybe** | browser revert | Until fixed |
| Wrong `week_num` (not 6) | step 9/10 | STOP; do NOT run Phase 2 | **Yes** | operational grant rollback + browser revert; value via Option B post-proofs | Yes |
| Payload mismatch (confirmation ≠ intended) | step 8 | Go Back; correct; do not submit | No | — | No (retry) |
| Closeout partial/ambiguous / unconfirmed 2xx | step 9 | Re-read both halves (client does this); do not retry blindly | No unless owner mutation needed | operational grant rollback + browser revert | Depends |
| Week-6 count/source mismatch (≠1 recon / ≠9 source=reconciliation) | step 10/12 | STOP; do NOT run Phase 2 (revoke script hard-stops too) | No (Phase 2 not run) | — | Yes |
| Option B / approved_reopen used during freeze | steps 11–16 | STOP immediately; re-capture payload+before-image; re-plan Phase 2 | Per §6 | do NOT weaken revoke SQL | Yes |
| Phase 2 precondition failure | step 12 | Script hard-stops; STOP | No | — | Yes |
| Stale browser: 2xx / false success / optimistic state / any row-timestamp change | step 14b | STOP; force-refresh the stale tab; investigate why the revoke didn't deny | **If a write occurred, escalate** | (a write post-revoke should be impossible) | Yes if a write occurred |
| Fresh browser: wrapper not callable / Option B not owner-gated / old BUILD_TS | step 14a | STOP; do not proceed to proofs | **Maybe** | browser revert / re-check grants | Until fixed |
| Proof A failure (any mutation / drift) | step 15 | Re-read; NEVER force; investigate | Assess | operational grant rollback if needed | Yes |
| Proof B signature-resolution ambiguity (PGRST202/404) | step 16 | Re-send with ALL named args incl. both JSONB + p_model_year=9999 | No | — | No (re-probe) |
| Final test failure / any readiness fallback | step 18 | STOP; do not report complete; investigate | No (post-activation) | — | Report + hold |

---

## 6. Rollback decision tree (by phase)

- **Before Phase 1 (steps 1–3):** nothing granted, nothing written. **No rollback** — just STOP and re-plan. Old RPC remains granted (unchanged). Data untouched.
- **After Phase 1, before browser deploy (steps 4–5):** **Operational grant rollback** — `activation-grants-rollback.sql` section A: revoke wrapper+Option B → inert; re-grant old recon RPC only. Browser not yet deployed → no revert needed. **Old RPC restored/retained.** No data change.
- **After browser deploy, before closeout (steps 6–8):** **Operational grant rollback (A) + browser revert** (revert the merge on main → redeploy pre-activation index.html). Old RPC re-granted; reverted browser writes via old RPC. No data change.
- **After closeout, before Phase 2 (steps 9–11):** **Operational grant rollback (A) + browser revert.** The Week-6 rows already written **STAY** — wrong values use the correction path (Option B) AFTER the freeze/proofs, **never a drop**. Old RPC re-granted. Do not restore the dump for this.
- **After Phase 2 (steps 12+):** the intended end state. If a problem: **Operational grant rollback (A) + browser revert** restores a working ordinary closeout via the old RPC (re-granted). **Exact ACL restoration** (`rollback.sql` section B, generated from the captured matrix) only if the precise pre-activation grant matrix is required — GRANT-only, never a full restore. Week-6 rows stay; corrections via Option B.
- **Catastrophic DR only:** the Slice-6 dump is the **disaster-recovery floor ONLY** — never a routine rollback and never a grant-restore tool. It predates the Week-6 write; restoring it after any post-dump write requires (1) DR approval, (2) restore-point-timestamp acknowledgement, (3) a preserve/replay-or-accept-loss plan for post-dump data, (4) scope verification against later reconciliation/snapshot state.

**Data preservation rule (all branches):** never delete reconciliation or snapshot rows; wrong values are corrected via Option B (owner-only), post-proofs. **Never edit or weaken the revoke SQL.**

---

## 7. ▲ WEEK-6 STATE-FREEZE BOX (Fable P1-1) ▲

> **From the SUCCESSFUL Week-6 closeout (step 9) until BOTH Proof A and Proof B finish (steps 15–16):**
> - **NO Option B correction of model week 6.**
> - **NO `approved_reopen` of model week 6.**
> - **NO direct mutation of the Week-6 reconciliation or its nine snapshots.**
> - If any wrong value is found during this interval, it **waits until after Proof B** — do not touch week 6.
> - If an owner mutation is genuinely unavoidable: **(a) do NOT edit or weaken the revoke SQL; (b)
>   re-capture the payload + before-image; (c) STOP and re-plan Phase 2.**
>
> Both proofs assume the Week-6 state is byte-identical to the step-10 before-image; any mutation in
> the interval invalidates them and forces a re-plan. **Release the freeze only after both proofs pass.**

---

## 8. Local readiness checklist (Adam — before Saturday)

- [ ] Supabase **production** project access (Adam-Dashboard `usayoldrawwmjsmretin`)
- [ ] Supabase **SQL Editor** access
- [ ] Valid **authenticated** app session (for the REST probes / closeout)
- [ ] Can retrieve the **anon key** and a valid **access token** locally (for the Proof B / inert probes)
- [ ] Production **direct DSN** available locally (env var / `~/.pgpass`) — for an optional fresh DR dump
- [ ] Local **backup directory** exists (`~/Herndon-FOS-DB-Backups/Adam-Dashboard/5G-1D-Slice6/`)
- [ ] Encrypted-backup **password stored in 1Password** (separate from the backup file)
- [ ] **GitHub auth** works (push + merge)
- [ ] **GitHub Pages** deployment visibility (Actions / `pages-build-deployment`)
- [ ] **Node / Playwright** environment works (`node test_regression.js`, `node e2e.js`)
- [ ] Local branch **fetched and clean** (§9 block)
- [ ] **No unrelated work** in the repo working tree
- [ ] Browser **DevTools** available (console + network)
- [ ] **Week-28 transactions + reconciliation inputs ready** (actual end-of-week balances for the closeout)

> Do NOT record credentials, tokens, DSNs, or passwords anywhere in the repo or evidence.

---

## 9. Saturday start command block (copy-paste; guarded — no unguarded reset)

```bash
cd ~/Adam-Dashboard || { echo "✗ repo not found"; return 2>/dev/null || exit 1; }
git fetch origin
git switch claude/herndon-5g-1d-preactivation-j428vn
# ▲▲▲ SEQUENCING WARNING ▲▲▲ Do NOT run `git reset --hard origin/<activation-branch>` until AFTER
# Adam has PUSHED the advanced activation branch. Before the push, the remote tip is still the OLD
# a952560; resetting to it would REWIND the local branch and DISCARD the reconciliation. The reset is
# therefore emitted as an instruction, NOT auto-run.
if [ -n "$(git status --porcelain)" ]; then
  echo "✗ STOP: working tree is DIRTY — investigate before Saturday. Do NOT reset."
else
  echo "→ ONLY AFTER Adam has PUSHED the advanced activation branch, align local with:"
  echo "    git reset --hard origin/claude/herndon-5g-1d-preactivation-j428vn"
fi
# Ancestry-plus-blob identity gate (do NOT pin the final tip hash — it is the docs reconciliation commit):
git merge-base --is-ancestor 4ce6aff HEAD && echo "ancestry:    4ce6aff is an ancestor of HEAD (OK)" || echo "✗ STOP: 4ce6aff is NOT an ancestor of HEAD"
echo "index blob:  $(git rev-parse HEAD:index.html)   # expect a4c458af2c9c53a67ceb621dd4d8c9c48d6343a2"
echo "tree:        $([ -z "$(git status --porcelain)" ] && echo CLEAN || echo DIRTY)"
echo "origin/main: $(git rev-parse origin/main)   # expect 5bd6c69787bee7a8fe26ee1fb2ceb0528526d6f1"
grep -o "BUILD_TS[^,;]*" index.html | head -1     # expect BUILD_TS='2026-07-15T20:52:49'
for f in docs/phase-5g-1d-gateb-activation-runbook-2026-07-13.md \
         docs/phase-5g-1d-gateb-adjunct-preflight.sql \
         docs/phase-5g-1d-activation-grants.sql \
         docs/phase-5g-1d-activation-grants-validation.sql \
         docs/phase-5g-1d-activation-revokes.sql \
         docs/phase-5g-1d-activation-grants-rollback.sql \
         docs/phase-5g-1d-rollback.sql \
         docs/phase-5g-1d-saturday-operator-package-2026-07-18.md; do
  [ -f "$f" ] && echo "ok  $f" || echo "MISSING  $f"
done
```

---

## 10. Operator evidence checklist (retain verbatim; balance-free in committed docs)

- [ ] Adjunct preflight output (3 rows) + pre-Phase-1 validation (17/17)
- [ ] Pre-grant and post-grant grant matrices
- [ ] Post-Phase-2 final grant matrix
- [ ] Deployment: merge commit hash + live `BUILD_TS` value
- [ ] **Post-Phase-2 browser verification (step 14):** stale old-RPC attempt HTTP/PostgREST result
  (expect 401/403/404); confirmation of **no row-count or timestamp change** after it; fresh-browser
  wrapper availability (callable + Option B owner-gated); console result (clean fresh / graceful stale)
- [ ] Week-6 **frozen payload** (LOCAL, balance-bearing — never committed)
- [ ] Week-6 row counts + source proof (1 recon; 9 source=reconciliation)
- [ ] Proof A result (branch-F identity; before/after equal)
- [ ] Proof B result (denial or `invalid model_year: 9999`)
- [ ] Static + E2E results (1543/0; 155/0/0; fallbacks 0/0)
- [ ] Final status-doc commit hash(es)

> **Committed evidence must NEVER contain:** secrets, JWTs, anon keys, DSNs, backup contents, or
> household balances. Value-bearing artifacts (the frozen payload, balances, the dump) stay local-only.

---

## 11. Final completion criteria

When steps 1–19 are green and the evidence is recorded, the terminal statement is:

> **5G-1D COMPLETE + GREEN. Production closeout now uses the atomic reconciliation-plus-nine-snapshot
> wrapper; Gate C lockdown is active; old direct write paths are revoked; Week 28/model week 6 is
> verified; rollback and audit evidence are recorded.**

Until every gate is green and the freeze is released after both proofs, 5G-1D is **not** complete —
do not report it complete.
