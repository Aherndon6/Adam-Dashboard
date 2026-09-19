// ═══════════════════════════════════════════════════════════════════════════
// Herndon Financial OS — P3b-1 A1b focused suite (spec rev 3.3)
// ───────────────────────────────────────────────────────────────────────────
// Standalone. Loads the candidate named by HFOS_INDEX (default ./index.html) exactly like
// test_regression.js, so mutation runs exercise the mutated candidate. No test in this file
// reads index.html by any other path.
//
// Tags (every test carries exactly one):
//   [A1b-R1]   state substrate authorized for Round 1 (read integrity, pair cycle, classification,
//              L1–L8, §7 exclusions, INV-A/B/C substrate, BLR_STATE, month-state derivation, D1).
//              Expected RED before Round 1, GREEN after.
//   [A1b-R2]   consumer / rendering / Manage Lines obligations intentionally deferred to Round 2.
//              Expected RED before AND after Round 1. Never faked green.
//   [A1b-BASE] obligations or regression guards A1a already satisfies. Expected GREEN throughout;
//              each exists to kill a specific mutant or to pin a boundary Round 1 must not cross.
//
// Interface names used below are the Round-1 state-layer interface (named in the Round-1 packet).
// ═══════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const crypto = require('crypto');

let pass = 0, fail = 0;
const failures = [];
const _syncTests = [];
function test(name, fn) { _syncTests.push({ name, fn, sync: true }); }
function testAsync(name, fn) { _syncTests.push({ name, fn, sync: false }); }
function assert(c, m) { if (!c) throw new Error(m || 'Assertion failed'); }

const htmlPath = process.env.HFOS_INDEX || './index.html';
const html = fs.readFileSync(htmlPath, 'utf8');
const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
if (!scriptMatch) throw new Error('No <script> block found');
let sc = scriptMatch[1];
sc = sc.replace(/\bconst\b/g, 'var');
sc = sc.replace(/^try\s*\{[\s\S]*?\}\s*catch[\s\S]*?\}/m, '');
sc = sc.replace(/^loadAll\(\);/m, '');
const stub = `
var window={fetch:function(){return Promise.resolve({ok:true,json:function(){return Promise.resolve([])}});}};
var document={getElementById:function(){return{innerHTML:'',addEventListener:function(){},value:'',textContent:'',style:{},classList:{remove:function(){},add:function(){}},scrollIntoView:function(){}};},querySelectorAll:function(){return[];},querySelector:function(){return null;},addEventListener:function(){},activeElement:null,body:{style:{}}};
var localStorage={getItem:function(){return null;},setItem:function(){},removeItem:function(){}};
var requestAnimationFrame=function(){};var fetch=window.fetch;
var supabase={createClient:function(){return{auth:{
  getSession:function(){return Promise.resolve({data:{session:null},error:null});},
  signInWithPassword:function(){return Promise.resolve({data:null,error:{message:'mock-no-login'}});},
  signOut:function(){return Promise.resolve({error:null});},
  onAuthStateChange:function(){}
}};} };
`;
try { eval(stub + sc); } catch (e) { console.error('FATAL eval:', e.message); process.exit(1); }
const WEEKS = runModel(7000, 7694.87);
// Silence expected diagnostic noise from fail-closed paths under test.
const _origErr = console.error, _origWarn = console.warn, _origLog = console.log;
function quiet(on){ if(on){ console.error=function(){}; console.warn=function(){}; } else { console.error=_origErr; console.warn=_origWarn; } }

// ── State isolation ───────────────────────────────────────────────────────
const STATE = ['fetch','getAuthHeaders','renderApp','USER_ROLE','_categoriesCache','_registriesLoadStatus',
  '_budgetSelectedMonth','_budgetTransactions','_budgetTransLoadStatus','_budgetRegisterSpendCache',
  '_budgetRegisterSpendLoadStatus','_budgetLineRulesCache','_budgetLineRulesLoadStatus','_blrModal','activeSection',
  '_budgetShowAddForm','_budgetEditId','_budgetFormData','budgetRulesLoadStatus','goalsLoadStatus','_supaConnected'];
const OPTIONAL_STATE = ['_budgetPairCycle','_budgetPairGen','_budgetTransLoadGen','_budgetRegisterSpendLoadGen'];
function snap(){ var s={}; STATE.concat(OPTIONAL_STATE).forEach(function(n){ try{ s[n]=eval(n); }catch(e){ s[n]='__absent__'; } }); s.__doc=document.getElementById; s.__Date=global.Date; return s; }
function restore(s){ STATE.concat(OPTIONAL_STATE).forEach(function(n){ var __v=s[n]; if(__v==='__absent__')return; try{ eval(n+'=__v'); }catch(e){} }); document.getElementById=s.__doc; global.Date=s.__Date; }
function T(name, fn){ test(name, function(){ var s=snap(); try{ return fn(); } finally { restore(s); } }); }
function TA(name, fn){ testAsync(name, async function(){ var s=snap(); try{ return await fn(); } finally { restore(s); } }); }

// ── Fetch fixtures (PostgREST-shaped) ─────────────────────────────────────
function resp(status, body, headers){
  var hd={}; Object.keys(headers||{}).forEach(function(k){ hd[k.toLowerCase()]=headers[k]; });
  return { ok: status>=200&&status<300, status: status, statusText: String(status),
    headers: { get: function(k){ var v=hd[String(k).toLowerCase()]; return v===undefined?null:v; } },
    json: function(){ return body instanceof Error ? Promise.reject(body) : Promise.resolve(body); },
    text: function(){ return Promise.resolve(typeof body==='string'?body:JSON.stringify(body)); } };
}
// Exact-count response exactly as PostgREST answers "Prefer: count=exact".
function exact(rows, total){ var n=(total===undefined)?rows.length:total; return resp(200, rows, {'content-range': rows.length?('0-'+(rows.length-1)+'/'+n):('*/'+n)}); }
function deferred(){ var a,b; var p=new Promise(function(r,j){a=r;b=j;}); return {p:p,resolve:a,reject:b}; }
async function flush(n){ for(var i=0;i<(n||60);i++) await Promise.resolve(); }
function router(handlers){
  var log=[];
  var f=async function(url,init){
    var hdrs=(init&&init.headers)||{}; var e={url:String(url),method:(init&&init.method)||'GET',headers:hdrs,body:(init&&init.body!==undefined)?init.body:null};
    log.push(e);
    for(var i=0;i<handlers.length;i++){ if(handlers[i][0](e)) return handlers[i][1](e); }
    return exact([]);
  };
  f.log=log; return f;
}
const isReg = e => e.method==='GET' && /\/rest\/v1\/transactions\?/.test(e.url);
const isLeg = e => e.method==='GET' && /\/rest\/v1\/budget_transactions\?/.test(e.url);
const isBlrWrite = e => /\/rest\/v1\/budget_line_rules/.test(e.url) && e.method!=='GET';
const isAug = e => /gte\.2026-08-01/.test(e.url);
function hdr(e,name){ var h=e.headers||{}; var k=Object.keys(h).find(function(x){return x.toLowerCase()===name.toLowerCase();}); return k?h[k]:undefined; }

// ── Category / budget-line fixtures ───────────────────────────────────────
const REG = BUDGET_CATEGORY_REGISTRY;
const REG_EXPENSE_LEAVES = REG.filter(function(c){ return c.leaf&&!c.isIncome&&c.key!=='misc.goal_sweep'; }).map(function(c){return c.key;});
const REG_INCOME_LEAVES = REG.filter(function(c){ return c.leaf&&c.isIncome; }).map(function(c){return c.key;});
const REG_EXPENSE_PARENTS = REG.filter(function(c){ return !c.leaf&&!c.isIncome; }).map(function(c){return c.key;});
const EXCLUDED_KEYS = ['income.deep_south_commissions','business.jabian_deposits_2026','income.interest','income.bkcpa_extra_pay'];
function live(key, over){ return Object.assign({key:key,label:key,parent_key:key.indexOf('.')>0?key.split('.')[0]:null,is_leaf:true,lifecycle_status:'active',
  behavior_class:'expense',budget_treatment:'tracked',cashflow_treatment:'operating',merged_into_key:null,display_order:1},over||{}); }
// A live category table that BACKS every registry key, plus the four §7 exclusions and ordinary
// non-Budget categories (transfers, business). Mirrors the post-C1 production shape.
function liveCats(){
  var out=[];
  REG.forEach(function(c){
    if(!c.leaf) out.push(live(c.key,{is_leaf:false,parent_key:null,behavior_class:null,budget_treatment:null,cashflow_treatment:null}));
    else if(c.isIncome) out.push(live(c.key,{behavior_class:'income',budget_treatment:'display_only',cashflow_treatment:'inflow'}));
    else if(c.key==='misc.goal_sweep') out.push(live(c.key,{behavior_class:'savings_allocation',budget_treatment:'planned_allocation'}));
    else out.push(live(c.key));
  });
  out.push(live('income.deep_south_commissions',{behavior_class:'commission_income',budget_treatment:'display_only'}));
  out.push(live('business.jabian_deposits_2026',{parent_key:'business',behavior_class:'reimbursable_income',budget_treatment:'excluded'}));
  out.push(live('income.interest',{behavior_class:'income',budget_treatment:'display_only'}));
  out.push(live('income.bkcpa_extra_pay',{behavior_class:'income',budget_treatment:'display_only'}));
  out.push(live('transfers.credit_card_payment',{parent_key:'transfers',behavior_class:'transfer',budget_treatment:'excluded'}));
  out.push(live('business.jabian_expenses_2026',{parent_key:'business',behavior_class:'reimbursable_expense',budget_treatment:'excluded'}));
  return out;
}
function withCat(cats, key, over){ return cats.map(function(c){ return c.key===key?Object.assign({},c,over):c; }); }
function without(cats, key){ return cats.filter(function(c){ return c.key!==key; }); }
function byKey(cats){ var m={}; cats.forEach(function(c){ m[c.key]=c; }); return m; }
const GROC='food_dining.groceries', RENT='home.mortgage_rent';
function line(key, amount, over){ return Object.assign({id:'L-'+key,category_key:key,line_label:null,amount:amount,start_month:'2026-06-01',end_month:null,is_active:true},over||{}); }
function validLines(){ return [line(GROC,500),line(RENT,1000),line('income.net_salary',6000),line('misc.goal_sweep',200)]; }
// Budget fully available for Aug 2026 (no month pair loaded yet).
function budgetReady(o){ o=o||{}; renderApp=function(){}; USER_ROLE='owner'; getAuthHeaders=async function(){return {apikey:'t'};};
  _registriesLoadStatus='loaded'; _categoriesCache=o.cats||liveCats();
  _budgetLineRulesLoadStatus='loaded'; _budgetLineRulesCache=o.lines||validLines();
  _budgetSelectedMonth='2026-08-01'; _budgetTransLoadStatus='not_loaded'; _budgetRegisterSpendLoadStatus='not_loaded';
  _budgetTransactions=[]; _budgetRegisterSpendCache=[]; captureDom(); }
