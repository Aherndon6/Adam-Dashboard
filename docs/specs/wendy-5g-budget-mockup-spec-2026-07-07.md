# Wendy 5G Budget / Cash Planning: Mockup Narrative and Screen-Flow Spec

**Version:** 1.2 (final). Supersedes v1.1 and the 2026-07-07 draft. **Date:** 2026-07-07 **Type:** Mockup spec. Not code, not a redesign, not implementation authority. **Status:** Final. All ten decisions confirmed by Adam 2026-07-07, including the corrected small-line amber rule and the soft convention for Set Aside writes. No open items. Treatment authority for UX-0 and the 5G mock frames. **Executes:** Sequencing option (a) from CODEX\_STATUS. 5G-0 scope locked separately (Section 9, decision 10). **Inputs:** UI/Flow Review v2 (`docs/reviews/ui-flow-review-triage-2026-07-07.md`), findings BUD-1, BUD-2, SYS-3; locked 5G architecture per `docs/phase-status.md`; AGENTS.md Do Not Touch list. **Inherited standards (do not reopen):** SYS-1 naming (Statement check, no phase strings), SYS-2 money format, Accounts status pills as the chip vocabulary (WK-1), FLOW-1 disabled-control-plus-live-link pattern, 5G-0 "Available for Goals" label. **Override rule:** Findings are hypotheses. Wendy's confirmed workflow wins.

**Guardrails restated:** No schema changes. No fake Register transactions. No fake Budget Clearance account. No Budget identity change before 5G-3. Register stays source of truth for actuals. Budget stays plan / spent / remaining / reporting. Nav change is exactly one new "Cash Planning" item under Planning next to Goals. Nothing else moves.

---

## 1\. Wendy-facing explanation (plain language)

Read this to Wendy as written.

Nothing about how you work changes before Alaska. You still enter every real transaction in Register. Budget still shows plan, spent, and remaining, and it still balances. The weekly closeout still uses real bank balances. The Quicken parallel run continues untouched.

Two things are coming. One is small, one is new.

The small one: the line called "Extra Pay Going to Spreadsheet" gets a clearer name, "Available for Goals." Same number, same row, same behavior. It is the money left over after planned spending, the part we can point at goals. Only the name changes for now. Later in the fall, after your July feedback, that line will start calculating itself. Today Adam hand-adjusts it so the budget lands on zero. After the change, the app does that math: income minus planned spending equals Available for Goals, automatically. The budget still balances. It just stops needing a manual nudge to get there.

The new one: a Cash Planning page, next to Goals. It answers a question Budget was never built to answer: of the money sitting in our accounts right now, how much is already spoken for by bills that have not hit yet, and how much is truly free? Think of Save-Up Bills as labeled jars. When we set money aside for the Mint Mobile renewals, we are labeling that money, not spending it. Nothing shows as "spent" anywhere until the real payment happens and gets entered in Register, once, like every other transaction. So nothing ever counts twice. Budget's Spent numbers stay tied to real card and bank activity only, and Cash Planning just keeps track of which dollars are already promised.

One honest wrinkle, said plainly so it never surprises you. For set-asides where money actually moves, like the Mint transfers to AMEX Savings, there are two entries. The real transfer goes in Register, the same as any transaction. The set-aside label goes in Cash Planning. That is not double-counting: one records money moving, the other records a plan. Adam records the Cash Planning side for now; you can see all of it.

Your weekly closeout does not change either. The balances you type in are still the real bank numbers. Planned bills never sneak into that check.

Two smaller fixes ride along. First, red will mean exactly one thing in Budget: a category actually over its budget. Right now income rows show red just because money has not arrived yet, which is normal, not a problem. That stops. Second, when a panel is empty, it will say why and what to do next, instead of looking broken. The panel at the bottom of Budget that says "No transactions for this period" in a month full of transactions is the first one getting fixed.

## 2\. Screen-flow sequence

**Flow A. Enter spending (unchanged).** Transactions, Register, Add Transaction, payee/amount/category/account, save. Budget's Spent picks it up automatically.

**Flow B. Monthly budget check (Budget, new color meanings).** Open Budget. Scan the grid: neutral rows are fine, amber rows are near their limit, red rows are over. Click a red row's label or Spent to open the category report. If something needs fixing, the fix happens in Register, and the report links there.

**Flow C. Weekly closeout (unchanged).** Weekly Model, current week, Reconcile, phases 0 through 4, real balances typed in from the bank. No Cash Planning data enters this flow.

