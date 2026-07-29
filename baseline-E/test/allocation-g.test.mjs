// rev-6.1 disposition-G: test 79 accepting + fail-closed twins with EXACT reason codes.
// H-1 authority, H-2 graph-identity reconciliation, §10 residual, §12 exactly-once, T-b..T-h, M6/M7/M8/M9/M10/M19.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { acceptGraph } from '../src/allocation-g.mjs';
import { edgeDigestV3, graphIdentity, graphDigestV3, authorityDigestV1 } from '../src/digests.mjs';

const hx = (n) => n.toString(16).padStart(64, '0');
// SYNTHETIC test-only UUID v4 (locally generated via crypto.randomUUID; not derived from any real identifier)
const SYNTHETIC_UUID = '2e6f8777-94c8-420e-aa20-c0c481d7ce5a';
const V4 = `user:${SYNTHETIC_UUID}`;
const TS = '2026-07-29T12:00:00.000Z';
const anchorsFor = (s, weak = false) => (weak
  ? [{ type: 'source_account_identity' }, { type: 'counterparty_identity' }]
  : [{ type: 'bank_reference' }, { type: 'source_system_identity' }]
).map((a, i) => ({ ...a, canonical_value_digest: hx(s + i), anchor_evidence_digest: hx(s + 10 + i), evidence_root_digest: hx(s + i),
  evidence_root: { source_system: 'sy' + s + i, source_record_digest: hx(s + 20 + i), source_field: 'f', derivation_method: 'direct_read' } }));

function mkEdge(event_id, original, s, { allocated, reflected, remaining, direction = 'credit', weak = false, retained_cash_effect = false } = {}) {
  reflected = reflected ?? original; remaining = remaining ?? original - reflected; allocated = allocated ?? reflected;
  return {
    bank_transaction_id: 't1', bank_transaction_content_digest: hx(1), event_id, event_content_digest: hx(s + 100),
    allocated_amount_cents: allocated, edge_direction: direction,
    reflected_component_id: event_id + '#refl', reflected_component_content_digest: hx(s + 200),
    reflected_component_amount_cents: reflected, reflected_component_state: remaining === 0 ? 'reflected_terminal' : 'partial_reflected', reflected_direction: direction,
    remaining_forward_component_id: event_id + '#rem', remaining_forward_component_content_digest: hx(s + 300),
    remaining_forward_component_amount_cents: remaining, remaining_forward_component_state: remaining === 0 ? 'zero_terminal_remainder' : 'active_remainder',
    original_event_amount_cents: original, evidence_root_digests: [hx(s), hx(s + 1)], anchors: anchorsFor(s, weak), retained_cash_effect,
  };
}

function build({ edges, posted = 10000 } = {}) {
  const bankTxn = { bank_transaction_id: 't1', bank_transaction_content_digest: hx(1), direction: 'credit', amount_cents: posted };
  const gi_events = edges.map((e) => ({ event_id: e.event_id, event_content_digest: e.event_content_digest }));
  const total = edges.reduce((a, e) => a + e.allocated_amount_cents, 0);
  const eds = edges.map(edgeDigestV3).sort();
  const gi = graphIdentity({ bank_transaction_id: 't1', bank_transaction_content_digest: hx(1), graph_direction: 'credit', events: gi_events, allocation_generation_or_adjudication_id: null });
  const gd = graphDigestV3({ graph_identity: gi, bank_transaction_content_digest: hx(1), graph_direction: 'credit', bank_posted_amount_cents: posted, total_allocated_amount_cents: total, graph_conservation_state: 'balanced', edge_digests: eds });
  const ad = authorityDigestV1({ authority_kind: 'owner', subject_or_role_id: V4, authority_record_digest: null, approved_at_ts_utc: TS, allocation_graph_digest: gd });
  edges.forEach((e) => { e.presented_edge_digest = edgeDigestV3(e); });
  return {
    bankTxn,
    graph: { graph_identity_events: gi_events, graph_direction: 'credit', allocation_generation_or_adjudication_id: null, presented: { graph_identity: gi, allocation_graph_digest: gd, total_allocated_amount_cents: total, allocation_complete: total === posted } },
    edges,
    authority: { authority_kind: 'owner', subject_or_role_id: V4, authority_record_digest: null, approved_at_ts_utc: TS, bound_graph_digest: gd, presented: { allocation_authority_digest: ad } },
    retainedScheduleMutations: edges.map((e) => ({ event_id: e.event_id, mutation_kind: 'reflected', amount_cents: e.reflected_component_amount_cents })),
  };
}
const valid = () => build({ edges: [mkEdge('e1', 4000, 10), mkEdge('e2', 6000, 20)], posted: 10000 });
// EARLY structural twins (gate fires in the edges loop / H-2, before authority): strip presented digests.
const strip = (mut) => { const i = structuredClone(valid()); i.edges.forEach((e) => delete e.presented_edge_digest); delete i.graph.presented; delete i.authority.presented; delete i.authority.bound_graph_digest; mut(i); return i; };
// LATE twins (residual/graph/authority/manifestation): keep valid presented+bound; mutate one field.
const mutValid = (mut) => { const i = structuredClone(valid()); mut(i); return i; };
const code = (r) => r.code;

