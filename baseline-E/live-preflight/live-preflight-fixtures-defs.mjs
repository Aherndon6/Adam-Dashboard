// baseline-E/live-preflight/live-preflight-fixtures-defs.mjs
// Fixture DEFINITIONS (mutate functions) for the hardened preflight. Kept separate from the golden factory to keep
// each file readable. Every fixture clones the golden and applies its mutate; stamping happens in the index module.
const AS_OF = '2026-07-30T12:00:00.000Z';

// verified-empty attestation for an emptied section
const attEmpty = (ns) => ({ status: 'verified_empty', attested: true, rows_visible: true, rows_returned: 0, zero_rows_verified: true, query_id: 'q_' + ns, schema_version: 'step8-schema-v1', extraction_ts: AS_OF, source_namespace: ns, row_count: 0 });
function emptyCommitments(p) {
  p.cash_commitment_evidence = []; p.off_model_obligation_evidence = []; p.terminal_resolution_evidence = [];
  p.completeness_attestations.commitments = attEmpty('cash_commitments');
  p.completeness_attestations.off_model_obligations = attEmpty('custom_tasks');
  p.completeness_attestations.terminal_resolution = attEmpty('terminal_resolutions');
}
// NEW-F helpers: a pending deduction (optional direct economic_event_id), an adjustment, a linkage record.
const pend = (txn_id, directEvent) => { const r = { txn_id, account_key: 'truist_checking', amount_cents: -1000, direction: 'debit', reflected_in_authoritative: false, represented_as_deduction: true, as_of_utc: AS_OF }; if (directEvent) r.economic_event_id = directEvent; return r; };
const adj = (adjustment_id, directEvent) => { const r = { adjustment_id, amount_cents: 100, source_account: 'truist_checking', active: true }; if (directEvent) r.economic_event_id = directEvent; return r; };
const link = (sn, si, tn, ti, cardinality = '1:1') => ({ source_namespace: sn, source_id: si, target_namespace: tn, target_id: ti, linkage_type: 'settles', cardinality });
// OBS-5: a non-deducting record that ESTABLISHES an authoritative event by carrying its direct economic_event_id.
const estab = (eventId, txn) => ({ txn_id: txn, account_key: 'truist_checking', amount_cents: -1000, direction: 'debit', reflected_in_authoritative: true, represented_as_deduction: false, economic_event_id: eventId, as_of_utc: AS_OF });
const twoLeg = (pairId, a1, a2, dedA, dedB) => ([
  { txn_id: 'tr1', account_key: 'truist_checking', amount_cents: a1, cleared: true, is_transfer_leg: true, transfer_group_id: pairId, transfer_pair_id: pairId, represented_as_deduction: dedA, transaction_date: '2026-07-30', as_of_utc: AS_OF },
  { txn_id: 'tr2', account_key: 'amex_savings', amount_cents: a2, cleared: true, is_transfer_leg: true, transfer_group_id: pairId, transfer_pair_id: pairId, represented_as_deduction: dedB, transaction_date: '2026-07-30', as_of_utc: AS_OF },
]);

