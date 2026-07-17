# Phase 5G-1D — Saturday Activation Checklist (2026-07-18)

**One-page operator checklist for the production sitting. NOT a replacement for the Operator Package** (`docs/phase-5g-1d-saturday-operator-package-2026-07-18.md`, **v5**) — every item cites the package section that governs. Balance-free. 🛑 = **explicit Adam approval required**. Work top to bottom; any **HARD STOP** ends the sitting until resolved. *Rough total: ~2.5–3.5 hrs.*

> **Recovery Rule**
> If any **HARD STOP** occurs:
> • Do not improvise. • Do not skip steps. • Preserve evidence. • Stop and review the situation with ChatGPT before proceeding.

## A. Before starting (~10–15 min) — §1, §8, §9
- [ ] Activation branch `claude/herndon-5g-1d-preactivation-j428vn` checked out (§9)
- [ ] `4ce6aff` is an ancestor of HEAD (`git merge-base --is-ancestor 4ce6aff HEAD`) (§1)
- [ ] Working tree CLEAN (`git status --porcelain` empty) (§1/§9)
- [ ] `BUILD_TS` == `2026-07-15T20:52:49` (§1)
- [ ] `index.html` blob == `a4c458af2c9c53a67ceb621dd4d8c9c48d6343a2` (§1/§9)
- [ ] `origin/main` == `5bd6c69…` unchanged (§1)
- [ ] Local baseline green: `node test_regression.js` 1543/0 · `node e2e.js` 155/0/0 · readiness 0/0 (§2 step 18)
- [ ] Production access (Adam-Dashboard `usayoldrawwmjsmretin`) · SQL Editor · authenticated app session · anon key + access token available (§8)

## B. Production prechecks (read-only) (~15 min) — §2 step 2–3, §2b, §4
- [ ] Adjunct preflight `gateb-adjunct-preflight.sql` → `ADJUNCT PREFLIGHT PASS`; wk5 9/2/11; recon 5 rows wks 1–5; snaps @ wk≥6 = 0 (§4)
- [ ] Pre-Phase-1 validation → 17/17 pass; inert; MD5 baselines; owner `postgres` (§2 step 3)
- [ ] §2b Adam-IRA precheck → exactly one completed `goal_adam_ira` $61.06, non-null amount + key (§2b)
- [ ] §2b unattributable-rows scan → **zero rows** (§2b) — **HARD STOP** if any
- [ ] Snapshot count @ wk≥6 = 0; reconciliation = 5 rows (wks 1–5) (§4)

## C. Commission gate (NEW v4) (~5 min) — §2c
- [ ] $2,108.78 Deep South commission has **POSTED** to Truist Checking (posted/cleared, available)
- [ ] "Processed"/"pending"/provisional does **NOT** qualify
- [ ] $425.68 commission-tax transfer has **NOT** already occurred (bank + §2b duplicate scan)
- [ ] Execute $425.68 → Vio Bank - Tax Reserve **only after** posted funds exist
- [ ] Mark **only** the correct Week-28 `commission_tax` task complete (persists `commission_tax / 425.68 / correct label`)
- [ ] Week 29 still shows the single `$417.83` `commission_tax` task
- [ ] **HARD STOP** if the commission has not posted → do not transfer, do not close Week 28 (delay = contingency annex, roadmap §7)

## C2. Extra-paycheck taxable-inflow constraint (NEW v5) — §2d
- [ ] **BINDING RULE:** never save a Week-28 Edit-Week taxable increase **after** any Week-28 `commission_tax` completion (§2d)
- [ ] Select **PATH A or PATH B by posting order** — never the prohibited middle sequence (§2d)
- [ ] **PATH A** ($1,752.26 posted, no commission_tax completion yet): enter $1,752.26 taxable → verify **one enabled `$1,544.42`** commission_tax task, **no `$417.83` deferred**, **no additional-income custom task** → transfer + complete **exactly $1,544.42** → verify persisted `completed_amount == 1544.42` → then close (§2d)
- [ ] **PATH B** ($1,752.26 not posted): §2c ($425.68) first → verify `completed_amount == 425.68` and `$417.83` deferred remains → **never enter $1,752.26 into Week 28** → enter only in its actual posting week → verify that week yields a **`$700.90`** commission_tax task with `$417.83` intact (§2d)
- [ ] 🛑 **MANDATORY STOP:** do NOT complete $425.68 then add taxable income to Week 28; if it occurs, **do not close Week 28** (§2d)
- [ ] Evidence: read-only `weekly_tasks` (`action_key='commission_tax'`) before/after each material step; `completed_amount` == actual bank transfer; Weekly-view retained; obligation conservation within rounding tolerance ($1,544.42 combined vs $1,544.41 sum-of-legs, ≤ $0.01) (§2d)

**STOP — Review results with ChatGPT before continuing.**
## D. 🛑 Approval Gate 1 — Adam authorizes Phase-1 grants (§2)

