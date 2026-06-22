# Herndon Financial OS — Authentication / Access Control Spec

**Version:** 1.3
**Date:** Cal Wk 25 (Jun 22, 2026)
**Status:** For review — no build authorized until approved by ChatGPT
**Scope:** Auth layer only. Zero model behavior changes.
**Changes from v1.2:** Added auth state machine (6 states), auth_user_id on app_users, explicit authentication vs. authorization separation, standardized RLS policy naming convention, login shell renders before auth, auth_error and unauthorized UI states, bootstrap and lockout recovery detail, Ask/Claude key unauthorized-state protection, role-enforcement timeline.

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

These are separate gates. Both must pass before the app loads data.

**Authentication** = the user has a valid Supabase Auth session (email + password verified, JWT issued).

**Authorization** = the authenticated user's email exists in `app_users` with `active = true`.

A valid Supabase session is **not sufficient** for app access. A user could have a valid session and still be unauthorized (e.g. account deactivated, email not in allowlist, wrong account).

The app enforces both gates in sequence:
1. Authenticate via Supabase Auth
2. Verify authorization via `is_allowed_user()` / `app_users`
3. Only then: `loadAll()` → `renderApp()`

---

## 3. Auth State Machine

The app maintains one of six auth states at any point. State determines which UI surface renders. State transitions are driven by `_supabase.auth.onAuthStateChange` and the result of the `app_users` authorization check.

```
                    ┌─────────────────────┐
                    │   checking_session   │  ← page load
                    └────────┬────────────┘
                             │ getSession()
              ┌──────────────┼──────────────┐
              │              │              │
         no session      session ok      error
              │              │              │
              ▼              ▼              ▼
    ┌──────────────┐  ┌─────────────┐  ┌────────────┐
    │unauthenticated│  │authenticated│  │ auth_error │
    └──────────────┘  └──────┬──────┘  └────────────┘
    show login form           │ check app_users
                    ┌─────────┴──────────┐
                    │                    │
               allowed             not allowed
               + active            or inactive
                    │                    │
                    ▼                    ▼
             ┌──────────┐        ┌─────────────┐
             │  ready   │        │unauthorized │
             └──────────┘        └─────────────┘
          loadAll() →           show "access denied"
          renderApp()           do NOT load data

    onAuthStateChange: SIGNED_OUT → session_expired (if token expired)
                                  → unauthenticated (if explicit sign out)
    ┌─────────────────┐
    │  session_expired │  ← token refresh failed mid-session
    └─────────────────┘
    show login form + "session expired" message
```

### State Definitions

| State | Meaning | UI Surface |
|---|---|---|
| `checking_session` | `getSession()` in flight at page load | Minimal shell / spinner |
| `unauthenticated` | No session exists | Login form (no error message) |
| `authenticated` | Valid session; `app_users` check in progress | Minimal shell / spinner |
| `unauthorized` | Valid session; email not in `app_users` or `active = false` | "Access denied" message with sign-out option |
| `session_expired` | Token refresh failed mid-session | Login form + "Your session expired" message |
| `auth_error` | `getSession()` threw or Supabase unreachable | Error message + retry option |

### UI Behavior by State

- `checking_session` / `authenticated` (authorization pending): render login shell only — no dashboard, no data, no API key
- `unauthenticated`: login form, no error prefill
- `session_expired`: login form with banner — "Your session expired. Please sign in again."
- `auth_error`: error banner — "Authentication service unavailable. Please try again." + retry button
- `unauthorized`: "Access denied. This account is not authorized to use this application." + sign-out link
- `ready`: full dashboard renders

The `unauthorized` state is distinct from `unauthenticated`. The UI must not show a generic "please log in" message when the user is logged in but not allowed — that is confusing and may suggest the problem is a wrong password.

---

## 4. app_users Allowlist Table

### 4.1 Design Rationale — Option A vs Option B

**Option A (Rejected): Hardcode email in every RLS policy**
```sql
-- 36+ policies would all contain:
USING (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us')
```
Brittle. Changing login email or adding a trusted user requires editing every policy on every table. Rejected.

**Option B (Adopted): app_users allowlist table**
One table controls access. Policies delegate to `is_allowed_user()`. Adding, changing, or revoking a user requires a single row change. No policy edits.

