# Herndon Family Cash Flow Model — Full Specification

**Version:** Phase 4 production  
**Date:** Cal Wk 24 (Jun 14, 2026)  
**Test status:** 270 tests passing, 0 failing (`node test_regression.js`)

---

## 1. Overview

Single-file HTML dashboard (`index.html`) running a 31-week forward-looking cash flow model from Cal Wk 23 (Jun 7, 2026) through Cal Wk 53 (Jan 9, 2027).

- **Local only** — Supabase credentials embedded for reconciliation writes; waterfall model is pure client-side JavaScript.
- **Vanilla JS, no frameworks, no build step** — everything in one `<script>` block.
- **Week-indexed** — model weeks 1–31 map to calendar weeks 23–53 (cal wk = model wk + 22).
- **Direct waterfall** — each week, surplus above the operating floor sweeps directly from Truist Checking to goals in priority order. No intermediate pool accounts.

---

## 2. Account Structure

| Account | Starting Balance | Role |
|---|---|---|
| Truist Checking (`chk`) | $18,037.73 | Primary operating account. All inflows and outflows run through here. |
| Truist Savings (`sav`) | $3,772.77 | Alaska cruise savings staging. After Alaska funds, residual sweeps to AMEX via one-time `mvS`. |
| AMEX Savings (`amx`) | $103.64 | IRA and 529 holding account. Receives $3,772.74 savings seed when Alaska completes; then accumulates waterfall contributions for IRA/529 goals. |
| Vio Bank — Tax Reserve (`tax`) | $0.00 | Commission and income tax reserve. 40% of commission income routes here. |
| Lending Club / EF (`lc`) | $13,488.88 | Emergency fund. Static — no model transfers in or out. |

**Starting balances reflect completed Cal Wk 23 setup transfers:**
- $2,750 Truist Savings → Truist Checking
- $1,000 Lending Club → Truist Checking
- $2,250 Lending Club → Truist Checking (Option 1 correction)

---

## 3. Core Constants

```javascript
START_CHK    = 18037.73   // Truist Checking (post-setup)
START_SAV    =  3772.77   // Truist Savings (post-setup)
START_AMX    =   103.64   // AMEX Savings (initial IRA seed already in holding)
START_TAX    =     0.00   // Vio Bank Tax Reserve (empty at model start)
START_LC     = 13488.88   // Lending Club / EF (static)

OP_FL        =  6500.00   // Hard operating floor — mv() never pulls checking below this
MIN_XFR      =   100.00   // Minimum transfer; smaller amounts suppressed and carried forward
AK_START     =     5      // Model week waterfall begins (weeks 1–4 settle setup)
BASE_TAX     =   521.36   // Pre-existing tax liability — sweeps to Vio first eligible week
RET_SAV_XFR  =  3772.74   // One-time Truist Savings → AMEX when Alaska fully funds

COMM_TAX     =   707.18   // Commission: 40% of $1,767.94 → Vio Bank Tax Reserve (Cal Wk 28)
COMM_AK      =  1060.76   // Commission: 60% of $1,767.94 — labeled for Alaska; routes via waterfall

// goalAk = $7,000; IRA targets = $7,000 each (adam_ira, wendy_ira)
// adam_ira seeded at START_AMX = $103.64 in goalSaved at model start
```

---

## 4. Time Horizon

| Field | Value |
|---|---|
| Model weeks | 1–31 |
| Calendar weeks | 23–53 |
| Start | Jun 7, 2026 (Cal Wk 23) |
| End | Jan 9, 2027 (Cal Wk 53) |

---

## 5. Week Definition Array (WD)

Each week is an 8-element array: `[num, dates, [inflows], [bills], [events], ct, ca, calNote]`

`[inflows]` and `[bills]` are model calculation inputs. `[events]` are display labels only. When a user overrides a week, effective inflows/bills are re-derived from overridden events.

### 5.1 All 31 Weeks

