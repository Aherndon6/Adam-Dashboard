// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Herndon Financial OS — Post-A1b Release B (variable-income tax correctness): G3 + G4
// ───────────────────────────────────────────────────────────────────────────────────────────────
// Standalone; loads HFOS_INDEX (default ./index.html) like test_regression.js.
// Tags:
//   [RB-PIN]  characterization of engine facts G3 relies on (ca has no cash effect; the two waterfalls
//             are identical; Edit-Week derives ct/ca only from Tax?-ticked gross). GREEN before and after.
//   [RB]      Release B contract. RED before implementation, GREEN after.
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
var __slot={innerHTML:'',addEventListener:function(){},value:'',textContent:'',style:{},classList:{remove:function(){},add:function(){}},scrollIntoView:function(){}};
var window={fetch:function(){return Promise.resolve({ok:true,json:function(){return Promise.resolve([])}});}};
var document={getElementById:function(){return __slot;},querySelector:function(){return null},querySelectorAll:function(){return[]},addEventListener:function(){},createElement:function(){return{style:{},appendChild:function(){},setAttribute:function(){}}},body:{appendChild:function(){}}};
var localStorage={getItem:function(){return null;},setItem:function(){},removeItem:function(){}};
var requestAnimationFrame=function(){};var fetch=window.fetch;
var supabase={createClient:function(){return{auth:{getSession:function(){return Promise.resolve({data:{session:null},error:null});},signInWithPassword:function(){return Promise.resolve({data:null,error:{message:'mock'}});},signOut:function(){return Promise.resolve({error:null});},onAuthStateChange:function(){}}};}};
`;
try { eval(stub + sc); } catch (e) { console.error('FATAL eval:', e.message); process.exit(1); }
// 2027 rollover Package A: 2026 characterization runs on the frozen 2026 composition
// (WD_2026_FROZEN once the product defines it; before the rollover WD is that source).
if (typeof WD_2026_FROZEN !== 'undefined') WD = WD_2026_FROZEN;
renderApp = function () {}; setSection = function () {};
const r2 = x => Math.round(x * 100) / 100;
function fnSrc(name) { const i = html.indexOf('function ' + name + '('); assert(i >= 0, name + ' not found'); let d = 0, k = html.indexOf('{', i); for (; k < html.length; k++) { if (html[k] === '{') d++; else if (html[k] === '}') { d--; if (d === 0) break; } } return html.slice(i, k + 1); }
function runScenario(type, params, wn) {
  scenarioState = { active: false, type, weekNum: wn, params, previewOverride: null, previewGoal: null, commitModal: false };
  applyScenario(); return scenarioState.previewOverride;
}
function baseCtCa(wn) { const ex = overrideData[wn]; const wd = WD.find(w => w[0] === wn) || []; return { ct: ex && ex.ct != null ? ex.ct : (wd[5] || 0), ca: ex && ex.ca != null ? ex.ca : (wd[6] || 0) }; }
const WN = 20; // a future model week with no seed commission (ct = ca = 0)

// ═══ [RB-PIN] engine facts ═══════════════════════════════════════════════════════════════════
test('[RB-PIN] GS-1 ca has no cash effect in runModel: identical balances for ca=0 and ca=5,000 (ct fixed at 0)', () => {
  const save = overrideData[WN]; const wd = WD.find(w => w[0] === WN);
  const base = { week_num: WN, dates: wd[1], events_json: wd[4], ct: 0, ca: 0 };
  try {
    overrideData[WN] = Object.assign({}, base, { ca: 0 }); const A = runModel(7000, 7694.87);
    overrideData[WN] = Object.assign({}, base, { ca: 5000 }); const B = runModel(7000, 7694.87);
    for (let i = 0; i < A.length; i++) for (const k of ['chk', 'sav', 'amx', 'tax', 'lc']) assert(A[i][k] === B[i][k], 'wk ' + A[i].num + ' ' + k + ' differs: ' + A[i][k] + ' vs ' + B[i][k]);
  } finally { if (save === undefined) delete overrideData[WN]; else overrideData[WN] = save; }
});
test('[RB-PIN] GS-2 the commission-week waterfall (varWF) equals the regular waterfall (regWF)', () => {
  assert(JSON.stringify(VARIABLE_WATERFALL) === JSON.stringify(REGULAR_WATERFALL), 'waterfalls differ');
});
test('[RB-PIN] GS-3 Edit-Week derives ct/ca only from Tax?-ticked gross (untaxed inflow → ca 0)', () => {
  const src = fnSrc('saveWeekEdits');
  assert(/taxableGross=events\.filter\(function\(e\)\{return e\.t==='in'&&e\.tx;\}\)/.test(src), 'taxableGross must sum only tx-ticked inflows');
  assert(/const ca=Math\.round\(taxableGross\*0\.60\*100\)\/100/.test(src) || /var ca=Math\.round\(taxableGross\*0\.60\*100\)\/100/.test(src), 'ca must be 60% of taxableGross');
});

// ═══ [RB] G3 ═════════════════════════════════════════════════════════════════════════════════
test('[RB] GS-4 Commission scenario, Taxable OFF: ct and ca unchanged from base; gross still added as an (untaxed) inflow', () => {
  const b = baseCtCa(WN); const o = runScenario('commission', { gross: '5000', taxable: false }, WN);
  assert(o.ct === b.ct, 'ct must not change when not taxable: ' + o.ct + ' vs base ' + b.ct);
  assert(o.ca === b.ca, 'ca must not change when not taxable: ' + o.ca + ' vs base ' + b.ca);
  const added = o.events_json[o.events_json.length - 1];
  assert(added.t === 'in' && added.a === 5000 && !added.tx, 'gross must remain the inflow, untaxed: ' + JSON.stringify(added));
});
test('[RB] GS-5 Commission scenario, Taxable ON: current 40/60 behaviour preserved', () => {
  const b = baseCtCa(WN); const o = runScenario('commission', { gross: '5000', taxable: true }, WN);
  assert(o.ct === r2(b.ct + 2000) && o.ca === r2(b.ca + 3000), 'expected +2,000 ct / +3,000 ca, got ' + o.ct + ' / ' + o.ca);
  const added = o.events_json[o.events_json.length - 1]; assert(added.a === 5000 && added.tx === true, 'taxable inflow must carry tx');
});
test('[RB] GS-6 commit summary agrees with the Taxable setting', () => {
  runScenario('commission', { gross: '5000', taxable: false }, WN); scenarioState.commitModal = true; renderScenarioModal();
  const off = __slot.innerHTML; assert(!/40%|Tax HYSA|Tax Reserve/.test(off), 'untaxed summary must not claim a 40% reserve');
  assert(/not taxable|no tax reserve/i.test(off), 'untaxed summary must say no reserve applies');
  runScenario('commission', { gross: '5000', taxable: true }, WN); scenarioState.commitModal = true; renderScenarioModal();
  const on = __slot.innerHTML; assert(/40%/.test(on) && /60%/.test(on), 'taxable summary must state the 40/60 split');
});
test('[RB] GS-7 the preview override is ct/ca-identical to base when not taxable (no spurious "customized" via ct/ca)', () => {
  const b = baseCtCa(WN); const o = runScenario('commission', { gross: '1234.56', taxable: false }, WN);
  assert(Number(o.ct) === Number(b.ct) && Number(o.ca) === Number(b.ca), 'ct/ca must equal base');
  const inflow = runScenario('inflow', { amount: '1234.56', taxable: false, label: 'x' }, WN);
  assert(o.ct === inflow.ct && o.ca === inflow.ca, 'untaxed commission must match untaxed inflow on ct/ca');
});

// ═══ [RB] G3 additions (R3 base, owner test contract 2026-10-05) ════════════════════════════
function trajectory(o) { const save = overrideData[WN]; overrideData[WN] = o;
  try { return runModel(7000, 7694.87).map(w => [w.num, w.chk, w.sav, w.amx, w.tax, w.lc]); }
  finally { if (save === undefined) delete overrideData[WN]; else overrideData[WN] = save; } }
test('[RB] GS-8 Taxable OFF commission: model trajectory identical to the equivalent untaxed Inflow (no phantom reserve, no false floor breach)', () => {
  const com = runScenario('commission', { gross: '5000', taxable: false }, WN);
  const inf = runScenario('inflow', { amount: '5000', taxable: false, label: 'x' }, WN);
  const A = trajectory(com), B = trajectory(inf);
  const i = A.findIndex((r, k) => JSON.stringify(r) !== JSON.stringify(B[k]));
  assert(i < 0, 'trajectories differ from week ' + (i >= 0 ? A[i][0] : '') + ': commission ' + JSON.stringify(A[i]) + ' vs inflow ' + JSON.stringify(B[i]));
});
test('[RB] GS-9 commit path: a Taxable OFF commission scenario never POSTs a phantom tax reserve to model_week_overrides', async () => {
  const b = baseCtCa(WN); const save = overrideData[WN]; const sent = [];
  const _fetch = fetch, _cw = canWriteFinancials, _ah = getAuthHeaders, _cl = clearScenario;
  try {
    fetch = function (u, init) { sent.push({ u: String(u), m: (init && init.method) || 'GET', body: init && init.body }); return Promise.resolve({ ok: true, status: 201, json: function () { return Promise.resolve([]); } }); };
    canWriteFinancials = function () { return true; }; getAuthHeaders = async function () { return {}; }; clearScenario = function () {};
    runScenario('commission', { gross: '5000', taxable: false }, WN);
    await commitScenario();
    const posts = sent.filter(x => x.m === 'POST' && /model_week_overrides/.test(x.u));
    assert(posts.length === 1, 'expected exactly one model_week_overrides POST, got ' + posts.length);
    const body = JSON.parse(posts[0].body);
    assert(Number(body.ct) === Number(b.ct), 'committed ct must equal base (no phantom reserve): ' + body.ct + ' vs ' + b.ct);
    assert(Number(body.ca) === Number(b.ca), 'committed ca must equal base: ' + body.ca + ' vs ' + b.ca);
    const added = body.events_json[body.events_json.length - 1]; assert(added.a === 5000 && !added.tx, 'committed gross must be the untaxed inflow');
  } finally { fetch = _fetch; canWriteFinancials = _cw; getAuthHeaders = _ah; clearScenario = _cl; if (save === undefined) delete overrideData[WN]; else overrideData[WN] = save; }
});
test('[RB] GS-10 commit path control: a Taxable ON commission scenario still POSTs the 40/60 split (unchanged behaviour)', async () => {
  const b = baseCtCa(WN); const save = overrideData[WN]; const sent = [];
  const _fetch = fetch, _cw = canWriteFinancials, _ah = getAuthHeaders, _cl = clearScenario;
  try {
    fetch = function (u, init) { sent.push({ u: String(u), m: (init && init.method) || 'GET', body: init && init.body }); return Promise.resolve({ ok: true, status: 201, json: function () { return Promise.resolve([]); } }); };
    canWriteFinancials = function () { return true; }; getAuthHeaders = async function () { return {}; }; clearScenario = function () {};
    runScenario('commission', { gross: '5000', taxable: true }, WN);
    await commitScenario();
    const body = JSON.parse(sent.filter(x => x.m === 'POST' && /model_week_overrides/.test(x.u))[0].body);
    assert(body.ct === r2(b.ct + 2000) && body.ca === r2(b.ca + 3000), 'taxable commit must carry +2,000 ct / +3,000 ca: ' + body.ct + ' / ' + body.ca);
  } finally { fetch = _fetch; canWriteFinancials = _cw; getAuthHeaders = _ah; clearScenario = _cl; if (save === undefined) delete overrideData[WN]; else overrideData[WN] = save; }
});

// ═══ [RB] G4 — policy-neutral wording, owner-approved contract P1–P24 (G4-STRING-REVIEW.md, 2026-10-05) ══
// TX-1 (frozen B) is REPLACED by TX-1′: it required the obsolete 2026-09-19 policy text, which the contract forbids.
// Every surface is extracted by its own anchor and must match EXACTLY ONCE (fail-closed on 0 or >1), so no test
// can pass by inspecting the wrong occurrence or fail on an unrelated one (e.g. the AU-11 comment at R3 :1812/:1842).
const strip = h => String(h).replace(/<[^>]+>/g, '');
function one(src, re, what) { const m = [...String(src).matchAll(re)]; assert(m.length === 1, what + ': anchor must match exactly once, matched ' + m.length); return m[0]; }
const APPROVED_60 = 'is not transferred separately and remains subject to the normal weekly waterfall';
const FINAL = {
  P1: 'Taxable: ticked = the model reserves 40% of this inflow for taxes; unticked = no tax reserve',
  P3: 'Tax reserve (Tax?)',
  P4: 'Tick <strong>Tax?</strong> on an inflow to have the model reserve <strong>40%</strong> of it for taxes: a transfer from Checking to <strong>Vio Bank - Tax Reserve</strong> (carried forward if Checking has no room above the floor). Leave it unticked and no tax reserve is created. The rest of the inflow is not transferred separately and remains subject to the normal weekly waterfall.',
  P5: 'When an inflow is marked <strong>Tax?</strong> in Edit Week, the model reserves <strong>40%</strong> of it as a transfer from Checking to <strong>Vio Bank - Tax Reserve</strong>. Inflows not marked Tax? create no tax reserve. The remaining 60% is not transferred separately and remains subject to the normal weekly waterfall.',
  P6: '<code>COMM_TAX = $707.18</code> and <code>COMM_AK = $1,060.76</code> are the 40% / 60% shares of the seeded Week 6 commission. Only <code>COMM_TAX</code> is a modeled transfer. <code>COMM_AK</code> moves no money; the 60% remainder is not transferred separately and remains subject to the normal weekly waterfall.',
  P7: 'When a commission week has no surplus above the floor, the 40% commission tax transfer defers under the commission_tax action identity through commTaxPending.',
  P8: 'Commission tax: 40% → Tax Reserve for an inflow marked Tax? (seeded on the Wk 6 commission); the 60% remainder is not transferred separately',
  P9: 'For an inflow marked Tax?, the model reserves 40% as a transfer to Vio Bank Tax Reserve; the rest is not transferred separately and remains subject to the normal weekly waterfall. Inflows not marked Tax? create no tax reserve. Commission tax preserves its own <code>commission_tax</code> identity and carries forward through <code>commTaxPending</code> if floor-blocked.',
  P10: 'Use Edit Week to add one-time inflows. Tick "Tax?" if you want the model to reserve 40% of that inflow for taxes; leave it unticked for no tax reserve.',
  P11: 'Sets aside 40% for tax first, then allocates the rest',
  P12: 'No tax set-aside — paycheck overage, extra cash',
  P13: 'Variable Income mode sets aside 40% for taxes before any other allocation. Choose Regular Surplus for income you are not reserving tax on.',
  P13_LABEL: '40% Tax Reserve → Vio Bank (Tax HYSA)',
  P14: 'Add commission income (40% tax reserve only if Taxable)',
  P15: 'Taxable (model reserves 40% for taxes)',
  P18: 'Taxable (model reserves 40% for taxes)',
  P20: 'Base tax reserve: $521.36 | Variable-income tax: an inflow marked taxable reserves 40% as a Checking → Vio transfer (deferred if below floor); untaxed inflows create no reserve; the 60% remainder is not transferred separately and remains subject to the normal weekly waterfall. Seeded Wk 6 commission: COMM_TAX $707.18 (transfer), COMM_AK $1,060.76 (no transfer; it only marks the week as a commission week, which selects a waterfall identical to the regular one).',
  P21: 'Week, gross amount, taxable toggle, with 40% tax-reserve preview when Taxable',
  // P23 (owner amendment 2026-10-05, contract now P1–P23): the Goal Funding Order footnote's pre-waterfall sentences.
  P23: 'Pre-waterfall: Base tax reserve ($521.36) and commission tax (40% → Vio for an inflow marked Tax?) are applied before the waterfall.',
  // P24 (owner amendment after Fable F2, contract now P1–P24): the Calendar Notes model Wk 6 item. Only the 40% (COMM_TAX) moves; it defers one week.
  P24: '<strong>Cal Wk 29 / Jul 13 (model Wk 6)</strong> — Commission week with heavy AMEX Gold; the 40% commission tax transfer defers one week. CHK ~$5,000.',
};
// What-If renderers (real code, stubbed DOM). active:false keeps the runModel diff table out of the form.
function whatIf(type, params, commitModal) { scenarioState = { active: !!commitModal, type, weekNum: WN, params, previewOverride: null, previewGoal: null, commitModal: !!commitModal }; }
function formHtml(type, params) { whatIf(type, params, false); return _renderScenarioForm(null); }
function summaryOf(type, params) { whatIf(type, params, true); renderScenarioModal();
  return one(__slot.innerHTML, /<div class="sc-modal-body"[^>]*><strong>You are about to make this permanent:<\/strong><br><br>([\s\S]*?)<\/div>/g, type + ' commit summary')[1]; }
function previewRows(taxable) { const h = formHtml('commission', { gross: '5000', taxable });
  const box = one(h, /<div class="sc-preview-box">([\s\S]*?)<\/div><button class="sc-apply-btn"/g, 'commission preview box (taxable=' + taxable + ')')[1];
  return { box, labels: [...box.matchAll(/<span class="sc-diff-lbl">([^<]*)<\/span>/g)].map(m => m[1]) }; }
function cardDescs() { // both renderers; every scenario type card
  whatIf('commission', { gross: '5000', taxable: false }, false); renderScenarios(null); const a = __slot.innerHTML; const b = _renderScenariosInline(null);
  const out = {}; for (const [r, h] of [['renderScenarios', a], ['_renderScenariosInline', b]]) for (const t of ['commission', 'expense', 'inflow', 'goal'])
    out[r + ':' + t] = one(h, new RegExp("selectScenarioType\\('" + t + "'\\)\">[\\s\\S]*?<div class=\"stc-desc\">([^<]*)</div>", 'g'), r + ' ' + t + ' card')[1];
  return out; }
// Every G4 surface, each by its own anchor. Source-extracted only where rendering needs live DOM/edit state.
function g4Surfaces() {
  const S = {};
  S['P1 Edit Week Tax? tooltip (addEditEvent)'] = one(fnSrc('addEditEvent'), /class="ev-tax-wrap" title="([^"]*)"/g, 'P1')[1];
  const drw = fnSrc('renderEditDrawer');
  S['P2 Edit Week Tax? tooltip, inflow (renderEditDrawer)'] = one(drw, /\(ev\.t==='ob'\?'N\/A for outflows':'([^']*)'\)/g, 'P2')[1];
  S['P3 Edit Week section header'] = one(drw, /<div class="drawer-sect">([^<]*)<\/div>'\+\s*'<div class="comm-hint">/g, 'P3')[1];
  S['P4 Edit Week comm-hint'] = one(drw, /<div class="comm-hint">([\s\S]*?)<\/div>/g, 'P4')[1];
  renderAssumptions(); const A = __slot.innerHTML;
  const card = one(A, /<h3>Commission Tax Split<\/h3>([\s\S]*?)<\/div>/g, 'Commission Tax Split card')[1];
  const ps = [...card.matchAll(/<p>([\s\S]*?)<\/p>/g)].map(m => m[1]); assert(ps.length === 3, 'Commission Tax Split card must have exactly 3 paragraphs, has ' + ps.length);
  S['P5 Rules card p1'] = ps[0]; S['P6 Rules card p2'] = ps[1]; S['P7 Rules card p3'] = ps[2];
  const order = one(A, /<h3>Goal Funding Order \(Phase 4 Direct Waterfall\)<\/h3>([\s\S]*?)<\/div>/g, 'Goal Funding Order card')[1];
  S['P23 Goal Funding Order footnote'] = one(order, /<p style="font-size:12px;color:var\(--muted\)">([\s\S]*?)<\/p>/g, 'P23 footnote')[1];
  const cal = one(A, /<h3>Calendar Notes<\/h3>([\s\S]*?)<\/div>/g, 'Calendar Notes card')[1];
  S['P24 Calendar Notes model Wk 6 item'] = one(cal, /<li>(<strong>[^<]*\(model Wk 6\)<\/strong>[\s\S]*?)<\/li>/g, 'P24 model Wk 6 item')[1];
  const sweeps = one(A, /<h3>How Surplus Sweeps Work<\/h3>([\s\S]*?)<\/div>/g, 'How Surplus Sweeps Work card')[1];
  const lis = [...one(sweeps, /<ol[^>]*>([\s\S]*?)<\/ol>/g, 'sweep priority list')[1].matchAll(/<li>([\s\S]*?)<\/li>/g)].map(m => m[1]);
  assert(/^Base income tax reserve/.test(lis[0] || ''), 'sweep list anchor: item 1 must be the base tax reserve'); S['P8 sweep list item 2'] = lis[1];
  S['P9 Assumptions "Commission income:"'] = one(sweeps, /<p><strong>Commission income:<\/strong> ([\s\S]*?)<\/p>/g, 'P9')[1];
  S['P10 Assumptions "Adding extra income:"'] = one(sweeps, /<p><strong>Adding extra income:<\/strong> ([\s\S]*?)<\/p>/g, 'P10')[1];
  const ge = fnSrc('_renderGoalsEngine');
  S['P11 calculator Variable sublabel'] = one(ge, /💰 Variable Income<br><span[^>]*>([^<]*)<\/span>/g, 'P11')[1];
  S['P12 calculator Regular sublabel'] = one(ge, /📋 Regular Surplus<br><span[^>]*>([^<]*)<\/span>/g, 'P12')[1];
  const step = one(fnSrc('runEngine'), /steps\.push\(\{type:'tax',num:'→',label:'([^']*)',amt:taxAmt,note:'([^']*)'\}\)/g, 'P13 runEngine tax step');
  S['P13 runEngine tax-step note'] = step[2]; S._P13_LABEL = step[1];
  const cards = cardDescs(); for (const k of ['renderScenarios:commission', '_renderScenariosInline:commission']) S['P14 What-If card ' + k] = cards[k];
  S['P15 commission Taxable checkbox'] = one(formHtml('commission', { gross: '5000', taxable: false }), /<label for="sc-tax">([^<]*)<\/label>/g, 'P15')[1];
  S['P16 commission preview, Taxable OFF'] = previewRows(false).box; S['P16 commission preview, Taxable ON'] = previewRows(true).box;
  S['P17 commission summary, Taxable ON'] = summaryOf('commission', { gross: '5000', taxable: true });
  S['P17 commission summary, Taxable OFF'] = summaryOf('commission', { gross: '5000', taxable: false });
  S['P18 inflow Taxable checkbox'] = one(formHtml('inflow', { amount: '2500', label: 'x', taxable: false }), /<label for="sc-inf-tax">([^<]*)<\/label>/g, 'P18')[1];
  S['P19 inflow summary, Taxable ON'] = summaryOf('inflow', { amount: '2500', label: 'x', taxable: true });
  S['P19 inflow summary, Taxable OFF'] = summaryOf('inflow', { amount: '2500', label: 'x', taxable: false });
  S['P20 AI context tax line'] = one(_buildModelContext(), /^(Base tax reserve: .*)$/gm, 'P20')[1];
  const seed = WISHLIST_SEED.filter(x => x.title === 'Commission scenario'); assert(seed.length === 1, 'WISHLIST_SEED must hold exactly one "Commission scenario" (title unchanged)');
  S['P21 WISHLIST_SEED Commission scenario notes'] = seed[0].notes;
  S['P22 dead Roadmap Commission scenario notes'] = one(fnSrc('_DEAD_renderRoadmap_phase2'), /\{title:'Commission scenario',notes:'([^']*)'/g, 'P22')[1];
  return S;
}
test('[RB] TX-1′ every replaced P1–P24 OLD string and the obsolete frozen-B policy text are gone', () => {
  // Whole-file scope is safe ONLY for these literals: on R3 each occurs solely at its P-target (census in the RED-gate
  // evidence). P16's row is scoped to its label span (bare "60% → Alaska" also occurs in the AU-11 comment and R3 :7810).
  const OLD = ['title="Mark if commission or BK bonus inflow"', "'Mark if commission or BK bonus'", '>Commission / bonus split<',
    'Check <strong>Tax?</strong> on any inflow that is a <strong>Wendy or Adam commission</strong> or <strong>BK bonus</strong>. The model auto-routes <strong>40% → Vio Bank - Tax Reserve</strong> and <strong>60% → current savings goal</strong> on top of normal surplus logic.',
    'When Wendy or Adam has a commission or BK bonus inflow (taxable), the model routes: <strong>40% → Vio Bank - Tax Reserve</strong> and <strong>60% → current savings goal</strong>.',
    '(40% of commission gross)', 'are defined as constants. Week 6 commission is deferred because checking is below floor after obligations — both transfers pick up the following week.',
    'The 60% goal allocation is also deferred until the waterfall can safely fund it.', 'Commission 40% → Tax Reserve, 60% → Alaska — triggers on Wk 6 commission income',
    'When Adam or Wendy earns a commission or BK bonus, the model auto-routes 40% → Vio Bank Tax Reserve and 60% → the current open goal.',
    'Check "Tax?" for taxable income — the 40/60 split fires automatically and accelerates whichever goal is currently open.',
    'Commission, bonus — 40/60 split applies', '>Paycheck overage, extra cash<', 'Non-negotiable on all variable income. Always moves first before any other allocation.',
    'Add commission income with 40/60 tax/Alaska split', 'Taxable income (enables 40/60 split)', '<span class="sc-diff-lbl">60% → Alaska</span>',
    ') → Tax HYSA, 60% (', ') → Alaska.', 'Taxable (apply 40/60 commission split)', '(taxable — splits applied).',
    'Commission tax split: 40% ($707.18) to Vio, 60% ($1,060.76) to Alaska savings', '40/60 split preview',
    'Commission tax (40% → Vio / 60% → Alaska) fires on commission weeks.', // P23: the false sentence itself (once on R3, :7810)
    '— Commission week with heavy AMEX Gold; commission transfers defer one week.']; // P24: the false plural (once on R3, :7792)
  const found = OLD.filter(s => html.indexOf(s) >= 0);
  // Frozen-B policy text. The date is matched only as the frozen-B "policy (owner, 2026-09-19)" phrase: the bare
  // "(owner, 2026-09-19)" legitimately occurs in the G1 vocabulary comment (R3 :4613), which B must not touch.
  if (/no automatic 40% reserve/i.test(html)) found.push('no automatic 40% reserve');
  if (/Jabian[^<]{0,80}\$20,000/.test(html)) found.push('Jabian … $20,000');
  if (/policy \(owner, 2026-09-19\)/.test(html)) found.push('policy (owner, 2026-09-19)');
  assert(found.length === 0, 'replaced/obsolete wording remains: ' + JSON.stringify(found));
});
test('[RB] TX-3 no names, sources, thresholds, dates or false routing on any G4 surface (scanned per surface)', () => {
  const FORBID = /Wendy|Adam|B&K|B&amp;K|BK bonus|Deep South|Jabian|\$20,000|2026-09-19|Non-negotiable|→ Alaska|60% →/i;
  const S = g4Surfaces(); const bad = [];
  for (const [k, v] of Object.entries(S)) { if (k[0] === '_') continue; const m = String(v).match(FORBID); if (m) bad.push(k + ' ⟵ "' + m[0] + '"'); }
  // P24 surface only: no plural commission transfers (only the 40% moves; the 60% is not a transfer)
  const pl = String(S['P24 Calendar Notes model Wk 6 item']).match(/commission\s+(?:tax\s+)?transfers|transfers\s+defer/i); if (pl) bad.push('P24 Calendar Notes model Wk 6 item ⟵ "' + pl[0] + '" (plural commission transfers)');
  assert(bad.length === 0, bad.length + ' surface(s) carry forbidden wording: ' + JSON.stringify(bad));
});
test('[RB] TX-4 each FINAL P1–P24 string is exactly what its own surface carries', () => {
  const S = g4Surfaces(); const wn = 'Week ' + getCalWeek(WN) + ' (' + getWeekDate(WN) + ')';
  const want = {
    'P1 Edit Week Tax? tooltip (addEditEvent)': FINAL.P1, 'P2 Edit Week Tax? tooltip, inflow (renderEditDrawer)': FINAL.P1,
    'P3 Edit Week section header': FINAL.P3, 'P4 Edit Week comm-hint': FINAL.P4,
    'P5 Rules card p1': FINAL.P5, 'P6 Rules card p2': FINAL.P6, 'P7 Rules card p3': FINAL.P7, 'P8 sweep list item 2': FINAL.P8,
    'P9 Assumptions "Commission income:"': FINAL.P9, 'P10 Assumptions "Adding extra income:"': FINAL.P10,
    'P11 calculator Variable sublabel': FINAL.P11, 'P12 calculator Regular sublabel': FINAL.P12, 'P13 runEngine tax-step note': FINAL.P13, _P13_LABEL: FINAL.P13_LABEL,
    'P14 What-If card renderScenarios:commission': FINAL.P14, 'P14 What-If card _renderScenariosInline:commission': FINAL.P14,
    'P15 commission Taxable checkbox': FINAL.P15, 'P18 inflow Taxable checkbox': FINAL.P18,
    'P20 AI context tax line': FINAL.P20, 'P24 Calendar Notes model Wk 6 item': FINAL.P24,
    'P23 Goal Funding Order footnote': 'Not in waterfall: Taxable ETF ($4,999.79) — Stretch/Phase 5 only. No contributions until all T1-T10 goals are funded. ' + FINAL.P23 + ' All transfers respect the $6,500 hard floor.', 'P21 WISHLIST_SEED Commission scenario notes': FINAL.P21, 'P22 dead Roadmap Commission scenario notes': FINAL.P21,
  };
  // Summaries are compared as visible text (markup such as <strong> around the week is presentation, not contract).
  const wantText = {
    'P17 commission summary, Taxable ON': 'Add commission of ' + f(5000) + ' to ' + wn + ', taxable: 40% (' + f(2000) + ') reserved → Vio Bank - Tax Reserve; the remaining 60% (' + f(3000) + ') ' + APPROVED_60 + '.',
    'P17 commission summary, Taxable OFF': 'Add commission of ' + f(5000) + ' to ' + wn + ' (not taxable — no tax reserve).',
    'P19 inflow summary, Taxable ON': 'Add inflow "x" of ' + f(2500) + ' to ' + wn + ' (taxable — 40% tax reserve applied).',
    'P19 inflow summary, Taxable OFF': 'Add inflow "x" of ' + f(2500) + ' to ' + wn + '.',
  };
  const bad = [];
  for (const [k, v] of Object.entries(want)) if (S[k] !== v) bad.push(k);
  for (const [k, v] of Object.entries(wantText)) if (strip(S[k]) !== v) bad.push(k);
  assert(bad.length === 0, bad.length + ' surface(s) differ from the approved FINAL text: ' + JSON.stringify(bad));
  // P2: the outflow branch of the same tooltip is unchanged.
  assert(/\(ev\.t==='ob'\?'N\/A for outflows':/.test(fnSrc('renderEditDrawer')), 'P2 outflow tooltip "N/A for outflows" must be unchanged');
});
test('[RB] TX-5 rendered commission What-If preview: no 60% row; the 40% reserve row only when Taxable', () => {
  const off = previewRows(false), on = previewRows(true);
  assert(!/60%/.test(off.box) && !/60%/.test(on.box), 'the preview must not show any 60% row (P16)');
  assert(JSON.stringify(off.labels) === JSON.stringify(['Income to Checking']), 'Taxable OFF rows must be [Income to Checking], got ' + JSON.stringify(off.labels));
  assert(JSON.stringify(on.labels) === JSON.stringify(['Income to Checking', '40% → Vio Bank - Tax Reserve']), 'Taxable ON rows must be [Income to Checking, 40% → Vio Bank - Tax Reserve], got ' + JSON.stringify(on.labels));
  assert(on.box.indexOf(f(2000)) >= 0, 'Taxable ON 40% row must show ' + f(2000));
});
test('[RB] TX-6 live What-If text never claims a separate 60% movement (What-If only; Goals calculator excluded)', () => {
  const T = {}; const c = cardDescs(); for (const k in c) T['card ' + k] = c[k];
  T['commission checkbox'] = one(formHtml('commission', { gross: '5000', taxable: false }), /<label for="sc-tax">([^<]*)<\/label>/g, 'commission checkbox')[1];
  T['inflow checkbox'] = one(formHtml('inflow', { amount: '2500', label: 'x', taxable: false }), /<label for="sc-inf-tax">([^<]*)<\/label>/g, 'inflow checkbox')[1];
  T['preview OFF'] = previewRows(false).box; T['preview ON'] = previewRows(true).box;
  for (const tx of [true, false]) { T['commission summary ' + (tx ? 'ON' : 'OFF')] = summaryOf('commission', { gross: '5000', taxable: tx });
    T['inflow summary ' + (tx ? 'ON' : 'OFF')] = summaryOf('inflow', { amount: '2500', label: 'x', taxable: tx }); }
  // Contract regex verbatim. Dollar amounts are normalised to "$X" first: its [^<.;] class otherwise stops at the
  // decimal point of a rendered amount, so "60% ($3,000.00) → Alaska" would escape it.
  const RE = /60%[^<.;]{0,60}(→|transferred to|routed|allocat|Alaska|goal|savings)/i; const bad = [];
  for (const [k, v] of Object.entries(T)) { const t = String(v).split(APPROVED_60).join('').replace(/\$[0-9][0-9,]*(\.[0-9]+)?/g, '$X'); const m = t.match(RE); if (m) bad.push(k + ' ⟵ "' + m[0] + '"');
    if (/40\/60/.test(t)) bad.push(k + ' ⟵ "40/60" (supplementary: a 40/60 split claim)'); }
  assert(bad.length === 0, bad.length + ' What-If text(s) claim a separate 60% movement: ' + JSON.stringify(bad));
});
test('[RB] TX-2 the Tax? mechanism itself is kept (checkbox rendered; ticked inflow still reserves 40%)', () => {
  assert((html.match(/<span class="ev-tax-lbl">Tax\?<\/span>/g) || []).length >= 2, 'Tax? checkbox must still render in Edit Week');
  const src = fnSrc('saveWeekEdits'); assert(/taxableGross\*0\.40/.test(src), 'ticked inflows must still reserve 40%');
});

(async () => {
  for (const t of tests) { try { await t.fn(); pass++; console.log('  ✓ ' + t.name); } catch (e) { fail++; console.log('  ✗ ' + t.name + '\n      ' + e.message); } }
  const tag = p => tests.filter(t => t.name.startsWith(p)).length;
  console.log('\nRESULTS  total ' + tests.length + ' · passed ' + pass + ' · failed ' + fail + '   ([RB-PIN] ' + tag('[RB-PIN]') + ', [RB] ' + tag('[RB] ') + ')');
  process.exit(0);
})();
