#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# ██  STAGING ONLY — herndon-fos-staging  ██   Phase 5G-1D Gate 2 — PostgREST call template.
# ═══════════════════════════════════════════════════════════════════════════
# Authored, NOT executed. This is the HTTP/PostgREST half of Gate 2 (the SQL editor bypasses RLS, so the
# real grant/RLS/SECURITY-DEFINER path must be exercised via a real bearer token). Copy to a LOCAL-ONLY
# filled file, fill the placeholders, chmod 600, `source` it in a dedicated shell, run gate2_preflight,
# then run each G2_* function MANUALLY at the point the runbook + the matching gate2-*.sql PRE/POST direct.
# Each function CAPTURES the response (HTTP status, body, code, message, hint, details) and ASSERTS the
# expected response classification — not just a printout. Tokens/keys are NEVER printed. No shell tracing.
# Do NOT commit a filled copy, tokens, or keys.
#
# PLACEHOLDERS (fill locally; never commit):
#   {{SUPA_URL}}      e.g. https://pkwotgqivgaapwuqgwqb.supabase.co
#   {{ANON_KEY}}      staging anon apikey (for anon call + apikey header)
#   {{OWNER_TOKEN}}   owner (Adam, is_owner()=true) access token — the <ADAM_UID> subject maps in the JWT
#   {{WENDY_TOKEN}}   household_admin (Wendy, is_owner()=false) access token
#   {{UNAUTH_TOKEN}}  a valid-JWT caller with NO app_users row (for G2-2)
#   {{PATCH_ID}}      the id captured from the gate2-20b pre-seed SELECT (G2-20b only)
# Balance-free: every value below is clearly synthetic (round hundreds; sentinel 424242.42).
# ─────────────────────────────────────────────────────────────────────────
# NOTE: `source` this file. We deliberately do NOT `set -e`/`set -x` (would leak into / trace the operator
# shell and could expose secrets). Each function reports ✓ PASS / ✗ FAIL and returns 0/1 explicitly.

SUPA_URL="{{SUPA_URL}}"; ANON_KEY="{{ANON_KEY}}"
OWNER_TOKEN="{{OWNER_TOKEN}}"; WENDY_TOKEN="{{WENDY_TOKEN}}"; UNAUTH_TOKEN="{{UNAUTH_TOKEN}}"
WRAP="$SUPA_URL/rest/v1/rpc/save_weekly_closeout_with_snapshots"
OPTB="$SUPA_URL/rest/v1/rpc/correct_goal_funding_snapshot"

# ── Preflight: hard-stop unless jq + curl exist AND no placeholder remains unfilled (item 4) ──
gate2_preflight() {
  command -v jq   >/dev/null 2>&1 || { echo "HARD STOP: jq not found — install jq (grounded JSON parser) before Gate 2."; return 1; }
  command -v curl >/dev/null 2>&1 || { echo "HARD STOP: curl not found."; return 1; }
  local v
  for v in SUPA_URL ANON_KEY OWNER_TOKEN WENDY_TOKEN UNAUTH_TOKEN; do
    case "${!v}" in *"{{"*"}}"*) echo "HARD STOP: placeholder still unresolved in \$$v — this is the committed template, not a filled local copy. Fill locally, do not run the committed file."; return 1;; esac
  done
  echo "gate2_preflight OK: jq $(jq --version), curl present, no unresolved placeholders."
}

# ── Core call: capture status+body; parse code/message/hint/details via jq. Never prints tokens/keys. ──
_do_call() { # $1=token $2=url $3=json-body
  local tok="$1" url="$2" body="$3" resp
  resp="$(curl -sS -w $'\n%{http_code}' -X POST "$url" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $tok" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' -d "$body" 2>/dev/null)" || { echo "  transport error (curl failed)"; _last_status="000"; _last_body=""; return 0; }
  _last_status="${resp##*$'\n'}"; _last_body="${resp%$'\n'*}"
  _last_code="$(printf '%s' "$_last_body"    | jq -r 'if type=="object" then (.code // "") else "" end' 2>/dev/null)"
  _last_message="$(printf '%s' "$_last_body" | jq -r 'if type=="object" then (.message // "") else "" end' 2>/dev/null)"
  _last_hint="$(printf '%s' "$_last_body"    | jq -r 'if type=="object" then (.hint // "") else "" end' 2>/dev/null)"
  _last_details="$(printf '%s' "$_last_body" | jq -r 'if type=="object" then (.details // "") else "" end' 2>/dev/null)"
  _last_ok="$(printf '%s' "$_last_body"      | jq -r 'if type=="object" then (.ok // false) else false end' 2>/dev/null)"
  _last_idem="$(printf '%s' "$_last_body"    | jq -r 'if type=="object" then (.idempotent // false) else false end' 2>/dev/null)"
  echo "  HTTP=$_last_status code=${_last_code:-<none>} ok=${_last_ok} idem=${_last_idem} msg=\"${_last_message}\" hint=\"${_last_hint}\" details=\"${_last_details}\""
}
_pass(){ echo "  ✓ $1"; return 0; }
_fail(){ echo "  ✗ $1"; return 1; }