## E. Phase 1 grants (MUTATING) (~10 min) — §2 step 4–5
- [ ] `activation-grants.sql` → `ACTIVATION GRANTS PASS`; COMMIT
- [ ] Post-grant validation → wrapper/Option B authenticated=T, anon=F; owner + bodies unchanged

**STOP — Review results with ChatGPT before continuing.**
## F. 🛑 Approval Gate 2 — Adam authorizes BUILD_TS stamp + merge + deploy (§2)

## G. Deploy (~15–30 min) — §2 step 6–7
- [ ] Stamp BUILD_TS; merge feature → main; GitHub Pages build green; live BUILD_TS advances
- [ ] Live-browser (pre-write): fresh session renders; closeout-state badges; confirmation view opens; console clean; **pre-close duplicate scan** — no enabled Adam IRA duplicate; one enabled `$425.68` commission_tax; narrative `$425.68`/`$417.83 carries forward` (§2b) — **DO NOT submit**

**STOP — Review results with ChatGPT before continuing.**
## H. 🛑 Approval Gate 3 — Adam authorizes the real Week-6 (Cal Wk 28) closeout (§2)

## I. Week 28 closeout (WRITE) (~20–30 min) — §2 step 8–10, §2b
- [ ] Frozen payload: confirm the nine funded values; **Adam IRA cumulative includes the executed $61.06** (§2b)
- [ ] "Confirm & close week" → `{ok:true, mode:normal_closeout, week_num:6, snapshot_count:9}`
- [ ] Durable-state verify (3 ways): 9 rows `source=reconciliation` @ wk6; badge "Closeout complete"; **post-close: zero later-week Adam IRA recommendation** (§2b)
- [ ] ▲ Week-6 state-freeze active (§7) — holds through Proof B

> **Point of No Return Verification** — final confirmation before revoking the legacy write paths:
> □ Week 6 reconciliation exists
> □ Nine reconciliation snapshots exist
> □ UI verified
> □ No duplicate Adam IRA recommendation
> □ Commission tax displays correctly
> □ Week 28 commission tax transfer ($425.68) completed
> □ Week 29 commission tax transfer ($417.83) remains scheduled

**STOP — Review results with ChatGPT before continuing.**
## J. 🛑 Approval Gate 4 — Adam authorizes Phase-2 revokes (only after Week-6 durably complete) (§2)

## K. Phase 2 lockdown (MUTATING) (~15 min) — §2 step 12–13
- [ ] `activation-revokes.sql` → `LOCKDOWN REVOKES PASS`; COMMIT (hard-stops unless wrapper granted / old RPC still granted / Week-6 durable / owner unchanged)
- [ ] Final grant validation → wrapper/Option B=T; old recon/repair/snapshot RPC=F; tables INS/UPD/DEL=F, SELECT=T; anon all F

## L. Proofs (~20–30 min) — §2 step 14–16, §3a
- [ ] **Stale-browser** (§3a): old-RPC call FAILS CLOSED (401/403/404); no false success; no optimistic state; **zero** row/timestamp change
- [ ] **Proof A** (non-mutating): wrapper idempotent re-submit → branch-F identity; before/after equal; **never force**
- [ ] **Proof B** (non-mutating): old-RPC probe (all args, `p_model_year=9999`) → denial or `invalid model_year: 9999`
- [ ] ▲ Release Week-6 freeze (only after BOTH proofs pass)

## M. Final validation (~20 min) — §2 step 18
- [ ] `node test_regression.js` → 1543/0 · `node e2e.js` → 155/0/0 · readiness 0/0
- [ ] **Known flake protocol:** a `clickNav`/headless timeout → rerun once; report both runs; a *logic* failure is a HARD STOP

## N. Evidence collection (~10 min) — §10
- [ ] Adjunct preflight + 17/17; both §2b precheck outputs; grant matrices (pre/post/final); merge hash + live BUILD_TS; pre-close scan; Week-6 frozen payload (LOCAL, balance-bearing — never committed); Week-6 counts (1 recon / 9 source=reconciliation); post-close zero-recommendation; stale-probe HTTP + no-row-change; Proof A/B; suites 1543/0, 155/0/0, 0/0 — **committed evidence is secrets-free & balance-free**

## O. Final GO / NO-GO summary
- [ ] All 🛑 gates approved; no HARD STOP triggered; both proofs passed; freeze released; suites green → **GO / COMPLETE**

## Expected success state
- Week 6 reconciliation written (1 row) · Nine reconciliation snapshots written (`source=reconciliation`) · Old write paths revoked · Wrapper active · BUILD_TS verified (advanced live) · Static 1543/0 · E2E 155/0/0 · No duplicate Adam IRA recommendation · Commission tax tracked as **Week 28: $425.68**, **Week 29: $417.83** · **Activation complete.**

## Activation Record
*(permanent operator record — fill in during the sitting)*
- Activation started: ____________________
- Activation completed: ____________________
- Final activation branch commit: ____________________
- Merge commit to main: ____________________
- Live BUILD_TS: ____________________
- Notes: ____________________
