# Herndon Financial OS — Phase 4B: Migrate Authorization from Email to auth.uid()

**Version:** 1.0
**Date:** June 22, 2026
**Status:** CLOSED — June 22, 2026 — all gates passed at 57/0 live, 57/0 local, 623/0 regression
**Prior closed builds:** Auth v1 (0f98fb3), Wishlist v2 (6fdc7ea), Phase 4A (caece2c)
**Dependencies:** Phase 4B-0 (sign-out UX) and Phase 4D (lockout prevention) must be closed first

---

## Problem Statement

`public.is_allowed_user()` currently checks authorization using the JWT email field:

```sql
-- current (email-based)
lower(email) = lower(auth.jwt() ->> 'email')
AND active = true
```

Email is mutable. A Supabase Auth email change does not automatically update `app_users.email`, which would break authorization without any database error. `auth.uid()` returns an immutable UUID tied permanently to the Supabase Auth identity — the correct identifier for authorization.

This phase migrates `public.is_allowed_user()` to use `auth_user_id = auth.uid()`. All 11 RLS policies already call `public.is_allowed_user()` — no policy changes are needed, only the function body changes.

---

## Scope

**In scope:**
- Confirm whether `app_users.auth_user_id` column exists
- If missing: add `auth_user_id uuid` column (nullable — not enforced NOT NULL until populated)
- Populate Adam and Wendy `auth_user_id` values from Supabase Auth UUIDs (Phase 4D Step 2)
- Verify both values are non-null before changing the function
- Update `public.is_allowed_user()` to use `auth_user_id = auth.uid() AND active = true`
- Verify all 11 RLS policies still reference `public.is_allowed_user()` (no policy changes needed)
- Run full Playwright gate after function change, before push

**Out of scope:**
- No `auth_user_id NOT NULL` constraint — added separately once confirmed stable
- No role enforcement (Phase 4C)
- No RLS policy changes
- No new users
- No UI changes (beyond Phase 4B-0 which closes first)
- No financial model changes
- No Wishlist UX changes
- No CSP/CDN hardening

---

## Pre-Execution Requirements

Before any SQL in this spec runs:
1. Phase 4B-0 is closed at live 57/0
2. Phase 4D is complete — Adam and Wendy Supabase Auth UUIDs are known, `is_allowed_user()` current body is documented, rollback SQL is ready
3. Playwright baseline is 57/0 locally and live

---

## SQL Execution Plan

### Step 1 — Confirm auth_user_id column state

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'app_users'
ORDER BY ordinal_position;
```

**If `auth_user_id` exists:** proceed to Step 2.
**If missing:** run Step 1a before Step 2.

### Step 1a — Add auth_user_id column (only if missing)

```sql
ALTER TABLE public.app_users
ADD COLUMN auth_user_id uuid;
```

Nullable intentionally. Do not add NOT NULL constraint until both rows are confirmed populated.

### Step 2 — Populate auth_user_id for Adam and Wendy

UUIDs confirmed in Phase 4D. `auth_user_id` column already exists (nullable uuid — Step 1a skipped).

```sql
UPDATE public.app_users
SET auth_user_id = '9f6c9e09-209d-4533-8cd9-9143e8d570fc'
WHERE email = 'aherndon6@gmail.com';

UPDATE public.app_users
SET auth_user_id = 'f5d77d9c-bb8d-4f3b-9245-fb5832e85ff7'
WHERE email = 'wherndon22@gmail.com';
```

Note: Adam has two Supabase Auth accounts. Use the email login UUID above (`9f6c9e09-...`), NOT the Google OAuth UUID (`7c112cff-e60e-4cf1-a4c9-da3f06202206`).

### Step 3 — Verify both rows populated

```sql
SELECT email, role, active, auth_user_id
FROM public.app_users
ORDER BY created_at ASC;
```

Expected: 2 rows, both `active = true`, both `auth_user_id` non-null. Do not proceed if either is NULL.

### Step 4 — Verify current is_allowed_user() (pre-change confirmation)

```sql
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'is_allowed_user'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```

Confirm this matches the rollback target from Phase 4D. If it does not match, stop and reconcile before proceeding.

### Step 5 — Update is_allowed_user()

```sql
CREATE OR REPLACE FUNCTION public.is_allowed_user()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.app_users
    WHERE auth_user_id = auth.uid()
      AND active = true
  );
