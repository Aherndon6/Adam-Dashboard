# Baseline E Adapter Differential-Oracle vs Financial OS Runtime Date & Model-Week Semantics

**Status: LOCAL, UNCOMMITTED. Read-only. No live system touched.**
**Gate verdict (owner-ruled 2026-07-29): 2 — PARITY PASS WITH NON-BLOCKING CONDITIONS — SAFE FOR NEXT BEFORE-LIVE GATE.**

> **Owner ruling (2026-07-29, option c).** `getCurrentWeek()` is ruled **out of the evidence-placement parity
> surface**: it is a UI/current-week cursor that places no transaction, reconciliation, obligation, candidate,
> graph event, allocation, coverage, or capacity input. The application evidence-placement oracle is
> `dateToModelWeek()`, which was proven timezone-invariant and in full parity across UTC / America/New_York /
> Asia/Kolkata / Pacific/Kiritimati with zero placement mismatches and all mandatory mutations caught. Baseline E
> was **not** changed to reproduce `getCurrentWeek()`'s behavior; the pinned America/New_York contract remains
> authoritative and unchanged. **Finding G-1 is excluded from this gate's parity surface and remains an OPEN,
> separately-tracked application UI/runtime defect** (`docs/get-current-week-timezone-defect.md`). This verdict
> does **not** authorize live execution. The prior recommendation (verdict 4 — fail-stop for owner decision) was
> the correct pre-ruling posture; the owner has now made that scope decision.

This gate proves whether Baseline E interprets dates, effective dates, and model-week placement identically to the
existing Financial OS application (`index.html`) before Baseline E may adjudicate live financial evidence. The
application's *actual runtime code* is the oracle: the relevant functions are extracted **verbatim** from
`index.html` and executed in a sandbox — not restated from memory.

---

## 1. Starting-state verification (all PASS)

| Assertion | Expected | Observed |
|---|---|---|
| repository | Adam-Dashboard | Adam-Dashboard |
| branch | main | main |
| HEAD | `f4c22674ded0bda14634d073206ed17453941476` | identical |
| local == origin/main | synced | synced |
| working tree | clean (before this gate) | clean |
| Baseline E suite | 150/150 | 150/150 |
| index.html SHA-256 | `162f4caa5fb2cfc865389e070df3905079e9d24a766f91e3f404f21d9620309c` | identical — independently recomputed (`shasum -a 256`) by the author and by the Fable reviewer, **and now enforced fail-closed in code** (F-1 CLOSED): `app-oracle.mjs` calls `assertIndexHtmlIntegrity()` before any extraction/execution and throws `OracleIntegrityError` (with expected+actual) on any drift. |
| frozen A/B/C/D SQL | unchanged | unchanged |

No starting-state hard-stop.

---

## 2. Application functions & dependencies reviewed (Phase 1 dependency map)

The application has **two distinct date→model-week mechanisms**, and only one is an evidence-placement oracle.

### 2a. `dateToModelWeek(dateStr)` — the EVIDENCE-PLACEMENT oracle
- **Location:** `index.html:10829-10834`.
- **Input:** bare calendar date string `YYYY-MM-DD` (from an `<input type="date">`, pre-validated by `isValidISODate`).
- **Output:** integer model week `1..31`, or `null` if outside the band.
- **Body:** `new Date(y, m-1, d, 12,0,0)` (local **noon**), banded against `_BR_START`/`_BR_END`, week = `floor((dt-_BR_START)/604800000)+1`.
- **Constants:** `_BR_START = new Date(2026,5,7,12,0,0)` (`index.html:10788`), `_BR_END = new Date(2027,0,9,12,0,0)` (`:10789`), `_BR_END_STR='2027-01-09'` (`:10790`).
- **Call graph / callers:** `buildBudgetRuleContext` (`:10891`, via `generateOccurrenceDates` → validated occurrence dates) and the What-If calculator (`:10957`, gated by `!whatIfState.date` and the date-picker). **Both callers feed only validated `YYYY-MM-DD`.**
- **Timezone/DST:** uses browser-**local** `Date` constructors, but is **noon-anchored** at both endpoints, so any ≤1h DST offset is absorbed and the result is a **pure function of the calendar-date string** — empirically timezone-invariant (§9).
- **Leniency note:** `dateToModelWeek` itself does **not** validate (it would silently roll `2026-02-30` → March). It is always fronted by `isValidISODate` (`index.html:10792-10797`, exact component round-trip). The app's date-**acceptance** oracle is therefore `isValidISODate`, which matches Baseline E's strict `parseCanonicalDateTime`.

