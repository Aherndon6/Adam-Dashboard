# Herndon Financial OS — Authentication / Access Control Spec

**Version:** 1.0
**Date:** Cal Wk 25 (Jun 21, 2026)
**Status:** For review — no build authorized until approved by ChatGPT
**Scope:** Auth layer only. Zero model behavior changes.

---

## 1. Current Supabase RLS Posture by Table

| Table | anon SELECT | anon INSERT | anon UPDATE | anon DELETE | Notes |
|---|---|---|---|---|---|
| `goals` | ✓ | ✓ | ✓ | ✓ | KV store — akFunded, IRA flags, misc state |
| `weekly_reconciliations` | ✓ | ✓ | ✓ | ✓ | Per-week actual balances |
| `weekly_tasks` | ✓ | ✓ | ✓ | ✓ | Per-task completion state |
| `weekly_notes` | ✓ | ✓ | ✓ | ✓ | Per-week text notes |
| `model_week_overrides` | ✓ | ✓ | ✓ | ✓ | Custom week event overrides |
| `wishlist_items` | ✓ | ✓ | ✓ | ✓ | Feature wishlist |
| `custom_tasks` | ✓ | ✓ | ✓ | ✓ | User-created weekly tasks |
| `budget_rules` | ✓ | ✓ | ✓ | ✓ | Recurring/one-time adjustments |
| `goal_registry` | ✓ | ✗ | ✗ | ✗ | SELECT-only RLS — Phase 6A |

**Summary:** 8 of 9 tables currently have full anon read/write access. Only `goal_registry` has a restricted policy, and it is read-only even for authenticated users.

---

## 2. Tables Currently Allowing anon Read/Write

All tables except `goal_registry` accept unauthenticated reads and writes. Anyone who discovers the deployed URL and extracts the anon key from `index.html` can read all financial data and write arbitrary values to any of these tables.

The anon key is embedded in plain text in `index.html` and is visible to any browser with devtools. This is unavoidable on a GitHub Pages static deployment — the key cannot be kept server-side. The mitigation is RLS policies that enforce authentication server-side, regardless of what the client sends.

---

## 3. Target Access Model After Auth

**Single authenticated user (Adam).** No multi-user support, no roles, no admin vs. read-only split.

| Table | After auth: SELECT | After auth: INSERT/UPDATE/DELETE |
|---|---|---|
| `goals` | authenticated only | authenticated only |
| `weekly_reconciliations` | authenticated only | authenticated only |
| `weekly_tasks` | authenticated only | authenticated only |
| `weekly_notes` | authenticated only | authenticated only |
| `model_week_overrides` | authenticated only | authenticated only |
| `wishlist_items` | authenticated only | authenticated only |
| `custom_tasks` | authenticated only | authenticated only |
| `budget_rules` | authenticated only | authenticated only |
| `goal_registry` | authenticated only | read-only (SELECT) — unchanged |

RLS policy pattern for all tables (except goal_registry which keeps its existing policy):

```sql
-- SELECT
CREATE POLICY "authenticated read" ON table_name
  FOR SELECT TO authenticated
  USING (true);

-- INSERT
CREATE POLICY "authenticated insert" ON table_name
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- UPDATE
CREATE POLICY "authenticated update" ON table_name
  FOR UPDATE TO authenticated
  USING (true);

-- DELETE (only tables that currently use delete)
CREATE POLICY "authenticated delete" ON table_name
  FOR DELETE TO authenticated
  USING (true);
```

The `anon` role will have no access to any table after migration. An unauthenticated visitor to the URL will see the login screen, not the dashboard.

---

## 4. Recommended Auth Approach: Supabase Auth — Email + Password

**Recommendation: Supabase Auth with email/password.**

Options considered:

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| Supabase Auth — email + password | Persistent sessions, JWT refresh, no email needed per login, Supabase native | Requires password management | **Recommended** |
| Supabase Auth — magic link | No password to remember | Requires email access every login (unless session persists) | Acceptable alternative |
| Custom password gate (client-side only) | Simplest to build | Not real auth — no server enforcement, anon key still works via API | Rejected — no security value |
| GitHub OAuth | Single sign-on | Overkill for single-user, requires OAuth app setup | Rejected for now |

**Why email + password:**
- Single user, so no user provisioning complexity
- Password can be stored in 1Password — no friction
- Sessions persist via Supabase JWT refresh tokens (not re-entering password on every visit)
- Works entirely client-side — compatible with GitHub Pages
- Supabase enforces auth server-side via RLS regardless of client key exposure
- Can be upgraded to MFA or magic link later without model changes

**Supabase Auth setup required:**
1. Enable Email provider in Supabase Auth settings
2. Create Adam's account via Supabase dashboard (no signup UI needed — direct account creation)
3. Set session duration (recommend 30-day refresh window)
4. Disable public signups (single-user app — no one else should be able to create an account)

