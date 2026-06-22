# Herndon Financial OS — Phase 4D: Backup Owner / Lockout Prevention

**Version:** 1.0
**Date:** June 22, 2026
**Status:** Awaiting approval — validation/documentation only, no app behavior changes
**Prior closed builds:** Auth v1 (0f98fb3), Wishlist v2 (6fdc7ea), Phase 4A (caece2c)

---

## Problem Statement

Phase 4B will change `public.is_allowed_user()` from email-based authorization to `auth.uid()`-based authorization. A bad function change — or a missing `auth_user_id` on either user row — could lock both Adam and Wendy out of the dashboard with no in-app recovery path. Before Phase 4B executes, the following must be true:

1. Adam and Wendy's `app_users` rows are confirmed with active=true
2. The current `is_allowed_user()` function body is documented with rollback SQL ready
3. Manual recovery path via Supabase dashboard is documented
4. Wendy's intended role is decided (even if not enforced until Phase 4C)

This phase makes no code or SQL changes to the running app.

---

## Scope

**In scope:**
- Run SQL inventory queries against `app_users`
- Confirm Adam and Wendy rows (email, role, active)
- Retrieve current `is_allowed_user()` function body from Supabase
- Write rollback SQL to restore email-based function if Phase 4B goes wrong
- Document Supabase dashboard recovery steps
- Decide Wendy's role for Phase 4C planning purposes

**Out of scope:**
- No role enforcement
- No auth.uid migration (that is Phase 4B)
- No UI changes
- No new users
- No financial model changes
- No RLS changes

---

## Step 1 — app_users Inventory

Run in Supabase SQL editor:

```sql
SELECT id, email, role, active, created_at
FROM public.app_users
ORDER BY created_at ASC;
```

Expected: 2 rows — Adam and Wendy, both `active = true`.

Also confirm `auth_user_id` column state (needed for Phase 4B planning):

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'app_users'
ORDER BY ordinal_position;
```

This tells us: does `auth_user_id` exist, and if so, is it populated or NULL?

---

## Step 2 — Supabase Auth User Inventory

In Supabase dashboard: Authentication → Users

Locate Adam and Wendy by email. For each, record:
- `id` (UUID — this is the `auth.uid()` value for that user)
- `email`
- `last_sign_in_at`
- `confirmed_at` (must be non-null for login to work)

These UUIDs are what Phase 4B will populate into `app_users.auth_user_id`.

---

## Step 3 — Retrieve Current is_allowed_user() Function

Run in Supabase SQL editor:

```sql
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'is_allowed_user'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
```

Paste the full output. This is the rollback target if Phase 4B breaks authorization.

---

## Step 4 — Rollback SQL

Confirmed function body (retrieved June 22, 2026 via `prosrc`). LANGUAGE sql, email-based:

```sql
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

This rollback restores the email-based function without touching any RLS policies, since all 11 tables already point to `public.is_allowed_user()`.

Rollback trigger conditions:
- Phase 4B function update causes Adam or Wendy login to fail
- AUTH-E2E-3, AUTH-E2E-7, or AUTH-E2E-8 fail after Phase 4B
- `HFOS_URL` live Playwright fails after Phase 4B push

---

## Step 5 — Manual Recovery via Supabase Dashboard

If the app is locked out and rollback SQL cannot be reached through the app:

1. Go to https://supabase.com → sign in as Adam (Supabase account)
2. Open the TAH Personal project → SQL Editor
3. Paste and run the rollback SQL from Step 4
4. Verify: `SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'is_allowed_user'...` returns the email-based function
5. Reload the live dashboard — login should work immediately (no deploy needed, function is server-side)

No code push is required to recover. The function change is purely in Supabase.

---

## Step 6 — Wendy's Role Decision

This is for Phase 4C planning. No enforcement happens in Phase 4B.

Proposed role matrix (Phase 4C will enforce):

| Role | Read | Operational Write | Admin/Config Write |
|---|---|---|---|
| owner | all tables | yes | yes |
| editor | all tables | yes | no |
| viewer | all tables | no | no |

Adam's intended role: **owner**
Wendy's intended role: **[TBD — decide before Phase 4C spec is finalized]**

Options for Wendy:
- `owner` — full access, same as Adam. Simple for a two-person household.
- `editor` — can read everything, can toggle tasks/write operational data, cannot change model or config.
- `viewer` — read-only. Suitable if Wendy should see but not write.

Recommendation: **editor** for Wendy. She should be able to use the dashboard operationally but not change model parameters or goal configuration. This distinction matters once Phase 4C enforces role checks.

---

## Lockout Prevention Checklist

Before Phase 4B executes:

- [x] Step 1 run — Adam row confirmed: aherndon6@gmail.com, active=true, role=owner
- [x] Step 1 run — Wendy row confirmed: wherndon22@gmail.com, active=true, role=owner
- [x] Step 2 run — Adam Supabase Auth UUID: `9f6c9e09-209d-4533-8cd9-9143e8d570fc` (email login)
- [x] Step 2 run — Wendy Supabase Auth UUID: `f5d77d9c-bb8d-4f3b-9245-fb5832e85ff7`
- [x] Step 3 run — current `is_allowed_user()` body retrieved and documented (LANGUAGE sql, email-based)
- [x] Rollback SQL written and saved (see Step 4 above)
- [x] Manual recovery path documented and understood (Step 5)
- [x] Wendy's role noted: currently `owner` in DB; Phase 4C spec recommends `editor` — decision deferred to Phase 4C build
- [x] At least one active owner (Adam) confirmed before Phase 4B starts

**Note:** Adam has two Supabase Auth accounts — Google OAuth (`adam@herndons.us`, `7c112cff-...`) and email (`aherndon6@gmail.com`, `9f6c9e09-...`). The app uses the email login account. Phase 4B populates `auth_user_id` with the email login UUID only.

---

## Acceptance Criteria

- [x] `app_users` inventory query returns Adam and Wendy rows, both active=true
- [x] Supabase Auth user UUIDs recorded for both users
- [x] `is_allowed_user()` current function body documented
- [x] Rollback SQL written and saved
- [x] Supabase dashboard recovery path documented
- [x] Wendy's role noted (currently `owner`; Phase 4C will decide if it changes to `editor`)
- [x] No app behavior changes in this phase
- [x] Phase 4B does not begin until this checklist is complete

**Phase 4D STATUS: CLOSED — June 22, 2026**