### 2b. `getCurrentWeek()` — the "current week" CURSOR (NOT a placement function)
- **Location:** `index.html:3441`; callers `:3442` (`currentW`), `:3457` (`activeW`).
- **Body:** `s=new Date(2026,5,7); t=new Date(); t.setHours(0,0,0,0); s.setHours(0,0,0,0); d=floor((t-s)/864e5); d<0?1:min(floor(d/7)+1,31)`.
- **Dependencies:** the **system clock** (`new Date()`) **and** the **process/browser timezone** (local-midnight anchoring). **Midnight-anchored** (not noon), so it is **not** calendar-pure.
- **Role:** UI "you are here" marker + default active week. It **does not place any transaction, obligation, transfer, or evidence.** It never feeds Baseline E.

### 2c. Functions searched for but NOT governing evidence date placement
- **`reconEffectiveWD()`** (`index.html:2949-2965`): a **schedule-override merge** (weekly delta application), keyed by action id / week integer — **no date parsing, no timezone, no model-week-from-date.** Not a date oracle.
- **`getWeekStartDate(n)`** (`:10028`): week integer → display `Date` (`new Date(2026,5,7+(n-1)*7)`); label formatting only.
- **`generateOccurrenceDates` / `addMonthsToDateStr` / `pinnedMonthlyDateStr`** (`:10837+`): recurrence expansion via **integer string math** (never `setMonth`), producing validated `YYYY-MM-DD` fed to `dateToModelWeek`.
- **`toLocaleDateString` sites** (`:3497`, `:9872`, `:11740`, `:11860`): **display** formatting of `recorded_at` only; never placement.
- **Cleared/pending, reconciliation, card-payment, transfer placement:** all are **application state / category** concerns; none alters the date→week computation. Confirmed: no `America/New_York`, `timeZone`, or `Intl.DateTimeFormat` anywhere in `index.html` (only browser-local and display-locale calls).

**No guessing was required; the runtime logic isolates cleanly. No Phase-1 hard-stop.**

---

## 3. Oracle design (`baseline-E/parity/app-oracle.mjs`)

- Reads `index.html`, then **fail-closed-enforces the pinned whole-file SHA-256** via `assertIndexHtmlIntegrity()`
  **before any extraction or execution** (F-1 CLOSED — `OracleIntegrityError` with expected+actual on drift), then
  **brace-matches and extracts the verbatim source** of `_BR_START`, `_BR_END`, `_BR_END_STR`, `isValidISODate`,
  `dateToModelWeek`, `getWeekStartDate`, `getCurrentWeek`. Each fragment's SHA-256 and the whole-file hash are also
  recorded in `EXTRACTION`. The guard is exercised by a positive test (pinned file accepted + oracle builds) and a
  negative test (one-byte-modified **scratch** copy rejected before execution; repo `index.html` untouched).
- Instantiates them with `new Function('Date', <verbatim source>)`, injecting a **sandbox `Date`** whose no-arg
  form returns a **caller-pinned instant** (so `getCurrentWeek()` never reads the real clock) and whose all other
  forms delegate to the real `Date` (honoring the process TZ, which the harness varies deliberately).
- **Not a reimplementation:** the function bodies are lifted byte-for-byte. If extraction cannot isolate the exact
  source, the module throws (Phase-2 hard-stop). No writes, no network, no Supabase, no state mutation, no clock read.

## 4. Adapter design (`baseline-E/parity/adapter.mjs`)

- Maps one canonical synthetic fixture into **(A)** the app-oracle input (bare `YYYY-MM-DD`) and **(B)** the
  Baseline E input (canonical UTC instant → ET values via the **real** `canon.mjs`). Every transformation is
  recorded in `transforms[]`; malformed fixture *structure* is rejected deterministically (`AdapterRejection`).
