# 2027 Rollover Specification v2

| | |
|---|---|
| Status | **FROZEN SPECIFICATION (v2).** The implementation specification for the 2027 rollover going forward. Documentation only. This document does **not** authorize implementation, SQL, schema changes, production or staging writes, golden-master changes, or a push. Implementation authority exists only through separate owner authorization of Gate 1 and each later gate in §23. |
| Date | 2026-10-07 (v1 frozen; v2 frozen the same day) |
| Governing documents | Financial OS Architecture v2 (frozen 2026-08-30) and the P3 Card-Cycle Admissibility Contract remain authoritative. This specification is implementation underneath them. |
| Consolidates | The rollover reconnaissance, the period-identity adversarial round, the proposed specification, the tightening round, the owner rulings of 2026-10-07, and the owner's disposition of the independent review of v1. Proposals superseded during those rounds are listed only in §25. |
| Goal funding | **OWNER HOLD remains ON.** Nothing here changes it. |

### Review history

- **v1 (frozen):** freeze date 2026-10-07; owner approved for freeze; commit `644f3f7d3eb1debcd38e1e9c5b61916b9d9e11b5`; file SHA-256 `77d66acad0de0cd2f53988b25b01dd15a23378aea6d91cefa8b03000f9d39fa9`. The v1 freeze record stated: Architecture v2 and P3 authoritative and unchanged; implementation authority none; OWNER HOLD ON. That commit is immutable and is not amended.
- **Independent review of v1 (Fable):** verdict **PASS WITH REQUIRED CHANGES**. Three required corrections (rollback, Edit-Week overrides, initialization atomicity) and fifteen non-blocking findings. Owner accepted the verdict and the dispositions on 2026-10-07. Architecture v2, P3, Design B, P2, Week-31 Option C and the O1/O2 rulings were not reopened.
- **v2 truthfulness round (2026-10-07):** owner closed Q2-Q13 (§26) and added the household truthfulness rule (G12): Goals plan-year scoping and a read-only historical group (§7.6), local disclosures (C20-C25), and follow-ons H-1, GR-1 and F-1 (§23), none implemented in rollover.
- **Fable re-review of v2 candidate `edcce633…`:** PASS WITH REQUIRED CHANGES (A-1 Cash Flow Mechanics pay literals; A-2 F-1 scope), B-1, B-2 and B-3 confirmed closed, Architecture v2 and P3 unchanged. Owner accepted 2026-10-07 and directed a final bounded hardening round (A-1, A-2, B-1 to B-13, D-2, D-3, D-5), applied here.
- **v2 (this document):** frozen by owner authorization (record below).

### v2 freeze record

- Freeze date: 2026-10-07
- Owner approval: authorized freeze of the candidate with SHA-256 `1511a1421cf3b463aec031ca2bd1e0cf573231ec30ba5b8eb5c5b184b729cc6a` (1080 lines); only this freeze metadata was changed at freeze
- Governing authority: Financial OS Architecture v2 and the P3 Card-Cycle Admissibility Contract remain authoritative and unchanged
- Implementation authority: none until the owner separately authorizes Gate 1 (§23); each later gate needs its own authorization
- Frozen v1 (commit `644f3f7`) remains an immutable prior audit artifact and historical evidence; v2 is the implementation specification going forward
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

[F] **Review concepts for household-facing results** (not a UI framework):
- **Authoritative:** the result can be relied on for its stated purpose.
- **Informational / non-authoritative:** useful, but not decision authority.
- **Incomplete / unavailable:** the OS cannot truthfully give the complete answer from admissible evidence or current capability.

The test is whether the household can correctly understand which of these a material result is (G12).

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
| G12 | **No silent material limitation.** A knowingly accepted limitation is disclosed at the relevant household-facing surface when omitting it could reasonably lead Adam or Wendy to read an incomplete or non-authoritative result as complete or authoritative. Documentation in this specification or in `CODEX_STATUS.md` alone is not sufficient in that case. The smallest local disclosure or correction is preferred. This is not authorization for a warning framework, banner system or new infrastructure | [F] |

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

[F] Date derivation from (week, `d`):
- `d` is the **existing** optional event field in month-day form (e.g. `'Jan 7'`). Edit-Week offers only the seven days of the event's own week. The 2026 schedule rows carry no `d`; their dates stay in their labels.
- **Event date.** The ISO date of an event in week n is the unique date in `weekStart(n)` .. `weekStart(n) + 6` whose month and day equal `d`. A week spans at most two calendar years, so at most one date can match. No match, or an impossible month-day, fails closed: the authoring tool refuses the row (T-SCH-5a).
- **Due date in a label.** Expected-item tagging reads the due month-day from the label as it does today (`due m/d`, else `(m/d`). A due date may fall just outside its week. Its year is the one that places that month-day **nearest to `weekStart(n)`**. A tie or an impossible date is refused by the authoring tool. At runtime (Edit-Week labels) such an event stays untagged, as an unparseable due date does today.
- For weeks 1-30 the nearest-date rule gives the same year as today's rule (January → following year, otherwise 2026) for every tagged 2026 event. Read-only check, 2026-10-07: all 51 tagged obligation events in weeks 1-30, 0 differences. Every 2026 expected-item ID is therefore unchanged.
- The expected-item ID year is `planYearOfWeek(n)`.

[F] Consequences:
- The household week equals today's displayed "Cal Wk" for weeks 1-30.
- Week 31 changes from "Cal Wk 53" to **2027 Wk 1**.
- An event dated Jan 1 in week 82 is 2028-01-01 and belongs to plan 2027.

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
- [F] Every 2027 event carries a date in the **existing** event `d` field (e.g. `'Jan 7'`). The ISO date is derived from the week and `d` by the §3 rule (R1). **No new event field is added** (R4).
- [F] **Private inputs stay private.** The owner input file is kept outside the repository (with the private evidence). It is never committed to make a test convenient.
- [F] **Verification contract.** Exact regeneration needs the private file, so it is proven at freeze time, not by later CI:
  1. **At authoring/freeze time (private file present):** the tool generates `WD_2027`, then a **regeneration check** regenerates it again and requires a byte-for-byte match with the block about to be embedded (T-SCH-5d). A **freeze manifest** is produced: generator commit, issuer-rules file hash, embedded `WD_2027` block hash, private input-file hash, date and owner approval.
  2. **In CI, without the private file:**
     - structural checks: card payment dates against the issuer rules (the rules file is in the repository; it holds no amounts); no pay event earlier than scheduled; every event has `d` and its date lies in its week (§3); every label due date resolves without a tie; no commission-tax or variable-income amounts; contiguity of weeks 31-82 (T-SCH-5a);
     - the embedded `WD_2027` block hash equals the hash in the repository freeze manifest (T-SCH-5b). This detects accidental or unauthorized edits to the block. It is **not** tamper-proof against a coordinated edit of both the block and the manifest hash. The second control is the owner-approved golden recapture (R6), review of any diff that touches the block or the manifest, and the private provenance record (step 3). No cryptographic signing is added;
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

### 5.5 Edit-Week overrides and the effective schedule

- [F] The model does not consume the composed schedule directly. It consumes the **effective schedule**: the output of the unchanged `reconEffectiveWD()` over the runtime composition and the stored `model_week_overrides`. That function overlays a non-custom override's events onto the row with the same week, and appends every custom override as an extra row ordered by week.
- [F] The schedule invariants S1 and S2 (§6) apply to the **effective** schedule, not only to the composed source.
- [F] **Preflight inspection (staging and production):** every `model_week_overrides` row with `week_num ≥ firstWeekOfPlan(2027)` is inspected, custom and non-custom.
  - If any exists, the deploy **FAILS CLOSED**.
  - No rollover step deletes or transforms such a row.
  - The owner decides each row's disposition with evidence: the row, when it was written, and its effect on the effective schedule. The decision is recorded. This specification does not prescribe the disposition.
- [F] Why this matters:
  - a non-custom override at week 31 written before deploy was entered against the legacy frozen row, and would silently replace the events of `WD_2027[31]`;
  - a custom row numbered 32 would add a second live week 32.
- [F] After deploy, C6 prevents new duplicates: no client path creates a custom row at or below the last authored week. An Edit-Week override of a 2027 week is an ordinary planning input against its `WD_2027` row.
- [F] Overrides are **financial model inputs**. Post-deploy overrides at week ≥ 31 are handled by the rollback guard (§18 condition 4d), not as residue.
- Production evidence E-1 (§17.2) recorded zero such rows. The preflight re-checks it.
- [B] Where the detection rule runs (preflight script or test helper) and its report format.

## 6. Plan-year derivation and invariants

[F] Every invariant below is enforced by test (§13).

- **S1:** the runtime schedule is contiguous, one row per absolute week, each 7 days, Sunday-start. This holds for the composed source and for the effective schedule (§5.5).
- **S2:** **exactly one runtime week 31 exists, and it is the `WD_2027` row**, never the `WD_2026_FROZEN` row. This holds for the composed source and for the effective schedule. A post-deploy Edit-Week override of week 31 is a planning input on that row and does not create a second week 31.
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

Read-only production verification (2026-10-07): all existing commitment and snapshot rows satisfy P-Y1 and P-Y2 (0 violations; E-2). The preflight re-checks this.

## 7. Goals and opening snapshots

### 7.1 Eligibility invariant

[F] **O1: A goal is snapshot-tracked for plan year Y if and only if an authorized opening snapshot exists for that goal at the designated opening position for Y.** The opening position is absolute week `openingWeekOfPlan(Y)` (§3).

[F] For 2026 the derived set equals the current hard-coded eligible nine. Production verification: exactly nine opening snapshots at week 5, matching the list (E-2).

### 7.2 Opening snapshots are control data

- [F] **O2:** snapshots with `source = 'opening_anchor'` are control data. They are created **only** by the owner-authorized plan-year initialization procedure (§7.4).
  - Ordinary closeout writes its normal snapshot rows (`source = 'reconciliation'`) for the week being closed, as in the existing closeout model. It **never creates, overwrites or modifies an `opening_anchor` row**, and never writes at the opening position.
  - The correction path writes `source = 'correction'` rows at closeable weeks only and **rejects the opening position**.
  - No client role can write snapshots.
- [F] **O3:** opening snapshots for Y may be re-initialized only before Y's first closeout, and only by the reversal-and-rerun mechanism of §7.4. **After the first closeout they are immutable.** Later adjustments use ordinary corrections at closeable weeks.
- [F] **Late prior-year corrections (owner, 2026-10-07).** After Y's first close, an authorized correction to Y−1 history never rewrites Y's opening state. If that correction reveals a real financial effect that belongs in Y, it is represented by an explicit Y correction under the existing correction semantics, independently supported by evidence. A synthetic Y adjustment made only to force arithmetic continuity is not permitted. The broader older-period correction architecture remains Gate R work.

### 7.3 Per-year goal identity

