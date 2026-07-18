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

At the **atomic capture moment**, let `A` = captured actual **Truist Checking** balance and `M` = the
model-projected **Week-28 ending Truist Checking** balance (after the `$5,666.01` AMEX outflow update;
**without** the `$1,752.26` income; with the `$425.68` commission-tax modeled as moved).

**Variance V = A − M.**

Explained components — **include ONLY those applicable at the atomic capture moment**; each sign is its
contribution to `A − M`:

| Component | Sign / value | Include when |
|---|---|---|
| Extra BK Pay unmodeled income | **+ `$1,752.26`** | always (permanent Week-29 attribution) |
| AMEX Gold in-flight (model removed it; Truist hasn't debited) | **+ `$5,666.01`** | iff `status ∈ {initiated, bank_pending}` at capture (omit if `cleared`) |
| Commission-tax `$425.68` in-flight (settles Mon 07/20) | **+ `$425.68`** | iff not yet debited from Truist at capture (omit if cleared) |
| Any other model-expected-but-not-yet-actual item | ± its amount | iff present at capture |

**Control:** `| V − Σ(included components) | ≤ $0.01`. **Zero unexplained residual** (tolerance ≤ `$0.01`).
Restated: `M + Σ(included components) = A` within `$0.01`. Any residual above `$0.01` = **HARD STOP** — do
not close until explained.

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
9. **Frozen-payload review** (step 8). Confirm the nine funded values; **Adam IRA cumulative includes the
   executed `$61.06`**; commission-tax shows **`$425.68` done + `$417.83` deferred** (total `$843.51`
   preserved, not doubled/lost); AMEX Gold reflects `$5,666.01` in-flight (Truist actual not manually
   reduced). **Run the §C variance control: `|V − Σcomponents| ≤ $0.01`, zero unexplained residual — HARD
   STOP otherwise.** Do NOT submit yet.
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
15. **Week-29 income + two-leg tax execution** (fresh week; PATH-A-safe — no prior completion). Enter the
    **`$1,752.26`** into **Week 29** (Edit Week, Tax? checked). Verify the model books a **`$700.90`**
    commission_tax leg **and preserves the `$417.83`** Deep-South carry-forward as a **separate** leg.
    Execute **two separate** Truist → Vio transfers and complete each task: **`$417.83`** and **`$700.90`**
    (**total `$1,118.73`** — never the combined `$1,118.74`). Verify each persisted `completed_amount`
    equals its actual transfer.
16. **Final tests + evidence + status.** `node test_regression.js` (1543/0) · `node e2e.js` (155/0/0,
    readiness 0/0); record closeout evidence; update status docs; docs-only commit; **push only on Adam's
    authorization.**

## E. Preserved Fable stop conditions (summary)
- §2d MANDATORY STOP (no income into Week 28, ever). · §13 write-lock (Weeks 1–5) + no-drift Baseline A/B.
- §2c commission-posting gate. · Frozen-payload / variance HARD STOP (residual > $0.01). · Closeout
  hard-stops (GFA01, domain reject, ambiguous 2xx, wrong week_num, count ≠ 9). · Week-6 freeze (no Option
  B / approved_reopen through both proofs). · Phase-2 pre-lockdown asserts. · Two-leg tax integrity
  ($417.83 + $700.90 separate; completed_amount = actual transfer).

---
**No production mutation, Week-28 edit, closeout, deploy, revoke, Phase 2, or push has occurred.** Gate 3
remains HARD-STOPPED pending Adam's authorization of step 1 (and each subsequent step).