| Wk | Cal Wk | Dates | Inflows | Bills | Notes |
|---|---|---|---|---|---|
| 1 | 23 | Jun 7–13 | — | $791 Kia | Setup week |
| 2 | 24 | Jun 14–20 | $2,552.50 Wendy | — | |
| 3 | 25 | Jun 21–27 | $5,816.50 Adam | $5,925.13 Disney Visa, $6,368.48 AMEX Plat | Last major Platinum bill |
| 4 | 26 | Jun 28–Jul 4 | $2,152.50 Wendy | $5,300 rent (3 Zelle) | July rent |
| 5 | 27 | Jul 5–11 | $5,816.50 Adam | $791 Kia | First waterfall week |
| 6 | 28 | Jul 12–18 | $1,767.94 commission, $2,152.50 Wendy | $5,500 Gold | Commission week; ct=COMM_TAX, ca=COMM_AK |
| 7 | 29 | Jul 19–25 | $5,816.50 Adam | $3,500 Disney Visa | |
| 8 | 30 | Jul 26–Aug 1 | $2,552.50 Wendy | $200 Plat stragglers, $2,000+$2,000 rent | Aug rent split: $4,000 in W8, $1,300 in W9 |
| 9 | 31 | Aug 2–8 | $5,816.50 Adam | $1,300 rent, $791 Kia | |
| 10 | 32 | Aug 9–15 | $2,152.50 Wendy | — | |
| 11 | 33 | Aug 16–22 | $5,816.50 Adam | $5,500 Gold, $3,500 Disney Visa | Double-bill week |
| 12 | 34 | Aug 23–29 | $2,552.50 Wendy | — | No bills, no Alaska draw |
| 13 | 35 | Aug 30–Sep 5 | — | $5,300 rent | Rent-only; lowest checking (~$4,908) |
| 14 | 36 | Sep 6–12 | $5,816.50 Adam, $2,152.50 Wendy | $791 Kia | Double paycheck |
| 15 | 37 | Sep 13–19 | — | $5,500 Gold | Code: `mvS(7000,'chk')` — $7k Alaska draw from savings |
| 16 | 38 | Sep 20–26 | $5,816.50 Adam, $2,552.50 Wendy | $3,500 Disney Visa | |
| 17 | 39 | Sep 27–Oct 3 | — | $5,300 rent | Rent-only |
| 18 | 40 | Oct 4–10 | $5,816.50 Adam, $2,152.50 Wendy | $791 Kia | |
| 19 | 41 | Oct 11–17 | — | $5,500 Gold | DCL due week |
| 20 | 42 | Oct 18–24 | $5,816.50 Adam, $2,552.50 Wendy | $3,500 Disney Visa | |
| 21 | 43 | Oct 25–31 | — | $2,000 rent (1 of 3) | Nov rent starts late Oct |
| 22 | 44 | Nov 1–7 | $5,816.50 Adam, $2,152.50 Wendy | $2,000+$1,300 rent, $791 Kia | |
| 23 | 45 | Nov 8–14 | — | — | Empty — no paycheck, no bills |
| 24 | 46 | Nov 15–21 | $5,816.50 Adam, $2,552.50 Wendy | $5,500 Gold | |
| 25 | 47 | Nov 22–28 | — | $3,500 Disney Visa | |
| 26 | 48 | Nov 29–Dec 5 | $2,152.50 Wendy | $5,300 rent | |
| 27 | 49 | Dec 6–12 | $5,816.50 Adam | $791 Kia | |
| 28 | 50 | Dec 13–19 | $2,552.50 Wendy | $5,500 Gold | |
| 29 | 51 | Dec 20–26 | $5,816.50 Adam | $3,500 Disney Visa | |
| 30 | 52 | Dec 27–Jan 2 | $2,152.50 Wendy | $5,300 rent | |
| 31 | 53 | Jan 3–9, 2027 | $5,816.50 Adam | $791 Kia | |

**Known thin weeks (floor violations):** W6 (~$4,999), W8 (~$4,961), W13 (~$4,908). Exactly 3 violations — locked by regression test.

---

## 6. Income Sources

**Adam paycheck:** $5,816.50 net biweekly. Weeks 3,5,7,9,11,14,16,18,20,22,24,27,29,31. 401(k) $1,020.83/paycheck deducted pre-tax — no checking impact.

**Wendy paycheck:** $2,152.50 (regular) or $2,552.50 (+$400 extra, alternating). Weeks 2,4,6,8,10,12,14,16,18,20,22,24,26,28,30.

**Deep South Commission (Wendy, Cal Wk 28 / W6):** $1,767.94 gross → checking. 40% ($707.18) → Vio via `mv(ct,'tax')`; remainder flows through normal waterfall.

---

## 7. Recurring Bills

**Rent:** $5,300/month in three Zelle transfers ($2,000+$2,000+$1,300) to Tiffany Dye. Due 1st–3rd. Distributed across weeks containing those dates.

**Kia:** $791/month, due 7th. Weeks 1,5,9,14,18,22,27,31.

**AMEX Gold:** ~$5,500/month, due ~17th. Weeks 6,11,15,19,24,28. Alaska charges (Aug 23–Sep 26) will elevate Sep/Oct statements — the W15 $7k draw provides cash to cover at reconciliation.

**Disney Visa:** ~$3,500/month, due ~23rd. Weeks 3 ($5,925.13 first statement — elevated), 7,11,16,20,25,29.

**AMEX Platinum:** W3 $6,368.48 (last major), W8 ~$200 stragglers. Done after W8.

---

## 8. Operating Floor and Look-Ahead

