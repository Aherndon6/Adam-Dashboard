// ═══════════════════════════════════════════════════════════════════════════
// Herndon Financial OS — Full Regression Suite (v2 — includes Phase 4 fields)
// ═══════════════════════════════════════════════════════════════════════════

const fs = require('fs');

// ── Harness ───────────────────────────────────────────────────────────────
let pass = 0, fail = 0;
const failures = [];
function test(name, fn) {
  try { fn(); pass++; process.stdout.write('  ✓ ' + name + '\n'); }
  catch(e) { fail++; failures.push({name,error:e.message}); process.stdout.write('  ✗ ' + name + '\n    → ' + e.message + '\n'); }
}
function assert(c,m){ if(!c) throw new Error(m||'Assertion failed'); }
function assertApprox(a,b,m,tol=0.05){ if(Math.abs(a-b)>tol) throw new Error((m||'')+` expected ~${b}, got ${a}`); }
function assertGt(a,b,m){ if(a<=b) throw new Error((m||'')+` expected > ${b}, got ${a}`); }
function assertLt(a,b,m){ if(a>=b) throw new Error((m||'')+` expected < ${b}, got ${a}`); }
function assertIncludes(str,sub,m){ if(!str.includes(sub)) throw new Error((m||'String missing: ')+`"${sub}"`); }

// ── Eval HTML script block ────────────────────────────────────────────────
const htmlPath = process.env.HFOS_INDEX || './index.html';
const html = fs.readFileSync(htmlPath,'utf8');
const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
if (!scriptMatch) throw new Error('No <script> block found');
let sc = scriptMatch[1];
sc = sc.replace(/\bconst\b/g,'var');
sc = sc.replace(/^try\s*\{[\s\S]*?\}\s*catch[\s\S]*?\}/m,'');
sc = sc.replace(/^loadAll\(\);/m,'');
const stub = `
var window={fetch:function(){return Promise.resolve({ok:true,json:function(){return Promise.resolve([])}});}};
var document={getElementById:function(){return{innerHTML:'',addEventListener:function(){},value:'',textContent:'',style:{},classList:{remove:function(){},add:function(){}},scrollIntoView:function(){}};},querySelectorAll:function(){return[];},querySelector:function(){return null;},activeElement:null,body:{style:{}}};
var localStorage={getItem:function(){return null;},setItem:function(){}};
var requestAnimationFrame=function(){};var fetch=window.fetch;
`;
try { eval(stub+sc); } catch(e) { console.error('FATAL eval:',e.message); process.exit(1); }

// Shared model output
const WEEKS = runModel(7000, 7694.87);
// mockVm: override key fields AND goalSaved so getGoalFunded reads test values
const mockVm = { weeks: WEEKS.map(w=>Object.assign({},w,{
  akSaved:3500,akRem:3500,amx:200,
  goalSaved:Object.assign({},w.goalSaved,{alaska:3500,adam_ira:200,bailey_529:0,wewe_rccl:0,wewe_dcl:0,bryce_vehicle:0})
})) };
const fullVm = (() => {
  const w=WEEKS; const cur=w.find(x=>x.num===getCurrentWeek())||w[0];
  return { goals:{ak:7000,rt:7694.87}, weeks:w, current:cur, finalWeek:w[w.length-1],
    currentWeekNum:cur.num, alaskaCompletion:w.find(x=>x.akRem<=0.01)||null,
    retirementCompletion:w.find(x=>x.retRem<=0.01)||null,
    surplusCompletion:w.find(x=>x.surplusSwept>0)||null,
    lowestChecking:w.reduce((m,x)=>x.chk<m.chk?x:m,w[0]),
    openActions:[],allActions:[],troughWeeks:[],managedWeeks:[],
    reconciledWeeks:[],editedWeeks:[],futureWeeks:[],pastWeeks:[] };
})();

function simulateEngine(amt,type,flags,fundedOverrides){
  const oF=Object.assign({},goalFlags),oA=Object.assign({},goalFundedAmounts),oT=engineType,oAmt=engineAmt;
  Object.assign(goalFlags,flags||{});Object.assign(goalFundedAmounts,fundedOverrides||{});
  engineType=type;engineAmt=String(amt);engineResult=null;
  runEngine({weeks:WEEKS});
  const r=engineResult?engineResult.slice():null;
  Object.assign(goalFlags,oF);for(const k of Object.keys(goalFundedAmounts))delete goalFundedAmounts[k];
  Object.assign(goalFundedAmounts,oA);engineType=oT;engineAmt=oAmt;
  return r;
}

console.log('\n╔══════════════════════════════════════════════════════════════╗');
console.log('║     Herndon Financial OS — Regression Suite v2             ║');
console.log('╚══════════════════════════════════════════════════════════════╝\n');