function reg(id, key, amount){ return {id:id,category_key:key,amount:amount,transaction_date:'2026-08-05'}; }
function leg(id, key, amount, over){ return Object.assign({id:id,transaction_date:'2026-08-06',created_at:'2026-08-06T10:00:00Z',amount:amount,
  transaction_type:'household_expense',category_key:key,excluded_from_budget:false,is_cleared:false,payment_account:'AMEX Gold'},over||{}); }
// Round-1 interface accessors that tolerate the pre-A1b baseline (so the red ledger shows the
// behavioural gap rather than a bare ReferenceError wherever an A1a analogue exists).
function cycle(){ try{ return _budgetPairCycle; }catch(e){ return undefined; } }
function pairGen(){ try{ return _budgetPairGen; }catch(e){ return undefined; } }
function src(name){ var c=cycle(); return c&&c.sources&&c.sources[name]; }
function pairLoad(m){ return (typeof _budgetLoadPair==='function')?_budgetLoadPair(m)
  :Promise.all([_budgetLoadRegisterSpend(m),_budgetLoadTransactions(m)]); } // pre-A1b: the two A1a loaders
// Load one complete month pair through the real pair loader.
async function loadPair(regRows, legRows, o){ o=o||{};
  fetch=router([[isReg,function(){ return o.regResp?o.regResp():exact(regRows||[]); }],[isLeg,function(){ return o.legResp?o.legResp():exact(legRows||[]); }]]);
  await pairLoad('2026-08-01'); await flush(); return fetch; }
function captureDom(){ var store={}; document.getElementById=function(id){ if(!store[id]) store[id]={id:id,innerHTML:'',value:'',textContent:'',style:{},classList:{add:function(){},remove:function(){}},addEventListener:function(){},scrollIntoView:function(){}}; return store[id]; }; return store; }
function reasons(ms){ return (ms&&ms.reasons||[]).map(function(r){ return r.code+(r.key?':'+r.key:''); }); }
function hasReason(ms, code, key){ return (ms&&ms.reasons||[]).some(function(r){ return r.code===code&&(key===undefined||r.key===key); }); }

// Brace-matched source of a top-level function (same method as the A1a pins).
function fnSrc(name){
  var tok='function '+name+'('; var i=html.indexOf(tok); if(i<0) return null;
  var j=html.indexOf('{',i), d=0, k=j, q=null;
  for(;k<html.length;k++){ var ch=html[k];
    if(q){ if(ch==='\\'){k++;continue;} if(ch===q)q=null; continue; }
    if(ch==='/'&&html[k+1]==='/'){ k=html.indexOf('\n',k); continue; }
    if(ch==="'"||ch==='"'||ch==='`'){ q=ch; continue; }
    if(ch==='{')d++; else if(ch==='}'){ d--; if(d===0) break; } }
  return html.slice(i,k+1);
}
function pin(name){ var s=fnSrc(name); return s===null?'MISSING':s.length+'/'+crypto.createHash('sha256').update(s).digest('hex').slice(0,16); }
function bh(tok){ var i=html.indexOf(tok); var j=html.indexOf('\nfunction ',i+tok.length); var s=html.slice(i,j<0?html.length:j); return s.length+'/'+crypto.createHash('sha256').update(s).digest('hex').slice(0,16); }

// Enumeration of category metadata used by parity / static tests.
const BCS=['expense','income','commission_income','reimbursable_income','reimbursable_expense','transfer','savings_allocation','goal_linked',null];
const BTS=['tracked','excluded','display_only','planned_allocation',null];
function allCombos(){ var out=[]; [true,false].forEach(function(leaf){ ['active','archived','merged'].forEach(function(lc){ BCS.forEach(function(bc){ BTS.forEach(function(bt){
  out.push({key:'x.k',is_leaf:leaf,lifecycle_status:lc,behavior_class:bc,budget_treatment:bt,merged_into_key:null}); }); }); }); }); return out; }

console.log('\n╔══════════════════════════════════════════════════════════════╗');
console.log('║     P3b-1 A1b focused suite                                  ║');
console.log('╚══════════════════════════════════════════════════════════════╝');
console.log('  candidate: '+htmlPath);

// ═══ S. Declarations, frozen predicates, static guards (§5, §7) ═══════════════════════════════
T('[A1b-R1] S1: §7 exclusion declaration — exactly the four keys, each with a non-empty reason, frozen',function(){
  assert(typeof BUDGET_INCOME_EXCLUSIONS==='object'&&BUDGET_INCOME_EXCLUSIONS,'BUDGET_INCOME_EXCLUSIONS missing');
  var ks=Object.keys(BUDGET_INCOME_EXCLUSIONS).sort();
  assert(JSON.stringify(ks)===JSON.stringify(EXCLUDED_KEYS.slice().sort()),'exclusion keys are '+JSON.stringify(ks));
  ks.forEach(function(k){ assert(typeof BUDGET_INCOME_EXCLUSIONS[k]==='string'&&BUDGET_INCOME_EXCLUSIONS[k].trim().length>10,'no reason for '+k); });
  assert(Object.isFrozen(BUDGET_INCOME_EXCLUSIONS),'declaration must be frozen');
});
T('[A1b-R1] S2: represented ∩ excluded = ∅ (no exclusion key is a registry key)',function(){
  assert(typeof BUDGET_INCOME_EXCLUSIONS==='object','declaration missing');
  var regKeys=REG.map(function(c){return c.key;});
  Object.keys(BUDGET_INCOME_EXCLUSIONS).forEach(function(k){ assert(regKeys.indexOf(k)<0,'excluded key '+k+' is also represented'); });
});
T('[A1b-BASE] S3: §5.2 static guard — SPEND_COUNTABLE ⇒ ASSIGNABLE over every leaf × lifecycle × behavior_class × budget_treatment',function(){
  var bad=allCombos().filter(function(c){ return _isCountableBudgetSpend(c)&&!_isAssignableCategory(c); });
  assert(bad.length===0,'SPEND_COUNTABLE without ASSIGNABLE: '+JSON.stringify(bad[0]));
  assert(allCombos().some(function(c){return _isCountableBudgetSpend(c);}),'enumeration must include countable cases');
});
T('[A1b-R1] S4: metadata wrappers equal the frozen predicates for active categories (parity, every combination)',function(){
  allCombos().filter(function(c){return c.lifecycle_status==='active';}).forEach(function(c){
    assert(_isSpendCountableMetadata(c)===_isCountableBudgetSpend(c),'spend parity broken for '+JSON.stringify(c));
    assert(_isIncomeCountableMetadata(c)===_isCountableBudgetIncome(c),'income parity broken for '+JSON.stringify(c));
  });
});
T('[A1b-R1] S5: metadata wrappers ignore lifecycle only (archived/merged == frozen predicate on an active copy); input not mutated',function(){
  allCombos().filter(function(c){return c.lifecycle_status!=='active';}).forEach(function(c){
    var before=JSON.stringify(c), act=Object.assign({},c,{lifecycle_status:'active'});
    assert(_isSpendCountableMetadata(c)===_isCountableBudgetSpend(act),'spend metadata ≠ predicate(active copy) for '+before);
    assert(_isIncomeCountableMetadata(c)===_isCountableBudgetIncome(act),'income metadata ≠ predicate(active copy) for '+before);
    assert(JSON.stringify(c)===before,'wrapper mutated its input');
  });
  assert(_isSpendCountableMetadata(null)===false&&_isIncomeCountableMetadata(undefined)===false,'null input must be non-countable');
});
T('[A1b-R1] S6: wrappers delegate to the frozen predicates (no cloned predicate logic)',function(){
  var s=fnSrc('_isSpendCountableMetadata'), i=fnSrc('_isIncomeCountableMetadata');
  assert(s&&s.indexOf('_isCountableBudgetSpend(')>=0,'spend wrapper must call _isCountableBudgetSpend');
  assert(i&&i.indexOf('_isCountableBudgetIncome(')>=0,'income wrapper must call _isCountableBudgetIncome');
  [s,i].forEach(function(x){ assert(!/savings_allocation|display_only|commission_income|'transfer'/.test(x),'wrapper clones predicate logic: '+x); });
});
T('[A1b-BASE] S7: frozen predicates and protected functions byte-identical (spec §23/§28; A1b wraps, never edits)',function(){
  assert(pin('_isCountableBudgetSpend')==='495/00b0a532e31f6c51','_isCountableBudgetSpend changed: '+pin('_isCountableBudgetSpend'));
  assert(pin('_isCountableBudgetIncome')==='255/8f30a4f5ac92ffce','_isCountableBudgetIncome changed: '+pin('_isCountableBudgetIncome'));
  assert(pin('_filterTxRows')==='1169/01186d010c979220','_filterTxRows changed');
  assert(pin('_sortTxRows')==='1727/8b04aa7713f27c0b','_sortTxRows changed');
  assert(pin('_computeLedgerBalances')==='374/c6ab1fc9bf055b5b','_computeLedgerBalances changed');
  assert(pin('_applyDisplayOrderBalances')==='526/08443d5c9cb5161e','_applyDisplayOrderBalances changed');
  assert(bh('function runModel(')==='33892/86f3f3082151fe56','runModel changed');
  assert(bh('function computeGoalTransferNetting(')==='10309/4670447ce489dd8b','netting changed');
  assert(bh('function resolveWeekTransfers(')==='5583/20d17438996ac8ba','resolver changed');
});
T('[A1b-BASE] S8: Round-1 boundary — no consumer, rendering, Goals, Manage Lines, Statement check or Category Report function changed',function(){
  var P={_computeRegisterSpend:'341/463f7468ccd6707e',_computeRegisterIncome:'340/3944f22cedc68cc1',_isAssignableCategory:'200/c4159141542a2a41',
    _txParseContentRangeTotal:'203/f81ce775b25c0e2b',_renderBudgetRecon:'3190/b8e4d15721109fff',_loadCategoryReport:'2108/0a5fb7f3667f7cb4',
    _getBudgetLivingExpenses:'611/2de448600e621f02',_getBudgetAmount:'423/93f65a0f5515eb2e',_getActiveBudgetCategories:'444/a8f4f710e9a959c6',
    _blrMutationUnavailable:'124/a4351cb013089224',_budgetLoadGateHtml:'2278/28ae0a75cdcaf7c5',_renderGoalsSavings:'12145/aedcf44d4be29f46'};
  Object.keys(P).forEach(function(n){ assert(pin(n)===P[n],n+' changed in Round 1: '+pin(n)); });
  var i=html.indexOf('function renderBudget(){'), g=html.indexOf('var gate=_budgetLoadGateHtml(monthIso);',i), e=html.indexOf('\nfunction _renderBudgetForm',i);
  var tail=html.slice(g,e); var h=tail.length+'/'+crypto.createHash('sha256').update(tail).digest('hex').slice(0,16);
  assert(g>0&&h==='32052/846f1d1fa94a8cf2','renderBudget changed after its load trigger (rendering is Round 2): '+h);
});
T('[A1b-BASE] S9: no schema/SQL/RPC/RLS/grant surface in the app script',function(){
  var script=scriptMatch[1];
  assert(!/CREATE POLICY|ALTER TABLE|DROP TABLE|CREATE TABLE|GRANT (SELECT|INSERT|UPDATE|DELETE)|REVOKE /.test(script),'schema statements present');
  assert(!/rest\/v1\/rpc\/[a-z_]*(budget|categor|transaction)/i.test(script),'a Budget/category/transaction RPC is referenced');
});

