# Herndon Financial OS — Phase 4A: RLS Tightening Spec

**Version:** 1.2
**Date:** June 22, 2026
**Status:** Awaiting final ChatGPT authorization before execution
**Prior closed builds:** Auth v1 (0f98fb3), Wishlist v2 (6fdc7ea)
**Related:** docs/auth-spec-v1.4.md, docs/security-brittleness-backlog.md
**Policy audit date:** June 22, 2026

---

## Problem Statement

Auth v1 established authenticated access to all Supabase tables. The anon key — present in git history and visible in source — still has read and write access to multiple financial data tables. Any actor with the anon key can read reconciliation data, read and write goal data, and read and write model week overrides without authenticating through the app.

The app itself no longer uses anon reads. All Supabase calls use `getAuthHeaders()` which returns a Bearer token post-login. Anon policies are dead weight creating real exposure.

---

## Scope

### In scope

- Remove all anon and public role policies from all public schema tables
- Add authenticated policies to `custom_tasks` before dropping its public policy (no authenticated policy currently exists)
- Convert `dashboard_data` public policy to authenticated (legacy table, app dependency unconfirmed — policy cleanup only, no table drop)
- Add AUTH-ANON-1 Playwright test confirming anon is blocked on live Supabase after changes
- Write exact rollback SQL before any DROP is executed

### Out of scope (explicit)

- No migration from `is_allowed_user()` email-based check to `auth.uid()` — Phase 4B
- No CSP or CDN hardening — separate build
- No role enforcement changes
- No changes to Auth architecture or auth state machine
- No `is_allowed_user()` function changes
- No financial model logic changes
- No Goal Registry CRUD
- No Wishlist UX changes
- No `app_users.auth_user_id NOT NULL` constraint — Phase 4B
- No `dashboard_data` table drop — Phase 4A is policy cleanup only

---

## Complete Policy Audit (June 22, 2026)

### Full table list — public schema (11 tables)

`app_users`, `budget_rules`, `custom_tasks`, `dashboard_data`, `goal_registry`, `goals`, `model_week_overrides`, `weekly_notes`, `weekly_reconciliations`, `weekly_tasks`, `wishlist_items`

### Policy inventory by table

**app_users** — No anon exposure. Nothing to drop.

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| app_users_select_self | SELECT | {authenticated} | lower(email) = lower(auth.jwt() ->> 'email') | — |

**budget_rules** — Anon SELECT only. Auth SELECT exists. No write policies for any role (read-only from app).

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| anon_read_budget_rules | SELECT | {anon} | true | — |
| budget_rules_select_app_users | SELECT | {authenticated} | is_allowed_user() | — |

**custom_tasks** — {public} ALL policy. No authenticated policy. Requires auth policies added before drop.

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| anon_all | ALL | {public} | true | true |

**dashboard_data** — {public} ALL with `auth.uid() = user_id` USING clause. Effectively anon-safe (auth.uid() returns NULL for anon so no rows match), but {public} should be {authenticated}. App dependency unconfirmed — likely a legacy table predating the current is_allowed_user() authorization pattern. Phase 4A treats this as policy cleanup only: convert {public} to {authenticated}, do not drop the table.

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| Users can only access their own data | ALL | {public} | auth.uid() = user_id | auth.uid() = user_id |

**goal_registry** — Anon SELECT only. Auth SELECT exists. No write policies for any role (managed via Supabase dashboard).

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| anon_read_goal_registry | SELECT | {anon} | true | — |
| goal_registry_select_app_users | SELECT | {authenticated} | is_allowed_user() | — |