- [F] Every snapshot-tracked goal belongs to exactly one plan year.
- [F] 2027 goals are **new registry rows with new identifiers**. A goal that continues from 2026 is issued again for 2027, with an **explicitly carried opening value**; it does not silently inherit state. A 2026 identifier is never reused as a 2027 identifier.
- [F] 2026 goals keep their history unchanged. Their final status uses **existing** status values; no new status is introduced (§7.4 final-status set).
- [F] **No `goal_registry` schema change.** Eligibility comes from O1; plan-year membership for display comes from O1 plus the legacy and UNASSIGNED rules of §7.6.
- [B] Identifier convention (e.g. `<name>_2027`).

### 7.4 Initialization, disposition and initialization window

- [F] **O4: initialization window.** Initialize 2027 after the **final 2026 close (absolute week 30)** and **before the first 2027 close (absolute week 31)**, because carried values must equal the final 2026 funded position. Expected dates: week-30 close about Jan 2-3, 2027; week-31 close about Jan 9-10, 2027.
- [F] **The first 2027 close fails closed** unless both hold:
  - **owner gate:** an initialization **PASS** for 2027 is recorded in its manifest and confirmed by the owner before the close (§17 step 9). Initialization is atomic and is the only writer of opening anchors (O2), so committed anchors imply that its postflight passed; the recorded PASS is the evidence of that;
  - **machine gate:** the first-close re-verification in the closeout wrapper passes (§10).

  "At least one opening anchor exists" is **not** sufficient.
- [F] Until initialization, the Goals view reports **2027 goals not initialized (INCOMPLETE)**.
- [F] **O5: disposition completeness.** Every 2026 snapshot-tracked goal is exactly one of:
  - **carried:** exactly one 2027 successor names it as predecessor. The successor's opening value equals the predecessor's **final 2026 funded value** (its plan-2026 snapshot at week 30, the final 2026 week), unless a permitted stated reason is recorded; or
  - **closed:** no successor names it, and its registry status is in the final-status set.

  **A carried balance cannot silently disappear.**
- [F] **Final-status set = {`executed`, `archived`}.** This follows the existing status semantics of the goal registry specification:

  | Status | Existing meaning | Final? |
  |---|---|---|
  | `executed` | Completed and deployed | **Yes** |
  | `archived` | Hidden from UI and model (retired) | **Yes** |
  | `funded` | Target reached; money still held, not yet executed | No |
  | `funding`, `planned` | Active | No |
  | `paused` | Temporarily halted | No |

  Closing a predecessor as `archived` with a non-zero final funded value requires a stated reason in the manifest. No new status is introduced.

  **Owner policy (2026-10-07):** use `executed` only when the goal was actually completed or deployed and that status is financially truthful. Use `archived` when a goal is retired without a successor and `executed` would be false. A status is never chosen because it makes rollover or later corrections easier. The fail-closed consequence of `archived` (§7.5) is accepted; before the first 2027 close the reversal mechanism below applies, and after it no rollover workaround is provided.
- [F] **Permitted stated reason:** a reason supplied for that goal in the owner-approved input (§21 fields 9-10), recorded in the anchor's note (carried) or in the manifest (closed). An empty reason is not permitted.
- [F] Carried predecessors keep their existing status. Initialization changes a 2026 status only to close a goal.
- [F] **One transaction, all or nothing.** Initialization is an owner-run procedure executed as a single database transaction. Clients cannot call it.
  - **Preflight** (inside the transaction, before any write):
    - week 30 is complete, and no `weekly_reconciliations` row has week ≥ 31;
    - no plan-2027 snapshot exists. If one exists, this is a re-initialization, and the prior initialization must be reversed first (below);
    - the intended 2027 goal set G and the disposition of every 2026 snapshot-tracked goal are read from the owner-approved input;
    - every 2026 snapshot-tracked goal appears exactly once in the disposition;
    - no identifier in G has any plan-2026 snapshot.
  - **Writes:**
    - the 2027 registry rows for G;
    - one opening anchor per goal in G at (plan 2027, week `openingWeekOfPlan(2027)` = 30), with a note in the anchor-note grammar below;
    - the status changes of closed predecessors.
  - **Postflight** (inside the transaction, before commit). Each must hold:
    - **IP-1** set equality: the goals with a 2027 opening anchor are exactly G;
    - **IP-2** every anchor's goal is a registry row inserted by this run, and that row is not `archived`;
    - **IP-3** no anchor's goal has any plan-2026 snapshot (a predecessor cannot be reused as a successor);
    - **IP-4** O5 completeness: every 2026 snapshot-tracked goal is carried or closed, never both, never neither; no successor names a goal that is not 2026 snapshot-tracked;
    - **IP-5** each carried opening value equals the predecessor's final 2026 funded value, or carries a permitted stated reason;
    - **IP-6** each closed predecessor's status is in the final-status set;
    - **IP-7** manifest completeness: the manifest lists every inserted row and every 2026 status before and after, and its counts equal the database changes made inside the transaction.
  - Any failure in preflight, a write or the postflight **rolls back everything**. No row remains.
  - On commit, the manifest records **PASS**, the run identity, the row fingerprints and (in the private evidence) the input-file hash.
- [F] **Re-verification at the first close.** The closeout wrapper re-checks IP-2 to IP-6 when it closes the first week of any plan Y ≥ 2027 (§10), each in a form derived only from the database at that moment:
  - **IP-2 (first-close form):** every anchor's goal exists in `goal_registry` and is not `archived`. "Inserted by this run" is initialization-manifest evidence and is not re-checked at the first close;
  - **IP-3 to IP-6:** as written, with predecessors and stated reasons read from the anchor notes by the grammar below.

  IP-1 and IP-7 depend on the owner input; they are covered by the transaction's atomicity and by O2 (only initialization writes opening anchors).
- [F] **Anchor-note grammar (machine-parsed; frozen before any SQL is authored).** The `note` of every opening anchor for a plan Y ≥ 2027 is exactly one of:
  - `new`: a goal with no predecessor;
  - `carry:<predecessor_id>`: a carried goal whose opening value equals the predecessor's final value;
  - `carry:<predecessor_id>;reason=<text>`: a carried goal whose opening value differs, with the permitted stated reason.

  `<predecessor_id>` is the predecessor's registry identifier exactly as stored, matching `[a-z0-9_]+`. `<text>` is non-empty and contains no line break. Every identifier in the intended goal set G must also match `[a-z0-9_]+` (checked in the preflight). A note outside this grammar fails the postflight and the first-close re-verification. The initialization script and the closeout wrapper parse the same grammar. Opening anchors of the 2026 plan (week 5) are not parsed by it.
- [F] **A 2026 change after initialization.** If a final 2026 value changes after initialization (a week-30 reopen or correction), the re-verification blocks the week-31 close (IP-5). The only remedy is the authorized pre-first-close mechanism:
  1. reverse the initialization exactly per its manifest, in one transaction. The reversal deletes the manifest's rows, restores the recorded statuses, and aborts if any week ≥ 31 is closed or any manifest row differs from its manifest record;
  2. make the week-30 change;
  3. run initialization again.

  A week-30 reopen or correction while a predecessor is `archived` fails closed (§7.5), so the reversal comes first. Every step is owner-authorized.
- [F] **Later plans.** For a plan Y after 2027, read 2027 as Y and 2026 as Y−1 throughout this section. The final week of Y−1 is `openingWeekOfPlan(Y)`, and the opening anchors are written there.
- [B] Script form and manifest format. The anchor-note grammar above is [F].

### 7.5 Waterfall and registry loading

- [F] For the 2026 plan, the goal waterfall list is built **exactly** as today (byte-identical behavior; protects the 2026 golden).
- [F] For plan years ≥ 2027, the waterfall includes only goals snapshot-tracked in the current plan year (O1).
- [F] Registry loading **fails closed**: no runtime fallback to hard-coded goals. On failure the Goals and closeout functions are unavailable and the reason is shown. Test harnesses keep explicit fixtures.
- [F] Duplicate-priority validation is scoped **per plan year**.
- [F] A goal that is snapshot-tracked in the target week's plan year but `archived` in the registry is a contradiction. It fails closed:
  - in the client (closeout, correction, waterfall);
  - on the server, in the closeout wrapper and in the correction function (§10).

  The server check adds one predicate to the registry read the wrapper already performs: it already locks and counts the eligible goals' registry rows. It is not a D-11 expansion.

  Consequence: once initialization closes a 2026 goal as `archived`, every later closeout or correction of a 2026 week fails closed. Before the first 2027 close the remedy is to reverse the initialization first (§7.4). After it, such a change needs an owner-authorized forward-fix (Q8).
- [F] **Pre-boundary forward view.** Before the current week reaches week 31, the current plan year is 2026. The waterfall list is therefore the 2026 list, and the unchanged engine applies it to every modeled week, including the 2027 weeks of the forward view. The forward view can therefore show 2026 goals receiving modeled allocations in 2027 weeks.
  - This is display under OWNER HOLD only, never funding authority.
  - It does not express the household rule that 2027 money never funds 2026 goals.
  - It is not changed in rollover (no `runModel` or Gate F change). It is **disclosed locally** while it exists (C25, G12).
  - From week 31 the current plan is 2027. Until 2027 initialization, the 2027 waterfall is empty and the Goals view reports INCOMPLETE.
- [F] The waterfall remains recommendation policy shown under OWNER HOLD. Nothing here authorizes goal funding.

### 7.6 Goals plan-year scoping and the historical group

[F] Plan membership for display, derived without schema change from existing columns:
- **plan Y ≥ 2027:** registry rows with an opening anchor for Y (O1);
- **plan 2026:** the legacy registry population. These are rows with no opening anchor for any later plan that were created before the first later-plan initialization, judged by registry `created_at` against the earliest opening anchor with `model_year ≥ 2027`. Before any later plan is initialized, every row is a plan-2026 row, as today;
- **UNASSIGNED:** any other row, i.e. one created after a later-plan initialization without an anchor for any plan. It never acquires 2026 membership by default. The Goals page shows it in no plan group and states visibly that a goal is not assigned to a plan (INCOMPLETE).

[F] Plan Y's snapshot-tracked goal set is fixed by its initialization (O3). Rollover provides no mid-plan addition; such a goal is not silently classified into any year.

[F] **Prior-plan registry rows.** Once a plan's successor is initialized, the earlier plan's registry rows are not edited as current-plan configuration. The only changes permitted are initialization status changes, their reversal, and a later explicitly authorized historical-correction mechanism (not defined here). Clients have no write access to `goal_registry`; this binds owner-run changes. No history table or versioning is added; stronger protection belongs to H-1.

[F] **Active Goals (current plan year Y).** Every working Goals list, total and projection uses only plan Y's goals and plan Y's weeks:
- the Savings Goals table, the Priorities list, the Funding Plan items and totals, the Funding Timeline, the Cash Flow Mechanics statistics, the Overview Capital Allocation Queue and the What-If Impact goal rows;
- a projection's week range is `firstWeekOfPlan(Y)` (week 1 for 2026) through the final week of Y. "Projected YE" reads the final week of the goal's plan. A goal not completed by that week shows a plan-bound label such as "Not completed within the 2026 plan", never wording that implies the same goal receives the next year's money (C17);
- 2026 and 2027 goals are never mixed in a current-plan list, total or projection.

