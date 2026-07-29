// baseline-E/src/identity.mjs
// rev-6.1 IS-1 + H-3 closed anchor-type vocabulary + N-1 provenance. Deterministic; no scores; fail-closed.
import { independenceGroups } from './independence.mjs';

export class IdentityError extends Error {}

// H-3: closed anchor-type → category vocabulary (rev-6.1 anchor taxonomy). Category is DERIVED from type;
// a caller-declared category that disagrees is a violation. amount/direction can NEVER be anchors.
export const ANCHOR_TYPE_CATEGORY = Object.freeze({
  // Category A — content-bound / externally-stable
  bank_reference: 'A', trace_reference: 'A', content_bound_external_reference: 'A',
  recurring_series_identity: 'A', source_system_identity: 'A',
  // Category B — supporting identity
  source_account_identity: 'B', destination_account_identity: 'B', counterparty_identity: 'B',
  event_classification: 'B', expected_date_identity: 'B',
  // Category C — recall-only (never counts toward IS-1)
  description_token: 'C', date_proximity: 'C', model_week_proximity: 'C',
  classification_similarity: 'C', ordinal_position: 'C',
});
const PROHIBITED_ANCHOR_TYPES = new Set(['amount', 'direction', 'amount_cents', 'edge_direction']);

// Validate an anchor's type/category. Returns the derived category, or throws IdentityError (⇒ FAIL-STOP).
export function validateAnchorType(anchor) {
  const t = anchor && anchor.type;
  if (PROHIBITED_ANCHOR_TYPES.has(t)) throw new IdentityError(`anchor type "${t}" prohibited: amount/direction can never be identity anchors (rev-6.1 H-3)`);
  const derived = ANCHOR_TYPE_CATEGORY[t];
  if (!derived) throw new IdentityError(`unknown anchor type "${t}" (rev-6.1 H-3 closed vocabulary)`);
  if (anchor.category !== undefined && anchor.category !== derived) {
    throw new IdentityError(`incompatible anchor type/category: type "${t}" ⇒ category ${derived}, declared "${anchor.category}" (rev-6.1 H-3)`);
  }
  return derived;
}

const NONDIRECT = new Set(['copied_from', 'transform_of', 'parsed_from']);
function derivationKind(deriv) {
  if (deriv === 'direct_read') return 'direct_read';
  const k = String(deriv || '').split(':')[0];
  return NONDIRECT.has(k) ? k : 'invalid';
}
// N-1: non-direct anchor MUST reference an originating evidence_root_digest to count toward IS-1.
// Fail-closed: a missing/malformed evidence_root yields false (never a raw crash).
export function provenanceOk(anchor) {
  if (!anchor || !anchor.evidence_root || typeof anchor.evidence_root !== 'object') return false;
  const kind = derivationKind(anchor.evidence_root.derivation_method);
  if (kind === 'direct_read') return true;
  if (kind === 'invalid') return false;
  const ref = String(anchor.evidence_root.derivation_method).split(':')[1] || '';
  return /^[0-9a-f]{64}$/.test(ref);
}

// IS-1 with H-3 vocabulary enforcement. Returns { strong, error?, ... }. A vocabulary violation sets `error`
// (⇒ caller FAIL-STOP). Only valid A/B anchors with provenance count; Category-C never contributes.
export function isIdentityStrong(anchors) {
  const withCat = [];
  for (const a of anchors || []) {
    let derived;
    try { derived = validateAnchorType(a); } catch (err) { return { strong: false, error: err.message, independent_group_count: 0, category_A_present: false }; }
    withCat.push({ ...a, category: derived });
  }
  const qualifying = withCat.filter((a) => (a.category === 'A' || a.category === 'B') && provenanceOk(a));
  if (qualifying.length < 2) return { strong: false, independent_group_count: qualifying.length ? 1 : 0, category_A_present: false };
  const { distinctGroupCount, categoryAPresentPerGroup } = independenceGroups(qualifying);
  const anyGroupHasA = [...categoryAPresentPerGroup.values()].some(Boolean);
  return { strong: distinctGroupCount >= 2 && anyGroupHasA, independent_group_count: distinctGroupCount, category_A_present: anyGroupHasA };
}

export function amountDirectionConflict(bank, event) {
  return !(bank.amount_cents === event.amount_cents && bank.direction === event.direction);
}
