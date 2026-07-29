# Step 8 — Baseline E: Owner Input-Assembly Checklist

## DRAFT / NOT AUTHORIZED / NOT EXECUTABLE (rev-8)

Collect these **immediately before** any eventual Baseline E execution — the live-bank figures and the whole
manifest are valid only within one **≤24-hour capture window** (spec §2/§16). Supplying this checklist does
**not** trigger execution: Baseline E must still be built-to-freeze (pure-adapter effective-schedule snapshot
+ budget-rules extract + manifest + Node script + tests + parity harness), Fable-re-reviewed, and
owner-approved first. Nothing here authorizes a transfer.

Format: **what to provide · why · what happens if unavailable.** These inputs populate the immutable JSON
manifest (`baseline-E-inputs.json`). **All amounts are recorded as exact decimal strings / integer cents
(spec §8) — never a rounded float.**

### A. Live-bank opening balance and its normalization

1. **The POSTED/CURRENT checking balance** (default basis, spec §5) — exact figure + confirmation you are
   reading posted/current, not available.
   - *Why:* posted/current + a manual pending ledger is deterministic; available-balance semantics are
     bank-defined and were a prior source of confusion.
   - *If you must use available:* document the bank's exact inclusion rules for pending debits, pending
     credits, and holds — otherwise **FAIL-STOP**.

2. **Exact capture date and time (to the minute, America/New_York).**
   - *Why:* drives the ≤24h window, the §5b/§5c capture-week cutover, and staleness gates. The capture **must
     fall within the current as-of model week** (spec §16); the capture-week identifier used by both
     reconciliation directions must equal `as_of_model_week`.
   - *If unavailable, or if the capture crosses a model-week boundary / the frontier advances:* the run
     regenerates and re-adjudicates, else **FAIL-STOP** (no stale as-of frontier paired with a later capture
     week).

3. **Full pending-item list.** For **each** pending checking item: amount · debit/credit · status ·
   in posted balance? · in available balance? · in the selected basis? · also a future scheduled item?
   - *Why:* the normalized opening balance counts every item exactly once (spec §5).
   - *If unavailable:* any unresolved pending item ⇒ **HOLD**.

4. **The +$15.00 Bailey item — in the selected basis, and/or in the forward schedule?** (Screenshot or
   explicit statement.)
   - *Why:* the bank label "pending" is not decisive; basis/schedule inclusion is (spec R2′).
   - *If unavailable / unresolved:* **HOLD.**

5. **Confirm the Alaska +$770.95 is already inside the selected balance** (yes/no).
   - *Why:* Baseline D says it is reflected; it must never be re-added (R1).
   - *If unavailable / "no":* **HOLD.**

### A′. Capture-week two-direction reconciliation (spec §5b **and** §5c)

**Both directions are required.** They jointly enforce the **global no-double-count invariant**: every cash
effect already in the balance you read appears **at most once** in the forward projection.

6. **(a) Schedule → bank (§5b).** **For every scheduled item the snapshot lists *anywhere in the capture
   week* — not only items dated on or before your capture time:** has it **actually posted before your
   capture**, and is it **included in the balance you read**? Answer for **both inflows and outflows** (a
   paycheck direct-deposited ahead of its date; an autopay that clears early).
   **(b) Bank → schedule (§5c — NEW).** **List every checking transaction that *posted* during the capture
   week at or before your capture time** (inflows and outflows), and for each state whether it **matches a
   scheduled event *anywhere* in the whole projection (from the current as-of model week through the
   projection horizon)** — especially a **future** week's
   event that the bank posted early — and whether it is **included in the balance you read**.
   - *Why:* an item **expected in a later week but posted early** is already inside the balance; a capture-week
     seam alone would miss it (its expected week is outside the capture week) and it would stay in the forward
     schedule and be **counted twice** (spec §5c/NF-1). Direction (b) catches exactly that. A matched
     posted+reflected event leaves the schedule (`already_reflected_in_opening_balance`); an unmatched posted
     transaction stays as balance-only history; a **partially posted** event is split (cent-conserving).
   - *If unavailable:* posting/inclusion ambiguous ⇒ **HOLD**; a transaction matching **multiple** events, an
     event matching **multiple** transactions without an explicit split, or contradictory evidence (marked
     posted but absent from the balance) ⇒ **FAIL-STOP.**

### B. The proposed transfer (ALWAYS required — there is no capacity-only run)

7. **Exact Wendy IRA amount to test** (cents).
   - *Why:* a final Baseline E run always concerns a supplied proposed transfer (spec §2 D). The engine may
     also derive a maximum-safe figure, but the PASS-SAFE/PASS-UNSAFE verdict is about *your* amount.
   - *If unavailable:* **the run cannot proceed to a verdict — HOLD** (no amount-less mode).

8. **Intended transfer date.**
   - *If unavailable:* **HOLD** (cannot place the transfer).

9. **Expected bank-posting date** (or accept the conservative earliest-plausible placement).
   - *If unavailable:* conservative placement used; run flagged.

### C. Material obligations — EXACT values

10. **For each of AMEX Gold, any AMEX Platinum residual, Disney Visa, Costco Visa, Kia, rent — and every
    other active or residual-balance account the registry lists (spec §16):** account · exact amount · due
    date · expected posting/payment date · statement source · already posted? · autopay/manual ·
    **does this amount already net any expected reimbursement?**
    - *Why:* these dominate the forward outflows; the model carries approximations (`~$5,500`, `~$3,500`,
      undated Costco). The embedded-reimbursement declaration prevents adding the same credit twice (R9).
    - *If unavailable:* an item with a **trustworthy conservative bound** (amount ceiling + earliest-plausible
      date) may proceed at that bound with **HOLD**; an undated/unbounded material item (e.g., Costco Visa) is
      a **final-execution FAIL-STOP**.

