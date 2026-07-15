# Operator Continuity Card

**Status:** TEMPLATE — complete and store a copy **with the off-device backups**. **Secrets-free, balance-free** — this card says *where things are and who to call*, never passwords or balances.
**Authority:** `docs/roadmap/canonical-roadmap.md` §14 (AF-5). **Purpose:** the household-level continuity gap behind "backup owner." Every control (closeouts, closes, corrections, DR) routes through one operator, and the OS is the sole record. If that operator is unavailable, this one page lets someone else understand the system, read current balances, and reach the right help — without operating the model.

---

## What this system is

The **Herndon Financial OS** (`dashboard.herndons.us`) is the household's **sole live system of record** for weekly cash flow, savings-goal funding, and budget reconciliation. It is a static web app (GitHub Pages) backed by a Supabase Postgres database. Quicken is retired (historical archive/reference only). There is no paper or spreadsheet parallel ledger.

## How to read current balances WITHOUT operating the model

- Log in at `dashboard.herndons.us` (owner: `aherndon6@gmail.com`; household admin: `wherndon22@gmail.com`).
- Open the **Register** — it shows account ledgers with historical balances (the observed record). This is read-only viewing; do **not** run a weekly closeout, correction, or reopen to "check" a balance.
- The authoritative current balances are the **bank statements**; the Register reflects entered transactions. When in doubt, trust the statement.

## Where things live (fill in pointers — not secrets)

| Thing | Location pointer |
|---|---|
| Password manager (all logins/keys) | `__________` |
| Off-device encrypted backups (DB dumps + `git bundle`) | `__________` |
| Backup-encryption passphrase | (in the password manager) `__________` |
| Environment manifest | `docs/environment-manifest.md` (in the repo / bundle) |
| Restore runbook | `docs/restore-runbook.md` |
| Supabase projects | prod `usayoldrawwmjsmretin`, staging `pkwotgqivgaapwuqgwqb` |

## Who to contact

| Role | Name | Contact |
|---|---|---|
| Primary operator | Adam Herndon | `__________` |
| Backup owner | `__________` | `__________` |
| CPA | `__________` | `__________` |
| Named technical contact | `__________` | `__________` |

## Do-not-do (for a non-operator)

- Do **not** run a weekly closeout, correction (Option B), or reopen.
- Do **not** write to the Supabase dashboard or delete/modify retained Quicken archive data.
- Do **not** enter credentials into any field on someone else's instruction.
- **If something looks wrong: write it down, don't touch it** — contact the operator or the named technical contact.

---

*Secrets-free, balance-free. Store a completed copy with the off-device backups; refresh when contacts or locations change.*
