#!/usr/bin/env node
'use strict';
// ════════════════════════════════════════════════════════════════════════════
// 2027 rollover Package C: hermetic server tests (frozen spec v2.1 §13 T-SRV, Gate 1 note N-9).
//
// Runs against a disposable local PostgreSQL (tools/rollover-pg.js): the deployed base objects
// extracted from the repository's own SQL, the documented stand-ins in
// fixtures/rollover/server/standins.sql, and, unless --baseline, the Package C server package
// docs/rollover-2027-server-package-c.sql. All data is synthetic. No remote database is used.
//
//   node test_rollover_server.js              Package C (expected green)
//   node test_rollover_server.js --baseline   the Package B baseline (RED evidence)
// ════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const path = require('path');
const PG = require('./tools/rollover-pg');
const FC = require('./tools/rollover-function-capture');

const REPO = __dirname;
const BASELINE = process.argv.includes('--baseline');
const PKG_PATH = path.join(REPO, 'docs', 'rollover-2027-server-package-c.sql');
const PKG_SQL = fs.readFileSync(PKG_PATH, 'utf8');

const results = [];
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function assert(c, m) { if (!c) throw new Error(m || 'assertion failed'); }

// ── Synthetic fixture (no household values) ─────────────────────────────────
const UID = '00000000-0000-4000-8000-000000000001';
const PRE = "SET request.jwt.claim.sub = '" + UID + "'; SET test.role = 'owner';\n";
// The 2026 tracked set R(2026): the nine goals the deployed wrapper hard-codes (identifiers only).
const NINE = ['adam_ira', 'alaska', 'bailey_529', 'bryce_529', 'bryce_vehicle', 'christmas_cruise', 'preston_529', 'wendy_ira', 'wendy_sep'];
const v26 = (g, w) => 1000 + 10 * w + NINE.indexOf(g);          // monotonic per goal
const rows26 = (w, f) => Object.fromEntries(NINE.map(g => [g, f ? f(g, w) : v26(g, w)]));
const S27 = { adam_ira_2027: 'carry:adam_ira', alaska_2027: 'carry:alaska;reason=synthetic stated reason', roof_2027: 'new' };
const OPEN27 = { adam_ira_2027: v26('adam_ira', 30), alaska_2027: 50, roof_2027: 0 };
const rows31 = (bump) => ({ adam_ira_2027: OPEN27.adam_ira_2027 + (bump || 5), alaska_2027: 60, roof_2027: 10 });

function seed2026(through, opt) {
  opt = opt || {};
  let s = "INSERT INTO auth.users VALUES ('" + UID + "');\n";
  s += "INSERT INTO public.goal_registry (id, status) VALUES " + NINE.map(g => "('" + g + "','funding')").join(',') + ",('legacy_x','funding');\n";
  s += "INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note) VALUES "
    + NINE.map(g => "(2026,5,'" + g + "'," + v26(g, 5) + ",'opening_anchor','synthetic opening')").join(',') + ";\n";
  for (let w = 6; w <= through; w++) {
    s += "INSERT INTO public.weekly_reconciliations (week_num, chk, sav, amx, tax, lc, balance_basis, recorded_at) VALUES (" + w + ",100,200,300,0,400,'posted_current_balance',now());\n";
    const goals = (opt.partial && opt.partial[w]) ? NINE.slice(0, opt.partial[w]) : NINE;
    s += "INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES "
      + goals.map(g => "(2026," + w + ",'" + g + "'," + v26(g, w) + ",'reconciliation')").join(',') + ";\n";
  }
  return s;
}
// The 2027 opening state as initialization (Package F) would leave it; written here directly.
function init2027(o) {
  o = o || {};
  const notes = Object.assign({}, S27, o.notes || {}), vals = Object.assign({}, OPEN27, o.values || {});
  const ids = Object.keys(notes);
  let s = "INSERT INTO public.goal_registry (id, status) VALUES " + ids.map(g => "('" + g + "','" + ((o.status27 || {})[g] || 'funding') + "')").join(',') + ";\n";
  s += "INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note) VALUES "
    + ids.map(g => "(2027,30,'" + g + "'," + vals[g] + ",'opening_anchor'," + (notes[g] === null ? 'NULL' : "'" + notes[g] + "'") + ")").join(',') + ";\n";
  const carried = Object.values(notes).map(n => (/^carry:([a-z0-9_]+)/.exec(n || '') || [])[1]).filter(Boolean);
  const closed = NINE.filter(g => carried.indexOf(g) < 0);
  const st = Object.assign(Object.fromEntries(closed.map(g => [g, 'executed'])), o.status26 || {});
  Object.entries(st).forEach(([g, v]) => { s += "UPDATE public.goal_registry SET status = '" + v + "' WHERE id = '" + g + "';\n"; });
  return s;
}
function closeSql(week, year, rows, o) {
  o = o || {};
  const snap = JSON.stringify(Object.entries(rows).map(([g, a]) => ({ goal_id: g, funded_amount: a })));
  const exp = o.expected !== undefined ? o.expected : Object.keys(rows).length;
  return "SELECT public.save_weekly_closeout_with_snapshots(" + week + "," + year + "," + (o.chk !== undefined ? o.chk : 100)
    + ",200,300,0,400,'posted_current_balance','" + JSON.stringify(o.nc || []) + "'::jsonb,'" + JSON.stringify(o.patched || [])
    + "'::jsonb,'" + snap + "'::jsonb,'" + (o.mode || 'normal_closeout') + "'," + exp + ");";
}
function corrSql(year, week, goal, amt, prior, note) {
  return "SELECT public.correct_goal_funding_snapshot(" + year + "," + week + ",'" + goal + "'," + amt + "," + prior + ",'" + (note || 'synthetic correction') + "');";
}
function commitSql(id, my, origin) {
  return "INSERT INTO public.cash_commitments (id, expected_item_id, model_year, origin_model_week, payee, commitment_class, required_or_discretionary, amount_cents, status) VALUES ('"
    + id + "','synth_" + id.slice(-4) + "'," + my + "," + origin + ",'SYNTH PAYEE','bill_payment','protected_required',12345,'planned');";
}

