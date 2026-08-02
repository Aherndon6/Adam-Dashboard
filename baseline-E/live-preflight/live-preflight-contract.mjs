// baseline-E/live-preflight/live-preflight-contract.mjs
// Versioned, machine-readable contract for a FUTURE live-evidence package (Step 8 Baseline E live-input preflight).
// LOCAL + SYNTHETIC ONLY. No network, no SQL, no secrets. Defines the sections, required provenance, supported
// schema versions, and a deterministic canonical digest used for evidence-integrity verification (P-4). This digest
// is a preflight-local integrity hash (canonical-JSON SHA-256) and is DISTINCT from the frozen rev-6.1 digest scheme
// (which is not touched by this package).
import { createHash } from 'node:crypto';

export const CONTRACT_VERSION = 'live-preflight-v1';

// Supported source schema/contract versions (P-3). An evidence package built against anything else FAIL-STOPs.
export const SUPPORTED_SCHEMA_VERSIONS = Object.freeze(['step8-schema-v1']);

// The intended live target (grounded in the frozen Step-8 A SQL). Used by P-1 environment certification. The LOCAL
// harness never contacts it; a synthetic package must declare environment:'synthetic'. A package declaring
// environment:'production' must carry the matching project_ref AND an operator project confirmation.
export const EXPECTED_PRODUCTION_PROJECT_REF = 'usayoldrawwmjsmretin'; // inert expected-value constant (already public in docs/*.sql)

// Package sections A..L are INPUT; M (preflight_results) is produced by the validator.
export const SECTIONS = Object.freeze({
  A: 'package_manifest',
  B: 'environment_identity',
  C: 'execution_identity',
  D: 'account_balance_evidence',
  E: 'weekly_reconciliation_evidence',
  F: 'cash_commitment_evidence',
  G: 'off_model_obligation_evidence',
  H: 'register_transaction_evidence',
  I: 'pending_or_uncleared_evidence',
  J: 'terminal_resolution_evidence',
  K: 'completeness_attestations',
  L: 'source_query_manifest',
});
export const REQUIRED_SECTIONS = Object.freeze(Object.values(SECTIONS)); // all A..L required (fail-closed on absence)
export const ARRAY_SECTIONS = Object.freeze(['account_balance_evidence', 'weekly_reconciliation_evidence', 'cash_commitment_evidence', 'off_model_obligation_evidence', 'register_transaction_evidence', 'pending_or_uncleared_evidence', 'terminal_resolution_evidence', 'source_query_manifest']);

// Provenance every source-query-manifest entry (L) must carry — the contract fails closed when any is absent.
export const REQUIRED_QUERY_PROVENANCE = Object.freeze(['query_id', 'relation', 'filter', 'expected_cardinality', 'extraction_ts', 'schema_version', 'row_count']);

// Balance-basis vocabulary + authority precedence (P-9). Higher index = higher authority.
export const BALANCE_BASIS_PRECEDENCE = Object.freeze(['stale', 'projected', 'available_balance', 'posted_current_balance', 'reconciled']);
export const USABLE_BALANCE_BASES = Object.freeze(['posted_current_balance', 'available_balance', 'reconciled']); // 'unknown'/'projected'/'stale'/null are NOT authoritative

// Supported terminal-resolution evidence types (S-7) and their PRIMARY resolution kind. `bank_cleared` (S-7 v3.1,
// s7-rev-8.3) is the durable bank-clearing type; because one type may cover BOTH `cleared` and `reflected` releases,
// the authoritative direction for S-7 is the reverse map REQUIRED_EVIDENCE_TYPE_BY_RESOLUTION below (this constant
// stays a per-type documentation map; nothing consumes it directly). Additive: void_cancellation / alternate_payment
// are unchanged, so no committed fixture is affected.
export const TERMINAL_EVIDENCE_TYPES = Object.freeze({ void_cancellation: 'voided', alternate_payment: 'paid_from_other_account', bank_cleared: 'cleared' });
// Authoritative resolution_type -> required terminal-evidence type (S-7 requiredType). `cleared` and `reflected` both
// require durable `bank_cleared` evidence; `paid_from_other_account` -> alternate_payment; `voided` -> void_cancellation.
// A released commitment whose resolution_type is null is UNDETERMINED (HOLD, per Part 5'); an out-of-vocabulary value
// is already FAIL-STOPped upstream by S-4 (S4_UNSUPPORTED_RESOLUTION), so this map only carries the valid vocabulary.
export const REQUIRED_EVIDENCE_TYPE_BY_RESOLUTION = Object.freeze({ cleared: 'bank_cleared', reflected: 'bank_cleared', paid_from_other_account: 'alternate_payment', voided: 'void_cancellation' });

