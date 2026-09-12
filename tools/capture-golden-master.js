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
//   node tools/capture-golden-master.js --write        # overwrite the fixture
//   node tools/capture-golden-master.js --write --note "why"
//
// The derivation mirrors reDerive() in test_regression.js exactly: same eval
// harness and stub, currentW pinned to the fixture's pinnedCurrentW so
// getGoalFunded is deterministic and calendar-stable, and the capture runs
// before anything can mutate model globals.
// ═══════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const htmlPath = process.env.HFOS_INDEX || path.join(REPO, 'index.html');
const fixturePath = path.join(REPO, 'fixtures', 'runmodel-golden-pre-1c-2.json');
const write = process.argv.includes('--write');
const noteIdx = process.argv.indexOf('--note');
const note = noteIdx > -1 ? process.argv[noteIdx + 1] : null;

const prior = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const meta = prior._meta;

// ── Same harness as test_regression.js ────────────────────────────────────
const html = fs.readFileSync(htmlPath, 'utf8');
const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
if (!scriptMatch) throw new Error('No <script> block found in ' + htmlPath);
let sc = scriptMatch[1]
  .replace(/\bconst\b/g, 'var')
  .replace(/^try\s*\{[\s\S]*?\}\s*catch[\s\S]*?\}/m, '')
  .replace(/^loadAll\(\);/m, '');

const stub = `
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

const derive = new Function('META', stub + sc + `
  var _sw = currentW;
  currentW = META.pinnedCurrentW;
  try {
    var w  = runModel(META.runModelArgs[0], META.runModelArgs[1]);
    var vm = buildDashboardViewModel(w, { ak: META.runModelArgs[0], rt: META.runModelArgs[1] });
    var ggf = {};
    META.goalOrder.forEach(function(id){ ggf[id] = getGoalFunded(id, vm); });
    return { weeks: w, goalCompletion: vm.goalCompletion, getGoalFunded: ggf };
  } finally { currentW = _sw; }
`);

const D = derive(meta);

// ── Structural guards: refuse to emit a fixture of the wrong shape ────────
function must(cond, msg){ if(!cond){ console.error('REFUSING TO CAPTURE: ' + msg); process.exit(1); } }
must(Array.isArray(D.weeks) && D.weeks.length === prior.weeks.length,
  'weeks length ' + (D.weeks||[]).length + ' != prior ' + prior.weeks.length);
must(Object.keys(D.goalCompletion).length === Object.keys(prior.goalCompletion).length,
  'goalCompletion key count changed');
must(Object.keys(D.getGoalFunded).length === meta.goalOrder.length,
  'getGoalFunded key count != goalOrder length');

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
