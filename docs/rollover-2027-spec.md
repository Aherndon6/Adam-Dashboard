# 2027 Rollover Specification

| | |
|---|---|
| Status | **FROZEN SPECIFICATION.** Documentation only. This document does **not** authorize implementation, SQL, schema changes, production or staging writes, golden-master changes, or a push. Each implementation gate in §23 requires separate owner authorization. |
| Date | 2026-10-07 |
| Governing documents | Financial OS Architecture v2 (frozen 2026-08-30) and the P3 Card-Cycle Admissibility Contract remain authoritative. This specification is implementation underneath them. |
| Consolidates | The rollover reconnaissance, the period-identity adversarial round, the proposed specification, the tightening round and the owner rulings of 2026-10-07. Proposals superseded during those rounds are listed only in §25. |
| Goal funding | **OWNER HOLD remains ON.** Nothing here changes it. |

### Freeze record

- Freeze date: 2026-10-07
- Owner approval: approved for freeze
- Governing authority: Financial OS Architecture v2 and P3 remain authoritative and unchanged
- Implementation authority: none; every §23 implementation gate still requires separate owner authorization
- OWNER HOLD: ON

### Legend

Every requirement carries one tag.

- **[F] Frozen requirement.** Changing it requires owner approval.
- **[I] Owner input.** Supplied later through the private input sheet (§21). Never written into this repository as household amounts.
- **[B] Builder choice.** An implementation detail the builder may choose, provided the frozen contract holds. A [B] item never becomes a requirement by being written down here.

---

## 1. Purpose and scope

[F] Carry the Financial OS from the 2026 plan into 2027 with the **smallest safe change**:
- preserve all 2026 history and reconciliation truth;
- remove every year-boundary ambiguity;
- keep one contiguous forward model with no cliff at the year boundary;
- load 2027 inputs explicitly and fail closed;
- leave Architecture v2 and P3 unchanged.

[F] Rollover is **narrow**. It does not implement:
- Gate R (reconciliation authority);
- Gate F (forward cash / funding authority);
- P3c-2;
- the dated walk, capacity or allocation;
- reconciliation redesign;
- privilege cleanup;
- any goal-funding authority (§20).

## 2. Authority and governing rulings

| # | Ruling (owner, 2026-10-07) | Tag |
|---|---|---|
| G1 | Architecture v2 and P3 remain authoritative and unchanged | [F] |
| G2 | **Design B:** continuous internal absolute weeks; the household calendar week resets each year; `model_year` keeps its meaning as the financial plan year | [F] |
| G3 | **P2:** a week belongs to the financial plan year in which its Sunday-start week begins | [F] |
| G4 | Design A (`model_year` frozen as an epoch marker) and Design C (composite keys with week restart) are rejected | [F] |
| G5 | **D10 option (b):** rollover runs on the existing engine. No Calc-Core extraction before or during rollover | [F] |
| G6 | **D-11:** a narrow exception limited to the server changes in §10. It excludes Gate R work, certified-period guard/correction, privilege cleanup, reconciliation redesign, broader RPC refactoring and unrelated schema work | [F] |
| G7 | **Freeze exceptions:** only the surfaces in §12, only for the rollover reason. Each change is RED-test first, minimal, independently reviewed and re-pinned after acceptance | [F] |
| G8 | **Week 31, Option C:** a frozen/runtime schedule split (§5). No permanent Edit-Week override to repair stale week-31 assumptions | [F] |
| G9 | Category rulings and the durable category principle (§11) | [F] |
| G10 | Recorded rollover requirements R1-R7 (2026-09-13) remain in force. R-h is a capability only | [F] |
| G11 | OWNER HOLD remains ON. The OS stays non-authoritative for goal-funding amounts until Gate F and an explicit owner release | [F] |

## 3. Identity contract

[F] Three identities, kept separate.

| Identity | Definition | Persisted | Visible to household |
|---|---|---|---|
| **Absolute week** `week_num` | Weeks since the permanent epoch, **Sunday 2026-06-07**: `weekStart(n) = 2026-06-07 + 7·(n−1)` days. Never reset, never reused. Existing values keep their meaning. | Yes | **No** |
| **Household calendar week** | `householdWeek(n)` returns (year Y, week k). Y = calendar year of `weekStart(n)`. k = (`weekStart(n)` − first Sunday on or after Jan 1 of Y)/7 + 1. Week 1 is the first Sunday-start week beginning in that year. Not ISO. | No (display only) | Yes |
| **Financial plan year** `model_year` | `planYearOfWeek(n)` = calendar year of `weekStart(n)` (P2). Snapshots and commitments carry it. A commitment keeps its **origin** week's plan year for its whole life. | Yes | As a year |

[F] Derived quantities:
- `firstWeekOfPlan(Y)` = the absolute week whose `weekStart` is the first Sunday of Y. **Defined only for Y ≥ 2027.** For 2026 the first Sunday precedes the epoch, so the formula has no meaning and must never be used for 2026.
- `openingWeekOfPlan(Y)` = the designated opening position for plan Y:
  - **`openingWeekOfPlan(2026) = 5`**, a frozen legacy exception. The 2026 plan began mid-year at the epoch; weeks 1-4 are legacy, and its opening snapshots were created at week 5.
  - **`openingWeekOfPlan(Y) = firstWeekOfPlan(Y) − 1` for Y ≥ 2027** (2027 → 30; 2028 → 82).
- The first closeable week of every plan is `openingWeekOfPlan(Y) + 1` (2026 → 6; 2027 → 31).
- [F] Every rule that needs an opening position or a first closeable week uses `openingWeekOfPlan`, never `firstWeekOfPlan`. The 2026 exception is written in exactly one place (this definition), mirrored once in the server helper (§10).

