// baseline-E/src/canon.mjs
// rev-6.1 anchor canonicalization (N-6) + candgen tokenization + ET day truncation. Fail-closed; no fuzzy.
// Case operations use the PINNED Unicode 15.1.0 full case fold (casefold.mjs), never runtime toLowerCase().
import { fullCaseFold, CASEFOLD_UNICODE_VERSION, CASEFOLD_SOURCE_SHA256, CASEFOLD_GENERATOR_VERSION } from './casefold.mjs';
export class CanonError extends Error {}

// N-6: canonicalization_version binds the PINNED case-fold provenance (Unicode 15.1.0 + source/generator sha),
// so a runtime ICU/Unicode change cannot silently alter folding. NFC uses the runtime (stable by Unicode
// normalization-stability policy for assigned characters).
export function canonicalizationVersion() {
  return `canon-v1|nfc|casefold:unicode-${CASEFOLD_UNICODE_VERSION}|src-sha:${CASEFOLD_SOURCE_SHA256.slice(0, 16)}|gen:${CASEFOLD_GENERATOR_VERSION}|rules:anchor-canon-v1`;
}

const nfc = (s) => s.normalize('NFC');

// Reference/id anchors (A1/A2/A3/A4): NFC + outer trim ONLY. No case-fold, no punctuation strip, no inner
// collapse; leading zeros preserved. Empty/malformed ⇒ CanonError (no qualifying anchor).
export function canonReference(raw) {
  if (typeof raw !== 'string') throw new CanonError('reference: non-string');
  const v = nfc(raw).replace(/^[\s]+|[\s]+$/gu, '');
  if (v === '') throw new CanonError('reference: empty after trim');
  return v;
}

// B3 counterparty (structured field only): NFC + trim + collapse inner whitespace + FULL case fold. No punctuation.
export function canonCounterparty(raw) {
  if (typeof raw !== 'string') throw new CanonError('counterparty: non-string');
  const v = fullCaseFold(nfc(raw).replace(/^[\s]+|[\s]+$/gu, '').replace(/\s+/gu, ' '));
  if (v === '') throw new CanonError('counterparty: empty');
  return v;
}

// B4 classification: exact token from the authoritative vocabulary (caller supplies the closed set).
export function canonClassification(raw, vocabulary) {
  if (typeof raw !== 'string' || !Array.isArray(vocabulary) || !vocabulary.includes(raw)) throw new CanonError(`classification: "${raw}" not in authoritative vocabulary`);
  return raw;
}

// Semantic canonical date/time parser (NOT bare Date.parse): accepts YYYY-MM-DD or
// YYYY-MM-DDTHH:MM:SS[.sss]Z, rejects rollover (e.g. 2026-02-30), impossible month/hour/min/sec, and
// non-canonical timezone forms. Verifies exact round-trip of every component (no silent normalization).
const DT_RE = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{3}))?Z)?$/;
export function parseCanonicalDateTime(s) {
  if (typeof s !== 'string') throw new CanonError('date/time: non-string');
  const m = DT_RE.exec(s);
  if (!m) throw new CanonError(`date/time: not canonical ISO date or UTC ms-Z ("${s}")`);
  const [Y, Mo, D, h, mi, se, ms] = [m[1], m[2], m[3], m[4] ?? '00', m[5] ?? '00', m[6] ?? '00', m[7] ?? '000'].map(Number);
  const d = new Date(Date.UTC(Y, Mo - 1, D, h, mi, se, ms));
  // exact component round-trip — any rollover (Feb-30 → Mar-02, month 13, hour 25 …) fails here
  if (d.getUTCFullYear() !== Y || d.getUTCMonth() !== Mo - 1 || d.getUTCDate() !== D ||
      d.getUTCHours() !== h || d.getUTCMinutes() !== mi || d.getUTCSeconds() !== se || d.getUTCMilliseconds() !== ms) {
    throw new CanonError(`date/time: impossible/rollover value ("${s}")`);
  }
  return d;
}

// B5 expected-date identity: inclusive interval of CANONICAL valid date/time values; start ≤ end;
// canonical representation returned only after round-trip validation of both endpoints.
export function canonExpectedDateInterval(interval) {
  if (!interval || typeof interval.start !== 'string' || typeof interval.end !== 'string') throw new CanonError('expected_date_interval: missing authoritative window');
  const s = parseCanonicalDateTime(interval.start);
  const e = parseCanonicalDateTime(interval.end);
  if (s.getTime() > e.getTime()) throw new CanonError('expected_date_interval: start after end');
  return `${s.toISOString()}|${e.toISOString()}`;
}

// ── candgen description tokenization: "unicode_ws_split_nfc_casefold_exact_v1" (rev-6.1 §C.4) ──────────
// NFC → Unicode 15.1.0 FULL case fold (pinned) → split on Unicode whitespace → drop empties. No punctuation
// strip, no stemming, no fuzzy, no transliteration, no locale-specific Turkic folding, no post-fold normalization.
export function tokenizeDescription(raw) {
  if (typeof raw !== 'string') return [];
  const folded = fullCaseFold(nfc(raw));
  return folded.split(/\s+/u).filter((t) => t.length > 0);
}
export function descriptionTokenMatch(bankDesc, eventDesc) {
  const a = new Set(tokenizeDescription(bankDesc));
  if (a.size === 0) return false;
  return tokenizeDescription(eventDesc).some((t) => a.has(t));
}

// ── ET (America/New_York) local calendar date truncation: "America/New_York:local_calendar_date:v1" ───
const ET_FMT = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit' });
export function etLocalDate(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) throw new CanonError(`etLocalDate: invalid instant "${iso}"`);
  return ET_FMT.format(d);
}
const MS_DAY = 86400000;
export function etDayDiff(isoA, isoB) {
  const [a, b] = [etLocalDate(isoA), etLocalDate(isoB)].map((s) => Date.parse(s + 'T00:00:00Z'));
  return Math.round((a - b) / MS_DAY);
}

// Semantic UTC timestamp (not regex-only): canonical RFC-3339 ms Z that round-trips exactly.
export function isCanonicalUtcMs(ts) {
  if (typeof ts !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(ts)) return false;
  const d = new Date(ts);
  return !Number.isNaN(d.getTime()) && d.toISOString() === ts;
}
