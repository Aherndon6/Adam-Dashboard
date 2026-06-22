# Herndon Financial OS — Authentication / Access Control Spec

**Version:** 1.1
**Date:** Cal Wk 25 (Jun 22, 2026)
**Status:** For review — no build authorized until approved by ChatGPT
**Scope:** Auth layer only. Zero model behavior changes.
**Changes from v1.0:** Corrected JWT injection claim, added getAuthHeaders() inventory, email-scoped RLS, migration verification step, supabase-js approach explicit, e2e secrets handling, Ask/Anthropic key coverage, updated test plans.

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

**Summary:** 8 of 9 tables have full anon read/write access. All 9 will require authentication after migration.

---

## 2. Tables Currently Allowing anon Read/Write

All 9 tables are currently accessible without authentication. The anon key is embedded in plain text in `index.html` and is visible in browser devtools. On a GitHub Pages static host, the key cannot be hidden server-side. The security model after auth shifts from key obscurity to RLS enforcement: the anon key remains in the file but RLS blocks all unauthenticated requests at the database layer.

---

## 3. Target Access Model After Auth

**Single authenticated user: `adam@herndons.us`.** No multi-user support, no roles.

| Table | After auth: SELECT | After auth: INSERT/UPDATE/DELETE |
|---|---|---|
| `goals` | adam@herndons.us only | adam@herndons.us only |
| `weekly_reconciliations` | adam@herndons.us only | adam@herndons.us only |
| `weekly_tasks` | adam@herndons.us only | adam@herndons.us only |
| `weekly_notes` | adam@herndons.us only | adam@herndons.us only |
| `model_week_overrides` | adam@herndons.us only | adam@herndons.us only |
| `wishlist_items` | adam@herndons.us only | adam@herndons.us only |
| `custom_tasks` | adam@herndons.us only | adam@herndons.us only |
| `budget_rules` | adam@herndons.us only | adam@herndons.us only |
| `goal_registry` | adam@herndons.us only | read-only (SELECT) — unchanged |

No anon access to any table. No exceptions.

---

## 4. Auth Approach: Supabase Auth — Email + Password with CDN-Loaded supabase-js

### 4.1 Supabase JS Client

The app will load `supabase-js` from CDN for auth functions only. No build step change. The existing raw `fetch` calls for data reads/writes are preserved but updated to use authenticated headers (see Section 5).

```html
<!-- Added to <head> of index.html -->
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
```

This is a UMD bundle — it exposes `window.supabase` globally. No npm, no bundler, no build step change. Compatible with GitHub Pages.

**supabase-js is used for auth functions only:**
- `supabase.auth.signInWithPassword({ email, password })`
- `supabase.auth.getSession()`
- `supabase.auth.signOut()`
- `supabase.auth.onAuthStateChange(callback)`

**supabase-js is NOT used for data reads/writes.** All existing `fetch` calls to the Supabase REST API remain as-is, with `SUPA_H` replaced by `await getAuthHeaders()` (see Section 5).

### 4.2 Supabase Client Initialization

```javascript
var _supabase = supabase.createClient(SUPA_URL, SUPA_KEY);
```

Initialized once at script load, before `loadAll()` or `renderApp()`. The anon key is used here only to initialize the client — auth calls use email/password, and data calls use the session JWT.

### 4.3 Session Persistence

Supabase-js stores the JWT access token and refresh token in `localStorage` automatically. On page load, `_supabase.auth.getSession()` checks for a valid session before any data fetch runs.

- Access token lifetime: 1 hour (Supabase default)
- Refresh token lifetime: 30 days (recommended — configure in Supabase Auth settings)
- Refresh is automatic and transparent

### 4.4 Auth Setup in Supabase Dashboard (one-time)

1. Enable Email provider in Supabase Auth → Providers
2. Disable "Enable email confirmations" (single-user app, no confirmation email needed)
3. Disable public signups (Auth → Settings → "Enable Signups" → off)
4. Create Adam's account: Supabase Auth → Users → "Invite user" or "Add user" with `adam@herndons.us`
5. Set password directly or use the Supabase "Send password reset" flow to set initial password

---

## 5. getAuthHeaders() — Centralized Authenticated Request Helper

### 5.1 Implementation

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

`SUPA_H` (the existing anon header const) is retired for all live data calls once auth is active. It may be kept in the file temporarily during the transition build but must not be used in any function that touches Supabase data.

### 5.2 Full Inventory of Functions to Update

Every function that makes a Supabase REST call must be updated to use `await getAuthHeaders()` instead of `SUPA_H`.

