# Herndon Financial OS — Authentication / Access Control Spec

**Version:** 1.2
**Date:** Cal Wk 25 (Jun 22, 2026)
**Status:** For review — no build authorized until approved by ChatGPT
**Scope:** Auth layer only. Zero model behavior changes.
**Changes from v1.1:** Replaced hardcoded email RLS with `app_users` allowlist table and `is_allowed_user()` SECURITY DEFINER function. Added Option A vs Option B comparison. Updated migration plan, test plans, and open questions.

---

## 1–3. Current State, Tables, and Target Access Model

*Unchanged from v1.1. All 9 tables move to authenticated-only access. No anon access. No exceptions.*

See v1.1 Sections 1–3 for the full table-by-table breakdown.

---

## 4. Auth Approach — Supabase Auth with Email + Password

*Unchanged from v1.1. supabase-js loaded from CDN for auth functions only. No build step change.*

---

## 5. Access Control Design — Option A vs Option B

### Option A: Hardcoded Email in RLS (Rejected)

```sql
-- Every policy on every table would contain:
USING (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us')
```

| | |
|---|---|
| **Pros** | Simple. No extra table. Fewer moving parts. |
| **Cons** | Brittle. Changing login email requires updating every RLS policy on all 9 tables (36+ policy edits). Adding Wendy, a CPA, or an advisor requires the same. No role distinction possible without a full redesign. |
| **Verdict** | Rejected. Too rigid for a system that will evolve. |

---

### Option B: app_users Allowlist Table (Recommended)

A lightweight allowlist table controls who has access. RLS on all data tables delegates to a single `is_allowed_user()` function that checks the allowlist.

**Benefits:**
- Change Adam's login email: update one row in `app_users`, zero policy changes
- Add Wendy, a CPA, or an advisor: insert one row, zero policy changes
- Revoke access: set `active = false` on one row
- Add role-based access later: extend the function, not the policies
- One place to audit and manage access

---

## 6. app_users Table

### 6.1 Schema

```sql
CREATE TABLE app_users (
  email      TEXT PRIMARY KEY,
  role       TEXT NOT NULL DEFAULT 'viewer',
  active     BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 6.2 Initial Seed

```sql
INSERT INTO app_users (email, role, active)
VALUES ('adam@herndons.us', 'owner', true);
```

This row must exist before any RLS policy changes go live. Seeding `app_users` is Step 1 of Phase 3 in the migration plan.

### 6.3 Role Framework

For v1, all active `app_users` have full read/write access regardless of role. The role column is seeded and reserved for future use.

| Role | v1 Access | Future Intent |
|---|---|---|
| `owner` | Full read/write | Manages app_users, budget_rules, goal_registry |
| `editor` | Full read/write (v1) | Limited write — no budget_rules or goal_registry changes |
| `viewer` | Full read/write (v1) | Read-only on all tables |

Role enforcement beyond `owner` is out of scope for this build. The column exists so it can be used in policy conditions later without a schema migration.

### 6.4 updated_at Trigger

```sql
CREATE OR REPLACE FUNCTION set_app_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER app_users_updated_at
  BEFORE UPDATE ON app_users
  FOR EACH ROW EXECUTE FUNCTION set_app_users_updated_at();
```

### 6.5 RLS on app_users

`app_users` must not be publicly writable. It is managed via Supabase dashboard only.

```sql
ALTER TABLE app_users ENABLE ROW LEVEL SECURITY;

-- Active users can read their own row (to check their own access status)
CREATE POLICY "read_own_row" ON app_users
  FOR SELECT TO authenticated
  USING (lower(email) = lower((auth.jwt() ->> 'email')::text));

-- No INSERT / UPDATE / DELETE policies on app_users via the app.
-- All app_users management is done via Supabase dashboard only.
```

This means only Adam (via Supabase dashboard) can add, modify, or deactivate users. No in-app user management UI is included in this build.

---

## 7. is_allowed_user() — SECURITY DEFINER Function

### 7.1 Why SECURITY DEFINER

If every data table's RLS policy contained an inline `EXISTS (SELECT 1 FROM app_users ...)` subquery, that subquery would itself be subject to `app_users`'s RLS. That works — Adam can see his own row — but it creates a layered RLS dependency that is difficult to debug and fragile under schema changes.

A `SECURITY DEFINER` function runs with elevated privileges (the function definer's role, not the caller's), bypassing RLS on `app_users`. This means the access check is clean, fast, and centralized. All 36+ policies across 9 tables call the same function. If the check logic ever changes (e.g. adding role enforcement), only the function is updated.

### 7.2 Implementation

```sql
CREATE OR REPLACE FUNCTION is_allowed_user()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM app_users
    WHERE lower(app_users.email) = lower((auth.jwt() ->> 'email')::text)
      AND app_users.active = true
  );