[F] Consequences:
- The household week equals today's displayed "Cal Wk" for weeks 1-30.
- Week 31 changes from "Cal Wk 53" to **2027 Wk 1**.

## 4. Boundary table

[F] Derived from §3; not hand-maintained.

| Absolute week | Dates | Household | Plan year |
|---|---|---|---|
| 28 | Dec 13-19, 2026 | 2026 Wk 50 | 2026 |
| 29 | Dec 20-26, 2026 | 2026 Wk 51 | 2026 |
| 30 | Dec 27, 2026 - Jan 2, 2027 | 2026 Wk 52 | 2026 (final week) |
| **31** | **Jan 3-9, 2027** | **2027 Wk 1** | **2027 (first week)** |
| 32 | Jan 10-16, 2027 | 2027 Wk 2 | 2027 |
| 82 | Dec 26, 2027 - Jan 1, 2028 | 2027 Wk 52 | 2027 (final week; 52 weeks) |
| 83 | Jan 2-8, 2028 | 2028 Wk 1 | 2028 (not authored by this rollover) |
| 135 | Dec 31, 2028 - Jan 6, 2029 | 2028 Wk 53 | 2028 |

Plan years therefore have 52 or 53 weeks, as the calendar dictates. No period boundary is authored by hand.

## 5. Schedule architecture

### 5.1 Frozen 2026 source and the 2027 schedule

- [F] The existing 31-row schedule source is renamed `WD_2026_FROZEN`. **Its row content stays byte-identical.**
- [F] `WD_2026_FROZEN` exists **solely** to preserve the accepted 2026 model and golden-master behavior (§14). **Its week 31 is legacy test/reference data and is never live January 2027 data.**
- [F] A separately authored `WD_2027` covers absolute weeks **31 through 82** (the 2027 plan).
- [F] Runtime schedule = `WD_2026_FROZEN` rows for weeks **< `firstWeekOfPlan(2027)`** (weeks 1-30), followed by `WD_2027` (weeks 31-82).
- [F] The **only** runtime reference to `WD_2026_FROZEN` is the composition step. Outside runtime, only test code may reference it: the 2026 golden-master harness and the §13 schedule tests.

### 5.2 Authoring mechanism

- [F] `WD_2027` rows are produced **deterministically** by an offline authoring tool from:
  - the owner input sheet [I];
  - a single card issuer-rules source (close day and due day per card; R3, CARD-CYCLE-1).
- [F] The tool **refuses to produce output** if any required input is missing or contradicts another.
- [F] Every 2027 event carries a date in the **existing** event `d` field (e.g. `'Jan 7'`). The ISO date is derived from the week and `d` (R1). **No new event field is added** (R4).
- [F] **Private inputs stay private.** The owner input file is kept outside the repository (with the private evidence). It is never committed to make a test convenient.
- [F] **Verification contract.** Exact regeneration needs the private file, so it is proven at freeze time, not by later CI:
  1. **At authoring/freeze time (private file present):** the tool generates `WD_2027`, then a **regeneration check** regenerates it again and requires a byte-for-byte match with the block about to be embedded (T-SCH-5d). A **freeze manifest** is produced: generator commit, issuer-rules file hash, embedded `WD_2027` block hash, private input-file hash, date and owner approval.
  2. **In CI, without the private file:**
     - structural checks: card payment dates against the issuer rules (the rules file is in the repository; it holds no amounts); no pay event earlier than scheduled; every event has `d`; no commission-tax or variable-income amounts; contiguity of weeks 31-82 (T-SCH-5a);
     - the embedded `WD_2027` block hash equals the hash in the repository freeze manifest, so any later hand edit fails (T-SCH-5b);
     - the generator is deterministic and correct on a **synthetic public fixture** with no household values (T-SCH-5c).

     CI **cannot** verify that the amounts equal the owner's private values. That is proven at freeze time and recorded.
  3. **Retained provenance:** the repository holds the non-sensitive freeze manifest (generator commit, issuer-rules hash, `WD_2027` block hash). The private evidence holds the input file, its hash, the regeneration log and the owner approval. The input-file hash is kept private: it isn't needed for any repository check, and keeping it out removes any guess-confirmation risk.
  4. **Changing `WD_2027`:** any change to any 2027 row is made by changing the private inputs and repeating step 1. The new block hash requires an owner-approved golden recapture (R6). Hand edits to the block are prohibited and fail T-SCH-5b. Runtime statement actuals are not changes to `WD_2027` (see the statement-actuals rule below).
- [F] The generated runtime schedule necessarily contains amounts, as the existing schedule source does today. Only the source input file is kept private.
- [F] Card payment rows are authored **for active cards only** (P3 coverage). There is one per (card, cycle, due date). Amounts are the owner's planning values, labelled as estimates. Payments due in January 2027 for December 2026 cycles use owner-supplied interim values [I].
- [F] Statement actuals that arrive later are **runtime evidence**, entered through the existing Edit-Week true-up as today. They never change `WD_2027` and never trigger a golden recapture.
- [F] No 2027 row is a code-level goal disbursement: no `ALASKA_DRAW`-style constants.
- [B] Tool location and language, input file format, row generation order, label wording.

### 5.3 Current week, end of schedule, and the author-next-plan warning

- [F] **S3:** `getCurrentWeek()` returns the **true** absolute week for the current date. It never silently caps at the last authored week.
- [F] **S4:** if the true week is beyond the last authored week:
  - the forward view is **INCOMPLETE** ("plan year not authored");
  - closeout is unavailable for weeks not in the schedule;
  - no projection is presented as current.
