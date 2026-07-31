// baseline-E/live-preflight/live-preflight-fixtures.mjs
// Synthetic-only live-evidence packages (hardened per Fable verdict-3). No real balances/ids/UUIDs.
import { CONTRACT_VERSION, digest, EXT_DIGEST_SECTIONS, packageFieldsForDigest } from './live-preflight-contract.mjs';

const WIN = { start: '2026-07-30T00:00:00.000Z', end: '2026-07-30T23:59:59.999Z' };
const AS_OF = '2026-07-30T12:00:00.000Z';
const EVAL_WEEK = 8;
const EVIDENCE_SECS = ['account_balance_evidence', 'weekly_reconciliation_evidence', 'cash_commitment_evidence', 'off_model_obligation_evidence', 'register_transaction_evidence', 'pending_or_uncleared_evidence', 'terminal_resolution_evidence'];
const ARRAY_SECS = EVIDENCE_SECS.concat(['source_query_manifest']);
const REL_SEC = { accounts: 'account_balance_evidence', weekly_reconciliations: 'weekly_reconciliation_evidence', cash_commitments: 'cash_commitment_evidence', custom_tasks: 'off_model_obligation_evidence', transactions: 'register_transaction_evidence', pending_transactions: 'pending_or_uncleared_evidence', terminal_resolutions: 'terminal_resolution_evidence' };
const ATT_SEC = { account_balances: 'account_balance_evidence', reconciliations: 'weekly_reconciliation_evidence', commitments: 'cash_commitment_evidence', off_model_obligations: 'off_model_obligation_evidence', register_transactions: 'register_transaction_evidence', pending_or_uncleared: 'pending_or_uncleared_evidence', terminal_resolution: 'terminal_resolution_evidence', source_query_manifest: 'source_query_manifest' };

// Recompute per-record digests; auto-sync query + attestation row counts to section lengths.
export function stampDigests(pkg) {
  for (const s of EVIDENCE_SECS) for (const r of pkg[s] || []) { delete r.digest; r.digest = digest(r); }
  if (Array.isArray(pkg.source_query_manifest)) for (const q of pkg.source_query_manifest) { const sec = REL_SEC[q.relation]; if (sec && pkg[sec]) q.row_count = pkg[sec].length; }
  if (pkg.completeness_attestations) for (const [rel, sec] of Object.entries(ATT_SEC)) { const a = pkg.completeness_attestations[rel]; if (a && pkg[sec]) { if (typeof a.rows_returned === 'number') a.rows_returned = pkg[sec].length; if (typeof a.row_count === 'number') a.row_count = pkg[sec].length; } }
  const counts = {}; for (const s of ARRAY_SECS) counts[s] = (pkg[s] || []).length;
  pkg.package_manifest.section_row_counts = counts;
  // NEW-D: whole-section ext digests (computed AFTER per-record digests so they cover the stamped content)
  const ext = {}; for (const sec of EXT_DIGEST_SECTIONS) ext[sec] = digest(pkg[sec] ?? null);
  ext.package_fields = digest(packageFieldsForDigest(pkg));
  pkg.package_manifest.ext_digests = ext;
  return pkg;
}

const att = (status, sourceNs, extra = {}) => Object.assign({ status, attested: status === 'complete' || status === 'verified_empty', rows_visible: true, rows_returned: 1, zero_rows_verified: false, query_id: 'q_' + sourceNs, schema_version: 'step8-schema-v1', extraction_ts: AS_OF, source_namespace: sourceNs, row_count: 1 }, extra);
const q = (query_id, relation, extra = {}) => Object.assign({ query_id, relation, environment: 'synthetic', schema_version: 'step8-schema-v1', extraction_ts: AS_OF, as_of: AS_OF, row_count: 1, execution_status: 'success', filter: 'synthetic-scope' }, extra);