END;
$$;
```

Notes:
- `SECURITY DEFINER` is preserved — required for RLS policies to query `app_users`
- `SET search_path = public` is preserved — prevents search path injection
- No email check remains in the function body after this change
- All 11 RLS policies continue to call `public.is_allowed_user()` with no changes

### Step 6 — Verify function updated

```sql
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'is_allowed_user'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```

Confirm the function body now references `auth_user_id = auth.uid()` and contains no email reference.

### Step 7 — Verify RLS policies unchanged

```sql
SELECT tablename, policyname, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```

Expected: same 32 policies as Phase 4A final inventory, all `{authenticated}`, all referencing `is_allowed_user()`. No changes should appear.

---

## Rollback SQL

If Adam or Wendy login fails after Step 5:

```sql
-- Restore email-based is_allowed_user() (confirmed body from Phase 4D)
CREATE OR REPLACE FUNCTION public.is_allowed_user()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE lower(email) = lower(auth.jwt() ->> 'email')
      AND active = true
  );
$function$;
```

No RLS policy changes are needed to rollback — all 11 policies still call `public.is_allowed_user()`.
No column removal needed — `auth_user_id` column can remain; it does not affect the email-based function.

---

## e2e.js Changes

No new tests are required. Existing tests already cover the critical paths:

- AUTH-E2E-3: Valid login renders dashboard — confirms Adam's auth.uid path works post-change
- AUTH-E2E-7: All 9 tables return data without 401 errors — confirms RLS still passes for authenticated user
- AUTH-E2E-8: app_users returns Adam row with active=true — confirms app_users query still works
- AUTH-ANON-1: Anon SELECT returns 0 rows — confirms anon is still blocked

No regression test additions required unless a new behavioral assertion is identified during execution.

---

## Test Gates

| Gate | Command | Target | When |
|---|---|---|---|
| Pre-build baseline | `node e2e.js` | 57/0 | Before any SQL |
| After Step 5 (function update) | `HFOS_URL=https://dashboard.herndons.us node e2e.js` | 57/0 | Immediately after function change |
| Regression | `node test_regression.js` | 623/0 | Before push |
| Local Playwright | `node e2e.js` | 57/0 | Before push |
| Live Playwright | `HFOS_URL=https://dashboard.herndons.us node e2e.js` | 57/0 | After push |

Live Playwright is the critical gate. If it fails after the function update but before push, run rollback SQL immediately.

---

## Manual Checklist

After Step 5 (function update), before push:

- [ ] Load `https://dashboard.herndons.us` — login form appears
- [ ] Login as Adam — dashboard renders, no console errors, no 401/403s
- [ ] Weekly tab — data loads correctly
- [ ] Goals tab — goal registry loads
- [ ] Wishlist tab — items load
- [ ] Sign out — login form returns
- [ ] Sign in as Wendy (incognito) — dashboard renders, no errors
- [ ] Sign out Wendy — clean
- [ ] Re-login as Adam — dashboard correct

After push:
- [ ] Live Playwright 57/0
- [ ] All above manual steps repeat on live URL

---

## Acceptance Criteria

- [x] `app_users.auth_user_id` populated for Adam and Wendy (non-null)
- [x] `public.is_allowed_user()` uses `auth_user_id = auth.uid() AND active = true`
- [x] No email reference remains in the function body
- [x] All 32 RLS policies unchanged — still `{authenticated}` via `is_allowed_user()`
- [x] Adam login works post-change
- [x] Wendy login works post-change
- [x] AUTH-ANON-1 still passes (anon remains blocked)
- [x] AUTH-E2E-3, AUTH-E2E-7, AUTH-E2E-8 still pass
- [x] Regression 623/0, local Playwright 57/0, live Playwright 57/0
- [x] Rollback SQL exists and is documented
- [x] `auth_user_id NOT NULL` constraint deferred to a future build
- [x] Phase 4C not started until this build is confirmed closed at live 57/0

**Phase 4B STATUS: CLOSED — June 22, 2026**
**Prior closed builds:** Auth v1 (0f98fb3), Wishlist v2 (6fdc7ea), Phase 4A (caece2c), Phase 4B-0 (visible sign-out)
