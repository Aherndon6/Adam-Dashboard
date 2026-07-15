# Defect — Executed transfer history disappears after reconciliation because transfer rows are re-derived and keyed positionally

> **Follow-on (2026-07-15):** this fix preserved executed-transfer *history* but did NOT stop an already-satisfied obligation from re-presenting as a NEW executable PLANNED row after an open-week recalc (the Adam IRA $61.06 duplicate). That open-window gap is closed by the mandatory pre-activation **open-window executed-transfer netting/suppression control** — see `docs/phase-5g-1b-openwindow-netting-2026-07-15.md` (adapter/projection + write-guard; frozen surfaces untouched) and the identity amendment `docs/roadmap/amendment-2026-07-15-progress-plane-transfer-identity.md`.

**Logged:** 2026-07-11 · **Status:** RESOLVED 2026-07-11 (adapter/UI fix, commit `db2704f`) ·
**Classification:** 5G-1B rider — stable executed-transfer identity and history preservation
(display/audit-history defect — NOT data loss, NOT an E2 blocker) ·

## Resolution (2026-07-11) — RESOLVED

Fixed in commit `db2704f` — **adapter/UI only; no runModel/reconciliation/snapshot/schema/SQL
change** (verified: `.sql` files changed = 0; runModel/waterfall/recon/C3 markers intact). A pure,
deterministic resolver (`resolveWeekTransfers`) matches current model-transfer recommendations to
persisted `weekly_tasks` completions by **identity** (`action_key` / `completed_label`),
**position-independent**, with tiered duplicate-key handling (exact key+label → unique key →
concordant occurrence → legacy exact-label; ambiguity prefers a false negative). Completions no
longer in the recommended set render as read-only **"Executed earlier"** rows (checked, disabled,
no write handler). The write path is **resolver-aware** (`_resolveWriteTarget` → matched `task_idx`
on uncheck, an unused index on a fresh check, and never overwrites a different action's row). Weekly
X/Y stays current-only with a separate **"Executed earlier: N"**; the History count and text export
reuse the resolver. No `(week_num, action_key)` uniqueness assumed; no schema/migration.

**Verification (final):** static regression **1431/0** (Section 5G-1B, 29 cases); full e2e **135/0**
(incl. two browser tests — executed-history visibility / Weekly-X-Y-exclusion / History-count, and
uncheck-writes-matched-`task_idx`-5-never-idx-0); e2e smoke **19/0**; browser console **clean**.

**Deferred (unchanged, future characterization):** durable immutable action identity, write-path
re-keying, and any unique constraint remain future work — not required for this fix.

**Owner:** 5G-1B owns the immediate correction; the identity/render adapter applies to **all**
model-generated transfer actions (not only holding goals) · **Fix timing:** post-E2 (E2 COMPLETE
2026-07-11), pre-Alaska-freeze.

## Observed production behavior

Before Week 5 (Cal Wk 27) reconciliation, Adam executed and checked **five** model-generated
transfer tasks, spanning four goal families:

- Alaska (`goal_alaska`)
- Wewe RCCL holding (`goal_wewe_rccl`)
- Wewe DCL holding (`goal_wewe_dcl`)
- Adam IRA, from Truist Checking (`goal_adam_ira`)
- Adam IRA seed, from Truist Savings (`goal_adam_ira_seed`)

After the Week 5 reconciliation saved, the visible "Transfers to execute" list re-rendered as a
smaller set and no longer showed the RCCL, DCL, or the two Adam IRA rows. The underlying
completion metadata remained intact in `public.weekly_tasks`.

## Verified evidence (read-only)

Verification date: **2026-07-11**. Adam ran this read-only query against production
(Adam-Dashboard, `usayoldrawwmjsmretin`):

```sql
select week_num, task_idx, completed, action_key,
       completed_label, completed_amount, completed_at
from public.weekly_tasks
where week_num = 5
order by task_idx;
```

**Verified result (summary — detailed rows NOT committed):** five completed Week-5 records were
returned from `public.weekly_tasks`, carrying these five `action_key` values (task_idx 0–4, all
`completed = true`):

- `goal_alaska`
- `goal_wewe_rccl`
- `goal_wewe_dcl`
- `goal_adam_ira`
- `goal_adam_ira_seed`

Detailed production results were reviewed on 2026-07-11 and retained outside the repository. No
amounts, timestamps, populated results, or evidence hashes are committed.

## Verified root cause

- Model transfer rows are ephemeral output from `runModel()` (waterfall `ac.push(...)` →
  `realActs`, `index.html:2518` / `:2592`).
- After reconciliation, the Cash Availability Engine reads the reconciled actual checking balance
  (`_actualChkForEngine`, `index.html:2392–2413`) and the goal waterfall emits a different
  `realActs` set for that week.
- The renderer (`index.html:4175–4206`) displays only the current re-derived rows.
- Completion state persists in `public.weekly_tasks`, keyed by `(week_num, task_idx)`, with
  `action_key` and `completed_label` retained (write `index.html:2826`; load `:7869`→`:7902`).
- There is no durable visible transfer-history layer — visible rows are always re-derived.
- Positional keying creates overwrite risk: a later `toggleTask(week, task_idx, …)` upsert
  (`resolution=merge-duplicates`) at the same `task_idx` overwrites the earlier row if a different
  action now occupies that index.

## Impact

- No financial movement lost.
- No reconciliation data lost.
- No `public.weekly_tasks` completion rows lost.
- Week 5 reconciliation remains valid.
- E2 is not blocked: it uses observed custodian/bank balances, and the nine eligible goals exclude
  RCCL/DCL. `goal_adam_ira` / `goal_adam_ira_seed` appear among the disappeared **rows**, but the
  E2 `adam_ira` Value-Card figure is read from the IRA custodian, not the model transfer row — so
  the affected rows are display-only for E2 purposes.
- Audit/history UX is defective.
- Existing completion rows are orphaned from the visible UI and overwrite-vulnerable.

## Implementation constraints (binding on the eventual fix)

- A stable, immutable action identity must replace positional `task_idx` as the effective identity.
  Existing `action_key` and `completed_label` may be used by the minimum adapter/UI correction, but
  the durable identity contract remains to be characterized.
- Executed transfer history must remain visible after model re-derivation.
- Historical executed rows must not be overwritten by a changed recommendation set.
- No financial-model math change.
- No reconciliation-engine rewrite.
- No `runModel` refactor beyond the minimum necessary adapter/render work.
- No production migration until separately approved.

## Future schema/identity requirement (characterize before designing a migration)

A durable data-model change is a **candidate, not a decided solution.** A unique constraint on
`(week_num, action_key)` must NOT be assumed: a single goal family can legitimately emit multiple
actions in one week (proven here by `goal_adam_ira` and `goal_adam_ira_seed`). The required
sequence is:

1. Define a **stable, immutable action identity** for every model-generated transfer action.
2. **Prove its uniqueness semantics** across all generated transfer types (including multi-action
   goal families and any repeat-within-week cases).
3. **Only then** design an additive schema / write-path migration, under separate approval.

For today's post-E2 work, the planned change is the **minimum safe adapter/UI fix** using the
`action_key` and `completed_label` data already persisted in `public.weekly_tasks`, plus guardrails
that prevent positional remapping. Schema hardening is a **separate follow-on slice** and is not in
scope unless investigation proves it is required for the minimum fix.

## Acceptance-test requirement (generic across all model-generated transfers)

A committed test must prove, end to end, for a Week whose recommendation set changes on
reconciliation:

- Completed actions remain **visible** after the recommendation set changes.
- Historical rows render from **persisted completion metadata** (`action_key` / `completed_label`),
  not from current `realActs`.
- **No completion maps to a different action** (no positional remap).
- **No existing `public.weekly_tasks` row is overwritten** during the tested flow.
- Current **unreconciled** model output remains unchanged.
- **No financial-model or reconciliation-math changes.**

## Cross-references

- **5G-1B** — owns the immediate correction; holding→payout lifecycle for RCCL/DCL. Note the
  identity/render adapter is broader than holding goals (Alaska + both IRA actions are affected).
- **5G-1D** — durable per-goal funded attribution (`goal_funding_snapshots` write-through); the
  durable-history model should align with, and may consume, 5G-1D's persisted state.
- **5G-1E** — Account Purpose / Holding Bucket Integrity (AMEX holding attribution hardened
  advisory→hard).
- **Test coverage** — reconcile→re-render behavior (no standalone test-hardening backlog file
  exists yet; requirement captured above).

## Controlling sequence

- **July 11 (done):** Week 5 reconciled; E2 Value Card, fresh independent review, local execution
  readiness, this defect proposal, and 5G-1D readiness work completed; `origin/main` kept unchanged
  through the seed. **E2 executed and validated the same day on the wk-5 basis (Guard A confirmed
  `max(week_num)=5`) — E2 COMPLETE + GREEN 2026-07-11.** The earlier "Jul 12–17 window" was a
  planning estimate, not a technical guard; it did not gate execution.
- **After E2 closed (now):** commit E2 closeout → commit this defect documentation + stale
  timing-comment correction → implement the minimum safe transfer-history fix → full verification →
  begin 5G-1D implementation.

5G-1D does not begin before this defect fix. **5G-1D Gate 0 (E2 completion) is now SATISFIED
(2026-07-11).** The documentation commit was deferred until after E2 completed so `origin/main` did
not move and lapse E2 clearance (E2 runbook §9). Not during the Alaska freeze (Jul 24–Aug 10).
