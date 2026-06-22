# Herndon Financial OS — Wishlist Tab v2 Spec

**Version:** 1.2  
**Date:** Cal Wk 25 (Jun 22, 2026)  
**Status:** Build authorized (ChatGPT, v1.1 → v1.2 clarifications accepted)  
**Prior reviews:** v1.0 → v1.1 (9 changes); v1.1 → v1.2 (6 clarifications)  
**Related:** docs/auth-v1-pre-push-report.md (Auth v1 — closed), docs/security-brittleness-backlog.md  

---

## Problem Statement

Auth v1 seeded 60+ wishlist items into Supabase. Three structural defects surfaced immediately:

1. **Done column is unnavigable.** Flat unsorted list with no grouping. Cannot tell what shipped in which build.
2. **Security / Platform / Auth+ items are uneditable.** The render function's `PHASES` array is hardcoded to `['Backlog','Phase 3','Phase 4','Phase 5','Phase 6']`. Security, Platform, and Auth+ phases exist in Supabase but are absent from the edit dropdown — items can be viewed but not reassigned.
3. **Build-close process requires patching index.html.** `phaseMigrateWishlist()` is the current mechanism for marking shipped items done. It runs on every page load, grows every build, and requires a JS change just to close out a wishlist item. The wishlist is in Supabase — done-marking should be a data operation, not a code change.

Immediate issue: "Authentication (Phase 6A)" is `status:'planned'` in the wishlist despite Auth v1 being closed. To be resolved as data-only SQL close-out in step 2 of the build order — no index.html migration.

---

## Scope

### In scope

- Schema: add `completed_in TEXT` and `completed_at TIMESTAMPTZ` columns to `wishlist_items`
- Done column: group by `completed_in` with hybrid sort (known tags by build order, unknown by `completed_at`, Untagged last)
- Filter bar: phase multiselect above the board, data-resilient (canonical + unknown phases)
- Done UX: inline dropdown for build tag selection (no raw `prompt()`)
- `moveWishlistItem()`: explicit set/clear of `completed_in` and `completed_at` on status transitions
- Pre-retirement reconciliation: concrete per-item verification before removing `statusCorrections`
- `phaseMigrateWishlist()`: remove `statusCorrections` block after reconciliation confirmed
- Auth v1 close-out: data-only SQL (no index.html change)
- Regression tests: 6 new WL-V2 unit tests
- Playwright: 2 new smoke tests → new baseline 56/0

### Out of scope

- Drag-and-drop reordering
- Priority ranking UI
- Full wishlist CRUD for non-owner users (requires role enforcement — backlog item 11)
- Mobile redesign (existing mobile viewport test must remain green; filter bar must not create horizontal overflow)
- Auth architecture changes
- Financial model logic changes
- Phase 4 RLS tightening / anon policy removal
- Role enforcement changes

---

## Clarification: Nav Target

The Wishlist tab uses section key `'roadmap'` internally. Mapping:

| Element | Value |
|---|---|
| Section ID | `s-roadmap` |
| Nav button ID | `nav-roadmap` |
| Display label | "Wishlist" |
| Playwright `clickNav()` call | `clickNav(page, 'roadmap')` |

The existing Playwright wishlist test already uses `clickNav(page, 'roadmap')` — this is correct. All new Playwright tests (WL-PW-1, WL-PW-2) use the same call. The spec's "Navigate to roadmap tab" language refers to `clickNav(page, 'roadmap')`, which opens the Wishlist section.

---

## Clarification: Playwright Count

Current baseline: **54/0**  
New tests added this build: **2** (WL-PW-1, WL-PW-2)  
Expected target: **56/0**  

No existing tests are renamed, split, or removed in this build. If the count differs from 56, the pre-push report must explain the delta explicitly.

---

## Clarification: `completed_at` Timestamp Source

Two sources are used — this is acceptable for a single-user dashboard and does not require a server RPC:

- **SQL close-outs** (e.g. Auth v1 close-out SQL, pre-build): use database server time via `now()`
- **UI close-outs** (clicking "✓ Done" in the app): use client ISO timestamp via `new Date().toISOString()`

Both write to the same `completed_at TIMESTAMPTZ` column. Minor clock skew between client and server is acceptable. No correction needed in v2.

---

## Schema Change

```sql
ALTER TABLE public.wishlist_items
  ADD COLUMN IF NOT EXISTS completed_in TEXT,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
```

No NOT NULL constraints — existing rows default to NULL. No RLS change needed; both columns fall under existing authenticated write policies.

---

## Auth v1 Close-Out (data-only — build step 2)

```sql
UPDATE public.wishlist_items
SET status = 'done',
    completed_in = 'Auth v1',
    completed_at = now()
WHERE title = 'Authentication (Phase 6A)';
```

No index.html migration. No `statusCorrections` entry.

