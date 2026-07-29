// baseline-E/src/manifest-validate.mjs
// Design ref: spec §2 (required inputs) + narrowest schema (schema/manifest.schema.json). Dependency-free
// SEMANTIC validator (not a general JSON-Schema engine): enforces the rules the design fixes, and applies
// constrained-string semantic checks where the design defines no closed vocabulary. Event- and allocation-level
// conservation are delegated to calc.mjs / allocation.mjs.

import { isIntegerCents } from './cents.mjs';

const CLOSED = {
  live_chk_selected_basis: ['posted_current', 'available'],
  direction: ['debit', 'credit'],
  channel: ['inflow', 'obligation', 'override_event', 'ct', 'ca', 'budget_rule', 'owner_committed', 'conditional', 'transfer_test'],
  verdict: ['PASS-SAFE', 'PASS-UNSAFE', 'HOLD', 'FAIL-STOP'],
};
// Constrained-string fields with NO closed vocabulary in the design — validated only as non-empty strings +
// (for disposition) the known §5c letter set, without inventing an exhaustive enum for a manifest schema.
const DISPOSITION_LETTERS = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

export function validateManifest(m) {
  const errors = [];
  const req = (k, cond, msg) => { if (!cond) errors.push(msg || `missing/invalid: ${k}`); };

  req('model_year', m?.model_year === 2026, 'model_year must be 2026');
  req('as_of_model_week', Number.isInteger(m?.as_of_model_week) && m.as_of_model_week >= 1 && m.as_of_model_week <= 31, 'as_of_model_week 1..31');
  req('coverage_horizon_end', Number.isInteger(m?.coverage_horizon_end), 'coverage_horizon_end integer');
  if (Number.isInteger(m?.coverage_horizon_end) && Number.isInteger(m?.as_of_model_week) && m.coverage_horizon_end < m.as_of_model_week) {
    errors.push('coverage_horizon_end must be >= as_of_model_week (frontier-relative horizon, §13/§14)');
  }
  req('operating_floor_cents', isIntegerCents(m?.operating_floor_cents) && m.operating_floor_cents >= 0, 'operating_floor_cents integer cents (owner-confirmed, §2 CONTROL)');
  req('live_chk_selected_basis', CLOSED.live_chk_selected_basis.includes(m?.live_chk_selected_basis), 'live_chk_selected_basis posted_current|available');
  req('live_chk_displayed_balance_cents', isIntegerCents(m?.live_chk_displayed_balance_cents) && m.live_chk_displayed_balance_cents >= 0, 'live_chk_displayed_balance_cents integer cents');
  req('live_chk_capture_ts', typeof m?.live_chk_capture_ts === 'string' && m.live_chk_capture_ts.length > 0, 'live_chk_capture_ts required');
  req('normalized_opening_chk_cents', isIntegerCents(m?.normalized_opening_chk_cents), 'normalized_opening_chk_cents integer cents');
  req('wendy_ira_amount_cents', isIntegerCents(m?.wendy_ira_amount_cents) && m.wendy_ira_amount_cents > 0, 'wendy_ira_amount_cents integer cents > 0 (no capacity-only mode, §2 D)');
  req('wendy_ira_intended_date', typeof m?.wendy_ira_intended_date === 'string' && m.wendy_ira_intended_date.length > 0, 'wendy_ira_intended_date required (§2 D)');
  req('wendy_ira_expected_posting', typeof m?.wendy_ira_expected_posting === 'string' && m.wendy_ira_expected_posting.length > 0, 'wendy_ira_expected_posting required (date | conservative)');

  if (!Array.isArray(m?.effective_schedule_events)) {
    errors.push('effective_schedule_events must be an array');
  } else {
    m.effective_schedule_events.forEach((e, i) => {
      if (!e?.event_id) errors.push(`event[${i}] missing event_id`);
      if (!e?.content_digest) errors.push(`event[${i}] missing content_digest`);
      if (!CLOSED.direction.includes(e?.direction)) errors.push(`event[${i}] direction debit|credit`);
      if (!isIntegerCents(e?.amount_cents) || e.amount_cents <= 0) errors.push(`event[${i}] amount_cents integer cents > 0`);
      if (!CLOSED.channel.includes(e?.channel)) errors.push(`event[${i}] channel not in closed vocabulary`);
    });
  }

  // constrained-string semantic checks where the design fixes no closed vocabulary
  for (const row of m?.bank_to_schedule_reconciliation ?? []) {
    if (row?.disposition != null && !DISPOSITION_LETTERS.includes(row.disposition)) {
      errors.push(`bank_to_schedule disposition "${row.disposition}" not a recognized §5c disposition letter`);
    }
    if (row?.match_method != null && (typeof row.match_method !== 'string' || row.match_method.length === 0)) {
      errors.push('bank_to_schedule match_method must be a non-empty constrained string');
    }
  }
  if (m?.verdict != null && !CLOSED.verdict.includes(m.verdict)) errors.push('verdict not in closed taxonomy (§12)');

  return { ok: errors.length === 0, errors };
}

export const MANIFEST_CLOSED_ENUMS = CLOSED;
