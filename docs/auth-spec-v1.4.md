# Herndon Financial OS — Authentication / Access Control Spec

**Version:** 1.4
**Date:** Cal Wk 25 (Jun 22, 2026)
**Status:** For review — build authorized only after ChatGPT approval of this version
**Scope:** Auth layer only. No existing model/data table schemas change.
**Changes from v1.3:** Hardened SECURITY DEFINER SQL (schema-qualified, search_path, REVOKE/GRANT). Removed SQL editor verification; replaced with app/Playwright verification. Clarified is_allowed_user() as RLS-only; app reads app_users row directly for authorization check. Fixed auth_user_id as nullable (Option A). Fixed schema-change language. Fixed app_users self-read policy wording. Tightened Phase 3 migration gate (grep + network assertion + unauthenticated failure test).

---

## 1. Current Supabase RLS Posture by Table

| Table | anon SELECT | anon INSERT | anon UPDATE | anon DELETE | Notes |
|---|---|---|---|---|---|
| `goals` | ✓ | ✓ | ✓ | ✓ | KV store — akFunded, IRA flags, Anthropic API key |
| `weekly_reconciliations` | ✓ | ✓ | ✓ | ✓ | Per-week actual balances |
| `weekly_tasks` | ✓ | ✓ | ✓ | ✓ | Per-task completion state |
| `weekly_notes` | ✓ | ✓ | ✓ | ✓ | Per-week text notes |
| `model_week_overrides` | ✓ | ✓ | ✓ | ✓ | Custom week event overrides |
| `wishlist_items` | ✓ | ✓ | ✓ | ✓ | Feature wishlist |
| `custom_tasks` | ✓ | ✓ | ✓ | ✓ | User-created weekly tasks |
| `budget_rules` | ✓ | ✓ | ✓ | ✓ | Recurring/one-time adjustments |
| `goal_registry` | ✓ | ✗ | ✗ | ✗ | SELECT-only RLS — Phase 6A |

**Target:** All 9 tables require authentication AND allowlist authorization. No anon access. No exceptions.

---

## 2. Authentication vs. Authorization — Explicit Distinction

**Authentication** = the user has a valid Supabase Auth session (email + password verified, JWT issued).

**Authorization** = the authenticated user's email exists in `app_users` with `active = true`.

A valid Supabase session is **not sufficient** for app access. Both gates must pass before data is loaded.

The app enforces both in sequence:
1. Authenticate via Supabase Auth → establishes JWT session
2. Read own `app_users` row → verify `active = true`
3. Only then: `loadAll()` → `renderApp()`

`is_allowed_user()` enforces this at the database layer in RLS policies. The app enforces it in the startup sequence as a UI gate. Both independently block unauthorized data access.

---

## 3. Auth State Machine

Six states. State determines which UI surface renders. `loadAll()` is called only from `ready` transition.

```
                    ┌─────────────────────┐
                    │   checking_session   │  ← page load
                    └────────┬────────────┘
                             │ getSession()
              ┌──────────────┼──────────────┐
              │              │              │
         no session      session ok      throws
              │              │              │
              ▼              ▼              ▼
    ┌──────────────┐  ┌─────────────┐  ┌────────────┐
    │unauthenticated│  │authenticated│  │ auth_error │
    └──────────────┘  └──────┬──────┘  └────────────┘
    show login form           │ SELECT from app_users
                    ┌─────────┴──────────┐
                    │                    │
               row found            no row / inactive
               + active = true           │
                    │                    ▼
                    ▼             ┌─────────────┐
             ┌──────────┐        │unauthorized │
             │  ready   │        └─────────────┘
             └──────────┘      "Access denied" + sign-out
          loadAll() →          do NOT call loadAll()
          renderApp()

    onAuthStateChange:
      SIGNED_OUT         → unauthenticated
      TOKEN_REFRESHED    → stay in current state (transparent)
      refresh failure    → session_expired

    ┌─────────────────┐
    │  session_expired │  ← token refresh failed mid-session
    └─────────────────┘
    show login form + "Your session expired" banner
```

