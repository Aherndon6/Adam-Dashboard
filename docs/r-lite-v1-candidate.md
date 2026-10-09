# R-lite V1 — Statement Compare (frozen candidate, 2026-10-09)

| | |
|---|---|
| Status | **FROZEN CANDIDATE — awaiting owner authorization to push.** Not pushed, not deployed. **No real shadow run yet** (it needs separate authorization) |
| Branch | `production-line-2026q4`, on top of live `14e76ec`. Commits: `72f6012` (feature), `9672711` (mutation-gap tests), `23dc3c1` (Fable follow-ups), `d69440c` (legacy test supersession), plus docs/fixtures `2a6e2bf`, `e639429` and this record |
| Design authority | `docs/r-lite-design-proposal.md` §23 (locked by the owner, 2026-10-09) |
| Private evidence | `~/Herndon-Financial-OS-Evidence/r-lite-2026-10-09/`: real-file profiles; the read-only Register extract (private); window and real-run aggregates; RED, mutation, validation and merge preview; `renderBudget` before/after/diff; the new protected baseline |

## What ships

- **Code:** `js/r-lite.js` (an ES module; no fetch, writes, globals or logging), plus these `index.html` changes:
  - **`renderTransactions` (unprotected):** the **Statement Compare** tab (replacing the disabled "Reconciliation" placeholder) and its mount point.
  - **`_renderBudgetRecon` (unprotected):** the legacy Statement check is **retired**. The panel now explains why and points to Statement Compare; it computes nothing and never shows "Reconciled".
  - **`renderBudget` (protected), owner-authorized documentation-text-only re-pin:** 3 help bullets became 1. Pin `2a77d0ce…` → `45ab6ac7…`. It is proven identical apart from those lines, and the before/after/diff and the new baseline are in private evidence.
  - **One module mount line.**
- **Fixtures:** `fixtures/r-lite/*.qfx`, sanitized structural copies of the four institutions' real exports.

## Behaviour

**The workflow:** account, then a QFX file, then an explicit account confirmation, then the results. The parser, the MATCHED contract A–F (window −4/+3; ±7 repeated-amount veto), the effective range, the current posted balance check and the account binding are exactly as locked in §23.

- **Fail closed.** If the account's Register history isn't fully loaded, or a Register amount can't be read exactly, there are no results. Results are discarded if the history reloads, and the owner presses "Compare again".
- **No writes and no authority.** Corrections are made with the existing Register controls; the existing reconciliation process stays authoritative.

## Verification

| Check | Result |
|---|---|
| RED (before the module) | 21 domain tests failing (`red-rlite.txt`). The follow-up tests also fail on the pre-fix module (`red-fable-fixes.txt`) |
| GREEN on `d69440c` | Regression 2040/0. e2e full suite 214/0 (0 real network contact) |
| Other suites | Release A 62/0. Release B 16/0. D-1 26/0. A1b 212/0. G1 32/0. Rollover 49/0. Rollover server 25/0 |
| Protected pins | D-1 baseline 48/49: **only** `renderBudget` differs, the authorized re-pin. New R-lite baseline 49/49 |
| Golden | Identical |
| Mutation | **44/44 killed**: 39 initial + 5 for the Fable follow-ups. Every false-MATCHED attack was caught (window, guard edges and sides, uniqueness, sign, description tie-break, context rows, auto-clear) |
| Local browser acceptance | Real module on a static server, synthetic data: 6/6 PASS, nothing written |
| Fable | **APPROVE WITH NON-BLOCKING FINDINGS** (no blocking). N-1 to N-5 and N-9 fixed in `23dc3c1` |

**Superseded legacy assertions** (the owner-authorized retirement, so the guarded behaviour no longer exists):
- D-1 B-5;
- A1b D10b;
- e2e BUD-4 (legacy Statement-check arithmetic);
- e2e TX-8 (the "Reconciliation" placeholder tab);
- regression 5B-35 and 5E10-06.

Each now asserts the new, truthful behaviour.

**Recorded, not fixed:**
- **N-6:** dead legacy Statement-check state and handlers (harmless; later cleanup).
- **N-8:** a balance timestamped in a western time zone and downloaded late in the evening Eastern can read as "yesterday", so the balance check is UNAVAILABLE. That is correct fail-closed behaviour; download again.

## Expected shadow-run volume (actual module on the six real files; aggregates)

| File | Matched | Bank only | Ambiguous (bank) | of which ±7 veto | Register only |
|---|---|---|---|---|---|
| Truist, Sep (51 rows) | 39 (76%) | 9 | 3 | 1 | 18 |
| Truist, Sep 15 – Oct 9 (37) | 28 (76%) | 3 | 6 | 2 | 10 |
| AMEX Gold, closed statement (179) | 158 (88%) | 3 | 18 | 8 | 10 |
| AMEX Gold, current cycle (106) | 92 (87%) | 2 | 12 | 5 | 7 |
| Citi Costco (16) | 16 (100%) | 0 | 0 | 0 | 1 |
| Chase Disney (4) | 4 (100%) | 0 | 0 | 0 | 0 |

**±7 guard calibration.**
- **Cost:** 1–2 extra AMBIGUOUS rows per Truist file and 5–8 per AMEX file.
- **±10 instead:** adds at most one more row.
- **No guard:** would turn about 13 AMEX repeated-amount pairs back into MATCHED.
- **Conflicts:** 0 in every configuration.
- **Verdict:** the evidence shows the guard is neither too conservative nor too loose (Fable concurs).
- **Residual risk:** a lone coincidental same-amount pair whose true counterpart is missing from the Register. That stays the shadow run's job.

**Notable:** Truist September shows **18 REGISTER ONLY** rows, entries with no same-amount bank row within −4/+3. These are real exception volume for owner adjudication, for example split or combined entries, or items dated far from posting.

## Shadow run (needs separate owner authorization)

At the next real reconciliation, download a fresh QFX for Truist Checking and AMEX Gold, run Statement Compare **alongside** the normal process, and record the items in §17 of the design. No reconciliation state is written.

## December integration

- The merge preview against `rollover-package-d` shows only the `BUILD_TS` conflict.
- Merged suites: regression 2040/0; e2e 214/0; golden identical; the same two known rollover reds.
- **New December requirement:** the rollover candidate's protected baseline (D candidate v2) still pins the old `renderBudget`. Carry this re-pin (`→ 45ab6ac7…`) into the rollover baseline at integration.

## Rollback

`git revert d69440c 23dc3c1 9672711 72f6012` on `main`, then push and a household reload. This also restores the legacy panel, the help text and the original pin. No data rollback.
