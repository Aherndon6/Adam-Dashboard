# Restore Runbook

**Status:** TEMPLATE — draft as DR-1 gate item 5; complete one tabletop walkthrough. **Secrets-free** — reference the password-manager entries and `docs/environment-manifest.md`; never inline credentials.
**Authority:** `docs/roadmap/canonical-roadmap.md` §5 / §14 (AF-1, AF-3). **Scope:** how to bring the Herndon Financial OS back from database loss, source loss, environment loss, credential loss, or full-project loss. The OS is the **sole live system of record** (Quicken retired) — this runbook is the recovery of record.

**Derived-vs-observed doctrine (read first):** the model derives state from constants + reconciliation history; observed bank balances are the ground truth for reconciliation, not the model's internal projections. On restore, verify **observed** balances against statements before trusting any derived figure. Never edit golden-master expected outputs to make a restored build "look right."

---

## A. Database restore (public-schema dump)

1. Identify the latest verified dump (see the dump-metadata doc; confirm SHA-256 + `pg_restore --list`).
2. Provision / select the target Supabase project (see `docs/environment-manifest.md` §1).
3. `pg_restore` the custom-format public-schema dump (`-Fc`, `--no-owner --no-acl`).
4. Validate: row counts per table vs the metadata doc; the Week-5 anchor row count; the two new SECURITY DEFINER functions present and owner-pinned; grants match the §4 restore target.
5. **The `auth` schema is NOT in this dump** — if this is a same-project restore, existing `auth.users` are intact and no re-link is needed. If this is a **full-project-loss** restore, go to §D before the app will authorize anyone.

## B. Source redeploy

1. Restore the repo from `origin/main`, a second-machine clone, or the off-device `git bundle` (all branches).
2. Confirm `origin/main` == the intended deployed build (commit hash in `docs/environment-manifest.md` §2 / the DR-1 record).
3. GitHub Pages auto-deploys on push to `main`. If Pages is unavailable, any static host can serve `index.html` — point DNS (`dashboard.herndons.us`) per the manifest.
4. Verify `BUILD_TS` in the deployed `index.html` matches the intended build.

## C. Environment / configuration restore

Restore from `docs/environment-manifest.md`: Supabase refs + `system_identifier`s; DNS/CNAME; the post-Phase-2 grant matrix as the target; the RLS role model. Verify `system_identifier` on the restored project matches (or is deliberately re-recorded for a new project).

## D. Full-project-loss auth re-link (AF-1 — REQUIRED)

*A successful data restore still produces total lockout in a rebuilt project: the public-schema dump does not carry `auth.users`; the rebuilt project issues **new** auth UUIDs; the restored `app_users.auth_user_id` values point at the old ones, so `is_allowed_user()` / `is_owner()` return false for everyone.* Recovery is possible **only because it is written down here** — the SQL Editor / service role bypasses RLS.

1. **Recreate the authorized Auth users** in the rebuilt project: `aherndon6@gmail.com` (owner) and `wherndon22@gmail.com` (household_admin). *(Do not recreate `adam@herndons.us` as an app login — seed-UUID only.)*
2. **Capture the new Auth UUIDs** for each recreated user (from the Auth users list / `auth.users`).
3. **Re-link `app_users.auth_user_id`** via the SQL Editor / service role (bypasses RLS):
   ```sql
   -- run as service role / SQL Editor; substitute the captured UUIDs
   update public.app_users set auth_user_id = '<new-adam-auth-uuid>'  where email = 'aherndon6@gmail.com';
   update public.app_users set auth_user_id = '<new-wendy-auth-uuid>' where email = 'wherndon22@gmail.com';
   ```
4. **Verify authorization for each authorized user:**
   ```sql
   -- expect: Adam is_allowed_user()=true, is_owner()=true; Wendy is_allowed_user()=true, is_owner()=false
   select email, auth_user_id, role from public.app_users order by email;
   ```
   Then confirm at real login: Adam authorizes and `is_owner()` true; Wendy authorizes and `is_owner()` false.
5. **Verify Wendy's role posture and the owner-only secret carve-out:** Wendy = household_admin (full financial operating), and Wendy **cannot** write the `anthropic_key` row (the owner-only carve-out). Adam retains platform/admin access.
6. Committed materials stay **secrets-free** — capture UUIDs in the local recovery worksheet only, never in a committed file.

## E. Credential recovery

Owner MFA + recovery codes (two locations, off-device); backup-owner account; Supabase org recovery email; password-manager entries per `docs/environment-manifest.md`. If MFA device is lost, use the recovery codes; if both are lost, use the backup-owner account, then re-enroll.

## F. Supabase inactivity-pause recovery (AF-3 / A19)

Free-tier projects have historically been **paused after ~1 week of API inactivity**. Under the Alaska skip posture (both operators traveling, near-zero traffic `Jul 29 – Aug 10`), the production project may be **paused on Aug 11** — recoverable, not lost.
1. **Verify the current pause policy** against both prod and staging before departure (A19). Record the finding + evidence in `docs/environment-manifest.md` §1. *Do not represent the policy as verified without current evidence; no plan upgrade is implied by this step.*
2. **Unpause:** open the Supabase dashboard for the project → restore/unpause → wait for the project to resume → confirm the REST API answers and the app loads.
3. If pause is likely and connectivity allows, one mid-trip app-open resets the inactivity clock (optional; never a closeout — read-only, per the trip rules).

---

## Appendix — Anon-key rotation (wishlist P6)

Execute only on key exposure/publication:
1. Rotate the anon key in the Supabase dashboard (API settings).
2. Update the key in `index.html` (the only client consumer).
3. Redeploy (`push_to_github.sh`); verify `BUILD_TS` and a clean app load.
4. Append a line to `docs/execution-ledger.md` (config change touching prod behavior).

---

*Secrets-free, balance-free runbook. Complete one tabletop walkthrough for DR-1. Update whenever the recovery topology changes.*