- [F] **S5:** if (last authored week − true week) < 13, show an **"author next plan year"** warning. It is an **operational warning only**. It is not a forecast horizon and changes no financial calculation.
- [B] How schedule-bounded consumers index the schedule (for example a separate bounded index variable), banner wording and placement.

### 5.4 No-cliff capability

[F] Nothing in the client, server or schema imposes an upper week limit (R2, R-h). Extending the model means appending the next plan's schedule rows and that plan's data (§22). Pre-authoring future plan years is **not** required.

## 6. Plan-year derivation and invariants

[F] Every invariant below is enforced by test (§13).

- **S1:** the runtime schedule is contiguous, one row per absolute week, each 7 days, Sunday-start.
- **S2:** **exactly one runtime week 31 exists, and it is the `WD_2027` row**, never the `WD_2026_FROZEN` row.
- **S6:** household-facing labels come only from `householdWeek(n)`. No absolute week number appears in household-facing text.
- **F1-F4:**
  - `WD_2026_FROZEN` is byte-identical;
  - its week 31 is legacy;
  - its only runtime use is the composition of weeks < 31;
  - the 2026 golden runs on all 31 frozen rows (§14).
- **P-Y1:** for every `cash_commitments` row, `model_year = planYearOfWeek(origin_model_week)`.
- **P-Y2:** for every `goal_funding_snapshots` row:
  - an `opening_anchor` row is at `openingWeekOfPlan(model_year)`;
  - every other row has `model_year = planYearOfWeek(week_num)`.
- **P-Y3:** every closeout and correction call carries `p_model_year = planYearOfWeek(p_week_num)`.

Read-only production verification (2026-10-07): all existing commitment and snapshot rows satisfy P-Y1 and P-Y2 (0 violations).

## 7. Goals and opening snapshots

### 7.1 Eligibility invariant

[F] **O1: A goal is snapshot-tracked for plan year Y if and only if an authorized opening snapshot exists for that goal at the designated opening position for Y.** The opening position is absolute week `openingWeekOfPlan(Y)` (§3).

[F] For 2026 the derived set equals the current hard-coded eligible nine. Production verification: exactly nine opening snapshots at week 5, matching the list.

### 7.2 Opening snapshots are control data

- [F] **O2:** snapshots with `source = 'opening_anchor'` are control data. They are created **only** by the owner-authorized plan-year initialization procedure (§7.4).
  - Ordinary closeout writes its normal snapshot rows (`source = 'reconciliation'`) for the week being closed, as in the existing closeout model. It **never creates, overwrites or modifies an `opening_anchor` row**, and never writes at the opening position.
  - The correction path writes `source = 'correction'` rows at closeable weeks only and **rejects the opening position**.
  - No client role can write snapshots.
- [F] **O3:** opening snapshots for Y may be re-initialized only before Y's first closeout. **After it they are immutable.** Later adjustments use ordinary corrections at closeable weeks.

### 7.3 Per-year goal identity

- [F] Every snapshot-tracked goal belongs to exactly one plan year.
- [F] 2027 goals are **new registry rows with new identifiers**. A goal that continues from 2026 is issued again for 2027, with an **explicitly carried opening value**; it does not silently inherit state.
- [F] 2026 goals keep their history unchanged. Their final status uses **existing** status values; no new status is introduced.
- [F] **No `goal_registry` schema change.** Plan-year membership and eligibility come from O1.
- [B] Identifier convention (e.g. `<name>_2027`).

### 7.4 Initialization, disposition and initialization window

- [F] **O4: initialization window.** Initialize 2027 after the **final 2026 close (absolute week 30)** and **before the first 2027 close (absolute week 31)**, because carried values must equal the final 2026 funded position. Expected dates: week-30 close about Jan 2-3, 2027; week-31 close about Jan 9-10, 2027.
- [F] **The first 2027 close fails closed** if O1 yields no goals for 2027.
- [F] Until initialization, the Goals view reports **2027 goals not initialized (INCOMPLETE)**.
- [F] **O5: disposition completeness.** Initialization asserts that every 2026 snapshot-tracked goal is one of:
  - **carried:** a 2027 successor exists, its opening note names the predecessor, and its opening value equals the predecessor's final 2026 funded value, unless a stated reason is recorded; or
  - **closed:** the predecessor has a final status.

  **A carried balance cannot silently disappear.**
- [F] Initialization is an owner-run, assertion-guarded procedure with preflight and postflight. It produces a **manifest**: every inserted registry and snapshot row ID, and every 2026 status before and after. Clients cannot call it.
- [F] The 2027 registry rows are inserted in the same window and the same manifest.
- [B] Script form, manifest format, note format (e.g. `carry:<goal>:<year>` or `new`).

### 7.5 Waterfall and registry loading

- [F] For the 2026 plan, the goal waterfall list is built **exactly** as today (byte-identical behavior; protects the 2026 golden).
- [F] For plan years ≥ 2027, the waterfall includes only goals snapshot-tracked in the current plan year (O1).
- [F] Registry loading **fails closed**: no runtime fallback to hard-coded goals. On failure the Goals and closeout functions are unavailable and the reason is shown. Test harnesses keep explicit fixtures.
- [F] Duplicate-priority validation is scoped **per plan year**.
- [F] A goal that is snapshot-tracked in the current plan year but archived in the registry is a contradiction. It fails closed.
- [F] The waterfall remains recommendation policy shown under OWNER HOLD. Nothing here authorizes goal funding.

## 8. Cross-year commitment contract

Example: a payment initiated in week 30 (2026 plan), still pending at that close, that clears in week 31 (2027 plan).