### 4.2 Schema

```sql
CREATE TABLE app_users (
  email        TEXT PRIMARY KEY,
  auth_user_id UUID UNIQUE,
  role         TEXT NOT NULL DEFAULT 'viewer',
  active       BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**`auth_user_id`** is the Supabase Auth UUID for the user (`auth.users.id`). Email can change; `auth.uid()` is permanent. Populating this now avoids a future migration if the `is_allowed_user()` function is later updated to use `auth.uid()` instead of email for durability.

If `auth_user_id` cannot be resolved at insert time (e.g. user not yet created in Supabase Auth), the column is nullable and can be backfilled. Document as a known gap if left null.

### 4.3 Initial Seed

Run after Adam's Supabase Auth account is created:

```sql
INSERT INTO app_users (email, auth_user_id, role, active)
VALUES (
  'adam@herndons.us',
  (SELECT id FROM auth.users WHERE email = 'adam@herndons.us' LIMIT 1),
  'owner',
  true
);
```

Verify the row exists before proceeding to any RLS changes:

```sql
SELECT email, auth_user_id, role, active FROM app_users;
-- Must return exactly one row: adam@herndons.us | <uuid> | owner | true
```

### 4.4 Role Framework

| Role | v1 Enforcement | Future Intent |
|---|---|---|
| `owner` | Full read/write (same as editor/viewer in v1) | Manages app_users, budget_rules, goal_registry |
| `editor` | Full read/write (v1 — not yet enforced) | Limited write — no schema-affecting tables |
| `viewer` | Full read/write (v1 — not yet enforced) | Read-only on all tables |

**v1 simplification:** All active `app_users` have identical access regardless of role. The `role` column is present and seeded, but `is_allowed_user()` checks only `active = true` for now. This is explicitly a temporary simplification — noted in the function definition. Role enforcement is a future build, not this one.

### 4.5 updated_at Trigger

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

### 4.6 RLS on app_users

`app_users` is managed via Supabase dashboard only. No in-app write path.

```sql
ALTER TABLE app_users ENABLE ROW LEVEL SECURITY;

-- Active users can read their own row only
CREATE POLICY "app_users_select_self"
  ON app_users FOR SELECT TO authenticated
  USING (lower(email) = lower((auth.jwt() ->> 'email')::text));

-- No INSERT / UPDATE / DELETE policies — dashboard management only
```

---

## 5. is_allowed_user() — SECURITY DEFINER Function

### 5.1 Why SECURITY DEFINER

An inline `EXISTS (SELECT 1 FROM app_users ...)` subquery in every RLS policy would itself be subject to `app_users`'s own RLS. That works but creates a layered RLS dependency that is opaque and fragile. A `SECURITY DEFINER` function runs with elevated privileges, bypasses RLS on `app_users`, and gives a single place to update the access logic.

### 5.2 Implementation

```sql
CREATE OR REPLACE FUNCTION is_allowed_user()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  -- v1: checks email and active status only.
  -- NOTE: role-based enforcement is a future build. The role column exists
  -- but is not checked here yet. All active app_users have equivalent access in v1.
  SELECT EXISTS (
    SELECT 1
    FROM app_users
    WHERE lower(app_users.email) = lower((auth.jwt() ->> 'email')::text)
      AND app_users.active = true
  );
$$;
```

Verify function works before applying RLS changes:

```sql
-- Run in Supabase SQL editor while authenticated as adam@herndons.us
SELECT is_allowed_user();
-- Must return: true
```

---

## 6. RLS Policies — Standardized Naming Convention

All policies follow the pattern: `{table}_{action}_app_users`

This makes the full policy set auditable with a single `pg_policies` query — every policy name clearly identifies the table, operation, and access model.

### 6.1 Existing Policy Audit (Run First)

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

Drop all existing policies before adding new ones to avoid conflicts.

### 6.2 Full Policy Set

**goals**
```sql
CREATE POLICY "goals_select_app_users" ON goals
  FOR SELECT TO authenticated USING (is_allowed_user());
CREATE POLICY "goals_insert_app_users" ON goals
  FOR INSERT TO authenticated WITH CHECK (is_allowed_user());
