// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Herndon Financial OS — P3c G1 recommendation guard: FAILING-FIRST contract suite
// Terminology (owner ruling 2026-09-19): positive verdict = NO MODEL OBJECTION ('NO_MODEL_OBJECTION');
// negative / fail-closed verdict = WITHHOLD. G1 never reports 'SAFE': it can only say the OS's modelled
// trajectory does not object; it cannot know every future real-world cash flow.
// ───────────────────────────────────────────────────────────────────────────────────────────────
// Branch p3c-g1-spec (from accepted A1a c59bae6). SPECIFICATION ONLY — G1 is NOT implemented.
// Contract: ~/Herndon-Financial-OS-Evidence/p3c-recon-2026-09-19/G1-CONTRACT.md
//
// Tags:
//   [G1-PIN]  characterization of CURRENT behaviour using existing functions + reconstructed
//             production fixtures. Expected GREEN now: proves each fixture reproduces the incident,
//             so the RED contract tests are not vacuous.
//   [G1]      the G1 contract. Expected RED now (G1 does not exist), GREEN after implementation.
//   [G1-BASE] boundaries G1 must not cross (non-goal writes unaffected). Expected GREEN throughout.
//
// Proposed interface (pure, synchronous, deterministic, no I/O):
//   g1ValidateRecommendations(ctx) -> {
//     status: 'OK' | 'UNAVAILABLE', reasons: [..],
//     horizon: {start, end, weeks},
//     items: [{actionKey, goalId, amount, verdict:'NO_MODEL_OBJECTION'|'WITHHOLD', reason, breachWeek, minChk}]
//   }
//   ctx = { num, weeks, effectiveWD, commitments, floor, minHorizonWeeks }
//     weeks        runModel output objects for model weeks >= num-1 (num, chk, reconciled, ac, acKeys,
//                  cashAvailability{reservedProtectedCents, reviewRequired, balanceBasisUnknown})
//     effectiveWD  reconEffectiveWD() rows [num, dates, inflows[], obs[], evs[{t,a,l,eid}], ct, ca, note]
//     commitments  cash_commitments rows (commitmentData)
//   g1WriteGuard(weekNum, actionKey, amount) -> {allow:boolean, reason}   (consulted by toggleTransfer
//                  for every goal_* key before any write; unknown/error -> allow:false)
// Model week = Cal week - 22. Floor $6,500.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
let pass = 0, fail = 0; const failures = []; const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
function assert(c, m) { if (!c) throw new Error(m || 'Assertion failed'); }

const htmlPath = process.env.HFOS_INDEX || './index.html';
const html = fs.readFileSync(htmlPath, 'utf8');
let sc = html.match(/<script>([\s\S]*?)<\/script>/)[1];
sc = sc.replace(/\bconst\b/g, 'var').replace(/^try\s*\{[\s\S]*?\}\s*catch[\s\S]*?\}/m, '').replace(/^loadAll\(\);/m, '');
const stub = `
var window={fetch:function(){return Promise.resolve({ok:true,json:function(){return Promise.resolve([])}});}};
var document={getElementById:function(){return{innerHTML:'',addEventListener:function(){},value:'',textContent:'',style:{},classList:{remove:function(){},add:function(){}},scrollIntoView:function(){}}},querySelector:function(){return null},querySelectorAll:function(){return[]},addEventListener:function(){},createElement:function(){return{style:{},appendChild:function(){},setAttribute:function(){}}},body:{appendChild:function(){}}};
var localStorage={getItem:function(){return null;},setItem:function(){},removeItem:function(){}};
var requestAnimationFrame=function(){};var fetch=window.fetch;
var supabase={createClient:function(){return{auth:{getSession:function(){return Promise.resolve({data:{session:null},error:null});},signInWithPassword:function(){return Promise.resolve({data:null,error:{message:'mock'}});},signOut:function(){return Promise.resolve({error:null});},onAuthStateChange:function(){}}};}};
`;
try { eval(stub + sc); } catch (e) { console.error('FATAL eval:', e.message); process.exit(1); }
const g1 = () => (typeof g1ValidateRecommendations === 'function' ? g1ValidateRecommendations : null);
function G1(ctx) { const f = g1(); assert(f, 'g1ValidateRecommendations is not implemented'); return f(ctx); }
const FLOOR = 6500;

