# Step 8 — Baseline E: Actual Checking Capacity Synthesis & Wendy-IRA Safety Test

## DRAFT / NOT AUTHORIZED / NOT EXECUTABLE (rev-8)

**Status:** DESIGN + INPUT-ASSEMBLY ONLY. This document is a specification. It is **not** an executable
artifact, it is **not** frozen, and it does **not** authorize any calculation, transfer, or Wendy-IRA
recommendation. No capacity number appears anywhere in this file and none may be derived from it until
Baseline E is separately built-to-freeze, Fable-re-reviewed, owner-approved, and owner-executed.

**rev-8 is a micro-revision: it adds one numbered test (§17: 79) directly proving disposition G's *accepting*
branch (a valid explicit one-transaction→multiple-events allocation) with a fail-closed twin, corrects the
§17 A–H coverage map so G points to test 79 (no longer implied by 69/70/71), and updates the enumerated test
count 78→79. No architecture change; no rev-4…rev-7 control reopened.**

**rev-7 (retained for lineage) was the final design-cleanup pass applying the independent Fable Mode-1 closure confirmation of rev-6
(verdict: APPROVE WITH REQUIRED CHANGES; NF-1 mechanism confirmed FULLY RESOLVED, no regression). It is a
narrowly-scoped correction — the confirmed two-direction reconciliation model and the global no-double-count
invariant are preserved unchanged. rev-7 makes only:** (1) the §5c **candidate-generation** clarification
(recall-oriented candidate generation independent of exact-amount equality; identity-strong amount/direction
conflict routes to disposition D, never silently to E); (2) two new numbered tests for §5c **dispositions D
and E** (§17: 76, 77); (3) small non-blocking consistency fixes — name §5c exclusion classes in §1d;
frontier-relative horizon wording (`as_of_model_week → coverage_horizon_end`) replacing hard-coded "weeks
8→31"; a **capture-week = `as_of_model_week`** execution precondition (§16, test 78); and a
`confirmed_matches[]` allocation/split manifest contract (§5c) sufficient for partial splits and explicit
multi-event/multi-transaction allocations.

**rev-6 (retained for lineage) closed:** (NF-1) the **cross-boundary early-posted inflow/outflow** residual
false-safe — the CD-1 seam mechanism displaced one week across the capture-week boundary — by adding a
**reverse bank-to-schedule reconciliation** direction (§5c) and the **global no-double-count invariant**
(§5/§5c), *complementing* (never replacing) the forward capture-week event seam (§5b/R13); plus four new
numbered tests (§17: cross-boundary early-posted inflow, cross-boundary early-posted outflow, seam
contradictory-evidence FAIL-STOP, budget-rule contradictory-evidence FAIL-STOP) and the bank↔schedule
match-multiplicity/partial/ambiguous/digest-mutation cases.

**rev-5 (retained for lineage) closed:** (CD-1) the capture-week seam universe false-safe (§5b/R13/§17);
(FS-2) the §1c/R12 budget-rule override-week wording conflict (§1c/§6-R12/§17); (MR-1) the §9 zero-maximum
self-verification exception (§9/§17); plus the two before-freeze clarifications — (MR-2) the §1b independent
RLS visibility-proof mechanism and (MR-3) the §8 JSON-number canonicalization requirement — and the two
advisory items (citation corrections §0; duplicate-week load nuance §0/§1a).

**rev-4 (superseded framing, retained for lineage) resolved the seven BLOCKING-BEFORE-SCRIPT-CONSTRUCTION
findings of the Fable Mode-1 re-review of rev-3.** Headline rev-4 changes (all preserved in rev-5):
1. **Schedule authority is a pure extraction adapter (§1a):** pinned `WD` source + a read-only production
   `model_week_overrides` snapshot + a verified pure merge adapter → the effective-schedule snapshot.
   In-app `reconEffectiveWD()` output is a **differential-test oracle**, not the canonical dependency.
2. **`reconEffectiveWD()` semantics corrected to the actual code (§0/§1a):** `events_json` **replaces**
   literal events **only when present and non-empty** (else falls back to the literal set); `ct`, `ca`,
   `dates` override **independently**; `is_custom` rows **append** (they are weeks `n>31`); duplicate
   `week_num` is detectable and never silently collapsed.
3. **Budget Rules are a first-class cash channel (§1c):** a dedicated read-only `budget_rules` extraction —
   never sourced from `reconEffectiveWD()` — with anti-duplication, drift, completeness, parity, and tests.
4. **`ct`/`ca` vs carried set-asides separated (§3b):** explicit effective `ct`/`ca` are preserved in the
   snapshot; a **mandatory carried-set-aside adjudication ledger** investigates every engine-origin set-aside
   scheduled on/before the as-of frontier that might remain outstanding.
5. **Custom-week / duplicate-week rules (§13):** no custom row silently dropped; out-of-horizon customs are
   coverage-evaluated; duplicate `week_num` triggers explicit adjudication (unexplained ⇒ FAIL-STOP).
6. **Stable content-bound event identities (§7):** order/index/ordinal-only IDs prohibited; digest-bound;
   digest change invalidates a prior adjudication to HOLD.
7. **Exact decimal-string → integer-cents contract (§8):** no float×100; a strict canonical-decimal parser.
8. **Maximum-safe-transfer algorithm fixed (§9):** synthetic transfer-position checkpoint; global-trough
   gate; mandatory Projection-B self-verification at the computed maximum and at maximum + 1¢.
9. **State-drift universe extended (§11):** adds `budget_rules`, `custom_tasks`, Goal-Ledger identity, and
   the parity-harness `actionOverrides` store to the enumerated surfaces.
10. **Closed parity-difference catalogue (§1e):** differences may no longer be merely "explained" in prose;
    each must map to a pre-approved non-cash class or FAIL-STOP.
11. **Capacity-only execution mode removed (§2 D):** a final run always concerns a supplied proposed transfer.
12. **Operating-floor confirmation is fail-closed (§2 CONTROL):** unconfirmed floor ⇒ HOLD, no silent default.

- Repository HEAD at drafting: `e169516ca92f50b821a3bfc428d471bbd3766576`
- `index.html` BUILD_TS at drafting: `2026-07-23T00:12:07` (`index.html:888`)
- Production project: `usayoldrawwmjsmretin`
- Predecessor: Baseline D frozen `6de0f8e554cb1a961f362229fa61d27ffa102a2d8240e4604aaeb1de75d8b893`,
  executed read-only 2026-07-28, D0–D9 PASS, `D_HANDOFF_PASS`, `as_of_model_week=8`,
  `as_of_is_reconciled=false`, authoritative DB reserved-obligation total **$0.00**.
- Operational HOLD remains active. No transfer authorized.

---

## 0. Grounding — where the authoritative forward schedule actually lives

The forward checking schedule is **not** in the production database and **not** fully in the hardcoded `WD`
literal either. Two code facts define the authority:

**(i) Effective-schedule transform — the actual `reconEffectiveWD()` semantics (`index.html:2949-2965`,
verbatim-verified):**
- For a week with **no** override row: the literal `WD` tuple is used unchanged.
- For a week **with** an override row `ov`:
  - **events:** `effEvs = (ov.events_json && ov.events_json.length) ? ov.events_json : evs` — the override
    event set **replaces** the literal events **only when `events_json` is present and non-empty**; an
    absent or empty `events_json` **falls back to the literal event set**.
  - **dates:** `ov.dates || dates` — override dates only when truthy, else literal dates.
  - **ct:** `ov.ct != null ? ov.ct : ct` — **independent** override; **ca:** `ov.ca != null ? ov.ca : ca` —
    **independent** override. (ct/ca are NOT tied to the events replacement.)
  - `calNote` is forced to the literal note.
- **Custom weeks are appended, not merged:** every `overrideData` row with `is_custom` is sorted by
  `week_num` and **pushed as an additional effective week** (`effEvs = ov.events_json || []`,
  `ct = ov.ct || 0`, `ca = ov.ca || 0`) — the operative append/sort is `index.html:2960-2963`. Custom weeks
  are created as `is_custom: isNew || (n>31)` and numbered `max(custom)+1` else 32 (`index.html:4735-4739`)
  — i.e. **weeks 32+**. (The in-app Assumptions-panel prose at `index.html:7370` merely *documents* this;
  it is not the operative code.) **Nothing in the transform de-duplicates `week_num`.**

> **Duplicate-`week_num` load nuance (advisory clarity, no control weakened):** the application load path
> keys `overrideData` by `week_num` (`overrideData[row.week_num]=row`, `index.html:9894`), so two DB rows
> sharing a `week_num` **collapse at load** before `reconEffectiveWD()` ever runs; `reconEffectiveWD()`
> itself performs **no** de-duplication, and a custom row can still produce a duplicate *effective* week
> number. The standalone pure adapter (§1a) reads and evaluates the **raw** override rows (it must not
> replicate the load-time collapse); any divergence between the adapter and the in-app oracle caused by that
> collapse is a **fail-closed parity failure**, and an unexplained duplicate row remains **FAIL-STOP** (§13).
> This nuance does not relax the adapter's no-silent-collapse requirement.

> **Correction of prior revs:** rev-2/rev-3 described this as unconditional "entire-week replacement." That
> is wrong. The replacement is **conditional (non-empty events only)** and `ct`/`ca`/`dates` are
> **independent**. Any adapter or test built on the old description would silently drop literal obligations
> on an empty-`events_json` override — a false-safe. §1a and test set §17 pin the **actual** semantics.

**(ii) Budget Rules are a separate cash channel the transform does not see.** `runModel` applies
production `budget_rules` deltas directly to checking: `chk = r(chk + applyBudgetRulesForWeek(num, …))`
(`index.html:3022`; loaded from `/rest/v1/budget_rules?active=eq.true`, `index.html:9863`), and this is
**bypassed for weeks that carry an override** (`if(overrideData[num]){…bypassed…} else {…apply…}`,
`index.html:3017-3023`). `reconEffectiveWD()` "Reads WD + overrideData only" and **never** supplies budget
rules. Any schedule built from the effective transform alone omits this channel — a false-safe. §1c makes
it first-class.

**The proven override case (motivating §1a):** the Week-11 AMEX Gold obligation was updated to the actual
statement liability via the canonical Edit-Week path on 2026-07-25 (AU-3; `CODEX_STATUS.md` 2026-07-25b —
actual **$11,501.12 due 2026-08-18**, replacing a `~$5,500` raw-`WD` estimate; `index.html:920` still
carries the estimate). A schedule transcribed from the literal alone understates that week by ~$6,001.
Overrides are where corrected reality lives.