let db, tpl;
function fresh(seed) {
  const name = PG.cloneFrom(db, tpl);
  if (seed) { const r = db.sql(PRE + seed, name); if (!r.ok) throw new Error('fixture failed: ' + r.err); }
  return {
    name,
    q(sql) { return db.sql(PRE + sql, name); },
    ok(sql, label) { const r = db.sql(PRE + sql, name); if (!r.ok) throw new Error((label || 'call') + ' failed: ' + r.err); return r.out; },
    fails(sql, re, label) {
      const r = db.sql(PRE + sql, name);
      if (r.ok) throw new Error((label || 'call') + ' should have raised but succeeded: ' + r.out);
      if (re && !re.test(r.err)) throw new Error((label || 'call') + ' raised for the wrong reason: ' + r.err);
      return r.err;
    },
    val(sql) { const r = db.sql(PRE + sql, name); if (!r.ok) throw new Error(r.err); return r.out; },
    session(sql) { return db.session(PRE + sql, name); },
  };
}
const anchors27 = t => t.val("SELECT string_agg(goal_id||'|'||funded_amount||'|'||source||'|'||coalesce(note,'')||'|'||updated_at, ';' ORDER BY goal_id) FROM goal_funding_snapshots WHERE model_year=2027 AND week_num=30;");

// ── Tests ───────────────────────────────────────────────────────────────────
test('T-SRV-1 week 30 closes as 2026 while 2027 opening snapshots exist (robustness outside the normal O4 sequence)', () => {
  const t = fresh(seed2026(29) + init2027());
  const before = anchors27(t);
  t.ok(closeSql(30, 2026, rows26(30)), 'week-30 close');
  assert(t.val("SELECT count(*) FROM goal_funding_snapshots WHERE model_year=2026 AND week_num=30;") === '9', 'week 30 holds the nine 2026 rows');
  assert(anchors27(t) === before, 'the 2027 opening anchors are untouched');
});

test('T-SRV-2 week 31 without opening state raises; with it and a passing re-verification, succeeds', () => {
  const a = fresh(seed2026(30));
  a.fails(closeSql(31, 2027, rows31()), /opening|model_year/i, 'week 31 without opening state');
  assert(a.val('SELECT count(*) FROM weekly_reconciliations WHERE week_num=31;') === '0', 'a refused close leaves no reconciliation');
  const b = fresh(seed2026(30) + init2027());
  const r = JSON.parse(b.ok(closeSql(31, 2027, rows31()), 'week-31 close'));
  assert(r.ok === true && r.week_num === 31 && r.snapshot_count === 3, 'result ' + JSON.stringify(r));
  assert(b.val("SELECT string_agg(goal_id||'='||funded_amount, ',' ORDER BY goal_id) FROM goal_funding_snapshots WHERE model_year=2027 AND week_num=31 AND source='reconciliation';")
    === 'adam_ira_2027=1305.00,alaska_2027=60.00,roof_2027=10.00', 'week 31 rows');
});

test('T-SRV-3 contiguity is proven: out-of-order close raises, a gap is named, the earliest half-close repair works', () => {
  const a = fresh(seed2026(20));
  a.fails(closeSql(22, 2026, rows26(22)), /next contiguous/, 'closing a week before its predecessor');
  // Gap fixture: week 15 is reconciled with 4 of 9 snapshots; weeks 16-20 are complete.
  const g = fresh(seed2026(20, { partial: { 15: 4 } }));
  g.fails(closeSql(21, 2026, rows26(21)), /\b15\b/, 'a new close with a gap below');
  g.fails(closeSql(20, 2026, rows26(20)), /\b15\b/, 'an idempotent retry above a gap');
  const r = JSON.parse(g.ok(closeSql(15, 2026, rows26(15)), 'half-close repair of the earliest incomplete week'));
  assert(r.repaired === true, 'repair result ' + JSON.stringify(r));
  g.ok(closeSql(21, 2026, rows26(21)), 'the next close once the gap is repaired');
});

test('T-SRV-4 a p_model_year mismatch raises (closeout, reconciliation and correction)', () => {
  const t = fresh(seed2026(30) + init2027());
  t.fails(closeSql(31, 2026, rows26(31)), /model_year/, 'week 31 as 2026');
  t.fails(closeSql(30, 2027, rows31()), /model_year/, 'week 30 as 2027');
  t.fails("SELECT public.save_reconciliation_with_commitments(31,2026,1,2,3,0,4,'posted_current_balance',now(),'[]','[]');", /model_year/, 'reconciliation for week 31 as 2026');
  t.fails(corrSql(2027, 20, 'adam_ira', v26('adam_ira', 20) + 1, v26('adam_ira', 20)), /model_year/, 'correction of week 20 as 2027');
  assert(t.val('SELECT count(*) FROM weekly_reconciliations WHERE week_num=31;') === '0', 'nothing written');
});

test('T-SRV-5 2026 goal IDs submitted for week 31 raise', () => {
  const t = fresh(seed2026(30) + init2027());
  t.fails(closeSql(31, 2027, rows26(31)), /adam_ira\b.*not tracked in plan 2027/, 'nine 2026 IDs for week 31');
  t.fails(closeSql(31, 2027, Object.assign(rows31(), { adam_ira: 2000 }), { expected: 4 }), /not tracked in plan 2027/, 'a 2026 ID mixed into the 2027 set');
  t.ok(closeSql(31, 2027, rows31()), 'the 2027 set closes');
});

