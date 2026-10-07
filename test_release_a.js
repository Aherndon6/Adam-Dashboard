// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Herndon Financial OS — Post-A1b Release A: owner-authority gate, goal truth, reconciliation
// prefill integrity, commitment visibility, deferral wording. FAILING-FIRST contract suite.
// ───────────────────────────────────────────────────────────────────────────────────────────────
// Companion to test_g1.js (the G1 validator contract). Loads HFOS_INDEX (default ./index.html).
// Tags: [RA-BASE] boundaries that hold before and after; [RA] contract (RED before implementation).
//
// Approved vocabulary (owner, 2026-09-19): RECOMMENDED (model proposal) · NO MODEL OBJECTION / WITHHOLD
// (G1 verdict) · AUTHORIZED / NOT AUTHORIZED (owner authority) · ACTIONABLE = NO MODEL OBJECTION + AUTHORIZED
// · MARKED DONE (operator assertion, not bank-verified) · RESERVED/INITIATED (commitment evidence)
// · FUNDED (reconciled snapshot only).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
let pass = 0, fail = 0; const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function assert(c, m) { if (!c) throw new Error(m || 'Assertion failed'); }
const htmlPath = process.env.HFOS_INDEX || './index.html';
const html = fs.readFileSync(htmlPath, 'utf8');
let sc = html.match(/<script>([\s\S]*?)<\/script>/)[1];
sc = sc.replace(/\bconst\b/g, 'var').replace(/^try\s*\{[\s\S]*?\}\s*catch[\s\S]*?\}/m, '').replace(/^loadAll\(\);/m, '');
// 2027 rollover Package A: deterministic clock (HFOS_TEST_DATE, default the legacy pin date).
const ROLLOVER_KIT = require('./tools/rollover-test-kit');
const stub = ROLLOVER_KIT.clockStubSource(process.env.HFOS_TEST_DATE) + `
var __els={};var __slot={innerHTML:'',addEventListener:function(){},value:'',textContent:'',style:{},classList:{remove:function(){},add:function(){}},scrollIntoView:function(){}};
var __errEl={textContent:'',style:{display:'none'}};
var window={fetch:function(){return Promise.resolve({ok:true,json:function(){return Promise.resolve([])}});}};
var document={getElementById:function(id){return __els[id]||__slot;},querySelector:function(s){return s==='.recon-error'?__errEl:null},querySelectorAll:function(){return[]},addEventListener:function(){},createElement:function(){return{style:{},appendChild:function(){},setAttribute:function(){}}},body:{appendChild:function(){}}};
var localStorage={getItem:function(){return null;},setItem:function(){},removeItem:function(){}};
var requestAnimationFrame=function(){};var fetch=window.fetch;var alert=function(){};
var supabase={createClient:function(){return{auth:{getSession:function(){return Promise.resolve({data:{session:null},error:null});},signInWithPassword:function(){return Promise.resolve({data:null,error:{message:'mock'}});},signOut:function(){return Promise.resolve({error:null});},onAuthStateChange:function(){}}};}};
`;
try { eval(stub + sc); } catch (e) { console.error('FATAL eval:', e.message); process.exit(1); }
// 2027 rollover Package A: 2026 characterization runs on the frozen 2026 composition
// (WD_2026_FROZEN once the product defines it; before the rollover WD is that source).
if (typeof WD_2026_FROZEN !== 'undefined') WD = WD_2026_FROZEN;
renderApp = function () {};
const _origWarn = console.warn, _origErr = console.error;
function quiet(on) { console.warn = on ? function () {} : _origWarn; console.error = on ? function () {} : _origErr; }
function fnSrc(name) { const i = html.search(new RegExp('(async )?function ' + name + '\\(')); assert(i >= 0, name + ' not found'); let d = 0, k = html.indexOf('{', i); for (; k < html.length; k++) { if (html[k] === '{') d++; else if (html[k] === '}') { d--; if (d === 0) break; } } return html.slice(i, k + 1); }
function need(name) { assert(typeof eval(name) !== 'undefined', name + ' is not implemented'); return eval(name); }
function countingFetch() { const box = { n: 0, calls: [] }; fetch = function (u, o) { box.n++; box.calls.push({ u: String(u), m: (o && o.method) || 'GET' }); return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve([]); } }); }; return box; }
function asOwner() { USER_ROLE = 'owner'; getAuthHeaders = async function () { return {}; }; }
const AUTH_OK = { state: 'AUTHORIZED', since: '2026-09-19', basis: 'test-only' };
const NMO = { actionKey: 'goal_wendy_ira', verdict: 'NO_MODEL_OBJECTION', reason: 'no_model_objection', amount: 1000 };
const WH = { actionKey: 'goal_wendy_ira', verdict: 'WITHHOLD', reason: 'candidate_breach', amount: 1000 };
// Minimal copies of the G1 synthetic fixture helpers (test_g1.js) for the FX tests.
const GOLD = { id: 'gold-1', expected_item_id: null, model_year: 2026, commitment_source: 'manual_reconciliation', origin_model_week: 15, source_account: 'truist_checking', amount_cents: 1132586, status: 'initiated', affects_deployable_cash: true, reflected_model_week: null, resolved_model_week: null, resolution_type: null };
function weekObj(num, chk, extra) { return Object.assign({ num, chk, mChk: chk, reconciled: false, ac: [], acKeys: [], cashAvailability: { reservedProtectedCents: 0, reviewRequired: false, balanceBasisUnknown: false } }, extra || {}); }
function acLine(amt, dest, name) { return 'Transfer $' + amt.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' from Truist Checking to ' + dest + ' (' + name + ')'; }
function synthetic(recs, dips, opts) {
  opts = opts || {}; const num = 10, last = opts.last || 20; const base = opts.base || 20000;
  const weeks = [weekObj(num - 1, 30000, { reconciled: true })];
  for (let n = num; n <= last; n++) weeks.push(weekObj(n, dips && dips[n] != null ? dips[n] : base));
  const w = weeks.find(x => x.num === num); w.ac = recs.map(r => acLine(r.amt, r.dest || 'AMEX Savings', r.name)); w.acKeys = recs.map(r => r.key);
  if (opts.reservedCents) for (const x of weeks) if (x.num >= num) x.cashAvailability.reservedProtectedCents = opts.reservedCents;
  if (opts.mutate) opts.mutate(weeks);
  const eff = []; for (let n = num; n <= last; n++) eff.push([n, '', [], [], (opts.evs && opts.evs[n]) || [], 0, 0, '']);
  return { num, weeks, effectiveWD: eff, commitments: opts.commitments || [], floor: 6500, minHorizonWeeks: 5 };
}
function G1(ctx) { return g1ValidateRecommendations(ctx); }
const item = (res, key) => (res.items || []).find(i => i.actionKey === key);


