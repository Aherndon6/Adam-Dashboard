// baseline-E/src/framing.mjs
// rev-6.1 canonical byte framing. Deterministic; dependency-free (node:crypto SHA-256 primitive only).
// lp(x) = u32be(len(utf8(x))) ‖ utf8(x). Domain tags are RAW prefixes consumed first. All hex lowercase.
import { createHash } from 'node:crypto';

export class FramingError extends Error {}

export const NULL_SENTINEL = Buffer.from([0x00, 0x4e, 0x55, 0x4c, 0x4c]); // "\x00NULL" (rev-6.1 §authority null)

export function u32be(n) {
  if (!Number.isInteger(n) || n < 0 || n > 0xffffffff) throw new FramingError(`u32be: bad length ${n}`);
  const b = Buffer.alloc(4);
  b.writeUInt32BE(n, 0);
  return b;
}

// length-prefixed UTF-8 field. Accepts a NON-EMPTY string OR the NULL_SENTINEL buffer (for *_or_null fields).
// Rejects undefined/null AND empty strings for required fields (spec §1: "non-empty string"). This aligns
// the code to the frozen spec and does NOT alter any accepted preimage — a valid preimage never contains an
// empty lp field (ids/digests/versions/directions/int2dec are all non-empty); it only rejects malformed input.
export function lp(x) {
  if (Buffer.isBuffer(x)) return Buffer.concat([u32be(x.length), x]); // null-sentinel / explicit byte fields
  if (x === undefined || x === null) throw new FramingError('lp: required field is undefined/null');
  if (typeof x !== 'string') throw new FramingError(`lp: required field must be a string (got ${typeof x})`);
  if (x.length === 0) throw new FramingError('lp: required string field is empty (spec §1 non-empty)');
  const bytes = Buffer.from(x, 'utf8');
  return Buffer.concat([u32be(bytes.length), bytes]);
}

// canonical non-negative integer → decimal ASCII; no leading '+', no leading zeros except "0"; no "-0".
export function int2dec(n, { allowNegative = false } = {}) {
  if (Object.is(n, -0)) n = 0;    // reject negative zero representation: normalize to canonical 0
  if (!Number.isInteger(n) || !Number.isSafeInteger(n)) throw new FramingError(`int2dec: non-integer ${n}`);
  if (!allowNegative && n < 0) throw new FramingError(`int2dec: negative not allowed (${n})`);
  return String(n);
}

const HEX64 = /^[0-9a-f]{64}$/;
export function assertHex64(h, field = 'digest') {
  if (typeof h !== 'string' || !HEX64.test(h)) throw new FramingError(`${field}: not lowercase 64-hex ("${h}")`);
  return h;
}

// Domain-tagged SHA-256 over a raw domain prefix followed by pre-framed field buffers. Returns lowercase hex.
export function digest(domain, parts) {
  const h = createHash('sha256');
  h.update(Buffer.from(domain, 'utf8'));
  for (const p of parts) h.update(p);
  return h.digest('hex');
}

// ascending lexicographic order over lowercase-hex strings; rejects duplicates (FAIL-STOP before hashing).
export function sortedUniqueHexOrThrow(hexes, field = 'digest_list') {
  const seen = new Set();
  for (const h of hexes) { assertHex64(h, field); if (seen.has(h)) throw new FramingError(`${field}: duplicate ${h}`); seen.add(h); }
  return [...hexes].sort();
}