| Function | Operation | Table(s) |
|---|---|---|
| `loadAll()` | SELECT (9 fetches in Promise.all) | All tables |
| `loadWishlist()` | SELECT | `wishlist_items` |
| `mergeSeedWishlist()` | INSERT/UPDATE | `wishlist_items` |
| `phaseMigrateWishlist()` | INSERT/UPDATE | `wishlist_items` |
| `saveWishlistItem()` | INSERT/UPDATE | `wishlist_items` |
| `saveRecon(n)` | INSERT (merge-duplicates) | `weekly_reconciliations` |
| `toggleTask(...)` | INSERT (merge-duplicates) | `weekly_tasks` |
| `saveNote(weekNum, el)` | INSERT (merge-duplicates) | `weekly_notes` |
| custom task write | INSERT/UPDATE | `custom_tasks` |
| override write | INSERT | `model_week_overrides` |
| override delete | DELETE | `model_week_overrides` |
| budget_rules read (in loadAll) | SELECT | `budget_rules` |
| goal_registry read (in loadAll) | SELECT | `goal_registry` |
| `saveApiKey()` | INSERT/UPDATE | `goals` |

**Every `fetch()` call in the above functions must be updated.** No Supabase data call may use `SUPA_H` after auth is active. A pre-push grep for `SUPA_H` in Supabase fetch calls will confirm no stragglers.

### 5.3 Error Handling

If `getAuthHeaders()` throws (no session), the calling function must not silently swallow the error. Behavior:

- `loadAll()`: catches the throw, does not attempt any fetch, calls `showLoginOverlay()`
- Write functions (saveRecon, toggleTask, etc.): catch the throw, log a warning, call `showLoginOverlay()`
- No data is lost — write functions are called on user action, and after re-login the user can retry

---

## 6. Login / Logout UX

### 6.1 Initialization Flow

```
page load
  → _supabase.auth.getSession()
      ├── session valid → loadAll() → renderApp()  [normal path]
      └── no session   → showLoginOverlay()         [auth required]
```

`renderApp()` is never called without a valid session. `loadAll()` is never called without a valid session.

### 6.2 Login Overlay

Full-page overlay rendered on top of (or instead of) the dashboard. Contains:
- Email field (pre-filled with `adam@herndons.us`, read-only or editable)
- Password field
- "Sign in" button
- Inline error message area (shown on failed login — "Invalid email or password")
- No signup link, no forgot-password link

On successful login:
1. Session established
2. Overlay dismissed
3. `loadAll()` called
4. `renderApp()` called

### 6.3 Logout

"Sign out" link in the dashboard header. On click:
1. `_supabase.auth.signOut()` called
2. `localStorage` session cleared (handled by supabase-js)
3. `showLoginOverlay()` called
4. Dashboard is not visible until re-login

### 6.4 Session Expiry Mid-Session

`_supabase.auth.onAuthStateChange` listener registered at init. If event is `SIGNED_OUT` or token refresh fails:
1. `showLoginOverlay()` called immediately
2. Any in-progress user action (e.g. saveRecon) is interrupted — `getAuthHeaders()` throws, error is caught, overlay shown
3. No crash, no blank panel

### 6.5 Ask / Anthropic API Key Handling

The Anthropic API key is stored in the `goals` table and loaded during `loadAll()`. After auth:
- The key is not loaded until `loadAll()` runs (which requires a valid session)
- The key is never displayed on the login screen
- `saveApiKey()` uses `await getAuthHeaders()` — same as all other write functions
- No API key is logged to console in error paths
- The key is stored and retrieved exactly as it is today — auth adds protection, not new behavior

---

## 7. GitHub Pages Deployment Impact

No deployment model change. GitHub Pages continues to serve `index.html` as a static file.

The only addition is the supabase-js CDN `<script>` tag in `<head>`. The CDN URL is:

```
https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js
```

This is a stable, versioned CDN load. If CDN is unavailable, auth functions fail and the login overlay cannot complete — the app cannot render. This is acceptable for a personal single-user app (same risk profile as any CDN dependency). An alternative is to download and commit the UMD file to the repo for full self-hosting — flagged as an option but not required for v1.

The anon key remains in `index.html`. After RLS migration, the anon key grants zero data access. Any unauthenticated request returns empty results (SELECT) or is rejected (INSERT/UPDATE/DELETE) at the Supabase layer.

---

## 8. Required Supabase Policy Changes

### 8.1 Email-Scoped RLS Pattern

All policies use Adam's email from the JWT claim, not a broad `USING (true)`:

```sql
-- Validated Supabase/PostgreSQL syntax for JWT email claim
USING (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us')
WITH CHECK (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us')
```

`auth.jwt()` returns the JWT payload as `jsonb`. `->> 'email'` extracts the email claim as `text`. The `::text` cast and `lower()` wrapper ensure consistent matching regardless of case. This is standard Supabase RLS syntax.

### 8.2 Existing Policy Cleanup

Before adding new policies, audit and drop all existing permissive policies on each table:

```sql
-- Run for each table to see what policies exist
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'goals';
-- Repeat for all 9 tables
```