**goals** — Anon SELECT, INSERT, UPDATE. No anon DELETE. All authenticated policies exist. CRITICAL: anon can write financial goals data right now.

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| anon_read | SELECT | {anon} | true | — |
| anon_write | INSERT | {anon} | — | true |
| anon_update | UPDATE | {anon} | true | — |
| goals_select_app_users | SELECT | {authenticated} | is_allowed_user() | — |
| goals_insert_app_users | INSERT | {authenticated} | — | is_allowed_user() |
| goals_update_app_users | UPDATE | {authenticated} | is_allowed_user() | is_allowed_user() |
| goals_delete_app_users | DELETE | {authenticated} | is_allowed_user() | — |

**model_week_overrides** — Anon ALL. All authenticated policies exist. CRITICAL: anon can write financial model overrides right now.

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| anon_all | ALL | {anon} | true | true |
| model_week_overrides_select_app_users | SELECT | {authenticated} | is_allowed_user() | — |
| model_week_overrides_insert_app_users | INSERT | {authenticated} | — | is_allowed_user() |
| model_week_overrides_update_app_users | UPDATE | {authenticated} | is_allowed_user() | is_allowed_user() |
| model_week_overrides_delete_app_users | DELETE | {authenticated} | is_allowed_user() | — |

**weekly_notes** — Anon ALL. All authenticated policies exist.

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| anon_all | ALL | {anon} | true | true |
| weekly_notes_select_app_users | SELECT | {authenticated} | is_allowed_user() | — |
| weekly_notes_insert_app_users | INSERT | {authenticated} | — | is_allowed_user() |
| weekly_notes_update_app_users | UPDATE | {authenticated} | is_allowed_user() | is_allowed_user() |
| weekly_notes_delete_app_users | DELETE | {authenticated} | is_allowed_user() | — |

**weekly_reconciliations** — Anon ALL. All authenticated policies exist. CRITICAL: anon can write financial reconciliation data right now.

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| anon_all | ALL | {anon} | true | true |
| weekly_reconciliations_select_app_users | SELECT | {authenticated} | is_allowed_user() | — |
| weekly_reconciliations_insert_app_users | INSERT | {authenticated} | — | is_allowed_user() |
| weekly_reconciliations_update_app_users | UPDATE | {authenticated} | is_allowed_user() | is_allowed_user() |
| weekly_reconciliations_delete_app_users | DELETE | {authenticated} | is_allowed_user() | — |

**weekly_tasks** — Anon ALL. All authenticated policies exist.

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| anon_all | ALL | {anon} | true | true |
| weekly_tasks_select_app_users | SELECT | {authenticated} | is_allowed_user() | — |
| weekly_tasks_insert_app_users | INSERT | {authenticated} | — | is_allowed_user() |
| weekly_tasks_update_app_users | UPDATE | {authenticated} | is_allowed_user() | is_allowed_user() |
| weekly_tasks_delete_app_users | DELETE | {authenticated} | is_allowed_user() | — |

**wishlist_items** — Anon SELECT, INSERT, UPDATE, DELETE (four separate policies). All authenticated policies exist.

| Policy | CMD | Roles | USING | WITH CHECK |
|---|---|---|---|---|
| anon_read | SELECT | {anon} | true | — |
| anon_insert | INSERT | {anon} | — | true |
| anon_update | UPDATE | {anon} | true | — |
| anon_delete | DELETE | {anon} | true | — |
| wishlist_items_select_app_users | SELECT | {authenticated} | is_allowed_user() | — |
| wishlist_items_insert_app_users | INSERT | {authenticated} | — | is_allowed_user() |
| wishlist_items_update_app_users | UPDATE | {authenticated} | is_allowed_user() | is_allowed_user() |
| wishlist_items_delete_app_users | DELETE | {authenticated} | is_allowed_user() | — |

---

## Anon Exposure Summary

