# Phase 5G-1D — Option C operator script + §2d PATH-B* amendment (2026-07-18)

**Fable verdict: Option C — PROCEED WITH CONDITIONS (provisional controlling path).** This doc records the
owner-approved decisions and the exact one-action-at-a-time operator sequence. **Nothing here is executed.
Gate 3 remains HARD-STOPPED. Every step is gated by Adam's separate per-step authorization.** Companions:
operator package §2c/§2d/§13/§14/§14.2; decision package `…-gate3-hardstop-decision-package-2026-07-18.md`.

## A. §2d PATH-B* amendment (owner-approved)

PATH B assumed the Extra BK Pay would post in a *later* week; it posted **07/17 in Week 28**. **PATH-B\***
is the owner-approved resolution:
- The **`$1,752.26` remains economically and bank-actually part of Week 28** (it is real cash that landed
  in Truist on 07/17).
- It is **documented in the Week-28 reconciliation variance** (§C below), **not** entered into the Week-28
  model.
- **Model/tax attribution is PERMANENTLY placed in Week 29** — this is a permanent owner decision, not a
  temporary deferral.
- **Do NOT retroactively re-enter it into closed Week 28 after B1 is fixed.** Once Week 28 is closed under
  PATH-B*, the income stays attributed to Week 29 forever.
- The §2d MANDATORY STOP still holds absolutely: **never add the `$1,752.26` (or any taxable income) to
  Week 28.**

**Amended 2026-07-18 (Fable Step-6 disposition — package §14.4; owner-adopted):**
- Week-28 **`$425.68`** executed leg (persisted `2026-07-18 03:20:38.457+00`) is **immutable**.
- Deep-South remainder **pinned at `$417.83`** (= `843.51 − 425.68`, executed basis). The model's
  **`$365.32`** carry display is a **known projection artifact** (the `$52.51` AMEX-edit re-split) and
  **must never be executed, completed, or used in evidence figures.**
- Extra BK Pay tax leg **pinned at `$700.90`**; Week-29 combined execution total **`$1,118.73`**
  (two separate legs).
- **The B1 correction must ship before the `$417.83` leg is executed/completed** (the fixed build must
  display carry = `417.83`). If B1 slips past ~Jul 23 → escalate for a supervised owner-approved
  completion; never complete a task displaying ≠ `417.83`.
- Conservation proof at every §14.1 rerun: Σ completed Week-28 `commission_tax` = `425.68`; after Week-29
  execution: `425.68 + 417.83 + 700.90 = 1,544.41` (= combined `1,544.42` within the documented ≤ `$0.01`).

## B. Option-C AMEX Gold requirement

- **Week-28 model outflow** updated from `~$5,500` → **`$5,666.01`** (outflow-only Edit-Week; **no
  taxable-income fields touched** → no commission-tax/goal backfill, per §14.2).
- The durable reservation is **created through the standard reconciliation Phase-2 path** (not a manual
  row). Confirm the commitment with exactly:
  - `payee` = **AMEX Gold**
  - `amount_cents` = **566601** (`$5,666.01`)
  - `commitment_class` = **credit_card_payment**
  - `required_or_discretionary` = **protected_required**
  - `source_account` = **truist_checking**
  - `affects_deployable_cash` = **true**
  - `status` = **determined from live AMEX/Truist state at the atomic capture** (`initiated` if submitted
    not yet debited; `bank_pending` if bank shows it pending; `cleared` only if actually debited)
  - **reflected-in-balance answer must MATCH the captured balance** used for the reconciliation.
- **No separate commitment for the `$425.68` commission-tax transfer** — it is a completed `weekly_tasks`
  row, not a `cash_commitments` obligation.

## C. Variance control (mathematically explicit)

> **CORRECTED 2026-07-18 per the Fable Step-6 disposition (package §14.4).** The original table below-noted
> two specification errors that caused the Step-6 false HARD STOP: it carried the commission line at the
> **executed** value where the `A − M` identity requires the **model-embedded** value, and it **omitted the
> modeled-but-unsettled Week-28 goal-funding legs**. The corrected control follows; the recorded Step-6
> residual `161.45 = 52.51 + 108.94` closes exactly under it.

At the **atomic capture moment**, let `A` = captured actual **Truist Checking** balance and `M` = the
model-projected **Week-28 ending Truist Checking** balance (after the `$5,666.01` AMEX outflow update;
**without** the `$1,752.26` income; with the model's Week-28 commission-tax leg — **`$478.19`** after the
known re-split — modeled as moved). `A`, `M`, and the full transfer enumeration are captured in **one
atomic observation window**; any mid-window posting into `A` (e.g., the Greenlight `+$120.00`,
Week-29-effective 07/20 — excluded from the Week-28 table) forces a full re-capture.

**Variance V = A − M (raw — never deployable/adjusted cash).**

