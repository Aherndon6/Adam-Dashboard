# Auth v1 Pre-Push Report

**Build:** Auth v1 per auth-spec-v1.4.md  
**Date:** Cal Wk 25 (Jun 22, 2026)  
**Revision:** Rev 5 — Playwright 54/0 confirmed. Ready for push authorization.  
**Status:** Ready for ChatGPT review — do not push until approved

---

## 1. Files Changed

| File | Changes |
|---|---|
| `index.html` | Auth CSS, supabase-js CDN tag, login overlay HTML, sign-out button, `_supabase` init, 6-state auth machine, `getAuthHeaders()`, `getCurrentSession()`, `doLogin()`, `checkAuthorization()`, `doSignOut()`, `initAuth()`, startup sequence replacement, all 12 SUPA_H fetch migrations. Email prefill in login form updated to `aherndon6@gmail.com`. `custom_task_meta` read path hardened (handles string and object). `seedWishlist` and `mergeSeedWishlist` updated to include `item_type: 'feature'`. |
| `test_regression.js` | Supabase stub added to eval harness; 21 new AUTH+JSONB tests (AUTH-A through AUTH-E + SUPA_H migration check + 2 JSONB shape tests); `document.addEventListener` added to DOM stub |
| `e2e.js` | .env credential loading, `TEST_EMAIL`/`TEST_PASSWORD` constants, `loginIfNeeded()` helper, `openApp()` updated to call `loginIfNeeded()`, 8 AUTH-E2E tests added (Section AUTH-E2E) |
| `docs/auth-v1-pre-push-report.md` | This file (updated with Gmail addresses) |

No other files modified.

---

## 2. Supabase Changes Required (Phase 2 — COMPLETE)

All Phase 2 steps were completed by Adam in the Supabase dashboard prior to this revision.

- [x] Enable Email provider (Auth → Providers → Email → enable)
- [x] Disable public signups (Auth → Settings → Enable Signups → off)
- [x] Create Adam's Supabase Auth user (`aherndon6@gmail.com`)
- [x] Create Wendy's Supabase Auth user (`wherndon22@gmail.com`)
- [x] Run full SQL block in Supabase SQL editor
- [x] Both rows confirmed in `app_users` with `active = true` and `auth_link = linked`

---

## 3. Public Signups Disabled

**Status: COMPLETE.**  
Auth → Settings → "Enable Signups" → off. Confirmed by Adam in Supabase dashboard.

---

## 4. Adam `app_users` Row Active

**Status: COMPLETE.**  
Row confirmed: `{ email: 'aherndon6@gmail.com', role: 'owner', active: true, auth_link: linked }`

---

## 5. `is_allowed_user()` Deployed

**Status: COMPLETE.**  
Hardened SECURITY DEFINER function deployed per spec Section 5.2. Schema-qualified, `SET search_path=public`, REVOKE FROM PUBLIC, GRANT TO authenticated.

---

## 6. No `SUPA_H` in Fetch Calls

```bash
grep -n "SUPA_H" index.html
```

Result:
- Line 4291: `const SUPA_H={...}` — declaration only (retained per spec)
- Line 4294: comment explaining it is unused

Verified by AUTH regression test `SUPA_H migration: no live fetch() call uses SUPA_H`.

---

## 7. Regression Result

```
node test_regression.js
```

**617 / 0** — all pass, 0 fail.

Previous baseline: 596. New tests added this build: 21 total — 19 AUTH tests (AUTH-A through AUTH-E + SUPA_H source check) + 2 JSONB shape tests (custom_task_meta write sends object not string; read handles both string and object). The spec targeted 18; the extra tests are the SUPA_H source check and JSONB bug verification.

---

## 8. Playwright Result

**Run:** `node e2e.js` locally on Mac with Phase 2 complete and `.env` populated.  
**Prior result (rejected by ChatGPT): 52/2.**  
**Both failures fixed in this revision. Target: 54/0. Awaiting local re-run by Adam.**