---

## 5. Login / Logout UX

**Login:** Full-page overlay rendered before `renderApp()` runs. If `supabase.auth.getSession()` returns null, show login form instead of dashboard. Form fields: email, password, submit button. On success: session stored, `loadAll()` called, dashboard renders. On failure: inline error message ("Invalid credentials").

**No signup UI.** Account created directly in Supabase dashboard. The login form has no register/forgot-password path visible to the user (password reset can be triggered via Supabase dashboard if needed).

**Logout:** Small "Sign out" link in the dashboard header or settings area. Calls `supabase.auth.signOut()`, clears session, renders login overlay.

**Unauthenticated API calls:** If a Supabase call returns 401 after session expiry, the app intercepts it, clears the session, and shows the login overlay. No crash, no blank panel.

---

## 6. Session Persistence

Supabase Auth stores the JWT access token and refresh token in `localStorage` (handled automatically by the Supabase JS client). On page load:

1. `supabase.auth.getSession()` is called before anything else
2. If a valid session exists: proceed to `loadAll()` and `renderApp()` as normal
3. If session is expired but refresh token is valid: Supabase auto-refreshes transparently
4. If no session or refresh fails: show login overlay

**Recommended session window:** 1-hour access token, 30-day refresh token (Supabase defaults). Adam will not need to re-enter credentials unless he explicitly signs out or goes 30 days without visiting.

**`onAuthStateChange` listener:** Register at init to catch token refreshes and mid-session expiry. If the auth state drops to `null` during an active session (e.g. token revoked), overlay is shown immediately.

---

## 7. Impact on GitHub Pages Deployment

**No deployment model change required.** Supabase Auth is entirely client-side. GitHub Pages continues to serve `index.html` as a static file with no server-side component.

The anon key remains embedded in `index.html` — this cannot be avoided on a static host. However, after RLS migration, the anon key has zero access to any table. An attacker with the key can reach the Supabase REST API but all queries will return empty (RLS blocks anon reads) and all writes will be rejected.

**The security model shifts from "obscurity" (hope nobody finds the key) to "enforcement" (RLS blocks unauthenticated access at the database layer).**

One side effect: the Supabase client initialization changes from using the anon key for all calls to using the session JWT for all calls after login. The anon key is still used to initialize the client; Supabase Auth handles injecting the JWT into subsequent requests automatically.

No changes to CNAME, GitHub Pages settings, or deployment process.

---

## 8. Required Supabase Policy Changes

### Step 1: Remove existing anon policies

For each of the 8 unrestricted tables, drop the permissive anon policies currently in place:

```sql
-- Example for weekly_reconciliations (repeat for all 8 tables)
DROP POLICY IF EXISTS "anon_read" ON weekly_reconciliations;
DROP POLICY IF EXISTS "anon_write" ON weekly_reconciliations;
-- (actual policy names may vary — check information_schema.policies first)
```

### Step 2: Add authenticated policies

For each table, add SELECT + INSERT + UPDATE (and DELETE where applicable):

```sql
-- weekly_reconciliations (representative — repeat pattern for all 8 tables)
CREATE POLICY "auth_select" ON weekly_reconciliations
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "auth_insert" ON weekly_reconciliations
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "auth_update" ON weekly_reconciliations
  FOR UPDATE TO authenticated USING (true);
```

### Step 3: goal_registry — update existing policy

Current policy allows anon SELECT. Change to authenticated SELECT:

```sql
DROP POLICY IF EXISTS "anon_select" ON goal_registry;

CREATE POLICY "auth_select" ON goal_registry
  FOR SELECT TO authenticated USING (true);
```

### Tables requiring DELETE policy

Review which tables use DELETE in the app (model_week_overrides uses delete on override removal; custom_tasks may use delete). Add `auth_delete` policy for those only.

---

## 9. Migration Plan — No Lockout Risk

The critical constraint: RLS policy changes take effect immediately. If policies are changed before Adam's session is established and verified, the app breaks.

**Order of operations:**

1. **Enable Supabase Auth** (Email provider on, public signups off) — no impact on current RLS
2. **Create Adam's account** via Supabase dashboard — no impact on current RLS
3. **Build and deploy the auth layer in index.html** — login overlay, session check, `signOut()` — but keep ALL existing RLS policies unchanged. App now requires login to render, but all Supabase calls still use anon access behind the scenes.
4. **Test login end-to-end on staging** (local file open or a test branch) — confirm session persists, loadAll() works, all tabs render correctly
5. **Run full regression + Playwright** — confirm 596/0 and 46/0 still pass with auth layer in place
6. **Only after step 5 passes:** change RLS policies table by table in Supabase dashboard, starting with lowest-risk table (wishlist_items), verifying app still loads after each change
7. **Push final commit** with RLS confirmed on all 9 tables