[F] **Historical group.** Goals of every earlier plan appear in a clearly labelled, read-only "<year> plan" group on the Goals page. It shows recorded facts only:
- the goal's name, target and status as recorded in that plan's registry row. `archived` means hidden from active and current views; it does not remove an archived goal from its historical group;
- its final funded value, taken only from recorded snapshots: the plan's snapshot at the plan's final week, or "no recorded snapshot" for a goal that was never snapshot-tracked. No static, fallback or model value is ever shown in its place;
- its successor, from the next plan's opening-anchor notes, when carried.

It shows no ETA, projection, waterfall, recommendation or What-If, and it has no write control. It never computes a value with current assumptions. In 2028 it holds the 2026 and 2027 groups. It is the rollover bridge for prior-year Goals; the full read-only navigation mechanism is H-1 (§23).

[F] **The 2026 plan before the boundary.** While the current plan is 2026 and no later plan is initialized, the active lists contain exactly today's goals in today's order. Year-bearing text follows C17. The projection range ends at week 30, the final 2026 week; it previously ended at legacy week 31. The engine and the 2026 golden (§14) are unaffected: scoping is display only.

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
| C1 | Period helpers: `planYearOfWeek`, `householdWeek` (+ label), `firstWeekOfPlan`, `openingWeekOfPlan` (§3); event date from (week, `d`) and label due-date year (§3 date derivation) | No |
| C2 | Replace the linear `getCalWeek = 22+n` (and its inline copy) with the household week. Cross-year identity displays show year and week (topbar, week header, history, reconcile/closeout title, timeline). | No |
| C3 | `getCurrentWeek` per §5.3 (true week; INCOMPLETE beyond the schedule; 13-week warning). The existing timezone defect is untouched. | No |
| C4 | Remove 1..31 assumptions: week validity, loops, day options, the budget-rules date band, the Budget month list, What-If limits (including the Scenario Builder week picker). Derived from the runtime schedule, except plan-scoped Goals surfaces, which use the plan's weeks (§7.6). | No |
| C5 | Schedule composition and the `WD_2027` block (§5) | WD data (§12) |
| C6 | `saveWeekEdits`: an edited week is "custom" only if beyond the last schedule week; custom numbering starts after it. Custom-week creation hidden. Prevents double-counting an edited 2027 week (§5.5). | **Yes** |
| C7 | Expected-item tagging: event date and label due-date year per §3; ID year = `planYearOfWeek(week)`. Every 2026 ID is unchanged. | No |
| C8 | `buildPhase2NewCommitments`: `model_year = planYearOfWeek(n)`. Phase 3 the same. | **Phase 2: yes** |
| C9 | `isReservedAsOf`: no longer drops other-plan-year commitments; a P-Y1 violation is treated as reserved and flagged (§8) | **Yes** |
| C10 | Commitment visibility: no plan-year filter (absolute weeks order correctly) | No |
| C11 | Loads commitments and snapshots of all plan years. **Complete or fail closed:** each load that Goals or closeout depends on pages until the exact row count reported for the query (Content-Range) is loaded, as the Register ledger load already does; a short, failed or changing load makes the dependent Goals and closeout results unavailable with the reason shown, never partially rendered. Each snapshot row keeps `model_year`, `source`, `note` and `created_at`, keyed so that rows of different plan years at the same absolute week (e.g. week 30) are never conflated. No new storage or schema | No |
| C12 | The hard-coded snapshot-eligible list is replaced by eligibility derived per **target** week from opening snapshots (O1). Empty → fail closed. An `archived` tracked goal → fail closed (§7.5). | No |
| C13 | `submitCloseout` and `renderCloseoutConfirm`: plan year, expected count and eligible goals come from the **target** week (so week 30 can close on Jan 3) | **Yes (both)** |
| C14 | Waterfall per §7.5 | No |
| C15 | Registry fail-closed loading and per-plan priority validation (§7.5) | No |
| C16 | Commission-tax pool: attestation explicitly pinned to the 2026 plan; pool window limited to 2026 weeks. The `PLAN_YEAR` constant is retired. The 2026 pool and attestation **end with the 2026 plan**. No 2027 commission-tax policy is defined; for plan years after 2026 there is no pool and no attestation. | No |
| C17 | Year-bearing UI text made plan-aware: model range, "31-week", Goals year labels and panel text (e.g. "Overall 2026 Progress", "Cal Wk 23-53"), custom-week text, and the Funding Plan status labels (plan-bound wording, §7.6). Every year in such text is **derived** from the plan year; no literal future year is written. The Goals header subtitle is plan-aware and no longer hard-coded to Alaska and Retirement | No |
| C18 | Pin the current week in the clock-dependent test that fails on its own from Jan 3, 2027 | Test only |
| C19 | Goals plan-year scoping and the read-only historical group (§7.6). Reuses the O1 derivation; it extends the Funding Timeline correction to every Goals working list, total and projection. Not a Goals redesign | No |
| C20 | What-If goal-total disclosure (G12). When the current plan year is 2027 or later, the What-If Impact result (Goals → What-If Impact) shows a visible note at the goal-total figure, and at any summary sentence that uses it, that the current plan's goals are not included in that total (e.g. "2027 goal totals are not included in this What-If result"). The cash-impact, lowest-checking and floor-breach figures are shown unchanged and are not marked invalid. Goal ETA rows for goals of an earlier plan are excluded or labelled with their plan year, so no 2026 goal reads as an active 2027 goal [B: which]. For plan 2026 the result is unchanged. The goal-total machinery itself is not extended | No |
| C21 | Auto-reminder disclosure (G12). In the weekly view's "Action items" section, for weeks whose plan year is 2027 or later, one line states that automatic reminders are generated from the 2026 plan only, that any automatic reminder shown for the week is a 2026-plan reminder, and that 2027 reminders are added as custom tasks. It does not claim that no automatic reminder can appear (week 31 keeps its existing 2026-keyed reminders, §9.1 item 10). No reminder is generated; 2026 weeks are unchanged | No |
| C22 | Decision Queue (Goals → Priorities): its static 2026 items are never presented as current pending decisions. When the current plan is 2027 or later they appear only inside the 2026 historical group, labelled as 2026 decisions and with no "pending" count, or are omitted [B: which] | No |
| C23 | Overview "Next Dollar" line: while owner authority is NOT_AUTHORIZED, a short caveat marks it as modeled and not authorized at **every** household-facing rendered use of `getNextDollarRec` (today two within `renderOverview`), placed at the unprotected rendering sites. The protected `getNextDollarRec` calculation and its pin are unchanged. Its input priority list is plan-scoped by §7.6 (approved scoping); for the 2026 plan that input is today's list | No |
| C24 | Goals allocation engine (Waterfall / Scenarios) output: a short statement that the result is informational and not authorized while OWNER HOLD is on and before Gate F. Its Variable Income 40% tax-reserve step is labelled as a legacy rule that is not current household tax policy. The engine logic, including the 40% step, is unchanged; its correction is follow-on F-1 (§23), whose inventory covers every surviving 40% path | No |
| C25 | Pre-boundary disclosure (§7.5, G12). In week detail, the goal-transfer section of a week whose plan year is later than the current plan year shows one line while that week displays modeled goal allocations. When no opening anchor exists for that week's plan: "2027 goals are not initialized yet; projected goal allocations shown for 2027 weeks still use the 2026 plan." When the plan is initialized but has not yet begun: an equivalent line that the allocations still use the 2026 plan until 2027 begins. Years are derived. The line disappears once the week's plan is the current plan | No |
| C26 | Cash Flow Mechanics base pay (G12; §9.1 item 14). For the 2026 plan, unchanged. For any other plan year, "Monthly Income" and "Planned Monthly Margin (Base Pay)" show the existing unavailable placeholder (the one the panel already shows when budget lines cannot be verified) with a short reason that base pay for that plan is not available in this panel, and the Paychecks flow box shows no amounts. The 2026 pay literals are never shown as current, no pay is inferred from 2026, and no value is derived from schedule events (that would be a second calculation path) | No |
| C27 | Remaining year-pinned surfaces (§9.1 items 15-19), presentation only: (a) Overview Account Integrity labels for Truist Savings and AMEX Savings use plan-neutral account names when the current plan is not 2026; account identity and treatment unchanged; (b) the Overview "Actions" chip carries the C21 qualifier when the current week's plan is 2027 or later; (c) the Scenario Builder's "Change Goal Targets" option and its "Alaska remaining" preview are offered only while the current plan is 2026; (d) the Assumptions page states in one line that its goal amounts, weeks and calendar notes describe the 2026 plan when the current plan is not 2026; (e) the Ask Claude context derives the model range and week count, and labels its fixed 2026 facts as 2026-plan facts | No |

[F] `runModel`, `reconEffectiveWD` and `getActiveModel` are **not changed**.

### 9.1 Year-pinned code inventory and deliberate 2027 behavior

[F] Each hard-coded 2026 goal identifier list and one-off key keeps a stated 2027 behavior. None is extended to 2027 identifiers; doing so would be new functionality.

| # | Item | Where | Deliberate 2027 behavior |
|---|---|---|---|
| 1 | Snapshot-eligible list (`SNAPSHOT_ELIGIBLE_GOAL_IDS`) and the literal expected count | Closeout paths | Replaced at runtime by the O1 derivation (C12, C13) |
| 2 | `alaska` special cases: target override, Truist Savings destination, completion check, `startsAfter` dependency, engine metrics, notes | Engine and display | 2026 only. 2027 identifiers never match, so 2027 goals take the generic path (registry target and destination) |
| 3 | `adam_ira` special cases: the initial AMEX Savings holding, the per-week snapshot override, the retirement-remaining metric, the related threshold constant and window anchor | Engine and display | 2026 only. The retirement-remaining metric keeps tracking the 2026 goal. Where it appears in 2027 weeks it is listed in the 2027 golden expected-effect record (§15) |
| 4 | `adam_401k` payroll accrual with `PAYCHECK_WKS` (absolute weeks up to 31); `adam_401k` and `wendy_sep` sort and exclusion rules; the paycheck readiness note | Engine and display | 2026 only. No accrual or readiness note after week 31; 2027 401(k) tracking is out of scope (§20). At runtime week 31 the accrual behaves as today for the 2026 goal; listed in the effect record |
| 5 | AMEX-holding goal lists (IRA and 529 goals; lookahead gate) and `HOLDING_TO_AMEX_GOALS` (`wewe_rccl`, `wewe_dcl`) | Engine and engine panel | 2026 only. 2027 goals are not holding-type (§21 field 12) and use the generic destination |
| 6 | `christmas_cruise` milestone display | Goals view | 2026 only |
| 7 | Funding Timeline goal list | `_renderGoalsFunding` (not protected) | C19 |
| 8 | What-If tracked-goal totals | `diffModels` (not protected) | Unchanged machinery. In 2027 the goal totals cover only 2026 goals; the limitation is disclosed at the result (C20) |
| 9 | One-off action defaults (`tax_base`, `commission_tax`, `alaska_draw`, `costco_visa`) and the modeled Alaska draw | Actions | All at 2026 weeks; they remain 2026 history. No 2027 one-off action key is created (§5.2) |
| 10 | Auto-reminders: year fixed at 2026 and absolute-week lists (including the reminder-only list inside the engine, which has no cash effect) | `getAutoRemindersForWeek` | Unchanged. Entries at week 31 still fire with their existing keys. No reminders are generated for weeks 32-82; the absence is disclosed in the weekly action list (C21) |
| 11 | Commission-tax pool and attestation (plan 2026, boundary week 5) | C16 | Ends with the 2026 plan |
| 12 | Hard-coded registry fallback | Registry load | Not used at runtime (C15); test fixtures keep it |
| 13 | Default Alaska and retirement targets passed to the engine | Engine arguments | 2026 only; unchanged |
| 14 | 2026 base-pay literals (Adam and Wendy paychecks) in Cash Flow Mechanics "Monthly Income", "Planned Monthly Margin (Base Pay)" and the Paychecks flow box | `_renderGoalsSavings` | C26: unavailable placeholder with a reason for any plan other than 2026 |
| 15 | Account-role labels "Alaska Funding" (Truist Savings) and "IRA Staging" (AMEX Savings) | `renderOverview` Account Integrity | C27(a): plan-neutral account names when the plan is not 2026 |
| 16 | Overview "Actions" chip ("All done") | `renderOverview` | C27(b): C21 qualifier for 2027-plan weeks |
| 17 | Scenario Builder "Change Goal Targets" (Alaska and Retirement only, writes the `goals` key-value targets) and "Alaska remaining" preview | `_renderScenarioForm` and preview | C27(c): offered only while the plan is 2026 |
| 18 | Assumptions page 2026 framing (starting balances, calendar notes, goal waterfall amounts and weeks; also the 40% rule text, which is in F-1) | `renderAssumptions` | C27(d): one dated line when the plan is not 2026 |
| 19 | Ask Claude context: the June 2026 to January 2027 range text, "all 31 weeks", fixed 2026 starting facts | Ask Claude prompt builder | C27(e): derived range and week count; fixed facts labelled 2026 |