### State Definitions

| State | Meaning | UI Surface |
|---|---|---|
| `checking_session` | `getSession()` in flight | Login shell / minimal spinner |
| `unauthenticated` | No session | Login form, no error |
| `authenticated` | Session valid; app_users check pending | Login shell / minimal spinner |
| `unauthorized` | Session valid; not in app_users or inactive | "Access denied" + sign-out link only |
| `session_expired` | Token refresh failed mid-session | Login form + "Your session expired" banner |
| `auth_error` | `getSession()` threw or Supabase unreachable | Error banner + retry button |
| `ready` | Auth + authorization passed; data loaded | Full dashboard |

`unauthorized` ≠ `unauthenticated`. The UI must not display a login form in the `unauthorized` state — the user is already authenticated, just not allowed. Showing a login form would imply a wrong password, which is misleading.

No dashboard content, API keys, or model data are visible in any state other than `ready`.

---

## 4. app_users Allowlist Table

### 4.1 Design: Option B — Allowlist Table (Adopted)

Option A (hardcoded email in every RLS policy) was rejected. Changing login email or adding a trusted user would require editing all 36+ policies across 9 tables. Option B (allowlist table) centralizes access control: a single row change adds, changes, or revokes a user with no policy edits and no code deploy.

### 4.2 Schema

```sql
CREATE TABLE public.app_users (
  email        TEXT PRIMARY KEY,
  auth_user_id UUID UNIQUE,            -- nullable in v1; see note below
  role         TEXT NOT NULL DEFAULT 'viewer',
  active       BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**`auth_user_id`:** Nullable in v1 for bootstrap flexibility — the column is populated from `auth.users.id` at seed time, but if the Supabase Auth account doesn't exist yet when the row is inserted, it can be left null and backfilled. This is explicitly a v1 simplification. `auth.uid()` is more durable than email (email can change; UUID cannot), so populating this column is the likely future migration path for the `is_allowed_user()` function.

### 4.3 Role Framework

| Role | v1 Enforcement | Future Intent |
|---|---|---|
| `owner` | Full read/write (same as all active users in v1) | Manages app_users, budget_rules, goal_registry |
| `editor` | Full read/write (not yet enforced in v1) | Limited write — no schema-affecting tables |
| `viewer` | Full read/write (not yet enforced in v1) | Read-only on all tables |

**v1 simplification:** `is_allowed_user()` checks `active = true` only — role is not yet enforced. This is documented as temporary. Role enforcement is a future build.

### 4.4 updated_at Trigger

```sql
CREATE OR REPLACE FUNCTION public.set_app_users_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER app_users_updated_at
  BEFORE UPDATE ON public.app_users
  FOR EACH ROW EXECUTE FUNCTION public.set_app_users_updated_at();
```

### 4.5 RLS on app_users

`app_users` is managed via Supabase dashboard only. No in-app write path.

```sql
ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can read their own row regardless of active status.
-- This allows inactive users to reach the unauthorized state rather than a confusing error.
-- Data-table access still requires is_allowed_user(), which checks active = true.
CREATE POLICY "app_users_select_self"
  ON public.app_users
  FOR SELECT TO authenticated
  USING (lower(email) = lower((auth.jwt() ->> 'email')::text));

