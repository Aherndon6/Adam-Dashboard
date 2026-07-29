// baseline-E/src/subject.mjs
// rev-6.1 §B/§3 — subject_or_role_id validation. subjid-v1a: user:<canonical-lowercase-uuid-v4> ONLY.
// role:<...> DISABLED this generation. Canonical parse (not shape-only). Failure ⇒ FAIL-STOP.
export class SubjectError extends Error {}

const UUID_RE = /^([0-9a-f]{8})-([0-9a-f]{4})-([0-9a-f]{4})-([0-9a-f]{4})-([0-9a-f]{12})$/;
const MAX_BYTES = 128;

// Accepted UUID version pinned from repository evidence: v4 (crypto.randomUUID at index.html:4674; all
// non-synthetic repo UUIDs are v4). Supabase auth-subject version confirmation is a before-LIVE-EXECUTION check.
const ACCEPTED_UUID_VERSION = '4';

export function validateSubjectId(id) {
  if (typeof id !== 'string') throw new SubjectError('subject_or_role_id: non-string');
  if (Buffer.byteLength(id, 'utf8') > MAX_BYTES) throw new SubjectError('subject_or_role_id: exceeds max length');
  if (id !== id.trim() || /\s/u.test(id)) throw new SubjectError('subject_or_role_id: whitespace');
  if (id.includes('@')) throw new SubjectError('subject_or_role_id: "@" prohibited (no email/alias)');
  if (id.startsWith('role:')) throw new SubjectError('subject_or_role_id: role identities disabled this generation (rev-6.1 §3 Option A)');
  if (!id.startsWith('user:')) throw new SubjectError('subject_or_role_id: must be tagged user:<uuid>');
  const uuid = id.slice('user:'.length);
  if (uuid !== uuid.toLowerCase()) throw new SubjectError('subject_or_role_id: uuid must be lowercase canonical');
  const m = UUID_RE.exec(uuid);
  if (!m) throw new SubjectError('subject_or_role_id: not a canonical hyphenated uuid');
  const version = m[3][0];                       // version nibble
  const variant = m[4][0];                       // variant nibble
  if (version !== ACCEPTED_UUID_VERSION) throw new SubjectError(`subject_or_role_id: UUID version ${version} != accepted v${ACCEPTED_UUID_VERSION}`);
  if (!'89ab'.includes(variant)) throw new SubjectError('subject_or_role_id: not RFC-4122 variant');
  // exact round-trip parse/serialize equality: canonical lowercase hyphenated reserialization must equal input
  const reser = `${m[1]}-${m[2]}-${m[3]}-${m[4]}-${m[5]}`;
  if (reser !== uuid) throw new SubjectError('subject_or_role_id: round-trip mismatch');
  return { ok: true, subject_id_format_version: 'subjid-v1a', uuid_version: version };
}
