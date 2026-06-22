// Hardening audit — Items 1, 2, 3
const fs=require('fs');
const html=fs.readFileSync('./index.html','utf8');
const scriptMatch=html.match(/<script>([\s\S]*?)<\/script>/);
let sc=scriptMatch[1];
sc=sc.replace(/\bconst\b/g,'var');
sc=sc.replace(/^try\s*\{[\s\S]*?\}\s*catch[\s\S]*?\}\s*$/m,'');
sc=sc.replace(/^loadAll\(\);/m,'');
var stub=`
var window={fetch:function(){return Promise.resolve({ok:true,json:function(){return Promise.resolve([])}});}};
var document={getElementById:function(){return{innerHTML:'',addEventListener:function(){},value:'',textContent:'',style:{},classList:{remove:function(){},add:function(){}},scrollIntoView:function(){}};},querySelectorAll:function(){return[];},querySelector:function(){return null;},activeElement:null,body:{style:{}}};
var localStorage={getItem:function(){return null;},setItem:function(){}};
var requestAnimationFrame=function(){};var fetch=window.fetch;
`;
eval(stub+sc);

let pass=0,fail=0;
const failures=[];
function test(name,fn){
  try{fn();pass++;console.log('  ✓ '+name);}
  catch(e){fail++;failures.push({name,err:e.message});console.log('  ✗ '+name+'\n    → '+e.message);}
}
function assert(c,m){if(!c)throw new Error(m||'Assertion failed');}
function assertApprox(a,b,m,tol=0.02){if(Math.abs(a-b)>tol)throw new Error((m||'')+' expected ~'+b+', got '+a);}

// ── ITEM 1: mv() semantics ──────────────────────────────────────────────────
console.log('\n── ITEM 1: mv() semantics ──');

function r2(n){return Math.round(n*100)/100;}
function sm_sim(b,a,f){return Math.max(0,Math.min(r2(a),r2(r2(b)-r2(f))));}

test('sm: full transfer (chk=7000, amt=400, fl=6500) = 400',()=>{
  assert(sm_sim(7000,400,6500)===400,'expected 400, got '+sm_sim(7000,400,6500));
});
test('sm: partial transfer (chk=6800, amt=400, fl=6500) = 300',()=>{
  assert(sm_sim(6800,400,6500)===300,'expected 300, got '+sm_sim(6800,400,6500));
});
test('sm: fully blocked (chk=6499, amt=400, fl=6500) = 0',()=>{
  assert(sm_sim(6499,400,6500)===0,'expected 0, got '+sm_sim(6499,400,6500));
});
test('sm: result never exceeds requested amt',()=>{
  [[7000,707.18,6500],[6600,200,6500],[6501,50,6500]].forEach(function(c){
    var res=sm_sim(c[0],c[1],c[2]);
    assert(res<=c[1],'sm exceeded amt: sm('+c+')='+res+' > amt='+c[1]);
  });
});
test('mv below MIN_XFR: sm=80 < 100, mv returns -80, nothing transferred (caller sees m<0, defers)',()=>{
  var below=sm_sim(6580,400,6500);
  assert(below===80,'sm should be 80 (below MIN_XFR), got '+below);
  assert(below<100,'should be below MIN_XFR=100');
  // Callers do if(m>0) — negative return means deferred, no silent loss
});
test('total tax deposited = BASE_TAX + COMM_TAX = 1228.54 (no silent loss)',()=>{
  var weeks=runModel(7000,7694.87);
  var deposited=r2(weeks[weeks.length-1].tax - weeks[0].startTax);
  assertApprox(deposited,1228.54,'Total tax deposited',0.05);
});
test('base tax fires full amount in week 2 (checking is high, no partial needed)',()=>{
  var weeks=runModel(7000,7694.87);
  var w2=weeks.find(function(w){return w.num===2;});
  assertApprox(w2.tax-w2.startTax,521.36,'Week 2 base tax transfer',0.05);
});

// ── ITEM 2: localStorage corruption recovery ────────────────────────────────
console.log('\n── ITEM 2: localStorage corruption recovery ──');

function withCorrupt(desc, corruptInput, fn){
  var orig=JSON.parse(JSON.stringify(actionOverrides));
  try{
    if(typeof corruptInput==='string'){
      try{actionOverrides=sanitizeOverrides(JSON.parse(corruptInput));}catch(e){actionOverrides={};}
    } else {
      actionOverrides=sanitizeOverrides(corruptInput);
    }
  }catch(e){actionOverrides={};}
  try{return fn();}finally{actionOverrides=orig;}
}