-- No INSERT / UPDATE / DELETE policies — Supabase dashboard management only.
```

**Clarification on wording:** The policy allows any authenticated user to read their own row, including inactive users. This is intentional: an inactive user needs to read their own row to discover they are inactive, so the app can display `unauthorized` rather than a broken state. The `is_allowed_user()` function independently enforces `active = true` for all data table access.

### 4.6 Initial Seed

Run after Adam's Supabase Auth account is created:

```sql
INSERT INTO public.app_users (email, auth_user_id, role, active)
VALUES (
  'adam@herndons.us',
  (SELECT id FROM auth.users WHERE email = 'adam@herndons.us' LIMIT 1),
  'owner',
  true
);
```

If the `auth.users` subquery returns null (account not yet created), omit `auth_user_id` and backfill later:

```sql
UPDATE public.app_users
SET auth_user_id = (SELECT id FROM auth.users WHERE email = 'adam@herndons.us' LIMIT 1)
WHERE email = 'adam@herndons.us';
```

**Verify the row exists before any RLS changes:**

```sql
SELECT email, auth_user_id, role, active FROM public.app_users;
-- Must return: adam@herndons.us | <uuid or null> | owner | true
```

---

## 5. is_allowed_user() — Hardened SECURITY DEFINER Function

### 5.1 Purpose and Scope

`is_allowed_user()` is used **exclusively in RLS policies**. It is not exposed as an RPC and is not called directly by the app or by Playwright tests. The app verifies authorization by reading its own `app_users` row after login (see Section 8).

### 5.2 Hardened Implementation

```sql
CREATE OR REPLACE FUNCTION public.is_allowed_user()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  -- v1: checks email and active status only.
  -- Role-based enforcement is a future build. The role column exists
  -- but is not checked here. All active app_users have equivalent access in v1.
  SELECT EXISTS (
    SELECT 1
    FROM public.app_users
    WHERE lower(public.app_users.email) = lower((auth.jwt() ->> 'email')::text)
      AND public.app_users.active = true
  );
$$;

-- Revoke default execute privilege from PUBLIC (all roles)
REVOKE ALL ON FUNCTION public.is_allowed_user() FROM PUBLIC;

-- Grant execute only to the authenticated role (used by RLS policy evaluation)
GRANT EXECUTE ON FUNCTION public.is_allowed_user() TO authenticated;
```

**Hardening notes:**
- `public.is_allowed_user()` — schema-qualified to prevent search_path hijacking
- `public.app_users` — schema-qualified table reference inside the function body
- `SET search_path = public` — prevents a malicious or misconfigured `search_path` from redirecting the function to a shadow table
- `SECURITY DEFINER` — runs with definer's privileges, bypasses `app_users` RLS in the subquery
- `REVOKE ALL FROM PUBLIC` — removes the default execute grant that PostgreSQL assigns to all functions; closes the path where any database role could call this function
- `GRANT EXECUTE TO authenticated` — only the `authenticated` role (which RLS policy evaluation uses for logged-in Supabase users) can call this function

### 5.3 Verification

The Supabase SQL editor does **not** run with Adam's browser JWT. `auth.jwt()` in the SQL editor context returns null or an empty object, not Adam's session. `SELECT public.is_allowed_user()` in the SQL editor is not a valid verification method and must not be used.

**Correct verification method:**
1. Deploy Phase 1 auth code to GitHub Pages
2. Log in through the deployed app as `adam@herndons.us`
3. Open browser devtools → Network tab
4. Confirm all Supabase REST requests include `Authorization: Bearer <token>` (not just `apikey`)
5. Confirm the dashboard renders (all tables return data)
6. AUTH-E2E-6 Playwright network assertion must pass (see Section 16)
7. Only after Phase 4 RLS tightening: confirm an unauthenticated `curl` to at least one table endpoint returns empty results or 401

---

## 6. RLS Policies — Standardized Naming Convention

Policy naming: `{table}_{action}_app_users`

Auditable via:
```sql
SELECT tablename, policyname, cmd, roles
FROM pg_policies
WHERE tablename IN (
  'goals','weekly_reconciliations','weekly_tasks','weekly_notes',
  'model_week_overrides','wishlist_items','custom_tasks',
  'budget_rules','goal_registry'
)
ORDER BY tablename, cmd;
```

Drop all existing policies before applying new ones.

### Full Policy Set

**goals**
```sql
CREATE POLICY "goals_select_app_users" ON public.goals
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "goals_insert_app_users" ON public.goals
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
CREATE POLICY "goals_update_app_users" ON public.goals
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
```

**weekly_reconciliations**
```sql
CREATE POLICY "weekly_reconciliations_select_app_users" ON public.weekly_reconciliations
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "weekly_reconciliations_insert_app_users" ON public.weekly_reconciliations
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
CREATE POLICY "weekly_reconciliations_update_app_users" ON public.weekly_reconciliations
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
```

**weekly_tasks**
```sql
CREATE POLICY "weekly_tasks_select_app_users" ON public.weekly_tasks
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "weekly_tasks_insert_app_users" ON public.weekly_tasks
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
CREATE POLICY "weekly_tasks_update_app_users" ON public.weekly_tasks
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
```

**weekly_notes**
```sql
CREATE POLICY "weekly_notes_select_app_users" ON public.weekly_notes
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "weekly_notes_insert_app_users" ON public.weekly_notes
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
CREATE POLICY "weekly_notes_update_app_users" ON public.weekly_notes
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
```

**model_week_overrides**
```sql
CREATE POLICY "model_week_overrides_select_app_users" ON public.model_week_overrides
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "model_week_overrides_insert_app_users" ON public.model_week_overrides
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
CREATE POLICY "model_week_overrides_update_app_users" ON public.model_week_overrides
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
CREATE POLICY "model_week_overrides_delete_app_users" ON public.model_week_overrides
  FOR DELETE TO authenticated USING (public.is_allowed_user());
