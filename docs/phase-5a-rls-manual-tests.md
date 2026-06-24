# Phase 5A — Manual RLS Verification Tests

**Purpose:** Confirm that row-level security is enforced at the database layer, independent of UI controls.  
**Run after:** SQL from `phase-5a-role-enforcement.sql` has been applied.  
**Supabase project:** `usayoldrawwmjsmretin`

---

## Setup: Get JWT Tokens for Each User

You need a live Bearer token for each user. Easiest way:

1. Open dashboard.herndons.us in a browser
2. Sign in as the user you want to test
3. Open browser DevTools → Network tab
4. Click any tab in the dashboard (Goals, Weeks, etc.)
5. Find any request to `usayoldrawwmjsmretin.supabase.co`
6. Copy the `Authorization` header value — it starts with `Bearer eyJ...`
7. That's your JWT token for that user

Do this once for Adam (adam@herndons.us), once for Wendy (wherndon22@gmail.com) — use a separate incognito window for Wendy.

Store them as shell variables for the curl tests below:

```bash
SUPA_URL="https://usayoldrawwmjsmretin.supabase.co"
SUPA_KEY="<your anon key from index.html>"   # SUPA_KEY constant in index.html
ADAM_TOKEN="eyJ..."    # Adam's Bearer token
WENDY_TOKEN="eyJ..."   # Wendy's Bearer token
```

---

## Test 1 — Wendy cannot INSERT anthropic_key row

**Expected: 403 Forbidden**

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$SUPA_URL/rest/v1/goals" \
  -H "Authorization: Bearer $WENDY_TOKEN" \
  -H "apikey: $SUPA_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: resolution=merge-duplicates,return=minimal" \
  -d '{"key":"anthropic_key","value":"sk-ant-fake-test"}'
```

**Pass:** response code is `403`  
**Fail:** response code is `201` or `200` (row was written — RLS not working)

---

## Test 2 — Wendy cannot UPDATE the anthropic_key row

**Expected: 403 Forbidden** (USING clause blocks access to the row)

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X PATCH "$SUPA_URL/rest/v1/goals?key=eq.anthropic_key" \
  -H "Authorization: Bearer $WENDY_TOKEN" \
  -H "apikey: $SUPA_KEY" \
  -H "Content-Type: application/json" \
  -d '{"value":"sk-ant-fake-test"}'
```

**Pass:** response code is `403` OR `200` with 0 rows affected  
To confirm 0 rows affected, check the response body: `[]` or empty means nothing was changed.

---

## Test 3 — Wendy cannot rename a normal row to anthropic_key (WITH CHECK test)

This tests that the `WITH CHECK` clause blocks a rename attack. Pick any existing financial goals key (e.g., `ak_goal`).

**Expected: 403**

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X PATCH "$SUPA_URL/rest/v1/goals?key=eq.ak_goal" \
  -H "Authorization: Bearer $WENDY_TOKEN" \
  -H "apikey: $SUPA_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key":"anthropic_key","value":"sk-ant-fake-test"}'
```

**Pass:** response code is `403`  
**Fail:** response code is `200` (rename succeeded — WITH CHECK not working)

---

## Test 4 — Wendy CAN update a normal financial goals row

**Expected: 200 or 204 (success)**

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X PATCH "$SUPA_URL/rest/v1/goals?key=eq.ak_goal" \
  -H "Authorization: Bearer $WENDY_TOKEN" \
  -H "apikey: $SUPA_KEY" \
  -H "Content-Type: application/json" \
  -d '{"value":"7000"}'
```

**Pass:** response code is `200` or `204`  
**Fail:** response code is `403` (Wendy incorrectly blocked from financial data)

> After this test passes, reset the value back to its original if needed.

---

## Test 5 — Adam CAN update anthropic_key row

**Expected: 200 or 204**

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X PATCH "$SUPA_URL/rest/v1/goals?key=eq.anthropic_key" \
  -H "Authorization: Bearer $ADAM_TOKEN" \
  -H "apikey: $SUPA_KEY" \
  -H "Content-Type: application/json" \
  -d '{"value":"sk-ant-test-verify-only"}'
```

**Pass:** response code is `200` or `204`  
**Fail:** response code is `403` (Adam incorrectly blocked — something wrong with is_owner())

> After this test passes, revert the key to the real value from the dashboard UI.

---

## Test 6 — Unauthenticated request is blocked

**Expected: 401 Unauthorized**

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X GET "$SUPA_URL/rest/v1/goals?select=*" \
  -H "apikey: $SUPA_KEY"
```

**Pass:** response code is `401` (no Bearer token = no access)  
**Fail:** response code is `200` (anonymous read still open — RLS not working)

---

## Quick Reference: Pass/Fail Summary

| Test | User | Action | Expected code | Meaning |
|------|------|--------|---------------|---------|
| 1 | Wendy | INSERT anthropic_key | 403 | Blocked by WITH CHECK |
| 2 | Wendy | UPDATE anthropic_key row | 403 or 200+empty | Blocked by USING |
| 3 | Wendy | Rename ak_goal → anthropic_key | 403 | Blocked by WITH CHECK |
| 4 | Wendy | Update ak_goal value | 200/204 | Allowed — financial write |
| 5 | Adam | Update anthropic_key | 200/204 | Allowed — owner |
| 6 | No auth | Read goals | 401 | Blocked — unauthenticated |

---

## If a test fails

- **Tests 1-3 fail (Wendy gets 200):** Goals policies may not have applied. Re-run Step 3 of the SQL. Verify `goals_financial_insert` and `goals_financial_update` policies exist in Supabase dashboard → Authentication → Policies.
- **Test 4 fails (Wendy gets 403):** `can_write_financials()` function may not have been created, or Wendy's role is not `household_admin`. Re-run Step 0 and Step 2 of the SQL.
- **Test 5 fails (Adam gets 403):** `is_owner()` function not created or Adam's role is not `owner`. Re-run Step 2.
- **Test 6 fails (unauthenticated gets 200):** SELECT policy was accidentally dropped. Restore from rollback SQL and re-apply.
