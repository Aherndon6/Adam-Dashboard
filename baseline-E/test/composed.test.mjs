// Composed end-to-end flows (owner-required): recall→classify, coverage→classify, A-with-all-gates,
// acceptGraph-G, canonReference→canonicalValueDigest.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateCandidates } from '../src/candgen.mjs';
import { classify } from '../src/match.mjs';
import { coverageSufficient } from '../src/coverage.mjs';
import { acceptGraph } from '../src/allocation-g.mjs';
import { canonReference } from '../src/canon.mjs';
import { canonicalValueDigest } from '../src/digests.mjs';
import { edgeDigestV3, graphIdentity, graphDigestV3, authorityDigestV1 } from '../src/digests.mjs';

const hx = (n) => n.toString(16).padStart(64, '0');
const bank = { amount_cents: 5000, direction: 'credit', bank_transaction_id: 't1', posted_at: '2026-07-01T12:00:00Z', description: '' };
const A = (t, s) => ({ type: t, canonical_value_digest: hx(1000 + s), anchor_evidence_digest: hx(2000 + s), evidence_root_digest: hx(3000 + s), evidence_root: { source_system: 's' + s, source_record_digest: hx(4000 + s), source_field: 'f', derivation_method: 'direct_read' } });

test('flow 1: generateCandidates (empty) → classify ⇒ E', () => {
  const { candidates, exhaustive } = generateCandidates({ bankTxn: bank, events: [] });
  const r = classify({ bankTxn: bank, candidates, coverageContext: { endpoint_ok: true, candgen_valid: true, candidates_exhaustive: exhaustive, coverage_sufficient: true } });
  assert.equal(r.disposition, 'E');
});
test('flow 2: coverageSufficient → classify ⇒ COVERAGE-HOLD when insufficient', () => {
  const cov = coverageSufficient({ measurement_start_week: 25, coverage_horizon_end_week: 31, scheduleEvents: [{ model_week: 26, kind: 'payroll_inflow', occurrence_id: 'p1' }] });
  const r = classify({ bankTxn: bank, candidates: [], coverageContext: { endpoint_ok: true, candgen_valid: true, candidates_exhaustive: true, coverage_sufficient: cov.coverage_sufficient } });
  assert.equal(r.disposition, 'COVERAGE-HOLD');
});
test('flow 3: classify A with all global gates valid', () => {
  const r = classify({ bankTxn: bank, candidates: [{ event_id: 'e1', event: { amount_cents: 5000, direction: 'credit' }, anchors: [A('bank_reference', 1), A('source_system_identity', 2)] }], coverageContext: { endpoint_ok: true, candgen_valid: true, candidates_exhaustive: true, coverage_sufficient: true } });
  assert.equal(r.disposition, 'A');
});
test('flow 4: acceptGraph G with reconciled identity + valid authority', () => {
  const anchors = (s) => [A('bank_reference', s), A('source_system_identity', s + 1)];
  const mk = (id, s) => ({ bank_transaction_id: 't1', bank_transaction_content_digest: hx(1), event_id: id, event_content_digest: hx(s + 100), allocated_amount_cents: 5000, edge_direction: 'credit', reflected_component_id: id + '#r', reflected_component_content_digest: hx(s + 200), reflected_component_amount_cents: 5000, reflected_component_state: 'reflected_terminal', reflected_direction: 'credit', remaining_forward_component_id: id + '#m', remaining_forward_component_content_digest: hx(s + 300), remaining_forward_component_amount_cents: 0, remaining_forward_component_state: 'zero_terminal_remainder', original_event_amount_cents: 5000, evidence_root_digests: [hx(s), hx(s + 1)], anchors: anchors(s) });
  const edges = [mk('e1', 10), mk('e2', 20)];
  const gi_events = edges.map((e) => ({ event_id: e.event_id, event_content_digest: e.event_content_digest }));
  const eds = edges.map(edgeDigestV3).sort();
  const gi = graphIdentity({ bank_transaction_id: 't1', bank_transaction_content_digest: hx(1), graph_direction: 'credit', events: gi_events, allocation_generation_or_adjudication_id: null });
  const gd = graphDigestV3({ graph_identity: gi, bank_transaction_content_digest: hx(1), graph_direction: 'credit', bank_posted_amount_cents: 10000, total_allocated_amount_cents: 10000, graph_conservation_state: 'balanced', edge_digests: eds });
  const V4 = 'user:2e6f8777-94c8-420e-aa20-c0c481d7ce5a';
  const ad = authorityDigestV1({ authority_kind: 'owner', subject_or_role_id: V4, authority_record_digest: null, approved_at_ts_utc: '2026-07-29T12:00:00.000Z', allocation_graph_digest: gd });
  edges.forEach((e) => { e.presented_edge_digest = edgeDigestV3(e); });
  const r = acceptGraph({ bankTxn: { bank_transaction_id: 't1', bank_transaction_content_digest: hx(1), direction: 'credit', amount_cents: 10000 }, graph: { graph_identity_events: gi_events, graph_direction: 'credit', allocation_generation_or_adjudication_id: null, presented: { graph_identity: gi, allocation_graph_digest: gd, total_allocated_amount_cents: 10000, allocation_complete: true } }, edges, authority: { authority_kind: 'owner', subject_or_role_id: V4, authority_record_digest: null, approved_at_ts_utc: '2026-07-29T12:00:00.000Z', bound_graph_digest: gd, presented: { allocation_authority_digest: ad } }, retainedScheduleMutations: edges.map((e) => ({ event_id: e.event_id, amount_cents: 5000 })) });
  assert.equal(r.disposition, 'G');
});
test('flow 5: canonReference NFC/trim → canonicalValueDigest matches independent ASCII oracle', () => {
  assert.equal(canonReference('  ABC123  '), 'ABC123');
  assert.equal(canonicalValueDigest(Buffer.from(canonReference('ABC123'), 'utf8')), 'cd3accb68225721c823e5b0e2159f0de4df13c87db23ca98684f715754d9d732');
});
