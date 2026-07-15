# Environment / Configuration Manifest (recovery target)

**Status:** TEMPLATE — complete as DR-1 gate item 3. **Secrets-free** — this file records *identifiers, pointers, and where-to-find-it*, never credentials, tokens, keys, or connection strings. Those live in the password manager (see the "location pointer" columns).
**Authority:** `docs/roadmap/canonical-roadmap.md` §5. **Use:** the restore target of record — what a rebuilt environment must match. Read alongside `docs/restore-runbook.md`.

---

## 1. Supabase projects

| Role | Project ref | `system_identifier` | Plan | PITR | Location pointer (password manager entry) |
|---|---|---|---|---|---|
| Production | `usayoldrawwmjsmretin` | `7632885393857617092` | Free | none | `__________` |
| Staging | `pkwotgqivgaapwuqgwqb` | `7656985631720456337` | Free | none | `__________` |

- Owner login (app identity): `aherndon6@gmail.com` (owner). Household admin: `wherndon22@gmail.com`.
- `adam@herndons.us` exists in `auth.users` for seed-UUID purposes only; it is **not** an app login.
- Supabase org recovery email verified: [ ].
- **Inactivity-pause policy (A19 / AF-3):** verified `__________` (date + evidence); unpause step in `docs/restore-runbook.md`.

## 2. Hosting / DNS

| Item | Value | Location pointer |
|---|---|---|
| Host | GitHub Pages, repo `Aherndon6/Adam-Dashboard`, deploys on push to `main` | — |
| Custom domain / CNAME | `dashboard.herndons.us` | — |
| DNS provider | `__________` | `__________` (registrar/DNS login) |
| Push command | `bash push_to_github.sh "message"` (gates on both test suites) | — |
| `BUILD_TS` convention | pre-commit hook stamps `index.html` `BUILD_TS` and stages it; use `git commit --no-verify` for docs/SQL-only commits to keep `index.html` untouched | — |

## 3. Authorization / RLS role model (restore target)

- RLS enforced at the DB level across all financial tables; helpers key on `auth.uid()` + role (`is_allowed_user()`, `is_owner()`, `can_write_financials()`) — **not** email (Phase 4B).
- Adam = owner (full financial + platform/admin). Wendy = household_admin (full financial operating; **cannot** write the `anthropic_key` row).
- **Auth re-link on full-project-loss (AF-1):** authorization keys on `app_users.auth_user_id = auth.uid()`; the public-schema dump does **not** capture `auth.users`. A rebuilt project issues new auth UUIDs → `app_users.auth_user_id` must be re-linked. Procedure in `docs/restore-runbook.md`.

## 4. Grant matrix (post-Phase-2 restore target)

The final post-Phase-2 grant posture (operator package §4) is the restore target: wrapper (`save_weekly_closeout_with_snapshots`) + Option B (`correct_goal_funding_snapshot`) = owner path only; old recon RPC / repair RPC / direct snapshot RPC / table INS/UPD(/DEL) = revoked. Pointer to the authoritative matrix: `docs/phase-5g-1d-gatec-register-2026-07-13.md` and `docs/phase-5g-1d-activation-*.sql`.

## 5. Anon-key rotation

Procedure pointer (wishlist P6): `docs/restore-runbook.md` appendix. Execute only on exposure/publication.

---

*Secrets-free manifest. Update when any identifier, host, DNS, or grant-target changes. No credentials in this file — ever.*