| Fact | Value | Source |
|---|---|---|
| Model epoch (week 1 start) | 2026-06-07 | `index.html:3441` `getCurrentWeek()` |
| Model horizon | 31 model weeks (ends "Jan 3-9 2027"); customs are weeks 32+ | `WD` `index.html:909-941`; `index.html:4739`,`7370` |
| Effective-schedule transform (exact semantics above) | conditional replace + independent ct/ca/dates + custom append | `reconEffectiveWD()` `index.html:2949-2965` |
| Budget-rules channel (separate) | `chk += applyBudgetRulesForWeek(...)`; bypassed on override weeks | `index.html:3017-3023`,`9863`,`10900` |
| Operating floor | `OP_FL = 6500` | `index.html:896` |
| Min transfer | `MIN_XFR = 100` | `index.html:896` |
| Per-week EOW checking | `weeks[].chk` | `index.html:3401-3402` |
| Reconciled-week override | `chk = rec.chk` | `index.html:3341` |
| Paycheck weeks | `[3,5,7,9,11,14,16,18,20,22,24,27,29,31]` | `index.html:1338` |
| Legacy Alaska draw (see §4) | model position `aoW(ACTION_KEYS.ALASKA_DRAW)` (default 15, `actionOverrides`-movable); `if(sav>=7000) mvS(7000,'chk')` else BLOCKED | `index.html:3056-3068`,`1006`,`1020` |
| Engine set-aside constants (see §3b) | `BASE_TAX=521.36`, `COMM_TAX=707.18`, `COMM_AK=1060.76`; `taxTodo=BASE_TAX` | `index.html:891`,`895`,`2990` |
| Cash-availability engine | `getCashAvailabilityEngine()` | `index.html:2453-2463` |
| Wendy IRA goal | `id:wendy_ira`, target `7500`, `_amxHold`, `needsFlag:ira_cpa_cleared` | `index.html:1598`,`3212` |
| `_amxHold` bypasses needsFlag | engine quirk; see §19 CPA gate | `index.html:3213` |

**Reconciled→projected seam:** weeks 1–7 reconciled at drafting; week 8 first projected
(`as_of_model_week=8`, `as_of_is_reconciled=false`). The opening point is a **fresh live-bank balance
captured inside the current projection week**. If reconciliation state advances before execution, §11-drift
**regenerates** this seam (never silently reuses week-8 assumptions).

### Section separation (mandated)

- **(A) LIVE-BANK** — fresh owner-captured Truist reality.
- **(B) CODE/MODEL** — the **effective-schedule snapshot** (pure adapter; §1a) + the **budget-rules channel**
  (§1c) + owner-readable cross-check transcription.
- **(C) BASELINE-D DB** — executed, frozen findings + the mandatory execution-time re-verification (§11).
- **(D) OWNER-REVIEW** — adjudicated adjustments (classification, set-asides, timing, staleness, seam, Alaska).
- **(E) ADVISORY OUT** — computed results. Advisory only; never a transfer authorization.

---

## 1. Execution architecture (rev-4)

Baseline E is executed by a **controlled combination**, not a single manual worksheet:

1. **Markdown design specification** (this document) — the human-authoritative contract.
2. **Effective-schedule snapshot (§1a)** — machine-generated by the **pure adapter**; the hashed schedule
   authority.
3. **Budget-rules channel extract (§1c)** — a separate hashed read-only extract.
4. **Immutable machine-readable input manifest (JSON)** — `baseline-E-inputs.json`. Every (A)/(B)/(C)/(D)
   input as data: normalized opening balance + pending ledger, the **event-level schedule** (§1d) derived
   from the snapshot **and** the budget-rules channel, the classification ledger, the carried-set-aside
   ledger (§3b), the Alaska release reconciliation, the seam reconciliation, all owner confirmations, and
   the proposed transfer (amount + intended date + posting assumption). Frozen by SHA-256; the script
   refuses to run against an unpinned/modified manifest. **All monetary fields are integer cents (§8).**
5. **Dedicated read-only deterministic Node calculation script** — `baseline-E-calc.mjs`. Pure function of
   the manifest → report. **No I/O, no network, no filesystem writes except the report, no clock/RNG.** It
   **must not `import`, `require`, `eval`, or otherwise reuse `runModel()` or any `index.html` code** —
   importing the app drags in the discretionary goal-waterfall (`_amxHold` sweeps), the single largest
   false-safe vector. Its forward engine applies **only** the classified manifest flows.
6. **Automated validation assertions + unit tests** — `baseline-E-calc.test.mjs`, covering the §17 matrix.
7. **Parity harness (§1e)** — a separate read-only cross-check against the application engine with
   discretionary sweeps suppressed; **never** the calculation engine.
8. **Deterministic execution report (JSON + Markdown)** — `baseline-E-report.json` + an owner-readable
   Markdown render (a report view, not the engine).
9. **Mandatory read-only SQL companion (§11)** — re-verifies DB state at freeze and again at execution.

### 1a. Effective-schedule pure-adapter authority (SCHEDULE AUTHORITY)

The **canonical** schedule-extraction method is a **standalone pure adapter**, not direct in-app
`reconEffectiveWD()`:

```
pinned WD source  +  read-only production model_week_overrides snapshot  +  verified pure merge adapter
      =  effective-schedule snapshot
```

- **The adapter reproduces the actual verified semantics of §0(i) exactly**, including: conditional
  `events_json` replacement (non-empty only, else literal fallback); independent `ct`/`ca`/`dates`
  overrides; `dates` fallback; `is_custom` **append** (not replace); custom `model_week` values outside the
  normal horizon; **detectable, never silently collapsed** duplicate `model_week` values.
- **Do not describe override behavior as unconditional entire-week replacement anywhere.**
- **Direct in-app `reconEffectiveWD()` output is a differential-test oracle, not the canonical dependency.**
  At the pinned HEAD, the adapter's output is compared **byte-for-byte** against a controlled in-app
  `reconEffectiveWD()` run over the same override snapshot; any divergence blocks freeze.
- **Mandatory provenance (in the snapshot):** source repository commit; `index.html` BUILD_TS; production
  project identity (`usayoldrawwmjsmretin`); the identity + content digest of **every** applied
  `model_week_overrides` row (`week_num` + row id + `events_json`/`ct`/`ca`/`dates` digest); extraction
  timestamp (ET); **adapter version/hash**; the projection week range; snapshot SHA-256.
- **Byte-stable output:** two adapter runs over an unchanged override snapshot are hash-identical.
- **Two capture points:** freeze-time and execution-time snapshots; differences enumerated/classified under
  §11; unexplained difference = FAIL-STOP.
- Hand-transcribed `WD` rows are an owner cross-check only; on conflict the snapshot governs (FAIL-STOP
  until explained).

### 1b. Extraction isolation & row-visibility controls (both adapter inputs and the differential oracle)

All of the following are required and recorded; any failure = **FAIL-STOP**:
- every read-only source fetch returns an explicit success status; **no silent fallback to empty override
  data** (guards the override silent-skip `if(overridesR.ok){…}` load block around `index.html:9894`, and
  the `budgetRulesLoadStatus='failed'` continue-on-error path `index.html:9950-9990`);
- **independent RLS visibility-proof (strengthened — MR-2):** the authenticated role must be **proven able to
  see every applicable `model_week_overrides` row** against an **independent visibility ground truth that
  cannot share the adapter's RLS restriction** — a naïve reconciliation is insufficient because the §11 SQL
  companion, if it runs under the *same* role, is blind to exactly the rows the adapter is blind to. Record
  and reconcile: extraction identity; the authenticated application role; owner-authorization status
  (provenance keyed to an immutable subject/user id / role, **not** a hard-coded personal email — the design
  states no personal email as the identity source); an **authoritative row count or row inventory obtained
  through a channel proven not to share the adapter's RLS restriction**; and a four-way comparison of
  {authoritative row count, adapter-visible row count, per-row ids, per-row content digests} at **both**
  capture points. A mismatch, an inability to establish independent visibility, or any unexplained hidden
  row = **FAIL-STOP before freeze.** The concrete mechanism is a **required Mode-2 + freeze-readiness
  verification item.**
- runtime source commit and BUILD_TS match the pinned expected values (served-file hash asserted);
- **no** application, database, or local-storage writes on any extraction path (network-log assertion);
- the differential oracle runs in a **fresh, controlled application profile** (no in-session Edit-Week
  activity; load-time `overrideData` only);
- all asynchronous loads complete **before** any comparison;
- repeated extraction from unchanged state is **byte-identical**;
- the browser `hfos_action_overrides` localStorage store (`index.html:1020`) is captured into provenance
  (it does not affect the snapshot but does affect any §1e harness run).

If full row visibility or successful load cannot be **proven**, extraction is invalid ⇒ FAIL-STOP.

### 1c. Budget Rules — first-class cash channel (dedicated read-only extraction)

Budget rules are extracted by a **dedicated read-only contract**, never via `reconEffectiveWD()`. For every
applicable rule (production `budget_rules`, `active=true`, over the projection horizon):

| field | meaning |
|---|---|
| `rule_id` | source row id |
| `rule_type` | rule category |
| `effective_range` | effective week/date span |
| `affected_target` | category or event affected |
| `checking_delta_cents` | integer-cents delta to checking (§8) |
| `applicability` | conditions under which it fires |
| `active_state` | active / inactive |
| `source_digest` | source-row content digest |
| `inclusion_classification` | mapped event(s), or excluded-with-reason |

**Governing inclusion contract (event-OR-classification — reconciles §1c with R12).** Every active and
otherwise-applicable `budget_rule` delta is represented **exactly once** as **either**:
- **(A)** an included manifest cash event (§1d); **or**
- **(B)** an explicit `inclusion_classification` row with disposition `excluded-with-reason`.

**Per applicable-rule × model-week intersection**, the manifest records an adjudication row:
`rule_id · rule_content_digest · model_week · active_status · ordinary_applicability_result ·
override_week_exists? · actual_engine_treatment · disposition (included | excluded-with-reason) ·
reason_code · resulting_event_id (if included) · adjudication_status`.

**Override-week bypass (verified `index.html:3017-3023`):** for a week that carries an override, `runModel`
**bypasses** budget rules. Therefore, for that rule-week intersection: **do not create a cash event**, and
classify it `excluded-with-reason: engine_override_week_bypass`. A real recurring flow thereby dropped on an
override week must be recaptured through the owner obligation-exactness confirmation (§2 B′) and completeness
(§16) — never by force-including the bypassed delta (an inflow-direction delta force-included here would be a
direct false-safe).

**Fail-closed behavior:**
- applicable rule-week intersection with **no adjudication** ⇒ **HOLD** if otherwise integrity-coherent;
  **FAIL-STOP before freeze** if it remains unresolved at freeze;
- **contradictory** engine/application evidence ⇒ **FAIL-STOP**;
- **both** an event **and** an exclusion classification present for one intersection ⇒ **FAIL-STOP**;
- **neither** present for an applicable intersection ⇒ **FAIL-STOP** before freeze.

A **zero-rule result is permitted only when established by the authoritative read-only extraction** (a
proven-empty applicable set), never assumed. Budget-rule events/classifications participate in event identity
(§7), anti-duplication (R7/R12), state-drift (§11), completeness (§16), and parity (§1d/§1e).