# ── Classification helpers (assert expected response class) ──
expect_success()           { [ "$_last_status" = "200" ] && [ "$_last_ok" = "true" ] && _pass "$1 SUCCESS" || _fail "$1 expected success (ok:true/200)"; }
expect_success_idem()      { [ "$_last_status" = "200" ] && [ "$_last_ok" = "true" ] && [ "$_last_idem" = "true" ] && _pass "$1 idempotent success" || _fail "$1 expected idempotent:true success"; }
expect_reopened()          { [ "$_last_status" = "200" ] && [ "$_last_ok" = "true" ] && printf '%s' "$_last_body" | jq -e '.reopened==true' >/dev/null 2>&1 && _pass "$1 genuine reopen" || _fail "$1 expected reopened:true success"; }
expect_repaired()          { [ "$_last_status" = "200" ] && [ "$_last_ok" = "true" ] && printf '%s' "$_last_body" | jq -e '.repaired==true' >/dev/null 2>&1 && _pass "$1 repair success" || _fail "$1 expected repaired:true success"; }
# anon path: grant-layer denial (function not exposed / no EXECUTE) — transport 401/403/404, never the body's 42501.
expect_anon_denied()       { case "$_last_status" in 401|403|404) _pass "$1 anon denied at grant layer (HTTP $_last_status)";; *) _fail "$1 expected anon grant-layer denial (401/403/404), got HTTP $_last_status code=$_last_code";; esac; }
# body-layer owner/writer authorization rejection.
expect_authz_reject()      { [ "$_last_code" = "42501" ] && _pass "$1 authorization reject (42501)" || _fail "$1 expected code=42501, got HTTP $_last_status code=$_last_code"; }
expect_gfa01()             { [ "$_last_code" = "GFA01" ] && [ "$_last_hint" = "REQUIRES_SUPERVISED_ADJUDICATION" ] && _pass "$1 GFA01 + REQUIRES_SUPERVISED_ADJUDICATION" || _fail "$1 expected code=GFA01 hint=REQUIRES_SUPERVISED_ADJUDICATION, got code=$_last_code hint=$_last_hint"; }
# domain hard-stop: a plpgsql RAISE (HTTP 400) whose message contains the expected DOMAIN phrase, and which
# is NOT an auth (42501)/GFA01/transport failure — proving the reject is the intended business guard.
expect_domain_reject()     { # $1=label $2=expected message substring
  if [ "$_last_status" = "400" ] && [ "$_last_code" != "42501" ] && [ "$_last_code" != "GFA01" ] \
     && printf '%s' "$_last_message" | grep -qiF -- "$2"; then _pass "$1 domain reject (\"$2\")";
  else _fail "$1 expected domain reject containing \"$2\" (HTTP 400, non-auth), got HTTP $_last_status code=$_last_code msg=\"$_last_message\""; fi; }
# injected atomic failure: proves the failure came from the ATOMIC-TEST trigger, not an earlier guard.
expect_atomic_fail()       { [ "$_last_status" = "400" ] && printf '%s' "$_last_message" | grep -qiF 'ATOMIC-TEST synthetic failure' && _pass "$1 rolled back via ATOMIC-TEST synthetic failure" || _fail "$1 expected 'ATOMIC-TEST synthetic failure' (not an earlier guard), got HTTP $_last_status code=$_last_code msg=\"$_last_message\""; }

