#!/usr/bin/env node
'use strict';
// ════════════════════════════════════════════════════════════════════════════
// Rollover contract-registry completion check (2027 rollover Package A, owner A-1).
// One fail-closed rule over fixtures/rollover/contract-registry.json:
//   a package is COMPLETE only if no entry it owns is PENDING, and every ACTIVE entry it
//   owns resolves to an existing test (impl = "<file>#<TEST-ID>", TEST-ID present in file).
// Unknown package identifiers fail closed.
//
// CLI (each package's completion gate):  node tools/rollover-contracts.js complete <PKG>
//   exit 0 = COMPLETE; exit 1 = NOT COMPLETE (lists every PENDING / unresolved entry).
// ════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const REGISTRY_PATH = path.join(REPO, 'fixtures', 'rollover', 'contract-registry.json');

function loadRegistry(p) { return JSON.parse(fs.readFileSync(p || REGISTRY_PATH, 'utf8')); }

// resolveImpl(impl) → true only if the referenced file exists and DEFINES the target:
// a .js file must contain a test definition `test('<ID> ` / `testAsync('<ID> ` (a mere mention
// in a comment or string does not count); a .md file must contain a heading with the text.
function defaultResolveImpl(impl) {
  if (typeof impl !== 'string' || impl.indexOf('#') < 1) return false;
  const i = impl.indexOf('#'), file = impl.slice(0, i), id = impl.slice(i + 1);
  const fp = path.join(REPO, file);
  if (!id || !fs.existsSync(fp)) return false;
  const src = fs.readFileSync(fp, 'utf8');
  const esc = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (/\.js$/.test(file)) return new RegExp('\\b(test|testAsync)\\((\'|")' + esc + '[ \'"]').test(src);
  if (/\.md$/.test(file)) return new RegExp('^#{1,6} .*' + esc, 'm').test(src);
  return false;
}

function packageCompletion(registry, pkg, resolveImpl) {
  resolveImpl = resolveImpl || defaultResolveImpl;
  const known = Object.keys((registry && registry._meta && registry._meta.packages) || {});
  if (known.indexOf(pkg) < 0) throw new Error('unknown package "' + pkg + '" (known: ' + known.join(', ') + ')');
  const owned = registry.entries.filter(e => e.package === pkg);
  const pending = owned.filter(e => e.status !== 'ACTIVE').map(e => e.id);
  const unresolved = owned.filter(e => e.status === 'ACTIVE' && !resolveImpl(e.impl)).map(e => e.id);
  return { package: pkg, complete: pending.length === 0 && unresolved.length === 0, owned: owned.length, pending, unresolved };
}

module.exports = { REGISTRY_PATH, loadRegistry, packageCompletion, defaultResolveImpl };

if (require.main === module) {
  const [cmd, pkg] = process.argv.slice(2);
  if (cmd !== 'complete' || !pkg) { console.error('usage: node tools/rollover-contracts.js complete <PKG>'); process.exit(2); }
  let r;
  try { r = packageCompletion(loadRegistry(), pkg); } catch (e) { console.error('NOT COMPLETE: ' + e.message); process.exit(1); }
  console.log((r.complete ? 'COMPLETE' : 'NOT COMPLETE') + ': package ' + pkg + ' owns ' + r.owned + ' contract(s); pending ' + r.pending.length + ', unresolved ' + r.unresolved.length);
  r.pending.forEach(id => console.log('  PENDING ' + id));
  r.unresolved.forEach(id => console.log('  UNRESOLVED ACTIVE ' + id));
  process.exit(r.complete ? 0 : 1);
}
