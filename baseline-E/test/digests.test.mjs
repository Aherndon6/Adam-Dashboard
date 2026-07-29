// T-a NORMATIVE conformance vectors (rev-6.1 §1) + version enforcement + component-state + graph_identity.
// Independence: expected digests are derived by an INDEPENDENT in-test preimage builder (NOT importing
// src/framing) and cross-checked against python3-hashlib oracles computed outside this process. The
// implementation-under-test never blesses its own oracle.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { canonicalValueDigest, anchorEvidenceDigest, evidenceRootDigest, edgeDigestV3, VERSIONS, DOMAINS } from '../src/digests.mjs';

// ── Independent framing (hand-written; shares no code with src/framing.mjs) ──────────────────────────
const u32be = (n) => { const b = Buffer.alloc(4); b.writeUInt32BE(n, 0); return b; };
const lp = (x) => { const b = Buffer.isBuffer(x) ? x : Buffer.from(String(x), 'utf8'); return Buffer.concat([u32be(b.length), b]); };
const sha = (parts) => createHash('sha256').update(Buffer.concat(parts)).digest('hex');
const dom = (s) => Buffer.from(s, 'utf8');

// python3-hashlib oracles (computed OUT of process; see implementation report §6)
const ORACLE = {
  cvd_ABC123: 'cd3accb68225721c823e5b0e2159f0de4df13c87db23ca98684f715754d9d732',
  cvd_nfc_eacute: '47ec75ff1f074489a02f909b3ca97da8677fd40ba69aebc5c9cea3b688585781',
  aed_fixture: 'ad8890463bceda89ba4da4fe321b8020665e6579da2c745e6674d39b253f9766',
  erd_fixture: 'f7bbd6e0360e7550898e6087327ef3fe7f64d06a4f9c0eff10c6cf7067aa3605',
};

test('T-a canonical_value_digest — ASCII vector: impl == independent preimage == python oracle', () => {
  const canon = Buffer.from('ABC123', 'utf8');
  const independent = sha([dom(DOMAINS.CANONICAL_VALUE), u32be(canon.length), canon]);
  assert.equal(independent, ORACLE.cvd_ABC123);            // independent builder == external python oracle
  assert.equal(canonicalValueDigest(canon), independent);  // implementation-under-test conforms
});

test('T-a canonical_value_digest — NFC-sensitive non-ASCII vector (N-6): decomposed ≡ precomposed', () => {
  const precomposed = 'é'.normalize('NFC');
  const decomposed = 'é'.normalize('NFC');           // e + COMBINING ACUTE → NFC 'é'
  const b = Buffer.from(precomposed, 'utf8');
  const independent = sha([dom(DOMAINS.CANONICAL_VALUE), u32be(b.length), b]);
  assert.equal(independent, ORACLE.cvd_nfc_eacute);
  assert.equal(canonicalValueDigest(Buffer.from(precomposed, 'utf8')), ORACLE.cvd_nfc_eacute);
  assert.equal(canonicalValueDigest(Buffer.from(decomposed, 'utf8')), ORACLE.cvd_nfc_eacute); // NFC-equivalent → same digest
});

test('T-a anchor_evidence_digest + evidence_root_digest vectors conform to independent oracles', () => {
  const cvd = ORACLE.cvd_ABC123;
  const aed = anchorEvidenceDigest({ anchor_type: 'bank_reference', category: 'A', source_system: 'truist', source_field: 'memo_ref', canonical_value_digest_hex: cvd, canonicalization_version: 'canon-v1' });
  assert.equal(aed, ORACLE.aed_fixture);
  const rec = 'a'.repeat(64);
  const erd = evidenceRootDigest({ source_system: 'truist', source_record_digest: rec, source_field: 'memo_ref', derivation_method: 'direct_read', canonical_value_digest_hex: cvd, anchor_evidence_digest_hex: aed, provenance_version: 'prov-v1' });
  assert.equal(erd, ORACLE.erd_fixture);
});