Explained components — **named components only; every component at MODEL basis**; each sign is its
contribution to `A − M`:

| Component | Sign / value | Include when |
|---|---|---|
| Extra BK Pay unmodeled income | **+ `$1,752.26`** | always (permanent Week-29 attribution) |
| AMEX Gold in-flight (model removed it; Truist hasn't debited) | **+ `$5,666.01`** | iff `status ∈ {initiated, bank_pending}` at capture (omit if `cleared`) |
| Commission-tax — **dual-basis line**: model **`$478.19`** = executed **`$425.68`** (settles Mon 07/20) + **`$52.51`** known re-split artifact | **+ `$478.19`** (model basis) | iff the executed leg not yet debited at capture (if cleared, include only the `$52.51` artifact) |
| **Week-28 goal-funding legs** — enumerate EVERY modeled-but-unsettled leg by **name/obligation · modeled amount · executed status · bank-settlement status** (known member: Adam IRA `$61.06`, executed-unsettled) | **+ `$108.94` exactly** (Σ of named legs) | per-leg, iff not debited at capture |

**Control:** `| V − Σ(named components) | ≤ $0.01`. **Zero unexplained residual.** **An approximate or
unnamed residual leg is NOT sufficient evidence** — if the named goal-funding set does not total exactly
`$108.94` (or the penny-exact in-window equivalent if settlement states changed), that is a **HARD STOP**,
not a rounding allowance. Reference closure at the recorded Step-6 capture:
`1,752.26 + 5,666.01 + 478.19 + 108.94 = 8,005.40 = V` exactly.

> Direction note: every component above is **positive** because each is either cash present in `A` but
> absent from `M` (the income) or cash the model already removed but that Truist still holds (undebited
> outflows). If an outflow has actually cleared by capture, it drops out (both `A` and `M` reflect it).

## D. Numbered operator script (one action at a time; each step awaits Adam's authorization)

**Standing controls (apply to every step) — Fable stop conditions preserved:**
- §2d MANDATORY STOP: **never add the `$1,752.26` (or any taxable income) to Week 28.** If it happens →
  stop, do not close, preserve evidence, no improvised repair.
- §13 RECONCILED-WEEK WRITE-LOCK: **no check/uncheck/custom-toggle/Edit-Week on Weeks 1–5**; Wendy must not
  touch past-week controls.
- §13.4 no-drift: any drift in Baseline A (`4/4·2/2·0/0·1/1·5/5`) or Baseline B (`15/14/1`) = **HARD STOP**.
- §2c commission-posting gate remains satisfied ($2,108.78 posted; $425.68 executed; task complete; $417.83
  intact).
- Closeout hard-stops: GFA01/adjudication, domain reject, ambiguous/unconfirmed 2xx, wrong `week_num`,
  count ≠ 9 → do not proceed; re-read, never force.

**Steps:**

1. **Re-ground + evidence baseline (read-only).** Re-run §14.1 **V1–V6/Q6** and **Baseline A/B**. Expect
   V1/V2 clean (61.06 + 425.68), V3 legacy pattern, V4 no drift, V5 Week-28 open, V6/Q6 no AMEX Gold /
   5 rows wk4–5. **HARD STOP on any drift or unexpected row.**
2. **Docs checkpoint.** Confirm this script + the corrected decision package + operator package §14.2 are
   committed (docs-only, unpushed). No production action.
3. **Week-28 outflow-only AMEX edit.** Edit Week 28 → correct the AMEX Gold outflow **`$5,718.52` →
   `$5,666.01`** (the persisted value was `$5,718.52`, not the `$5,500` planning amount; a later AMEX
   credit reduced the verified balance). **Touch NO taxable-income field. Do NOT enter the `$1,752.26`.**
   Save. — **DONE 2026-07-18: post-save PASS** (both rows unchanged, no custom task, Baseline A/B no drift).
4. **Immediate V1/V2 re-verify (read-only).** Confirm `commission_tax` = **425.68** and `goal_adam_ira` =
   **61.06** are **UNCHANGED** (the outflow edit must not have altered them). **HARD STOP** if either
   changed, or if any new completed `commission_tax`/goal row appeared.
5. **AMEX submission branch.**
   - **If not yet submitted:** submit the **`$5,666.01`** payment via AMEX from Truist Checking …0608
     (independent operator bank action).
   - **If already submitted:** record the current AMEX status; do not resubmit.
6. **Atomic balance/payment-state capture.** At one moment, capture together: (a) actual Truist Checking
   balance `A`; (b) AMEX Gold live status (submitted/pending/cleared); (c) `$425.68` debit status
   (cleared or in-flight). These feed the commitment `status`, the variance components, and the
   reflected-in-balance answer.
7. **Open Week-6 reconciliation → Phase 1** (prior-commitment resolution). Resolve any Phase-1 prior
   commitments per the panel; **no Week 1–5 controls touched.**
8. **Phase 2 (new commitments) → AMEX commitment confirmation.** Confirm the AMEX Gold commitment via the
   standard Phase-2 path with the exact §B fields; `status` from the step-6 capture; **reflected-in-balance
   answer must match `A`.** **No separate `$425.68` commitment.**
9. **Frozen-payload review** (step 8) — *expectation amended 2026-07-18 (package §14.4(5)).* Confirm the
   nine funded values; **Adam IRA cumulative includes the executed `$61.06`**; **the completed `$425.68`
   commission-tax row is INTACT (hard check — any mutation of that row = HARD STOP)**; on the current
   build **expect the temporary `$365.32` carry display** (known `$52.51` re-split artifact — it is NOT
   executable and NOT a false-stop condition; the pinned obligation remains `$417.83`); AMEX Gold reflects
   `$5,666.01` in-flight (Truist actual not manually reduced). **Run the corrected §C variance control:
   `|V − Σ(named components)| ≤ $0.01`, zero unexplained residual, goal-funding set named and exactly
   `$108.94` — HARD STOP otherwise.** Do NOT submit yet.
10. **Wrapper submission** (Approval Gate 3 — Adam authorizes). "Confirm & close week" → expect
    `{ok:true, mode:normal_closeout, week_num:6, snapshot_count:9}`.
11. **Durable verification** (3 ways): 9 rows `source=reconciliation` @ wk6; badge "Closeout complete";
    the AMEX Gold commitment persisted; post-close **zero later-week Adam IRA recommendation**.
12. **No-drift rerun #1.** Baseline A/B unchanged (`4/4·2/2·0/0·1/1·5/5`; `15/14/1`); V1/V2 unchanged.
    **HARD STOP on any drift.**
13. **Week-6 freeze ACTIVE** (§7) — no Option B / approved_reopen of week 6 through both proofs.
14. **Approval Gate 4 → no-drift rerun #2 (immediately before revokes) → Phase 2 revokes**
    (`activation-revokes.sql` → `LOCKDOWN REVOKES PASS`) → final grant validation (raw + consolidated
    `post_phase_2` 17/17) → **Proof A / Proof B** (both non-mutating) → **release the freeze** after both
    pass.
15. **Week-29 income + two-leg tax execution** — *amended 2026-07-18 (package §14.4(4)).* Enter the
    **`$1,752.26`** into **Week 29** (Edit Week, Tax? checked; fresh week, PATH-A-safe). Verify the model
    books a **`$700.90`** commission_tax leg. The Deep-South carry may DISPLAY **`$365.32`** (and may
    slide to Week 30 once Week 29 carries its own `ct` — expected pre-B1 behavior): **the pinned leg is
    `$417.83` and `$365.32` is never executed or completed.** **The `$417.83` leg executes ONLY on the
    B1-corrected build** (which must display carry = `417.83`); if B1 has not shipped by ~Jul 23, escalate
    for a supervised owner-approved completion — never complete a task displaying ≠ `417.83`. The
    `$700.90` leg (its own correctly-displayed task) may execute on the current build if needed. Execute
    **two separate** Truist → Vio transfers and complete each task: **`$417.83`** and **`$700.90`**
    (**total `$1,118.73`** — never the combined `$1,118.74`; never a blended completion). Verify each
    persisted `completed_amount` equals its actual transfer; then run the conservation check
    `425.68 + 417.83 + 700.90 = 1,544.41` (= combined `1,544.42` within ≤ `$0.01`).
16. **Final tests + evidence + status.** `node test_regression.js` (1543/0) · `node e2e.js` (155/0/0,
    readiness 0/0); record closeout evidence; update status docs; docs-only commit; **push only on Adam's
    authorization.**

## E. Preserved Fable stop conditions (summary)
- §2d MANDATORY STOP (no income into Week 28, ever). · §13 write-lock (Weeks 1–5) + no-drift Baseline A/B.
- §2c commission-posting gate. · Frozen-payload / variance HARD STOP (residual > $0.01). · Closeout
  hard-stops (GFA01, domain reject, ambiguous 2xx, wrong week_num, count ≠ 9). · Week-6 freeze (no Option
  B / approved_reopen through both proofs). · Phase-2 pre-lockdown asserts. · Two-leg tax integrity
  ($417.83 + $700.90 separate; completed_amount = actual transfer).
- **Added 2026-07-18 (§14.4):** goal-funding enumeration must be **named** and total **exactly `$108.94`**
  in the atomic window (no approximate/unnamed residual). · Any mid-window posting into `A` → full
  re-capture. · **`$365.32` never executed/completed.** · Any mutation of the `$425.68` row = HARD STOP.
  · **Week-28 Edit-Week is CLOSED for this sitting** (no further saves of any field). · The `$417.83` leg
  only on the B1-corrected build.

---

## F. 🛑 STEP-6 HARD STOP (2026-07-18) — reconciliation BLOCKED

Steps 1–5 executed and passed (re-ground; docs; outflow-only AMEX edit `$5,718.52 → $5,666.01` post-save
PASS; AMEX submitted conf W3870). **Step 6 (atomic capture) does NOT pass — reconciliation is prohibited.**

### F.1 Step-6 atomic capture (recorded)
- `A` = Truist available balance = **`14,505.40`**
- `M` = Week-28 projected balance = **`6,500.00`**
- `V = A − M =` **`8,005.40`**
- AMEX `5,666.01` = **`initiated`**, not posted (conf W3870; no posted/pending Truist debit)
- Commission-tax `425.68` = executed but **not posted** (settles Mon 07/20)
- Greenlight **`+120.00`** is **Week 29** (effective 2026-07-20) → **excluded** from the Week-28 decomposition

### F.2 Variance-control FAILURE
- Currently documented component sum (§C: income `1,752.26` + AMEX `5,666.01` + commission-tax `425.68`)
  = **`7,843.95`**
- **Unexplained residual = `161.45`** → **Step 6 FAILS the ≤ `$0.01` control as currently specified.**
- **Reconciliation remains PROHIBITED** until the **complete Week-28 projected-transfer decomposition** is
  enumerated (every modeled-but-unsettled Week-28 transfer, incl. goal-funding sweeps) and the residual
  closes to ≤ `$0.01`. (§C omitted the modeled goal transfers, and the model's tax outflow is now `478.19`,
  not `425.68`.)

### F.3 Commission-tax re-split divergence
- Executed reality remains **`425.68`**.
- Model now displays **`478.19`** for Week 28 and **`365.32`** carry-forward (because the `52.51` AMEX
  reduction was absorbed into the Week-28 tax allocation).
- **Correct remaining Deep-South obligation (executed basis) remains `417.83`** (`= 843.51 − 425.68`).
- **Week 29 must NOT be allowed to book only `365.32`** — that would **underfund the `843.51` obligation by
  `52.51`.** The PATH-B* Week-29 Deep-South leg stays **`417.83`**.

### F.4 Stop conditions preserved (all)
**No** reconciliation · **no** wrapper · **no** commitment creation · **no** Phase 2 · **no** deploy ·
**no** revoke · **no** push · **no** Week-28 Extra BK Pay entry · **no** Weeks 1–5 edits.

### F.5 Disposition
Escalated to Fable — see `docs/phase-5g-1d-gate3-fable-followup-step6-2026-07-18.md` (items A–D). Activation
remains blocked pending Fable disposition + Adam authorization.

### F.6 FABLE DISPOSITION RECEIVED + OWNER-ADOPTED (2026-07-18) — Step-6 control corrected; resume path defined

**Ruling (package §14.4 is the authoritative record):** the Step-6 failure was caused by a
**mis-specified variance control**, not by wrong production state — the `161.45` residual decomposes
exactly as **`52.51`** (commission line recorded at executed `425.68` where the `A − M` identity requires
the model-embedded `478.19`) **+ `108.94`** (omitted modeled-but-unsettled Week-28 goal-funding legs).
The `$52.51` re-split **remains a real display/projection defect** (B1 class — surplus-driven
reallocation of an executed tax obligation); no write path consumes `478.19`/`365.32`.
**Operator-side control is sufficient for activation; the B1 correction is mandatory before the Week-29
Deep-South (`$417.83`) execution.**

**Resume conditions (all required before re-attempting Step 6):**
1. §C control replaced by the corrected specification (done above — dual-basis commission line at model
   `$478.19`; named goal-funding enumeration totaling exactly `$108.94`; raw `A − M`; atomic window).
2. Fresh atomic capture (`A`, `M`, full enumeration in one window) closing to ≤ `$0.01` with **zero
   unnamed residual**; reference closure `1,752.26 + 5,666.01 + 478.19 + 108.94 = 8,005.40`.
3. PATH-B\* amendment (§A above / §14.4(4)) + amended step-9 expectation (§14.4(5)) recorded — done.
4. **Week-28 Edit-Week CLOSED for the sitting** (no further saves of any field).
5. Adam's per-step authorization to resume at Step 6.

**Gate 3: RESUMES under these conditions.** B1 scope additions (anchored executed legs; carry = total −
Σ executed; cash-side edits never re-split an executed leg; the `$5,718.52 → $5,666.01` regression case)
are binding on the B1 correction (§14.4(6)).

---
**No production mutation, closeout, deploy, revoke, Phase 2, or push has occurred beyond the recorded
Steps 3 (outflow-only AMEX edit) and 5 (AMEX bank submission).** Gate 3 remains HARD-STOPPED.