export const DEFS = [
  // ── original 40 classes (adapted to the hardened golden) ────────────────────────────────────────────────
  { id: 'PF-01', cls: 'fully_admissible', expect_admissible: true, mutate: () => {} },
  { id: 'PF-02', cls: 'missing_required_section', expect_admissible: false, mutate: (p) => { delete p.cash_commitment_evidence; } },
  { id: 'PF-03', cls: 'wrong_environment', expect_admissible: false, mutate: (p) => { p.environment_identity.environment = 'staging'; p.environment_identity.expected_environment = 'production'; } },
  { id: 'PF-04', cls: 'environment_identity_mismatch', expect_admissible: false, mutate: (p) => { p.environment_identity.environment = 'production'; p.environment_identity.expected_environment = 'production'; p.environment_identity.project_ref = 'wrong_ref'; p.environment_identity.operator_project_confirmation = true; for (const q of p.source_query_manifest) q.environment = 'production'; } },
  { id: 'PF-05', cls: 'unsupported_contract_version', expect_admissible: false, mutate: (p) => { p.package_manifest.contract_version = 'live-preflight-v0'; } },
  { id: 'PF-06', cls: 'null_checking_reconciliation', expect_admissible: false, mutate: (p) => { p.weekly_reconciliation_evidence[0].chk_cents = null; } },
  { id: 'PF-07', cls: 'missing_checking_field', expect_admissible: false, mutate: (p) => { delete p.weekly_reconciliation_evidence[0].chk_cents; } },
  { id: 'PF-08', cls: 'duplicate_reconciliation_row', expect_admissible: false, mutate: (p) => { p.weekly_reconciliation_evidence.push({ ...p.weekly_reconciliation_evidence[0] }); } },
  { id: 'PF-09', cls: 'stale_reconciliation', expect_admissible: false, mutate: (p) => { p.weekly_reconciliation_evidence[0].recorded_at = '2026-07-01T12:00:00.000Z'; } },
  { id: 'PF-10', cls: 'invalid_balance_basis', expect_admissible: false, mutate: (p) => { p.weekly_reconciliation_evidence[0].balance_basis = 'unknown'; } },
  { id: 'PF-11', cls: 'failed_commitment_fetch', expect_admissible: false, mutate: (p) => { p.completeness_attestations.commitments.status = 'failed_fetch'; p.completeness_attestations.commitments.attested = false; } },
  { id: 'PF-12', cls: 'silent_empty_commitment_fetch', expect_admissible: false, mutate: (p) => { emptyCommitments(p); p.completeness_attestations.commitments = { status: 'silent_empty', attested: false, rows_visible: false, rows_returned: 0, zero_rows_verified: false, query_id: 'q_cc', schema_version: 'step8-schema-v1', extraction_ts: AS_OF, source_namespace: 'cash_commitments', row_count: 0 }; } },
  { id: 'PF-13', cls: 'verified_empty_commitments_attested', expect_admissible: true, mutate: (p) => emptyCommitments(p) },
  { id: 'PF-14', cls: 'partial_commitment_load', expect_admissible: false, mutate: (p) => { p.completeness_attestations.commitments.status = 'partial'; p.completeness_attestations.commitments.attested = false; } },
  { id: 'PF-15', cls: 'rls_filtered_uncertainty', expect_admissible: false, mutate: (p) => { p.completeness_attestations.commitments.status = 'rls_filtered'; p.completeness_attestations.commitments.attested = false; p.completeness_attestations.commitments.rows_visible = false; } },
  { id: 'PF-16', cls: 'schema_mismatch', expect_admissible: false, mutate: (p) => { p.source_query_manifest[0].schema_version = 'legacy-v0'; } },
  { id: 'PF-17', cls: 'negative_commitment', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[0].amount_cents = -200000; } },
  { id: 'PF-18', cls: 'duplicate_commitment_identity', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence.push({ ...p.cash_commitment_evidence[0] }); } },
  { id: 'PF-19', cls: 'duplicate_clearing_linkage', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[0].cleared_transaction_id = 'ctxX'; p.cash_commitment_evidence[0].cleared_amount_cents = 200000; p.cash_commitment_evidence[0].cleared_source_account = 'truist_checking'; p.cash_commitment_evidence[1].cleared_transaction_id = 'ctxX'; p.cash_commitment_evidence[1].cleared_amount_cents = 70090; p.cash_commitment_evidence[1].cleared_source_account = 'truist_checking'; } },
  { id: 'PF-20', cls: 'material_offmodel_absent_from_deduction', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].authoritative_path = null; } },
  { id: 'PF-21', cls: 'material_offmodel_promoted_to_commitment', expect_admissible: true, mutate: () => {} },
  { id: 'PF-22', cls: 'material_offmodel_as_baseline_adjustment', expect_admissible: true, mutate: (p) => { p.off_model_obligation_evidence[0].authoritative_path = 'baseline_e_adjustment'; p.off_model_obligation_evidence[0].linked_economic_id = 'adj_bkx'; p.baseline_e_adjustments = [{ adjustment_id: 'adj_bkx', amount_cents: 70090, source_account: 'truist_checking', economic_event_id: 'adj_bkx' }]; } },
  { id: 'PF-23', cls: 'uncleared_debit_unreflected', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence[0].reflected_in_authoritative = false; p.pending_or_uncleared_evidence[0].represented_as_deduction = false; } },
  { id: 'PF-24', cls: 'uncleared_debit_as_deduction', expect_admissible: true, mutate: (p) => { p.pending_or_uncleared_evidence[0].reflected_in_authoritative = false; p.pending_or_uncleared_evidence[0].represented_as_deduction = true; p.pending_or_uncleared_evidence[0].economic_event_id = 'pend_evt_1'; } },
  { id: 'PF-25', cls: 'transfer_mirror_double_counted', expect_admissible: false, mutate: (p) => { p.register_transaction_evidence = twoLeg('TP1', -30000, 30000, true, true); } },
  { id: 'PF-26', cls: 'transfer_pair_neutralized', expect_admissible: true, mutate: (p) => { p.register_transaction_evidence = twoLeg('TP1', -30000, 30000, false, false); } },
  { id: 'PF-27', cls: 'terminal_valid_typed_evidence', expect_admissible: true, mutate: () => {} },
  { id: 'PF-28', cls: 'terminal_missing_evidence', expect_admissible: false, mutate: (p) => { delete p.terminal_resolution_evidence[0].resolution_evidence; } },
  { id: 'PF-29', cls: 'terminal_missing_evidence_type', expect_admissible: false, mutate: (p) => { delete p.terminal_resolution_evidence[0].resolution_evidence_type; } },
  { id: 'PF-30', cls: 'terminal_stale_evidence', expect_admissible: false, mutate: (p) => { p.terminal_resolution_evidence[0].resolution_stale = true; } },
  { id: 'PF-31', cls: 'terminal_contradictory_status_type', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[2].status = 'open'; } },
  { id: 'PF-32', cls: 'evidence_reused_across_commitments', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[0].status = 'voided'; p.cash_commitment_evidence[0].resolution_type = 'voided'; p.terminal_resolution_evidence.push({ commitment_expected_item_id: '2026mw6_rent_2026_07_01', resolution_type: 'voided', status: 'voided', resolution_evidence: 'synthetic-void', resolution_evidence_type: 'void_cancellation', resolution_evidence_id: 're1', amount_cents: 200000, source_account: 'truist_checking', as_of_utc: AS_OF }); } },
  { id: 'PF-33', cls: 'manifest_rowcount_mismatch', expect_admissible: false, mutate: () => {}, post: (p) => { p.package_manifest.section_row_counts.cash_commitment_evidence = 9; } },
  { id: 'PF-34', cls: 'evidence_hash_mismatch', expect_admissible: false, mutate: () => {}, post: (p) => { p.cash_commitment_evidence[0].amount_cents = 999999; } },
  { id: 'PF-35', cls: 'incoherent_as_of', expect_admissible: false, mutate: (p) => { p.account_balance_evidence[0].as_of_utc = '2026-06-01T12:00:00.000Z'; } },
  { id: 'PF-36', cls: 'duplicate_stable_identity', expect_admissible: false, mutate: (p) => { p.register_transaction_evidence.push({ ...p.register_transaction_evidence[0] }); } },
  { id: 'PF-37', cls: 'same_obligation_commitment_and_adjustment', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].authoritative_path = 'baseline_e_adjustment'; p.off_model_obligation_evidence[0].linked_economic_id = 'adj_bkx'; p.baseline_e_adjustments = [{ adjustment_id: 'adj_bkx', amount_cents: 70090, source_account: 'truist_checking', active: true }]; p.economic_linkages = [{ source_namespace: 'adjustment', source_id: 'adj_bkx', target_namespace: 'commitment', target_id: '2026mw6_bkx_2026_07_01', linkage_type: 'settles', cardinality: '1:1' }]; } },
  { id: 'PF-38', cls: 'missing_source_query_manifest', expect_admissible: false, mutate: (p) => { delete p.source_query_manifest; } },
  { id: 'PF-39', cls: 'missing_completeness_attestation', expect_admissible: false, mutate: (p) => { delete p.completeness_attestations.commitments; } },
  { id: 'PF-40', cls: 'hold_cannot_be_admissible', expect_admissible: false, mutate: (p) => { p.weekly_reconciliation_evidence[0].chk_cents = null; } },

  // ── S-7 cross-consistency (owner §13.1-7) ───────────────────────────────────────────────────────────────
  { id: 'PF-41', cls: 's7_reflected_release_no_j', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[0].reflected_model_week = 7; } },
  { id: 'PF-42', cls: 's7_resolved_release_no_j', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[0].resolved_model_week = 7; } },
  { id: 'PF-43', cls: 's7_reflected_release_valid_j', expect_admissible: true, mutate: (p) => { p.cash_commitment_evidence[0].reflected_model_week = 7; p.cash_commitment_evidence[0].resolution_type = 'paid_from_other_account'; p.terminal_resolution_evidence.push({ commitment_expected_item_id: '2026mw6_rent_2026_07_01', resolution_type: 'paid_from_other_account', status: 'open', resolution_evidence: 'synthetic-alt', resolution_evidence_type: 'alternate_payment', resolution_evidence_id: 're_rent', amount_cents: 200000, source_account: 'truist_checking', as_of_utc: AS_OF }); } },
  { id: 'PF-44', cls: 's7_bare_cleared_txn_no_meta', expect_admissible: false, mutate: (p) => { p.terminal_resolution_evidence[0].cleared_transaction_id = 'ctx1'; } },
  { id: 'PF-45', cls: 's7_clearing_amount_mismatch', expect_admissible: false, mutate: (p) => { Object.assign(p.terminal_resolution_evidence[0], { cleared_transaction_id: 'ctx1', cleared_amount_cents: 40000, cleared_source_account: 'truist_checking', cleared_state: 'cleared', cleared_as_of: AS_OF }); } },
  { id: 'PF-46', cls: 's7_clearing_source_mismatch', expect_admissible: false, mutate: (p) => { Object.assign(p.terminal_resolution_evidence[0], { cleared_transaction_id: 'ctx1', cleared_amount_cents: 50000, cleared_source_account: 'vio_tax', cleared_state: 'cleared', cleared_as_of: AS_OF }); } },
  { id: 'PF-47', cls: 's7_orphan_evidence', expect_admissible: false, mutate: (p) => { p.terminal_resolution_evidence.push({ commitment_expected_item_id: 'no_such_commitment', resolution_type: 'voided', status: 'voided', resolution_evidence: 'x', resolution_evidence_type: 'void_cancellation', resolution_evidence_id: 're2', amount_cents: 1, source_account: 'truist_checking', as_of_utc: AS_OF }); } },

  // ── S-1 referential integrity (owner §13.8-13) ─────────────────────────────────────────────────────────
  { id: 'PF-48', cls: 's1_dangling_reference', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].linked_economic_id = 'ghost_never_exists'; } },
  { id: 'PF-49', cls: 's1_matching_commitment', expect_admissible: true, mutate: () => {} },
  { id: 'PF-50', cls: 's1_matching_adjustment', expect_admissible: true, mutate: (p) => { p.off_model_obligation_evidence[0].authoritative_path = 'baseline_e_adjustment'; p.off_model_obligation_evidence[0].linked_economic_id = 'adj_bkx'; p.baseline_e_adjustments = [{ adjustment_id: 'adj_bkx', amount_cents: 70090, source_account: 'truist_checking', economic_event_id: 'adj_bkx' }]; } },
  { id: 'PF-51', cls: 's1_reference_amount_mismatch', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].amount_cents = 99999; } },
  { id: 'PF-52', cls: 's1_reference_source_mismatch', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].source_account = 'vio_tax'; } },
  { id: 'PF-53', cls: 's1_shared_deduction', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence.push({ obligation_id: 'off_bkx_2', label: 'second obligation same deduction', material: true, amount_cents: 70090, source_account: 'truist_checking', authoritative_path: 'cash_commitment', linked_economic_id: '2026mw6_bkx_2026_07_01', as_of_utc: AS_OF }); } },

  // ── S-5 threshold (owner §13.14-15) ─────────────────────────────────────────────────────────────────────
  { id: 'PF-54', cls: 's5_self_asserted_threshold', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence[0].reflected_in_authoritative = false; p.pending_or_uncleared_evidence[0].immaterial_under_authorized_threshold = true; } },
  { id: 'PF-55', cls: 's5_uncleared_neither', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence[0].reflected_in_authoritative = false; p.pending_or_uncleared_evidence[0].represented_as_deduction = false; } },

  // ── balance anchor (owner §13.16-19) ────────────────────────────────────────────────────────────────────
  { id: 'PF-56', cls: 'anchor_d_and_e_empty', expect_admissible: false, mutate: (p) => { p.account_balance_evidence = []; p.weekly_reconciliation_evidence = []; p.completeness_attestations.account_balances = attEmpty('accounts'); p.completeness_attestations.reconciliations = attEmpty('weekly_reconciliations'); } },
  { id: 'PF-57', cls: 'anchor_projected_only', expect_admissible: false, mutate: (p) => { p.account_balance_evidence[0].balance_basis = 'projected'; p.weekly_reconciliation_evidence[0].balance_basis = 'projected'; } },
  { id: 'PF-58', cls: 'anchor_valid', expect_admissible: true, mutate: () => {} },
  { id: 'PF-59', cls: 'anchor_competing_unresolved', expect_admissible: false, mutate: (p) => { p.account_balance_evidence[0].selected = false; p.account_balance_evidence.push({ account_key: 'truist_checking', balance_basis: 'available_balance', balance_cents: 999999, as_of_utc: AS_OF, source: 'bank', direct_derived_attested: 'direct', selected: false }); } },

  // ── S-6 coverage (owner §13.20-24) ──────────────────────────────────────────────────────────────────────
  { id: 'PF-60', cls: 's6_verified_empty_no_rows_visible', expect_admissible: false, mutate: (p) => { emptyCommitments(p); p.completeness_attestations.commitments.rows_visible = false; } },
  { id: 'PF-61', cls: 's6_zero_not_verified', expect_admissible: false, mutate: (p) => { emptyCommitments(p); p.completeness_attestations.commitments.zero_rows_verified = false; } },
  { id: 'PF-62', cls: 's6_pending_unattested', expect_admissible: false, mutate: (p) => { p.completeness_attestations.pending_or_uncleared.status = 'unattested'; p.completeness_attestations.pending_or_uncleared.attested = false; } },
  { id: 'PF-63', cls: 's6_terminal_unattested', expect_admissible: false, mutate: (p) => { p.completeness_attestations.terminal_resolution.status = 'unattested'; p.completeness_attestations.terminal_resolution.attested = false; } },
  { id: 'PF-64', cls: 's6_all_attested', expect_admissible: true, mutate: () => {} },

  // ── P-8 transfers (owner §13.25-29) ─────────────────────────────────────────────────────────────────────
  { id: 'PF-65', cls: 'p8_three_leg_group', expect_admissible: false, mutate: (p) => { const l = twoLeg('TP1', -30000, 30000, false, false); l.push({ txn_id: 'tr3', account_key: 'truist_checking', amount_cents: 0, cleared: true, is_transfer_leg: true, transfer_group_id: 'TP1', transfer_pair_id: 'TP1', represented_as_deduction: false, transaction_date: '2026-07-30', as_of_utc: AS_OF }); p.register_transaction_evidence = l; } },
  { id: 'PF-66', cls: 'p8_one_cent_skew', expect_admissible: false, mutate: (p) => { p.register_transaction_evidence = twoLeg('TP1', -30000, 29999, false, false); } },
  { id: 'PF-67', cls: 'p8_same_direction', expect_admissible: false, mutate: (p) => { p.register_transaction_evidence = twoLeg('TP1', -30000, -30000, false, false); } },
  { id: 'PF-68', cls: 'p8_valid_two_leg', expect_admissible: true, mutate: (p) => { p.register_transaction_evidence = twoLeg('TP1', -30000, 30000, false, false); } },
  { id: 'PF-69', cls: 'p8_missing_transfer_identity', expect_admissible: false, mutate: (p) => { const l = twoLeg('TP1', -30000, 30000, false, false); l[0].transfer_group_id = null; l[0].transfer_pair_id = null; p.register_transaction_evidence = l; } },

  // ── P-7 economic identity (owner §13.30-33) ─────────────────────────────────────────────────────────────
  { id: 'PF-70', cls: 'p7_freetext_only_identity', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence[0].reflected_in_authoritative = false; p.pending_or_uncleared_evidence[0].represented_as_deduction = true; delete p.pending_or_uncleared_evidence[0].economic_event_id; } },
  { id: 'PF-71', cls: 'p7_authoritative_event_id', expect_admissible: true, mutate: (p) => { p.pending_or_uncleared_evidence[0].reflected_in_authoritative = false; p.pending_or_uncleared_evidence[0].represented_as_deduction = true; p.pending_or_uncleared_evidence[0].economic_event_id = 'auth_evt_1'; } },
  { id: 'PF-72', cls: 'p7_duplicate_linkage', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence[0].reflected_in_authoritative = false; p.pending_or_uncleared_evidence[0].represented_as_deduction = true; delete p.pending_or_uncleared_evidence[0].economic_event_id; p.economic_linkages = [{ source_namespace: 'pending', source_id: 'p1', target_namespace: 'commitment', target_id: 'X', linkage_type: 'settles', cardinality: '1:1' }, { source_namespace: 'pending', source_id: 'p1', target_namespace: 'commitment', target_id: 'X', linkage_type: 'settles', cardinality: '1:1' }]; } },
  { id: 'PF-73', cls: 'p7_linkage_to_commitment_double', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence[0].reflected_in_authoritative = false; p.pending_or_uncleared_evidence[0].represented_as_deduction = true; delete p.pending_or_uncleared_evidence[0].economic_event_id; p.economic_linkages = [{ source_namespace: 'pending', source_id: 'p1', target_namespace: 'commitment', target_id: '2026mw6_rent_2026_07_01', linkage_type: 'settles', cardinality: '1:1' }]; } },

  // ── provenance / P-2 (owner §13.34-40) ──────────────────────────────────────────────────────────────────
  { id: 'PF-74', cls: 'pq_missing_query_link', expect_admissible: false, mutate: (p) => { p.source_query_manifest = p.source_query_manifest.filter((q) => q.relation !== 'cash_commitments'); }, post: (p) => { p.package_manifest.section_row_counts.source_query_manifest = p.source_query_manifest.length; } },
  { id: 'PF-75', cls: 'pq_orphan_manifest', expect_admissible: false, mutate: (p) => { p.source_query_manifest.push({ query_id: 'q_orphan', relation: 'unknown_relation', environment: 'synthetic', schema_version: 'step8-schema-v1', extraction_ts: AS_OF, as_of: AS_OF, row_count: 1, execution_status: 'success', filter: 'x' }); } },
  { id: 'PF-76', cls: 'pq_rowcount_mismatch', expect_admissible: false, mutate: () => {}, post: (p) => { for (const q of p.source_query_manifest) if (q.relation === 'cash_commitments') q.row_count = 99; } },
  { id: 'PF-77', cls: 'p2_invalid_timestamp', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[0].as_of_utc = 'not-a-timestamp'; } },
  { id: 'PF-78', cls: 'p2_non_utc_timestamp', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[0].as_of_utc = '2026-07-30T12:00:00+00:00'; } },
  { id: 'PF-79', cls: 'p2_record_outside_window', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[0].as_of_utc = '2026-08-15T12:00:00.000Z'; } },
  { id: 'PF-80', cls: 'p2_freshness_no_policy', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[0].freshness_dependent = true; } },

  // ── cross-control (owner §12 / §14.13) ──────────────────────────────────────────────────────────────────
  { id: 'PF-81', cls: 'xc_transfer_also_deducted', expect_admissible: false, mutate: (p) => { p.register_transaction_evidence = twoLeg('TP1', -30000, 30000, false, false); p.pending_or_uncleared_evidence[0].txn_id = 'tr1'; p.pending_or_uncleared_evidence[0].reflected_in_authoritative = false; p.pending_or_uncleared_evidence[0].represented_as_deduction = true; p.pending_or_uncleared_evidence[0].economic_event_id = 'evtx'; } },

  // ── NEW-A duplicate manifest relation (owner §10.1-7) ───────────────────────────────────────────────────
  { id: 'PF-82', cls: 'newA_duplicate_relation_entry', expect_admissible: false, mutate: (p) => { const q0 = p.source_query_manifest.find((q) => q.relation === 'cash_commitments'); p.source_query_manifest.push({ ...q0, query_id: 'q_cc2' }); } },
  { id: 'PF-83', cls: 'newA_conflicting_row_count', expect_admissible: false, mutate: (p) => { const q0 = p.source_query_manifest.find((q) => q.relation === 'cash_commitments'); p.source_query_manifest.push({ ...q0, query_id: 'q_cc2' }); }, post: (p) => { const dup = p.source_query_manifest.find((q) => q.query_id === 'q_cc2'); dup.row_count = 99; } },
  { id: 'PF-84', cls: 'newA_conflicting_scope', expect_admissible: false, mutate: (p) => { const q0 = p.source_query_manifest.find((q) => q.relation === 'cash_commitments'); p.source_query_manifest.push({ ...q0, query_id: 'q_cc2', filter: 'other-scope' }); } },
  { id: 'PF-85', cls: 'newA_conflicting_digest', expect_admissible: false, mutate: (p) => { const q0 = p.source_query_manifest.find((q) => q.relation === 'cash_commitments'); q0.digest = 'a'.repeat(64); p.source_query_manifest.push({ ...q0, query_id: 'q_cc2', digest: 'b'.repeat(64) }); } },
  { id: 'PF-86', cls: 'newA_duplicate_query_id', expect_admissible: false, mutate: (p) => { const q0 = p.source_query_manifest.find((q) => q.relation === 'cash_commitments'); p.source_query_manifest.push({ ...q0, relation: 'transactions' }); } },
  { id: 'PF-87', cls: 'newA_success_plus_partial', expect_admissible: false, mutate: (p) => { const q0 = p.source_query_manifest.find((q) => q.relation === 'cash_commitments'); p.source_query_manifest.push({ ...q0, query_id: 'q_cc2', execution_status: 'partial' }); } },

  // ── NEW-B materiality self-assertion (owner §10.8-13) ───────────────────────────────────────────────────
  { id: 'PF-88', cls: 'newB_material_false_no_deduction', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].material = false; p.off_model_obligation_evidence[0].authoritative_path = null; } },
  { id: 'PF-89', cls: 'newB_material_missing_no_deduction', expect_admissible: false, mutate: (p) => { delete p.off_model_obligation_evidence[0].material; p.off_model_obligation_evidence[0].authoritative_path = null; } },
  { id: 'PF-90', cls: 'newB_material_false_with_live_deduction', expect_admissible: true, mutate: (p) => { p.off_model_obligation_evidence[0].material = false; } },
  { id: 'PF-91', cls: 'newB_completed_task_no_deduction', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].material = true; p.off_model_obligation_evidence[0].authoritative_path = null; } },

  // ── NEW-C referenced-deduction liveness (owner §10.14-22) ───────────────────────────────────────────────
  { id: 'PF-92', cls: 'newC_linked_voided_commitment', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].linked_economic_id = '2026mw6_voided_x'; p.off_model_obligation_evidence[0].amount_cents = 50000; } },
  { id: 'PF-93', cls: 'newC_linked_affects_false', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[1].affects_deployable_cash = false; } },
  { id: 'PF-94', cls: 'newC_linked_already_reflected', expect_admissible: false, mutate: (p) => { p.cash_commitment_evidence[1].reflected_in_actuals = true; } },
  { id: 'PF-95', cls: 'newC_inactive_adjustment', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].authoritative_path = 'baseline_e_adjustment'; p.off_model_obligation_evidence[0].linked_economic_id = 'adj_bkx'; p.baseline_e_adjustments = [{ adjustment_id: 'adj_bkx', amount_cents: 70090, source_account: 'truist_checking', economic_event_id: 'adj_bkx', active: false }]; } },
  { id: 'PF-96', cls: 'newC_linked_valid_active', expect_admissible: true, mutate: () => {} },

  // ── NEW-D extended integrity (owner §10.23-28) — post-stamp tamper ──────────────────────────────────────
  { id: 'PF-97', cls: 'newD_tamper_adjustment', expect_admissible: false, mutate: (p) => { p.baseline_e_adjustments = [{ adjustment_id: 'adj_x', amount_cents: 100, source_account: 'truist_checking', economic_event_id: 'adj_x', active: true }]; }, post: (p) => { p.baseline_e_adjustments[0].amount_cents = 999999; } },
  { id: 'PF-98', cls: 'newD_tamper_linkage', expect_admissible: false, mutate: (p) => { p.economic_linkages = [{ source_namespace: 'pending', source_id: 'x', target_namespace: 'commitment', target_id: 'y', linkage_type: 'settles', cardinality: '1:1' }]; }, post: (p) => { p.economic_linkages[0].target_id = 'z'; } },
  { id: 'PF-99', cls: 'newD_tamper_attestation', expect_admissible: false, mutate: () => {}, post: (p) => { p.completeness_attestations.commitments.rows_returned = 999; } },
  { id: 'PF-100', cls: 'newD_tamper_manifest', expect_admissible: false, mutate: () => {}, post: (p) => { p.source_query_manifest[0].filter = 'tampered'; } },
  { id: 'PF-101', cls: 'newD_tamper_eval_window', expect_admissible: false, mutate: () => {}, post: (p) => { p.execution_identity.evaluation_model_week = 30; } },

  // ── NEW-E within-path economic-identity dedup (owner §10.29-35) ─────────────────────────────────────────
  { id: 'PF-102', cls: 'newE_two_pending_same_event', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [{ txn_id: 'pa', account_key: 'truist_checking', amount_cents: -1000, direction: 'debit', reflected_in_authoritative: false, represented_as_deduction: true, economic_event_id: 'dup_evt', as_of_utc: AS_OF }, { txn_id: 'pb', account_key: 'truist_checking', amount_cents: -1000, direction: 'debit', reflected_in_authoritative: false, represented_as_deduction: true, economic_event_id: 'dup_evt', as_of_utc: AS_OF }]; } },
  { id: 'PF-103', cls: 'newE_two_adjustments_same_event', expect_admissible: false, mutate: (p) => { p.baseline_e_adjustments = [{ adjustment_id: 'a1', amount_cents: 100, source_account: 'truist_checking', economic_event_id: 'dup_evt', active: true }, { adjustment_id: 'a2', amount_cents: 100, source_account: 'truist_checking', economic_event_id: 'dup_evt', active: true }]; } },
  { id: 'PF-104', cls: 'newE_same_label_distinct_ids', expect_admissible: true, mutate: (p) => { p.pending_or_uncleared_evidence = [{ txn_id: 'pa', account_key: 'truist_checking', amount_cents: -1000, direction: 'debit', reflected_in_authoritative: false, represented_as_deduction: true, economic_event_id: 'evt_a', label: 'same label', as_of_utc: AS_OF }, { txn_id: 'pb', account_key: 'truist_checking', amount_cents: -1000, direction: 'debit', reflected_in_authoritative: false, represented_as_deduction: true, economic_event_id: 'evt_b', label: 'same label', as_of_utc: AS_OF }]; } },

  // ── NEW-F linkage-derived authoritative identity (owner §8.1-14) ────────────────────────────────────────
  // (OBS-5) each linked event target below is ESTABLISHED by a non-deducting estab() record carrying its direct id;
  // the double-count / distinct-target semantics are unchanged, but the target now genuinely exists in the package.
  { id: 'PF-105', cls: 'newF_two_pending_linked_same_target', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa'), pend('pb'), estab('T', 'eT')]; p.economic_linkages = [link('pending', 'pa', 'event', 'T'), link('pending', 'pb', 'event', 'T')]; } },
  { id: 'PF-106', cls: 'newF_two_adjustments_linked_same_target', expect_admissible: false, mutate: (p) => { p.baseline_e_adjustments = [adj('a1'), adj('a2')]; p.pending_or_uncleared_evidence = [estab('T', 'eT')]; p.economic_linkages = [link('adjustment', 'a1', 'event', 'T'), link('adjustment', 'a2', 'event', 'T')]; } },
  { id: 'PF-107', cls: 'newF_pending_and_adjustment_same_target', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa'), estab('T', 'eT')]; p.baseline_e_adjustments = [adj('a1')]; p.economic_linkages = [link('pending', 'pa', 'event', 'T'), link('adjustment', 'a1', 'event', 'T')]; } },
  { id: 'PF-108', cls: 'newF_direct_and_linked_same_target', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa', 'T'), pend('pb')]; p.economic_linkages = [link('pending', 'pb', 'event', 'T')]; } },
  { id: 'PF-109', cls: 'newF_distinct_targets', expect_admissible: true, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa'), pend('pb'), estab('T1', 'eT1'), estab('T2', 'eT2')]; p.economic_linkages = [link('pending', 'pa', 'event', 'T1'), link('pending', 'pb', 'event', 'T2')]; } },
  { id: 'PF-110', cls: 'newF_linkage_ambiguous_target', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa'), estab('T1', 'eT1'), estab('T2', 'eT2')]; p.economic_linkages = [link('pending', 'pa', 'event', 'T1'), link('pending', 'pa', 'event', 'T2')]; } },
  { id: 'PF-111', cls: 'newF_duplicate_linkage', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', 'pa', 'event', 'T1'), link('pending', 'pa', 'event', 'T1')]; } },
  { id: 'PF-112', cls: 'newF_many_to_one_no_aggregation', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa'), pend('pb'), estab('T', 'eT')]; p.economic_linkages = [link('pending', 'pa', 'event', 'T'), link('pending', 'pb', 'event', 'T')]; } },
  { id: 'PF-113', cls: 'newF_rename_label_same_target', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [{ ...pend('pa'), label: 'A' }, { ...pend('pb'), label: 'B' }, estab('T', 'eT')]; p.economic_linkages = [link('pending', 'pa', 'event', 'T'), link('pending', 'pb', 'event', 'T')]; } },
  { id: 'PF-114', cls: 'newF_unresolved_identity', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; } },
  { id: 'PF-115', cls: 'newF_valid_single_linkage_established_target', expect_admissible: true, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa'), estab('T1', 'eT1')]; p.economic_linkages = [link('pending', 'pa', 'event', 'T1')]; } },

  // ── section-G source-authority (owner §5 / §8.15-24) — no self-asserted exemption ──────────────────────
  { id: 'PF-116', cls: 'secG_affects_false_builder_no_deduction', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].affects_deployable_cash = false; p.off_model_obligation_evidence[0].authoritative_path = null; } },
  { id: 'PF-117', cls: 'secG_completed_no_deduction', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].completed = true; p.off_model_obligation_evidence[0].material = true; p.off_model_obligation_evidence[0].authoritative_path = null; } },
  { id: 'PF-118', cls: 'secG_unsupported_field_no_deduction', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].some_claimed_authority = true; p.off_model_obligation_evidence[0].authoritative_path = null; } },
  { id: 'PF-119', cls: 'secG_linked_non_live', expect_admissible: false, mutate: (p) => { p.off_model_obligation_evidence[0].linked_economic_id = '2026mw6_voided_x'; p.off_model_obligation_evidence[0].amount_cents = 50000; } },
  { id: 'PF-120', cls: 'secG_linked_valid_active_adjustment', expect_admissible: true, mutate: (p) => { p.off_model_obligation_evidence[0].authoritative_path = 'baseline_e_adjustment'; p.off_model_obligation_evidence[0].linked_economic_id = 'adj_bkx'; p.baseline_e_adjustments = [{ adjustment_id: 'adj_bkx', amount_cents: 70090, source_account: 'truist_checking', economic_event_id: 'adj_bkx', active: true }]; } },

  // ── RG-1..RG-6 linkage-graph residual hardening (owner-authorized additive pass 2026-07-30) ─────────────
  // RG-1: an unrecognized target namespace (`evt` vs `event`) fails closed — no open vocabulary.
  { id: 'PF-121', cls: 'rg1_unknown_target_namespace', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', 'pa', 'evt', 'FRESH')]; } },
  // RG-1: an unrecognized source namespace fails closed.
  { id: 'PF-122', cls: 'rg1_unknown_source_namespace', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('sched', 'pa', 'event', 'FRESH')]; } },
  // RG-2: a direct economic_event_id equal to a commitment expected_item_id is the SAME event -> double count.
  { id: 'PF-123', cls: 'rg2_direct_event_equals_commitment', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa', '2026mw6_bkx_2026_07_01')]; } },
  // RG-3: a two-hop chain (pa -> pb -> event:T) — the pb hop targets a local row (caught by vocab; graph guard behind it).
  { id: 'PF-124', cls: 'rg3_linkage_chain', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa'), pend('pb')]; p.economic_linkages = [link('pending', 'pa', 'pending', 'pb'), link('pending', 'pb', 'event', 'T')]; } },
  // RG-4: a linkage target that is another deduction's local row id (adjustment a1) fails closed.
  { id: 'PF-125', cls: 'rg4_target_is_local_row', expect_admissible: false, mutate: (p) => { p.baseline_e_adjustments = [adj('a1', 'EV_A1')]; p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', 'pa', 'adjustment', 'a1')]; } },
  // RG-5: declared_aggregations is REMOVED — a self-asserted aggregation exemption no longer excuses a within-path double count.
  { id: 'PF-126', cls: 'rg5_declared_aggregation_ignored', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa'), pend('pb'), estab('T', 'eT')]; p.economic_linkages = [link('pending', 'pa', 'event', 'T'), link('pending', 'pb', 'event', 'T')]; p.declared_aggregations = [{ target_namespace: 'event', target_id: 'T' }]; } },

  // ── OBS-5 identity validation + source/target existence + orphan linkages (owner final correction 2026-07-30) ──
  // RG-3 isolated: a namespace-VALID shared-token indirection (pa->event:SH, adjustment:SH->commitment) — the id token
  // 'SH' is both a linkage source and a linkage target. Caught by the graph guard with vocabulary validation ACTIVE.
  { id: 'PF-127', cls: 'obs5_rg3_shared_token_indirection', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.baseline_e_adjustments = [adj('SH')]; p.economic_linkages = [link('pending', 'pa', 'event', 'SH'), link('adjustment', 'SH', 'commitment', '2026mw6_rent_2026_07_01')]; } },
  // empty / whitespace / malformed identities → HOLD (validated before namespace construction or dedup).
  { id: 'PF-128', cls: 'obs5_empty_source_id', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', '', 'event', 'T')]; } },
  { id: 'PF-129', cls: 'obs5_whitespace_source_id', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', '   ', 'event', 'T')]; } },
  { id: 'PF-130', cls: 'obs5_empty_target_id', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', 'pa', 'event', '')]; } },
  { id: 'PF-131', cls: 'obs5_whitespace_target_id', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', 'pa', 'event', '  ')]; } },
  // source record absent (event target established so the sole fault is the missing source).
  { id: 'PF-132', cls: 'obs5_source_record_absent', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [estab('T', 'eT')]; p.economic_linkages = [link('pending', 'ghostsrc', 'event', 'T')]; } },
  // commitment target absent → HOLD; flips admissible only if commitment existence is ignored.
  { id: 'PF-133', cls: 'obs5_commitment_target_absent', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', 'pa', 'commitment', 'NOEXIST')]; } },
  // event target referenced only by the linkage (not independently established) → HOLD.
  { id: 'PF-134', cls: 'obs5_event_target_not_established', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', 'pa', 'event', 'GHOST')]; } },
  // event target established by a direct authoritative economic_event_id record → VALID.
  { id: 'PF-135', cls: 'obs5_event_target_established_valid', expect_admissible: true, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa'), estab('EOK', 'eok')]; p.economic_linkages = [link('pending', 'pa', 'event', 'EOK')]; } },
  // commitment target resolves to exactly one commitment (existence passes) — a deducting source then correctly double-counts.
  { id: 'PF-136', cls: 'obs5_commitment_resolves_one_double_count', expect_admissible: false, mutate: (p) => { p.baseline_e_adjustments = [adj('a1')]; p.economic_linkages = [link('adjustment', 'a1', 'commitment', '2026mw6_bkx_2026_07_01')]; } },
  // commitment target ambiguous (two commitments share an id) → FAIL_STOP (P-6 identity uniqueness).
  { id: 'PF-137', cls: 'obs5_commitment_target_ambiguous', expect_admissible: false, mutate: (p) => { const dup = { ...p.cash_commitment_evidence[0], expected_item_id: 'DUPID' }; p.cash_commitment_evidence.push(dup, { ...dup }); p.pending_or_uncleared_evidence = [pend('pa')]; p.economic_linkages = [link('pending', 'pa', 'commitment', 'DUPID')]; } },
  // orphan unused linkage (source is a non-deducting record) → HOLD; flips admissible only if orphans are ignored.
  { id: 'PF-138', cls: 'obs5_orphan_unused_linkage', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [{ ...estab('EOK', 'orph'), economic_event_id: undefined }, estab('EOK', 'eok')]; p.economic_linkages = [link('pending', 'orph', 'event', 'EOK')]; } },
  // linkage target that exists only in an unknown top-level section is NOT established → HOLD.
  { id: 'PF-139', cls: 'obs5_target_only_in_unknown_section', expect_admissible: false, mutate: (p) => { p.pending_or_uncleared_evidence = [pend('pa')]; p.some_unknown_section = [{ economic_event_id: 'GHOSTSEC' }]; p.economic_linkages = [link('pending', 'pa', 'event', 'GHOSTSEC')]; } },
  // valid source + valid authoritative (adjustment-source, established event) target → admissible.
  { id: 'PF-140', cls: 'obs5_valid_source_and_authoritative_target', expect_admissible: true, mutate: (p) => { p.baseline_e_adjustments = [adj('a1')]; p.pending_or_uncleared_evidence = [estab('EB', 'eb')]; p.economic_linkages = [link('adjustment', 'a1', 'event', 'EB')]; } },
];