The inventory was taken read-only on 2026-10-07 by searching the client for the 2026 goal identifiers, action keys and other material year-pinned household constants (pay, account-role labels, year-bearing text). Gate 1 repeats that widened search. Any additional hit is added with a stated 2027 behavior before RED tests are written.

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
- **archived contradiction:** raise if any goal tracked in the target week's plan year has registry status `archived` (§7.5);
- **proven global contiguity:**
  - K = the set of complete weeks ≥ `openingWeekOfPlan(2026) + 1` (= 6). "Complete" = reconciliation present plus every snapshot required by that week's plan year;
  - K must equal {6, ..., max K}. A gap makes every normal closeout raise, naming the gap;
  - the next closeable week = 6 + |K|;
  - the existing half-close repair path for the earliest incomplete week is unchanged;
- **first-close re-verification:** when `p_week_num = openingWeekOfPlan(p_model_year) + 1` and `p_model_year ≥ 2027`, re-check §7.4 IP-2 to IP-6; any failure raises;
- the latest completed week for reopen is global;
- the monotonic prior and every snapshot read/write are scoped to `p_model_year`.

**`save_reconciliation_with_commitments`:**
- P-Y3; week ≥ 1;
- **patch scope:** `origin_model_week ≤ p_week_num` **and** `model_year ≤ p_model_year`;
- new commitments still carry `model_year = p_model_year`.

**Other functions:**
- `validate_commitment_state`: week ≥ 1.
- `save_goal_funding_snapshots`: week ≥ 1; when called from closeout it writes `reconciliation` rows only, never an `opening_anchor` row and never at the opening position (O2).
- `correct_goal_funding_snapshot`: P-Y3; eligibility from O1; the archived contradiction (§7.5); **rejects the opening position**.

[F] **Boundedness.** Three predicates were added after the v1 review: the archived contradiction, proven contiguity, and the first-close re-verification. Each is a read-only check inside a function already in D-11 scope, over tables that function already reads. None adds an object, grant, table or column.

**Unchanged [F]:**
- `weekly_reconciliations`, `weekly_tasks`, `weekly_notes`, `model_week_overrides`, `custom_tasks` (no re-key);
- `goal_registry` schema;
- RLS: the 2026 pins on `cash_commitments` are inert because clients have SELECT only;
- grants (E-4);
- the advisory lock key;
- the `model_year` default;
- `repair_commitments_for_week` (no client execute grant; no callers; documented as 2026-only).

[F] The initialization procedure (§7.4) and the rollback package (§18) are owner-run transactions. They are not client-callable functions and add no grant. [B] Their form.

## 11. Category rollover policy

[F] **Durable category principle:** a year belongs in category identity only when it represents a real accounting or plan boundary. Ongoing economic-purpose categories do not receive annual successor keys merely because the calendar year changes. Event-specific categories keep the event's identity and become inactive when settled. This is not a category migration project; existing keys remain authoritative.

| Category key | Ruling [F] |
|---|---|
| `health_fitness.flexible_spending_2026` | Keep unchanged. Later 2026 claims and reimbursements stay attributable to it. |
| `health_fitness.flexible_spending_2027` | **Create** in the deploy window with the same treatment attributes as the 2026 FSA category. The year is real identity (annual election and claim period). It is the **only** data mutation in the rollout manifest. Rollback reverses it; if any row references it, the rollback guard aborts for owner disposition (§18, 4c). |
| `business.jabian_expenses_2026`, `business.jabian_deposits_2026` | **Keep keys. No `_2027` successors.** Approved household labels: "Jabian Expenses" and "Jabian Reimbursements". |
| `taxes.vio_transfer_2026` | **Keep key. No successor.** Approved household label: "Tax Reserve Transfers". |
| `trips.*_2026` | Keep. Mark inactive through the existing mechanism once settled. Late genuine trip transactions stay with the trip. Not gated on rollover. |

[F] **The approved Jabian and Vio label changes are not part of the rollover.** They are a separate owner-authorized cleanup, outside the deploy window and outside the rollout and rollback manifests.

**Label-change verification (read-only, 2026-10-07):**
- No code looks up categories by label.
- Pairing uses keys (`reimbursement_pairing_key`), so it is unaffected.
- The zero-write fingerprint hashes full table content. A label edit therefore changes the `categories` fingerprint as an **expected, attributable change**; it does not change identity.
- The protected `renderBudget` contains a help-text literal naming "Jabian Expenses 2026". It is left unchanged: it is cosmetic, and changing it is not within the §12 exceptions.
- [F] The separate label cleanup repeats this verification first and records the expected fingerprint change.

## 12. Protected and frozen surfaces: authorized exceptions

[F] Each exception requires: a RED test demonstrating the rollover failure first; a minimal change; independent review; and a re-pin after acceptance. Nothing beyond this table is authorized.

| Surface | Exception | Reason |
|---|---|---|
| Schedule data (Do Not Touch: WD) | Rename to `WD_2026_FROZEN` (rows unchanged); add the composition and the `WD_2027` block | §5 |
| `saveWeekEdits` | C6 | Prevents week double-counting |
| `submitCloseout`, `renderCloseoutConfirm` | C13 | Plan year and eligibility per target week |
| `isReservedAsOf` | C9 | Cross-year reservation |
| `buildPhase2NewCommitments` | C8 | Plan year per target week |
| Reconciliation RPCs and state machine (Do Not Touch) | §10 only (D-11) | Continuous weeks, plan-year validation, data-derived eligibility, proven global contiguity, first-close re-verification, cross-year resolution |
| `cash_commitments` schema (Do Not Touch) | Check replacement and P-Y1 | §10 |
| `goal_funding_snapshots` | Check replacement and P-Y2 | §10 |
| Script-body growth rule | Period helpers and `WD_2027` rows (data, not feature code) | §5, §9 |
| Golden masters (R6) | 2026 harness input selection; new 2027 fixture (synthetic goal data, §15); capture tool support | §14, §15 |

## 13. RED-first test specification

[F] Written and failing before the corresponding change. IDs are referenced in §24.

**Identity and calendar (T-ID):**
- **T-ID-1** `householdWeek` at weeks 1, 30, 31, 32, 82, 83 and 135 equals §4.
- **T-ID-2** `planYearOfWeek` at the T-ID-1 points; `firstWeekOfPlan(2027) = 31` and `(2028) = 83`; `firstWeekOfPlan(2026)` is rejected (fail closed); `openingWeekOfPlan(2026) = 5`, `(2027) = 30`, `(2028) = 82`; JS and SQL helpers agree on all of these.
- **T-ID-3** `weekStart` of 31, 32 and 82.
- **T-ID-4** No absolute week number appears in rendered household labels.
- **T-ID-5** Clock mocked at 2027-01-02, 2027-01-03, 2027-01-10 and past the schedule: true week, INCOMPLETE state, 13-week warning.
- **T-ID-6** Date derivation (§3):
  - week 82 with `d` `'Jan 1'` → 2028-01-01, plan 2027;
  - week 30 `'Jan 1'` → 2027-01-01, plan 2026;
  - week 31 `'Jan 3'` → 2027-01-03, plan 2027;
  - a `d` outside its week is refused;
  - a week-82 label due `1/5` → 2028-01-05 with an ID prefix of plan 2027 and week 82;
  - every 2026 expected-item ID is unchanged (with T-CC-1).

**Schedule (T-SCH):**
- **T-SCH-1** Runtime schedule contiguous 1..82, 7-day Sunday weeks.
- **T-SCH-2** **Exactly one runtime week 31, deep-equal to `WD_2027[31]`, and not equal to the frozen row.**
- **T-SCH-3** Runtime weeks 1-30 byte-equal `WD_2026_FROZEN`; the frozen source hash is unchanged.
- **T-SCH-4** In runtime code, `WD_2026_FROZEN` is referenced only by the composition step. Test code is exempt (static test).
- **T-SCH-5a (CI)** Structural checks on `WD_2027`: issuer-rule dates, `d` present and inside its week, label due dates resolve without a tie, no pay earlier than scheduled, no commission-tax or variable income, contiguity.
- **T-SCH-5b (CI)** Embedded `WD_2027` block hash equals the repository freeze manifest (detects accidental or unauthorized edits; see §5.2 for its limit).
- **T-SCH-5c (CI)** Generator determinism and output on a synthetic public fixture.
- **T-SCH-5d (freeze time, private)** Regeneration from the private inputs equals the block to be embedded, byte for byte. Recorded in the freeze manifest and private evidence; not runnable in CI.
- **T-SCH-6 (CI)** The generator refuses a synthetic fixture with a missing or contradictory input.
- **T-SCH-7** Date-to-week mapping, Budget months and What-If limits cover the schedule.

**Edit-Week (T-EDIT):**
- **T-EDIT-1** An override for week 33 is not custom; the effective schedule has exactly one week 33.
- **T-EDIT-2** Custom-week creation is unavailable.
- **T-EDIT-3** Effective schedule and override preflight, using the unchanged `reconEffectiveWD()` over the runtime composition:
  - (a) a non-custom override at week 31 written before deploy makes the effective week 31 differ from `WD_2027[31]`. The preflight detector flags that row;
  - (b) a custom override numbered 32 makes the effective schedule contain two week-32 rows. The detector flags that row;
  - (c) with neither row, the effective schedule satisfies S1 and S2 (one row per week 1..82; exactly one week 31, deep-equal to `WD_2027[31]`);
  - (d) the detector reports FAIL for (a) and (b) and modifies no row.

