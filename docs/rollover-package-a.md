# 2027 Rollover Package A: test and evidence infrastructure

| | |
|---|---|
| Governing specification | `docs/rollover-2027-spec.md`, frozen v2.1 (commit `9949225`, SHA-256 `b8443406…cf57`) |
| Scope | Test and evidence infrastructure only. No product file changes (`index.html`, goldens, SQL, specs untouched). |
| Owner authorization | Package A, 2026-10-07 |
| OWNER HOLD | ON (`GOAL_FUNDING_OWNER_AUTHORITY` = `NOT_AUTHORIZED`) |

## 1. What Package A adds

| Requirement | Mechanism | Where |
|---|---|---|
| A. Frozen 2026 composition | The legacy suites bind `WD` to the frozen 2026 source: `WD_2026_FROZEN` once the product defines it, otherwise `WD`, which before the rollover is that source. The golden re-derive also pins the 2026 goal inputs (hard-coded fallback registry) and empties overrides and snapshots explicitly. | `test_regression.js`, `test_a1b.js`, `test_d1.js`, `test_release_a.js`, `test_release_b.js`, `tools/capture-golden-master.js` |
| B. Clock pinning | Static suites evaluate the product with a pinned `Date` (local noon on `HFOS_TEST_DATE`, default `2026-10-07`). Explicit-argument dates are untouched. Browser contexts install the Playwright clock at the same start time; time then flows. | `tools/rollover-test-kit.js` (`clockStubSource`), the five static suites, `e2e.js` |
| C. Suite structure | `test_rollover.js` (gated in `scripts/pre-push.hook`) holds Package A tests and later rollover contract tests. Every frozen §13 test is registered with its owning package in `fixtures/rollover/contract-registry.json`; the suite fails if the registry and the frozen spec diverge. A fail-closed completion check (section 2) stops a package from being accepted while it owns a PENDING contract. | `test_rollover.js`, `fixtures/rollover/contract-registry.json`, `tools/rollover-contracts.js`, `scripts/pre-push.hook` |
| D. Legacy classification | Section 3 below. | this document |
| E. Future-plan harness | `compositionFor(Y, src)` composes frozen weeks 1-30 plus plan blocks and truncates at plan Y's final week; `synthPlanBlock` makes synthetic, self-consistent, non-household rows; `cal` is an independent §3 period oracle. | `tools/rollover-test-kit.js` |
| F. Rollback evidence | §18 business-and-control fingerprint with the OD-1 exclusion list frozen at exactly `goal_registry.updated_at`; RB-2 baseline comparison with enumerated household history and §16 step 15(b) manifest status changes; RB-1 write-set check. NB-5 checkpoint-C equivalence is a separate function with an explicit generated-column list. | `tools/rollover-fingerprint.js` |
| G. Function-body evidence | Builds and compares captures of `pg_get_functiondef` output (definition hash, security definer, config, owner, ACL). Never connects to a database; tested on fixtures. | `tools/rollover-function-capture.js` |
| H. Capture tool plan support | `--plan 2026` (default) re-derives the protected fixture unchanged; `--check` compares without writing; `--plan Y` with synthetic inputs derives plan Y on its own composition and refuses the protected 2026 fixture path. | `tools/capture-golden-master.js` |
| I. N-9 | `checkHelperRevokes` asserts that each new helper is created and explicitly revokes EXECUTE from PUBLIC, anon and authenticated, with no client grant. Registered as `X-N9` for the server package. | `tools/rollover-function-capture.js` |
| J. Protected pins | Recomputes the protected-function pins with the release method and compares them with a baseline file. | `tools/protected-pins.js` |

Usage:

```bash
node test_rollover.js
```

```bash
HFOS_TEST_DATE=2027-01-03 node test_regression.js
```

```bash
node tools/capture-golden-master.js --check
```

```bash
node tools/protected-pins.js ~/Herndon-Financial-OS-Evidence/d1-release-2026-10-06/package/protected-49-baseline-d1.txt
```

## 2. Package completion gate (owner A-1)