| Table | Anon exposure | Severity | Auth covered? | Action |
|---|---|---|---|---|
| app_users | None | — | Yes | Nothing to do |
| budget_rules | SELECT | Low | Yes | DROP 1 policy |
| custom_tasks | ALL (via public) | High | No | ADD 4 auth policies, then DROP |
| dashboard_data | ALL (via public, auth.uid() neutralizes anon) | Low | No explicit auth policy | Convert public → authenticated |
| goal_registry | SELECT | Low | Yes | DROP 1 policy |
| goals | SELECT + INSERT + UPDATE | Critical | Yes | DROP 3 policies |
| model_week_overrides | ALL | Critical | Yes | DROP 1 policy |
| weekly_notes | ALL | High | Yes | DROP 1 policy |
| weekly_reconciliations | ALL | Critical | Yes | DROP 1 policy |
| weekly_tasks | ALL | High | Yes | DROP 1 policy |
| wishlist_items | SELECT + INSERT + UPDATE + DELETE | High | Yes | DROP 4 policies |

**Total policies to drop: 14**
**Policies to add before drop (custom_tasks): 4**
**Total SQL operations: 19**

---

## Execution Plan

### Pre-execution baseline

Before any SQL changes, confirm 56/0 locally:
```bash
cd ~/Adam-Dashboard && node e2e.js
```

---

### Group 1 — Read-only config tables

Tables: `budget_rules`, `goal_registry`
Exposure removed: anon SELECT on config data. No write exposure in these tables.

```sql
DROP POLICY IF EXISTS "anon_read_budget_rules" ON public.budget_rules;
DROP POLICY IF EXISTS "anon_read_goal_registry" ON public.goal_registry;
```

**Verification after Group 1:**
```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('budget_rules', 'goal_registry')
  AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
-- Expected: 0 rows
```

Live Playwright gate: `HFOS_URL=https://dashboard.herndons.us node e2e.js` → 56/0

---

### Group 2 — Wishlist items

Table: `wishlist_items`
Exposure removed: anon SELECT, INSERT, UPDATE, DELETE

```sql
DROP POLICY IF EXISTS "anon_read" ON public.wishlist_items;
DROP POLICY IF EXISTS "anon_insert" ON public.wishlist_items;
DROP POLICY IF EXISTS "anon_update" ON public.wishlist_items;
DROP POLICY IF EXISTS "anon_delete" ON public.wishlist_items;
```

**Verification after Group 2:**
```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'wishlist_items'
  AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
-- Expected: 0 rows
```

Live Playwright gate: 56/0

---

### Group 3 — Weekly operational tables

Tables: `weekly_notes`, `weekly_tasks`
Exposure removed: anon ALL (full CRUD)

```sql
DROP POLICY IF EXISTS "anon_all" ON public.weekly_notes;
DROP POLICY IF EXISTS "anon_all" ON public.weekly_tasks;
```

**Verification after Group 3:**
```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('weekly_notes', 'weekly_tasks')
  AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
-- Expected: 0 rows
```

Live Playwright gate: 56/0

---

### Group 4 — Weekly reconciliations

Table: `weekly_reconciliations`
Exposure removed: anon ALL on primary financial data. Isolated from Group 3 for individual rollback containment.

```sql
DROP POLICY IF EXISTS "anon_all" ON public.weekly_reconciliations;
```

**Verification after Group 4:**
```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'weekly_reconciliations'
  AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
-- Expected: 0 rows
```

Live Playwright gate: 56/0

---

### Group 5 — Goals and model overrides

Tables: `goals`, `model_week_overrides`
Exposure removed: anon SELECT/INSERT/UPDATE on goals (financial write exposure), anon ALL on model overrides

```sql
DROP POLICY IF EXISTS "anon_read" ON public.goals;
DROP POLICY IF EXISTS "anon_write" ON public.goals;
DROP POLICY IF EXISTS "anon_update" ON public.goals;
DROP POLICY IF EXISTS "anon_all" ON public.model_week_overrides;
```

**Verification after Group 5:**
```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('goals', 'model_week_overrides')
  AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
-- Expected: 0 rows
```

Live Playwright gate: 56/0

---

### Group 6 — custom_tasks (add auth policies first, then drop public)