test('T-SRV-6 the cross-year patch succeeds and keeps model_year 2026 and origin unchanged', () => {
  const id = '11111111-1111-4111-8111-000000000006';
  const t = fresh(seed2026(30) + init2027() + commitSql(id, 2026, 30));
  const patch = [{ id, status: 'cleared', reflected_model_week: 31, resolved_model_week: 31, resolution_type: 'cleared' }];
  t.ok(closeSql(31, 2027, rows31(), { patched: patch }), 'week-31 close with a patch to a 2026 commitment');
  assert(t.val("SELECT model_year||'|'||origin_model_week||'|'||status||'|'||resolved_model_week FROM cash_commitments WHERE id='" + id + "';") === '2026|30|cleared|31', 'patched row');
});

test('T-SRV-7 a future-plan-year patch raises', () => {
  const id = '11111111-1111-4111-8111-000000000007';
  const t = fresh(seed2026(29) + "INSERT INTO public.cash_commitments (id, expected_item_id, model_year, origin_model_week, payee, commitment_class, required_or_discretionary, amount_cents, status) VALUES ('" + id + "','synth_fut7',2027,31,'SYNTH PAYEE','bill_payment','protected_required',12345,'planned');");
  t.fails(closeSql(30, 2026, rows26(30), { patched: [{ id, status: 'voided', resolved_model_week: 30, resolution_type: 'voided', resolution_notes: 'x' }] }), /not found|model_year/, 'week-30 close patching a 2027 commitment');
  t.fails("SELECT public.save_reconciliation_with_commitments(30,2026,1,2,3,0,4,'posted_current_balance',now(),'[]','[{\"id\":\"" + id + "\",\"notes\":\"x\"}]');", /not found|model_year/, 'reconciliation patching a 2027 commitment');
  assert(t.val("SELECT coalesce(notes,'')||'|'||status FROM cash_commitments WHERE id='" + id + "';") === '|planned', 'the 2027 commitment is unchanged');
});

test('T-SRV-8 the P-Y1 and P-Y2 table checks reject violating rows', () => {
  const t = fresh(seed2026(6));
  t.fails(commitSql('11111111-1111-4111-8111-000000000081', 2027, 20), /chk_cc_plan_year/, 'P-Y1: plan 2027 commitment from week 20');
  t.fails(commitSql('11111111-1111-4111-8111-000000000082', 2026, 31), /chk_cc_plan_year/, 'P-Y1: plan 2026 commitment from week 31');
  t.ok(commitSql('11111111-1111-4111-8111-000000000083', 2027, 31), 'P-Y1: plan 2027 commitment from week 31');
  t.ok(commitSql('11111111-1111-4111-8111-000000000084', 2027, 40), 'weeks beyond 31 are allowed (>= 1)');
  t.ok("INSERT INTO goal_registry (id) VALUES ('synth_a_2027'),('synth_b_2027');", 'registry');
  t.fails("INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES (2027,20,'synth_a_2027',1,'reconciliation');", /chk_gfs_plan_year/, 'P-Y2: plan 2027 row at week 20');
  t.fails("INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES (2027,31,'synth_a_2027',1,'opening_anchor');", /chk_gfs_plan_year/, 'P-Y2: plan 2027 opening anchor at week 31');
  t.ok("INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note) VALUES (2027,30,'synth_a_2027',1,'opening_anchor','new');", 'P-Y2: plan 2027 opening anchor at week 30');
  t.ok("INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES (2027,40,'synth_b_2027',1,'reconciliation');", 'P-Y2: plan 2027 row at week 40');
  t.ok("INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES (2026,5,'legacy_x',1,'correction');", 'P-Y2: a correction row at the 2026 opening week (as production holds)');
});

test('T-SRV-9 the monotonic check runs against the opening snapshot', () => {
  const t = fresh(seed2026(30) + init2027());
  t.fails(closeSql(31, 2027, Object.assign(rows31(), { adam_ira_2027: OPEN27.adam_ira_2027 - 0.01 })), /monotonic violation: adam_ira_2027/, 'below the opening value');
  t.ok(closeSql(31, 2027, Object.assign(rows31(), { adam_ira_2027: OPEN27.adam_ira_2027 })), 'equal to the opening value');
});

test('T-SRV-10 correction at the opening position raises; correction at a 2027 closeable week succeeds', () => {
  const t = fresh(seed2026(30) + init2027());
  t.ok(closeSql(31, 2027, rows31()), 'week-31 close');
  t.fails(corrSql(2027, 30, 'adam_ira_2027', 1400, OPEN27.adam_ira_2027), /model_year|opening/, 'plan 2027 opening position');
  t.fails(corrSql(2026, 5, 'adam_ira', 1100, v26('adam_ira', 5)), /opening position/, 'plan 2026 opening position');
  const r = JSON.parse(t.ok(corrSql(2027, 31, 'adam_ira_2027', 1310, 1305), 'correction at week 31'));
  assert(r.corrected === true, JSON.stringify(r));
  assert(t.val("SELECT funded_amount||'|'||source FROM goal_funding_snapshots WHERE model_year=2027 AND week_num=31 AND goal_id='adam_ira_2027';") === '1310.00|correction', 'corrected row');
  t.fails(corrSql(2027, 31, 'alaska_2027', 49, 60), /below preceding effective value/, 'a correction below the opening value');
});

test('T-SRV-11 reopen of the latest week works across plan years', () => {
  const t = fresh(seed2026(30) + init2027());
  t.ok(closeSql(30, 2026, rows26(30), { mode: 'approved_reopen', chk: 101 }), 'reopen week 30 while it is the latest');
  t.ok(closeSql(31, 2027, rows31()), 'week-31 close');
  t.fails(closeSql(30, 2026, rows26(30), { mode: 'approved_reopen', chk: 102 }), /not the latest completed week \(latest=31\)/, 'reopen week 30 once week 31 is closed');
  const r = JSON.parse(t.ok(closeSql(31, 2027, rows31(), { mode: 'approved_reopen', chk: 150 }), 'reopen week 31'));
  assert(r.reopened === true && t.val('SELECT chk FROM weekly_reconciliations WHERE week_num=31;') === '150', 'week 31 reopened');
});

