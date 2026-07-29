# DEFECT G-1 — `getCurrentWeek()` depends on uncontrolled runtime/browser timezone

**Status: OPEN. Local, uncommitted. Application NOT modified. Remediation authorized (owner 2026-07-29) but DEFERRED.**
**Severity: low-to-moderate (UI cursor correctness; latent coupling risk). Not a Baseline E parity defect.**

Filed from the Baseline E adapter differential-oracle gate (see `docs/baseline-e-adapter-differential-oracle.md`,
verdict: PARITY PASS WITH NON-BLOCKING CONDITIONS). By owner ruling (2026-07-29, option c), `getCurrentWeek()` is
**excluded from the evidence-placement parity surface** and tracked here as a separate application defect.

---

## 1. Exact location

- **Function:** `getCurrentWeek()`
- **File / line:** `index.html:3441`
- **Source (verbatim):**
  ```js
  function getCurrentWeek(){const s=new Date(2026,5,7);const t=new Date();t.setHours(0,0,0,0);s.setHours(0,0,0,0);const d=Math.floor((t-s)/864e5);if(d<0)return 1;return Math.min(Math.floor(d/7)+1,31);}
  ```
- **Callers:** `index.html:3442` (`const currentW=getCurrentWeek()`), `index.html:3457` (`let activeW=getCurrentWeek()`).

## 2. Defect

`getCurrentWeek()` derives the model "current week" from `new Date()` (the **system clock**) and
`new Date(2026,5,7)` / `setHours(0,0,0,0)` (**process/browser-local** midnight). Because it is **midnight-anchored**
in local time (unlike the noon-anchored, calendar-pure `dateToModelWeek()`), the computed week can differ by
timezone for the same absolute instant near a local-midnight boundary.

### Same-instant witness (deterministic, reproduced by `baseline-E/parity/run-parity.mjs`)

Instant `2026-06-14T03:30:00.000Z`:

| Process timezone | `getCurrentWeek()` result |
|---|---|
| America/New_York | **1** |
| UTC | **2** |
| Asia/Kolkata | **2** |
| Pacific/Kiritimati | **2** |

The same wall-clock moment yields week 1 in ET and week 2 in UTC/eastward zones.

## 3. Current blast radius

- **Confirmed:** `getCurrentWeek()` **does not feed evidence placement.** Transactions, reconciliations,
  obligations, candidates, graph events, allocations, coverage, and capacity inputs are placed by
  `dateToModelWeek()` (`index.html:10829`), which is **noon-anchored, calendar-pure, and proven timezone-invariant**
  across four zones in the parity gate.
- **Full reach of the cursor (F-2, per independent review) — none of these place evidence, but they are more than a
  passive indicator:**
  - **UI current-week indicator / default active week:** `currentW`/`activeW` (`index.html:3442`, `:3457`).
  - **Scenario-commit default week:** `currentW` is the *default* `scenarioState.weekNum` (`:11034`, `:11155`);
    `commitScenario` (`:11043-11063`) persists a `model_week_overrides` row **at the operator-confirmed week**. The
    clock supplies only a default — the week is user-selectable and shown in the confirm modal (`:11096`) — so a
    wrong-TZ default is corrigible by the operator, not a silent placement.
  - **Advisory allocation reads:** `getGoalFunded` (`:6334`, `:6339`) reads snapshots "as of `currentW`", feeding
    the **display-only** allocation engine `runEngine` (`:6357-6381`) and `getNextDollarRec` (`:5041`, `:5044`);
    `engineResult` is rendered, never persisted, and never feeds Baseline E.
- Baseline E never calls `getCurrentWeek()` and is unaffected.

## 4. Risk

- **Inconsistent UI current-week indication** for users whose browser timezone is not America/New_York, especially
  around local midnight — the app could highlight the wrong "this week" row.
- **Browser-location-dependent behavior** — two users viewing at the same instant may see different current weeks.
- **Latent coupling risk** — if any future logic begins deriving placement/scheduling decisions from the cursor
  value (instead of `dateToModelWeek()`), the timezone-sensitivity would silently leak into evidence handling. The
  scenario-commit default week (§3) is the nearest existing coupling: today it is operator-confirmed, but a future
  path that committed at `currentW` **without** operator confirmation would turn this cursor defect into a
  placement defect.

## 5. Required remediation (authorized 2026-07-29; DEFERRED — do NOT apply under the current authorization)

1. **Pin current-week determination to America/New_York calendar semantics** (same contract as Baseline E's
   `America/New_York:local_calendar_date:v1`), e.g. compute "today" via
   `Intl.DateTimeFormat('en-CA',{timeZone:'America/New_York', …})` rather than local `new Date()` / `setHours`.
2. **Preserve the existing model anchor and week-band rules** — epoch Jun 7 2026, week 1..31, `d<0 ⇒ 1`,
   `min(…,31)` cap. Only the timezone basis changes; week numbering and clamping must be identical.
3. **Add deterministic tests across multiple process timezones** (UTC, America/New_York, a non-US zone, and an
   extreme zone such as Pacific/Kiritimati) asserting `getCurrentWeek()` returns the **same** week for a given
   pinned instant regardless of process TZ — mirroring the placement TZ-invariance already proven for
   `dateToModelWeek()`.

## 6. Constraints on remediation

- Requires **separate owner authorization to modify `index.html`**. Not covered by the parity-gate authorization.
- Must not alter frozen rev-6.1, Baseline E canonicalization, or the pinned America/New_York contract.
- Recommend pairing with a check that no other code path consumes `getCurrentWeek()` for placement before/after
  the change.