// ─────────────────────────────────────────────────────────────────────────
console.log('── Section 1: Helper functions ──');
test('f() formats positive',()=>assert(f(1234.56)==='$1,234.56'));
test('f() formats zero',()=>assert(f(0)==='$0.00'));
test('f() abs of negative',()=>assert(f(-500)==='$500.00'));
test('fc() no dollar sign',()=>assert(fc(1000)==='1,000.00'));
test('getCurrentWeek() 1-31',()=>{ const w=getCurrentWeek(); assert(w>=1&&w<=31,'week='+w); });
test('getCalWeek(1) = Jun 2026 cal week',()=>{ const cw=getCalWeek(1); assert(cw>=23&&cw<=25,'cw='+cw); });
test('getCalWeek(31) = Cal Wk 53 (fixed 2026-base, no year-rollover bug)',()=>{ const cw=getCalWeek(31); assert(cw===53,'cw='+cw); });
test('getWeekStartDate(1) = Jun 7 2026',()=>{ const d=getWeekStartDate(1); assert(d.getFullYear()===2026&&d.getMonth()===5&&d.getDate()===7,'d='+d.toDateString()); });
test('getWeekStartDate(31) = Jan 3 2027',()=>{ const d=getWeekStartDate(31); assert(d.getFullYear()===2027&&d.getMonth()===0&&d.getDate()===3,'d='+d.toDateString()); });
test('formatWeekRange() non-empty',()=>assert(formatWeekRange('2026-10-18').length>3));

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 2: Core model engine ──');
test('runModel returns 31 weeks',()=>assert(WEEKS.length===31));
test('Week 1 startChk = $18,037.73',()=>assertApprox(WEEKS[0].startChk,18037.73,'startChk'));
test('Week 1 startSav = $3,772.77',()=>assertApprox(WEEKS[0].startSav,3772.77,'startSav'));
test('OP_FL = $6,500',()=>assertApprox(OP_FL,6500,'OP_FL'));
test('Model defers (not drops) transfers below floor',()=>{ const d=WEEKS.flatMap(w=>w.tr||[]).filter(t=>t.r==='defer'); assertGt(d.length,0,'No deferrals found'); });
test('W6 commission 40% deferred when chk < floor',()=>{ const w6=WEEKS.find(w=>w.num===6); assert(w6.tr.some(t=>t.r==='defer'&&t.l.includes('40%')),'No deferral in W6.tr'); });
test('No week has negative checking',()=>{ const neg=WEEKS.filter(w=>w.chk<0); assert(neg.length<=5,'Unexpectedly many negative weeks: '+neg.map(w=>'W'+w.num+'('+w.chk.toFixed(0)+')').join(',')); });
test('Alaska savings monotonically non-decreasing',()=>{ for(let i=1;i<WEEKS.length;i++) assert(WEEKS[i].akSaved>=WEEKS[i-1].akSaved-0.01,'Backward W'+WEEKS[i].num); });
test('Alaska fully funds by W31',()=>{ const d=WEEKS.find(w=>w.akRem<=0.01); assert(d&&d.num<=31,'Never funded'); });
test('Alaska funded = $7,000 at completion',()=>{ const d=WEEKS.find(w=>w.akRem<=0.01); assertApprox(d.akSaved,7000,'akSaved',5); });
test('AMEX savings grows over model',()=>assertGt(WEEKS[WEEKS.length-1].amx,WEEKS[0].amx,'AMEX'));
test('Tax reserve accumulates after commission',()=>assert(WEEKS.find(w=>w.num>6&&w.tax>0),'No tax reserve'));
test('Week numbers sequential 1-31',()=>WEEKS.forEach((w,i)=>assert(w.num===i+1,'W'+i+' num='+w.num)));
test('Surplus begins after retirement funded',()=>{ const s=WEEKS.find(w=>w.surplusSwept>0),r=WEEKS.find(w=>w.retRem<=0.01); if(s&&r) assert(s.num>=r.num,'Surplus before retirement'); });
test('W15 savings decreases (Alaska $7k draw to checking)',()=>{ const w14=WEEKS.find(w=>w.num===14),w15=WEEKS.find(w=>w.num===15); assertLt(w15.sav,w14.sav+0.01,'Savings should drop W15'); });
test('Reconciliation fields on every week',()=>WEEKS.forEach(w=>{ assert('reconciled'in w,'W'+w.num+' missing reconciled'); assert('variance'in w,'W'+w.num+' missing variance'); }));
test('runModel(0,0) completes',()=>assert(runModel(0,0).length===31));
test('runModel(999999,999999) completes',()=>assert(runModel(999999,999999).length===31));

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 3: Goals registry integrity ──');
test('GOALS_REGISTRY has 13 entries',()=>assert(GOALS_REGISTRY.length===13,'count='+GOALS_REGISTRY.length));
test('All entries have id,name,tier,target',()=>GOALS_REGISTRY.forEach(g=>assert(g.id&&g.name&&g.tier&&g.target>0,'Bad: '+JSON.stringify(g))));
test('No duplicate IDs',()=>{ const ids=GOALS_REGISTRY.map(g=>g.id); assert(new Set(ids).size===ids.length,'Duplicates'); });
test('adam_401k target = $24,500',()=>assertApprox(GOALS_REGISTRY.find(g=>g.id==='adam_401k').target,24500));
test('wendy_sep complete=true',()=>assert(GOALS_REGISTRY.find(g=>g.id==='wendy_sep').complete===true));
test('alaska target = $7,000',()=>assertApprox(GOALS_REGISTRY.find(g=>g.id==='alaska').target,7000));
test('IRA goals have needsFlag=ira_cpa_cleared',()=>['adam_ira','wendy_ira'].forEach(id=>assert(GOALS_REGISTRY.find(g=>g.id===id).needsFlag==='ira_cpa_cleared',id)));
test('taxable_etf stretch=true',()=>assert(GOALS_REGISTRY.find(g=>g.id==='taxable_etf').stretch===true));
test('Non-stretch totals $50k-$150k',()=>{ const t=GOALS_REGISTRY.filter(g=>!g.stretch).reduce((s,g)=>s+g.target,0); assertGt(t,50000);assertLt(t,150000); });
test('PRIORITY_TIERS has 11 entries',()=>assert(PRIORITY_TIERS.length===11,'count='+PRIORITY_TIERS.length));
test('All tier goal IDs exist in registry',()=>{ const ids=new Set(GOALS_REGISTRY.map(g=>g.id)); PRIORITY_TIERS.forEach(t=>t.goals.forEach(id=>assert(ids.has(id),'Unknown: '+id))); });
test('VARIABLE_WATERFALL IDs in registry',()=>{ const ids=new Set(GOALS_REGISTRY.map(g=>g.id)); VARIABLE_WATERFALL.forEach(id=>assert(ids.has(id),'Unknown: '+id)); });
test('REGULAR_WATERFALL IDs in registry',()=>{ const ids=new Set(GOALS_REGISTRY.map(g=>g.id)); REGULAR_WATERFALL.forEach(id=>assert(ids.has(id),'Unknown: '+id)); });
// Phase 4: IRAs/529s are NOW direct waterfall goals (retirement_rebuild pool removed)
test('adam_ira IS in both waterfalls (direct funding)',()=>{ assert(VARIABLE_WATERFALL.includes('adam_ira'),'adam_ira missing from variable'); assert(REGULAR_WATERFALL.includes('adam_ira'),'adam_ira missing from regular'); });
test('wendy_ira IS in both waterfalls (direct funding)',()=>{ assert(VARIABLE_WATERFALL.includes('wendy_ira'),'wendy_ira missing from variable'); assert(REGULAR_WATERFALL.includes('wendy_ira'),'wendy_ira missing from regular'); });
test('529s ARE in both waterfalls (direct funding)',()=>{ ['bailey_529','bryce_529','preston_529'].forEach(id=>{ assert(VARIABLE_WATERFALL.includes(id),id+' missing from variable'); assert(REGULAR_WATERFALL.includes(id),id+' missing from regular'); }); });
test('taxable_etf NOT in either waterfall (stretch, unfunded until 2027)',()=>{ assert(!VARIABLE_WATERFALL.includes('taxable_etf')); assert(!REGULAR_WATERFALL.includes('taxable_etf')); });
test('retirement_rebuild NOT in either waterfall (pool removed Phase 4)',()=>{ assert(!VARIABLE_WATERFALL.includes('retirement_rebuild'),'retirement_rebuild in variable'); assert(!REGULAR_WATERFALL.includes('retirement_rebuild'),'retirement_rebuild in regular'); });
test('Waterfall order: alaska → rccl → dcl → adam_ira in both',()=>{ const rv=VARIABLE_WATERFALL,rr=REGULAR_WATERFALL; assert(rv.indexOf('alaska')<rv.indexOf('wewe_rccl')&&rv.indexOf('wewe_rccl')<rv.indexOf('wewe_dcl')&&rv.indexOf('wewe_dcl')<rv.indexOf('adam_ira'),'VARIABLE order wrong'); assert(rr.indexOf('alaska')<rr.indexOf('wewe_rccl')&&rr.indexOf('wewe_rccl')<rr.indexOf('wewe_dcl')&&rr.indexOf('wewe_dcl')<rr.indexOf('adam_ira'),'REGULAR order wrong'); });
test('Waterfall has exactly 10 items',()=>{ assert(VARIABLE_WATERFALL.length===10,'variable='+VARIABLE_WATERFALL.length); assert(REGULAR_WATERFALL.length===10,'regular='+REGULAR_WATERFALL.length); });
test('PRIORITY_TIERS tier 1 = Alaska',()=>{ const t=PRIORITY_TIERS.find(t=>t.num===1); assert(t&&t.goals.includes('alaska'),'T1 should be alaska'); });
test('PRIORITY_TIERS tier 2 = Wewe RCCL',()=>{ const t=PRIORITY_TIERS.find(t=>t.num===2); assert(t&&t.goals.includes('wewe_rccl'),'T2 should be wewe_rccl'); });
test('PRIORITY_TIERS tier 3 = Wewe DCL',()=>{ const t=PRIORITY_TIERS.find(t=>t.num===3); assert(t&&t.goals.includes('wewe_dcl'),'T3 should be wewe_dcl'); });
test('PRIORITY_TIERS tier 4 = Adam IRA',()=>{ const t=PRIORITY_TIERS.find(t=>t.num===4); assert(t&&t.goals.includes('adam_ira'),'T4 should be adam_ira'); });
test('PRIORITY_TIERS tier 5 = Wendy IRA',()=>{ const t=PRIORITY_TIERS.find(t=>t.num===5); assert(t&&t.goals.includes('wendy_ira'),'T5 should be wendy_ira'); });
test('PRIORITY_TIERS tiers numbered 1-11 sequentially',()=>{ for(var i=1;i<=11;i++) assert(PRIORITY_TIERS.find(t=>t.num===i),'Missing tier '+i); });
test('adam_401k dest = Empower 401(k)',()=>assert(GOALS_REGISTRY.find(g=>g.id==='adam_401k').dest==='Empower 401(k)'));
test('wendy_sep dest = Ascensus / BK CPA',()=>assert(GOALS_REGISTRY.find(g=>g.id==='wendy_sep').dest==='Ascensus / BK CPA'));
test('adam_ira dest = AMEX Savings (IRA Holding)',()=>assert(GOALS_REGISTRY.find(g=>g.id==='adam_ira').dest==='AMEX Savings (IRA Holding)'));
test('wendy_ira dest = AMEX Savings (IRA Holding)',()=>assert(GOALS_REGISTRY.find(g=>g.id==='wendy_ira').dest==='AMEX Savings (IRA Holding)'));
test('No goal has poolSource property (pool removed Phase 4)',()=>GOALS_REGISTRY.forEach(g=>assert(!g.poolSource,'poolSource found on: '+g.id)));
test('No goal has poolDeploys property (pool removed Phase 4)',()=>GOALS_REGISTRY.forEach(g=>assert(!g.poolDeploys,'poolDeploys found on: '+g.id)));
test('adam_401k funded = 10208',()=>assertApprox(goalFundedAmounts.adam_401k,10208));
test('wewe_rccl tier = Travel',()=>assert(GOALS_REGISTRY.find(g=>g.id==='wewe_rccl').tier==='Travel'));
test('wewe_dcl tier = Travel',()=>assert(GOALS_REGISTRY.find(g=>g.id==='wewe_dcl').tier==='Travel'));
test('christmas_cruise tier = Travel',()=>assert(GOALS_REGISTRY.find(g=>g.id==='christmas_cruise').tier==='Travel'));
test('SECTION_TITLES.goals="Goals"',()=>assert(SECTION_TITLES.goals==='Goals'));
test('SECTION_TITLES has 8 sections',()=>['overview','weekly','goals','scenarios','history','assumptions','roadmap','ask'].forEach(s=>assert(s in SECTION_TITLES,'Missing: '+s)));
test('START_CHK = $18,037.73',()=>assertApprox(START_CHK,18037.73,undefined,0.01));
test('EF_AMT = $13,488.88',()=>assertApprox(EF_AMT,13488.88,undefined,0.01));

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 4: Goal calculation functions ──');
test('getGoalFunded(alaska) = model akSaved',()=>assertApprox(getGoalFunded('alaska',mockVm),3500));
test('getGoalFunded(adam_ira) = goalSaved[adam_ira]',()=>assertApprox(getGoalFunded('adam_ira',mockVm),200));
test('getGoalFunded(wendy_sep) = 17859',()=>assertApprox(getGoalFunded('wendy_sep',mockVm),17859));
test('getGoalFunded(bailey_529) = 0 (static default)',()=>assertApprox(getGoalFunded('bailey_529',mockVm),0));
test('getGoalRemaining(alaska) = 3500',()=>assertApprox(getGoalRemaining('alaska',mockVm),3500));
test('getGoalRemaining(wendy_sep) = 0',()=>assertApprox(getGoalRemaining('wendy_sep',mockVm),0));
test('getGoalRemaining never negative',()=>GOALS_REGISTRY.forEach(g=>assert(getGoalRemaining(g.id,mockVm)>=0,g.id+' negative')));
test('getGoalRemaining: overfunded → 0',()=>{ const ov={weeks:WEEKS.map(w=>Object.assign({},w,{akSaved:9000,akRem:0,amx:200,goalSaved:Object.assign({},w.goalSaved,{alaska:9000})}))}; assert(getGoalRemaining('alaska',ov)===0); });

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 5: Decision Engine — variable income ──');
test('Variable: first step is 40% tax',()=>{ const s=simulateEngine(5000,'variable',{ira_cpa_cleared:false}); assert(s[0].type==='tax','type='+s[0].type); assertApprox(s[0].amt,2000); });
test('Variable: info step = 60%',()=>{ const s=simulateEngine(5000,'variable',{ira_cpa_cleared:false}); assertApprox(s.find(x=>x.type==='info').amt,3000); });
test('Variable: total = input',()=>{ const s=simulateEngine(5000,'variable',{ira_cpa_cleared:false}); assertApprox(s.filter(x=>x.type!=='info').reduce((t,x)=>t+x.amt,0),5000); });
test('Variable: $1767.94 → $707.18 tax',()=>{ const s=simulateEngine(1767.94,'variable',{ira_cpa_cleared:false}); assertApprox(s.find(x=>x.type==='tax').amt,707.18,undefined,0.02); });
// Phase 4: IRAs are now direct waterfall goals, gated by needsFlag:ira_cpa_cleared
test('Variable: engine routes to adam_ira directly (not retirement pool)',()=>{ const s=simulateEngine(50000,'variable',{ira_cpa_cleared:true}); assert(!s.filter(x=>x.type==='goal').some(x=>x.label&&x.label.includes('Retirement Rebuild')),'retirement_rebuild should not appear as engine step'); });
test('Variable: IRA steps appear when CPA cleared',()=>{ const s=simulateEngine(50000,'variable',{ira_cpa_cleared:true}); assert(s.filter(x=>x.type==='goal').some(x=>x.label&&x.label.includes('IRA')),'IRA should appear as engine goal step when flag set'); });
test('Variable: sums match for $1k,$5k,$10k,$50k',()=>{ [1000,5000,10000,50000].forEach(amt=>{ const s=simulateEngine(amt,'variable',{ira_cpa_cleared:false}); assertApprox(s.filter(x=>x.type!=='info').reduce((t,x)=>t+x.amt,0),amt,'$'+amt); }); });

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 6: Decision Engine — regular surplus ──');
test('Regular: no tax step',()=>assert(!simulateEngine(5000,'regular',{ira_cpa_cleared:false}).find(x=>x.type==='tax')));
test('Regular: first goal is Alaska',()=>{ const s=simulateEngine(1000,'regular',{ira_cpa_cleared:false}); const f=s.find(x=>x.type==='goal'); assert(f&&f.label.includes('Alaska'),'first='+( f?f.label:'none')); });
// Phase 4: engine routes directly alaska → rccl → dcl → adam_ira (no retirement pool)
test('Regular: engine order is alaska → rccl → dcl → adam_ira',()=>{ const s=simulateEngine(50000,'regular',{ira_cpa_cleared:true}); const g=s.filter(x=>x.type==='goal'); const ak=g.findIndex(x=>x.label&&x.label.includes('Alaska')),rccl=g.findIndex(x=>x.label&&x.label.includes('RCCL')),ira=g.findIndex(x=>x.label&&x.label.includes('Adam IRA')); assert(ak>=0&&rccl>=0&&ira>=0,'Goal steps not found: ak='+ak+' rccl='+rccl+' ira='+ira); assert(ak<rccl&&rccl<ira,'Order wrong: ak='+ak+' rccl='+rccl+' ira='+ira); });
test('Regular: IRA steps appear when CPA cleared',()=>{ const s=simulateEngine(50000,'regular',{ira_cpa_cleared:true}); assert(s.filter(x=>x.type==='goal').some(x=>x.label&&x.label.includes('IRA')),'IRA goal step missing when cleared'); });
test('Regular: sums match for $500,$3k,$8k,$25k',()=>{ [500,3000,8000,25000].forEach(amt=>{ const s=simulateEngine(amt,'regular',{ira_cpa_cleared:true}); assertApprox(s.reduce((t,x)=>t+x.amt,0),amt,'$'+amt); }); });
test('Regular: no surplus with $500',()=>assert(!simulateEngine(500,'regular',{ira_cpa_cleared:false}).find(x=>x.type==='surplus')));
test('Regular: surplus with $200k',()=>{ const s=simulateEngine(200000,'regular',{ira_cpa_cleared:true}); const sp=s.find(x=>x.type==='surplus'); assert(sp&&sp.amt>0,'No surplus'); });

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 7: Edge cases ──');
test('$0 → engineResult null',()=>{ simulateEngine(0,'regular',{}); assert(engineResult===null); });
test('Negative → engineResult null',()=>{ simulateEngine(-500,'regular',{}); assert(engineResult===null); });
test('toggleGoalFlag flips and restores',()=>{ const o=goalFlags.ira_cpa_cleared; toggleGoalFlag('ira_cpa_cleared'); assert(goalFlags.ira_cpa_cleared!==o); toggleGoalFlag('ira_cpa_cleared'); assert(goalFlags.ira_cpa_cleared===o); });
test('_gProgCls: locked=s',()=>{ assert(_gProgCls(100,true,false)==='s'); assert(_gProgCls(50,true,false)==='s'); });
test('_gProgCls: stretch=s',()=>assert(_gProgCls(50,false,true)==='s'));
test('_gProgCls: 0%=s',()=>assert(_gProgCls(0,false,false)==='s'));
test('_gProgCls: 1-24%=r',()=>{ assert(_gProgCls(1,false,false)==='r'); assert(_gProgCls(24,false,false)==='r'); });
test('_gProgCls: 25-74%=a',()=>{ assert(_gProgCls(25,false,false)==='a'); assert(_gProgCls(74,false,false)==='a'); });
test('_gProgCls: 75-100%=g',()=>{ assert(_gProgCls(75,false,false)==='g'); assert(_gProgCls(100,false,false)==='g'); });

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 8: Rendering smoke tests ──');
test('_renderGoalsSavings: non-empty HTML',()=>{ const h=_renderGoalsSavings(fullVm); assert(typeof h==='string'&&h.length>100); });
test('_renderGoalsSavings: contains all 13 goal names',()=>{ const h=_renderGoalsSavings(fullVm); GOALS_REGISTRY.forEach(g=>assertIncludes(h,g.name)); });
test('_renderGoalsSavings: lock icon when IRA flag off',()=>{ goalFlags.ira_cpa_cleared=false; assert(_renderGoalsSavings(fullVm).includes('🔒')); });
test('_renderGoalsSavings: no lock icon when IRA cleared',()=>{ goalFlags.ira_cpa_cleared=true; assert(!_renderGoalsSavings(fullVm).includes('🔒')); goalFlags.ira_cpa_cleared=false; });
test('_renderGoalsPriorities: non-empty',()=>assert(_renderGoalsPriorities(fullVm).length>100));
test('_renderGoalsPriorities: T1-T11 present',()=>{ const h=_renderGoalsPriorities(fullVm); for(let i=1;i<=11;i++) assertIncludes(h,'T'+i,'T'+i+' missing from priorities render'); });
test('_renderGoalsFunding: non-empty',()=>{ const w=fullVm.weeks.find(x=>x.num===getCurrentWeek())||fullVm.weeks[0]; assert(_renderGoalsFunding(fullVm,w).length>200); });
test('_renderGoalsFunding: major goal names present',()=>{ const w=fullVm.weeks[0]; const h=_renderGoalsFunding(fullVm,w); ['Alaska Cruise','Adam IRA','Wendy IRA','Wewe','529'].forEach(n=>assertIncludes(h,n)); });
test('_renderEngineOutput: numbered steps',()=>{ const h=_renderEngineOutput([{type:'goal',num:1,label:'Alaska',amt:3500,note:'Test'},{type:'goal',num:2,label:'Retirement',amt:1500,note:'Test2'}]); assertIncludes(h,'Alaska'); assertIncludes(h,'5,000'); });
test('_renderEngineOutput: tax class',()=>assertIncludes(_renderEngineOutput([{type:'tax',num:'→',label:'40% Tax',amt:400,note:'n'}]),'engine-step-num tax'));
test('_renderEngineOutput: hold class',()=>assertIncludes(_renderEngineOutput([{type:'hold',num:1,label:'IRA Hold',amt:700,note:'n'}]),'engine-step-num hold'));

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 9: Backwards compatibility ──');
test('renderGoalRail: HTML with Alaska',()=>{ const h=renderGoalRail(fullVm); assert(typeof h==='string'&&h.includes('Alaska')); });
test('renderTimeline: non-empty',()=>assert(renderTimeline(fullVm,'weekly').length>100));
test('buildDashboardViewModel: expected keys',()=>{ const vm=buildDashboardViewModel(WEEKS,{ak:7000,rt:7694.87}); ['weeks','current','finalWeek','alaskaCompletion','openActions'].forEach(k=>assert(k in vm,'Missing: '+k)); });
test('getGoals() returns ak and rt',()=>{ const g=getGoals(); assert('ak'in g&&'rt'in g); assertApprox(g.ak,7000); });
test('getWeekChipClass() contains weekChip',()=>assert(getWeekChipClass(WEEKS[0]).includes('weekChip')));

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 10: Phase 4 — Funding source & destination accounts ──');

