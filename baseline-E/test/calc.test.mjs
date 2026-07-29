// Design ref: §9/§10/§12. Covers §17 tests 1,2,3,4,15,16,17,48,49,64 and the §9 self-verification cases.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { analyze, verdictForTransfer, projectionTrough, FLOOR_CENTS } from '../src/calc.mjs';

// Fixture 1 — clean above-floor baseline; transfer at position 0.
const F1 = { opening_cents: 2000000, eventsA: [-500000, 580000, -300000], transfer_position: 0 };
// balancesA: 1500000, 2080000, 1780000 → troughA=1500000; maxSafe=1500000-650000=850000

test('§17-1 no-transfer baseline: B==A at 0', () => {
  const troughA = projectionTrough(F1.opening_cents, F1.eventsA);
  const { troughB } = verdictForTransfer({ ...F1, transfer_cents: 0 });
  assert.equal(troughB, troughA);
});

test('§17-2 transfer before trough: troughB = troughA − amount', () => {
  const troughA = projectionTrough(F1.opening_cents, F1.eventsA);
  const { troughB } = verdictForTransfer({ ...F1, transfer_cents: 100000 });
  assert.equal(troughB, troughA - 100000);
});

test('§17-15/48 exact floor equality at max-safe ⇒ PASS-SAFE; §9 case A self-verify', () => {
  const a = analyze(F1);
  assert.equal(a.maxSafe, 850000);
  assert.equal(a.selfVerify.case, 'A');
  assert.equal(a.selfVerify.ok, true);
  assert.equal(a.selfVerify.atMax, FLOOR_CENTS);              // trough exactly at floor
  const { verdict } = verdictForTransfer({ ...F1, transfer_cents: a.maxSafe });
  assert.equal(verdict, 'PASS-SAFE');                          // trough == floor ⇒ PASS-SAFE (≥)
});

test('§17-16/49 max-safe + 1¢ ⇒ PASS-UNSAFE (one-cent breach)', () => {
  const a = analyze(F1);
  assert.ok(a.selfVerify.atMaxPlus < FLOOR_CENTS);
  const { verdict } = verdictForTransfer({ ...F1, transfer_cents: a.maxSafe + 1 });
  assert.equal(verdict, 'PASS-UNSAFE');
});

// Fixture 2 — pre-transfer breach: the global min is BEFORE the transfer position.
const F2 = { opening_cents: 2000000, eventsA: [-1500000, 1600000, -200000], transfer_position: 2 };
// balancesA: 500000, 2100000, 1900000 → troughA=500000 (<floor), preTransferTrough=500000 → breach

test('§17-3 transfer after an earlier trough: global governs; pre-transfer breach ⇒ max-safe 0, PASS-UNSAFE', () => {
  const a = analyze(F2);
  assert.equal(a.breach, true);
  assert.equal(a.maxSafe, 0);
  assert.equal(a.selfVerify.case, 'B');
  assert.equal(a.selfVerify.reason, 'pre_transfer_breach');
  assert.equal(a.selfVerify.ok, true);
  const { verdict } = verdictForTransfer({ ...F2, transfer_cents: 100000 });
  assert.equal(verdict, 'PASS-UNSAFE');
});

// Fixture 3 — non-negativity CLAMP (rev-5 MR-1): pre-transfer ≥ floor but at/after baseline min < floor.
const F3 = { opening_cents: 2000000, eventsA: [100000, -1500000], transfer_position: 1 };
// balancesA: 2100000, 600000 → troughA=600000; preTransferTrough=2000000 (no breach); atAfterMin=600000

test('§17-64 zero max-safe via post-transfer-position clamp ⇒ PASS-UNSAFE (NOT FAIL-STOP)', () => {
  const a = analyze(F3);
  assert.equal(a.breach, false);
  assert.equal(a.maxSafe, 0);                       // clamp: max(0, 600000−650000)
  assert.equal(a.selfVerify.case, 'B');
  assert.equal(a.selfVerify.reason, 'non_negativity_clamp');
  assert.equal(a.selfVerify.ok, true);              // A/B reconcile at $0; not a FAIL-STOP
  const { verdict } = verdictForTransfer({ ...F3, transfer_cents: 1 });
  assert.equal(verdict, 'PASS-UNSAFE');
});

test('§17-17 baseline_capacity clamps to 0 when troughA < floor', () => {
  const a = analyze(F3);
  assert.equal(a.baseline_capacity, 0);
});