### 1d. Event schema + event-level & aggregate parity

The manifest's schedule is a flat event list derived deterministically from the snapshot (§1a) **and** the
budget-rules extract (§1c). Each event carries the **§7 content-bound identity fields** plus:

| field | meaning |
|---|---|
| `model_week` | current as-of week … 31 (customs: their own `week_num`, §13) |
| `date_or_position` | authoritative date when known (§2 B′), else conservative position class (§14) |
| `direction` | debit / credit |
| `amount_cents` | integer > 0 (§8) |
| `channel` | `inflow`/`obligation`/`override_event`/`ct`/`ca`/`budget_rule`/`owner_committed`/`conditional`/`transfer_test` |
| `account` | source-frame account (`truist_checking`) |
| `source` / `source_record_id` | `wd_literal` / `override:{row}` / `budget_rule:{id}` / `goal_ledger:{rec}` / `owner:{decl}` / `transfer_test` |
| `content_digest` | §7 digest bound to this event |
| `classification` | §3 bucket, or `excluded:{rule}` |

**Deterministic parity (FAIL-STOP on any unexplained mismatch):**
- **Event-level:** every snapshot/budget-rule event appears in the manifest exactly once with identical
  week/direction/amount/channel/provenance. **Excluded schedule events** are recorded, never silently dropped,
  under a named class: **`excluded:seam`** (§5b capture-week treatment) · **`excluded:
  already_reflected_in_opening_balance`** (§5c bank→schedule treatment) · **`excluded:partial_reflected`** (a
  §5b or §5c partial-posting reflected component). Every exclusion carries: governing rule · bank transaction
  identity (where applicable) · event identity · **both** relevant content digests · `amount_cents` ·
  evidence · adjudication status.
- **Aggregate:** per-week inflow, outflow, `ct`, `ca`, **budget-rule net**, and overall net — snapshot+extract
  vs manifest — reconciled exactly.
- Aggregate agreement is **never** accepted where event-level agreement fails.

### 1e. Parity harness + closed parity-difference catalogue

A separate read-only harness compares **Projection A** against the deployed application engine under a
controlled scenario with **discretionary sweeps suppressed** (input-level suppression; state-isolated;
restoration verified; run under the §1b identity assertions and a clean/recorded `actionOverrides` profile).
Purpose: prove schedule semantics match over the overlapping construct **without** using the engine as the
calculation engine.

**Closed difference catalogue (replaces "explained in prose").** Before freeze, the only permitted
difference classes are, e.g.:
- intentionally excluded discretionary waterfall;
- owner-input-only event not present in the app engine;
- conservative timing relocation with unchanged amount;
- explicitly modeled bank-seam adjustment;
- explicitly excluded conditional credit.

Each observed difference must map to **one** approved class **with event-level evidence**. **Any
cash-affecting difference, or any difference of an unknown class, = FAIL-STOP.** Prose cannot waive a cash
difference.

### Why a dedicated Node script remains safer

- **vs SQL-only:** the effective schedule + budget rules are outside a single SQL result; SQL alone cannot
  compute a forward trough.
- **vs manual arithmetic:** ~24 weeks × multiple channels is error-prone, not unit-testable, not
  reproducible. The worksheet survives as the human-readable *report*.
- **vs `runModel()` directly:** it re-runs the discretionary waterfall (`_amxHold`, `index.html:3212-3213`),
  a double-count and an unauditable trough. The snapshot + budget extract + parity give the script the
  model's *schedule truth* without importing its *discretionary behavior*.

---

## 2. Required inputs

Field columns: **name · type · authority · timestamp · staleness · validation · fail-closed · sign**
(`+`/`−`/`i`). **All monetary values: integer cents (§8).**

### (A) LIVE-BANK inputs (feed §5 normalization + §5b seam)

| name | type | authority | timestamp | staleness | validation | fail-closed | sign |
|---|---|---|---|---|---|---|---|
| `live_chk_selected_basis` | enum {`posted_current` (default), `available`} | owner | req | — | `available` only with §5 documented semantics | unknown ⇒ FAIL-STOP | i |
| `live_chk_displayed_balance_cents` | int cents | Truist | req | **>24h ⇒ FAIL-STOP** | integer ≥ 0 (§8) | missing/stale ⇒ FAIL-STOP | opening base |
| `live_chk_capture_ts` | tstamp (ET) | owner | req | — | ISO-8601, not future | missing ⇒ FAIL-STOP | i |
| `pending_items[]` | table (§5) | Truist + owner | req | — | each fully classified | any unresolved ⇒ HOLD | ± |
| `capture_week_seam[]` | table (§5b) | owner + Truist | req | — | every capture-week event adjudicated (schedule→bank) | ambiguous ⇒ HOLD; contradictory ⇒ FAIL-STOP | i |
| `bank_to_schedule_reconciliation[]` | table (§5c) | owner + Truist | req | — | every capture-week transaction posted ≤ capture reconciled vs the **entire** forward schedule (bank→schedule) | multiple/conflict ⇒ FAIL-STOP; ambiguous ⇒ HOLD | i |
| `alaska_770_in_basis` | bool | Truist + owner | req | — | boolean | false w/o explanation ⇒ HOLD | i (R1) |

**Manifest-wide execution window:** the whole manifest is captured as one coherent set; execution must occur
within the same **≤24h window** as `live_chk_capture_ts`, else FAIL-STOP. §16 sequences the capture.

### (B) CODE/MODEL inputs

| name | type | authority | validation | fail-closed | sign |
|---|---|---|---|---|---|
| `model_year` | int | `index.html:902` | `=2026` | mismatch ⇒ FAIL-STOP | i |
| `as_of_model_week` | int | Baseline D + §11 re-derivation | current at execution | stale vs DB ⇒ FAIL-STOP | i |
| `horizon_end_week` | int | snapshot | `=31` (customs handled per §13) | ≠31 w/o §13 handling ⇒ FAIL-STOP | i |
| `effective_schedule_snapshot` | §1a artifact | pure adapter | provenance complete + hash + oracle parity | missing/uncited/divergent ⇒ FAIL-STOP | ± |
| `budget_rules_extract` | §1c artifact | dedicated extraction | active-set complete or proven-zero | active rule not incorporated ⇒ FAIL-STOP | ± |
| `effective_schedule_events[]` | §1d schema | derived | event + aggregate parity | any unexplained mismatch ⇒ FAIL-STOP | ± |
| `wd_cross_check_transcription[]` | table | owner-readable cross-check | conflicts investigated | conflict unexplained ⇒ FAIL-STOP | i |
| `paycheck_wks` | array | `index.html:1338` | exact match | mismatch ⇒ FAIL-STOP | + |
| `override_inventory[]` | list | snapshot provenance | complete vs production at execution (§11) | undisclosed/undetected override ⇒ FAIL-STOP | i |
| `model_build_identity` | {HEAD,BUILD_TS,adapter_hash} | git + `index.html:888` + adapter | recorded; matches snapshot | drift after capture ⇒ FAIL-STOP | i |

### (B′) Material-obligation exactness

Each card/material obligation requires **exact** confirmation before freeze: account · exact amount (cents) ·
due date · expected posting/payment date · statement source · already-posted? · autopay/manual ·
effective-schedule value · reconciliation result · **embedded-reimbursement declaration** · inclusion
decision. Applies to **AMEX Gold, any AMEX Platinum residual, Disney Visa, Costco Visa, Kia, rent, Alaska
releases, reimbursements, and every other active/residual obligation** (§16). If a **trustworthy conservative
bound** exists (amount upper bound + earliest-plausible date), the item may proceed at that bound with HOLD;
otherwise a material undated item (e.g. undated Costco Visa, `index.html:3036`) is a **final-execution
FAIL-STOP**.

### (C) BASELINE-D DB inputs (frozen; §11 re-verified at execution — MANDATORY)

| name | value | disposition | sign |
|---|---|---|---|
| D7 authoritative reserved total | **$0.00** | six commitments `reflected_into_balance` | 0 forward |
| D2 Alaska `goal_disbursement` | **+$770.95** | already recorded + reflected | i — not additive (R1) |
| D2B uncleared Bailey | **+$15.00** | conditional (§5/R2′) | + iff not in opening basis nor schedule |
| six `cash_commitments` | `reflected_into_balance` | in balance | 0 (R3) |
| $435.63 commission-tax | reflected/resolved wk5, excluded from D7 | historical | 0 (R4) — see §3b candidate |
| BKX $700.90 | evidence only in `custom_tasks.label` | §3 adjudication / R5 | 0 unless fresh evidence |
| architecture | **pre-AU-11** (`au11_objects_present=0`) | no custom_task is an engine reservation — **not** proof of economic irrelevance (§3) | i |

### CONTROL input — operating floor (fail-closed)

`OP_FL` is documented as **$6,500** (`index.html:896`), but **execution requires explicit owner
confirmation** of: the floor amount; whether a separate named reserve exists; the source of authority.
**Unconfirmed floor ⇒ HOLD (no silent default).** Any reserve above the floor is a **named control input**,
never an undocumented buffer.

### (D) TRANSFER inputs (a final run ALWAYS concerns a supplied transfer — no capacity-only mode)

| name | type | authority | required |
|---|---|---|---|
| `wendy_ira_amount_cents` | int cents | owner | **yes** |
| `wendy_ira_intended_date` | date | owner | **yes** |
| `wendy_ira_expected_posting` | date or `conservative` | owner | **yes** (else earliest-plausible placement, §14) |

The engine may still **derive** `maximum_floor_safe_transfer` as an output, but the final
PASS-SAFE/PASS-UNSAFE verdict always concerns the supplied proposed transfer. There is **no** amount-less
final-execution mode.

---

## 3. Counterfactual-baseline classification ledger

Every future goal/waterfall/action/custom item that could affect checking is classified into exactly one
bucket. **Projection A** contains every **mandatory** and **owner-committed** future checking flow that would
occur **without** the proposed transfer — and excludes **discretionary** items.

| class | definition | in Projection A? |
|---|---|---|
| **mandatory / already-authorized** | fixed contractual flows: rent, AMEX Gold, AMEX Plat residual, Disney Visa, Costco Visa, Kia, paychecks, effective `ct`/`ca`, incorporated `budget_rule` deltas | **YES** |
| **owner-committed** | externally committed — bank-scheduled, promised to a third party, or decision-logged — regardless of engine class; **includes outstanding carried set-asides (§3b)** | **YES** (each owner-adjudicated) |
| **discretionary / removable** | deferrable **solely at owner option**: goal-waterfall sweeps (`adam_ira`, `wendy_ira`, `bailey_529`, `bryce_529`, `preston_529`, cruise/vehicle) | **NO** |
| **historical / already reflected** | Alaska +$770.95, six commitments, $435.63 (subject to §3b confirmation), already-posted items | **NO** |
| **conditional** | depends on an unmet precondition (e.g. an Alaska release, §4) | **only if §4/§2 confirms** |
| **unresolved** | economic treatment unknown | **HOLD** when material |

