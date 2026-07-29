// Design ref: §5c confirmed_matches[] + allocation-graph validator. Covers §17 test 71 (partial split) and
// test 79 (disposition G accepting branch + fail-closed twin: exact cent conservation, no tolerance).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateAllocation } from '../src/allocation.mjs';

const mk = (event_id, allocated) => ({ event_id, event_content_digest: `d:${event_id}`, allocated_amount_cents: allocated });

test('§17-79 disposition G accepting branch: exact allocation across ≥2 events', () => {
  const r = validateAllocation({
    posted_amount_cents: 100000,
    confirmed_matches: [mk('e1', 60000), mk('e2', 40000)],
  });
  assert.deepEqual(r, { ok: true, disposition: 'G', allocated_sum_cents: 100000 });
});

test('§17-79 fail-closed twin: $0.01 allocation imbalance ⇒ FAIL-STOP (no tolerance)', () => {
  const r = validateAllocation({
    posted_amount_cents: 100000,
    confirmed_matches: [mk('e1', 60000), mk('e2', 39999)], // off by 1¢
  });
  assert.equal(r.ok, false);
  assert.equal(r.disposition, 'FAIL-STOP');
});

test('§17-79 fail-closed twin: missing content digest ⇒ FAIL-STOP', () => {
  const r = validateAllocation({
    posted_amount_cents: 50000,
    confirmed_matches: [{ event_id: 'e1', allocated_amount_cents: 50000 }], // no digest
  });
  assert.equal(r.ok, false);
});

test('§17-79 fail-closed twin: event in multiple reconciliations without explicit allocation graph ⇒ FAIL-STOP', () => {
  const bad = validateAllocation({
    posted_amount_cents: 100000,
    confirmed_matches: [mk('e1', 50000), mk('e1', 50000)], // same event twice, no graph
  });
  assert.equal(bad.ok, false);
  const ok = validateAllocation({
    posted_amount_cents: 100000,
    confirmed_matches: [mk('e1', 50000), mk('e1', 50000)],
    allocation_graph: ['e1'], // explicit graph permits it
  });
  assert.equal(ok.ok, true);
});

test('§17-71 partial early-posting split: reflected + remaining == original, exactly (disposition B)', () => {
  const r = validateAllocation({
    posted_amount_cents: 30000, // only the reflected part posted
    confirmed_matches: [{
      event_id: 'e1', event_content_digest: 'd:e1', allocated_amount_cents: 30000,
      reflected_component: { id: 'e1#refl', amount_cents: 30000 },
      remaining_forward_component: { id: 'e1#rem', amount_cents: 70000 },
      original_event_amount_cents: 100000,
    }],
  });
  assert.equal(r.ok, true);
  assert.equal(r.disposition, 'B');
});

test('§17-71 split imbalance by $0.01 ⇒ FAIL-STOP', () => {
  const r = validateAllocation({
    posted_amount_cents: 30000,
    confirmed_matches: [{
      event_id: 'e1', event_content_digest: 'd:e1', allocated_amount_cents: 30000,
      reflected_component: { id: 'e1#refl', amount_cents: 30000 },
      remaining_forward_component: { id: 'e1#rem', amount_cents: 69999 }, // 30000+69999 != 100000
      original_event_amount_cents: 100000,
    }],
  });
  assert.equal(r.ok, false);
});