**Flow D. Cash Planning review (new, roughly weekly).** Planning, Cash Planning. Top: allocation placeholder in v1, then the allocation strip when 5G-2 ships (Spoken For plus Free to Use equals Balance, per account). Middle: Upcoming Spend, anything due inside the 6-week horizon. Bottom: Save-Up Bills, each showing target, due date, set aside so far, and a status pill. Set Aside events are recorded by Adam in v1; Wendy views everything.

**Flow E. Paying a Save-Up Bill (the no-double-count proof).** Bill comes due. Pay it for real. Enter the payment in Register once, normal categorization rules apply. In Cash Planning, mark the bill Paid. The jar empties, Spoken For drops, Free to Use rises. Budget saw the payment exactly once, through Register.

**Flow F. Available for Goals, later (5G-3).** Budget's balance area becomes an identity strip: Income minus Planned equals Available for Goals, calculated. The hand-adjusted sweep edit disappears. Everything else on the page reads the same.

## 3\. What changes on Budget: now vs later

| Element | Now (pre-Alaska) | Later (5G-3, post-Alaska, gated) |
| :---- | :---- | :---- |
| Sweep line label | Renamed "Available for Goals" (5G-0) | Same label |
| Sweep line value | Hand-set by Adam, balances plan to zero | Derived: income minus planned; edit control removed |
| Balance footer | Balanced check / out-of-balance amber banner, unchanged | Banner retired; identity strip replaces it (out of balance impossible by construction) |
| Income rows | Remaining stops rendering red; muted "expected" treatment (UX-0) | Budgeted income lines only; variable income stays model-side |
| Expense row states | Over \= red, near \= amber, under \= neutral (UX-0, rule in Section 6\) | Same |
| Row actions | Edit/Archive demoted to neutral; amber-dark confirms (UX-0) | Same |
| Empty panels | Say why and next step, with live Register link (UX-0; BUD-2, FLOW-1 pattern) | Same standard |
| "Reconciliation" block | Retitled "Statement check"; phase strings stripped (5G-0, SYS-1) | Same |
| Spent source | Register plus legacy rows, unchanged mechanics | Unchanged |
| Identity math | Untouched | Changes only here, behind its gates |

**Implementation routing (decision 10):** 5G-0 stays label/docs cleanup only: Available for Goals rename, SYS-1, SYS-4 exact strings, WK-6. No Budget row treatment work in 5G-0. BUD-1, BUD-2, and SYS-3 land as a named UX-0 slice immediately after 5G-0 (or inside the pre-5G bundle if that ships first), display-only, before 5G-1 tables inherit styles. If the pre-5G bundle does not ship, SYS-2 money format becomes a 5G-1 day-one standard for new surfaces per the triage.

## 4\. What belongs in Cash Planning

One nav item under Planning, next to Goals, visible to Wendy at 5G-1 (decision 8). Four blocks, top to bottom.

**Allocation strip (5G-2).** Identity strip, same pattern as the Budget balanced footer: Spoken For \+ Free to Use \= Balance, total and per account as stat tiles. Derived, read-only, never a stored ledger. Uses posted balances. In the live 5G-1 release, before this ships, the page carries one quiet line in its place: "Account allocation (Spoken For / Free to Use) arrives in the next update."

**Upcoming Spend.** Planned outflows due inside 6 weeks (decision 5), grouped by due date. Each row: label, amount, due date, source account, funding badge (Transfer to AMEX Savings for Mint), status pill. Reuses the existing transfer status vocabulary; per the WK-1 lesson, dollars that already have a status representation do not get a second one.

**Save-Up Bills.** One card per accruing bill, small-caps header. Fields: target amount, due date, set aside so far, funded amount, remaining to set aside. Status pills from the Accounts pill system: Accruing, Funded, Paid. Actions: Set Aside, Adjust, Mark Paid. The two Mint rows (Adam due 2027-02-01, Bailey due 2027-05-23) show an out-of-window note: "Accrues now; due beyond the current model window."

**Activity log.** Read-only per-bill drawer listing Set Aside / Paid / Adjust entries, newest first. Append-only by design; no edit or delete of history.

Plus the collapsible help link: "How Cash Planning works," carrying the not-an-expense explainer and this v1 line: "Adam records set-aside entries for now."

**Event recording in v1 (decision 6, confirmed):** Adam records Set Aside / Adjust / Mark Paid events at first, by household convention. Wendy views everything. No new owner-only role logic for Cash Planning writes and no isOwnerUser() gate on these actions; the 5E-7 role matrix stays untouched (household operational writes remain owner and household\_admin). Help copy states Adam is handling set-aside entries for now. Permissions get revisited only if actual usage shows a need.

**Not in this surface:** actual transactions, budget line editing, goal editing, reconciliation, transfer execution buttons, recommendations or shortfall warnings (5G-4a), any stored allocation balances.

## 5\. Empty-state copy recommendations

