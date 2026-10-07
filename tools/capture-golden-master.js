// ═══════════════════════════════════════════════════════════════════════════
// Golden-master capture — fixtures/runmodel-golden-pre-1c-2.json
// ───────────────────────────────────────────────────────────────────────────
// The original fixture (e1eac07, 2026-07-08) was captured by hand with no
// script, so it could not be reproduced or re-derived — which is part of why
// a stale baseline went unnoticed for five weeks after 2026-08-08. This tool
// makes the capture reproducible and auditable.
//
// PROTECTED OUTPUT. Per AGENTS.md, golden-master expected outputs are never
// regenerated to make a test pass without explicit Adam approval. Running this
// script IS that regeneration. Do not run it to clear a red suite; run it only
// when the owner has approved a re-baseline and the behavior delta is already
// characterised in writing.
//
// Usage:
//   node tools/capture-golden-master.js                # print to stdout
//   node tools/capture-golden-master.js --check        # re-derive and compare with the fixture (no write)
//   node tools/capture-golden-master.js --write        # overwrite the fixture
//   node tools/capture-golden-master.js --write --note "why"
//
// Plan selection (2027 rollover Package A, frozen spec v2.1 §14/§15/§22 step 4):
//   --plan 2026 (default) — the protected 2026 fixture above, derived on the frozen 2026
//     composition (WD_2026_FROZEN when the product defines it, else WD) with the 2026 goal
//     inputs (hard-coded fallback registry) pinned explicitly. Output is unchanged.
//   --plan <Y ≥ 2027> --schedule <blocks.json> --goals <registry.json> --current-week <n>
//       [--snapshots <snapshots.json>] [--fixture <path>]
//     derives plan Y on its own composition (frozen weeks 1-30 + blocks up to Y, truncated at
//     Y's final week). Refuses to touch the 2026 fixture. Synthetic inputs only until the owner
//     approves a real 2027 golden (§15).
//   --date YYYY-MM-DD pins the clock for the evaluated app (default: the legacy pin date).
//
// The derivation mirrors reDerive() in test_regression.js exactly: same eval
// harness and stub, currentW pinned to the fixture's pinnedCurrentW so
// getGoalFunded is deterministic and calendar-stable, and the capture runs
// before anything can mutate model globals.
// ═══════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const path = require('path');

const KIT = require('./rollover-test-kit');
const REPO = path.resolve(__dirname, '..');
const htmlPath = process.env.HFOS_INDEX || path.join(REPO, 'index.html');
const FIXTURE_2026 = path.join(REPO, 'fixtures', 'runmodel-golden-pre-1c-2.json');
function arg(name){ const i = process.argv.indexOf(name); return i > -1 ? process.argv[i + 1] : null; }
const write = process.argv.includes('--write');
const check = process.argv.includes('--check');
const note = arg('--note');
const plan = arg('--plan') ? Number(arg('--plan')) : 2026;
const clockDate = KIT.resolveTestDate(arg('--date') || process.env.HFOS_TEST_DATE);
if (!(plan === 2026 || plan >= 2027)) { console.error('REFUSING: --plan must be 2026 or a year >= 2027'); process.exit(1); }

let fixturePath, prior, meta, planInputs = null;
if (plan === 2026) {
  fixturePath = FIXTURE_2026;
  prior = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
  meta = prior._meta;
} else {
  const readJson = p => JSON.parse(fs.readFileSync(p, 'utf8'));
  if (!arg('--schedule') || !arg('--goals') || !arg('--current-week')) { console.error('REFUSING: --plan ' + plan + ' needs --schedule, --goals and --current-week'); process.exit(1); }
  fixturePath = path.resolve(arg('--fixture') || path.join(REPO, 'fixtures', 'runmodel-golden-' + plan + '.json'));
  if (fixturePath === FIXTURE_2026) { console.error('REFUSING: plan ' + plan + ' may not write the protected 2026 fixture'); process.exit(1); }
  const goals = readJson(arg('--goals'));
  planInputs = { blocks: readJson(arg('--schedule')), goals, snapshots: arg('--snapshots') ? readJson(arg('--snapshots')) : {} };
  prior = fs.existsSync(fixturePath) ? JSON.parse(fs.readFileSync(fixturePath, 'utf8')) : null;
  meta = { plan, runModelArgs: [7000, 7694.87], pinnedCurrentW: Number(arg('--current-week')), goalOrder: goals.map(g => g.id),
           finalWeek: KIT.cal.finalWeekOfPlan(plan), rebaselineHistory: prior ? (prior._meta.rebaselineHistory || []) : [] };
}

// ── Same harness as test_regression.js ────────────────────────────────────
const html = fs.readFileSync(htmlPath, 'utf8');
const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
if (!scriptMatch) throw new Error('No <script> block found in ' + htmlPath);
let sc = scriptMatch[1]
  .replace(/\bconst\b/g, 'var')
  .replace(/^try\s*\{[\s\S]*?\}\s*catch[\s\S]*?\}/m, '')
  .replace(/^loadAll\(\);/m, '');