**Commitments (T-CC):**
- **T-CC-1** Every expected-item ID for weeks 1-30 is identical before and after, including the week-30 January-dated items.
- **T-CC-2** A 2027 February due date produces year 2027 in the ID and `due_date`.
- **T-CC-3** Phase 2 and Phase 3 plan year follow the target week (week 30 → 2026 while the current week is 31).
- **T-CC-4** A prior-plan-year open commitment is reserved and visible at week 31.
- **T-CC-5** A P-Y1 violation is reserved, flagged and blocks closeout.

**Goals (T-GL):**
- **T-GL-1** Derived eligibility: week 30 → the 2026 nine; week 31 → the 2027 initialized set.
- **T-GL-2** No 2027 opening snapshots → week-31 closeout unavailable in the client (fails closed). A failed first-close re-verification is a server raise (T-SRV-2, T-SRV-14).
- **T-GL-3** `submitCloseout` for week 30 while the current week is 31 sends plan 2026 with its count; week 31 sends plan 2027 with its count.
- **T-GL-4** The 2026 waterfall is identical to today; the 2027 waterfall contains only 2027-initialized goals.
- **T-GL-5** Registry failure → no fallback; closeout unavailable.
- **T-GL-6** Priority validation per plan year.
- **T-GL-7** An archived goal with an opening snapshot in the target week's plan fails closed (client).
- **T-GL-8** Plan scoping (C19, §7.6), current plan 2027 with 2027 initialized. Each §7.6 working surface is checked individually: the Savings Goals table, the Priorities list, the Funding Plan items and totals, the Funding Timeline, the Cash Flow Mechanics statistics, the Overview Capital Allocation Queue and the What-If Impact goal rows. On each:
  - no 2026 goal appears; every 2027 goal appears exactly once;
  - Funding Plan totals equal the sums over the 2027 goals;
  - "Projected YE" reads week 82; a goal not completed by week 82 shows the plan-bound label.
  - A registry row created after initialization without an anchor appears in no plan group and the UNASSIGNED notice is shown.
- **T-GL-9** Historical group (§7.6):
  - in 2027 the "2026 plan" group lists every 2026-plan goal with its recorded target and status, its week-30 snapshot (or "no recorded snapshot") and its successor;
  - the fixture includes a 2026 goal that was never snapshot-tracked, shown with "no recorded snapshot" and never a static or fallback value, and an `archived` closed predecessor with a non-zero final funded value, shown with that recorded value and status;
  - it shows no ETA, projection, waterfall or recommendation and no write control;
  - the facts are unchanged after the week-31 and week-32 closes;
  - with a 2028 schedule fixture, both the 2026 and 2027 groups are present.
- **T-GL-10** The 2026 plan before the boundary (§7.6):
  - with the current week at 29 and no later plan initialized, the active lists equal today's goal set and order;
  - "Projected YE" for a 2026 goal reads week 30; a goal not completed by week 30 reads "Not completed within the 2026 plan" (year derived);
  - the engine output and the 2026 golden are unchanged.
- **T-GL-11** Plan-aware text (C17, C22):
  - with the current plan at 2027, the Goals header contains no hard-coded Alaska or Retirement text and names the plan year;
  - the Decision Queue shows no pending count and no 2026 item outside the 2026 historical group.

**Truthfulness disclosures (T-TR):**
- **T-TR-1** What-If (C20):
  - with the current plan at 2027, the note appears at the goal-total figure and at every summary sentence using it;
  - no earlier-plan goal row appears unlabelled in the Goal ETA table;
  - the cash-impact and floor-breach figures still render;
  - with the current plan at 2026, the rendered result equals today's output.
- **T-TR-2** Auto-reminders (C21): the note appears in the action list for weeks 31, 32 and 82, and not for week 30. At week 31 the existing 2026-keyed reminders and the note render together, and the note does not claim that no reminder can appear. The reminder lists are unchanged.
- **T-TR-3** Pre-boundary (C25):
  - current week 29, 2027 not initialized: week-31 and week-40 goal-transfer sections show the "not initialized" line; week 30 does not;
  - current week 30 with 2027 initialized: the "until 2027 begins" variant shows instead;
  - current week 31: no line on any 2027 week;
  - the modeled amounts themselves equal the values without the change.
- **T-TR-4** Next Dollar (C23): every rendered occurrence of the Next Dollar text carries the caveat while owner authority is NOT_AUTHORIZED (the test enumerates all occurrences, not one); the `getNextDollarRec` string and its protected pin are unchanged.
- **T-TR-6** Cash Flow Mechanics (C26):
  - with the current plan at 2027, neither 2026 pay literal nor any figure derived from them (monthly income, per-earner monthly amounts, margin) appears; the unavailable placeholder and the reason appear instead;
  - with the plan at 2026, the panel output equals today's.
- **T-TR-7** Remaining surfaces (C27), current plan 2027:
  - the account names replace "Alaska Funding" and "IRA Staging";
  - the Actions chip carries the qualifier;
  - "Change Goal Targets" and "Alaska remaining" are absent;
  - the Assumptions line is present;
  - the Ask Claude context contains the derived range and no undated 2026 fact.
  
  With the plan at 2026, each surface equals today's output.
- **T-TR-5** Allocation engine (C24): the informational statement and the 40% legacy label appear; for the same inputs, the engine's steps and amounts are unchanged.

**Loads (T-SNAP):**
- **T-SNAP-1** Complete or fail closed (C11):
  - with a fixture whose snapshot query reports more rows than one page returns, the loader pages until the reported count is loaded;
  - a short or count-mismatched load makes Goals and closeout unavailable with the reason shown, and no funded value renders;
  - plan-2026 and plan-2027 rows at week 30 stay distinct, with `model_year`, `source` and `note` retained;
  - the same holds for the commitment load.

**Commission tax (T-CT):**
- **T-CT-1** The 2026 attestation stays valid while the current week is in 2027; the pool is limited to 2026 weeks; no pool or attestation exists for plan 2027.

**Preflight (T-PRE):**
- **T-PRE-1** Catalog assertion:
  - on a production-shaped catalog (E-3) the preflight passes;
  - it fails if a `week_num` column of an unchanged week-keyed table is not integer;
  - it fails if such a table has a week upper-bound check.

**Server (staging) (T-SRV):**
- **T-SRV-1** Robustness test of a state outside the normal O4 sequence: week 30 closes as 2026 while 2027 opening snapshots exist.
- **T-SRV-2** Week 31 without opening state raises; with it and a passing re-verification, succeeds.
- **T-SRV-3** Contiguity is proven:
  - closing a week before its predecessor raises;
  - a gap fixture (a week below the latest complete week that is not complete) makes every normal closeout raise, naming the gap;
  - the half-close repair of the earliest incomplete week still works.
- **T-SRV-4** `p_model_year` mismatch raises.
- **T-SRV-5** 2026 goal IDs submitted for week 31 raise.
- **T-SRV-6** The cross-year patch succeeds and keeps `model_year` 2026 and origin unchanged.
- **T-SRV-7** A future-plan-year patch raises.
- **T-SRV-8** The P-Y1 and P-Y2 table checks reject violating rows.
- **T-SRV-9** Monotonic check against the opening snapshot.
- **T-SRV-10** Correction at the opening position raises; correction at a 2027 closeable week succeeds.
- **T-SRV-11** Reopen of the latest week works across plan years.
- **T-SRV-12** Closeout cannot create, overwrite or modify an `opening_anchor` row, and cannot write at the opening position.
- **T-SRV-13** After plan Y's first close, re-initializing Y's opening snapshots is rejected (O3): the reversal aborts.
- **T-SRV-14** Initialization (§7.4):
  - (a) a failure injected after some writes leaves zero residue: row fingerprints equal the pre-initialization state;
  - (b) an intended goal without an anchor fails the postflight (IP-1);
  - (c) a successor identifier equal to a 2026 snapshot-tracked identifier fails (IP-3);
  - (d) a 2026 snapshot-tracked goal that is neither carried nor closed fails (IP-4);
  - (e) a closed predecessor with a status outside {`executed`, `archived`} (e.g. `funded` or `paused`) fails (IP-6);
  - (f) a carried value that differs from the final 2026 value without a stated reason fails (IP-5); the same difference with a permitted stated reason (`carry:<id>;reason=<text>`) passes, at initialization and at the first close;
  - (f2) a note outside the anchor-note grammar fails the postflight and the first-close re-verification;
  - (g) after a successful initialization, a changed week-30 value for a carried predecessor makes the week-31 close raise. After reversal and a fresh initialization, the week-31 close succeeds;
  - (h) a successful run records PASS. Its manifest lists every inserted row and status change and matches the database changes (IP-7).
- **T-SRV-15** The closeout wrapper and the correction function raise when a goal tracked in the target week's plan has registry status `archived`.

**Rollback (T-RB):**
- **T-RB-1** The rollback guard aborts, changing nothing, on each condition of §18 (1, 2, 3, 4a-4e), one fixture per condition.
- **T-RB-2** Before the point of no simple return, rollback restores the prior implementation:
  - RB-1 to RB-4 pass;
  - with no post-deploy writes, every pre-existing baseline row is byte-identical to its baseline.
- **T-RB-3** Rollback after a legitimate post-deploy 2026 close (a week closed after deploy, including a patch to a pre-existing commitment row):
  - that week's reconciliation, snapshots and commitment rows are preserved and enumerated;
  - the patched commitment keeps its post-deploy value;
  - RB-1 to RB-4 pass.
- **T-RB-4** The 2027 FSA category:
  - with the row present and unreferenced, the guard reports eligible and rollback deletes exactly that row;
  - with any referencing row, the guard aborts (4c).
- **T-RB-5** Staging sequencing (§16):
  - at the rehearsal step, conditions 1-3 are false and the guard reports eligible;
  - after re-establishment, the candidate state matches the pre-rehearsal checkpoint;
  - the harness refuses the week-31 close until that match is recorded;
  - after the week-31 close, the guard aborts (condition 1).

**Intentional expectation changes** (listed up front, reviewed, never silent). The inventory below was taken read-only on 2026-10-07. Gate 1 repeats the search for each listed token and adds any further hit before RED tests are written.

- `test_regression.js`:
  - the schedule source-extraction token (`const WD=[`) changes with the rename. The pinned content hash of weeks 1-15 must stay equal;
  - schedule length assertions (`WD.length===31` and runModel output length 31 at several sites): assertions on the frozen source stay 31; assertions on the runtime schedule become the authored length;
  - `getCalWeek` expectations, including `getCalWeek(31)===53` and `getWeekStartDate(31)`;
  - the date-to-week null boundary tests (`dateToModelWeek` with 2027 dates);
  - the Budget available-months count;
  - source assertions on the 2026 RPC literals (`<> 2026`) and the week check `BETWEEN 1 AND 31`;
  - the runtime week-31 expected-item ID (`2026mw31_…` becomes a plan-2027 prefix). Tests on the frozen row are unchanged;
  - `PLAN_YEAR` reference tests;
  - assertions on the hard-coded snapshot-eligible list and the literal expected count of nine (C12);
  - assertions on the hard-coded registry fallback at runtime (C15). Fixtures keep the list;
  - the clock-dependent test in C18.