**Boundary rule (C-7):** externally committed or decision-logged ⇒ owner-committed; deferrable solely at
owner discretion ⇒ discretionary. The falsely-optimistic direction (a committed outflow mis-bucketed
discretionary) is the dangerous one; §10's `other_authorized_unexecuted_uses` is the second capture.

**Custom-task evidence bar (pre-AU-11 refined):** pre-AU-11 proves no `custom_task` is an *engine
reservation*; it does **not** prove economic irrelevance. Include a future custom task as **owner-committed**
only with **all** of: parsed amount · date (or conservative §14 position) · owner affirmation · not-posted
evidence (bank check) · not-represented-elsewhere proof. Exclude as **historical** only with settlement
evidence or explicit owner voiding. Else **unresolved ⇒ HOLD when material** (e.g. BKX $700.90 — R5).

**Undated committed items must not disappear:** boundable ⇒ conservatively-dated event (§14); unboundable ⇒
a **committed-capacity claim** in `other_authorized_unexecuted_uses` (§10) **plus HOLD** if its plausible
timing could alter the trough. Dated committed items are **schedule events**; undated ones are
**capacity-claim deductions** — never both for one item (R7).

---

## 3b. Carried-set-aside adjudication ledger (mandatory)

Engine carry-forward set-asides can be **forward checking outflows that appear in no effective week ≥ as-of**
(every literal future week has `ct=0, ca=0`; the engine resolves deferrals in its *simulated* early weeks).
**Zero future `ct`/`ca` is NOT proof of closure.** A **mandatory adjudication ledger** investigates every
engine-origin set-aside scheduled on/before the as-of frontier that might remain outstanding.

Candidate values identified from source — `BASE_TAX=$521.36`, `COMM_TAX=$707.18`, `COMM_AK=$1,060.76`
(`index.html:891,895,2990`), and any other engine-modeled transfer scheduled ≤ as-of week — are
**investigation candidates, not automatic Projection-A obligations.** For each, record:
candidate identity · source amount (cents) · source week · intended destination · engine execution status ·
bank evidence · Register evidence · `cash_commitment` evidence · `custom_task` evidence · settlement/
supersession evidence · remaining amount · final classification · forward `event_id` if included.

Rules:
- proven **executed/reflected** → historical; **do not re-add**;
- proven **superseded/voided** → excluded with evidence;
- proven **outstanding and intended** → **owner-committed forward flow** (§3, dated or capacity-claim per §14);
- **unresolved and material → HOLD**;
- **contradictory integrity evidence → FAIL-STOP**.

Note Baseline D resolved a **$435.63** commission-tax correspondence (≠ `COMM_TAX` $707.18); that resolution
is evidence for one candidate, not blanket closure. Tests (§17): explicit `ct` inclusion; explicit `ca`
inclusion; carried set-aside executed; carried set-aside outstanding; partial settlement; reflected amount
re-added (FAIL-STOP); unresolved candidate (HOLD).

---

## 4. Alaska source-of-funds reconciliation (releases; Goal-Ledger-sourced)

**Governing reality to verify (not assume):** the household's adopted Alaska model is **statement-level
savings→checking releases**, recorded in the canonical **interim Alaska Goal Ledger** (system of record —
the Alaska interim operating decision record + the `CODEX_STATUS.md` Goal-Ledger currency note). The legacy
code-side bulk draw at model position `aoW(ACTION_KEYS.ALASKA_DRAW)` (default week 15, `actionOverrides`-
movable; `index.html:3056-3068`) predates it. **Neither the code constant nor a fixed "week 15" may be
assumed current** — the model position is sourced or explicitly excluded under the controlled extraction/
harness contract, and the exact figures come **from the Goal Ledger**.

Required inputs (each Goal-Ledger-sourced + live bank, integer cents):
- `alaska_goal_ledger_source` — ledger document identity + as-of date.
- `alaska_custody_cents` — Alaska-earmarked funds **actually in Truist Savings now**.
- `alaska_spendable_cents` — remaining spendable per the ledger.
- `alaska_settled_releases[]` — already executed (historical; never re-added).
- `alaska_proposed_releases[]` — each future savings→checking release: amount · expected date · intended? ·
  source-sufficiency-in-sequence · duplication check vs the effective schedule, Register, pending items, and
  other owner inputs.
- `alaska_legacy_draw_status` — superseded / retained / re-derived (owner adjudication with ledger evidence).

Decision rules:
- **Mutual exclusion (R8′):** the legacy bulk draw and statement-level releases may **never both** be
  included. One representation of custody; Σ releases ≤ custody; sequential sufficiency at each release date.
- A release enters Projection A/B as a **conditional inflow** only if intended **and** dated **and**
  sequentially funded **and** not double-represented.
- **Unscheduled/unapproved releases are excluded by default** (conservative for the floor). If the transfer's
  safety verdict *depends* on an excluded release, report the dependence and return **HOLD**.
- Insufficient source / uncertain amount / stale ledger → **HOLD** (immaterial) or **FAIL-STOP** (material).
- Never let a release depend on future waterfall-generated savings.

---

## 5. Live-bank opening-balance normalization

**Default basis = `posted_current`.** `available` may be selected **only** when the bank's inclusion
semantics for pending debits, pending credits, and holds are explicitly documented in the manifest
(available-vs-cleared confusion is a known prior failure).

```
normalized_opening_chk_cents
    = live_chk_displayed_balance_cents (selected basis)
    + confirmed pending CREDITS not already included in the selected basis
    − confirmed pending DEBITS  not already included in the selected basis
```

**Every** pending item carries: `amount_cents` · `direction` · `status` (pending/posted/hold/memo) ·
`in_posted_balance` · `in_available_balance` · `in_selected_basis` · `in_forward_schedule` · `treatment`.

**Bailey +$15.00 rule (R2′):** "pending" is not decisive; inclusion in the **selected basis** and/or the
**forward schedule** is:
- in selected basis, not in schedule ⇒ **$0** adjustment.
- not in basis, not in schedule ⇒ add **once**.
- in schedule, not in basis ⇒ schedule carries it ⇒ **$0** opening adjustment.
- in both basis and schedule ⇒ **remove the schedule instance**; keep it in opening.
- status/inclusion `unresolved` ⇒ **HOLD**.

Same partition for every pending item and for reimbursements (only post-capture, not-yet-included inflows may
be forward credits).

**GLOBAL NO-DOUBLE-COUNT INVARIANT (binding).** *Every cash effect represented in the opening checking
balance or its pending adjustment is represented **no more than once** in the retained projection schedule.*
This invariant holds **regardless of the model week in which an event was originally expected** — a posted
inflow already inside the opening balance must never also remain as a retained forward inflow, and likewise
for outflows. The forward capture-week event seam (§5b) and the reverse bank→schedule reconciliation (§5c)
**together** enforce it; any violation is FAIL-STOP.

### 5b. Capture-week seam reconciliation (the deterministic live→schedule cutover)

**Seam universe (corrected — CD-1).** The seam covers **every effective-schedule event expected *anywhere* in
the capture week**, **not merely** events whose expected time is at or before `live_chk_capture_ts`. This is
mandatory because an event **expected later in the week** can have **actually posted before capture** (a
paycheck direct-deposited early, an autopay that cleared ahead of its due date) — such an event is already
inside the opening balance yet, under a cutover-only scope, would be retained in the forward schedule and
**counted twice**. The capture timestamp remains the deterministic cutover for *conservative placement of
retained events*, but the seam **universe** is the whole capture week. This aligns §5b with R13's "every
capture-week event."

For **every** capture-week event, the manifest carries a seam adjudication row with at minimum:
`event_id` (§7) · `event_content_digest` · expected date/model position · `direction` · `amount_cents` ·
**bank posting status as of `live_chk_capture_ts`** · **included in the selected bank-balance basis?** ·
`pending/posted/unknown` state · `schedule_disposition` · `evidence_reference` · `adjudication_status`.

Deterministic treatment (applies to **both directions** — early-posted inflows and early-posted outflows):
- **posted before capture AND included in the selected basis → remove from the retained forward schedule**
  (it lives in the balance); recorded `excluded:seam`, never silently dropped (§1d parity).
- **not posted before capture → retain** in the forward schedule, conservatively placed after the cutover
  (§14).
- **partially posted → split** into a posted/reflected component (excluded:seam) and a remaining-forward
  component, using distinct content-bound identities (§7).
- **posting known but basis-inclusion unknown, or otherwise ambiguous → HOLD.**
- **contradictory evidence** (e.g. marked posted but absent from the basis) **→ FAIL-STOP.**
- **event digest changed after seam adjudication → the adjudication is invalidated** (§7): return to
  unresolved/HOLD on regeneration; execution-time mismatch ⇒ FAIL-STOP.

Seam tests (§17): early-posted inflow (expected later **in the capture week**, posted early, reflected)
proven **not** counted in both opening balance and schedule; early-posted outflow; event not yet posted
(retained); partial posting (split); posting known but basis-inclusion unknown (HOLD); event digest changed
after adjudication (invalidation); duplicate seam inclusion → FAIL-STOP.

### 5c. Reverse bank→schedule reconciliation (NEW — NF-1; the complementary direction)

§5b scans **schedule → bank** for events expected *in the capture week*. It does **not** catch a
**future-scheduled** event (model week **N+1 or later**) that the bank **posts early** — before
`live_chk_capture_ts`, during the capture week — because such an event is inside the opening balance yet its
*expected* position is outside the capture week and it is not an obligation (so §2 B′ never asks) and, once
posted, no longer a *pending* item (so §5 never adjusts). rev-6 adds the reverse direction. **§5c
complements §5b; it does not replace it — both are required.**

**Scope:** **every** checking-account transaction **posted during the capture week and at or before
`live_chk_capture_ts`** is evaluated against the **entire retained forward schedule from the current as-of
model week through the approved projection horizon (`as_of_model_week → coverage_horizon_end`)** — not only
capture-week events. **Both directions** (inflows and outflows).

For each in-scope posted transaction, a `bank_to_schedule_reconciliation[]` row:
`bank_transaction_id` (stable bank-record identity) · `bank_transaction_content_digest` · `posted_at` ·
`direction` · `amount_cents` · `description_or_reference` · **included in the selected opening-balance
basis?** · `candidate_forward_matches[]` (recall-oriented; §5c matching standard) · `confirmed_matches[]`
(precision-oriented; the allocation/split contract below) · `match_method` · `disposition` ·
`evidence_reference` · `adjudication_status`.

