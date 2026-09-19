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
const stub = `
var __slot={innerHTML:'',addEventListener:function(){},value:'',textContent:'',style:{},classList:{remove:function(){},add:function(){}},scrollIntoView:function(){}};
var window={fetch:function(){return Promise.resolve({ok:true,json:function(){return Promise.resolve([])}});}};
var document={getElementById:function(){return __slot;},querySelector:function(){return null},querySelectorAll:function(){return[]},addEventListener:function(){},createElement:function(){return{style:{},appendChild:function(){},setAttribute:function(){}}},body:{appendChild:function(){}}};
var localStorage={getItem:function(){return null;},setItem:function(){},removeItem:function(){}};
var requestAnimationFrame=function(){};var fetch=window.fetch;
var supabase={createClient:function(){return{auth:{getSession:function(){return Promise.resolve({data:{session:null},error:null});},signInWithPassword:function(){return Promise.resolve({data:null,error:{message:'mock'}});},signOut:function(){return Promise.resolve({error:null});},onAuthStateChange:function(){}}};}};
`;
try { eval(stub + sc); } catch (e) { console.error('FATAL eval:', e.message); process.exit(1); }
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

// ═══ [RB] G4 ═════════════════════════════════════════════════════════════════════════════════
test('[RB] TX-1 no remaining instruction to route 40% of Wendy B&K / Deep South / every commission to Vio', () => {
  const stale = ['Mark if commission or BK bonus', 'Non-negotiable on all variable income', 'Commission, bonus — 40/60 split applies',
    'Check "Tax?" for taxable income — the 40/60 split fires automatically', 'on any inflow that is a <strong>Wendy or Adam commission</strong>',
    'When Wendy or Adam has a commission or BK bonus inflow (taxable), the model routes', 'the model auto-routes 40% → Vio Bank Tax Reserve and 60%',
    'Add commission income with 40/60 tax/Alaska split'];
  const found = stale.filter(s => html.indexOf(s) >= 0); assert(found.length === 0, 'stale guidance remains: ' + JSON.stringify(found));
  // The current policy must be stated where the owner decides (Edit Week hint + Rules page).
  const pol = (html.match(/no automatic 40% reserve/gi) || []).length; assert(pol >= 2, 'current policy statement missing (found ' + pol + ')');
  assert(/Jabian[^<]{0,80}\$20,000/.test(html), 'Jabian hold-below-$20,000 policy must be stated');
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
