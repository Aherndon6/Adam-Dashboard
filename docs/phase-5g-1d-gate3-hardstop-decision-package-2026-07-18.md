# Phase 5G-1D — Gate-3 HARD STOP decision package (2026-07-18)

**Status: DEFERRED — pending Fable + owner review. No option is implemented. Week 28 is OPEN; nothing
pushed; no production mutation.** Governing context: operator package §2c/§2d/§14; decision-log
2026-07-18. Read-only verification: operator package §14.1 (run before deciding).

## Situation (one paragraph)

The B&K deposit `$3,904.76` **posted 07/17/2026** inside Week 28 (regular `$2,152.50` + **Extra BK Pay
`$1,752.26`**), and it posted **before** the operator completed the `$425.68` Week-28 `commission_tax`
task later that evening. So PATH A was the correct path, but PATH B's action (complete `$425.68` first,
income not entered) was taken. The correct combined Week-28 obligation is **`$1,544.42`**; only `$425.68`
is transferred (settling Mon 07/20); **`$1,118.74` remains to transfer** (`$417.83` modeled deferral +
`$700.91` incremental Extra-BK-Pay shortfall). Entering the income into Week 28 now (post-completion) is
the §2d prohibited sequence (delta-backfill corrupts the `$425.68` record). This package compares the
three resolution paths.

## Invariants every option must preserve

- The real bank facts: `$425.68` already moved to Vio (settles Mon 07/20); `$3,904.76` is real cash in
  Truist Checking as of 07/17.
- Persisted `completed_amount` **must equal the actual bank transfer** (§2d evidence rule) — no inflated
  completed amounts, ever.
- No positional fallback / no positional backfill; no fabricated row identity.
- Week-6 closeout write path does not read `weekly_tasks`; the 9-goal snapshot reflects **actual**
  funded balances.
- Historical Baseline A/B fingerprint (§13.4) must not drift.
- **AMEX Gold Week-28 payment (operator package §14.2; V6/Q6-verified):** AMEX Gold is **forecast-only**
  in the Week-6 client model (`modelData[6]` `t:'ob' -5500`, index.html:915) — it is **NOT** in
  `cash_commitments` (Q6: 5 rows, weeks 4–5 only; no week-6, no AMEX Gold), so the Cash Availability Engine
  reserves **nothing** for it today. Whichever option is chosen, the Week-6 close **must CREATE** the
  durable reservation as a new commitment: `payee=AMEX Gold`, `amount_cents=$5,666.01` (566601),
  `commitment_class=credit_card_payment`, `required_or_discretionary=protected_required`,
  `source_account=truist_checking`, `status=initiated|bank_pending` (live status), `affects_deployable_cash=true`.
  If the Truist debit has not posted by the Week-28 cutoff, **do not manually reduce the Truist actual** —
  treat it as outstanding and record the bank debit on its **actual** posting date (Week-29 if it lands then),
  retaining the 07/18 initiation evidence. The outflow-only estimate→actual model update ($5,500→$5,666.01)
  is **not** §2d-blocked but is bundled into the selected path's supervised Week-28 pass for cleanliness.
  This AMEX item does **not** alter the commission-tax HARD STOP.

---

## Option A — Ship the B1 amount-correction fix first, then enter the income and close

Ship the recorded B1 fix (Edit-Week delta-backfill: never overwrite a non-null `completed_amount`;
compute added obligation from `total tax − Σ completed commission_tax`; decouple custom-task creation
from the legacy PATCH; floor-split fixture). On the fixed build, enter `$1,752.26` (Edit Week, Tax?),
which safely raises the Week-28 obligation to `$1,544.42` while **preserving** the `$425.68` completion;
execute + complete the additional `$1,118.74`; then close Week 28.

- **Production mutations:** (1) deploy the B1-fix build (index.html → new BUILD_TS, merge→main, Pages);
  (2) Edit-Week income entry (weekly_tasks/override write); (3) additional `$1,118.74` Truist→Vio
  transfer + task completion (bank + weekly_tasks write); (4) Week-6 closeout (wrapper: 1 recon + 9
  snapshots).
- **Identity/amount risks:** LOWEST — the fix directly removes the root-cause backfill defect;
  `$425.68` completion preserved; combined obligation computed correctly. Residual risk = the fix must
  itself be correct (mitigated by tests + independent review).