11. **Any reimbursement still expected** (amount, expected date) beyond what is already in the balance — and
    whether it is already netted inside any obligation amount from #10.
    - *If unavailable:* excluded (conservative); netted-and-separately-listed ⇒ **FAIL-STOP** (R9).

### C′. Engine set-aside execution status (spec §3b — NEW)

12. **For each carried engine set-aside scheduled on or before the current as-of week** — the base tax
    (~$521.36), the commission tax (~$707.18), and the commission-to-Alaska set-aside (~$1,060.76), plus any
    other engine-modeled transfer scheduled that early — state its **actual execution status** with evidence:
    executed/reflected · superseded/voided · still outstanding-and-intended · unknown; and cite bank /
    Register / `cash_commitment` / `custom_task` evidence.
    - *Why:* the effective schedule shows `ct=0, ca=0` for every future week, so a still-owed set-aside is a
      forward checking outflow that **no snapshot week would carry** (spec §3b). Baseline D's $435.63
      commission-tax resolution is evidence for one candidate only — **not** blanket closure.
    - *If unavailable:* a still-outstanding-and-intended set-aside becomes an **owner-committed** forward flow;
      an unresolved material one ⇒ **HOLD**; contradictory integrity evidence ⇒ **FAIL-STOP**.

### D. Alaska — Goal-Ledger-sourced release reconciliation (spec §4)

13. **From the canonical interim Alaska Goal Ledger** (cite the ledger record + as-of date — do not work from
    memory): current custody in Truist Savings · remaining spendable · releases already settled · **each
    proposed future savings→checking release** (amount, expected date, still intended?, sequential source
    sufficiency, and whether it already appears in the schedule/Register/pending items) · your adjudication of
    the **legacy bulk draw** (superseded / retained / re-derived — with ledger evidence). The legacy draw's
    model position is `actionOverrides`-movable, **not** a fixed "week 15."
    - *Why:* the code-side $7,000 draw may not be assumed current; the adopted model is statement-level
      releases; the bulk draw and releases can never both be included (R8′); every release must be
      sequentially funded from actual custody.
    - *If unavailable / insufficient / stale:* releases **excluded** (conservative) and the run is **HOLD** —
      and if the transfer's safety would depend on an excluded release, the result is HOLD regardless.

### E. Schedule integrity, drift, classification, horizon

14. **Report all changes since Baseline D (2026-07-28)** — transfers made; Edit-Week overrides added/changed
    (incl. any with an **empty** event set, which keeps the literal events but may still change `ct`/`ca`/
    dates); **custom weeks (32+)** added; weeks reconciled; new commitments; **new or changed budget rules**;
    unusual Register activity. **Changes are not violations** — each is classified and incorporated by
    regeneration (spec §11); only **undisclosed or unexplained** change is a FAIL-STOP.
    - *Why:* the snapshot, budget extract, seam, and Baseline-D overlay must reflect current reality; a newly
      reconciled week regenerates the projection start rather than reusing stale assumptions.
    - *If unavailable:* **HOLD.**

15. **Adjudicate every open custom task / planned action with possible cash impact** (e.g., BKX-class items)
    into: mandatory / owner-committed / discretionary / historical / conditional / unresolved — using the
    evidence bar (spec §3): owner-committed only with amount + date-or-bounded-timing + your affirmation +
    not-posted evidence + not-represented-elsewhere proof; historical only with settlement evidence or your
    explicit voiding. **Undated committed items do not disappear** — they become conservatively-dated events
    (if boundable) or committed-capacity claims with HOLD.
    - *If unavailable:* unresolved ⇒ **HOLD** when material.

16. **List other owner-authorized-but-unexecuted uses of capacity** (approved actions that will also draw
    checking, including undated committed items from #15 and any outstanding set-asides from #12).
    - *Why:* residual deployable capacity = maximum-safe-transfer − these claims; gross cushion is never
      reported as deployable while they exist (spec §10).
    - *If unavailable:* residual capacity cannot be stated; only the gross figure, flagged.

17. **Confirm the horizon** — week 31 remains the model endpoint; no known material obligation just past it
    makes a "safe" result misleading; **approve, revise, or reject the PROPOSED minimum-coverage policy**
    (spec §13(d): ≥8 weeks, ≥2 paycheck cycles, ≥2 card-statement cycles after the transfer); and flag any
    **custom week beyond week 31** that could affect the decision.
    - *If unavailable:* insufficient approved coverage, or an unbounded material out-of-horizon custom ⇒
      **HOLD.**

18. **Explicitly confirm the operating floor (fail-closed).** State: the floor amount; whether a separate
    named reserve exists; the source of authority.
    - *Why:* $6,500 is the documented floor, but execution requires your explicit confirmation; any reserve
      above it is a named control input, never a silent buffer (spec §2 CONTROL).
    - *If unavailable:* **HOLD** — execution does **not** proceed on a silent default.

### Governance reminder

Providing these inputs is preparation only. Baseline E remains **not executed**; no capacity number exists;
no Wendy-IRA decision is made. **A future PASS-SAFE result would establish checking-capacity safety only — it
does not satisfy the separate CPA-clearance requirement (`ira_cpa_cleared`) for the Wendy IRA and does not
authorize any transfer.** The operational HOLD stays active.