- `test_release_a.js`: `PLAN_YEAR` in the commitment fixture.
- `test_release_b.js`: week-label expectations built from `getCalWeek` (C2).
- `e2e.js`: What-If date limits with 2027 dates; `PLAN_YEAR`; the literal expected count; hard-coded registry fallback references.
- `tools/audit.js`: the 31-week expectation.
- `tools/capture-golden-master.js`: refuses a week or goal count change (capture tool support, §12).
- Verified unchanged: fixtures that carry `model_year: 2026` and `2026mw…` IDs for 2026 weeks (`test_g1.js`, `test_release_a.js`).

## 14. 2026 golden-master preservation

- [F] The existing 2026 fixture is **not modified**.
- [F] The harness runs it on the full 31-row `WD_2026_FROZEN` with its existing pinned inputs. The result must be byte-identical.
- [F] Runtime check: weeks 1-25 of the runtime composition produce output identical to the frozen run.
- [F] Weeks 26-30 may differ only because their look-ahead now reaches 2027 rows. Every such difference is listed and attributed in the evidence record. None is "fixed" by editing expectations.
- [F] **Parametric harness selection.** The harness runs each plan's golden on that plan's own frozen composition, from week 1 through that plan's final week (2026: the 31-row frozen source as above; 2027: weeks 1-82). Appending a later plan's block (e.g. `WD_2028`) therefore cannot change an accepted earlier golden through look-ahead.

## 15. 2027 golden procedure and dependency chain

[F] Dependency chain (this controls timing; there is no other golden deadline):
1. Owner inputs final [I]: schedule values and the 2027 goal list (targets and priorities affect the model).
2. `WD_2027` generated from the private inputs; freeze-time regeneration check passed (T-SCH-5d); freeze manifest recorded; CI checks green (T-SCH-5a-c); `WD_2027` frozen.
3. 2027 golden **dry run**: runtime schedule weeks 1-82, a pinned current week, and a committed **synthetic** goal fixture: the 2026 registry and week-5 opening rows as already committed in the existing 2026 fixture, plus **synthetic** 2027 goals and synthetic 2027 opening values. The synthetic part is labelled synthetic and contains no owner [I] value. An expected-effect record is produced, including the §9.1 items visible in 2027 weeks.
4. **Owner approval**, then capture to a new fixture file.
5. **Real-input evidence (private, at freeze time):** a dry run with the real 2027 goal list and the real `WD_2027`. It proves that the real inputs run through the unchanged engine without failure, and that the owner reviewed the resulting effect record. Its hashes and record are kept in the private evidence. It is not a CI test and is not committed.
6. Rollout package frozen (client hash, server package, rollback package, initialization procedure, preflight).
7. Staging rehearsal passed (§16).
8. Production within **Dec 12-19, 2026** (Dec 19 hard latest).

Notes:
- [F] The golden does **not** depend on production opening values (set at initialization) or on December statement actuals (runtime evidence).
- [F] Any later change to `WD_2027` requires an owner-approved recapture (R6).
- [F] The private-input ruling is unchanged: no real 2027 goal value is committed.
- *Recommendation, not a requirement:* finalize inputs around mid-November so steps 2-7 fit before Dec 12.

## 16. Staging rehearsal

[F] Sequence:
1. **Target.** Restore a fresh encrypted production backup (DR-1 method, with the security posture file) into an **isolated target**: a preview branch or temporary project (preferred).
   - The shared staging project holds the uncommitted AU-11 package state and is not overwritten.
   - If no isolated target is available, use the shared staging project only with an explicit preservation procedure: capture the AU-11 state (dump plus fingerprints) first, then re-apply it at step 16 with a fingerprint-equality proof.
2. Take the pre-deploy baseline: per-row fingerprints (§18).
3. Run the preflight (§17.1).
4. Apply the server package.
5. Deploy the candidate client (SSEP). Create the 2027 FSA category and record the rollout manifest.
6. Simulate at least one legitimate post-deploy 2026 close before week 30 (for example weeks 28 and 29), including a patch to a pre-existing commitment row.
7. Close week 30 (2026).
8. Run the 2027 initialization transaction. Its PASS is recorded with its manifest.
9. **Checkpoint C:** per-row fingerprints of the candidate state.
10. **Rollback rehearsal, before any week-31 close:**
    - the guard reports eligible;
    - run the rollback;
    - RB-1 to RB-4 pass;
    - the post-deploy week 28-30 history is preserved and enumerated;
    - the FSA row is removed.
