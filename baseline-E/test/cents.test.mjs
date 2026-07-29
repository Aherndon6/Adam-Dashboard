// Design ref: §8 decimal→cents contract. Covers §17 tests 27 & 41 (money validation, cent-boundary exactness).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseMoneyToken, canonicalizeNumberToCents, canonicalizeEventsJsonAmount, MoneyError } from '../src/cents.mjs';

test('§17-41 exact decimal tokens → integer cents', () => {
  assert.equal(parseMoneyToken('707.18'), 70718);
  assert.equal(parseMoneyToken('5816.5'), 581650);   // 1 dp padded to 2
  assert.equal(parseMoneyToken('0'), 0);
  assert.equal(parseMoneyToken('0.10'), 10);
  assert.equal(parseMoneyToken('-12.30', { allowNegative: true }), -1230);
});

test('§17-41 field sign enforcement', () => {
  assert.throws(() => parseMoneyToken('-5.00', { field: 'obligation' }), MoneyError); // negative forbidden by default
  assert.equal(parseMoneyToken('-5.00', { allowNegative: true }), -500);
});

test('§17-41 rejects >2 dp / exponent / malformed / non-finite', () => {
  assert.throws(() => parseMoneyToken('12.345'), MoneyError);     // 3 dp
  assert.throws(() => parseMoneyToken('1e3'), MoneyError);        // exponent
  assert.throws(() => parseMoneyToken('1,234.00'), MoneyError);   // thousands separator
  assert.throws(() => parseMoneyToken('abc'), MoneyError);
  assert.throws(() => parseMoneyToken('Infinity'), MoneyError);
  assert.throws(() => parseMoneyToken(''), MoneyError);
});

test('§17-41 float contamination fail-closed (0.1 + 0.2)', () => {
  assert.throws(() => canonicalizeNumberToCents(0.1 + 0.2), MoneyError); // "0.30000000000000004" → >2dp reject
  assert.equal(canonicalizeNumberToCents(5816.5), 581650);
  assert.throws(() => canonicalizeNumberToCents(12.345), MoneyError);
  assert.throws(() => canonicalizeNumberToCents(1e21), MoneyError);      // exponent form
  assert.throws(() => canonicalizeNumberToCents(Infinity), MoneyError);
});

test('§17-41 half-cent boundary rejected via number path', () => {
  assert.throws(() => canonicalizeNumberToCents(0.125), MoneyError); // "0.125" → 3dp reject (no ambiguous rounding)
});

test('§8 events_json amount: decimal-token path preferred; JS number canonicalized fail-closed', () => {
  assert.deepEqual(canonicalizeEventsJsonAmount('707.18'), { cents: 70718, path: 'decimal_token' });
  assert.deepEqual(canonicalizeEventsJsonAmount(707.18), { cents: 70718, path: 'js_number_canonicalized' });
  assert.throws(() => canonicalizeEventsJsonAmount(0.1 + 0.2), MoneyError);
});

test('§17-41 cent-boundary accumulation exactness (no float drift)', () => {
  let sum = 0;
  for (let i = 0; i < 1000; i++) sum += parseMoneyToken('0.01');
  assert.equal(sum, 1000); // exactly $10.00, no drift
});
