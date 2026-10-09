# Release 2: Register entry assist (closed 2026-10-09)

| | |
|---|---|
| Status | **DEPLOYED — PASS · PRODUCTION ACCEPTANCE — PASS · CLOSED** (owner, 2026-10-09). Pushed `78ad6c7..3963ed1` (fast-forward); `BUILD_TS` `2026-10-09T14:54:00`; served `index.html`, `js/register-assist.js` and `js/version-check.js` byte-identical to the commit |
| Branch | `production-line-2026q4`, on top of live `78ad6c7` (Release 1) and docs `87d0d78`. Commits: `32f044d` (feature), `ea345fe` (Fable review fixes), `f9c044f` (mutation-gap tests; readable accent-fold range), `d5c5ecd` (legacy-category test); docs `8608754` and this record |
| Authority | Owner authorization of 2026-10-09: implementation through frozen candidate; no push, no deploy |
| Private evidence | `~/Herndon-Financial-OS-Evidence/release-2-2026-10-09/` |

**Entry assistance only.** It is not:
- automated bookkeeping or categorization;
- reconciliation or import;
- a new ledger;
- an authority change.

The person decides every saved transaction. The Register stays the ledger.

## How it is built

- **One new ES module,** `js/register-assist.js`, mounted with one `<script type="module">` line. It has three parts:
  - pure domain rules;
  - a read-only view of the Register state the app has already loaded;
  - the DOM wiring.
- **The protected `_renderTxRegister` is unchanged** (pin intact). After each render, the module adds its controls to the Add form that function drew. Then:
  - it routes the form's own Add button through the duplicate check, and then the **same `_saveTxForm`**;
  - a regression tripwire (`R2-W2`) fails if the markup it attaches to ever changes.
- **The single classic-script change:** `_saveTxForm` now returns `true` on its success path, after the POST succeeded and the ledger reload completed. Every refusal or failure path is unchanged and returns nothing.
- **No new data access:**
  - suggestions and duplicates read only the selected account's complete, already-loaded history;
  - no new fetch;
  - no schema, RLS or grants;
  - no new globals.
- **If the module fails to load,** the Register works exactly as before.

## UX contract

### Save & Add Another (R2-1)

- The current entry saves through the normal `_saveTxForm` path: same validation, same fresh category-authority read, one POST.
- The next form opens **only after `_saveTxForm` reports success**.
- **On failure:**
  - the form and every entered value stay;
  - the normal error message shows;
  - no next form opens.
- **No reopen** if the person pressed Cancel during the save, opened an edit, opened a delete confirmation, or switched account.
- **Double-click, or clicking both buttons:** one save. A click while a previous save is still finishing shows "Your previous entry is still saving".
- No batch save.

### What carries to the next entry (R2-2)

| Field | Next entry | Why |
|---|---|---|
| Account | Same | It is the Register's selected account; the form saves to it. Shown as "Account: …" |
| Date | **The date just used, visibly marked** | Amber outline, plus "Date kept from your last entry (Oct 3) — change it if this one is different." The marker clears when the date changes. See the date decision below |
| Payee, memo, outflow, inflow | Cleared | Transaction-specific |
| Category | **Cleared** (no carry) | It can only be set by the person: the select, a search result, or "Use" on a suggestion |
| Cleared | **Unchecked** | Reconciliation-relevant; never carried |

**Date decision.** The existing Add form defaults to **today**. When entering from a statement or a stack of receipts, today is almost always wrong, and nothing on screen says so. The previous line's date is the most likely date for the next line, and it is shown explicitly as carried. So carrying it is at least as safe as today and is never silent. (Fable agreed.) If the owner prefers today, it is a one-line change in `nextEntryFormData`.

### Category search and grouping (R2-3)

- **Grouping:**
  - the same options the form already offers (the same keys, from the same live category registry and authority) are grouped under their parent category;
  - groups sorted A–Z, ungrouped as "Other", labels A–Z within a group;
  - any legacy option is kept.
- **Search box:** "Search categories…" above the select. Every typed word must start a word of the category's shown name or its group.
  - Click a result to choose it.
  - **Enter** chooses only when there is **exactly one** match.
