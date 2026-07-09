# Phase 5G-1C-2 RLS Behavioral Smoke — Gate 2 (real API caller)

**STAGING ONLY** (`pkwotgqivgaapwuqgwqb`). Runs the actual **Auth → JWT → PostgREST → RLS** path that Gate 1's SQL impersonation cannot exercise. **RLS is not declared cleared until Gate 2 passes.** DO NOT run against production (`usayoldrawwmjsmretin`).

The runnable script lives **uncommitted in scratchpad** (`scratchpad/gate2c2-smoke.sh`) because it carries the staging **anon key** and the test users' **passwords**. Never commit keys/passwords. Mirror the shape of the 5G-1 `gate2-smoke.sh` (same four identities, same status-class assertions).

Prereq: re-apply `phase-5g-1c-2-migration.sql` on a freshly-marked staging DB, and have the four `[STAGING]` identities (writer/viewer/unauthorized/anon) from the 5G-1 Gate-2 run available. At least one **reconciled** `weekly_reconciliations` week must exist to exercise the RPC happy-path (rows 11–13); if none exists on staging, seed one first or record those rows as **SKIPPED**.

## Identities

Four **real** GoTrue callers, all on staging (identical to the 5G-1 Gate-2 set):

| Caller | Auth | `app_users` | Expectation class |
|---|---|---|---|
| **writer** | password sign-in → bearer | active, `household_admin` | read + write (via RPC) allowed |
| **viewer** | password sign-in → bearer | active, `viewer` | read allowed; write + RPC denied |
| **unauthorized** | password sign-in → bearer (real `auth.users` row) | **no `app_users` row** | read empty; write + RPC denied |
| **anon** | apikey header only, no bearer | n/a | everything denied |

> Writes to `goal_funding_snapshots` go through the **RPC** in the app; the table's direct INSERT/UPDATE policies exist as defense-in-depth and are also probed here.

## Exact HTTP audit matrix

Capture for every call: **HTTP status**, **response body**, and the PostgREST **`code`/`message`** on failures. A denied write that returns an empty/no-op **2xx** is a **FAIL** — a real RLS denial is an explicit 401/403 with `code=42501`. An RPC business-rule rejection surfaces as **400** with the `RAISE` message in the body.

`base = https://pkwotgqivgaapwuqgwqb.supabase.co/rest/v1`
RPC endpoint: `POST {base}/rpc/save_goal_funding_snapshots` with body `{"p_model_year":2026,"p_week_num":<recweek>,"p_rows":[...]}`