**`confirmed_matches[]` allocation/split contract (manifest sufficiency, rev-7).** A singular
`matched_event_id` cannot represent every permitted disposition. `confirmed_matches[]` therefore represents:
one-txn→one-event; one-txn→an explicitly approved allocation across multiple events (G); multiple-txns
composing one event (F, only with decomposition); and partial-posting split components (B). Each confirmed
match carries: `event_id` · `event_content_digest` · `allocated_amount_cents` · `allocation_reason` ·
`expected_model_week_and_date` · `resulting_disposition` · `reflected_component_id` (if a split) ·
`remaining_forward_component_id` (if a split). Required conservation: **Σ `allocated_amount_cents` = the
adjudicated posted amount** where allocation is complete; **reflected + remaining components = the original
schedule-event amount**; **no event or transaction participates in multiple reconciliations without an
explicit allocation graph**; all components use content-bound identities (§7); **unexplained multiplicity or
any cent imbalance ⇒ FAIL-STOP.**

**Deterministic treatment:**
- **(A) exactly one retained future-event match, and included in opening balance:** remove/exclude the matched
  event from the retained forward schedule; classify `already_reflected_in_opening_balance`; bind the
  exclusion to **both** the bank and schedule content digests.
- **(B) partial early posting of a future event:** split the schedule event into an **already-reflected
  component** and a **remaining-forward component**, distinct content-bound identities (§7), **exact cent
  conservation**.
- **(C) matches multiple candidate schedule events:** **HOLD** pending adjudication; **FAIL-STOP before
  freeze** if unresolved.
- **(D) conflicts with the candidate in amount, direction, identity, or evidence:** **FAIL-STOP.**
- **(E) no forward match** — permitted **only after** candidate generation has evaluated the required
  identity/context signals and **no plausible forward event remains**: retain the bank transaction as
  **balance-only history**; create **no** offsetting or synthetic future event; the **retained forward
  schedule is byte-identical before and after** the no-match adjudication (E adds no schedule representation
  for a cash effect already in the opening balance). Determine whether it is an off-model inflow / off-model
  outflow / custom-task execution / Goal-Ledger movement / budget-rule effect / other authorized event, and
  route it through completeness (§16) and state-drift (§11).
- **(F) a future event matched to >1 posted transaction without an explicit partial-posting decomposition:**
  **FAIL-STOP.**
- **(G) a posted transaction matched to >1 future event:** **FAIL-STOP** unless an explicit,
  evidence-supported allocation is recorded.
- **(H) match/adjudication digest changes after capture:** invalidate the prior adjudication; regenerate →
  re-parity → re-hash → re-adjudicate (§11).

**Matching standard — two explicitly separated stages (rev-7).**

**(A) Candidate generation — recall-oriented, deliberately broad.** Search the **complete retained forward
schedule from the current as-of model week through the projection horizon** (`as_of_model_week →
coverage_horizon_end`). A schedule event enters `candidate_forward_matches[]` when **one or more
identity-bearing or contextual signals** indicate a plausible relationship, as applicable: source-account
identity · destination/counterparty identity · bank reference / trace reference · transaction description
token · event classification · payroll / reimbursement / transfer / card-payment / Goal-Ledger / budget-rule
/ custom-task identity · expected-date window · model-week proximity · known recurring-series identity ·
content-bound external reference. **Exact amount and direction are validation attributes, NOT prerequisites
for candidate generation** — candidate generation **must not** be restricted to exact-amount matches. *Any
implementation that filters candidate generation by exact amount before testing identity/context evidence is
non-conforming and must FAIL-STOP in Mode 2.*

**(B) Match confirmation — precision-oriented, requires sufficient evidence.** A deterministic automatic
confirmation requires a **sufficiently strong combination** (exact amount **and** direction · source-account
identity · destination/counterparty identity · bank reference · expected-date window · event classification ·
content-bound event identity); it may **not** rest on any of {equal amount alone, description similarity, date
proximity, ordinal position} in isolation.

**Deterministic D-vs-E routing (binding).**
- An **identity-strong candidate with an amount or direction conflict routes to disposition D (FAIL-STOP)** —
  it **must not** silently fall to disposition E, and the future event must **not** remain silently retained
  while the posted amount sits in the opening balance. No prose waiver or ordinary HOLD resolves it.
- **Multiple plausible candidates** route to disposition **C** (or **G** where an explicit allocation
  applies) adjudication.
- A **true disposition-E no-match** is permitted **only after** the required candidate-generation signals
  above have been evaluated and **no plausible forward event remains**.

**Ambiguous matches must not be guessed** — HOLD (→ FAIL-STOP at freeze if unresolved). Manual adjudication is
permitted only if it records: candidate set · selected match · evidence · owner/reviewer identity ·
timestamp · bank digest · event digest.

**False-safe rule (restates the §5 invariant for this direction):** a posted **inflow** already included in
the opening balance must **never** remain as a retained forward inflow, **regardless of the week it was
originally expected**; likewise a posted **outflow** already included must not remain as a retained future
outflow.

§5c tests (§17): cross-boundary early-posted **inflow** (expected week N+1, posted in week N before capture,
in balance, matched, future event excluded, appears **exactly once**, `maximum_floor_safe_transfer` not
overstated); cross-boundary early-posted **outflow**; one bank txn → multiple events (FAIL-STOP/HOLD); one
event → multiple bank txns without decomposition (FAIL-STOP); partial early posting (split, cent-conserving);
ambiguous match (HOLD→FAIL-STOP); digest mutation after match (invalidation).

---

## 6. Anti-double-counting rules (deterministic PASS / HOLD / FAIL-STOP)

- **R1 — Alaska +$770.95:** `alaska_770_in_basis==true` ⇒ never re-add. False/unexplained ⇒ HOLD. Added
  forward ⇒ FAIL-STOP.
- **R2′ — Bailey +$15.00:** §5 partition; counted **exactly once**. In both opening and schedule ⇒ FAIL-STOP.
- **R3 — six reflected commitments:** D7 `$0.00` ⇒ no forward subtraction. Re-subtracted ⇒ FAIL-STOP.
- **R4 — $435.63 commission-tax:** reflected/resolved ⇒ no subtraction (see §3b). Deducted again ⇒ FAIL-STOP.
- **R5 — BKX $700.90:** subtract **only** with fresh evidence still-unpaid **and** off-schedule (§3 + HOLD);
  else none. Deducted without evidence ⇒ FAIL-STOP.
- **R6 — custom_tasks are never engine reservations** (pre-AU-11); economic relevance is the §3 question.
- **R7 — one representation per obligation:** each item appears in **exactly one** of {schedule event,
  capacity-claim deduction, opening balance}. D7=$0.00 ⇒ (C) forward-subtraction set empty. Duplication ⇒
  FAIL-STOP.
- **R8′ — Alaska custody single-representation:** §4; **legacy bulk draw XOR statement releases**; Σ ≤
  custody; sequential sufficiency; never conflated with +$770.95; never dependent on waterfall savings.
  Unconfirmed ⇒ HOLD/exclude.
- **R9 — reimbursements:** only post-capture, not-in-basis inflows are forward credits (§5); a reimbursement
  **netted in a confirmed obligation amount (§2 B′) is never separately added.** Ambiguous ⇒ HOLD.
- **R10 — timing ambiguity:** unconfirmed posted/forward/intra-day order ⇒ conservative placement (§14) +
  HOLD on that item.
- **R11′ — discretionary sweeps vs the tested transfer:** discretionary sweeps (§3) **excluded from both
  projections**; the tested transfer is the **only** IRA move in Projection B. Any discretionary
  `wendy_ira`/`adam_ira`/529 sweep coexisting with the tested transfer ⇒ FAIL-STOP.
- **R12 — channel completeness:** every snapshot `ct`/`ca` amount appears as a manifest event (§1d parity);
  and every active, otherwise-applicable `budget_rule` delta is represented **exactly once** as **either** a
  manifest cash event **or** an `inclusion_classification: excluded-with-reason` row (§1c contract, incl.
  `engine_override_week_bypass`). Any cash-affecting channel value dropped, any intersection with **both**
  event and exclusion, and any applicable intersection with **neither** ⇒ FAIL-STOP.
- **R13 — seam single-count (both directions):** every capture-week event resolved per §5b (schedule→bank),
  **and** every checking transaction posted in the capture week at/before `live_chk_capture_ts` reconciled
  against the entire retained forward schedule per §5c (bank→schedule). The **global no-double-count
  invariant** (§5) holds: every cash effect in the opening balance / pending adjustment appears **≤ once** in
  the retained schedule, regardless of originally-expected week. Any contradiction, duplicate (balance +
  schedule), or unresolved multiplicity ⇒ FAIL-STOP.
- **R14 — carried set-aside single-representation:** every §3b candidate resolved to exactly one disposition;
  a reflected/settled set-aside re-added ⇒ FAIL-STOP; an outstanding one omitted ⇒ (caught by §3b) HOLD/
  FAIL-STOP by materiality.

---

## 7. Stable content-bound event-identity contract

**Prohibited:** event IDs derived **solely** from array position, extraction order, a runtime counter, or a
mutable ordinal among non-identical events.

**Canonical identity** includes stable source attributes: `source_class` (namespace) · `source_record_id`
where available · `model_week` · `channel` · `direction` · `amount_cents` · `label_text_digest` ·
`account_identity` · `override_provenance`.

**Namespaces (explicit):** `wd_literal` · `override_event` · `ct` · `ca` · `budget_rule` · `custom_task` ·
`owner_committed` · `alaska_release` (Goal-Ledger record) · `pending_bank_adjustment` · `transfer_test`
(fixed id `transfer_test:wendy_ira`). ct/ca: at most one each per week (enforced); id `wk{N}:ct` / `wk{N}:ca`
+ amount.

**Collision control:** identical-content duplicates within a week (e.g. two $2,000 rent events) take a
deterministic duplicate index **only within the identical-content group**, so unrelated edits cannot re-map
them.

**Digest binding:** every seam adjudication, classification, and cross-reference also carries the event's
`content_digest`. If an `event_id` survives but its digest changes: the prior adjudication is **invalidated**;
the item returns to **unresolved/HOLD** during regeneration; an execution-time mismatch is **FAIL-STOP** until
re-adjudicated. Tests (§17): collision handling; digest-rebinding invalidation; unchanged-state ID stability;
localized change on edit.

---

## 8. Exact decimal-string → integer-cents contract

All authoritative monetary values enter the manifest as **canonical decimal strings or integer cents**.
**Never derive cents by multiplying an IEEE-754 float by 100** (e.g. `707.18*100 = 70718.000…01`).

Define a parser that:
- accepts a canonical **signed decimal string**;
- permits **no more than two fractional digits** for ordinary currency;
- pads one fractional digit to two;
- **rejects** more than two fractional digits unless the source contract explicitly defines an approved
  rounding rule;
- **rejects** exponent notation, NaN, Infinity, malformed separators, and ambiguous locale formats;
- returns an **integer number of cents**;
- **enforces the allowed sign by field** (e.g. obligations forbid positive-as-credit misuse; adjustments may
  be signed).

**Preferred path for repository numeric literals:** source-text decimal **extraction** into exact decimal
strings **before** conversion (the `WD`/constant literals are decimal text in `index.html`).