- **Explicit parity contract (documented, not hidden):** the application has **no timestamp→calendar-date
  truncation** in its placement path — it trusts the picker string. Baseline E fixes the derivation to
  `America/New_York:local_calendar_date:v1` (`canon.etLocalDate`). The adapter therefore applies **ET truncation**
  to produce the app's calendar-date input. The differential then proves the app's **week/band placement of that
  ET date** agrees with Baseline E's independent placement, under every timezone.
- **Independent Baseline E reference** (`beRefModelWeek`): ET-truncate, then **pure UTC-integer calendar math**
  banded to the shared epoch (Jun 7 2026) and endpoint (Jan 9 2027). No local-time `Date` arithmetic → TZ-invariant
  by construction. This is a *different implementation* from the app's local-noon arithmetic, so agreement is a
  real cross-check, not a tautology.

---

## 5. Fixture inventory (`baseline-E/parity/fixtures.mjs`) — 35 synthetic `PX-NN`

PX-01 ordinary · PX-02 UTC-midnight · PX-03 ET-midnight · PX-04 spring-forward · PX-05 fall-back · PX-06 leap day ·
PX-07 month-end · PX-08 year-end · PX-09 week-start · PX-10 week-end · PX-11 1ms-before-boundary ·
PX-12 1ms-after-boundary · PX-13 −14 exact · PX-14 +14 exact · PX-15 −15 · PX-16 +15 · PX-17 cleared ·
PX-18 uncleared · PX-19 reconciled-week · PX-20 unreconciled-week · PX-21 transfer-debit · PX-22 transfer-credit ·
PX-23 card-statement · PX-24 card-payment · PX-25 goal-disbursement · PX-26 reimbursement-inflow ·
PX-27 interval-exact-day · PX-28 interval-two-day · PX-29 invalid-date · PX-30 missing-timezone ·
PX-31 ambiguous-fallback · PX-32 nonexistent-springforward · PX-33 UTC≠ET-daycount · PX-34 week-31-cursor ·
PX-35 outside-horizon.

---

## 6. Differential results by fixture (system-TZ pass; identical under all zones)

| Fixture | ET date | app_wk | be_wk | classification |
|---|---|---|---|---|
| PX-01 | 2026-07-15 | 6 | 6 | EXACT_MATCH |
| PX-02 | 2026-07-14 | 6 | 6 | EXACT_MATCH |
| PX-03 | 2026-07-15 | 6 | 6 | EXACT_MATCH |
| PX-04 | 2026-03-08 | null | null | EXACT_MATCH |
| PX-05 | 2026-11-01 | 22 | 22 | EXACT_MATCH |
| PX-06 | 2028-02-29 | null | null | EXACT_MATCH |
| PX-07 | 2026-07-31 | 8 | 8 | EXACT_MATCH |
| PX-08 | 2026-12-31 | 30 | 30 | EXACT_MATCH |
| PX-09 | 2026-08-09 | 10 | 10 | EXACT_MATCH |
| PX-10 | 2026-08-15 | 10 | 10 | EXACT_MATCH |
| PX-11 | 2026-08-15 | 10 | 10 | EXACT_MATCH |
| PX-12 | 2026-08-16 | 11 | 11 | EXACT_MATCH |
| PX-13 | 2026-08-01 | 8 | 8 | EXACT_MATCH (ET diff −14 inclusive) |
| PX-14 | 2026-08-29 | 12 | 12 | EXACT_MATCH (ET diff +14 inclusive) |
| PX-15 | 2026-07-31 | 8 | 8 | EXACT_MATCH (−15 excluded) |
| PX-16 | 2026-08-30 | 13 | 13 | EXACT_MATCH (+15 excluded) |
| PX-17 | 2026-09-10 | 14 | 14 | EXACT_MATCH (cleared) |
| PX-18 | 2026-09-10 | 14 | 14 | EXACT_MATCH (uncleared; == PX-17) |
| PX-19 | 2026-06-20 | 2 | 2 | EXACT_MATCH (reconciled-week) |
| PX-20 | 2026-06-20 | 2 | 2 | EXACT_MATCH (== PX-19) |
| PX-21 | 2026-09-20 | 16 | 16 | EXACT_MATCH (transfer debit) |
| PX-22 | 2026-09-20 | 16 | 16 | EXACT_MATCH (transfer credit; == PX-21) |
| PX-23 | 2026-10-15 | 19 | 19 | EXACT_MATCH (card statement) |
| PX-24 | 2026-10-20 | 20 | 20 | EXACT_MATCH (card payment) |
| PX-25 | 2026-11-05 | 22 | 22 | EXACT_MATCH (goal disbursement) |
| PX-26 | 2026-11-10 | 23 | 23 | EXACT_MATCH (reimbursement) |
| PX-27 | 2026-07-01 | 4 | 4 | EXACT_MATCH (interval exact day) |
| PX-28 | 2026-07-01 | 4 | 4 | EXACT_MATCH (interval two-day) |
| PX-29 | — | reject | reject | EXACT_MATCH (both fail-closed) |
| PX-30 | — | reject | reject | EXACT_MATCH (both fail-closed) |
| PX-31 | 2026-11-01 | 22 | 22 | EXACT_MATCH (ambiguous fall-back; deterministic) |
| PX-32 | 2026-03-08 | null | null | EXACT_MATCH (nonexistent spring-forward; deterministic) |
| PX-33 | 2026-08-15 | 10 | 10 | EXACT_MATCH (ET truncation decides; UTC would be wk11) |
| PX-34 | — | — | — | **SEMANTIC_MATCH_REPR_DIFF** (band edges exact; `getCurrentWeek` cursor is clock+TZ dependent) |
| PX-35 | 2027-02-01 | null | null | EXACT_MATCH (outside horizon) |

