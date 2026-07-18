# Phase 5G-1D — Gate-3 disposition review request (for Fable) — 2026-07-18

**Ask:** a clear **A / B / C verdict** on how to resolve the Week-28 Gate-3 HARD STOP, **plus an exact
same-day execution sequence if it is safely feasible today.** Supporting artifacts: decision package
`docs/phase-5g-1d-gate3-hardstop-decision-package-2026-07-18.md`; operator package §2c/§2d/§13/§14/§14.2;
decision-log 2026-07-18. **Nothing is executed; Week 28 is OPEN; nothing pushed.**

## 1. Why Gate 3 is HARD-STOPPED

The B&K deposit **$3,904.76 posted 07/17/2026 inside Week 28** (Wendy regular $2,152.50 + **Extra BK Pay
$1,752.26**), and it posted **before** the operator completed the $425.68 Week-28 `commission_tax` task
that evening. So **PATH A was the correct path**, but PATH B's action was taken (complete $425.68 first,
income not entered). Reflecting the income's tax in Week 28 now requires an **Edit-Week taxable increase
after the completion** — the §2d **prohibited middle sequence** (the unfixed delta-backfill would rewrite
$425.68→$843.51, hide $417.83, strand $1,118.74). Per §2d MANDATORY STOP: **do not close Week 28 — hold
and escalate.** PATH B is invalidated; PATH A cannot be applied retroactively without the prohibited op.

**Arithmetic:** combined obligation 40% × ($2,108.78 + $1,752.26) = **$1,544.42**; transferred **$425.68**
(settles Mon 07/20); still to transfer **$1,118.74** (= $417.83 modeled deferral + $700.91 incremental).

## 2. Read-only production evidence (V1–V6 / Q6, all captured)

- **V1/V2 — Week 6 CLEAN:** exactly two rows — `goal_adam_ira` 61.06 and `commission_tax` 425.68, both
  fully keyed/labeled, distinct identities. The active collision defect is resolved; the PATH B write is
  correct (425.68, not 843.51).
- **V3 — legacy pattern (expected):** `commission_tax` rows at wk2 (375.68, null label), wk4 (null amount),
  wk6 (425.68, fully attributed). Consistent with the deferred 5G-1D-HIST-1 legacy-attribution item.
- **V4 — NO DRIFT:** Baseline A = 1→4/4, 2→2/2, 3→0/0, 4→1/1, 5→5/5; Baseline B = 15 total / 14 completed
  / 1 incomplete. Unchanged.
- **V5 — Week 28 OPEN:** `weekly_reconciliations` = weeks 1–5 only (no wk6); `goal_funding_snapshots`
  wk≥6 = 0. No closeout written.
- **V6 / Q6 — AMEX Gold reservation:** `cash_commitments` has 5 rows (four at wk4, one at wk5, all
  `protected_required`); **no wk6 row; no AMEX Gold row.** → AMEX Gold is **forecast-only** in the Week-6
  client model (index.html:915); the durable reservation is **created at reconciliation**, not before.

## 3. Edit-Week backfill — exact trigger (verified in `saveWeekEdits`, index.html:3615)

- The unsafe path fires **only on a positive commission-tax delta** `_deltaCt = ct − _oldCt > 0.005`,
  where `ct = 40% × taxableGross` and `taxableGross` sums **taxable inflows only** (3627–3628, guard ≈3658).
  Identity-selected PATCH of the completed `commission_tax` row (B1).
- **Adding the $1,752.26 to Week 28 is exactly this positive taxable-income delta → PROHIBITED.**
- An **outflow-only** change (e.g., the AMEX Gold $5,500→$5,666.01 refinement) yields `_deltaCt = 0` and no
  positive goal-sweep delta (≈3721) → **triggers neither backfill**; it is technically safe, and is bundled
  into the supervised pass only for cleanliness.

## 4. AMEX Gold Week-28 payment ($5,666.01) — corrected

