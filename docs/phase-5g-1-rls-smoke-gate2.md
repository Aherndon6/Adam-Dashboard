# Phase 5G-1 RLS Behavioral Smoke — Gate 2 (real API caller)

**STAGING ONLY** (`pkwotgqivgaapwuqgwqb`). Runs the actual **Auth → JWT → PostgREST → RLS** path that Gate 1's SQL impersonation cannot exercise. **RLS is not declared cleared until Gate 2 passes.**

Runnable script lives **uncommitted in scratchpad** (`gate2-smoke.sh`) because it carries the staging **anon key** and the test users' **passwords**. Never commit keys/passwords.

## Identities (edit #2 — real unauthorized user included)

Four **real** GoTrue sign-ins / callers, all on staging:

| Caller | Auth | `app_users` | Expectation class |
|---|---|---|---|
| **writer** | password sign-in → bearer | active, `household_admin` | read + write allowed |
| **viewer** | password sign-in → bearer | active, `viewer` | read allowed, write denied |
| **unauthorized** | password sign-in → bearer (a **real** `auth.users` row) | **no `app_users` row** | read empty, write denied — proves "authenticated but not allowlisted" through the real API |
| **anon** | apikey header only, **no** bearer | n/a | everything denied |

> The **email/sub mismatch** probes (M1/M2) are **Gate-1 policy/harness probes only** (edit #3). They are not normal GoTrue behavior — a real Supabase JWT always carries `sub` and `email` from the same `auth.users` row — so they are **not** part of this Gate-2 matrix. M2's finding (write gate ignores email) is filed as backlog, not re-tested here.

## Exact HTTP audit matrix (edit #1)

Capture, for every call: **HTTP status**, **response body**, and the PostgREST **`code`/`message`** on failures. A denied write that returns an empty/no-op **2xx** is a **FAIL** — a real RLS denial is an explicit 401/403 with `code=42501`.

`base = https://pkwotgqivgaapwuqgwqb.supabase.co/rest/v1`

Status columns give the accepted **class** (D7): assert the status is in the set **and** the body carries the expected `code`/message. The runner (`gate2-smoke.sh`) implements **all 17 rows** and enforces exactly this.

| # | Caller | Request | Expect status | Expect body / error |
|---|---|---|---|---|
| 1 | anon | `GET  {base}/planned_outflows?select=*` (apikey only) | **401 / 403** | `{"code":"42501","message":"permission denied for table planned_outflows"}` |
| 2 | anon | `POST {base}/outflow_events` (apikey only) | **401 / 403** | `code 42501` permission denied |
| 3 | unauthorized | `GET  {base}/planned_outflows?select=*` (bearer) | **200** | `[]` (empty array — RLS filters all rows; **not** an error) |
| 4 | unauthorized | `POST {base}/planned_outflows` (bearer, valid body) | **403** | `{"code":"42501","message":"new row violates row-level security policy for table \"planned_outflows\""}` |
| 5 | unauthorized | `POST {base}/outflow_events` (bearer, valid body) | **403** | `code 42501` RLS violation |
| 6 | viewer | `GET  {base}/planned_outflows?select=*` (bearer) | **200** | non-empty array (read gate passes) |
| 7 | viewer | `GET  {base}/outflow_events?select=*` (bearer) | **200** | non-empty array |
| 8 | viewer | `POST {base}/planned_outflows` (bearer, valid body) | **403** | `code 42501` RLS violation |
| 9 | viewer | `POST {base}/outflow_events` (bearer, valid body) | **403** | `code 42501` RLS violation |
| 10 | viewer | `PATCH {base}/planned_outflows?key=eq.__gate2__` (bearer, `{"label":"x"}`) | **200 / 204** | 0 rows matched under RLS `USING`; **followed by a GET post-check (row 10b) proving `label` is still `gate2`** — the only 2xx accepted, and only with the no-mutation proof |
| 11 | writer | `GET  {base}/planned_outflows?select=*` (bearer) | **200** | non-empty array |
| 12 | writer | `POST {base}/planned_outflows` (bearer, `Prefer: return=representation`, no `created_by_user_id`) | **201** | returned row has `created_by_user_id` = writer's `sub` (proves `auth.uid()` default + FK + write policy) |
| 13 | writer | `POST {base}/outflow_events` (bearer, valid `set_aside`) | **201** | returned row `created_by_user_id` = writer's `sub` |
| 14 | writer | `PATCH {base}/outflow_events?...` (bearer, `{"memo":"x"}`) | **403** | `code 42501` permission denied (no UPDATE grant) |
| 15 | writer | `DELETE {base}/outflow_events?...` (bearer) | **403** | `code 42501` permission denied (no DELETE grant) |
| 16 | writer | `DELETE {base}/planned_outflows?key=eq.__gate2__` (bearer) | **403** | `code 42501` permission denied (no DELETE grant) |
| 17 | writer | `PATCH {base}/planned_outflows?key=eq.__gate2__` (bearer, `{"key":"__renamed__"}`) | **400/403/409** | immutability trigger raise: `message` contains `immutable after insert` |

> Status-class note (edit #1 / D7): PostgREST maps a **grant-level** permission-denied to **401 for anonymous** callers and **403 for authenticated** callers — but the exact split is version-dependent, so the runner accepts **{401,403}** for anon (rows 1–2) and asserts on `code 42501`. It maps an **RLS `WITH CHECK`** violation to **403** with `code 42501` (rows 4–5, 8–9, and grant-denied 14–16). A trigger `RAISE EXCEPTION` (row 17) surfaces as **{400,403,409,500}** across versions, so the runner asserts on the `message` substring `immutable` rather than a single code. Record the actual code/message; deviations from these classes are findings.

**Execution order (D8):** the runner reorders from the matrix numbering so the viewer PATCH (row 10) has a real target — the **writer creates `__gate2__` first** (rows 12–13), then anon/unauthorized/viewer denials run against real committed data, then the writer append-only/immutability checks (rows 14–17).

## Post-mutation proof (edits #6/#7 carried into Gate 2)

Gate 2 writes **commit** (no rollback). After the run, as service_role/owner verify:
- Only the intended writer rows exist (`__gate2__` plan + its events); no rows authored by viewer/unauthorized/anon.
- The `__gate2__` label/key are unchanged by rows 10 and 17.
These committed rows are removed later by `phase-5g-1-rollback.sql` (drops the tables) during cleanup — see `phase-5g-1-rls-smoke-cleanup.sql`.

## Final assertion — no app flag/UI enablement (edit #6)

This is a DB/API-layer smoke only. Confirm at the end:
- `showCashPlanning` is **absent** from `index.html` `FEATURE_FLAGS` (not merely false) — `git grep -n showCashPlanning -- index.html` returns nothing.
- **No app code changed** — `git status --porcelain index.html` empty; no diff to any app source.
- No Cash Planning nav/section is reachable in any environment.

## Sequence

1. (already done) re-apply `phase-5g-1-migration.sql` on freshly-marked staging + seed `[STAGING]` app_users.
2. Gate 1 (`phase-5g-1-rls-smoke-gate1.sql`) green.
3. Gate 2 (`scratchpad/gate2-smoke.sh`) — this matrix green.
4. `phase-5g-1-rollback.sql` → `phase-5g-1-rls-smoke-cleanup.sql`.
5. Post-rollback schema diff vs the rehearsal baseline.