**Hard floor:** `OP_FL = $6,500`. `mv()` enforces this — never pulls checking below it. Three display tiers: $6,500 hard gate / $10,000 warning / $12,000 target.

**Look-ahead floor:**
```javascript
_laNetOut = max(0, next_week_outflows - next_week_inflows)
laFl = (_laNetOut > $3,000) ? OP_FL + _laNetOut : OP_FL
```
Raises effective floor before large-outflow weeks. Example: week before rent-only ($5,300 out, $0 in): laFl = $6,500 + $5,300 = $11,800.

---

## 9. Transfer Helpers

**`mv(amt, dst, allowFinal)`** — from Truist Checking, floor-enforced:
```
actual = min(amt, chk - laFl)
if actual <= 0: return 0
if actual < $100 and not allowFinal: suppress, return negative (carry forward)
chk -= actual; dst += actual; return actual
```
Destinations: `sav`, `amx`, `tax`, `lc`, `surplus`, `goal`.

**`mvS(amt, dst)`** — from Truist Savings, no floor:
```
sav -= amt; dst += amt
```
Destinations: `chk`, `amx`, `lc`.

---

## 10. Special Model Events

**W1 setup (historical):** Four completed EF injection transfers explain START_CHK. Shown as "done" in transfer log.

**W15 Alaska draw:** `if(num===15){mvS(7000,'chk');}` — code event, not in WD[]. CalNote describes it. W15 events[] has only Gold $5,500.

**IRA seed sweep (one-time, when Alaska completes):**
```javascript
if (goalSaved['alaska'] >= akTarget - 0.01 && !rtSavSwept) {
  const ms = mvS(RET_SAV_XFR, 'amx');   // $3,772.74 Savings → AMEX
  goalSaved['adam_ira'] += ms;            // credited to adam_ira
  rtSavSwept = true;
}
```
Fires same week Alaska funds (typically W5). Zero checking impact.

**401(k):** `PAYCHECK_WKS=[3,5,7,9,11,14,16,18,20,22,24,27,29,31]`, `PAY_401K=1020.83`. Pre-tax, no checking impact.

**Monthly Vio→LC boost:** Weeks 1,5,9,14,18,22,27,31 — reminder to move $250 Vio→LC. Weeks 14,27 — also $750 LC→Vio return first.

---

## 11. Goal Registry

| ID | Name | Tier | Target | Key Flags |
|---|---|---|---|---|
| `adam_401k` | Adam 401(k) | Retirement | $24,500 | auto=true; YTD $10,208 at model start |
| `wendy_sep` | Wendy SEP | Retirement | $17,859 | complete=true |
| `alaska` | Alaska Cruise | Travel | $7,000 | dest: sav |
| `wewe_rccl` | Wewe RCCL | Travel | $600 | startsAfter: alaska; dueWeek: 8 |
| `wewe_dcl` | Wewe DCL | Travel | $500 | startsAfter: alaska; dueWeek: 19 |
| `adam_ira` | Adam IRA | Retirement | $7,000 | needsFlag: ira_cpa_cleared; startsAfter: wewe_dcl; dest: amx |
| `wendy_ira` | Wendy IRA | Retirement | $7,000 | needsFlag: ira_cpa_cleared; dest: amx |
| `bailey_529` | Bailey 529 | Education | $3,500 | dest: amx |
| `bryce_529` | Bryce 529 | Education | $1,500 | dest: amx |
| `preston_529` | Preston 529 | Education | $1,000 | dest: amx |
| `bryce_vehicle` | Bryce Vehicle | Emerging | $8,000 | dest: external |
| `christmas_cruise` | Christmas Cruise | Travel | $5,000 | milestone: $2,500; dest: external |
| `taxable_etf` | Taxable ETF | Stretch | $4,999.79 | stretch=true; dest: external |

`retirement_rebuild` was removed in Phase 4. AMEX Savings is now a direct IRA/529 holding account, not a pool goal. No `poolSource` / `poolDeploys` properties remain.

---

## 12. Priority Tiers (T1–T11)

T1 Alaska → T2 Wewe RCCL → T3 Wewe DCL → T4 Adam IRA → T5 Wendy IRA → T6 Bailey 529 → T7 Bryce 529 → T8 Preston 529 → T9 Bryce Vehicle → T10 Christmas Cruise → T11 Taxable ETF (stretch)

---

## 13. Goal Waterfall

### 13.1 Arrays

```javascript
VARIABLE_WATERFALL = REGULAR_WATERFALL =
  ['alaska','wewe_rccl','wewe_dcl','adam_ira','wendy_ira',
   'bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']
```

### 13.2 Per-Week Execution Order

