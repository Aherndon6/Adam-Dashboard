// baseline-E/src/digests.mjs
// rev-6.1 §1/§6/§8 digest suite. Byte-for-byte per the pinned preimages. Version-enforced.
import { lp, u32be, int2dec, digest, assertHex64, sortedUniqueHexOrThrow, NULL_SENTINEL, FramingError } from './framing.mjs';

// ── Pinned version constants (rev-6.1 §1/§6; immutable this generation) ──────────────────────────────
export const VERSIONS = Object.freeze({
  edge_schema_version: 'v3',
  graph_schema_version: 'v3',
  authority_schema_version: 'v1',
  canonicalization_version: 'canon-v1',
  provenance_version: 'prov-v1',
  candidate_generation_version: 'candgen-v1',
  component_schema_version: 'component-v1',
  framing_version: 'framing-v1',
  routing_rule_version: 'routing-v1',
  subject_id_format_version: 'subjid-v1a',
  coverage_policy_version: 'coverage-v1',
});
export const DOMAINS = Object.freeze({
  CANONICAL_VALUE: 'BASELINE-E:CANONICAL-VALUE:v1',
  ANCHOR_EVIDENCE: 'BASELINE-E:ANCHOR-EVIDENCE:v1',
  EVIDENCE_ROOT: 'BASELINE-E:EVIDENCE-ROOT:v1',
  EDGE: 'BASELINE-E:ALLOCATION-EDGE:v3',
  GRAPH: 'BASELINE-E:ALLOCATION-GRAPH:v3',
  AUTHORITY: 'BASELINE-E:ALLOCATION-AUTHORITY:v1',
  GRAPH_IDENTITY: 'BASELINE-E:GRAPH-IDENTITY:v1',
});
export const COMPONENT_STATES = Object.freeze(['partial_reflected', 'reflected_terminal', 'active_remainder', 'zero_terminal_remainder']);

// ── canonical_value_digest (rev-6.1 §1 / rev-3): value only, no anchor/source/provenance ─────────────
export function canonicalValueDigest(canonicalValueBytes) {
  const b = Buffer.isBuffer(canonicalValueBytes) ? canonicalValueBytes : Buffer.from(String(canonicalValueBytes), 'utf8');
  return digest(DOMAINS.CANONICAL_VALUE, [u32be(b.length), b]);
}

// ── anchor_evidence_digest: value×role×source; never used for independence ───────────────────────────
export function anchorEvidenceDigest({ anchor_type, category, source_system, source_field, canonical_value_digest_hex, canonicalization_version }) {
  assertHex64(canonical_value_digest_hex, 'canonical_value_digest');
  return digest(DOMAINS.ANCHOR_EVIDENCE, [
    lp(anchor_type), lp(category), lp(source_system), lp(source_field),
    lp(canonical_value_digest_hex), lp(canonicalization_version),
  ]);
}

// ── evidence_root_digest: provenance-root identity (independence, references, edge binding) ───────────
export function evidenceRootDigest({ source_system, source_record_digest, source_field, derivation_method, canonical_value_digest_hex, anchor_evidence_digest_hex, provenance_version }) {
  assertHex64(canonical_value_digest_hex, 'canonical_value_digest');
  assertHex64(anchor_evidence_digest_hex, 'anchor_evidence_digest');
  return digest(DOMAINS.EVIDENCE_ROOT, [
    lp(source_system), lp(source_record_digest), lp(source_field), lp(derivation_method),
    lp(canonical_value_digest_hex), lp(anchor_evidence_digest_hex), lp(provenance_version),
  ]);
}

function orNull(x) { return (x === null || x === undefined) ? NULL_SENTINEL : String(x); }

