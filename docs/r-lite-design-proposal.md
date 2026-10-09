# R-lite V1: design proposal (for owner review before implementation, 2026-10-09)

| | |
|---|---|
| Status | **DESIGN LOCKED (owner final checkpoint, 2026-10-09; section 23).** Implementation authorized through a frozen candidate. No push, no deploy, no real shadow run |
| Authority | Owner R-lite authorization (2026-10-09). R-lite is **non-authoritative**: it assists, and the existing reconciliation process stays authoritative |
| Production baseline | `14e76ec` (`BUILD_TS` `2026-10-09T16:27:26`). Releases 0–2 and the Register follow-ups are CLOSED |
| Boundaries | No schema, RLS or grants. No writes. No new ledger, no certification, no lock. No OCR or OAuth. No Edge Function. No runModel, WD, closeout or rollover change. OWNER HOLD unchanged |

## What the inspection found

| Fact | Evidence |
|---|---|
| **Register row identity** is a server UUID `id`. There is **no bank reference column** | `docs/phase-5e-migration.sql` |
| **Register fields R-lite can use:** `account_key`, `transaction_date`, `payee`, `amount` (NUMERIC(12,2), signed: outflow negative, never 0), `cleared`, `created_at` | Same. `posted_date` exists but the Add form never sets it, and `reconciled` is unused |
| **Complete history:** `_loadTxLedger` loads one account's full history, checked against an exact count and a newest-updated fingerprint taken before and after. A partial load becomes `incomplete` or `failed` and **no rows are exposed** | `index.html` (P0 loader). Identical on `rollover-package-d` |
| **Card sign:** outflows are negative, and card balances show negative while owed | Register UI (e.g. AMEX Gold running balance −21,664.10) |
| **Accounts and institutions** | Truist (Checking, Savings, Mastercard); American Express (Blue, Gold, Platinum, Savings); Bank of America Visa; Chase Disney Visa; Citi Costco Visa; Vio Bank (2); Lending Club; Fidelity (view-only). `docs/phase-5d-1-migration.sql`. Most still carry `quicken_name`s, so these institutions supported Quicken (QFX) downloads |
| **Existing reconciliation workflow** | Statement-driven **Cleared** ticking in the Register (Wendy). The weekly checking reconciliation and the manual Saturday certification stay authoritative |
| **Legacy Budget "Statement check"** (`_renderBudgetRecon`, **unprotected**) | It sums **legacy Budget-entered rows** for one month, compares them with a typed statement balance, and shows a green **"✓ Reconciled"**. Misleading on both the source and the claim. Its help text lives **inside the protected `renderBudget`** |
| **UI surface** | Transactions already has a disabled **"Reconciliation"** sub-tab placeholder in the **unprotected** `renderTransactions` |
| **Import code** | None exists |

## 1. Supported source format

**V1 accepts OFX/QFX only** (OFX 1.x SGML and 2.x XML, `.qfx` / `.ofx`).

**Why it's the smallest practical choice for this household:**
- **One parser covers every institution above.** Truist, American Express, Chase, Bank of America and Citi all offer a "Quicken / QFX" or OFX download (to be confirmed by the owner when downloading: section 19, question 1).
- **Per-row unique ids (`FITID`)** make duplicate rows detectable.
- **An explicit statement period** (`DTSTART`/`DTEND`) defines which Register rows are in scope.
- **The institution's own ledger balance** (`LEDGERBAL`, as of `DTASOF`) is authoritative balance evidence; per-bank CSVs usually lack it.
- **One documented sign convention,** instead of a different one per bank's CSV.

**Not in V1:** CSV, XLS, PDF, OCR, aggregator APIs. Savings, Lending Club and Fidelity are excluded unless the owner asks for them; they have very low transaction volume.

## 2. Normalization contract

For each statement-transaction record (`STMTTRN`) R-lite reads:

| Field | Required? | Use |
|---|---|---|
| `FITID` | Required | Row identity inside the file |
| `TRNAMT` | Required | Decimal amount, parsed **to integer cents** without floating-point error |
| `DTPOSTED` | Required | Posting date, normalized to `YYYY-MM-DD`; time and time zone ignored |
| `DTUSER` | Optional | Transaction date |
| `NAME`, `MEMO` | Optional | Description |
| `TRNTYPE` | Optional | Shown only |