// ═══ R. Read integrity (§16.2–16.6, INV-F1; E3) ════════════════════════════════════════════════
function V(body, cr){ return _budgetVerifyMonthRows(body, cr); }
T('[A1b-R1] R1: rows == exact total with unique ids → complete',function(){
  var r=V([{id:'a'},{id:'b'}],'0-1/2'); assert(r.status==='complete'&&r.rows.length===2&&r.total===2,'got '+JSON.stringify(r));
});
T('[A1b-R1] R2: an exact empty month (*/0, []) is complete (a real zero is not a failure)',function(){
  var r=V([],'*/0'); assert(r.status==='complete'&&r.total===0,'got '+JSON.stringify(r));
});
T('[A1b-R1] R3: rows < total (server cap) → incomplete',function(){
  var r=V([{id:'a'},{id:'b'}],'0-1/3'); assert(r.status==='incomplete','got '+r.status);
});
T('[A1b-R1] R4: rows > total → incomplete',function(){
  var r=V([{id:'a'},{id:'b'}],'0-1/1'); assert(r.status==='incomplete','got '+r.status);
});
T('[A1b-R1] R5: missing or malformed Content-Range → incomplete (never assumed complete)',function(){
  [null,undefined,'','0-1/*','*/*','abc','0-1/-2','0-1/2.5','0-1/99999999999999999999'].forEach(function(cr){
    var r=V([{id:'a'},{id:'b'}],cr); assert(r.status==='incomplete','Content-Range '+JSON.stringify(cr)+' gave '+r.status);
  });
});
T('[A1b-R1] R6: duplicate ids → incomplete even when the count matches',function(){
  var r=V([{id:'a'},{id:'a'}],'0-1/2'); assert(r.status==='incomplete','got '+r.status);
});
T('[A1b-R1] R7: a row with no id → not complete (uniqueness cannot be proven)',function(){
  [[{id:'a'},{}],[{id:'a'},{id:null}],[{id:'a'},{id:''}]].forEach(function(b){ var r=V(b,'0-1/2'); assert(r.status!=='complete','missing id accepted: '+JSON.stringify(b)); });
});
T('[A1b-R1] R8: non-array body → failed (E3), for object, null, string, number',function(){
  [{},null,'[]',42,{rows:[]}].forEach(function(b){ var r=V(b,'*/0'); assert(r.status==='failed','body '+JSON.stringify(b)+' gave '+r.status); });
});
T('[A1b-R1] R9: a null/primitive row element → not complete',function(){
  [[null],['x'],[7]].forEach(function(b){ var r=V(b,'0-0/1'); assert(r.status!=='complete','row '+JSON.stringify(b)+' accepted'); });
});
TA('[A1b-R1] R10: both month reads request Prefer: count=exact, no limit/offset; Register selects id and category_key',async function(){
  budgetReady(); var f=await loadPair([],[]);
  var R=f.log.filter(isReg), L=f.log.filter(isLeg);
  assert(R.length===1&&L.length===1,'expected exactly one read per source, got '+R.length+'/'+L.length);
  [R[0],L[0]].forEach(function(e){
    assert(/count=exact/i.test(String(hdr(e,'Prefer')||'')),'Prefer: count=exact missing on '+e.url);
    assert(!/[?&](limit|offset)=/.test(e.url),'pagination/limit present on '+e.url);
    assert(/transaction_date=gte\.2026-08-01/.test(e.url)&&/transaction_date=lte\.2026-08-31/.test(e.url),'month filter changed: '+e.url);
  });
  var sel=/[?&]select=([^&]*)/.exec(R[0].url); var cols=sel?decodeURIComponent(sel[1]).split(','):[];
  ['id','category_key','amount','transaction_date'].forEach(function(c){ assert(cols.indexOf(c)>=0,'Register select lacks '+c+': '+R[0].url); });
  assert(cols.indexOf('account_key')<0,'D2: Budget Register read must not add account_key');
  assert(/[?&]select=\*/.test(L[0].url),'legacy read must keep select=* (already includes id): '+L[0].url);
});
[['HTTP 500',function(){return resp(500,{message:'x'});},'failed'],
 ['network error',function(){return Promise.reject(new Error('net'));},'failed'],
 ['unparseable body',function(){return resp(200,new Error('bad json'),{'content-range':'*/0'});},'failed'],
 ['non-array 200 body',function(){return resp(200,{rows:[]},{'content-range':'*/0'});},'failed'],
 ['rows < total',function(){return exact([reg('a',GROC,-5)],2);},'incomplete'],
 ['missing Content-Range',function(){return resp(200,[reg('a',GROC,-5)]);},'incomplete'],
 ['duplicate id',function(){return exact([reg('a',GROC,-5),reg('a',GROC,-6)]);},'incomplete']].forEach(function(c,ix){
  TA('[A1b-R1] R11-'+(ix+1)+': Register '+c[0]+' → source '+c[2]+'; consumer mirror fails closed (status failed, no rows)',async function(){
    budgetReady(); quiet(true); try{ await loadPair(null,[],{regResp:c[1]}); } finally { quiet(false); }
    assert(_budgetRegisterSpendLoadStatus==='failed','mirror status must be failed, got '+_budgetRegisterSpendLoadStatus);
    assert(Array.isArray(_budgetRegisterSpendCache)&&_budgetRegisterSpendCache.length===0,'no rows may reach the consumer mirror');
    assert(src('register')&&src('register').status===c[2],'source status '+(src('register')&&src('register').status));
    assert(_budgetTransLoadStatus==='loaded'&&src('legacy').status==='complete','the other source is unaffected');
  });
  TA('[A1b-R1] R12-'+(ix+1)+': legacy '+c[0]+' → source '+c[2]+'; consumer mirror fails closed',async function(){
    budgetReady(); var lr=c[1]; quiet(true); try{ await loadPair([],null,{legResp:function(){ var r=lr(); return r; }}); } finally { quiet(false); }
    assert(_budgetTransLoadStatus==='failed'&&Array.isArray(_budgetTransactions)&&_budgetTransactions.length===0,'legacy mirror must fail closed, got '+_budgetTransLoadStatus);
    assert(src('legacy')&&src('legacy').status===c[2],'source status '+(src('legacy')&&src('legacy').status));
  });
});
TA('[A1b-R1] R13 (E3): a malformed 200 body never reaches the Budget renderer (no throw, no figures)',async function(){
  budgetReady(); var dom=captureDom();
  quiet(true);
  try{
    fetch=router([[isReg,function(){ return resp(200,{unexpected:true},{'content-range':'*/0'}); }],[isLeg,function(){ return exact([]); }]]);
    await pairLoad('2026-08-01');
    await flush();
    renderBudget();
  } finally { quiet(false); }
  assert(!/<table/.test(dom['budget-content'].innerHTML),'a figure grid rendered from a malformed body');
  assert(Array.isArray(_budgetRegisterSpendCache),'a non-array body reached the consumer cache');
});
TA('[A1b-BASE] R14: an auth-header failure fails the pair closed (no request, no throw)',async function(){
  budgetReady(); getAuthHeaders=async function(){ throw new Error('no session'); }; var f=router([]); fetch=f;
  quiet(true); try{ await pairLoad('2026-08-01'); await flush(); } finally { quiet(false); }
  assert(_budgetRegisterSpendLoadStatus==='failed'&&_budgetTransLoadStatus==='failed','both mirrors must fail closed, got '+_budgetRegisterSpendLoadStatus+'/'+_budgetTransLoadStatus);
});