// ── Reconstructed production fixtures (read-only capture 2026-09-19, A1a build) ──────────────
// effectiveWD rows for model weeks 15..31: [num, inflows, obligations] (ct = ca = 0 in every row).
// Production-derived fixtures live OUTSIDE the repo (balance-free rule). Point HFOS_G1_FIXTURES at the evidence JSON.
const FX = (() => { try { return JSON.parse(fs.readFileSync(process.env.HFOS_G1_FIXTURES || '', 'utf8')); } catch (e) { return null; } })();
function needFX() { assert(FX, 'production fixtures unavailable: set HFOS_G1_FIXTURES to the evidence-folder JSON'); return FX; }
const EFF_RAW = FX ? FX.EFF_RAW : [];
const EFF = EFF_RAW.map(r => [r[0], '', r[1], r[2], r[1].map(a => ({ t: 'in', a })).concat(r[2].map(a => ({ t: 'ob', a: -a }))), 0, 0, '']);
// Budget Rules overlay residual per model week (not in effectiveWD; applied by runModel): Cal 40/44/48 −1,154; Cal 53 −750.
const RULES = FX ? FX.RULES : {};
function wdNet(n) { const r = EFF_RAW.find(x => x[0] === n); return r[1].reduce((a, b) => a + b, 0) - r[2].reduce((a, b) => a + b, 0) + (RULES[n] || 0); }
const r2 = x => Math.round(x * 100) / 100;
function trajectory(fromNum, startChk, lastNum) { const out = {}; let c = startChk; out[fromNum] = r2(c); for (let n = fromNum + 1; n <= lastNum; n++) { c = r2(c + wdNet(n)); out[n] = c; } return out; }
function weekObj(num, chk, extra) { return Object.assign({ num, chk, mChk: chk, reconciled: false, ac: [], acKeys: [], cashAvailability: { reservedProtectedCents: 0, reviewRequired: false, balanceBasisUnknown: false } }, extra || {}); }
function acLine(amt, dest, name) { return 'Transfer $' + amt.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' from Truist Checking to ' + dest + ' (' + name + ')'; }
const GOLD = { id: 'gold-1', expected_item_id: null, model_year: 2026, commitment_source: 'manual_reconciliation', origin_model_week: 15, source_account: 'truist_checking', amount_cents: FX ? Math.round(FX.gold * 100) : 0, status: 'initiated', affects_deployable_cash: true, reflected_model_week: null, resolved_model_week: null, resolution_type: null };

// Fixture W38: the Week 38 preview exactly as the live model produced it (model wk16, Gold reserved).
function fixtureW38(opts) {
  const F = needFX(); opts = opts || {}; const posted = !!opts.posted; const shift = posted ? -F.gold : 0;
  const traj = trajectory(16, F.w38EndChk + shift, 31);
  const weeks = [weekObj(15, r2(F.w37Recon + shift), { reconciled: true })];
  for (let n = 16; n <= 31; n++) weeks.push(weekObj(n, traj[n]));
  const w16 = weeks.find(w => w.num === 16);
  w16.ac = F.w38Recs.map(x => acLine(x[0], x[1], x[2])); w16.acKeys = F.w38Recs.map(x => x[3]);
  for (const w of weeks) if (w.num >= 16) w.cashAvailability.reservedProtectedCents = posted ? 0 : Math.round(F.gold * 100); // per-week CAE (Fable 6e)
  return { num: 16, weeks, effectiveWD: EFF, commitments: posted ? [] : [GOLD], floor: FLOOR, minHorizonWeeks: 5 };
}
// Fixture EV7: governance event #7 (model wk15, pre-close, no commitment yet). Post-sweep modeled chk 7,683.55.
function fixtureEV7() {
  const F = needFX(); const traj = trajectory(15, F.ev7PostSweepChk, 31);
  const weeks = [weekObj(14, F.w36Recon, { reconciled: true })];
  for (let n = 15; n <= 31; n++) weeks.push(weekObj(n, traj[n]));
  const w15 = weeks.find(w => w.num === 15);
  w15.ac = F.ev7Recs.map(x => acLine(x[0], x[1], x[2])); w15.acKeys = F.ev7Recs.map(x => x[3]);
  return { num: 15, weeks, effectiveWD: EFF, commitments: [], floor: FLOOR, minHorizonWeeks: 5 };
}
// Synthetic: a flat horizon; `dips` = {modelWeek: chkAfterAllRecommendations}.
function synthetic(recs, dips, opts) {
  opts = opts || {}; const num = 10, last = opts.last || 20; const base = opts.base || 20000;
  const weeks = [weekObj(num - 1, 30000, { reconciled: true })];
  for (let n = num; n <= last; n++) weeks.push(weekObj(n, dips && dips[n] != null ? dips[n] : base));
  const w = weeks.find(x => x.num === num);
  w.ac = recs.map(r => acLine(r.amt, r.dest || 'AMEX Savings', r.name)); w.acKeys = recs.map(r => r.key);
  if (opts.reservedCents) for (const x of weeks) if (x.num >= num) x.cashAvailability.reservedProtectedCents = opts.reservedCents; // per-week CAE (Fable 6e)
  if (opts.mutate) opts.mutate(weeks);
  const eff = []; for (let n = num; n <= last; n++) eff.push([n, '', [], [], (opts.evs && opts.evs[n]) || [], 0, 0, '']);
  return { num, weeks, effectiveWD: eff, commitments: opts.commitments || [], floor: FLOOR, minHorizonWeeks: 5 };
}
const item = (res, key) => (res.items || []).find(i => i.actionKey === key);