test('T-SRV-12 closeout cannot create, overwrite or modify an opening_anchor row, and cannot write at the opening position', () => {
  const t = fresh(seed2026(29) + init2027());
  const before = anchors27(t);
  t.fails(closeSql(5, 2026, rows26(5)), /opening anchor|legacy|not the next/, 'closeout of the 2026 opening week');
  t.fails(closeSql(30, 2027, rows31()), /model_year/, 'closeout at the 2027 opening position');
  t.ok(closeSql(30, 2026, rows26(30)), 'week-30 close');
  // With week 30 reconciled, the snapshot function itself must still refuse both writes.
  t.fails("SELECT public.save_goal_funding_snapshots(2027,30,'[{\"goal_id\":\"adam_ira_2027\",\"funded_amount\":9999,\"source\":\"opening_anchor\"}]');", /opening/, 'snapshot write of an opening anchor');
  t.fails("SELECT public.save_goal_funding_snapshots(2027,30,'[{\"goal_id\":\"adam_ira_2027\",\"funded_amount\":9999,\"source\":\"reconciliation\"}]');", /opening position/, 'snapshot write at the opening position');
  t.ok(closeSql(31, 2027, rows31()), 'week-31 close');
  t.fails("SELECT public.save_goal_funding_snapshots(2027,31,'[{\"goal_id\":\"adam_ira_2027\",\"funded_amount\":9999,\"source\":\"opening_anchor\"}]');", /chk_gfs_plan_year/, 'an opening anchor outside the opening position (overwriting a week-31 row)');
  assert(anchors27(t) === before, 'the opening anchors are byte-identical after the closes');
});

test('T-SRV-15 the closeout wrapper and the correction function raise when a tracked goal is archived', () => {
  const a = fresh(seed2026(20) + "UPDATE goal_registry SET status='archived' WHERE id='wendy_sep';");
  a.fails(closeSql(21, 2026, rows26(21)), /archived contradiction: goal wendy_sep/, '2026 close');
  a.fails(corrSql(2026, 20, 'adam_ira', v26('adam_ira', 20), v26('adam_ira', 20)), /archived contradiction/, '2026 correction');
  const b = fresh(seed2026(30) + init2027({ status27: { roof_2027: 'archived' } }));
  b.fails(closeSql(31, 2027, rows31()), /archived contradiction: goal roof_2027/, '2027 first close');
  const c = fresh(seed2026(20) + "UPDATE goal_registry SET status='archived' WHERE id='legacy_x';");
  c.ok(closeSql(21, 2026, rows26(21)), 'an archived goal that is not tracked does not block');
});

test('T-SRV-16 re-verification scope by branch (OD-3) and the R(Y) source filter', () => {
  // New first close: a failing predecessor condition raises (IP-5, IP-4/IP-6, IP-3, grammar).
  fresh(seed2026(30) + init2027({ values: { adam_ira_2027: 1 } })).fails(closeSql(31, 2027, rows31()), /IP-5/, 'IP-5 carried value without a reason');
  fresh(seed2026(30) + init2027({ status26: { bailey_529: 'funded' } })).fails(closeSql(31, 2027, rows31()), /IP-4\/IP-6\): bailey_529/, 'IP-6 closed predecessor not final');
  fresh(seed2026(30) + init2027({ notes: { roof_2027: 'carry:alaska' } })).fails(closeSql(31, 2027, rows31()), /IP-4\): alaska is carried by more than one/, 'IP-4 two successors');
  fresh(seed2026(30) + init2027({ notes: { roof_2027: 'carry:legacy_x' } })).fails(closeSql(31, 2027, rows31()), /IP-4\): roof_2027 names legacy_x/, 'IP-4 untracked predecessor');
  fresh(seed2026(30) + init2027({ notes: { roof_2027: 'Carry:alaska' } })).fails(closeSql(31, 2027, rows31()), /anchor-note grammar/, 'grammar');
  fresh(seed2026(30) + init2027({ notes: { roof_2027: null } })).fails(closeSql(31, 2027, rows31()), /anchor-note grammar/, 'grammar: a null note');
  fresh(seed2026(30) + init2027({ notes: { roof_2027: 'carry:alaska;reason=' } })).fails(closeSql(31, 2027, rows31()), /anchor-note grammar/, 'grammar: an empty reason');
  fresh(seed2026(30) + init2027() + "INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES (2026,29,'roof_2027',1,'correction');")
    .fails(closeSql(31, 2027, rows31()), /IP-3\): roof_2027/, 'IP-3 successor with a 2026 snapshot');
  fresh(seed2026(30) + init2027({ notes: { alaska_2027: 'carry:alaska' }, values: { alaska_2027: v26('alaska', 30) } })).ok(closeSql(31, 2027, Object.assign(rows31(), { alaska_2027: v26('alaska', 30) })), 'clean carry passes');
  // Half-close repair of week 31 runs them.
  const h = fresh(seed2026(30) + init2027() + "INSERT INTO weekly_reconciliations (week_num, chk, sav, amx, tax, lc, balance_basis, recorded_at) VALUES (31,100,200,300,0,400,'posted_current_balance',now());"
    + "INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES (2027,31,'roof_2027',10,'reconciliation');");
  h.ok("UPDATE goal_registry SET status='funded' WHERE id='bailey_529';");
  h.fails(closeSql(31, 2027, rows31()), /IP-4\/IP-6\): bailey_529/, 'half-close repair with a failing condition');
  h.ok("UPDATE goal_registry SET status='executed' WHERE id='bailey_529';");
  assert(JSON.parse(h.ok(closeSql(31, 2027, rows31()), 'half-close repair')).repaired === true, 'repair completes');
  // An idempotent retry and an approved_reopen do not run them, after a later authorized 2026 correction.
  const t = fresh(seed2026(30) + init2027());
  t.ok(closeSql(31, 2027, rows31()), 'week-31 close');
  t.ok(corrSql(2026, 30, 'adam_ira', v26('adam_ira', 30) + 7, v26('adam_ira', 30)), 'later authorized 2026 correction of the carried predecessor');
  assert(JSON.parse(t.ok(closeSql(31, 2027, rows31()), 'idempotent retry')).idempotent === true, 'idempotent retry succeeds');
  assert(JSON.parse(t.ok(closeSql(31, 2027, rows31(), { mode: 'approved_reopen', chk: 140 }), 'approved_reopen')).reopened === true, 'reopen succeeds');
  // R(2026) comes from opening_anchor rows only: a correction row at week 5 is not an opening snapshot.
  const k = fresh(seed2026(20) + "INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES (2026,5,'legacy_x',1,'correction');");
  k.ok(closeSql(21, 2026, rows26(21)), 'the nine still close with a correction row at week 5');
});