**`events_json` amounts (mandatory artifact requirement — MR-3).** Override `events_json` amounts arrive from
PostgREST as **JSON numbers** (IEEE-754). The implementation must **prove one of two safe paths**, and Mode-2
must inspect and test the concrete implementation:
- **Preferred:** obtain the authoritative **decimal token / raw JSON text** and parse the monetary token
  directly as an exact decimal string into integer cents (never touch the parsed float).
- **Alternative (only if unavoidable):** accept a parsed JavaScript number **only** through an explicitly
  reviewed canonicalization function that: proves the number is **finite**; proves it maps **unambiguously**
  to a cent value within a specified tolerance; **rejects** values near a half-cent boundary or with
  non-cent precision; and **never** uses `value × 100` without that validation. Fails closed at cent
  ambiguity.

All arithmetic and comparisons use **integer cents only**.

Tests (§17): `707.18`; `5816.5`; `0`; `0.1 + 0.2` float contamination (rejected/canonicalized exactly);
a value just **below** a half-cent boundary; a value just **above** a half-cent boundary; a three-decimal
JSON value (reject unless an explicit source rule governs); exponent notation in raw JSON (reject); malformed
/ non-finite value (reject); a negative allowed adjustment; a forbidden negative obligation; one decimal place
(pad to two); cent-boundary accumulation exactness.

---

## 9. Two projections, global trough, and the maximum-safe-transfer algorithm

**No `post_transfer_trough = baseline_trough − transfer` shortcut.** Two complete, independent projections:

- **Projection A (counterfactual baseline):** normalized opening balance forward through the horizon applying
  all **mandatory + owner-committed + confirmed-conditional** flows (§3/§3b/§4), **without** the proposed
  transfer. Contains a **synthetic transfer-position checkpoint** carrying the pre-debit running balance
  immediately before the proposed transfer's position. Produces the full series, `troughA`, `troughA_position`.
- **Projection B (post-transfer):** identical inputs plus the proposed transfer **debit inserted at its
  earliest-plausible posting position** (§14). Full running balance recomputed — `troughB`, `troughB_position`;
  the transfer event's own post-balance is a scanned event.

**GLOBAL TROUGH GOVERNS.** The verdict uses the **global conservative trough across the complete horizon** —
pre-transfer events, the synthetic checkpoint, the transfer event, and post-transfer events.

**Maximum-safe-transfer — corrected algorithm:**
- If **any** conservative Projection-A balance **before** the transfer position is `< $6,500`, then
  `maximum_floor_safe_transfer = $0` (a pre-transfer breach cannot be cured by later headroom).
- Otherwise the governing minimum includes the **synthetic transfer-position pre-debit balance** and **all
  later event balances**.