// ═══ G. Pair generation (§17; E2) ══════════════════════════════════════════════════════════════
TA('[A1b-R1] G1: the Budget trigger starts ONE cycle that owns both reads (one request per source)',async function(){
  budgetReady(); var f=router([]); fetch=f;
  renderBudget(); await flush();
  assert(f.log.filter(isReg).length===1&&f.log.filter(isLeg).length===1,'expected one read per source, got '+f.log.filter(isReg).length+'/'+f.log.filter(isLeg).length);
  assert(cycle()&&typeof cycle().gen==='number'&&cycle().monthIso==='2026-08-01','no pair cycle recorded');
  assert(src('register')&&src('legacy'),'both sources must be recorded on the same cycle');
});
[['_budgetLoadTransactions','legacy post-write reload'],['_budgetLoadRegisterSpend','Register source reload']].forEach(function(c,ix){
  TA('[A1b-R1] G2-'+(ix+1)+': '+c[1]+' ('+c[0]+') re-reads BOTH sources under one new generation',async function(){
    budgetReady(); await loadPair([reg('r1',GROC,-10)],[]); var g0=cycle()&&cycle().gen;
    var f=router([]); fetch=f; await eval(c[0])('2026-08-01'); await flush();
    assert(f.log.filter(isReg).length===1&&f.log.filter(isLeg).length===1,'a single-source reload must reload the pair, got '+f.log.filter(isReg).length+'/'+f.log.filter(isLeg).length);
    assert(cycle().gen!==g0,'the reload must run under a new generation');
  });
});
TA('[A1b-R1] G3: one old source + one current source never form a presented pair (post-write reload of one source)',async function(){
  budgetReady(); await loadPair([reg('r-old',GROC,-10)],[]);
  var dR=deferred(); fetch=router([[isReg,function(){return dR.p;}],[isLeg,function(){return exact([leg('l-new',GROC,5)]);}]]);
  var p=_budgetLoadTransactions('2026-08-01'); await flush();
  assert(!(_budgetRegisterSpendLoadStatus==='loaded'&&_budgetTransLoadStatus==='loaded'),'a mixed pair (old Register + new legacy) is presented as loaded');
  dR.resolve(exact([reg('r-new',GROC,-20)])); await p; await flush();
  assert(_budgetRegisterSpendCache.length===1&&_budgetRegisterSpendCache[0].id==='r-new'&&_budgetTransactions[0].id==='l-new','final pair must be one generation: '+JSON.stringify([_budgetRegisterSpendCache,_budgetTransactions]));
});
TA('[A1b-R1] G4: month change invalidates the in-flight pair immediately; the late month-A pair is discarded',async function(){
  budgetReady(); var dA=deferred(), dL=deferred();
  fetch=router([[function(e){return isReg(e)&&isAug(e);},function(){return dA.p;}],[function(e){return isLeg(e)&&isAug(e);},function(){return dL.p;}]]);
  var p=pairLoad('2026-08-01'); await flush(); var g0=pairGen();
  window._budgetChangeMonth('2026-09-01');
  var g1=pairGen();
  dA.resolve(exact([reg('aug',GROC,-1)])); dL.resolve(exact([])); await p; await flush();
  assert(_budgetRegisterSpendLoadStatus==='not_loaded'&&_budgetTransLoadStatus==='not_loaded','late month-A responses changed month-B state: '+_budgetRegisterSpendLoadStatus+'/'+_budgetTransLoadStatus);
  assert(typeof g0==='number'&&g1!==g0,'month change must invalidate the current pair generation synchronously (gen '+g0+' → '+g1+')');
  assert(!(cycle()&&cycle().monthIso==='2026-08-01'),'the month-A cycle is still current');
});
TA('[A1b-R1] G5: Retry starts a new pair — responses of the pre-Retry cycle cannot commit',async function(){
  budgetReady(); var dR=deferred(), dL=deferred();
  fetch=router([[isReg,function(){return dR.p;}],[isLeg,function(){return dL.p;}]]);
  var p=pairLoad('2026-08-01'); await flush();
  _budgetRetryLoad();
  dR.resolve(exact([reg('pre-retry',GROC,-1)])); dL.resolve(exact([])); await p; await flush();
  assert(_budgetRegisterSpendLoadStatus!=='loaded'&&_budgetTransLoadStatus!=='loaded','pre-Retry responses committed after Retry: '+_budgetRegisterSpendLoadStatus+'/'+_budgetTransLoadStatus);
});
[['success',function(){return exact([reg('aug-old',GROC,-1)]);}],['HTTP 500',function(){return resp(500,{});}],['incomplete',function(){return exact([reg('aug-old',GROC,-1)],5);}],['network error',function(){return Promise.reject(new Error('net'));}]].forEach(function(v,ix){
  TA('[A1b-R1] G6-'+(ix+1)+': Aug → Sep → Aug — the late FIRST Aug Register response ('+v[0]+') cannot change current state',async function(){
    budgetReady(); var d1=deferred(), n=0;
    fetch=router([[function(e){return isReg(e)&&isAug(e);},function(){ n++; return n===1?d1.p:exact([reg('aug-new',GROC,-2)]); }]]);
    var p1=pairLoad('2026-08-01'); await flush();
    window._budgetChangeMonth('2026-09-01'); await pairLoad('2026-09-01'); await flush();
    window._budgetChangeMonth('2026-08-01'); await pairLoad('2026-08-01'); await flush();
    quiet(true); try{ d1.resolve(v[1]()); try{ await p1; }catch(e){} await flush(); } finally { quiet(false); }
    assert(_budgetRegisterSpendLoadStatus==='loaded'&&_budgetRegisterSpendCache.length===1&&_budgetRegisterSpendCache[0].id==='aug-new','current state changed: '+_budgetRegisterSpendLoadStatus+' '+JSON.stringify(_budgetRegisterSpendCache));
    assert(src('register').status==='complete','current completeness status changed');
  });
});
TA('[A1b-R1] G7: pinned month — both reads use the cycle month even if the resolved month drifts during the auth await',async function(){
  budgetReady(); _budgetSelectedMonth='';
  var da=deferred(); getAuthHeaders=function(){ return da.p; };
  var f=router([]); fetch=f;
  var p=pairLoad('2026-08-01'); await flush();
  _budgetSelectedMonth='2026-10-01'; // resolved month drifts without a month-change action
  da.resolve({apikey:'t'}); await p; await flush();
  f.log.filter(function(e){return isReg(e)||isLeg(e);}).forEach(function(e){ assert(isAug(e)&&/lte\.2026-08-31/.test(e.url),'a read resolved the month again: '+e.url); });
  assert(f.log.filter(isReg).length===1&&f.log.filter(isLeg).length===1,'expected one read per source');
  assert(cycle()&&cycle().monthIso==='2026-08-01','cycle month not pinned');
});
TA('[A1b-R1] G8 (E2): calendar rollover while the current-month pair is in flight cannot strand Budget in loading',async function(){
  budgetReady(); _budgetSelectedMonth='';
  var RealDate=global.Date, now=new RealDate(2026,8,30,23,59,0).getTime();
  global.Date=class extends RealDate{ constructor(...a){ if(a.length===0) super(now); else super(...a); } static now(){ return now; } };
  var dR=deferred(), dL=deferred(), n=0;
  fetch=router([[function(e){return isReg(e)&&/gte\.2026-09-01/.test(e.url);},function(){return dR.p;}],[function(e){return isLeg(e)&&/gte\.2026-09-01/.test(e.url);},function(){return dL.p;}]]);
  var renders=0; renderApp=function(){ renders++; renderBudget(); };
  renderBudget(); await flush();
  now=new RealDate(2026,9,1,0,1,0).getTime(); // midnight passes: current month is now October
  dR.resolve(exact([reg('sep',GROC,-1)])); dL.resolve(exact([])); await flush(200);
  assert(_budgetRegisterSpendLoadStatus!=='loading'&&_budgetTransLoadStatus!=='loading','Budget stranded in loading after rollover: '+_budgetRegisterSpendLoadStatus+'/'+_budgetTransLoadStatus);
  assert(cycle()&&cycle().monthIso==='2026-10-01','after rollover the pair must be for the displayed month, got '+(cycle()&&cycle().monthIso));
});
TA('[A1b-BASE] G9: overlapping same-month cycles — the older cycle cannot beat the newer one, even between fetch and body parse',async function(){
  budgetReady(); var dj=deferred(), n=0;
  fetch=router([[isReg,function(){ n++; if(n===1){ var r0=exact([]); r0.json=function(){return dj.p;}; return r0; } return exact([reg('new',GROC,-2)]); }]]);
  var p1=pairLoad('2026-08-01'); await flush();
  await pairLoad('2026-08-01'); await flush();
  dj.resolve([reg('old',GROC,-1)]); await p1; await flush();
  assert(_budgetRegisterSpendCache.length===1&&_budgetRegisterSpendCache[0].id==='new','older cycle body overwrote the newer pair');
});
TA('[A1b-R1] G11 (Fable F-5): a cycle superseded during its auth await issues NO request',async function(){
  budgetReady(); var da=deferred(), calls=0; getAuthHeaders=function(){ calls++; return calls<=2?da.p:Promise.resolve({apikey:'t'}); };
  var f=router([]); fetch=f;
  var p1=pairLoad('2026-08-01'); await flush();
  var p2=pairLoad('2026-08-01'); await p2; await flush();
  var afterNew=f.log.length;
  da.resolve({apikey:'t'}); await p1; await flush();
  assert(afterNew===2,'the current cycle must issue exactly one read per source, got '+afterNew);
  assert(f.log.length===2,'the superseded cycle issued '+(f.log.length-afterNew)+' request(s) after its auth await');
});
T('[A1b-BASE] G10: entering Budget resets both month sources (A1a B6 intent kept)',function(){
  renderApp=function(){}; _budgetTransLoadStatus='loaded'; _budgetRegisterSpendLoadStatus='loaded';
  setSection('budget');
  assert(_budgetRegisterSpendLoadStatus==='not_loaded'&&_budgetTransLoadStatus==='not_loaded','Budget entry must reset both sources');
});