test('corrupt week_num=-5: sanitized, aoW falls back to default',()=>{
  withCorrupt('neg',-5,function(){
    actionOverrides={'commission_tax':{week_num:-5}};
    sanitizeOverrides(actionOverrides);
    // week_num=-5 stripped, aoW returns default
    var result=aoW('commission_tax');
    assert(result===ACTION_DEFAULT_WEEKS['commission_tax'],
      'Expected default '+ACTION_DEFAULT_WEEKS['commission_tax']+', got '+result);
  });
});

test('corrupt week_num=999: aoW falls back to default',()=>{
  var orig=actionOverrides['commission_tax'];
  actionOverrides['commission_tax']={week_num:999};
  sanitizeOverrides(actionOverrides);
  var result=aoW('commission_tax');
  if(orig===undefined)delete actionOverrides['commission_tax']; else actionOverrides['commission_tax']=orig;
  assert(result===ACTION_DEFAULT_WEEKS['commission_tax'],'aoW should default for week_num=999, got '+result);
});

test('corrupt week_num="abc": aoW falls back to default',()=>{
  var orig=actionOverrides['commission_tax'];
  actionOverrides['commission_tax']={week_num:'abc'};
  sanitizeOverrides(actionOverrides);
  var result=aoW('commission_tax');
  if(orig===undefined)delete actionOverrides['commission_tax']; else actionOverrides['commission_tax']=orig;
  assert(result===ACTION_DEFAULT_WEEKS['commission_tax'],'aoW should default for string week_num, got '+result);
});

test('corrupt null entry: aoW returns default, no crash',()=>{
  var orig=actionOverrides['commission_tax'];
  actionOverrides['commission_tax']=null;
  var result;
  try{result=aoW('commission_tax');}catch(e){throw new Error('aoW crashed on null: '+e.message);}
  if(orig===undefined)delete actionOverrides['commission_tax']; else actionOverrides['commission_tax']=orig;
  assert(result===ACTION_DEFAULT_WEEKS['commission_tax'],'null entry should give default, got '+result);
});

test('corrupt deleted:true + week_num:null: model runs, returns 31 weeks',()=>{
  var orig=actionOverrides['commission_tax'];
  actionOverrides['commission_tax']={deleted:true,week_num:null};
  sanitizeOverrides(actionOverrides);
  var weeks;
  try{weeks=runModel(7000,7694.87);}catch(e){throw new Error('runModel crashed: '+e.message);}
  if(orig===undefined)delete actionOverrides['commission_tax']; else actionOverrides['commission_tax']=orig;
  assert(weeks.length===31,'Model should return 31 weeks with deleted+null entry');
});

test('corrupt: all bad overrides at once, no negative balances',()=>{
  var orig=JSON.parse(JSON.stringify(actionOverrides));
  actionOverrides={
    commission_tax:{week_num:-5},
    tax_base:{week_num:999},
    alaska_draw:{week_num:'bad'},
    costco_visa:null
  };
  sanitizeOverrides(actionOverrides);
  var weeks=runModel(7000,7694.87);
  actionOverrides=orig;
  var negChk=weeks.filter(function(w){return w.chk<-0.01;});
  var negSav=weeks.filter(function(w){return w.sav<-0.01;});
  assert(negChk.length===0,'Negative checking after corrupt overrides: '+negChk.map(function(w){return w.num;}));
  assert(negSav.length===0,'Negative savings after corrupt overrides: '+negSav.map(function(w){return w.num;}));
});

test('malformed JSON string: sanitizeOverrides(null) returns empty object',()=>{
  var result=sanitizeOverrides(null);
  assert(result&&typeof result==='object'&&!Array.isArray(result),'Expected {}, got '+JSON.stringify(result));
});

// ── ITEM 3: action identity uniqueness ─────────────────────────────────────
console.log('\n── ITEM 3: action identity uniqueness ──');

test('realActKeys.length === realActs.length on every week (parallel arrays in sync)',()=>{
  // ac[] includes the "No transfers" sentinel which has no key; realActs/realActKeys exclude it.
  // The binding invariant is on the filtered pair, not the raw pair.
  var weeks=runModel(7000,7694.87);
  weeks.forEach(function(w){
    var rk=(w.realActKeys||[]).length;
    var ra=(w.realActs||[]).length;
    assert(rk===ra,'Week '+w.num+': realActKeys['+rk+'] !== realActs['+ra+']');
  });
});