**Totals: 34 EXACT_MATCH, 1 SEMANTIC_MATCH_WITH_REPRESENTATION_DIFFERENCE, 0 MISMATCH, 0 BASELINE_E_FAIL_STOP.**

---

## 7. Exact mismatches

**None on the evidence-placement surface.** `app_wk === be_wk` for all 33 placement fixtures across all four
timezones; both reject fixtures fail-closed on both sides.

## 8. Classification of each mismatch

No mismatches to classify. The single non-EXACT disposition (PX-34) is a **SEMANTIC MATCH WITH REPRESENTATION
DIFFERENCE**, and it carries the governance flag below — the representation difference (clock+TZ-dependent cursor)
is *not* on the candidate-generation / graph-identity / classification / allocation / coverage / capacity path,
because `getCurrentWeek` never places evidence.

### Governance finding (Phase 6) — returned for OWNER DECISION
- **Finding G-1:** `getCurrentWeek()` (`index.html:3441`) **depends on the uncontrolled system timezone and the
  system clock.** Witness (same instant `2026-06-14T03:30:00.000Z`): returns **week 1** under `America/New_York`
  but **week 2** under `UTC`, `Asia/Kolkata`, and `Pacific/Kiritimati`.
- This **literally triggers** the Phase-6 unconditional hard-stop: *"runtime behavior depends on browser locale or
  uncontrolled system timezone."*
- **Source classification:** *undocumented/uncontrolled application behavior* (not a Baseline E defect, not an
  adapter defect). It is **not** the evidence-placement oracle; `dateToModelWeek` is deterministic and TZ-invariant.
- **Why this is returned, not self-adjudicated:** the hard-stop list is directive and unconditional. Whether
  `getCurrentWeek` is *in scope* for "the date/model-week interpretation Baseline E must match" is a **scoping
  decision reserved to the owner.** Baseline E was **not** changed to copy or accommodate this behavior.
- **No parity change would be safe otherwise:** matching `getCurrentWeek`'s TZ-dependence would require Baseline E
  to abandon its pinned `America/New_York` contract — i.e., weaken determinism / canonicalization — which is itself
  a listed hard-stop. So the only acceptable resolutions are owner-side: **(a)** rule `getCurrentWeek` out of scope
  for this gate (it is a UI cursor, not evidence placement), and/or **(b)** authorize a separate remediation that
  pins `getCurrentWeek` to `America/New_York` in the application.

---

## 9. DST & timezone results

- **Placement TZ-invariance (empirical):** the placement fingerprint (concatenated `PX-NN:week` over all placement
  fixtures) hashes **identically** under `UTC`, `America/New_York`, `Asia/Kolkata`, and `Pacific/Kiritimati`
  (UTC+14). `placement_timezone_invariant: true`, `any_mismatch: false`, `repeatable: true`
  (`baseline-E/parity/parity-results.json`).
