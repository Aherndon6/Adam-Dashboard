// Design ref: §0(i)/§1a. Covers §17 tests 34 (override replacement), 35 (empty events_json fallback),
// 36 (independent ct/ca/dates), 37 (custom week appended), 38 (duplicate week detected, never collapsed).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mergeEffectiveSchedule } from '../src/adapter.mjs';

// Minimal synthetic WD: [num, dates, inflows, obs, evs, ct, ca, note]
const WD = [
  [11, 'wk11', [5816.5], [5500], [{ l: 'gold', t: 'ob', a: -5500 }, { l: 'pay', t: 'in', a: 5816.5 }], 0, 0, ''],
  [12, 'wk12', [], [], [], 7.0, 3.0, 'note12'],
];

test('§17-34 non-empty override events REPLACE literal events (not add)', () => {
  const { effective } = mergeEffectiveSchedule(WD, [
    { week_num: 11, events_json: [{ l: 'gold-actual', t: 'ob', a: -11501.12 }], is_custom: false },
  ]);
  const w11 = effective.find((e) => e.week_num === 11);
  assert.equal(w11.evs.length, 1);
  assert.equal(w11.obs[0], 11501.12);   // replaced, not merged with the literal 5500
  assert.equal(w11.events_fallback, false);
  assert.equal(w11.source, 'override:11');
});

test('§17-35 empty/absent events_json FALLS BACK to literal events', () => {
  const { effective } = mergeEffectiveSchedule(WD, [
    { week_num: 11, events_json: [], ct: 9, is_custom: false }, // empty events → literal retained; ct still overrides
  ]);
  const w11 = effective.find((e) => e.week_num === 11);
  assert.equal(w11.evs.length, 2);           // literal events retained
  assert.equal(w11.events_fallback, true);
  assert.equal(w11.ct, 9);                    // independent ct override still applied
});

test('§17-36 ct / ca / dates override INDEPENDENTLY', () => {
  const { effective } = mergeEffectiveSchedule(WD, [
    { week_num: 12, dates: 'wk12-edited', ca: 42, is_custom: false }, // no events_json, no ct
  ]);
  const w12 = effective.find((e) => e.week_num === 12);
  assert.equal(w12.dates, 'wk12-edited');
  assert.equal(w12.ct, 7.0);   // literal ct retained (not overridden)
  assert.equal(w12.ca, 42);    // ca overridden independently
});

test('§17-37 is_custom rows APPENDED (not merged), sorted by week_num', () => {
  const { effective } = mergeEffectiveSchedule(WD, [
    { week_num: 33, events_json: [{ l: 'c33', t: 'ob', a: -100 }], is_custom: true },
    { week_num: 32, events_json: [{ l: 'c32', t: 'in', a: 200 }], is_custom: true },
  ]);
  assert.equal(effective.length, WD.length + 2);
  const tail = effective.slice(-2).map((e) => e.week_num);
  assert.deepEqual(tail, [32, 33]);          // appended after base, sorted
});

test('§17-38 duplicate week_num preserved + flagged (never silently collapsed)', () => {
  const dupRows = mergeEffectiveSchedule(WD, [
    { week_num: 11, events_json: [{ l: 'a', t: 'ob', a: -1 }], is_custom: false },
    { week_num: 11, events_json: [{ l: 'b', t: 'ob', a: -2 }], is_custom: false }, // duplicate non-custom row
  ]);
  assert.equal(dupRows.hasDuplicates, true);
  assert.ok(dupRows.duplicates.some((d) => d.week_num === 11));

  const customDup = mergeEffectiveSchedule(WD, [
    { week_num: 12, events_json: [{ l: 'x', t: 'in', a: 5 }], is_custom: true }, // custom sharing base week 12
  ]);
  assert.equal(customDup.hasDuplicates, true); // duplicate EFFECTIVE week_num detected
});
