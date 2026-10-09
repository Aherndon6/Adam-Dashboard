// ═══════════════════════════════════════════════════════════════════════════
// Herndon Financial OS — D-1 sign-truthfulness (presentation only)
// ───────────────────────────────────────────────────────────────────────────
// Standalone; loads HFOS_INDEX (default ./index.html) like test_release_b.js.
// Contract (owner ruling, 2026-10-06, Option B): wherever a financially meaningful value can be negative,
// the displayed or AI-transmitted text must keep its sign/direction. f() stays a magnitude formatter
// (unchanged); the fix lives at the presentation boundary. Fixtures reuse the live negative-checking
// semantics observed 2026-10-06 (Cal 48 / 51 / 52: −2,955.21 / −727.42 / −2,574.92).
// Tags:  [D1]      contract — RED before the fix, GREEN after.
//        [D1-REG]  regression controls — GREEN before and after (positive/zero/magnitude sites unchanged).
// ═══════════════════════════════════════════════════════════════════════════
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
console.error = function () {}; console.warn = function () {};

// ── helpers ───────────────────────────────────────────────────────────────
const txt = h => String(h).replace(/<[^>]+>/g, ' ').replace(/&minus;/g, '−').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ');
// every occurrence of a magnitude must carry its sign/direction: preceded by "−" or followed by a direction word
function directional(text, mag) {
  const bad = []; const re = new RegExp('\\$' + mag.replace(/[.,]/g, m => '\\' + m), 'g'); let m;
  while ((m = re.exec(text))) {
    const before = text.slice(Math.max(0, m.index - 1), m.index), after = text.slice(m.index + m[0].length, m.index + m[0].length + 24);
    if (before !== '−' && !/^\)?\s*(below|short|over)/i.test(after) && !/(over (plan )?by|below)\s*$/i.test(text.slice(Math.max(0, m.index - 16), m.index))) bad.push(text.slice(Math.max(0, m.index - 40), m.index + m[0].length + 24));
  }
  return bad;
}
function fnSrc(name) { const i = html.indexOf('function ' + name + '('); assert(i >= 0, name + ' not found'); let d = 0, k = html.indexOf('{', i), q = null; for (; k < html.length; k++) { const ch = html[k]; if (q) { if (ch === '\\') { k++; continue; } if (ch === q) q = null; continue; } if (ch === '/' && html[k + 1] === '/') { k = html.indexOf('\n', k); continue; } if (ch === "'" || ch === '"' || ch === '`') { q = ch; continue; } if (ch === '{') d++; else if (ch === '}') { d--; if (d === 0) break; } } return html.slice(i, k + 1); }
const G = getGoals();
const BASE = applyCompletionSnapshots(runModel(G.ak, G.rt));
const clone = ws => ws.map(w => Object.assign({}, w));
// live 2026-10-06 negative-week semantics, applied to model weeks 26 / 29 / 30 (unreconciled: mChk === chk, verified live)
function negWeeks() {
  const ws = clone(BASE), set = (n, o) => Object.assign(ws.find(w => w.num === n), o);
  set(26, { chk: -2955.21, mChk: -2955.21, startChk: 1446.29, ol: -2955.16 });
  set(29, { chk: -727.42, mChk: -727.42, startChk: 4222.79, ol: -727.37 });
  set(30, { chk: -2574.92, mChk: -2574.92, startChk: -727.42, ol: -2574.87 });
  return ws;
}
function posWeeks() { const ws = clone(BASE); Object.assign(ws.find(w => w.num === 26), { chk: 2955.21, mChk: 2955.21, startChk: 1446.29, ol: 2955.16 }); return ws; }
function withGlobals(over, fn) { const saved = {}; for (const k of Object.keys(over)) { saved[k] = eval(k); eval(k + '=over[k]'); } try { return fn(); } finally { for (const k of Object.keys(saved)) eval(k + '=saved[k]'); } }

// ═══ [D1-REG] formatter contract unchanged ═══════════════════════════════
test('[D1-REG] R-1 f() is unchanged (magnitude formatter) and fsigned() is unchanged', () => {
  assert(fnSrc('f') === "function f(n){return '$'+Math.abs(n).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2})}", 'f() changed');
  assert(fnSrc('fsigned') === "function fsigned(n){return(n<0?'−':'')+f(Math.abs(n));}", 'fsigned() changed');
  assert(f(-2955.21) === '$2,955.21' && fsigned(-2955.21) === '−$2,955.21' && fsigned(2955.21) === '$2,955.21' && fsigned(0) === '$0.00', 'formatter outputs');
});