// ═══ C. Register row classification (§10, §5.1) ════════════════════════════════════════════════
function CR(row, cats){ return _classifyRegisterRow(row, byKey(cats||liveCats())); }
T('[A1b-R1] C1: NULL category → uncategorized',function(){
  var c=CR(reg('a',null,-5)); assert(c.kind==='uncategorized','got '+JSON.stringify(c));
  var c2=CR({id:'b',amount:3,transaction_date:'2026-08-01'}); assert(c2.kind==='uncategorized','undefined key: '+JSON.stringify(c2));
});
T('[A1b-R1] C2: active leaf → current predicates (spend counted / income counted / not counted)',function(){
  var s=CR(reg('a',GROC,-5)); assert(s.kind==='counted'&&s.as==='spend','spend: '+JSON.stringify(s));
  var i=CR(reg('b','income.net_salary',5)); assert(i.kind==='counted'&&i.as==='income','income: '+JSON.stringify(i));
  var t=CR(reg('c','transfers.credit_card_payment',-5)); assert(t.kind==='none','transfer: '+JSON.stringify(t));
  var x=CR(reg('d','business.jabian_expenses_2026',-5)); assert(x.kind==='none','excluded: '+JSON.stringify(x));
});
T('[A1b-R1] C3: active NON-leaf category → unverified',function(){
  var c=CR(reg('a','food_dining',-5)); assert(c.kind==='unverified','got '+JSON.stringify(c));
});
T('[A1b-R1] C4: archived or merged SPEND/INCOME-countable metadata → unverified (would be silently dropped)',function(){
  ['archived','merged'].forEach(function(lc){
    var s=CR(reg('a',GROC,-5),withCat(liveCats(),GROC,{lifecycle_status:lc})); assert(s.kind==='unverified','spend '+lc+': '+JSON.stringify(s));
    var i=CR(reg('b','income.net_salary',5),withCat(liveCats(),'income.net_salary',{lifecycle_status:lc})); assert(i.kind==='unverified','income '+lc+': '+JSON.stringify(i));
  });
});
T('[A1b-R1] C5: archived or merged NON_COUNTABLE metadata → no Budget effect',function(){
  ['archived','merged'].forEach(function(lc){
    var c=CR(reg('a','transfers.credit_card_payment',-5),withCat(liveCats(),'transfers.credit_card_payment',{lifecycle_status:lc})); assert(c.kind==='none',lc+': '+JSON.stringify(c));
  });
});
T('[A1b-R1] C6: merged rows follow their OWN metadata, never merged_into_key (both directions)',function(){
  var cats=liveCats().concat([live('old.noncount',{lifecycle_status:'merged',merged_into_key:GROC,behavior_class:'transfer',budget_treatment:'excluded'})]);
  var a=CR(reg('a','old.noncount',-5),cats); assert(a.kind==='none','non-countable source merged into a countable target must have no effect: '+JSON.stringify(a));
  var cats2=liveCats().concat([live('old.count',{lifecycle_status:'merged',merged_into_key:'transfers.credit_card_payment'})]);
  var b=CR(reg('b','old.count',-5),cats2); assert(b.kind==='unverified','countable source merged into a non-countable target must be unverified: '+JSON.stringify(b));
});
T('[A1b-R1] C7: key absent from loaded category state → unverified',function(){
  var c=CR(reg('a','nope.missing',-5)); assert(c.kind==='unverified','got '+JSON.stringify(c));
  var e=CR(reg('b','',-5)); assert(e.kind==='unverified','empty-string key is not NULL: '+JSON.stringify(e));
});
T('[A1b-R1] C8: archived/merged INDETERMINATE metadata (NULL behavior or treatment on a leaf) → unverified',function(){
  [{behavior_class:null},{budget_treatment:null}].forEach(function(o){
    var c=CR(reg('a','old.x',-5),liveCats().concat([live('old.x',Object.assign({lifecycle_status:'archived'},o))])); assert(c.kind==='unverified',JSON.stringify(o)+': '+JSON.stringify(c));
  });
});
T('[A1b-R1] C9: allocation behavior (active savings_allocation leaf) → not counted, as today',function(){
  var c=CR(reg('a','misc.goal_sweep',-5)); assert(c.kind==='none','got '+JSON.stringify(c));
});
T('[A1b-R1] C10: unrecognized lifecycle_status → unverified',function(){
  [null,'retired','Active'].forEach(function(lc){ var c=CR(reg('a',GROC,-5),withCat(liveCats(),GROC,{lifecycle_status:lc})); assert(c.kind==='unverified',JSON.stringify(lc)+': '+JSON.stringify(c)); });
});
T('[A1b-R1] C11: a counted or uncategorized row with a non-finite amount → unverified (not silently dropped)',function(){
  [NaN,'abc',null,Infinity].forEach(function(a){
    assert(CR(reg('a',GROC,a)).kind==='unverified','countable row amount '+String(a));
    assert(CR(reg('b',null,a)).kind==='unverified','uncategorized row amount '+String(a));
  });
  assert(CR(reg('c','transfers.credit_card_payment','abc')).kind==='none','a non-countable row with a bad amount has no Budget effect');
});
// OWNER RULING (A1b Round-1 gate, F-1 reconsideration): a Register row on an archived OR merged NON-leaf
// category is UNVERIFIED, like an active non-leaf — lifecycle change must not make it drop out of integrity.
// The row's own category decides (never merged_into_key); frozen predicates and Budget arithmetic unchanged.
function nonLeaf(key, over){ return live(key, Object.assign({is_leaf:false,parent_key:null}, over||{})); }
T('[A1b-R1] F1-A: active non-leaf → UNVERIFIED (active_non_leaf)',function(){
  var c=CR(reg('a','old.parent',-5),liveCats().concat([nonLeaf('old.parent')])); assert(c.kind==='unverified'&&c.reason==='active_non_leaf'&&c.key==='old.parent','got '+JSON.stringify(c));
});
[['archived','NULL treatment',{lifecycle_status:'archived',behavior_class:null,budget_treatment:null}],
 ['archived','non-null treatment',{lifecycle_status:'archived'}],
 ['merged','NULL treatment',{lifecycle_status:'merged',behavior_class:null,budget_treatment:null,merged_into_key:GROC}],
 ['merged','non-null treatment',{lifecycle_status:'merged',merged_into_key:GROC}],
 ['archived','non-countable treatment',{lifecycle_status:'archived',behavior_class:'transfer',budget_treatment:'excluded'}]].forEach(function(v,ix){
  T('[A1b-R1] F1-'+'BCDEX'[ix]+': '+v[0]+' non-leaf with '+v[1]+' → UNVERIFIED naming its own key',function(){
    var c=CR(reg('a','old.parent',-5),liveCats().concat([nonLeaf('old.parent',v[2])]));
    assert(c.kind==='unverified'&&c.key==='old.parent','got '+JSON.stringify(c));
  });
});
T('[A1b-R1] F1-F: merged non-leaf never follows merged_into_key (countable leaf target or non-countable target alike)',function(){
  [GROC,'transfers.credit_card_payment'].forEach(function(t){
    var c=CR(reg('a','old.parent',-5),liveCats().concat([nonLeaf('old.parent',{lifecycle_status:'merged',merged_into_key:t})]));
    assert(c.kind==='unverified'&&c.key==='old.parent'&&c.reason!=='unknown_category','merged into '+t+': '+JSON.stringify(c));
  });
});
T('[A1b-R1] F1-G: archived/merged LEAF behaviour unchanged (countable → UNVERIFIED, non-countable → none, indeterminate → UNVERIFIED)',function(){
  ['archived','merged'].forEach(function(lc){
    assert(CR(reg('a',GROC,-5),withCat(liveCats(),GROC,{lifecycle_status:lc})).reason==='inactive_countable',lc+' countable leaf');
    assert(CR(reg('b','transfers.credit_card_payment',-5),withCat(liveCats(),'transfers.credit_card_payment',{lifecycle_status:lc})).kind==='none',lc+' non-countable leaf');
    assert(CR(reg('c',GROC,-5),withCat(liveCats(),GROC,{lifecycle_status:lc,budget_treatment:null})).reason==='indeterminate',lc+' indeterminate leaf');
  });
});
TA('[A1b-R1] F1-H: classification/authority only — the frozen spend fold is unchanged and the month is UNVERIFIED naming the key',async function(){
  var cats=liveCats().concat([nonLeaf('old.parent',{lifecycle_status:'archived'})]);
  var rows=[reg('a','old.parent',-5),reg('b',GROC,-7)];
  var sp=_computeRegisterSpend(rows,byKey(cats));
  assert(JSON.stringify(sp)===JSON.stringify({'food_dining.groceries':7}),'frozen spend fold changed: '+JSON.stringify(sp));
  assert(pin('_computeRegisterSpend')==='341/463f7468ccd6707e'&&pin('_isCountableBudgetSpend')==='495/00b0a532e31f6c51','frozen arithmetic/predicate changed');
  budgetReady({cats:cats}); await loadPair(rows,[]);
  var ms=_budgetMonthState('2026-08-01'); assert(ms.state==='UNVERIFIED'&&(ms.reasons||[]).some(function(r){return r.key==='old.parent';}),'got '+JSON.stringify(reasons(ms)));
});
T('[A1b-R1] C12: classification decides only; it computes no amounts and needs no request',function(){
  var f=router([]); fetch=f; var c=CR(reg('a',GROC,-5));
  assert(f.log.length===0,'classification made a request');
  assert(!('amount' in c)&&!('net' in c),'classification must not carry a recomputed amount');
});

// ═══ L. Legacy budget_transactions L1–L8 (§16.7.3) ══════════════════════════════════════════════
function CL(row){ return _classifyLegacyRow(row); }
T('[A1b-R1] L1: reimbursable_expense / reimbursement_income → no Budget effect',function(){
  ['reimbursable_expense','reimbursement_income'].forEach(function(t){ var c=CL(leg('a',null,5,{transaction_type:t,excluded_from_budget:true})); assert(c.case==='L1'&&c.kind==='none',t+': '+JSON.stringify(c)); });
});
T('[A1b-R1] L2: household_expense excluded_from_budget=true → no Budget effect',function(){
  var c=CL(leg('a',GROC,5,{excluded_from_budget:true})); assert(c.case==='L2'&&c.kind==='none','got '+JSON.stringify(c));
});
T('[A1b-R1] L3: every legacy expense leaf key is counted exactly as today',function(){
  REG_EXPENSE_LEAVES.forEach(function(k){ var c=CL(leg('a',k,5)); assert(c.case==='L3'&&c.kind==='counted',k+': '+JSON.stringify(c)); });
});
T('[A1b-R1] L4: NULL, empty or whitespace key → uncategorized',function(){
  [null,undefined,'','   '].forEach(function(k){ var c=CL(leg('a',k,5)); assert(c.case==='L4'&&c.kind==='uncategorized',JSON.stringify(k)+': '+JSON.stringify(c)); });
});
T('[A1b-R1] L5: every registry expense parent/group key → unverified naming the key',function(){
  REG_EXPENSE_PARENTS.forEach(function(k){ var c=CL(leg('a',k,5)); assert(c.case==='L5'&&c.kind==='unverified'&&c.key===k,k+': '+JSON.stringify(c)); });
});
T('[A1b-R1] L6: misc.goal_sweep → unverified (an allocation is never legacy spending)',function(){
  var c=CL(leg('a','misc.goal_sweep',5)); assert(c.case==='L6'&&c.kind==='unverified'&&c.key==='misc.goal_sweep','got '+JSON.stringify(c));
});
T('[A1b-R1] L7: income leaf, non-registry key, typo or padded key → unverified naming the key',function(){
  ['income.net_salary','income.interest','income','nope.key',' '+GROC,GROC.toUpperCase()].forEach(function(k){ var c=CL(leg('a',k,5)); assert(c.case==='L7'&&c.kind==='unverified'&&c.key===k,JSON.stringify(k)+': '+JSON.stringify(c)); });
});
T('[A1b-R1] L8: unrecognized transaction_type or non-finite amount → unverified (checked before L1–L7)',function(){
  [leg('a',GROC,5,{transaction_type:'refund'}),leg('b',GROC,5,{transaction_type:null}),leg('c',GROC,'abc'),leg('d',GROC,NaN),leg('e',GROC,Infinity),
   leg('f',null,'x',{transaction_type:'reimbursable_expense'})].forEach(function(r){ var c=CL(r); assert(c.case==='L8'&&c.kind==='unverified',JSON.stringify(r)+': '+JSON.stringify(c)); });
});
T('[A1b-BASE] L9 (X3): today\'s legacy spentByKey fold for L3 rows is unchanged (arithmetic characterization through renderBudget)',function(){
  // Budget grid with two L3 legacy rows on groceries: Spent must equal 12.34 + 7.66 = 20.00 exactly as today.
  var dom=captureDom(); renderApp=function(){}; USER_ROLE='owner';
  _registriesLoadStatus='loaded'; _categoriesCache=liveCats(); _budgetSelectedMonth='2026-08-01';
  _budgetLineRulesLoadStatus='loaded'; _budgetLineRulesCache=validLines();
  _budgetTransLoadStatus='loaded'; _budgetTransactions=[leg('a',GROC,'12.34'),leg('b',GROC,7.66)];
  _budgetRegisterSpendLoadStatus='loaded'; _budgetRegisterSpendCache=[];
  try{ _budgetPairCycle=null; }catch(e){}
  renderBudget(); var h=dom['budget-content'].innerHTML;
  var i=h.indexOf('data-cat-key="'+GROC+'"'); var row=i<0?'':h.slice(i,h.indexOf('</tr>',i));
  assert(i>=0,'groceries row not rendered');
  assert(row.indexOf('$20.00')>=0,'L3 legacy fold changed (expected groceries Spent $20.00): '+row.replace(/<[^>]+>/g,' ').replace(/\s+/g,' ').slice(-120));
});