- **DST:** spring-forward (PX-04/PX-32) and fall-back (PX-05/PX-31) truncate deterministically to the intended ET
  calendar date; noon-anchoring in `dateToModelWeek` absorbs the post-Nov-1 EST offset with no week drift.
- **Cursor TZ-sensitivity:** the sole TZ-sensitive witness is `getCurrentWeek` (Finding G-1); no placement fixture
  is TZ-sensitive.

## 10. Boundary-inclusivity results
- Model-week boundary is **inclusive-start**: PX-11 (1ms before ET-midnight) → wk10; PX-12 (ET-midnight) → wk11.
- Band endpoints **inclusive**: `2027-01-09` → wk31; `2027-01-10` → null (both sides).
- ±14 ET-day proximity **inclusive on both edges**: −14/+14 within, −15/+15 excluded.

## 11. Cleared/pending placement results
- Placement is **invariant** to cleared/pending on both sides: PX-17==PX-18, PX-19==PX-20, PX-21==PX-22.

## 12. Mutation results (all six produce a deterministic parity FAILURE — as required)
| Mutation | Induced defect | Deterministic divergence |
|---|---|---|
| 1 week-start | epoch +1 day | weeks shift; diverges at PX-09/PX-10 |
| 2 timezone | truncate as UTC not ET | date diverges (PX-02 Jul-15≠Jul-14); week diverges (PX-33 wk11≠wk10) |
| 3 ±14 inclusivity | make exclusive (`<14`) | PX-13/PX-14 flip within→outside |
| 4 DST | fixed −5 offset (ignore EDT) | PX-12 date Aug-15≠Aug-16 → wk10≠wk11 |
| 5 cleared/pending | placement `+1` when cleared | breaks invariance at PX-17/PX-19/PX-21 |
| 6 interval boundary | end-exclusive (executable mutant) | end-boundary day flips member→non-member at PX-27/PX-28 (interval valid; not a validation reject) |

## 13. Test totals (after F-1/F-3/F-5 hardening)
- Existing Baseline E suite: **150/150** (unchanged — no regression).
- New parity suite (`parity-differential.test.mjs`): **20/20** (18 original + 2 F-1 hash-guard tests; mutation-6
  strengthened in place).
- Combined: **170/170**, 0 fail / 0 skipped / 0 todo.

## 14. Files created (all local, uncommitted)
- `baseline-E/parity/app-oracle.mjs` (oracle — verbatim extraction + sandbox)
- `baseline-E/parity/adapter.mjs` (adapter + Baseline E reference)
- `baseline-E/parity/fixtures.mjs` (35 synthetic fixtures)
- `baseline-E/parity/differential.mjs` (differential engine + classification)
- `baseline-E/parity/run-parity.mjs` (TZ-matrix + repeatability runner)
- `baseline-E/parity/parity-results.json` (machine-readable results)
- `baseline-E/test/parity-differential.test.mjs` (parity suite + mutation probes)
- `docs/baseline-e-adapter-differential-oracle.md` (this report)

## 15. Working-tree status
The artifacts in §14 appear as **untracked**; additionally **`CODEX_STATUS.md` is modified** (the 2026-07-29c
currency note, session-protocol-sanctioned). Nothing staged, committed, or pushed. HEAD `f4c22674…` unchanged.
`index.html` SHA-256 unchanged (`162f4caa…`) — the application was read, never modified. `baseline-E/src/`
(incl. `canon.mjs`), frozen rev-6.1, and canonicalization untouched.

### Independent Fable review (2026-07-29) — verdict: APPROVE WITH NON-BLOCKING CONDITIONS → all conditions CLOSED
The oracle/adapter evidence was independently reviewed (read-only). Verdict **2 — APPROVE WITH NON-BLOCKING
CONDITIONS**. All eight review dimensions passed on substance (extraction fidelity, adapter contract, fixture
sufficiency, TZ matrix reproduced, mutation adequacy, and **the exclusion of `getCurrentWeek()` from the
evidence-placement surface confirmed legitimate** — no overlooked path lets any clock/TZ-dependent function place
evidence, candidates, allocation, coverage, or capacity). Owner-authorized hardening pass (2026-07-29) closed the
code conditions:
- **F-1 (moderate) — CLOSED:** pinned `index.html` hash is now **fail-closed-enforced** in `app-oracle.mjs`
  (`assertIndexHtmlIntegrity()` before extraction/execution; `OracleIntegrityError` with expected+actual). Proven by
  a positive test (pinned accepted, oracle builds) and a negative test (one-byte scratch copy rejected before
  execution; repo file untouched).
