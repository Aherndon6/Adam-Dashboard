# Herndon Financial OS: UI & Flow Review Triage (v2, phase-framed)

**Date:** 2026-07-07 · v2 supersedes v1's timing buckets. Calendar language retired; the deployment freeze is a constraint, not a bucket. Phase names follow the authoritative map in CODEX\_STATUS.md: 5G Cash Planning \+ Allocation, 5H Register capture speed \+ mobile quick-add, 5I Splits, 5J Month-end close \+ minimal goal editing, 5K Transfers, 5L Architecture hardening. **Scope and inputs unchanged from v1:** 19 desktop screenshots, review brief, index.html \+ AGENTS.md \+ CODEX\_STATUS.md from repo main. UI and flow only. Wendy-confirmed workflows untouched. Findings are hypotheses; Wendy's confirmed workflow overrides.

## Recommended pre-5G UX cleanup bundle

Core bundle, one to two short sessions, all display or routing level. None touch schema, model math, the reconciliation engine, Register schema, Budget identity, or nav grouping.

1. FLOW-2: default Transactions to Register (one-line default change)  
2. FLOW-1: make the Budget helper a live link to Register  
3. WK-1: fix transfer status vs task check semantics (adopt the existing Accounts status pills)  
4. REG-1: make the Register filtered state unmistakable  
5. SYS-2: one money format standard (separators, one negative convention)

Rider, only if the Register table is already open: REG-2 group labels (sort order untouched).

Routed into 5G-0 instead of the bundle, because 5G-0's charter is already label/docs cleanup: SYS-1 reconciliation naming, SYS-4 plain-language sweep, WK-6 pluralization fix. Same species of work as the Available for Goals rename. If Adam wants 5G-0 to stay literally one rename, SYS-1 falls back into the bundle; SYS-4 and WK-6 can wait.

Hard cap: if the bundle threatens to grow past this list, cut the rider first. Do not let 24 findings become a phase.

## Phase-bucketed triage (all 24 findings)