// ── allocation edge digest v3 (rev-6.1 §1) — edge-local only; NO authority/graph fields ──────────────
export function edgeDigestV3(e) {
  if (!Number.isInteger(e.allocated_amount_cents) || e.allocated_amount_cents < 1) throw new FramingError('edge: allocated_amount_cents must be integer ≥ 1 (rev-6.1 §5)');
  if (!Number.isInteger(e.remaining_forward_component_amount_cents) || e.remaining_forward_component_amount_cents < 0) throw new FramingError('edge: remaining ≥ 0 required (rev-6.1 §2/T-b)');
  if (!Number.isInteger(e.reflected_component_amount_cents) || e.reflected_component_amount_cents < 0) throw new FramingError('edge: reflected ≥ 0 required');
  if (!COMPONENT_STATES.includes(e.reflected_component_state) || !COMPONENT_STATES.includes(e.remaining_forward_component_state)) throw new FramingError('edge: bad component_state (rev-6.1 §2)');
  const roots = sortedUniqueHexOrThrow(e.evidence_root_digests || [], 'evidence_root_digests'); // duplicate ⇒ FAIL-STOP (T-e)
  if (roots.length < 1) throw new FramingError('edge: ≥1 evidence_root_digest required (rev-6.1 §4/T-g)');
  const parts = [
    lp(VERSIONS.edge_schema_version),
    lp(e.bank_transaction_id), lp(assertHex64(e.bank_transaction_content_digest, 'bank_txn_digest')),
    lp(e.event_id), lp(assertHex64(e.event_content_digest, 'event_digest')),
    lp(int2dec(e.allocated_amount_cents)), lp(e.edge_direction),
    lp(e.reflected_component_id), lp(assertHex64(e.reflected_component_content_digest, 'reflected_digest')),
    lp(int2dec(e.reflected_component_amount_cents)), lp(e.reflected_component_state), lp(e.reflected_direction),
    lp(e.remaining_forward_component_id), lp(assertHex64(e.remaining_forward_component_content_digest, 'remaining_digest')),
    lp(int2dec(e.remaining_forward_component_amount_cents)), lp(e.remaining_forward_component_state),
    lp(int2dec(e.original_event_amount_cents)),
    u32be(roots.length), ...roots.map((r) => lp(r)),
  ];
  return digest(DOMAINS.EDGE, parts);
}

// ── graph_identity (rev-6.1 §8) — content-derived; validates the tagged gen/adjudication id ───────────
const GEN_ADJ_RE = /^(generation|adjudication):[0-9a-f]{64}$/;
export function validateGenAdjOrNull(v) {
  if (v === null || v === undefined) return NULL_SENTINEL;
  if (typeof v !== 'string' || !GEN_ADJ_RE.test(v)) throw new FramingError(`graph_identity gen/adjudication id malformed ("${v}") (rev-6.1 §2)`);
  return v;
}
export function graphIdentity(g) {
  const pairs = (g.events || []).map((ev) => [ev.event_id, assertHex64(ev.event_content_digest, 'event_digest')]);
  pairs.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : (a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0)));
  const parts = [
    lp(VERSIONS.graph_schema_version),
    lp(g.bank_transaction_id), lp(assertHex64(g.bank_transaction_content_digest, 'bank_txn_digest')),
    lp(g.graph_direction),
    u32be(pairs.length), ...pairs.flatMap(([id, dg]) => [lp(id), lp(dg)]),
    lp(validateGenAdjOrNull(g.allocation_generation_or_adjudication_id)),
  ];
  return digest(DOMAINS.GRAPH_IDENTITY, parts);
}

// ── allocation graph digest v3 (rev-6.1 §1/§2) ───────────────────────────────────────────────────────
export function graphDigestV3(g) {
  const edges = sortedUniqueHexOrThrow(g.edge_digests || [], 'edge_digests'); // duplicate edge ⇒ FAIL-STOP
  const parts = [
    lp(VERSIONS.graph_schema_version),
    lp(assertHex64(g.graph_identity, 'graph_identity')),
    lp(assertHex64(g.bank_transaction_content_digest, 'bank_txn_digest')),
    lp(g.graph_direction),
    lp(int2dec(g.bank_posted_amount_cents)), lp(int2dec(g.total_allocated_amount_cents)),
    lp(g.graph_conservation_state),
    u32be(edges.length), ...edges.map((e) => lp(e)),
  ];
  return digest(DOMAINS.GRAPH, parts);
}

// ── allocation authority digest v1 (rev-6.1 §1; graph-scoped, not per-edge) ──────────────────────────
export function authorityDigestV1(a) {
  const rec = (a.authority_kind === 'authoritative_record')
    ? assertHex64(a.authority_record_digest, 'authority_record_digest') : orNull(a.authority_record_digest);
  return digest(DOMAINS.AUTHORITY, [
    lp(VERSIONS.authority_schema_version), lp(a.authority_kind), lp(a.subject_or_role_id),
    lp(rec), lp(a.approved_at_ts_utc), lp(assertHex64(a.allocation_graph_digest, 'allocation_graph_digest')),
  ]);
}