- **F-2 (low) — CLOSED:** G-1 blast radius corrected in `docs/get-current-week-timezone-defect.md` (scenario-commit
  default week + advisory allocation reads; both operator-confirmed or display-only).
- **F-3 (low) — CLOSED:** mutation-6 now **runs an executable end-exclusive interval mutant** against a candidate
  exactly on the interval end boundary (PX-27 single-day; PX-28 end), proving deterministic divergence, with a
  guard that the interval is valid (not caught first by an unrelated validation gate).
- **F-4 (info) — CLOSED:** §15 acknowledges the modified `CODEX_STATUS.md`.
- **F-5 (info) — CLOSED:** dead ternary at `differential.mjs` collapsed to `CLASS.EXACT` (no result/fingerprint/
  verdict change; fingerprint re-verified byte-identical).

## 16. Specification-to-runtime mapping
| Baseline E (rev-6.1) construct | Runtime counterpart | Parity |
|---|---|---|
| `canon.etLocalDate` — `America/New_York:local_calendar_date:v1` | app has **no** truncation; adapter supplies ET (contract) | contract-defined; downstream week agrees exactly |
| model week from date | `dateToModelWeek` (`:10829`) | EXACT, TZ-invariant |
| retained horizon (weeks 1..31) | band `_BR_START.._BR_END` (Jun 7 2026 .. Jan 9 2027) | EXACT |
| strict date acceptance (`parseCanonicalDateTime`) | `isValidISODate` (`:10792`) | EXACT (both reject Feb-30, non-leap Feb-29, rollovers) |
| ±14 ET-day candidate proximity | *no application counterpart* | Baseline-E-only (APPLICATION AMBIGUITY at attribute level; app never does candidate recall) |
| `canonExpectedDateInterval` | *no interval type*; app bands each endpoint | endpoints band identically |
| — | `getCurrentWeek` cursor (`:3441`) | **not matched — Finding G-1 (owner scope decision)** |

## 17. Mismatch register (unresolved)
| # | Item | Type | Disposition |
|---|---|---|---|
| G-1 | `getCurrentWeek()` clock+TZ dependence | undocumented/uncontrolled application behavior | **Owner-ruled 2026-07-29: EXCLUDED from the evidence-placement parity surface** (UI cursor). Remains an **OPEN application defect** tracked in `docs/get-current-week-timezone-defect.md`; ET-pinning remediation authorized but **deferred** (not applied under this gate). Baseline E unchanged. |

There are **no open items on the evidence-placement surface.** The single register item (G-1) is out of scope
for this gate by owner ruling and is tracked separately.

---

## 18. Verdict

**2 — PARITY PASS WITH NON-BLOCKING CONDITIONS — SAFE FOR NEXT BEFORE-LIVE GATE** (owner-ruled 2026-07-29).

**Scope boundary applied.** The parity pass covers, and only covers, the evidence-placement surface:
`dateToModelWeek()`; effective calendar-date interpretation; model-week placement; model-horizon boundaries; ±14
local-calendar-day inclusivity; DST spring-forward and fall-back behavior; cleared/pending placement invariance;
expected-date interval boundaries; retained-horizon placement behavior. `getCurrentWeek()` (the UI current-week
cursor) is **out of scope** by owner ruling.

**Non-blocking condition.** G-1 (`getCurrentWeek()` timezone dependence) is **not a Baseline E parity defect**; it
is a separately-tracked application UI/runtime cursor defect (`docs/get-current-week-timezone-defect.md`).
Remediation (ET-pinning) is owner-authorized but deferred; no application change was made under this gate.

Supporting evidence: 34 EXACT / 1 semantic representation difference (the out-of-scope cursor) / **0
evidence-placement mismatches**; timezone-invariant placement fingerprint; repeatable results; **168/168** tests;
all six mandatory mutations caught.

This verdict authorizes **nothing** operationally: no production access, no staging, no live Baseline E execution,
no capacity calculation, no Wendy-IRA determination, no transfer. The operational HOLD remains active. The next
gate is an independent Fable review of the oracle/adapter evidence.