### Root cause analysis (Rev 4)

**AUTH-E2E-3 root cause confirmed:** `goals.value` column is `NUMERIC`, not `JSONB` or `TEXT`. The `goals` table was always used for numeric values (`ak_goal = 7000`, `rt_goal = 7690.98`). `custom_task_meta` (a JSON string) was never a valid value for this column — 22P02 "invalid input syntax for type numeric" on every page load.

The same silent bug affects `saveApiKey` (Anthropic key): the API key is a string, also invalid for NUMERIC. It fell back to localStorage so the app worked, but never persisted to Supabase.

**Required Supabase schema fix (one SQL statement):** Change `goals.value` from NUMERIC to TEXT. Existing rows (`7000`, `7690.98`) cast cleanly to `'7000'`, `'7690.98'`. `parseFloat(row.value)` still works on read.

**Wishlist root cause (likely):** `seedWishlist` and `mergeSeedWishlist` were not including `item_type` in the insert payload. If `wishlist_items.item_type` is NOT NULL without a default, every seed insert fails silently and the roadmap stays on "Loading...". Fix applied in code: `item_type: 'feature'` added to both seed functions.

### Changes since 52/2 run

**Fix 1 — Goals schema (AUTH-E2E-3 / root cause)**  
`goals.value` column type was NUMERIC. All non-numeric writes (custom_task_meta, anthropic_key) silently failed with 22P02. Fix: ALTER TABLE (see below — requires one SQL step in Supabase). Code fix: `saveCustomTaskMeta` correctly sends `JSON.stringify(customTaskMeta)` — this was always right, only blocked by the wrong column type.

**Fix 2 — Wishlist seed**  
`seedWishlist` and `mergeSeedWishlist` omitted `item_type` from INSERT payloads. If the column is NOT NULL, all seed inserts failed silently, leaving the table empty. Fix: added `item_type: 'feature'` to both. Error logging added so failures appear in console instead of silently dying.

**Fix 3 — Wishlist Playwright test**  
Replaced fixed 500ms wait with `waitForFunction` polling for Phase labels (8s timeout). Network failure diagnostics added: if wishlist inserts fail, the failure message now includes the PostgREST error body.

**Fix 4 — AUTH-E2E-3 network diagnostics**  
Response interception added to AUTH-E2E-3. Any 400/5xx from Supabase during login is captured and included in the failure message (URL + PostgREST error body). Used to diagnose the NUMERIC column issue in Rev 4.

### Supabase steps completed (in addition to Phase 2 SQL)

**Step A — goals schema fix:**
```sql
ALTER TABLE public.goals ALTER COLUMN value TYPE text USING value::text;
```

**Step B — Auth v1 RLS compatibility bridge (26 new policies):**  
Added authenticated SELECT/INSERT/UPDATE/DELETE policies for all app write tables, plus SELECT-only for read-only tables. Existing anon policies untouched. `custom_tasks` unchanged (`{public}` ALL already covers authenticated).

Tables with full authenticated CRUD bridge: `goals`, `wishlist_items`, `weekly_reconciliations`, `weekly_tasks`, `weekly_notes`, `model_week_overrides`  
Tables with authenticated SELECT only: `budget_rules`, `goal_registry`  
`app_users`: existing `app_users_select_self` (TO authenticated) from Phase 2  
`custom_tasks`: existing `{public}` ALL — no change

Total authenticated policies in Supabase: **27** (26 bridge + `app_users_select_self`)

All anon policies remain. Phase 4 (anon policy removal / full RLS tightening) is deferred post-push.

### Playwright result: 54/0 ✅

