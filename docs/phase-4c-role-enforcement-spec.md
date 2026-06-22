# Herndon Financial OS — Phase 4C: Role Enforcement

**Version:** 1.0
**Date:** June 22, 2026
**Status:** Spec only — do not build until Phase 4B is live and stable at 57/0
**Prior closed builds:** Auth v1 (0f98fb3), Wishlist v2 (6fdc7ea), Phase 4A (caece2c)
**Dependencies:** Phase 4B-0, Phase 4D, Phase 4B all closed first

---

## Problem Statement

After Phase 4B, `public.is_allowed_user()` will authorize by `auth_user_id = auth.uid() AND active = true`. This is correct but binary: any active user in `app_users` has the same access as Adam. `app_users.role` was added in Auth v1 and is seeded, but it is not yet checked.

Before giving Wendy meaningful access beyond read-only, or before adding any CPA/advisor user, role enforcement needs to be in place. Without it, any user added to `app_users` with `active = true` gets full write access to all financial data.

---

## Role Matrix

| Role | Read all tables | Operational writes | Config/model writes | Admin (app_users mgmt) |
|---|---|---|---|---|
| `owner` | yes | yes | yes | yes |
| `editor` | yes | yes | no | no |
| `viewer` | yes | no | no | no |

**Definitions:**

- Operational writes: weekly_reconciliations INSERT/UPDATE/DELETE, weekly_tasks PATCH, weekly_notes INSERT/UPDATE, custom_tasks INSERT/UPDATE/DELETE, goals INSERT/UPDATE (key-value operational entries), wishlist_items all writes
- Config/model writes: model_week_overrides INSERT/UPDATE/DELETE, goals writes for model-affecting keys (e.g., `anthropic_key`, `ira_flag`, goal registry entries), budget_rules (currently read-only for all users)
- Admin: changes to `app_users` rows, role or active flag changes — managed via Supabase dashboard only, not in-app

**User assignments (post-Phase 4D decision):**

| User | Role |
|---|---|
| Adam | `owner` |
| Wendy | `editor` (recommended — operational but not model-config) |
| CPA/advisor | `viewer` — deferred, do not add until after Phase 4C is stable |

---

## Scope

**In scope:**
- Create `public.is_editor_or_owner()` and `public.is_owner()` helper functions (SECURITY DEFINER, same pattern as `is_allowed_user()`)
- Update RLS policies for write-protected tables to use `is_editor_or_owner()` or `is_owner()` instead of `is_allowed_user()` where role distinction matters
- Add UI suppression for non-owner actions (disable or hide model-config controls for viewer/editor roles)
- Confirm Adam owner writes still work
- Confirm Wendy editor reads and operational writes work
- Confirm Wendy editor cannot write model_week_overrides or model-config goals keys
- Update Playwright to gate role-specific behavior where meaningful

**Out of scope:**
- No in-app user management UI
- No CPA/advisor onboarding
- No financial model changes
- No Goal Registry CRUD
- No Wishlist UX changes
- No new `app_users` rows

---

## Proposed Helper Functions

```sql
-- Allows any active user (existing behavior — used for reads)
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

-- Allows editor or owner (operational writes)
CREATE OR REPLACE FUNCTION public.is_editor_or_owner()
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
      AND role IN ('editor', 'owner')
  );
END;
$$;

-- Allows owner only (config/model writes)
CREATE OR REPLACE FUNCTION public.is_owner()
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
      AND role = 'owner'
  );
END;
$$;
```

---

## RLS Policy Changes

All SELECT policies remain `is_allowed_user()` — all active users read everything.

Write policy changes by table:

| Table | Current write policy | Phase 4C write policy |
|---|---|---|
| `weekly_reconciliations` | `is_allowed_user()` | `is_editor_or_owner()` |
| `weekly_tasks` | `is_allowed_user()` | `is_editor_or_owner()` |
| `weekly_notes` | `is_allowed_user()` | `is_editor_or_owner()` |
| `custom_tasks` | `is_allowed_user()` | `is_editor_or_owner()` |
| `wishlist_items` | `is_allowed_user()` | `is_editor_or_owner()` |
| `goals` | `is_allowed_user()` | Split — see below |
| `model_week_overrides` | `is_allowed_user()` | `is_owner()` |

**goals split:** Goals keys are mixed — some are operational (task completion amounts), some are model-config (IRA flag, Anthropic key, goal registry entries). Splitting at the RLS level by key is not practical with PostgREST. Options:
1. Apply `is_owner()` to all goals writes — Wendy cannot write any goal key. Safest, simplest.
2. Keep `is_editor_or_owner()` for goals writes and suppress in UI only for config keys.
3. Accept that editor can write all goals keys for now and address in a later build.

