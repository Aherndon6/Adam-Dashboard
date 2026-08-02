// baseline-E/live-preflight/run-live-preflight.mjs
// Runs every synthetic fixture + the executable mutation matrix through the actual validator; writes deterministic
// machine-readable results. SYNTHETIC ONLY. No network, no SQL, no secrets, no capacity math.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { validatePackage, controlBooleans } from './live-preflight-validator.mjs';
import { FIXTURES } from './live-preflight-fixtures.mjs';
import { CONTRACT_VERSION, LEGACY_SPEC_VERSION } from './live-preflight-contract.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));

// [id, fixtureId, mut, baseMut?] — correct = validate(fixture, baseMut); mutant = validate(fixture, {...baseMut,...mut}).
// Each must flip NOT-ADMISSIBLE -> ADMISSIBLE deterministically.
export const MUTATIONS = [
  ['MUT-01_null_recon_accepted', 'PF-06', { nullReconAccepted: true }],
  ['MUT-02_duplicate_recon_ignored', 'PF-08', { ignoreDupRecon: true }],
  ['MUT-03_failed_fetch_as_empty', 'PF-11', { failedFetchAsEmpty: true }],
  ['MUT-04_offmodel_warning_only', 'PF-20', { offModelWarningOnly: true }],
  ['MUT-05_negative_commitment_accepted', 'PF-17', { negativeCommitmentAccepted: true }],
  ['MUT-06_uncleared_item_omitted', 'PF-23', { unclearedOmitted: true }],
  ['MUT-07_terminal_release_no_evidence', 'PF-28', { terminalNoEvidence: true }],
  ['MUT-08_untyped_evidence_accepted', 'PF-29', { untypedEvidence: true }],
  ['MUT-09_manifest_count_ignored', 'PF-33', { ignoreCardinality: true }],
  ['MUT-10_evidence_hash_bypassed', 'PF-34', { bypassIntegrity: true }],
  ['MUT-11_environment_mismatch_ignored', 'PF-04', { ignoreEnvMismatch: true }],
  ['MUT-12_duplicate_obligation_deduction', 'PF-37', { allowDoubleCount: true }],
  ['MUT-13_transfer_mirror_double_count', 'PF-25', { allowTransferDouble: true }],
  ['MUT-14_hold_promoted_to_pass', 'PF-40', { holdToPass: true }],
  ['MUT-15_f_release_without_j_evidence', 'PF-41', { terminalNoEvidence: true }],
  ['MUT-16_bare_clearing_linkage_accepted', 'PF-44', { acceptBareClearing: true }],
  ['MUT-17_dangling_offmodel_reference_accepted', 'PF-48', { offModelWarningOnly: true }],
  ['MUT-18_self_asserted_threshold_accepted', 'PF-54', { acceptThreshold: true }],
  ['MUT-19_empty_balance_anchor_accepted', 'PF-56', { ignoreAnchor: true }],
  ['MUT-20_verified_empty_no_rows_visible_accepted', 'PF-60', { acceptVerifiedEmptyNoVisible: true }],
  ['MUT-21_unattested_terminal_section_accepted', 'PF-63', { acceptUnattested: true }],
  ['MUT-22_malformed_multileg_transfer_accepted', 'PF-65', { allowTransferDouble: true }],
  ['MUT-23_one_cent_transfer_skew_accepted', 'PF-66', { allowTransferDouble: true }],
  ['MUT-24_renameable_economic_identity_accepted', 'PF-70', { allowDoubleCount: true }],
  ['MUT-25_missing_query_provenance_accepted', 'PF-74', { ignoreProvenance: true }],
  ['MUT-26_out_of_window_timestamp_accepted', 'PF-77', { ignoreAsOf: true }],
  ['MUT-27_cross_control_contradiction_ignored', 'PF-81', { ignoreCrossControl: true }],
  // ── NEW-A..E + meta (final hardening) ──
  ['MUT-28_duplicate_manifest_relation_accepted', 'PF-82', { ignoreDupRelation: true }],
  ['MUT-29_trust_self_asserted_material_false', 'PF-88', { trustMaterialFalse: true }],
  ['MUT-30_ignore_deduction_liveness', 'PF-92', { ignoreDeductionLiveness: true }],
  ['MUT-31_exclude_ext_sections_from_hashing', 'PF-97', { excludeExtDigest: true }],
  ['MUT-32_within_path_double_count_allowed', 'PF-102', { allowDoubleCount: true }],
  ['MUT-33_skip_required_blocking_control', 'PF-41', { skipControl: 'reserve_release_evidence_complete', metaBlind: true }],
  ['MUT-34_admissible_before_xc', 'PF-81', { earlyReturnBeforeControl: 'cross_control_consistency_verified', metaBlind: true }],
  ['MUT-35_caller_supplied_admissibility', 'PF-40', { callerAdmissible: true }],
  ['MUT-36_ignore_duplicate_control_result', 'PF-01', { metaBlind: true }, { injectDuplicatePass: 'commitments_valid' }],
  ['MUT-37_ignore_unknown_control_result', 'PF-01', { metaBlind: true }, { injectUnknownPass: true }],
  // ── NEW-F + section-G source authority (final) ──
  ['MUT-38_dedup_local_row_id_fallback', 'PF-105', { dedupLocalRowFallback: true }],
  ['MUT-39_trust_section_g_affects_false', 'PF-116', { trustAffectsFalse: true }],
  ['MUT-40_trust_section_g_completed', 'PF-117', { trustCompleted: true }],
  ['MUT-41_permit_ambiguous_linkage_target', 'PF-110', { ignoreLinkageAmbiguity: true }],
  // ── RG-1..RG-4 linkage-graph residual hardening (RG-5 removal / RG-6 reason-code proven by fixtures+tests) ──
  ['MUT-42_open_namespace_vocabulary', 'PF-121', { ignoreNamespaceVocab: true }],
  ['MUT-43_event_commitment_id_dodge', 'PF-123', { ignoreEventCommitmentEquivalence: true }],
  ['MUT-45_target_is_local_row_id', 'PF-125', { ignoreNamespaceVocab: true }],
  // ── OBS-5 identity-resolution guards (empty-id / source-existence / isolated RG-3 proven by attribution tests) ──
  ['MUT-46_ignore_orphan_linkage', 'PF-138', { allowOrphanLinkage: true }],
  ['MUT-47_trust_event_target_as_proof', 'PF-134', { trustEventTargetEstablished: true }],
  ['MUT-48_ignore_commitment_target_existence', 'PF-133', { ignoreCommitmentTargetExistence: true }],
  // ── S-7 v3.1 durable-clearing lane (G1/G2/G5/legacy-authority) ──
  ['MUT-49_ignore_cleared_release', 'PF-141', { ignoreClearedRelease: true }],           // G1 released-set is load-bearing
  ['MUT-50_ignore_evidence_source_routing', 'PF-146', { ignoreEvidenceSourceRouting: true }], // G2 closed-set routing is load-bearing
  ['MUT-51_ignore_cross_lane_reuse', 'PF-151', { ignoreCrossLaneReuse: true }],            // G5/G8 cross-lane reuse guard is load-bearing
  ['MUT-52_ignore_legacy_authority', 'PF-148', { ignoreLegacyAuthority: true }, { useGlobalLegacyFloor: true }], // legacy pinned-six gate load-bearing (v2 lower-bound-missing neutralized in base)
  // ── Mode-2 F-1/F-2 durable-clearing binding + as-of window ──
  ['MUT-53_ignore_clearing_txn_existence', 'PF-153', { ignoreClearingTxnExistence: true }], // F-1 referenced-txn existence
  ['MUT-54_ignore_clearing_txn_digest', 'PF-156', { ignoreClearingTxnDigest: true }],        // F-1 clearing-digest recompute/match
  ['MUT-55_ignore_clearing_binding_direction', 'PF-143', { ignoreClearingTxnBinding: true }],// F-1 register-authoritative direction
  ['MUT-56_ignore_clearing_binding_state', 'PF-144', { ignoreClearingTxnBinding: true }],    // F-1 register-authoritative state
  ['MUT-57_ignore_clearing_asof_lower', 'PF-160', { ignoreClearingAsofLower: true }],         // F-2/N-5 as-of lower bound (isolated)
  ['MUT-58_ignore_clearing_asof_upper', 'PF-145', { ignoreClearingAsofUpper: true }],         // F-2/N-5 as-of upper bound (isolated)
  ['MUT-59_ignore_legacy_unauthorized', 'PF-149', { ignoreLegacyAuthority: true }],          // legacy authorized-owner gate
  ['MUT-60_ignore_legacy_unregistered', 'PF-150', { ignoreLegacyAuthority: true }],          // legacy accepted-registry gate
  // ── Mode-2 N-1..N-5 (isolated attribution; transfer guards use baseMut to disable the OTHER control) ──
  ['MUT-61_ignore_s7_transfer_leg', 'PF-164', { ignoreS7TransferLeg: true }, { ignoreXcJLaneTransfer: true }],  // N-1 S-7 transfer-leg guard (XC off in base)
  ['MUT-62_ignore_xc_jlane_transfer', 'PF-164', { ignoreXcJLaneTransfer: true }, { ignoreS7TransferLeg: true }],// N-1 XC J-lane transfer guard (S-7 off in base)
  ['MUT-63_ignore_clearing_date_binding', 'PF-165', { ignoreClearingDateBinding: true }],     // N-3 exact row-date binding
  ['MUT-64_ignore_pending_clearing_conflict', 'PF-168', { ignorePendingClearingConflict: true }], // N-4 pending-and-clearing contradiction
  ['MUT-65_ignore_resolution_undetermined', 'PF-169', { ignoreResolutionUndetermined: true }], // N-5 null-resolution UNDETERMINED
  ['MUT-66_ignore_pinned_legacy_source', 'PF-170', { ignorePinnedLegacySource: true }],         // Obs-B: pinned-legacy source gate is load-bearing (untagged committed-class bypass)
  // ── legacy-clearing-v2 principal guards (F-3): baseMut acceptAllLegacyRegistry bypasses the pre-freeze empty registry
  //    so the Phase-1 v2 guard under test is reached; the mut disables exactly that guard and must flip to admissible. ──
  ['MUT-67_legacy_asof_lower_bound', 'PF-177', { ignoreClearingAsofLower: true }, { acceptAllLegacyRegistry: true }],           // v2: commitment-specific legacy lower bound (Kia < 07-07 floor)
  ['MUT-68_legacy_asof_upper_bound', 'PF-178', { ignoreClearingAsofUpper: true }, { acceptAllLegacyRegistry: true }],           // v2: legacy-lane upper freshness bound (window.end)
  ['MUT-69_legacy_asof_row_date_binding', 'PF-179', { ignoreClearingDateBinding: true }, { acceptAllLegacyRegistry: true }],    // v2: N-3 exact as-of/row-date binding on the legacy lane
  ['MUT-70_committed_lane_floor_isolation', 'PF-180', { applyLegacyFloorToCommittedLane: true }],                               // v2: committed lane keeps window.start (no legacy floor leak)
  ['MUT-71_legacy_lower_bound_missing', 'PF-181', { ignoreLegacyLowerBoundMissing: true }, { acceptAllLegacyRegistry: true, simulateMissingLegacyLowerBound: '2026mw4_rent_tiffany_dye_2026_07_01' }], // v2: map-gap defense-in-depth
  ['MUT-72_kia_pinned_variance', 'PF-183', { acceptAnyVariance: true }, { acceptAllLegacyRegistry: true }],                     // v2: Kia -50 is exact (delta -49 must HOLD; no band)
  ['MUT-73_nonkia_variance_rejected', 'PF-184', { acceptAnyVariance: true }, { acceptAllLegacyRegistry: true }],                // v2: -50 accepted ONLY for Kia (strict elsewhere)
  ['MUT-74_transfer_disposition_pinned', 'PF-187', { ignoreTransferDispositionGate: true }, { acceptAllLegacyRegistry: true, ignoreXcJLaneTransfer: true }], // v2: matched_internal_transfer only for the pinned-transfer set
  ['MUT-75_internal_transfer_leg_required', 'PF-188', { ignoreInternalTransferLegRequired: true, ignoreTransferGroup: true }, { acceptAllLegacyRegistry: true }], // v2: an internal transfer must reference an actual transfer leg
  ['MUT-76_transfer_group_malformed', 'PF-189', { ignoreTransferGroup: true }, { acceptAllLegacyRegistry: true, allowTransferDouble: true }],  // v2: authoritative two-leg group shape (P-8 bypassed to isolate S-7)
  ['MUT-77_transfer_group_mismatch', 'PF-194', { ignoreTransferGroup: true }, { acceptAllLegacyRegistry: true, ignoreXcJLaneTransfer: true }], // v2: record group id must equal the row group id
  ['MUT-78_transfer_group_id_invalid', 'PF-199', { acceptInvalidTransferGroupId: true }, { acceptAllLegacyRegistry: true, ignoreXcJLaneTransfer: true }], // F-2: non-empty canonical group id
  ['MUT-79_transfer_leg_also_deducted', 'PF-196', { ignoreTransferGroup: true }, { acceptAllLegacyRegistry: true, allowTransferDouble: true }], // v2: a transfer leg must not also be a deduction
  ['MUT-80_transfer_bank_clearing_on_leg', 'PF-197', { ignoreS7TransferLeg: true }, { acceptAllLegacyRegistry: true, ignoreXcJLaneTransfer: true }], // v2: matched_bank_clearing may not use a transfer leg
  ['MUT-81_transfer_mirror_leg_reuse', 'PF-195', { ignoreMirrorLegReuse: true }, { acceptAllLegacyRegistry: true, ignoreXcJLaneTransfer: true }], // v2: both legs participate in reuse protection
  ['MUT-82_xc_superseded_no_exemption', 'PF-198', { looseXcExemption: true }, { acceptAllLegacyRegistry: true }], // F-1: a superseded internal-transfer record must not earn the XC transfer exemption
];