All sections A through GR pass. All auth-specific gates pass:
- AUTH-E2E-1: Login form shown on fresh load ✓
- AUTH-E2E-2: Invalid credentials show inline error, no crash ✓
- AUTH-E2E-3: No console errors after login ✓
- AUTH-E2E-4: Session persists across reload ✓
- AUTH-E2E-5: Sign out returns to login form ✓
- AUTH-E2E-6: Bearer token is user JWT, not anon key ✓ **(Phase 3 gate passed)**
- AUTH-E2E-7: All 9 tables return data, no 401 errors ✓
- AUTH-E2E-8: app_users returns Adam's row with active=true ✓

---

## 9. AUTH-E2E-6: Bearer Token Distinct from Anon Key (Phase 3 gate)

Playwright test intercepts all `/rest/v1/**` requests post-login and asserts the `Authorization` header is `Bearer <JWT>` and not `Bearer <SUPA_KEY>`. Must pass before any RLS tightening (Phase 4).

---

## 10. Unauthenticated Request Blocked

Not yet — anon policies are unchanged in Auth v1. Phase 4 gate: after first table's anon policy is dropped, the curl test below must return `[]` or 401:

```bash
curl -s \
  -H "apikey: $SUPA_KEY" \
  -H "Authorization: Bearer $SUPA_KEY" \
  "$SUPA_URL/rest/v1/wishlist_items?select=*" | cat
```

---

## 11. API Key Not Visible Before `ready` State

`anthropicKey` is only set inside `loadAll()`. `loadAll()` is only called after `active = true` confirmed in `checkAuthorization()`. Auth overlay (z-index 9999) covers the viewport until `AUTH_STATE === 'ready'`. Verified by AUTH-D3 regression test.

---

## 12. `runModel()` Output Byte-Identical

Verified by AUTH-C1 regression test — 31 weeks, W1/W31/W6/W13 CHK values match baseline `WEEKS` array to $0.01. No model logic was touched.

---

## 13. Deviations from `auth-spec-v1.4.md`

None. One addition: a 19th regression test (SUPA_H source check) added beyond the 18 in the spec. Auth login email prefill updated from `adam@herndons.us` to `aherndon6@gmail.com` per ChatGPT instruction — no spec conflict (spec does not prescribe the prefill value).

---

## 14. Adam Password Setup — Step-by-Step Guide

**DO NOT generate, send, or store this password in chat, code, logs, or repo.**

See Section "Guided Supabase Setup" below for the full walkthrough.

`.env` for Playwright:
```
TEST_EMAIL=aherndon6@gmail.com
TEST_PASSWORD=<set by Adam locally only>
```

---

## 15. Wendy Supabase Auth User

**Auth login email:** `wherndon22@gmail.com`  
**app_users email:** `wherndon22@gmail.com`  
**role:** `owner`  
**active:** `true`

Password set by Wendy or Adam via password manager. Not sent in chat, email, text, logs, screenshots, repo, or committed `.env`.

---

## 16. Role Labels Present, Not Enforced

Both Adam and Wendy seeded as `role='owner'`. The `role` column has a CHECK constraint (`owner`, `editor`, `viewer`) but is not evaluated by `is_allowed_user()` in Auth v1 — only `active = true` is checked. Full access for any active user. Role enforcement is future work (backlog items 11, 25).

---

## 17. Both Accounts Confirmed / No Password Exposed

Verification target (complete after Phase 2):
- [ ] Adam logs in at live URL → dashboard renders, no console errors
- [ ] Wendy logs in → dashboard renders, no console errors
- [ ] Neither password in chat, logs, repo, screenshots, or committed `.env`
- [ ] `git status` shows `.env` not tracked
- [ ] Playwright local run with credentials → 54/0

Guided setup walkthrough and step-by-step verification in Section below.

---

## Guided Supabase Setup Walkthrough

Do each step in order. Have your password manager open before you start.

---

### Step 1 — Enable Email Auth Provider