test('T-SRV-17 stable predecessor state in two concurrent sessions (OD-4)', async () => {
  const HOLD = "SELECT pg_sleep(1.2);";
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const waits = [];
  // (a) close first; a 2026 correction of a carried predecessor waits for it, then applies (serial order).
  {
    const t = fresh(seed2026(30) + init2027());
    const s1 = t.session('BEGIN; ' + closeSql(31, 2027, rows31()) + HOLD + ' COMMIT;');
    await wait(300);
    const s2 = t.session(corrSql(2026, 30, 'adam_ira', v26('adam_ira', 30) + 7, v26('adam_ira', 30)));
    const [r1, r2] = await Promise.all([s1, s2]);
    assert(r1.ok && r2.ok, 'both commit: ' + r1.err + ' / ' + r2.err);
    assert(r2.ms >= 600, 'the correction waited for the close (' + r2.ms + ' ms)'); waits.push('correction behind close ' + r2.ms + 'ms');
    assert(t.val("SELECT count(*) FROM goal_funding_snapshots WHERE model_year=2027 AND week_num=31;") === '3', 'close committed');
  }
  // (b) correction first; the close waits, then its re-verification sees the changed final value (serial order).
  {
    const t = fresh(seed2026(30) + init2027());
    const s2 = t.session('BEGIN; ' + corrSql(2026, 30, 'adam_ira', v26('adam_ira', 30) + 7, v26('adam_ira', 30)) + HOLD + ' COMMIT;');
    await wait(300);
    const s1 = t.session(closeSql(31, 2027, rows31()));
    const [r2, r1] = await Promise.all([s2, s1]);
    assert(r2.ok && !r1.ok && /IP-5/.test(r1.err), 'correction commits; the close then fails IP-5: ' + r1.err);
    assert(r1.ms >= 600, 'the close waited for the correction (' + r1.ms + ' ms)'); waits.push('close behind correction ' + r1.ms + 'ms, then IP-5');
    assert(t.val('SELECT count(*) FROM weekly_reconciliations WHERE week_num=31;') === '0', 'no partial close');
  }
  // (c) a week-30 reopen started during the first close waits, then is refused (week 31 is now the latest).
  {
    const t = fresh(seed2026(30) + init2027());
    const s1 = t.session('BEGIN; ' + closeSql(31, 2027, rows31()) + HOLD + ' COMMIT;');
    await wait(300);
    const s2 = t.session(closeSql(30, 2026, rows26(30), { mode: 'approved_reopen', chk: 103 }));
    const [r1, r2] = await Promise.all([s1, s2]);
    assert(r1.ok && !r2.ok && /latest=31/.test(r2.err) && r2.ms >= 600, 'reopen waited and was refused: ' + r2.err); waits.push('week-30 reopen behind close ' + r2.ms + 'ms, then refused');
  }
  // (d) an initialization reversal racing the first close. The reversal is Package F; this stand-in
  //     follows its frozen lock order (plan Y rows FOR UPDATE, then plan Y-1 rows) and its abort guard.
  const REVERSAL = "BEGIN; SELECT 1 FROM goal_registry WHERE id IN ('adam_ira_2027','alaska_2027','roof_2027') ORDER BY id FOR UPDATE;"
    + " SELECT 1 FROM goal_registry WHERE id IN (" + NINE.map(g => "'" + g + "'").join(',') + ") ORDER BY id FOR UPDATE;"
    + " DO $$ BEGIN IF EXISTS (SELECT 1 FROM weekly_reconciliations WHERE week_num >= 31) THEN RAISE EXCEPTION 'reversal refused: week 31 is closed'; END IF; END $$;"
    + " DELETE FROM goal_funding_snapshots WHERE model_year=2027 AND week_num=30 AND source='opening_anchor';";
  {
    const t = fresh(seed2026(30) + init2027());
    const sR = t.session(REVERSAL + HOLD + ' COMMIT;');
    await wait(300);
    const s1 = t.session(closeSql(31, 2027, rows31()));
    const [rR, r1] = await Promise.all([sR, s1]);
    assert(rR.ok && !r1.ok && /opening state of plan 2027 changed|no opening state/.test(r1.err), 'reversal first, then the close fails: ' + r1.err); waits.push('close behind reversal ' + r1.ms + 'ms, then re-derive mismatch');
  }
  {
    const t = fresh(seed2026(30) + init2027());
    const s1 = t.session('BEGIN; ' + closeSql(31, 2027, rows31()) + HOLD + ' COMMIT;');
    await wait(300);
    const sR = t.session(REVERSAL + ' COMMIT;');
    const [r1, rR] = await Promise.all([s1, sR]);
    assert(r1.ok && !rR.ok && /reversal refused/.test(rR.err) && rR.ms >= 600, 'close first, then the reversal is refused: ' + rR.err); waits.push('reversal behind close ' + rR.ms + 'ms, then refused');
    assert(t.val("SELECT count(*) FROM goal_funding_snapshots WHERE model_year=2027 AND week_num=30;") === '3', 'anchors remain');
  }
  // (e) lock modes and exactness while a first close holds its locks: R(2027) FOR UPDATE,
  //     exactly R(2026) FOR SHARE, nothing else.
  {
    const t = fresh(seed2026(30) + init2027());
    const s1 = t.session('BEGIN; ' + closeSql(31, 2027, rows31()) + HOLD + ' COMMIT;');
    await wait(300);
    const probe = (id, mode) => t.q("BEGIN; SELECT 1 FROM goal_registry WHERE id='" + id + "' FOR " + mode + " NOWAIT; ROLLBACK;").ok;
    const p = {
      r27share: probe('roof_2027', 'SHARE'), r26share: probe('adam_ira', 'SHARE'), r26update: probe('bailey_529', 'UPDATE'),
      otherUpdate: probe('legacy_x', 'UPDATE'),
    };
    const r1 = await s1;
    assert(r1.ok, r1.err);
    assert(!p.r27share, 'R(2027) is held FOR UPDATE');
    assert(p.r26share && !p.r26update, 'R(2026) is held FOR SHARE');
    assert(p.otherUpdate, 'a goal outside R(2026) and R(2027) is not locked');
  }
  // (f) the OD-4 order in the server package: derive, lock R(Y) in identifier order, re-derive and
  //     assert, then share-lock R(Y-1) in identifier order, then the IP reads.
  {
    const w = PKG_SQL.slice(PKG_SQL.indexOf('FUNCTION public.save_weekly_closeout_with_snapshots'), PKG_SQL.indexOf('FUNCTION public.correct_goal_funding_snapshot'));
    const at = s => { const i = w.indexOf(s); assert(i >= 0, 'missing step: ' + s); return i; };
    const steps = [at('pg_advisory_xact_lock'), at('INTO v_elig\n'), at('ORDER BY id FOR UPDATE'), at('INTO v_elig2'), at('v_elig2 IS DISTINCT FROM v_elig'), at('ORDER BY id FOR SHARE'), at('IP-2 (first-close form)')];
    assert(steps.every((x, i) => i === 0 || x > steps[i - 1]), 'OD-4 order ' + steps.join(','));
  }
  // (g) no deadlock across the pairings above (each pairing ended in commit or a fail-closed raise, never 40P01).
  console.log('    two-session evidence: ' + waits.join('; '));
});