Drop any policy that uses `TO anon` or `USING (true)` without a user check.

### 8.3 New Policies Per Table

Repeat this pattern for all 8 previously-unrestricted tables:

```sql
-- Example: weekly_reconciliations
CREATE POLICY "adam_select" ON weekly_reconciliations
  FOR SELECT TO authenticated
  USING (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us');

CREATE POLICY "adam_insert" ON weekly_reconciliations
  FOR INSERT TO authenticated
  WITH CHECK (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us');

CREATE POLICY "adam_update" ON weekly_reconciliations
  FOR UPDATE TO authenticated
  USING (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us')
  WITH CHECK (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us');
```

For tables where DELETE is used (`model_week_overrides`):

```sql
CREATE POLICY "adam_delete" ON model_week_overrides
  FOR DELETE TO authenticated
  USING (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us');
```

### 8.4 goal_registry Policy Update

Replace existing anon SELECT policy:

```sql
DROP POLICY IF EXISTS "anon_select" ON goal_registry;
-- (use actual policy name from pg_policies audit above)

CREATE POLICY "adam_select" ON goal_registry
  FOR SELECT TO authenticated
  USING (lower((auth.jwt() ->> 'email')::text) = 'adam@herndons.us');
```

---

## 9. Migration Plan — No Lockout Risk

**Rule: code ships first. RLS changes after code is verified in production.**

### Phase 1 — Auth Code Only (anon RLS unchanged)

1. Add supabase-js CDN script tag to `<head>`
2. Initialize `_supabase` client
3. Implement `getCurrentSession()`, `getAuthHeaders()`
4. Implement `showLoginOverlay()`, login form, logout button
5. Implement `onAuthStateChange` listener
6. Gate `loadAll()` and `renderApp()` on valid session
7. Update all functions in the Section 5.2 inventory to use `await getAuthHeaders()`
8. Run full regression (596/0) and Playwright (46/0)
9. Push to GitHub Pages
10. Verify login works end-to-end on live deployment

### Phase 2 — JWT Verification Before RLS Change

Before any anon policy is removed, verify that post-login Supabase calls are using the session JWT, not the anon key.

**Verification method:** Playwright network assertion in AUTH-E2E-7:

```javascript
// In e2e.js — intercept a Supabase REST call after login and assert Authorization header
// uses Bearer <token> not just the anon apikey
const [request] = await Promise.all([
  page.waitForRequest(req =>
    req.url().includes(SUPA_URL) &&
    req.headers()['authorization'] &&
    req.headers()['authorization'].startsWith('Bearer ') &&
    !req.headers()['authorization'].includes(SUPA_KEY) // not the anon key itself
  ),
  page.reload()
]);
// If this assertion passes, requests are using the session JWT
```

Do not proceed to Phase 3 until this test passes.

### Phase 3 — RLS Tightening (one table at a time)

Once Phase 2 is verified:

1. Start with `wishlist_items` (display-only, low stakes)
2. Confirm app still loads and wishlist tab renders after RLS change
3. Proceed table by table in order of increasing sensitivity: wishlist_items → weekly_notes → weekly_tasks → custom_tasks → weekly_reconciliations → model_week_overrides → budget_rules → goals → goal_registry
4. After each table change, reload the live app and confirm no console errors and no blank panels
5. After all 9 tables are done, run full Playwright suite against live deployment

---

## 10. Rollback Plan

| Scenario | Rollback action | Time to restore |
|---|---|---|
| Login overlay broken, can't log in | Revert index.html to pre-auth commit; anon RLS still active so app still works | Minutes (git push) |
| RLS tightened but session JWT not working | Restore anon policies in Supabase dashboard | Seconds (no deploy needed) |
| supabase-js CDN unavailable | Commit UMD bundle to repo and load locally instead | One commit |
| Refresh token expiry causing unexpected logout | Extend refresh window in Supabase Auth settings | Seconds (no deploy) |
| getAuthHeaders() throwing unexpectedly | Add session null-check in calling function; temporary fallback to anon while debugging | One commit |

The most important safety property: RLS changes are instant and reversible in Supabase dashboard without a code deploy. If Phase 3 breaks anything, restoring anon policies immediately restores the pre-auth app state.

---

## 11. Regression Test Plan

New test sections added to `test_regression.js`. All 596 existing tests must continue to pass with zero modifications.

### AUTH-A: getAuthHeaders() behavior (4 tests)

- AUTH-A1: `getAuthHeaders()` with a valid mock session returns `Authorization: Bearer <token>`, `apikey: SUPA_KEY`, and `Content-Type: application/json`
- AUTH-A2: `getAuthHeaders()` with a null session throws `'[Auth] No authenticated session'`
- AUTH-A3: Extra headers passed to `getAuthHeaders(extra)` are merged correctly without overwriting required fields
- AUTH-A4: `getCurrentSession()` returns null when `_supabase.auth.getSession()` resolves with no session data