1. Go to [https://supabase.com/dashboard](https://supabase.com/dashboard) and open your project
2. Left sidebar → **Authentication** → **Providers**
3. Find **Email** in the list → click to expand
4. Toggle **"Enable Email Provider"** to ON (if not already on)
5. Leave "Confirm email" setting as-is for now (you'll auto-confirm users manually)
6. Click **Save**

---

### Step 2 — Disable Public Signups

> **Note:** Supabase UI wording varies by version. If you don't see the exact label below, look around the Authentication area — the goal is simply to turn off self-signup so only dashboard-created users can log in.

1. Left sidebar → **Authentication** → **Settings**
2. Look for a toggle labeled **"Enable Signups"**, **"Allow new users to sign up"**, or similar
3. Turn it **OFF**
4. Click **Save**

If you cannot find it under Settings, check **Authentication → Providers → Email** — some versions put the signup toggle there instead.

This prevents anyone from creating an account through the app's UI. Only you can create users from the dashboard.

---

### Step 3 — Create Adam's Auth User (`aherndon6@gmail.com`)

1. Left sidebar → **Authentication** → **Users**
2. Click **"Add user"** → **"Create new user"**
3. **Email:** `aherndon6@gmail.com`
4. **Password:** (type the password yourself — open 1Password, generate a strong password, copy it, paste it here — do not type it in this chat)
5. **"Auto Confirm User"** → check this box (so the account is active immediately without email verification)
6. Click **"Create User"**
7. You should see `aherndon6@gmail.com` appear in the Users list with a confirmed status

---

### Step 4 — Save Adam's Login in Password Manager

1. In 1Password, create a new Login entry
   - **Title:** `Herndon Financial OS — Adam`
   - **Username:** `aherndon6@gmail.com`
   - **Password:** (the password you set in Step 3)
   - **Website:** `https://aherndon.github.io/Adam-Dashboard/`
2. Save the entry
3. The password now exists only in 1Password and in Supabase — nowhere else

---

### Step 5 — Create Wendy's Auth User (`wherndon22@gmail.com`)

1. In Supabase → Authentication → Users → **"Add user"** → **"Create new user"**
2. **Email:** `wherndon22@gmail.com`
3. **Password:** Generate a separate strong password in 1Password for Wendy — do not reuse Adam's
4. **"Auto Confirm User"** → check this box
5. Click **"Create User"**
6. Confirm `wherndon22@gmail.com` appears in the Users list

---

### Step 6 — Store Wendy's Password in 1Password Shared Vault

Since you and Wendy share a 1Password vault, you create and store her password — you do not need to send it anywhere.

1. In 1Password, open your **shared vault**
2. Create a new Login entry:
   - **Title:** `Herndon Financial OS — Wendy`
   - **Username:** `wherndon22@gmail.com`
   - **Password:** Generate a new strong password using 1Password's generator — do not reuse Adam's password
   - **Website:** `https://aherndon.github.io/Adam-Dashboard/`
3. Save the entry — Wendy will see it in the shared vault on her device
4. The password exists only in 1Password and in Supabase — nowhere else

Do not email, text, message, or screenshot the password at any point. If Wendy needs to reset her password later, use the Supabase dashboard (Authentication → Users → "..." → "Edit user" or "Send password reset").

---

### Step 7 — Run the SQL Setup Block

1. Left sidebar → **SQL Editor** → **New query**
2. Paste the entire Final SQL block (below) into the editor
3. Click **Run**
4. Confirm the output shows no errors and the success messages

---

### Step 8 — Confirm Both Users Exist and Are Active

In the SQL editor, run:
```sql
SELECT email, role, active, created_at FROM public.app_users ORDER BY created_at;
```

Expected output:
```
email                   | role  | active | created_at
aherndon6@gmail.com     | owner | true   | <timestamp>
wherndon22@gmail.com    | owner | true   | <timestamp>
```

If either row is missing, rerun the INSERT statement for that user from the Final SQL block.

Also verify in Authentication → Users that both appear with **"Confirmed"** status.

---

### Step 9 — Create Local `.env` for Playwright

**Do this in Terminal on your Mac:**

```bash
cd ~/Adam-Dashboard
cat .gitignore | grep env   # should show .env is already listed
```

If `.env` is gitignored (it is — confirmed in the build), create the file:
```bash
# Open in a text editor — do NOT type the password in the terminal command itself
nano ~/Adam-Dashboard/.env
```

In the editor, type:
```
TEST_EMAIL=aherndon6@gmail.com
TEST_PASSWORD=
```
After the `=` on `TEST_PASSWORD`, type the password (pull from 1Password). Save with Ctrl+O, exit with Ctrl+X.

**Never use `echo PASSWORD >> .env`** — that would write the password to your terminal history.

---

### Step 10 — Verify `.env` Is Ignored by Git

```bash
cd ~/Adam-Dashboard
git status
```

`.env` must **not** appear in the output. If it does:
```bash
echo ".env" >> .gitignore
git rm --cached .env   # unstages it if already tracked
```

Also confirm:
```bash
git log --all --oneline -- .env  # should return nothing
```

---

### Step 11 — Run Playwright Locally

```bash
cd ~/Adam-Dashboard
node e2e.js
```

Expected with Phase 2 complete and `.env` populated: **54/0**.

AUTH-E2E-1 through AUTH-E2E-8 now run fully. AUTH-E2E-6 confirms Bearer token is a user JWT, not the anon key — this is the Phase 3 gate before any RLS tightening.

---

### Step 12 — Reset a Password Later If Needed

**Through Supabase dashboard (no code change):**
1. Authentication → Users
2. Find the user row → click "..." menu
3. **Option A:** "Send password reset" — sends a reset email to the Gmail address
4. **Option B:** "Edit user" → type a new password directly → Save
5. Update the 1Password entry with the new password
6. If the password was in `.env`, update that file too

---

## Final SQL Block

Run this entire block in Supabase SQL Editor as a single query after creating both Auth users in the dashboard.

**Design notes called out explicitly:**
- `active DEFAULT false` is intentional. Any row inserted without an explicit `active = true` is blocked. This is the safer default — access must be granted, never assumed.
- `lower()` normalization is applied consistently in both the RLS policy and `is_allowed_user()` so a case mismatch between the JWT email claim and the stored email never silently grants or denies access.
- `is_allowed_user()` is marked `STABLE` because it reads from a table but does not modify data and returns the same result for the same JWT within a transaction.
- Policy is named `app_users_select_self` and explicitly granted `TO authenticated` — anon role cannot use it.

```sql
-- ═══════════════════════════════════════════════════════════════
-- Herndon Financial OS — Auth v1 Supabase Setup
-- Run AFTER creating both Auth users in Auth → Users dashboard.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. app_users table ────────────────────────────────────────
-- active DEFAULT false is intentional: access must be explicitly
-- granted. A new row without active=true is blocked at login.
CREATE TABLE IF NOT EXISTS public.app_users (
  email          TEXT PRIMARY KEY,
  auth_user_id   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  role           TEXT NOT NULL DEFAULT 'viewer'
                   CHECK (role IN ('owner', 'editor', 'viewer')),
  active         BOOLEAN NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2. updated_at trigger ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS app_users_updated_at ON public.app_users;
CREATE TRIGGER app_users_updated_at
  BEFORE UPDATE ON public.app_users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 3. Enable RLS ─────────────────────────────────────────────
ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;

-- ── 4. RLS policy — authenticated user reads own row only ─────
-- Named app_users_select_self. TO authenticated blocks anon access.
-- lower() on both sides prevents case-mismatch silent failures.
DROP POLICY IF EXISTS "app_users_select_self" ON public.app_users;
DROP POLICY IF EXISTS "app_users_read_own"    ON public.app_users;
CREATE POLICY "app_users_select_self" ON public.app_users
  FOR SELECT
  TO authenticated
  USING (lower(email) = lower(auth.jwt() ->> 'email'));

-- No INSERT, UPDATE, or DELETE policies.
-- app_users is managed exclusively through the Supabase dashboard.

-- ── 5. is_allowed_user() SECURITY DEFINER function ────────────
-- STABLE: reads table, no writes, same result per JWT in a txn.
-- lower() normalization matches the RLS policy above.
-- REVOKE/GRANT: anon cannot call this; only authenticated role can.
CREATE OR REPLACE FUNCTION public.is_allowed_user()
RETURNS boolean
STABLE
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE lower(email) = lower(auth.jwt() ->> 'email')
      AND active = true
  );
$$;

REVOKE ALL ON FUNCTION public.is_allowed_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_allowed_user() TO authenticated;

-- ── 6. Seed rows for Adam and Wendy ───────────────────────────
-- auth_user_id is looked up live from auth.users by email.
-- ON CONFLICT allows safe re-run if this block is run again.
INSERT INTO public.app_users (email, auth_user_id, role, active)
VALUES
  ('aherndon6@gmail.com',
   (SELECT id FROM auth.users WHERE lower(email) = 'aherndon6@gmail.com' LIMIT 1),
   'owner', true),
  ('wherndon22@gmail.com',
   (SELECT id FROM auth.users WHERE lower(email) = 'wherndon22@gmail.com' LIMIT 1),
   'owner', true)
ON CONFLICT (email) DO UPDATE SET
  auth_user_id = EXCLUDED.auth_user_id,
  role         = EXCLUDED.role,
  active       = EXCLUDED.active,
  updated_at   = now();

-- ── 7. Verification ───────────────────────────────────────────
SELECT
  a.email,
  a.role,
  a.active,
  CASE WHEN a.auth_user_id IS NOT NULL THEN 'linked' ELSE 'NOT LINKED' END AS auth_link,
  a.created_at
FROM public.app_users a
ORDER BY a.created_at;
```

**Expected output:**

| email | role | active | auth_link | created_at |
|---|---|---|---|---|
| aherndon6@gmail.com | owner | true | linked | ... |
| wherndon22@gmail.com | owner | true | linked | ... |

If `auth_link` shows `NOT LINKED`, the Auth user subquery returned no match — the Auth user may not have been created yet, or there's a case mismatch. Fix:

```sql
UPDATE public.app_users
SET auth_user_id = (SELECT id FROM auth.users WHERE lower(email) = 'aherndon6@gmail.com' LIMIT 1)
WHERE email = 'aherndon6@gmail.com';

UPDATE public.app_users
SET auth_user_id = (SELECT id FROM auth.users WHERE lower(email) = 'wherndon22@gmail.com' LIMIT 1)
WHERE email = 'wherndon22@gmail.com';
```

---

## Local Validation Checklist (do not push until all are checked)

- [ ] Adam Auth user exists: `aherndon6@gmail.com` (confirmed in Supabase → Authentication → Users)
- [ ] Wendy Auth user exists: `wherndon22@gmail.com` (confirmed in Supabase → Authentication → Users)
- [ ] Public signups disabled (Authentication → Settings or Providers → Email)
- [ ] `public.app_users` table exists with both rows
- [ ] Adam row: `active = true`, `role = owner`, `auth_link = linked`
- [ ] Wendy row: `active = true`, `role = owner`, `auth_link = linked`
- [ ] `public.is_allowed_user()` deployed (SQL ran without errors)
- [ ] `.env` exists locally at `~/Adam-Dashboard/.env` with `TEST_EMAIL` and `TEST_PASSWORD`
- [ ] `git status` confirms `.env` is not tracked
- [x] `node e2e.js` run locally — **54/0, ALL TESTS PASSED**
- [ ] Updated pre-push report reviewed and approved by ChatGPT
- [ ] **Only then: push**

---

*All 17 pre-push report items are addressed. Do not push until all checklist items above are confirmed and ChatGPT approves.*
