// baseline-E/src/allocation-g.mjs
// rev-6.1 disposition-G acceptance. Fail-closed; independent recompute (N-3); structured failure codes.
// H-1 authority binding (required fields, no truthiness escape); H-2 graph_identity reconciled to edges;
// §10 residual<0 unconditional; §3 cross-transaction; §4/§5 edge validity; §2 component-state; T-b/T-d;
// §12 exactly-once reverse manifestation; §9 graph-scoped authority.
import { edgeDigestV3, graphIdentity, graphDigestV3, authorityDigestV1 } from './digests.mjs';
import { isIdentityStrong } from './identity.mjs';
import { validateSubjectId } from './subject.mjs';
import { isCanonicalUtcMs } from './canon.mjs';

const F = (code, reason, disposition = 'FAIL-STOP') => ({ ok: false, disposition, code, reason });

export function acceptGraph(input) {
  const { bankTxn, graph, edges, authority, retainedScheduleMutations } = input;
  if (!Array.isArray(edges) || edges.length < 2) return F('G_MIN_EDGES', 'G requires ≥2 allocation edges (§5c G)', 'C-HOLD');
  if (!authority || typeof authority !== 'object') return F('H1_MISSING_AUTHORITY', 'authority record required for G (H-1)');
  if (!Array.isArray(retainedScheduleMutations)) return F('G12_MUTATIONS_REQUIRED', 'reverse-manifestation set required (§12)');

  // ── H-2: reconcile the participating event set FROM the edges ────────────────────────────────────────
  const reconciled = new Map();           // event_id → event_content_digest (unique, conflict-checked)
  const eventSeen = new Set();
  let totalAllocated = 0;
  const recomputedEdgeDigests = [];
  for (const e of edges) {
    // §3 cross-transaction consistency
    if (e.bank_transaction_id !== bankTxn.bank_transaction_id) return F('T_F_CROSS_TXN', `cross-transaction edge ${e.event_id}: bank_transaction_id mismatch (§3/T-f)`);
    if (e.bank_transaction_content_digest !== bankTxn.bank_transaction_content_digest) return F('T_F_CROSS_TXN_DIGEST', 'cross-transaction edge: bank_transaction_content_digest mismatch (§3/T-f)');
    if (!(e.edge_direction === graph.graph_direction && e.edge_direction === bankTxn.direction)) return F('EDGE_DIRECTION_MISMATCH', 'edge/graph/txn direction mismatch (§3)', 'D-FAIL-STOP');
    if (!Number.isInteger(e.allocated_amount_cents) || e.allocated_amount_cents < 1) return F('T_H_ALLOCATED_LT_1', `allocated_amount_cents < 1 for ${e.event_id} (§5/T-h)`);
    if (e.remaining_forward_component_amount_cents === 0 && e.remaining_forward_component_state !== 'zero_terminal_remainder') return F('COMPONENT_STATE', 'zero remaining must be zero_terminal_remainder (§2)');
    if (e.remaining_forward_component_amount_cents > 0 && e.remaining_forward_component_state !== 'active_remainder') return F('COMPONENT_STATE', 'positive remaining must be active_remainder (§2)');
    if (e.reflected_component_id === e.remaining_forward_component_id) return F('COMPONENT_IDS', 'reflected/remaining component ids must be distinct (§2)');
    if (e.allocated_amount_cents !== e.reflected_component_amount_cents) return F('EDGE_AMOUNT', `allocated != reflected for ${e.event_id}`, 'D-FAIL-STOP');
    if (e.reflected_direction !== e.edge_direction) return F('REFLECTED_DIRECTION', 'reflected_direction != edge_direction', 'D-FAIL-STOP');
    if (e.remaining_forward_component_amount_cents < 0) return F('T_B_NEG_REMAINING', 'negative remaining (T-b)');
    if (e.reflected_component_amount_cents > e.original_event_amount_cents) return F('T_B_REFLECTED_GT_ORIGINAL', 'reflected > original (T-b)');
    if (e.reflected_component_amount_cents + e.remaining_forward_component_amount_cents !== e.original_event_amount_cents) return F('T_B_EVENT_CONSERVATION', `event conservation imbalance for ${e.event_id} (T-b)`);
    const is1 = isIdentityStrong(e.anchors || []);
    if (is1.error) return F('H3_ANCHOR_VOCABULARY', `edge ${e.event_id}: ${is1.error}`);
    if (!is1.strong) return F('N4_WEAK_EVENT_IDENTITY', `allocated event ${e.event_id} not identity-strong — graph cannot waive IS-1 (N-4)`, 'C-HOLD');
    // any repeated event_id across edges is governed by F_EVENT_MULTI_EDGE (fires first), so a
    // same-id/conflicting-digest case cannot slip through; no separate H2_CONFLICTING_EVENT code is needed.
    if (eventSeen.has(e.event_id)) return F('F_EVENT_MULTI_EDGE', `event ${e.event_id} in multiple edges (§5c F)`);
    eventSeen.add(e.event_id);
    reconciled.set(e.event_id, e.event_content_digest);
    let ed; try { ed = edgeDigestV3(e); } catch (err) { return F('EDGE_DIGEST_RECOMPUTE', `edge digest recompute failed for ${e.event_id}: ${err.message}`); }
    if (e.presented_edge_digest !== undefined && e.presented_edge_digest !== ed) return F('N3_EDGE_DIGEST_MISMATCH', `edge_digest mismatch for ${e.event_id} (N-3)`);
    recomputedEdgeDigests.push(ed);
    totalAllocated += e.allocated_amount_cents;
  }

  // H-2: presented graph_identity_events (if any) must EXACTLY equal the reconciled edge-derived set.
  if (graph.graph_identity_events !== undefined) {
    const pres = graph.graph_identity_events;
    if (!Array.isArray(pres) || pres.length !== reconciled.size) return F('H2_EVENT_SET_SIZE', 'graph_identity event set size != reconciled edge events (H-2)');
    for (const ev of pres) {
      if (!reconciled.has(ev.event_id)) return F('H2_PHANTOM_EVENT', `phantom graph-identity event ${ev.event_id} not in edges (H-2)`);
      if (reconciled.get(ev.event_id) !== ev.event_content_digest) return F('H2_EVENT_DIGEST_MISMATCH', `graph-identity event_content_digest mismatch for ${ev.event_id} (H-2)`);
    }
    // a duplicate event_id in the presented set forces some reconciled id to be missing at equal length,
    // which H2_OMITTED_EVENT (below) governs; no separate H2_DUPLICATE_EVENT code is needed.
    const presIds = new Set(pres.map((e) => e.event_id));
    for (const id of reconciled.keys()) if (!presIds.has(id)) return F('H2_OMITTED_EVENT', `participating event ${id} omitted from graph identity (H-2)`);
  }
  const reconciledEvents = [...reconciled.entries()].map(([event_id, event_content_digest]) => ({ event_id, event_content_digest }));

  // ── §10 independent residual recompute (unconditional; never trusts allocation_complete) ─────────────
  const residual = bankTxn.amount_cents - totalAllocated;
  if (residual < 0) return F('D_RESIDUAL_NEGATIVE', `over-allocation: residual ${residual} < 0 (§10) — unconditional FAIL-STOP`);
  if (graph.presented && graph.presented.total_allocated_amount_cents !== undefined && graph.presented.total_allocated_amount_cents !== totalAllocated) return F('M19_TOTAL_ALLOCATED_MISMATCH', 'presented total_allocated != recomputed (N-3)');
  if (graph.presented && typeof graph.presented.allocation_complete === 'boolean' && graph.presented.allocation_complete !== (residual === 0)) return F('M10_ALLOC_COMPLETE_INCONSISTENT', 'presented allocation_complete inconsistent with recomputed completeness (N-3)');
  if (residual > 0) return F('INCOMPLETE_ALLOCATION', `incomplete allocation: residual ${residual} > 0 (§3) — never G, never E`, 'C-HOLD');

  // ── graph_identity + graph digest recompute (from reconciled events) ─────────────────────────────────
  let gi; try { gi = graphIdentity({ bank_transaction_id: bankTxn.bank_transaction_id, bank_transaction_content_digest: bankTxn.bank_transaction_content_digest, graph_direction: graph.graph_direction, events: reconciledEvents, allocation_generation_or_adjudication_id: graph.allocation_generation_or_adjudication_id }); }
  catch (err) { return F('GRAPH_IDENTITY_INVALID', `graph_identity invalid: ${err.message} (§8)`); }
  if (graph.presented && graph.presented.graph_identity !== undefined && graph.presented.graph_identity !== gi) return F('M9_GRAPH_IDENTITY_MISMATCH', 'presented graph_identity mismatch (N-3)');
  let gd; try { gd = graphDigestV3({ graph_identity: gi, bank_transaction_content_digest: bankTxn.bank_transaction_content_digest, graph_direction: graph.graph_direction, bank_posted_amount_cents: bankTxn.amount_cents, total_allocated_amount_cents: totalAllocated, graph_conservation_state: 'balanced', edge_digests: recomputedEdgeDigests }); }
  catch (err) { return F('GRAPH_DIGEST_RECOMPUTE', `graph digest recompute failed: ${err.message}`); }
  if (graph.presented && graph.presented.allocation_graph_digest !== undefined && graph.presented.allocation_graph_digest !== gd) return F('N3_GRAPH_DIGEST_MISMATCH', 'allocation_graph_digest mismatch (N-3)');

  // ── H-1 authority (graph-scoped, §9): all required fields present; no truthiness escape ──────────────
  try { validateSubjectId(authority.subject_or_role_id); } catch (err) { return F('AUTH_SUBJECT_INVALID', `authority subject invalid: ${err.message} (§9)`); }
  if (!['owner', 'authoritative_record'].includes(authority.authority_kind)) return F('M8_AUTH_KIND_INVALID', 'authority_kind not in enum (§9)');
  if (!isCanonicalUtcMs(authority.approved_at_ts_utc)) return F('M7_AUTH_TS_INVALID', 'approved_at_ts_utc not canonical UTC ms Z (semantic, §9)');
  if (authority.bound_graph_digest === undefined || authority.bound_graph_digest === null) return F('H1_MISSING_BOUND', 'authority.bound_graph_digest required (H-1) — no truthiness escape');
  if (authority.bound_graph_digest !== gd) return F('H1_BOUND_MISMATCH', 'authority approves a different allocation_graph_digest (§9/H-1) — stale/mismatched');
  if (!authority.presented || authority.presented.allocation_authority_digest === undefined || authority.presented.allocation_authority_digest === null) return F('H1_MISSING_AUTH_DIGEST', 'presented allocation_authority_digest required (H-1)');
  let ad; try { ad = authorityDigestV1({ authority_kind: authority.authority_kind, subject_or_role_id: authority.subject_or_role_id, authority_record_digest: authority.authority_record_digest ?? null, approved_at_ts_utc: authority.approved_at_ts_utc, allocation_graph_digest: gd }); }
  catch (err) { return F('AUTH_DIGEST_RECOMPUTE', `authority digest recompute failed: ${err.message}`); }
  if (authority.presented.allocation_authority_digest !== ad) return F('H1_AUTH_DIGEST_MISMATCH', 'allocation_authority_digest mismatch (H-1/N-3)');

  // ── §12 exactly-once reverse schedule-manifestation ─────────────────────────────────────────────────
  const edgeByEvent = new Map(edges.map((e) => [e.event_id, e]));
  const mutatedEvents = new Set();
  for (const mut of retainedScheduleMutations) {
    if (!edgeByEvent.has(mut.event_id)) return F('G12_ORPHAN_MUTATION', `orphan schedule mutation for ${mut.event_id} (§12)`);
    if (mutatedEvents.has(mut.event_id)) return F('M6_DUP_MUTATION', `duplicate schedule mutation for ${mut.event_id} (§12)`);
    mutatedEvents.add(mut.event_id);
    const e = edgeByEvent.get(mut.event_id);
    if (mut.amount_cents !== undefined && mut.amount_cents !== e.reflected_component_amount_cents) return F('G12_MUTATION_AMOUNT', `mutation amount inconsistent with edge for ${mut.event_id} (§12)`);
  }
  // exactly-once: every participating event has exactly one manifestation (zero is not acceptable)
  for (const id of edgeByEvent.keys()) if (!mutatedEvents.has(id)) return F('G12_MISSING_MANIFESTATION', `missing reverse manifestation for participating event ${id} (§12 exactly-once)`);
  // T-d: fully-reflected event may not retain a forward cash effect
  for (const e of edges) if (e.remaining_forward_component_state === 'zero_terminal_remainder' && e.retained_cash_effect === true) return F('T_D_RETAINED_AFTER_FULL_REFLECTION', `fully-reflected event ${e.event_id} retains a cash effect (§2/T-d)`);

  return { ok: true, disposition: 'G', code: 'G_ACCEPTED', evidence: { total_allocated_amount_cents: totalAllocated, residual, graph_identity: gi, allocation_graph_digest: gd, allocation_authority_digest: ad, edge_digests: recomputedEdgeDigests } };
}
