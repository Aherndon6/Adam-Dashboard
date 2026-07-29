// item K (rev-6.1 §10): legacy allocation.mjs must never label an over-allocation as ok/G,
// regardless of the presented allocation_complete flag.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateAllocation } from '../src/allocation.mjs';

const mk = (event_id, allocated) => ({ event_id, event_content_digest: `d:${event_id}`, allocated_amount_cents: allocated });

test('over-allocation with allocation_complete=true ⇒ FAIL-STOP (never G)', () => {
  const r = validateAllocation({ posted_amount_cents: 100, confirmed_matches: [mk('e1', 60), mk('e2', 60)], allocation_complete: true });
  assert.equal(r.ok, false); assert.equal(r.disposition, 'FAIL-STOP');
});
test('over-allocation with allocation_complete=false ⇒ FAIL-STOP (was the legacy foot-gun; now unconditional)', () => {
  const r = validateAllocation({ posted_amount_cents: 100, confirmed_matches: [mk('e1', 60), mk('e2', 60)], allocation_complete: false });
  assert.equal(r.ok, false); assert.equal(r.disposition, 'FAIL-STOP');
  assert.match(r.reason, /over-allocation/);
});
test('exact complete allocation still accepted (G)', () => {
  const r = validateAllocation({ posted_amount_cents: 100, confirmed_matches: [mk('e1', 40), mk('e2', 60)], allocation_complete: true });
  assert.equal(r.ok, true); assert.equal(r.disposition, 'G');
});
