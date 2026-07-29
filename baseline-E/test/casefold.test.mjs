// rev-6.1 §C.4 (owner Option-1): Unicode 15.1.0 FULL case folding conformance + runtime-independence.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fullCaseFold, CASEFOLD_UNICODE_VERSION, CASEFOLD_SOURCE_SHA256 } from '../src/casefold.mjs';
import { tokenizeDescription } from '../src/canon.mjs';

test('provenance: pinned Unicode 15.1.0 + recorded source sha', () => {
  assert.equal(CASEFOLD_UNICODE_VERSION, '15.1.0');
  assert.equal(CASEFOLD_SOURCE_SHA256, '4e55acfdc32825a22e87670e9056a3bf94ad7c5400065778e9e10f8314372bcf');
});

test('conformance vectors: ẞ/ß→ss, ſ→s, ﬀ→ff, I→i, i→i, İ→i̇, ı→ı', () => {
  assert.equal(fullCaseFold('ẞ'), 'ss');           // U+1E9E full
  assert.equal(fullCaseFold('ß'), 'ss');           // U+00DF full
  assert.equal(fullCaseFold('ſ'), 's');            // U+017F common
  assert.equal(fullCaseFold('ﬀ'), 'ff');           // U+FB00 full
  assert.equal(fullCaseFold('I'), 'i');            // ASCII
  assert.equal(fullCaseFold('i'), 'i');            // ASCII (no fold entry)
  assert.equal(fullCaseFold('İ'), 'i̇');      // U+0130 default (non-Turkic) F mapping = i + COMBINING DOT ABOVE
  assert.equal(fullCaseFold('ı'), 'ı');            // U+0131 default (non-Turkic): no fold, unchanged
});

test('multi-code-point full mapping not in the base examples: ﬃ → ffi', () => {
  assert.equal(fullCaseFold('ﬃ'), 'ffi');          // U+FB03 → 0066 0066 0069
});

test('NFC-sensitive equivalence via tokenizer (NFC then fold): precomposed ≡ decomposed', () => {
  assert.deepEqual(tokenizeDescription('É'), tokenizeDescription('É')); // both → ["é"]
  assert.deepEqual(tokenizeDescription('É'), ['é']);
});

test('runtime-independence: result is table-driven (ẞ→ss), NOT String.prototype.toLowerCase (ẞ→ß)', () => {
  assert.equal(fullCaseFold('ẞ'), 'ss');
  assert.notEqual('ẞ'.toLowerCase(), 'ss');        // proves the pinned table, not the runtime, governs folding
});