11. **Re-establish the candidate state.** Re-apply the rollout (server package, client, FSA row) and re-run initialization; this also rehearses a re-deploy after rollback. Prove equivalence with checkpoint C. [B] The generated columns excluded from that comparison, which are listed.
12. Close week 31 (2027), including the cross-year commitment; the first-close re-verification passes.
13. Close week 32.
14. Run the remaining T-SRV and T-RB cases, including T-RB-1 after the week-31 close. Cases that need a state no longer present (for example T-SRV-14's injected failure) run on a separate isolated fixture target [B].
15. Confirm every pre-deploy baseline row is byte-identical, or is a simulated post-deploy write enumerated in step 10's evidence.
16. If the shared staging project was used, re-apply and verify the AU-11 state (step 1).

[F] **Ordering assertion:** steps 10 and 11 precede step 12. The harness refuses step 12 until step 11's equivalence proof is recorded (T-RB-5).

[B] Simulation values, fixture data, harness tooling.

## 17. Production rollout sequence

[F] All steps are owner-gated.

**Deploy window (Dec 12-19, 2026):**
1. Fresh encrypted backup plus posture file; pre-deploy baseline (per-row fingerprints, §18).
2. Preflight (§17.1). Any failure stops the deploy.
3. Server package.
4. Frozen client (hash recorded).
5. Create `health_fitness.flexible_spending_2027` and record it in the **rollout manifest**. No other data mutation is made in the deploy window; category label changes are not part of the rollout (§11).
6. **Stale-client control**, then deploy acceptance (§19.1). After the accepted client is live and before normal household use resumes:
   - Adam and Wendy each reload or replace every open Financial OS browser tab, and confirm the build stamp shown in the navigation footer ("Last build") matches the accepted client;
   - the `model_week_overrides` inspection (§5.5) is re-run after both confirmations;
   - any row with week ≥ `firstWeekOfPlan(2027)` fails closed under the owner-disposition rule of §5.5;
   - both confirmations and the inspection result, with times, are recorded in the deployment evidence.

   This is an **operational** stale-client control. It is not a technical guarantee against someone deliberately keeping and using an obsolete client; rollback condition 4d (§18) remains the backstop.

**Boundary:**
7. **Week-30 close** (2026 plan; about Jan 2-3, 2027).
8. **2027 initialization** in one transaction (§7.4): registry rows, opening snapshots, 2026 dispositions, manifest with recorded PASS. Between the week-30 and week-31 closes. A FAIL leaves no residue; correct the inputs and re-run.
9. **Pre-first-close check:**
   - the owner confirms the recorded PASS;
   - the §5.5 `model_week_overrides` inspection is repeated for every row with week ≥ `firstWeekOfPlan(2027)`:
     - a custom row at or below the last authored week fails closed for owner disposition, since only a pre-deploy client can write one;
     - every non-custom row is listed with its evidence. That evidence is: its timestamp compared with the §17 step 6 confirmations, which is supporting evidence only because the timestamp is client-supplied; and whether its events follow the legacy frozen week-31 row or the `WD_2027` row;
     - the household confirms each listed row as its own 2027 planning input; any row not so confirmed fails closed for owner disposition;
   - the inspection result is recorded in the first-close evidence;
   - if any final 2026 value changed after initialization, reverse and re-initialize (§7.4) before step 10.
10. **Week-31 close:** the first 2027 close (about Jan 9-10, 2027). The closeout wrapper re-verifies O5 (§10).
11. Boundary acceptance (§19.2).

### 17.1 Preflight

[F] Run in staging (§16 step 3) and production (step 2). Read-only. Any failure stops the deploy, and the evidence goes to the owner. Nothing is repaired automatically.
- E-1 to E-5 (§17.2) re-checked against the live database.
- P-Y1 and P-Y2 hold on every existing row.
- Override inspection (§5.5): no `model_week_overrides` row with `week_num ≥ firstWeekOfPlan(2027)`.
- Catalog assertion (T-PRE-1): the five unchanged week-keyed tables keep integer `week_num` and have no week upper-bound check.
- The complete-week set is contiguous from week 6 (§10).
- No goal snapshot-tracked in 2026 has registry status `archived` (§7.5).
- Grants as recorded in E-4.

### 17.2 Production evidence record

These are read-only observations of 2026-10-07. They are **not permanent assumptions**: every item can change, so each is re-checked by the preflight (§17.1). A mismatch fails closed.

| ID | Observation (production, read-only, 2026-10-07) |
|---|---|
| E-1 | `model_week_overrides`: 0 rows with week ≥ 31; 0 custom rows; maximum week 30 |
| E-2 | `goal_funding_snapshots`: exactly 9 `opening_anchor` rows, all at (plan 2026, week 5); P-Y1 and P-Y2: 0 violations |
| E-3 | The five unchanged week-keyed tables (`weekly_reconciliations`, `weekly_tasks`, `weekly_notes`, `model_week_overrides`, `custom_tasks`) use integer `week_num`; none has a week upper-bound check |
| E-4 | No client EXECUTE on `repair_commitments_for_week`, `save_goal_funding_snapshots` or `save_reconciliation_with_commitments`. Authenticated EXECUTE only on `save_weekly_closeout_with_snapshots` and `correct_goal_funding_snapshot`. Signed-in users have SELECT only on `goal_funding_snapshots` and `cash_commitments` |
| E-5 | 0 `cash_commitments` rows with any week ≥ 31; 0 snapshots with week ≥ 31; 0 `weekly_reconciliations` rows with week ≥ 31 |

## 18. Rollback contract

[F] **Governing invariant (owner, 2026-10-07):** rollback removes rollover-specific state and restores the pre-rollover implementation while preserving legitimate, authorized household operating history written after deployment.

[F] **Definitions:**
- **Pre-deploy baseline:** a per-row fingerprint (table, primary key, content hash) of every row in the fingerprinted tables, taken at §17 step 1.
- **Rollout manifest:** every data mutation made by the rollout. It contains exactly one row: the `categories` row `health_fitness.flexible_spending_2027`, with its full content. Server DDL and function bodies belong to the server package, not the manifest.
- **Initialization manifest:** §7.4.
- **Post-deploy household history:** every row inserted, updated or deleted after the baseline by ordinary authorized operation (closeouts, Register entry, Edit-Week, tasks and notes). It is not in either manifest.

[F] **Guard conditions.** The guard aborts if any condition holds. Nothing is changed when it aborts.

*Point of no simple return (2027 operating history exists):*
1. any `weekly_reconciliations` row with week ≥ 31;
2. any `cash_commitments` row with `model_year ≠ 2026` or any week value ≥ 31;
3. any `goal_funding_snapshots` row with week ≥ 31.

*Unexpected state.* The owner disposes of these with evidence before any rollback. Nothing is deleted or transformed automatically.

- **4a** `goal_registry`:
  - a row whose ID is in neither the baseline nor the initialization manifest; or
  - a manifest status change whose current value differs from the manifest's recorded post-initialization value.
- **4b** `goal_funding_snapshots`:
  - a row with `model_year ≥ 2027`, or with `source = 'opening_anchor'`, that is in neither the baseline nor the initialization manifest; or
  - a manifest row whose content differs from its manifest record.
- **4c** `categories`:
  - the rollout-manifest FSA row is referenced by any other row; or
  - its content differs from its manifest record.

  Other category rows added after deploy are post-deploy household history: they are preserved and enumerated, and they do not block.
- **4d** `model_week_overrides`: any row with week ≥ 31 that is not in the baseline. These are financial model inputs (§5.5).
- **4e** the rollout manifest is missing or incomplete. Before initialization there is no initialization manifest and none is required. After an initialization, a missing or incomplete initialization manifest shows up as rows in no manifest (4a, 4b).

In practice the point of no simple return is the **first 2027 close (week 31)**. Week 31 is named explicitly because the prior server functions would accept it and wrongly close it as a 2026 week.

[F] **Machine-checked rollback.** The rollback package runs as one transaction:
- **(a) preflight:** evaluates conditions 1-4 and **aborts** if any is true; records the pre-rollback per-row fingerprint;
- **(b) data reversal:** if initialization has run, deletes exactly the initialization manifest's rows (opening snapshots, then 2027 registry rows) and restores the manifest's recorded prior 2026 statuses; deletes the rollout manifest's FSA row; asserts counts;
- **(c) server restore:** restores the prior function bodies (stored with the server package) and the prior checks. Postgres validation of the restored checks is a second guard;
- **(d) postflight.** Each must hold, or the whole rollback transaction rolls back and the failure is reported:
  - **RB-1 write set:** the pre-rollback and post-rollback fingerprints differ in exactly the manifest-reversal rows. No other row is inserted, updated or deleted by rollback;
  - **RB-2 baseline (owner confirmed 2026-10-07):** every pre-deploy baseline row either equals its baseline fingerprint or differs only through post-deploy household history listed under RB-3. No baseline row differs through a rollout or initialization mutation; those were all reversed;
  - **RB-3 enumeration:** the rollback evidence lists every post-deploy household history row (table, key, week, plan year, kind of change). Each is preserved. Weeks 28-30 closed after deploy appear here; they are never discarded to reproduce an old fingerprint;
  - **RB-4 compatibility:** the restored checks validate against every preserved row, and the complete-week set is contiguous from week 6.

Additional rules:
- The client is reverted only together with the server step. Household OS use is paused across the whole server-and-client rollback swap and resumes only after both are reverted and Adam and Wendy have reloaded their open tabs, so no normal use happens with mixed versions. This is an operational step; no infrastructure is added.
- Non-financial rows at week ≥ 31 (`weekly_tasks`, `weekly_notes`, `custom_tasks`) are listed by the preflight and preserved; they do not block. `model_week_overrides` are financial model inputs and fall under condition 4d.

[F] **After the point of no simple return:**
- **Forward-fix** within the same D-11 scope (preferred).
- Or restore the pre-deploy encrypted backup (last resort). It discards every write after deploy, which must then be replayed from the evidence record.
- The backup, posture file, fingerprints and manifests are retained until rollover acceptance.

## 19. Acceptance criteria

**19.1 Deploy acceptance [F]:**
- Every pre-deploy baseline row unchanged except through enumerated post-deploy household history (for example the acceptance close below); the only rollout data mutation is the rollout-manifest FSA row.
- Week labels correct (e.g. the deploy week shows 2026 Wk 50 or 51).
- Schedule visible through 2027 Wk 52.
- No absolute week numbers in household text.
- The current 2026 week closes normally with the 2026 goal set.
- OWNER HOLD constant unchanged.
- The stale-client control (§17 step 6) is recorded: both household confirmations of the accepted build, followed by an override inspection finding no row with week ≥ 31. Deploy acceptance cannot be recorded without it.
- The 2027 FSA category exists and is recorded in the rollout manifest; with it present, the rollback guard reports eligible.

**19.2 Boundary acceptance [F]:**
- Week 30 closed as 2026.
- Initialization PASS recorded; manifest complete; O5 satisfied.
- The pre-first-close override inspection (§17 step 9) is recorded, with every row confirmed or disposed of.
- Week 31 closed as 2027 with the 2027 set; the first-close re-verification passed.
- Any cross-year commitment resolved as one row with its origin unchanged.
- Goals view shows the 2027 plan only, with the 2026 plan in its read-only historical group (§7.6); no pre-boundary line remains on any 2027 week (C25).
- No INCOMPLETE state except as specified.

**19.3 Rollover acceptance [F]:** 19.1 and 19.2 met. Recording rollover acceptance in `CODEX_STATUS.md` is a separate owner-authorized step. Gate R acceptance weeks **exclude week 31 (2027 Wk 1)**.

## 20. Out of scope

[F] Not part of this rollover:
- Gate R and its controls (statement check, certified-period guard and correction path, the destructive-privilege fix);
- Gate F (dated walk, parity, capacity, allocation, the weekly operating allowance, P3 runtime conformance, the empty baseline waterfall R-f);
- P3c-2 and its evidence fields; runtime schedule generation (R-d);
- reimbursement forecasting; tax estimation; any 2027 commission-tax policy (the 2026 pool and attestation end with the 2026 plan);
- any OWNER HOLD change or goal funding;
- 2027 401(k) tracking;
- the existing `getCurrentWeek` timezone defect;
- baseline-E refresh; October label debt; What-If rework, including 2027 What-If goal totals;
- the approved Jabian and Vio category label changes (a separate owner-authorized cleanup);
- 2027 auto-reminders;
- extending any 2026-identifier special case (§9.1) to 2027 identifiers;
- changing the pre-boundary forward view itself (§7.5); only its disclosure (C25) is in scope;
- the full read-only plan-history navigation (H-1) and the reconciled-period write guards (GR-1); both are §23 follow-ons;
- any change to the 40% tax-reserve logic (follow-on F-1); any tax estimation or 2027 tax policy;
- a cross-OS view-year framework, historical versioning or a generic warning framework;
- a mid-plan goal-addition workflow (§7.6); a `goal_registry` history table;
- deriving base pay from schedule events or any new income model (C26);
- performance work on the engine: `runModel` simulates from the 2026 epoch over the whole effective schedule, which grows each year. This is a watch item only; no optimization or engine extraction in rollover;
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
| 9 | 2027 goals: identifier, name, target, priority, due date, carried-from (if any), and a stated reason wherever a carried opening value is not to equal the final 2026 value | Registry, initialization, the private real-input dry run (§15). Not the committed golden, which uses synthetic goals |
| 10 | Disposition of each 2026 snapshot-tracked goal: carry (successor) or close (final status `executed` or `archived`; a stated reason when archiving a non-zero balance) | Initialization (O5) |
| 11 | Reminders continuing in 2027 (monthly and quarterly transfers, reimbursement review) | Recorded for the household's own task list; not consumed by rollover (§9.1 item 10; Q2) |
| 12 | Confirmation that no 2027 goal is holding-type or depends on a 2026-identifier special case (§9.1) | §7.5, §9.1 |
| 13 | Confirmation that the operating floor is unchanged | Unchanged constant |

## 22. Future-rollover contract (2028 onward)

[F] A normal future rollover changes **no server function, schema, RLS, grant or identity rule**. Plan years, household weeks, opening positions, eligibility and contiguity are all derived, and 53-week years arise from the calendar (2028). It is not effortless; the recurring work each year is:
1. Supply the next plan's inputs [I].
2. Author and generate the next schedule block (e.g. `WD_2028`, absolute weeks from `firstWeekOfPlan(2028)` = 83) with the freeze-time regeneration check and freeze manifest (§5.2).
3. Append it to the runtime composition. The block is embedded in the client as data and added to the composition's ordered list of plan blocks. This is a client-file change under the schedule-data and script-body-growth exceptions (§12), authorized by the owner for that year's block.
4. Preserve every existing golden unmodified, each run on its own plan's frozen composition through that plan's final week (§14 parametric harness), and capture an owner-approved golden for the new plan with a synthetic goal fixture (R6, §15).
5. Create that year's FSA category (e.g. `health_fitness.flexible_spending_2028`) as the rollout-manifest row.
6. Author that plan year's preflight and rollback packages (their conditions name that year's boundary weeks and plan year), then run the preflight (§17.1), including the override inspection for weeks ≥ `firstWeekOfPlan(Y)`.
7. Initialize the plan between the prior plan's final close and the new plan's first close (§7.4).
8. Disposition the year-pinned controls: inventory every year-pinned item and household constant (the widened §9.1 search) and record its behavior for the new plan. Known today: the commission-tax pool and attestation (ended with 2026; nothing for later years unless the owner adopts a policy outside rollover), the auto-reminder lists (2026 only; Q2), and the 2026 base-pay literals (C26).
9. Add the new plan's boundary tests. General tests are written against derived bounds so they need no annual edit.

[F] **Truthfulness check.** Steps 2-5 and 9 change committed client data, fixtures and tests every year. That is authored schedule data, not code architecture. Under the current design, the only behavior that would need an annual code edit is the auto-reminder lists (§9.1 item 10), and this specification does not add 2027 reminders (Q2). The 2026-identifier special cases (§9.1) are not extended, so they need no annual edit. Goals plan scoping, the historical group (§7.6), the plan-aware text (C17, years derived) and the C20, C21, C25, C26 and C27 behaviors derive from the plan year, so each closed plan joins the historical group with no annual edit and no literal-year change. Prior goldens are not mutated (§14).

**Recurring operational obligation:** author the next plan before the S5 warning window, i.e. at least 13 weeks before the current plan's final week (for 2027, by early October 2027).

A future change to this contract would be an architecture question, not a routine rollover.

## 23. Implementation sequence and owner gates

| Gate | Content | Owner authorization |
|---|---|---|
| 0 | Freeze this specification; independent review | Freeze decision |
| 1 | Repo: RED tests (after the widened §9.1 search and the §13 inventory search are repeated); anchor-note grammar fixed in the initialization script and wrapper before SQL is authored; authoring tool, issuer-rules source, CI checks and freeze manifest (with the freeze-time regeneration check run privately); client changes; 2026 golden proof; 2027 golden dry run on the synthetic goal fixture, then owner approval, then capture; private real-input dry run; protected-function review and re-pins | Per §12, plus golden approval |
| 2 | Staging rehearsal (§16), including the rollback rehearsal before the week-31 close | Staging authorization |
| 3 | Production deploy (§17 steps 1-6) | Production DDL and deploy |
| 4 | Boundary: week-30 close, 2027 initialization with recorded PASS, pre-first-close check, week-31 close (§17 steps 7-11) | Initialization authorization |
| 5 | Rollover acceptance recorded | Status update |

