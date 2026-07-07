# 5G-0 Finding / 5G-1 Input — Weekly Model Transfer Issues

Date: 2026-07-07. Captured during 5G-0. **No code changed.** 5G-0 scope is LOCKED to label/docs cleanup only (per `CODEX_STATUS.md`), so both issues below are documented as findings and routed to 5G-1+; neither is included in or blocks 5G-0.

Adam raised two Weekly Model issues while 5G-0 was in flight, with an explicit ask: verify whether transfer destination is a display string or structured model/account data, because if it's structured it affects account projections and reconciliation (AMEX Savings would increase by $1,100).

---

## Verification result: transfer routing is STRUCTURED, and it is NOT the `dest` string field

There are two independent representations of a transfer's destination, and they are currently inconsistent for RCCL/DCL:

1. **`gdef.dest` — display string only.** `GOALS_REGISTRY` rows carry a `dest` label (e.g. `wewe_rccl.dest = 'RCCL payment'`, `wewe_dcl.dest = 'DCL payment'`, `adam_ira.dest = 'AMEX Savings (IRA Holding)'`). This string only feeds UI labels: the transfer action text (`dstLbl` at `index.html:2460`), the route chips (`index.html:4358`, `index.html:4728`). It never moves money.

2. **The `dst` code — structured model routing.** Actual money movement in `runModel` goes through `mv(amt, dst, allowFinal)` (`index.html:2254`), where `dst` is a hardcoded account code that maps to one of the five tracked model accounts: `chk`, `sav` (Truist Savings), `amx` (AMEX Savings), `tax` (Vio), `lc` (Lending Club) — or the sentinel `'goal'`, which **deducts from checking with no destination account tracked** (`index.html:2262`: "'goal': deducted from checking; external destination — no model account tracked").

The goal→`dst` mapping is a single ternary at **`index.html:2434`**:

```js
var _amxHold=['adam_ira','wendy_ira','bailey_529','bryce_529','preston_529']; // line 2425
var dst = goalId==='alaska' ? 'sav'
        : (_amxHold.indexOf(goalId)>=0 ? 'amx' : 'goal');
```

So today:
- `alaska` → `sav` (Truist Savings increases — tracked)
- IRA/529 goals → `amx` (AMEX Savings increases — tracked)
- **`wewe_rccl`, `wewe_dcl`, and all other goals → `'goal'`** → leave Truist Checking, go to an **untracked external destination**. AMEX Savings does **not** increase.

**Bottom line for Adam's question:** the routing is structured model data, but it lives in the `dst` ternary (`index.html:2434`), not in the `dest` string. RCCL/DCL currently route to `'goal'` (external, untracked) — neither the display string ("RCCL payment"/"DCL payment") nor the structural routing sends them to AMEX Savings today.

---

## Issue 2 — Week 27 RCCL/DCL routing to AMEX Savings (holding)

**Requested:** Wewe RCCL $600 and Wewe DCL $500 should transfer Truist Checking → AMEX Savings as holding funds (not direct RCCL/DCL payments). AMEX Savings should increase by **$1,100**.

**Current model behavior:** both route to `dst='goal'` → money leaves checking, AMEX Savings unchanged. So the requested change **is** a structured model-projection change, exactly as Adam suspected. Implemented, it would raise modeled `mAmx` by $1,100 in and after the funding weeks and shift reconciliation expectations for AMEX Savings.

**This is a `runModel` internals change, which is on the Do Not Touch list** ("runModel internals frozen through 5G-2" — `AGENTS.md` / `CODEX_STATUS.md`). It cannot be a quick display patch. Options for 5G-1+:
- Add `wewe_rccl`/`wewe_dcl` to `_amxHold` so `dst='amx'`. **Caveat:** `_amxHold` also drives (a) the 5-week AMEX-sweep lookahead safety gate (`index.html:2437-2445`) and (b) the `needsFlag` bypass (`index.html:2426`). Adding them subjects RCCL/DCL to AMEX lookahead gating and changes their `needsFlag` handling — this is a behavior change beyond just the account they land in, not a one-liner.
- Or introduce a dedicated "holding in AMEX Savings" routing that lands in `amx` without inheriting the full `_amxHold` gating semantics. Cleaner but more design.
- Also update the `dest` display strings so the UI label matches the new destination (currently "RCCL payment"/"DCL payment").

Recommend this go through the 5G-1 schema/build gate with a deliberate decision on gating semantics, not a patch during 5G-0.

## Issue 1 — Transfer execution timing / readiness labels

**Requested:** Week 27 transfers are dated Jul 5 (week start), but several depend on Adam's paycheck clearing Jul 7. Need a readiness/due label like "After Adam paycheck clears — target Jul 7" for paycheck-funded transfers.

**Current model behavior:**
- Transfer actions are label strings pushed into `ac[]` with a parallel `acKeys[]` (`runModel`); they carry a label, an action key, a result code, and a reason — but **no readiness/dependency/due-date field**.
- The date shown next to each transfer is `getWeekDate(w.num)` (`index.html:4112`), which is the **week-start date** — one date for the whole week, not per transfer (`getWeekDate` at `index.html:7759`).
- Paydays are modeled only at week granularity: `PAYCHECK_WKS=[3,5,7,9,11,14,16,18,20,22,24,27,29,31]` (`index.html:2194`). Week 27 = model week 5, which is a paycheck week — but there is no day-level payday and no link tagging a transfer as "funded by this week's paycheck."

**So this is a genuine structural gap, not just a display string.** There is no per-transfer readiness/due concept to hang the label on. Delivering it well means adding a small structured field (e.g. a `readiness`/`fundedBy` tag on paycheck-dependent model actions, plus a payday date per paycheck week) and rendering it. A pure display hack (hardcode a string in the Transfers section) is possible but would be a special-case that doesn't generalize and risks going stale.

Recommend 5G-1+ as a scoped "transfer readiness" slice. Lower risk than Issue 2 (doesn't necessarily touch the money-movement math), but still net-new structured model data, so out of 5G-0.

---

## 5G-0 disposition

- 5G-0 is label/docs cleanup only and touches neither transfer routing nor account reconciliation. **Neither issue needs to be included before closing 5G-0, and neither blocks it.**
- Both are 5G-1+ inputs. Issue 2 in particular touches frozen `runModel` internals (Do Not Touch through 5G-2) and changes account projections + reconciliation — it needs an explicit design decision and phase gate, not a display patch.
- Corrected framing for the roadmap: RCCL/DCL "destination" is not merely a label — the money-movement is real and currently routes them out of checking to an untracked external target, so "make AMEX Savings +$1,100" is a projection/reconciliation change, confirming Adam's read.

## Disposition — updated 2026-07-07 (5G-0 closed)

- 5G-0 is CLOSED; neither issue was included in it.
- Both issues are promoted into the **5G-1A CANDIDATE — Weekly Transfer Routing + Readiness** (see `CODEX_STATUS.md` for the locked desired scope). Issue 2 is 5G-1A core (items 1-5); Issue 1 (readiness labeling) folds into 5G-1A only if low-risk, else defers to 5G-1B.
- **Known real-world variance:** Adam will execute the Week 27 RCCL $600 + DCL $500 transfers to AMEX Savings manually after the 7/7 paycheck clears, and treats the resulting **$1,100 AMEX Savings variance as KNOWN/expected** until 5G-1A ships. Do not flag it as a reconciliation error in the interim.
- 5G-1A touches frozen `runModel` internals and must not start without Adam's explicit in-session go-ahead and a gating-semantics decision.
