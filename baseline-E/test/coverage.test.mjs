// rev-6.1 §1A/§4 + item H — endpoint validation + fixed coverage-v1 + de-dup by content-bound occurrence_id.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { coverageSufficient, validateCoverageHorizonEnd, CoverageError } from '../src/coverage.mjs';

const ev = (model_week, kind, occurrence_id) => ({ model_week, kind, occurrence_id });

test('endpoint validation: 31 ok; else FAIL-STOP', () => {
  assert.equal(validateCoverageHorizonEnd(31), 31);
  assert.throws(() => validateCoverageHorizonEnd(30), CoverageError);
});
test('coverage_sufficient TRUE with ≥8 weeks, ≥2 unique paycheck, ≥2 unique card', () => {
  const events = [ev(9, 'payroll_inflow', 'p1'), ev(11, 'payroll_inflow', 'p2'), ev(11, 'card_payment_obligation', 'c1'), ev(15, 'card_payment_obligation', 'c2')];
  const r = coverageSufficient({ measurement_start_week: 8, coverage_horizon_end_week: 31, scheduleEvents: events });
  assert.equal(r.coverage_sufficient, true); assert.equal(r.weeks, 24); assert.equal(r.paycheck_cycles, 2); assert.equal(r.card_statement_cycles, 2);
});
test('item H: duplicate occurrence_id does NOT inflate counts', () => {
  const events = [ev(9, 'payroll_inflow', 'p1'), ev(9, 'payroll_inflow', 'p1'), ev(11, 'payroll_inflow', 'p1'), ev(11, 'card_payment_obligation', 'c1'), ev(15, 'card_payment_obligation', 'c2')];
  const r = coverageSufficient({ measurement_start_week: 8, coverage_horizon_end_week: 31, scheduleEvents: events });
  assert.equal(r.paycheck_cycles, 1);       // three representations of occurrence p1 = one cycle
  assert.equal(r.coverage_sufficient, false); // only 1 unique paycheck cycle < 2
});
test('item H: irrelevant events do not count', () => {
  const events = [ev(9, 'rent_obligation', 'r1'), ev(10, 'note', 'n1'), ev(9, 'payroll_inflow', 'p1')];
  const r = coverageSufficient({ measurement_start_week: 8, coverage_horizon_end_week: 31, scheduleEvents: events });
  assert.equal(r.paycheck_cycles, 1); assert.equal(r.card_statement_cycles, 0);
});
test('item H: policy is fixed coverage-v1 and NOT caller-overridable', () => {
  const events = [ev(9, 'payroll_inflow', 'p1')];
  // even if a caller passes a weaker "policy", it is ignored (thresholds fixed at 2/2/8)
  const r = coverageSufficient({ measurement_start_week: 8, coverage_horizon_end_week: 31, scheduleEvents: events, policy: { min_model_weeks: 1, min_paycheck_cycles: 1, min_card_statement_cycles: 0 } });
  assert.equal(r.coverage_policy_version, 'coverage-v1');
  assert.equal(r.coverage_sufficient, false);   // fixed policy still requires 2 paycheck + 2 card
});
test('coverage event missing content-bound occurrence_id ⇒ FAIL-STOP', () => {
  assert.throws(() => coverageSufficient({ measurement_start_week: 8, coverage_horizon_end_week: 31, scheduleEvents: [{ model_week: 9, kind: 'payroll_inflow' }] }), CoverageError);
});
test('< 8 model weeks ⇒ insufficient', () => {
  const events = [ev(26, 'payroll_inflow', 'p1'), ev(28, 'payroll_inflow', 'p2'), ev(27, 'card_payment_obligation', 'c1'), ev(29, 'card_payment_obligation', 'c2')];
  const r = coverageSufficient({ measurement_start_week: 25, coverage_horizon_end_week: 31, scheduleEvents: events });
  assert.equal(r.weeks, 7); assert.equal(r.coverage_sufficient, false);
});