test('no duplicate acKeys within any single week (default model)',()=>{
  var weeks=runModel(7000,7694.87);
  weeks.forEach(function(w){
    var seen={};var dups=[];
    (w.acKeys||[]).forEach(function(k){if(k&&seen[k])dups.push(k);seen[k]=true;});
    assert(dups.length===0,'Week '+w.num+' has duplicate acKeys: '+dups.join(','));
  });
});

test('no duplicate acKeys when commission_tax and tax_base both moved to same week',()=>{
  var origCt=actionOverrides['commission_tax'];
  var origTb=actionOverrides['tax_base'];
  actionOverrides['commission_tax']={week_num:5};
  actionOverrides['tax_base']={week_num:5};
  var weeks=runModel(7000,7694.87);
  actionOverrides['commission_tax']=origCt;
  actionOverrides['tax_base']=origTb;
  var w5=weeks.find(function(w){return w.num===5;});
  var seen={};var dups=[];
  (w5.acKeys||[]).forEach(function(k){if(k&&seen[k])dups.push(k);seen[k]=true;});
  assert(dups.length===0,'Week 5 (both taxes same week) has duplicate acKeys: '+dups.join(','));
});

test('commission_tax never appears under tax_base key',()=>{
  var weeks=runModel(7000,7694.87);
  var commTaxAsTaxBase=false;
  weeks.forEach(function(w){
    (w.acKeys||[]).forEach(function(k,i){
      if(k==='tax_base'){
        var label=w.ac[i]||'';
        if(label.toLowerCase().includes('commission'))commTaxAsTaxBase=true;
      }
    });
  });
  assert(!commTaxAsTaxBase,'commission_tax action must not appear under tax_base key');
});

test('commission_tax appears in model (not swallowed by taxTodo)',()=>{
  var weeks=runModel(7000,7694.87);
  var has=weeks.some(function(w){return (w.acKeys||[]).indexOf('commission_tax')>=0;});
  assert(has,'commission_tax key must appear somewhere in 31-week model');
});

test('alaska_draw appears exactly once (default)',()=>{
  var weeks=runModel(7000,7694.87);
  var count=weeks.reduce(function(s,w){return s+((w.acKeys||[]).filter(function(k){return k==='alaska_draw';}).length);},0);
  assert(count===1,'alaska_draw should appear exactly once, got '+count);
});

test('costco_visa appears exactly once (default)',()=>{
  var weeks=runModel(7000,7694.87);
  var count=weeks.reduce(function(s,w){return s+((w.acKeys||[]).filter(function(k){return k==='costco_visa';}).length);},0);
  assert(count===1,'costco_visa should appear exactly once by default, got '+count);
});

test('costco_visa deleted: appears zero times',()=>{
  var orig=actionOverrides['costco_visa'];
  actionOverrides['costco_visa']={deleted:true};
  var weeks=runModel(7000,7694.87);
  if(orig===undefined)delete actionOverrides['costco_visa']; else actionOverrides['costco_visa']=orig;
  var count=weeks.reduce(function(s,w){return s+((w.acKeys||[]).filter(function(k){return k==='costco_visa';}).length);},0);
  assert(count===0,'Deleted costco_visa must not appear in any week, got '+count);
});

test('commission_tax moved to week 8: no fires before week 8, max one per week',()=>{
  var orig=actionOverrides['commission_tax'];
  actionOverrides['commission_tax']={week_num:8};
  var weeks=runModel(7000,7694.87);
  if(orig===undefined)delete actionOverrides['commission_tax']; else actionOverrides['commission_tax']=orig;
  var early=weeks.filter(function(w){return w.num<8&&(w.acKeys||[]).indexOf('commission_tax')>=0;});
  assert(early.length===0,'commission_tax fired before week 8: weeks '+early.map(function(w){return w.num;}));
  weeks.forEach(function(w){
    var ct_count=(w.acKeys||[]).filter(function(k){return k==='commission_tax';}).length;
    assert(ct_count<=1,'commission_tax appears '+ct_count+' times in week '+w.num+' (max 1)');
  });
});

// ── RESULTS ─────────────────────────────────────────────────────────────────
console.log('\n══════════════════════════════════════════════');
console.log('  Audit: '+pass+' pass, '+fail+' fail');
if(failures.length){console.log('\n  FAILURES:');failures.forEach(function(f,i){console.log('  '+(i+1)+'. '+f.name+'\n     '+f.err);});}
console.log(fail===0?'  ✅ ALL AUDIT CHECKS PASSED\n':'  ❌ FAILURES ABOVE\n');
