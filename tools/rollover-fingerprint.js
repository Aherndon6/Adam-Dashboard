'use strict';
// ════════════════════════════════════════════════════════════════════════════
// Rollover rollback / rehearsal comparison tooling (2027 rollover Package A).
// Pure functions over row data (JSON); performs no database access.
// Governing spec: docs/rollover-2027-spec.md frozen v2.1, §18 (RB-1..RB-4, OD-1), §7.4
// reversal, §16 step 15, and Gate 1 note NB-5 (checkpoint-C equivalence).
//
// TWO DIFFERENT COMPARISONS — never merge them:
//   1. §18 business-and-control fingerprint (rollback, RB-1..RB-4, 4a/4b, §7.4 reversal,
//      §16 step 15). Excludes ONLY the columns in OD1_EXCLUSIONS (goal_registry.updated_at).
//   2. NB-5 checkpoint-C equivalence (§16 step 11, re-established candidate vs checkpoint C).
//      Its generated-column exclusions are supplied explicitly per call and never feed (1).
// ════════════════════════════════════════════════════════════════════════════
const crypto = require('crypto');

// OD-1 (frozen v2.1 §18): the complete list. Adding a column requires proof that it is
// trigger-maintained and changes unavoidably under an authorized restoration, plus owner
// approval. Frozen so callers cannot extend it at runtime.
const OD1_EXCLUSIONS = Object.freeze({ goal_registry: Object.freeze(['updated_at']) });

function canonical(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v === undefined ? null : v);
  if (Array.isArray(v)) return '[' + v.map(canonical).join(',') + ']';
  return '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canonical(v[k])).join(',') + '}';
}
function sha256(s) { return crypto.createHash('sha256').update(s).digest('hex'); }

// §18 business-and-control fingerprint of one row.
function rowFingerprint(table, row) {
  const excl = OD1_EXCLUSIONS[table] || [];
  const business = {}, excluded = {};
  Object.keys(row).forEach(k => { if (excl.indexOf(k) >= 0) excluded[k] = row[k]; else business[k] = row[k]; });
  return { hash: sha256(canonical(business)), business, excluded };
}

// tables: { name: { pk: 'id', rows: [...] } } → { name: Map(key → fingerprint) }
function snapshot(tables) {
  const out = {};
  Object.keys(tables).forEach(t => {
    const pk = tables[t].pk || 'id';
    const m = new Map();
    tables[t].rows.forEach(r => {
      const key = String(r[pk]);
      if (m.has(key)) throw new Error('duplicate primary key ' + t + '.' + key);
      m.set(key, rowFingerprint(t, r));
    });
    out[t] = { pk, rows: m };
  });
  return out;
}

function _k(t, k) { return t + '|' + k; }

// Every changed excluded value, reported before and after (OD-1: never silently discarded).
function _excludedChanges(t, key, a, b) {
  const out = [];
  const cols = new Set(Object.keys(a ? a.excluded : {}).concat(Object.keys(b ? b.excluded : {})));
  cols.forEach(col => {
    const before = a ? a.excluded[col] : undefined, after = b ? b.excluded[col] : undefined;
    if (canonical(before) !== canonical(after)) out.push({ table: t, key, column: col, before, after });
  });
  return out;
}

