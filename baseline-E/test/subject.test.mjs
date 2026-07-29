// rev-6.1 §B/§3/§9 — subject_or_role_id validation (UUID v4 only; role disabled).
// All fixtures derive from the documented SYNTHETIC test-only UUID (locally generated via crypto.randomUUID;
// not derived from any real identifier). Negative fixtures are programmatic transforms of the synthetic UUID.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateSubjectId } from '../src/subject.mjs';

const SYNTH = '2e6f8777-94c8-420e-aa20-c0c481d7ce5a'; // synthetic v4 (variant a); test-only
const V4 = `user:${SYNTH}`;
const badVersion = `user:${SYNTH.replace('-420e-', '-120e-')}`;   // version nibble 4 → 1 (not v4)
const badVariant = `user:${SYNTH.replace('-aa20-', '-cc20-')}`;   // variant nibble a → c (not RFC-4122)
const upper = `user:${SYNTH.toUpperCase()}`;                       // non-canonical uppercase

test('valid user:<canonical v4 uuid> accepted, round-trip', () => {
  const r = validateSubjectId(V4);
  assert.equal(r.ok, true); assert.equal(r.uuid_version, '4'); assert.equal(r.subject_id_format_version, 'subjid-v1a');
});
test('role:<...> disabled this generation ⇒ throw', () => { assert.throws(() => validateSubjectId('role:owner')); });
test('non-v4 UUID version rejected', () => { assert.throws(() => validateSubjectId(badVersion)); });
test('non-RFC-4122 variant rejected', () => { assert.throws(() => validateSubjectId(badVariant)); });
test('uppercase / whitespace / "@" / untagged rejected', () => {
  assert.throws(() => validateSubjectId(upper));
  assert.throws(() => validateSubjectId(' ' + V4));
  assert.throws(() => validateSubjectId('user:a@b'));
  assert.throws(() => validateSubjectId(SYNTH)); // untagged
});
