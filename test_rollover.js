// ════════════════════════════════════════════════════════════════════════════
// 2027 rollover suite. Package A: test and evidence infrastructure.
// Governing spec: docs/rollover-2027-spec.md (frozen v2.1). Package A changes no product
// behavior; these tests exercise the harness, the synthetic future-plan composition, the
// rollback fingerprint tooling and the evidence tools. Frozen §13 contract tests live in
// fixtures/rollover/contract-registry.json as PENDING until their package activates them.
// Exit code 1 on any failure (gated by scripts/pre-push.hook).
// ════════════════════════════════════════════════════════════════════════════
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const K = require('./tools/rollover-test-kit');
const FP = require('./tools/rollover-fingerprint');
const FC = require('./tools/rollover-function-capture');
const PINS = require('./tools/protected-pins');
const CONTRACTS = require('./tools/rollover-contracts');

let pass = 0, fail = 0;
const failures = [];
function test(name, fn) {
  try { fn(); pass++; process.stdout.write('  ✓ ' + name + '\n'); }
  catch (e) { fail++; failures.push({ name, error: e.message }); process.stdout.write('  ✗ ' + name + '\n    → ' + e.message + '\n'); }
}
function assert(c, m) { if (!c) throw new Error(m || 'Assertion failed'); }
function throws(fn, re, m) { let t = null; try { fn(); } catch (e) { t = e; } assert(t && (!re || re.test(t.message)), m || ('expected throw ' + re)); }

const REPO = __dirname;
const GOLD_PATH = path.join(REPO, 'fixtures', 'runmodel-golden-pre-1c-2.json');
const GOLD = JSON.parse(fs.readFileSync(GOLD_PATH, 'utf8'));
const GOLD_SHA = crypto.createHash('sha256').update(fs.readFileSync(GOLD_PATH)).digest('hex');
const SPEC_PATH = path.join(REPO, 'docs', 'rollover-2027-spec.md');

function freshGoals(ctx) { ctx.applyGoalsFromData(ctx.HARDCODED_GOALS_FALLBACK.map(g => Object.assign({}, g))); }
function runOn(ctx, rows) { ctx.WD = rows; ctx.overrideData = {}; ctx.goalSnapData = {}; freshGoals(ctx); return K.plain(ctx.runModel(7000, 7694.87)); }
function diffWeeks(a, b, n) { const d = []; for (let i = 0; i < n; i++) { try { K.deepEq(a[i], b[i]); } catch (e) { d.push(i + 1); } } return d; }

console.log('\n══ 2027 rollover suite — Package A (test and evidence infrastructure) ══');

// ── B. Clock pinning ──────────────────────────────────────────────────────────
console.log('── Clock pinning ──');
test('PKGA-CLOCK-1 pinned dates give deterministic current weeks (pre-rollover characterization: product caps at 31 until C3)', () => {
  const want = { '2026-12-27': 30, '2027-01-02': 30, '2027-01-03': 31, '2027-01-10': 31 };
  Object.keys(want).forEach(d => { const c = K.loadApp({ date: d }); assert(c.getCurrentWeek() === want[d] && c.currentW === want[d], d + ': got ' + c.getCurrentWeek()); });
  assert(K.cal.householdWeek(32).year === 2027 && K.cal.householdWeek(32).week === 2, 'oracle: true week on 2027-01-10 is 2027 Wk 2 (absolute 32)');
});
test('PKGA-CLOCK-2 pins do not leak: separate contexts keep separate clocks; the process clock is untouched', () => {
  const a = K.loadApp({ date: '2026-12-27' }), b = K.loadApp({ date: '2027-01-10' });
  assert(a.getCurrentWeek() === 30 && b.getCurrentWeek() === 31 && a.getCurrentWeek() === 30, 'contexts interfered');
  assert(Math.abs(Date.now() - new Date().getTime()) < 1000 && typeof Date.__hfosPinned === 'undefined', 'process Date was modified');
});
test('PKGA-CLOCK-3 the pinned Date preserves explicit dates, Date() strings and instanceof', () => {
  const c = K.loadApp({ date: '2027-01-03' });
  const probe = require('vm').runInContext('[new Date().getDate(), new Date(2026,5,7).getMonth(), typeof Date(), (new Date()) instanceof Date, Date.now()===new Date().getTime()]', c);
  assert(probe[0] === 3 && probe[1] === 5 && probe[2] === 'string' && probe[3] === true && probe[4] === true, JSON.stringify(probe));
  throws(() => K.resolveTestDate('2027-02-30'), /invalid calendar date/);
  throws(() => K.resolveTestDate('01/03/2027'), /YYYY-MM-DD/);
  assert(K.resolveTestDate(undefined) === K.LEGACY_DEFAULT_TEST_DATE && K.resolveTestDate('') === K.LEGACY_DEFAULT_TEST_DATE, 'default pin');
});
test('PKGA-CLOCK-4 CLOSED (C18): the pinned-week 5G1C1-12 fixture renders its label at every boundary date; the label logic never reads the clock', () => {
  function render(date, cw) {
    const c = K.loadApp({ date }), weeks = [];
    for (let i = 1; i <= 31; i++) weeks.push({ num: i, dates: 'x', goalSaved: { bailey_529: (i <= cw ? 0 : 2555) } });
    return c._renderGoalsFunding({ weeks, goalCompletion: {} }, weeks[cw - 1] || weeks[0]);
  }
  ['2026-10-07', '2026-12-27', '2027-01-02', '2027-01-03', '2027-01-10'].forEach(d => assert(render(d, 18).includes('Partial in 2026'), d + ': label missing'));
  // The label comes from _fundingWhenLabel, which is pure: identical items give identical labels in
  // contexts pinned to different dates, and its source reads no clock or current week. (Other parts
  // of the Funding Plan, e.g. the timeline's current-week marker, correctly move with the date.)
  const item = { g: { auto: false, stretch: false, target: 3500 }, funded: 0, fundedYE: 2555, pct: 0, pctYE: 73, comp: null, isFunded: false, isLocked: false };
  const a = K.loadApp({ date: '2026-10-07' }), b = K.loadApp({ date: '2027-01-10' });
  K.deepEq(K.plain(a._fundingWhenLabel(item)), K.plain(b._fundingWhenLabel(item)), 'label');
  assert(!/currentW|Date|getCurrentWeek/.test(a._fundingWhenLabel.toString()), '_fundingWhenLabel must not read the clock');
  // The former defect: a fixture whose current week came from the live clock held no projected
  // funding once the clock reached week 31, so the old assertion failed on correct output.
  assert(!render('2027-01-03', 31).includes('Partial in 2026'), 'week-31 data has no projected funding (fixture, not product logic)');
  const src = fs.readFileSync(path.join(REPO, 'test_regression.js'), 'utf8');
  const blk = src.slice(src.indexOf("test('5G1C1-12"), src.indexOf("test('5G1C1-13"));
  assert(!/getCurrentWeek\(\)/.test(blk) && /const _cw=18;/.test(blk), '5G1C1-12 must use a pinned current week (C18)');
});
test('PKGA-CLOCK-5 legacy suites read the clock only through the pinned stub', () => {
  ['test_regression.js', 'test_a1b.js', 'test_d1.js', 'test_release_a.js', 'test_release_b.js'].forEach(f => {
    const s = fs.readFileSync(path.join(REPO, f), 'utf8');
    assert(/clockStubSource\((process\.env\.HFOS_TEST_DATE|HFOS_TEST_DATE)\)/.test(s), f + ' does not pin the clock');
  });
  const e2e = fs.readFileSync(path.join(REPO, 'e2e.js'), 'utf8');
  assert(/ctx\.clock\.install\(\{ time:/.test(e2e) && /resolveTestDate\(process\.env\.HFOS_TEST_DATE\)/.test(e2e), 'e2e.js does not pin the browser clock');
});

// ── A. Frozen 2026 composition ────────────────────────────────────────────────
console.log('── Frozen 2026 composition ──');
test('PKGA-FROZEN-1 the 2026 golden is byte-identical on disk and reproduced exactly in an isolated context', () => {
  assert(GOLD_SHA === '157753ce76001e21687b7c84ccd2a1ee7584057372f4fb7eafe6482b9497b088', 'golden fixture bytes changed: ' + GOLD_SHA);
  const c = K.loadApp({});
  const D = K.withFrozen2026(c, () => K.plain(K.goldenDerive(c, GOLD._meta)));
  K.deepEq(D.weeks, GOLD.weeks, 'weeks'); K.deepEq(D.goalCompletion, GOLD.goalCompletion, 'goalCompletion'); K.deepEq(D.getGoalFunded, GOLD.getGoalFunded, 'getGoalFunded');
});
test('PKGA-FROZEN-2 simulated post-rollover product: the harness binds WD_2026_FROZEN, and the golden is unchanged while runtime runs 82 weeks', () => {
  const c = K.loadApp({});
  const frozen = K.plain(c.WD);
  c.WD_2026_FROZEN = frozen;
  c.WD = K.compositionFor(2027, { frozen, blocks: { 2027: K.synthPlanBlock(2027) } });
  assert(K.frozen2026Rows(c) === c.WD_2026_FROZEN, 'harness did not select WD_2026_FROZEN');
  const D = K.withFrozen2026(c, () => K.plain(K.goldenDerive(c, GOLD._meta)));
  K.deepEq(D.weeks, GOLD.weeks, 'weeks');
  assert(c.WD.length === 82, 'runtime composition was not restored after the frozen run');
  freshGoals(c); c.overrideData = {}; c.goalSnapData = {};
  assert(c.runModel(7000, 7694.87).length === 82, 'runtime model should span 82 weeks');
});
test('PKGA-FROZEN-3 the legacy suite and capture tool bind the frozen source explicitly (hook present in source)', () => {
  const tr = fs.readFileSync(path.join(REPO, 'test_regression.js'), 'utf8');
  assert(/typeof WD_2026_FROZEN !== 'undefined'\) \? WD_2026_FROZEN : WD/.test(tr) && /WD = LEGACY_FROZEN_2026_ROWS;/.test(tr), 'test_regression.js frozen binding missing');
  assert(/applyGoalsFromData\(HARDCODED_GOALS_FALLBACK\.slice\(\)\)/.test(tr), 'golden re-derive must pin the 2026 goal inputs');
  ['test_a1b.js', 'test_d1.js', 'test_release_a.js', 'test_release_b.js'].forEach(f => {
    assert(/if \(typeof WD_2026_FROZEN !== 'undefined'\) WD = WD_2026_FROZEN;/.test(fs.readFileSync(path.join(REPO, f), 'utf8')), f + ' frozen binding missing');
  });
  const cap = fs.readFileSync(path.join(REPO, 'tools', 'capture-golden-master.js'), 'utf8');
  assert(/typeof WD_2026_FROZEN !== 'undefined'\) \? WD_2026_FROZEN : WD/.test(cap), 'capture tool frozen binding missing');
});

