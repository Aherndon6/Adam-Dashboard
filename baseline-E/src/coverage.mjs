// baseline-E/src/coverage.mjs
// rev-6.1 §1(A)/§4 — coverage_horizon_end endpoint validation + coverage_sufficient predicate + cycle counting.
// coverage_horizon_end is the AUTHORITATIVE loaded endpoint (never moved to manufacture sufficiency).

export class CoverageError extends Error {}
export const COVERAGE_POLICY_V1 = Object.freeze({ min_model_weeks: 8, min_paycheck_cycles: 2, min_card_statement_cycles: 2 });
const AUTHORITATIVE_ENDPOINT_MODEL_WEEK = 31; // current model generation (validated against the loaded snapshot)

// Validate that the loaded projection endpoint is the authoritative endpoint (rev-6.1 §1A). Mismatch ⇒ FAIL-STOP.
export function validateCoverageHorizonEnd(loadedEndpointModelWeek) {
  if (loadedEndpointModelWeek !== AUTHORITATIVE_ENDPOINT_MODEL_WEEK) {
    throw new CoverageError(`coverage_horizon_end integrity: loaded endpoint ${loadedEndpointModelWeek} != authoritative ${AUTHORITATIVE_ENDPOINT_MODEL_WEEK}`);
  }
  return loadedEndpointModelWeek;
}

// Cycle counting is schedule-derived (rev-6.1 §4) and DE-DUPLICATED by content-bound occurrence_id (item H):
// duplicate representations of one occurrence must not inflate counts; irrelevant events never count. The
// fixed coverage-v1 policy is NON-OVERRIDABLE (the caller cannot weaken thresholds).
// scheduleEvents: [{ model_week, kind:'payroll_inflow'|'card_payment_obligation'|..., occurrence_id }]
export function coverageSufficient({ measurement_start_week, coverage_horizon_end_week, scheduleEvents }) {
  validateCoverageHorizonEnd(coverage_horizon_end_week);
  if (!Number.isInteger(measurement_start_week) || measurement_start_week < 1) throw new CoverageError('bad measurement_start_week');
  const policy = COVERAGE_POLICY_V1;                                     // fixed; not caller-overridable (item H)
  const inWin = (w) => Number.isInteger(w) && w >= measurement_start_week && w <= coverage_horizon_end_week;
  const weeks = coverage_horizon_end_week - measurement_start_week + 1;  // inclusive
  const paycheckIds = new Set(), statementIds = new Set();
  for (const ev of scheduleEvents || []) {
    if (!inWin(ev.model_week)) continue;
    const id = ev.occurrence_id;
    if (id === undefined || id === null || id === '') throw new CoverageError('coverage event missing content-bound occurrence_id (item H)');
    if (ev.kind === 'payroll_inflow') paycheckIds.add(id);              // unique occurrences only (de-dup)
    else if (ev.kind === 'card_payment_obligation') statementIds.add(id);
    // irrelevant kinds are ignored
  }
  const paycheck = paycheckIds.size, statement = statementIds.size;
  const sufficient = weeks >= policy.min_model_weeks && paycheck >= policy.min_paycheck_cycles && statement >= policy.min_card_statement_cycles;
  return { coverage_sufficient: sufficient, weeks, paycheck_cycles: paycheck, card_statement_cycles: statement,
           policy, coverage_policy_version: 'coverage-v1', measurement_start_week, coverage_horizon_end_week };
}