- **File level:** `BANKID`/`ACCTID`, kept only as the **last 4 digits**; `DTSTART`, `DTEND`; `LEDGERBAL`/`BALAMT` and `DTASOF` when present. Nothing else is read.
- **Description normalization** (used only as a matching tie-breaker): lower-case; accents folded; punctuation becomes spaces; split into words.
  - This is a **separate rule from the payee autocomplete**. Prefix or substring matching is never used for reconciliation.

## 3. Sign convention

- **The file's sign is used exactly as given** (OFX: negative = money out of the account holder's pocket; for card accounts charges are negative and payments/credits positive).
- That is the same as the Register's sign. **No sign is ever flipped.**
- If a file appears to use the opposite convention (e.g. most rows match only when negated), R-lite says so. It never auto-corrects.
- The shadow run checks this per institution.

## 4. Account association

- The owner **chooses the Register account** first.
- After the file loads, R-lite shows the file's institution and **account ending ••1234** and asks the owner to confirm: "This file is for AMEX Gold".
- **Wrong-account file:** no account identifiers can be stored (no schema), so R-lite remembers the last-4 per account **in this browser only** (per-viewer convenience) and **warns** when a different last-4 appears.
- A file with **multiple accounts** is rejected in V1.

## 5. Deterministic matching hierarchy

**The matching date.** A bank row's date is `DTUSER` if present, else `DTPOSTED`. A Register row is a candidate for a bank row only if:
- it is **the same account** (by construction);
- it has the **same signed amount to the cent**; and
- its `transaction_date` falls in **[bank date − 5 days, bank date + 2 days]** (purchases are entered on or after the purchase day and post up to about 5 days later).

**The tiers.** They are applied in order, each only to rows still unmatched:

| Tier | Rule | MATCHED reason shown |
|---|---|---|
| T1 | Same amount and **same date**, and the pair is **mutually unique**: neither side has another T1 candidate | "same amount and date" |
| T2 | Same amount within the window, mutually unique | "same amount, N days apart, no other candidate" |
| T3 (tie-break) | Several candidates remain, and **exactly one** Register row's normalized payee words appear **as whole consecutive words** in the bank description (e.g. "kroger" in "KROGER #123 ATLANTA GA"), mutually unique under that rule | "same amount, N days apart, payee 'Kroger' appears in the bank description" |

- Description alone **never** creates a match. It only breaks ties between same-amount candidates.
- There is no score, and no global optimization.

## 6. Ambiguity rules

- Candidates exist but no tier yields a mutually unique pair → **AMBIGUOUS**. Every row involved is listed, with its candidates.
- **Legitimate identical transactions** (e.g. two $5.00 coffees on the same day) are AMBIGUOUS in V1. R-lite never pairs them arbitrarily.
- **A false MATCHED is treated as worse than AMBIGUOUS.** The mutation tests attack exactly this.

## 7. Comparison states

| Level | State | Meaning |
|---|---|---|
| Per row | **MATCHED** | With its tier and reason |
| Per row | **BANK ONLY** | No Register candidate at all |
| Per row | **REGISTER ONLY** | A Register row dated inside the statement period with no bank candidate. Flagged "may not have posted yet" if dated within 5 days of `DTEND` |
| Per row | **AMBIGUOUS** | Candidates exist, but no unique pair |
| Per file | **COMPARISON UNAVAILABLE** | Register history not complete. See section 10 |
| Per file | **FILE REJECTED** | Malformed. See section 11 |

## 8. Transaction-total comparison

Shown for the statement period. **Informational only:**
- bank total;
- Register total (rows dated in the period);
- difference;
- the difference broken down as bank-only sum, Register-only sum and ambiguous sums.

A zero difference is **not** reported as "reconciled".

## 9. Balance comparison (separate from section 8)

**When it runs:** only if the file has `LEDGERBAL` with `DTASOF`, **and** the account has a starting balance.
- It compares the institution's ledger balance with the Register balance computed from **complete** history through `DTASOF`: the starting balance plus every row dated on or before `DTASOF`, cleared or not. The cleared-only figure is shown alongside.
- **Outcomes:** **BALANCE AGREES** / **BALANCE DIFFERS by $X** / **BALANCE NOT AVAILABLE** (with the reason).
- An institution balance is **never synthesized**.
- A transaction tie **never implies** a balance tie.

## 10. Incomplete history: fail closed

Comparison runs **only** when the selected account's Register load status is `loaded` (the P0 complete-history guarantee), with the same account key as the file. Otherwise R-lite shows **"Comparison unavailable — this account's Register history isn't fully loaded"**, and produces:
- **no** row states;
- **no** totals;
- **no** BANK ONLY (missing Register evidence must never look like absent transactions);
- **no** balance.