test('§17-79 accepting: $100 = $40 + $60 ⇒ G', () => { const r = acceptGraph(valid()); assert.equal(r.disposition, 'G'); assert.equal(r.code, 'G_ACCEPTED'); assert.equal(r.evidence.residual, 0); });
test('§17-79 partial reflection accepting ⇒ G', () => { assert.equal(acceptGraph(build({ edges: [mkEdge('e1', 4000, 30, { allocated: 3000, reflected: 3000, remaining: 1000 }), mkEdge('e2', 6000, 40)], posted: 9000 })).disposition, 'G'); });

test('§10 residual < 0 (over-allocation) ⇒ FAIL-STOP D_RESIDUAL_NEGATIVE (isolated; all other gates valid)', () => {
  const r = acceptGraph(build({ edges: [mkEdge('e1', 4000, 10), mkEdge('e2', 7000, 20, { allocated: 7000, reflected: 7000 })], posted: 10000 }));
  assert.equal(r.disposition, 'FAIL-STOP'); assert.equal(r.code, 'D_RESIDUAL_NEGATIVE');
});
test('§3 residual > 0 (incomplete) ⇒ C/HOLD', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[1] = mkEdge('e2', 5000, 20, { allocated: 5000, reflected: 5000 }); }))), 'INCOMPLETE_ALLOCATION'); });
test('T-b 1¢ event imbalance ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[0].remaining_forward_component_amount_cents = 1; i.edges[0].remaining_forward_component_state = 'active_remainder'; }))), 'T_B_EVENT_CONSERVATION'); });
test('T-b negative remaining ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[0].remaining_forward_component_amount_cents = -1; }))), 'T_B_NEG_REMAINING'); });
test('T-b reflected > original ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[0].reflected_component_amount_cents = 5000; i.edges[0].allocated_amount_cents = 5000; }))), 'T_B_REFLECTED_GT_ORIGINAL'); });
test('T-h zero-cent edge ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[0].allocated_amount_cents = 0; }))), 'T_H_ALLOCATED_LT_1'); });
test('edge direction conflict ⇒ D/FAIL-STOP', () => { const r = acceptGraph(strip((i) => { i.edges[0].edge_direction = 'debit'; })); assert.equal(r.disposition, 'D-FAIL-STOP'); assert.equal(r.code, 'EDGE_DIRECTION_MISMATCH'); });
test('T-f cross-transaction edge ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[0].bank_transaction_id = 'other'; }))), 'T_F_CROSS_TXN'); });
test('T-g zero evidence roots ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[0].evidence_root_digests = []; }))), 'EDGE_DIGEST_RECOMPUTE'); });
test('T-e duplicate evidence root ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[0].evidence_root_digests = [hx(10), hx(10)]; }))), 'EDGE_DIGEST_RECOMPUTE'); });
test('N-4 weak allocated event ⇒ C/HOLD (graph cannot waive IS-1)', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[0].anchors = anchorsFor(10, true); }))), 'N4_WEAK_EVENT_IDENTITY'); });
test('H-3 vocabulary in allocated event (amount as anchor) ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[0].anchors = [{ type: 'amount' }, { type: 'bank_reference' }]; }))), 'H3_ANCHOR_VOCABULARY'); });
test('§5c F cross-participating event ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.edges[1].event_id = 'e1'; }))), 'F_EVENT_MULTI_EDGE'); });

// H-2 graph-identity reconciliation
test('H-2 phantom graph-identity event (size+1) ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.graph.graph_identity_events.push({ event_id: 'ghost', event_content_digest: hx(999) }); }))), 'H2_EVENT_SET_SIZE'); });
test('H-2 EQUAL-SIZE phantom (replace a real event with a ghost) ⇒ H2_PHANTOM_EVENT (exact reconciliation, not just size)', () => { assert.equal(code(acceptGraph(strip((i) => { i.graph.graph_identity_events[1] = { event_id: 'ghost', event_content_digest: hx(999) }; }))), 'H2_PHANTOM_EVENT'); });
test('H-2 omitted participating event ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.graph.graph_identity_events = [i.graph.graph_identity_events[0]]; }))), 'H2_EVENT_SET_SIZE'); });
test('H-2 event_content_digest mismatch ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(strip((i) => { i.graph.graph_identity_events[0].event_content_digest = hx(888); }))), 'H2_EVENT_DIGEST_MISMATCH'); });

// N-3 digest recompute
test('N-3 presented edge_digest mismatch ⇒ FAIL-STOP', () => { const i = valid(); i.edges[0].presented_edge_digest = hx(777777); assert.equal(acceptGraph(i).code, 'N3_EDGE_DIGEST_MISMATCH'); });
test('M9 presented graph_identity mismatch ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.graph.presented.graph_identity = hx(1234); }))), 'M9_GRAPH_IDENTITY_MISMATCH'); });
test('N-3 presented graph_digest mismatch ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.graph.presented.allocation_graph_digest = hx(4321); }))), 'N3_GRAPH_DIGEST_MISMATCH'); });
test('M19 presented total_allocated mismatch ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.graph.presented.total_allocated_amount_cents = 9999; }))), 'M19_TOTAL_ALLOCATED_MISMATCH'); });
test('M10 allocation_complete inconsistency ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.graph.presented.allocation_complete = false; }))), 'M10_ALLOC_COMPLETE_INCONSISTENT'); });

// H-1 authority binding (fail-closed; no truthiness escape)
test('H-1 missing bound_graph_digest ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { delete i.authority.bound_graph_digest; }))), 'H1_MISSING_BOUND'); });
test('H-1 mismatched bound_graph_digest (stale) ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.authority.bound_graph_digest = hx(5555); }))), 'H1_BOUND_MISMATCH'); });
test('H-1 missing presented authority digest ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { delete i.authority.presented.allocation_authority_digest; }))), 'H1_MISSING_AUTH_DIGEST'); });
test('H-1 mismatched authority digest ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.authority.presented.allocation_authority_digest = hx(6666); }))), 'H1_AUTH_DIGEST_MISMATCH'); });
test('M8 invalid authority_kind ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.authority.authority_kind = 'bogus'; }))), 'M8_AUTH_KIND_INVALID'); });
test('M7 invalid authority timestamp (semantic) ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.authority.approved_at_ts_utc = '2026-07-29 12:00'; }))), 'M7_AUTH_TS_INVALID'); });
test('M7 timestamp regex-shaped but not real (Feb 30) ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.authority.approved_at_ts_utc = '2026-02-30T12:00:00.000Z'; }))), 'M7_AUTH_TS_INVALID'); });
test('invalid authority subject (role:) ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.authority.subject_or_role_id = 'role:owner'; }))), 'AUTH_SUBJECT_INVALID'); });

// §12 exactly-once reverse manifestation
test('§12 exactly-once: ZERO manifestations ⇒ FAIL-STOP (not accepted)', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.retainedScheduleMutations = []; }))), 'G12_MISSING_MANIFESTATION'); });
test('M6 duplicate manifestation ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.retainedScheduleMutations.push({ event_id: 'e1', mutation_kind: 'reflected', amount_cents: 4000 }); }))), 'M6_DUP_MUTATION'); });
test('§12 orphan manifestation ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.retainedScheduleMutations.push({ event_id: 'ghost', amount_cents: 1 }); }))), 'G12_ORPHAN_MUTATION'); });
test('§12 amount-mismatched manifestation ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.retainedScheduleMutations[0].amount_cents = 3999; }))), 'G12_MUTATION_AMOUNT'); });
test('T-d fully-reflected event retains cash effect ⇒ FAIL-STOP', () => { assert.equal(code(acceptGraph(mutValid((i) => { i.edges[0].retained_cash_effect = true; }))), 'T_D_RETAINED_AFTER_FULL_REFLECTION'); });

test('graphDigestV3 rejects duplicate edge digests (no silent dedup)', () => {
  assert.throws(() => graphDigestV3({ graph_identity: hx(1), bank_transaction_content_digest: hx(1), graph_direction: 'credit', bank_posted_amount_cents: 1, total_allocated_amount_cents: 1, graph_conservation_state: 'balanced', edge_digests: [hx(5), hx(5)] }));
});