### AUTH-B: App behavior without session (3 tests)

- AUTH-B1: With no session, `loadAll()` does not make any Supabase fetch calls
- AUTH-B2: With no session, `renderApp()` is not called during initialization
- AUTH-B3: A simulated 401 response from any table fetch triggers session clear path, not a JS error

### AUTH-C: No model behavior change gate (3 tests)

- AUTH-C1: `runModel()` output for weeks 1–31 is byte-identical before and after auth wrapper is added — same gate structure as GR-A1
- AUTH-C2: `VARIABLE_WATERFALL` and `REGULAR_WATERFALL` are unchanged (10 items each)
- AUTH-C3: `PRIORITY_TIERS` has 11 entries (unchanged)

### AUTH-D: Ask / Anthropic key (2 tests)

- AUTH-D1: `saveApiKey()` constructs a request using `getAuthHeaders()`, not `SUPA_H`
- AUTH-D2: A null session causes `saveApiKey()` to throw rather than send an unauthenticated request

**Total new regression tests: 12. New total: 608.**

---

## 12. Playwright Test Plan

New E2E section `AUTH` targeting 7 tests. Test credentials loaded from `.env` (never hardcoded, never committed).

| Test | Description |
|---|---|
| AUTH-E2E-1 | Fresh page load with no session shows login overlay, not dashboard |
| AUTH-E2E-2 | Invalid credentials show inline error, no crash, no redirect |
| AUTH-E2E-3 | Valid login renders dashboard; no console errors |
| AUTH-E2E-4 | Session persists across page reload; no re-login prompt |
| AUTH-E2E-5 | Sign out clears session and shows login overlay |
| AUTH-E2E-6 | After login, no Supabase REST call uses anon-only Authorization header (network assertion) |
| AUTH-E2E-7 | After login, all 9 tables return data; no 401 errors in network log |

**New total Playwright tests: 53.**

### Credentials handling in e2e.js

```javascript
// At top of e2e.js
const TEST_EMAIL    = process.env.TEST_EMAIL;
const TEST_PASSWORD = process.env.TEST_PASSWORD;

if (!TEST_EMAIL || !TEST_PASSWORD) {
  console.error('[e2e] ERROR: TEST_EMAIL and TEST_PASSWORD must be set in environment.');
  console.error('[e2e] Create a .env file (gitignored) with these values.');
  process.exit(1);
}
```

- `.env` is already covered by `.gitignore`
- Credentials are never logged — no `console.log(password)` in any path
- Password field is not captured in screenshots (Playwright screenshot masking or login overlay dismissed before screenshot)
- `TEST_EMAIL` and `TEST_PASSWORD` are never interpolated into error messages

---

## 13. What Will Not Change

The following are outside auth scope and will not be touched:

- `runModel()` — no changes
- `applyGoalsFromData()` — no changes
- `VARIABLE_WATERFALL`, `REGULAR_WATERFALL` — no changes
- `PRIORITY_TIERS` — no changes
- `applyBudgetRulesForWeek()` — no changes
- `diffModels()` — no changes
- `applyCompletionSnapshots()` — no changes
- All week object fields and shapes — no changes
- All Supabase table schemas — no changes (RLS policies change, schemas do not)
- `HARDCODED_GOALS_FALLBACK` — no changes
- `goalsLoadStatus` state machine — no changes
- All waterfall constants (`OP_FL`, `MIN_XFR`, `AK_START`, etc.) — no changes
- Commission split logic — no changes
- `START_CHK` / `START_SAV` / all starting balances — no changes
- Budget Rules engine — no changes
- What-If Calculator — no changes
- GitHub Pages deployment structure — no changes
- CNAME — no changes
- `model_spec.md` model invariants — all remain true

---

## 14. No Model Behavior Changes — Confirmation

This build adds an authentication wrapper around app initialization. It does not touch any value, function, or code path that flows into `runModel()`. The model runs identically for an authenticated user as it did for an unauthenticated user. AUTH-C regression gate is the machine-verifiable proof: `runModel()` output must be byte-identical before and after the auth build.

---

## Open Questions Resolved from v1.0

| Question | Resolution |
|---|---|
| Should `wishlist_items` remain anon-readable? | No. Auth-only. No exceptions. |
| Login email? | `adam@herndons.us` |
| No in-app forgot-password UI? | Acceptable for v1. Reset via Supabase dashboard. |
| `USING (true)` vs email-scoped RLS? | Email-scoped. `auth.jwt() ->> 'email' = 'adam@herndons.us'`. No `user_id` columns needed. |
| Use `supabase-js`? | Yes, CDN-loaded UMD for auth functions only. No build step change. |

---

*Spec v1.1. No build authorized until approved by ChatGPT.*