// ── S-7 v3.1 durable-clearing lane (design s7-rev-8.3-bankcleared) ─────────────────────────────────────────────
export const S7_SPEC_REVISION = 's7-rev-8.3-bankcleared';
export const LEGACY_SPEC_VERSION = 'legacy-clearing-v1';
export const AUTHORITY_VERSION = 'authority-v1';
export const LEGACY_REGISTRY_VERSION = 'legacy-registry-v1';
// evidence_source is a CLOSED set. A J record with NO evidence_source is the committed evidence class (validated by the
// committed S-7 rules, unchanged). Any explicitly-declared value outside this set (including a present-but-null value)
// FAIL-STOPs (S7_UNSUPPORTED_EVIDENCE_SOURCE).
export const SUPPORTED_EVIDENCE_SOURCES = Object.freeze(['au11', 'legacy_adjudication']);
// The authorized owner subject id (Gate-A owner; owner-run extraction identity; resolved_by on all six commitments).
export const AUTHORIZED_OWNER_SUBJECT_ID = '9f6c9e09-209d-4533-8cd9-9143e8d570fc';
// The legacy-adjudication lane is machine-bounded to EXACTLY these six pre-AU-11 commitments. Any other commitment on
// the legacy path FAIL-STOPs (S7_LEGACY_COMMITMENT_NOT_PINNED). Changing this set requires a new LEGACY_SPEC_VERSION.
export const PINNED_LEGACY_COMMITMENTS = Object.freeze([
  '2026mw4_rent_tiffany_dye_2026_07_01', '2026mw4_rent_tiffany_dye_2026_07_02', '2026mw4_rent_tiffany_dye_2026_07_03',
  '2026mw4_tax_transfer_vio_2026_06_28', '2026mw5_kia_payment_2026_07_07', 'manual_18313b87-a03b-4034-a1a8-a73fa0bfadd9',
]);
// Closed, versioned legacy disposition vocabulary. An out-of-vocab disposition FAIL-STOPs (S7_UNSUPPORTED_DISPOSITION).
export const LEGACY_DISPOSITION_VOCAB = Object.freeze(['matched_bank_clearing', 'paid_from_other_account', 'voided_or_never_cleared', 'unresolved_hold']);
// Frozen accepted-record-digest registry. EMPTY until the six records are created + independently reviewed + owner-
// ratified (owner decision (h), migration step 11). Pre-freeze this is empty, so EVERY legacy_adjudication record
// FAIL-STOPs (S7_ADJUDICATION_NOT_IN_REGISTRY) — the correct pre-freeze fail-closed posture.
export const ACCEPTED_LEGACY_RECORD_DIGESTS = Object.freeze([]);

// Attestation states (S-6). Only these two may proceed; every other state HOLDs.
export const ATTEST_OK = Object.freeze(['complete', 'verified_empty']);

// No materiality threshold and no real-time freshness policy are authorized for this gate.
export const AUTHORIZED_MATERIALITY_THRESHOLD = null;
export const FRESHNESS_POLICY_AUTHORIZED = false;

// Sections that MUST carry a completeness attestation (S-6) and a source-query manifest linkage (query provenance).
export const ATTESTED_SECTIONS = Object.freeze(['account_balances', 'reconciliations', 'commitments', 'off_model_obligations', 'register_transactions', 'pending_or_uncleared', 'terminal_resolution', 'source_query_manifest']);
export const ATTEST_TO_SECTION = Object.freeze({ account_balances: 'account_balance_evidence', reconciliations: 'weekly_reconciliation_evidence', commitments: 'cash_commitment_evidence', off_model_obligations: 'off_model_obligation_evidence', register_transactions: 'register_transaction_evidence', pending_or_uncleared: 'pending_or_uncleared_evidence', terminal_resolution: 'terminal_resolution_evidence', source_query_manifest: 'source_query_manifest' });
// Every evidence-bearing array section must be tied to a source-query manifest entry via query_id (provenance).
export const SECTION_TO_RELATION = Object.freeze({ account_balance_evidence: 'accounts', weekly_reconciliation_evidence: 'weekly_reconciliations', cash_commitment_evidence: 'cash_commitments', off_model_obligation_evidence: 'custom_tasks', register_transaction_evidence: 'transactions', pending_or_uncleared_evidence: 'pending_transactions', terminal_resolution_evidence: 'terminal_resolutions' });

// Canonical UTC instant: RFC-3339 ms Z that round-trips exactly (not a bare lexicographic string compare).
export function parseUtcInstant(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(s)) return null;
  const d = new Date(s);
  return (!Number.isNaN(d.getTime()) && d.toISOString() === s) ? d.getTime() : null;
}

// ── canonical digest (deterministic; sorted keys) ────────────────────────────────────────────────────────────
export function canonicalize(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v ?? null);
  if (Array.isArray(v)) return '[' + v.map(canonicalize).join(',') + ']';
  return '{' + Object.keys(v).sort().map((k) => JSON.stringify(k) + ':' + canonicalize(v[k])).join(',') + '}';
}
export function digest(v) { return createHash('sha256').update(canonicalize(v), 'utf8').digest('hex'); }

// NEW-D: admissibility-relevant sections that are NOT the 7 per-record-digested evidence arrays. Each is integrity-
// hashed as a whole into package_manifest.ext_digests, so post-stamp tamper of any of these is detected by P-4.
// Domain: canonical-JSON SHA-256 of the section content, excluding generated digest fields. Separate from rev-6.1.
export const EXT_DIGEST_SECTIONS = Object.freeze(['baseline_e_adjustments', 'economic_linkages', 'completeness_attestations', 'source_query_manifest']);
export function packageFieldsForDigest(pkg) {
  const ei = pkg.execution_identity || {}, en = pkg.environment_identity || {};
  return { evaluation_model_week: ei.evaluation_model_week, extraction_window: ei.extraction_window, environment: en.environment, expected_environment: en.expected_environment, project_ref: en.project_ref, operator_project_confirmation: en.operator_project_confirmation };
}