const stub = KIT.clockStubSource(clockDate) + `
var window={fetch:function(){return Promise.resolve({ok:true,json:function(){return Promise.resolve([])}});}};
var document={getElementById:function(){return{innerHTML:'',addEventListener:function(){},value:'',textContent:'',style:{},classList:{remove:function(){},add:function(){}},scrollIntoView:function(){},focus:function(){},blur:function(){}};},querySelectorAll:function(){return[];},querySelector:function(){return null;},addEventListener:function(){},activeElement:null,body:{style:{}}};
var localStorage={getItem:function(){return null;},setItem:function(){}};
var requestAnimationFrame=function(){};var fetch=window.fetch;
var supabase={createClient:function(){return{auth:{
  getSession:function(){return Promise.resolve({data:{session:null},error:null});},
  signInWithPassword:function(){return Promise.resolve({data:null,error:{message:'mock-no-login'}});},
  signOut:function(){return Promise.resolve({error:null});},
  onAuthStateChange:function(){}
}};} };
`;

const derive = new Function('META', 'PLAN', 'COMPOSE', stub + sc + `
  var _sw = currentW;
  currentW = META.pinnedCurrentW;
  // Frozen 2026 composition and 2026 goal inputs, bound explicitly (Package A). Both are
  // no-ops on the pre-rollover product, whose WD is the frozen source and whose registry at
  // load is the hard-coded fallback.
  var _frozen = (typeof WD_2026_FROZEN !== 'undefined') ? WD_2026_FROZEN : WD;
  WD = PLAN ? COMPOSE(_frozen, PLAN.blocks) : _frozen;
  applyGoalsFromData((PLAN ? PLAN.goals : HARDCODED_GOALS_FALLBACK).map(function(g){ return Object.assign({}, g); }));
  overrideData = {};
  goalSnapData = PLAN ? PLAN.snapshots : {};
  try {
    var w  = runModel(META.runModelArgs[0], META.runModelArgs[1]);
    var vm = buildDashboardViewModel(w, { ak: META.runModelArgs[0], rt: META.runModelArgs[1] });
    var ggf = {};
    META.goalOrder.forEach(function(id){ ggf[id] = getGoalFunded(id, vm); });
    return { weeks: w, goalCompletion: vm.goalCompletion, getGoalFunded: ggf };
  } finally { currentW = _sw; }
`);

const compose = (frozen, blocks) => KIT.compositionFor(plan, { frozen: JSON.parse(JSON.stringify(frozen)), blocks });
const D = JSON.parse(JSON.stringify(derive(meta, planInputs, compose)));

// ── Structural guards: refuse to emit a fixture of the wrong shape ────────
function must(cond, msg){ if(!cond){ console.error('REFUSING TO CAPTURE: ' + msg); process.exit(1); } }
if (plan === 2026) {
  must(Array.isArray(D.weeks) && D.weeks.length === prior.weeks.length,
    'weeks length ' + (D.weeks||[]).length + ' != prior ' + prior.weeks.length);
  must(Object.keys(D.goalCompletion).length === Object.keys(prior.goalCompletion).length,
    'goalCompletion key count changed');
} else {
  must(Array.isArray(D.weeks) && D.weeks.length === meta.finalWeek,
    'plan ' + plan + ' weeks length ' + (D.weeks||[]).length + ' != final week ' + meta.finalWeek);
}
must(Object.keys(D.getGoalFunded).length === meta.goalOrder.length,
  'getGoalFunded key count != goalOrder length');

if (check) {
  if (!prior) { console.error('CHECK: no existing fixture at ' + fixturePath); process.exit(1); }
  try {
    KIT.deepEq(D.weeks, prior.weeks, 'weeks'); KIT.deepEq(D.goalCompletion, prior.goalCompletion, 'goalCompletion');
    KIT.deepEq(D.getGoalFunded, prior.getGoalFunded, 'getGoalFunded');
  } catch (e) { console.error('CHECK FAILED: ' + e.message); process.exit(1); }
  console.log('CHECK OK: derived plan ' + plan + ' output is identical to ' + path.relative(REPO, fixturePath));
  process.exit(0);
}

const out = {
  _meta: Object.assign({}, meta, {
    capturedFromCommit: (process.env.HFOS_CAPTURE_COMMIT || 'see rebaselineHistory'),
    capturedAt: new Date().toISOString().slice(0,10),
    rebaselineHistory: (meta.rebaselineHistory || []).concat(note ? [note] : [])
  }),
  weeks: D.weeks,
  goalCompletion: D.goalCompletion,
  getGoalFunded: D.getGoalFunded
};

if (write) {
  fs.writeFileSync(fixturePath, JSON.stringify(out, null, 1) + '\n');
  console.log('WROTE ' + fixturePath);
} else {
  console.log(JSON.stringify(out._meta, null, 1));
  console.log('(dry run — pass --write to overwrite the fixture)');
}
// The evaluated app schedules timers (the auth-password focus retry). Exit now
// so the tool terminates deterministically instead of throwing from a stray
// timeout after the fixture has already been written.
process.exit(0);
