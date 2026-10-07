#!/usr/bin/env node
'use strict';
// ════════════════════════════════════════════════════════════════════════════
// Server function-definition evidence tooling (2027 rollover Package A).
// Builds and compares captures of authoritative function definitions so a later gate can
// prove that restored bodies equal the pre-deploy bodies byte for byte (§18 (c) rollback,
// Gate 1 finding: prod wrapper/Option B/repair bodies have no committed md5 pins).
//
// THIS TOOL NEVER CONNECTS TO A DATABASE. It consumes the JSON rows produced by running
// CAPTURE_QUERY under a separately authorized gate, and is tested here against fixtures only.
//
// Also: checkHelperRevokes (Gate 1 note N-9) — a static check that each new helper function
// created by a server package explicitly revokes EXECUTE from PUBLIC, anon and authenticated.
//
// CLI:  node tools/rollover-function-capture.js build <rows.json> <label> > capture.json
//       node tools/rollover-function-capture.js compare <a.json> <b.json>
//       node tools/rollover-function-capture.js revokes <file.sql> <helper> [<helper> ...]
// ════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const crypto = require('crypto');

// Read-only catalog query (text only; executed only under a later, owner-authorized gate).
const CAPTURE_QUERY = [
  'SELECT p.oid::regprocedure::text AS signature,',
  '       pg_get_functiondef(p.oid)  AS definition,',
  '       p.prosecdef                AS security_definer,',
  '       p.proconfig                AS config,',
  '       pg_get_userbyid(p.proowner) AS owner,',
  '       p.proacl::text             AS acl',
  '  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace',
  " WHERE n.nspname = 'public' AND p.proname = ANY($1)",
  ' ORDER BY 1;',
].join('\n');

const sha = s => crypto.createHash('sha256').update(String(s)).digest('hex');

function buildCapture(rows, meta) {
  if (!Array.isArray(rows) || !rows.length) throw new Error('buildCapture: rows required');
  const seen = new Set();
  const functions = rows.map(r => {
    if (!r.signature || typeof r.definition !== 'string') throw new Error('buildCapture: each row needs signature and definition');
    if (seen.has(r.signature)) throw new Error('buildCapture: duplicate signature ' + r.signature);
    seen.add(r.signature);
    return {
      signature: r.signature,
      definition_sha256: sha(r.definition),
      definition: r.definition,
      security_definer: r.security_definer === true,
      config: r.config == null ? null : [].concat(r.config),
      owner: r.owner == null ? null : String(r.owner),
      acl: r.acl == null ? null : String(r.acl),
    };
  }).sort((a, b) => (a.signature < b.signature ? -1 : a.signature > b.signature ? 1 : 0));
  const body = functions.map(f => [f.signature, f.definition_sha256, f.security_definer, JSON.stringify(f.config), f.owner, f.acl].join('\t')).join('\n');
  return { label: (meta && meta.label) || null, captured_at: (meta && meta.capturedAt) || null, query_sha256: sha(CAPTURE_QUERY), manifest_sha256: sha(body), functions };
}

// Exact comparison: a restored body must equal the captured body byte for byte, with the
// same security-definer flag, config (search_path), owner and ACL.
function compareCaptures(a, b) {
  const A = new Map(a.functions.map(f => [f.signature, f])), B = new Map(b.functions.map(f => [f.signature, f]));
  const diffs = [];
  new Set([...A.keys(), ...B.keys()]).forEach(sig => {
    const x = A.get(sig), y = B.get(sig);
    if (!x || !y) { diffs.push({ signature: sig, field: x ? 'missing_in_b' : 'missing_in_a' }); return; }
    if (x.definition_sha256 !== sha(x.definition) || y.definition_sha256 !== sha(y.definition)) diffs.push({ signature: sig, field: 'definition_sha256_tampered' });
    ['definition_sha256', 'security_definer', 'owner', 'acl'].forEach(k => { if (x[k] !== y[k]) diffs.push({ signature: sig, field: k }); });
    if (JSON.stringify(x.config) !== JSON.stringify(y.config)) diffs.push({ signature: sig, field: 'config' });
  });
  return { identical: diffs.length === 0, diffs };
}

// N-9: for each helper, the SQL must CREATE it and explicitly REVOKE EXECUTE from PUBLIC,
// anon and authenticated, and must not GRANT EXECUTE on it to anon or authenticated.
function checkHelperRevokes(sqlText, helperNames) {
  const sql = String(sqlText).replace(/--[^\n]*/g, ' ');
  return helperNames.map(name => {
    const n = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const created = new RegExp('CREATE\\s+(OR\\s+REPLACE\\s+)?FUNCTION\\s+(public\\.)?' + n + '\\s*\\(', 'i').test(sql);
    const revokeRe = new RegExp('REVOKE\\s+(ALL|EXECUTE)\\s+ON\\s+FUNCTION\\s+(public\\.)?' + n + '\\s*\\([^)]*\\)\\s+FROM\\s+([^;]+);', 'ig');
    const revoked = new Set();
    let m;
    while ((m = revokeRe.exec(sql))) m[3].split(',').map(s => s.trim().toLowerCase()).forEach(r => revoked.add(r));
    const grantRe = new RegExp('GRANT\\s+(ALL|EXECUTE)\\s+ON\\s+FUNCTION\\s+(public\\.)?' + n + '\\s*\\([^)]*\\)\\s+TO\\s+([^;]+);', 'ig');
    const grantedTo = new Set();
    while ((m = grantRe.exec(sql))) m[3].split(',').map(s => s.trim().toLowerCase()).forEach(r => grantedTo.add(r));
    const missing = ['public', 'anon', 'authenticated'].filter(r => !revoked.has(r));
    const badGrants = ['anon', 'authenticated', 'public'].filter(r => grantedTo.has(r));
    return { helper: name, created, missingRevokes: missing, clientGrants: badGrants, pass: created && missing.length === 0 && badGrants.length === 0 };
  });
}

module.exports = { CAPTURE_QUERY, buildCapture, compareCaptures, checkHelperRevokes };

if (require.main === module) {
  const [cmd, ...args] = process.argv.slice(2);
  const readJson = p => JSON.parse(fs.readFileSync(p, 'utf8'));
  if (cmd === 'build') {
    process.stdout.write(JSON.stringify(buildCapture(readJson(args[0]), { label: args[1] || null }), null, 2) + '\n');
  } else if (cmd === 'compare') {
    const r = compareCaptures(readJson(args[0]), readJson(args[1]));
    console.log(JSON.stringify(r, null, 2)); process.exit(r.identical ? 0 : 1);
  } else if (cmd === 'revokes') {
    const r = checkHelperRevokes(fs.readFileSync(args[0], 'utf8'), args.slice(1));
    console.log(JSON.stringify(r, null, 2)); process.exit(r.every(x => x.pass) ? 0 : 1);
  } else {
    console.error('usage: build <rows.json> <label> | compare <a.json> <b.json> | revokes <file.sql> <helper...>');
    process.exit(2);
  }
}