```

**wishlist_items**
```sql
CREATE POLICY "wishlist_items_select_app_users" ON public.wishlist_items
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "wishlist_items_insert_app_users" ON public.wishlist_items
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
CREATE POLICY "wishlist_items_update_app_users" ON public.wishlist_items
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
```

**custom_tasks**
```sql
CREATE POLICY "custom_tasks_select_app_users" ON public.custom_tasks
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "custom_tasks_insert_app_users" ON public.custom_tasks
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
CREATE POLICY "custom_tasks_update_app_users" ON public.custom_tasks
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
```

**budget_rules**
```sql
CREATE POLICY "budget_rules_select_app_users" ON public.budget_rules
  FOR SELECT TO authenticated USING (public.is_allowed_user());
CREATE POLICY "budget_rules_insert_app_users" ON public.budget_rules
  FOR INSERT TO authenticated WITH CHECK (public.is_allowed_user());
CREATE POLICY "budget_rules_update_app_users" ON public.budget_rules
  FOR UPDATE TO authenticated
  USING (public.is_allowed_user()) WITH CHECK (public.is_allowed_user());
```

**goal_registry** (replaces existing anon SELECT policy)
```sql
CREATE POLICY "goal_registry_select_app_users" ON public.goal_registry
  FOR SELECT TO authenticated USING (public.is_allowed_user());
```

---

## 7. getAuthHeaders() and Authenticated Fetch Wrapper

`SUPA_H` (the existing anon header const) is retired for all live data calls. No data read or write may use `SUPA_H` after auth is active. A pre-push grep for `SUPA_H` in non-auth fetch calls confirms no stragglers.

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

**Function inventory** — every function updated to use `await getAuthHeaders()`:

| Function | Operation | Table(s) |
|---|---|---|
| `loadAll()` | SELECT (9 fetches) | All tables |
| `loadWishlist()` | SELECT | `wishlist_items` |
| `mergeSeedWishlist()` | INSERT/UPDATE | `wishlist_items` |
| `phaseMigrateWishlist()` | INSERT/UPDATE | `wishlist_items` |
| `saveWishlistItem()` | INSERT/UPDATE | `wishlist_items` |
| `saveRecon(n)` | INSERT | `weekly_reconciliations` |
| `toggleTask(...)` | INSERT | `weekly_tasks` |
| `saveNote(weekNum, el)` | INSERT | `weekly_notes` |
| custom task write | INSERT/UPDATE | `custom_tasks` |
| override write | INSERT | `model_week_overrides` |
| override delete | DELETE | `model_week_overrides` |
| `saveApiKey()` | INSERT/UPDATE | `goals` |

---

## 8. App Startup Sequence

Login shell renders before any data is loaded. `loadAll()` is never called before both auth gates pass.

```
1. Page loads
2. Render login shell (no data, no dashboard, no API key)
3. setAuthState('checking_session')
4. await _supabase.auth.getSession()
      ├── throws          → setAuthState('auth_error')     → show error UI
      ├── no session      → setAuthState('unauthenticated') → show login form
      └── session found   → setAuthState('authenticated')
              ↓