If the history reloads, for example after an edit in the Register, R-lite **discards the previous results** and asks the owner to compare again.

## 11. Malformed files

The **whole file is rejected, with a reason**. There are no partial results. Causes:
- not OFX/QFX;
- unreadable or empty;
- no statement transactions **and** no balance;
- more than one account;
- a missing required field (`FITID`, `TRNAMT`, `DTPOSTED`) on any row;
- an unparseable amount or date;
- an amount of exactly 0;
- a period end before its start.

**Duplicate `FITID`:**
- byte-identical repeats → collapsed into one, with a visible notice;
- the same `FITID` with different content → the file is rejected.

## 12. File handling and security

- The file is chosen with a standard file picker and **parsed in the browser, in memory**. Nothing is uploaded or sent anywhere: no Supabase, no AI, no third-party service.
- **Nothing persists** except the per-account last-4 hint in this browser's storage. Results disappear on reload or navigation.
- **No transaction contents** go to the console.
- There is a size limit (2 MB). Only `.qfx`/`.ofx` files are accepted.

## 13. UI location and workflow

The Transactions → **"Reconciliation"** placeholder tab is enabled and renamed **"Statement compare"**, avoiding any claim of authority. The workflow:
1. Choose the account. This loads its complete Register history through the existing loader.
2. Choose the QFX file and confirm the account.
3. See the results:
   - counts per state;
   - totals (section 8);
   - balance (section 9);
   - rows grouped by state, each MATCHED row with its reason.

The owner then makes any corrections in the **existing Register** (Add, Edit, Delete, Cleared).
- R-lite has **no write buttons**.
- V1 may offer a convenience "**Show in Register**" link that only switches tab and sets the existing search filter.

Feature code is a new ES module, `js/r-lite.js`. The only `index.html` change is a few lines in the **unprotected** `renderTransactions` (enable the tab and give the module a mount point) plus one mount line.

## 14. The legacy Budget Statement Check

- **The panel (unprotected `_renderBudgetRecon`): retire it.** Replace the panel's content with a short notice:
  - "This check used Budget-entered entries, not the Register, and could show 'Reconciled' when it wasn't."
  - "Use Transactions → Statement compare."

  There is no green "Reconciled" any more. `renderBudget` itself is unchanged.
- **The help text, which lives inside the protected `renderBudget`, still tells people to use the panel. STOP — owner decision (section 19, question 2):**

| Option | Change | Downside |
|---|---|---|
| (a) Re-pin `renderBudget` | Replace the 3 help bullets about the Statement check panel with one pointing to Statement compare. The exact diff is prepared on approval | A protected re-pin. A new pin, D1 baseline update, re-pin record, and December re-pin coordination |
| (b) Unprotected alternative | The module rewrites those help bullets on screen after each render. No source change; a tripwire test fails if the protected help text ever changes | A runtime patch of protected output; with the module off, the old text shows |
| (c) Leave the help text temporarily | Nothing | The help text points to a panel that now says it has moved. Mildly confusing; no false "Reconciled" |

**Recommendation: (b) for V1**, with (a) folded into the December integration.

## 15. Protected-function impact

**None** for R-lite itself. The functions involved are:
- `renderTransactions` and `_renderBudgetRecon`, which are unprotected;
- the new module;
- reads of `_loadTxLedger`'s results, unchanged.

The only protected touch point is the help text in `renderBudget` (section 14).

## 16. RED test matrix (before implementation)

**Parser and file**
- Valid OFX 1.x (SGML) and 2.x (XML).
- Malformed file; empty file; missing required columns (`FITID`, `TRNAMT`, `DTPOSTED`).
- Unparseable amount or date; zero amount.
- Cent precision (e.g. `-0.1`, `1234.5`, `-84.22`).
- Duplicate rows: identical → collapsed; conflicting → rejected.
- Multi-account file; wrong-account file (last-4 warning).
- Size and extension limits.

**Matching**
- **Exact match;** posting-date offset inside the window; just outside it (no match).
- **Descriptions:** the bank description differs from the Register payee (T2 still matches when unique).
- **Same amount, unrelated** (two candidates, no description tie-break → AMBIGUOUS).
- **Legitimate identical transactions** → AMBIGUOUS.
- **Multiple plausible Register matches** → AMBIGUOUS. T3 resolves only on a whole-word payee in the description.
- **BANK ONLY;** REGISTER ONLY in the period; REGISTER ONLY near `DTEND` flagged.
- **Signs:** refund/credit (positive) never matches a purchase (negative); card payment/transfer (positive on the card, negative in checking); a sign-convention anomaly is flagged.
- Mutual uniqueness on **both sides**.