| Element | Contract [F] |
|---|---|
| Identity | One row. `model_year` = 2026 and `origin_model_week` = 30, **never changed**. The expected-item ID is unchanged. |
| Visibility | Loaded and shown at the week-31 close whatever its plan year. |
| Resolution | The week-31 close (`p_model_year` 2027) may patch it: origin 30 ≤ 31 and plan 2026 ≤ 2027. `reflected/resolved_model_week` = 31. |
| Reservation | Remains reserved until resolved. **An unresolved prior-plan-year commitment is never silently dropped.** |
| Fail closed | A patch to a future-plan-year commitment is rejected. A row violating P-Y1 is rejected by the server; if one is seen, the client treats it as reserved, flags it and blocks closeout until it is resolved. |

## 9. Client changes

[F] The changes, behavior and protected status below are frozen. [B] Internal structure, names and UI wording are builder choices.

| ID | Change | Protected function? |
|---|---|---|
| C1 | Period helpers: `planYearOfWeek`, `householdWeek` (+ label), `firstWeekOfPlan`, `openingWeekOfPlan` (§3), ISO date from (week, `d`) | No |
| C2 | Replace the linear `getCalWeek = 22+n` (and its inline copy) with the household week. Cross-year identity displays show year and week (topbar, week header, history, reconcile/closeout title, timeline). | No |
| C3 | `getCurrentWeek` per §5.3 (true week; INCOMPLETE beyond the schedule; 13-week warning). The existing timezone defect is untouched. | No |
| C4 | Remove 1..31 assumptions: week validity, loops, day options, the budget-rules date band, the Budget month list, What-If limits. All derived from the runtime schedule. | No |
| C5 | Schedule composition and the `WD_2027` block (§5) | WD data (§12) |
| C6 | `saveWeekEdits`: an edited week is "custom" only if beyond the last schedule week; custom numbering starts after it. Custom-week creation hidden. Prevents double-counting an edited 2027 week. | **Yes** |
| C7 | Expected-item tagging: due date from `d` (or the label); due year from the week; ID year = `planYearOfWeek(week)`. Every 2026 ID is unchanged. | No |
| C8 | `buildPhase2NewCommitments`: `model_year = planYearOfWeek(n)`. Phase 3 the same. | **Phase 2: yes** |
| C9 | `isReservedAsOf`: no longer drops other-plan-year commitments; a P-Y1 violation is treated as reserved and flagged (§8) | **Yes** |
| C10 | Commitment visibility: no plan-year filter (absolute weeks order correctly) | No |
| C11 | Loads: commitments of all plan years; snapshots of all plan years, including source and note | No |
| C12 | The hard-coded snapshot-eligible list is replaced by eligibility derived per **target** week from opening snapshots (O1). Empty → fail closed. | No |
| C13 | `submitCloseout` and `renderCloseoutConfirm`: plan year, expected count and eligible goals come from the **target** week (so week 30 can close on Jan 3) | **Yes (both)** |
| C14 | Waterfall per §7.5 | No |
| C15 | Registry fail-closed loading and per-plan priority validation (§7.5) | No |
| C16 | Commission-tax pool: attestation explicitly pinned to the 2026 plan; pool window limited to 2026 weeks. The `PLAN_YEAR` constant is retired. | No |
| C17 | Year-bearing UI text (model range, "31-week", Goals year labels, custom-week text) made plan-aware | No |
| C18 | Pin the current week in the clock-dependent test that fails on its own from Jan 3, 2027 | Test only |

[F] `runModel`, `reconEffectiveWD` and `getActiveModel` are **not changed**.

## 10. Server, RPC and schema changes

[F] These are the complete D-11 scope. SQL is not authored by this document.

**New objects:**
- Two immutable helper functions: plan year of an absolute week; opening week of a plan year (`openingWeekOfPlan`, including the 2026 exception of §3).
- [B] Their names.

**`cash_commitments`:**
- origin, reflected and resolved week checks change from 1..31 to **≥ 1**;
- **add P-Y1 as a table check**.

**`goal_funding_snapshots`:**
- the week check changes to **≥ 1**;
- **add P-Y2 as a table check**.

  With the existing unique key on (`model_year`, `week_num`, `goal_id`), this guarantees at most one opening snapshot per (plan year, goal). No new index.

**`save_weekly_closeout_with_snapshots`:**
- P-Y3 (mismatch → raise);
- week ≥ 1;
- eligible set, expected count and opening-state check derived from opening snapshots (O1); empty → raise;
- **global contiguity:** the next closeable week = 1 + the latest complete week (when none is complete, `openingWeekOfPlan(2026) + 1` = 6). "Complete" = reconciliation present plus every snapshot required by that week's plan year;
- the latest completed week for reopen is global;
- the monotonic prior and every snapshot read/write are scoped to `p_model_year`.

**`save_reconciliation_with_commitments`:**
- P-Y3; week ≥ 1;
- **patch scope:** `origin_model_week ≤ p_week_num` **and** `model_year ≤ p_model_year`;
- new commitments still carry `model_year = p_model_year`.

**Other functions:**
- `validate_commitment_state`: week ≥ 1.
- `save_goal_funding_snapshots`: week ≥ 1; when called from closeout it writes `reconciliation` rows only, never an `opening_anchor` row and never at the opening position (O2).
- `correct_goal_funding_snapshot`: P-Y3; eligibility from O1; **rejects the opening position**.

**Unchanged [F]:**
- `weekly_reconciliations`, `weekly_tasks`, `weekly_notes`, `model_week_overrides`, `custom_tasks` (no re-key);
- `goal_registry` schema;
- RLS: the 2026 pins on `cash_commitments` are inert because clients have SELECT only;
- the advisory lock key;
- the `model_year` default;
- `repair_commitments_for_week` (no client execute grant; no callers; documented as 2026-only).

## 11. Category rollover policy