test('X-N9 the new helpers revoke EXECUTE from PUBLIC, anon and authenticated, with no client grant', () => {
  const st = FC.checkHelperRevokes(PKG_SQL, ['plan_year_of_week', 'opening_week_of_plan']);
  assert(st.every(x => x.pass), 'static: ' + JSON.stringify(st));
  const t = fresh('');
  ['plan_year_of_week', 'opening_week_of_plan'].forEach(f => {
    const acl = t.val("SELECT coalesce(array_to_string(proacl, ','), '<default>') FROM pg_proc WHERE proname='" + f + "';");
    assert(acl !== '<default>' && !/(^|,)=X/.test(acl) && !/anon=|authenticated=/.test(acl), f + ' ACL ' + acl);
    ['anon', 'authenticated'].forEach(r => assert(t.val("SELECT has_function_privilege('" + r + "','public." + f + "(int)','EXECUTE');") === 'f', f + ' callable by ' + r));
  });
});

// ── Supporting tests added after the Fable review (owner disposition 2026-10-08); not contracts ──
test('PKGC-NB1-BLANK-REASON a whitespace-only stated reason is not a reason (§7.4: an empty reason is not permitted)', () => {
  ['carry:alaska;reason= ', 'carry:alaska;reason=     ', 'carry:alaska;reason=\t', 'carry:alaska;reason= \t '].forEach(n =>
    fresh(seed2026(30) + init2027({ notes: { alaska_2027: n } })).fails(closeSql(31, 2027, rows31()), /anchor-note grammar/, JSON.stringify(n)));
  fresh(seed2026(30) + init2027({ notes: { alaska_2027: 'carry:alaska;reason= a stated reason' } })).ok(closeSql(31, 2027, rows31()), 'a nonblank reason passes');
});

test('PKGC-NEVER-BOTH a carried predecessor whose status is executed or archived fails IP-4', () => {
  ['executed', 'archived'].forEach(st =>
    fresh(seed2026(30) + init2027({ status26: { adam_ira: st } })).fails(closeSql(31, 2027, rows31()), new RegExp('IP-4\\): adam_ira is both carried and closed \\(status ' + st + '\\)'), st));
});

test('PKGC-LATER-CLOSE an ordinary later close (week 32) does not rerun the first-close checks', () => {
  const t = fresh(seed2026(30) + init2027());
  t.ok(closeSql(31, 2027, rows31()), 'week-31 close');
  // State that would fail a first close: a closed predecessor no longer final, and a note outside the grammar.
  t.ok("UPDATE goal_registry SET status='funded' WHERE id='bailey_529'; UPDATE goal_funding_snapshots SET note='Carry:x' WHERE model_year=2027 AND week_num=30 AND goal_id='roof_2027';");
  t.ok(closeSql(32, 2027, { adam_ira_2027: 1306, alaska_2027: 61, roof_2027: 11 }), 'week-32 close');
});

