'use strict';
// ════════════════════════════════════════════════════════════════════════════
// Rollover test kit (2027 rollover Package A). TEST AND EVIDENCE INFRASTRUCTURE ONLY.
// Governing spec: docs/rollover-2027-spec.md (frozen v2.1). This file changes no product
// behavior; it loads index.html into isolated contexts for tests.
//
// Provides:
//   clockStubSource(dateStr)     source text that pins Date inside an eval'd product scope
//   resolveTestDate(envValue)    parse HFOS_TEST_DATE (default LEGACY_DEFAULT_TEST_DATE)
//   loadApp(opts)                fresh node:vm context per call (no cross-test leakage)
//   frozen2026Rows(ctx)          WD_2026_FROZEN if the product defines it, else WD (pre-rollover)
//   compositionFor(Y, src)       plan-Y schedule composition, truncated at Y's final week
//   synthPlanBlock(Y, opts)      synthetic (non-household) schedule rows for plan Y
//   cal                          independent period oracle for spec §3 (test-side only)
//   deepEq, withFrozen2026, goldenDerive
// ════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const REPO = path.resolve(__dirname, '..');

// The legacy suites ran against the real clock until Package A. This is the date the
// suites were last run green on the real clock (Package A authorization day); pinning it
// keeps today's results identical while removing machine-date dependence.
const LEGACY_DEFAULT_TEST_DATE = '2026-10-07';

function resolveTestDate(envValue) {
  const v = (envValue === undefined || envValue === null || envValue === '') ? LEGACY_DEFAULT_TEST_DATE : String(envValue);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new Error('HFOS_TEST_DATE must be YYYY-MM-DD, got ' + v);
  const [y, m, d] = v.split('-').map(Number);
  const probe = new Date(y, m - 1, d, 12, 0, 0, 0);
  if (probe.getFullYear() !== y || probe.getMonth() !== m - 1 || probe.getDate() !== d) throw new Error('invalid calendar date ' + v);
  return v;
}

// Source text that, when evaluated BEFORE the product script in the same scope, makes
// `new Date()`, `Date()` and `Date.now()` return local noon on dateStr. Explicit-argument
// constructions (new Date(2026,5,7), new Date(iso)) are untouched. Local noon is stable in
// every timezone for week arithmetic. The pinned constructor shares Date.prototype, so
// `x instanceof Date` keeps working.
function clockStubSource(dateStr) {
  const v = resolveTestDate(dateStr);
  const [y, m, d] = v.split('-').map(Number);
  return `
var __HFOS_RealDate = globalThis.Date;
var __HFOS_PIN = new __HFOS_RealDate(${y}, ${m - 1}, ${d}, 12, 0, 0, 0).getTime();
var Date = (function(RD, PIN){
  function PinnedDate(){
    if (!(this instanceof PinnedDate)) return new RD(PIN).toString();
    if (arguments.length === 0) return new RD(PIN);
    return new (Function.prototype.bind.apply(RD, [null].concat(Array.prototype.slice.call(arguments))))();
  }
  PinnedDate.prototype = RD.prototype;
  PinnedDate.now = function(){ return PIN; };
  PinnedDate.UTC = RD.UTC; PinnedDate.parse = RD.parse;
  PinnedDate.__hfosPinned = '${v}';
  return PinnedDate;
})(__HFOS_RealDate, __HFOS_PIN);
`;
}

// Same product-script preparation as test_regression.js (const→var so tests may rebind
// globals; drop the startup try-block and loadAll()).
function productScript(indexPath) {
  const html = fs.readFileSync(indexPath, 'utf8');
  const m = html.match(/<script>([\s\S]*?)<\/script>/);
  if (!m) throw new Error('No <script> block found in ' + indexPath);
  let sc = m[1];
  sc = sc.replace(/\bconst\b/g, 'var');
  sc = sc.replace(/^try\s*\{[\s\S]*?\}\s*catch[\s\S]*?\}/m, '');
  sc = sc.replace(/^loadAll\(\);/m, '');
  return { html, sc };
}

const DOM_STUB = `
var window={fetch:function(){return Promise.resolve({ok:true,json:function(){return Promise.resolve([])}});}};
var document={getElementById:function(){return{innerHTML:'',addEventListener:function(){},value:'',textContent:'',style:{},classList:{remove:function(){},add:function(){}},scrollIntoView:function(){}};},querySelectorAll:function(){return[];},querySelector:function(){return null;},addEventListener:function(){},body:{style:{},classList:{add:function(){},remove:function(){}}},createElement:function(){return{style:{},setAttribute:function(){},appendChild:function(){},classList:{add:function(){},remove:function(){}}};}};
var localStorage={getItem:function(){return null;},setItem:function(){},removeItem:function(){}};
var sessionStorage={getItem:function(){return null;},setItem:function(){},removeItem:function(){}};
var requestAnimationFrame=function(){};var fetch=window.fetch;
var supabase={createClient:function(){return{auth:{
  getSession:function(){return Promise.resolve({data:{session:null},error:null});},
  signInWithPassword:function(){return Promise.resolve({data:null,error:{message:'mock-no-login'}});},
  signOut:function(){return Promise.resolve({error:null});},
  onAuthStateChange:function(){}
}};} };
`;