[F] **Durable category principle:** a year belongs in category identity only when it represents a real accounting or plan boundary. Ongoing economic-purpose categories do not receive annual successor keys merely because the calendar year changes. Event-specific categories keep the event's identity and become inactive when settled. This is not a category migration project; existing keys remain authoritative.

| Category key | Ruling [F] |
|---|---|
| `health_fitness.flexible_spending_2026` | Keep unchanged. Later 2026 claims and reimbursements stay attributable to it. |
| `health_fitness.flexible_spending_2027` | **Create** with the same treatment attributes as the 2026 FSA category. The year is real identity (annual election and claim period). |
| `business.jabian_expenses_2026`, `business.jabian_deposits_2026` | **Keep keys. No `_2027` successors.** Approved household labels: "Jabian Expenses" and "Jabian Reimbursements". |
| `taxes.vio_transfer_2026` | **Keep key. No successor.** Approved household label: "Tax Reserve Transfers". |
| `trips.*_2026` | Keep. Mark inactive through the existing mechanism once settled. Late genuine trip transactions stay with the trip. Not gated on rollover. |

**Label-change verification (read-only, 2026-10-07):**
- No code looks up categories by label.
- Pairing uses keys (`reimbursement_pairing_key`), so it is unaffected.
- The zero-write fingerprint hashes full table content. A label edit therefore changes the `categories` fingerprint as an **expected, attributable change**; it does not change identity.
- The protected `renderBudget` contains a help-text literal naming "Jabian Expenses 2026". It is left unchanged: it is cosmetic, and changing it is not within the §12 exceptions.
- [F] Before applying labels, repeat this verification and record the expected fingerprint change.

## 12. Protected and frozen surfaces: authorized exceptions

[F] Each exception requires: a RED test demonstrating the rollover failure first; a minimal change; independent review; and a re-pin after acceptance. Nothing beyond this table is authorized.

| Surface | Exception | Reason |
|---|---|---|
| Schedule data (Do Not Touch: WD) | Rename to `WD_2026_FROZEN` (rows unchanged); add the composition and the `WD_2027` block | §5 |
| `saveWeekEdits` | C6 | Prevents week double-counting |
| `submitCloseout`, `renderCloseoutConfirm` | C13 | Plan year and eligibility per target week |
| `isReservedAsOf` | C9 | Cross-year reservation |
| `buildPhase2NewCommitments` | C8 | Plan year per target week |
| Reconciliation RPCs and state machine (Do Not Touch) | §10 only (D-11) | Continuous weeks, plan-year validation, data-derived eligibility, global contiguity, cross-year resolution |
| `cash_commitments` schema (Do Not Touch) | Check replacement and P-Y1 | §10 |
| `goal_funding_snapshots` | Check replacement and P-Y2 | §10 |
| Script-body growth rule | Period helpers and `WD_2027` rows (data, not feature code) | §5, §9 |
| Golden masters (R6) | 2026 harness input selection; new 2027 fixture; capture tool support | §14, §15 |

## 13. RED-first test specification

[F] Written and failing before the corresponding change. IDs are referenced in §24.

**Identity and calendar (T-ID):**
- **T-ID-1** `householdWeek` at weeks 1, 30, 31, 32, 82, 83 and 135 equals §4.
- **T-ID-2** `planYearOfWeek` at the T-ID-1 points; `firstWeekOfPlan(2027) = 31` and `(2028) = 83`; `firstWeekOfPlan(2026)` is rejected (fail closed); `openingWeekOfPlan(2026) = 5`, `(2027) = 30`, `(2028) = 82`; JS and SQL helpers agree on all of these.
- **T-ID-3** `weekStart` of 31, 32 and 82.
- **T-ID-4** No absolute week number appears in rendered household labels.
- **T-ID-5** Clock mocked at 2027-01-02, 2027-01-03, 2027-01-10 and past the schedule: true week, INCOMPLETE state, 13-week warning.

**Schedule (T-SCH):**
- **T-SCH-1** Runtime schedule contiguous 1..82, 7-day Sunday weeks.
- **T-SCH-2** **Exactly one runtime week 31, deep-equal to `WD_2027[31]`, and not equal to the frozen row.**
- **T-SCH-3** Runtime weeks 1-30 byte-equal `WD_2026_FROZEN`; the frozen source hash is unchanged.
- **T-SCH-4** In runtime code, `WD_2026_FROZEN` is referenced only by the composition step. Test code is exempt (static test).
- **T-SCH-5a (CI)** Structural checks on `WD_2027`: issuer-rule dates, `d` present, no pay earlier than scheduled, no commission-tax or variable income, contiguity.
- **T-SCH-5b (CI)** Embedded `WD_2027` block hash equals the repository freeze manifest.
- **T-SCH-5c (CI)** Generator determinism and output on a synthetic public fixture.
- **T-SCH-5d (freeze time, private)** Regeneration from the private inputs equals the block to be embedded, byte for byte. Recorded in the freeze manifest and private evidence; not runnable in CI.
- **T-SCH-6 (CI)** The generator refuses a synthetic fixture with a missing or contradictory input.
- **T-SCH-7** Date-to-week mapping, Budget months and What-If limits cover the schedule.

**Edit-Week (T-EDIT):**
- **T-EDIT-1** An override for week 33 is not custom; the effective schedule has exactly one week 33.
- **T-EDIT-2** Custom-week creation is unavailable.

**Commitments (T-CC):**
- **T-CC-1** Every expected-item ID for weeks 1-30 is identical before and after.
- **T-CC-2** A 2027 February due date produces year 2027 in the ID and `due_date`.
- **T-CC-3** Phase 2 and Phase 3 plan year follow the target week (week 30 → 2026 while the current week is 31).
- **T-CC-4** A prior-plan-year open commitment is reserved and visible at week 31.
- **T-CC-5** A P-Y1 violation is reserved, flagged and blocks closeout.

