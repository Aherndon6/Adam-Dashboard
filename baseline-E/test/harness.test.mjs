// Design ref: §1e parity harness + §1b RLS visibility-proof harness. These prove the harness COMPARISON logic
// against deterministic fixtures. LIVE parity (vs deployed runModel) and the independent live RLS channel are
// AUTHORIZED-CAPTURE-time steps, marked PENDING — see the *.pending markers below.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { reconcileParity, LIVE_PARITY_EVIDENCE } from '../harness/parity.mjs';
import { reconcileVisibility, LIVE_RLS_EVIDENCE } from '../harness/rls-proof.mjs';

test('§1e parity: identical event sets ⇒ PARITY_OK', () => {
  const evs = [{ event_id: 'a', amount_cents: 100, direction: 'debit' }];
  assert.equal(reconcileParity({ scriptEvents: evs, engineEvents: evs }).ok, true);
});

test('§1e parity: uncatalogued one-sided difference ⇒ FAIL-STOP', () => {
  const r = reconcileParity({
    scriptEvents: [{ event_id: 'a', amount_cents: 100, direction: 'debit' }],
    engineEvents: [{ event_id: 'a', amount_cents: 100, direction: 'debit' }, { event_id: 'x', amount_cents: 5, direction: 'credit' }],
  });
  assert.equal(r.verdict, 'FAIL-STOP');
});

test('§1e parity: catalogued NON-cash difference is permitted', () => {
  const r = reconcileParity({
    scriptEvents: [{ event_id: 'a', amount_cents: 100, direction: 'debit' }, { event_id: 'sweep', amount_cents: 900, direction: 'debit' }],
    engineEvents: [{ event_id: 'a', amount_cents: 100, direction: 'debit' }],
    differenceClassifications: { sweep: { class: 'intentionally_excluded_discretionary_waterfall', cash_affecting: false } },
  });
  assert.equal(r.ok, true);
});

test('§1e parity: shared-id amount mismatch is always a cash difference ⇒ FAIL-STOP', () => {
  const r = reconcileParity({
    scriptEvents: [{ event_id: 'a', amount_cents: 100, direction: 'debit' }],
    engineEvents: [{ event_id: 'a', amount_cents: 101, direction: 'debit' }],
  });
  assert.equal(r.ok, false);
});

test('§1b RLS: matching authoritative/adapter inventory (independence established) ⇒ OK', () => {
  const rows = [{ id: 'r1', content_digest: 'd1' }, { id: 'r2', content_digest: 'd2' }];
  assert.equal(reconcileVisibility({ authoritative: rows, adapterVisible: rows, independenceEstablished: true }).ok, true);
});

test('§1b RLS: hidden row (authoritative id not adapter-visible) ⇒ FAIL-STOP', () => {
  const r = reconcileVisibility({
    authoritative: [{ id: 'r1', content_digest: 'd1' }, { id: 'r2', content_digest: 'd2' }],
    adapterVisible: [{ id: 'r1', content_digest: 'd1' }],
    independenceEstablished: true,
  });
  assert.equal(r.verdict, 'FAIL-STOP');
});

test('§1b RLS: independence not established ⇒ FAIL-STOP (a same-role reconcile proves nothing)', () => {
  const rows = [{ id: 'r1', content_digest: 'd1' }];
  assert.equal(reconcileVisibility({ authoritative: rows, adapterVisible: rows, independenceEstablished: false }).ok, false);
});

test('live-evidence gates are explicitly PENDING (not silently "passed")', () => {
  assert.equal(LIVE_PARITY_EVIDENCE, 'PENDING_AUTHORIZED_CAPTURE');
  assert.equal(LIVE_RLS_EVIDENCE, 'PENDING_AUTHORIZED_CAPTURE');
});