Standard (from the review, adopted day one): every empty state says why it is empty and the next action.

| Surface | Trigger | Copy |
| :---- | :---- | :---- |
| Budget bottom transactions panel (BUD-2) | Zero legacy Budget-entered rows | "No Budget-entered transactions for July. Actual spending is entered in Register and is already counted in Spent above. Open Register" (live link, FLOW-1 pattern) |
| Budget grid | New month, no spend anywhere | "No spending recorded for August yet. Transactions entered in Register appear in Spent automatically." (one caption under the totals, not per row) |
| Category report | No rows for month | "No Register transactions in this category for July. Spending entered in Register shows here and in Spent." |
| Cash Planning page | No planned outflows | "Nothing planned yet. Add a bill or save-up target. Planned items set money aside; they are not expenses and never count as spending." |
| Cash Planning allocation slot (5G-1 live) | 5G-2 not yet shipped | "Account allocation (Spoken For / Free to Use) arrives in the next update." |
| Upcoming Spend | Nothing due in horizon | "Nothing due in the next 6 weeks. Save-Up Bills below keep accruing." |
| Allocation strip (5G-2) | No earmarks | "Nothing is spoken for yet. Free to Use equals the full balance." |
| Bill activity log | No events | "No activity yet for this bill. Set Aside entries will appear here." |

## 6\. Red / amber / neutral semantics

Rule one, resolving the BUD-1 collision: red means a real money problem on actuals, nothing else. Income not yet received is a normal state and never renders red.

| Color | Means | Where |
| :---- | :---- | :---- |
| Red | Expense category over budget (Remaining below zero): red Remaining value plus "Over by $X" badge. Later: 5G-4a shortfall warnings. Nothing else. | Value and badge only. Never row backgrounds, never buttons, never idle chrome. (Decision 3, confirmed.) |
| Amber | Near limit per the threshold rule below. Existing amber stays: out-of-balance plan banner (until 5G-3), unknown-basis warning, backfill/review prompts, truncation notices. Save-Up deferral cards later. | Value tint or banner, per existing amber conventions. |
| Neutral | Everything operational: row actions, filters, counts, informational text. Income Remaining renders muted with "expected" phrasing, no color state, no late-income signal (decision 2). | Default ink. |
| Green | Sparing: balanced-plan check (existing), Funded pill on a fully set-aside bill. No new green. | Pill or check only. |

**Near-limit threshold (decision 1, final):**

Lines with Budget \>= $100: amber when Spent \>= 90% of Budget AND Remaining \<= $100. The dollar condition stops large lines from going amber early: a $2,000 line is not amber at $200 remaining; it waits for $100.

Lines with Budget \< $100: no amber state. Neutral until over budget, then red. Rationale, recorded once: worst-case overage on a sub-$100 line is small money, so amber earns nothing there, and any absolute-remaining trigger inverts below the $100 crossover. Intended behavior confirmed: the $34 Google line stays neutral at $33.60 spent and only changes state if it goes over.

Mechanics: thresholds computed per row on that row's own numbers; parent rows apply the same rules to their own totals. No pacing logic anywhere, including weekly entertainment buckets (decision 1).

**Row actions (SYS-3, decision 4):** Edit and Archive become neutral ghost/text controls, hover-reveal acceptable. Archive keeps its confirmation modal with the existing what-will-happen copy; the confirm button styles amber-dark. Register's manual-row delete keeps its inline confirm strip, also amber-dark. Red is fully retired from controls.

## 7\. Mockup requirements: 5G-0, 5G-1, 5G-2, 5G-3

Each is a static frame set (annotated screens), built to current app patterns: small-caps card headers, stat tiles, identity strips, status pills, inline band conventions. Use real July numbers where they exist.

**5G-0 frame: Budget, current identity, final labels.** Grid showing: the renamed line "Available for Goals" (keep the flexible-sweep annotation); three expense rows rendered in the three states with real-style values (under: Groceries neutral; near: a normal-size line at 90%+ with \<= $100 remaining, amber; over: a sample row red, "Over by $41.12"; the $34 Google line renders neutral even at $33.60 spent, demonstrating the small-line rule); one income row with the muted "expected" treatment replacing red; balanced footer unchanged; Statement check retitle in place, phase strings gone (SYS-1); WK-6 pluralization corrected wherever the banner appears in frame; neutral Edit/Archive controls with an amber-dark confirm shown once (SYS-3); bottom panel with the BUD-2 copy and live Register link; disabled Add Transaction with its live link. Purpose: Wendy sees the finished naming and color language on the page she already knows, with nothing structurally moved. (Frame shows the UX-0 visual target; per decision 10 the row-treatment code ships in UX-0, not 5G-0.)