// ═══ B. BLR_STATE (§8.1) ═══════════════════════════════════════════════════════════════════════
function BS(){ return _blrState('2026-08-01'); }
function blrReady(lines, cats){ renderApp=function(){}; _registriesLoadStatus='loaded'; _categoriesCache=cats||liveCats(); _budgetLineRulesLoadStatus='loaded'; _budgetLineRulesCache=lines||validLines(); }
[['budget lines not loaded',function(){_budgetLineRulesLoadStatus='not_loaded';_budgetLineRulesCache=null;}],
 ['budget lines loading',function(){_budgetLineRulesLoadStatus='loading';}],
 ['budget lines failed',function(){_budgetLineRulesLoadStatus='failed';}],
 ['budget lines failed with a stale prior cache',function(){_budgetLineRulesLoadStatus='failed';}],
 ['budget lines loaded but not an array',function(){_budgetLineRulesCache={};}],
 ['budget lines loaded-empty',function(){_budgetLineRulesCache=[];}],
 ['categories not loaded',function(){_registriesLoadStatus='not_loaded';}],
 ['categories loading',function(){_registriesLoadStatus='loading';}],
 ['categories failed',function(){_registriesLoadStatus='failed';}],
 ['categories loaded but not an array',function(){_categoriesCache=null;}]].forEach(function(c,ix){
  T('[A1b-R1] B1-'+(ix+1)+': '+c[0]+' → UNAVAILABLE',function(){
    blrReady(); c[1](); var s=BS(); assert(s&&s.state==='UNAVAILABLE','got '+JSON.stringify(s));
  });
});
TA('[A1b-R1] B2: a failed post-write reload (§18.3) → UNAVAILABLE for every month, stale cache never VALID',async function(){
  blrReady(); getAuthHeaders=async function(){return {};}; fetch=router([[function(e){return /budget_line_rules/.test(e.url);},function(){return resp(500,{});}]]);
  quiet(true); try{ await _blrReloadAndRender(); } finally { quiet(false); }
  ['2026-06-01','2026-08-01','2026-12-01'].forEach(function(m){ var s=_blrState(m); assert(s.state==='UNAVAILABLE',m+': '+JSON.stringify(s)); });
  fetch=router([[function(e){return /budget_line_rules/.test(e.url);},function(){return resp(200,validLines());}]]);
  await _blrReloadAndRender(); assert(BS().state==='VALID','a successful reload must restore VALID, got '+JSON.stringify(BS()));
});
T('[A1b-R1] B3: all active lines on BACKED registry leaves → VALID',function(){ blrReady(); var s=BS(); assert(s.state==='VALID','got '+JSON.stringify(s)); });
T('[A1b-R1] B4: June parent-key line (entertainment) with a BACKED_PARENT live category → VALID',function(){
  blrReady(validLines().concat([line('entertainment',300,{start_month:'2026-06-01',end_month:'2026-06-01'})]));
  var s=_blrState('2026-06-01'); assert(s.state==='VALID','got '+JSON.stringify(s));
});
[['missing',function(c){return without(c,'entertainment');}],['archived',function(c){return withCat(c,'entertainment',{lifecycle_status:'archived'});}],
 ['a leaf',function(c){return withCat(c,'entertainment',{is_leaf:true});}]].forEach(function(v,ix){
  T('[A1b-R1] B5-'+(ix+1)+': parent-key line whose live parent is '+v[0]+' → INVALID naming the key',function(){
    blrReady(validLines().concat([line('entertainment',300)]),v[1](liveCats()));
    var s=BS(); assert(s.state==='INVALID'&&s.keys.indexOf('entertainment')>=0,'got '+JSON.stringify(s));
  });
});
[['non-registry key',function(){ return {lines:validLines().concat([line('nope.orphan',50)]),cats:liveCats(),key:'nope.orphan'}; }],
 ['§7 exclusion key (not represented)',function(){ return {lines:validLines().concat([line('income.interest',5)]),cats:liveCats(),key:'income.interest'}; }],
 ['registry leaf with no live category',function(){ return {lines:validLines(),cats:without(liveCats(),GROC),key:GROC}; }],
 ['registry leaf archived',function(){ return {lines:validLines(),cats:withCat(liveCats(),GROC,{lifecycle_status:'archived'}),key:GROC}; }],
 ['registry leaf live as non-leaf',function(){ return {lines:validLines(),cats:withCat(liveCats(),GROC,{is_leaf:false}),key:GROC}; }],
 ['expense leaf whose live treatment is not spend-countable',function(){ return {lines:validLines(),cats:withCat(liveCats(),GROC,{behavior_class:'transfer'}),key:GROC}; }],
 ['income leaf whose live treatment is not income-countable',function(){ return {lines:validLines(),cats:withCat(liveCats(),'income.net_salary',{behavior_class:'expense',budget_treatment:'tracked'}),key:'income.net_salary'}; }],
 ['misc.goal_sweep not planned_allocation',function(){ return {lines:validLines(),cats:withCat(liveCats(),'misc.goal_sweep',{budget_treatment:'tracked'}),key:'misc.goal_sweep'}; }]].forEach(function(v,ix){
  T('[A1b-R1] B6-'+(ix+1)+': active covering line on '+v[0]+' → INVALID naming the key',function(){
    var x=v[1](); blrReady(x.lines,x.cats); var s=BS(); assert(s.state==='INVALID'&&s.keys.indexOf(x.key)>=0,'got '+JSON.stringify(s));
  });
});
T('[A1b-R1] B7: lines that do not cover the month (inactive, ended, future) never invalidate it',function(){
  blrReady(validLines().concat([line('nope.a',1,{is_active:false}),line('nope.b',1,{end_month:'2026-07-01'}),line('nope.c',1,{start_month:'2026-09-01'})]));
  var s=BS(); assert(s.state==='VALID','got '+JSON.stringify(s));
});
T('[A1b-R1] B11 (Fable F-3): a line on the INCOME parent key is INVALID (BACKED_PARENT is for expense parents only)',function(){
  blrReady(validLines().concat([line('income',100)])); var s=BS();
  assert(s.state==='INVALID'&&s.keys.indexOf('income')>=0,'income parent line accepted: '+JSON.stringify(s));
});
T('[A1b-R1] B12 (Fable F-4): misc.goal_sweep live as a NON-leaf is not BACKED (INV-A) and its line is INVALID',function(){
  var cats=withCat(liveCats(),'misc.goal_sweep',{is_leaf:false});
  assert(_budgetRegistryBackingViolations(byKey(cats)).indexOf('misc.goal_sweep')>=0,'non-leaf goal_sweep counted as BACKED');
  blrReady(validLines(),cats); var s=BS(); assert(s.state==='INVALID'&&s.keys.indexOf('misc.goal_sweep')>=0,'got '+JSON.stringify(s));
});
T('[A1b-R1] B13 (Fable F-6): INVALID names EVERY offending key, not just the first',function(){
  blrReady(validLines().concat([line('nope.one',1),line('nope.two',2)])); var s=BS();
  assert(s.state==='INVALID'&&s.keys.indexOf('nope.one')>=0&&s.keys.indexOf('nope.two')>=0&&s.keys.length===2,'got '+JSON.stringify(s));
});
T('[A1b-R1] B8: UNAVAILABLE takes precedence over INVALID; BLR_STATE makes no request',function(){
  blrReady(validLines().concat([line('nope.orphan',50)])); _registriesLoadStatus='failed'; var f=router([]); fetch=f;
  var s=BS(); assert(s.state==='UNAVAILABLE','got '+JSON.stringify(s)); assert(f.log.length===0,'BLR_STATE issued a request');
});
T('[A1b-R1] B9: all ten Entertainment slots backed with no lines → VALID (no finding)',function(){
  blrReady(); var s=BS(); assert(s.state==='VALID','got '+JSON.stringify(s));
  assert(_budgetRegistryBackingViolations(byKey(liveCats())).length===0,'backed slots produced an INV-A finding');
});
T('[A1b-R1] B10: BLR_STATE UNAVAILABLE carries the existing A1a unavailability reason (one availability source)',function(){
  blrReady(); _budgetLineRulesCache=[]; var s=BS(); var u=_blrUnavailable();
  assert(u&&s.state==='UNAVAILABLE'&&s.code===u.code,'BLR_STATE and _blrUnavailable disagree: '+JSON.stringify([s,u]));
});