function run() {
  const fixtureRows = FIXTURES.map((fx) => {
    const r = validatePackage(fx.package);
    return { id: fx.id, cls: fx.cls, expect_admissible: fx.expect_admissible, package_admissible: r.package_admissible, worst_disposition: r.worst_disposition, reasons: [...r.fail_stops, ...r.holds].filter(Boolean) };
  });
  const fixtureMismatches = fixtureRows.filter((r) => r.package_admissible !== r.expect_admissible);
  const mutationRows = MUTATIONS.map(([id, fixtureId, mut, baseMut]) => {
    const fx = FIXTURES.find((f) => f.id === fixtureId);
    const base = baseMut || {};
    const correct = validatePackage(fx.package, base).package_admissible;
    const mutated = validatePackage(fx.package, { ...base, ...mut }).package_admissible;
    const mutated2 = validatePackage(fx.package, { ...base, ...mut }).package_admissible;
    return { id, fixture: fixtureId, correct_admissible: correct, mutated_admissible: mutated, diverged: correct !== mutated, deterministic: mutated === mutated2 };
  });
  const mutationCoverageComplete = mutationRows.every((m) => m.diverged && m.deterministic && m.correct_admissible === false && m.mutated_admissible === true);
  const rep = FIXTURES.map((fx) => fx.id + ':' + validatePackage(fx.package).package_admissible).join('|') === fixtureRows.map((r) => r.id + ':' + r.package_admissible).join('|');
  const golden = validatePackage(FIXTURES.find((f) => f.id === 'PF-01').package);
  const gb = controlBooleans(golden);
  const notAdmissible = (id) => validatePackage(FIXTURES.find((f) => f.id === id).package).package_admissible === false;
  const closed = { A: notAdmissible('PF-82'), B: notAdmissible('PF-88'), C: notAdmissible('PF-92'), D: notAdmissible('PF-97'), E: notAdmissible('PF-102'), F: notAdmissible('PF-105') };
  const secG = { affectsFalse: notAdmissible('PF-116'), completed: notAdmissible('PF-117'), unsupported: notAdmissible('PF-118') };
  const reasonOf = (id, ctrl) => { const r = validatePackage(FIXTURES.find((f) => f.id === id).package); return (r.control_results.find((c) => c.id === ctrl) || {}).reason_code; };
  const rg = {
    RG1: notAdmissible('PF-121') && notAdmissible('PF-122') && reasonOf('PF-121', 'P-7') === 'P7_LINKAGE_TARGET_NOT_AUTHORITATIVE' && reasonOf('PF-122', 'P-7') === 'P7_LINKAGE_SOURCE_NAMESPACE_UNKNOWN',
    RG2: notAdmissible('PF-123') && reasonOf('PF-123', 'P-7') === 'P7_DUPLICATE_LINKED_ECONOMIC_EVENT',
    RG3: notAdmissible('PF-124') && reasonOf('PF-124', 'P-7') === 'P7_LINKAGE_TARGET_NOT_AUTHORITATIVE'
      && validatePackage(FIXTURES.find((f) => f.id === 'PF-124').package, { ignoreNamespaceVocab: true }).control_results.find((c) => c.id === 'P-7').reason_code === 'P7_LINKAGE_GRAPH_INDIRECTION',
    RG4: notAdmissible('PF-125') && reasonOf('PF-125', 'P-7') === 'P7_LINKAGE_TARGET_NOT_AUTHORITATIVE',
    RG5: notAdmissible('PF-126') && reasonOf('PF-126', 'P-7') === 'P7_LINKAGE_WITHIN_PATH_DOUBLE_COUNT',
    RG6: notAdmissible('PF-118') && reasonOf('PF-118', 'S-1') === 'S1_UNSUPPORTED_AUTHORITY_FIELD',
  };
  const rgAllClosed = Object.values(rg).every(Boolean);
  const p7ReasonMut = (id, mut) => (validatePackage(FIXTURES.find((f) => f.id === id).package, mut).control_results.find((c) => c.id === 'P-7') || {}).reason_code;
  const admissible = (id) => validatePackage(FIXTURES.find((f) => f.id === id).package).package_admissible === true;
  const obs5 = {
    empty_identity_rejected: reasonOf('PF-128', 'P-7') === 'P7_LINKAGE_SOURCE_ID_MISSING' && reasonOf('PF-129', 'P-7') === 'P7_LINKAGE_SOURCE_ID_MISSING'
      && reasonOf('PF-130', 'P-7') === 'P7_LINKAGE_TARGET_ID_MISSING' && reasonOf('PF-131', 'P-7') === 'P7_LINKAGE_TARGET_ID_MISSING'
      && p7ReasonMut('PF-128', { acceptEmptySourceId: true }) !== 'P7_LINKAGE_SOURCE_ID_MISSING' && p7ReasonMut('PF-130', { acceptEmptyTargetId: true }) !== 'P7_LINKAGE_TARGET_ID_MISSING',
    linkage_source_existence_verified: reasonOf('PF-132', 'P-7') === 'P7_LINKAGE_SOURCE_NOT_FOUND' && p7ReasonMut('PF-132', { ignoreSourceExistence: true }) !== 'P7_LINKAGE_SOURCE_NOT_FOUND',
    linkage_target_existence_verified: reasonOf('PF-133', 'P-7') === 'P7_LINKAGE_COMMITMENT_NOT_FOUND' && reasonOf('PF-134', 'P-7') === 'P7_LINKAGE_EVENT_NOT_ESTABLISHED' && reasonOf('PF-139', 'P-7') === 'P7_LINKAGE_EVENT_NOT_ESTABLISHED',
    authoritative_event_target_established: admissible('PF-135') && admissible('PF-140'),
    authoritative_commitment_target_resolved: reasonOf('PF-136', 'P-7') === 'P7_DUPLICATE_LINKED_ECONOMIC_EVENT' && notAdmissible('PF-137'),
    orphan_linkages_rejected: reasonOf('PF-138', 'P-7') === 'P7_ORPHAN_LINKAGE',
    pf_115_corrected: admissible('PF-115') && (FIXTURES.find((f) => f.id === 'PF-115').package.pending_or_uncleared_evidence || []).some((r) => r.economic_event_id === 'T1' && r.represented_as_deduction === false),
    rg3_graph_guard_independently_mutated: reasonOf('PF-127', 'P-7') === 'P7_LINKAGE_GRAPH_INDIRECTION' && p7ReasonMut('PF-127', { allowGraphIndirection: true }) !== 'P7_LINKAGE_GRAPH_INDIRECTION',
  };
  const obs5Closed = Object.values(obs5).every(Boolean);
  // ── legacy-clearing-v2 durable coverage (F-3): each specific v2 reason code + the PASS lanes, witnessed with the
  //    registry-bypass injection so this artifact permanently records the Phase-1 legacy behavior. ──
  const reasonMut = (id, ctrl, mut) => (validatePackage(FIXTURES.find((f) => f.id === id).package, mut).control_results.find((c) => c.id === ctrl) || {}).reason_code;
  const admMut = (id, mut) => validatePackage(FIXTURES.find((f) => f.id === id).package, mut).package_admissible === true;
  const REG = { acceptAllLegacyRegistry: true };
  const v2 = {
    spec_version: LEGACY_SPEC_VERSION,
    lower_bound_valid_floor_pass: admMut('PF-176', REG),
    lower_bound_kia_one_day_before_floor: reasonMut('PF-177', 'S-7', REG) === 'S7_CLEARING_ASOF_OUT_OF_WINDOW',
    lower_bound_after_window: reasonMut('PF-178', 'S-7', REG) === 'S7_CLEARING_ASOF_OUT_OF_WINDOW',
    lower_bound_row_date_mismatch: reasonMut('PF-179', 'S-7', REG) === 'S7_CLEARING_ASOF_ROW_MISMATCH',
    committed_lane_isolation: notAdmissible('PF-180') && admMut('PF-180', { applyLegacyFloorToCommittedLane: true }),
    lower_bound_missing_map_entry: reasonMut('PF-181', 'S-7', { ...REG, simulateMissingLegacyLowerBound: '2026mw4_rent_tiffany_dye_2026_07_01' }) === 'S7_LEGACY_LOWER_BOUND_MISSING',
    variance_kia_exact_pass: admMut('PF-182', REG),
    variance_kia_minus_49_hold: reasonMut('PF-183', 'S-7', REG) === 'S7_CLEARING_AMOUNT_MISMATCH',
    variance_nonkia_minus_50_hold: reasonMut('PF-184', 'S-7', REG) === 'S7_CLEARING_AMOUNT_MISMATCH',
    variance_kia_row_amount_mismatch: reasonMut('PF-185', 'S-7', REG) === 'S7_CLEARING_AMOUNT_MISMATCH',
    transfer_valid_internal_transfer_pass: admMut('PF-186', REG),
    transfer_disposition_not_pinned: reasonOf('PF-187', 'S-7') === 'S7_TRANSFER_DISPOSITION_NOT_PINNED',
    transfer_unmarked_leg: reasonMut('PF-188', 'S-7', REG) === 'S7_INTERNAL_TRANSFER_LEG_REQUIRED',
    transfer_malformed_one_leg: reasonMut('PF-189', 'S-7', { ...REG, allowTransferDouble: true }) === 'S7_TRANSFER_GROUP_MALFORMED',
    transfer_malformed_three_leg: reasonMut('PF-190', 'S-7', { ...REG, allowTransferDouble: true }) === 'S7_TRANSFER_GROUP_MALFORMED',
    transfer_same_sign_legs: reasonMut('PF-191', 'S-7', { ...REG, allowTransferDouble: true }) === 'S7_TRANSFER_GROUP_MALFORMED',
    transfer_unequal_amounts: reasonMut('PF-192', 'S-7', { ...REG, allowTransferDouble: true }) === 'S7_TRANSFER_GROUP_MALFORMED',
    transfer_same_account_legs: reasonMut('PF-193', 'S-7', REG) === 'S7_TRANSFER_GROUP_MALFORMED',
    transfer_group_id_mismatch: reasonMut('PF-194', 'S-7', REG) === 'S7_TRANSFER_GROUP_MISMATCH',
    transfer_mirror_leg_reuse: reasonMut('PF-195', 'S-7', { ...REG, ignoreXcJLaneTransfer: true }) === 'S7_CLEARING_TXN_REUSE_CONFLICT',
    transfer_leg_also_deducted: reasonMut('PF-196', 'S-7', { ...REG, allowTransferDouble: true }) === 'S7_CLEARING_TXN_ALSO_DEDUCTED',
    transfer_bank_clearing_on_leg: reasonMut('PF-197', 'S-7', REG) === 'S7_CLEARING_TXN_IS_TRANSFER' || reasonMut('PF-197', 'XC', REG) === 'XC_TRANSFER_ALSO_CLEARING',
    f1_superseded_no_xc_exemption: reasonMut('PF-198', 'XC', REG) === 'XC_TRANSFER_ALSO_CLEARING' && admMut('PF-198', { ...REG, looseXcExemption: true }),
    f2_invalid_transfer_group_id: reasonMut('PF-199', 'S-7', REG) === 'S7_TRANSFER_GROUP_ID_INVALID',
  };
  const v2AllClosed = Object.entries(v2).filter(([, x]) => typeof x === 'boolean').every(([, x]) => x);
  const allClosed = fixtureMismatches.length === 0 && mutationCoverageComplete && Object.values(closed).every(Boolean) && Object.values(secG).every(Boolean) && rgAllClosed && obs5Closed && v2AllClosed;

  const out = {
    gate: 'BASELINE_E_LIVE_INPUT_PREFLIGHT', contract_version: CONTRACT_VERSION,
    note: 'SYNTHETIC-ONLY local proof of the fail-closed live-input preflight. A synthetic PASS does NOT imply live readiness or that any live package was collected.',
    synthetic_only: true, live_access_performed: false, sql_executed: false, operational_hold: true,
    capacity_calculation_eligible: false, obligation_set_complete: false, live_ready: false,
    package_admissible: golden.package_admissible,
    fable_re_review_verdict: 'APPROVE_WITH_NON_BLOCKING_CONDITIONS',
    // Prior narrow re-glance (NEW-F + section-G authority) returned verdict 2 with 6 linkage-graph residuals RG-1..RG-6.
    // Owner authorized an additive pass (2026-07-30) closing all six. A NEW narrow re-glance limited to RG-1..RG-6 +
    // the declared_aggregations removal follows this run; leave the verdict PENDING until it returns.
    // OBS-5 re-glance (2026-07-30) — scope: identity validation + source/target existence + orphan linkages + PF-115 +
    // independent RG-3. Verdict APPROVE_WITH_NON_BLOCKING_CONDITIONS: all OBS-5 guards confirmed load-bearing, PF-115
    // corrected, RG-3 independently proven; NO capacity-overstating escape survived. Two new non-blocking residuals
    // (R-1 inert/consistency, R-2 understating id-hygiene) — NOT implemented (new semantics -> owner review per §12).
    fable_re_glance_verdict: 'APPROVE_WITH_NON_BLOCKING_CONDITIONS',
    fable_re_glance_scope: 'OBS-5 (empty/whitespace ids, source/target existence, orphan linkages) + PF-115 + independent RG-3 mutation',
    prior_rg_re_glance_verdict: 'APPROVE_WITH_NON_BLOCKING_CONDITIONS', // RG-1..RG-6 confirmed closed; OBS-5 was the open condition
    fable_re_glance_capacity_overstating_escape_found: false,
    obs5_re_glance_new_residuals: [
      { id: 'R-1', direction: 'inert_consistency', capacity_overstating: false, summary: 'A linkage whose source carries a direct economic_event_id different from the linkage target is validated but never applied (resolve() prefers the direct id) and is marked consumed because the source row is a deduction. Count-preserving (each deduction counted once), not capacity-overstating; a dead/contradictory linkage rides along. Suggested tightening: HOLD P7_LINKAGE_DIRECT_ID_CONFLICT when a linkage source also carries a differing direct economic_event_id.' },
      { id: 'R-2', direction: 'capacity_understating', capacity_overstating: false, summary: 'Unicode format chars (e.g. U+200B zero-width space) pass isValidId (not trimmed, outside the \\u0000-\\u001F\\u007F screen). Establishment still requires an exact-match real record so no phantom target is established; the residual is visually-twin ids (T vs T\\u200B) counting as two events -> extra deduction = understating (OBS-1 family). Optional: extend the screen to \\u200B-\\u200D\\u2060\\uFEFF.' },
    ],
    rg_residuals_closed: rg,               // per-finding closure booleans (fixture + reason-code verified)
    rg_all_residuals_closed: rgAllClosed,
    declared_aggregations_removed: rg.RG5, // no self-asserted/inferred aggregation exemption remains in P-7
    linkage_namespace_vocabulary_closed: rg.RG1,
    event_commitment_identity_unified: rg.RG2,
    linkage_graph_indirection_rejected: rg.RG3,
    linkage_target_authoritative_only: rg.RG4,
    unsupported_authority_field_reason_code: rg.RG6,
    // ── OBS-5 closure (identity validation + source/target existence + orphan linkages + independent RG-3) ──
    obs_5_closed: obs5Closed,
    empty_identity_rejected: obs5.empty_identity_rejected,
    linkage_source_existence_verified: obs5.linkage_source_existence_verified,
    linkage_target_existence_verified: obs5.linkage_target_existence_verified,
    authoritative_event_target_established: obs5.authoritative_event_target_established,
    authoritative_commitment_target_resolved: obs5.authoritative_commitment_target_resolved,
    orphan_linkages_rejected: obs5.orphan_linkages_rejected,
    pf_115_corrected: obs5.pf_115_corrected,
    rg3_graph_guard_independently_mutated: obs5.rg3_graph_guard_independently_mutated,
    all_p7_identity_bypasses_closed: rgAllClosed && obs5Closed,
    obs5_detail: obs5,
    // ── legacy-clearing-v2 durable coverage (F-3): spec version + per-scenario reason-code / PASS-lane witnesses ──
    legacy_clearing_v2_spec_version: LEGACY_SPEC_VERSION,
    legacy_clearing_v2_coverage_closed: v2AllClosed,
    legacy_clearing_v2_coverage: v2,
    // OBS-1..OBS-4 remain documented non-blocking limitations (conservative / inert); OBS-5 is now CLOSED.
    remaining_non_blocking_observations: [
      { id: 'OBS-1', direction: 'capacity_understating', summary: 'RG-2 closes literal event/commitment id equality only; distinct id strings are distinct events without an authoritative event registry (understating).' },
      { id: 'OBS-2', direction: 'over_blocking', summary: 'A legitimate many-to-one split-payment aggregation is inexpressible (intended by RG-5).' },
      { id: 'OBS-3', direction: 'over_blocking', summary: 'Cross-id-space textual collision over-blocks (intended consequence of the one-id-space ruling).' },
      { id: 'OBS-4', direction: 'inert_structural', summary: 'Unknown top-level sections ride unhashed; inert today (no control reads them; the authoritative universe is built only from known sections). A section allowlist would close the class.' },
    ],
    new_f_closed: closed.F,
    linkage_authoritative_identity_resolved: closed.F && notAdmissible('PF-114'),
    linkage_target_deduplication_enforced: closed.F && notAdmissible('PF-106') && notAdmissible('PF-107'),
    linkage_within_path_double_count_closed: closed.F,
    local_row_id_fallback_prohibited: true, // MUT-38 proves the fallback is a caught bug
    section_g_cash_impact_authority_required: secG.affectsFalse,
    package_builder_cash_impact_exemption_closed: secG.affectsFalse,
    self_asserted_non_cash_exemption_closed: secG.affectsFalse && secG.completed && closed.B,
    authoritative_non_cash_proof_present: false, // no authoritative section-G non-cash field or policy artifact is authorized
    all_identity_family_findings_closed: closed.E && closed.F,
    all_known_preflight_findings_closed: allClosed,
    original_fable_findings_closed: true,
    new_a_closed: closed.A, new_b_closed: closed.B, new_c_closed: closed.C, new_d_closed: closed.D, new_e_closed: closed.E,
    all_capacity_overstatement_findings_closed: closed.A && closed.B && closed.C,
    duplicate_manifest_relation_closed: closed.A,
    materiality_self_assertion_closed: closed.B,
    referenced_deduction_liveness_enforced: closed.C,
    full_integrity_domain_covered: closed.D,
    within_path_deduplication_enforced: closed.E,
    // control-flow admissibility invariant (from the golden validation)
    required_control_ids: golden.required_control_ids,
    executed_control_ids: golden.executed_control_ids,
    missing_control_ids: golden.missing_control_ids,
    duplicate_control_ids: golden.duplicate_control_ids,
    unknown_control_ids: golden.unknown_control_ids,
    all_required_controls_executed: golden.all_required_controls_executed,
    control_flow_complete: golden.control_flow_complete,
    admissibility_derived_only: golden.admissibility_derived_only,
    alternate_success_path_detected: golden.alternate_success_path_detected,
    executable_mutation_coverage_complete: mutationCoverageComplete,
    all_fable_findings_closed: allClosed, // 8 original + NEW-A..F + section-G authority + meta
    all_capacity_overstatement_findings_closed: closed.A && closed.B && closed.C,
    open_findings: allClosed ? [] : ['see fixture/mutation totals'], // OBS-5 CLOSED; only conservative/inert OBS-1..OBS-4 remain (see remaining_non_blocking_observations)
    repeatable: rep,
    blocking_controls: golden.required_control_ids.concat(['contract_version_supported', 'required_sections_present', 'META']),
    golden_controls: gb, control_results: golden.control_results,
    fixture_totals: { total: FIXTURES.length, expected_admissible: FIXTURES.filter((f) => f.expect_admissible).length, expected_not_admissible: FIXTURES.filter((f) => !f.expect_admissible).length, mismatches: fixtureMismatches.length },
    fixtures: fixtureRows,
    mutation_totals: { total: mutationRows.length, all_caught: mutationCoverageComplete },
    mutations: mutationRows,
    remaining_blockers: [
      'Live evidence has NOT been collected: synthetic contract + validator proof only.',
      'A production package requires operator project confirmation, an authorized read-only extraction, and RLS/visibility proof — a separate owner-authorized gate.',
      'No materiality threshold and no real-time freshness policy are authorized; both fail closed.',
      'obligation_set_complete and capacity_calculation_eligible remain false until a real, attested live obligation load passes this preflight.',
    ],
  };
  writeFileSync(join(HERE, 'live-preflight-results.json'), JSON.stringify(out, null, 2));
  return out;
}

const out = run();
console.log('wrote live-preflight-results.json');
console.log('fixtures:', out.fixture_totals.total, 'mismatches:', out.fixture_totals.mismatches, '| golden admissible:', out.package_admissible);
console.log('mutations:', out.mutation_totals.total, 'all_caught:', out.mutation_totals.all_caught, '| repeatable:', out.repeatable);
console.log('new A/B/C/D/E closed:', out.new_a_closed, out.new_b_closed, out.new_c_closed, out.new_d_closed, out.new_e_closed, '| all_closed:', out.all_fable_findings_closed);
console.log('meta: all_required_executed:', out.all_required_controls_executed, '| control_flow_complete:', out.control_flow_complete, '| capacity_eligible:', out.capacity_calculation_eligible);
export { run };
