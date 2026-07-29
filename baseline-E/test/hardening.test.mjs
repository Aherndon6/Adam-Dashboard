// rev-6.1a hardening: B5 semantic date validation (N-2), candgen manifest field mutation (N-3),
// missing evidence_root fail-closed (cleanup 5), lp empty-string (cleanup 4).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonExpectedDateInterval, parseCanonicalDateTime, CanonError } from '../src/canon.mjs';
import { CANDGEN_V1, validateCandgenManifest } from '../src/candgen.mjs';
import { classify } from '../src/match.mjs';
import { isIdentityStrong } from '../src/identity.mjs';
import { lp, NULL_SENTINEL, FramingError } from '../src/framing.mjs';

// ── N-2 B5 semantic date/time validation ─────────────────────────────────────────────────────────────
test('B5 valid interval accepted + canonicalized', () => {
  assert.equal(canonExpectedDateInterval({ start: '2026-07-01', end: '2026-07-15' }), '2026-07-01T00:00:00.000Z|2026-07-15T00:00:00.000Z');
});
test('B5 impossible date Feb-30 rejected (no rollover)', () => {
  assert.throws(() => canonExpectedDateInterval({ start: '2026-02-30', end: '2026-03-01' }), CanonError);
  assert.throws(() => parseCanonicalDateTime('2026-02-30'), CanonError);
});
test('B5 invalid month / hour / minute / second rejected', () => {
  assert.throws(() => parseCanonicalDateTime('2026-13-01'), CanonError);
  assert.throws(() => parseCanonicalDateTime('2026-01-01T25:00:00.000Z'), CanonError);
  assert.throws(() => parseCanonicalDateTime('2026-01-01T00:60:00.000Z'), CanonError);
  assert.throws(() => parseCanonicalDateTime('2026-01-01T00:00:61.000Z'), CanonError);
});
test('B5 noncanonical timezone form rejected', () => {
  assert.throws(() => parseCanonicalDateTime('2026-01-01T00:00:00+00:00'), CanonError);
  assert.throws(() => parseCanonicalDateTime('2026-01-01T00:00:00'), CanonError); // no Z
});
test('B5 start after end rejected', () => {
  assert.throws(() => canonExpectedDateInterval({ start: '2026-07-15', end: '2026-07-01' }), CanonError);
});
test('B5 boundary-valid leap date accepted; non-leap Feb-29 rejected', () => {
  assert.doesNotThrow(() => parseCanonicalDateTime('2028-02-29')); // 2028 is a leap year
  assert.throws(() => parseCanonicalDateTime('2026-02-29'), CanonError); // 2026 not leap
});

// ── N-3 candgen-v1 manifest full validation ──────────────────────────────────────────────────────────
test('candgen manifest: exact frozen constant is valid', () => { assert.equal(validateCandgenManifest(CANDGEN_V1).ok, true); });
test('candgen manifest: EVERY pinned field mutation ⇒ invalid', () => {
  for (const k of Object.keys(CANDGEN_V1)) {
    const bad = { ...CANDGEN_V1, [k]: (typeof CANDGEN_V1[k] === 'number') ? CANDGEN_V1[k] + 1 : (typeof CANDGEN_V1[k] === 'object' ? { mutated: true } : CANDGEN_V1[k] + '_x') };
    assert.equal(validateCandgenManifest(bad).ok, false, `mutating ${k} should invalidate`);
  }
});
test('candgen manifest: missing field / undefined value / extra key ⇒ invalid', () => {
  const miss = { ...CANDGEN_V1 }; delete miss.date_proximity_days;
  assert.equal(validateCandgenManifest(miss).ok, false);
  assert.equal(validateCandgenManifest({ ...CANDGEN_V1, date_proximity_days: undefined }).ok, false);
  assert.equal(validateCandgenManifest({ ...CANDGEN_V1, extra_key: 1 }).ok, false);
  assert.equal(validateCandgenManifest({ ...CANDGEN_V1, coverage_policy: { min_model_weeks: 1, min_paycheck_cycles: 1, min_card_statement_cycles: 1 } }).ok, false); // weakened thresholds
});

// ── cleanup 5: missing evidence_root fail-closed (no crash) ──────────────────────────────────────────
const bank = { amount_cents: 5000, direction: 'credit' };
const goodA = (s) => ({ type: 'bank_reference', canonical_value_digest: 'a'.repeat(64), anchor_evidence_digest: 'b'.repeat(64), evidence_root_digest: (s + '').padStart(64, '0'), evidence_root: { source_system: 's' + s, source_record_digest: (s + 'r').padStart(64, '0'), source_field: 'f', derivation_method: 'direct_read' } });
test('missing evidence_root: non-authoritative anchor excluded (no crash) ⇒ not strong', () => {
  const noRoot = { type: 'source_system_identity' }; // no evidence_root
  assert.equal(isIdentityStrong([noRoot, goodA(1)]).strong, false);
});
test('missing evidence_root: authoritative anchor ⇒ FAIL-STOP (N-1), not a raw crash', () => {
  const noRoot = { type: 'bank_reference', authoritative_role: true };
  const r = classify({ bankTxn: { ...bank, bank_transaction_id: 't1' }, candidates: [{ event_id: 'e1', event: { amount_cents: 5000, direction: 'credit' }, anchors: [noRoot, goodA(2)] }] });
  assert.equal(r.code, 'N1_AUTHORITATIVE_NO_PROVENANCE');
});

// ── cleanup 4: lp rejects empty required string; null sentinel still works ────────────────────────────
test('lp rejects empty string; accepts null sentinel buffer', () => {
  assert.throws(() => lp(''), FramingError);
  assert.throws(() => lp(undefined), FramingError);
  assert.doesNotThrow(() => lp(NULL_SENTINEL));
  assert.doesNotThrow(() => lp('x'));
});