5. SELECT active FROM public.app_users
   WHERE lower(email) = lower(current user email)
      ├── no row or active = false → setAuthState('unauthorized') → show access denied
      └── active = true            →
              ↓
6. await loadAll()
7. renderApp()
8. setAuthState('ready')

9. Register _supabase.auth.onAuthStateChange:
      SIGNED_OUT      → setAuthState('unauthenticated')
      TOKEN_REFRESHED → no state change
      refresh failure → setAuthState('session_expired')
```

The `app_users` SELECT in step 5 uses `getAuthHeaders()` — same authenticated path as all other data calls. It is a direct table read, not an RPC call to `is_allowed_user()`. The function is used only by RLS policies, not by the app.

---

## 9. Login / Logout UX

**Login form** (shown in `unauthenticated` and `session_expired` states):
- Email field (pre-populated `adam@herndons.us`)
- Password field
- "Sign in" button
- Inline error on failed attempt: "Invalid email or password"
- `session_expired` variant adds banner: "Your session expired. Please sign in again."
- No signup link, no forgot-password link, no public registration

**Unauthorized state** (distinct from login form):
- "Access denied. This account is not authorized to access this application."
- "Sign out" link only — no password field, no login form
- No data visible, no dashboard

**Logout:**
- "Sign out" in dashboard header
- `_supabase.auth.signOut()` called
- Session cleared from localStorage
- `setAuthState('unauthenticated')`

---

## 10. Ask / Anthropic API Key Protection

- Key not loaded before `ready` state — `loadAll()` does not run until auth + authorization pass
- Key not visible in login, session-expired, auth-error, or unauthorized states
- `saveApiKey()` uses `await getAuthHeaders()`
- No key value interpolated into any console.log, console.error, or error message
- No key captured in Playwright screenshots (login overlay renders before dashboard in all non-ready states)

---

## 11. supabase-js Approach

CDN-loaded UMD bundle, auth functions only. No build step change.

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
```

```javascript
var _supabase = supabase.createClient(SUPA_URL, SUPA_KEY);
```

Used for: `signInWithPassword()`, `getSession()`, `signOut()`, `onAuthStateChange()`.
Not used for: data reads/writes (those remain raw `fetch()` calls using `getAuthHeaders()`).

GitHub Pages deployment unchanged. CNAME unchanged.

---

## 12. Migration Plan

**Rule: code ships first. app_users seeded before RLS changes. JWT verification confirmed before anon policies are removed.**

### Phase 1 — Auth Code Deployed, anon RLS Unchanged

1. Add supabase-js CDN tag to `<head>`
2. Initialize `_supabase` client
3. Implement `getCurrentSession()`, `getAuthHeaders()`
4. Implement auth state machine (6 states), login UI, unauthorized UI, session-expired UI, auth-error UI
5. Implement `onAuthStateChange` listener
6. Gate `loadAll()` on `ready` state transition (after app_users SELECT confirms active = true)
7. Update all functions in Section 7 inventory to use `await getAuthHeaders()`
8. Run full regression (596/0) and Playwright (46/0)
9. Push to GitHub Pages
10. Verify end-to-end on live deployment: login works, dashboard renders, all tabs load, no console errors