Table: `custom_tasks`
Current state: one `{public}` ALL policy, no authenticated policy. Must add authenticated policies before dropping, or the app loses access.

**Step 6a — Add authenticated policies:**

Note: `public.is_allowed_user()` is schema-qualified to avoid ambiguity. Each CREATE is preceded by a DROP IF EXISTS to make this safe for partial reruns.

```sql
DROP POLICY IF EXISTS "custom_tasks_select_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_select_app_users"
ON public.custom_tasks
FOR SELECT TO authenticated
USING (public.is_allowed_user());

DROP POLICY IF EXISTS "custom_tasks_insert_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_insert_app_users"
ON public.custom_tasks
FOR INSERT TO authenticated
WITH CHECK (public.is_allowed_user());

DROP POLICY IF EXISTS "custom_tasks_update_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_update_app_users"
ON public.custom_tasks
FOR UPDATE TO authenticated
USING (public.is_allowed_user())
WITH CHECK (public.is_allowed_user());

DROP POLICY IF EXISTS "custom_tasks_delete_app_users" ON public.custom_tasks;
CREATE POLICY "custom_tasks_delete_app_users"
ON public.custom_tasks
FOR DELETE TO authenticated
USING (public.is_allowed_user());
```

**Step 6b — Gate on live Playwright with both policies active:**

Live Playwright gate: 56/0 (both the public policy and the new authenticated policies are active simultaneously)

Also confirm in the live dashboard that custom tasks load, create, and save correctly before proceeding to 6c.

**Step 6c — Drop the public policy:**

```sql
DROP POLICY IF EXISTS "anon_all" ON public.custom_tasks;
```

**Verification after Group 6:**
```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'custom_tasks';
-- Expected: 4 rows, all roles = {authenticated}
```

Also confirm no anon/public policies remain:
```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'custom_tasks'
  AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
-- Expected: 0 rows
```

Live Playwright gate: 56/0

---

### Group 7 — dashboard_data policy cleanup

Table: `dashboard_data`
Status: Legacy table. App dependency unconfirmed — no current app code path is known to read or write this table. The existing policy uses `auth.uid() = user_id` which already neutralizes anon access (auth.uid() is NULL for anon, so no rows match). This group is structural cleanup: convert {public} to {authenticated}.

```sql
DROP POLICY IF EXISTS "Users can only access their own data" ON public.dashboard_data;

DROP POLICY IF EXISTS "dashboard_data_all_app_users" ON public.dashboard_data;
CREATE POLICY "dashboard_data_all_app_users"
ON public.dashboard_data
FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
```

**Verification after Group 7:**
```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'dashboard_data';
-- Expected: 1 row, roles = {authenticated}
```

```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'dashboard_data'
  AND ('anon' = ANY(roles) OR 'public' = ANY(roles));
-- Expected: 0 rows
```

Live Playwright gate: 56/0

---

## Final Anon-Blocked Verification (after all groups)

Run in Supabase SQL editor after all groups complete:

```sql
SELECT tablename, policyname, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND ('anon' = ANY(roles) OR 'public' = ANY(roles))
ORDER BY tablename, policyname;
-- Expected: 0 rows
```

If any row appears here, that policy was not dropped and must be investigated before proceeding.

---

## AUTH-ANON-1 Playwright Test

**Important:** AUTH-ANON-1 makes direct HTTP calls to the live Supabase project using `SUPA_URL` and `SUPA_ANON` from the page context. These constants point to the production Supabase instance regardless of whether `node e2e.js` is run against `file://` locally or `HFOS_URL=https://dashboard.herndons.us`. This test always hits live Supabase. It will fail if run before the SQL groups are executed, and pass after.

Add to e2e.js before Section H (XSS safety), after existing wishlist tests. Add after all SQL groups are complete.

