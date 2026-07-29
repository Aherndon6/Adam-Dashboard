// baseline-E/src/allocation.mjs
// Design ref: spec §5c confirmed_matches[] + allocation-graph VALIDATOR; test 79 (disposition G accepting branch
// + fail-closed twin), test 71 (partial split, cent conservation). Integer cents; exact; no rounding tolerance.
//
// This validates OWNER-ADJUDICATED allocation input (evidence-driven). It is NOT an allocation solver — the
// design treats allocation as adjudicated evidence, validated here against the conservation invariants.

function fail(reason) { return { ok: false, disposition: 'FAIL-STOP', reason }; }

export function validateAllocation({
  posted_amount_cents,
  confirmed_matches,
  allocation_graph = null,   // explicit list of event_ids permitted to appear in >1 reconciliation
  allocation_complete = true,
} = {}) {
  if (!Number.isInteger(posted_amount_cents)) return fail('posted_amount_cents not integer cents');
  if (!Array.isArray(confirmed_matches) || confirmed_matches.length === 0) return fail('no confirmed_matches');

  const componentIds = new Set();
  const eventCounts = new Map();
  let allocatedSum = 0;

  for (const m of confirmed_matches) {
    if (!m || !m.event_id) return fail('confirmed match missing event_id');
    if (!m.event_content_digest) return fail(`missing event_content_digest for ${m.event_id}`);
    if (!Number.isInteger(m.allocated_amount_cents)) return fail(`non-integer allocated_amount_cents for ${m.event_id}`);
    allocatedSum += m.allocated_amount_cents;

    // event appearing in >1 reconciliation is only permitted via an explicit allocation graph (§5c G)
    eventCounts.set(m.event_id, (eventCounts.get(m.event_id) || 0) + 1);
    if (eventCounts.get(m.event_id) > 1 && !(Array.isArray(allocation_graph) && allocation_graph.includes(m.event_id))) {
      return fail(`event ${m.event_id} participates in multiple reconciliations without an explicit allocation graph`);
    }

    // partial-posting split conservation (§5c B): reflected + remaining == original event amount, exactly
    if (m.reflected_component || m.remaining_forward_component) {
      const r = m.reflected_component, f = m.remaining_forward_component;
      if (!r?.id || !f?.id) return fail(`split missing component identity for ${m.event_id}`);
      if (!Number.isInteger(r.amount_cents) || !Number.isInteger(f.amount_cents)) return fail(`split component non-integer for ${m.event_id}`);
      if (!Number.isInteger(m.original_event_amount_cents)) return fail(`split missing original_event_amount_cents for ${m.event_id}`);
      if (r.amount_cents + f.amount_cents !== m.original_event_amount_cents) return fail(`split imbalance for ${m.event_id} (no rounding tolerance)`);
      for (const id of [r.id, f.id]) { if (componentIds.has(id)) return fail(`duplicate component identity ${id}`); componentIds.add(id); }
    }
  }

  // item K (rev-6.1 §10): over-allocation is UNCONDITIONALLY fail-closed — never ok/G regardless of the
  // presented allocation_complete flag.
  if (allocatedSum > posted_amount_cents) {
    return fail(`over-allocation: sum ${allocatedSum}¢ > posted ${posted_amount_cents}¢ (unconditional FAIL-STOP, rev-6.1 §10/item K)`);
  }
  // exact integer-cent conservation of the whole allocation — no $0.01 tolerance
  if (allocation_complete && allocatedSum !== posted_amount_cents) {
    return fail(`allocation sum ${allocatedSum}¢ != posted ${posted_amount_cents}¢ (exact conservation required)`);
  }

  const disposition = confirmed_matches.length >= 2 ? 'G'
    : (confirmed_matches[0].reflected_component ? 'B' : 'A');
  return { ok: true, disposition, allocated_sum_cents: allocatedSum };
}
