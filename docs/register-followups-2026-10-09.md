# Register follow-ups: blank-date fix and payee autocomplete (closed 2026-10-09)

| | |
|---|---|
| Status | **DEPLOYED — PASS · PRODUCTION ACCEPTANCE — PASS · CLOSED** (owner, 2026-10-09). Pushed `3963ed1..14e76ec` (fast-forward); `BUILD_TS` `2026-10-09T16:27:26`; served `index.html` and `js/register-assist.js` byte-identical to the commit |
| Branch | `production-line-2026q4`, on top of live `3963ed1` (Release 2) and docs `5c7c4de`. Commits: `8d23939` (blank-date fix), `d6c2661` (payee autocomplete), `b818b10` (Fable review fixes), `65cdb92` (mutation-gap tests), plus this record |
| Authority | Owner amendment of 2026-10-09: blank-date fix approved; partial-payee matching for investigation and conditional implementation, corrected the same day to **user-controlled autocomplete on the Payee field** |
| Not included | R-lite (a separate workstream; authorized by the owner and moved forward from about Nov 8, starting after this closure). The What-If "(no change)" issue stays out |
| Private evidence | `~/Herndon-Financial-OS-Evidence/register-followups-2026-10-09/` |

## 1. Blank-date defect (Fable R2 N-8)

**Root cause.**
- `_refreshTxFormCategoryLabels` (unprotected) fell back to `_today` whenever the Add-form date was blank.
- `_today` exists only as a local variable inside the protected `_renderTxRegister`.
- Chrome reports a cleared date, or a partly typed (invalid) one, as `''`, so clearing the field threw `ReferenceError: _today is not defined`.

**Second symptom found while reproducing.**
- After a blank date, any re-render redrew the field as **today**: the protected renderer writes `value = fd.transaction_date || _today`.
- Meanwhile the form's data still had no date. The screen showed a date that Save would reject.

**Fix (narrow, unprotected).**
- `_refreshTxFormCategoryLabels` now uses the global `_todayTxDate()` for the **category-label month only**. It is the same value the renderer uses; regression test 5E8-R20b checks they are equal.
- The module keeps a cleared date **blank on screen** after re-renders. It never writes the date data.
- Save then shows the normal "Date is required." (or "Enter a valid date."), saves nothing, and keeps every other value. This is verified for ordinary Save and for Save & Add Another, and covers edit mode too.
- No protected function, date semantics or persistence path changed. Today is never inserted into the data.

## 2. Payee autocomplete

### Investigation

| Question | Answer |
|---|---|
| Does Register history support it? | Yes. The payee strings in the selected account's complete loaded history |
| Entirely in unprotected `js/register-assist.js`? | Yes. No `index.html` change for this item |
| Account-specific or household-wide? | **Account-specific.** It is the history already loaded; household-wide would need new reads of other accounts. Limitation: a payee used only on another account is not offered |
| Prefix only (A), substring (B), or leave exact only (C)? | **B with explicit ordering:** exact → prefix → substring. Prefix alone covers "ube" → Uber; substring adds interior matches ("ber" → Uber) **without ever pre-selecting them** |
| R-lite coupling | None. UI only; R-lite matches bank lines to Register rows, and this changes neither |

### The contract (implemented)

**Matching**

| Rule | Detail |
|---|---|
| Activation | 3 or more normalized characters. Shorter input offers nothing |
| Normalization | The Release 2 rule: case, accents, apostrophes and punctuation fold; `&` becomes "and"; trailing store/reference numbers drop; check numbers are kept |
| Deduplication | One choice per normalized payee, with an entry count. Shown and inserted in its **most recent spelling that has no store/reference number**, otherwise simply the most recent |
| Ordering | Class (exact, prefix, substring), then most entries, then most recent, then name. No score |
| Limit | At most 6 shown, plus "N more — keep typing" |
| Incomplete history | No list, and the existing "history isn't loaded" note shows |

**Accepting a payee**

- **Accept means one of:**
  - **Tab or Enter** on the highlighted item (Tab then moves on to Memo as usual);
  - a **click** on any item;
  - ↑/↓ to move the highlight.