- Presentation only: IDs and accounting semantics are untouched, and the chosen key is what saves.

### Payee → category suggestion (R2-4)

A deterministic rule; it **suggests, never decides**.

| Step | Rule |
|---|---|
| Normalization | Lower-case; accents removed; apostrophes removed; `&` becomes "and"; punctuation becomes spaces. Trailing store/reference numbers drop ("Publix #1234" → "publix"), **except check numbers** ("Check 1052" stays distinct). Exact match only: no fuzzy or prefix matching |
| History | This account's complete loaded Register history only. Categorized rows with the same normalized payee; the **10 most recent** (date, then created, then id) |
| Insufficient | Fewer than **2** such rows → no suggestion. A one-character payee → none |
| Conflicts / ties | Suggest only if one category holds **≥ 75%** of the considered rows (ties can never pass). Otherwise none |
| Inactive / invalid | The winner must be assignable **now** and present in the form's options. Otherwise **none**: no runner-up fallback |
| Display | "Suggested category: Groceries — used for 3 of the last 3 'Publix' entries in this account. [Use Groceries]". Never applied without the click |
| History not loaded | The form says: "This account's history isn't loaded, so payee suggestions and the duplicate check are off for now." |

### Possible-duplicate warning (R2-5)

- **Rule** (deterministic and conservative). A likely duplicate needs all of:
  - same account;
  - same **signed** amount to the cent (a refund is not a duplicate of the purchase);
  - same normalized payee;
  - dates at most **3 days** apart.
- **When it runs:** before any add-mode save, from either button.
- **What it shows:** "Possible duplicate — nothing has been saved yet." Then up to three matches ("Possible duplicate: Costco · $84.22 · Costco Visa · Oct 7") and two buttons:
  - **Go back:** nothing saved; the form is kept.
  - **Save anyway:** one save through the normal path.
- **"Save anyway" covers exactly what was shown.** Editing the entry withdraws the warning, and the next save re-checks.
- **Never** merges, deletes, suppresses or blocks.
- **Not checked:** edit mode, and incomplete entries (those go straight to the normal validation message).

## Verification

| Check | Result |
|---|---|
| RED before the feature | 14 regression failures. 11/11 e2e failures on the pre-Release-2 code with a stub module |
| GREEN on `d5c5ecd` | Regression 2009/0. e2e full suite 194/0 (2 prod-verify skipped; 0 real network contact) |
| Other suites | Release A 62/0. Release B 16/0. D1 26/0. A1b 212/0. G1 32/0. Rollover 49/0. Rollover server 25/0 |
| Pins and golden | Protected pins D1 49/49. 2026 golden identical |
| Mutation | 44 mutants: 41 killed. The 3 survivors (M4, M18, M28) are equivalent by construction (defence in depth). Earlier runs found gaps, closed by R2-E10 (double-click), R2-N1 (dirty form), R2-E15 and R2-E16 |
| Browser acceptance (local static server, real module, Supabase mocked) | 6/6 PASS |
| Independent review (Fable) | APPROVE WITH NON-BLOCKING FINDINGS (no blocking findings). N-1 to N-7 fixed in `ea345fe`. N-8 is a pre-existing out-of-scope defect, recorded below |

### Recorded, not fixed (out of scope)

**N-8 (pre-existing).** `_refreshTxFormCategoryLabels` refers to `_today`, which exists only inside `_renderTxRegister`. Clearing the Add form's date to blank therefore throws a console ReferenceError. Release 2 never triggers it. It goes to the backlog.

## Production acceptance (owner, 2026-10-09): PASS

| Check | Result |
|---|---|
| Release 1 version-notice proof | **PASS**. The Release 1 tab left open showed the update notice and did not reload by itself |
| A. Register assist UI | **PASS** |
| B. Payee suggestion | **PASS**. "Everyday" → Jabian Expenses 2026 ("9 of the last 10"). Applied only on Use; the owner's own category was never overridden. A partial payee ("ube") correctly gave no suggestion |
| C. Category search | **PASS** |
| D. Save & Add Another with a real transaction | **PASS by owner waiver**. Not observed in production; relies on the frozen e2e, browser and mutation evidence |
| E. Duplicate warning | **NOT EXERCISED** in production (no natural duplicate); the frozen evidence stands |
| F. Household build | **PASS** (Adam and Wendy) |
| Data check | Nothing was saved during acceptance |