// ── edge_digest v3 conformance + B-1 exclusion proof (rev-6.1 §1 / editorial §4) ─────────────────────
const baseEdge = () => ({
  bank_transaction_id: 'btx1', bank_transaction_content_digest: 'b'.repeat(64),
  event_id: 'ev1', event_content_digest: 'c'.repeat(64),
  allocated_amount_cents: 4000, edge_direction: 'credit',
  reflected_component_id: 'ev1#refl', reflected_component_content_digest: 'd'.repeat(64),
  reflected_component_amount_cents: 4000, reflected_component_state: 'reflected_terminal', reflected_direction: 'credit',
  remaining_forward_component_id: 'ev1#rem', remaining_forward_component_content_digest: 'e'.repeat(64),
  remaining_forward_component_amount_cents: 0, remaining_forward_component_state: 'zero_terminal_remainder',
  original_event_amount_cents: 4000, evidence_root_digests: ['1'.repeat(64), '2'.repeat(64)],
});

function independentEdgeDigest(e) {
  const roots = [...e.evidence_root_digests].sort();
  const parts = [
    dom(DOMAINS.EDGE), lp('v3'), lp(e.bank_transaction_id), lp(e.bank_transaction_content_digest),
    lp(e.event_id), lp(e.event_content_digest), lp(String(e.allocated_amount_cents)), lp(e.edge_direction),
    lp(e.reflected_component_id), lp(e.reflected_component_content_digest), lp(String(e.reflected_component_amount_cents)),
    lp(e.reflected_component_state), lp(e.reflected_direction),
    lp(e.remaining_forward_component_id), lp(e.remaining_forward_component_content_digest), lp(String(e.remaining_forward_component_amount_cents)),
    lp(e.remaining_forward_component_state), lp(String(e.original_event_amount_cents)),
    u32be(roots.length), ...roots.map(lp),
  ];
  return sha(parts);
}

test('T-a edge_digest v3 — impl == independent preimage builder', () => {
  const e = baseEdge();
  assert.equal(edgeDigestV3(e), independentEdgeDigest(e));
  assert.equal(VERSIONS.edge_schema_version, 'v3');
  assert.equal(DOMAINS.EDGE, 'BASELINE-E:ALLOCATION-EDGE:v3');
});

test('T-a edge preimage EXCLUDES authority/graph (B-1): changing an edge-local field changes the digest', () => {
  const e = baseEdge();
  const d0 = edgeDigestV3(e);
  const d1 = edgeDigestV3({ ...e, allocated_amount_cents: 4001, reflected_component_amount_cents: 4001, original_event_amount_cents: 4001 });
  assert.notEqual(d0, d1);
  // attaching arbitrary authority/graph fields to the edge object must NOT affect the edge digest (excluded)
  const d2 = edgeDigestV3({ ...e, allocation_authority_digest: 'f'.repeat(64), allocation_graph_digest: '0'.repeat(64), authority_kind: 'owner' });
  assert.equal(d0, d2);
});

test('§17 v2-as-v3 rejection: a v2-domain edge digest can never equal the v3 digest', () => {
  const e = baseEdge();
  const roots = [...e.evidence_root_digests].sort();
  const v2parts = [dom('BASELINE-E:ALLOCATION-EDGE:v2'), lp('v2'), lp(e.bank_transaction_id)]; // wrong domain+version
  const v2 = sha(v2parts);
  assert.notEqual(v2, edgeDigestV3(e));
});

test('component-state twins: zero remaining must be zero_terminal_remainder; bad state ⇒ throw', () => {
  const e = baseEdge();
  assert.throws(() => edgeDigestV3({ ...e, remaining_forward_component_state: 'mystery' }));
  assert.throws(() => edgeDigestV3({ ...e, allocated_amount_cents: 0 }));               // T-h boundary (≥1)
  assert.throws(() => edgeDigestV3({ ...e, evidence_root_digests: [] }));               // T-g (≥1 evidence root)
  assert.throws(() => edgeDigestV3({ ...e, evidence_root_digests: ['1'.repeat(64), '1'.repeat(64)] })); // T-e duplicate
});