### Phase 2 — Supabase Setup (before any RLS changes)

1. Enable Email provider in Supabase Auth → Providers
2. Disable public signups (Auth → Settings → Enable Signups → off)
3. Create Adam's account: Auth → Users → Add user (`adam@herndons.us`)
4. Create `public.app_users` table with schema and trigger (Section 4)
5. Seed Adam's row (Section 4.6) — verify row exists before continuing
6. Apply RLS to `app_users` (read-own-row only, no write policies)
7. Create `public.is_allowed_user()` with hardened SQL (Section 5.2)

### Phase 3 — Verification Gate (Required Before Phase 4)

All three checks must pass before any anon policy is removed:

**Check 1 — grep:** Confirm no live data fetch call in `index.html` still uses `SUPA_H`:
```bash
grep -n "SUPA_H" ~/Adam-Dashboard/index.html
# Expected: only the const declaration, no fetch() usage
```

**Check 2 — Playwright network assertion (AUTH-E2E-6):** Post-login Supabase REST calls must include `Authorization: Bearer <session.access_token>`. The token value must not equal `SUPA_KEY` (the anon key). This test must pass before proceeding.

**Check 3 — unauthenticated rejection (post-Phase 4 spot check):** After the first table's anon policy is removed, send an unauthenticated `curl` request to that table's REST endpoint and confirm an empty result or 401 is returned:
```bash
curl -s \
  -H "apikey: $SUPA_KEY" \
  -H "Authorization: Bearer $SUPA_KEY" \
  "$SUPA_URL/rest/v1/wishlist_items?select=*" | cat
# Expected after RLS tightening: empty array [] or error — not data
```

### Phase 4 — RLS Tightening (one table at a time)

1. Audit existing policies (Section 6 pg_policies query)
2. Drop anon policies, apply `{table}_{action}_app_users` policies, one table at a time
3. Order: `wishlist_items` → `weekly_notes` → `weekly_tasks` → `custom_tasks` → `weekly_reconciliations` → `model_week_overrides` → `budget_rules` → `goals` → `goal_registry`
4. After each table: reload live app, confirm no console errors, no blank panels, no 401s in devtools
5. After all 9 tables: run full Playwright suite against live deployment

---

## 13. Bootstrap Scenarios

**Add a second user:**
```sql
INSERT INTO public.app_users (email, auth_user_id, role, active)
VALUES (
  'wendy@herndons.us',
  (SELECT id FROM auth.users WHERE email = 'wendy@herndons.us' LIMIT 1),
  'owner',
  true
);
```
No code change or deploy required.

**Revoke access:**
```sql
UPDATE public.app_users SET active = false WHERE email = 'example@email.com';
```
Effective immediately on next request.

**Change Adam's login email:**
1. Update in Supabase Auth dashboard (Auth → Users → Edit)
2. `UPDATE public.app_users SET email = 'new@email.com' WHERE email = 'adam@herndons.us';`
3. No policy edits, no code changes, no deploy required

**Add a second owner for emergency access:**
```sql
-- Create account via Supabase Auth dashboard first, then:
INSERT INTO public.app_users (email, auth_user_id, role, active)
VALUES ('backup@email.com', '<uuid>', 'owner', true);
```

---

## 14. Rollback Plan

| Scenario | Rollback action | Time to restore |
|---|---|---|
| Login overlay broken | Revert `index.html` to pre-auth commit; anon RLS still active | Minutes (git push) |
| RLS tightened but JWT not working | Restore anon policies in Supabase dashboard | Seconds (no deploy) |
| `app_users` empty / Adam's row missing | `INSERT INTO public.app_users ...` in Supabase dashboard | Seconds |
| `is_allowed_user()` function broken | Restore anon policies temporarily; rewrite function | Seconds (policy restore) |
| `app_users` RLS too restrictive | `DROP POLICY` on `app_users`; restore permissive SELECT | Seconds |
| supabase-js CDN unavailable | Commit UMD bundle to repo (`tools/supabase.js`), update script tag | One commit |
| Token refresh causing unexpected logout | Extend refresh window in Supabase Auth settings | Seconds (no deploy) |