Statement balance due **$5,666.01** (supersedes the earlier assumed $5,718.52), due 07/18 from Truist
Checking …0608, not yet submitted; the bank payment is independent of the HARD STOP. Per §2 above it is
**forecast-only** today (not in `cash_commitments`), so the Cash Availability Engine reserves nothing for
it yet. **Whichever path is chosen, the Week-6 close must CREATE** the durable reservation:
`payee=AMEX Gold`, `amount_cents=566601` ($5,666.01), `commitment_class=credit_card_payment`,
`required_or_discretionary=protected_required`, `source_account=truist_checking`,
`status=initiated|bank_pending` (live), `affects_deployable_cash=true`. If not yet debited by the Week-28
cutoff: do not manually reduce the Truist actual; record the debit on its actual posting date (Week-29 if
it lands then), retaining the 07/18 initiation evidence.

## 5. Options (full detail in the decision package)

| | A — B1 fix first, then close | B — uncheck + PATH-A redo | C — Deep-South close, extra in Wk29 |
|---|---|---|---|
| Code deploy | Yes (B1 fix) | No | No |
| Touches the $425.68 | No (preserved) | **Yes (rewrite)** | No (preserved) |
| Posting-week accurate | **Yes** | Yes | **No (income Wk28 → modeled Wk29)** |
| First-close variance | Clean | Clean | **Large positive (unmodeled deposit)** |
| Identity/amount risk | Lowest | Highest | Low–medium |
| Same-day feasible safely? | **No** (needs reviewed B1-fix deploy) | Not recommended | **Possibly** (if C's timing exception accepted) |

**Recommendation:** **A** for correctness (preserves $425.68, models the combined obligation in Week 28,
posting-week accurate) — but it requires a reviewed B1-fix deploy and is **not** safely same-day.
**C** is the only plausibly same-day path (no deploy, never touches $425.68) but is **not** posting-week
accurate and anchors the first frozen snapshot with a large Week-28 variance. **B not recommended** (rewrites
a real completion on the defective build). In all three, $1,118.74 additional Vio transfer is owed, and the
AMEX Gold $5,666.01 commitment must be created at the close.

## 6. Requested verdict + same-day sequence

**Please return:**
1. **A / B / C selection** (or an alternative), with rationale.
2. **If same-day completion is desired:** confirm whether **Option C's timing exception and first-close
   variance are acceptable** (Option A cannot be safely completed today — it needs a reviewed B1-fix deploy).

**Draft same-day sequence — ONLY if Fable selects C and accepts its trade-offs** (not executed; each step
still gated by Adam's per-step authorization and the §13 write-lock / no-drift reruns):
1. Submit the AMEX Gold $5,666.01 bank payment (independent operator action).
2. Edit Week 28 — update AMEX Gold estimate → actual $5,666.01 (outflow-only; safe); **do NOT enter the
   $1,752.26**.
3. Frozen-payload review (step 8): nine funded values; Adam IRA cumulative includes $61.06; commission-tax
   shows $425.68 done + $417.83 deferred; AMEX Gold reflects $5,666.01 in-flight (Truist actual not reduced).
4. Confirm the AMEX Gold Phase-2 commitment (§4 field spec) at the close.
5. Wrapper closeout → `{ok:true, mode:normal_closeout, week_num:6, snapshot_count:9}`.
6. Durable-state verify (9 `source=reconciliation`) + **no-drift rerun #1** (Baseline A/B unchanged) +
   Week-6 freeze.
7. Handle the Extra BK Pay $1,752.26 in **Week 29** (fresh week, PATH-A-safe): books $700.90 alongside the
   $417.83 carry-forward; execute the $1,118.74 Vio transfer there.
8. Gate 4 / Phase 2 only after the freeze/proofs, with **no-drift rerun #2** immediately before revokes.

If Fable selects **A**, same-day is declined; the B1 fix ships as its own reviewed change first, then a
follow-up closeout sitting.

---
**No production mutation, code change, Week-28 edit, closeout, Phase 2, deploy, or push has occurred.**
Gate 3 remains HARD-STOPPED pending this verdict + Adam's authorization.
