# Restore Runbook

**Status:** REHEARSED 2026-09-12 (DR-1 part 3). Database restore path §3 executed end to end against a blank Supabase branch: PASS. Revised in place; git history is the changelog.
**Rules for this file:** secrets-free, location-free, balance-free. This repository is public. Passphrases, passwords, file locations and household figures live in the password manager and in the owner's evidence folder, never here.
**Authority:** DR-1 in `CODEX_STATUS.md`; `docs/roadmap/canonical-roadmap.md` §5. The Financial OS is the sole live system of record (Quicken retired 2026-07-13), so this runbook is the recovery of record.
**Backup owner:** Adam Herndon.

**Derived-vs-observed doctrine (read first):** the model derives state from constants plus reconciliation history. Observed bank balances are ground truth. After any restore, check observed balances against statements before trusting a derived figure. Never edit golden-master expected outputs to make a restored build "look right."

---

## 1. Pick the scenario

| Scenario | Symptom | Path | Rehearsed |
|---|---|---|---|
| **S1** Bad data change, project intact | Wrong or deleted rows, app still loads | §2 Pro daily backup restore | No |
| **S2** Project or Supabase account lost | Project deleted, account locked, org gone | §3 Off-device dump into a new project | **Yes, 2026-09-12, PASS** |
| **S3** Source or hosting lost | GitHub repo or Pages unavailable | §5 Source redeploy | No |

If unsure between S1 and S2, prefer S1 while the project still exists: it keeps auth settings, API keys and the app URL.

## 2. S1: Pro daily backup restore (project intact)

Pro keeps daily backups for 7 days. A restore replaces the **whole** database with the backup and loses every write since it was taken, including Register entries and reconciliations.

1. Write down what was entered since the backup time (Register rows, closeouts). They must be re-entered.
2. Supabase dashboard → the production project → Database → Backups → pick the backup → Restore. Expect downtime.
3. Run the §4 verification gates against production after it returns (read-only queries).
4. Re-enter the lost writes. Reconcile against bank statements.

Alternative for a single bad table: restore the backup to a **new** project (dashboard "restore to new project" where offered) and copy only the affected rows back. Owner-gated production write.

## 3. S2: Restore the off-device dump into a new project

### 3.1 What the backup set must contain

| Item | Why |
|---|---|
| Encrypted custom-format `pg_dump` of production (AES-256-CBC, PBKDF2, 600,000 iterations) | The data, schema, RLS policies, functions and `auth.users` |
| Its passphrase, in the password manager, distinct from the database password | Without it the archive is noise |
| **The post-restore security posture SQL file** | The dump is taken `--no-privileges`, so it carries **no grants**. Without this file the restored app cannot read or write anything. |
| SHA-256 of the encrypted file, recorded when it was made | Detects a corrupted or swapped archive before you trust it |

All four must exist off-device, outside the Supabase account. Refresh the dump monthly. **Refresh the posture file whenever production grants change** (any migration with GRANT/REVOKE, or any new table or function in `public`). The posture file is generated from the production catalog and carries a fingerprint to verify against.

### 3.2 Tools

`pg_restore` and `psql` version 17 or newer (Homebrew `libpq` works), and `openssl`. Use the **Session pooler** connection. The direct connection is IPv6-only and fails on many home networks.

### 3.3 Procedure

1. **Create the target.** New Supabase project (or a blank branch for a rehearsal), same region, same Postgres major version. Reset its database password and copy it. Copy its Session pooler host. The pooler user is `postgres.<project-ref>`.
2. **Prove the target is blank and is not production or staging.** Check `select system_identifier from pg_control_system()` is not either value recorded in `docs/environment-manifest.md`, and that `public` has 0 relations and `auth.users` has 0 rows. Stop if not.
3. **Verify and decrypt.** Compare the encrypted file's SHA-256 with the recorded value. Decrypt into a folder only you can read (`umask 077`):
   `openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in <archive>.dump.enc -out <work>/prod.dump`
   `bad decrypt` means the wrong passphrase: the prompt wants the **backup passphrase**, not the database password.
4. **Check the archive reads.** `pg_restore --list <work>/prod.dump` must succeed. Count the `TABLE DATA` entries.
5. **Restore auth rows first.** Order is mandatory: 15 `public` foreign keys reference `auth.users(id)`, so a public-first restore rolls back.
   `pg_restore --data-only --schema=auth -t users -t identities -t mfa_factors -f <work>/auth.sql <work>/prod.dump`
   `psql -X -v ON_ERROR_STOP=1 --single-transaction -c "set session_replication_role = replica" -f <work>/auth.sql`
   Do **not** restore sessions, refresh tokens, flow state, audit log or `auth.schema_migrations`: they are live credentials or belong to the new platform.
6. **Restore the public schema and data.**
   `pg_restore --no-owner --no-privileges --no-statistics --schema=public --single-transaction --exit-on-error --dbname=postgres <work>/prod.dump`