CREATE POLICY "goals_update_app_users" ON goals
  FOR UPDATE TO authenticated
  USING (is_allowed_user()) WITH CHECK (is_allowed_user());
```

**weekly_reconciliations**
```sql
CREATE POLICY "weekly_reconciliations_select_app_users" ON weekly_reconciliations
  FOR SELECT TO authenticated USING (is_allowed_user());
CREATE POLICY "weekly_reconciliations_insert_app_users" ON weekly_reconciliations
  FOR INSERT TO authenticated WITH CHECK (is_allowed_user());
CREATE POLICY "weekly_reconciliations_update_app_users" ON weekly_reconciliations
  FOR UPDATE TO authenticated
  USING (is_allowed_user()) WITH CHECK (is_allowed_user());
```

**weekly_tasks**
```sql
CREATE POLICY "weekly_tasks_select_app_users" ON weekly_tasks
  FOR SELECT TO authenticated USING (is_allowed_user());
CREATE POLICY "weekly_tasks_insert_app_users" ON weekly_tasks
  FOR INSERT TO authenticated WITH CHECK (is_allowed_user());
CREATE POLICY "weekly_tasks_update_app_users" ON weekly_tasks
  FOR UPDATE TO authenticated
  USING (is_allowed_user()) WITH CHECK (is_allowed_user());
```

**weekly_notes**
```sql
CREATE POLICY "weekly_notes_select_app_users" ON weekly_notes
  FOR SELECT TO authenticated USING (is_allowed_user());
CREATE POLICY "weekly_notes_insert_app_users" ON weekly_notes
  FOR INSERT TO authenticated WITH CHECK (is_allowed_user());
CREATE POLICY "weekly_notes_update_app_users" ON weekly_notes
  FOR UPDATE TO authenticated
  USING (is_allowed_user()) WITH CHECK (is_allowed_user());
```

**model_week_overrides**
```sql
CREATE POLICY "model_week_overrides_select_app_users" ON model_week_overrides
  FOR SELECT TO authenticated USING (is_allowed_user());
CREATE POLICY "model_week_overrides_insert_app_users" ON model_week_overrides
  FOR INSERT TO authenticated WITH CHECK (is_allowed_user());
CREATE POLICY "model_week_overrides_update_app_users" ON model_week_overrides
  FOR UPDATE TO authenticated
  USING (is_allowed_user()) WITH CHECK (is_allowed_user());
CREATE POLICY "model_week_overrides_delete_app_users" ON model_week_overrides
  FOR DELETE TO authenticated USING (is_allowed_user());
```

**wishlist_items**
```sql
CREATE POLICY "wishlist_items_select_app_users" ON wishlist_items
  FOR SELECT TO authenticated USING (is_allowed_user());
CREATE POLICY "wishlist_items_insert_app_users" ON wishlist_items
  FOR INSERT TO authenticated WITH CHECK (is_allowed_user());
CREATE POLICY "wishlist_items_update_app_users" ON wishlist_items
  FOR UPDATE TO authenticated
  USING (is_allowed_user()) WITH CHECK (is_allowed_user());
```

**custom_tasks**
```sql
CREATE POLICY "custom_tasks_select_app_users" ON custom_tasks
  FOR SELECT TO authenticated USING (is_allowed_user());
CREATE POLICY "custom_tasks_insert_app_users" ON custom_tasks
  FOR INSERT TO authenticated WITH CHECK (is_allowed_user());
CREATE POLICY "custom_tasks_update_app_users" ON custom_tasks
  FOR UPDATE TO authenticated
  USING (is_allowed_user()) WITH CHECK (is_allowed_user());
```

**budget_rules**
```sql
CREATE POLICY "budget_rules_select_app_users" ON budget_rules
  FOR SELECT TO authenticated USING (is_allowed_user());
CREATE POLICY "budget_rules_insert_app_users" ON budget_rules
  FOR INSERT TO authenticated WITH CHECK (is_allowed_user());
CREATE POLICY "budget_rules_update_app_users" ON budget_rules
  FOR UPDATE TO authenticated
  USING (is_allowed_user()) WITH CHECK (is_allowed_user());
```

**goal_registry** (replaces existing anon SELECT policy)
```sql
CREATE POLICY "goal_registry_select_app_users" ON goal_registry
  FOR SELECT TO authenticated USING (is_allowed_user());