---

## 15. No User Management UI in v1

Hard boundaries:
- No invite flow
- No role-editing UI
- No public signup
- No in-app password reset
- No in-app user administration

`app_users` managed via Supabase dashboard only.

---

## 16. Regression Test Plan

All 596 existing tests pass with zero modifications. New sections added.

### AUTH-A: getAuthHeaders() (4 tests)
- AUTH-A1: Returns `{apikey, Authorization: Bearer <token>, Content-Type}` with valid session
- AUTH-A2: Throws `[Auth] No authenticated session` with null session
- AUTH-A3: Extra headers merged without overwriting required fields
- AUTH-A4: `getCurrentSession()` returns null when session data is absent

### AUTH-B: Auth state machine (5 tests)
- AUTH-B1: `checking_session` → `loadAll()` and `renderApp()` not called
- AUTH-B2: `unauthenticated` → login form shown, no data fetch
- AUTH-B3: `unauthorized` → access denied UI shown, `loadAll()` not called
- AUTH-B4: `session_expired` → login form with expired banner
- AUTH-B5: 401 from any table fetch → `session_expired` state, no crash

### AUTH-C: No model behavior change gate (3 tests)
- AUTH-C1: `runModel()` weeks 1–31 byte-identical before and after auth wrapper
- AUTH-C2: `VARIABLE_WATERFALL` and `REGULAR_WATERFALL` unchanged (10 items each)
- AUTH-C3: `PRIORITY_TIERS` has 11 entries (unchanged)

### AUTH-D: Ask / Anthropic key protection (3 tests)
- AUTH-D1: `saveApiKey()` uses `getAuthHeaders()`, not `SUPA_H`
- AUTH-D2: Null session causes `saveApiKey()` to throw, not send unauthenticated request
- AUTH-D3: API key not accessible in any non-`ready` auth state

### AUTH-E: app_users (3 tests)
- AUTH-E1: Mock app_users row with `active = true` → `loadAll()` proceeds
- AUTH-E2: Mock app_users row with `active = false` → `unauthorized` state, `loadAll()` blocked
- AUTH-E3: No app_users row for current email → `unauthorized` state, `loadAll()` blocked

**Total new regression tests: 18. New total: 614.**

---

## 17. Playwright Test Plan

New E2E section AUTH — 8 tests.

| Test | Description |
|---|---|
| AUTH-E2E-1 | Fresh page load with no session shows login form, not dashboard |
| AUTH-E2E-2 | Invalid credentials show inline error, no crash |
| AUTH-E2E-3 | Valid login renders dashboard; no console errors |
| AUTH-E2E-4 | Session persists across page reload; no re-login prompt |
| AUTH-E2E-5 | Sign out clears session and shows login form |
| AUTH-E2E-6 | Post-login Supabase calls use `Authorization: Bearer <token>` distinct from anon key (network assertion — Phase 3 gate) |
| AUTH-E2E-7 | After login, all 9 tables return data; no 401 errors in network log |
| AUTH-E2E-8 | app_users returns Adam's row with `active = true` after login |

**New total Playwright tests: 54.**

```javascript
// e2e.js — fail fast if credentials missing
const TEST_EMAIL    = process.env.TEST_EMAIL;
const TEST_PASSWORD = process.env.TEST_PASSWORD;
if (!TEST_EMAIL || !TEST_PASSWORD) {
  console.error('[e2e] ERROR: TEST_EMAIL and TEST_PASSWORD must be set.');
  console.error('[e2e] Add a .env file (gitignored) with these values.');
  process.exit(1);
}
```