// ═══ I. INV-A / B / C (§8) ═════════════════════════════════════════════════════════════════════
T('[A1b-R1] I1: INV-A — every registry leaf BACKED → no violation; an unbacked leaf is named',function(){
  assert(_budgetRegistryBackingViolations(byKey(liveCats())).length===0,'backed registry reported violations');
  var v=_budgetRegistryBackingViolations(byKey(without(liveCats(),'entertainment.week_5'))); assert(v.indexOf('entertainment.week_5')>=0,'got '+JSON.stringify(v));
  var w=_budgetRegistryBackingViolations(byKey(withCat(liveCats(),'misc.goal_sweep',{budget_treatment:'tracked',behavior_class:'expense'}))); assert(w.indexOf('misc.goal_sweep')>=0,'planned-allocation row must require planned_allocation: '+JSON.stringify(w));
});
T('[A1b-R1] I2: INV-C — the four exclusions produce no violation',function(){
  var r=_budgetIncomeCoverage(liveCats()); assert(r.violations.length===0,'got '+JSON.stringify(r));
});
T('[A1b-R1] I3: INV-C — removing an exclusion flags that key; an unrepresented, unexcluded income category is flagged',function(){
  var ex=Object.assign({},BUDGET_INCOME_EXCLUSIONS); delete ex['income.interest'];
  var r=_budgetIncomeCoverage(liveCats(),ex); assert(r.violations.indexOf('income.interest')>=0,'got '+JSON.stringify(r));
  var r2=_budgetIncomeCoverage(liveCats().concat([live('income.new_bonus',{behavior_class:'income',budget_treatment:'display_only'})]));
  assert(r2.violations.indexOf('income.new_bonus')>=0,'got '+JSON.stringify(r2));
});
T('[A1b-R1] I4: INV-C — represented ∩ excluded is a violation (static rule enforced by the checker too)',function(){
  var ex=Object.assign({},BUDGET_INCOME_EXCLUSIONS,{'income.net_salary':'test overlap'});
  var r=_budgetIncomeCoverage(liveCats(),ex); assert(r.overlap.indexOf('income.net_salary')>=0,'got '+JSON.stringify(r));
});
T('[A1b-R1] I5: an exclusion whose live category is not income-countable is an audit finding, not a silent pass',function(){
  var r=_budgetIncomeCoverage(withCat(liveCats(),'income.interest',{behavior_class:'expense',budget_treatment:'tracked'}));
  assert(r.findings.indexOf('income.interest')>=0,'got '+JSON.stringify(r));
});

// ═══ M. Month state derivation (§19.1; internal — no consumer reads it in Round 1) ════════════
TA('[A1b-R1] M1: LOADING while no pair, a pair for another month, or the current pair is in flight',async function(){
  budgetReady(); try{ _budgetPairCycle=null; }catch(e){}
  assert(_budgetMonthState('2026-08-01').state==='LOADING','no cycle must be LOADING');
  var d=deferred(); fetch=router([[isReg,function(){return d.p;}]]);
  var p=pairLoad('2026-08-01'); await flush();
  assert(_budgetMonthState('2026-08-01').state==='LOADING','in-flight cycle must be LOADING');
  d.resolve(exact([])); await p; await flush();
  assert(_budgetMonthState('2026-09-01').state==='LOADING','a pair for another month must not certify this month');
});
TA('[A1b-R1] M2: clean month → VERIFIED',async function(){
  budgetReady(); await loadPair([reg('a',GROC,-40),reg('b','income.net_salary',6000),reg('c','transfers.credit_card_payment',-900)],[leg('l',GROC,5)]);
  var ms=_budgetMonthState('2026-08-01'); assert(ms.state==='VERIFIED','got '+JSON.stringify(ms));
});
TA('[A1b-R1] M3: Register NULL inflow + outflow and a legacy L4 row → COMPLETE_WITH_UNCATEGORIZED, N=3, signed net (Register +amount, legacy −amount)',async function(){
  budgetReady(); await loadPair([reg('a',GROC,-40),reg('u1',null,10),reg('u2',null,-40.25)],[leg('l4',null,25)]);
  var ms=_budgetMonthState('2026-08-01');
  assert(ms.state==='COMPLETE_WITH_UNCATEGORIZED','got '+JSON.stringify(ms));
  assert(ms.uncategorized.count===3,'count '+ms.uncategorized.count);
  assert(Math.abs(ms.uncategorized.net-(10-40.25-25))<1e-9,'signed net '+ms.uncategorized.net+' (expected -55.25)');
});
TA('[A1b-R1] M4: precedence — uncategorized + an incomplete source → UNVERIFIED',async function(){
  budgetReady(); await loadPair([reg('u1',null,10)],null,{legResp:function(){return exact([leg('l',GROC,5)],2);}});
  var ms=_budgetMonthState('2026-08-01'); assert(ms.state==='UNVERIFIED'&&hasReason(ms,'source_incomplete'),'got '+JSON.stringify(ms));
});
[['Register incomplete',{regResp:function(){return exact([reg('a',GROC,-1)],9);}},'source_incomplete'],
 ['legacy failed',{legResp:function(){return resp(500,{});}},'source_failed'],
 ['Register malformed body',{regResp:function(){return resp(200,{},{'content-range':'*/0'});}},'source_failed']].forEach(function(v,ix){
  TA('[A1b-R1] M5-'+(ix+1)+': '+v[0]+' → UNVERIFIED ('+v[2]+')',async function(){
    budgetReady(); quiet(true); try{ await loadPair([],[],v[1]); } finally { quiet(false); }
    var ms=_budgetMonthState('2026-08-01'); assert(ms.state==='UNVERIFIED'&&hasReason(ms,v[2]),'got '+JSON.stringify(reasons(ms)));
  });
});
[['categories not loaded',function(){_registriesLoadStatus='failed';},'categories_unavailable'],
 ['budget lines loaded-empty (UNAVAILABLE)',function(){_budgetLineRulesCache=[];},'budget_lines_unavailable'],
 ['budget lines failed',function(){_budgetLineRulesLoadStatus='failed';},'budget_lines_unavailable'],
 ['orphan budget line (INVALID)',function(){_budgetLineRulesCache=validLines().concat([line('nope.orphan',9)]);},'budget_lines_invalid'],
 ['unbacked registry leaf (INV-A)',function(){_categoriesCache=without(liveCats(),'home.openai');},'registry_unbacked'],
 ['unrepresented, unexcluded income category (INV-C)',function(){_categoriesCache=liveCats().concat([live('income.new_bonus',{behavior_class:'income',budget_treatment:'display_only'})]);},'income_unrepresented']].forEach(function(v,ix){
  TA('[A1b-R1] M6-'+(ix+1)+': '+v[0]+' → UNVERIFIED ('+v[2]+')',async function(){
    budgetReady(); await loadPair([reg('a',GROC,-1)],[]); v[1]();
    var ms=_budgetMonthState('2026-08-01'); assert(ms.state==='UNVERIFIED'&&hasReason(ms,v[2]),'got '+JSON.stringify(reasons(ms)));
  });
});
[['unknown Register key',[reg('a','nope.k',-1)],[],'unknown_category','nope.k'],
 ['archived countable Register reference',[reg('a','old.count',-1)],[],'inactive_countable','old.count'],
 ['active non-leaf Register reference',[reg('a','food_dining',-1)],[],'active_non_leaf','food_dining'],
 ['unrepresented spend-countable category WITH rows (INV-B)',[reg('a','pets.vet',-1)],[],'unrepresented_spend','pets.vet'],
 ['legacy L5 parent key',[],[leg('l','entertainment',5)],'legacy_group_key','entertainment'],
 ['legacy L6 misc.goal_sweep',[],[leg('l','misc.goal_sweep',5)],'legacy_allocation_key','misc.goal_sweep'],
 ['legacy L7 unknown key',[],[leg('l','nope.k',5)],'legacy_unknown_key','nope.k'],
 ['legacy L8 malformed',[],[leg('l',GROC,'x')],'legacy_malformed']].forEach(function(v,ix){
  TA('[A1b-R1] M7-'+(ix+1)+': '+v[0]+' → UNVERIFIED naming '+v[4],async function(){
    budgetReady({cats:liveCats().concat([live('old.count',{lifecycle_status:'archived'}),live('pets.vet',{parent_key:'pets'})])});
    await loadPair(v[1],v[2]);
    var ms=_budgetMonthState('2026-08-01'); assert(ms.state==='UNVERIFIED'&&hasReason(ms,v[3]),'got '+JSON.stringify(reasons(ms)));
    if(v[3]!=='legacy_malformed') assert(hasReason(ms,v[3],v[4]),'reason must name '+v[4]+': '+JSON.stringify(reasons(ms)));
  });
});
TA('[A1b-R1] M8: INV-B — an unrepresented spend-countable category WITHOUT displayed-month rows changes nothing at runtime (audit finding only)',async function(){
  budgetReady({cats:liveCats().concat([live('pets.vet',{parent_key:'pets'})])}); await loadPair([reg('a',GROC,-1)],[]);
  var ms=_budgetMonthState('2026-08-01'); assert(ms.state==='VERIFIED','got '+JSON.stringify(reasons(ms)));
  assert((ms.auditFindings||[]).some(function(f){return f.code==='unrepresented_spend_category'&&f.key==='pets.vet';}),'audit finding missing: '+JSON.stringify(ms.auditFindings));
});
TA('[A1b-R1] M9: month state derives from the committed pair only — later edits to the consumer mirrors cannot change it',async function(){
  budgetReady(); await loadPair([reg('a',GROC,-1)],[]);
  _budgetRegisterSpendCache.push(reg('junk','nope.k',-1)); _budgetRegisterSpendLoadStatus='loaded';
  var ms=_budgetMonthState('2026-08-01'); assert(ms.state==='VERIFIED','mirror edit changed certification: '+JSON.stringify(reasons(ms)));
});
TA('[A1b-R1] M10: month state is pure — no request, no mutation of Budget state',async function(){
  budgetReady(); await loadPair([reg('u',null,-1)],[]); var f=router([]); fetch=f;
  var before=JSON.stringify([_budgetRegisterSpendCache,_budgetTransactions,_budgetRegisterSpendLoadStatus,_budgetTransLoadStatus,cycle().gen]);
  _budgetMonthState('2026-08-01'); _budgetMonthState('2026-08-01');
  assert(f.log.length===0,'month state issued a request');
  assert(JSON.stringify([_budgetRegisterSpendCache,_budgetTransactions,_budgetRegisterSpendLoadStatus,_budgetTransLoadStatus,cycle().gen])===before,'month state mutated Budget state');
});