# ── reusable synthetic payloads (eligible nine; monotonic-safe) ──
NINE_EQ='[{"goal_id":"adam_ira","funded_amount":100},{"goal_id":"wendy_ira","funded_amount":200},{"goal_id":"wendy_sep","funded_amount":300},{"goal_id":"alaska","funded_amount":400},{"goal_id":"bailey_529","funded_amount":500},{"goal_id":"bryce_529","funded_amount":600},{"goal_id":"preston_529","funded_amount":700},{"goal_id":"bryce_vehicle","funded_amount":800},{"goal_id":"christmas_cruise","funded_amount":900}]'
# G2-19a: adam_ira 50 < anchor 100 (wk6, prior=opening_anchor)
NINE_LOW='[{"goal_id":"adam_ira","funded_amount":50},{"goal_id":"wendy_ira","funded_amount":200},{"goal_id":"wendy_sep","funded_amount":300},{"goal_id":"alaska","funded_amount":400},{"goal_id":"bailey_529","funded_amount":500},{"goal_id":"bryce_529","funded_amount":600},{"goal_id":"preston_529","funded_amount":700},{"goal_id":"bryce_vehicle","funded_amount":800},{"goal_id":"christmas_cruise","funded_amount":900}]'
# G2-19b (wk8): wendy_ira 50 < wk7 recon 200 → reject on wendy_ira (adam_ira 120 >= wk7 corrected 120)
NINE_W8B='[{"goal_id":"adam_ira","funded_amount":120},{"goal_id":"wendy_ira","funded_amount":50},{"goal_id":"wendy_sep","funded_amount":300},{"goal_id":"alaska","funded_amount":400},{"goal_id":"bailey_529","funded_amount":500},{"goal_id":"bryce_529","funded_amount":600},{"goal_id":"preston_529","funded_amount":700},{"goal_id":"bryce_vehicle","funded_amount":800},{"goal_id":"christmas_cruise","funded_amount":900}]'
# G2-19c (wk8): adam_ira 100 < wk7 CORRECTED 120 → reject on adam_ira (prior=correction)
NINE_W8C='[{"goal_id":"adam_ira","funded_amount":100},{"goal_id":"wendy_ira","funded_amount":200},{"goal_id":"wendy_sep","funded_amount":300},{"goal_id":"alaska","funded_amount":400},{"goal_id":"bailey_529","funded_amount":500},{"goal_id":"bryce_529","funded_amount":600},{"goal_id":"preston_529","funded_amount":700},{"goal_id":"bryce_vehicle","funded_amount":800},{"goal_id":"christmas_cruise","funded_amount":900}]'
# half-close close payload (wk8/wk9): adam_ira 120 (>= wk7 corrected 120), others 200..900
NINE_HC='[{"goal_id":"adam_ira","funded_amount":120},{"goal_id":"wendy_ira","funded_amount":200},{"goal_id":"wendy_sep","funded_amount":300},{"goal_id":"alaska","funded_amount":400},{"goal_id":"bailey_529","funded_amount":500},{"goal_id":"bryce_529","funded_amount":600},{"goal_id":"preston_529","funded_amount":700},{"goal_id":"bryce_vehicle","funded_amount":800},{"goal_id":"christmas_cruise","funded_amount":900}]'
# sentinel: adam_ira = 424242.42 (an INCREASE → passes validation+monotonicity; trips the G2-20 trigger)
NINE_SENTINEL='[{"goal_id":"adam_ira","funded_amount":424242.42},{"goal_id":"wendy_ira","funded_amount":200},{"goal_id":"wendy_sep","funded_amount":300},{"goal_id":"alaska","funded_amount":400},{"goal_id":"bailey_529","funded_amount":500},{"goal_id":"bryce_529","funded_amount":600},{"goal_id":"preston_529","funded_amount":700},{"goal_id":"bryce_vehicle","funded_amount":800},{"goal_id":"christmas_cruise","funded_amount":900}]'
B='"p_chk":1000,"p_sav":2000,"p_amx":3000,"p_tax":4000,"p_lc":5000,"p_balance_basis":"available_balance"'
B2='"p_chk":1001,"p_sav":2000,"p_amx":3000,"p_tax":4000,"p_lc":5000,"p_balance_basis":"available_balance"'
CC_G(){ echo "{\"expected_item_id\":\"$1\",\"model_year\":2026,\"origin_model_week\":$2,\"amount_cents\":100,\"payee\":\"__GATE2__\",\"commitment_class\":\"other_transfer\",\"required_or_discretionary\":\"discretionary_deployment\"}"; }