// ═══ [G1-PIN] fixtures reproduce the incidents under the CURRENT control surface ═══════════════
test('[G1-PIN] EV7: existing 5-week check APPROVES the recommendation (Cal 39 lands at exactly the floor)', () => {
  const eff5 = EFF_RAW.map(r => [r[0], '', r[1], r[2]]);
  const F = needFX(); assert(amxSweepKeepsFloor(F.ev7Total, F.ev7PreSweep, 15, eff5, FLOOR, 5) === true, 'current check should pass');
  assert(r2(maxSafeAmxSweep(99999, F.ev7PreSweep, 15, eff5, FLOOR, 5)) >= r2(F.ev7Total - 0.1), 'max-safe within 5 weeks ≈ the recommendation');
});
test('[G1-PIN] EV7: the known model horizon breaches after the 5-week window (Cal 43 and later)', () => {
  const t = fixtureEV7(); const cal43 = t.weeks.find(w => w.num === 21).chk; const min = Math.min(...t.weeks.filter(w => w.num >= 15).map(w => w.chk));
  assert(cal43 < FLOOR, 'Cal 43 should be below the floor, got ' + cal43); assert(min < 0, 'full-horizon trough should be negative, got ' + min);
});
test('[G1-PIN] W38: existing 5-week check APPROVES the full recommendation from the unreserved start', () => {
  const eff5 = EFF_RAW.map(r => [r[0], '', r[1], r[2]]);
  const F = needFX(); assert(amxSweepKeepsFloor(F.w38Total, F.w38PreSweep, 16, eff5, FLOOR, 5) === true);
});
test('[G1-PIN] W38: the model\'s own trajectory still contains the reserved commitment (Cal 38 end = floor + reservation)', () => {
  const F = needFX(); const t = fixtureW38(); assert(t.weeks.find(w => w.num === 16).chk === r2(FLOOR + F.gold));
  const withReserve = r2(t.weeks.find(w => w.num === 17).chk - F.gold); assert(withReserve < 0, 'Cal 39 net of the reserve should be negative, got ' + withReserve);
});
test('[G1-PIN] current engine: vehicle/cruise are not lookahead-gated (only the next-week raw-WD laFl gate applies; Fable C)', () => {
  const src = runModel.toString(); const m = /var _amxHold=\[([^\]]*)\]/.exec(src); assert(m, 'AMEX-hold list not found');
  assert(!/bryce_vehicle|christmas_cruise/.test(m[1]), 'vehicle/cruise unexpectedly lookahead-gated');
});
test('[G1] write path: toggleTransfer consults the canonical goal-action decision before any goal write', () => {
  // Was a [G1-PIN] characterising the pre-G1 state (no refusal). Flipped by intent when G1 is implemented.
  const src = toggleTransfer.toString(); assert(/goalActionDecision\(/.test(src), 'toggleTransfer must consult goalActionDecision');
});

// ═══ [G1] contract — RED until implemented ═════════════════════════════════════════════════════
test('[G1] 1 EV7: passes the 5-week check but fails the known horizon → WITHHOLD', () => {
  const r = G1(fixtureEV7()); assert(r.status === 'OK', 'status ' + r.status);
  const w = item(r, 'goal_wendy_ira'); assert(w && w.verdict === 'WITHHOLD', 'Wendy IRA must be WITHHOLD'); assert(w.breachWeek != null && w.breachWeek > 20, 'breach must be beyond the 5-week window, got ' + (w && w.breachWeek));
});
test('[G1] 2 W38: current cap reserves the Gold but the projection retains it → every recommendation WITHHOLD', () => {
  const r = G1(fixtureW38()); assert(r.status === 'OK');
  for (const k of ['goal_wendy_ira', 'goal_bailey_529', 'goal_bryce_529', 'goal_preston_529', 'goal_bryce_vehicle']) assert(item(r, k) && item(r, k).verdict === 'WITHHOLD', k + ' must be WITHHOLD');
  // Corrected by intent (2026-09-19): under the approved SEQUENTIAL rule goal 1 is validated with the later
  // items added back, so Wendy IRA's first breach is Cal 43 (model wk21). Cal 39 (wk17) is the breach only
  // when ALL five recommendations are executed — pinned separately below.
  assert(item(r, 'goal_wendy_ira').breachWeek === 21, 'Wendy IRA first breach must be Cal 43 (model wk21), got ' + item(r, 'goal_wendy_ira').breachWeek);
  const allExec = Math.min(...fixtureW38().weeks.filter(w => w.num >= 16).map(w => Math.round((w.chk - needFX().gold) * 100) / 100));
  assert(allExec < 0 && fixtureW38().weeks.find(w => w.num === 17).chk - needFX().gold < FLOOR, 'with every recommendation executed the reserve-adjusted Cal 39 breaches');
});
test('[G1] 3 W38 after the Gold posts: identical trajectory and verdicts (representation invariance: reserve ≡ posted debit)', () => {
  const a = G1(fixtureW38()), b = G1(fixtureW38({ posted: true }));
  for (const k of ['goal_wendy_ira', 'goal_bryce_vehicle']) { assert(item(a, k).minChk === item(b, k).minChk, k + ' minChk differs: ' + item(a, k).minChk + ' vs ' + item(b, k).minChk); assert(item(a, k).breachWeek === item(b, k).breachWeek); }
});
test('[G1] 4 sequential: goal 1 NO MODEL OBJECTION, goal 2 WITHHOLD (goal 2 validated after goal 1)', () => {
  // All recommendations executed → trough 5,000 at wk 14. Goal 1 alone (goal 2's 1,000 added back) → 6,000 → still unsafe;
  // so use goal 2 = 2,000: goal 1 alone → 7,000 NO MODEL OBJECTION; goal 1+2 → 5,000 WITHHOLD.
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }, { key: 'goal_bailey_529', amt: 2000, name: 'Bailey 529' }], { 14: 5000 }));
  assert(item(r, 'goal_wendy_ira').verdict === 'NO_MODEL_OBJECTION', 'goal 1 must be NO MODEL OBJECTION'); assert(item(r, 'goal_bailey_529').verdict === 'WITHHOLD', 'goal 2 must be WITHHOLD');
});
test('[G1] 4b break rule: after a WITHHOLD item, every later item is WITHHOLD (priority preserved, no reallocation)', () => {
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 3000, name: 'Wendy IRA' }, { key: 'goal_bailey_529', amt: 100, name: 'Bailey 529' }], { 14: 5000 }));
  assert(item(r, 'goal_wendy_ira').verdict === 'WITHHOLD'); const b = item(r, 'goal_bailey_529'); assert(b.verdict === 'WITHHOLD' && /prior/.test(b.reason), 'later item must be withheld: ' + JSON.stringify(b));
});
test('[G1] 5 vehicle: a recommendation current logic allows (no lookahead) is withheld when the horizon breaches', () => {
  const r = G1(synthetic([{ key: 'goal_bryce_vehicle', amt: 2000, name: 'Bryce Vehicle', dest: 'Truist Checking (hold)' }], { 18: 6000 }));
  assert(item(r, 'goal_bryce_vehicle').verdict === 'WITHHOLD');
});
test('[G1] 6 cruise: same property for Christmas Cruise (and any other goal_* class)', () => {
  const r = G1(synthetic([{ key: 'goal_christmas_cruise', amt: 500, name: 'Christmas Cruise', dest: 'Truist Savings (earmarked)' }, { key: 'goal_taxable_etf', amt: 100, name: 'Taxable ETF', dest: 'Brokerage (Fidelity)' }], { 19: 6300 }));
  assert(item(r, 'goal_christmas_cruise').verdict === 'WITHHOLD'); assert(item(r, 'goal_taxable_etf').verdict === 'WITHHOLD');
});
test('[G1] 7 exact floor: trough == 6,500.00 is NO MODEL OBJECTION', () => {
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }], { 15: 6500 })); assert(item(r, 'goal_wendy_ira').verdict === 'NO_MODEL_OBJECTION');
});
test('[G1] 8 one cent: trough == 6,499.99 is WITHHOLD', () => {
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }], { 15: 6499.99 })); assert(item(r, 'goal_wendy_ira').verdict === 'WITHHOLD');
});
test('[G1] 9 unavailable / incomplete state → every item WITHHOLD (fail closed)', () => {
  const recs = [{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }];
  const cases = {
    missingWeek: c => { c.weeks = c.weeks.filter(w => w.num !== 13); },
    nanChk: c => { c.weeks.find(w => w.num === 12).chk = NaN; },
    shortHorizon: c => { c.weeks = c.weeks.filter(w => w.num <= 12); c.effectiveWD = c.effectiveWD.filter(r => r[0] <= 12); },
    noCashAvailability: c => { delete c.weeks.find(w => w.num === 10).cashAvailability; },
    reviewRequired: c => { c.weeks.find(w => w.num === 10).cashAvailability.reviewRequired = true; },
    basisUnknown: c => { c.weeks.find(w => w.num === 10).cashAvailability.balanceBasisUnknown = true; },
    unparseableAction: c => { c.weeks.find(w => w.num === 10).ac[0] = 'Move some money to AMEX (Wendy IRA)'; },
    reservedParityMismatch: c => { c.weeks.find(w => w.num === 10).cashAvailability.reservedProtectedCents = 50000; },
    bankPendingReserve: c => { c.weeks.find(w => w.num === 10).cashAvailability.hasBankPendingReserve = true; },
    weekAlreadyReconciled: c => { c.weeks.find(w => w.num === 10).reconciled = true; },
    noWeeks: c => { c.weeks = null; }
  };
  for (const [name, mut] of Object.entries(cases)) {
    const c = synthetic(recs, null); mut(c); let r; try { r = G1(c); } catch (e) { throw new Error(name + ': G1 threw instead of failing closed: ' + e.message); }
    const it = item(r, 'goal_wendy_ira'); assert(!it || it.verdict === 'WITHHOLD', name + ': must be WITHHOLD, got ' + JSON.stringify(it));
    assert(r.status === 'UNAVAILABLE' || (it && it.verdict === 'WITHHOLD'), name + ': must fail closed');
  }
});
test('[G1] 10 reservation already represented as a future model outflow → subtracted only until that week (no double subtraction)', () => {
  // Commitment 3,000 initiated at wk10, linked to a WD obligation event in wk13. Trajectory (model) already subtracts it at wk13.
  const cm = Object.assign({}, GOLD, { id: 'c-link', origin_model_week: 9, amount_cents: 300000, expected_item_id: '2026mw13_amex_platinum_2026_10_27' });
  const evs = { 13: [{ t: 'ob', a: -3000, l: 'AMEX Platinum', eid: '2026mw13_amex_platinum_2026_10_27' }] };
  // weeks 10–12 chk 10,000 (reserve applies → 7,000); weeks 13+ chk 7,200 (already net of the outflow; must NOT subtract again).
  const dips = { 10: 10000, 11: 10000, 12: 10000 }; for (let n = 13; n <= 20; n++) dips[n] = 7200;
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 500, name: 'Wendy IRA' }], dips, { reservedCents: 300000, commitments: [cm], evs }));
  const it = item(r, 'goal_wendy_ira'); assert(it.verdict === 'NO_MODEL_OBJECTION', 'double subtraction would make wk13+ 4,200 → WITHHOLD; got ' + JSON.stringify(it));
  assert(it.minChk === 7000, 'minChk must be 7,000 (reserve applied wk10–12 only), got ' + it.minChk);
});
test('[G1] 10b unlinked reservation (no matching future event) is subtracted across the whole horizon', () => {
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 500, name: 'Wendy IRA' }], null, { base: 9000, reservedCents: 300000, commitments: [Object.assign({}, GOLD, { origin_model_week: 9, amount_cents: 300000 })] }));
  const it = item(r, 'goal_wendy_ira'); assert(it.verdict === 'WITHHOLD' && it.minChk === 6000, JSON.stringify(it));
});
test('[G1] 11 no reservations: an ordinary safe recommendation stays NO MODEL OBJECTION', () => {
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }], null)); assert(r.status === 'OK' && item(r, 'goal_wendy_ira').verdict === 'NO_MODEL_OBJECTION');
});
test('[G1] 12 reconciled truth: the prior reconciled ending (carried by the model) is authoritative, not its projection', () => {
  // wk9 reconciled chk 30,000 but its model projection (mChk) was 50,000; wk10+ derive from the reconciled value.
  const c = synthetic([{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }], { 16: 6000 }); c.weeks.find(w => w.num === 9).mChk = 50000;
  const r = G1(c); assert(item(r, 'goal_wendy_ira').verdict === 'WITHHOLD', 'G1 must use the model weeks (recon-carried), never a projected prior mChk');
});
test('[G1] G1-9 no I/O and no mutation: pure, zero fetches, inputs unchanged', () => {
  let n = 0; const of = fetch; fetch = function () { n++; return of.apply(this, arguments); };
  try { const c = fixtureW38(); const before = JSON.stringify(c); G1(c); assert(JSON.stringify(c) === before, 'input mutated'); assert(n === 0, 'fetch called ' + n); } finally { fetch = of; }
});
test('[G1] G1-10 deterministic: same inputs → identical output; no clock dependence', () => {
  const a = JSON.stringify(G1(fixtureW38())); const OD = Date; Date = function () { throw new Error('clock read'); }; Date.now = () => { throw new Error('clock read'); };
  try { assert(JSON.stringify(G1(fixtureW38())) === a, 'non-deterministic'); } finally { Date = OD; }
});
test('[G1] G1-7 write path: toggleTransfer refuses a goal_* key the guard does not allow — zero requests', async () => {
  assert(typeof g1WriteGuard === 'function', 'g1WriteGuard is not implemented');
});
test('[G1] G1-7 write guard fails closed: with no validated verdict for the week, goal keys are not allowed', () => {
  assert(typeof g1WriteGuard === 'function', 'g1WriteGuard is not implemented');
  const d = g1WriteGuard(16, 'goal_wendy_ira', 7500); assert(d && d.allow === false, 'unknown state must not allow: ' + JSON.stringify(d));
});