```

---

## 7. getAuthHeaders() and Authenticated Fetch Wrapper

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

`SUPA_H` (the existing anon header const) is retired for all live data calls once auth is active. No data read or write may use `SUPA_H` after auth is deployed. A pre-push grep confirms no stragglers.

**Full function inventory** — every function updated to use `await getAuthHeaders()`:

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

The login shell renders first. Data is never loaded before auth and authorization both pass.

```
1. Page loads → render login shell (no data, no dashboard, no API key visible)
2. setAuthState('checking_session')
3. _supabase.auth.getSession()
      ├── error → setAuthState('auth_error') → show error UI
      ├── no session → setAuthState('unauthenticated') → show login form
      └── session found → setAuthState('authenticated')
              → check is_allowed_user() (or app_users SELECT)
                    ├── not allowed / inactive → setAuthState('unauthorized') → show access denied UI
                    └── allowed → loadAll() → renderApp() → setAuthState('ready')

4. Register _supabase.auth.onAuthStateChange:
      SIGNED_OUT → setAuthState('unauthenticated')
      TOKEN_REFRESHED → no state change (stay ready)
      refresh failure → setAuthState('session_expired') → show expired UI
```

`loadAll()` is called once, only after both gates pass. `renderApp()` is called only after `loadAll()` completes.

---

## 9. Login / Logout UX

**Login overlay** — shown in `unauthenticated` and `session_expired` states:
- Email field (pre-populated with `adam@herndons.us` for convenience)
- Password field
- "Sign in" button
- Inline error area (shown only on failed attempt — "Invalid email or password")
- No signup link, no forgot-password link, no public registration path

**Session expired variant** — same form with additional banner: "Your session expired. Please sign in again."

**Unauthorized state** — separate from login form:
- Message: "Access denied. This account is not authorized."
- "Sign out" link only (no password field — the user is already authenticated, just not authorized)

**Logout** — "Sign out" link in dashboard header:
- `_supabase.auth.signOut()` called
- Session cleared from localStorage
- `setAuthState('unauthenticated')` → login form shown

---

## 10. Ask / Anthropic API Key Protection

The Anthropic API key is stored in the `goals` table and loaded during `loadAll()`.

- Key is not loaded until `loadAll()` runs (requires both auth gates to pass)
- Key is not visible on the login screen, session-expired screen, auth-error screen, or unauthorized screen
- Key is not visible in any non-`ready` auth state
- `saveApiKey()` uses `await getAuthHeaders()` — same as all other write functions
- No API key value is interpolated into any error message, console.log, or console.error call
- No API key is captured in Playwright screenshots (key is only rendered in the `ready` state; non-ready states show no dashboard)

---

## 11. supabase-js Approach

**supabase-js loaded from CDN — auth functions only. No build step change.**

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
```

Initialized once:

```javascript
var _supabase = supabase.createClient(SUPA_URL, SUPA_KEY);
```

supabase-js is used for: `signInWithPassword()`, `getSession()`, `signOut()`, `onAuthStateChange()`.

supabase-js is NOT used for data reads/writes. Existing `fetch()` calls are preserved and updated to use `await getAuthHeaders()`.

GitHub Pages deployment is unchanged. The CDN load is the only new external dependency.

---

## 12. Migration Plan — Bootstrap and Lockout Recovery

### Phase 1 — Auth Code Deployed, anon RLS Unchanged

1. Add supabase-js CDN tag
2. Initialize `_supabase` client, implement auth state machine
3. Implement login overlay, unauthorized UI, session-expired UI, auth-error UI
4. Implement `getCurrentSession()`, `getAuthHeaders()`, `onAuthStateChange` listener
5. Gate `loadAll()` and `renderApp()` on `ready` state
6. Update all functions in Section 7 inventory to use `await getAuthHeaders()`
7. Run full regression (596/0) and Playwright (46/0)
8. Push to GitHub Pages
9. Verify end-to-end on live deployment: login works, dashboard renders, all tabs load

### Phase 2 — Supabase Setup (before any RLS changes)