# ══════════════ SUB-PHASE 3 — core ══════════════
G2_19a() { _do_call "$OWNER_TOKEN" "$WRAP" "{\"p_week_num\":6,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_LOW,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_domain_reject G2-19a "monotonic violation"; }
G2_1()   { _do_call "$ANON_KEY"     "$WRAP" "{\"p_week_num\":6,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_anon_denied G2-1; }
G2_2()   { _do_call "$UNAUTH_TOKEN" "$WRAP" "{\"p_week_num\":6,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_authz_reject G2-2; }
G2_3()   { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":6,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_success G2-3; }
G2_4()   { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":6,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_success_idem G2-4; }
G2_5()   { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":6,\"p_model_year\":2026,$B,\"p_new_commitments\":[$(CC_G __GATE2_G5__ 6)],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_gfa01 G2-5; }
G2_6()   { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":6,\"p_model_year\":2026,$B2,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_domain_reject G2-6 "already fully closed with different values"; }
G2_7()   { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":8,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_domain_reject G2-7 "not the next contiguous closeout week"; }
G2_8()   { _do_call "$WENDY_TOKEN"  "$WRAP" "{\"p_week_num\":7,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_success G2-8; }

# ══════════════ SUB-PHASE 4 — reopen ══════════════
G2_9()   { _do_call "$WENDY_TOKEN"  "$WRAP" "{\"p_week_num\":7,\"p_model_year\":2026,$B2,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"approved_reopen\",\"p_expected_count\":9}"; expect_authz_reject G2-9; }
G2_10b() { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":7,\"p_model_year\":2026,$B2,\"p_new_commitments\":[$(CC_G __GATE2_G10B__ 7)],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"approved_reopen\",\"p_expected_count\":9}"; expect_domain_reject G2-10b "must not carry commitment operations"; }
G2_10()  { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":7,\"p_model_year\":2026,$B2,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"approved_reopen\",\"p_expected_count\":9}"; expect_reopened G2-10; }
G2_11()  { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":7,\"p_model_year\":2026,$B2,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"approved_reopen\",\"p_expected_count\":9}"; expect_success_idem G2-11; }
G2_12()  { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":7,\"p_model_year\":2026,$B2,\"p_new_commitments\":[$(CC_G __GATE2_G12__ 7)],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"approved_reopen\",\"p_expected_count\":9}"; expect_gfa01 G2-12; }
G2_13()  { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":6,\"p_model_year\":2026,$B2,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_EQ,\"p_mode\":\"approved_reopen\",\"p_expected_count\":9}"; expect_domain_reject G2-13 "not the latest completed week"; }

# ══════════════ SUB-PHASE 5 — Option B (+ G2-16b run in Sub-phase 7) ══════════════
G2_14()  { _do_call "$OWNER_TOKEN"  "$OPTB" '{"p_model_year":2026,"p_week_num":7,"p_goal_id":"adam_ira","p_new_funded_amount":120,"p_expected_prior":100,"p_note":"[STAGING-FIXTURE][GATE2] G2-14 in-bounds correction"}'; expect_success G2-14; }
G2_15()  { _do_call "$OWNER_TOKEN"  "$OPTB" '{"p_model_year":2026,"p_week_num":7,"p_goal_id":"adam_ira","p_new_funded_amount":130,"p_expected_prior":999,"p_note":"[STAGING-FIXTURE][GATE2] G2-15 stale prior"}'; expect_domain_reject G2-15 "stale expected_prior"; }
G2_16a() { _do_call "$OWNER_TOKEN"  "$OPTB" '{"p_model_year":2026,"p_week_num":7,"p_goal_id":"adam_ira","p_new_funded_amount":50,"p_expected_prior":120,"p_note":"[STAGING-FIXTURE][GATE2] G2-16a below preceding"}'; expect_domain_reject G2-16a "below preceding effective value"; }
G2_17()  { _do_call "$WENDY_TOKEN"  "$OPTB" '{"p_model_year":2026,"p_week_num":7,"p_goal_id":"adam_ira","p_new_funded_amount":121,"p_expected_prior":120,"p_note":"[STAGING-FIXTURE][GATE2] G2-17 wendy"}'; expect_authz_reject G2-17; }
# G2-16b — RUN IN SUB-PHASE 7 AFTER CLOSE-W8 (wk8 adam_ira=120 becomes the following bound), before closing wk9:
G2_16b() { _do_call "$OWNER_TOKEN"  "$OPTB" '{"p_model_year":2026,"p_week_num":7,"p_goal_id":"adam_ira","p_new_funded_amount":130,"p_expected_prior":120,"p_note":"[STAGING-FIXTURE][GATE2] G2-16b above following"}'; expect_domain_reject G2-16b "above following effective value"; }

# ══════════════ SUB-PHASE 6 — monotonicity (wk8 rejects; wk8 stays open) ══════════════
G2_19b() { _do_call "$OWNER_TOKEN" "$WRAP" "{\"p_week_num\":8,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_W8B,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_domain_reject G2-19b "monotonic violation"; }
G2_19c() { _do_call "$OWNER_TOKEN" "$WRAP" "{\"p_week_num\":8,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_W8C,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_domain_reject G2-19c "monotonic violation"; }
# G2-19d: a later-week closeout WHILE a wk5 anchor row is removed (SQL in gate2-monotonic.sql) → anchor-incomplete:
G2_19d() { _do_call "$OWNER_TOKEN" "$WRAP" "{\"p_week_num\":8,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_HC,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_domain_reject G2-19d "opening anchor incomplete at week 5"; }

# ══════════════ SUB-PHASE 7 — half-close (wk8 real close, then G2-16b, wk9 close→break→repair) ══════════════
G2_close_w8()  { _do_call "$OWNER_TOKEN" "$WRAP" "{\"p_week_num\":8,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_HC,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_success CLOSE-W8; }
G2_close_w9()  { _do_call "$OWNER_TOKEN" "$WRAP" "{\"p_week_num\":9,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_HC,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_success CLOSE-W9; }
G2_18_repair() { _do_call "$OWNER_TOKEN" "$WRAP" "{\"p_week_num\":9,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_HC,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_repaired G2-18; }
G2_18b_repair(){ _do_call "$OWNER_TOKEN" "$WRAP" "{\"p_week_num\":9,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_HC,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_repaired G2-18b; }
# MANDATORY blocked-advance: while wk9 is incomplete, wk10 cannot close (expected next contiguous week = 9):
G2_block_w10() { _do_call "$OWNER_TOKEN" "$WRAP" "{\"p_week_num\":10,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[],\"p_snapshot_rows\":$NINE_HC,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_domain_reject BLOCKED-W10 "not the next contiguous closeout week"; }

# ══════════════ SUB-PHASE 8/9 — G2-20 atomic rollback (wk10; trigger installed via SQL first) ══════════════
# G2-20a: new closeout wk10 with sentinel snapshot + synthetic commitment CREATE; snapshot INSERT trips trigger → full rollback
G2_20a() { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":10,\"p_model_year\":2026,$B,\"p_new_commitments\":[{\"expected_item_id\":\"__ATOMIC_TEST_WD__\",\"model_year\":2026,\"origin_model_week\":10,\"amount_cents\":100,\"payee\":\"__GATE2_ATOMIC__\",\"commitment_class\":\"other_transfer\",\"required_or_discretionary\":\"discretionary_deployment\"}],\"p_patched\":[],\"p_snapshot_rows\":$NINE_SENTINEL,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_atomic_fail G2-20a; }
# G2-20b: new closeout wk10 with sentinel snapshot + PATCH of the pre-seeded __ATOMIC_TEST_PATCH__ (fill {{PATCH_ID}} from the pre-seed):
G2_20b() { _do_call "$OWNER_TOKEN"  "$WRAP" "{\"p_week_num\":10,\"p_model_year\":2026,$B,\"p_new_commitments\":[],\"p_patched\":[{\"id\":\"{{PATCH_ID}}\",\"amount_cents\":222}],\"p_snapshot_rows\":$NINE_SENTINEL,\"p_mode\":\"normal_closeout\",\"p_expected_count\":9}"; expect_atomic_fail G2-20b; }

echo "Template only — nothing auto-runs. Run gate2_preflight, then invoke a single G2_* function at the runbook step."