function golden() {
  const pkg = {
    package_manifest: { contract_version: CONTRACT_VERSION, package_id: 'PF-GOLDEN', generated_note: 'synthetic', package_as_of: AS_OF, section_row_counts: {} },
    environment_identity: { environment: 'synthetic', expected_environment: 'synthetic', project_ref: null, operator_project_confirmation: false, db_name: 'synthetic', session_user: 'synthetic', session_timezone: 'UTC', server_version: 'synthetic' },
    execution_identity: { subject_uuid: '2e6f8777-94c8-420e-aa20-c0c481d7ce5a', role_disabled: true, as_of_utc: AS_OF, evaluation_model_week: EVAL_WEEK, extraction_window: { start: WIN.start, end: WIN.end } },
    account_balance_evidence: [
      { account_key: 'truist_checking', balance_basis: 'reconciled', balance_cents: 1000000, as_of_utc: AS_OF, source: 'reconciliation', direct_derived_attested: 'direct', selected: true },
    ],
    weekly_reconciliation_evidence: [
      { week_num: 8, chk_cents: 1000000, sav_cents: 0, amx_cents: 0, tax_cents: 0, lc_cents: 0, balance_basis: 'posted_current_balance', recorded_at: AS_OF, source_relation: 'weekly_reconciliations' },
    ],
    cash_commitment_evidence: [
      { expected_item_id: '2026mw6_rent_2026_07_01', source_account: 'truist_checking', amount_cents: 200000, model_year: 2026, origin_model_week: 6, reflected_model_week: null, resolved_model_week: null, status: 'open', resolution_type: null, affects_deployable_cash: true, commitment_source: 'user', as_of_utc: AS_OF },
      { expected_item_id: '2026mw6_bkx_2026_07_01', source_account: 'truist_checking', amount_cents: 70090, model_year: 2026, origin_model_week: 6, reflected_model_week: null, resolved_model_week: null, status: 'open', resolution_type: null, affects_deployable_cash: true, commitment_source: 'user', as_of_utc: AS_OF },
      { expected_item_id: '2026mw6_voided_x', source_account: 'truist_checking', amount_cents: 50000, model_year: 2026, origin_model_week: 6, reflected_model_week: null, resolved_model_week: null, status: 'voided', resolution_type: 'voided', affects_deployable_cash: true, commitment_source: 'user', as_of_utc: AS_OF },
    ],
    off_model_obligation_evidence: [
      { obligation_id: 'off_bkx_1', label: 'synthetic BKX-style tax reserve', material: true, amount_cents: 70090, source_account: 'truist_checking', authoritative_path: 'cash_commitment', linked_economic_id: '2026mw6_bkx_2026_07_01', as_of_utc: AS_OF },
    ],
    register_transaction_evidence: [
      { txn_id: 't1', account_key: 'truist_checking', amount_cents: -2000, cleared: true, is_transfer_leg: false, transfer_pair_id: null, represented_as_deduction: false, transaction_date: '2026-07-30', as_of_utc: AS_OF },
    ],
    pending_or_uncleared_evidence: [
      { txn_id: 'p1', account_key: 'truist_checking', amount_cents: -1500, direction: 'debit', reflected_in_authoritative: true, represented_as_deduction: false, as_of_utc: AS_OF },
    ],
    terminal_resolution_evidence: [
      { commitment_expected_item_id: '2026mw6_voided_x', resolution_type: 'voided', status: 'voided', resolution_evidence: 'synthetic-void', resolution_evidence_type: 'void_cancellation', resolution_evidence_id: 're1', amount_cents: 50000, source_account: 'truist_checking', as_of_utc: AS_OF },
    ],
    baseline_e_adjustments: [],
    economic_linkages: [],
    completeness_attestations: {
      account_balances: att('complete', 'accounts'), reconciliations: att('complete', 'weekly_reconciliations'),
      commitments: att('complete', 'cash_commitments'), off_model_obligations: att('complete', 'custom_tasks'),
      register_transactions: att('complete', 'transactions'), pending_or_uncleared: att('complete', 'pending_transactions'),
      terminal_resolution: att('complete', 'terminal_resolutions'), source_query_manifest: att('complete', 'source_query_manifest'),
    },
    source_query_manifest: [
      q('q_accounts', 'accounts'), q('q_weekly_reconciliations', 'weekly_reconciliations'), q('q_cash_commitments', 'cash_commitments'),
      q('q_custom_tasks', 'custom_tasks'), q('q_transactions', 'transactions'), q('q_pending_transactions', 'pending_transactions'),
      q('q_terminal_resolutions', 'terminal_resolutions'),
    ],
  };
  return pkg;
}

export { golden, stampDigests as _stamp };

import { DEFS } from './live-preflight-fixtures-defs.mjs';

export const FIXTURES = DEFS.map((d) => {
  const pkg = golden();
  d.mutate(pkg);
  stampDigests(pkg);
  if (d.post) d.post(pkg);
  return { id: d.id, cls: d.cls, expect_admissible: d.expect_admissible, package: pkg };
});