```javascript
// ── AUTH-ANON-1: Anon key blocked after RLS tightening ────────────────────
// NOTE: This test calls live Supabase directly using SUPA_URL + SUPA_ANON from
// page context. It runs against the production Supabase project regardless of
// whether e2e.js is targeting file:// or the live URL.
console.log('── AUTH-ANON-1: Anon key blocked on live Supabase ──');
await test('AUTH-ANON-1: Anon key returns no protected rows and cannot write', async () => {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
  await page.waitForTimeout(500);

  // ── Part 1: Anon SELECT returns no protected rows ──
  const readResults = await page.evaluate(async () => {
    const tables = [
      'weekly_reconciliations',
      'goals',
      'model_week_overrides',
      'wishlist_items'
    ];
    const out = [];
    for (const t of tables) {
      try {
        const r = await fetch(
          SUPA_URL + '/rest/v1/' + t + '?select=id&limit=5',
          {
            headers: {
              'apikey': SUPA_ANON,
              'Authorization': 'Bearer ' + SUPA_ANON
            }
          }
        );
        const body = await r.json();
        const rowCount = Array.isArray(body) ? body.length : -1;
        out.push({ table: t, status: r.status, rows: rowCount });
      } catch (e) {
        out.push({ table: t, status: -1, rows: -1, error: e.message });
      }
    }
    return out;
  });

  for (const r of readResults) {
    // Accept 401, 403, or 200 with empty rows. Any non-empty 2xx is a failure.
    const blocked = r.status === 401 || r.status === 403 || r.rows === 0;
    assert(
      blocked,
      'AUTH-ANON-1 SELECT: anon key returned protected rows on ' + r.table +
      ' (status=' + r.status + ', rows=' + r.rows + ')'
    );
  }

  // ── Part 2: Anon INSERT is blocked ──
  // Attempts to insert a clearly-marked test row into wishlist_items.
  // Expected: non-2xx status OR 2xx with RLS error in body (no row created).
  // If the insert unexpectedly succeeds, the test fails loudly and attempts cleanup.
  const writeResult = await page.evaluate(async () => {
    try {
      const r = await fetch(
        SUPA_URL + '/rest/v1/wishlist_items',
        {
          method: 'POST',
          headers: {
            'apikey': SUPA_ANON,
            'Authorization': 'Bearer ' + SUPA_ANON,
            'Content-Type': 'application/json',
            'Prefer': 'return=representation'
          },
          body: JSON.stringify({
            title: '__anon_write_test_should_be_blocked__',
            phase: 'Backlog',
            status: 'idea',
            priority: 0,
            item_type: 'feature'
          })
        }
      );
      const body = await r.json();
      const rowCreated = r.ok && Array.isArray(body) && body.length > 0;
      // If write somehow succeeded, attempt cleanup
      if (rowCreated && body[0] && body[0].id) {
        await fetch(
          SUPA_URL + '/rest/v1/wishlist_items?id=eq.' + body[0].id,
          {
            method: 'DELETE',
            headers: {
              'apikey': SUPA_ANON,
              'Authorization': 'Bearer ' + SUPA_ANON
            }
          }
        );
      }
      return { status: r.status, rowCreated };
    } catch (e) {
      return { status: -1, rowCreated: false, error: e.message };
    }
  });

  assert(
    !writeResult.rowCreated,
    'AUTH-ANON-1 INSERT: anon key successfully wrote a row to wishlist_items — ' +
    'RLS is not blocking anon writes (status=' + writeResult.status + '). ' +
    'Cleanup attempted. Phase 4A SQL may not have been applied.'
  );

  // NOTE: If AUTH-ANON-1 fails because anon insert unexpectedly succeeded,
  // check wishlist_items in Supabase for a row with title
  // '__anon_write_test_should_be_blocked__' and manually delete it before
  // continuing. The test attempts anon-key cleanup above, but that cleanup
  // may itself fail depending on which anon policies remain active at the
  // time of the failure.

  await context.close();
});
```

After adding this test, new Playwright baseline: **57/0**.