A package is complete only if no registry entry it owns is PENDING and every ACTIVE entry it owns resolves to a real test definition (`impl` = `<file>#<TEST-ID>`, where a `.js` file must define `test('<TEST-ID> …` and a `.md` file must have a heading with the text; a mere mention does not count). Unknown package identifiers fail closed.

Each package runs this at its own acceptance, and acceptance may not be recorded unless it exits 0:

```bash
node tools/rollover-contracts.js complete D
```

Exit 0 prints `COMPLETE`; exit 1 prints `NOT COMPLETE` and lists every PENDING or unresolved entry by ID. Activation never weakens a contract: the package writes each owned test RED against the unchanged product, implements until green, then sets the entry ACTIVE with its `impl` reference.

Current state: Package A owns 12 ACTIVE entries and is COMPLETE. Packages B, C, D, E, F and G own 4, 18, 37, 5, 7 and 2 PENDING entries and are NOT COMPLETE. The normal suite asserts this state without failing (`PKGA-DONE-6`).

## 3. Carried Gate 1 notes (not specification requirements)

- **NB-5 (rehearsal):** checkpoint-C staging equivalence for re-inserted rows must account for newly generated `created_at` (and generated identifiers) under its own comparison contract, `compareCheckpoint`, with the generated columns listed explicitly per table. It is never merged with the §18 fingerprint; `created_at` is not an OD-1 exclusion. Registered as `X-NB5`.
- **N-9 (server package):** new helper functions explicitly `REVOKE EXECUTE` from PUBLIC, anon and authenticated, because PostgreSQL grants EXECUTE on new functions to PUBLIC by default. No privileges change in Package A. Registered as `X-N9`.
- **C18 (clock-dependent test):** `5G1C1-12` fails from 2027-01-03 on today's product; Package A reproduces this deterministically (`PKGA-CLOCK-4`) and the legacy suite runs at the pinned date. Registered as `X-C18`.

## 4. Legacy test classification

Classes: **1** historical 2026 characterization, run on the frozen composition; **2** runtime behavior that must evolve for the rollover; **3** obsolete after the rollover; **4** needs an owner or spec decision.

Evidence: a scratch simulation of the post-rollover product (the schedule renamed `WD_2026_FROZEN`, a synthetic `WD_2027`, runtime `WD` composed) ran the legacy suites with the Package A binding. `test_regression.js` had exactly one failure, the source-token pin (class 2, hash unchanged); `test_a1b.js`, `test_d1.js`, `test_release_a.js` and `test_release_b.js` were fully green. Real `WD_2027` values arrive only with Package E, so class-1 status for model-output assertions is proven for synthetic data and must be re-confirmed then.