The **closed form** may be used **only** when all four preconditions are asserted by the script:
1. the tested transfer is a single one-time checking debit;
2. event ordering is fixed (no event's position depends on balances);
3. the transfer changes no other flow's amount or timing;
4. no included conditional flow's precondition references checking or the transfer's destination account
   (**conditional-independence assertion**, checked over the manifest).

Under those conditions:
```
maximum_floor_safe_transfer
  = max( 0,
         ( min over the synthetic transfer-position checkpoint and all later Projection-A event balances )
         − 650000¢ )
  ,  and = 0 if any pre-transfer conservative balance < 650000¢
```

**Mandatory self-verification (always) — three cases (corrected, MR-1):**

- **(A) Positive computed maximum, no external cap:** Projection B **at the computed maximum** must have a
  global conservative trough **exactly equal to $6,500**; Projection B **at maximum + $0.01** must **breach**
  the floor.
- **(B) Maximum constrained to $0** — by **either** the pre-transfer-breach gate **or** the non-negativity
  clamp (the at/after baseline minimum is already below the floor): Projection B **at $0** must **reproduce
  the underlying Projection-A trough** (it is **not** required to equal the floor). This is a valid
  **zero-capacity / PASS-UNSAFE** outcome, **not** FAIL-STOP, **provided** Projection A and Projection B
  reconcile exactly at zero transfer. Projection B **at $0.01** must **not improve** the trough and must
  remain below the floor.
- **(C) External cap binds below the mechanical maximum:** Projection B **at the cap** must remain
  floor-safe; document the cap as the binding constraint; the capped result is **not** required to place the
  trough exactly at the floor.

**FAIL-STOP only when the projection recomputation disagrees with the expected mathematical relationship for
the applicable case above.** In particular, a maximum clamped to $0 by a **post-transfer-position** baseline
trough below the floor is case (B): it yields **PASS-UNSAFE**, never FAIL-STOP.

**Projection B at the owner's proposed amount also remains mandatory.** If conditional independence is not
established, the closed form is forbidden: deterministic bisection over integer cents (full recomputation per
candidate), or HOLD/FAIL-STOP. Tests (§17): large inflow immediately after transfer; transfer exactly at
trough; pre-transfer breach; computed-maximum verification; maximum + 1¢; conditional-independence failure.

---

## 10. Calculation structure (defined, NOT executed) — separated capacity outputs

```
normalized_opening_chk_cents                (§5, §5b)

Projection A (no new transfer):
  ordered event stream (§14) over the horizon:
     apply mandatory + owner-committed + confirmed-conditional flows; NO discretionary sweeps
     include the synthetic transfer-position checkpoint (§9)
  troughA           = global conservative trough (event-level)
  cushionA          = troughA − 650000¢
  baseline_capacity = max(0, cushionA)

Projection B (proposed transfer at earliest-plausible posting position):
  as A, plus wendy_ira_amount_cents debit at the transfer position
  troughB  = global conservative trough (pre-transfer + checkpoint + transfer event + post-transfer)
  cushionB = troughB − 650000¢

maximum_floor_safe_transfer            # §9 gated closed form (self-verified) or bisection; never a subtraction
other_authorized_unexecuted_uses       # owner-listed committed-capacity claims (undated items, §3)
residual_deployable_capacity
  = max(0, maximum_floor_safe_transfer − Σ other_authorized_unexecuted_uses)
post_transfer_residual_capacity        # residual after the proposed transfer, if executed
```

**Capacity terminology (binding):** *gross mechanical floor cushion* (`cushionA`), *owner-committed
unexecuted claims*, *residual deployable capacity*, *proposed transfer amount*, and *post-transfer residual
capacity* are **distinct** reported quantities. Gross cushion is **never** labeled "available"/"deployable"
while any owner-committed claim holds priority. **No buffer beyond $6,500** without an explicit named control
input (§2 CONTROL).

---

## 11. State-drift universe (freeze + execution; both mandatory, read-only)

Legitimate post-Baseline-D changes are **detected, classified, and incorporated by regeneration — not
prohibited.** Enumerate every relevant surface:
- `weekly_reconciliations`;
- `model_week_overrides` (row identity + `events_json`/`ct`/`ca`/`dates` digest);
- `budget_rules` (active set + digests);
- `cash_commitments` (new/changed/resolution);
- `custom_tasks` (new committed-capacity candidates, BKX-class);
- relevant **accounts registry** (§16);
- **Goal Ledger source identity + applicable records** (§4);
- effective-schedule **source commit / BUILD_TS / adapter hash**;
- **`hfos_action_overrides`** (used only by the §1e parity harness);
- **bank capture + pending-item state**.

For every detected change: **enumerate → classify** (benign / schedule-affecting / basis-affecting /
integrity-affecting) **→ incorporate by regeneration** (snapshot, budget extract, seam, classification,
overlay relevance) **→ re-parity (§1d) → re-hash → re-adjudicate** where content identity changed (§7 digest
binding). **No legitimate change is prohibited for being new.** **Unexplained, invisible, contradictory, or
unincorporated change = FAIL-STOP.**

**Reconciliation-frontier contingency:** if a later week becomes reconciled before execution, the frozen
week-8-unreconciled assumptions are **invalid** — regenerate opening basis, projection start, snapshot,
overlay relevance, and seam for the new as-of week. **Never continue on the stale frontier.**

**Mandatory execution-time read-only SQL companion:** re-verifies the reconciliation frontier; authoritative
reserved total; the six commitments' `reflected_into_balance`; new `cash_commitments`/`model_week_overrides`/
`budget_rules` rows; the active-account registry (§16); and the override-inventory row-count + digest
reconciliation (§1b). Computes no capacity; touches nothing.

---

## 12. Verdict taxonomy + precedence

- **PASS-SAFE** — all inputs & controls valid; Projection B global conservative trough **≥ $6,500**.
- **PASS-UNSAFE** — all inputs & controls valid; complete; Projection B global conservative trough
  **< $6,500** (incl. the pre-transfer-breach case, `maximum_floor_safe_transfer=0`). A trustworthy negative,
  reported as a completed result, not an error.
- **HOLD** — owner-review, timing, staleness, coverage, or evidence uncertainty prevents action.
- **FAIL-STOP** — structural/integrity/completeness/input failure prevents a trustworthy calculation.

```
Precedence:  FAIL-STOP  ≻  HOLD  ≻  PASS-UNSAFE  ≻  PASS-SAFE
```
Evaluate the complete condition set first. A valid breach is PASS-UNSAFE; a breach with any HOLD condition
reports HOLD; any FAIL-STOP dominates.

---

## 13. Custom-week, duplicate-week, horizon & coverage

**Custom weeks (`is_custom`, weeks 32+):**
- **No custom row may be silently dropped.**
- A custom row **inside the approved projection horizon** becomes explicit events (§1d).
- A custom row **beyond the model endpoint** is recorded as a **known out-of-horizon item** and evaluated
  under the coverage policy; a **material** out-of-horizon flow that could affect the decision ⇒ **HOLD**
  unless the horizon is extended or the effect is conservatively bounded.

**Duplicate `model_week`:**
- Preserved at extraction; **triggers explicit adjudication**; the manifest **must not silently merge**
  duplicate weeks; **unexplained duplicate-week execution semantics = FAIL-STOP.**

**Horizon & coverage (PROPOSED policy — owner must approve/revise/reject before freeze):**
- (a) week 31 confirmed as the current authoritative model endpoint (`WD` week-31 row `index.html:940`; the
  array closes at `:941`);
- (b) the horizon from the transfer date forward contains all known material obligations affected by the
  decision;
- (c) no known material obligation immediately after week 31 makes a "safe" result misleading;
- (d) **proposed minimum coverage:** the transfer date leaves **≥ 8 weeks**, **≥ 2 paycheck cycles**, and
  **≥ 2 card-statement cycles** of modeled coverage before the horizon end.
If the approved minimum coverage is not met → **HOLD**.

---

## 14. Event ordering & conservative placement (deterministic)

1. **Exact dates** when authoritative (§2 B′ confirmations, seam evidence).
2. **Date-unknown outflows at the earliest plausible position** (week start).
3. **Date-unknown inflows at the latest plausible position** (week end).
4. **Debits before credits** on the same date.
5. **Deterministic tie-break by manifest `event_id`** (§7).
6. **The proposed transfer at its earliest-plausible posting position.**
7. Weekends/holidays/known posting delays placed conservatively (an outflow never later than earliest
   plausible; an inflow never earlier than latest plausible).

**Reported quantities (both projections):** event-level running balance · daily trough · weekly EOW ·
**global conservative trough** (with position). **The floor test uses the lowest trustworthy result** — never
EOW-only.

---

## 15. (reserved — see §14/§13)

*Ordering and coverage are consolidated in §13–§14; this number is intentionally left as a pointer to avoid
renumbering the output schema and cross-references.*

---

## 16. Schedule-completeness reconciliation + extraction-window sequencing

**Completeness.** Reconcile across: **active-account registry (pulled fresh from the authoritative `accounts`
table by the §11 SQL companion — never from memory) · effective-schedule snapshot · budget-rules extract ·
current statements · Register · pending bank transactions · `custom_tasks` · owner confirmation.** Every
active card/residual account **included exactly once** or **explicitly excluded with evidence**.
Deterministic controls: **duplicate** (same obligation in two layers, incl. same account under two
identifiers), **omission** (active account with no forward representation), **unresolved-account**. Any
duplicate/omission/unresolved ⇒ FAIL-STOP (structural) or HOLD (evidence pending).

**Capture-week = as-of precondition (deterministic, rev-7).** `live_chk_capture_ts` **must fall within the
calendar/model boundaries of `as_of_model_week`**, and the capture-week identifier used by §5b and §5c
**must equal `as_of_model_week`**. A stale as-of frontier may **never** be paired with a later calendar
capture week. If execution crosses into another model week, **or** the reconciliation frontier changes before
freeze: invalidate the capture → regenerate the effective schedule → rerun parity (§1d) → recapture bank
evidence → re-run **both** reconciliation directions (§5b + §5c) → re-hash → re-adjudicate → reapprove where
required (§11). An unresolved capture-week / as-of mismatch is **FAIL-STOP before freeze** (test 78).

**≤24-hour capture sequence (recommended order):**
1. Capture repository/build identity (HEAD, BUILD_TS, adapter hash).
2. Extract production `model_week_overrides`, `budget_rules`, `cash_commitments`, `custom_tasks`, accounts
   registry, and other DB evidence (read-only; §1b controls; §11 companion).
3. Generate the effective-schedule snapshot (pure adapter) + budget-rules channel; run the differential
   oracle.
4. Run parity (§1d), completeness (this section), and the parity harness (§1e).
5. Capture Goal-Ledger evidence + owner classifications (§3/§3b/§4).
6. Resolve required regenerations (§11).
7. **Capture the live bank balance + pending activity last** — and the list of **checking transactions
   posted during the capture week at/before capture** (for §5c).
8. Complete **both** reconciliation directions: the capture-week event seam (§5b, schedule→bank) **and** the
   reverse bank→schedule reconciliation of posted capture-week transactions vs the entire forward schedule
   (§5c); verify the global no-double-count invariant (§5).
9. Hash the final manifest.
10. Execute immediately within the remaining validity window.

**Any post-balance regeneration that changes a forward event requires the seam and manifest to be
revalidated** (and re-hashed) before execution.

---

## 17. Automated test matrix (REQUIRED; pure manifest-in/result-out; no clock/RNG)

Grouped; **≥ 60 deterministic cases** (79 enumerated: 1–52 below + rev-5 additions 53–66 + rev-6 additions
67–75 + rev-7 additions 76–78 + rev-8 addition 79):

**Trough & transfer:** 1 no-transfer baseline (B==A); 2 transfer before trough (troughB=troughA−amt only
here); 3 transfer after an earlier trough (global governs; pre-transfer breach ⇒ PASS-UNSAFE, max-safe=0);
4 transfer exactly at the trough event; 5 same-week outflow-before-inflow (low<EOW); 6 large inflow
immediately after transfer; 7 computed-maximum verification (troughB==$6,500); 8 maximum+1¢ breach;
9 conditional-independence failure (closed form forbidden).

**Opening & seam:** 10 pending credit already in balance ($0); 11 pending credit not in balance (+once);
12 seam posted inflow removed; 13 seam posted outflow removed; 14 seam pending retained; 15 seam duplicate
inclusion ⇒ FAIL-STOP; 16 post-capture mutation outside window ⇒ FAIL-STOP.

**Double-count & channels:** 17 duplicate scheduled obligation (once, R7); 18 reflected commitment re-added
⇒ FAIL-STOP; 19 embedded reimbursement + separate credit ⇒ FAIL-STOP; 20 explicit `ct` inclusion; 21 explicit
`ca` inclusion; 22 nonzero `ct`/`ca` absent from events ⇒ R12 FAIL-STOP; 23 budget-rule zero-set (proven);
24 budget-rule one active rule incorporated; 25 budget-rule overlapping rules; 26 inactive budget rule
excluded; 27 budget-rule changed between snapshots (drift); 28 active budget rule not incorporated ⇒
FAIL-STOP.

**Set-asides (§3b):** 29 carried set-aside executed→historical; 30 carried set-aside outstanding→committed;
31 partial settlement; 32 reflected set-aside re-added ⇒ FAIL-STOP; 33 unresolved candidate ⇒ HOLD.

**Schedule semantics:** 34 override replacement (override events, not literal, not both); 35 **empty
`events_json` override falls back to literal events** (not dropped); 36 independent `ct`/`ca`/`dates`
override; 37 custom week (weeks 32+) present, not dropped; 38 duplicate `model_week` ⇒ adjudication /
FAIL-STOP if unexplained; 39 omitted active card ⇒ §16 FAIL-STOP; 40 duplicate account under two identifiers
⇒ FAIL-STOP.

**Money & identity:** 41 integer-cents validation (`707.18`, `5816.5`, `0`, allowed negative, forbidden
negative, 1-dp pad, 3-dp reject, exponent reject, malformed reject, cent-boundary accumulation); 42
event-ID stability under unchanged state + localized change on edit; 43 digest-rebinding invalidation ⇒ HOLD /
execution-mismatch FAIL-STOP.

**Drift, coverage, precedence:** 44 freeze-vs-execution snapshot differ — **classified ⇒ regenerate →
re-parity → re-hash → re-adjudicate → reapprove-where-required, then proceed; unclassified ⇒ FAIL-STOP**;
45 source-commit/BUILD_TS/adapter drift ⇒ FAIL-STOP; 46 SQL-evidence drift vs manifest (C) ⇒ FAIL-STOP/HOLD;
47 insufficient coverage (§13) ⇒ HOLD; 48 exact floor equality (650000¢) ⇒ PASS-SAFE; 49 one-cent breach
(649999¢) ⇒ PASS-UNSAFE; 50 simultaneous FAIL-STOP+HOLD+breach ⇒ FAIL-STOP; 51 equal-timestamp ordering
(debit-before-credit + `event_id` tiebreak) deterministic; 52 delayed-outflow / delayed-transfer monotonicity
(never improves the verdict).

**rev-5 additions:**
- **Seam universe (§5b / CD-1):** 53 early-posted capture-week **inflow** (expected later, posted early,
  reflected) — **proven NOT counted in both opening balance and forward schedule**; 54 early-posted
  capture-week **outflow** removed; 55 **partial** capture-week posting split (posted/reflected +
  remaining-forward, distinct identities); 56 posting known but **basis-inclusion unknown** ⇒ HOLD; 57 seam
  **event digest changed after adjudication** ⇒ invalidation (HOLD / execution-mismatch FAIL-STOP).
- **Budget-rule adjudication (§1c / R12 / FS-2):** 58 active rule in **ordinary non-override** week ⇒ included
  event; 59 active rule in **override** week ⇒ `excluded-with-reason: engine_override_week_bypass` (no event);
  60 **inflow-direction** rule in an override week ⇒ excluded (proves **no false-safe inclusion**); 61 override
  week that **independently changes `ct` while suppressing a budget rule** (bypass + independent-`ct` + R12
  together); 62 **missing** rule-week adjudication ⇒ HOLD, then FAIL-STOP if unresolved at freeze; 63 **both**
  event and exclusion for one intersection ⇒ FAIL-STOP.
- **Max-safe (§9 / MR-1):** 64 zero maximum by **post-transfer-position baseline trough below floor** ⇒
  **PASS-UNSAFE** (not FAIL-STOP), Projection A/B reconcile at $0; Projection-A-vs-B disagreement at $0 ⇒
  FAIL-STOP.
- **Identity / visibility:** 65 **equal-depth double trough** — deterministic `troughA_position` reporting;
  66 **RLS independent-visibility mismatch** (authoritative vs adapter-visible row count / ids / digests) ⇒
  FAIL-STOP. (JSON-number canonicalization cases — `0.1+0.2`, half-cent boundaries, 3-dp, exponent,
  non-finite — are enumerated under §8/test 41 and are mandatory Mode-2 artifact tests.)

**rev-6 additions (bank→schedule reverse reconciliation §5c + contradictory-evidence FAIL-STOPs):**
- 67 **cross-boundary early-posted future INFLOW (NF-1 canonical):** inflow expected model week **N+1**, bank
  posts it in capture week N **before** `live_chk_capture_ts`, included in the opening balance; §5c matches
  it against the whole horizon; the future event is excluded `already_reflected_in_opening_balance`; the
  inflow appears **exactly once** in the complete projection; **`maximum_floor_safe_transfer` is not
  overstated.**
- 68 **cross-boundary early-posted future OUTFLOW:** symmetric — future outflow posted early, in balance,
  matched, future event excluded, appears exactly once (no dropped/duplicated outflow).
- 69 **one bank txn → multiple candidate events (§5c C):** HOLD pending adjudication; unresolved ⇒ FAIL-STOP.
- 70 **one future event → multiple bank txns without decomposition (§5c F):** FAIL-STOP.
- 71 **partial early posting (§5c B):** split into already-reflected + remaining-forward, distinct
  content-bound identities, **exact cent conservation**.
- 72 **ambiguous match (§5c matching standard):** weak signals (amount-only / description-similarity /
  date-proximity / ordinal) never auto-matched ⇒ HOLD → FAIL-STOP at freeze if unresolved.
- 73 **match/adjudication digest mutation after capture (§5c H):** prior adjudication invalidated ⇒
  regenerate/re-parity/re-hash/re-adjudicate; execution-time mismatch ⇒ FAIL-STOP.
- 74 **seam contradictory evidence (§5b):** an event/bank record marked posted, evidence says it should be in
  the selected opening-balance basis, but the captured basis / bank evidence **contradicts** that inclusion ⇒
  **FAIL-STOP** (violated invariant: an item may not be treated as both reflected and unreflected; the global
  no-double-count / single-representation invariant, §5). Not resolvable by prose or ordinary HOLD.
- 75 **budget-rule contradictory engine evidence (§1c):** adapter/application evidence says the rule is
  bypassed (an override row exists) while another authoritative source / the resulting application output
  shows it applied (or vice versa) ⇒ **FAIL-STOP** — **cannot** be resolved through a prose waiver or ordinary
  HOLD.

**rev-7 additions (§5c candidate generation / D-vs-E routing / frontier alignment):**
- 76 **disposition D — identity-strong amount/direction conflict (parameterized across inflow and outflow):**
  a checking transaction posts in the capture week, included in the opening basis; bank reference /
  counterparty / classification / recurring-series identity points to **one** retained future-schedule event;
  the posted **amount differs** (or direction conflicts); the event is therefore in
  `candidate_forward_matches[]`; result = **disposition D ⇒ FAIL-STOP**; it must **not** route to E; the
  future event must **not** remain silently retained while the posted amount sits in the opening balance; no
  prose waiver or ordinary HOLD resolves it.
- 77 **disposition E — true no-match:** an in-scope posted transaction, in the opening basis; candidate
  generation evaluates the **entire retained forward schedule** (`as_of_model_week → coverage_horizon_end`)
  using **all** required signals; **no plausible candidate** exists; disposition = E; transaction stays
  **balance-only history**; **no offsetting/synthetic future event is created**; the **retained forward
  schedule is byte-identical** before and after; completeness/drift routing occurs; the global invariant
  holds (E creates **no** new schedule representation for a cash effect already in the opening balance).
- 78 **capture-week / as-of mismatch (§16 precondition):** `live_chk_capture_ts` outside `as_of_model_week`,
  or the frontier advances before freeze ⇒ invalidate → regenerate → re-parity → recapture → re-run §5b+§5c →
  re-hash → re-adjudicate; unresolved ⇒ **FAIL-STOP** (a stale as-of frontier may never pair with a later
  calendar capture week).
- 79 **disposition G — explicit one-transaction→multiple-events allocation (accepting branch + fail-closed
  twin).**
  *Passing branch:* one checking transaction posts in the capture week at/before `live_chk_capture_ts`,
  included in the selected opening-balance basis; candidate generation identifies **two or more** plausible
  retained forward-schedule events; authoritative evidence supports an **explicit allocation** across them;
  `confirmed_matches[]` records **one entry per allocated event**, each carrying `event_id` ·
  `event_content_digest` · `allocated_amount_cents` · `allocation_reason` · `expected_model_week_and_date` ·
  `resulting_disposition` · `reflected_component_id` (where applicable) · `remaining_forward_component_id`
  (where applicable). **Assertions:** Σ `allocated_amount_cents` **= the adjudicated posted amount exactly**;
  each allocated event is excluded/reduced/split **exactly once**; reflected + remaining components **= the
  original event amount exactly**; all resulting components use **distinct content-bound identities** (§7);
  the allocation graph **explicitly binds the one bank transaction to all allocated events**; no event
  participates in another reconciliation unless that participation is explicitly represented in the **same
  approved allocation graph**; the retained projection contains each cash effect **exactly once**; the global
  no-double-count invariant holds; **result = accepted disposition G.**
  *Fail-closed twin (same setup):* **any** of the following ⇒ **FAIL-STOP** — allocated amounts differ from
  the posted amount by **$0.01**; reflected + remaining differ from an original event amount by **$0.01**; an
  allocated event also participates in another reconciliation **without** an explicit allocation graph; an
  allocation entry lacks a required content digest or component identity; the same cash effect remains in the
  retained schedule after being fully reflected in the opening balance; allocation evidence is incomplete or
  contradictory. The test explicitly states: **no rounding tolerance** is allowed; **no prose waiver** is
  allowed; **ordinary HOLD is not sufficient** once a contradictory or imbalanced allocation is presented for
  acceptance; **acceptance requires exact integer-cent conservation.**

**§5c disposition A–H numbered-coverage confirmation:** A (exact match) → tests **67/68** (+ §5b analogues
53); B (partial single-event split, cent conservation) → **71**; C (multiple candidates) → **69**; D
(identity/content conflict) → **76**; E (true no-match) → **77**; F (event → multiple txns without
decomposition) → **70**; G (txn allocated to multiple events, explicit allocation graph — **accepting branch
+ fail-closed twin**) → **79**; H (digest mutation after adjudication) → **73**. Tests 69/70/71 remain the
proofs for ambiguous multiple candidates (69), prohibited unexplained multiplicity (70), and partial
single-event decomposition (71) respectively — **they are not the accepting-branch proof for G**, which is
test 79. Explicit-allocation exact integer-cent conservation (Σ allocated = adjudicated posted; reflected +
remaining = original event amount) is proven by **test 79**.

Tests are pure (manifest-in, verdict-out), deterministic, no clock/RNG.

---

## 18. Output schema (of the eventual Baseline E report)

JSON (machine) + Markdown (owner-readable), in order:
1. `execution_identity` (who/when, read-only, method + manifest hash)
2. `artifact_hash` (script) · `manifest_hash` · `snapshot_hashes` (freeze+execution) · `adapter_hash` · `budget_extract_hash`
3. `repo_build_identity` (HEAD + BUILD_TS; must match both snapshots + adapter)
4. `live_chk` — selected basis (+ documented semantics if `available`), displayed balance, capture ts
5. `balance_age` + manifest-window verdict
6. `as_of_model_week` + reconciliation-frontier verification (§11)
7. `projection_horizon` + §13 coverage-policy result + custom/out-of-horizon ledger
8. `opening_balance_reconciliation` (§5, incl. global no-double-count invariant result) · `capture_week_seam` (§5b, schedule→bank) · `bank_to_schedule_reconciliation` (§5c, bank→schedule, whole-horizon dispositions)
9. `effective_schedule_provenance` (§1a incl. override inventory + adapter/oracle parity) · `budget_rules_extract` (§1c) · `parity_result` (§1d)
10. `classification_ledger` (§3) · `carried_set_aside_ledger` (§3b) · `excluded_item_ledger`
11. `alaska_reconciliation` (§4, ledger-sourced, mutual-exclusion result)
12. `input_ledger` (A/B/C/D, signed, cited, integer cents)
13. `projectionA` — event series, synthetic checkpoint, daily trough, weekly EOW, `troughA`, `troughA_position`, `cushionA`, `baseline_capacity`
14. `projectionB` — same, with the transfer event; `troughB`, `troughB_position`, `cushionB`
15. `wendy_ira_amount_cents` / `intended_date` / `expected_posting`
16. `maximum_floor_safe_transfer` (+ closed-form-vs-bisection basis + the four precondition assertions + self-verification results at max and max+1¢)
17. `other_authorized_unexecuted_uses` · `residual_deployable_capacity` · `post_transfer_residual_capacity`
18. `operating_floor` (owner-confirmed) + any named reserve input
19. `anti_double_count_results` (R1…R14) · `schedule_completeness_result` (§16) · `parity_harness_result` (§1e)
20. `state_drift_result` (§11 enumeration + classifications + regenerations)
21. `staleness_status` · `confidence_status` · `test_suite_result` (§17)
22. `verdict` — PASS-SAFE / PASS-UNSAFE / HOLD / FAIL-STOP (§12 precedence)
23. `authorization_disclaimer` — **§19 verbatim.**

---

## 19. Authorization boundary (CPA gate)

> **A PASS-SAFE result establishes only checking-capacity safety under the frozen inputs. It does not satisfy
> the household's separate CPA-clearance requirement for the Wendy IRA (`ira_cpa_cleared`; the engine's
> `_amxHold` bypass at `index.html:3213` is a code quirk, not an authorization), and it does not authorize any
> transfer. Any transfer requires separate owner authorization, remains subject to the CPA-clearance gate,
> and remains under the operational HOLD until that HOLD is explicitly lifted.**