---

## Pre-Retirement Reconciliation (build step 3)

The current `statusCorrections` array in `phaseMigrateWishlist()` contains exactly one entry:

| Title | Correction target | Expected current Supabase state |
|---|---|---|
| Playwright end-to-end smoke tests | `status='done'` | Already seeded as `done` in `WISHLIST_SEED` (line 5025) — correction is expected to be a no-op |

**Verification query (run in Supabase SQL editor before removing statusCorrections):**

```sql
SELECT title, phase, status, completed_in, completed_at
FROM public.wishlist_items
WHERE title IN (
  'Playwright end-to-end smoke tests',
  'Authentication (Phase 6A)'
)
ORDER BY title;
```

**Expected results:**

| title | status | completed_in | completed_at |
|---|---|---|---|
| Authentication (Phase 6A) | done | Auth v1 | (not null) |
| Playwright end-to-end smoke tests | done | null | null |

If "Playwright end-to-end smoke tests" shows `status='planned'` in Supabase (correction not yet landed), apply it manually before removing the block:

```sql
UPDATE public.wishlist_items
SET status = 'done'
WHERE title = 'Playwright end-to-end smoke tests' AND status != 'done';
```

Remove `statusCorrections` from `phaseMigrateWishlist()` only after the above query confirms both rows are in expected state.

**Full state scan** (run alongside to catch any other items needing attention):

```sql
SELECT title, phase, status, completed_in, completed_at
FROM public.wishlist_items
ORDER BY status, phase, title;
```

---

## JS Constants

### Build Tags

```javascript
var WISHLIST_BUILD_TAGS = [
  'Auth v1',
  'Stabilization S1',
  'Phase 6A Goal Registry',
  'Phase 5 What-If',
  'Phase 5 Budget Rules',
  'Phase 4',
  'Phase 3'
];
```

Newest/current build tag is `WISHLIST_BUILD_TAGS[0]`. Default selection when marking an item done.

### Phase Order

```javascript
var WISHLIST_PHASE_ORDER = [
  'Backlog','Phase 3','Phase 4','Phase 5','Phase 6',
  'Security','Platform','Auth+'
];
```

Actual dropdown/filter options = `WISHLIST_PHASE_ORDER` + any unique `phase` values found in loaded `wishlistData` not already in the list (appended alphabetically). Ensures future phases added in Supabase remain editable without a code change.

---

## Status Model

Allowed statuses: `idea`, `planned`, `done`. No `in-progress` status. Do not introduce one.

Column mapping:
- Ideas → `status === 'idea'`
- Planned → `status === 'planned'`
- Done → `status === 'done'`

---

## UI Changes

### 1. Filter Bar

Rendered above `.wl-board`. Phase multiselect pill group:

- "All" selected by default
- Multiple phases can be active simultaneously
- Applies to all three columns client-side (no Supabase query)
- State in `wishlistPhaseFilter` (array), reset on tab navigation
- No localStorage persistence
- Must not cause horizontal overflow

### 2. Done Column — Group by `completed_in`

Sort order:
1. Known build tags in `WISHLIST_BUILD_TAGS` order (index 0 = newest = top)
2. Unknown build tags (not in `WISHLIST_BUILD_TAGS`), sorted by newest `completed_at` first (fallback `updated_at`)
3. `completed_in = NULL` → "Untagged" group, always last

Group header: same pill + item count + horizontal rule style as Planned column phase separators.

Unknown build tags render — they are not suppressed.

### 3. Done UX — Inline Build Tag Dropdown

When "✓ Done" is clicked, card expands inline:

```
Mark as done — Build tag:
[ Auth v1 ▾ ]  [Confirm]  [Cancel]
```

- Dropdown populated from `WISHLIST_BUILD_TAGS`
- Default: `WISHLIST_BUILD_TAGS[0]`
- On Confirm: PATCH `{ status: 'done', completed_in: <selected>, completed_at: new Date().toISOString() }`
- On Cancel: no change

No raw `prompt()`.

### 4. `moveWishlistItem()` — Explicit Set/Clear

```
Moving TO 'done':
  PATCH { status: 'done', completed_in: <tag>, completed_at: new Date().toISOString() }

Moving AWAY FROM 'done' (to 'planned' or 'idea'):
  PATCH { status: <new>, completed_in: null, completed_at: null }
```

No stale completion tags on non-done items.

### 5. Phase Dropdown Fix

Edit form phase dropdown uses data-resilient phase list. `phaseColor()` additions:

- Security: `#dc2626`
- Platform: `#6366f1`
- Auth+: `#0891b2`
- Unknown phases: `#94a3b8` (default)

---

## `phaseMigrateWishlist()` Changes

Remove `statusCorrections` block (after reconciliation confirmed — build step 3). Retain:
- Phase 4 planned → Phase 5 bulk migration
- Title-based phase corrections
- Title rename corrections

