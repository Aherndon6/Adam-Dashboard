// baseline-E/parity/adapter.mjs
// ADAPTER (clearly labeled — this is NOT oracle code). Maps ONE canonical synthetic fixture into:
//   A. the application-oracle input  (a bare 'YYYY-MM-DD' calendar-date string), and
//   B. the Baseline E input          (a canonical UTC instant + ET-derived values via the REAL canon.mjs).
//
// Every transformation is explicit and recorded in `transforms[]`. No silent coercion. Malformed/incomplete
// fixtures are rejected deterministically (never guessed, never rolled over).
//
// KEY SEMANTIC FACT established in Phase 1 (documented in docs/baseline-e-adapter-differential-oracle.md):
//   * The application has NO timestamp->calendar-date truncation in its placement path. `dateToModelWeek`
//     consumes a bare calendar date produced upstream by an <input type="date"> (validated by isValidISODate).
//   * Baseline E's date contract IS "America/New_York:local_calendar_date:v1" (canon.etLocalDate).
//   Therefore the adapter applies ET truncation to derive the app's calendar-date input. This ET-truncation
//   step is the *parity contract*: the app defers date derivation to whatever fed the picker; Baseline E fixes
//   it to ET. The differential then proves the app's WEEK/BAND placement of that ET date agrees with Baseline
//   E's independent (ET-truncate + pure UTC calendar math) placement, and that this holds under every TZ.
import { etLocalDate, isCanonicalUtcMs, parseCanonicalDateTime, canonExpectedDateInterval, etDayDiff, CanonError } from '../src/canon.mjs';

export class AdapterRejection extends Error { constructor(code, msg) { super(msg); this.code = code; } }

const TXN_TYPES = new Set(['debit', 'credit', 'transfer_debit', 'transfer_credit', 'card_statement', 'card_payment', 'goal_disbursement', 'reimbursement_inflow']);

// ── Baseline E model-week interpretation: ET-truncate, then PURE UTC-integer calendar math banded to the shared
//    epoch. TZ-invariant by construction (no local-time Date arithmetic). This is the independent oracle used to
//    cross-check the application's local-time `dateToModelWeek`. ─────────────────────────────────────────────
const EPOCH_UTC = Date.UTC(2026, 5, 7);       // model week-1 start (Jun 7 2026), pure UTC midnight
const BAND_END_UTC = Date.UTC(2027, 0, 9);    // model week-31 end (Jan 9 2027), inclusive
const MS_WEEK = 604800000;

function ymdToUtcMidnight(ymd) {
  if (typeof ymd !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(ymd)) return null;
  const [y, m, d] = ymd.split('-').map(Number);
  const t = Date.UTC(y, m - 1, d);
  const dt = new Date(t);
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null; // reject rollover
  return t;
}
export function beRefModelWeek(ymd) {
  const t = ymdToUtcMidnight(ymd);
  if (t === null) return { week: null, in_band: false, reason: 'invalid_date' };
  if (t < EPOCH_UTC) return { week: null, in_band: false, reason: 'before_band' };
  if (t > BAND_END_UTC) return { week: null, in_band: false, reason: 'after_band' };
  return { week: Math.floor((t - EPOCH_UTC) / MS_WEEK) + 1, in_band: true, reason: 'in_band' };
}
export const BE_RETAINED_HORIZON = { first_week: 1, last_week: 31, first_day: '2026-06-07', last_day: '2027-01-09' };

// ── fixture validation ───────────────────────────────────────────────────────────────────────────────────
function requireFixtureShape(fx) {
  if (!fx || typeof fx !== 'object') throw new AdapterRejection('FX_NOT_OBJECT', 'fixture is not an object');
  if (typeof fx.id !== 'string' || !/^PX-\d{2}$/.test(fx.id)) throw new AdapterRejection('FX_BAD_ID', `fixture id must be synthetic PX-NN (got ${JSON.stringify(fx.id)})`);
  if (typeof fx.cls !== 'string' || fx.cls.length === 0) throw new AdapterRejection('FX_NO_CLASS', `${fx.id}: missing class`);
  if (fx.txn_type !== undefined && !TXN_TYPES.has(fx.txn_type)) throw new AdapterRejection('FX_BAD_TXN_TYPE', `${fx.id}: unknown txn_type ${fx.txn_type}`);
  if (fx.cleared !== undefined && typeof fx.cleared !== 'boolean') throw new AdapterRejection('FX_BAD_CLEARED', `${fx.id}: cleared must be boolean`);
}

