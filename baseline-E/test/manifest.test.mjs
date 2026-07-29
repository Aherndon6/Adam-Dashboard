// Design ref: §2 required inputs + narrowest schema. Covers coverage_horizon_end binding, integer-cents,
// closed enums, no capacity-only mode (transfer required), frontier-relative horizon.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateManifest } from '../src/manifest-validate.mjs';

const base = () => ({
  model_year: 2026,
  as_of_model_week: 8,
  coverage_horizon_end: 31,
  operating_floor_cents: 650000,
  live_chk_selected_basis: 'posted_current',
  live_chk_displayed_balance_cents: 1234567,
  live_chk_capture_ts: '2026-07-29T10:00:00-04:00',
  normalized_opening_chk_cents: 1234567,
  effective_schedule_events: [
    { event_id: 'e1', model_week: 9, direction: 'debit', amount_cents: 500000, channel: 'obligation', content_digest: 'd1' },
  ],
  wendy_ira_amount_cents: 300000,
  wendy_ira_intended_date: '2026-08-03',
  wendy_ira_expected_posting: 'conservative',
});

test('valid minimal manifest passes', () => {
  assert.equal(validateManifest(base()).ok, true);
});

test('coverage_horizon_end < as_of_model_week ⇒ error (frontier-relative binding)', () => {
  const m = base(); m.coverage_horizon_end = 7;
  const r = validateManifest(m);
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.includes('coverage_horizon_end')));
});

test('no capacity-only mode: missing wendy_ira_amount_cents ⇒ error', () => {
  const m = base(); delete m.wendy_ira_amount_cents;
  assert.equal(validateManifest(m).ok, false);
});

test('money fields must be integer cents', () => {
  const m = base(); m.normalized_opening_chk_cents = 1234.56; // float ⇒ invalid
  assert.equal(validateManifest(m).ok, false);
});

test('closed enums enforced (bad channel, bad direction, bad verdict)', () => {
  const m1 = base(); m1.effective_schedule_events[0].channel = 'mystery';
  assert.equal(validateManifest(m1).ok, false);
  const m2 = base(); m2.effective_schedule_events[0].direction = 'sideways';
  assert.equal(validateManifest(m2).ok, false);
  const m3 = base(); m3.verdict = 'MAYBE';
  assert.equal(validateManifest(m3).ok, false);
});

test('model_year must be 2026', () => {
  const m = base(); m.model_year = 2027;
  assert.equal(validateManifest(m).ok, false);
});
