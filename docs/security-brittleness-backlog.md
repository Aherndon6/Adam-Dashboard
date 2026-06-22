# Herndon Financial OS — Security & Architecture Backlog

**Version:** 1.0
**Date:** Cal Wk 25 (Jun 22, 2026)
**Purpose:** Track security, auth-hardening, and architecture items that are important but not required for Auth v1 build authorization. All items here are also tracked in the OS Wishlist tab.
**Related specs:** docs/auth-spec-v1.4.md (Auth v1 build spec), docs/stabilization-roadmap-spec.md (S1 closed)

---

## Auth v1 Build Blockers (not tracked here — tracked in auth-spec-v1.4.md)

The following are required for Auth v1 and are NOT in this backlog — they must be completed before push:
- Hardened `is_allowed_user()` SECURITY DEFINER function
- No live data fetch using `SUPA_H` after auth
- Login shell → authenticate → authorize → loadAll() startup sequence
- Playwright network assertion (Bearer token, not anon key)
- RLS tightening verification (unauthenticated request blocked after policy change)
- Credentials hygiene (.env, no password logging, no screenshot capture)
- Ask/Claude API key not loaded or visible before `ready` state

---

## Post-Auth Near-Term Backlog

| ID | Item | Risk | Severity | Blocking for Auth v1? | Target | Wishlist |
|---|---|---|---|---|---|---|
| 8 | MFA for owner Supabase account | Account compromise | High | No | Shortly after auth lands | ✓ |
| 9 | Backup owner account | Lockout | High | No | Shortly after auth lands | ✓ |
| 10 | Migrate RLS to auth.uid() (from email) | Email change breaks auth | Medium | No | Before second user added | ✓ |
| 11 | Enforce roles (owner/editor/viewer) | Unauthorized write access | Medium | No | Before Wendy/CPA access | ✓ |
| 12 | Anthropic key → Supabase vault / edge function | Key exposure | High | No | Before wider access | ✓ |
| 13 | CDN dependency hardening (supabase-js SRI/vendor) | Supply chain | Medium | No | After auth stable | ✓ |
| 14 | Content Security Policy / XSS hardening | XSS / token exfiltration | Medium-High | No | After auth stable | ✓ |
| 15 | Session and token policy review | Session hijack, shared computers | Medium | No | After auth stable | ✓ |
| 16 | Supabase audit and access logging | No visibility into access | Medium | No | Before second user | ✓ |
| 17 | Formal versioned SQL migration scripts | Undocumented schema state | Medium | No | Before multiple contributors | ✓ |
| 18 | Data export and backup plan | Data loss | Medium | No | After auth stable | ✓ |

---

## Later Backlog — Auth+ (after role enforcement)

| ID | Item | Risk | Severity | Blocking? | Target | Wishlist |
|---|---|---|---|---|---|---|
| 19 | In-app user management UI | Manual Supabase management required | Low | No | After role enforcement | ✓ |
| 20 | User invite flow | No self-serve onboarding | Low | No | After in-app user mgmt | ✓ |
| 21 | Forgot-password UI | Password reset requires Supabase dashboard | Low | No | Nice-to-have | ✓ |
| 22 | Read-only viewer dashboard mode | All users have full write access | Medium | No | Before Wendy/viewer access | ✓ |
| 23 | CPA / advisor access mode | No scoped read-only access | Medium | No | Before CPA access | ✓ |
| 24 | Wendy access mode | No family member access | Low | No | Before Wendy access | ✓ |
| 25 | Role-aware UI suppression | RLS enforces but UI still shows edit controls | Medium | No | With role enforcement | ✓ |

---

## Platform / Architecture Brittleness

| ID | Item | Risk | Severity | Blocking? | Target | Wishlist |
|---|---|---|---|---|---|---|
| P1 | Auto-derive START_CHK/START_SAV from reconciliation (TD-8) | Model drift from reality | High | No | Before model is substantially wrong | ✓ |
| P2 | Write debouncing on toggleTask / saveNote | Race conditions, Supabase spam | Low | No | Anytime | ✓ |
| P3 | Input validation on Supabase write paths | Corrupted data in DB | Medium | No | Before wider access | ✓ |
| P4 | Model re-baseline procedure for 2027 | App breaks after Cal Wk 53 | High | No | Before Jan 2027 | ✓ |
| P5 | updated_at triggers on write tables | No change tracking on reconciliation/tasks/notes | Low | No | Low-hanging fruit | ✓ |
| P6 | Supabase anon key rotation procedure | Key permanently in git history | Medium | No | Document now, execute if needed | ✓ |
| P7 | ~~`custom_task_meta` JSONB type error on goals write~~ | ~~400 on every page load; metadata not persisted to DB~~ | ~~Medium~~ | ~~No~~ | **FIXED in Auth v1 build** | — |

---

## Item Detail Notes

### Item 8 — MFA
Enable TOTP-based MFA in Supabase Auth dashboard for `adam@herndons.us`. No code change required. Prevents account compromise even if password is exposed.

### Item 9 — Backup owner account
Create second Supabase Auth account (e.g. backup@herndons.us or a Wendy email), insert into `app_users` as `role=owner`. If Adam's account is locked or compromised, backup owner can access. No code change required.

### Item 10 — auth.uid() migration
Current `is_allowed_user()` uses email match. Email can change. `auth.uid()` is the permanent UUID assigned at account creation. Migration path: populate `auth_user_id` on all app_users rows, then rewrite `is_allowed_user()` to use `auth.uid()` instead of email. The column is already present (nullable) from auth v1.