- **Escape** dismisses the list without changing her text.
- **Typing on, or leaving the field,** keeps exactly what she typed. Shift+Tab and IME-composition keys never accept.
- **Pre-highlight** (what Tab/Enter accept without arrowing) is set only when all of these hold:
  - exactly one name *starts with* the typed text;
  - none equals it;
  - the typing stops mid-word and not on a digit.
- **Examples:**

  | Typed | History | Result |
  |---|---|---|
  | "ube" | Uber | Uber pre-highlighted |
  | "mar" | Marriott, Marshalls, Marco's Pizza | All shown, none chosen |
  | "Target" | Target Optical | Offered, **not** highlighted, so Tab keeps "Target" |
  | "Check 105" | Check 1052 | Not highlighted |

**Two separate decisions**

1. **Accepting a payee changes only the payee.**
2. The **unchanged Release 2 exact-payee category rule** then runs against that payee:
   - at least 2 of the newest 10 entries;
   - one category with at least 75%;
   - the category is assignable now.

   The **category changes only when she presses Use**.

**Never**
- saves;
- chooses a category;
- overwrites continued typing;
- reads new data;
- changes schema;
- creates a payee registry.

## Verification (summary; detail in private evidence)

| Check | Result |
|---|---|
| RED: blank date | Uncaught `ReferenceError` in the unit test and in Chromium; Save showed today after a re-render |
| RED: autocomplete | 7 rule tests and 6 browser scenarios failed before the feature (E4/E6 are safety controls that pass before and after) |
| RED: review follow-ups | Inverse spelling, single check and IME Enter failed on the pre-fix module |
| GREEN on `65cdb92` | Regression 2018/0. e2e full suite 205/0 (0 real network contact) |
| Other suites | Release A 62/0. Release B 16/0. D1 26/0. A1b 212/0. G1 32/0. Rollover 49/0. Rollover server 25/0 |
| Pins and golden | Protected pins D1 49/49. 2026 golden identical |
| Browser acceptance | 8/8 PASS (local static server, real modules) |
| Mutation | **30/30 killed**, 0 equivalent. Six apparent survivors: three were a results-parser miss, and three were real gaps, closed in `65cdb92`: frequency ordering, Enter with nothing highlighted, a stale cache with incomplete status |
| Independent review (Fable) | APPROVE WITH NON-BLOCKING FINDINGS (no blocking). N-1 to N-6 fixed in `b818b10` |

## Impact on Release 2

- None on its contract:
  - the exact category rule and its thresholds are unchanged (a test pins them);
  - the duplicate warning still runs on an accepted payee, and a stale warning is withdrawn on acceptance;
  - Save & Add Another is unchanged (regression tests cover both).
- The visible additions:
  - the payee list;
  - a cleared date now stays blank instead of reappearing as today.

## Production acceptance (owner, 2026-10-09): PASS (zero-write)

| Check | Result |
|---|---|
| A. Autocomplete | **PASS**. "ube" on AMEX Gold listed "Uber · 9 entries", highlighted. Payee stayed "ube" until accepted, then became "Uber"; the category was untouched. No category suggestion appeared, which is correct: Uber's newest 10 entries there do not reach 75% in one category |
| B. Escape / typing on | **PASS**. Typed text kept; nothing substituted |
| C. Blank date | **PASS**. "Date is required."; the field stayed blank; no exception; other values kept |
| D. Household build | **PASS** (Adam and Wendy) |

Nothing was saved during acceptance.

The checks as planned before the push:

1. In Register → Add, type "ube" (or the first letters of a familiar payee).
   - The list appears and **nothing changes** until Tab/Enter on the highlighted item, or a click.
   - Then the category suggestion appears separately, and **Use** is still needed.
2. Escape, and leaving the field, keep what was typed.
3. Clear the date (one Backspace in the month) and press Add.
   - "Date is required."
   - Nothing is saved.
   - The other fields are kept.
   - The field stays blank.
4. Adam and Wendy each reload once.

## December integration

- Merge preview against `rollover-package-d`: the only conflict is the `BUILD_TS` line.
- Merged suites:
  - regression 2018/0;
  - e2e 205/0;
  - D candidate v2 pins 49/49;
  - golden identical.
- `test_rollover` shows the same two known reds as the earlier previews.
- No new December requirement.

## Rollback

`git revert 65cdb92 b818b10 d6c2661 8d23939` on `main`, then the normal push/deploy and a household reload. No data rollback.