**Fail-closed**
- History `incomplete`, `failed`, `loading`, or for another account → COMPARISON UNAVAILABLE: no states, no BANK ONLY, no totals.
- History reload → results discarded.

**Balance**
- `LEDGERBAL` present → agrees, or differs by $X; absent → NOT AVAILABLE.
- No starting balance → NOT AVAILABLE.

**Safety**
- No writes (no fetch other than the existing ledger loader).
- No globals. Nothing logged.
- Statement Check shows no "Reconciled".

**Adversarial mutation targets:** false MATCHED by dropping mutual uniqueness, widening the window, ignoring sign, ignoring cents, substring description matching, matching across accounts, treating incomplete history as empty, a synthesized balance.

## 17. Shadow-run procedure (separate owner authorization)

1. At the next real reconciliation, the owner downloads the QFX for **Truist Checking** (and one card, e.g. AMEX Gold) and runs Statement compare **alongside** the normal process. The normal process is unchanged and authoritative.
2. Record:
   - institution rows;
   - counts per state;
   - **false matches** found by the owner;
   - **obvious matches missed**;
   - parsing exceptions;
   - totals and balance availability;
   - time compared with the current process;
   - friction;
   - changes needed before operational trust.
3. No reconciliation state is written. The results go into the private evidence folder, not the repository.

## 18. V1 exclusions

Excluded from V1:
- CSV, XLS or PDF;
- OCR;
- bank OAuth or aggregators;
- Edge Functions;
- schema, RLS or grants;
- a new ledger or adjudication store;
- a reconciliation lock or certification;
- any automatic Add, Edit, Delete, Cleared, category or reconciliation write;
- automatic owner decisions;
- savings, Lending Club and Fidelity accounts (unless requested);
- multi-account files;
- matching identical groups;
- persisting bank files or results;
- runModel, WD, closeout and rollover changes.

## 19. Owner decisions requested before implementation

1. **Format:** confirm OFX/QFX is the V1 format. When you next log in, check that Truist Checking and AMEX Gold offer a "Quicken (QFX)" or "OFX" download (any date range). Name any other accounts you want in V1.
2. **Statement Check help text:** option (a), (b) or (c) from section 14 (recommended: b).
3. **Matching window:** [bank date − 5, + 2 days] and the T1/T2/T3 hierarchy, as above.
4. **Tab name:** "Statement compare" (not "Reconciliation").

## 20. Owner rulings (2026-10-09)

These supersede the matching sections above where they differ.

**1. Format: QFX provisionally approved; verify before freeze.**

| Account | Download options seen on the owner's screens |
|---|---|
| Truist Checking | XLS, CSV, **QFX**, QBO |
| Citi Costco | CSV, TXT, **QFX**, QBO, OFX |
| Chase Disney | Excel/CSV, **QFX**, QIF, QBO |
| AMEX Gold | Excel, CSV, QuickBooks, "Quicken" (the extension is **not yet proven** to be QFX) |

- **V1 account scope:** Truist Checking, AMEX Gold, Citi Costco, Chase Disney. Others only with evidence that weekly reconciliation needs them.
- **CSV:** a potential fallback only. **No second parser** unless the real QFX files fail.
- **The parser contract is built from real files,** not from the specification. Tests use **sanitized structural fixtures** derived from them. No real transaction data is committed.

**2. Legacy Statement Check: option (a), under exact-diff control.**
- **The panel:** the unprotected `_renderBudgetRecon` is replaced by a notice. Statement Compare is an **assistance / comparison tool that does not certify reconciliation**; the old check used Budget-entered entries, not the Register.
- **The help text in protected `renderBudget`:** a **documentation-text-only** edit, then a re-pin. Controls:
  - no executable, calculation or data-source change, and no reconciliation logic;
  - the before/after diff is captured, and it is proven that only the intended text changed;
  - then the re-pin, the protected-function and golden controls, and the regression suite.
- No other protected function is touched. Option (b), the runtime rewrite, is rejected.

**3. Matching: conservative V1.**
- **MATCHED** only for a **unique** same-amount candidate (mutually unique on both sides):
  - **Tier 1:** same date;
  - **Tier 2:** Register date in **[institution date − 5, + 2]**. This window is **provisional until validated against real files and history** (section 21).
