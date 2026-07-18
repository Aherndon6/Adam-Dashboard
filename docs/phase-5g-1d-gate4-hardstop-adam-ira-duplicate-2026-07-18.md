# Phase 5G-1D — Gate-4 HARD STOP: Week-29 Adam IRA duplicate recommendation (2026-07-18)

**Status: 🛑 GATE-4 HARD STOP. Phase-2 revokes BLOCKED under operator package §2b. No production change,
no commit/push pending owner review.** Companions: operator package §2b (POST-CLOSE VERIFICATION), checklist
§I/§J; `docs/phase-5g-1b-openwindow-netting-2026-07-15.md`; e2e `5G1B-NET-E2`.

## 1. Incident

During the detailed Gate-4 Point-of-No-Return UI review, Week 29 (Cal Wk 29) shows a **clickable/actionable
PLANNED transfer**:

> **Transfer $61.06 from Truist Checking to AMEX Savings (Adam IRA)**

Week 28 correctly shows the historical **executed** `$61.06` item. This is a **later-week (Cal Wk 29+)
actionable Adam IRA recommendation reappearing after the wk6 closeout** — the open-window duplicate the
netting control is supposed to suppress once the snapshot boundary advances.

## 2. Earlier UI Check 1 PASS — SUPERSEDED

The initial UI Check 1 was reported PASS ("no later-week actionable Adam IRA recommendation; Week 29 shows
only the completed historical funded item"). The **detailed** Gate-4 review found the clickable Week-29
PLANNED `$61.06` row. **The earlier PASS is SUPERSEDED by this finding.**

## 3. Governing determination — committed §2b hard stop

Operator package **§2b POST-CLOSE VERIFICATION** (verbatim): *"**zero later-week (Cal Wk 29+) Adam IRA
transfer recommendations** remain … **Hard stop** if a later-week Adam IRA recommendation reappears → the
anchor did not absorb the execution; **do NOT run Phase 2 revokes; investigate.**"* Corroborated by checklist
§I ("post-close: zero later-week Adam IRA recommendation") + the Point-of-No-Return "No duplicate Adam IRA
recommendation", the netting-control spec, and e2e `5G1B-NET-E2`.

- **Point-of-No-Return "No duplicate Adam IRA recommendation" = FAILED.**
- **Phase-2 revokes = BLOCKED under §2b.**
- **Not** within the §13/5G-1D-HIST-1 legacy-display carve-out (that covers reconciled **Weeks 1–5**;
  Week 29 is an **open** future week). A clickable PLANNED row (not a fail-closed "Review required" block,
  not a read-only "Executed earlier" item) means the netting did not step back to the durable wk6 snapshot.

## 4. Operational guardrail (in force now)

**Do NOT click/execute the Week-29 `$61.06` Adam IRA transfer** — it is the already-executed obligation
re-surfacing; completing it would create a real duplicate transfer/completion. Leave it untouched; preserve
evidence. No Week-6 mutation (freeze active). No Phase 2.

## 5. Read-only investigation plan (NOT executed yet)

All steps read-only (SQL `SELECT` / code inspection); execution deferred pending owner authorization.

| # | Question | Read-only method (to run later) |
|---|---|---|
| I-1 | **Persisted Week-6 `adam_ira` snapshot value** — did the closeout snapshot record the cumulative funded value *including* the executed `$61.06` (i.e., adam_ira at/near target)? | `select * from public.goal_funding_snapshots where model_year=2026 and week_num=6 and goal_id = 'adam_ira';` — inspect the persisted funded value + `source`. |
| I-2 | **Funded target + remaining used by the live renderer** — what target and remaining does the renderer compute for adam_ira that drives the Week-29 recommendation? | Code: `GOALS_REGISTRY` adam_ira `target`; `getGoalFunded(adam_ira)` / remaining derivation (index.html). Compare to I-1's snapshot value. |
| I-3 | **Snapshot-boundary selection for Week 29** — did the boundary for adam_ira advance to wk6 post-close, or is it stale/open-horizon? | Code: `computeGoalTransferNetting` `boundaryByGoal` (index.html ≈3288+); `_goalSnapLoadStatus === 'loaded'` gate; the boundary the renderer uses for Week 29. |
| I-4 | **Completed open-window credit recognition** — is the executed `$61.06` `goal_adam_ira` completion recognized/credited by the netting (action_key + completed_amount)? | SQL: the wk6 `goal_adam_ira` completion (already: 61.06, keyed); code: how netting reads/credits the completion vs the snapshot. |
| I-5 | **Why the deployed netting emitted an actionable row** — for adam_ira @ Week 29: classification (`target_accumulation`), cumulative target vs funded, disposition (normal/suppressed/blocked). Why `normal` (actionable) not suppressed? | Code trace: `computeGoalTransferNetting` for adam_ira at Week 29; inputs (`goalSnapData`, `reconData`, registry). |
| I-6 | **Defect classification** — is it (a) **data-state** (snapshot omitted the `$61.06` → adam_ira appears underfunded → recommendation "correct but unwanted"); (b) **resolver identity** (completion not matched to adam_ira); (c) **snapshot loading** (`goalSnapData`/`_goalSnapLoadStatus` not loaded → netting fails open / stale boundary); or (d) **renderer logic** (recommendation emitted despite netting suppression)? | Synthesis of I-1…I-5. |

## 6. Disposition

Blocked pending Fable + owner. If I-6 = **data-state (snapshot wrong)**, note a conflict: correcting the
wk6 `adam_ira` snapshot is barred by the **Week-6 freeze (§7)** until after both proofs — so the disposition
must reconcile the defect fix against the freeze. **No production change until dispositioned.**

## 7. S1 result — classification A (SHORT Week-6 snapshot; data-state)

Read-only S1 (`goal_funding_snapshots`, adam_ira, wk5/wk6): Week-5 funded `7438.94`; Week-6 funded
`7438.94`; **delta `0.00`**. Target `7500.00` (`7438.94 + 61.06`). The executed open-window `$61.06` was
**NOT absorbed** into the wk6 snapshot → the durable anchor is short → the Week-29 clickable `$61.06`
recommendation is a true **data-state** consequence, not render-only.

## 8. Root-cause finding (on collected evidence)

- **#2 wrapper — RULED OUT:** persisted `7438.94` = the model prefill; e2e `5G1D-CO-9` (persisted must match confirmed).
- **#4 Step-11R value-verification gap — MOST LIKELY:** §14.1/Step-11R asserted counts + `weekly_tasks`, never a snapshot **value**; a single `adam_ira = 7500.00` check would have caught it.
- **#1 operator error — POSSIBLE/contributing:** §2b "Week-6 cumulative value" required including the `$61.06` ("Go Back and correct if omitted"); the short prefill was confirmed as-is.
- **#3 confirmation-UX — POSSIBLE/contributing:** prefill = model value (excludes the open-window `$61.06`); the "include it" rule was doc-only, not UI-enforced; the write path does not read `weekly_tasks` (§14.4).
- **#5 combination — YES:** #4 + #1 + #3 over a **#5 open-window model limitation** (prefill/netting exclude executed open-window transfers — same root as the Week-29 duplicate).

## 9. Owner disposition — D1–D7 ADOPTED (this incident is DISPOSITIONED)

Authoritative record: **operator package §14.6** — D1 exceptional recovery ordering (no-drift rerun #2 →
revokes → validation → Proof A → Proof B → release freeze → Option B correction; narrow, no precedent, no
revoke-SQL weakening); D2 conditional post-Proof-B Option B (adam_ira/2026/wk6, prior `7438.94` → `7500.00`,
note cites this incident, expect `ok=true`+`corrected=true`, stop on any mismatch/drift); D3 interim
no-click (the `$61.06` never re-executed); D4 Amendment A independently-derived value verification; D5 B1
scope (open-window prefill/credit + pre-submit block); D6 post-correction 8+1 partition (revoke precondition
unchanged, runs before the correction); D7 docs commit. **Binding: after Option B, the original frozen
payload must NEVER be resubmitted for wk6.**