---

## Owner decisions required

**ADOPTED DESIGN CONTROLS — subject only to confirmation (NOT optional policy choices).** The following are
technical safety controls the design has **adopted**; the owner confirms them but may not silently waive them
(each is fail-closed): the **canonical pure adapter** (§1a); **Budget Rules support** (§1c); **no final
capacity-only mode** (§2 D); **content-bound event IDs** (§7); **exact decimal→cents handling** (§8);
**fail-closed custom-week treatment** (§13); **extraction visibility proof** (§1b). Where a control offers a
fail-safe *alternative* (e.g. a §1c channel vs a proven-zero-rules FAIL-STOP), the choice is between two
safe implementations — not whether the safety holds.

**Confirmation items before SCRIPT CONSTRUCTION (shape schema/behavior; all are adopted controls above):**
1. Budget-rules handling: §1c channel, or the proven-zero-rules FAIL-STOP alternative (both fail-safe).
2. Confirm **no** capacity-only mode.
3. Confirm the §7 event-identity scheme.
4. Custom-week / `week_num>31` handling: include-with-extended-horizon **or** FAIL-STOP — never silent drop (§13).
5. Carried-set-aside adjudication input shape (§3b) + classification routing.
6. Decimal-string→cents conversion rule (§8).
7. Extraction method: pure adapter (canonical) + differential oracle + SQL-companion **independent**
   RLS-visibility proof (§1a/§1b).

**GENUINE owner / governance decisions before FREEZE:**
1. §13 minimum-coverage policy — approve/revise/reject.
2. **Out-of-horizon treatment policy** (§13) — how a material custom week beyond week 31 is bounded or the
   horizon extended (else HOLD).
3. §5 basis — confirm `posted_current` (or supply documented `available` semantics).
4. §4 Alaska — Goal-Ledger source identity; legacy-draw status; approved dated releases.
5. §3/§3b — adjudicate each open custom task, owner-committed candidate, and set-aside; list
   `other_authorized_unexecuted_uses`.
6. CONTROL — explicit floor confirmation (**fail-closed**: unconfirmed ⇒ freeze blocked) or a named reserve.
7. §1e closed parity-difference catalogue approved.
8. §1b independent RLS visibility-proof mechanism + §8 `events_json` JSON-number canonicalization — both
   **required Mode-2 + freeze-readiness verification items**.

**Before EXECUTION (≤24h window, §16):**
1. Transfer amount, intended date, posting assumption.
2. Live-bank capture set (balance, basis, timestamp, pending ledger, Bailey four-cell, Alaska +$770.95 in-basis).
3. §5b seam adjudications against the execution-time snapshot.
4. §11 drift disclosures + sign-off on all regenerations.
5. Confirmation approved Alaska releases remain intended + sequentially funded.

---

## Repository change boundary (reaffirmed)

This design creates/updates draft documentation only. No frozen Baseline A/B/C/D artifact, production SQL,
migration, schema, application behavior, model calculation, `index.html`, production data, or AU-11 artifact
is modified. No executable Baseline E artifact (adapter/snapshot/budget-extract/manifest/script/tests/harness)
is created yet. Nothing is committed by drafting this file.
```
Reconfirm: Baseline E not executed · checking capacity not calculated · no Wendy-IRA result · no transfer
authorized · no SQL executed · no production/staging mutation · no script or manifest created · operational
HOLD active.
```
