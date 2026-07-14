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
| Feature branch | `claude/herndon-5g-1d-preactivation-j428vn` |
| HEAD commit | `7f0f47d7b27a2de6101a951996230343a7ed824c` |
| `origin/main` | `5bd6c69787bee7a8fe26ee1fb2ceb0528526d6f1` (must stay unchanged until the merge step) |
| Working tree | CLEAN (`git status --porcelain` empty) |
| `BUILD_TS` (pre-activation) | `2026-07-11T17:26:14` (unchanged until the deploy step) |
| Production project | **Adam-Dashboard**, ref **`usayoldrawwmjsmretin`**, `system_identifier 7632885393857617092`, `app_environment` ABSENT |
| Week mapping | **model `week_num = 6` = calendar Week 28** (`getCalWeek(6)=28`); the first closeout persists `week_num = 6` |

**Authoritative runbook + SQL files (all committed at HEAD above):**
- Runbook: `docs/phase-5g-1d-gateb-activation-runbook-2026-07-13.md`
- Read-only: `docs/phase-5g-1d-gateb-adjunct-preflight.sql`, `docs/phase-5g-1d-activation-grants-validation.sql`
- Mutating (grants): `docs/phase-5g-1d-activation-grants.sql` (Phase 1), `docs/phase-5g-1d-activation-revokes.sql` (Phase 2)
- Rollback: `docs/phase-5g-1d-activation-grants-rollback.sql` (grant rollback, two scopes), `docs/phase-5g-1d-rollback.sql` (Slice-6 DROP — not expected in Gate B)
- Browser: `index.html` (closeout + row-9 guard + response validation; verified gate static **1507/0**, e2e **148/0/0**)
- DR floor: the Slice-6 restore point `5G-1D-slice6-restorepoint-20260713T222223Z.dump` (local + encrypted off-device). *The adjunct preflight (step 2) confirms production has not been written since 07-13, so this dump is still a valid pre-Week-6 DR floor. A fresh same-sitting `pg_dump` (Slice-6 runbook §2 procedure) is OPTIONAL belt-and-suspenders — recommended if any doubt.*

---

## 2. One-page execution checklist (in order — 🛑 = STOP for explicit Adam approval)

```
[ ]  1. RE-GROUND ............... §9 start block: branch, HEAD 7f0f47d, clean tree, origin/main, BUILD_TS, files
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
[ ] 18. FINAL TEST SUITE (LOCAL)  node test_regression.js (1507/0) ; node e2e.js (148/0/0, fallbacks 0/0)
[ ] 19. CLOSEOUT EVIDENCE + STATUS updates (docs: CODEX_STATUS, phase-status, AGENTS refresh, activation closeout evidence)
[ ] 20. FINAL COMMIT + PUSH ..... docs-only --no-verify; feature branch; (merge to main already done in step 6)
```

---

## 3. Exact file + command map (per step)

| # | Step | File / action | R/W | Runs in | Expected success | Hard-stop |
|---|---|---|---|---|---|---|
| 1 | Re-ground | §9 block | RO | Local terminal | HEAD=7f0f47d, tree clean, origin/main=5bd6c69, BUILD_TS 2026-07-11T17:26:14 | Any mismatch |
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
| 18 | Final tests | `node test_regression.js`; `node e2e.js` | RO | Local terminal | 1507/0; 148/0/0; fallbacks 0/0 | Any fail / any readiness fallback |
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
# clean-tree GUARD before aligning to remote (no destructive reset on a dirty tree):
if [ -n "$(git status --porcelain)" ]; then
  echo "✗ STOP: working tree is DIRTY — investigate before Saturday. Do NOT reset."; 
else
  git reset --hard origin/claude/herndon-5g-1d-preactivation-j428vn
fi
echo "HEAD:        $(git rev-parse HEAD)          # expect 7f0f47d7b27a2de6101a951996230343a7ed824c"
echo "tree:        $([ -z "$(git status --porcelain)" ] && echo CLEAN || echo DIRTY)"
echo "origin/main: $(git rev-parse origin/main)   # expect 5bd6c69787bee7a8fe26ee1fb2ceb0528526d6f1"
grep -o "BUILD_TS[^,;]*" index.html | head -1     # expect BUILD_TS='2026-07-11T17:26:14'
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
- [ ] Static + E2E results (1507/0; 148/0/0; fallbacks 0/0)
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