- **Required tests:** B1 unit/regression (no non-null `completed_amount` overwrite; obligation = total −
  Σ completed; custom-task decoupled; floor-split fixture) + full suites green (`1543/0` + new,
  `155/0/0`, readiness `0/0`) + a Week-28 combined-obligation e2e.
- **Deployment/rollback:** a fresh Gate-2-style deploy (stamp BUILD_TS, merge, Pages). Rollback = revert
  the merge on main (browser revert); grants already in place, unaffected. Adds one reviewed
  code-deploy cycle (likely a follow-up sitting).
- **Effect on the already-scheduled `$425.68`:** **PRESERVED** — no uncheck; it settles Mon 07/20 as
  scheduled and remains the real recorded completion.
- **Exact remaining bank transfer:** **`$1,118.74`** to Vio Tax Reserve (`$1,544.42 − $425.68`).
- **Snapshot correct without fabricating history?** **YES** — cleanest; the `$425.68` stays real, the
  delta is computed, no history is rewritten.

## Option B — Controlled task-state correction + PATH-A reconstruction

Uncheck the `$425.68` completion, then follow PATH A on the current build: enter `$1,752.26` first → one
`$1,544.42` task → complete `$1,544.42`.

- **Production mutations:** (1) uncheck the `$425.68` task (weekly_tasks alter); (2) Edit-Week income
  entry; (3) additional `$1,118.74` transfer + completion at `$1,544.42`; (4) closeout.
- **Identity/amount risks:** HIGH. **Rejection rationale (corrected 2026-07-18):** the immediate
  delta-backfill is **not** the stated issue — **unchecking REMOVES the completed-row match**, so the
  backfill has no completed `commission_tax` row to rewrite at that moment. B is rejected because it
  **(a) rewrites a truthful executed-transfer record** (the real $425.68 that moved), **(b) breaks the
  task-to-bank-leg mapping** (the completion no longer corresponds to the actual Vio transfer), and
  **(c) creates unsafe multi-step choreography on the defective build** (uncheck → re-enter income →
  re-complete at $1,544.42), any step of which can mis-write. Collapses the Deep-South `$425.68`/`$417.83`
  split into a single `$1,544.42`.
- **Required tests:** none added (no code change), which is a liability — the sequence relies on manual
  operation of the defective path. Re-verify via §14.1 after each step.
- **Deployment/rollback:** no deploy. Rollback is manual and fragile — if the uncheck/re-entry corrupts,
  recovery alters completion history further.
- **Effect on the already-scheduled `$425.68`:** **ALTERED** — the uncheck de-links the task from a real
  (settling Mon) transfer; the record no longer cleanly reflects the `$425.68` that actually moved.
- **Exact remaining bank transfer:** **`$1,118.74`** (to reach `$1,544.42` total).
- **Snapshot correct without fabricating history?** **NO — REJECTED.** It **rewrites a truthful
  executed-transfer record**, **breaks the task-to-bank-leg mapping**, and requires **unsafe multi-step
  choreography on the defective build**. Not recommended.

## Option C — Close Week 28 on the Deep-South basis only; model the Extra BK Pay in Week 29

Do **not** touch Week 28's `$425.68` completion or enter the income there. Close Week 28 as currently
modeled (Deep South: `$425.68` done + `$417.83` deferred) against actual balances. **Unmodeled-income
variance = `$1,752.26` only** (the regular Wendy paycheck `$2,152.50` is already modeled in Week 6, so it
is NOT part of the variance; the `$3,904.76` deposit is `$2,152.50` modeled + `$1,752.26` unmodeled). Enter
the `$1,752.26` in **Week 29 (Cal 29 / model wk 7)** — a fresh week with **no prior completion**, so entry
is PATH-A-safe there. **The two tax legs stay SEPARATE** (two tasks, two bank transfers): the `$417.83`
Deep-South deferral carries into Week 29, and the Extra BK Pay books `$700.90` (= 40% × `$1,752.26`) —
**total `$1,118.73`** (`$417.83` + `$700.90`). **Do NOT force the combined-basis `$1,118.74`**; the one-cent
difference vs `$1,544.42 − $425.68` is documented rounding.

- **Production mutations:** (1) Week-6 closeout (wrapper: 1 recon + 9 snapshots) — Week 28 only; later,
  in Week 29, (2) Edit-Week income entry + (3) **two separate** transfers/completions (`$417.83` + `$700.90`
  = `$1,118.73`). **No Week-28 mutation beyond the normal closeout; no code deploy.**