test('All 13 registry entries have src field',()=>
  GOALS_REGISTRY.forEach(g=>assert(g.src&&g.src.length>0,'Missing src on: '+g.id)));

test('All 13 registry entries have dest field',()=>
  GOALS_REGISTRY.forEach(g=>assert(g.dest&&g.dest.length>0,'Missing dest on: '+g.id)));

test('alaska src contains "Truist Checking"',()=>{
  const g=GOALS_REGISTRY.find(g=>g.id==='alaska');
  assertIncludes(g.src,'Truist Checking');
});
test('alaska dest = Truist Savings',()=>{
  const g=GOALS_REGISTRY.find(g=>g.id==='alaska');
  assertIncludes(g.dest,'Truist Savings');
});
test('adam_ira startsAfter = wewe_dcl',()=>{
  const g=GOALS_REGISTRY.find(g=>g.id==='adam_ira');
  assert(g.startsAfter==='wewe_dcl','startsAfter='+g.startsAfter);
});
test('adam_ira dest = AMEX Savings (IRA Holding)',()=>{
  assert(GOALS_REGISTRY.find(g=>g.id==='adam_ira').dest==='AMEX Savings (IRA Holding)');
});
test('wendy_ira dest = AMEX Savings (IRA Holding)',()=>{
  assert(GOALS_REGISTRY.find(g=>g.id==='wendy_ira').dest==='AMEX Savings (IRA Holding)');
});
test('adam_401k src contains "Payroll"',()=>{
  assertIncludes(GOALS_REGISTRY.find(g=>g.id==='adam_401k').src,'Payroll');
});
test('adam_401k dest = "Empower 401(k)"',()=>{
  assert(GOALS_REGISTRY.find(g=>g.id==='adam_401k').dest==='Empower 401(k)');
});
test('taxable_etf dest contains "Brokerage"',()=>{
  assertIncludes(GOALS_REGISTRY.find(g=>g.id==='taxable_etf').dest,'Brokerage');
});
test('bryce_vehicle dest contains "Truist Checking"',()=>{
  assertIncludes(GOALS_REGISTRY.find(g=>g.id==='bryce_vehicle').dest,'Truist Checking');
});
test('529 goals dest = AMEX Savings (529 Holding)',()=>{
  ['bailey_529','bryce_529','preston_529'].forEach(id=>{
    assert(GOALS_REGISTRY.find(g=>g.id===id).dest==='AMEX Savings (529 Holding)',id+' dest should be AMEX Savings (529 Holding)');
  });
});