`.env` gitignored. No password in console output. No password captured in screenshots.

---

## 18. What Changes and What Does Not

### What changes in this build

- `index.html` — auth state machine, login UI, `getAuthHeaders()`, `_supabase` client init, supabase-js CDN tag, all functions in Section 7 inventory updated
- `e2e.js` — AUTH-E2E-1 through AUTH-E2E-8 added, credential loading from `.env`
- `test_regression.js` — AUTH-A through AUTH-E sections added
- Supabase dashboard — `app_users` table, `is_allowed_user()` function, RLS policies on all 9 tables, Supabase Auth account created

### What does not change

- No existing model/data table schemas change (columns, types, constraints — unchanged)
- One new auth-support table added: `public.app_users`
- One new auth-support function added: `public.is_allowed_user()`
- Existing data/model tables receive RLS policy changes only
- `runModel()`, `applyGoalsFromData()`, `VARIABLE_WATERFALL`, `REGULAR_WATERFALL`, `PRIORITY_TIERS`
- `applyBudgetRulesForWeek()`, `diffModels()`, `applyCompletionSnapshots()`
- All week object shapes and fields
- `HARDCODED_GOALS_FALLBACK`, `goalsLoadStatus` state machine
- All waterfall constants, commission split logic, starting balances
- Budget Rules engine, What-If Calculator
- GitHub Pages deployment structure, CNAME

---

## 19. No Model Behavior Changes — Confirmation

Auth wraps app initialization only. AUTH-C regression gate is the machine-verifiable proof: `runModel()` output must be byte-identical before and after the auth build.

---

## Summary Table

| Decision | Choice |
|---|---|
| Auth provider | Supabase Auth, email + password |
| supabase-js | CDN UMD, auth functions only, no build step change |
| Access control | `app_users` allowlist (Option B) |
| RLS enforcement | `public.is_allowed_user()` — RLS-only, not callable as RPC |
| SECURITY DEFINER hardening | Schema-qualified, `SET search_path = public`, REVOKE ALL from PUBLIC, GRANT to authenticated |
| Verification method | App login + Playwright network assertion — not SQL editor |
| RLS policy naming | `{table}_{action}_app_users` |
| Auth state machine | 6 states — unauthenticated ≠ unauthorized |
| `auth_user_id` | Nullable in v1 (Option A); email-primary-key with UUID backfill path |
| Role column | Present, seeded as `owner`, unenforced in v1 |
| app_users management | Supabase dashboard only |
| Forgot-password | Supabase dashboard only |
| All 9 tables | Auth-only, no anon exceptions |
| Ask/Claude key | Not loaded or visible until `ready` state |

---

---

## 20. Post-Auth Security and Architecture Backlog

Auth v1 closes the anon access gap. It does not address all security or architecture risks. The following items are explicitly tracked for future builds and are visible in the OS Wishlist tab.

**Tracking locations:**
- `docs/security-brittleness-backlog.md` — full item detail, risk ratings, prioritization notes
- OS Wishlist tab — all items seeded with phase labels "Security", "Auth+", or "Platform"

**Post-auth near-term (items 8–18):** MFA, backup owner account, auth.uid() migration, role enforcement, Anthropic key vault, CDN hardening, CSP/XSS hardening, session policy review, audit logging, SQL migration scripts, data backup plan, anon key rotation procedure.

**Auth+ later (items 19–25):** In-app user management, invite flow, forgot-password UI, viewer dashboard mode, CPA/advisor access, Wendy access, role-aware UI suppression.

**Platform / brittleness (P1–P6):** START_CHK/START_SAV drift fix (TD-8, highest priority), write debouncing, input validation on write paths, 2027 model re-baseline procedure, updated_at triggers on write tables.

None of the above are required for Auth v1 build authorization. They are tracked so they do not get lost as the app evolves.

---

*Spec v1.4. No build authorized until approved by ChatGPT.*