| Gate 1 finding | Location (at `9949225`) | Class | Reason / handling |
|---|---|---|---|
| Shared `WEEKS = runModel(...)` corpus | `test_regression.js` (load), `test_a1b.js` (load) | 1 | 2026 characterization; the suites now bind the frozen composition before computing it |
| `WEEKS[30]`, "week 31 is last", `w31 = last element` idioms | `test_regression.js` model-output tests (e.g. W31 and last-week checks) | 1 | On the frozen 31-row composition, week 31 is the legacy row the assertions were written for |
| Floor-violation sets, lowest checking, negative-week count | `test_regression.js` floor tests | 1 | Frozen composition |
| D1 `BASE` | `test_d1.js` | 1 for the model base; 2 for rendered text that C23 changes | Package B adds the Next Dollar caveat |
| WD-content tests: card totals (`EXPECT[31]`), Disney weeks 26-31, card events tagged from week 16, rent week 31, full tagged-event census | `test_regression.js` P3c-1, rent audit, 5F tagging sections | 1 | They describe the frozen rows, which stay byte-identical; Package D repoints any direct `WD` reference to `WD_2026_FROZEN` |
| Liquidity fixture loops 15..31 | `test_regression.js` `withAmpleLiquidity`; `e2e.js` fixture | 1 (static); 2 (e2e, which runs the runtime composition) | Package D extends the e2e fixture to the runtime weeks |
| `getCurrentWeek()` in 1..31 | `test_regression.js` Section 1 | 2 | C3 removes the cap |
| Funding source assertions (`calWk:22+w.num`, `Cal Wk 23`, the 23-to-53 Funding Timeline heading) | `test_regression.js` 5G1C1 sources | 2 | C2, C17, C19 |
| Release A/B label-format tests (`Cal 43`, `Cal 50`, P20/P24 strings) | `test_release_a.js`, `test_release_b.js` | 2 | C2 label format ([B]); numeric `getCalWeek` is preserved, so most remain valid |
| AU-11 `!/WD/.test(block)` checks | `test_regression.js` AU-11 sections | 2 | Re-evaluate if C12/C13 code adds a `WD` token in those blocks |
| Protected `bh()` pins (function plus trailing text) | `test_regression.js` (11 sites), `test_a1b.js` | 1, with a constraint | Valid while `runModel`, netting and the resolver are unchanged; no new code may be inserted directly after them |
| e2e GR-2 (Savings Goals shows 2026 goals) | `e2e.js` | 1 at the pinned date | Runtime 2027 behavior is T-GL-8 |
| `5G1C1-12` clock dependence | `test_regression.js` | 1 at the pinned date | Defect reproduced in `PKGA-CLOCK-4`; fix C18 (`X-C18`) |
| Golden length 31; `runModel` length-31 sites | `test_regression.js` | 1 | Frozen composition |
| `getCalWeek(31) === 53` | `test_regression.js` Section 1 | 2 | C2 (week 31 becomes 2027 Wk 1) |
| `getWeekStartDate(31)` = Jan 3 2027 | `test_regression.js` Section 1 | 1 | Value unchanged |
| `dateToModelWeek` 2027 nulls (BR-F6, WC-A4; e2e WC-6) | `test_regression.js`, `e2e.js` | 2 | C4 extends the window |
| `_budgetAvailableMonths` count | `test_regression.js` | 2 | C4 |
| `const WD=[` source token and weeks 1-15 hash pin `a33b2076` | `test_regression.js` P3c-1 | 2 | Token becomes `const WD_2026_FROZEN=[`; the hash stays `a33b2076` (verified in the simulation) |
| SQL-file literal assertions (`<> 2026`, `BETWEEN 1 AND 31`) | `test_regression.js` 5F/5G SQL-file sections | 3 | They read historical migration files and stay true of those files; the server package brings its own assertions |
| Week-31 expected-item ID `2026mw31_kia_payment_2027_01_07` | `test_regression.js` 5F tagging | **4** | OPEN owner decision D-A1; expectation unchanged |
| `PLAN_YEAR` reference tests | `test_regression.js`, `test_release_a.js`, `e2e.js` | 2 | C16 retires `PLAN_YEAR` |
| Snapshot-eligible nine and literal count 9 | `test_regression.js`, `e2e.js` | 2 | C12, C13 |
| Hard-coded registry fallback at runtime | `test_regression.js` GR sections, `e2e.js` GR-1/3/5 | 2 | C15 (fixtures keep the list; the golden now injects it explicitly) |
| `tools/audit.js` 31-week expectation | `tools/audit.js` | **4**, dispositioned | D-A2: out of rollover scope; untouched |
| Capture tool structural guard | `tools/capture-golden-master.js` | resolved | Package A adds `--plan` |

## 5. Owner decisions

- **D-A1 (OPEN, class 4, deferred to Package D activation).** The week-31 expected-item ID test tags the frozen legacy row 31, which is reference data and never runtime data, while C7 is new runtime year derivation. The expected ID is not changed in Package A. At Package D activation the exact expectation is resolved against frozen v2.1 C7 and the applicable §13 contract. No spec redesign is authorized or expected.
- **D-A2 (owner ruling 2026-10-07: out of scope).** `tools/audit.js` stays untouched and outside the rollover; any retirement is separate cleanup work.
- **Hook installation (owner ruling: accepted).** `scripts/pre-push.hook` runs `test_rollover.js`. The local `.git/hooks` copy is installed separately after the Package A commit, using the repository's normal procedure (`bash scripts/install-hooks.sh`).