| Phase bucket | ID | Surface | Finding | Impact | Effort | Notes |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| Pre-5G bundle | FLOW-2 | Transactions nav | Sub-nav defaults to the read-only Accounts table (verified in code and screenshot; the landing header itself says "Read only"). Default to Register. | M | S | Cheapest meaningful fix in the review |
| Pre-5G bundle | FLOW-1 | Budget → Register | Disabled Add Transaction points to Register via tooltip and plain text only. Make the helper a live link. Button stays disabled per Wendy's confirmed flow. | H | S | Removes the dead end on her most common path |
| Pre-5G bundle | WK-1 | Weekly Model | "Transfers this week" shows all green checks while "Transfers to execute" shows 1/6 done. Same money, two check meanings; green reads as executed. Relabel the model panel and restyle its checks as status chips. | H | S | Chip system already exists (Accounts pills); adopt, do not invent |
| Pre-5G bundle | REG-1 | Register | Filter-active state is a small "12 of 15" plus an italic note. Add persistent filter chips or a tinted header while filtered so a partial ledger cannot be misread. | M | S |  |
| Pre-5G bundle | SYS-2 | Cross-surface | Register drops thousands separators ("$20095.69") and prints "$-12624.22"; other surfaces use "$14,935.14". One standard before 5G inherits table styles. | M | S | Display formatting only |
| Pre-5G bundle (rider) | REG-2 | Register | Uncleared block above cleared has no labels. Add thin "Uncleared (n)" and "Cleared" group headers. Sort order untouched, per Wendy's confirmed default. | M | S | Optional; only if Register table is already open |
| 5G-0 fold-in | SYS-1 | Cross-surface | "Reconciliation" names three things: weekly reconcile, Budget statement check, and a grayed sub-tab leaking "Phase 5F". Accounts footer also prints "Phase 5D-1/5D-2". Rename Budget block "Statement check", strip phase strings, reserve "Reconcile" for the weekly flow. | M | S | In-charter for 5G-0 (label/docs cleanup); must land before 5G-1 introduces Spoken For / Free to Use |
| 5G-0 fold-in | SYS-4 | Cross-surface | Plain-language sweep: CLR → Cleared (table header and form checkbox); MODEL/TRANSFER chips → Planned/Custom; "(existing registry keys only)" → "existing categories only"; pick one of Rule vs Line; rewrite the Register reconciliation hint in household terms. | M | S | String-only pass |
| 5G-0 fold-in | WK-6 | Reconcile flow | Copy bug: "1 current-week protected obligations not yet recorded." Pluralize correctly. | L | S | One string |
| Wendy mockup | BUD-1 | Budget | Red in Remaining means opposite things (expense overage vs income not yet received) and there is no over vs near vs under distinction without per-row math. Standardize semantics; add a near-limit state. | H | M | Primary mockup question; settle the income-red collision first |
| Wendy mockup | BUD-2 | Budget | Bottom Transactions panel says "No transactions for this period" in a month with 50+ transactions. Empty state must say why and the next step. | M | S | Carries the "actuals reconcile through Register" story; generalizes to the 5G empty-state standard |
| Wendy mockup | SYS-3 | Budget, Register | Red destructive controls on every row (Archive chips, row X) compete with genuine red money alerts. Demote to neutral or hover-reveal; reserve red for money problems. Register delete already has an inline confirm (verified). | M | S | Moved out of pre-5G so Budget rows are restyled once, per mockup, not twice |
| 5H | REG-5 | Register | Payee free text already shows drift (Trader Joes / Trader Joe's / Trader joes; rent vs Rent), degrading search and reporting. Suggest previously used payees while typing. | M | S | Capture assistance is 5H's charter; do not build early |
| 5H | REG-4 | Register, Budget | Uncategorized rows exist in live data and are invisible once saved: no count, no filter; Budget's category Spent quietly excludes them. Add an Uncategorized filter option plus a visible count. Surfacing only; whether Category becomes required is a workflow call. | M | S | Category assistance side of 5H; revisit earlier only if 5H slips |
| 5H | FLOW-4 | Global | Desktop quick-add entry point. Real gap; capture design belongs to 5H. | M | M | Deferred in v1; unchanged |
| 5I+ / later | WK-2 | Reconcile flow | Phases 0-4 read as one flat form; required Phase 0 only surfaces as red text at Save. Add step chips with done states; on blocked save, focus Phase 0\. | M | S | Reconcile form is mid-build (its own UI says commitment tracking is still being built); attach to the form-completion work, not standalone cleanup |
| 5I+ / later | WK-3 | Reconcile flow | "Select response..." dropdowns hide the possible answers. Show responses as visible buttons or radios. Same options, presentation only. | M | S | Attach to form-completion work |
| 5I+ / later | FLOW-3 | Weekly → Register | Phase 4 balance entry has no path to Register. Add an "Open Register" link on the phase header. | M | S | Attach to form-completion work |
| 5I+ / later | WK-5 | Weekly Model | Actual and Variance columns show bare dashes pre-reconcile. Add a one-line "fills after reconcile" hint. | L | S | Attach to form-completion work |
| 5I+ / later | WK-4 | Weekly Model | Header banner is narrative while the week's open work sits below the fold. Add a compact counts strip beside the week title. Distinct from the known deferred Review Required verdict string. | M | M |  |
| 5I+ / later | BUD-3 | Budget | Category Report is a two-step modal while row drill-through opens the same layout in one click. Fold pickers into the report modal, retire the picker step. | M | M | Mockup tag dropped in v2; report consolidation is not part of the balancing story |
| 5I+ / later | POL-1 | Register, Budget | Polish bundle: ISO dates vs friendly dates; duplicate "Selected account:" line; income-row Edit link misaligned; add-form validation is one unanchored message with no field highlight. | L | S | Reporting-polish class |
| 5I+ / later | NAV-1 | Left nav | Nav reflects build history; daily loop spans three groups. Defer. Single regroup decision later, triggered by 3+ weeks of Wendy's live 5G usage; likely shape is a Money group (Budget, Cash Planning, Transactions) with top and bottom anchors preserved. | L | S | If it touches routing or the Transactions container, it waits for 5L |
| Park | GLS-1 | Goals (P3 skim) | Dense insider vocabulary without a collapsible explainer. Nothing else glaring; explainer patterns there are strong. | L | S | Resurface only through Wendy usage |

## Wendy 5G Budget mockup inputs

Open questions the mockup must answer:

- BUD-1: over vs near vs under treatment, and one meaning for red. Settle the income-red vs expense-red collision first.  
- BUD-2: how the Budget page tells the "actuals reconcile through Register" story, including what its panels say when empty.  
- SYS-3: the row-action treatment (Archive/Edit) so real alerts own the color red.

Standards the mockup inherits rather than reopens: SYS-1 naming, SYS-2 money format, the Accounts status-pill chip system (via WK-1), the FLOW-1 disabled-control-plus-live-link redirect pattern, and the 5G-0 "Available for Goals" label.

Framing constraint, not a finding: Register stays the source of truth for actuals. The mockup explains that; it never works around it.

## 5G implementation pattern guidance

No standalone findings live here; this is guidance extracted from the review.

- One dollar, one status vocabulary. The WK-1 lesson. The allocation view shows the same dollars the weekly transfer lists show; do not mint a second status representation for money that already has one.  
- Inherit: identity strips (Weekly liquidity equation, Budget balanced footer) for Spoken For \+ Free to Use \= Available; the amber deferral card and look-ahead floor banner for Save-Up Bills warnings; the stat-tile row for allocation summaries; the inline add/edit band with in-place row gray-out for editable planned-outflow rows; Accounts status pills as the chip vocabulary to extend; small-caps card headers; the collapsible help link; the Overview status banner for any verdict line.  
- Empty-state copy standard from day one: say why it is empty and the next action.

## 5H candidates (hold)

REG-5, REG-4, FLOW-4. All are capture speed or entry assistance, which is 5H's charter by the authoritative phase map. Building desktop shortcuts ahead of 5H creates a second capture pattern to reconcile later.

## Nav decision (confirmed)

1. No left-nav regroup now.  
2. FLOW-2 ships as the minimal nav fix.  
3. 5G launches as one new "Cash Planning" item under Planning, next to Goals. Nothing else moves.  
4. Broader regroup is a single later decision, triggered by 3+ weeks of Wendy's real 5G usage, validated with her before shipping. Preserve the top anchor (Weekly Model) and bottom anchor (Transactions).

## 5G-0 impact

5G-0's designed scope and architecture stand. One recommended in-charter addition: fold SYS-1, SYS-4, and WK-6 into 5G-0, since 5G-0 is by definition the label/docs cleanup pass. Nothing else from this review changes 5G-0. If the pre-5G bundle does not ship, SYS-2 becomes a 5G-1 day-one standard for new surfaces rather than a retrofit.

## What to avoid

- Turning this list into a phase. The bundle is five items plus one rider; everything else has a phase home or a trigger.  
- Restyling Budget rows before the mockup settles the row treatment (why SYS-3 moved).  
- Shipping any nav movement with the 5G launch beyond the single Cash Planning item.  
- Polishing the reconcile form while it is mid-build; WK-2, WK-3, FLOW-3, and WK-5 attach to the form-completion work.  
- New capabilities before one clean July operating week with Wendy (repo guardrail). That includes payee suggestions and quick-add.

## Changes from v1

Timing column replaced by phase buckets; calendar language retired. SYS-1, SYS-4, WK-6 rerouted into 5G-0 as in-charter label/docs work. SYS-3 moved from pre-5G to mockup input. BUD-3's mockup tag dropped. REG-2 downgraded from core to rider. NAV-1 remains Defer with an explicit usage trigger. No findings added or removed; count stays 24\.

## Carried from v1 (condensed)

Already working, leave alone: the full-ledger note under Register filters; the add/edit inline band with in-place row gray-out and mode-aware page subtitles; drill-through and Category Report sharing one layout; the under-$50 logging tip; Accounts status pills; the Overview status banner; the calm italic "Balance not set" treatment. Not reviewed: Manage Lines list view, expanded help panel, Categories table, loading and save-failure states, Register-level starting-balance-not-set state. None blocks this triage.  