---

## Regression Tests

| ID | Test |
|---|---|
| WL-V2-1 | `WISHLIST_BUILD_TAGS` is defined and `[0] === 'Auth v1'` |
| WL-V2-2 | `WISHLIST_PHASE_ORDER` includes Security, Platform, Auth+ |
| WL-V2-3 | `phaseColor()` returns non-default values for Security, Platform, Auth+ |
| WL-V2-4 | `moveWishlistItem()` PATCH body includes `completed_in` and `completed_at` when moving to done |
| WL-V2-5 | `moveWishlistItem()` PATCH body sets `completed_in: null` and `completed_at: null` when moving away from done |
| WL-V2-6 | `phaseMigrateWishlist()` source does NOT contain a `statusCorrections` array |

---

## Playwright Tests

**WL-PW-1: Filter smoke**

```
1. clickNav(page, 'roadmap') — opens Wishlist section
2. waitForFunction: roadmap-content contains 'Phase'
3. PRE-FILTER ASSERTIONS (unfiltered board):
   - Assert: at least one card with phase badge 'Security' is visible in the board
   - Assert: at least one card with phase badge 'Phase 6' is visible in the board
4. Click the 'Security' phase filter pill
5. POST-FILTER ASSERTIONS:
   - Assert: at least one card with phase badge 'Security' is still visible
   - Assert: no card with phase badge 'Phase 6' is visible
6. Click 'All' pill to clear filter
7. Assert: Phase 6 cards are visible again
```

**WL-PW-2: Done grouping smoke**

```
1. clickNav(page, 'roadmap') — opens Wishlist section
2. waitForFunction: roadmap-content contains 'Phase'
3. Locate the Done column container
4. Within the Done column, locate the 'Auth v1' group header element
5. Within that group container (between 'Auth v1' header and the next group header or column end),
   assert a card with title 'Authentication (Phase 6A)' is present
```

WL-PW-2 must scope the title assertion to the Auth v1 group container inside the Done column — not a loose page-level search.

Existing mobile viewport test must remain green. Filter bar must not produce horizontal scroll.

---

## Build Order

1. Run schema migration (`completed_in`, `completed_at`)
2. Run Auth v1 close-out SQL
3. Run statusCorrections reconciliation query — confirm expected state — report results
4. Update JS constants (`WISHLIST_BUILD_TAGS`, `WISHLIST_PHASE_ORDER`) and rendering
5. Update `moveWishlistItem()` set/clear behavior
6. Remove `statusCorrections` from `phaseMigrateWishlist()` (only after step 3 confirmed)
7. Add regression tests (WL-V2-1 through WL-V2-6)
8. Add Playwright tests (WL-PW-1, WL-PW-2)
9. Run regression and Playwright locally — target 56/0
10. Send pre-push report before pushing

---

## Guardrails (ChatGPT-specified)

- No financial model logic changes
- No Auth architecture changes
- No Phase 4 RLS tightening / anon policy removal
- No role enforcement changes
- No drag-and-drop
- No priority UI
- No mobile redesign

---

## Build Close Report Format

```
Wishlist close-out:
  <title>: <old status> → done | completed_in='<tag>' | completed_at=<timestamp>
  [one line per item changed]
```

---

## Acceptance Criteria

- [ ] Schema: `wishlist_items.completed_in TEXT` column exists
- [ ] Schema: `wishlist_items.completed_at TIMESTAMPTZ` column exists
- [ ] Auth v1 close-out: "Authentication (Phase 6A)" → `status='done'`, `completed_in='Auth v1'`, `completed_at IS NOT NULL`
- [ ] Done column groups by `completed_in`; "Auth v1" group visible; "Authentication (Phase 6A)" appears inside that group (scoped, not loose search)
- [ ] Unknown build tags render and sort after known tags by `completed_at`
- [ ] Moving item to done sets both `completed_in` and `completed_at` (via inline dropdown, no `prompt()`)
- [ ] Moving item away from done clears both `completed_in` and `completed_at` to null; no item with `status !== 'done'` has non-null `completed_in` or `completed_at` after a status move
- [ ] Filter bar renders above board; selecting a phase hides other-phase cards; no horizontal overflow
- [ ] Phase edit dropdown includes Security, Platform, Auth+; unknown data-phases also appear
- [ ] `phaseMigrateWishlist()` contains no `statusCorrections` array
- [ ] Pre-retirement reconciliation: query results documented in pre-push report
- [ ] Regression: 6 WL-V2 tests pass + all prior tests green
- [ ] Playwright: **56/0** (WL-PW-1 and WL-PW-2 passing; no existing tests changed)
- [ ] Live: verified at https://dashboard.herndons.us
- [ ] Build close report includes wishlist section with per-item status/completion log