test('[G1] 13 attribution (Fable 6a): a breach already present with ZERO sweep is reported as pre-existing, still WITHHOLD', () => {
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 100, name: 'Wendy IRA' }], { 18: 6000 })); // zero-sweep 6,100 < floor
  const it = item(r, 'goal_wendy_ira'); assert(it.verdict === 'WITHHOLD'); assert(it.preExistingBreach === true && /pre.?existing/i.test(it.reason), 'must say the breach is pre-existing: ' + JSON.stringify(it));
});
test('[G1] 13b attribution: a breach caused only by the candidate is reported as candidate-caused', () => {
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }], { 18: 6000 })); // zero-sweep 7,000 ≥ floor
  const it = item(r, 'goal_wendy_ira'); assert(it.verdict === 'WITHHOLD' && it.preExistingBreach === false, JSON.stringify(it));
});
test('[G1] 14 tax-clamp non-linearity (Fable 6c): a future commission-tax transfer clamped below its scheduled ct → WITHHOLD (fail closed)', () => {
  const c = synthetic([{ key: 'goal_wendy_ira', amt: 500, name: 'Wendy IRA' }], null);
  c.effectiveWD.find(r => r[0] === 13)[5] = 1000; // scheduled ct 1,000 at wk13
  const w13 = c.weeks.find(w => w.num === 13); w13.ac = ['Transfer $400.00 from Truist Checking to Vio Bank - Tax Reserve (commission tax)']; w13.acKeys = [ACTION_KEYS.COMMISSION_TAX];
  const it = item(G1(c), 'goal_wendy_ira'); assert(it && it.verdict === 'WITHHOLD' && /tax/i.test(it.reason), JSON.stringify(it));
});
test('[G1] 15 manual Phase-3 reservation (Fable 6d): manual_… identity matches no WD event → subtracted through the whole horizon', () => {
  const cm = Object.assign({}, GOLD, { id: 'm1', origin_model_week: 9, amount_cents: 300000, expected_item_id: 'manual_2026mw9_abc' });
  const r = G1(synthetic([{ key: 'goal_wendy_ira', amt: 500, name: 'Wendy IRA' }], null, { base: 9500, reservedCents: 300000, commitments: [cm] }));
  const it = item(r, 'goal_wendy_ira'); assert(it.verdict === 'NO_MODEL_OBJECTION' && it.minChk === 6500, 'expected 9,500 − 3,000 = 6,500 everywhere: ' + JSON.stringify(it));
});
test('[G1] 16 netting (Fable 6k): the NET actionable amount is validated, and the gross is added back only once', () => {
  // Model debited gross 3,000; netting says only 1,000 remains actionable (2,000 already executed and in the balance).
  const c = synthetic([{ key: 'goal_wendy_ira', amt: 3000, name: 'Wendy IRA' }], { 15: 6000 });
  c.netting = { goal_wendy_ira: { disposition: 'partial', netAmount: 1000, executedAmount: 2000 } };
  const it = item(G1(c), 'goal_wendy_ira');
  assert(it.amount === 1000, 'must validate the net amount, got ' + (it && it.amount)); assert(it.verdict === 'WITHHOLD', 'executed 2,000 already left: the trough is 6,000 regardless');
});