test('PKGC-2028-BOUNDARY the next boundary works end to end with no 2027 special case', () => {
  let fill = '';
  for (let w = 31; w <= 81; w++) fill += "INSERT INTO weekly_reconciliations (week_num, chk, sav, amx, tax, lc, balance_basis, recorded_at) VALUES (" + w + ",100,200,300,0,400,'posted_current_balance',now());"
    + "INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES (2027," + w + ",'adam_ira_2027'," + (1300 + w) + ",'reconciliation'),(2027," + w + ",'alaska_2027'," + (50 + w) + ",'reconciliation'),(2027," + w + ",'roof_2027'," + w + ",'reconciliation');\n";
  const t = fresh(seed2026(30) + init2027() + fill);
  const r82 = { adam_ira_2027: 1382, alaska_2027: 132, roof_2027: 82 };
  t.fails(closeSql(82, 2028, r82), /model_year/, 'week 82 as 2028');
  t.ok(closeSql(82, 2027, r82), 'week 82 (2027 Wk 52) as 2027');
  t.fails(closeSql(83, 2028, { adam_ira_2028: 1390 }), /no opening state for plan 2028: no opening anchors at week 82/, 'week 83 without 2028 opening state');
  t.ok("INSERT INTO goal_registry (id) VALUES ('adam_ira_2028');"
    + "INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note) VALUES (2028,82,'adam_ira_2028',1382,'opening_anchor','carry:adam_ira_2027');"
    + "UPDATE goal_registry SET status='executed' WHERE id IN ('alaska_2027','roof_2027');", '2028 opening state at week 82');
  const r = JSON.parse(t.ok(closeSql(83, 2028, { adam_ira_2028: 1390 }), 'week 83 (2028 Wk 1), the 2028 first close'));
  assert(r.ok === true && r.snapshot_count === 1, JSON.stringify(r));
  t.fails("INSERT INTO goal_registry (id) VALUES ('late_2028'); INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note) VALUES (2028,83,'late_2028',1,'opening_anchor','new');", /chk_gfs_plan_year/, 'a 2028 opening anchor at week 83');
});

test('PKGC-HELPER-MIRROR the SQL period helpers equal the §3 oracle (Package A cal) over weeks 1-1500 and plans 2026-2055', () => {
  const K = require('./tools/rollover-test-kit');
  const t = fresh('');
  const py = JSON.parse(t.val('SELECT json_agg(plan_year_of_week(w) ORDER BY w) FROM generate_series(1,1500) w;'));
  const ow = JSON.parse(t.val('SELECT json_agg(opening_week_of_plan(y) ORDER BY y) FROM generate_series(2026,2055) y;'));
  const bad = [];
  py.forEach((v, i) => { if (v !== K.cal.planYearOfWeek(i + 1)) bad.push('week ' + (i + 1)); });
  ow.forEach((v, i) => { if (v !== K.cal.openingWeekOfPlan(2026 + i)) bad.push('plan ' + (2026 + i)); });
  assert(!bad.length, 'mismatches: ' + bad.slice(0, 10).join(', '));
  assert(t.val('SELECT coalesce(plan_year_of_week(0)::text,\'null\')||\'|\'||coalesce(opening_week_of_plan(2025)::text,\'null\');') === 'null|null', 'outside the domain: NULL (and the table checks treat NULL as a violation)');
});

test('PKGC-W30-HALF-CLOSED a first close with week 30 only half-closed is refused until the week-30 repair, then succeeds', () => {
  const t = fresh(seed2026(30, { partial: { 30: 4 } }) + init2027());
  t.fails(closeSql(31, 2027, rows31()), /not the next contiguous closeout week \(expected 30\)/, 'week-31 close over a half-closed week 30');
  assert(JSON.parse(t.ok(closeSql(30, 2026, rows26(30)), 'week-30 half-close repair')).repaired === true, 'repair');
  t.ok(closeSql(31, 2027, rows31()), 'week-31 close after the repair');
});

test('PKGC-NEW-COMMITMENT-2027 a new commitment created at the week-31 close is plan 2027 with origin 31', () => {
  const nc = m => [{ expected_item_id: 'synth_nc31_' + m, model_year: m, origin_model_week: 31, amount_cents: 500, payee: 'SYNTH', commitment_class: 'bill_payment', required_or_discretionary: 'protected_required' }];
  fresh(seed2026(30) + init2027()).fails(closeSql(31, 2027, rows31(), { nc: nc(2026) }), /commitment model_year \(2026\) != p_model_year \(2027\)/, 'a plan-2026 commitment from week 31');
  const t = fresh(seed2026(30) + init2027());
  t.ok(closeSql(31, 2027, rows31(), { nc: nc(2027) }), 'week-31 close with a new commitment');
  assert(t.val("SELECT model_year||'|'||origin_model_week FROM cash_commitments WHERE expected_item_id='synth_nc31_2027';") === '2027|31', 'new commitment row');
});

// ── Atomicity (supporting evidence): a failure after the reconciliation write leaves nothing ──
test('PKGC-ATOMIC a first close that fails after its reconciliation and commitment writes leaves no partial state', () => {
  const id = '11111111-1111-4111-8111-0000000000a1';
  const t = fresh(seed2026(30) + init2027() + commitSql(id, 2026, 30) + "UPDATE goal_registry SET auto = true WHERE id = 'roof_2027';");
  const fp = () => t.val("SELECT md5(coalesce(string_agg(x, ';' ORDER BY x),'')) FROM (SELECT 'r'||week_num||'|'||chk AS x FROM weekly_reconciliations UNION ALL SELECT 's'||model_year||'|'||week_num||'|'||goal_id||'|'||funded_amount||'|'||source||'|'||coalesce(note,'')||'|'||updated_at FROM goal_funding_snapshots UNION ALL SELECT 'c'||id||'|'||status||'|'||coalesce(resolved_model_week,0)||'|'||updated_at FROM cash_commitments) q;");
  const before = fp();
  const nc = [{ expected_item_id: 'synth_new31', model_year: 2027, origin_model_week: 31, amount_cents: 500, payee: 'SYNTH', commitment_class: 'bill_payment', required_or_discretionary: 'protected_required' }];
  const patch = [{ id, status: 'cleared', reflected_model_week: 31, resolved_model_week: 31, resolution_type: 'cleared' }];
  t.fails(closeSql(31, 2027, rows31(), { nc, patched: patch }), /auto goal/, 'the snapshot write fails after the reconciliation write');
  assert(fp() === before, 'reconciliation, snapshots and commitments are exactly as before');
});