$$;
```

**Properties:**
- `SECURITY DEFINER` — bypasses RLS on `app_users` for the subquery
- `STABLE` — safe for use in RLS policies (does not modify data, result is stable within a transaction)
- Returns `true` if the authenticated user's email appears in `app_users` with `active = true`
- Returns `false` for any unauthenticated request or email not in the allowlist

### 7.3 Future Role Extension (Example Only — Not Built in v1)

When role-based access is needed, the function can be replaced without touching any policy:

```sql
-- Future: check for specific role
CREATE OR REPLACE FUNCTION is_allowed_user(required_role TEXT DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM app_users
    WHERE lower(app_users.email) = lower((auth.jwt() ->> 'email')::text)
      AND app_users.active = true
      AND (required_role IS NULL OR app_users.role = required_role)
  );
$$;
```

This is illustrative only. v1 uses the no-argument form.

---

## 8. RLS Policies Using is_allowed_user()

### 8.1 Pattern for All Data Tables

Replace all existing anon policies with:

```sql
-- Example: weekly_reconciliations (repeat for all 8 previously-unrestricted tables)
CREATE POLICY "allowed_user_select" ON weekly_reconciliations
  FOR SELECT TO authenticated
  USING (is_allowed_user());

CREATE POLICY "allowed_user_insert" ON weekly_reconciliations
  FOR INSERT TO authenticated
  WITH CHECK (is_allowed_user());

CREATE POLICY "allowed_user_update" ON weekly_reconciliations
  FOR UPDATE TO authenticated
  USING (is_allowed_user())
  WITH CHECK (is_allowed_user());
```

For tables where DELETE is used (`model_week_overrides`):

```sql
CREATE POLICY "allowed_user_delete" ON model_week_overrides
  FOR DELETE TO authenticated
  USING (is_allowed_user());
```

### 8.2 goal_registry

Replace existing anon SELECT policy:

```sql
DROP POLICY IF EXISTS "anon_select" ON goal_registry;

CREATE POLICY "allowed_user_select" ON goal_registry
  FOR SELECT TO authenticated
  USING (is_allowed_user());
```

### 8.3 Existing Policy Cleanup (Run First)

Before adding new policies, audit existing ones:

```sql
SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE tablename IN (
  'goals','weekly_reconciliations','weekly_tasks','weekly_notes',
  'model_week_overrides','wishlist_items','custom_tasks',
  'budget_rules','goal_registry'
)
ORDER BY tablename, cmd;
```

Drop any policy granting `TO anon` or using `USING (true)` without a user check.

---

## 9. getAuthHeaders() and Function Inventory

*Unchanged from v1.1. All functions listed in v1.1 Section 5.2 still apply.*

```javascript
async function getCurrentSession() {
  var result = await _supabase.auth.getSession();
  return result.data && result.data.session ? result.data.session : null;
}