- **Identity/amount risks:** LOW-MEDIUM — never touches the `$425.68` completion (no backfill trigger);
  Week-29 entry is on a clean week. Risk = a **one-week timing shift** (income posted Week 28, taxed/
  allocated from Week 29) and closing the FIRST activation closeout with a **large positive checking
  variance** (the posted deposit unmodeled in Week 28).
- **Required tests:** none new (no code change); confirm the model books Week-29 `$700.90` + preserves
  the `$417.83` carry-forward (existing commission-tax/commTaxPending behavior; covered by regression).
- **Deployment/rollback:** no deploy. Rollback of the Week-6 closeout = the standard operational
  grant-rollback + browser revert; Week-6 rows stay (corrections via Option B post-proofs).
- **Effect on the already-scheduled `$425.68`:** **PRESERVED and untouched** — settles Mon 07/20.
- **Exact remaining bank transfer:** **`$1,118.73`**, executed in **Week 29** as **two separate legs** —
  `$417.83` (Deep-South deferral) + `$700.90` (Extra BK Pay). Two tasks, two transfers; not combined.
- **Snapshot correct without fabricating history?** **Only partially, and NOT posting-week-accurate.**
  Option C **does not reflect the actual bank posting week.** The `$1,752.26` **posted 07/17 in Week 28**;
  assigning its tax/allocation to Week 29 is a **deliberate model-timing exception**, not a faithful
  representation. Consequences: (1) a **Week-28 bank/model variance** — the actual Truist balance carries
  the unmodeled `$1,752.26` (the regular `$2,152.50` is already modeled) — documented in the Week-28
  reconciliation variance per the PATH-B* amendment; (2) a **potentially inaccurate FIRST frozen
  snapshot** — the Week-6 closeout (the first supervised wrapper write, subsequently frozen through both
  proofs) is anchored on a Week-28 state that knowingly excludes income that posted that week; (3) the
  extra income's `$700.90` tax and `~$1,051.36` goal allocation are shifted a week off their actual
  posting. C does **not** fabricate row identity, but it **does** encode a timing exception into the
  first anchor. **C is NOT equivalent to A:** A models the income in its true week (Week 28) and produces
  a posting-accurate close; C avoids a deploy at the cost of posting-week fidelity and a variance-laden
  first snapshot. The deploy-avoidance is a convenience, not a correctness parity.

---

## Comparison at a glance

| Dimension | A (fix first) | B (uncheck + PATH-A) | C (Deep-South close, extra in Wk29) |
|---|---|---|---|
| Code deploy | Yes (B1 fix) | No | No |
| Touches the `$425.68` completion | No (preserved) | **Yes (uncheck/rewrite)** | No (preserved) |
| Runs on the defective build | No | **Yes** | No (avoids the trigger) |
| Remaining transfer | `$1,118.74` | `$1,118.74` | `$1,118.74` (in Wk29) |
| Fabricates/rewrites history | No | **Borderline** | No — **but not posting-accurate** (deliberate Wk29 timing exception) |
| Posting-week accurate | **Yes (income in Week 28)** | Yes | **No (income posted Wk28, modeled Wk29)** |
| First-closeout variance | Clean | Clean | **Large positive (unmodeled deposit)** |
| Identity/amount risk | Lowest | Highest | Low–medium |

## Recommendation (for Fable + owner)

Lead candidate: **Option A** — it is the only path that preserves the real `$425.68` completion, models
the combined obligation correctly, **and stays posting-week accurate** (income booked in Week 28, where it
posted), with no history rewrite; its cost is one reviewed code-deploy cycle (appropriately a follow-up
sitting, not an in-sitting improvisation). **Option C is a deploy-free FALLBACK, not a correctness peer of
A:** it avoids a deploy and never touches the `$425.68`, but it **deliberately models Week-28 income in
Week 29**, so it is **not posting-week accurate**, leaves a **large Week-28 bank/model variance**, and
anchors the **first frozen snapshot** on a knowingly incomplete Week-28 state. C should be chosen only if
the owner explicitly accepts that timing exception and variance; the deploy-avoidance alone does not make
it equivalent to A. **Option B is not recommended** — it rewrites a real completion on the defective
build. In all three, `$1,118.74` of additional Vio Tax Reserve transfer is owed, and the `$425.68`
already scheduled for Mon 07/20 is preserved except under B.

**Next step:** run §14.1 read-only verification, confirm the current production state, then Fable + owner
select A / B / C. No implementation until that decision.
