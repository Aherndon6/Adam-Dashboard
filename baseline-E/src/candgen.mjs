// baseline-E/src/candgen.mjs
// rev-6.1 §C/§D — frozen candgen-v1 manifest + recall windows. Recall is deliberately broad; never affects IS-1.
import { descriptionTokenMatch, etDayDiff, canonicalizationVersion, CanonError } from './canon.mjs';

// Frozen owner-selected values (rev-6.1 §C/§D). candgen-v1 manifest. canonicalization_version binds the
// pinned casefold provenance (rev-6.1 §2/§D: canonicalization/runtime dependencies).
export const CANDGEN_V1 = Object.freeze({
  candidate_generation_version: 'candgen-v1',
  date_proximity_days: 14,                              // ±14 ET calendar days, inclusive
  model_week_proximity: 'full_retained_horizon',
  expected_date_interval: 'authoritative_event_window_inclusive',
  description_token: 'unicode_ws_split_nfc_casefold_exact_v1', // encodes ws-split + NFC + full case fold + exact-token
  window_boundaries: 'inclusive_inclusive',
  day_truncation: 'America/New_York:local_calendar_date:v1',
  coverage_policy_version: 'coverage-v1',
  coverage_policy: Object.freeze({ min_model_weeks: 8, min_paycheck_cycles: 2, min_card_statement_cycles: 2 }),
  canonicalization_version: canonicalizationVersion(),  // pinned Unicode 15.1.0 full-casefold provenance (N-6)
});

// Deep exact-equality against the frozen constant (closed manifest). Rejects missing, undefined/null, extra
// keys, altered types/values, weakened thresholds, or caller overrides. Missing/mismatched ⇒ prohibit E;
// false "complete" ⇒ FAIL-STOP (§D).
function deepEqual(a, b) {
  if (a === b) return true;
  if (typeof a !== 'object' || typeof b !== 'object' || a === null || b === null) return false;
  const ka = Object.keys(a), kb = Object.keys(b);
  if (ka.length !== kb.length) return false;
  return ka.every((k) => Object.prototype.hasOwnProperty.call(b, k) && deepEqual(a[k], b[k]));
}
export function validateCandgenManifest(m) {
  const errors = [];
  if (!m || typeof m !== 'object') return { ok: false, errors: ['candgen manifest not an object'], canonicalization_version: CANDGEN_V1.canonicalization_version };
  const expectedKeys = Object.keys(CANDGEN_V1);
  for (const k of expectedKeys) {
    if (!Object.prototype.hasOwnProperty.call(m, k)) { errors.push(`candgen manifest missing ${k}`); continue; }
    if (m[k] === undefined || m[k] === null) { errors.push(`candgen manifest ${k} is undefined/null`); continue; }
    if (!deepEqual(m[k], CANDGEN_V1[k])) errors.push(`candgen manifest ${k} != frozen candgen-v1 value`);
  }
  for (const k of Object.keys(m)) if (!expectedKeys.includes(k)) errors.push(`candgen manifest has unexpected key ${k} (closed manifest)`);
  return { ok: errors.length === 0, errors, canonicalization_version: CANDGEN_V1.canonicalization_version };
}

// Recall candidate generation (amount-independent), FAIL-CLOSED on horizon membership (item I).
// Returns { candidates, exhaustive }. exhaustive === false whenever ANY event lacks a validated boolean
// in_retained_horizon — so unknown/malformed membership PROHIBITS disposition E (never silently enables it),
// and an in-horizon event is ALWAYS a candidate (full_retained_horizon; model-week distance never excludes).
export function generateCandidates({ bankTxn, events, manifest = CANDGEN_V1 }) {
  const v = validateCandgenManifest(manifest);
  if (!v.ok) throw new CanonError(`candgen manifest invalid: ${v.errors.join('; ')}`);
  const out = [];
  let exhaustive = true;
  for (const ev of events) {
    const membership = ev.in_retained_horizon;
    if (membership !== true && membership !== false) exhaustive = false; // unknown/malformed ⇒ not provably exhaustive
    let signal = membership === true;                                    // in-horizon event is always a candidate
    if (!signal && ev.expected_position && bankTxn.posted_at) {
      try { signal = Math.abs(etDayDiff(ev.expected_position, bankTxn.posted_at)) <= manifest.date_proximity_days; } catch { /* invalid instant ⇒ no date signal */ }
    }
    if (!signal && descriptionTokenMatch(bankTxn.description, ev.description)) signal = true;
    if (!signal && ev.recall_identity_signal === true) signal = true;
    // An unknown-membership event with NO recall signal is not a candidate; this is safe because
    // `exhaustive=false` (set above) already prohibits disposition E, so it can never cause a false no-match.
    if (signal) out.push(ev);
  }
  return { candidates: out, exhaustive };
}