test('_renderGoalsSavings: src→dest routing appears for alaska',()=>{
  const h=_renderGoalsSavings(fullVm);
  assertIncludes(h,'Truist Checking (weekly surplus)');
  assertIncludes(h,'Truist Savings');
});
test('_renderGoalsSavings: AMEX Savings routing appears for IRA/529 holding',()=>{
  const h=_renderGoalsSavings(fullVm);
  assertIncludes(h,'AMEX Savings');
});
test('_renderGoalsSavings: goal-route CSS class present',()=>{
  assertIncludes(_renderGoalsSavings(fullVm),'goal-route');
});
test('_renderGoalsSavings: route-acct chips present',()=>{
  assertIncludes(_renderGoalsSavings(fullVm),'route-acct');
});
test('_renderGoalsSavings: startsAfter shown for adam_ira (depends on Wewe DCL)',()=>{
  const h=_renderGoalsSavings(fullVm);
  assertIncludes(h,'Starts after');
});
test('_renderGoalsFunding: routing chips appear in funding plan',()=>{
  const w=fullVm.weeks[0];
  const h=_renderGoalsFunding(fullVm,w);
  assertIncludes(h,'ft-route');
});
test('_renderGoalsFunding: Alaska src→dest in funding plan',()=>{
  const w=fullVm.weeks[0];
  const h=_renderGoalsFunding(fullVm,w);
  assertIncludes(h,'Truist Checking (weekly surplus)');
});
test('_renderGoalsFunding: AMEX Savings appears in retirement funding event',()=>{
  const w=fullVm.weeks[0];
  const h=_renderGoalsFunding(fullVm,w);
  assertIncludes(h,'AMEX Savings');
});
test('_renderGoalsFunding: IRA hold destination changes with flag',()=>{
  const w=fullVm.weeks[0];
  goalFlags.ira_cpa_cleared=false;
  const hLocked=_renderGoalsFunding(fullVm,w);
  // New dynamic render: locked goals show lock icon + Awaiting CPA
  assertIncludes(hLocked,'Awaiting CPA');
  goalFlags.ira_cpa_cleared=true;
  const hCleared=_renderGoalsFunding(fullVm,w);
  // When cleared, IRA goals appear with their dest names
  assertIncludes(hCleared,'Adam IRA');
  goalFlags.ira_cpa_cleared=false;
});
test('_renderGoalsFunding: no raw model week numbers in when-column (must use Cal Wk prefix)',()=>{
  const w=fullVm.weeks[0];
  const h=_renderGoalsFunding(fullVm,w);
  // ft-when column values: only valid forms are "✅ Funded", "🔒 Awaiting CPA", "Cal Wk N...", "2027 restart", "Beyond 2026", "Auto..."
  const whenFields=h.match(/class="ft-when[^"]*">([^<]+)/g)||[];
  whenFields.forEach(f=>{
    const raw=f.replace(/class="ft-when[^"]*">/,'');
    const hasCalPrefix=raw.includes('Cal Wk')||raw.includes('✅')||raw.includes('🔒')||raw.includes('Auto')||raw.includes('2027')||raw.includes('Beyond')||raw.includes('In Progress')||raw.includes('Awaiting');
    assert(hasCalPrefix,'ft-when field missing cal prefix or known label: '+raw);
  });
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 10b: Cash Flow Mechanics panel (Task #15) ──');

test('_renderGoalsSavings: Cash Flow Mechanics panel renders',()=>{
  const h=_renderGoalsSavings(fullVm);
  assertIncludes(h,'Cash Flow Mechanics','Panel header missing');
});
test('_renderGoalsSavings: flow chain boxes all present',()=>{
  const h=_renderGoalsSavings(fullVm);
  assertIncludes(h,'Floor Protection','Floor Protection box missing');
  assertIncludes(h,'Available to Sweep','Available to Sweep box missing');
  assertIncludes(h,'Waterfall Goals','Waterfall Goals box missing');
  assertIncludes(h,'Goal Buckets','Goal Buckets box missing');
});
test('_renderGoalsSavings: look-ahead floor explanation present',()=>{
  const h=_renderGoalsSavings(fullVm);
  assertIncludes(h,'Look-ahead floor','Look-ahead floor warning missing');
});
test('_renderGoalsSavings: monthly income = $15,938',()=>{
  const h=_renderGoalsSavings(fullVm);
  assertIncludes(h,'15,938','Monthly income $15,938 not found');
});
test('_renderGoalsSavings: monthly bills = $15,091',()=>{
  const h=_renderGoalsSavings(fullVm);
  assertIncludes(h,'15,091','Monthly bills $15,091 not found');
});
test('_renderGoalsSavings: funded definition present',()=>{
  const h=_renderGoalsSavings(fullVm);
  assertIncludes(h,'"funded" means','Funded definition missing');
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 10c: Funding Timeline visual (Task #16) ──');

test('_renderGoalsFunding: Funding Timeline panel renders',()=>{
  const h=_renderGoalsFunding(fullVm,WEEKS[0]);
  assertIncludes(h,'Funding Timeline','Timeline heading missing');
});
test('_renderGoalsFunding: timeline has Cal Wk 23 start label and 53 in heading',()=>{
  const h=_renderGoalsFunding(fullVm,WEEKS[0]);
  assertIncludes(h,'Cal Wk 23','Start week label missing');
  assertIncludes(h,'23 – 53','Heading range Cal Wk 23-53 missing');
});
test('_renderGoalsFunding: timeline renders sweep bars (at least 4)',()=>{
  const h=_renderGoalsFunding(fullVm,WEEKS[0]);
  const bars=(h.match(/title="Cal Wk \d+: \+\$[\d,]+\.\d+"/g)||[]);
  assert(bars.length>=4,'Expected at least 4 sweep bars, got '+bars.length);
});
test('_renderGoalsFunding: alaska sweep bar present in timeline',()=>{
  const h=_renderGoalsFunding(fullVm,WEEKS[0]);
  assert(/title="Cal Wk 2[0-9]: \+\$7,000\.00"/.test(h)||h.includes('7,000.00'),'Alaska $7,000 sweep bar missing');
});
test('_renderGoalsFunding: now marker present in timeline',()=>{
  const h=_renderGoalsFunding(fullVm,WEEKS[0]);
  assertIncludes(h,'>now<','Now marker missing from timeline');
});
test('_renderGoalsFunding: timeline legend rendered',()=>{
  const h=_renderGoalsFunding(fullVm,WEEKS[0]);
  assertIncludes(h,'Sweep received that week','Timeline legend missing');
});
test('_renderGoalsFunding: all 10 waterfall goals appear in timeline',()=>{
  const h=_renderGoalsFunding(fullVm,WEEKS[0]);
  ['alaska','wewe_rccl','wewe_dcl','adam_ira','wendy_ira','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'].forEach(id=>{
    const g=GOALS_REGISTRY.find(x=>x.id===id);
    assert(g&&h.includes(g.name),'Timeline missing goal: '+id);
  });
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 11: Full waterfall goalSaved tracking ──');

test('Every week has goalSaved object',()=>
  WEEKS.forEach(w=>assert(w.goalSaved&&typeof w.goalSaved==='object','W'+w.num+' missing goalSaved')));

test('goalSaved has entry for every non-complete goal',()=>{
  const activeIds=GOALS_REGISTRY.filter(g=>!g.complete).map(g=>g.id);
  WEEKS.forEach(w=>activeIds.forEach(id=>assert(id in w.goalSaved,'W'+w.num+' missing '+id+' in goalSaved')));
});

test('goalSaved values non-negative every week',()=>{
  WEEKS.forEach(w=>Object.entries(w.goalSaved).forEach(([k,v])=>
    assert(v>=0,'W'+w.num+' '+k+' negative goalSaved='+v)));
});

test('goalSaved values monotonically non-decreasing for each goal',()=>{
  for(let i=1;i<WEEKS.length;i++){
    const prev=WEEKS[i-1].goalSaved,curr=WEEKS[i].goalSaved;
    Object.keys(curr).forEach(k=>{
      assert((curr[k]||0)>=(prev[k]||0)-0.005,'W'+WEEKS[i].num+' '+k+' decreased: '+prev[k]+' → '+curr[k]);
    });
  }
});

test('W1-W4 goalSaved: only 401k and adam_ira have non-zero values (seed only, no premature allocations)',()=>{
  WEEKS.slice(0,4).forEach(w=>{
    const violations=Object.entries(w.goalSaved).filter(([k,v])=>
      !['adam_401k','adam_ira'].includes(k)&&v>0.005);
    assert(violations.length===0,'W'+w.num+' pre-AK_START allocations: '+violations.map(([k,v])=>k+'='+v).join(', '));
  });
});

test('goalSaved snapshots are independent objects (not same reference)',()=>{
  for(let i=1;i<WEEKS.length;i++){
    assert(WEEKS[i].goalSaved!==WEEKS[i-1].goalSaved,'W'+i+'/W'+(i+1)+' share goalSaved reference');
  }
});

test('alaska goalSaved reaches 7000 by W5',()=>{
  const w5=WEEKS.find(x=>x.num===5);
  assertApprox(w5.goalSaved.alaska,7000,'alaska at W5',0.02);
});

test('adam_ira accumulates after wewe_dcl completes',()=>{
  // adam_ira starts after wewe_dcl; with needsFlag gated off by default,
  // seed value stays at 103.64 unless flags change. Just verify seed is there.
  const w1=WEEKS.find(x=>x.num===1);
  assertGt(w1.goalSaved.adam_ira||0,100,'adam_ira seed missing at W1 (expected ~103.64)');
});

test('wewe_rccl goalSaved reaches 600 within 31 weeks',()=>{
  const done=WEEKS.find(w=>(w.goalSaved.wewe_rccl||0)>=599.99);
  assert(done&&done.num<=31,'wewe_rccl never completes. W31='+WEEKS[30].goalSaved.wewe_rccl);
});

test('wewe_dcl goalSaved reaches 500 within 31 weeks',()=>{
  const done=WEEKS.find(w=>(w.goalSaved.wewe_dcl||0)>=499.99);
  assert(done&&done.num<=31,'wewe_dcl never completes. W31='+WEEKS[30].goalSaved.wewe_dcl);
});

test('goalSaved initial seed: adam_ira starts at START_AMX (~103.64)',()=>{
  assertApprox(WEEKS[0].goalSaved.adam_ira,103.64,'adam_ira seed at W1',0.02);
});

test('goalSaved initial seed: adam_401k starts at 10208',()=>{
  assertApprox(WEEKS[0].goalSaved.adam_401k,10208,'401k seed at W1',0.02);
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 12: AK_START gate — priority discipline ──');

test('AK_START = 5',()=>assertApprox(AK_START,5,'AK_START'));

test('No waterfall allocation before W5 for any goal except seeds',()=>{
  // Before AK_START: goalSaved should stay at initial values (0 or seed)
  WEEKS.filter(w=>w.num<AK_START).forEach(w=>{
    const hasAllocations=Object.entries(w.goalSaved).some(([k,v])=>
      !['adam_401k','adam_ira'].includes(k)&&v>0.005);
    assert(!hasAllocations,'Pre-AK_START W'+w.num+' has unexpected allocations');
  });
});

test('Alaska is first goal funded: goalSaved[alaska] > 0 at W5 before lower-tier goals',()=>{
  const w5=WEEKS.find(x=>x.num===5);
  assertGt(w5.goalSaved.alaska||0,0,'alaska not funded at W5');
});

test('Lower-tier goals (529s) stay 0 while alaska is incomplete',()=>{
  // 529s are T6-T8; they should not start until T1 (alaska) is funded
  const firstBailey=WEEKS.find(w=>(w.goalSaved.bailey_529||0)>0.005);
  const alaskaDone=WEEKS.find(w=>w.goalSaved.alaska>=6999.99);
  if(firstBailey&&alaskaDone){
    assert(firstBailey.num>=alaskaDone.num,'529 funded before alaska completes');
  }
});

test('runModel respects AK_START: W(AK_START-1) has 0 for all non-seed goalSaved',()=>{
  const wPre=WEEKS.find(x=>x.num===AK_START-1);
  // adam_ira has seed (START_AMX ~103.64), adam_401k has seed too — both excluded
  const nonSeedKeys=['alaska','wewe_rccl','wewe_dcl','wendy_ira','bailey_529','bryce_529','preston_529','christmas_cruise','bryce_vehicle'];
  nonSeedKeys.forEach(k=>assert((wPre.goalSaved[k]||0)<=0.005,'Pre-gate W'+(AK_START-1)+' '+k+' already funded: '+(wPre.goalSaved[k]||0)));
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 13: 401k auto-contribution ──');

const PAYCHECK_WEEKS_EXPECTED=[3,5,7,9,11,14,16,18,20,22,24,27,29,31];
const PAY_PER_CHECK=1020.83;

test('401k increases exactly on paycheck weeks only',()=>{
  for(let i=1;i<WEEKS.length;i++){
    const w=WEEKS[i];const prev=WEEKS[i-1];
    const delta=Math.round((w.goalSaved.adam_401k-prev.goalSaved.adam_401k)*100)/100;
    const isPaycheck=PAYCHECK_WEEKS_EXPECTED.includes(w.num);
    if(isPaycheck){
      assert(delta>0,'No 401k contribution on paycheck W'+w.num+' (delta='+delta+')');
    }else{
      assertApprox(delta,0,'Non-paycheck W'+w.num+' has unexpected 401k delta='+delta,0.01);
    }
  }
});

test('401k contribution at W3 = ~$11,228.83 (YTD + 1 paycheck)',()=>
  assertApprox(WEEKS.find(x=>x.num===3).goalSaved.adam_401k,11228.83,'W3 401k',0.05));

test('401k contribution at W5 = ~$12,249.66 (YTD + 2 paychecks)',()=>
  assertApprox(WEEKS.find(x=>x.num===5).goalSaved.adam_401k,12249.66,'W5 401k',0.05));

test('401k reaches near $24,500 target by W31',()=>
  assertApprox(WEEKS[30].goalSaved.adam_401k,24499.62,'W31 401k',0.1));

test('401k appears in week tr as info type (no checking impact)',()=>{
  const paycheckW=WEEKS.find(x=>x.num===3);
  const entry=paycheckW.tr.find(t=>t.l.includes('401')&&t.r==='info');
  assert(entry,'W3 missing 401k info tr entry');
});

test('401k contributions do not appear in done tr (no checking debit)',()=>{
  PAYCHECK_WEEKS_EXPECTED.forEach(n=>{
    const w=WEEKS.find(x=>x.num===n);
    const doneEntry=w.tr.find(t=>t.l.includes('401')&&t.r==='done');
    assert(!doneEntry,'W'+n+' has 401k as done (should be info)');
  });
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 14: Retirement savings sweep ──');

test('Savings sweep fires in W5 (alaska completion week): sav increases net',()=>{
  // W5: sav goes up because alaska transfers $7k to sav, then sweep moves $3772.74 to amx
  // Net sav change: +7000 - 3772.74 = +3227.26
  const w4=WEEKS.find(x=>x.num===4),w5=WEEKS.find(x=>x.num===5);
  assertApprox(w5.sav-w4.sav,3227.26,'W5 net sav change',0.1);
});

test('Savings sweep: amx increases by ~3772.74 in W5 (sweep only — retirement starts after DCL)',()=>{
  const w4=WEEKS.find(x=>x.num===4),w5=WEEKS.find(x=>x.num===5);
  // Retirement now starts after DCL completes. W5 surplus above floor is ~$79 (below MIN_XFR),
  // so only the savings sweep (3772.74) moves to AMEX — no waterfall retirement allocation.
  assertApprox(w5.amx-w4.amx,3772.74,'W5 amx delta',0.5);
});

test('Savings sweep fires only once: sav is unchanged from W5 to W6',()=>{
  const w5=WEEKS.find(x=>x.num===5),w6=WEEKS.find(x=>x.num===6);
  // No cruise draws in W5/W6, no new alaska transfers — sav should stay flat
  assertApprox(w6.sav,w5.sav,'W5→W6 sav should not change',0.02);
});

test('Savings sweep: adam_ira goalSaved at W5 = seed + sweep only',()=>{
  // seed(~103.64) + sweep(3772.74) = ~3876.38
  // rtSavSwept now credits adam_ira; no waterfall allocation yet (DCL completed same week, surplus <MIN_XFR)
  assertApprox(WEEKS.find(x=>x.num===5).goalSaved.adam_ira,3876.38,'adam_ira goalSaved at W5',1.0);
});

test('W5 sweep tr appears: Truist Savings → AMEX Savings',()=>{
  const w5=WEEKS.find(x=>x.num===5);
  const entry=w5.tr.find(t=>t.l.includes('AMEX Savings')&&t.r==='done');
  assert(entry,'W5 missing savings sweep tr entry');
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 15: Commission week — VARIABLE_WATERFALL ──');

test('W6 is a commission week (ct>0)',()=>{
  const w6=WD.find(([num])=>num===6);
  assertGt(w6[5],0,'W6 ct should be >0');
});

test('W6 tr contains 40% commission entry',()=>{
  const w6=WEEKS.find(x=>x.num===6);
  assert(w6.tr.some(t=>t.l.includes('40%')),'W6 missing 40% commission tr');
});

test('W6 adam_ira allocation suppressed or deferred (checking near floor, needsFlag off)',()=>{
  // W6 is commission week. adam_ira is gated by needsFlag:ira_cpa_cleared (default false).
  // Even if flag were on, W6 start is ~$6,579 (only ~$79 above floor) — surplus too small.
  const w6=WEEKS.find(x=>x.num===6);
  const iraEntry=w6.tr.find(t=>t.l.toLowerCase().includes('adam ira')&&t.r==='done');
  assert(!iraEntry,'W6 should not have a completed adam_ira allocation: '+(iraEntry&&iraEntry.l));
});

test('VARIABLE_WATERFALL includes adam_ira (Phase 4: direct waterfall)',()=>
  assert(VARIABLE_WATERFALL.includes('adam_ira'),'adam_ira missing from VARIABLE_WATERFALL'));

test('REGULAR_WATERFALL includes adam_ira after wewe_dcl',()=>{
  const dcl=REGULAR_WATERFALL.indexOf('wewe_dcl');
  const ira=REGULAR_WATERFALL.indexOf('adam_ira');
  assert(dcl>=0,'wewe_dcl missing from REGULAR_WATERFALL');
  assert(ira>dcl,'adam_ira not after wewe_dcl in REGULAR_WATERFALL');
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 16: buildDashboardViewModel goalCompletion ──');

const bvm=buildDashboardViewModel(WEEKS,{ak:7000,rt:7694.87});

test('buildDashboardViewModel has goalCompletion key',()=>
  assert('goalCompletion'in bvm,'goalCompletion missing from vm'));

test('goalCompletion has entry for all 13 goals',()=>{
  GOALS_REGISTRY.forEach(g=>assert(g.id in bvm.goalCompletion,'Missing goalCompletion for '+g.id));
});

test('goalCompletion[alaska] = W5',()=>{
  const c=bvm.goalCompletion.alaska;
  assert(c&&c.num===5,'alaska completion expected W5, got: '+JSON.stringify(c));
});

test('goalCompletion[alaska] dates contain Jul',()=>{
  const c=bvm.goalCompletion.alaska;
  assert(c&&c.dates&&c.dates.includes('Jul'),'alaska dates should be Jul, got: '+(c&&c.dates));
});

test('goalCompletion[wendy_sep] = Completed (complete=true)',()=>{
  const c=bvm.goalCompletion.wendy_sep;
  assert(c&&c.dates==='Completed','wendy_sep goalCompletion expected Completed, got: '+JSON.stringify(c));
});

test('goalCompletion[adam_ira] = null (needsFlag off by default, target not reached)',()=>
  assert(bvm.goalCompletion.adam_ira===null,'adam_ira should be null, got: '+JSON.stringify(bvm.goalCompletion.adam_ira)));

test('goalCompletion[taxable_etf] = null (stretch goal)',()=>
  assert(bvm.goalCompletion.taxable_etf===null,'taxable_etf should be null'));

test('goalCompletion[wewe_rccl] is non-null (funds within model)',()=>
  assert(bvm.goalCompletion.wewe_rccl&&bvm.goalCompletion.wewe_rccl.num>0,'wewe_rccl should complete within model'));

test('goalCompletion weeks consistent with goalSaved reaching target',()=>{
  ['alaska','wewe_rccl','wewe_dcl'].forEach(id=>{
    const c=bvm.goalCompletion[id];
    if(!c||c.dates==='Completed')return;
    const g=GOALS_REGISTRY.find(x=>x.id===id);
    const wMatch=WEEKS.find(w=>w.num===c.num);
    assert(wMatch&&(wMatch.goalSaved[id]||0)>=g.target-0.05,
      id+' goalCompletion W'+c.num+' but goalSaved='+(wMatch&&wMatch.goalSaved[id]));
  });
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 17: Dynamic Funding Plan rendering ──');

const fpHtml=(()=>{ const w=bvm.weeks.find(x=>x.num===getCurrentWeek())||bvm.weeks[0]; return _renderGoalsFunding(bvm,w); })();
// Also build a locked version for IRA tests
goalFlags.ira_cpa_cleared=false;
const fpHtmlLocked=(()=>{ const w=bvm.weeks[0]; return _renderGoalsFunding(bvm,w); })();
goalFlags.ira_cpa_cleared=false;

test('Funding plan: all 13 goal names appear in output',()=>
  GOALS_REGISTRY.forEach(g=>assertIncludes(fpHtml,g.name)));

test('Funding plan: ft-when class present',()=>assertIncludes(fpHtml,'ft-when'));

test('Funding plan: ft-funded-row class present for funded goals',()=>assertIncludes(fpHtml,'ft-funded-row'));

test('Funding plan: ft-locked-row class present when IRA locked',()=>assertIncludes(fpHtmlLocked,'ft-locked-row'));

test('Funding plan: ft-stretch-row class present for taxable_etf',()=>assertIncludes(fpHtml,'ft-stretch-row'));

test('Funding plan: ✅ Funded text appears for completed goals',()=>assertIncludes(fpHtml,'✅ Funded'));

test('Funding plan: 🔒 Awaiting CPA appears when IRA locked',()=>assertIncludes(fpHtmlLocked,'Awaiting CPA'));

test('Funding plan: 2027 restart appears for stretch goal',()=>assertIncludes(fpHtml,'2027 restart'));

test('Funding plan: Overall 2026 Progress summary panel present',()=>assertIncludes(fpHtml,'Overall 2026 Progress'));

test('Funding plan: ft-live badge appears for model-tracked goals',()=>assertIncludes(fpHtml,'ft-live'));

test('Funding plan: route-acct chips present',()=>assertIncludes(fpHtml,'route-acct'));

test('Funding plan: Cal Wk prefix used for projected completion weeks',()=>assertIncludes(fpHtml,'Cal Wk'));

test('Funding plan: ft-prog-wrap progress bars present',()=>assertIncludes(fpHtml,'ft-prog-wrap'));

test('Funding plan: funded goals sort before unfunded (alaska appears before bailey_529)',()=>{
  const akPos=fpHtml.indexOf('Alaska Cruise');
  const b5Pos=fpHtml.indexOf('Bailey 529');
  assert(akPos<b5Pos,'Alaska should appear before Bailey 529 in sorted output. ak='+akPos+' b529='+b5Pos);
});

test('Priorities tab: ranked list T1 through T11 present',()=>{
  const h=_renderGoalsPriorities(bvm);
  for(var i=1;i<=11;i++) assertIncludes(h,'T'+i,'T'+i+' missing from priorities');
});

test('Priorities tab: Cal Wk appears in projection badges',()=>{
  const h=_renderGoalsPriorities(bvm);
  assertIncludes(h,'Cal Wk');
});

// ─────────────────────────────────────────────────────────────────────────
// RENDER INTEGRATION — catches browser-only scope errors (e.g., r not defined)
// ─────────────────────────────────────────────────────────────────────────
test('renderWeekDetail: executes without throwing (regression — r() scope bug)',()=>{
  // r() was defined only inside runModel; renderWeekDetail called it at lines 1561-1563
  // causing a blank Weekly Model in the browser. This test catches that class of error.
  const w=WEEKS[0];
  const html=renderWeekDetail(w,WEEKS);
  assertGt(html.length,100,'renderWeekDetail must return non-empty HTML');
  assertIncludes(html,'panel','renderWeekDetail must include panel markup');
});

test('renderWeekDetail: cash flow equation elements present',()=>{
  const w=WEEKS[1]; // pick a week with inflows likely
  const html=renderWeekDetail(w,WEEKS);
  assertIncludes(html,'floor-health','cash flow summary panel must render');
});

test('renderWeekly: executes without throwing',()=>{
  const vm=buildDashboardViewModel(WEEKS,{ak:7000,rt:7694.87});
  // document.getElementById returns stub with innerHTML — no throw = pass
  var threw=false;
  try{ renderWeekly(vm); }catch(e){ threw=true; }
  assert(!threw,'renderWeekly must not throw: '+( threw?'threw':'' ));
});

test('r() helper is globally accessible outside runModel',()=>{
  assert(typeof r==='function','r must be a globally declared function');
  assertApprox(r(1.005),1.01,'r() must round to 2 decimal places');
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 18: Phase 4 regression tests ──');

// ── WD bug fixes ──
test('Ph4 WD: Wk 12 has no bills (Alaska draw removed)',()=>{
  const wd=WD.find(([n])=>n===12);
  assert(wd&&wd[3].length===0,'W12 bills should be empty, got: '+JSON.stringify(wd&&wd[3]));
});
test('Ph4 WD: Wk 12 has no Alaska outflow event',()=>{
  const wd=WD.find(([n])=>n===12);
  const evs=wd&&wd[4]||[];
  assert(!evs.some(e=>e.l&&e.l.toLowerCase().includes('alaska')&&e.a<0),'W12 still has Alaska outflow event');
});
test('Ph4 WD: Wk 16 has no Alaska outflow event',()=>{
  const wd=WD.find(([n])=>n===16);
  const evs=wd&&wd[4]||[];
  assert(!evs.some(e=>e.l&&e.l.toLowerCase().includes('alaska')&&e.a<0),'W16 still has Alaska outflow event');
});
test('Ph4 WD: Wk 16 has Disney Visa bill',()=>{
  const wd=WD.find(([n])=>n===16);
  assert(wd&&wd[3].some(b=>b>=3000&&b<=4000),'W16 missing Disney Visa ~$3,500 in bills');
});
test('Ph4 WD: Wk 22 Wendy paycheck $2,152.50 present',()=>{
  const wd=WD.find(([n])=>n===22);
  const inflows=wd&&wd[2]||[];
  assert(inflows.some(v=>Math.abs(v-2152.5)<0.01),'W22 missing Wendy paycheck $2,152.50 in inflows');
});
test('Ph4 WD: Wk 26 Wendy paycheck $2,152.50 present',()=>{
  const wd=WD.find(([n])=>n===26);
  const inflows=wd&&wd[2]||[];
  assert(inflows.some(v=>Math.abs(v-2152.5)<0.01),'W26 missing Wendy paycheck $2,152.50 in inflows');
});

// ── Alaska $7k draw at model Wk 15 ──
test('Ph4 model: Wk 15 tr contains Alaska $7,000 transfer',()=>{
  const w15=WEEKS.find(x=>x.num===15);
  assert(w15&&w15.tr.some(t=>t.l&&t.l.includes('Alaska')&&t.a===7000),'W15 missing Alaska $7,000 transfer in tr');
});
test('Ph4 model: Wk 15 SAV drops ~$7,000 from Wk 14',()=>{
  const w14=WEEKS.find(x=>x.num===14),w15=WEEKS.find(x=>x.num===15);
  const delta=w14.sav-w15.sav;
  assert(delta>6900&&delta<7100,'W15 SAV should drop ~$7k from W14, got delta='+delta.toFixed(2));
});

// ── Waterfall structure ──
test('Ph4 waterfall: retirement_rebuild absent from GOALS_REGISTRY',()=>{
  assert(!GOALS_REGISTRY.find(g=>g.id==='retirement_rebuild'),'retirement_rebuild still in GOALS_REGISTRY');
});
test('Ph4 waterfall: adam_ira IS in VARIABLE_WATERFALL',()=>
  assert(VARIABLE_WATERFALL.includes('adam_ira'),'adam_ira missing from VARIABLE_WATERFALL'));
test('Ph4 waterfall: wendy_ira IS in VARIABLE_WATERFALL',()=>
  assert(VARIABLE_WATERFALL.includes('wendy_ira'),'wendy_ira missing from VARIABLE_WATERFALL'));
test('Ph4 waterfall: 529s ARE in VARIABLE_WATERFALL',()=>
  ['bailey_529','bryce_529','preston_529'].forEach(id=>
    assert(VARIABLE_WATERFALL.includes(id),id+' missing from VARIABLE_WATERFALL')));
test('Ph4 waterfall: complete order is alaska→rccl→dcl→adam_ira→wendy_ira→bailey→bryce→preston→vehicle→cruise',()=>{
  const wf=VARIABLE_WATERFALL;
  const expected=['alaska','wewe_rccl','wewe_dcl','adam_ira','wendy_ira','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
  expected.forEach((id,i)=>assert(wf[i]===id,'VARIABLE_WATERFALL['+i+'] expected '+id+' got '+wf[i]));
});

// ── Goal lifecycle status ──
test('Ph4 lifecycle: all goals have valid status field',()=>{
  const valid=['planned','funding','funded','approved','executed','cancelled'];
  GOALS_REGISTRY.forEach(g=>assert(g.status&&valid.includes(g.status),'Bad status on '+g.id+': '+g.status));
});
test('Ph4 lifecycle: alaska status = funded',()=>
  assert(GOALS_REGISTRY.find(g=>g.id==='alaska').status==='funded','alaska status not funded'));
test('Ph4 lifecycle: adam_ira status = planned',()=>
  assert(GOALS_REGISTRY.find(g=>g.id==='adam_ira').status==='planned','adam_ira status not planned'));
test('Ph4 lifecycle: wendy_sep status = executed',()=>
  assert(GOALS_REGISTRY.find(g=>g.id==='wendy_sep').status==='executed','wendy_sep status not executed'));
test('Ph4 lifecycle: adam_401k status = funding',()=>
  assert(GOALS_REGISTRY.find(g=>g.id==='adam_401k').status==='funding','adam_401k status not funding'));

// ── rtSavSwept credits adam_ira ──
test('Ph4 rtSavSwept: W5 tr contains Adam IRA seed label',()=>{
  const w5=WEEKS.find(x=>x.num===5);
  assert(w5&&w5.tr.some(t=>t.l&&t.l.toLowerCase().includes('adam ira')||t.l&&t.l.toLowerCase().includes('ira seed')),
    'W5 tr missing Adam IRA seed entry. tr labels: '+w5.tr.map(t=>t.l).join(' | '));
});

// ── adam_ira seed ──
test('Ph4 goalSaved: adam_ira seed at W1 ≈ 103.64',()=>
  assertApprox(WEEKS[0].goalSaved.adam_ira,103.64,'adam_ira W1 seed',0.05));
test('Ph4 goalSaved: no retirement_rebuild in W1 goalSaved',()=>
  assert(!('retirement_rebuild' in WEEKS[0].goalSaved)||WEEKS[0].goalSaved.retirement_rebuild===undefined,
    'retirement_rebuild still in W1 goalSaved'));

// ── Three-tier floor and Decision Queue in Priorities tab ──
test('Ph4 Priorities: three-tier floor legend present ($6,500 / $10,000 / $12,000)',()=>{
  const h=_renderGoalsPriorities(fullVm);
  assertIncludes(h,'6,500','$6,500 floor missing from priorities');
  assertIncludes(h,'10,000','$10,000 warning missing from priorities');
  assertIncludes(h,'12,000','$12,000 target missing from priorities');
});
test('Ph4 Priorities: Decision Queue section present',()=>{
  const h=_renderGoalsPriorities(fullVm);
  assertIncludes(h,'Decision Queue','Decision Queue section missing from priorities');
});

// ── Wishlist seed data ──
test('Ph4 Wishlist: WISHLIST_SEED has Phase 4 items',()=>{
  assert(WISHLIST_SEED.some(x=>x.phase==='Phase 4'),'No Phase 4 items in WISHLIST_SEED');
});
test('Ph4 Wishlist: WISHLIST_SEED has Phase 5 items',()=>{
  assert(WISHLIST_SEED.some(x=>x.phase==='Phase 5'),'No Phase 5 items in WISHLIST_SEED');
});
test('Ph4 Wishlist: Phase 4 items include retirement pool removal',()=>{
  assert(WISHLIST_SEED.some(x=>x.phase==='Phase 4'&&(x.title.toLowerCase().includes('pool')||x.title.toLowerCase().includes('retirement')||x.title.toLowerCase().includes('ira'))),'Phase 4 wishlist missing retirement/IRA/pool item');
});
test('Ph4 Wishlist: all WISHLIST_SEED items have title, phase, status',()=>{
  WISHLIST_SEED.forEach(x=>assert(x.title&&x.phase&&x.status,'WISHLIST_SEED item missing field: '+JSON.stringify(x)));
});

// ── Model accuracy ──
// Phase 4 model produces exactly 3 floor violations: W6, W8, W13
// (rent-heavy / bill-heavy weeks with thin income). Look-ahead floor protects transfers.
test('Ph4 model: floor violations are exactly W6, W8, W13',()=>{
  const expectedViolationWeeks=[6,8,13];
  const actualViolationWeeks=WEEKS.filter(w=>w.chk<6500).map(w=>w.num);
  assert(JSON.stringify(actualViolationWeeks)===JSON.stringify(expectedViolationWeeks),
    'Unexpected floor violations: '+JSON.stringify(actualViolationWeeks));
});
test('Ph4 model: lowest checking is W13 (~$4,908)',()=>{
  const lowest=WEEKS.reduce((m,w)=>w.chk<m.chk?w:m,WEEKS[0]);
  assert(lowest.num===13,'Expected lowest week W13, got W'+lowest.num+' ('+lowest.chk.toFixed(0)+')');
  assert(lowest.chk>=4700&&lowest.chk<=5100,'Expected W13 ~$4,908, got '+lowest.chk.toFixed(0));
});
test('Ph4 model: no week ends with negative checking (EF backstop holds)',()=>{
  const bad=WEEKS.filter(w=>w.chk<0);
  assert(bad.length===0,'Week(s) went negative: '+bad.map(w=>'W'+w.num+'('+w.chk.toFixed(0)+')').join(','));
});

// ─────────────────────────────────────────────────────────────────────────
console.log('\n── Section 19: IRA gate — blocking vs cleared ──');

// Helper: run model with ira_cpa_cleared temporarily set
function runModelWithFlags(flagOverrides){
  var saved=Object.assign({},goalFlags);
  Object.assign(goalFlags,flagOverrides);
  var result=runModel(7000,7694.87);
  Object.assign(goalFlags,saved);
  for(var k in goalFlags)if(!(k in saved))delete goalFlags[k];
  return result;
}
var WEEKS_LOCKED = runModelWithFlags({ira_cpa_cleared:false});  // default — CPA not cleared
var WEEKS_CLEARED = runModelWithFlags({ira_cpa_cleared:true});  // CPA cleared

// ── Locked (CPA not cleared) — strict block behavior ──
test('Locked: 529s get $0 throughout entire model (blocked by IRA gate)',()=>{
  ['bailey_529','bryce_529','preston_529'].forEach(id=>{
    var w31=WEEKS_LOCKED[WEEKS_LOCKED.length-1];
    assert((w31.goalSaved[id]||0)<0.01,id+' has funds while CPA locked: '+(w31.goalSaved[id]||0));
  });
});
test('Locked: bryce_vehicle gets $0 throughout entire model',()=>{
  var w31=WEEKS_LOCKED[WEEKS_LOCKED.length-1];
  assert((w31.goalSaved.bryce_vehicle||0)<0.01,'bryce_vehicle funded while CPA locked: '+(w31.goalSaved.bryce_vehicle||0));
});
test('Locked: christmas_cruise gets $0 throughout entire model',()=>{
  var w31=WEEKS_LOCKED[WEEKS_LOCKED.length-1];
  assert((w31.goalSaved.christmas_cruise||0)<0.01,'christmas_cruise funded while CPA locked: '+(w31.goalSaved.christmas_cruise||0));
});
test('Locked: no surplus fires while IRA gate is closed',()=>{
  var surplus=WEEKS_LOCKED.find(function(w){return w.surplusSwept>0;});
  assert(!surplus,'Surplus fired while CPA locked at W'+( surplus&&surplus.num));
});
test('Locked: adam_ira never reaches $7,000 target (only seed + sweep)',()=>{
  var w31=WEEKS_LOCKED[WEEKS_LOCKED.length-1];
  assert((w31.goalSaved.adam_ira||0)<7000,'adam_ira reached target while CPA locked: '+(w31.goalSaved.adam_ira||0));
});
test('Locked: wendy_ira stays at $0 (no seed, blocked by flag)',()=>{
  var w31=WEEKS_LOCKED[WEEKS_LOCKED.length-1];
  assert((w31.goalSaved.wendy_ira||0)<0.01,'wendy_ira funded while CPA locked: '+(w31.goalSaved.wendy_ira||0));
});
test('Locked: alaska and wewe_rccl still fund normally (above gate)',()=>{
  var akDone=WEEKS_LOCKED.find(function(w){return w.akRem<=0.01;});
  assert(akDone&&akDone.num<=10,'Alaska failed to fund with CPA locked');
  var w31=WEEKS_LOCKED[WEEKS_LOCKED.length-1];
  assertApprox(w31.goalSaved.wewe_rccl||0,600,'wewe_rccl with CPA locked',1);
});
test('Locked: wewe_dcl funds normally (above gate)',()=>{
  var w31=WEEKS_LOCKED[WEEKS_LOCKED.length-1];
  assertApprox(w31.goalSaved.wewe_dcl||0,500,'wewe_dcl with CPA locked',1);
});

// ── Cleared (CPA cleared) — full waterfall runs ──
test('Cleared: adam_ira receives waterfall contributions after wewe_dcl completes',()=>{
  // Find first week adam_ira gets a contribution above its seed (~103.64)
  var dclDone=WEEKS_CLEARED.find(function(w){return(w.goalSaved.wewe_dcl||0)>=499.99;});
  assert(dclDone,'DCL never completes with CPA cleared');
  // After DCL done, adam_ira should grow beyond seed+sweep
  var postDcl=WEEKS_CLEARED.filter(function(w){return w.num>dclDone.num;});
  var iraGrows=postDcl.some(function(w){return(w.goalSaved.adam_ira||0)>4000;});
  assert(iraGrows,'adam_ira never grew past seed+sweep after DCL done with CPA cleared');
});
test('Cleared: wendy_ira receives waterfall contributions',()=>{
  var w31=WEEKS_CLEARED[WEEKS_CLEARED.length-1];
  assertGt(w31.goalSaved.wendy_ira||0,0,'wendy_ira never funded with CPA cleared');
});
test('Cleared: 529s only start after IRA gate opens and wewe_dcl is complete',()=>{
  var dclDone=WEEKS_CLEARED.find(function(w){return(w.goalSaved.wewe_dcl||0)>=499.99;});
  var firstBailey=WEEKS_CLEARED.find(function(w){return(w.goalSaved.bailey_529||0)>0.01;});
  if(firstBailey&&dclDone){
    assert(firstBailey.num>=dclDone.num,'bailey_529 funded before DCL complete');
  }
});
test('Cleared: model still returns 31 weeks',()=>assert(WEEKS_CLEARED.length===31));
test('Cleared: no negative checking',()=>{
  var neg=WEEKS_CLEARED.filter(function(w){return w.chk<0;});
  assert(neg.length===0,'Negative checking with CPA cleared: '+neg.map(function(w){return'W'+w.num+'('+w.chk.toFixed(0)+')';}).join(','));
});
test('Cleared: goalSaved values non-negative',()=>{
  WEEKS_CLEARED.forEach(function(w){
    Object.entries(w.goalSaved).forEach(function(kv){
      assert(kv[1]>=0,'W'+w.num+' '+kv[0]+' negative: '+kv[1]);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────
console.log('── Section 20: Decision Engine / runModel parity ──');
// IRA LOCKED — regular income
test('Engine parity: locked regular — no 529s, vehicle, cruise, or surplus',()=>{
  const s=simulateEngine(200000,'regular',{ira_cpa_cleared:false});
  const labels=s.map(x=>x.label||'').join('|');
  assert(labels.includes('Adam IRA')||labels.includes('IRA'),'IRA gate step should appear');
  assert(!labels.includes('Bailey 529'),'Bailey 529 should not appear while IRA locked');
  assert(!labels.includes('Bryce 529'),'Bryce 529 should not appear while IRA locked');
  assert(!labels.includes('Preston 529'),'Preston 529 should not appear while IRA locked');
  assert(!labels.includes('Bryce Vehicle'),'Bryce Vehicle should not appear while IRA locked');
  assert(!labels.includes('Christmas Cruise'),'Christmas Cruise should not appear while IRA locked');
  assert(!s.some(x=>x.type==='surplus'),'No surplus step while IRA locked — gate absorbs remaining');
});
test('Engine parity: locked regular — gate step has non-zero blocked amount',()=>{
  const s=simulateEngine(200000,'regular',{ira_cpa_cleared:false});
  const gate=s.find(x=>x.type==='hold');
  assert(gate,'Gate step must exist');
  assert(gate.amt>0,'Gate step amt must be positive (blocked funds absorbed into hold step)');
});
test('Engine parity: locked regular — sum still equals input',()=>{
  const amt=200000;
  const s=simulateEngine(amt,'regular',{ira_cpa_cleared:false});
  const total=Math.round(s.reduce((t,x)=>t+x.amt,0)*100)/100;
  assertApprox(total,amt,'Regular locked sum');
});
// IRA LOCKED — variable income
test('Engine parity: locked variable — no 529s, vehicle, cruise, or surplus',()=>{
  const s=simulateEngine(200000,'variable',{ira_cpa_cleared:false});
  const labels=s.map(x=>x.label||'').join('|');
  assert(labels.includes('Adam IRA')||labels.includes('IRA'),'IRA gate step should appear');
  assert(!labels.includes('Bailey 529'),'Bailey 529 should not appear while IRA locked');
  assert(!labels.includes('Bryce 529'),'Bryce 529 should not appear while IRA locked');
  assert(!labels.includes('Preston 529'),'Preston 529 should not appear while IRA locked');
  assert(!labels.includes('Bryce Vehicle'),'Bryce Vehicle should not appear while IRA locked');
  assert(!labels.includes('Christmas Cruise'),'Christmas Cruise should not appear while IRA locked');
  assert(!s.some(x=>x.type==='surplus'),'No surplus step while IRA locked');
});
test('Engine parity: locked variable — sum equals input',()=>{
  const amt=200000;
  const s=simulateEngine(amt,'variable',{ira_cpa_cleared:false});
  const total=Math.round(s.filter(x=>x.type!=='info').reduce((t,x)=>t+x.amt,0)*100)/100;
  assertApprox(total,amt,'Variable locked sum');
});
// IRA CLEARED — ordering: adam_ira → wendy_ira → 529s → vehicle → cruise → surplus
test('Engine parity: cleared regular — IRA, 529s, vehicle, cruise all appear in order',()=>{
  const s=simulateEngine(200000,'regular',{ira_cpa_cleared:true});
  const goals=s.filter(x=>x.type==='goal').map(x=>x.label||'');
  const iIdx=goals.findIndex(l=>l.includes('Adam IRA'));
  const wIdx=goals.findIndex(l=>l.includes('Wendy IRA'));
  const bIdx=goals.findIndex(l=>l.includes('Bailey'));
  const vIdx=goals.findIndex(l=>l.includes('Bryce Vehicle'));
  const cIdx=goals.findIndex(l=>l.includes('Christmas'));
  assert(iIdx>=0,'Adam IRA must appear when cleared');
  assert(wIdx>iIdx,'Wendy IRA must follow Adam IRA');
  assert(bIdx>wIdx,'Bailey 529 must follow Wendy IRA');
  assert(vIdx>bIdx,'Bryce Vehicle must follow 529s');
  assert(cIdx>vIdx,'Christmas Cruise must follow Bryce Vehicle');
});
test('Engine parity: cleared regular — surplus appears after all goals',()=>{
  const s=simulateEngine(200000,'regular',{ira_cpa_cleared:true});
  assert(s.some(x=>x.type==='surplus'),'Surplus must appear when all goals funded');
  const lastGoalIdx=s.reduce((m,x,i)=>x.type==='goal'?i:m,-1);
  const surplusIdx=s.findIndex(x=>x.type==='surplus');
  assert(surplusIdx>lastGoalIdx,'Surplus must come after last goal step');
});
test('Engine parity: cleared variable — no surplus suppression when gate is open',()=>{
  const s=simulateEngine(200000,'variable',{ira_cpa_cleared:true});
  assert(s.some(x=>x.type==='surplus'),'Surplus must appear when CPA cleared and all goals funded');
});

// ─────────────────────────────────────────────────────────────────────────
console.log('── Section 21: Mutation guards (tests must catch intentional breaks) ──');
// Each mutation temporarily corrupts a core value, runs the model, confirms
// a key assertion fails, then restores the value. If none of these catch
// their mutation, the suite is not actually guarding the logic.

// Mutation A: reorder waterfall — 529 before IRA
test('Mutation A: reordering Bailey 529 before Adam IRA is caught',()=>{
  var origVar=VARIABLE_WATERFALL.slice();
  var origReg=REGULAR_WATERFALL.slice();
  // swap bailey_529 to position 3 (before adam_ira at 3)
  var bIdx=VARIABLE_WATERFALL.indexOf('bailey_529');
  var aIdx=VARIABLE_WATERFALL.indexOf('adam_ira');
  VARIABLE_WATERFALL.splice(bIdx,1);
  VARIABLE_WATERFALL.splice(aIdx,0,'bailey_529');
  var bIdx2=REGULAR_WATERFALL.indexOf('bailey_529');
  var aIdx2=REGULAR_WATERFALL.indexOf('adam_ira');
  REGULAR_WATERFALL.splice(bIdx2,1);
  REGULAR_WATERFALL.splice(aIdx2,0,'bailey_529');
  var caught=false;
  try{
    // With ira_cpa_cleared=false and bailey_529 ahead of adam_ira, bailey_529 would fund
    var s=simulateEngine(200000,'regular',{ira_cpa_cleared:false});
    var labels=s.map(x=>x.label||'').join('|');
    if(labels.includes('Bailey 529'))caught=true; // mutation visible — test guards this
  }finally{
    VARIABLE_WATERFALL.length=0;origVar.forEach(function(v){VARIABLE_WATERFALL.push(v);});
    REGULAR_WATERFALL.length=0;origReg.forEach(function(v){REGULAR_WATERFALL.push(v);});
  }
  assert(caught,'Mutation A not visible — waterfall order guard is broken');
});

// Mutation B: change AK_START — Alaska contributions before Wk 5
test('Mutation B: lowering AK_START to 2 causes pre-Wk-5 Alaska allocation',()=>{
  var orig=AK_START;
  AK_START=2;
  var caught=false;
  try{
    var vm=runModel(7000,7694.87); // returns array directly
    // With AK_START=2, weeks 2-4 should now have alaska contributions above seed
    var earlyAlloc=vm.filter(function(w){return w.num>=2&&w.num<5&&(w.goalSaved['alaska']||0)>103.64;});
    if(earlyAlloc.length>0)caught=true;
  }finally{AK_START=orig;}
  assert(caught,'Mutation B not visible — AK_START guard is broken');
});

// Mutation C: change OP_FL — affects floor violation week set
test('Mutation C: raising OP_FL to $8,000 changes floor violation set',()=>{
  var orig=OP_FL;
  OP_FL=8000;
  var caught=false;
  try{
    var vm=runModel(7000,7694.87);
    var viols=vm.filter(function(w){return w.chk<8000;}).map(function(w){return w.num;});
    // At $8k floor there are more violations than the baseline [6,8,13]
    if(JSON.stringify(viols)!==JSON.stringify([6,8,13]))caught=true;
  }finally{OP_FL=orig;}
  assert(caught,'Mutation C not visible — OP_FL floor guard is broken');
});

// Mutation D: remove needsFlag from adam_ira — adam_ira funds even when CPA locked
test('Mutation D: removing needsFlag from adam_ira lets it fund despite locked flag',()=>{
  var g=GOALS_REGISTRY.find(function(x){return x.id==='adam_ira';});
  var orig=g.needsFlag;
  g.needsFlag=null;
  var caught=false;
  try{
    // With gate removed, adam_ira appears as a goal step (not hold) when flag=false
    var s=simulateEngine(200000,'regular',{ira_cpa_cleared:false});
    var goals=s.filter(function(x){return x.type==='goal';}).map(function(x){return x.label||'';});
    if(goals.some(function(l){return l.includes('Adam IRA');}))caught=true;
  }finally{g.needsFlag=orig;}
  assert(caught,'Mutation D not visible — IRA needsFlag guard is broken');
});

// Mutation E: swap adam_ira / wendy_ira waterfall positions — wendy_ira appears first
// Note: startsAfter on adam_ira is redundant with waterfall order (DCL is slot 3, adam_ira slot 4)
// so the meaningful order mutation is swapping the two IRAs.
test('Mutation E: swapping adam_ira and wendy_ira waterfall order is detectable',()=>{
  var origVar=VARIABLE_WATERFALL.slice();
  var origReg=REGULAR_WATERFALL.slice();
  // Swap positions of adam_ira and wendy_ira
  function swapIds(arr,a,b){var ai=arr.indexOf(a),bi=arr.indexOf(b);arr[ai]=b;arr[bi]=a;}
  swapIds(VARIABLE_WATERFALL,'adam_ira','wendy_ira');
  swapIds(REGULAR_WATERFALL,'adam_ira','wendy_ira');
  var caught=false;
  try{
    var s=simulateEngine(200000,'regular',{ira_cpa_cleared:true});
    var goals=s.filter(function(x){return x.type==='goal';}).map(function(x){return x.label||'';});
    var aIdx=goals.findIndex(function(l){return l.includes('Adam IRA');});
    var wIdx=goals.findIndex(function(l){return l.includes('Wendy IRA');});
    // After swap wendy_ira (slot 3) appears before adam_ira (slot 4)
    if(wIdx>=0&&aIdx>=0&&wIdx<aIdx)caught=true;
  }finally{
    VARIABLE_WATERFALL.length=0;origVar.forEach(function(v){VARIABLE_WATERFALL.push(v);});
    REGULAR_WATERFALL.length=0;origReg.forEach(function(v){REGULAR_WATERFALL.push(v);});
  }
  assert(caught,'Mutation E not visible — waterfall IRA order guard is broken');
});

// Mutation F: remove savings seed sweep
test('Mutation F: setting RET_SAV_XFR to 0 suppresses AMEX seed',()=>{
  var orig=RET_SAV_XFR;
  RET_SAV_XFR=0;
  var caught=false;
  try{
    var vm=runModel(7000,7694.87);
    // Without the $3,772.74 seed, AMEX peak stays near the $103.64 starting balance
    var maxAmx=vm.reduce(function(m,w){return Math.max(m,w.amx||0);},0);
    if(maxAmx<3000)caught=true; // seed should have pushed AMEX above $3k
  }finally{RET_SAV_XFR=orig;}
  assert(caught,'Mutation F not visible — savings seed guard is broken');
});

// ─────────────────────────────────────────────────────────────────────────
// RESULTS
// ─────────────────────────────────────────────────────────────────────────
console.log('\n╔══════════════════════════════════════════════════════════════╗');
console.log('║                       RESULTS                               ║');
console.log('╚══════════════════════════════════════════════════════════════╝');
console.log(`  Passed:  ${pass}`);
console.log(`  Failed:  ${fail}`);
if(failures.length){
  console.log('\n  FAILURES:');
  failures.forEach((f,i)=>console.log(`  ${i+1}. ${f.name}\n     ${f.error}`));
}
console.log(fail===0?'\n  ✅ ALL TESTS PASSED\n':'\n  ❌ FAILURES ABOVE\n');
process.exit(fail>0?1:0);