1. Apply inflows/bills to `chk`
2. W15: `mvS(7000,'chk')` — Alaska draw
3. 401(k) auto-contribution (paycheck weeks)
4. Commission tax → Vio; or tax backlog if non-commission week
5. Compute look-ahead floor (`laFl`)
6. **Waterfall loop** for each goal in order:
   - Break if `chk - laFl < $0.005`
   - Skip (continue) if `num < AK_START`
   - Skip (continue) if `startsAfter` dependency not yet funded (checks `goalSaved` + `justFunded{}` for same-run allocations)
   - **Break (strict)** if `needsFlag` not cleared → `hitGate=true`; all remaining shown as `hold` step
   - Skip if already funded
   - `mv(remaining, dst)` — allocate up to goal remaining or floor-limited surplus
7. IRA seed sweep (once, after waterfall, when Alaska completes)
8. Surplus: only if `!hitGate && remaining > $0.005`
9. `allFunded` check: gated goals count as unfunded — surplus blocked while IRA gate is closed

### 13.3 IRA Gate Detail

When `ira_cpa_cleared = false`:
- Waterfall reaches adam_ira → hard break
- `hitGate = true`; gate step shows `type: 'hold'`, `amt: remaining` (full blocked amount)
- No 529s, vehicle, cruise, or surplus receive funds
- Toggle "IRA CPA Cleared" in Goals tab to lift gate

### 13.4 justFunded Tracking

`justFunded{}` accumulates same-run allocations so `startsAfter` resolves within one deposit. Example: if wewe_dcl funds to completion in W7, adam_ira becomes eligible immediately in that same week's waterfall pass.

---

## 14. Decision Engine (runEngine)

```javascript
runEngine(amt, engineType, flags)
// Returns: [{type, num, label, amt, note}]
// type: 'goal' | 'hold' | 'surplus' | 'info'
```

Uses same waterfall arrays and gate logic as `runModel()`. Parity tested in Section 20.

---

## 15. Reconciliation and Override System

- **Reconciliation (`reconData`):** User enters actual end-of-week balances; model cascades forward from actuals.
- **Week overrides (`overrideData`):** User edits any week's events; effective inflows/bills re-derived.
- **Custom weeks:** User inserts new weeks for one-off events.

All data persisted to Supabase REST API.

---

## 16. Model Output — Per-Week Object

```javascript
{
  num, dates,
  chk, sav, amx, tax, lc,        // ending balances
  mChk, mSav, mAmx, mTax, mLc,  // model-projected (pre-reconciliation)
  goalSaved,                      // { goalId: cumulativeAmountFunded }
  akSaved, akRem,                 // alaska shortcuts
  retRem,                         // adam_ira remaining (backwards compat)
  ol,                             // chk + sav
  tr,                             // transfer log [{l, r, a, rsn}]
  ac,                             // action checklist string[]
  recActs,                        // monthly reminders
  reconciled, variance, actualBals,
  surplusSwept, surplusStart,
  totalTasks, doneTasks
}
```

---

## 17. Test Harness

**File:** `test_regression.js`  
**Run:** `node test_regression.js` (or `HFOS_INDEX=/path/to/index.html node test_regression.js`)  
**Count:** 270 tests, 0 failing

| Section | Coverage |
|---|---|
| 1–17 | Constants, WD structure, account math, balance trajectories, waterfall, goal lifecycle, render functions, UI HTML |
| 18 | Phase 4 regressions — bugs fixed in this build locked in |
| 19 | IRA gate: locked vs cleared, 14 tests covering surplus suppression, goal blocking, clearing behavior |
| 20 | Decision Engine / runModel parity (8 tests) |
| 21 | Mutation guards — 6 intentional breaks, each must be caught |

**Mutation guards (Section 21):** A) 529 before IRA reorder, B) AK_START=2, C) OP_FL=$8,000, D) needsFlag removed from adam_ira, E) adam_ira/wendy_ira waterfall swap, F) RET_SAV_XFR=0.

---

## 18. Phase 5 Wishlist

1. Supabase live data connection
2. Ask Claude API key security (Supabase Edge Function proxy)
3. Playwright e2e activation (`e2e.js` already written)
4. Costco Visa modeling (pending date confirmation)
5. Mobile UI polish

---

## 19. Technology Stack

| Component | Details |
|---|---|
| Frontend | Single HTML file, vanilla JS, inline CSS |
| Backend | Supabase (PostgreSQL + REST API) |
| Persisted | Reconciliation, overrides, task completion, notes, wishlist |
| Computed | All model projections (recomputed each render) |
| Unit tests | `test_regression.js` — Node.js, 270 tests |
| E2E tests | `e2e.js` — Playwright (Phase 5) |

---

*Source of truth: `index.html`. `curr_runModel.js` is a stale tombstone — do not use.*
