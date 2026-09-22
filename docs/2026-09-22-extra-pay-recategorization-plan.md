# Adam Extra Pay — data plan (2026-09-22)

Companion to `2026-09-22-income-extra-pay-category.sql`. **Nothing here has been executed.**
No production row was changed by this session; every query run was read-only.

## Owner decisions (2026-09-22)
- Key `income.extra_pay`, label **"Adam Extra Pay"**. Wendy's `income.bkcpa_extra_pay` unchanged.
- Adam's budgeted salary base = **$5,816.50**.
- **"Start clean going forward"** — history is not retroactively split.
- **De minimis threshold $50** — only net pay more than $50 over the base moves to Extra Pay.

## Sequencing
All of this happens in the **Release A sitting, after the 2026-09-26 A1b sitting closes**. The
category row cannot precede A1b (see the SQL header: INV-C → HOLD). The Register edits below
need the category to exist first, so they follow it in the same sitting.

## Act on

| Row | Date | Amount | From → To | Why |
|---|---|---|---|---|
| `54955374` | 2026-09-04 | $411.14 | `income.bkcpa_extra_pay` → `income.extra_pay` | Adam's Jabian FICA-threshold row, parked in Wendy's category. Wendy: *"it's in Wendy's Extra BK for now until you set up a category for it."* Moved there by the household on 2026-09-22; this is its intended home. |
| ~~`d3da2b55`~~ | 2026-09-22 | $5,838.84 | ~~split~~ **no action** | Superseded by the $50 de minimis decision below: $22.34 over base is under the threshold, so it stays a single Net Salary row. |

## Leave alone

| Row | Date | Amount | Why not |
|---|---|---|---|
| `464acee6` | 2026-07-22 | $22.26, memo "Extra", in `income.net_salary` | **`updated_at` = 2026-09-18 02:01:35Z, inside the C1/R1 production sitting window** (`p3b-1-production-20260918T011833Z`, opened 01:18:33Z). It is almost certainly one of R1's 50 reviewed targets. Confirm against the sealed closeout manifest before ever touching it. Moving it would put live data out of step with frozen evidence. |
| `1a15a163` / `cf8171cf` | 2026-08-07 / 08-21 | $5,838.95 each | ~$22.45 above base is folded in, not split out. Owner ruling: start clean going forward. |
| `50202ec7` / `ecc8c538` | 2026-07-07 / 07-22 | $5,816.72 each | History. |

## Going-forward rule
Budgeted salary → `income.net_salary`. Net pay above $5,816.50 → `income.extra_pay` ("Adam Extra Pay").
Wendy's budgeted salary → `income.net_salary_spouse` ($2,152.50, already clean); her supplemental
BK pay → `income.bkcpa_extra_pay`, unchanged.

### De minimis threshold: $50 (owner decision, 2026-09-22)

**Split to Extra Pay only when net pay exceeds the budgeted base by more than $50.**
Anything at or under $50 stays in Net Salary as ordinary withholding drift.

Why a threshold was needed: $5,816.50 is the *lowest* of the six observed 2026 nets, so without one
almost every paycheck throws a remainder, most of them noise.

| Paycheck | Net | Over base | Under the $50 rule |
|---|---|---|---|
| 2026-07-07 | 5,816.72 | $0.22 | stays in Net Salary |
| 2026-07-22 | 5,816.72 | $0.22 | stays in Net Salary |
| 2026-08-07 | 5,838.95 | $22.45 | stays in Net Salary |
| 2026-08-21 | 5,838.95 | $22.45 | stays in Net Salary |
| 2026-09-04 | 5,816.50 | $0.00 | stays in Net Salary |
| 2026-09-22 | 5,838.84 | $22.34 | **stays in Net Salary** |
| 2026-09-04 (FICA) | +411.14 | $411.14 | **→ Adam Extra Pay** |

The threshold is a household data-entry rule, not enforced in code. Nothing in `index.html`
implements or checks it.

#### Consequence: the 2026-09-22 paycheck is no longer split
Row `d3da2b55` is $22.34 over base, under the threshold. It **stays as a single $5,838.84 row in
`income.net_salary`** and needs no edit. That empties the "act on" list down to one item: moving the
$411.14 FICA row. See the table above, which this decision supersedes.

### Note on the FICA row
"Extra due to Fica" is not additional earnings: Adam crossed the Social Security wage base, so OASDI
withholding stopped and net pay rose on the same gross. It **reverses in January**, which matters for
the 2027 rollover model. Filing it under Extra Pay is right for cash tracking; the memo carries the
cause. Do not model it as recurring income.
