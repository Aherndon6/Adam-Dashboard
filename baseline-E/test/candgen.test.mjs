// rev-6.1 §C/§D + item I — candgen-v1 recall: boundary, DST, full-horizon, tokenization, fail-closed membership.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CANDGEN_V1, validateCandgenManifest, generateCandidates } from '../src/candgen.mjs';
import { etDayDiff, etLocalDate, tokenizeDescription, descriptionTokenMatch } from '../src/canon.mjs';

test('candgen-v1 frozen values', () => {
  assert.equal(CANDGEN_V1.date_proximity_days, 14);
  assert.equal(CANDGEN_V1.model_week_proximity, 'full_retained_horizon');
  assert.deepEqual(CANDGEN_V1.coverage_policy, { min_model_weeks: 8, min_paycheck_cycles: 2, min_card_statement_cycles: 2 });
});
test('manifest validation: complete ⇒ ok; wrong version ⇒ error', () => {
  assert.equal(validateCandgenManifest(CANDGEN_V1).ok, true);
  assert.equal(validateCandgenManifest({ ...CANDGEN_V1, candidate_generation_version: 'x' }).ok, false);
  assert.equal(validateCandgenManifest({ ...CANDGEN_V1, date_proximity_days: 7 }).ok, false);
});
test('date-proximity boundary ±14 ET inclusive; ±15 fails the date signal', () => {
  const bankTxn = { posted_at: '2026-07-01T12:00:00Z', description: '' };
  const near = { expected_position: '2026-07-15T12:00:00Z', in_retained_horizon: false, description: '' };
  const far = { expected_position: '2026-07-16T12:00:00Z', in_retained_horizon: false, description: '' };
  assert.equal(generateCandidates({ bankTxn, events: [near] }).candidates.length, 1);
  assert.equal(generateCandidates({ bankTxn, events: [far] }).candidates.length, 0);
});
test('DST: ET local dates differ by 1 across spring-forward (not elapsed 24h)', () => {
  assert.equal(etDayDiff('2026-03-09T12:00:00Z', '2026-03-08T12:00:00Z'), 1);
  assert.equal(etLocalDate('2026-03-08T06:30:00Z'), '2026-03-08');
});
test('full_retained_horizon: in-horizon event is always a candidate + exhaustive true', () => {
  const bankTxn = { posted_at: '2026-07-01T12:00:00Z', description: '' };
  const far = { expected_position: '2026-12-31T12:00:00Z', in_retained_horizon: true, description: '' };
  const r = generateCandidates({ bankTxn, events: [far] });
  assert.equal(r.candidates.length, 1); assert.equal(r.exhaustive, true);
});
test('item I: unknown/malformed horizon membership ⇒ exhaustive=false (E prohibited); event not silently dropped', () => {
  const bankTxn = { posted_at: '2026-07-01T12:00:00Z', description: 'zelle tiffany' };
  const unknown = { description: 'zelle tiffany' };               // no in_retained_horizon
  const r = generateCandidates({ bankTxn, events: [unknown] });
  assert.equal(r.exhaustive, false);                              // prohibits E
  assert.equal(r.candidates.length, 1);                           // still recalled via token signal (not dropped)
});
test('description tokenization: NFC + FULL casefold + ws-split, exact containment, no punctuation strip', () => {
  assert.deepEqual(tokenizeDescription('  Zelle  TIFFANY  '), ['zelle', 'tiffany']);
  assert.equal(descriptionTokenMatch('rent tiffany', 'ZELLE TIFFANY dye'), true);
  assert.equal(descriptionTokenMatch('tiffany.', 'tiffany'), false);
});
test('description tokenization applies FULL case fold (ẞ→ss), not toLowerCase', () => {
  assert.deepEqual(tokenizeDescription('STRAẞE'), ['strasse']); // ẞ folds to ss under full folding
});