// ── E. Plan compositions and future-plan isolation ────────────────────────────
console.log('── Plan compositions ──');
test('PKGA-PLAN-1 spec §3/§4 period oracle', () => {
  const c = K.cal;
  assert(c.firstWeekOfPlan(2027) === 31 && c.firstWeekOfPlan(2028) === 83, 'firstWeekOfPlan');
  throws(() => c.firstWeekOfPlan(2026), /undefined for 2026/, 'firstWeekOfPlan(2026) must be rejected');
  assert(c.openingWeekOfPlan(2026) === 5 && c.openingWeekOfPlan(2027) === 30 && c.openingWeekOfPlan(2028) === 82, 'openingWeekOfPlan');
  assert(c.finalWeekOfPlan(2026) === 30 && c.finalWeekOfPlan(2027) === 82 && c.finalWeekOfPlan(2028) === 135, 'finalWeekOfPlan (2028 has 53 weeks)');
  const hw = n => { const h = c.householdWeek(n); return h.year + '-' + h.week; };
  assert(hw(1) === '2026-23' && hw(30) === '2026-52' && hw(31) === '2027-1' && hw(82) === '2027-52' && hw(83) === '2028-1' && hw(135) === '2028-53', 'householdWeek per §4');
  assert(c.planYearOfWeek(30) === 2026 && c.planYearOfWeek(31) === 2027 && c.planYearOfWeek(82) === 2027 && c.planYearOfWeek(83) === 2028, 'planYearOfWeek');
});
test('PKGA-PLAN-2 compositionFor: plan 2026 = 31 frozen rows; 2027 = weeks 1..82; 2028 = 1..135; contiguity enforced', () => {
  const c = K.loadApp({}); const frozen = K.plain(c.WD);
  const b = { 2027: K.synthPlanBlock(2027), 2028: K.synthPlanBlock(2028) };
  assert(K.compositionFor(2026, { frozen, blocks: b }).length === 31, '2026');
  const p27 = K.compositionFor(2027, { frozen, blocks: b });
  assert(p27.length === 82 && p27[30][0] === 31 && p27[30][1].indexOf('SYNTH') === 0, '2027 week 31 must be the authored block, never frozen row 31');
  assert(K.compositionFor(2028, { frozen, blocks: b }).length === 135, '2028');
  const gap = { 2027: K.synthPlanBlock(2027).filter(r => r[0] !== 40) };
  throws(() => K.compositionFor(2027, { frozen, blocks: gap }), /not contiguous/, 'gap must be refused');
});
test('PKGA-PLAN-3 future-plan isolation: appending WD_2028 cannot change the plan-2027 golden (truncated composition)', () => {
  const c = K.loadApp({}); const frozen = K.plain(c.WD);
  const opt = { income: 4400, bill: 1800 };
  const b27 = K.synthPlanBlock(2027, opt), b28 = K.synthPlanBlock(2028, Object.assign({ spike: { 83: 60000 } }, opt));
  const g27 = runOn(c, K.compositionFor(2027, { frozen, blocks: { 2027: b27 } }));
  const g27b = runOn(c, K.compositionFor(2027, { frozen, blocks: { 2027: b27, 2028: b28 } }));
  K.deepEq(g27b, g27, 'plan-2027 golden');
  // Negative control: without truncation, week 83 reaches the plan-2027 look-ahead.
  const untrunc = runOn(c, frozen.slice(0, 30).concat(b27, b28)).slice(0, 82);
  const d = diffWeeks(untrunc, g27, 82);
  assert(d.length > 0 && d.every(n => n >= 78), 'negative control must show look-ahead contamination near week 82, got ' + JSON.stringify(d));
});
test('PKGA-PLAN-4 a synthetic future plan cannot contaminate the 2026 golden; §14 runtime prefix weeks 1-25 identical', () => {
  const c = K.loadApp({}); const frozen = K.plain(c.WD);
  const fz = runOn(c, frozen);
  const rt = runOn(c, K.compositionFor(2027, { frozen, blocks: { 2027: K.synthPlanBlock(2027, { spike: { 31: 90000, 32: 90000 } }) } }));
  const d = diffWeeks(rt, fz, 30);
  assert(d.every(n => n >= 26), '§14: runtime weeks 1-25 must equal the frozen run; differed at ' + JSON.stringify(d));
  // The context's WD is now the 82-row runtime composition; the frozen-row resolver refuses it
  // as a 2026 source (fail closed) until the frozen source is declared, as the product will.
  throws(() => K.frozen2026Rows(c), /must have 31 rows/, 'a non-31-row WD must never be taken as the frozen 2026 source');
  c.WD_2026_FROZEN = frozen;
  const D = K.withFrozen2026(c, () => K.plain(K.goldenDerive(c, GOLD._meta)));
  K.deepEq(D.weeks, GOLD.weeks, 'golden after a synthetic future run');
});
test('PKGA-PLAN-5 synthetic rows are self-consistent, dated within their week, and non-household', () => {
  [2027, 2028].forEach(Y => K.synthPlanBlock(Y, { spike: { 90: 5 } }).forEach(r => {
    const evs = r[4];
    K.deepEq(r[2], evs.filter(e => e.t === 'in').map(e => e.a), 'wd[2]'); K.deepEq(r[3], evs.filter(e => e.t === 'ob').map(e => Math.abs(e.a)), 'wd[3]');
    evs.forEach(e => {
      assert(/^SYNTH /.test(e.l) && /^[A-Z][a-z]{2} \d{1,2}$/.test(e.d), 'label/d format ' + JSON.stringify(e));
      const ws = K.cal.weekStartUTC(r[0]), MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const ok = [0, 1, 2, 3, 4, 5, 6].some(k => { const t = new Date(ws + k * 86400000); return MO[t.getUTCMonth()] + ' ' + t.getUTCDate() === e.d; });
      assert(ok, 'd outside its week: ' + r[0] + ' ' + e.d);
    });
  }));
});