// Map a canonical fixture -> both inputs, recording each transformation. Never throws for *expected* rejections;
// returns { rejected:{...} } for those, and only throws AdapterRejection for malformed FIXTURE STRUCTURE.
export function adapt(fx) {
  requireFixtureShape(fx);
  const transforms = [];
  const out = { id: fx.id, cls: fx.cls, txn_type: fx.txn_type ?? null, cleared: fx.cleared ?? null };

  // 1. canonical-UTC gate (Baseline E requires an RFC-3339 ms-Z instant that round-trips)
  const inst = fx.instant_utc;
  const canonical_utc = typeof inst === 'string' ? isCanonicalUtcMs(inst) : false;
  out.instant_utc = typeof inst === 'string' ? inst : null;
  out.canonical_utc = canonical_utc;
  transforms.push(`canonical_utc_gate: isCanonicalUtcMs(${JSON.stringify(inst)}) = ${canonical_utc}`);

  // 2. deterministic rejection for malformed/incomplete date inputs
  if (fx.expect_reject) {
    // BE side: prove it fails-closed; app side: prove its acceptance gate (isValidISODate) also rejects the naive date
    let be_reason = null;
    try { etLocalDate(inst); be_reason = 'ET_ACCEPTED_UNEXPECTED'; } catch (e) { be_reason = e instanceof CanonError ? 'CANON_ERROR' : 'THROW'; }
    if (canonical_utc) be_reason = be_reason === 'CANON_ERROR' ? be_reason : 'CANONICAL_BUT_FLAGGED';
    out.rejected = { code: fx.expect_reject, be_canonical_utc: canonical_utc, be_reason };
    transforms.push(`expected-reject class: canonical_utc=${canonical_utc}, be_reason=${be_reason}`);
    out.transforms = transforms;
    return out;
  }

  // 3. ET calendar-date truncation (the shared parity contract). Requires a canonical instant.
  if (!canonical_utc) throw new AdapterRejection('NONCANONICAL_INSTANT', `${fx.id}: instant_utc is not canonical RFC-3339 ms Z: ${JSON.stringify(inst)}`);
  const etDate = etLocalDate(inst);
  transforms.push(`ET truncation (America/New_York:local_calendar_date:v1): etLocalDate = ${etDate}`);
  out.et_date = etDate;

  // A. application-oracle input: the ET calendar date fed to the app's picker-equivalent
  out.app_input = { date_str: etDate };
  transforms.push(`app_input.date_str <- ET date (app has no truncation of its own; ET is the contract): ${etDate}`);

  // B. Baseline E interpretation of that instant
  out.be = { et_date: etDate, model_week: beRefModelWeek(etDate) };
  transforms.push(`be.model_week <- beRefModelWeek(${etDate}) = ${JSON.stringify(out.be.model_week)}`);

  // ±14 ET-day candidate proximity (Baseline-E-only concept; app has NO counterpart)
  if (typeof fx.anchor_instant_utc === 'string') {
    if (!isCanonicalUtcMs(fx.anchor_instant_utc)) throw new AdapterRejection('BAD_ANCHOR', `${fx.id}: anchor_instant_utc not canonical`);
    const diff = etDayDiff(inst, fx.anchor_instant_utc);
    out.be.candidate_proximity = { et_day_diff: diff, within_14_inclusive: Math.abs(diff) <= 14, anchor: fx.anchor_instant_utc };
    transforms.push(`be.candidate_proximity: etDayDiff=${diff}, |diff|<=14 = ${Math.abs(diff) <= 14} (APP: no counterpart)`);
  }

  // expected-date interval (Baseline-E-only concept; app analog = per-endpoint band placement)
  if (fx.expected_date_interval) {
    let canon = null, err = null;
    try { canon = canonExpectedDateInterval(fx.expected_date_interval); } catch (e) { err = e.message; }
    out.be.expected_date_interval = { input: fx.expected_date_interval, canonical: canon, error: err };
    // app analog: band each endpoint via the app oracle (done in differential.mjs); record intent
    transforms.push(`be.expected_date_interval: canon=${JSON.stringify(canon)} err=${err ?? 'none'}`);
  }

  out.cleared_note = 'cleared/pending does NOT affect date/model-week placement in either side (invariant)';
  out.transforms = transforms;
  return out;
}