**5G-1 frame set: Cash Planning v1.** Nav frame: Planning group with Goals then Cash Planning, nothing else moved, item visible (decision 8). Page frame: title, the purpose line verbatim: "Plans money before it is spent. Actual transactions stay in Register." Collapsible help link. Allocation placeholder line in position. Upcoming Spend block in its empty state (nothing due in horizon at launch). Save-Up Bills block with the two seeded Mint cards: target, due date, set aside so far, funded amount, Transfer to AMEX Savings badge, Accruing pill, out-of-window note. Set Aside modal frame with the copy: "This sets money aside. It does not record spending. Enter the matching transfer in Register as usual." Mark Paid modal frame with: "Enter the real payment in Register first, then mark this paid here." Activity log drawer with two sample Set Aside entries. Help copy includes the Adam-records-events line.

**5G-2 frame: Allocation strip (decision 9, now part of the set).** One frame atop the 5G-1 page: the identity strip, Spoken For \+ Free to Use \= Balance, with per-account stat tiles (checking, AMEX Savings at minimum) and the total. Sample state: Mint accruals spoken for against AMEX Savings; checking fully free. Include the no-earmarks empty state from Section 5\. Annotate the frame: "Arrives after the first Cash Planning release." Purpose: this is the frame that shows Wendy why Cash Planning exists; the 5G-1 live page points at it without pretending it is built.

**5G-3 frame: Budget, derived identity (mock only, gated).** Balance area replaced by the identity strip: "Income $15,938 − Planned $14,488 \= Available for Goals $1,450 (calculated)". Sweep row shown read-only with a calculated tag and tooltip; hand-edit control absent. Out-of-balance banner absent; one info line: "Available for Goals updates automatically when lines change." Income section shows budgeted lines only, with a footnote that variable income stays in the weekly model. Include a before/after strip (today's page beside the 5G-3 page) as a conversation artifact for Wendy. Build gates unchanged and restated on the frame: Wendy feedback, A2 income actuals, 5G-2.5 extraction. This frame exists to earn her sign-off early, not to schedule the build.

## 8\. What not to build yet

Recommendations and shortfall warnings (5G-4a). Earmark adapter into the availability engine (5G-4b). Spreadsheet retirement (5G-5). Any linking of Set Aside events to Register rows (5K Transfers territory; v1 is two entries, one real, one planning, accepted per decision 7). Mobile Cash Planning (consistent with the Transactions posture; capture speed is 5H). Payee suggestions, quick-add, uncategorized surfacing (REG-5, FLOW-4, REG-4: 5H charter). Reconcile-form polish (WK-2, WK-3, FLOW-3, WK-5 attach to form-completion work). Category report consolidation (BUD-3). Nav regroup (NAV-1, triggered only by 3+ weeks of Wendy's live 5G usage). Progress bars, pacing logic, late-income signals, goal editing inside Cash Planning, hard role gates on Cash Planning writes (soft convention in v1). UX-0 is not on this list; it is scheduled work per decision 10\. And per the repo guardrail: no new capabilities before one clean July operating week with Wendy.

## 9\. Decisions log (2026-07-07)

1. Near-limit (final): lines \>= $100 amber at Spent \>= 90% AND Remaining \<= $100; lines under $100 have no amber state, neutral until over, then red. No pacing logic. Confirmed 2026-07-07.  
2. Income rows: muted "expected," never red, no late-income signal.  
3. Red placement: value plus "Over by $X" badge only. No row tint. Confirmed.  
4. Confirms: amber-dark for Archive and Register delete. Red fully retired from controls.  
5. Upcoming Spend horizon: 6 weeks.  
6. Set Aside recording (final): Adam only in v1 by household convention, Wendy views. No isOwnerUser gate, no new owner-only role logic for Cash Planning writes; 5E-7 matrix untouched. Revisit only if usage shows a need. Confirmed 2026-07-07.  
7. Two-entry pattern for transfer-funded set-asides: accepted for v1 and called out to Wendy directly (Section 1).  
8. Cash Planning nav: visible to Wendy at 5G-1, bills only, purpose line explicit.  
9. 5G-2 allocation frame: added to the mockup set.  
10. Sequencing: 5G-0 locked to rename \+ SYS-1 \+ SYS-4 exact strings \+ WK-6. BUD-1/BUD-2/SYS-3 routed to UX-0 immediately after 5G-0 (or the pre-5G bundle if it ships first). No Budget row treatment in 5G-0.

All ten decisions are confirmed. The spec is final. Next action: build the four static mock frames (5G-0, 5G-1 set, 5G-2 allocation, 5G-3 before/after) from this spec for the Wendy walkthrough.  