// RB-2 (and §16 step 15 when manifestStatusChanges are supplied): compare a pre-deploy
// baseline with the current state by the §18 fingerprint.
//   householdHistory: [{table, key, kind:'inserted'|'updated'|'deleted'}] enumerated post-deploy
//     household history (RB-3); a row may differ only if it is listed here with the right kind.
//   manifestStatusChanges: [{table:'goal_registry', key, before, after}] status changes recorded
//     in the initialization manifest (§16 step 15(b)); the row may differ ONLY in `status`,
//     and its current status must equal the recorded `after`.
// Returns { pass, equal, household, manifestExpected, unexplained, excludedChanges }.
function compareBaseline(baseline, current, opts) {
  opts = opts || {};
  const hh = new Map((opts.householdHistory || []).map(h => [_k(h.table, String(h.key)), h.kind]));
  const ms = new Map((opts.manifestStatusChanges || []).map(m => [_k(m.table, String(m.key)), m]));
  const res = { equal: [], household: [], manifestExpected: [], unexplained: [], excludedChanges: [] };
  const tables = new Set(Object.keys(baseline).concat(Object.keys(current)));
  tables.forEach(t => {
    const A = baseline[t] ? baseline[t].rows : new Map(), B = current[t] ? current[t].rows : new Map();
    const keys = new Set([...A.keys(), ...B.keys()]);
    keys.forEach(key => {
      const a = A.get(key), b = B.get(key), id = _k(t, key);
      res.excludedChanges.push(..._excludedChanges(t, key, a, b));
      if (a && b && a.hash === b.hash) { res.equal.push(id); return; }
      const kind = !a ? 'inserted' : !b ? 'deleted' : 'updated';
      if (hh.get(id) === kind) { res.household.push({ id, kind }); return; }
      const m = ms.get(id);
      if (m && a && b && kind === 'updated') {
        const ab = Object.assign({}, a.business), bb = Object.assign({}, b.business);
        const statusOk = ab.status === m.before && bb.status === m.after;
        delete ab.status; delete bb.status;
        if (statusOk && canonical(ab) === canonical(bb)) { res.manifestExpected.push({ id, before: m.before, after: m.after }); return; }
      }
      res.unexplained.push({ id, kind });
    });
  });
  res.pass = res.unexplained.length === 0;
  return res;
}

// RB-1: the rollback transaction's write set equals exactly the manifest-reversal rows.
// reversalKeys: [{table, key}] rows the manifest reversal deletes or restores.
function compareWriteSet(preRollback, postRollback, reversalKeys) {
  const want = new Set(reversalKeys.map(r => _k(r.table, String(r.key))));
  const changed = new Set(), excludedChanges = [];
  const tables = new Set(Object.keys(preRollback).concat(Object.keys(postRollback)));
  tables.forEach(t => {
    const A = preRollback[t] ? preRollback[t].rows : new Map(), B = postRollback[t] ? postRollback[t].rows : new Map();
    new Set([...A.keys(), ...B.keys()]).forEach(key => {
      const a = A.get(key), b = B.get(key);
      excludedChanges.push(..._excludedChanges(t, key, a, b));
      if (!a || !b || a.hash !== b.hash) changed.add(_k(t, key));
    });
  });
  const unexpected = [...changed].filter(k => !want.has(k));
  const missing = [...want].filter(k => !changed.has(k));
  return { pass: unexpected.length === 0 && missing.length === 0, changed: [...changed], unexpected, missing, excludedChanges };
}

// NB-5 — checkpoint-C staging equivalence (§16 step 11). A DIFFERENT comparison: rows
// re-inserted by re-running the rollout/initialization get newly generated values (e.g.
// created_at, uuid ids). The caller must list those generated columns explicitly, per table;
// rows are matched by the supplied natural key, not by a generated id. Never used for RB-1..4.
function compareCheckpoint(checkpointRows, currentRows, spec) {
  if (!spec || !spec.generatedColumns || typeof spec.generatedColumns !== 'object') throw new Error('compareCheckpoint: explicit generatedColumns required (NB-5)');
  if (!spec.naturalKey || typeof spec.naturalKey !== 'object') throw new Error('compareCheckpoint: explicit naturalKey per table required');
  const diffs = [];
  Object.keys(spec.naturalKey).forEach(t => {
    const gen = spec.generatedColumns[t] || [];
    const nk = spec.naturalKey[t];
    const strip = r => { const o = {}; Object.keys(r).forEach(k => { if (gen.indexOf(k) < 0) o[k] = r[k]; }); return o; };
    const keyOf = r => nk.map(c => canonical(r[c])).join('|');
    const A = new Map((checkpointRows[t] || []).map(r => [keyOf(r), canonical(strip(r))]));
    const B = new Map((currentRows[t] || []).map(r => [keyOf(r), canonical(strip(r))]));
    new Set([...A.keys(), ...B.keys()]).forEach(k => { if (A.get(k) !== B.get(k)) diffs.push({ table: t, key: k, checkpoint: A.has(k), current: B.has(k) }); });
  });
  return { pass: diffs.length === 0, diffs, generatedColumns: spec.generatedColumns };
}

module.exports = { OD1_EXCLUSIONS, canonical, rowFingerprint, snapshot, compareBaseline, compareWriteSet, compareCheckpoint };