// ═══ Authority gate ═════════════════════════════════════════════════════════════════════════════
test('[RA] AU-1 authority missing / malformed / unknown → NOT_AUTHORIZED (fail closed); the shipped state is NOT_AUTHORIZED', () => {
  const f = need('goalOwnerAuthority'); const save = GOAL_FUNDING_OWNER_AUTHORITY;
  try {
    assert(f().state === 'NOT_AUTHORIZED', 'shipped authority must be NOT_AUTHORIZED');
    for (const bad of [undefined, null, 'AUTHORIZED', {}, { state: 'AUTHORIZED' }, { state: 'AUTHORIZED', since: 'soon' }, { state: 'authorized', since: '2026-09-19' }, { state: 'MAYBE', since: '2026-09-19' }, 42]) {
      GOAL_FUNDING_OWNER_AUTHORITY = bad; assert(f().state === 'NOT_AUTHORIZED', 'must fail closed for ' + JSON.stringify(bad));
    }
    GOAL_FUNDING_OWNER_AUTHORITY = AUTH_OK; assert(f().state === 'AUTHORIZED', 'well-formed AUTHORIZED must be recognised');
  } finally { GOAL_FUNDING_OWNER_AUTHORITY = save; }
});
test('[RA] AU-2 NO MODEL OBJECTION + NOT AUTHORIZED → not actionable, with the owner reason', () => {
  const c = need('composeGoalActionability'); const d = c(NMO, { state: 'NOT_AUTHORIZED', reason: 'owner_not_authorized' });
  assert(d.actionable === false && d.reasons.some(r => /owner/.test(r)), JSON.stringify(d));
  const p = need('goalRowPresentation')(d, false); assert(p.checkboxDisabled === true, 'checkbox must be disabled');
  assert(p.lines.join(' ').match(/Not authorized/i), 'row must say not authorized: ' + JSON.stringify(p));
});
test('[RA] AU-3 toggleTransfer refuses a goal key with ZERO requests when not actionable (not authorized / G1 withhold / G1 unavailable)', async () => {
  need('goalActionDecision'); asOwner(); quiet(true);
  try {
    _xfrWriteCtx['16_90'] = { actionKey: 'goal_wendy_ira', completedLabel: 'Transfer $1,000.00 from Truist Checking to AMEX Savings (Wendy IRA)', amount: 1000, matchTaskIdx: null };
    const box = countingFetch(); await toggleTransfer(16, '16_90', true);
    assert(box.n === 0, 'goal write must be refused, saw ' + box.n + ' request(s)');
  } finally { quiet(false); }
});
test('[RA] AU-3b the dormant toggleTask path also refuses goal keys (no optimistic write, no request)', async () => {
  need('goalActionDecision'); asOwner(); quiet(true);
  try { const box = countingFetch(); delete taskData['16_44']; await toggleTask(16, 44, true, 'goal_wendy_ira', 1000);
    assert(box.n === 0 && !taskData['16_44'], 'goal toggleTask must be refused before any write'); } finally { quiet(false); }
});
test('[RA] AU-4 unticking a goal row is always allowed (one write)', async () => {
  asOwner(); quiet(true);
  try {
    const lbl = 'Transfer $1,000.00 from Truist Checking to AMEX Savings (Wendy IRA)';
    taskData['16_7'] = { completed: true, completedAt: '2026-09-20T00:00:00Z', completedAmount: 1000, actionKey: 'goal_wendy_ira', completedLabel: lbl };
    _xfrWriteCtx['16_91'] = { actionKey: 'goal_wendy_ira', completedLabel: lbl, amount: 1000, matchTaskIdx: 7 };
    const box = countingFetch(); await toggleTransfer(16, '16_91', false); delete taskData['16_7'];
    assert(box.n === 1, 'untick of an existing completion must write once, saw ' + box.n);
  } finally { quiet(false); }
});
test('[RA] AU-5 display, toggleTransfer and toggleCustomTask all consult the ONE canonical goalActionDecision', () => {
  need('goalActionDecision');
  assert(/goalActionDecision\(/.test(fnSrc('toggleTransfer')), 'toggleTransfer must call goalActionDecision');
  assert(/goalActionDecision\(/.test(fnSrc('toggleCustomTask')), 'toggleCustomTask must call goalActionDecision');
  assert(/goalActionDecision\(/.test(fnSrc('renderWeekDetail')), 'renderWeekDetail must call goalActionDecision');
  assert(/goalActionDecision\(/.test(fnSrc('g1WriteGuard')), 'g1WriteGuard must delegate to goalActionDecision');
  assert(/composeGoalActionability\(/.test(fnSrc('goalActionDecision')), 'goalActionDecision must use composeGoalActionability');
  assert(/canWriteFinancials\(\)&&!\(_gp&&_gp\.checkboxDisabled\)/.test(fnSrc('renderWeekDetail')), 'goal row checkbox must be disabled from the canonical decision');
});
test('[RA] AU-6 non-goal actions are outside the gate (a neutral key still writes once)', async () => {
  asOwner(); quiet(true);
  try {
    _xfrWriteCtx['16_92'] = { actionKey: 'lc_boost', completedLabel: 'Move $500 Checking → LC', amount: 500, matchTaskIdx: null };
    const box = countingFetch(); await toggleTransfer(16, '16_92', true); assert(box.n === 1, 'non-goal write must proceed, saw ' + box.n);
    assert(need('goalActionDecision')(16, 'lc_boost', 500).scope === 'not_goal');
  } finally { quiet(false); }
});
test('[RA] AU-7 autoBackfillGoal follow-up goal tasks (gd_goal_…) cannot be ticked; ordinary custom tasks can', async () => {
  need('goalKeyForCustomTask'); asOwner(); quiet(true);
  try {
    const gid = 'gd_goal_wendy_ira_1726790000000_ab12', oid = 'ct_manual_1';
    customTaskData[16] = [{ id: gid, label: 'Transfer $500.00 from Truist Checking to AMEX Savings (Wendy IRA — additional allocation)', completed: false }, { id: oid, label: 'Call the bank', completed: false }];
    let box = countingFetch(); await toggleCustomTask(16, gid, true); assert(box.n === 0, 'follow-up goal task must be refused, saw ' + box.n);
    box = countingFetch(); await toggleCustomTask(16, oid, true); assert(box.n >= 1, 'ordinary custom task must still write');
    assert(goalKeyForCustomTask(gid) === 'goal_wendy_ira' && goalKeyForCustomTask(oid) === null);
  } finally { quiet(false); }
});
function withG1Stub(items, fn) {
  const saveR = g1ResultForWeek, saveA = GOAL_FUNDING_OWNER_AUTHORITY;
  g1ResultForWeek = function () { return { status: 'OK', reasons: [], items: items }; }; GOAL_FUNDING_OWNER_AUTHORITY = AUTH_OK;
  try { return fn(); } finally { g1ResultForWeek = saveR; GOAL_FUNDING_OWNER_AUTHORITY = saveA; }
}
test('[RA] AU-7b a follow-up allocation stays WITHHOLD even when authorized and the base recommendation has no model objection', () => withG1Stub([NMO], () => {
  const d = goalActionDecision(16, 'goal_wendy_ira', null, null, { followup: true }); assert(d.actionable === false && /followup/.test(d.reasons.join(' ')), JSON.stringify(d));
  assert(goalActionDecision(16, 'goal_wendy_ira', 1000).actionable === true, 'control: the validated recommendation itself is actionable when authorized');
}));
test('[RA] AU-11 a write amount above the validated (net) amount is not actionable, even when authorized', () => withG1Stub([NMO], () => {
  for (const amt of [1000.01, 5000, -1, 0, 'abc']) { const d = goalActionDecision(16, 'goal_wendy_ira', amt); assert(d.actionable === false, 'amount ' + amt + ' must not be actionable'); }
  assert(goalActionDecision(16, 'goal_wendy_ira', 999.99).actionable === true, 'an amount within the validated amount is actionable');
}));
test('[RA] AU-8 the authority value is period-independent (calendar date + state only; no model-week fields)', () => {
  const a = need('GOAL_FUNDING_OWNER_AUTHORITY'); const keys = Object.keys(a).sort().join(',');
  assert(/^basis,since,state$/.test(keys), 'unexpected authority fields: ' + keys);
  assert(/^\d{4}-\d{2}-\d{2}$/.test(a.since), 'since must be a calendar date'); assert(a.state === 'NOT_AUTHORIZED');
});
test('[RA] AU-9 recording reconciled truth is outside the gate (closeout path does not consult it)', () => {
  need('goalActionDecision');
  for (const fn of ['submitCloseout', 'renderCloseoutConfirm']) assert(!/goalActionDecision|goalOwnerAuthority/.test(fnSrc(fn)), fn + ' must not be gated');
});
test('[RA] AU-10 composition: only NO MODEL OBJECTION + AUTHORIZED is actionable; disagreement / missing inputs fail closed', () => {
  const c = need('composeGoalActionability'); const OK = { state: 'AUTHORIZED', reason: 'owner_authorized' };
  assert(c(NMO, OK).actionable === true, 'NMO + AUTHORIZED must be actionable');
  assert(c(WH, OK).actionable === false, 'WITHHOLD + AUTHORIZED must not be actionable');
  assert(c(null, OK).actionable === false, 'missing model verdict must not be actionable');
  assert(c(NMO, null).actionable === false, 'missing authority must not be actionable');
  assert(c({ verdict: 'SAFE' }, OK).actionable === false, 'unknown verdict must not be actionable');
});

// ═══ Goal truth ═════════════════════════════════════════════════════════════════════════════════
function withGoalState(fn) {
  const save = { currentW, reconData: Object.assign({}, reconData), snap: JSON.parse(JSON.stringify(goalSnapData || {})), task: Object.assign({}, taskData) };
  try { return fn(); } finally { currentW = save.currentW; reconData = save.reconData; goalSnapData = save.snap; taskData = save.task; }
}
function openWeekVm() {
  currentW = 16; delete reconData[16]; reconData[15] = reconData[15] || { chk: 26699.77, balance_basis: 'posted_current_balance' };
  goalSnapData[15] = Object.assign({}, goalSnapData[15] || {}, { wendy_ira: 0, bailey_529: 0 });
  return { weeks: [{ num: 15, reconciled: true, goalSaved: { wendy_ira: 0 }, ac: [], acKeys: [] },
    { num: 16, reconciled: false, goalSaved: { wendy_ira: 7500, bailey_529: 3500 }, ac: ['Transfer $7,500.00 from Truist Checking to AMEX Savings (Wendy IRA)'], acKeys: ['goal_wendy_ira'], realActs: ['Transfer $7,500.00 from Truist Checking to AMEX Savings (Wendy IRA)'], realActKeys: ['goal_wendy_ira'] }] };
}
test('[RA] TR-1 in an open week, displayed "funded" is the last reconciled snapshot, never the model recommendation', () => withGoalState(() => {
  const vm = openWeekVm(); const f = need('goalFundedForDisplay');
  assert(f('wendy_ira', vm) === 0, 'funded must be 0 (snapshot), got ' + f('wendy_ira', vm)); assert(f('bailey_529', vm) === 0, 'bailey funded must be 0');
  for (const fn of ['renderOverview', '_renderGoalsSavings', '_renderGoalsPriorities', '_renderGoalsFunding'])
    assert(!/getGoalFunded\(/.test(fnSrc(fn)) && /goalFundedForDisplay\(/.test(fnSrc(fn)), fn + ' must display goalFundedForDisplay');
}));
test('[RA-BASE] TR-1b getGoalFunded itself is unchanged (golden-master pinned; model-side calculators keep it)', () => withGoalState(() => {
  const vm = openWeekVm(); assert(getGoalFunded('wendy_ira', vm) === 7500, 'getGoalFunded must still return the model goalSaved');
}));
test('[RA] TR-2 a ticked goal line in an unreconciled week is "Marked done — awaiting reconciliation", not funded', () => withGoalState(() => {
  const vm = openWeekVm(); taskData['16_0'] = { completed: true, completedAmount: 7500, actionKey: 'goal_wendy_ira', completedLabel: 'x' };
  const s = need('goalOpenWeekStatus')('wendy_ira', vm); assert(s.markedDone === 7500 && goalFundedForDisplay('wendy_ira', vm) === 0, JSON.stringify(s));
  const p = goalRowPresentation({ scope: 'goal', actionable: false, model: WH, owner: { state: 'NOT_AUTHORIZED' }, reasons: [] }, true);
  assert(/Marked done — awaiting reconciliation/.test(p.lines.join(' ') + p.badgeText), 'done wording: ' + JSON.stringify(p));
  assert(p.checkboxDisabled === false, 'unticking must remain possible');
}));
test('[RA] TR-3 an unticked recommendation reads "Recommended — not executed"', () => withGoalState(() => {
  const vm = openWeekVm(); const s = goalOpenWeekStatus('wendy_ira', vm); assert(s.recommended === 7500, JSON.stringify(s));
  const p = goalRowPresentation({ scope: 'goal', actionable: false, model: NMO, owner: { state: 'NOT_AUTHORIZED' }, reasons: [] }, false);
  assert(/Recommended — not executed/.test(p.badgeText + ' ' + p.lines.join(' ')), JSON.stringify(p));
}));
test('[RA] TR-4 a reconciled current week keeps today\'s behaviour (snapshot overlay)', () => withGoalState(() => {
  currentW = 15; reconData[15] = { chk: 1 }; goalSnapData[15] = { wendy_ira: 1234.5 };
  const vm = { weeks: [{ num: 15, reconciled: true, goalSaved: { wendy_ira: 1234.5 } }] }; assert(need('goalFundedForDisplay')('wendy_ira', vm) === 1234.5);
}));
test('[RA] TR-5 no unreconciled goal state is described as funded / transferred / executed', () => {
  const p1 = need('goalRowPresentation')({ scope: 'goal', actionable: false, model: NMO, owner: { state: 'NOT_AUTHORIZED' }, reasons: [] }, false);
  const p2 = goalRowPresentation({ scope: 'goal', actionable: false, model: WH, owner: { state: 'NOT_AUTHORIZED' }, reasons: [] }, true);
  // Affirmative claims only: the approved negative labels ("not executed", "not to be executed") are allowed.
  for (const p of [p1, p2]) { const t = (p.badgeText + ' ' + p.lines.join(' ')).toLowerCase().replace(/not (to be )?executed/g, '').replace(/not bank-verified/g, '');
    assert(!/\bfunded\b|transferred|\bexecuted\b|bank-verified/.test(t), 'overclaim: ' + t); }
  const hist = fnSrc('renderWeekDetail'); assert(/Marked done earlier/.test(hist), 'goal executed-history rows must say "Marked done earlier"');
});
test('[RA] TR-7 "Transfers this week": an unexecuted model allocation is never shown as funded/done', () => {
  const f = need('goalSummaryLine'); const x = { l: 'Wendy IRA $7,500.00 → AMEX Savings — Wendy IRA funded!', r: 'done', _key: 'goal_wendy_ira' };
  const a = f(x, false, false); assert(a.icon !== '✅' && /Recommended — not executed/.test(a.rsn) && !/funded/i.test(a.l), JSON.stringify(a));
  const b = f(x, true, false); assert(/Marked done — awaiting reconciliation/.test(b.rsn) && !/funded/i.test(b.l), JSON.stringify(b));
  const c = f({ l: 'Bailey 529 $164.01 → AMEX Savings: $3,335.99 remaining', r: 'done', _key: 'goal_bailey_529' }, false, true);
  assert(/reconciled goal snapshot is the funding record/.test(c.rsn) && !/remaining/.test(c.l), JSON.stringify(c));
  assert(/goalSummaryLine\(/.test(fnSrc('renderWeekDetail')), 'renderWeekDetail must use goalSummaryLine');
});
test('[RA] TR-6 model-only figures carry an explicit caveat (Overview AMEX forecast; Model Avg Sweep)', () => {
  // Updated by intent (Fable Pass 2 D3/D4): the caveats are derived (authority-aware / week-aware), not literals.
  assert(/Model Avg Sweep \/ Month[\s\S]{0,400}modelSweepCaveat\(\)/.test(html), 'Avg Sweep caveat missing');
  assert(/AMEX Savings — IRA \+ 529s[\s\S]{0,600}amexForecastCaveat\(_grw\)/.test(html), 'AMEX forecast caveat missing');
});

// ═══ Reconciliation prefill integrity ═══════════════════════════════════════════════════════════
test('[RA] PF-1 unreconciled week: inputs start EMPTY; model values are separate, labelled estimates', () => {
  const f = need('_reconPrefillValues'); const w = { num: 16, reconciled: false, mChk: 17825.86, mSav: 1, mAmx: 21745.17, mTax: 2, mLc: 3 };
  _reconBalances = null; _reconDraft = null; const r = f(w);
  for (const k of ['chk', 'sav', 'amx', 'tax', 'lc']) assert(r.values[k] === '', k + ' must start empty, got ' + r.values[k]);
  assert(r.reference && r.reference.amx === 21745.17 && r.referenceIsModel === true, 'model reference missing: ' + JSON.stringify(r));
  assert(/estimate/i.test(fnSrc('renderWeekDetail')) && /_reconPrefillValues\(/.test(fnSrc('renderWeekDetail')), 'render must use the helper and label estimates');
});
function runBegin(vals) {
  asOwner(); canSaveRecon = function () { return true; }; closeoutState = function () { return 'open'; };
  __els = {}; for (const k of Object.keys(vals)) __els[k] = { value: vals[k] }; __errEl.textContent = ''; __errEl.style.display = 'none';
  _reconBalances = null; quiet(true); const box = countingFetch();
  try { beginCloseout(16); } catch (e) { /* downstream harness limits after capture are irrelevant */ } finally { quiet(false); }
  return { bal: _reconBalances, err: __errEl.textContent, fetches: box.n };
}
const ALL = v => ({ ri_chk: v, ri_sav: v, ri_amx: v, ri_tax: v, ri_lc: v });
test('[RA] PF-2 beginCloseout refuses blank / whitespace / non-numeric / malformed balances before the confirmation (no capture, no write)', () => {
  for (const bad of ['', '   ', 'abc', '12,345.00', '1e3', '12.345', '--1', '.']) {
    const vals = ALL('100.00'); vals.ri_amx = bad; const r = runBegin(vals);
    assert(r.bal === null, 'must not capture balances for ' + JSON.stringify(bad) + ' (got ' + JSON.stringify(r.bal) + ')');
    assert(r.fetches === 0 && /bank balance/i.test(r.err), 'must show the entry error and write nothing for ' + JSON.stringify(bad));
  }
});
test('[RA] PF-3 an explicitly entered 0 is valid and distinguishable from blank', () => {
  const r = runBegin(ALL('0')); assert(r.bal && r.bal.chk === 0 && r.bal.amx === 0, 'literal 0 must be accepted: ' + JSON.stringify(r));
  const r2 = runBegin(Object.assign(ALL('0'), { ri_lc: '' })); assert(r2.bal === null, 'blank beside zeros must still be refused');
});
test('[RA] PF-4 saved draft and back-from-confirmation values keep precedence over the empty default', () => {
  const f = need('_reconPrefillValues'); const w = { num: 16, reconciled: false, mChk: 1, mSav: 1, mAmx: 1, mTax: 1, mLc: 1 };
  _reconBalances = null; _reconDraft = { week: 16, chk: '555.55' }; let r = f(w); assert(r.values.chk === '555.55' && r.values.amx === '', JSON.stringify(r.values));
  _reconDraft = { week: 16, amx: '' }; r = f(w); assert(r.values.amx === '', 'a deliberately cleared draft field stays cleared');
  _reconDraft = null; _reconBalances = { chk: 10, sav: 20, amx: 30, tax: 40, lc: 50 }; r = f(w); assert(r.values.amx === 30, 'back-from-confirmation values win');
  _reconBalances = null; _reconDraft = null;
});
test('[RA] PF-5 editing an already reconciled week still prefills its saved actuals', () => {
  const f = need('_reconPrefillValues'); _reconBalances = null; _reconDraft = null;
  const r = f({ num: 15, reconciled: true, actualBals: { chk: 26699.77, sav: 1, amx: 2, tax: 3, lc: 4 }, mChk: 999 });
  assert(r.values.chk === 26699.77 && r.referenceIsModel === false, JSON.stringify(r));
});

// ═══ Commitment visibility (T4) ═════════════════════════════════════════════════════════════════
const CM = (o) => Object.assign({ id: 'c1', model_year: PLAN_YEAR, source_account: 'truist_checking', affects_deployable_cash: true, status: 'initiated', origin_model_week: 15, reflected_model_week: null, resolved_model_week: null, resolution_type: null, amount_cents: 1132586, payee: 'AMEX Gold payment in transit', commitment_source: 'manual_reconciliation' }, o || {});
function cvRun(commitments, reservedCents, originReconciled) {
  const f = need('commitmentVisibilityRows'); const saveC = commitmentData; commitmentData = commitments;
  const weeks = [{ num: 15, reconciled: originReconciled !== false, cashAvailability: { reservedProtectedCents: 0 } }, { num: 16, reconciled: false, cashAvailability: { reservedProtectedCents: reservedCents } }];
  try { return f(16, weeks); } finally { commitmentData = saveC; }
}
test('[RA] CV-1a counted reservation → deducted for goal recommendations; projected checking still includes it', () => {
  const r = cvRun([CM()], 1132586); const row = r.rows[0]; assert(r.status === 'OK' && row.counted === true, JSON.stringify(r));
  assert(/Deducted from deployable cash for goal recommendations/.test(row.wording) && /Projected checking[^.]*still includes it until it posts/.test(row.wording), row.wording);
});
test('[RA] CV-1b bank_pending → counted, plus review required', () => {
  const r = cvRun([CM({ status: 'bank_pending' })], 1132586); assert(/Review required/.test(r.rows[0].wording), r.rows[0].wording);
});
test('[RA] CV-1c origin week not reconciled → recorded, not yet counted', () => {
  const r = cvRun([CM()], 0, false); assert(r.rows[0].counted === false && /Recorded, not yet counted against deployable cash/.test(r.rows[0].wording), JSON.stringify(r));
});
test('[RA] CV-1d reflected / resolved → not shown as in flight', () => {
  const r = cvRun([CM({ reflected_model_week: 15 }), CM({ id: 'c2', resolved_model_week: 16, status: 'cleared' })], 0); assert(r.rows.length === 0, JSON.stringify(r));
});
test('[RA] CV-1e other account / not affecting deployable cash / voided / paid elsewhere → "Not deducted from Truist Checking capacity"', () => {
  for (const o of [{ source_account: 'truist_savings' }, { affects_deployable_cash: false }, { status: 'voided' }, { resolution_type: 'paid_from_other_account' }]) {
    const r = cvRun([CM(o)], 0); const rows = r.rows.filter(x => !x.hidden);
    assert(rows.length === 0 || (rows[0].counted === false && /Not deducted from Truist Checking capacity/.test(rows[0].wording)), JSON.stringify(o) + ' → ' + JSON.stringify(r));
  }
});
test('[RA] CV-2 UI-derived reserved set ≠ model reserved total → RESERVATION STATUS UNAVAILABLE (no stronger claim)', () => {
  const r = cvRun([CM()], 999); assert(r.status === 'UNAVAILABLE' && /Reservation status unavailable/i.test(r.wording || ''), JSON.stringify(r));
  assert(!(r.rows || []).some(x => /Deducted/.test(x.wording)), 'no deducted claim when unavailable');
});
test('[RA] CV-3 wording never keys on commitment classification', () => {
  const a = cvRun([CM({ commitment_class: 'other_transfer' })], 1132586).rows[0].wording, b = cvRun([CM({ commitment_class: 'credit_card_payment' })], 1132586).rows[0].wording;
  assert(a === b, 'classification must not change wording');
});

// ═══ Deferral / verdict wording (G2) ════════════════════════════════════════════════════════════
test('[RA] DW-1 candidate-caused WITHHOLD names the breach week and attributes it to this transfer', () => {
  const t = need('g1VerdictText')({ verdict: 'WITHHOLD', reason: 'candidate_breach', breachWeek: 21, preExistingBreach: false, minChk: 4083.36 });
  assert(/Withhold/.test(t) && /this transfer/i.test(t) && /Cal 43/.test(t) && /\$6,500/.test(t), t);
});
test('[RA] DW-2 pre-existing breach WITHHOLD says the model is already below the floor without this week\'s goal transfers', () => {
  const t = need('g1VerdictText')({ verdict: 'WITHHOLD', reason: 'pre_existing_breach', breachWeek: 21, preExistingBreach: true, preExistingWeek: 28, minChk: 4083.36 });
  assert(/already below \$6,500/.test(t) && /without this week/.test(t) && /Cal 50/.test(t), t);
});
test('[RA] DW-3 a lookahead defer after a higher-priority allocation says the room was used, not that this goal is a floor risk', () => {
  const f = need('g2DeferText'); const used = f('Bryce 529 deferred — 5-wk lookahead: floor risk', true);
  assert(/higher-priority/.test(used) && !/floor risk/.test(used), used);
  const genuine = f('Bailey 529 deferred — 5-wk lookahead: floor risk', false); assert(/below \$6,500/.test(genuine), genuine);
  assert(/g2DeferText\(/.test(fnSrc('renderWeekDetail')), 'renderWeekDetail must use g2DeferText');
});

// ═══ Fable Pass 1 / Pass 2 fixes (RED first) ═════════════════════════════════════════════════════
test('[RA] FX-B1 an active What-If scenario makes G1 UNAVAILABLE (estimates never validate a recommendation)', () => {
  const save = scenarioState; try {
    scenarioState = { active: true, type: 'inflow', weekNum: 16, params: { amount: '50000', taxable: false }, previewOverride: null, previewGoal: null, commitModal: false };
    const r = g1ResultForWeek(16); assert(r.status === 'UNAVAILABLE' && r.reasons.indexOf('scenario_active') >= 0, JSON.stringify({ s: r.status, r: r.reasons }));
    assert(goalActionDecision(16, 'goal_wendy_ira', 1).actionable === false);
  } finally { scenarioState = save; }
});
test('[RA] FX-B2 no display surface pairs the snapshot "funded" with the model "remaining" (Priorities ✅/Funded badge)', () => {
  for (const fn of ['renderOverview', '_renderGoalsSavings', '_renderGoalsPriorities', '_renderGoalsFunding']) {
    const src = fnSrc(fn); assert(!(/goalFundedForDisplay\(/.test(src) && /getGoalRemaining\(/.test(src)), fn + ' mixes display funded with model remaining');
  }
});
test('[RA] FX-D2 reconciled-week goal rows say reconciled — never "awaiting reconciliation" or "Recommended"', () => {
  for (const done of [true, false]) {
    const p = goalRowPresentation({ scope: 'goal', actionable: false, model: WH, owner: { state: 'NOT_AUTHORIZED' }, reasons: [] }, done, true);
    const t = p.badgeText + ' ' + p.lines.join(' ');
    assert(/Reconciled/.test(t) && !/awaiting reconciliation|Recommended|Not authorized|snapshot is the funding record/.test(t) && p.checkboxDisabled === true, JSON.stringify(p));  // Fable P2 N11
  }
  assert(/goalRowPresentation\([^;]*w\.reconciled/.test(fnSrc('renderWeekDetail')), 'render must pass w.reconciled');
});
test('[RA] FX-D3 "not authorized" wording follows the authority constant (never hard-coded)', () => {
  const lines = need('goalOpenWeekLines'), cav = need('modelSweepCaveat'), save = GOAL_FUNDING_OWNER_AUTHORITY;
  try {
    assert(/not authorized/.test(lines({ markedDone: 0, recommended: 100 }).join(' ')) && /not authorized/.test(cav()), 'NOT_AUTHORIZED wording');
    GOAL_FUNDING_OWNER_AUTHORITY = AUTH_OK;
    assert(!/not authorized/.test(lines({ markedDone: 0, recommended: 100 }).join(' ')) && !/not authorized/.test(cav()), 'AUTHORIZED must not say not authorized');
  } finally { GOAL_FUNDING_OWNER_AUTHORITY = save; }
  assert(!/not executed; not authorized/.test(html) && !/modeled, not authorized</.test(html), 'no hard-coded authority literals remain');
});
test('[RA] FX-D4 AMEX forecast caveat matches the browsed week (reconciled / current open / future)', () => {
  const f = need('amexForecastCaveat'); const saveW = currentW; try {
    currentW = 16;
    assert(/reconciled/i.test(f({ num: 15, reconciled: true })) && !/not a bank balance/.test(f({ num: 15, reconciled: true })), 'reconciled');
    assert(/this week's recommended transfers/.test(f({ num: 16, reconciled: false })), 'current open');
    assert(/every modeled transfer/.test(f({ num: 20, reconciled: false })), 'future');
  } finally { currentW = saveW; }
});
test('[RA] FX-D5 commitment wording in a reconciled week refers to the reconciled (posted) balance, not "projected checking below"', () => {
  const saveC = commitmentData; commitmentData = [CM()];
  try {
    const r = commitmentVisibilityRows(15, [{ num: 15, reconciled: true, cashAvailability: { reservedProtectedCents: 1132586, reservedCommitmentCount: 1 } }]);
    const t = r.rows[0].wording; assert(!/Projected checking below/.test(t) && !/\(posted\)/.test(t) && /reconciled balance still includes it/.test(t), t);  // Fable P2 N13: basis may not be posted
  } finally { commitmentData = saveC; }
});
test('[RA] FX-D6 partial goal rows: "Partially marked done"; note says "already marked done", never "already transferred"', () => {
  const p = goalRowPresentation({ scope: 'goal', actionable: false, model: NMO, owner: { state: 'NOT_AUTHORIZED' }, reasons: [] }, false, false, true);
  assert(/Partially marked done/.test(p.badgeText), JSON.stringify(p));
  const src = fnSrc('renderWeekDetail'); assert(/already marked done this cycle/.test(src) && !/already transferred this cycle/.test(src), 'partial note wording');
});
test('[RA] FX-N1 the zero-checking-impact adam_ira seed line does not make the week UNAVAILABLE', () => {
  const c = synthetic([{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }], null);
  const w = c.weeks.find(x => x.num === 10); w.ac.push('Transfer $3,772.74 from Truist Savings to AMEX Savings (IRA Holding) — Adam IRA seed'); w.acKeys.push('goal_adam_ira_seed');
  const r = G1(c); assert(r.status === 'OK' && item(r, 'goal_wendy_ira').verdict === 'NO_MODEL_OBJECTION', JSON.stringify(r.reasons));
});
test('[RA] FX-N2 follow-up task ids with any goal-id charset are still recognised', () => {
  assert(goalKeyForCustomTask('gd_goal_Bryce-Vehicle_1726790000000_ab12') === 'goal_Bryce-Vehicle');
});
test('[RA] FX-N3 a linked stop only removes ITS commitment while it is still reserved (no erasing other reservations)', () => {
  const c1 = Object.assign({}, GOLD, { id: 'L1', origin_model_week: 9, amount_cents: 300000, expected_item_id: 'eidX', resolved_model_week: 15 });
  const c2 = Object.assign({}, GOLD, { id: 'M1', origin_model_week: 9, amount_cents: 100000, expected_item_id: 'manual_x' });
  const dips = {}; for (let n = 10; n <= 14; n++) dips[n] = 20000; for (let n = 15; n <= 20; n++) dips[n] = 7200;
  const ctx = synthetic([{ key: 'goal_wendy_ira', amt: 100, name: 'Wendy IRA' }], dips, { commitments: [c1, c2], evs: { 13: [{ t: 'ob', a: -3000, eid: 'eidX' }] },
    mutate: ws => ws.forEach(w => { if (w.num >= 10) w.cashAvailability.reservedProtectedCents = w.num <= 14 ? 400000 : 100000; }) });
  const it = item(G1(ctx), 'goal_wendy_ira'); assert(it.verdict === 'WITHHOLD' && it.minChk === 6200, JSON.stringify(it));
});
test('[RA] FX-N4 the authority object is frozen and declared const in source', () => {
  assert(Object.isFrozen(GOAL_FUNDING_OWNER_AUTHORITY) && /const GOAL_FUNDING_OWNER_AUTHORITY=Object\.freeze\(/.test(html));
});
test('[RA] FX-N6 "Transfers this week" treats a bound completion as marked done even with a NULL amount', () => {
  const src = fnSrc('renderWeekDetail');
  assert(/if\(td&&td\.completed\)_trDone\[ak\]=true;/.test(src), 'completion map must not require an amount');
  assert(/goalSummaryLine\(x,!!_trDone\[x\._key\]/.test(src), 'summary must key marked-done on completion, not on a non-null amount');
});
test('[RA] FX-P2N1 NO MODEL OBJECTION wording is precise about income', () => {
  const t = g1VerdictText({ verdict: 'NO_MODEL_OBJECTION' }); assert(!/variable income not counted/.test(t) && /not yet entered/.test(t), t);
});
test('[RA] FX-P2N8 reservation parity checks the COUNT as well as the sum (G1 and T4)', () => {
  const c = synthetic([{ key: 'goal_wendy_ira', amt: 100, name: 'Wendy IRA' }], null, { base: 20000, reservedCents: 300000, commitments: [Object.assign({}, GOLD, { origin_model_week: 9, amount_cents: 300000 })],
    mutate: ws => ws.forEach(w => { w.cashAvailability.reservedCommitmentCount = 2; }) });
  assert(G1(c).status === 'UNAVAILABLE', 'G1 must fail closed on count mismatch');
  const saveC = commitmentData; commitmentData = [CM()];
  try { const r = commitmentVisibilityRows(16, [{ num: 15, reconciled: true, cashAvailability: { reservedProtectedCents: 0 } }, { num: 16, reconciled: false, cashAvailability: { reservedProtectedCents: 1132586, reservedCommitmentCount: 2 } }]);
    assert(r.status === 'UNAVAILABLE', 'T4 must fail closed on count mismatch'); } finally { commitmentData = saveC; }
});
test('[RA] FX-P2N10 the marked-done line states its scope (unreconciled weeks)', () => {
  assert(/unreconciled weeks/.test(need('goalOpenWeekLines')({ markedDone: 50, recommended: 0 }).join(' ')));
});

test('[RA] FX-N14 a seed row reads as outside the model check (not "not a current recommendation") and is never actionable', () => {
  const d = goalActionDecision(16, 'goal_adam_ira_seed', null); assert(d.actionable === false && /seed/.test(d.reasons.join(' ')), JSON.stringify(d));
  assert(/outside the model check/.test(g1VerdictText(d.model)));
});
test('[RA] FX-N12 the reconciled AMEX caveat says "at reconciliation", not "at closeout"', () => {
  assert(/at reconciliation/.test(amexForecastCaveat({ num: 1, reconciled: true })) && !/closeout/.test(amexForecastCaveat({ num: 1, reconciled: true })));
});

// ═══ Adam Extra Pay category (Wendy request 2026-09-22; owner decisions same day) ═══════════════
// Budgeted salary belongs in income.net_salary; net pay above the budgeted base belongs in
// income.extra_pay. Excluded (not represented) for the same reason as its sibling
// income.bkcpa_extra_pay: supplemental pay handled by the weekly model, not a recurring salary line.
const XP = 'income.extra_pay';
function xpLive(key, over) {
  return Object.assign({ key: key, label: key, parent_key: key.indexOf('.') > 0 ? key.split('.')[0] : null,
    is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked',
    cashflow_treatment: 'operating', merged_into_key: null, display_order: 1 }, over || {});
}
const xpIncome = over => xpLive(XP, Object.assign({ behavior_class: 'income', budget_treatment: 'display_only' }, over || {}));

test('[RA] XP-1 income.extra_pay is declared in BUDGET_INCOME_EXCLUSIONS with a substantive reason', () => {
  const ex = need('BUDGET_INCOME_EXCLUSIONS');
  assert(Object.prototype.hasOwnProperty.call(ex, XP), XP + ' is not declared in BUDGET_INCOME_EXCLUSIONS');
  assert(typeof ex[XP] === 'string' && ex[XP].trim().length > 10, 'no substantive reason for ' + XP);
  assert(Object.isFrozen(ex), 'declaration must stay frozen');
});

test('[RA] XP-2 the exclusion set is exactly five keys — the four A1b keys plus income.extra_pay', () => {
  const ks = Object.keys(need('BUDGET_INCOME_EXCLUSIONS')).sort();
  assert(JSON.stringify(ks) === JSON.stringify(['business.jabian_deposits_2026', 'income.bkcpa_extra_pay',
    XP, 'income.deep_south_commissions', 'income.interest'].sort()), 'exclusion keys are ' + JSON.stringify(ks));
});

test('[RA] XP-3 income.extra_pay is excluded, never represented — the registry stays at 41 entries', () => {
  assert(BUDGET_CATEGORY_REGISTRY.length === 41, 'registry is ' + BUDGET_CATEGORY_REGISTRY.length + ' entries; Extra Pay must not be represented');
  assert(!_budgetRegistryEntry(XP), XP + ' must not be a registry entry (represented ∩ excluded = ∅)');
  assert(_budgetIncomeCoverage([xpIncome()]).overlap.length === 0, 'overlap reported for ' + XP);
});

test('[RA] XP-4 INV-C — a live, active, income-countable income.extra_pay produces no violation', () => {
  const r = _budgetIncomeCoverage([xpIncome()]);
  assert(r.violations.length === 0, 'INV-C violations: ' + JSON.stringify(r.violations));
  assert(r.findings.length === 0, 'INV-C findings: ' + JSON.stringify(r.findings));
});

test('[RA] XP-5 the exclusion is load-bearing — drop it and the same category is flagged', () => {
  const ex = Object.assign({}, need('BUDGET_INCOME_EXCLUSIONS')); delete ex[XP];
  const r = _budgetIncomeCoverage([xpIncome()], ex);
  assert(r.violations.indexOf(XP) >= 0, 'without its exclusion ' + XP + ' must be an INV-C violation: ' + JSON.stringify(r));
});

test('[RA] XP-6 a non-income Extra Pay row is an audit finding, not a silent pass', () => {
  const r = _budgetIncomeCoverage([xpLive(XP, { behavior_class: 'expense', budget_treatment: 'tracked' })]);
  assert(r.findings.indexOf(XP) >= 0, 'expected an audit finding: ' + JSON.stringify(r));
});

test('[RA] XP-7 Extra Pay is income for Register classification and never counts as Budget spend', () => {
  const c = xpIncome();
  assert(_isCountableBudgetIncome(c) === true, 'Extra Pay must be countable income');
  assert(_isCountableBudgetSpend(c) === false, 'Extra Pay must never count as Budget spend');
  const cls = _classifyRegisterRow({ category_key: XP, amount: 411.14 }, { [XP]: c });
  assert(cls.kind === 'counted' && cls.as === 'income', 'Register classification: ' + JSON.stringify(cls));
});

test('[RA] XP-8 Wendy\'s income.bkcpa_extra_pay is untouched — still excluded, still its own key', () => {
  const ex = need('BUDGET_INCOME_EXCLUSIONS');
  assert(Object.prototype.hasOwnProperty.call(ex, 'income.bkcpa_extra_pay'), 'Wendy\'s category lost its exclusion');
  assert(ex['income.bkcpa_extra_pay'] !== ex[XP], 'the two extra-pay categories must carry distinct reasons');
  const r = _budgetIncomeCoverage([xpIncome(), xpLive('income.bkcpa_extra_pay', { behavior_class: 'income', budget_treatment: 'display_only' })]);
  assert(r.violations.length === 0 && r.findings.length === 0, 'both extra-pay categories must coexist cleanly: ' + JSON.stringify(r));
});

// ═══ Boundaries ════════════════════════════════════════════════════════════════════════════════
test('[RA-BASE] runModel, submitCloseout, computeGoalTransferNetting, resolveWeekTransfers, isReservedAsOf, getCashAvailabilityEngine unchanged in role (present)', () => {
  for (const n of ['runModel', 'submitCloseout', 'computeGoalTransferNetting', 'resolveWeekTransfers', 'isReservedAsOf', 'getCashAvailabilityEngine']) assert(typeof eval(n) === 'function', n);
});

(async () => {
  for (const t of tests) { try { await t.fn(); pass++; console.log('  ✓ ' + t.name); } catch (e) { fail++; console.log('  ✗ ' + t.name + '\n      ' + e.message); } }
  const tag = p => tests.filter(t => t.name.startsWith(p)).length;
  console.log('\nRESULTS  total ' + tests.length + ' · passed ' + pass + ' · failed ' + fail + '   ([RA] ' + tag('[RA] ') + ', [RA-BASE] ' + tag('[RA-BASE]') + ')');
  process.exit(0);
})();
