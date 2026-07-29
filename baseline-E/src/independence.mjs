// baseline-E/src/independence.mjs
// rev-6.1 §2 (rev-2/rev-3) provenance-root independence + closed collapse set (T-c fail-closed default).
// An anchor carries: { category:'A'|'B'|'C', evidence_root:{source_system, source_record_digest, source_field,
//   derivation_method, canonical_value_digest}, canonical_value_digest, evidence_root_digest }.

export class IndependenceError extends Error {}

// Two A/B anchors collapse to ONE group iff any: (1) equal canonical_value_digest; (2) equal evidence_root_digest;
// (3) same source_record_digest AND same source_field; (4) one derivation_method references the other's
// evidence_root_digest; (5) cross-system replication of equal value w/o attested origination (= clause 1 default).
function refersTo(deriv, rootHex) {
  return typeof deriv === 'string' && (deriv === `copied_from:${rootHex}` || deriv === `transform_of:${rootHex}` || deriv === `parsed_from:${rootHex}`);
}
function collapses(a, b) {
  if (a.canonical_value_digest === b.canonical_value_digest) return true;                       // (1)/(5)
  if (a.evidence_root_digest === b.evidence_root_digest) return true;                           // (2)
  if (a.evidence_root.source_record_digest === b.evidence_root.source_record_digest &&
      a.evidence_root.source_field === b.evidence_root.source_field) return true;               // (3)
  if (refersTo(a.evidence_root.derivation_method, b.evidence_root_digest)) return true;          // (4)
  if (refersTo(b.evidence_root.derivation_method, a.evidence_root_digest)) return true;          // (4)
  return false;
}

// Returns distinct independence-group keys among A/B anchors (Category-C excluded), with per-anchor group id.
export function independenceGroups(anchors) {
  const ab = anchors.filter((x) => x.category === 'A' || x.category === 'B');
  const parent = ab.map((_, i) => i);
  const find = (i) => { while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; } return i; };
  const union = (i, j) => { const ri = find(i), rj = find(j); if (ri !== rj) parent[Math.max(ri, rj)] = Math.min(ri, rj); };
  for (let i = 0; i < ab.length; i++) for (let j = i + 1; j < ab.length; j++) if (collapses(ab[i], ab[j])) union(i, j);
  const groupOf = ab.map((_, i) => ab[find(i)].evidence_root_digest); // deterministic: lowest member's root
  const distinct = new Set(groupOf);
  return { ab, groupOf, distinctGroupCount: distinct.size, categoryAPresentPerGroup: groupOfHasA(ab, groupOf) };
}
function groupOfHasA(ab, groupOf) {
  const byGroup = new Map();
  ab.forEach((a, i) => { const g = groupOf[i]; byGroup.set(g, (byGroup.get(g) || false) || a.category === 'A'); });
  return byGroup; // group key → boolean (group contains a Category-A anchor)
}
