// baseline-E/harness/parity.mjs
// Design ref: spec §1e — parity harness INTERFACE + closed difference catalogue + local fixtures.
// LIVE parity against the deployed runModel (production data) is an AUTHORIZED-CAPTURE-time step: NOT run here.

export const LIVE_PARITY_EVIDENCE = 'PENDING_AUTHORIZED_CAPTURE';

// Closed catalogue (§1e): the ONLY permitted difference classes. Any cash-affecting or uncatalogued
// difference ⇒ FAIL-STOP. Prose cannot waive a cash difference.
export const PARITY_DIFFERENCE_CATALOGUE = Object.freeze([
  'intentionally_excluded_discretionary_waterfall',
  'owner_input_only_event_not_in_app_engine',
  'conservative_timing_relocation_unchanged_amount',
  'explicitly_modeled_bank_seam_adjustment',
  'explicitly_excluded_conditional_credit',
]);

// Event-level parity reconciliation. `differenceClassifications` maps an event_id present on exactly one side
// to one catalogue class with evidence. Returns { ok, verdict, unexplained[] }.
export function reconcileParity({ scriptEvents = [], engineEvents = [], differenceClassifications = {} }) {
  const byId = (arr) => new Map(arr.map((e) => [e.event_id, e]));
  const s = byId(scriptEvents), g = byId(engineEvents);
  const unexplained = [];

  const check = (id, side) => {
    const cls = differenceClassifications[id];
    if (!cls || !PARITY_DIFFERENCE_CATALOGUE.includes(cls.class)) {
      unexplained.push({ event_id: id, side, reason: cls ? `uncatalogued class "${cls.class}"` : 'unexplained difference' });
    } else if (cls.cash_affecting) {
      unexplained.push({ event_id: id, side, reason: 'cash-affecting difference cannot be waived' });
    }
  };
  for (const id of s.keys()) if (!g.has(id)) check(id, 'script_only');
  for (const id of g.keys()) if (!s.has(id)) check(id, 'engine_only');
  // amount/direction mismatch on a shared id is always a cash difference ⇒ unexplained
  for (const id of s.keys()) if (g.has(id)) {
    const a = s.get(id), b = g.get(id);
    if (a.amount_cents !== b.amount_cents || a.direction !== b.direction) {
      unexplained.push({ event_id: id, side: 'both', reason: 'shared-id amount/direction mismatch (cash difference)' });
    }
  }

  return unexplained.length === 0
    ? { ok: true, verdict: 'PARITY_OK', unexplained: [] }
    : { ok: false, verdict: 'FAIL-STOP', unexplained };
}