7. **Apply the security posture file.** `psql -X -v ON_ERROR_STOP=1 -f <posture-file>.sql`. It refuses to run on production or staging, resets every `public` grant to the production matrix, sets default privileges, and recreates the `ensure_rls` event trigger (a schema-scoped restore does not carry event triggers).
8. **Delete the plaintext dump** and anything extracted from it. It contains credential hashes.
9. **Run the §4 verification gates.** Do not point the app at the new project until all pass.
10. **Cut the app over.** In `index.html` set `SUPA_URL` and `SUPA_KEY` to the new project's URL and anon key; commit and push per `AGENTS.md`. In the new project's Auth settings set the Site URL and redirect URLs for `dashboard.herndons.us`. Users sign in with email and password; the restored password hashes carry over, but every existing session is invalid (new JWT secret), so both users sign in again.
11. **Record the new project** (ref, `system_identifier`) in `docs/environment-manifest.md`, and take a fresh encrypted dump plus posture file from the new production.

Storage buckets, storage objects and Vault secrets were all empty in production when this was written. If that changes, this procedure no longer covers them: storage files live outside Postgres, and Vault secrets are encrypted with a per-project key and will not decrypt in a new project.

### 3.4 If `auth.users` is not in the dump

Recreating users produces new UUIDs, and the restored `public` rows still point at the old ones through 15 foreign keys, so step 6 fails. The old "re-link `app_users.auth_user_id`" fix is **not sufficient** on its own. The dump has included `auth` since 2026-09-07; keep it that way. If you are ever forced down this path, it needs a planned remap of every `auth.users` foreign key (`created_by`, `updated_by`, `user_id`, `resolved_by`, `auth_user_id` columns) inside one transaction, designed and reviewed before execution.

## 4. Verification gates (all must pass)

| Gate | Check | Pass |
|---|---|---|
| V1 Data | Row count and order-independent content hash per table, offline dump vs restored database: every restored `public` table plus `auth.users`, `auth.identities`, `auth.mfa_factors` | All equal |
| V2 Reference counts | The owner-held reference counts for key tables (kept outside this repo) vs dump vs restored | Three-way equal. A mismatch means the dump is not the snapshot you think; stop, don't explain it away |
| V3 Schema | Fingerprints of function definitions, policies, triggers, columns, constraints, indexes; RLS enabled on every `public` table | Equal to the fingerprint recorded with the posture file |
| V4 Security posture | Order-independent grant fingerprint over `public` tables, sequences, functions, owners and `ensure_rls` | Equal to the posture file's recorded fingerprint |
| V5 Authorization | Simulated sessions in a rolled-back transaction (`request.jwt.claims` sub from `app_users`, `set local role authenticated`) | Adam: allowed, owner, can write, sees all rows. Wendy: allowed, **not** owner, can write, no `cash_commitments` INSERT, no `weekly_reconciliations` DELETE. anon: nothing allowed, 0 rows, no INSERT or TRUNCATE |
| V6 App | Owner and Wendy sign in to the cut-over app; Register, Budget and the latest reconciliation load | Loads with expected data. **Not yet rehearsed** |

The fingerprint queries used on 2026-09-12 are kept with the rehearsal evidence.

## 5. S3: Source redeploy

1. Restore the repo from `origin/main`, a second-machine clone, or the off-device `git bundle` (all branches).
2. Confirm the commit matches the intended deployed build.
3. GitHub Pages deploys on push to `main`. If Pages is down, any static host can serve `index.html`; point DNS for `dashboard.herndons.us` per `docs/environment-manifest.md`.
4. Verify `BUILD_TS` in the served `index.html`.

## 6. Credential recovery

- Supabase owner login has MFA with **two authenticator apps in different failure domains**. **Supabase issues no recovery codes.** Losing every registered authenticator locks the account permanently; the printed TOTP setup key is the only offline path.
- Backup passphrase, database passwords and domain logins are in the password manager.
- Supabase Pro projects do not pause for inactivity. (The Free-tier unpause step formerly here is retired.)

## 7. Rehearsal record

| Date | Target | Result | Data restore time | Notes |
|---|---|---|---|---|
| 2026-09-12 | Blank Supabase preview branch (deleted after) | **PASS**: V1 to V5 | 18 s (about 3.5 min end to end, including prompts) | Found and fixed before execution: auth-before-public order. Found during: `--no-privileges` restore leaves the app locked out until the posture file runs; after it, grants matched production exactly. V6 not run. |

Re-rehearse after any change to the backup method, after a Postgres major upgrade, and at least every 6 months.

---

## Appendix: anon-key rotation (wishlist P6)

Execute only on key exposure:
1. Rotate the anon key in the Supabase dashboard (API settings).
2. Update `SUPA_KEY` in `index.html` (the only client consumer).
3. Redeploy; verify `BUILD_TS` and a clean app load.
4. Append a line to `docs/execution-ledger.md`.