- **Multiple plausible candidates stay AMBIGUOUS.**
- **Tier 3 is removed from V1.** The institution description and the Register payee are **shown as evidence** to help the owner adjudicate an AMBIGUOUS row. They **never** turn an ambiguity into MATCHED. (The proposal's wording was contradictory: under mutual uniqueness there is nothing left to tie-break.)

**4. Tab name:** **Statement Compare.** Never "Reconciliation".

**5. Parser requirements.** The tests must attack:
- missing `FITID`; duplicate `FITID`; duplicate downloaded rows;
- absent ledger balance; missing or odd statement dates;
- transaction-date vs posting-date differences;
- debit/credit sign differences; payments/transfers; refunds/credits;
- malformed OFX/QFX; an **HTML or error page saved as the file**;
- wrong-account file; unexpected account identifier;
- cent precision; empty transaction set;
- a file covering a **broader range** than the comparison period.

**Transaction comparison never depends on a balance.** With no authoritative balance in the file, transaction comparison may still run, and balance comparison is **UNAVAILABLE**. A balance is never synthesized.

## 21. Real-file inspection (before the parser and date contract are frozen)

**Method.**
- The owner saves the downloads to `~/Herndon-Financial-OS-Evidence/r-lite-2026-10-09/raw/`. That is private, outside the repository, and never uploaded.
- A local **structure profiler** (`r-lite-profile.js`, kept in the evidence folder) reports only:
  - format, header, encoding;
  - which fields exist and how often;
  - date and amount *formats* (patterns, not values);
  - sign counts by transaction type;
  - transaction-date vs posting-date gaps;
  - `FITID` uniqueness and shape;
  - statement-period coverage;
  - balance presence;
  - the account id length plus its last 4.

  It does **not** print payees, descriptions or amounts.
- Sanitized fixtures keep each institution's exact structure (header, tag order, date/amount formats, optional-field pattern), with **synthetic** payees, amounts, ids and account numbers.

**Window evidence.**
- From the files: transaction-date vs posting-date gaps (where both exist).
- Against the Register: the gap between each institution row and its unique same-amount Register row.

  This second check needs a **read-only** query of those accounts' Register rows for the file periods (date and amount only), run either through the Supabase connector or through the app. **It needs a separate owner authorization.** It writes nothing, and only aggregate gap counts are recorded.

## 22. Real-file evidence (2026-10-09) and recommended final contracts

**Sources.**
- Six real downloads (QFX), profiled locally for **structure only**. They stay in the private evidence folder.
- An owner-authorized **read-only** Register extract: account, date and signed amount for the four accounts, Aug 10 – Oct 9. No writes.

Only aggregates are recorded here. The sanitized structural fixtures are in `fixtures/r-lite/`: one per institution, exact structure, synthetic values, and a leak check passed against 1,280 real values.

### 22.1 What the files contain

| | Truist Checking | AMEX Gold | Citi Costco | Chase Disney |
|---|---|---|---|---|
| Format | OFX 1.02 SGML, CRLF | **OFX 2.02 XML**: AMEX's "Quicken" download **is QFX** (`.qfx`) | OFX 1.02 SGML, LF; extension `.QFX` | OFX 1.02 SGML, LF |
| Message set / account type | Bank / `CHECKING` | Credit card | **Bank set with `ACCTTYPE` `CREDITLINE`** | Credit card |
| Account id (`ACCTID`) | 10 digits | 21-character composite (`letters…\|digits`) | 16 characters (masked letters + 4 digits) | 15 characters (`digits-last4`) |
| `ORG` | `BB&amp;T` (legacy, entity-escaped) | `AMEX` | `Citibank` | `B1` |
| `FITID` | 10 digits; unique; **stable across overlapping downloads (25/25)** | 18 digits; unique; equals `REFNUM`; stability **unproven** (no overlapping rows in these files) | 14 digits; unique | 31 digits; unique |
| Amount / sign | `n.dd`, debits negative | Same | Same | Same |
| `TRNTYPE` | **Mixed case** (`Debit`/`Credit`), plus `DEP`, `ATM` | `DEBIT`/`CREDIT` | `DEBIT`/`CREDIT` | `DEBIT`/`CREDIT` |
| Dates | `DTPOSTED` + `DTUSER` + `DTAVAIL` (no zone). `DTUSER` = `DTPOSTED` on 50 of 51 rows | `DTPOSTED` only, with milliseconds and a time zone | `DTPOSTED` only | `DTPOSTED` only, with a zone |
| Statement period | `DTEND` = requested end **+1 day** | Closed statement: Aug 25 – Sep 23. **Current-cycle file: `DTEND` in the future, and 6 rows posted before `DTSTART`** | Aug 24 – Sep 20 (statement "closed Sep 22") | Aug 27 – Sep 26 |
| Balance | `LEDGERBAL` + `AVAILBAL` | `LEDGERBAL` | `LEDGERBAL` | `LEDGERBAL` + `AVAILBAL` |
| Balance as-of date | **The download date**, not the statement end | Same | Same | Same |
| Description | `NAME` often cut at 32 characters (45 of 51 rows) | `NAME` (often cut at 32) **plus `MEMO` on every row** | `NAME` | `NAME` |

**Across all six files:**
- no duplicate or conflicting `FITID`s;
- no zero amounts;
- no unknown tags;
- one account per file;
- no pending marker of any kind, so the files appear to contain posted transactions only.

### 22.2 Contradictions with our assumptions

1. **`LEDGERBAL` is the balance on the day of download, not the statement balance.** No file contains a statement closing balance. Balance comparison is therefore "**institution posted balance on the download date vs the Register cleared balance**". That matches the Register's own rule: "the newest cleared row should match your posted account balance". It is meaningful only for a fresh download, and statement closing balances stay outside R-lite.
2. **The statement period does not bound the rows.** AMEX's current-cycle file has rows before `DTSTART` and a `DTEND` in the future; Truist's `DTEND` is one day past the request. The comparison range must come from the **rows themselves**: earliest to latest posting date, never later than the download date.
3. **Date meaning differs by institution.**
   - Only Truist has `DTUSER`.
   - AMEX's `DTPOSTED` behaves like a **transaction** date: 221 of 239 safe pairs fall on the same day.
   - Truist and Chase Register dates run **before** the posting date.
   - Citi Register dates run **after** it.
4. **A credit card in the bank message set** (Citi `CREDITLINE`). The parser must accept both message sets and must take the sign **only** from `TRNAMT`, never from `TRNTYPE` (whose spelling varies).
5. **`ORG` is not an institution name** you can rely on (`B1`, `BB&amp;T`), and `ACCTID` formats all differ. Only the **last 4 digits of `ACCTID`** are consistently derivable.
6. **Account binding cannot be proven from the file alone.** The OS stores no account numbers, so the binding must be the owner's explicit confirmation, plus two checks:
   - **Type consistency:** a checking file only for a checking account; a credit-card message set or `CREDITLINE` only for a credit card.
   - **A remembered last-4:** per browser, with a warning on any mismatch.

   A filename is never used.

### 22.3 Date-window evidence

Gap = Register date − institution date. Pairs are counted only when they are unique on both sides within ±15 days; ambiguous ones were excluded, not forced.

| Account | Same day | Register 1–5 days before | Register after | Outside −5/+2 | Unable to pair safely | No Register row of that amount within ±15 days |
|---|---|---|---|---|---|---|
| Truist Checking (63 rows) | 31 | 1d: 6, 2d: 1, 3d: 2, **4d: 3** | 1d: 1, 2d: 1 | **2** (8 and 9 days before) | 8 | 8 |
| AMEX Gold (285) | 221 | 1d: 12, 2d: 1 | 1d: 3 | **2** (3 days after) | 41 | 5 |
| Citi Costco (16) | 14 | — | 2d: 1 | **1** (3 days after) | 0 | 0 |
| Chase Disney (4) | 1 | 1d: 1, 2d: 2 | — | 0 | 0 | 0 |

**Candidate windows** under the V1 rule (unique on both sides inside the window). Across all four accounts and every window tested, there were **0 conflicts** with the wide-search safe pair.

| Window | Truist M / A / none | AMEX M / A / none | Citi M / A / none | Chase M / A / none |
|---|---|---|---|---|
| −4 / +2 | 47 / 6 / 10 | 262 / 16 / 7 | 15 / 0 / 1 | 4 / 0 / 0 |
| **−4 / +3** | **47 / 6 / 10** | **263 / 17 / 5** | **16 / 0 / 0** | **4 / 0 / 0** |
| −5 / +2 (provisional) | 47 / 6 / 10 | 261 / 17 / 7 | 15 / 0 / 1 | 4 / 0 / 0 |

(M = MATCHED, A = AMBIGUOUS, none = no candidate.)

**Recommendation: −4 / +3.**
- It is the smallest window that holds every safe pair except Truist's two rows dated 8–9 days early (likely checks or ACH entered well before they posted). Those surface as visible BANK ONLY / REGISTER ONLY exceptions, not as matches.
- Going to −5 adds nothing.
- Going to +3 picks up three real card pairs.

### 22.4 Repeated-amount guard (an extra safety option)

**The risk.** Recurring same-amount charges (subscriptions, tolls, coffee) are where a false MATCHED could come from. AMEX has 25 window-unique matches whose amount repeats within ±15 days.

**The option.** Add a guard: **MATCHED requires that no other same-amount row exists within ±7 days of either side.** Otherwise the row is AMBIGUOUS.

| Option | Truist M / A | AMEX M / A | Recurring-amount matches left (AMEX) |
|---|---|---|---|
| −4 / +3, no guard | 47 / 6 | 263 / 17 | 25 |
| **−4 / +3, ±7 guard** | **45 / 8** | **250 / 30** | **11** |
| −4 / +3, ±10 guard | 45 / 8 | 248 / 32 | 9 |

**Recommendation: adopt the ±7 guard.** It costs about 13 more AMBIGUOUS rows per AMEX month (about 10% of rows), in exchange for removing most of the recurring-amount pairings, which are exactly the false-MATCHED risk the owner ranked worst.

### 22.5 Recommended final parser contract

**Accepted input.**
- OFX 1.x SGML (closing tags optional) or OFX 2.x XML; `.qfx`/`.ofx`, any case.
- Either the bank message set (`CHECKING`, `SAVINGS`, `CREDITLINE`) or the credit-card message set.
- **Exactly one** statement and account per file.

**Field handling.**
- **HTML entities** are decoded.
- **Dates:** the first 8 digits are taken as the date; time and zone are ignored.
- **Amounts:** parsed exactly to integer cents; the sign comes **from `TRNAMT` only**.
- **Required per row:** `FITID`, `TRNAMT`, `DTPOSTED`.
- **Optional:** `DTUSER`, `NAME`, `MEMO`, `TRNTYPE` (normalized to upper case), `REFNUM`.

**Comparison range.** From the earliest to the latest posting date in the file, never later than the balance date (or today). `DTSTART`/`DTEND` are shown, but are **not** used as bounds.

**Balance.** `LEDGERBAL` `BALAMT` + `DTASOF`, shown as "**posted balance on the download date**". It is compared only with the Register **cleared** balance as of that date. When absent: **BALANCE UNAVAILABLE**, and the transaction comparison still runs.

**The whole file is rejected (no partial results) for:**
- HTML or an error page;
- not OFX;
- unparseable;
- more than one statement or account;
- any row missing a required field;
- an unparseable amount or date;
- a zero amount;
- a conflicting `FITID`.

Byte-identical duplicate rows are collapsed with a notice.

**A transaction-free file** with a balance runs only the balance check.

**The bank's `FITID`** identifies rows **within a file only**. It is never matched to the Register (which has no such field) and never stored.

### 22.6 Recommended final matching contract

**MATCHED** requires all of:
- the same account (with the owner's confirmation);
- the same signed amount to the cent;
- **mutual uniqueness** inside the window: the Register date in **[institution date − 4, + 3]**, where the institution date is `DTUSER` if present, else `DTPOSTED`;
- the **±7-day repeated-amount guard**.

The tier is reported: same date, or the "N days" gap.

- **Description and payee** are shown as evidence only. They **never** create a match.
- **Everything else:** BANK ONLY, REGISTER ONLY (in range) or AMBIGUOUS.
- If Register history is not `loaded`, everything is **COMPARISON UNAVAILABLE**.

### 22.7 Accounts and scope

- **All four target accounts fit V1.** No institution needs a CSV fallback.
- **Chase Disney** is very low volume (4 rows a month).
- **AMEX Platinum:** both AMEX Gold downloads (closed and current cycle) share an identical structure, which supports **reusing the AMEX adapter for Platinum** without format-specific work. It gets real validation on its first file.
- **No other account** showed evidence of being needed for routine reconciliation.

### 22.8 Shadow-run expectations from the evidence

These are rows with **no** Register row of the same amount within ±15 days:
- **Truist:** 8;
- **AMEX:** 5.

These would appear as BANK ONLY. They may be genuinely missing Register entries, or entries Wendy split or combined (e.g. deposits); R-lite cannot tell which, and the owner adjudicates them in the shadow run. Payees were deliberately not inspected.

## 23. Final owner rulings and the locked contracts (2026-10-09)

Where earlier sections differ, this section governs.

**Parser.** §22.5 is **approved** as written: OFX 1.02 SGML and OFX 2.02 XML; the observed bank and credit-card message types; exactly one account per file.
- **Required evidence per row:** `FITID`, a signed amount (exact cents) and `DTPOSTED`.
- The sign comes only from the amount.
- Malformed required evidence, or HTML posing as QFX, rejects the file.
- `FITID` is used **only** for file integrity and de-duplication. It is not Register identity, is never persisted, and no mapping table is created.
- CSV is not needed for V1.

**Window.** Approved at **−4 / +3**: Register date − institution `DTPOSTED`, inclusive. Exceptions outside it stay exceptions; the window is never widened to remove them.

**MATCHED contract (locked).** Let *B* be an institution row and *R* a Register row of the selected (bound) account.

| Step | Definition |
|---|---|
| A | Same bound account |
| B | Same signed amount to the cent |
| C | `eligible(B,R)` ⇔ A and B hold, and −4 ≤ (`R.date` − `B.posted`) ≤ +3 |
| D | *B* has **exactly one** eligible *R*, looked for across the **whole** loaded Register history of the account (not only the effective range) |
| E | That *R* has **exactly one** eligible *B* among the file's rows |
| F | **±7 guard (veto).** Let *W* = [min(`B.posted`, `R.date`) − 7, max(`B.posted`, `R.date`) + 7], inclusive. If **any other** institution row *B′ ≠ B*, or **any other** Register row *R′ ≠ R*, has the **same signed amount** and a date inside *W*, the pair is **vetoed** |
| Result | MATCHED only if A–F all hold. The reason shown: "same amount and date", or "same amount, N days apart" |

- **The guard only vetoes.**
  - It never creates or chooses a match.
  - It never uses descriptions, merges, splits, or balances totals.
  - It is evaluated once per candidate pair, **not transitively**, so no ambiguity cluster can grow.
- **The evaluation is order-independent:** every pair is decided from the full row sets at once.

**Per-row states.**
- **Institution rows:**
  - **MATCHED** when the contract holds.
  - **BANK ONLY** when there are no eligible *R*. A same-amount Register row within ±15 days is shown as a "possible counterpart outside the window" hint, which is evidence only.
  - **AMBIGUOUS** otherwise: several eligible *R*, a shared *R*, or a guard veto. The candidate and nearby rows are listed.
- **Register rows inside the effective range:**
  - **MATCHED** (paired);
  - **AMBIGUOUS** (has at least one eligible *B* but isn't matched);
  - **REGISTER ONLY** (no eligible *B*).
- **Register rows outside the effective range** are **matching context only**:
  - they can be a candidate, a match, or a guard row for an institution row;
  - they are never listed as REGISTER ONLY and never counted in the Register total;
  - the number of Register rows dated after the file's last row is shown as "not compared".

**Effective range.** From the earliest to the latest `DTPOSTED` of the valid rows. It is displayed. `DTSTART`/`DTEND` are shown for information only.

**Current posted balance check.** It is never called "reconciled" or "statement".
- **What it compares:** the file's `LEDGERBAL` (`BALAMT` at `DTASOF`, shown with its date and time) **vs the Register cleared balance**: the account's starting balance plus every **cleared** row dated on or before the `DTASOF` date.
- **The compatible cutoff:** the Register's Cleared marks reflect *now*, so the check runs only when the `DTASOF` date is **today**. A balance from a past date (an old download) or a future date gives **UNAVAILABLE**, with the reason. No balance in the file, or no starting balance on the account, also gives UNAVAILABLE.
- **Outcomes:** AGREES, or DIFFERS by $X.
- **Independence:** the check is independent of the transaction results in both directions, and never synthesized.

**Account binding (fail closed).**
- The owner selects the account. V1 accounts: Truist Checking, AMEX Gold, AMEX Platinum, Citi Costco, Chase Disney.
- **Type compatibility:** `CHECKING` ↔ checking; the credit-card message set or `CREDITLINE` ↔ credit card. Anything else is **refused**.
- **Remembered last-4** is a per-browser convenience, not authority:
  - a file whose last-4 differs from the one remembered for that account → **refused** (no comparison);
  - a last-4 remembered for **another** account → **refused**.
- **Every import** shows "This file appears to be a credit card ending •NNNN. Compare it with AMEX Gold?" and needs an explicit confirmation.
- **Re-binding** is a separate, explicit owner action.
- The filename and `ORG` are never used. No server-side binding store.

**Process.**
- Fixture commits use the normal hook path. The docs-only exception is for docs only. The normal validation over `2a6e2bf` passed (private evidence).
- The legacy Statement Check ruling stands: retire the unprotected panel; a documentation-text-only `renderBudget` re-pin with the exact before/after diff captured.
