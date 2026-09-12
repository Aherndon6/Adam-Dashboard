# Closeout — Register date-entry fix + test-baseline repair (2026-09-12)

Branch `fix/register-date-entry`, 4 commits off `origin/main` `1f03a37`. Fast-forward,
no conflicts. **Not pushed** — push is the owner's gate.

History document (append-only). The `CODEX_STATUS.md` pointer this work needs could not
be written in-session: the WI-3 publication freeze reserves that file to the WI-3 chat.
The proposed State text is in §5 below, ready to paste.

---

## 1. What shipped

| commit | what |
|---|---|
| `bda2e75` | Register New Transaction date field lost focus after one digit |
| `18401b4` | freeze pins, override tests, golden-master capture tool — 14 failures → 2 |
| `6b75e33` | golden-master re-capture — 2 → 0 |
| `228e3a7` | test counts removed from Law; pre-push gate added |

Static regression: **1788/14 → 1805/0**. e2e: 161 passed, 3 failed (see §3).

## 2. The Register defect

`_setTxFormField()` called `renderApp()` for `transaction_date`. The add form pre-fills
today's date, so the field always holds a complete valid value, and Chrome fires `change`
the instant a segment edit leaves it complete-and-valid. Typing `1` into the month
produced `2026-01-12`, committed, re-rendered the whole app, destroyed the
`<input type="date">` node mid-entry, and left `document.activeElement === <body>`. The
month stayed `1`, the second digit went nowhere, and Tab never reached Payee.

5E-8 introduced that `renderApp()` for one narrow reason — the category dropdown's option
labels are month-derived. `_regMonthIso` has no other consumer, so the labels are now
refreshed in place instead.

The tab-order complaint was the same defect. DOM order was already correct, there is no
`tabindex` anywhere in `index.html`, and Chrome traverses the date segments natively. No
ordering change was needed. Note the date input has **four** internal tab stops, not
three: month, day, year, and the built-in calendar-picker icon.

New coverage `RD-1`/`RD-2` in `e2e.js` drives **real keystrokes**. Every pre-existing
Register test set `_txFormData.transaction_date` directly and so never exercised the
native segment editor — which is exactly how this shipped past 1300+ tests.

## 3. Why the suite was red, and for how long

All 14 static failures came from **one commit**: `caed4737` (2026-08-08, card Phase 1
stabilization). The suite was 1802/0 at `caed4737~1`.

Characterised before any pin was moved: `runModel`'s numeric output is unchanged across
all 31 weeks except `week[0].totalTasks 4 -> 3` (a reminder count). Every cash, trough,
balance and goal figure is byte-identical. Corroboration: the `computeGoalTransferNetting`
and `resolveWeekTransfers` freeze pins still match their ORIGINAL values and were never
touched — only `runModel` moved. **`runModel`'s freeze is not lifted**; it stays frozen
until Calc-Core Extraction.

### The three e2e failures — engine is correct, tests are not

`5G1B-NET-E1`, `5G1B-NET-E3`, and the 5G-1C-2.1 anchor test fail because **the e2e suite
is not hermetic**. With `.env` present it authenticates to **production**
(`usayoldrawwmjsmretin`) as owner and runs against live household data:

```
DIAG_authState  ready     DIAG_goalsLoadStatus  loaded
DIAG_userRole   owner     DIAG_goals  {ak: 7000, rt: 7690.98}   DIAG_allIra  []
```

Unauthenticated, the identical code emits the residual correctly — `$61.06` at week 20,
`residCount: 1`, `seedCount: 0`, amount exactly `target − anchor`. Verified in Node and in
a real browser, with and without `clickNav`, across load delays, and across anchors from
7438.94 down to 6500.

The tests were written 07-11 and 07-15 against a production state where Adam IRA was short
exactly $61.06 — the number hardcoded in them. The 5G-1D activation on 2026-07-18 corrected
`adam_ira` 7438.94 → 7500.00, closing that shortfall, and the scenario stopped existing.

**There is no undetected money bug here.** The netting, write-guard and anchor-seed logic
are fine. But three money-adjacent behaviors have had no effective coverage since mid-July.

⚠️ **Method warning for whoever picks this up.** Bisecting e2e through history is
unreliable, because old code checked out today still runs against *today's* production
data. I initially concluded "these tests never passed" on exactly that confound. It was
wrong. Do not repeat it.

## 4. Other findings

- **Delete-override capability is orphaned.** `DELETEABLE_MODEL_ACTIONS` contains only
  `costco_visa`, whose emitter `caed4737` removed. No model action can currently be
  deleted. The one test covering it was passing **vacuously** — asserting an absence that
  was already true for the wrong reason. Replaced with a direct machinery test plus a pin
  that fails loudly if an emitter is ever restored.
- **Not every action key is override-aware.** The week-1 SETUP/EF injections are emitted
  unconditionally and never consult `actionOverrides`. `tax_base` is the correct vehicle.
- **e2e has no credentials fallback.** Without `.env` it hangs retrying against the auth
  overlay instead of failing fast.
- **`push_to_github.sh` stages with `git add -A`** — the same hazard behind the `388aacc`
  contamination. Left alone; changing it changes the owner's working flow.
- **Register date FILTER inputs have the same root cause** (`setTxFilter` → `renderApp`)
  and are worse: typing a full date into an empty filter yields `0002-10-05`, because the
  value "completes" after the first year digit. Focus-restore and defer-to-blur were both
  tested and are **actively harmful** (they blank the filter, and swallow the next click,
  respectively). The correct fix is re-rendering only the ledger table — a refactor of a
  Wendy-critical display path, not a surgical change. NOT done.

## 5. Proposed `CODEX_STATUS.md` insert (needs the WI-3 chat or a lifted freeze)

> **TEST BASELINE RE-ESTABLISHED (2026-09-12).** Measured on `fix/register-date-entry`
> (base `origin/main` `1f03a37`): **static 1805/0**; **e2e 161 passed / 3 failed**.
> The three e2e failures are `5G1B-NET-E1`, `5G1B-NET-E3` and the 5G-1C-2.1 anchor test.
> They are NOT engine defects — the suite authenticates to production and those tests
> depend on an Adam-IRA shortfall that the 5G-1D activation closed on 2026-07-18. Open
> task: make them hermetic, and decide whether e2e should authenticate to production at
> all. Until then e2e's expected state is 161/3, not green.
>
> Prior claims of `1332/0` and `130/0` in `AGENTS.md` were wrong and have been removed;
> per the rule added 2026-09-12, test counts live here in State, never in Law, and are
> recorded with the date and commit measured.

## 6. Ordering that matters

**Install the pre-push hook only AFTER this work reaches `main`.** Verified today: the
`wi-3-p2-reconciliation-state` branch runs **1788/14**. Installing first would block that
workstream's next push on failures it did not cause and cannot fix without merging this.
Hooks live in the shared git common dir, so installation affects every worktree at once.

```bash
bash scripts/install-hooks.sh      # AFTER the merge, not before
```

To remove: delete `pre-push` from `$(git rev-parse --git-common-dir)/hooks/`.

## 7. Open, ranked

1. Make the 3 e2e tests hermetic; decide whether e2e should hit production at all.
2. Register date-filter defect (§4) — needs the ledger-table partial-render refactor.
3. **DR-1 part 3** — documented + tested restore. This was the original objective of the
   2026-09-12 session and was never started; `AGENTS.md` has called backup/restore an
   immediate production-operability requirement since 2026-07-13.