---

## Rollback SQL

Execute only the rollback for groups that have already been dropped. Rollback is per-group.

**Group 1 rollback:**
```sql
CREATE POLICY "anon_read_budget_rules"
ON public.budget_rules FOR SELECT TO anon USING (true);

CREATE POLICY "anon_read_goal_registry"
ON public.goal_registry FOR SELECT TO anon USING (true);
```

**Group 2 rollback:**
```sql
CREATE POLICY "anon_read"
ON public.wishlist_items FOR SELECT TO anon USING (true);

CREATE POLICY "anon_insert"
ON public.wishlist_items FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "anon_update"
ON public.wishlist_items FOR UPDATE TO anon USING (true);

CREATE POLICY "anon_delete"
ON public.wishlist_items FOR DELETE TO anon USING (true);
```

**Group 3 rollback:**
```sql
CREATE POLICY "anon_all"
ON public.weekly_notes FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_all"
ON public.weekly_tasks FOR ALL TO anon USING (true) WITH CHECK (true);
```

**Group 4 rollback:**
```sql
CREATE POLICY "anon_all"
ON public.weekly_reconciliations FOR ALL TO anon USING (true) WITH CHECK (true);
```

**Group 5 rollback:**
```sql
CREATE POLICY "anon_read"
ON public.goals FOR SELECT TO anon USING (true);

CREATE POLICY "anon_write"
ON public.goals FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "anon_update"
ON public.goals FOR UPDATE TO anon USING (true);

CREATE POLICY "anon_all"
ON public.model_week_overrides FOR ALL TO anon USING (true) WITH CHECK (true);
```

**Group 6 rollback:**
```sql
DROP POLICY IF EXISTS "custom_tasks_select_app_users" ON public.custom_tasks;
DROP POLICY IF EXISTS "custom_tasks_insert_app_users" ON public.custom_tasks;
DROP POLICY IF EXISTS "custom_tasks_update_app_users" ON public.custom_tasks;
DROP POLICY IF EXISTS "custom_tasks_delete_app_users" ON public.custom_tasks;

CREATE POLICY "anon_all"
ON public.custom_tasks FOR ALL TO public USING (true) WITH CHECK (true);
```

**Group 7 rollback:**
```sql
DROP POLICY IF EXISTS "dashboard_data_all_app_users" ON public.dashboard_data;

CREATE POLICY "Users can only access their own data"
ON public.dashboard_data
FOR ALL TO public
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
```

**Rollback trigger conditions:**
- Login fails in production after any group
- Any Playwright test fails unexpectedly after a group drop
- Dashboard section fails to load data after login
- Adam or Wendy cannot sign in

---

## Test Gates

| Gate | Command | Target | When |
|---|---|---|---|
| Pre-build baseline | `node e2e.js` | 56/0 local | Before any SQL |
| After Group 1 | `HFOS_URL=https://dashboard.herndons.us node e2e.js` | 56/0 | After Group 1 |
| After Group 2 | Live Playwright | 56/0 | After Group 2 |
| After Group 3 | Live Playwright | 56/0 | After Group 3 |
| After Group 4 | Live Playwright | 56/0 | After Group 4 |
| After Group 5 | Live Playwright | 56/0 | After Group 5 |
| After Group 6 step 6b | Live Playwright | 56/0 | After auth policies added, before public drop |
| After Group 6 step 6c | Live Playwright | 56/0 | After public drop |
| After Group 7 | Live Playwright | 56/0 | After dashboard_data conversion |
| Final anon-blocked SQL check | SQL editor | 0 rows | After all groups |
| Add AUTH-ANON-1 to e2e.js | — | — | After all SQL complete |
| Regression | `node test_regression.js` | 623/0 | Before push |
| Local Playwright | `node e2e.js` | 57/0 | Before push |
| Live Playwright | `HFOS_URL=https://dashboard.herndons.us node e2e.js` | 57/0 | After push |