**Goals (T-GL):**
- **T-GL-1** Derived eligibility: week 30 → the 2026 nine; week 31 → the 2027 initialized set.
- **T-GL-2** No 2027 opening snapshots → week-31 closeout unavailable (fails closed).
- **T-GL-3** `submitCloseout` for week 30 while the current week is 31 sends plan 2026 with its count; week 31 sends plan 2027 with its count.
- **T-GL-4** The 2026 waterfall is identical to today; the 2027 waterfall contains only 2027-initialized goals.
- **T-GL-5** Registry failure → no fallback; closeout unavailable.
- **T-GL-6** Priority validation per plan year.
- **T-GL-7** An archived goal with an opening snapshot in the current plan fails closed.

**Commission tax (T-CT):**
- **T-CT-1** The 2026 attestation stays valid while the current week is in 2027; the pool is limited to 2026 weeks.

**Server (staging) (T-SRV):**
- **T-SRV-1** Week 30 closes as 2026 while 2027 opening snapshots exist.
- **T-SRV-2** Week 31 without opening state raises; with it, succeeds.
- **T-SRV-3** Closing a week before its predecessor raises (global contiguity).
- **T-SRV-4** `p_model_year` mismatch raises.
- **T-SRV-5** 2026 goal IDs submitted for week 31 raise.
- **T-SRV-6** The cross-year patch succeeds and keeps `model_year` 2026 and origin unchanged.
- **T-SRV-7** A future-plan-year patch raises.
- **T-SRV-8** The P-Y1 and P-Y2 table checks reject violating rows.
- **T-SRV-9** Monotonic check against the opening snapshot.
- **T-SRV-10** Correction at the opening position raises; correction at a 2027 closeable week succeeds.
- **T-SRV-11** Reopen of the latest week works across plan years.
- **T-SRV-12** Closeout cannot create, overwrite or modify an `opening_anchor` row, and cannot write at the opening position.
- **T-SRV-13** After plan Y's first close, re-initializing Y's opening snapshots is rejected (O3).

**Rollback (T-RB):**
- **T-RB-1** The rollback guard aborts when any point-of-no-simple-return condition (§18) is true.
- **T-RB-2** Before that point, rollback restores the pre-deploy fingerprints for all 2026 rows.

**Intentional expectation changes** (listed up front, reviewed, never silent):
- the date-to-week null boundary tests;
- the `getCalWeek(31)` expectation;
- schedule length assertions;
- source assertions on the 2026 RPC literals;
- the `PLAN_YEAR` reference tests;
- the clock-dependent test in C18.

## 14. 2026 golden-master preservation

- [F] The existing 2026 fixture is **not modified**.
- [F] The harness runs it on the full 31-row `WD_2026_FROZEN` with its existing pinned inputs. The result must be byte-identical.
- [F] Runtime check: weeks 1-25 of the runtime composition produce output identical to the frozen run.
- [F] Weeks 26-30 may differ only because their look-ahead now reaches 2027 rows. Every such difference is listed and attributed in the evidence record. None is "fixed" by editing expectations.

## 15. 2027 golden procedure and dependency chain

[F] Dependency chain (this controls timing; there is no other golden deadline):
1. Owner inputs final [I]: schedule values and the 2027 goal list (targets and priorities affect the model).
2. `WD_2027` generated from the private inputs; freeze-time regeneration check passed (T-SCH-5d); freeze manifest recorded; CI checks green (T-SCH-5a-c); `WD_2027` frozen.
3. 2027 golden **dry run**: runtime schedule weeks 1-82, a pinned current week, a pinned registry fixture (2026 nine plus 2027 goals) and a pinned snapshot fixture (2026 week-5 openings plus 2027 openings). An expected-effect record is produced.
4. **Owner approval**, then capture to a new fixture file.
5. Rollout package frozen (client hash, server package, rollback package, initialization procedure).
6. Staging rehearsal passed (§16).
7. Production within **Dec 12-19, 2026** (Dec 19 hard latest).

Notes:
- [F] The golden does **not** depend on production opening values (set at initialization) or on December statement actuals (runtime evidence).
- [F] Any later change to `WD_2027` requires an owner-approved recapture (R6).
- *Recommendation, not a requirement:* finalize inputs around mid-November so steps 2-6 fit before Dec 12.

## 16. Staging rehearsal

[F] Sequence:
1. Restore a fresh encrypted production backup (DR-1 method, with the security posture file) into an isolated preview or staging target.
2. Take per-table fingerprints (row counts and content hashes).
3. Run preflight: P-Y1 and P-Y2 hold on existing rows; grants as expected.
4. Apply the server package.
5. Deploy the candidate client to staging (SSEP).
6. Simulate closes through week 30 (2026).
7. Run 2027 initialization with its manifest.
8. Close week 31 (2027), including the cross-year commitment.
9. Close week 32.
10. Run T-SRV and T-RB.
11. Confirm every pre-existing 2026 row is byte-identical.
12. Rehearse the rollback guard and rollback before the point of no simple return.

[B] Simulation values, fixture data, harness tooling.

## 17. Production rollout sequence

[F] All steps are owner-gated.

**Deploy window (Dec 12-19, 2026):**
1. Fresh encrypted backup plus posture file; pre-deploy fingerprints.
2. Preflight.
3. Server package.
4. Frozen client (hash recorded).
5. Create `health_fitness.flexible_spending_2027`. Optional approved label changes, after the §11 verification.
6. Deploy acceptance (§19.1).