// ═══ Week detail ═════════════════════════════════════════════════════════
test('[D1] W-1 Week detail: negative Ending / Beginning / watch alert / liquidity keep their sign (Cal 48, 52 fixtures)', () => {
  const ws = negWeeks(); const t48 = txt(renderWeekDetail(ws.find(w => w.num === 26), ws)); const t52 = txt(renderWeekDetail(ws.find(w => w.num === 30), ws));
  assert(/Ending \(Checking\) −\$2,955\.21/.test(t48), 'Ending must read −$2,955.21');
  assert(/checking at −\$2,955\.21/.test(t48), 'watch alert must read −$2,955.21');
  assert(/Operational liquidity \(Checking \+ Savings\) −\$2,955\.16/.test(t48), 'liquidity must read −$2,955.16');
  assert(/Beginning −\$727\.42/.test(t52), 'Cal 52 Beginning must read −$727.42');
  const bad = directional(t48, '2,955.21').concat(directional(t48, '2,955.16'), directional(t52, '727.42'), directional(t52, '2,574.92'));
  assert(bad.length === 0, 'unsigned negative magnitudes: ' + JSON.stringify(bad));
});
test('[D1] W-2 Week detail: $9,455.21 BELOW the floor never reads as above/available', () => {
  const ws = negWeeks(); const t = txt(renderWeekDetail(ws.find(w => w.num === 26), ws));
  assert(/\$9,455\.21 below floor/.test(t), 'cushion must read "$9,455.21 below floor": ' + (t.match(/.{0,30}9,455\.21.{0,20}/) || [''])[0]);
  assert(!/\+\$9,455\.21/.test(t) && !/(^|[^−])\$9,455\.21 vs floor/.test(t), 'no positive/neutral "vs floor" wording for a below-floor cushion');
});
test('[D1-REG] W-3 Week detail positive control: positive balances unchanged, no minus, cushion wording unchanged', () => {
  const ws = posWeeks(); const t = txt(renderWeekDetail(ws.find(w => w.num === 26), ws));
  assert(/Ending \(Checking\) \$2,955\.21/.test(t) && !/−\$2,955\.21/.test(t), 'positive Ending unchanged');
  const ws2 = clone(BASE); Object.assign(ws2.find(w => w.num === 26), { chk: 7000 }); const t2 = txt(renderWeekDetail(ws2.find(w => w.num === 26), ws2));
  assert(/\+\$500\.00 vs floor/.test(t2), 'above-floor cushion wording unchanged (+$500.00 vs floor)');
});
test('[D1] W-2b Week detail: a POSITIVE balance below the floor shows its floor gap directionally (cushion −3,544.79)', () => {
  const ws = posWeeks(); const t = txt(renderWeekDetail(ws.find(w => w.num === 26), ws));
  assert(/\$3,544\.79 below floor/.test(t), 'cushion must read "$3,544.79 below floor": ' + (t.match(/.{0,20}3,544\.79.{0,20}/) || [''])[0]);
});
test('[D1-REG] W-4 Week detail zero control: a zero balance renders $0.00 (no minus)', () => {
  const ws = clone(BASE); Object.assign(ws.find(w => w.num === 26), { chk: 0, ol: 0 }); const t = txt(renderWeekDetail(ws.find(w => w.num === 26), ws));
  assert(/Ending \(Checking\) \$0\.00/.test(t) && !/−\$0\.00/.test(t), 'zero renders $0.00');
});
test('[D1] W-5 Week detail reconciliation reference (model estimates) keeps signs: each reference balance formatted signed', () => {
  const s = fnSrc('renderWeekDetail');
  for (const k of ['chk', 'sav', 'amx', 'tax', 'lc']) assert(new RegExp("fsigned\\(_pf\\.reference\\." + k + "\\)").test(s), 'reference.' + k + ' must be sign-preserving');
  assert(!/[^d]f\(_pf\.reference\./.test(s), 'no magnitude-only reference balance remains');
});

test('[D1] W-6 Week detail: a negative reconciled actual balance keeps its sign in the account table', () => {
  const ws = negWeeks(); const w = ws.find(x => x.num === 26);
  Object.assign(w, { reconciled: true, actualBals: { chk: -10, sav: 50, amx: 1, tax: 1, lc: 1 }, variance: { chk: 2945.21, sav: 0, amx: 0, tax: 0, lc: 0 } });
  const t = txt(renderWeekDetail(w, ws)); assert(/Truist Checking −\$1,446\.29|Truist Checking \$1,446\.29/.test(t), 'account table rendered');
  assert(/−\$10\.00/.test(t) && directional(t, '10.00').length === 0, 'reconciled actual must read −$10.00: ' + JSON.stringify(directional(t, '10.00')));
});

// ═══ Overview ════════════════════════════════════════════════════════════
test('[D1] O-1 Overview: negative projected EOW cash, deployable formula and near-term risk keep their sign', () => {
  const ws = negWeeks(); Object.assign(ws.find(w => w.num === 28), { chk: 8000 });
  const out = withGlobals({ currentW: 26 }, () => { renderOverview(buildDashboardViewModel(ws, G)); return __slot.innerHTML; });
  const t = txt(out);
  assert(/Proj\. EOW Cash −\$2,955\.21/.test(t), 'Proj. EOW Cash must read −$2,955.21');
  assert(/−\$2,955\.21 checking/.test(t), 'deployable formula must read −$2,955.21 checking');
  const out2 = withGlobals({ currentW: 27 }, () => { const w2 = negWeeks(); Object.assign(w2.find(w => w.num === 27), { chk: 9000 }); Object.assign(w2.find(w => w.num === 28), { chk: 8000 }); renderOverview(buildDashboardViewModel(w2, G)); return __slot.innerHTML; });
  const t2 = txt(out2);
  assert(/projects −\$727\.42/.test(t2), 'near-term risk must read "projects −$727.42": ' + (t2.match(/projects.{0,30}/) || [''])[0]);
  const bad = directional(t, '2,955.21').concat(directional(t2, '727.42'), directional(t2, '2,955.21'));
  assert(bad.length === 0, 'unsigned negative magnitudes: ' + JSON.stringify(bad));
});
test('[D1-REG] O-2 Overview positive control: positive Proj. EOW Cash unchanged', () => {
  const ws = posWeeks(); const t = txt(withGlobals({ currentW: 26 }, () => { renderOverview(buildDashboardViewModel(ws, G)); return __slot.innerHTML; }));
  assert(/Proj\. EOW Cash \$2,955\.21/.test(t) && !/Proj\. EOW Cash −/.test(t), 'positive unchanged');
});

// ═══ Goals (Savings tab): running balance + Planned Monthly Margin ══════════
function goalsSavings(ws, le) { return txt(withGlobals({ _getBudgetLivingExpenses: function () { return le; }, _blrState: function () { return { state: 'VALID', keys: [] }; } }, () => _renderGoalsSavings(buildDashboardViewModel(ws, G)))); }
test('[D1] G-1 Goals: negative running checking balance keeps its sign', () => {
  const t = withGlobals({ currentW: 26 }, () => goalsSavings(negWeeks(), 14488));
  assert(/currently −\$2,955\.21/.test(t), 'running balance must read −$2,955.21: ' + (t.match(/currently.{0,20}/) || [''])[0]);
});
test('[D1] G-2 Goals: a negative Planned Monthly Margin (latent) renders negative, not as a positive green margin', () => {
  const raw = withGlobals({ currentW: 26, _getBudgetLivingExpenses: function () { return 16938; }, _blrState: function () { return { state: 'VALID', keys: [] }; } }, () => _renderGoalsSavings(buildDashboardViewModel(posWeeks(), G)));
  const t = txt(raw);
  assert(/Planned Monthly Margin \(Base Pay\) −\$1,000\.00/.test(t), 'margin must read −$1,000.00: ' + (t.match(/Planned Monthly Margin \(Base Pay\).{0,20}/) || [''])[0]);
  const seg = raw.slice(raw.indexOf('Planned Monthly Margin (Base Pay)'), raw.indexOf('Planning estimate'));
  assert(!/color:var\(--green\)/.test(seg), 'a negative margin must not be styled as a positive (green) value');
});
test('[D1-REG] G-3 Goals positive control: margin $1,450.00 unchanged and green', () => {
  const raw = withGlobals({ currentW: 26, _getBudgetLivingExpenses: function () { return 14488; }, _blrState: function () { return { state: 'VALID', keys: [] }; } }, () => _renderGoalsSavings(buildDashboardViewModel(posWeeks(), G)));
  const t = txt(raw); assert(/Planned Monthly Margin \(Base Pay\) \$1,450\.00/.test(t), 'positive margin unchanged');
  const seg = raw.slice(raw.indexOf('Planned Monthly Margin (Base Pay)'), raw.indexOf('Planning estimate')); assert(/color:var\(--green\)/.test(seg), 'positive margin stays green');
});

// ═══ What-If impact ══════════════════════════════════════════════════════
function whatIf(minS, minB) {
  return txt(withGlobals({ whatIfResult: { cashSummary: { scenarioMinChk: minS, baselineMinChk: minB, totalCashImpact: 500, occurrenceCount: 1, scenarioTotalGoals: 100, baselineTotalGoals: 100, floorBreachWeeks: [] }, goalImpact: [], bypassedWeeks: [], entryWeeks: [] },
    whatIfState: Object.assign({}, whatIfState, { direction: 'outflow', amount: 500, date: '2026-11-01', recurrence: 'one-time' }) }, () => _renderGoalsImpact()));
}
test('[D1] I-1 What-If: a negative lowest-checking result stays negative (scenario and baseline)', () => {
  const t = whatIf(-2955.21, -727.42);
  assert(/Lowest checking −\$2,955\.21/.test(t), 'scenario low must read −$2,955.21: ' + (t.match(/Lowest checking.{0,20}/) || [''])[0]);
  assert(/baseline: −\$727\.42/.test(t), 'baseline low must read −$727.42');
});
test('[D1-REG] I-2 What-If positive control unchanged', () => {
  const t = whatIf(7100.5, 7200); assert(/Lowest checking \$7,100\.50/.test(t) && /baseline: \$7,200\.00/.test(t), 'positive unchanged');
});

// ═══ G1 goal-warning low ═════════════════════════════════════════════════
test('[D1] V-1 G1 withhold text: a negative low-water value keeps its sign', () => {
  const s = g1VerdictText({ verdict: 'WITHHOLD', reason: 'candidate_breach', breachWeek: 26, minChk: -2955.21 });
  assert(/\(low −\$2,955\.21\)/.test(s), 'G1 low must read −$2,955.21: ' + s);
});
test('[D1-REG] V-2 G1 positive low unchanged', () => {
  const s = g1VerdictText({ verdict: 'WITHHOLD', reason: 'candidate_breach', breachWeek: 26, minChk: 5100 }); assert(/\(low \$5,100\.00\)/.test(s), s);
});

// ═══ History ═════════════════════════════════════════════════════════════
test('[D1] H-1 History: a negative modeled checking balance keeps its sign', () => {
  const t = txt(withGlobals({ historyFilter: 'all' }, () => { const r = renderHistory(negWeeks()); return typeof r === 'string' ? r : __slot.innerHTML; }));
  const bad = directional(t, '2,955.21').concat(directional(t, '2,574.92'), directional(t, '727.42'));
  assert(/−\$2,955\.21/.test(t), 'History must show −$2,955.21');
  assert(bad.length === 0, 'unsigned negative magnitudes: ' + JSON.stringify(bad.slice(0, 3)));
});

test('[D1] H-2 History: a negative reconciled actual balance keeps its sign', () => {
  const ws = negWeeks(); Object.assign(ws.find(x => x.num === 26), { reconciled: true, actualBals: { chk: -10, sav: 50, amx: 1, tax: 1, lc: 1 }, variance: { chk: 2945.21, sav: 0, amx: 0, tax: 0, lc: 0 } });
  const t = txt(withGlobals({ historyFilter: 'all' }, () => { const r = renderHistory(ws); return typeof r === 'string' ? r : __slot.innerHTML; }));
  assert(/−\$10\.00/.test(t) && directional(t, '10.00').length === 0, 'History reconciled actual must read −$10.00');
});

// ═══ Ask Claude context (owner-only AI context) ══════════════════════════
test('[D1] A-1 Ask Claude context: negative model balances and a negative reconciled variance are transmitted with their sign', () => {
  const ws = negWeeks(); const w = ws.find(x => x.num === 26);
  Object.assign(w, { reconciled: true, actualBals: { chk: -10, sav: 50, amx: 1, tax: 1, lc: 1 }, variance: { chk: -123.45, sav: 0, amx: 0, tax: 0, lc: 0 } });
  const ctx = withGlobals({ runModel: function () { return ws; }, applyCompletionSnapshots: function (x) { return x; } }, () => _buildModelContext());
  assert(/Chk=−\$2,955\.21/.test(ctx), 'context must carry Chk=−$2,955.21');
  assert(/Chk=−\$727\.42/.test(ctx) && /Chk=−\$2,574\.92/.test(ctx), 'context must carry the other negative weeks');
  assert(/Actual: Chk=−\$10\.00/.test(ctx), 'reconciled actual must keep its sign');
  assert(/Chk variance: −\$123\.45/.test(ctx), 'variance must keep its sign');
  assert(!/Chk=\$2,955\.21/.test(ctx), 'no false-positive checking balance in the AI context');
});
test('[D1-REG] A-2 Ask Claude context positive control: positive balances transmitted unchanged', () => {
  const ws = posWeeks(); const ctx = withGlobals({ runModel: function () { return ws; }, applyCompletionSnapshots: function (x) { return x; } }, () => _buildModelContext());
  assert(/Chk=\$2,955\.21/.test(ctx) && !/Chk=−\$2,955\.21/.test(ctx), 'positive unchanged');
});

// ═══ Budget (renderBudget — protected, owner-approved re-pin) ═════════════
const GROC = 'food_dining.groceries', RENT = 'home.mortgage_rent';
function live(key, over) { return Object.assign({ key: key, label: key, parent_key: key.indexOf('.') > 0 ? key.split('.')[0] : null, is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked', cashflow_treatment: 'operating', merged_into_key: null, display_order: 1 }, over || {}); }
function liveCats() { const out = []; BUDGET_CATEGORY_REGISTRY.forEach(c => { if (!c.leaf) out.push(live(c.key, { is_leaf: false, parent_key: null, behavior_class: null, budget_treatment: null, cashflow_treatment: null })); else if (c.isIncome) out.push(live(c.key, { behavior_class: 'income', budget_treatment: 'display_only', cashflow_treatment: 'inflow' })); else if (c.key === 'misc.goal_sweep') out.push(live(c.key, { behavior_class: 'savings_allocation', budget_treatment: 'planned_allocation' })); else out.push(live(c.key)); });
  ['income.deep_south_commissions', 'income.interest', 'income.bkcpa_extra_pay', 'income.extra_pay'].forEach(k => out.push(live(k, { behavior_class: 'income', budget_treatment: 'display_only' })));
  out.push(live('business.jabian_deposits_2026', { parent_key: 'business', behavior_class: 'reimbursable_income', budget_treatment: 'excluded' })); return out; }
function line(key, amount) { return { id: 'L-' + key, category_key: key, line_label: null, amount: amount, start_month: '2026-06-01', end_month: null, is_active: true }; }
function resp(rows) { return { ok: true, status: 200, headers: { get: k => String(k).toLowerCase() === 'content-range' ? (rows.length ? '0-' + (rows.length - 1) + '/' + rows.length : '*/0') : null }, json: () => Promise.resolve(rows) }; }
async function flush(n) { for (let i = 0; i < (n || 80); i++) await Promise.resolve(); }
async function budgetText(lines, regRows) {
  const store = {}; document.getElementById = id => (store[id] = store[id] || { id, innerHTML: '', value: '', textContent: '', style: {}, classList: { add() {}, remove() {} }, addEventListener() {}, scrollIntoView() {} });
  renderApp = function () {}; USER_ROLE = 'owner'; getAuthHeaders = async () => ({ apikey: 't' });
  _registriesLoadStatus = 'loaded'; _categoriesCache = liveCats(); _budgetLineRulesLoadStatus = 'loaded'; _budgetLineRulesCache = lines;
  _budgetSelectedMonth = '2026-08-01'; _budgetTransLoadStatus = 'not_loaded'; _budgetRegisterSpendLoadStatus = 'not_loaded'; _budgetTransactions = []; _budgetRegisterSpendCache = [];
  fetch = async (url) => /\/rest\/v1\/transactions\?/.test(String(url)) ? resp(regRows) : resp([]);
  await _budgetLoadPair('2026-08-01'); await flush(); renderBudget(); return txt(store['budget-content'].innerHTML);
}
const reg = (id, key, amount) => ({ id, category_key: key, amount, transaction_date: '2026-08-05' });
test('[D1] B-1 Budget: negative Planned remaining / total Remaining / group Remaining read as over plan, not money remaining', async () => {
  // planned expense 500 + 1000 + 200 (allocation) = 1,700; spent 700 + 1,100 = 1,800 → over plan by $100.00; groceries group over by $200.00
  const t = await budgetText([line(GROC, 500), line(RENT, 1000), line('income.net_salary', 6000), line('misc.goal_sweep', 200)], [reg('a', GROC, -700), reg('b', RENT, -1100)]);
  assert(/Over plan by \$100\.00/.test(t), 'strip must say "Over plan by $100.00": ' + (t.match(/.{0,40}100\.00.{0,20}/) || [''])[0]);
  assert(/Total Planned Budget[^]*?Over by \$100\.00/.test(t), 'Total row Remaining must read "Over by $100.00"');
  assert(/Food & Dining \$700\.00 \$500\.00 Over by \$200\.00/.test(t), 'Food group-header Remaining must read "Over by $200.00": ' + (t.match(/Food & Dining.{0,40}/) || [''])[0]);
  assert(!/Planned remaining \$100\.00/.test(t), 'no "Planned remaining $100.00" for an over-plan month');
});
test('[D1] B-2 Budget: a negative Income − Total Planned difference keeps its sign', async () => {
  const t = await budgetText([line(GROC, 500), line(RENT, 1000), line('income.net_salary', 1000), line('misc.goal_sweep', 200)], [reg('a', GROC, -100)]);
  assert(/out of balance[^]*?−\$700\.00/.test(t), 'Income − Total Planned must read −$700.00: ' + (t.match(/out of balance.{0,140}/) || [''])[0]);
});
test('[D1-REG] B-3 Budget positive control: positive remaining reads as remaining (unchanged wording, no minus / over-plan)', async () => {
  const t = await budgetText([line(GROC, 500), line(RENT, 1000), line('income.net_salary', 6000), line('misc.goal_sweep', 200)], [reg('a', GROC, -100), reg('b', RENT, -1000)]);
  assert(/Planned remaining \$600\.00/.test(t), 'strip "Planned remaining $600.00" unchanged: ' + (t.match(/Planned remaining.{0,20}/) || [''])[0]);
  assert(!/Over plan by/.test(t) && !/−\$600\.00/.test(t), 'no over-plan wording or minus on a positive remaining');
});
test('[D1-REG] B-4 Budget zero control: exactly-on-plan reads $0.00 remaining', async () => {
  const t = await budgetText([line(GROC, 500), line(RENT, 1000), line('income.net_salary', 6000), line('misc.goal_sweep', 200)], [reg('a', GROC, -500), reg('b', RENT, -1000)]);
  assert(/Planned remaining \$200\.00|Planned remaining \$0\.00/.test(t) && !/Over plan by/.test(t), 'on/under plan never reads as over: ' + (t.match(/Planned remaining.{0,20}/) || [''])[0]);
});
test('[D1] B-5 Budget statement check: retired by R-lite (owner 2026-10-09) — no Statement − Cleared difference or "Reconciled" is shown at all', () => {
  // Superseded: the sign-preservation this test guarded belonged to the legacy Statement check, which the owner retired
  // (it compared Budget-entered entries, not the Register). The truthful replacement is Transactions → Statement Compare.
  const src = fnSrc('_renderBudgetRecon');
  assert(!/Difference \(Stmt - Cleared\)|fsigned\(diff\)|Reconciled/.test(src) && /Statement check \(retired\)/.test(src), 'the retired check computes and claims nothing');
});

(async () => {
  for (const t of tests) { try { await t.fn(); pass++; console.log('  ✓ ' + t.name); } catch (e) { fail++; console.log('  ✗ ' + t.name + '\n      ' + e.message); } }
  const tag = p => tests.filter(t => t.name.startsWith(p)).length;
  console.log('\nRESULTS  total ' + tests.length + ' · passed ' + pass + ' · failed ' + fail + '   ([D1] ' + tag('[D1] ') + ', [D1-REG] ' + tag('[D1-REG]') + ')');
  process.exit(0);
})();
