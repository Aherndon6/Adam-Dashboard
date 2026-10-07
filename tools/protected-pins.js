#!/usr/bin/env node
'use strict';
// ════════════════════════════════════════════════════════════════════════════
// Protected-function pin recompute (2027 rollover Package A, requirement J).
// Same method as the release preflights and test_a1b.js fnSrc: full sha256 of the
// brace-matched source starting at `function NAME(` (string- and //-comment-aware).
//
// CLI: node tools/protected-pins.js <baseline.txt> [index.html]
//   baseline format: "<sha256>  <name>" per line; '#' lines ignored.
//   Exit 0 only if every baseline function is present and its pin matches.
// ════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const crypto = require('crypto');

function fnSrc(html, name) {
  const tok = 'function ' + name + '(';
  const i = html.indexOf(tok); if (i < 0) return null;
  let j = html.indexOf('{', i), d = 0, k = j, q = null;
  for (; k < html.length; k++) {
    const ch = html[k];
    if (q) { if (ch === '\\') { k++; continue; } if (ch === q) q = null; continue; }
    if (ch === '/' && html[k + 1] === '/') { k = html.indexOf('\n', k); continue; }
    if (ch === "'" || ch === '"' || ch === '`') { q = ch; continue; }
    if (ch === '{') d++; else if (ch === '}') { d--; if (d === 0) break; }
  }
  return html.slice(i, k + 1);
}
function pin(html, name) { const s = fnSrc(html, name); return s === null ? null : crypto.createHash('sha256').update(s).digest('hex'); }

function readBaseline(text) {
  return text.split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('#')).map(l => {
    const m = l.match(/^([0-9a-f]{64})\s+(\S+)$/); if (!m) throw new Error('bad baseline line: ' + l);
    return { sha: m[1], name: m[2] };
  });
}

function verify(html, baseline) {
  const rows = baseline.map(b => { const p = pin(html, b.name); return { name: b.name, expected: b.sha, actual: p, ok: p === b.sha }; });
  return { pass: rows.every(r => r.ok), count: rows.length, mismatched: rows.filter(r => !r.ok), rows };
}

module.exports = { fnSrc, pin, readBaseline, verify };

if (require.main === module) {
  const [baselinePath, indexPath] = process.argv.slice(2);
  if (!baselinePath) { console.error('usage: node tools/protected-pins.js <baseline.txt> [index.html]'); process.exit(2); }
  const html = fs.readFileSync(indexPath || 'index.html', 'utf8');
  const r = verify(html, readBaseline(fs.readFileSync(baselinePath, 'utf8')));
  console.log((r.pass ? 'PASS' : 'FAIL') + ' ' + (r.count - r.mismatched.length) + '/' + r.count + ' protected pins match');
  r.mismatched.forEach(m => console.log('  MISMATCH ' + m.name + ' expected ' + m.expected + ' actual ' + (m.actual || 'MISSING')));
  process.exit(r.pass ? 0 : 1);
}