**Boundary:**
7. **Week-30 close** (2026 plan; about Jan 2-3, 2027).
8. **2027 initialization:** registry rows, opening snapshots, 2026 dispositions, manifest. Between the week-30 and week-31 closes.
9. **Week-31 close:** the first 2027 close; about Jan 9-10, 2027.
10. Boundary acceptance (§19.2).

## 18. Rollback contract

[F] **Point of no simple return.** The earliest of:
1. any `weekly_reconciliations` row with week ≥ 31;
2. any `cash_commitments` row with `model_year ≠ 2026` or any week value ≥ 31;
3. any `goal_funding_snapshots` row with week ≥ 31;
4. any 2027-plan data not listed in the initialization manifest.

In practice this is the **first 2027 close (week 31)**. Week 31 is named explicitly because the prior server functions would accept it and wrongly close it as a 2026 week.

[F] **Machine-checked rollback guard.** The rollback package runs as one transaction:
- **(a) preflight:** evaluates conditions 1-4 and **aborts** if any is true;
- **(b) data reversal:** deletes exactly the manifest's rows (opening snapshots, then 2027 registry rows), restores the manifest's prior 2026 statuses and asserts counts;
- **(c) server restore:** restores the prior function bodies (stored with the server package) and the prior checks. Postgres validation of the restored checks is a second guard;
- **(d) postflight:** fingerprints for all 2026 rows equal the pre-deploy baseline.

Additional rules:
- The client is reverted only together with the server step.
- Non-financial residue at week ≥ 31 (overrides, tasks, notes) is listed by the preflight and does not block.

[F] **After the point of no simple return:**
- **Forward-fix** within the same D-11 scope (preferred).
- Or restore the pre-deploy encrypted backup (last resort). It discards every write after deploy, which must then be replayed from the evidence record.
- The backup, posture file, fingerprints and manifests are retained until rollover acceptance.

## 19. Acceptance criteria

**19.1 Deploy acceptance [F]:**
- Fingerprints of all 2026 rows unchanged.
- Labels correct (e.g. the deploy week shows 2026 Wk 50 or 51).
- Schedule visible through 2027 Wk 52.
- No absolute week numbers in household text.
- The current 2026 week closes normally with the 2026 goal set.
- OWNER HOLD constant unchanged.
- The rollback guard reports eligible.
- The 2027 FSA category exists.

**19.2 Boundary acceptance [F]:**
- Week 30 closed as 2026.
- Initialization manifest complete; O5 satisfied.
- Week 31 closed as 2027 with the 2027 set.
- Any cross-year commitment resolved as one row with its origin unchanged.
- Goals view shows the 2027 plan.
- No INCOMPLETE state except as specified.

**19.3 Rollover acceptance [F]:** 19.1 and 19.2 met. Recording rollover acceptance in `CODEX_STATUS.md` is a separate owner-authorized step. Gate R acceptance weeks **exclude week 31 (2027 Wk 1)**.

## 20. Out of scope

[F] Not part of this rollover:
- Gate R and its controls (statement check, certified-period guard and correction path, the destructive-privilege fix);
- Gate F (dated walk, parity, capacity, allocation, the weekly operating allowance, P3 runtime conformance, the empty baseline waterfall R-f);
- P3c-2 and its evidence fields; runtime schedule generation (R-d);
- reimbursement forecasting; tax estimation;
- any OWNER HOLD change or goal funding;
- 2027 401(k) tracking;
- the existing `getCurrentWeek` timezone defect;
- baseline-E refresh; October label debt; What-If rework;
- broad privilege cleanup; RLS edits;
- any table re-key; any `goal_registry` schema change; a period table;
- the `renderBudget` help-text literal;
- re-placing card due dates in the 2026 schedule rows (2026 planning continues through Edit-Week).

## 21. Owner input sheet (fields only)

[I] Values are supplied privately and kept outside the repository (§5.2). They appear in the repository only as the generated runtime schedule requires.

| # | Field | Used by |
|---|---|---|
| 1 | Each earner's 2027 base net pay per paycheck; pay-date rules (Adam semi-monthly, Wendy bi-weekly, with first 2027 date) | `WD_2027` |
| 2 | Rent: payments per month, day of each, amount, lease term | `WD_2027` |
| 3 | Auto loan: amount, day, payoff month | `WD_2027` |
| 4 | Card issuer rules: close day and due day per card | Issuer-rules source (R3) |
| 5 | Active and dormant card set (P3 coverage; confirm Platinum) | `WD_2027` |
| 6 | Monthly planning value per active card | `WD_2027` |
| 7 | Interim values for payments due January 2027 on December 2026 cycles | `WD_2027` |
| 8 | Known dated non-card Checking obligations in 2027 | `WD_2027` |
| 9 | 2027 goals: identifier, name, target, priority, due date, carried-from (if any) | Registry, initialization, golden fixture |
| 10 | Disposition of each 2026 snapshot-tracked goal: carry (successor) or close (final status) | Initialization (O5) |
| 11 | Reminders continuing in 2027 (monthly and quarterly transfers, reimbursement review) | Reminder schedule |
| 12 | Confirmation that no holding-type goals exist in 2027 | §7.5 |
| 13 | Confirmation that the operating floor is unchanged | Unchanged constant |

## 22. Future-rollover contract (2028 onward)

[F] A normal future rollover is **data and schedule authoring only**:
1. Supply the next plan's inputs.
2. Generate and append that plan's schedule rows (e.g. `WD_2028`; absolute weeks from `firstWeekOfPlan(2028)` = 83), with the freeze-time regeneration check and freeze manifest of §5.2.
3. Capture an owner-approved golden for the new schedule.
4. Initialize the plan (registry rows, opening snapshots at `openingWeekOfPlan(Y)`, dispositions, manifest) between the prior plan's final close and the new plan's first close.