The checks as planned before the push:

1. **Before the push**, Adam leaves one Release 1 dashboard tab open. After deploy, that tab must show the update notice when he returns to it, or within 15 minutes, and must **not** reload by itself. This is the final Release 1 version-notice proof.
2. Confirm the served `index.html` and `js/register-assist.js` match the commit, and the new `BUILD_TS`.
3. **Register → Add Transaction**, on a real account with history:
   - type a payee used before; the suggestion appears and nothing is chosen until **Use**;
   - search a category; the click sets it.
4. **Save & Add Another** with a real transaction. Check the next form:
   - the same account;
   - the date kept and marked;
   - everything else blank;
   - the cursor in Payee.
5. **Duplicate check:** enter the same payee and amount as a recent entry on the same account, then press Save & Add Another. The warning appears; press **Go back**. Nothing is saved.
6. Adam and Wendy each reload and confirm the build.

Real entries made during acceptance are ordinary Register transactions; Wendy decides which.

## Rollback

`git revert d5c5ecd f9c044f ea345fe 32f044d` on `main`, then the normal push/deploy and a household reload. No data rollback: every transaction was saved by the normal path.

## December integration

- Merge preview against `rollover-package-d` (`260169b` + `d5c5ecd`): the only conflict is the `BUILD_TS` line.
- Merged suites:
  - regression 2009/0;
  - e2e 194/0;
  - D candidate v2 pins 49/49;
  - golden identical.
- `test_rollover` shows the same two reds as the Release 0 and Release 1 previews (`PKGD-D2-SRC`: the Release 0 labels; `PKGD-DEPLOY-GUARD`: Package E pending).
- Release 2 adds no new December requirement.
- Rollover does not touch `_saveTxForm`, `_renderTxRegister`, `_openTxForm`, `_setTxFormField` or `_loadTxLedger`.

## R-lite observations (design facts from this work; R-lite NOT started)

1. **Transaction identity.**
   - `transactions.id` is a server-generated UUID (`docs/phase-5e-migration.sql`).
   - There is **no external/bank reference column** (no FITID-like key), so R-lite matching cannot rely on a bank id without schema.
   - `source` allows `manual | import | migration`; today every row is `manual` and hand-keyed.
2. **Matching-relevant fields.**
   - The Add form sets `transaction_date` but never `posted_date`, which exists but stays NULL. A bank download is keyed on the posted date, so R-lite must allow a date window between the bank posting date and the Register `transaction_date`.
   - `amount` is NUMERIC(12,2), signed, and never zero.
   - `reconciled` exists but is unused by the client.
   - `transfer_pair_id` is dormant.
3. **Payee.**
   - Hand-typed Register payees will not equal bank descriptors (e.g. "SQ *…", "POS DEBIT …").
   - R2's `normalizePayee` folds case, punctuation and store numbers, but R-lite should match primarily on **account + signed cents + date window** and use payee only as a tie-breaker or display. The R2 duplicate rule deliberately requires payee equality because it compares two hand-typed entries.
4. **Account identity.**
   - `account_key` is a TEXT foreign key to `accounts.key`.
   - The Register loads one account's **complete** history with a fingerprint check (`_loadTxLedger`, P0). R-lite can reuse that completeness guarantee and should refuse to compare on an incomplete load, as R2 does.
5. **Duplicate semantics.**
   - Legitimate same-day, same-amount, same-payee entries exist, so neither R2 nor R-lite may treat a match as an error.
   - R-lite needs many-to-one ambiguity handling ("these 2 Register rows could be this 1 bank line") resolved by the owner, not by rule.
6. **Owner adjudication can reuse existing controls:**
   - Register edit (PATCH);
   - the Cleared toggle (sends exactly `{cleared}`);
   - delete with confirmation;
   - Add / Save & Add Another for missing rows;
   - Search, the date filters and "Uncategorized only" to find rows.
7. **Still required:** R-lite must explicitly retire or replace the legacy Budget "Statement check" and its help reference (owner, 2026-10-09).