1. Create Adam's Supabase Auth account (`adam@herndons.us`)
2. Create `app_users` table with schema and trigger (Section 4)
3. Seed Adam's row (Section 4.3) — verify row exists before continuing
4. Set RLS on `app_users` (read-own-row only, no write policies)
5. Create `is_allowed_user()` SECURITY DEFINER function (Section 5)
6. Verify `SELECT is_allowed_user();` returns `true` for Adam's session in Supabase SQL editor

### Phase 3 — JWT Verification Before Removing Anon Policies

Confirm that post-login Supabase calls use the session JWT, not the anon key. AUTH-E2E-6 (network assertion) must pass. Do not proceed until verified.

### Phase 4 — RLS Tightening (one table at a time)

1. Audit existing policies (Section 6.1) — drop anon policies
2. Apply new policies one table at a time, in order: `wishlist_items` → `weekly_notes` → `weekly_tasks` → `custom_tasks` → `weekly_reconciliations` → `model_week_overrides` → `budget_rules` → `goals` → `goal_registry`
3. After each table: reload live app, confirm no console errors, no blank panels, no 401s
4. After all 9 tables: run full Playwright suite against live deployment

### Bootstrap Scenarios

**Adding a second owner manually:**
```sql
INSERT INTO app_users (email, auth_user_id, role, active)
VALUES (
  'wendy@herndons.us',
  (SELECT id FROM auth.users WHERE email = 'wendy@herndons.us' LIMIT 1),
  'owner',
  true
);
```
No code change or deploy required.

**Revoking access:**
```sql
UPDATE app_users SET active = false WHERE email = 'example@email.com';
```
Takes effect immediately on next request. No deploy required.

**Changing Adam's login email:**
1. Update in Supabase Auth dashboard (Auth → Users → Edit)
2. Update `app_users`: `UPDATE app_users SET email = 'new@email.com' WHERE email = 'adam@herndons.us';`
3. No policy changes, no code changes, no deploy required

---

## 13. Rollback Plan

| Scenario | Rollback action | Time to restore |
|---|---|---|
| Login overlay broken | Revert `index.html` to pre-auth commit; anon RLS still active | Minutes (git push) |
| RLS tightened but JWT not working | Restore anon policies in Supabase dashboard | Seconds (no deploy) |
| `app_users` empty / Adam's row missing | `INSERT INTO app_users ...` in Supabase dashboard | Seconds |
| `is_allowed_user()` function broken | Revert to anon policies; debug function separately | Seconds (policy restore) |
| `app_users` RLS too restrictive | `DROP POLICY` on `app_users`; restore permissive SELECT | Seconds |
| supabase-js CDN unavailable | Commit UMD bundle to repo, load locally | One commit |
| Refresh token expiry causing unexpected logout | Extend refresh window in Supabase Auth settings | Seconds (no deploy) |

---

## 14. No User Management UI in v1

Hard boundaries for this build:

- No invite flow
- No role-editing UI
- No public signup
- No in-app password reset (Supabase dashboard only)
- No in-app user administration of any kind

`app_users` is managed manually in the Supabase dashboard. This is acceptable for a single-owner app.

---

## 15. Regression Test Plan

New sections added to `test_regression.js`. All 596 existing tests pass with zero modifications.

### AUTH-A: getAuthHeaders() (4 tests)
- AUTH-A1: Returns correct header shape with valid session
- AUTH-A2: Throws `[Auth] No authenticated session` with null session
- AUTH-A3: Extra headers merged correctly without overwriting required fields
- AUTH-A4: `getCurrentSession()` returns null when no session data

### AUTH-B: App behavior by auth state (5 tests)
- AUTH-B1: `checking_session` state — `loadAll()` and `renderApp()` not called
- AUTH-B2: `unauthenticated` state — login form shown, no data fetch
- AUTH-B3: `unauthorized` state — access denied UI shown, `loadAll()` not called
- AUTH-B4: `session_expired` state — login form shown with expired message
- AUTH-B5: 401 response from any table fetch → `session_expired` state, no crash

### AUTH-C: No model behavior change gate (3 tests)
- AUTH-C1: `runModel()` output weeks 1–31 byte-identical before and after auth wrapper
- AUTH-C2: `VARIABLE_WATERFALL` and `REGULAR_WATERFALL` unchanged (10 items each)
- AUTH-C3: `PRIORITY_TIERS` has 11 entries (unchanged)