**Recommendation for Phase 4C:** Apply `is_owner()` to goals writes and `model_week_overrides` writes. Apply `is_editor_or_owner()` to operational tables. Document this decision. Revisit if Wendy operational use requires goal key writes.

---

## UI Suppression

For non-owner users, disable or hide controls that trigger owner-only writes. This is a UX layer on top of RLS enforcement — RLS is the real gate.

Controls to suppress for non-owner:
- Model week override edit panel (used by `saveOverride`, `deleteOverride`)
- IRA flag toggle in Goals tab
- Anthropic API key field
- Any budget rules configuration (currently no UI exists)
- Goal Registry configuration (no UI yet)

Controls available to editor:
- All weekly reconciliation inputs
- Task checkboxes
- Weekly notes
- Custom task creation / deletion
- Wishlist item CRUD

Implementation: after login, read `app_users.role` for the current user and set a JS global `USER_ROLE`. Check `USER_ROLE` in UI render functions to disable/hide owner-only controls.

```javascript
// Add after loadAll() completes
var _roleRow = await (await fetch(SUPA_URL+'/rest/v1/app_users?auth_user_id=eq.'+encodeURIComponent(authUid)+'&select=role&limit=1', {headers:h})).json();
var USER_ROLE = _roleRow && _roleRow[0] ? _roleRow[0].role : 'viewer';
```

Note: this query requires updating app_users SELECT policy USING clause to allow users to read their own row by auth_user_id — or querying via the existing `app_users_select_self` policy (which uses email). Exact implementation to be determined during build.

---

## Rollback Plan

Rollback: restore all write policies to `is_allowed_user()` and drop `is_editor_or_owner()` and `is_owner()` functions.

```sql
-- Restore all write policies to is_allowed_user()
-- (full SQL to be written during build, after exact policy names are confirmed)

DROP FUNCTION IF EXISTS public.is_editor_or_owner();
DROP FUNCTION IF EXISTS public.is_owner();
```

No function changes to `is_allowed_user()` are needed for rollback — it is not changed in Phase 4C.

---

## Open Questions Before Build

1. **Wendy's role decision** — must be confirmed in Phase 4D before 4C build starts.
2. **goals write policy** — `is_owner()` vs `is_editor_or_owner()`. Recommend `is_owner()` for safety.
3. **app_users SELECT policy update** — current policy uses email-based USING clause. After Phase 4B, it uses auth.uid. Confirm this is already handled before adding UI role fetch.
4. **UI suppression approach** — inline JS flag vs. CSS class on body vs. per-component check. Decide during build spec revision.

---

## Test Gates

| Gate | Target |
|---|---|
| Pre-build baseline (post-4B) | 57/0 live |
| After function and policy changes | Live Playwright 57/0 |
| Adam owner write: model override | passes |
| Adam owner write: goals | passes |
| Wendy editor write: weekly data | passes |
| Wendy editor write: model override | fails (RLS blocks) |
| Wendy editor write: goals (if is_owner()) | fails (RLS blocks) |
| AUTH-ANON-1 | still passes |
| Regression | 623/0 (plus any new 4C tests) |

---

## Manual Checklist

- [ ] Adam (owner) — full write on all tables, model overrides, goals, wishlist
- [ ] Wendy (editor) — can toggle tasks, save reconciliation, write notes, write wishlist
- [ ] Wendy (editor) — cannot write model_week_overrides (REST returns 403)
- [ ] Wendy (editor) — owner-only controls are hidden or disabled in UI
- [ ] No console errors for either user
- [ ] Sign-out and re-login for both users clean

---

## Acceptance Criteria

- [ ] `is_editor_or_owner()` and `is_owner()` functions created with correct role checks
- [ ] Write policies on model_week_overrides use `is_owner()`
- [ ] Write policies on operational tables use `is_editor_or_owner()`
- [ ] SELECT policies unchanged — all active users read all tables
- [ ] UI suppresses owner-only controls for non-owner sessions
- [ ] Adam owner path: all writes work
- [ ] Wendy editor path: operational writes work, model-config writes blocked
- [ ] AUTH-ANON-1 still passes
- [ ] Regression and live Playwright clean
- [ ] Rollback SQL exists
- [ ] No in-app user management, no new users, no CPA/advisor onboarding