**Why nothing else is needed:**
- No server function, schema, RLS or identity change: plan years, household weeks, eligibility and contiguity are all derived.
- 53-week years arise from the calendar automatically (2028).

**Recurring operational obligation:** author the next plan before the S5 warning window, i.e. at least 13 weeks before the current plan's final week (for 2027, by early October 2027).

A future change to this contract would be an architecture question, not a routine rollover.

## 23. Implementation sequence and owner gates

| Gate | Content | Owner authorization |
|---|---|---|
| 0 | Freeze this specification; independent review | Freeze decision |
| 1 | Repo: RED tests; authoring tool, issuer-rules source, CI checks and freeze manifest (with the freeze-time regeneration check run privately); client changes; 2026 golden proof; 2027 golden dry run, then owner approval, then capture; protected-function review and re-pins | Per §12, plus golden approval |
| 2 | Staging rehearsal (§16) | Staging authorization |
| 3 | Production deploy (§17 steps 1-6) | Production DDL and deploy |
| 4 | Boundary: week-30 close, 2027 initialization, week-31 close (§17 steps 7-10) | Initialization authorization |
| 5 | Rollover acceptance recorded | Status update |

## 24. Traceability

| Requirement / ruling | Section | Tests |
|---|---|---|
| Design B (G2); absolute week; household week; plan year | §3, §4 | T-ID-1..4 |
| P2 (G3) | §3, §4, §6 | T-ID-2, T-GL-1, T-GL-3 |
| Design A and C rejected (G4) | §3, §10 | T-SRV-4, T-SRV-8 |
| D10 (b) (G5) | §9 (`runModel` unchanged) | T-SCH-3, §14 |
| D-11 narrow (G6) | §10 | T-SRV-1..13 |
| Freeze exceptions (G7) | §12 | RED tests per change |
| Week 31 Option C (G8) | §5.1, §6 S2, F1-F4 | T-SCH-2, T-SCH-3, T-SCH-4 |
| Category rulings and principle (G9) | §11 | Verification record |
| R1 structured dates | §5.2 | T-SCH-5a |
| R2 / R-h no cliff (capability) | §5.3, §5.4, §22 | T-ID-5, T-SCH-1 |
| R3 issuer-rule authoring | §5.2 | T-SCH-5a, T-SCH-5c |
| R4 no P3c-2 fields | §5.2 | T-SCH-5a |
| R5 committed-cash walk not made harder | §5.2 (dated events), §3 (absolute weeks) | T-SCH-5a |
| R6 golden approval | §14, §15 | Golden review |
| R7 no P3c-2 in rollover | §20 | n/a |
| Owner-confirmed 2027 base pay | §5.2, §21 | T-SCH-5d, owner approval |
| Registry fail closed; no code disbursements | §5.2, §7.5 | T-GL-5 |
| Private inputs; verification contract; `WD_2027` change control | §5.2 | T-SCH-5b, T-SCH-5d, T-SCH-6 |
| `openingWeekOfPlan` and the 2026 legacy exception | §3, §6 P-Y2, §7.1, §10 | T-ID-2, T-SRV-8 |
| Eligibility invariant O1; control data O2/O3 | §7.1, §7.2 | T-GL-1, T-GL-2, T-SRV-10, T-SRV-12, T-SRV-13 |
| Initialization window O4; disposition O5 | §7.4 | T-GL-2, staging step 7 |
| Cross-year commitments | §8 | T-CC-4, T-CC-5, T-SRV-6, T-SRV-7 |
| 2026 history preserved | §6, §14, §16 | T-CC-1, T-SCH-3, T-RB-2 |
| Current week never silently capped; INCOMPLETE; operational warning | §5.3 | T-ID-5 |
| Rollback point and guard | §18 | T-RB-1, T-RB-2 |
| Commission-tax pool pinned to 2026 | §9 C16 | T-CT-1 |
| OWNER HOLD unchanged (G11) | §2, §19.1 | Deploy acceptance |
| Gate R excludes week 31 | §19.3 | n/a |

## 25. Superseded proposals (do not implement)

| Superseded proposal | Replaced by |
|---|---|
| Composite `(model_year, week_num)` re-key of the week-keyed tables | Design B; no re-key |
| `model_year` frozen at 2026 as an epoch marker | Plan-year meaning (G2) |
| 2027 plan = weeks 32-83 ending on the "second Saturday of January" | P2: weeks 31-82 |
| Fixed "Cal Wk 22+n" labels; "Cal Wk 53" for Jan 3-9 | Household week reset (C2) |
| Owner Edit-Week override to fix week-31 pay | Option C split (§5) |
| Editing WD row 31 in place | Option C split |
| `goal_registry.plan_year` and `snapshot_eligible` columns | Eligibility from opening snapshots (O1) |
| Initializing opening snapshots during the deploy window | O4 initialization window after the week-30 close |
| Capping the current week at the last authored week | S3, S4 |
| A "Nov 1" golden deadline | The §15 dependency chain |
| A new structured-date event field | The existing `d` field |
| A stored period or week-date table | Derived dates (§3) |
| Annual `_2027` successors for Jabian and Vio categories | §11 rulings |
| A CI test that regenerates `WD_2027` from inputs committed to the repository | §5.2 verification contract (private inputs) |
| Deriving the 2026 opening position from `firstWeekOfPlan` | `openingWeekOfPlan` with the explicit 2026 exception (§3) |

## 26. Open specification questions

- **Q1 (placement of owner input values): CLOSED** by owner direction (2026-10-07). Private inputs stay outside the repository; the verification contract is §5.2.

No open question remains. Everything else is frozen [F], an owner input [I], or a builder choice [B].