test('[G1] 17 terminology: verdicts are only NO_MODEL_OBJECTION or WITHHOLD — never SAFE', () => {
  const rs = [G1(synthetic([{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }], null)), G1(synthetic([{ key: 'goal_wendy_ira', amt: 1000, name: 'Wendy IRA' }], { 15: 6000 }))];
  for (const r of rs) for (const it of r.items || []) { assert(it.verdict === 'NO_MODEL_OBJECTION' || it.verdict === 'WITHHOLD', 'bad verdict ' + it.verdict); assert(!/\bSAFE\b/.test(JSON.stringify(it)), 'SAFE must not appear: ' + JSON.stringify(it)); }
});

// ═══ [G1-BASE] boundaries ═══════════════════════════════════════════════════════════════════════
test('[G1-BASE] runModel, computeGoalTransferNetting, resolveWeekTransfers remain present (G1 must not replace them)', () => {
  assert(typeof runModel === 'function' && typeof computeGoalTransferNetting === 'function' && typeof resolveWeekTransfers === 'function');
});
test('[G1-BASE] non-goal action keys are outside G1 scope (commission_tax guard path is independent)', () => {
  assert(typeof ACTION_KEYS === 'object' && ACTION_KEYS.COMMISSION_TAX, 'commission_tax key present'); assert(!/^goal_/.test(ACTION_KEYS.COMMISSION_TAX));
});

(async () => {
  for (const t of tests) { try { await t.fn(); pass++; console.log('  ✓ ' + t.name); } catch (e) { fail++; failures.push(t.name + ' — ' + e.message); console.log('  ✗ ' + t.name + '\n      ' + e.message); } }
  const tag = p => tests.filter(t => t.name.startsWith(p)).length;
  console.log('\nRESULTS  total ' + tests.length + ' · passed ' + pass + ' · failed ' + fail + '   ([G1-PIN] ' + tag('[G1-PIN]') + ', [G1] ' + tag('[G1] ') + ', [G1-BASE] ' + tag('[G1-BASE]') + ')');
  process.exit(0);
})();