// Fresh, isolated product context. Each call gets its own globals, its own pinned Date and
// no timers (setTimeout/setInterval are inert), so nothing leaks between scenarios.
function loadApp(opts) {
  opts = opts || {};
  const indexPath = opts.indexPath || process.env.HFOS_INDEX || path.join(REPO, 'index.html');
  const { sc } = productScript(indexPath);
  const sandbox = {
    console: opts.quiet === false ? console : { log() {}, warn() {}, error() {}, info() {}, debug() {} },
    setTimeout: function () { return 0; }, clearTimeout: function () {},
    setInterval: function () { return 0; }, clearInterval: function () {},
    queueMicrotask: queueMicrotask,
    crypto: require('crypto').webcrypto,
    TextEncoder, TextDecoder, URL, URLSearchParams,
  };
  const ctx = vm.createContext(sandbox);
  vm.runInContext(clockStubSource(opts.date) + DOM_STUB + sc, ctx, { filename: 'index.html#script' });
  return ctx;
}

// ── Spec §3 period oracle (independent of product code) ───────────────────────────
const DAY = 86400000;
const EPOCH_UTC = Date.UTC(2026, 5, 7); // Sunday 2026-06-07
const cal = {
  weekStartUTC(n) { return EPOCH_UTC + 7 * DAY * (n - 1); },
  planYearOfWeek(n) { return new Date(cal.weekStartUTC(n)).getUTCFullYear(); },
  firstWeekOfPlan(Y) {
    if (!(Y >= 2027)) throw new Error('firstWeekOfPlan undefined for ' + Y + ' (spec §3)');
    const jan1 = Date.UTC(Y, 0, 1);
    const dow = new Date(jan1).getUTCDay();
    const firstSunday = jan1 + ((7 - dow) % 7) * DAY;
    return (firstSunday - EPOCH_UTC) / (7 * DAY) + 1;
  },
  openingWeekOfPlan(Y) { return Y === 2026 ? 5 : cal.firstWeekOfPlan(Y) - 1; },
  finalWeekOfPlan(Y) { return cal.firstWeekOfPlan(Y + 1) - 1; },
  householdWeek(n) {
    const ws = cal.weekStartUTC(n);
    const Y = new Date(ws).getUTCFullYear();
    const jan1 = Date.UTC(Y, 0, 1);
    const firstSunday = jan1 + ((7 - new Date(jan1).getUTCDay()) % 7) * DAY;
    return { year: Y, week: (ws - firstSunday) / (7 * DAY) + 1 };
  },
};

// ── Schedule composition (spec §5.1, §14, §22 step 4) ─────────────────────────────
// src: { frozen: <31 frozen 2026 rows>, blocks: { 2027: rows, 2028: rows, ... } }
// Plan 2026 → the full 31-row frozen source (the 2026 golden runs on all 31 frozen rows).
// Plan Y ≥ 2027 → frozen rows below firstWeekOfPlan(2027), then each block for plans ≤ Y,
// truncated at finalWeekOfPlan(Y) so a later block can never reach plan Y's look-ahead.
function compositionFor(planYear, src) {
  if (!src || !Array.isArray(src.frozen)) throw new Error('compositionFor: src.frozen required');
  if (planYear === 2026) return src.frozen.slice();
  const cut = cal.firstWeekOfPlan(2027);
  const out = src.frozen.filter(r => r[0] < cut);
  const years = Object.keys(src.blocks || {}).map(Number).filter(y => y <= planYear).sort((a, b) => a - b);
  years.forEach(y => { (src.blocks[y] || []).forEach(r => out.push(r)); });
  const last = cal.finalWeekOfPlan(planYear);
  const res = out.filter(r => r[0] <= last);
  for (let i = 0; i < res.length; i++) {
    if (res[i][0] !== i + 1) throw new Error('compositionFor: schedule not contiguous at index ' + i + ' (week ' + res[i][0] + ')');
  }
  if (res.length !== last) throw new Error('compositionFor: plan ' + planYear + ' needs weeks 1..' + last + ', got ' + res.length);
  return res;
}

