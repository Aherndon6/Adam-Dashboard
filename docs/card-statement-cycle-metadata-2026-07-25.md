# Card Statement-Cycle Metadata — Canonical Record + Backlog (2026-07-25)

**Type:** canonical record (History/reference tier) + backlog seed.
**Documentation only — no code, schema, SQL, production-data, weekly-model, or financial change is made by
this record. It creates no cash obligation.**
**Secrets-free, balance-free.**

---

## 1. Why this document exists

Recording the Costco Anywhere Visa first-statement facts surfaced that **the Financial OS has no data model
for card statement-cycle metadata** (statement close date, payment due date, minimum payment, cycle day).
Read-only inspection (2026-07-25) established:

- **`public.accounts` has no statement-cycle columns.** Full column set: `id, key, label, institution,
  account_type, lifecycle_status, include_in_budget, include_in_cashflow, starting_balance,
  starting_balance_as_of, starting_balance_source, starting_balance_note, quicken_name, notes,
  display_order, created_at, updated_at, created_by, updated_by`. The only free-text fields are `notes`
  and `starting_balance_note` — **miscellaneous fields, not a canonical home for cycle metadata.**
- **No other table carries statement-cycle metadata.** No `statement`, `cycle`, `due`, or `close` field
  exists anywhere in the exposed schema.
- **Every other card's cycle facts are hardcoded in `index.html`**, not stored as data:
  - Close days are literal strings in the reminder logic — AMEX Gold *"(23rd)"*, Disney Visa *"(26th)"*,
    AMEX Platinum *"(2nd)"* (`index.html` ~lines 1462–1464 / 2703–2711), keyed off the
    `_amexGoldClose` / `_disneyVisaClose` / `_amexPlatClose` week arrays.
  - Bill **amounts/due dates** live in the hardcoded `WEEKS` array and are trued-up per week via
    **Edit Week** overrides (`model_week_overrides.events_json`).
  - Costco already carries a literal backlog placeholder in code:
    `[PENDING #20] Costco Visa — Confirm closing date, due date, and card transition timing`
    (`index.html:2350`, the moveable/deleteable `ACTION_KEYS.COSTCO_VISA` reminder).

**Conclusion (per the recording question's option set):** the facts do **not** belong in an existing
account/card registry record or any existing table, and must **not** be forced into `accounts.notes`.
The proper home is a **new configuration capability that does not yet exist**. Until it does, the facts
are recorded here canonically and a scoped backlog item is opened (§4).

---

## 2. Costco Anywhere Visa — statement-cycle facts (canonical record)

| fact | value |
|---|---|
| Card | Costco Anywhere Visa (Citi) — account key `costco_visa` |
| First statement close date | **2026-07-22** |
| Payment due date | **2026-08-20** |
| First statement balance | **zero** |
| Minimum payment | **zero** |
| Weekly-model cash obligation | **none created** — the statement carries no balance, so there is nothing to model |

**No cash obligation, commitment, or Edit-Week entry is created for a zero-balance statement.** This is
consistent with the setup task's own rule: *"Do not model an amount until a real statement exists"* — a
real statement now exists and it is zero, so the correct modeled amount is nothing.

---

## 3. Cross-check against the existing hardcoded Costco surfaces

- The model reminder `ACTION_KEYS.COSTCO_VISA` (moveable/deleteable; default Cal Wk 24 per
  `ACTION_DEFAULT_WEEKS.costco_visa`) remains a **display prompt** only. Its retirement/deletion is a
  separate, optional action (`saveActionOverride({deleted:true})`) and is **not** performed by this record.
- No change is made to `index.html`, the `WEEKS` array, or any override.

---

## 4. Backlog item — **CARD-CYCLE-1** (narrowly scoped)

**Title:** Card statement-cycle metadata capability.

**Problem:** card statement-cycle facts (close date, due date, minimum, cycle day) have no data model;
they are hardcoded per-card in `index.html` and trued-up via Edit Week. New cards (Costco) have nowhere
canonical to record their cycle, and the close-day literals are not owner-editable data.

**Scope (deliberately narrow):** a per-card statement-cycle metadata store — e.g. `close_day`,
`due_offset_days` (or `due_day`), optional `minimum_payment_rule` — read by the reminder/close-review
logic in place of the hardcoded literals. **Out of scope:** statement *balances* (those stay in the
Register/model true-up), payment automation, and any change to how obligations are modeled.

**Priority:** low. **Trigger to revisit:** whenever a card statement-cycle admin/registry surface is
built, or the next time a new card is added. Supersedes the code placeholder `[PENDING #20]`.

**Interim rule:** record new card statement-cycle facts in a dated canonical doc like this one; do **not**
use `accounts.notes`; do **not** create a zero-balance obligation.

---

## 5. Week-29 Costco setup task disposition

The setup custom task **`ct_1784858137013_derx`** (persisted `week_num = 7` = **Cal Wk 29**) reads:
*"Costco Visa — capture statement close date, due date, and first statement balance from Citi; then add
the weekly-model obligation. Do not model an amount until a real statement exists."*

Its substance is now **satisfied**: the close date (2026-07-22), due date (2026-08-20), and first-statement
balance (zero) are captured here, and the correct weekly-model obligation for a zero-balance statement is
**none**. The task is therefore **completable**. Completion itself is a normal in-app task-state action
(owner session) — see the session hand-off; this record does not mutate task state.

---

## Cross-references

- Accounts write surface / registry: `docs/phase-5g-1d-gatec-register-2026-07-13.md`
- Weekly-model override mechanism: `model_week_overrides.events_json` (Edit Week)
- Decision-log entry: `docs/decision-log.md` (2026-07-25 row)