// ═══ E. Deferred A1a cases (E1 / D1; availability convergence) ═════════════════════════════════
TA('[A1b-R1] E1 (D1): loadAll network failure → budget-line status failed (not a lingering "not_loaded"); BLR_STATE UNAVAILABLE(failed)',async function(){
  renderApp=function(){}; getAuthHeaders=async function(){return {};}; _budgetLineRulesLoadStatus='not_loaded'; _budgetLineRulesCache=null;
  fetch=function(){ return Promise.reject(new Error('offline')); };
  quiet(true); try{ await loadAll(); await flush(); } finally { quiet(false); }
  assert(_budgetLineRulesLoadStatus==='failed','budget-line status after loadAll failure: '+_budgetLineRulesLoadStatus);
  var u=_blrUnavailable(); assert(u&&u.code==='failed','Goals/Manage Lines would still say "loading": '+JSON.stringify(u));
});
TA('[A1b-BASE] E1b (D1 guard): a SUCCESSFUL budget-line load is never turned into failed by a later loadAll error',async function(){
  renderApp=function(){}; getAuthHeaders=async function(){return {};}; _budgetLineRulesLoadStatus='not_loaded'; _budgetLineRulesCache=null;
  fetch=router([[function(e){return /budget_line_rules/.test(e.url);},function(){return resp(200,validLines());}],
    [function(e){return /goal_registry/.test(e.url);},function(){return resp(200,new Error('goal registry body broke'));}]]);
  quiet(true); try{ await loadAll(); await flush(); } finally { quiet(false); }
  assert(_budgetLineRulesLoadStatus==='loaded','a later loadAll error overwrote a successful budget-line load: '+_budgetLineRulesLoadStatus);
  assert(Array.isArray(_budgetLineRulesCache)&&_budgetLineRulesCache.length===4,'loaded lines lost');
});
T('[A1b-R1] E1c (D1): the correction is the one guarded statement inside loadAll\'s existing catch, mirroring the sibling statuses',function(){
  var s=fnSrc('loadAll'); var m=/\}catch\(e\)\{console\.error\('loadAll:',e\);([^\n]*)\}/.exec(s||'');
  assert(m,'loadAll catch not found');
  assert(m[1].indexOf("if(_budgetLineRulesLoadStatus!=='loaded')_budgetLineRulesLoadStatus='failed';")>=0,'guarded budget-line failure statement missing from the catch: '+m[1]);
  assert((s.match(/_budgetLineRulesLoadStatus='failed'/g)||[]).length===2,'loadAll must set failed only in its HTTP branch and its catch');
});

// ═══ Deferred Round-2 consumers (expected RED after Round 1 — never faked green) ═════════════════
T('[A1b-R2] D1: INV-D — every financial budget-line consumer calls the shared BLR_STATE determination',function(){
  ['_getBudgetAmount','_getActiveBudgetCategories','_getBudgetLivingExpenses','_blrMutationUnavailable','_budgetLoadGateHtml'].forEach(function(n){
    var s=fnSrc(n); assert(s&&s.indexOf('_blrState(')>=0,n+' does not use _blrState');
  });
  ['_getCategoryDisplayLabel','getBudgetCatLabel'].forEach(function(n){ var s=fnSrc(n); assert(s,'label consumer '+n+' missing'); });
});
T('[A1b-R2] D2: Goals — INVALID budget lines → Living Expenses unavailable (no partial sum)',function(){
  blrReady(validLines().concat([line('nope.orphan',50)])); assert(_getBudgetLivingExpenses(12)===null,'Goals summed an INVALID budget-line set');
});
T('[A1b-R2] D3a: Manage Lines is unavailable when categories are unavailable (§18.2), including with an empty budget-line table',function(){
  blrReady(); _registriesLoadStatus='failed'; assert(_blrMutationUnavailable()===true,'categories-unavailable still allows Manage Lines writes');
  blrReady(); _budgetLineRulesCache=[]; _registriesLoadStatus='failed'; assert(_blrMutationUnavailable()===true,'empty lines + categories-unavailable still allows writes');
});
// OWNER CLARIFICATION (A1b Round-1 gate, Issue A; §18.2 / INV-E): "budget-line state unavailable" in §18.2
// means budget-line or category AUTHORITY unavailable (not loaded / loading / failed / malformed), NOT
// BLR_STATE. An authoritative loaded-empty population stays BLR_STATE UNAVAILABLE for financial
// presentation (§8.1 unchanged; never VALID) but does not by itself forbid creating the first line: Add
// may proceed when categories and budget lines are both loaded/current, the population is demonstrably
// empty, the key passes the fresh INV-E BACKED read, and every other guard passes. "empty" never masks
// unavailable category authority.
TA('[A1b-R2] D3b: loaded-empty bootstrap — Add of a BACKED key proceeds from an authoritative empty population; empty never masks unavailable categories',async function(){
  blrReady([],liveCats()); USER_ROLE='owner'; getAuthHeaders=async function(){return {};};
  assert(_blrState('2026-10-01').state==='UNAVAILABLE','loaded-empty must stay UNAVAILABLE for financial presentation');
  assert(_blrMutationUnavailable()===false,'an authoritative empty population must allow controlled first-line creation');
  var f=router([[function(e){return /\/rest\/v1\/categories\?/.test(e.url);},function(){ return resp(200,[live('home.google')]); }],[isBlrWrite,function(){return resp(201,null);}]]); fetch=f; captureDom();
  _blrModal={mode:'add',key:'home.google',monthIso:'2026-10-01',label:'Google',amount:'50',scope:'forward',saving:false,error:null,isIncome:false};
  await _blrSaveAdd(); await flush();
  assert(f.log.filter(isBlrWrite).length===1,'first line was not created from an authoritative empty population');
  assert(f.log.some(function(e){return /\/rest\/v1\/categories\?/.test(e.url);}),'the first line was written without the fresh INV-E BACKED read');
  blrReady([],liveCats()); _registriesLoadStatus='failed'; assert(_blrMutationUnavailable()===true,'"empty" masked unavailable category authority');
  blrReady([],liveCats()); _budgetLineRulesLoadStatus='failed'; assert(_blrMutationUnavailable()===true,'failed budget lines must stay unavailable');
});

T('[A1b-R2] D4: Manage Lines Add offers only BACKED registry leaves (INV-E §18.1)',function(){
  blrReady(validLines(),without(liveCats(),'entertainment.event_4')); USER_ROLE='owner'; var dom=captureDom(); _blrOpenAdd('2026-10-01');
  var h=(dom['blr-modal-slot']||{}).innerHTML||'';
  assert(h.indexOf('value="entertainment.event_3"')>=0,'precondition: the Add modal must render and offer backed keys');
  assert(h.indexOf('value="entertainment.event_4"')<0,'unbacked key offered');
});
TA('[A1b-R2] D5: Manage Lines Add/Edit refuse an unbacked key after a fresh read, with no write (INV-E §18.2)',async function(){
  blrReady(validLines(),without(liveCats(),'home.google')); USER_ROLE='owner'; getAuthHeaders=async function(){return {};};
  var f=router([[function(e){return /\/rest\/v1\/categories\?/.test(e.url);},function(e){ return resp(200,[]); }],[isBlrWrite,function(){return resp(201,null);}]]); fetch=f; captureDom();
  _blrModal={mode:'add',key:'home.google',monthIso:'2026-10-01',label:'Google',amount:'50',scope:'forward',saving:false,error:null,isIncome:false};
  await _blrSaveAdd(); await flush();
  assert(f.log.filter(isBlrWrite).length===0,'unbacked Add was written');
});
function renderAug(regRows, legRows, o){ return (async function(){ budgetReady(o); var dom=captureDom(); await loadPair(regRows,legRows,o); renderBudget(); return dom['budget-content'].innerHTML; })(); }
TA('[A1b-R2] D6: UNVERIFIED — actual cells show "—" with "can\'t verify"; planned amounts stay visible; one integrity message',async function(){
  var h=await renderAug([reg('a',GROC,-40)],null,{legResp:function(){return exact([leg('l',GROC,5)],2);}});
  assert(/<table/.test(h),'UNVERIFIED must keep the grid (planned values per §8.1), not the whole-grid panel');
  assert(/can.t verify/i.test(h),'"can\'t verify" missing');
  assert(/\$500\.00/.test(h),'planned amount not shown');
  assert(!/\$45\.00/.test(h)&&!/\$40\.00/.test(h),'an unverifiable actual is shown as a figure');
});
TA('[A1b-R2] D7: COMPLETE WITH UNCATEGORIZED notice — N and the signed net, with a Register link; never "verified"',async function(){
  var h=await renderAug([reg('a',GROC,-40),reg('u1',null,10),reg('u2',null,-40.25)],[leg('l4',null,25)]);
  assert(/3 uncategorized transactions \(net -\$55\.25\) are not included in any category.s actuals\./.test(h),'notice missing or unsigned');
  assert(/setTxFilterUncategorized|_txFilterUncategorized/.test(h),'notice has no Register uncategorized link');
  assert(!/\bverified\b/i.test(h.replace(/can.t verify/ig,'')),'the state is described as verified');
});
TA('[A1b-R2] D8: UNAVAILABLE (loaded-empty budget lines) — planned cells "—", no $0 plan',async function(){
  var h=await renderAug([reg('a',GROC,-40)],[],{lines:[]});
  assert(!/\$0\.00/.test(h),'a $0 planned figure is shown for unavailable budget lines');
  assert(/Budget lines unavailable/i.test(h),'unavailable reason missing');
});
TA('[A1b-R2] D9: INVALID — budget-line totals "—", valid rows\' planned visible, offending key named',async function(){
  var h=await renderAug([reg('a',GROC,-40)],[],{lines:validLines().concat([line('nope.orphan',70)])});
  assert(/nope\.orphan/.test(h),'offending key not named');
  assert(/\$500\.00/.test(h),'valid row planned amount hidden');
});
TA('[A1b-R2] D10: Statement check is not authoritative-looking unless the legacy source is COMPLETE',async function(){
  var h=await renderAug([reg('a',GROC,-40)],null,{legResp:function(){return exact([leg('l',GROC,5)],3);}});
  var i=h.indexOf('Statement check'); assert(i>=0,'Statement check panel not rendered at all (per-cell rendering expected)');
  var panel=h.slice(i,i+3000); assert(/can.t verify|unavailable/i.test(panel)&&!/Reconciled/.test(panel),'Statement check presented without a complete legacy source');
});

// ── Runner ────────────────────────────────────────────────────────────────
(async () => {
  for (const t of _syncTests) {
    try { if (t.sync) t.fn(); else await t.fn(); pass++; process.stdout.write('  ✓ ' + t.name + '\n'); }
    catch (e) { fail++; failures.push({ name: t.name, error: e && e.message }); process.stdout.write('  ✗ ' + t.name + '\n    → ' + (e && e.message) + '\n'); }
  }
  const tags = {}; _syncTests.forEach(function(t){ var m=/^\[(A1b-[A-Z0-9]+)\]/.exec(t.name); var k=m?m[1]:'untagged'; tags[k]=tags[k]||{pass:0,fail:0}; });
  const failed = new Set(failures.map(f=>f.name));
  _syncTests.forEach(function(t){ var m=/^\[(A1b-[A-Z0-9]+)\]/.exec(t.name); var k=m?m[1]:'untagged'; if(failed.has(t.name)) tags[k].fail++; else tags[k].pass++; });
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║                       RESULTS                               ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log(`  Passed:  ${pass}`);
  console.log(`  Failed:  ${fail}`);
  Object.keys(tags).sort().forEach(function(k){ console.log('  '+k+': '+tags[k].pass+' pass / '+tags[k].fail+' fail'); });
  process.exit(fail > 0 ? 1 : 0);
})();