**Tests that must remain green throughout:**
- AUTH-E2E-3: Valid login renders dashboard
- AUTH-E2E-6: Post-login calls use Bearer token distinct from anon key
- AUTH-E2E-7: All tables return data without 401 errors (authenticated)
- AUTH-E2E-8: app_users returns Adam row with active=true after login

---

## Manual Live Checklist

Run manually after all groups complete and Playwright passes:

- [ ] Load `https://dashboard.herndons.us` — login form appears, no errors
- [ ] Login as Adam — dashboard renders, no console errors, no 401/403s
- [ ] Weekly tab — data loads, reconciliation entries visible
- [ ] Save a note — persists after reload
- [ ] Toggle a task — state persists after reload
- [ ] Create or modify a custom task — saves correctly
- [ ] Save a reconciliation entry — data saves, UI updates
- [ ] Goals tab — goal registry loads, progress bars render
- [ ] Wishlist tab — items load, filter bar renders, Done grouping visible (Auth v1 group present)
- [ ] Update a Wishlist item status — persists
- [ ] Sign out Adam — login form returns, session cleared
- [ ] Sign in as Wendy — dashboard renders, data loads without errors, no 401/403s
- [ ] Confirm Wendy session has no console errors
- [ ] Sign out Wendy — login form returns cleanly
- [ ] Sign back in as Adam — dashboard renders correctly

---

## Code Changes

**e2e.js:**
- Add AUTH-ANON-1 test after all SQL complete, before push
- New Playwright baseline: 57/0

**No other app code changes.** Phase 4A is Supabase SQL only plus the anon-blocking integration test.

Not permitted in this build:
- Auth state machine changes
- `is_allowed_user()` or `public.is_allowed_user()` function body changes
- Financial model changes
- Wishlist UX changes
- Role enforcement
- `auth.uid()` migration
- CSP/CDN hardening

---

## Pre-Push / Post-Push Process

1. Run local Playwright baseline: 56/0
2. Execute SQL groups 1–7 in order, with live Playwright gate after each group (and between steps 6b and 6c)
3. Run final anon-blocked SQL verification: 0 rows expected
4. Complete manual live checklist including Wendy login
5. Add AUTH-ANON-1 to e2e.js
6. Run `node test_regression.js` → 623/0
7. Run `node e2e.js` locally → 57/0
8. Send pre-push report documenting per-group SQL results and all gate outcomes
9. Push
10. Run `HFOS_URL=https://dashboard.herndons.us node e2e.js` → 57/0
11. Do not begin Phase 4B (auth.uid migration) until Phase 4A is confirmed closed at live 57/0

---

## Guardrails

- No changes to `is_allowed_user()` function
- No Auth architecture changes
- No financial model changes
- No CSP or CDN hardening
- No role enforcement
- Do not push without pre-push report reviewed

---

## Acceptance Criteria

- [ ] All anon and public policies removed from all 11 public schema tables
- [ ] `custom_tasks` authenticated policies added before public policy dropped; custom task functionality confirmed working between steps 6b and 6c
- [ ] `dashboard_data` public policy converted to authenticated (legacy table retained, no app dependency assumed)
- [ ] Final anon-blocked SQL verification returns 0 rows
- [ ] AUTH-ANON-1 passes: anon SELECT returns 0 protected rows; anon INSERT to wishlist_items is blocked
- [ ] AUTH-E2E-3, AUTH-E2E-6, AUTH-E2E-7, AUTH-E2E-8 all pass throughout
- [ ] Regression: 623/0
- [ ] Playwright local: 57/0
- [ ] Playwright live: 57/0
- [ ] Manual checklist completed including Wendy sign-in and sign-out
- [ ] Pre-push report documents per-group SQL results, all Playwright gate outcomes, and anon-blocked verification result
- [ ] Phase 4B not started until this build is confirmed closed at live 57/0