// ── H. Capture tool plan support ──────────────────────────────────────────────
console.log('── Capture tool ──');
function runCapture(args) { return execFileSync(process.execPath, [path.join(REPO, 'tools', 'capture-golden-master.js')].concat(args), { cwd: REPO, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }); }
test('PKGA-CAP-1 capture --check reproduces the protected 2026 fixture and does not write it', () => {
  const out = runCapture(['--check']);
  assert(/CHECK OK: derived plan 2026/.test(out), out);
  assert(crypto.createHash('sha256').update(fs.readFileSync(GOLD_PATH)).digest('hex') === GOLD_SHA, 'fixture changed');
});
test('PKGA-CAP-2 capture --plan 2027 derives a synthetic plan on its own composition and refuses the 2026 fixture path', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hfos-pkga-'));
  try {
    const c = K.loadApp({});
    fs.writeFileSync(path.join(dir, 'blocks.json'), JSON.stringify({ 2027: K.synthPlanBlock(2027) }));
    fs.writeFileSync(path.join(dir, 'goals.json'), JSON.stringify(K.plain(c.HARDCODED_GOALS_FALLBACK)));
    const fx = path.join(dir, 'golden-2027.json');
    const base = ['--plan', '2027', '--schedule', path.join(dir, 'blocks.json'), '--goals', path.join(dir, 'goals.json'), '--current-week', '31'];
    runCapture(base.concat(['--fixture', fx, '--write']));
    const g = JSON.parse(fs.readFileSync(fx, 'utf8'));
    assert(g.weeks.length === 82 && g._meta.plan === 2027 && g._meta.finalWeek === 82, 'plan-2027 capture shape');
    assert(/CHECK OK: derived plan 2027/.test(runCapture(base.concat(['--fixture', fx, '--check']))), 'plan-2027 capture must be reproducible');
    let refused = false; try { runCapture(base.concat(['--fixture', GOLD_PATH, '--write'])); } catch (e) { refused = /may not write the protected 2026 fixture/.test(String(e.stderr)); }
    assert(refused, 'plan 2027 must refuse the protected 2026 fixture');
    assert(crypto.createHash('sha256').update(fs.readFileSync(GOLD_PATH)).digest('hex') === GOLD_SHA, 'protected fixture changed');
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

// ── F. §18 business-and-control fingerprint (OD-1) ────────────────────────────
console.log('── Rollback fingerprint (OD-1) ──');
const REG = (st, upd, extra) => Object.assign({ id: 'alaska', name: 'Alaska Cruise', target: 7000, priority: 1, status: st, updated_at: upd, created_at: '2026-07-01T00:00:00Z' }, extra || {});
const snapT = (rows, more) => FP.snapshot(Object.assign({ goal_registry: { pk: 'id', rows } }, more || {}));
test('PKGA-FP-1 OD-1 exclusions are exactly goal_registry.updated_at and cannot be extended at runtime', () => {
  K.deepEq(K.plain(FP.OD1_EXCLUSIONS), { goal_registry: ['updated_at'] }, 'OD1_EXCLUSIONS');
  assert(Object.isFrozen(FP.OD1_EXCLUSIONS) && Object.isFrozen(FP.OD1_EXCLUSIONS.goal_registry), 'must be frozen');
  try { FP.OD1_EXCLUSIONS.goal_registry.push('created_at'); } catch (e) {}
  try { FP.OD1_EXCLUSIONS.cash_commitments = ['updated_at']; } catch (e) {}
  K.deepEq(K.plain(FP.OD1_EXCLUSIONS), { goal_registry: ['updated_at'] }, 'mutated');
});
test('PKGA-FP-2 (T-RB-6 a) status changed then restored exactly, only trigger-maintained updated_at differs → PASS', () => {
  const r = FP.compareBaseline(snapT([REG('funding', 't0')]), snapT([REG('funding', 't2')]), {});
  assert(r.pass && r.equal.length === 1, JSON.stringify(r));
});
test('PKGA-FP-3 (T-RB-6 b) an unmanifested business-field difference → FAIL', () => {
  const r = FP.compareBaseline(snapT([REG('funding', 't0')]), snapT([REG('funding', 't2', { target: 7001 })]), {});
  assert(!r.pass && r.unexplained.length === 1, JSON.stringify(r));
});
test('PKGA-FP-4 (T-RB-6 c) the excluded updated_at change stays visible in evidence, before and after', () => {
  const r = FP.compareBaseline(snapT([REG('funding', 't0')]), snapT([REG('funding', 't2')]), {});
  assert(r.excludedChanges.length === 1 && r.excludedChanges[0].column === 'updated_at' && r.excludedChanges[0].before === 't0' && r.excludedChanges[0].after === 't2', JSON.stringify(r.excludedChanges));
});
test('PKGA-FP-5 updated_at on any other table is NOT excluded (cash_commitments row) → FAIL unless enumerated household history', () => {
  const cc = upd => ({ cash_commitments: { pk: 'id', rows: [{ id: 'c1', status: 'pending', updated_at: upd }] } });
  const r = FP.compareBaseline(snapT([REG('funding', 't0')], cc('u0')), snapT([REG('funding', 't0')], cc('u1')), {});
  assert(!r.pass && r.unexplained.some(u => u.id === 'cash_commitments|c1'), JSON.stringify(r));
  const h = FP.compareBaseline(snapT([REG('funding', 't0')], cc('u0')), snapT([REG('funding', 't0')], cc('u1')), { householdHistory: [{ table: 'cash_commitments', key: 'c1', kind: 'updated' }] });
  assert(h.pass && h.household.length === 1, 'enumerated household history must pass');
});
test('PKGA-FP-6 RB-2/RB-3 household history: inserted and updated rows pass only when enumerated with the right kind', () => {
  const base = snapT([REG('funding', 't0')]);
  const cur = snapT([REG('funding', 't0'), Object.assign(REG('funding', 't0'), { id: 'new_goal' })]);
  assert(!FP.compareBaseline(base, cur, {}).pass, 'unenumerated insert must fail');
  assert(!FP.compareBaseline(base, cur, { householdHistory: [{ table: 'goal_registry', key: 'new_goal', kind: 'updated' }] }).pass, 'wrong kind must fail');
  assert(FP.compareBaseline(base, cur, { householdHistory: [{ table: 'goal_registry', key: 'new_goal', kind: 'inserted' }] }).pass, 'enumerated insert must pass');
  assert(!FP.compareBaseline(base, snapT([]), {}).pass, 'an unexplained deleted baseline row must fail');
});
test('PKGA-FP-7 §16 step 15(b): a manifest-recorded status change passes only when status alone differs and matches the record', () => {
  const ms = [{ table: 'goal_registry', key: 'alaska', before: 'funding', after: 'executed' }];
  const base = snapT([REG('funding', 't0')]);
  assert(FP.compareBaseline(base, snapT([REG('executed', 't9')]), { manifestStatusChanges: ms }).pass, 'expected status change must pass');
  assert(!FP.compareBaseline(base, snapT([REG('archived', 't9')]), { manifestStatusChanges: ms }).pass, 'status not equal to the manifest must fail');
  assert(!FP.compareBaseline(base, snapT([REG('executed', 't9', { target: 1 })]), { manifestStatusChanges: ms }).pass, 'status plus another field must fail');
  assert(!FP.compareBaseline(base, snapT([REG('executed', 't9')]), {}).pass, 'without the manifest record it must fail');
});
test('PKGA-FP-8 RB-1 write set: rollback changes exactly the manifest-reversal rows', () => {
  const pre = snapT([REG('executed', 't1'), Object.assign(REG('planned', 't1'), { id: 'adam_ira_2027' })]);
  const post = snapT([REG('funding', 't2')]);
  const rev = [{ table: 'goal_registry', key: 'alaska' }, { table: 'goal_registry', key: 'adam_ira_2027' }];
  const ok = FP.compareWriteSet(pre, post, rev);
  assert(ok.pass && ok.excludedChanges.some(x => x.key === 'alaska' && x.column === 'updated_at'), JSON.stringify(ok));
  assert(!FP.compareWriteSet(pre, post, rev.slice(0, 1)).pass, 'an extra changed row must fail');
  assert(!FP.compareWriteSet(pre, pre, rev).pass, 'a missing reversal must fail');
});

// ── NB-5 checkpoint-C equivalence (separate comparison) ───────────────────────
console.log('── Checkpoint-C equivalence (NB-5) ──');
const anchor = (id, ca) => ({ id, model_year: 2027, week_num: 30, goal_id: 'adam_ira_2027', source: 'opening_anchor', funded_amount: 100, note: 'new', created_at: ca });
test('PKGA-NB5-1 checkpoint comparison requires explicit generated columns and natural keys', () => {
  throws(() => FP.compareCheckpoint({}, {}, {}), /explicit generatedColumns/);
  throws(() => FP.compareCheckpoint({}, {}, { generatedColumns: {} }), /naturalKey/);
});
test('PKGA-NB5-2 re-inserted rows that differ only in listed generated columns are equivalent; unlisted differences fail', () => {
  const spec = { generatedColumns: { goal_funding_snapshots: ['id', 'created_at'] }, naturalKey: { goal_funding_snapshots: ['model_year', 'week_num', 'goal_id'] } };
  assert(FP.compareCheckpoint({ goal_funding_snapshots: [anchor('u1', 'c1')] }, { goal_funding_snapshots: [anchor('u2', 'c2')] }, spec).pass, 'generated columns listed');
  assert(!FP.compareCheckpoint({ goal_funding_snapshots: [anchor('u1', 'c1')] }, { goal_funding_snapshots: [anchor('u2', 'c2')] }, { generatedColumns: { goal_funding_snapshots: ['id'] }, naturalKey: spec.naturalKey }).pass, 'unlisted created_at must fail');
  const changed = Object.assign(anchor('u2', 'c2'), { funded_amount: 101 });
  assert(!FP.compareCheckpoint({ goal_funding_snapshots: [anchor('u1', 'c1')] }, { goal_funding_snapshots: [changed] }, spec).pass, 'a business difference must fail');
});
test('PKGA-NB5-3 NB-5 never weakens §18: created_at differences fail the rollback fingerprint, and OD-1 is unchanged', () => {
  FP.compareCheckpoint({ goal_registry: [REG('funding', 't0')] }, { goal_registry: [REG('funding', 't0')] }, { generatedColumns: { goal_registry: ['created_at', 'updated_at'] }, naturalKey: { goal_registry: ['id'] } });
  K.deepEq(K.plain(FP.OD1_EXCLUSIONS), { goal_registry: ['updated_at'] }, 'OD1_EXCLUSIONS');
  const r = FP.compareBaseline(snapT([REG('funding', 't0')]), snapT([Object.assign(REG('funding', 't0'), { created_at: '2027-01-02T00:00:00Z' })]), {});
  assert(!r.pass, '§18 must treat a created_at difference as unexplained');
});

// ── G. Function-body evidence capture ─────────────────────────────────────────
console.log('── Function-body capture ──');
const FROW = (sig, def, extra) => Object.assign({ signature: sig, definition: def, security_definer: true, config: ['search_path=public, pg_temp'], owner: 'postgres', acl: '{postgres=X/postgres,authenticated=X/postgres}' }, extra || {});
test('PKGA-FC-1 captures are deterministic; identical bodies compare identical; every definition/flag change is detected', () => {
  const a = FC.buildCapture([FROW('public.b()', 'BODY B'), FROW('public.a()', 'BODY A')], { label: 'pre' });
  const a2 = FC.buildCapture([FROW('public.a()', 'BODY A'), FROW('public.b()', 'BODY B')], { label: 'pre' });
  assert(a.manifest_sha256 === a2.manifest_sha256 && a.functions[0].signature === 'public.a()', 'order-independent and sorted');
  assert(FC.compareCaptures(a, a2).identical, 'identical captures');
  const mut = [['definition', 'BODY A '], ['security_definer', false], ['owner', 'other'], ['acl', '{postgres=X/postgres}'], ['config', ['search_path=public']]];
  mut.forEach(([k, v]) => {
    const b = FC.buildCapture([FROW('public.a()', 'BODY A', { [k]: v }), FROW('public.b()', 'BODY B')], {});
    assert(!FC.compareCaptures(a, b).identical, 'missed change in ' + k);
  });
  assert(!FC.compareCaptures(a, FC.buildCapture([FROW('public.a()', 'BODY A')], {})).identical, 'missing function');
  const t = JSON.parse(JSON.stringify(a)); t.functions[0].definition = 'TAMPERED';
  assert(FC.compareCaptures(t, a).diffs.some(d => d.field === 'definition_sha256_tampered'), 'tampering');
  throws(() => FC.buildCapture([FROW('public.a()', 'x'), FROW('public.a()', 'y')], {}), /duplicate signature/);
});
test('PKGA-FC-2 the capture query is read-only catalog text', () => {
  const q = FC.CAPTURE_QUERY.toUpperCase();
  assert(/^SELECT /.test(q) && !/\b(INSERT|UPDATE|DELETE|ALTER|GRANT|REVOKE|CREATE|DROP|TRUNCATE|COPY)\b/.test(q.replace(/PG_GET_FUNCTIONDEF/g, '')), 'capture query must be a read-only SELECT');
});
test('PKGA-N9-1 (Gate 1 note N-9) new helpers must REVOKE EXECUTE from PUBLIC, anon and authenticated', () => {
  const good = 'CREATE OR REPLACE FUNCTION public.plan_year_of_week(n int) RETURNS int LANGUAGE sql IMMUTABLE AS $$ select 1 $$;\nREVOKE EXECUTE ON FUNCTION public.plan_year_of_week(int) FROM PUBLIC, anon, authenticated;';
  assert(FC.checkHelperRevokes(good, ['plan_year_of_week'])[0].pass, 'compliant SQL');
  assert(!FC.checkHelperRevokes(good.replace(', anon', ''), ['plan_year_of_week'])[0].pass, 'missing anon');
  assert(!FC.checkHelperRevokes(good + '\nGRANT EXECUTE ON FUNCTION public.plan_year_of_week(int) TO authenticated;', ['plan_year_of_week'])[0].pass, 'client grant');
  assert(!FC.checkHelperRevokes('-- CREATE FUNCTION public.x(n int)\nREVOKE EXECUTE ON FUNCTION public.x(int) FROM PUBLIC, anon, authenticated;', ['x'])[0].pass, 'commented-out create must not count');
  assert(!FC.checkHelperRevokes(good, ['opening_week_of_plan'])[0].pass, 'an uncreated helper must fail');
});

// ── J. Protected-function pins ────────────────────────────────────────────────
console.log('── Protected pins ──');
test('PKGA-PIN-1 the pin tool matches the release method (string- and comment-aware brace matching) and detects changes', () => {
  const html = "x\nfunction runModel(a){ var s='}'; // }\n return {a:\"{\"}; }\nfunction other(){}";
  assert(PINS.fnSrc(html, 'runModel') === "function runModel(a){ var s='}'; // }\n return {a:\"{\"}; }", 'brace matching');
  const base = [{ name: 'runModel', sha: PINS.pin(html, 'runModel') }];
  assert(PINS.verify(html, base).pass && !PINS.verify(html.replace('return', 'return 1,'), base).pass, 'verify');
  assert(!PINS.verify(html, [{ name: 'missingFn', sha: '0'.repeat(64) }]).pass, 'missing function');
  const real = fs.readFileSync(path.join(REPO, 'index.html'), 'utf8');
  ['runModel', 'reconEffectiveWD', 'getActiveModel'].forEach(n => assert(PINS.fnSrc(real, n), n + ' not found'));
});

// ── C. Contract registry (frozen §13 tests and Gate 1 notes) ──────────────────
console.log('── Contract registry ──');
const REGISTRY = JSON.parse(fs.readFileSync(path.join(REPO, 'fixtures', 'rollover', 'contract-registry.json'), 'utf8'));
test('PKGA-REG-1 every frozen v2.1 §13 test is registered with an owning package; nothing extra, nothing forgotten', () => {
  const specBytes = fs.readFileSync(SPEC_PATH);
  assert(crypto.createHash('sha256').update(specBytes).digest('hex') === REGISTRY._meta.spec_sha256, 'spec changed since the registry was built: update the registry with owner approval');
  const ids = [...specBytes.toString('utf8').matchAll(/^- \*\*(T-[A-Z]+-[0-9]+[a-d]?)(?: \([^)]*\))?\*\*/gm)].map(m => m[1]);
  const reg = REGISTRY.entries.filter(e => e.id.startsWith('T-')).map(e => e.id);
  K.deepEq(reg.slice().sort(), ids.slice().sort(), 'registry vs spec §13');
  assert(ids.length === 70 && new Set(reg).size === reg.length, 'expected 70 unique §13 tests');
});
test('PKGA-REG-2 registry entries are well formed; Gate 1 notes C18, N-9 and NB-5 are carried', () => {
  const pk = Object.keys(REGISTRY._meta.packages);
  REGISTRY.entries.forEach(e => {
    assert(pk.indexOf(e.package) >= 0 && REGISTRY._meta.statuses.indexOf(e.status) >= 0 && e.spec, 'bad entry ' + JSON.stringify(e));
    assert(e.status !== 'ACTIVE' || CONTRACTS.defaultResolveImpl(e.impl), 'ACTIVE entry must resolve to an existing test: ' + e.id);
  });
  ['X-C18', 'X-N9', 'X-NB5'].forEach(id => assert(REGISTRY.entries.some(e => e.id === id), id + ' missing'));
  const counts = {}; REGISTRY.entries.forEach(e => { counts[e.package + ':' + e.status] = (counts[e.package + ':' + e.status] || 0) + 1; });
  process.stdout.write('    registry: ' + JSON.stringify(counts) + '\n');
});

// ══ Package B: year-neutral client hardening (C11, C18, C23, C24) ══════════════
// Contracts T-SNAP-1, T-TR-4, T-TR-5, X-C18 (frozen v2.1 §9, §13). Baseline product for
// differential checks: the Package A commit, whose index.html is product b0762e3.
console.log('── Package B contracts ──');
const PKGB_BASE_COMMIT = '822062132e78812759dfb1dc3f2382253c361c12';
let _baseIndexPath = null;
function baseIndexPath() {
  if (_baseIndexPath) return _baseIndexPath;
  const html = execFileSync('git', ['show', PKGB_BASE_COMMIT + ':index.html'], { cwd: REPO, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hfos-pkgb-'));
  _baseIndexPath = path.join(dir, 'index.html'); fs.writeFileSync(_baseIndexPath, html);
  process.on('exit', () => { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {} });
  return _baseIndexPath;
}
function captureDom(c) {
  const store = {};
  c.document.getElementById = function (id) {
    if (!store[id]) store[id] = { id, innerHTML: '', value: '', textContent: '', style: {}, classList: { add() {}, remove() {} }, addEventListener() {}, scrollIntoView() {}, querySelector() { return null; }, querySelectorAll() { return []; }, getContext() { return null; }, setAttribute() {} };
    return store[id];
  };
  return store;
}
function vmFor(c) { freshGoals(c); c.overrideData = {}; return c.buildDashboardViewModel(c.applyCompletionSnapshots(c.runModel(7000, 7694.87)), { ak: 7000, rt: 7694.87 }); }

// Mock PostgREST: per-table rows, server row cap (like max-rows), Prefer count=exact →
// Content-Range, keyset id=gt + order=id.asc + limit, order=updated_at.desc[.nullslast]&limit=1,
// model_year=eq filter (so the pre-C11 loader can be exercised), and fault injection.
function mockPostgrest(tables, opt) {
  opt = opt || {};
  const calls = [];
  let pageCalls = 0;
  const fetchFn = function (url, init) {
    const u = new URL(url); const table = u.pathname.replace('/rest/v1/', ''); calls.push(u.pathname + u.search);
    const prefer = (init && init.headers && (init.headers.Prefer || init.headers.prefer)) || '';
    let rows = (tables[table] || []).slice();
    if (opt.mutate && opt.mutate.table === table) rows = opt.mutate.rowsAt(pageCalls, rows);
    const my = u.searchParams.get('model_year'); if (my && /^eq\./.test(my)) rows = rows.filter(r => String(r.model_year) === my.slice(3));
    const total = rows.length;
    const order = u.searchParams.get('order') || '';
    if (/^updated_at\.desc/.test(order)) rows.sort((a, b) => (a.updated_at < b.updated_at ? 1 : a.updated_at > b.updated_at ? -1 : 0));
    else rows.sort((a, b) => (String(a.id) < String(b.id) ? -1 : String(a.id) > String(b.id) ? 1 : 0));
    const gt = u.searchParams.get('id'); if (gt && /^gt\./.test(gt)) { const cur = gt.slice(3); rows = rows.filter(r => String(r.id) > cur); pageCalls++; if (opt.failPage && opt.failPage.table === table && pageCalls >= opt.failPage.at) return Promise.resolve(resp(500, [], null)); }
    let lim = Number(u.searchParams.get('limit') || 1e9); lim = Math.min(lim, opt.cap || 1e9); rows = rows.slice(0, lim);
    if (opt.dropFromPages && opt.dropFromPages.table === table && !/^updated_at/.test(order)) rows = rows.filter(r => opt.dropFromPages.ids.indexOf(r.id) < 0);
    const cr = /count=exact/i.test(prefer) ? (opt.noCount && opt.noCount === table ? null : (rows.length ? '0-' + (rows.length - 1) + '/' + total : '*/' + total)) : null;
    return Promise.resolve(resp(200, rows, cr));
  };
  function resp(status, body, cr) { return { ok: status >= 200 && status < 300, status, headers: { get: k => (String(k).toLowerCase() === 'content-range' ? cr : null) }, json: () => Promise.resolve(JSON.parse(JSON.stringify(body))) }; }
  fetchFn.calls = calls;
  return fetchFn;
}
function snapRow(i, my, wk, goal, src, note) { return { id: 's' + String(i).padStart(3, '0'), model_year: my, week_num: wk, goal_id: goal, funded_amount: 100 + i, source: src, note: note || null, created_at: '2026-07-0' + (1 + (i % 8)) + 'T00:00:00Z', updated_at: '2026-07-10T00:00:0' + (i % 10) + 'Z' }; }
function snapFixture() {
  const rows = [];
  ['adam_ira', 'wendy_ira', 'alaska', 'bailey_529', 'bryce_529', 'preston_529', 'bryce_vehicle'].forEach((g, i) => rows.push(snapRow(i, 2026, 5, g, 'opening_anchor', '[PROD opening_anchor]')));
  rows.push(snapRow(20, 2026, 30, 'adam_ira', 'reconciliation', null));
  rows.push(snapRow(21, 2027, 30, 'adam_ira_2027', 'opening_anchor', 'carry:adam_ira'));
  return rows;
}
function ccRow(i, my, wk) { return { id: 'c' + String(i).padStart(3, '0'), model_year: my, origin_model_week: wk, reflected_model_week: null, resolved_model_week: null, amount_cents: 1000 + i, payee: 'SYNTH ' + i, status: 'pending', updated_at: '2026-07-10T00:00:0' + (i % 10) + 'Z' }; }
function ccFixture() { const r = []; for (let i = 0; i < 6; i++) r.push(ccRow(i, 2026, 20 + i)); r.push(ccRow(9, 2027, 31)); return r; }
async function withMock(c, tables, opt, fn) { c.getAuthHeaders = async function () { return {}; }; c.fetch = mockPostgrest(tables, opt); return fn(c.fetch); }

const _asyncB = [];
function testAsync(name, fn) { _asyncB.push({ name, fn }); }

testAsync('T-SNAP-1 (a) paging: the snapshot load pages past the server row cap until the reported count is loaded', async () => {
  const c = K.loadApp({}); const rows = snapFixture();
  await withMock(c, { goal_funding_snapshots: rows }, { cap: 3 }, () => c.reloadGoalSnapshots());
  assert(c._goalSnapLoadStatus === 'loaded', 'status ' + c._goalSnapLoadStatus);
  const got = Object.keys(c.goalSnapData).reduce((n, w) => n + Object.keys(c.goalSnapData[w]).length, 0);
  assert(got === 8, 'all 8 plan-2026 rows must be present in the model projection; got ' + got + ' (partial page accepted as loaded)');
  assert(Array.isArray(c.goalSnapRows) && c.goalSnapRows.length === 9, 'full-fidelity store must hold all 9 rows of every plan year; got ' + (c.goalSnapRows && c.goalSnapRows.length));
});
testAsync('T-SNAP-1 (b) a short or count-mismatched load makes Goals and closeout unavailable with the reason; no funded value renders', async () => {
  const c = K.loadApp({}); const rows = snapFixture();
  await withMock(c, { goal_funding_snapshots: rows }, { cap: 3, dropFromPages: { table: 'goal_funding_snapshots', ids: ['s004', 's005'] } }, () => c.reloadGoalSnapshots());
  assert(c._goalSnapLoadStatus !== 'loaded', 'a short load must not be marked loaded');
  assert(c.goalSnapRows.length === 0 && Object.keys(c.goalSnapData).length === 0, 'a partial history must not be retained');
  const store = captureDom(c); const vmod = vmFor(c);
  ['savings', 'priorities', 'funding', 'engine'].forEach(tab => {
    c.goalsSubTab = tab; c.renderGoals(vmod);
    const h = store['goals-content'].innerHTML;
    assert(/Goal funding history is unavailable/.test(h) && h.indexOf(c._goalSnapLoadReason) >= 0, tab + ': reason not shown');
    assert(!/goal-tbl-funded|Overall .* Progress|engine-output/.test(h), tab + ': a funded value rendered');
  });
  c.renderOverview(vmod);
  const ov = store['overview-content'].innerHTML;
  assert(/Goal funding history is unavailable/.test(ov) && !/Fund next queue item|ov3-alloc-row/.test(ov), 'overview rendered goal funding from a partial load');
  c._reconBasis = 'posted_current_balance';
  assert(c.canSaveRecon(7) === false && /Goal funding history is unavailable/.test(c.reconSaveBlockedReason(7)), 'closeout must be unavailable with the reason');
  // A complete load followed by a short reload must not leave the earlier history in place.
  const f = K.loadApp({});
  await withMock(f, { goal_funding_snapshots: rows }, { cap: 3 }, () => f.reloadGoalSnapshots());
  assert(f._goalSnapLoadStatus === 'loaded' && f.goalSnapRows.length === 9, 'setup: first load complete');
  await withMock(f, { goal_funding_snapshots: rows }, { cap: 3, dropFromPages: { table: 'goal_funding_snapshots', ids: ['s004'] } }, () => f.reloadGoalSnapshots());
  assert(f._goalSnapLoadStatus !== 'loaded' && f.goalSnapRows.length === 0 && Object.keys(f.goalSnapData).length === 0, 'a short reload kept the earlier history');
});
testAsync('T-SNAP-1 (c) a changing load (retried once) and a failed page both fail closed', async () => {
  const c = K.loadApp({}); const base = snapFixture();
  const grow = { table: 'goal_funding_snapshots', rowsAt: (n, rows) => rows.concat([Object.assign(snapRow(90, 2026, 6, 'alaska', 'reconciliation', null), { funded_amount: 500 + n, updated_at: '2026-12-31T00:00:0' + n + 'Z' })]) };
  await withMock(c, { goal_funding_snapshots: base }, { cap: 3, mutate: grow }, () => c.reloadGoalSnapshots());
  assert(c._goalSnapLoadStatus !== 'loaded' && /changed while loading/.test(c._goalSnapLoadReason), 'changing load: ' + c._goalSnapLoadStatus + ' / ' + c._goalSnapLoadReason);
  const d = K.loadApp({});
  await withMock(d, { goal_funding_snapshots: base }, { cap: 3, failPage: { table: 'goal_funding_snapshots', at: 2 } }, () => d.reloadGoalSnapshots());
  assert(d._goalSnapLoadStatus === 'error' && /HTTP 500/.test(d._goalSnapLoadReason) && d.goalSnapRows.length === 0, 'failed page: ' + d._goalSnapLoadStatus);
  const e = K.loadApp({});
  await withMock(e, { goal_funding_snapshots: base }, { noCount: 'goal_funding_snapshots' }, () => e.reloadGoalSnapshots());
  assert(e._goalSnapLoadStatus !== 'loaded' && /exact .* count/.test(e._goalSnapLoadReason), 'missing exact count must fail closed');
});
testAsync('T-SNAP-1 (d) row fidelity: plan-2026 and plan-2027 rows at week 30 stay distinct with model_year, source and note', async () => {
  const c = K.loadApp({});
  await withMock(c, { goal_funding_snapshots: snapFixture() }, { cap: 4 }, () => c.reloadGoalSnapshots());
  assert(Array.isArray(c.goalSnapRows), 'no full-fidelity snapshot store: model_year, source and note are discarded');
  const w30 = c.goalSnapRows.filter(r => r.week_num === 30).map(r => [r.model_year, r.goal_id, r.source, r.note, typeof r.created_at]);
  K.deepEq(K.plain(w30).sort(), [[2026, 'adam_ira', 'reconciliation', null, 'string'], [2027, 'adam_ira_2027', 'opening_anchor', 'carry:adam_ira', 'string']], 'week-30 rows');
  assert(c.goalSnapData[30] && c.goalSnapData[30].adam_ira === 120 && !('adam_ira_2027' in c.goalSnapData[30]), 'the model projection must hold plan-2026 rows only (year-neutral)');
  const dupe = snapFixture().concat([Object.assign(snapRow(22, 2026, 30, 'adam_ira', 'correction', 'x'), { id: 's999' })]);
  const d = K.loadApp({});
  await withMock(d, { goal_funding_snapshots: dupe }, { cap: 4 }, () => d.reloadGoalSnapshots());
  assert(d._goalSnapLoadStatus !== 'loaded', 'two rows for one (model_year, week, goal) must fail closed');
  assert(d.goalSnapRows.length === 0 && Object.keys(d.goalSnapData).length === 0, 'rows read before the duplicate must not be retained');
});
testAsync('T-SNAP-1 (e) the commitment load pages completely across plan years and fails closed when short', async () => {
  const c = K.loadApp({}); const cc = ccFixture();
  await withMock(c, { cash_commitments: cc, weekly_reconciliations: [] }, { cap: 2 }, () => c.reloadReconAndCommitments());
  assert(c._commitmentLoadStatus === 'loaded' && c.commitmentData.length === 7, 'all 7 commitments of every plan year must load; got ' + c.commitmentData.length);
  assert(c.commitmentData.some(r => r.model_year === 2027), 'other plan years are loaded, not filtered out');
  await withMock(c, { cash_commitments: cc, weekly_reconciliations: [] }, { cap: 2, dropFromPages: { table: 'cash_commitments', ids: ['c003'] } }, () => c.reloadReconAndCommitments());
  assert(c._commitmentLoadStatus !== 'loaded' && c.commitmentData.length === 0, 'a short reload kept the earlier commitments');
  const d = K.loadApp({});
  await withMock(d, { cash_commitments: cc, weekly_reconciliations: [] }, { cap: 2, dropFromPages: { table: 'cash_commitments', ids: ['c003'] } }, () => d.reloadReconAndCommitments());
  assert(d._commitmentLoadStatus !== 'loaded' && d.commitmentData.length === 0, 'a short commitment load must not be used');
  d._goalSnapLoadStatus = 'loaded'; d._reconBasis = 'posted_current_balance';
  assert(d.canSaveRecon(7) === false && /Commitments are unavailable/.test(d.reconSaveBlockedReason(7)), 'closeout must be unavailable with the reason');
  const store = captureDom(d);
  const html = d.renderCommitmentVisibility(20, d.applyCompletionSnapshots(d.runModel(7000, 7694.87)));
  assert(/Commitments are unavailable/.test(html), 'commitment visibility must state the load is unavailable');
});

// T-SNAP-1 (f)/(g): G1, Goals and Overview depend on both loads (commitments clamp the goal sweep;
// snapshots anchor each goal's funded amount in runModel), so missing evidence makes them
// unavailable. It is never shown as zero commitments, a valid $0, NO_MODEL_OBJECTION or a hold.
const SNAP1_AUTH = { state: 'AUTHORIZED', since: '2026-10-07', basis: 'test-only context (never the product constant)' };
function snap1App(state) {
  const c = K.loadApp({}); c.overrideData = {};
  c.reconData = { 17: { chk: 22000, sav: 9000, amx: 0, tax: 0, lc: 0, balance_basis: 'posted_current_balance' } };
  c._c11ApplySnapshots({ kind: 'ok', rows: state.snaps || [] });
  c._c11ApplyCommitments({ kind: 'ok', rows: state.commitments || [] });
  if (state.failCommitments) c._c11ApplyCommitments({ kind: 'incomplete', msg: 'loaded 0 of 1 commitments' });
  if (state.failSnaps) c._c11ApplySnapshots({ kind: 'failed', msg: 'HTTP 500' });
  const W = c.applyCompletionSnapshots(c.runModel(7000, 7694.87));
  const keys = W.find(x => x.num === 18).acKeys.filter(k => typeof k === 'string' && k.indexOf('goal_') === 0);
  return { c, W, keys };
}
const SNAP1_CARD = { id: 'x1', expected_item_id: 'synth_card_pay', model_year: 2026, commitment_source: 'wd_reconciliation', origin_model_week: 17,
  payee: 'SYNTH CARD', commitment_class: 'credit_card_payment', required_or_discretionary: 'protected_required', source_account: 'truist_checking',
  affects_deployable_cash: true, amount_cents: 300000, status: 'pending', reflected_model_week: null, resolved_model_week: null, resolution_type: null };
function snap1Unavailable(t, reasonRe, label) {
  const g1 = t.c.g1ResultForWeek(18, t.W);
  assert(g1.status === 'UNAVAILABLE' && !(g1.items || []).length, label + ': G1 must be UNAVAILABLE with no verdicts; got ' + g1.status + ' ' + JSON.stringify((g1.items || []).map(i => [i.actionKey, i.verdict])));
  assert(t.keys.length > 0, label + ': fixture must carry goal recommendations');
  t.keys.forEach(k => {
    const d = t.c.goalActionDecision(18, k, null, t.W);
    assert(!d.actionable && d.model && d.model.verdict === 'WITHHOLD' && reasonRe.test(d.model.reason), label + ': ' + k + ' must WITHHOLD as unavailable; got ' + JSON.stringify(d.model));
    assert(!/hold/i.test(d.model.reason), label + ': unavailability must not be reported as a hold');
  });
  // The write guard refuses on the model side alone: even with owner authority granted in this test context.
  t.c.GOAL_FUNDING_OWNER_AUTHORITY = SNAP1_AUTH;
  t.keys.forEach(k => assert(t.c.g1WriteGuard(18, k, null).allow === false, label + ': write guard allowed ' + k + ' with authority granted'));
  const wk = t.c.renderWeekDetail(t.W.find(x => x.num === 18), t.W);
  assert(!/No model objection/.test(wk), label + ': Weekly still shows a model answer');
  const store = captureDom(t.c); const vmod = t.c.buildDashboardViewModel(t.W, { ak: 7000, rt: 7694.87 });
  ['savings', 'priorities', 'funding', 'engine'].forEach(tab => {
    t.c.goalsSubTab = tab; t.c.renderGoals(vmod); const h = store['goals-content'].innerHTML;
    assert(reasonRe.test(h) && !/goal-tbl-funded|Overall .* Progress|engine-output|Recommended \$/.test(h), label + ': Goals ' + tab + ' rendered goal amounts or no reason');
  });
  t.c.renderOverview(vmod); const ov = store['overview-content'].innerHTML;
  assert(reasonRe.test(ov) && !/Fund next queue item|ov3-alloc-row|All priority goals funded|Cushion thin|Retain — collision/.test(ov), label + ': Overview rendered a Next Dollar or queue answer');
}
test('T-SNAP-1 (f) a failed commitment load makes G1, Goals and Overview unavailable; the $3,000 reservation case never becomes NO_MODEL_OBJECTION', () => {
  const L = snap1App({ commitments: [SNAP1_CARD] });
  const wl = (L.c.g1ResultForWeek(18, L.W).items || []).find(i => i.actionKey === 'goal_wendy_ira');
  assert(wl && wl.verdict === 'WITHHOLD' && wl.reason === 'candidate_breach', 'loaded: Wendy IRA must be withheld by the $3,000 reservation; got ' + JSON.stringify(wl));
  L.c.GOAL_FUNDING_OWNER_AUTHORITY = SNAP1_AUTH;
  assert(L.c.g1WriteGuard(18, 'goal_adam_ira', null).allow === true, 'control: with complete evidence and authority, a validated item is allowed (guard is not vacuous)');
  const F = snap1App({ commitments: [SNAP1_CARD], failCommitments: true });
  assert(F.c.commitmentData.length === 0 && F.c._commitmentLoadStatus === 'incomplete', 'setup: the commitment load failed');
  snap1Unavailable(F, /Commitments are unavailable|commitments_unavailable/, 'commitments failed');
  const cv = F.c.renderCommitmentVisibility(18, F.W);
  assert(/Commitments are unavailable/.test(cv) && !/\$0\.00|no commitments/i.test(cv), 'missing commitments must not read as zero');
});
test('T-SNAP-1 (g) a failed snapshot load makes G1 unavailable: a goal the history shows funded is never re-recommended as NO_MODEL_OBJECTION', () => {
  const funded = [{ id: 'g1', model_year: 2026, week_num: 17, goal_id: 'wendy_ira', funded_amount: 7500, source: 'reconciliation', note: null, created_at: '2026-10-03T00:00:00Z' }];
  const L = snap1App({ snaps: funded });
  assert(L.keys.indexOf('goal_wendy_ira') < 0, 'loaded: the funded Wendy IRA goal is not recommended');
  const F = snap1App({ snaps: funded, failSnaps: true });
  assert(F.keys.indexOf('goal_wendy_ira') >= 0, 'setup: without history the model re-recommends the funded goal');
  snap1Unavailable(F, /Goal funding history is unavailable|goal_history_unavailable/, 'snapshots failed');
});

test('T-TR-4 Next Dollar (C23): every rendered occurrence carries the modeled/not-authorized caveat; getNextDollarRec unchanged', () => {
  const FORMS = /(Below floor — do not deploy\. Address deficit first\.|Retain — collision window in Wk [^<]*?\)|Cushion thin — hold until next income week\.|Fund next queue item: [^<]*?(?:remaining\)|pending CPA clearance)|All priority goals funded — hold pending next strategic decision)/g;
  let seen = 0;
  [null, -5000].forEach(chkShift => {
    const c = K.loadApp({}); c._goalSnapLoadStatus = 'loaded'; c._commitmentLoadStatus = 'loaded';
    const store = captureDom(c); const vmod = vmFor(c);
    if (chkShift !== null) vmod.weeks.forEach(w => { if (w.num === c.currentW) w.chk = c.OP_FL + chkShift; });
    c.renderOverview(vmod);
    const h = store['overview-content'].innerHTML;
    const m = [...h.matchAll(FORMS)];
    assert(m.length >= 2, 'expected both rendered Next Dollar sites; found ' + m.length);
    m.forEach(x => { const tail = h.slice(x.index + x[0].length, x.index + x[0].length + 160); assert(/modeled, not authorized/.test(tail), 'occurrence without caveat: ' + x[0]); });
    seen += m.length;
  });
  const base = fs.readFileSync(baseIndexPath(), 'utf8'), cur = fs.readFileSync(path.join(REPO, 'index.html'), 'utf8');
  const pinNow = PINS.pin(cur, 'getNextDollarRec');
  assert(pinNow === PINS.pin(base, 'getNextDollarRec') && pinNow.startsWith('6a3b9678'), 'getNextDollarRec source/pin changed: ' + pinNow);
  assert(seen >= 4, 'scenario coverage');
});
test('T-TR-5 allocation engine (C24): informational/not-authorized statement and 40% legacy label; steps and amounts unchanged', () => {
  function engineRun(indexPath) {
    const c = K.loadApp({ indexPath }); c._goalSnapLoadStatus = 'loaded'; c._commitmentLoadStatus = 'loaded';
    const store = captureDom(c); const vmod = vmFor(c);
    c.engineType = 'variable'; c.engineAmt = '2500'; c.renderApp = function () {};
    c.runEngine(vmod);
    c.goalsSubTab = 'engine'; c.renderGoals(vmod);
    return { steps: K.plain(c.engineResult), html: store['goals-content'].innerHTML };
  }
  const now = engineRun(), base = engineRun(baseIndexPath());
  K.deepEq(now.steps, base.steps, 'engine steps');
  assert(now.steps.some(s => s.type === 'tax'), 'fixture must exercise the 40% step');
  assert(/Informational only\. Not authorized while OWNER HOLD is on \(before Gate F\)\./.test(now.html), 'informational statement missing');
  assert(/Legacy 40% rule, not current household tax policy/.test(now.html), '40% legacy label missing');
});
test('X-C18 (C18): the legacy suite passes 5G1C1-12 at every Package A boundary date', () => {
  ['2026-12-27', '2027-01-02', '2027-01-03', '2027-01-10'].forEach(d => {
    let out = '', code = 0;
    try { out = execFileSync(process.execPath, [path.join(REPO, 'test_regression.js')], { cwd: REPO, encoding: 'utf8', env: Object.assign({}, process.env, { HFOS_TEST_DATE: d }), stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 }); }
    catch (e) { code = e.status; out = String(e.stdout); }
    assert(code === 0 && /✓ 5G1C1-12/.test(out), d + ': legacy suite exit ' + code + (/✗ 5G1C1-12/.test(out) ? ' (5G1C1-12 failed)' : ''));
  });
});

// ── Owner A-1: package-completion gate (fail closed) ──────────────────────────
console.log('── Package completion (A-1) ──');
const SYN = entries => ({ _meta: { packages: { A: 'a', B: 'b', D: 'd' } }, entries });
const OK = () => true;
test('PKGA-DONE-1 a package with zero PENDING entries passes completion', () => {
  const r = CONTRACTS.packageCompletion(SYN([{ id: 'X1', package: 'B', status: 'ACTIVE', impl: 'f#X1' }, { id: 'X2', package: 'B', status: 'ACTIVE', impl: 'f#X2' }]), 'B', OK);
  assert(r.complete && r.owned === 2 && r.pending.length === 0, JSON.stringify(r));
});
test('PKGA-DONE-2 one PENDING entry fails completion and is named', () => {
  const r = CONTRACTS.packageCompletion(SYN([{ id: 'X1', package: 'B', status: 'ACTIVE', impl: 'f#X1' }, { id: 'T-GL-8', package: 'B', status: 'PENDING' }]), 'B', OK);
  assert(!r.complete && r.pending.length === 1 && r.pending[0] === 'T-GL-8', JSON.stringify(r));
});
test('PKGA-DONE-3 every PENDING entry stays visible', () => {
  const r = CONTRACTS.packageCompletion(SYN(['P1', 'P2', 'P3'].map(id => ({ id, package: 'D', status: 'PENDING' }))), 'D', OK);
  K.deepEq(r.pending, ['P1', 'P2', 'P3'], 'pending list'); assert(!r.complete, 'must not be complete');
});
test('PKGA-DONE-4 entries owned by another package do not block the package being checked', () => {
  const reg = SYN([{ id: 'X1', package: 'B', status: 'ACTIVE', impl: 'f#X1' }, { id: 'P1', package: 'D', status: 'PENDING' }]);
  assert(CONTRACTS.packageCompletion(reg, 'B', OK).complete && !CONTRACTS.packageCompletion(reg, 'D', OK).complete, 'cross-package leakage');
});
test('PKGA-DONE-5 fail closed: unknown package, and an ACTIVE entry whose test does not resolve', () => {
  throws(() => CONTRACTS.packageCompletion(SYN([]), 'Z', OK), /unknown package "Z"/);
  const r = CONTRACTS.packageCompletion(SYN([{ id: 'X1', package: 'B', status: 'ACTIVE', impl: 'test_rollover.js#NO-SUCH-TEST-ID-xyz' }]), 'B');
  assert(!r.complete && r.unresolved[0] === 'X1', 'unresolvable ACTIVE impl must block completion');
});
test('PKGA-DONE-6 real registry: Package A is COMPLETE; each later package reports exactly its registry state; C-G remain NOT COMPLETE', () => {
  const reg = CONTRACTS.loadRegistry();
  const a = CONTRACTS.packageCompletion(reg, 'A');
  assert(a.complete && a.owned === 12, 'Package A must satisfy its own completion rule: ' + JSON.stringify(a));
  const report = {};
  ['B', 'C', 'D', 'E', 'F', 'G'].forEach(p => {
    const r = CONTRACTS.packageCompletion(reg, p), owned = reg.entries.filter(e => e.package === p);
    const expectComplete = owned.length > 0 && owned.every(e => e.status === 'ACTIVE');
    assert(r.owned === owned.length && r.complete === (expectComplete && r.unresolved.length === 0), p + ': completion does not match the registry');
    assert(r.pending.length === owned.filter(e => e.status !== 'ACTIVE').length, p + ': pending list incomplete');
    report[p] = r.complete ? 'COMPLETE' : 'NOT COMPLETE (' + r.pending.length + ' pending, ' + r.unresolved.length + ' unresolved)';
  });
  ['C', 'D', 'E', 'F', 'G'].forEach(p => assert(!CONTRACTS.packageCompletion(reg, p).complete, p + ' must still be NOT COMPLETE'));
  process.stdout.write('    package completion: ' + JSON.stringify(report) + '\n');
});
test('PKGA-DONE-7 the completion CLI gate exits 0 for Package A and 1 for a package with PENDING contracts', () => {
  const cli = args => { try { return { code: 0, out: execFileSync(process.execPath, [path.join(REPO, 'tools', 'rollover-contracts.js')].concat(args), { cwd: REPO, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }) }; } catch (e) { return { code: e.status, out: String(e.stdout) + String(e.stderr) }; } };
  const a = cli(['complete', 'A']), d = cli(['complete', 'D']), z = cli(['complete', 'Z']);
  assert(a.code === 0 && /^COMPLETE: package A/.test(a.out), a.out);
  assert(d.code === 1 && /NOT COMPLETE: package D/.test(d.out) && /PENDING T-ID-1/.test(d.out) && /PENDING T-TR-8/.test(d.out), d.out);
  assert(z.code === 1 && /unknown package/.test(z.out), z.out);
});

(async () => {
for (const t of _asyncB) {
  try { await t.fn(); pass++; process.stdout.write('  ✓ ' + t.name + '\n'); }
  catch (e) { fail++; failures.push({ name: t.name, error: e.message }); process.stdout.write('  ✗ ' + t.name + '\n    → ' + e.message + '\n'); }
}
console.log('\n══ RESULTS ══');
console.log('  Passed:  ' + pass);
console.log('  Failed:  ' + fail);
if (fail) { failures.forEach(f => console.log('  ✗ ' + f.name + ' → ' + f.error)); process.exit(1); }
console.log('  ✅ ALL ROLLOVER TESTS PASSED');
process.exit(0);
})();