async function getAuthHeaders(extra) {
  var session = await getCurrentSession();
  var token = session && session.access_token;
  if (!token) throw new Error('[Auth] No authenticated session — cannot fetch data');
  return Object.assign({}, {
    apikey: SUPA_KEY,
    Authorization: 'Bearer ' + token,
    'Content-Type': 'application/json'
  }, extra || {});
}
```

Functions to update (identical to v1.1): `loadAll()`, `loadWishlist()`, `mergeSeedWishlist()`, `phaseMigrateWishlist()`, `saveWishlistItem()`, `saveRecon()`, `toggleTask()`, `saveNote()`, custom task write, override write/delete, `saveApiKey()`.

---

## 10. Login / Logout UX

*Unchanged from v1.1.*

---

## 11. GitHub Pages Deployment Impact

*Unchanged from v1.1. CDN supabase-js, no build step change, anon key stays in file but RLS blocks unauthenticated access.*

---

## 12. Migration Plan — No Lockout Risk

**Rule: code ships first. RLS changes after code is verified. app_users seeded before RLS changes.**

### Phase 1 — Auth Code Only (anon RLS unchanged)

1. Add supabase-js CDN script tag
2. Initialize `_supabase` client
3. Implement `getCurrentSession()`, `getAuthHeaders()`
4. Implement login overlay, `onAuthStateChange`, logout
5. Gate `loadAll()` and `renderApp()` on valid session
6. Update all functions in the inventory to use `await getAuthHeaders()`
7. Run full regression (596/0) and Playwright (46/0)
8. Push to GitHub Pages
9. Verify login works end-to-end on live deployment

### Phase 2 — Supabase Setup (before RLS changes)

1. Create `app_users` table with schema and trigger
2. Seed `adam@herndons.us / owner / true`
3. Apply RLS to `app_users` (read-own-row only, no write policies)
4. Create `is_allowed_user()` SECURITY DEFINER function
5. Verify function returns `true` for Adam's session by running directly in Supabase SQL editor:
   ```sql
   -- Run while authenticated as adam@herndons.us
   SELECT is_allowed_user();
   -- Must return: true
   ```

### Phase 3 — JWT Verification Before Removing Anon Policies

Before any anon policy is removed, confirm post-login requests use the session JWT not the anon key. AUTH-E2E-6 (Playwright network assertion) must pass. Do not proceed until this test passes.

### Phase 4 — RLS Tightening (one table at a time)

1. Drop anon policies and add `is_allowed_user()` policies, one table at a time
2. Order: `wishlist_items` → `weekly_notes` → `weekly_tasks` → `custom_tasks` → `weekly_reconciliations` → `model_week_overrides` → `budget_rules` → `goals` → `goal_registry`
3. After each table: reload live app, confirm no console errors, no blank panels
4. After all 9 tables: run full Playwright suite against live deployment

---

## 13. Rollback Plan

*Unchanged from v1.1, with one addition:*

| Scenario | Rollback action |
|---|---|
| `app_users` empty or Adam's row missing | Insert row in Supabase dashboard — instant |
| `is_allowed_user()` function broken | Revert to inline email check in policies, or restore anon policies temporarily |
| All others | See v1.1 Section 10 |

---

## 14. Regression Test Plan

*Sections AUTH-A, AUTH-B, AUTH-C, AUTH-D unchanged from v1.1.*

### New: AUTH-E — app_users and is_allowed_user() (3 tests)

- AUTH-E1: Mock `is_allowed_user()` returning `true` — `loadAll()` proceeds normally
- AUTH-E2: Mock `is_allowed_user()` returning `false` — `loadAll()` is blocked, login overlay shown
- AUTH-E3: `app_users` seed check — row with `email = 'adam@herndons.us'`, `role = 'owner'`, `active = true` must exist before RLS phase begins (migration gate test)

**Total new regression tests: 15. New total: 611.**

---

## 15. Playwright Test Plan

*AUTH-E2E-1 through AUTH-E2E-7 unchanged from v1.1.*

### New: AUTH-E2E-8 — allowlist behavior

- AUTH-E2E-8: After login as `adam@herndons.us`, confirm `app_users` returns exactly one row with `active = true` (verifies allowlist is seeded and query works)

**New total Playwright tests: 54.**

Credentials handling unchanged from v1.1: `.env` gitignored, fail-fast if missing, no password logged, no password captured in screenshots.

---

## 16. What Will Not Change

*Identical to v1.1 Section 13. No model functions, constants, waterfall behavior, or table schemas change.*

---

## 17. No Model Behavior Changes — Confirmation

*Identical to v1.1 Section 14. AUTH-C regression gate is the machine-verifiable proof.*

---

## Summary of Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Auth provider | Supabase Auth, email + password | Single user, persistent sessions, client-side compatible |
| supabase-js | CDN UMD, auth functions only | No build step change; data calls stay as raw fetch |
| Access control | Option B: app_users allowlist | Flexible, not brittle; add/change users without touching policies |
| RLS check | `is_allowed_user()` SECURITY DEFINER | Centralized, debuggable, bypasses layered RLS dependency |
| Role column | Present but unenforced in v1 | Reserved for future role-based access without schema migration |
| app_users management | Supabase dashboard only | No in-app user management UI in v1 |
| Forgot-password | Supabase dashboard only | Acceptable for single-user app |
| wishlist_items | Auth-only | No anon exceptions |

---

*Spec v1.2. No build authorized until approved by ChatGPT.*