**Never change RLS and code in the same step.** Code first, verify, then RLS.

---

## 10. Rollback Plan

| Scenario | Rollback action |
|---|---|
| Login overlay broken — can't authenticate | Revert index.html to pre-auth commit; RLS still anon so app still works |
| RLS changed but session not working | Restore anon policies in Supabase dashboard (takes effect immediately, no deploy needed) |
| Refresh token expiry causing mid-session logout | Extend refresh window in Supabase Auth settings (no code change) |
| Auth change breaks loadAll() | Revert RLS to anon; debug session JWT injection |

**Key safety property:** RLS changes are instant and reversible via Supabase dashboard with no code deploy. If auth is broken at any point, restoring anon policies immediately restores the app to its pre-auth state while code is debugged.

---

## 11. Regression Test Plan

The test harness (`test_regression.js`) loads `index.html` by stripping the `<script>` block and evaluating it in Node.js with a stubbed `window.fetch`. Auth adds a new surface:

**New test sections required:**

`AUTH-A: Session check behavior`
- AUTH-A1: If `getSession()` returns null, `goalsLoadStatus` remains `'not_configured'` and `renderApp()` is not called
- AUTH-A2: If `getSession()` returns a valid session, `loadAll()` is called normally
- AUTH-A3: `onAuthStateChange` with `SIGNED_OUT` event triggers login overlay render, not a crash

`AUTH-B: Authenticated Supabase call shape`
- AUTH-B1: After successful login, all `loadAll()` fetch calls include Authorization header with Bearer token
- AUTH-B2: A 401 response from any Supabase table triggers session clear and overlay, not a JS error

`AUTH-C: No model behavior change gate`
- AUTH-C1: `runModel()` output for weeks 1–31 is byte-identical before and after auth layer — same as GR-A1 gate structure
- AUTH-C2: `VARIABLE_WATERFALL` and `REGULAR_WATERFALL` are unchanged
- AUTH-C3: `PRIORITY_TIERS` has 11 entries (unchanged)

**Existing tests:** All 596 must continue to pass. No existing test should require modification — the auth layer wraps the app initialization, not any model logic.

---

## 12. Playwright Test Plan

New E2E section `AUTH` (target: 6 tests):

| Test | Description |
|---|---|
| AUTH-E2E-1 | Fresh page load with no session shows login overlay, not dashboard |
| AUTH-E2E-2 | Valid email + password login renders dashboard and passes console-error check |
| AUTH-E2E-3 | Session persists across page reload (no re-login required within refresh window) |
| AUTH-E2E-4 | Sign out button clears session and shows login overlay |
| AUTH-E2E-5 | Invalid credentials show inline error message, no crash |
| AUTH-E2E-6 | After login, all 9 Supabase tables return data (no 401 errors in network log) |

These tests require a real Supabase test account (or the production account with test credentials stored as environment variables in the e2e runner). The Playwright tests currently run against the live deployment — AUTH-E2E-1 through AUTH-E2E-6 will require the test runner to have valid credentials available.

**Approach:** Store test credentials in a `.env` file (gitignored) and load in `e2e.js` via `process.env.TEST_EMAIL` / `process.env.TEST_PASSWORD`. The `.env` file is already covered by `.gitignore` (`*.env` / `.env`).

---

## 13. Explicit List of What Will Not Change

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
- `START_CHK` / `START_SAV` / starting balances — no changes
- Budget Rules engine — no changes
- What-If Calculator — no changes
- GitHub Pages deployment structure — no changes
- CNAME — no changes

---

## 14. Confirmation: No Model Behavior Changes

This spec describes an authentication wrapper only. The model runs identically before and after auth. Auth determines whether `loadAll()` is called and whether Supabase REST calls succeed — it does not touch any value that flows into `runModel()`.

The AUTH-C regression gate (item 11) is the machine-verifiable proof of this: `runModel()` output must be byte-identical before and after the auth build.

---

## Open Questions for ChatGPT Review

1. **anon SELECT after auth:** Should any tables remain anon-readable after migration (e.g. `wishlist_items` which is display-only)? Keeping all tables auth-only is simpler and more consistent, but there is no functional reason `wishlist_items` needs to be private.

2. **Supabase Auth email:** Adam's login email will be `adam@herndons.us`. Confirm this is acceptable or whether a separate Supabase-specific email is preferred.

3. **Password reset path:** No in-app forgot-password UI is planned. If Adam loses the password, reset is via Supabase dashboard. Confirm this is acceptable for a single-user app.

4. **Row-level user_id scoping:** The current data model has no `user_id` column on any table — data is not user-scoped. The auth policies use `USING (true)` rather than `USING (auth.uid() = user_id)`. This is correct for a single-user app but would need to change before multi-user access is ever added. Confirm this approach is acceptable.

---

*Spec v1.0. No build authorized until ChatGPT approves.*
