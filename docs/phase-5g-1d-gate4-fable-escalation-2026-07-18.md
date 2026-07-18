# Phase 5G-1D — Fable escalation: Gate-4 HARD STOP (Week-29 Adam IRA duplicate) — 2026-07-18

**Ask: root-cause classification + disposition (proceed / defer-under-control / correct-first), and how any
fix reconciles with the active Week-6 freeze.** Full record:
`docs/phase-5g-1d-gate4-hardstop-adam-ira-duplicate-2026-07-18.md`. **No production change; Week 6 frozen;
nothing pushed.**

## Situation

After a verified wk6 closeout (Step-11R PASS: 1 recon row, 9 `source=reconciliation` snapshots,
`weekly_tasks` unchanged, Baselines A/B unchanged, no wk7+ drift) and with the Week-6 freeze ACTIVE, the
detailed Gate-4 Point-of-No-Return review found a **clickable/actionable Week-29 (Cal Wk 29) PLANNED
transfer: "Transfer $61.06 from Truist Checking to AMEX Savings (Adam IRA)."** Week 28 correctly shows the
executed `$61.06` history. The earlier UI-Check-1 PASS is superseded.

## Governing sections

- **Operator package §2b POST-CLOSE VERIFICATION** — "**Hard stop** if a later-week Adam IRA recommendation
  reappears → the anchor did not absorb the execution; **do NOT run Phase 2 revokes; investigate.**"
- **Checklist §I** ("post-close: zero later-week Adam IRA recommendation") + Point-of-No-Return "No duplicate
  Adam IRA recommendation" — **FAILED.**
- **`docs/phase-5g-1b-openwindow-netting-2026-07-15.md`** (the deployed suppression control) and e2e
  **`5G1B-NET-E2`** ("after wk6 closeout no later-week Adam IRA recommendation is emitted") — contradicted by
  production.
- **§13 / 5G-1D-HIST-1** does **not** apply (that carve-out is reconciled Weeks 1–5; Week 29 is open).

## Observed evidence

- Week 29: **clickable PLANNED** `$61.06` adam_ira transfer (not a fail-closed "Review required" block, not a
  read-only "Executed earlier" item).
- Week 28: executed `$61.06` `goal_adam_ira` completion (persisted `61.06`, keyed/labeled) — unchanged.
- Durable closeout verified; Week-6 freeze active; before-image captured local-only.

## Read-only investigation (proposed; not yet run)

I-1 persisted wk6 `adam_ira` snapshot value (incl. `$61.06`?); I-2 renderer's funded target + remaining;
I-3 Week-29 snapshot-boundary selection (`computeGoalTransferNetting.boundaryByGoal`, `_goalSnapLoadStatus`);
I-4 completed open-window credit recognition; I-5 why netting emitted `normal` (actionable) not suppressed;
I-6 classification: **data-state / resolver-identity / snapshot-loading / renderer-logic.**

## Decision options

- **A — Investigate-then-decide (recommended):** run I-1…I-6 read-only, classify the root cause, then choose
  B/C/D below. No Phase 2 until classified.
- **B — Data-state (wk6 snapshot omitted the `$61.06`):** the durable anchor is wrong → the recommendation is
  "correct but unwanted." ⚠ **Conflict:** correcting the wk6 `adam_ira` snapshot is barred by the Week-6
  freeze (§7) until after both proofs — this would force a freeze/Phase-2 re-plan. Needs explicit owner ruling.
- **C — Display/netting-only (durable snapshot correct; suppression not applied at Week 29):** possibly a
  bounded display defect. Unlike HIST-1, Week 29 is **open** and the row is **clickable** (a stray click
  mutates), so an operator write-lock alone is weaker; assess whether a resolver/netting correction is
  required before Phase 2, or a strict "do-not-touch Week 29" control suffices interim.
- **D — Block/slip:** hold Phase 2 (and the sitting) until a reviewed fix ships; the §2b hard stop already
  mandates no Phase 2 until investigated.

## Requested disposition

1. Confirm the I-6 root-cause class from the read-only evidence.
2. Rule whether Phase 2 may proceed at all before resolution (default: **no**, per §2b).
3. If a wk6-snapshot correction is implicated, rule how it reconciles with the **Week-6 freeze** (proofs
   assume byte-identical Week-6 state).
4. Specify the interim control for the clickable Week-29 row (do-not-touch vs code fix required first).

Constraints unchanged: no Phase 2, no Week-6 mutation, no grants/snapshots/recon/weekly_tasks change, no
push. Gate 4 HARD-STOPPED.