// Synthetic, NON-HOUSEHOLD schedule rows for plan Y. Amounts are arbitrary round fixture
// values; labels are prefixed SYNTH so no protected-payee tagging rule can match.
// wd[2]/wd[3] are derived from wd[4] so the tuple is self-consistent (Gate 1 hazard H4).
function synthPlanBlock(Y, opts) {
  opts = opts || {};
  const first = cal.firstWeekOfPlan(Y), last = cal.finalWeekOfPlan(Y);
  const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const rows = [];
  for (let n = first; n <= last; n++) {
    const ws = new Date(cal.weekStartUTC(n));
    const d = MO[ws.getUTCMonth()] + ' ' + ws.getUTCDate();
    const evs = [];
    if ((n - first) % 2 === 0) evs.push({ l: 'SYNTH income', t: 'in', a: opts.income || 4000, d: d });
    evs.push({ l: 'SYNTH bill', t: 'ob', a: -(opts.bill || 1500), d: d });
    if (opts.spike && opts.spike[n]) evs.push({ l: 'SYNTH spike', t: 'ob', a: -opts.spike[n], d: d });
    const inflows = evs.filter(e => e.t === 'in').map(e => e.a);
    const bills = evs.filter(e => e.t === 'ob').map(e => Math.abs(e.a));
    rows.push([n, 'SYNTH ' + Y + ' wk ' + (n - first + 1), inflows, bills, evs, 0, 0, '']);
  }
  return rows;
}

function frozen2026Rows(ctx) {
  const rows = (typeof ctx.WD_2026_FROZEN !== 'undefined' && ctx.WD_2026_FROZEN) ? ctx.WD_2026_FROZEN : ctx.WD;
  if (!Array.isArray(rows) || rows.length !== 31) throw new Error('frozen 2026 source must have 31 rows, got ' + (rows && rows.length));
  return rows;
}

// Run fn with ctx bound to the frozen 2026 composition and the 2026 goal inputs (the
// hard-coded fallback registry the golden was captured with), restoring every global after.
function withFrozen2026(ctx, fn) {
  const keys = ['WD', 'overrideData', 'goalSnapData', 'currentW', 'GOALS_REGISTRY', 'REGULAR_WATERFALL',
    'VARIABLE_WATERFALL', 'PRIORITY_TIERS', 'goalsLoadStatus'];
  const save = {};
  keys.forEach(k => { save[k] = ctx[k]; });
  try {
    ctx.WD = frozen2026Rows(ctx);
    ctx.overrideData = {};
    ctx.goalSnapData = {};
    ctx.applyGoalsFromData(ctx.HARDCODED_GOALS_FALLBACK.map(g => Object.assign({}, g)));
    return fn(ctx);
  } finally {
    keys.forEach(k => { ctx[k] = save[k]; });
  }
}

function goldenDerive(ctx, meta) {
  const sw = ctx.currentW; ctx.currentW = meta.pinnedCurrentW;
  try {
    const w = ctx.runModel(meta.runModelArgs[0], meta.runModelArgs[1]);
    const vmod = ctx.buildDashboardViewModel(w, { ak: meta.runModelArgs[0], rt: meta.runModelArgs[1] });
    const ggf = {}; meta.goalOrder.forEach(id => { ggf[id] = ctx.getGoalFunded(id, vmod); });
    return { weeks: w, goalCompletion: vmod.goalCompletion, getGoalFunded: ggf };
  } finally { ctx.currentW = sw; }
}

// Strict structural deep-equal (same contract as the C1 golden gate in test_regression.js).
// Values crossing the vm boundary are normalised through JSON first.
function deepEq(a, b, p) {
  p = p || '$';
  if (a === b) return;
  if (a === null || b === null || typeof a !== typeof b) throw new Error('mismatch at ' + p + ': ' + JSON.stringify(a) + ' !== ' + JSON.stringify(b));
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b)) throw new Error('array/non-array at ' + p);
    if (a.length !== b.length) throw new Error('array length at ' + p + ': ' + a.length + ' !== ' + b.length);
    for (let i = 0; i < a.length; i++) deepEq(a[i], b[i], p + '[' + i + ']');
    return;
  }
  if (typeof a === 'object') {
    const ka = Object.keys(a).sort(), kb = Object.keys(b).sort();
    if (ka.length !== kb.length || ka.some((k, i) => k !== kb[i])) throw new Error('key-set mismatch at ' + p + ': [' + ka + '] vs [' + kb + ']');
    ka.forEach(k => deepEq(a[k], b[k], p + '.' + k));
    return;
  }
  throw new Error('value mismatch at ' + p + ': ' + JSON.stringify(a) + ' !== ' + JSON.stringify(b));
}
function plain(x) { return JSON.parse(JSON.stringify(x)); }

module.exports = {
  REPO, LEGACY_DEFAULT_TEST_DATE, resolveTestDate, clockStubSource, productScript, loadApp,
  cal, compositionFor, synthPlanBlock, frozen2026Rows, withFrozen2026, goldenDerive, deepEq, plain,
};
