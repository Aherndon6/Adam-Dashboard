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

// Supported terminal-resolution evidence types (S-7) and their required resolution kinds.
export const TERMINAL_EVIDENCE_TYPES = Object.freeze({ void_cancellation: 'voided', alternate_payment: 'paid_from_other_account' });

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