### AUTH-D: Ask / Anthropic key protection (3 tests)
- AUTH-D1: `saveApiKey()` uses `getAuthHeaders()`, not `SUPA_H`
- AUTH-D2: Null session causes `saveApiKey()` to throw, not send unauthenticated request
- AUTH-D3: No API key value present in any auth state other than `ready`

### AUTH-E: app_users and is_allowed_user() (3 tests)
- AUTH-E1: Mock `is_allowed_user()` true → `loadAll()` proceeds
- AUTH-E2: Mock `is_allowed_user()` false → `unauthorized` state, `loadAll()` blocked
- AUTH-E3: app_users seed row: `adam@herndons.us / owner / true` must exist pre-RLS (migration gate)

**Total new regression tests: 18. New total: 614.**

---

## 16. Playwright Test Plan

New E2E section `AUTH` — 8 tests.

| Test | Description |
|---|---|
| AUTH-E2E-1 | Fresh page load with no session shows login form, not dashboard |
| AUTH-E2E-2 | Invalid credentials show inline error, no crash, no redirect |
| AUTH-E2E-3 | Valid login renders dashboard; no console errors |
| AUTH-E2E-4 | Session persists across page reload; no re-login prompt |
| AUTH-E2E-5 | Sign out clears session and shows login form |
| AUTH-E2E-6 | Post-login Supabase calls use `Authorization: Bearer <token>`, not anon key only (network assertion — required before Phase 4 RLS changes) |
| AUTH-E2E-7 | After login, all 9 tables return data; no 401 errors in network log |
| AUTH-E2E-8 | `app_users` returns Adam's row with `active = true` after login |

**New total Playwright tests: 54.**

**Credentials handling:**
```javascript
const TEST_EMAIL    = process.env.TEST_EMAIL;
const TEST_PASSWORD = process.env.TEST_PASSWORD;
if (!TEST_EMAIL || !TEST_PASSWORD) {
  console.error('[e2e] ERROR: TEST_EMAIL and TEST_PASSWORD must be set in environment.');
  console.error('[e2e] Create a .env file (gitignored) with these values.');
  process.exit(1);
}
```
- `.env` is gitignored — credentials never committed
- No password logged to console in any path
- No password captured in screenshots (login overlay dismissed before any screenshot)

---

## 17. What Will Not Change

- `runModel()`, `applyGoalsFromData()`, `VARIABLE_WATERFALL`, `REGULAR_WATERFALL`, `PRIORITY_TIERS`
- `applyBudgetRulesForWeek()`, `diffModels()`, `applyCompletionSnapshots()`
- All week object shapes and fields
- All Supabase table schemas (RLS changes; schemas do not)
- `HARDCODED_GOALS_FALLBACK`, `goalsLoadStatus` state machine
- All waterfall constants, commission split logic, starting balances
- Budget Rules engine, What-If Calculator
- GitHub Pages deployment structure, CNAME
- All `model_spec.md` model invariants

---

## 18. No Model Behavior Changes — Confirmation

Auth wraps app initialization. It does not touch any value or function that flows into `runModel()`. AUTH-C regression gate is the machine-verifiable proof: `runModel()` output must be byte-identical before and after the auth build.

---

## Summary Table

| Decision | Choice |
|---|---|
| Auth provider | Supabase Auth, email + password |
| supabase-js | CDN UMD, auth functions only, no build step change |
| Access control model | `app_users` allowlist (Option B) |
| RLS enforcement | `is_allowed_user()` SECURITY DEFINER function |
| RLS policy naming | `{table}_{action}_app_users` |
| Auth state machine | 6 states: checking_session, unauthenticated, authenticated, unauthorized, session_expired, auth_error |
| Auth vs authorization | Explicitly separate gates; session alone is not sufficient |
| Role column | Present, seeded as `owner`, unenforced in v1 |
| `auth_user_id` | Populated at seed time from `auth.users.id`; nullable fallback |
| app_users management | Supabase dashboard only — no in-app UI |
| Forgot-password | Supabase dashboard only |
| All 9 tables | Auth-only, no anon exceptions |
| Ask/Claude key | Not loaded or visible until `ready` state |

---

*Spec v1.3. No build authorized until approved by ChatGPT.*