| # | Caller | Request | Expect status | Expect body / error |
|---|---|---|---|---|
| 1 | anon | `GET  {base}/goal_funding_snapshots?select=*` (apikey only) | **401 / 403** | `code 42501` permission denied |
| 2 | anon | `POST {base}/rpc/save_goal_funding_snapshots` (apikey only) | **401 / 403 / 404** | denied (no EXECUTE for anon) |
| 3 | unauthorized | `GET  {base}/goal_funding_snapshots?select=*` (bearer) | **200** | `[]` (RLS filters all rows; **not** an error) |
| 4 | unauthorized | `POST {base}/goal_funding_snapshots` (bearer, valid body) | **403** | `code 42501` RLS violation |
| 5 | unauthorized | `POST {base}/rpc/save_goal_funding_snapshots` (bearer) | **400 / 403** | RPC raise `not authorized` |
| 6 | viewer | `GET  {base}/goal_funding_snapshots?select=*` (bearer) | **200** | array (read gate passes; may be `[]` pre-seed) |
| 7 | viewer | `POST {base}/goal_funding_snapshots` (bearer, valid body) | **403** | `code 42501` RLS violation |
| 8 | viewer | `PATCH {base}/goal_funding_snapshots?...` (bearer, `{"funded_amount":1}`) | **200 / 204** | 0 rows matched under RLS `USING`; **followed by a GET post-check proving no mutation** — the only 2xx accepted, and only with the no-mutation proof |
| 9 | viewer | `POST {base}/rpc/save_goal_funding_snapshots` (bearer) | **400 / 403** | RPC raise `not authorized` |
| 10 | writer | `GET  {base}/goal_funding_snapshots?select=*` (bearer) | **200** | array |
| 11 | writer | `POST {base}/rpc/save_goal_funding_snapshots` (bearer, one valid `reconciliation` row at a reconciled week) | **200** | returns row count `1`; a follow-up GET shows the row with `created_by_user_id` = writer's `sub` |
| 12 | writer | `POST {base}/rpc/...` **again**, same key, new amount (idempotent) | **200** | still `1` row for that `(model_year,week_num,goal_id)`; amount updated |
| 13 | writer | `POST {base}/rpc/...` unreconciled week | **400** | RPC raise `week % is not reconciled` |
| 14 | writer | `POST {base}/rpc/...` `funded_amount:-1` | **400** | RPC raise `negative funded_amount` |
| 15 | writer | `POST {base}/rpc/...` `source:"bogus"` | **400** | RPC raise `invalid source` |
| 16 | writer | `POST {base}/rpc/...` `goal_id:"wewe_rccl"` | **400** | RPC raise `excluded` |
| 17 | writer | `POST {base}/rpc/...` `goal_id:"adam_401k"` (auto) | **400** | RPC raise `auto goal` |
| 18 | writer | `DELETE {base}/goal_funding_snapshots?...` (bearer) | **403** | `code 42501` permission denied (no DELETE grant) |

> Status-class note: PostgREST maps a **grant-level** permission-denied to **401 for anon** / **403 for authenticated** (assert on `code 42501`); an **RLS `WITH CHECK`** violation to **403** `code 42501`; and a function **`RAISE EXCEPTION`** (RPC business rules, rows 5/9/13–17) to **400** with the message in `body.message`. Record the actual code/message; deviations from these classes are findings. anon-on-RPC (row 2) may surface as 401/403/404 depending on `pgrst` exposure of a no-EXECUTE function — assert "not executed / denied," not a single code.

> Payload-shape rejections (optional writer rows): `p_rows` **null** → **400** `message` contains `must be a JSON array`; `p_rows` **`[]`** (empty) → **400** `message` contains `at least one row`. The RPC rejects both explicitly (null is not COALESCEd to a no-op; empty arrays are not a legitimate save). Include these two calls in the runner if convenient.

**Execution order:** writer seeds row 11 first (real committed data), then anon/unauthorized/viewer denials run against it, then the writer rejection matrix (13–17) and DELETE (18). Rows 11–12 **commit**; everything else is read-only or denied.

## Post-mutation proof

Gate 2 writes **commit** (no rollback). After the run, as service_role/owner verify:
- Only the intended writer rows exist (the row 11/12 upsert); no rows authored by viewer/unauthorized/anon.
- The upserted row's `created_by_user_id` = writer's `sub`; `source`/`funded_amount` match the last (row 12) call.

## Final assertion — no app flag/UI enablement

Gate 2 exercises the **API surface only**. It does **not** enable any app flag, run `runModel`, or touch `index.html` / the overlay. The `runModel` overlay, `getGoalFunded` snapshot read, loader, and Funding Plan label edits (behind the identity gate + freeze exception) are a **separate** step, gated on Adam's go-ahead after this staging package is green — and are **not** part of 5G-1C-2's staging rehearsal.

## Cleanup

There is no separate cleanup file in the 5G-1C-2 package. Return staging to the clean baseline by running **`phase-5g-1c-2-rollback.sql`** (drops the RPC + table; nothing references `goal_funding_snapshots`, so no CASCADE is needed), then confirm the post-rollback schema-only diff equals the pre-migration baseline (ignoring pg_dump's per-run `\restrict` tokens). Delete any throwaway `auth.users` / `app_users` rows created solely for the smoke if they were not already retained from the 5G-1 Gate-2 run. Leave `app_environment` and `fn_set_updated_at()` intact.