### Item 11 — Role enforcement
`app_users.role` column is seeded but `is_allowed_user()` only checks `active = true`. To enforce roles: extend the function to accept a `required_role` parameter, or create role-specific variants. Design sketch is in docs/auth-spec-v1.3.md Section 5.3.

### Item 12 — Anthropic key storage
Current: user enters API key in the UI; stored in `goals` table via Supabase. Protected by RLS after auth lands, but key is still stored as a plain value in a data table. Better: Supabase vault (encrypted column), or route all Anthropic calls through a Supabase Edge Function that holds the key as an environment variable server-side. Edge function path removes the key from the browser entirely. See existing wishlist item "Ask Claude API key security — backend proxy."

### Item 13 — CDN hardening
The auth build loads supabase-js from `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js`. If the CDN is compromised or the package is tampered with, the app loads malicious code. Mitigations: (a) pin to exact version (already done via `@2/dist/umd`), (b) add SRI hash via `integrity=` attribute on the script tag, (c) vendor the file to `tools/supabase.js` and load locally. Option (c) is the most robust but requires manually updating the vendored file on upgrades.

### Item 14 — Content Security Policy
GitHub Pages can only set CSP via `<meta http-equiv="Content-Security-Policy">` tag in `<head>`. A restrictive CSP would prevent injected scripts from running and block exfiltration of localStorage tokens to unknown origins. Challenge: the app uses inline `<script>` blocks and `onclick=` handlers which require `unsafe-inline` for scripts. `unsafe-inline` significantly weakens CSP. Evaluate feasibility of moving toward event listeners and separate JS to enable a useful CSP.

### Item 15 — Token policy
Supabase default: 1-hour access token, 30-day refresh. Consider: shorter refresh window for shared computers, auto-logout on inactivity, explicit "remember me" toggle. No code change for shorter window — Supabase Auth settings only.

### Item 16 — Audit logging
Supabase dashboard shows auth logs (logins, failures). For data write visibility, a lightweight `audit_log` table (table_name, action, performed_by, performed_at) could be written on each significant write. Overkill for single-user v1 but needed before multiple users or before any financial write capability is shared.

### Item 17 — SQL migration scripts
Current approach: run DDL directly in Supabase SQL editor. No version history of schema changes. As complexity grows, a `docs/sql/` directory with numbered migration files (e.g. `001_create_app_users.sql`, `002_create_is_allowed_user.sql`) would give an auditable history and enable repeatable deploys.

### Item 18 — Data backup
Supabase Pro includes daily backups. Verify backup cadence in Supabase dashboard. Add a procedure for manual JSON export of all tables (via Supabase table editor CSV export or API). Document recovery procedure for bad writes (restore specific table from backup, or manually re-enter from paper/CSV).

### Item P1 — START_CHK / START_SAV drift (TD-8)
The most impactful platform gap. Every week the model diverges from reality because starting balances are hardcoded. Fix: on load, find the most recently reconciled week, use its actual balances as the model starting point. This is model-affecting — requires a spec and ChatGPT review before build. Do not delay past mid-2026.

### Item P4 — 2027 re-baseline
When Cal Wk 53 (Jan 9, 2027) passes, the 31-week model window is exhausted. The app needs: new START_CHK/START_SAV from the final reconciliation, new calendar week range (Cal Wk 1 2027 through Cal Wk 31 2027), new goal states (carry funded amounts forward), and potentially new goal targets. This should be planned by Nov 2026 at the latest.

### Item P7 — custom_task_meta goals write error (FIXED)

**Fixed in Auth v1 build (Cal Wk 25, Jun 22 2026).**

Root cause (confirmed via PostgREST error body): `goals.value` column type is `NUMERIC`. `saveCustomTaskMeta()` sends `JSON.stringify(customTaskMeta)` — a JSON string — which PostgreSQL rejects with 22P02 "invalid input syntax for type numeric". The same bug silently affected `saveApiKey` (Anthropic key stored in goals), which fell back to localStorage without persisting to Supabase.

Fix: `ALTER TABLE public.goals ALTER COLUMN value TYPE text USING value::text` (one SQL step in Supabase). Code was always correct — the bug was in the schema. Read path updated with defensive string/object check for future compatibility. Two regression tests added.

### Item P6 — Anon key rotation
The Supabase anon key is embedded in every commit of `index.html` since the beginning of the project. Even after auth makes the key powerless for data access, it is permanently in git history. If the Supabase project is ever made public or the repo is shared, the key history is exposed. Rotation procedure: (1) generate new anon key in Supabase dashboard, (2) update SUPA_KEY in index.html, (3) push, (4) verify app loads. The old key is invalidated immediately. Old commits remain in history but the old key is no longer valid.

---

## Prioritization Recommendation

**Do immediately after auth v1 closes:**
- Item 8 (MFA) — one-time Supabase dashboard action, zero code
- Item 9 (backup owner) — one SQL insert, zero code
- Item P1 (START_CHK drift) — most impactful architecture item, needs its own spec

**Before adding a second user (Wendy / CPA):**
- Item 11 (role enforcement)
- Item 22 (viewer mode)
- Item 16 (audit logging)
- Item 25 (role-aware UI suppression)

**Before any public exposure or key sharing:**
- Item 12 (Anthropic key → vault)
- Item 14 (CSP hardening)
- Item P6 (key rotation if repo ever goes public)

**Before Jan 2027:**
- Item P4 (model re-baseline procedure)

---

*All items except auth v1 blockers are future builds. None require action before auth v1 push authorization.*