// ── 2026 parity (supporting evidence, not a registry contract) ──────────────
test('PKGC-2026-PARITY the 2026 closeout, reopen, repair and correction outcomes equal the baseline', () => {
  const script = [
    ['close 6', closeSql(6, 2026, rows26(6))], ['close 7', closeSql(7, 2026, rows26(7))],
    ['retry 7', closeSql(7, 2026, rows26(7))], ['GFA01 7', closeSql(7, 2026, rows26(7), { nc: [{ x: 1 }] })],
    ['changed 7', closeSql(7, 2026, rows26(7), { chk: 1 })], ['skip to 9', closeSql(9, 2026, rows26(9))],
    ['monotonic 8', closeSql(8, 2026, rows26(8, (g, w) => v26(g, 6) - 1))], ['close 8', closeSql(8, 2026, rows26(8))],
    ['reopen 8', closeSql(8, 2026, rows26(8), { mode: 'approved_reopen', chk: 111 })],
    ['reopen 7', closeSql(7, 2026, rows26(7), { mode: 'approved_reopen', chk: 112 })],
    ['week 5', closeSql(5, 2026, rows26(5))], ['week 3', closeSql(3, 2026, rows26(3))],
    ['bad mode', closeSql(9, 2026, rows26(9), { mode: 'x' })], ['8 rows', closeSql(9, 2026, Object.fromEntries(NINE.slice(0, 8).map(g => [g, v26(g, 9)])), { expected: 8 })],
    ['expected 8', closeSql(9, 2026, rows26(9), { expected: 8 })], ['unknown goal', closeSql(9, 2026, Object.assign(rows26(9), { zz: 1 }), { expected: 10 })],
    ['correct 8', corrSql(2026, 8, 'alaska', v26('alaska', 8) + 0.5, v26('alaska', 8))],
    ['correct 5', corrSql(2026, 5, 'alaska', 1, v26('alaska', 5))],
    ['correct ineligible', corrSql(2026, 8, 'legacy_x', 1, 1)],
    ['half-close 9', "INSERT INTO weekly_reconciliations (week_num, chk, sav, amx, tax, lc, balance_basis, recorded_at) VALUES (9,100,200,300,0,400,'posted_current_balance',now());"
      + "INSERT INTO goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source) VALUES (2026,9,'adam_ira'," + v26('adam_ira', 9) + ",'reconciliation');" + closeSql(9, 2026, rows26(9))],
    ['close 10', closeSql(10, 2026, rows26(10))],
    ['household_admin reopen', "SET test.role='household_admin';" + closeSql(10, 2026, rows26(10), { mode: 'approved_reopen', chk: 5 })],
    ['viewer close', "SET test.role='none';" + closeSql(11, 2026, rows26(11))],
  ];
  const fp = "SELECT md5(string_agg(x, ';' ORDER BY x)) FROM (SELECT 'r'||week_num||'|'||chk||'|'||sav||'|'||balance_basis AS x FROM weekly_reconciliations UNION ALL SELECT 's'||model_year||'|'||week_num||'|'||goal_id||'|'||funded_amount||'|'||source||'|'||coalesce(note,'') FROM goal_funding_snapshots) q;";
  const runOn = template => {
    const name = PG.cloneFrom(db, template); db.sql(PRE + seed2026(5), name);
    const out = script.map(([label, sql]) => { const r = db.sql(PRE + sql, name); return label + ': ' + (r.ok ? 'ok ' + r.out.replace(/"reopened_at": "[^"]*"/, '') : 'raise'); });
    return { out, fp: db.sql(fp, name).out };
  };
  const base = runOn(baseTpl), now = runOn(tpl);
  const diff = base.out.map((l, i) => l === now.out[i] ? null : '  baseline ' + l + '\n  package  ' + now.out[i]).filter(Boolean);
  assert(!diff.length, '2026 outcomes differ:\n' + diff.join('\n'));
  assert(base.fp === now.fp, 'final 2026 state differs');
});

// ── Runner ──────────────────────────────────────────────────────────────────
let baseTpl;
(async () => {
  console.log('═══ 2027 rollover Package C: hermetic server tests' + (BASELINE ? ' — BASELINE (Package B, no Package C SQL)' : '') + ' ═══');
  db = PG.start();
  try {
    console.log('  PostgreSQL ' + db.version + ' (disposable cluster, Unix socket only, synthetic data)');
    baseTpl = PG.buildTemplate(db, 'tpl_base');
    tpl = BASELINE ? baseTpl : PG.buildTemplate(db, 'tpl_pkgc', PKG_SQL);
    for (const t of tests) {
      if (BASELINE && t.name.startsWith('PKGC-')) continue;
      try { await t.fn(); results.push([true, t.name]); console.log('  ✓ ' + t.name); }
      catch (e) { results.push([false, t.name, e.message]); console.log('  ✗ ' + t.name + '\n    → ' + e.message.split('\n').join('\n      ')); }
    }
  } finally { db.stop(); }
  const failed = results.filter(r => !r[0]);
  console.log('\n  Passed:  ' + (results.length - failed.length) + '\n  Failed:  ' + failed.length);
  process.exit(failed.length ? 1 : 0);
})();