**Follow-on items created by this specification (not implemented in rollover) [F]:**

| ID | Item | Workstream and deadline |
|---|---|---|
| H-1 | **Read-only plan history.** While operating in a later year, Adam and Wendy can deliberately navigate to useful earlier-year financial truth without changing the current operating year. Built on persisted or proven-reconstructable truth only. A value that cannot be shown truthfully is UNAVAILABLE, never recomputed with current assumptions. The §7.6 historical group is the rollover bridge and does not need the H-1 mechanism. Evidence to address: historical Budget targets can be erased by later rule archival (`is_active=false`) or rewritten by edits made from a past month; historical planned events can be changed by later edits to mutable overrides; closed-plan projections that cannot be reconstructed truthfully are UNAVAILABLE, never recomputed with current assumptions | Post-rollover, Gate R workstream. **Must be complete before Gate R is declared complete** |
| GR-1 | **Reconciled-period write guard (Gate R prerequisite).** Today Edit Week, Notes and Scenario Commit can write against reconciled historical weeks. Required end state: ordinary historical browsing is read-only; a reconciled or certified period cannot be changed through those ordinary paths; explicit authorized correction and reopen remain a separate controlled workflow | Gate R prerequisite inventory (certified-period write guard and historical browsing) |
| F-1 | **Stale 40% tax-reserve behavior.** Resolve every surviving 40% path that conflicts with current household policy, so none can enter Gate F authority: (1) the allocation engine's Variable Income 40% tax-reserve step; (2) the Edit-Week "Tax?" split; (3) the resulting commission-tax computation in `saveWeekEdits` and the commission-tax transfers and actions in `runModel`; (4) the resulting actionable and settlement rows in week detail; (5) Scenario Builder commit and result wording that states 40%; (6) Assumptions and other documentation text that states the 40% rule. F-1 chooses remove, keep as an explicit user option, or relabel for each path. Rollover changes none of this behavior. No tax estimation and no invented 2027 tax policy | Bounded item, **before Gate F** |

## 24. Traceability

| Requirement / ruling | Section | Tests |
|---|---|---|
| Design B (G2); absolute week; household week; plan year | §3, §4 | T-ID-1..4 |
| P2 (G3) | §3, §4, §6 | T-ID-2, T-GL-1, T-GL-3 |
| Date derivation from (week, `d`); label due-date year | §3, §5.2, §9 C1/C7 | T-ID-6, T-CC-1, T-SCH-5a |
| Design A and C rejected (G4) | §3, §10 | T-SRV-4, T-SRV-8 |
| D10 (b) (G5) | §9 (`runModel` unchanged) | T-SCH-3, §14 |
| D-11 narrow (G6) | §10 | T-SRV-1..15 |
| Freeze exceptions (G7) | §12 | RED tests per change |
| Week 31 Option C (G8) | §5.1, §6 S2, F1-F4 | T-SCH-2, T-SCH-3, T-SCH-4 |
| Overrides on the effective schedule | §5.5, §6, §17.1, §18 (4d) | T-EDIT-3, T-RB-1 |
| Category rulings and principle (G9); labels outside rollout | §11, §17 | Verification record, T-RB-4 |
| R1 structured dates | §3, §5.2 | T-SCH-5a, T-ID-6 |
| R2 / R-h no cliff (capability) | §5.3, §5.4, §22 | T-ID-5, T-SCH-1 |
| R3 issuer-rule authoring | §5.2 | T-SCH-5a, T-SCH-5c |
| R4 no P3c-2 fields | §5.2 | T-SCH-5a |
| R5 committed-cash walk not made harder | §5.2 (dated events), §3 (absolute weeks) | T-SCH-5a |
| R6 golden approval | §14, §15 | Golden review |
| R7 no P3c-2 in rollover | §20 | n/a |
| Owner-confirmed 2027 base pay | §5.2, §21 | T-SCH-5d, owner approval |
| Registry fail closed; no code disbursements | §5.2, §7.5 | T-GL-5 |
| Private inputs; verification contract; `WD_2027` change control; hash-check limit | §5.2 | T-SCH-5b, T-SCH-5d, T-SCH-6 |
| Synthetic committed golden fixture; private real-input dry run | §15 | Golden review |
| `openingWeekOfPlan` and the 2026 legacy exception | §3, §6 P-Y2, §7.1, §10 | T-ID-2, T-SRV-8 |
| Eligibility invariant O1; control data O2/O3 | §7.1, §7.2 | T-GL-1, T-GL-2, T-SRV-10, T-SRV-12, T-SRV-13 |
| Initialization window O4; disposition O5; atomic initialization; final-status set; first-close re-verification | §7.4, §10 | T-GL-2, T-SRV-2, T-SRV-14, staging steps 8 and 12 |
| Archived contradiction (client and server) | §7.5, §10 | T-GL-7, T-SRV-15 |
| Pre-boundary forward view documented and disclosed | §7.5, C25 | T-TR-3 |
| Goals plan-year scoping; historical group | §7.6, C19, C17, C22 | T-GL-8, T-GL-9, T-GL-10, T-GL-11 |
| Next Dollar and allocation-engine disclosures; 40% follow-on | C23, C24, §23 | T-TR-4, T-TR-5 |
| H-1, GR-1, F-1 follow-ons (F-1 covers every 40% path) | §23 | n/a (not in rollover) |
| Cash Flow Mechanics base pay; remaining year-pinned surfaces | §9.1 items 14-19, C26, C27 | T-TR-6, T-TR-7 |
| Complete-or-fail-closed snapshot and commitment loads | C11 | T-GL-9, T-SNAP-1 |
| Plan membership, UNASSIGNED rows, prior-plan registry rule | §7.6 | T-GL-8, T-GL-9 |
| Anchor-note grammar; first-close IP-2 form | §7.4 | T-SRV-14 |
| Second override inspection before the first close | §17 step 9, §19.2 | First-close evidence |
| Rollback household-use pause | §18 | Rollback runbook |
| Prior golden isolation | §14, §22 | Golden harness |
| Year-pinned code inventory | §9.1, C19 | Gate 1 search, T-GL-8, golden effect record |
| Proven global contiguity | §10 | T-SRV-3 |
| Cross-year commitments | §8 | T-CC-4, T-CC-5, T-SRV-6, T-SRV-7 |
| 2026 history preserved | §6, §14, §16, §18 | T-CC-1, T-SCH-3, T-RB-2, T-RB-3 |
| Current week never silently capped; INCOMPLETE; operational warning | §5.3 | T-ID-5 |
| Preflight; production evidence E-1..E-5 | §17.1, §17.2 | T-PRE-1, preflight record |
| Rollback invariant, manifests, guard and postflight | §18 | T-RB-1..4 |
| Staging isolation and rehearsal ordering | §16 | T-RB-5 |
| Commission-tax pool pinned to 2026 and ended | §9 C16 | T-CT-1 |
| OWNER HOLD unchanged (G11) | §2, §19.1 | Deploy acceptance |
| No silent material limitation (G12) | §1, §2, §9 C20/C21 | T-TR-1, T-TR-2 |
| Operational stale-client control | §17 step 6, §19.1 | Deployment evidence |
| Late prior-year corrections; status policy | §7.2, §7.4 | T-SRV-14 |
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
| v1: rollback postflight requiring all 2026 rows to equal the pre-deploy fingerprints | §18 governing invariant and RB-1 to RB-4 |
| v1: "any 2027-plan data not listed in the initialization manifest" as a guard condition | §18 conditions 4a-4e |
| v1: optional category label changes in the deploy window | Separate owner-authorized cleanup (§11) |
| v1: rollback rehearsal after the week-31 and week-32 closes | §16 ordering (rehearsal before week 31) |
| v1: overrides at week ≥ 31 treated as non-financial residue | §5.5 fail-closed preflight; §18 condition 4d |
| v1: next closeable week = 1 + the latest complete week | Proven contiguity (§10) |
| v1: initialization as a procedure without single-transaction atomicity; "opening snapshots exist" as the week-31 condition | §7.4 one transaction with postflight and recorded PASS; first-close re-verification |
| v1: a pinned golden fixture carrying real 2027 goals | Synthetic committed fixture plus private real-input evidence (§15) |
| v1: due year resolved by "January means next year" | Nearest-date rule (§3) |
| Every anchorless registry row belongs to plan 2026 | Legacy population by creation time; later anchorless rows UNASSIGNED (§7.6) |
| Anchor-note format as a builder choice | Frozen anchor-note grammar (§7.4) |
| IP-2 re-checked at the first close as "inserted by this run" | First-close IP-2 form derived from the database only (§7.4) |
| F-1 limited to the allocation-engine 40% step | F-1 inventory of every 40% path (§23) |

## 26. Open specification questions

- **Q1 (placement of owner input values): CLOSED** by owner direction (2026-10-07). Private inputs stay outside the repository; the verification contract is §5.2.

Q2-Q13 were closed by the owner on 2026-10-07:
- **Q2 (2027 auto-reminders): CLOSED.** Limitation accepted; no 2027 reminder generation in rollover. The action list could reasonably be read as complete, so the smallest local disclosure applies (C21).
- **Q3 (What-If goal totals in 2027): CLOSED.** Limitation accepted, not silent: disclosed at the affected result (C20, T-TR-1).
- **Q4 (C19): CLOSED.** Accepted; reuses the O1-derived current-plan set. Not a Goals redesign.
- **Q5 (baseline rows changed by legitimate post-deploy writes): CLOSED.** Confirmed as written in §18 RB-1 to RB-3.
- **Q6 (stale pre-deploy client sessions): CLOSED.** Tightened with the operational stale-client control (§17 step 6, §19.1).
- **Q7 (first-close re-verification placement): CLOSED.** Accepted as bounded D-11 work; not broadened into Gate R.
- **Q8 (archived predecessors): CLOSED.** Owner status policy recorded in §7.4; fail-closed consequence accepted.
- **Q9 (2026 corrections after the first 2027 close): CLOSED.** Recorded in §7.2; no synthetic continuity adjustment; Gate R scope unchanged.

- **Q10 (Goals plan-year scoping): CLOSED, approved.** §7.6 and C19: plan-scoped working lists, totals and projections, plus the read-only historical group. Bounded; not a Goals redesign.
- **Q11 (pre-boundary disclosure): CLOSED, approved.** C25 and T-TR-3; shown only while the condition exists. No `runModel`, Gate F or forward-model change.
- **Q12 (further silent limitations): CLOSED, approved with modification.**
  - the Goals header is fixed (C17);
  - the Decision Queue is no longer presented as current (C22);
  - Next Dollar (C23) and the allocation engine (C24) get local caveats; the protected calculation is unchanged;
  - the 40% tax-reserve logic is unchanged, labelled, and tracked as F-1 before Gate F.
- **Q13 (multi-year navigation): CLOSED, Option 2 with timing modification.** Rollover preserves the data. H-1 is a post-rollover Gate R item, complete before Gate R is declared complete. The reconciled-period write guards are recorded as Gate R prerequisite GR-1. Neither is implemented in rollover.

No open question remains.

Everything else is frozen [F], an owner input [I], or a builder choice [B].
