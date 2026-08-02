// baseline-E/test/live-preflight.test.mjs
// Hardened fail-closed live-input preflight: 140 synthetic fixtures + 47 executable mutations + invariants.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FIXTURES, golden, _stamp } from '../live-preflight/live-preflight-fixtures.mjs';
import { validatePackage, REQUIRED_CONTROL_IDS } from '../live-preflight/live-preflight-validator.mjs';
import { MUTATIONS } from '../live-preflight/run-live-preflight.mjs';
import { digest, AUTHORIZED_OWNER_SUBJECT_ID } from '../live-preflight/live-preflight-contract.mjs';

const byId = (id) => FIXTURES.find((f) => f.id === id);
const V = (id, mut) => validatePackage(byId(id).package, mut);
const holds = (id) => V(id).holds;
const stops = (id) => V(id).fail_stops;

test('169 synthetic PF-NN fixtures, unique ids', () => {
  assert.equal(FIXTURES.length, 169);
  assert.equal(new Set(FIXTURES.map((f) => f.id)).size, 169);
  for (const f of FIXTURES) assert.match(f.id, /^PF-\d{2,3}$/);
});

test('every fixture yields its expected admissibility', () => {
  for (const fx of FIXTURES) {
    const r = validatePackage(fx.package);
    assert.equal(r.package_admissible, fx.expect_admissible, `${fx.id} (${fx.cls}): ${[...r.fail_stops, ...r.holds].filter(Boolean)}`);
  }
});

test('INVARIANT: any HOLD/FAIL_STOP control makes a package inadmissible (HOLD can never be PASS)', () => {
  for (const fx of FIXTURES) {
    const r = validatePackage(fx.package);
    if (r.holds.length || r.fail_stops.length) assert.equal(r.package_admissible, false, `${fx.id}`);
    if (r.package_admissible) { assert.equal(r.holds.length, 0); assert.equal(r.fail_stops.length, 0); }
  }
});

test('fail-closed structural gates (missing section / version) run before substantive controls', () => {
  assert.ok(stops('PF-02').includes('SEC_MISSING_REQUIRED_SECTION'));
  assert.ok(stops('PF-38').includes('SEC_MISSING_REQUIRED_SECTION'));
  assert.ok(stops('PF-05').includes('CV_UNSUPPORTED_CONTRACT_VERSION'));
});

// ── S-7 cross-consistency with committed state-parity (reflected/resolved release needs typed J evidence) ──
test('S-7: section-F reflected/resolved release without J evidence HOLDs (state-parity SP-79 semantic)', () => {
  assert.ok(holds('PF-41').includes('S7_RELEASE_NO_EVIDENCE')); // reflected release, no J
  assert.ok(holds('PF-42').includes('S7_RELEASE_NO_EVIDENCE')); // resolved release, no J
  assert.equal(V('PF-43').package_admissible, true);            // reflected release WITH valid typed J -> admissible
  assert.ok(holds('PF-44').includes('S7_CLEARING_METADATA_MISSING')); // bare cleared_transaction_id
  assert.ok(holds('PF-45').includes('S7_CLEARING_AMOUNT_MISMATCH'));
  assert.ok(holds('PF-46').includes('S7_CLEARING_SOURCE_MISMATCH'));
  assert.ok(holds('PF-47').includes('S7_ORPHAN_EVIDENCE'));
});

// ── S-7 v3.1 durable-clearing lane (design s7-rev-8.3-bankcleared; G1-G10 + Mode-2 F-1..F-4) ──
test('S-7 v3.1 G1: a cleared commitment with no J is RELEASED and HOLDs (no capacity bypass)', () => {
  assert.ok(holds('PF-141').includes('S7_RELEASE_NO_EVIDENCE'));
  assert.equal(V('PF-141').package_admissible, false);
  assert.equal(validatePackage(byId('PF-141').package, { ignoreClearedRelease: true }).package_admissible, true);
});
test('S-7 v3.1 F-1: a bank_cleared release binds to a real Register txn (fabricated/absent/duplicate/digest all fail closed)', () => {
  assert.equal(V('PF-142').package_admissible, true);                          // valid, bound to a Register row
  assert.ok(holds('PF-153').includes('S7_CLEARING_TXN_NOT_FOUND'));            // referenced txn absent
  assert.ok(holds('PF-154').includes('S7_CLEARING_METADATA_MISSING'));         // supplied digest missing
  assert.ok(stops('PF-155').includes('P6_DUPLICATE_IDENTITY'));                // duplicate register txn identity
  assert.ok(stops('PF-155').includes('S7_CLEARING_TXN_AMBIGUOUS'));            // + S-7 defense-in-depth
  assert.ok(holds('PF-156').includes('S7_CLEARING_DIGEST_MISMATCH'));          // digest over an altered row
});
test('S-7 v3.1 F-1: amount/source/direction/state validated against the referenced ROW, not the J self-report', () => {
  assert.ok(holds('PF-157').includes('S7_CLEARING_AMOUNT_MISMATCH'));          // row amount != commitment (J self-report matched)
  assert.ok(holds('PF-158').includes('S7_CLEARING_SOURCE_MISMATCH'));          // row account != source
  assert.ok(holds('PF-143').includes('S7_CLEARING_DIRECTION_INVALID'));        // row is a credit (positive)
  assert.ok(holds('PF-144').includes('S7_CLEARING_STATE_INVALID'));            // row not cleared
});
test('S-7 v3.1 F-2: cleared_as_of must parse and lie within [window.start, window.end] (inclusive), else HOLD', () => {
  assert.ok(holds('PF-159').includes('S7_CLEARING_ASOF_UNPARSEABLE'));         // unparseable
  assert.ok(holds('PF-163').includes('S7_CLEARING_METADATA_MISSING'));         // missing (committed metadata check)
  assert.ok(holds('PF-160').includes('S7_CLEARING_ASOF_OUT_OF_WINDOW'));       // before lower bound
  assert.ok(holds('PF-145').includes('S7_CLEARING_ASOF_OUT_OF_WINDOW'));       // after upper bound
  assert.equal(V('PF-161').package_admissible, true);                          // exactly at window.start (inclusive)
  assert.equal(V('PF-162').package_admissible, true);                          // exactly at window.end (inclusive)
});
test('S-7 v3.1 G2: evidence_source is a closed set (explicit unknown FAIL-STOPs; absent = committed path preserved)', () => {
  assert.ok(stops('PF-146').includes('S7_UNSUPPORTED_EVIDENCE_SOURCE'));
  assert.equal(V('PF-27').package_admissible, true);
});
test('S-7 v3.1 H2: the NEW cleared+status=voided overlap FAIL-STOPs; committed contradiction (PF-31) stays inadmissible', () => {
  assert.ok(stops('PF-147').includes('S7_CONTRADICTORY_STATE'));
  assert.equal(V('PF-31').package_admissible, false);
});
test('S-7 v3.1 legacy lane: machine-bounded to the six pinned commitments; authority + registry gated (fail-closed pre-freeze)', () => {
  assert.ok(stops('PF-148').includes('S7_LEGACY_COMMITMENT_NOT_PINNED'));
  assert.ok(stops('PF-149').includes('S7_ADJUDICATION_AUTHORITY_UNAUTHORIZED'));
  assert.ok(stops('PF-150').includes('S7_ADJUDICATION_NOT_IN_REGISTRY'));
});
test('S-7 v3.1 G5/G8: one clearing txn bound to two commitments across lanes FAIL-STOPs (reuse conflict)', () => {
  assert.ok(stops('PF-151').includes('S7_CLEARING_TXN_REUSE_CONFLICT'));
});
test('S-7 v3.1 G9/H3: a superseded record invalid three ways is inert audit; the active au11 J admits', () => {
  assert.equal(V('PF-152').package_admissible, true);
});
// ── legacy registry lane (injected test registry; empty frozen registry fail-closes pre-freeze) ──
const OWNER = AUTHORIZED_OWNER_SUBJECT_ID, PIN = '2026mw4_rent_tiffany_dye_2026_07_01', AS = '2026-07-30T12:00:00.000Z';
function legacyPkg(overrides = [], cidId = PIN) {                    // build fresh packages (never mutate shared fixtures)
  const p = golden();
  Object.assign(p.cash_commitment_evidence[0], { expected_item_id: cidId, status: 'cleared', resolution_type: 'cleared' });
  const rds = [];
  overrides.forEach((ov, i) => {
    const txn = ov.txn || ('ltx' + i);
    const row = { txn_id: txn, account_key: 'truist_checking', amount_cents: -200000, cleared: true, is_transfer_leg: false, transfer_pair_id: null, represented_as_deduction: false, transaction_date: '2026-07-30', as_of_utc: AS };
    p.register_transaction_evidence.push(row);
    const base = { commitment_expected_item_id: cidId, evidence_source: 'legacy_adjudication', disposition: ov.disposition || 'matched_bank_clearing', adjudicated_by_subject_id: OWNER, resolution_type: 'cleared', resolution_evidence: 'legacy', resolution_evidence_type: 'bank_cleared', cleared_transaction_id: txn, cleared_amount_cents: 200000, cleared_source_account: 'truist_checking', cleared_state: 'cleared', cleared_as_of: AS, direction: 'debit', amount_cents: 200000, source_account: 'truist_checking', as_of_utc: AS, cleared_transaction_digest: digest(row), ...ov.j };
    if (base.record_digest === undefined) { const { record_digest, ...rest } = base; base.record_digest = digest(rest); }
    rds.push(base.record_digest);
    p.terminal_resolution_evidence.push(base);
  });
  _stamp(p);
  return { p, rds };
}
test('S-7 v3.1 registry: a frozen-accepted, register-bound legacy record is admissible', () => {
  const ok = legacyPkg([{}]);
  assert.equal(validatePackage(ok.p, { testAcceptedRegistry: ok.rds }).package_admissible, true);
});
test('S-7 v3.1 F-4: acceptForgedAdjudication is load-bearing — a tampered payload (stale digest) FAIL-STOPs; only forging it through admits', () => {
  const tampered = legacyPkg([{ j: { record_digest: 'a'.repeat(64) } }]);          // stored digest != recompute
  const base = { testAcceptedRegistry: ['a'.repeat(64)] };
  assert.ok(validatePackage(tampered.p, base).fail_stops.includes('S7_ADJUDICATION_DIGEST_MISMATCH'));   // correct: mismatch STOPs
  assert.equal(validatePackage(tampered.p, { ...base, acceptForgedAdjudication: true }).package_admissible, true); // mutant admits
});
test('S-7 v3.1 F10: more than one ACTIVE adjudication FAIL-STOPs; ignoreMultipleActive is load-bearing', () => {
  const two = legacyPkg([{ txn: 'ltxA' }, { txn: 'ltxB' }]);
  const base = { testAcceptedRegistry: two.rds };
  assert.ok(validatePackage(two.p, base).fail_stops.includes('S7_MULTIPLE_ACTIVE_ADJUDICATIONS'));
  assert.equal(validatePackage(two.p, { ...base, ignoreMultipleActive: true }).package_admissible, true);
});
test('S-7 v3.1 F10: a self-superseding record is a CYCLE; ignoreSupersessionStructure is load-bearing', () => {
  const cyc = legacyPkg([{ j: { record_digest: 'selfX', supersedes: 'selfX' } }]);
  assert.ok(validatePackage(cyc.p, { ignoreLegacyAuthority: true }).fail_stops.includes('S7_SUPERSESSION_CYCLE'));
  assert.equal(validatePackage(cyc.p, { ignoreLegacyAuthority: true, ignoreSupersessionStructure: true }).package_admissible, true);
});
test('S-7 v3.1 F-3: a fully-formed clearing record cannot make unresolved_hold or voided_or_never_cleared PASS', () => {
  const uh = legacyPkg([{ disposition: 'unresolved_hold' }]);
  const ur = validatePackage(uh.p, { testAcceptedRegistry: uh.rds });
  assert.ok(ur.holds.includes('S7_UNRESOLVED_LEGACY'));
  assert.equal(ur.package_admissible, false);
  const vc = legacyPkg([{ disposition: 'voided_or_never_cleared' }]);
  const vr = validatePackage(vc.p, { testAcceptedRegistry: vc.rds });
  assert.ok(vr.holds.includes('S7_RELEASE_NOT_CLEARED'));
  assert.equal(vr.package_admissible, false);
  // the disposition gate is load-bearing: skipping it lets the clearing evidence through
  assert.equal(validatePackage(uh.p, { testAcceptedRegistry: uh.rds, ignoreLegacyDisposition: true }).package_admissible, true);
});

// ── Mode-2 N-1..N-5 corrections ──
test('N-1: a transfer leg can never satisfy a durable bank_cleared release (S-7 STOP + XC J-lane STOP)', () => {
  assert.ok(stops('PF-164').includes('S7_CLEARING_TXN_IS_TRANSFER'));
  assert.ok(stops('PF-164').includes('XC_TRANSFER_ALSO_CLEARING'));
  assert.equal(V('PF-164').package_admissible, false);
  // both guards independently load-bearing (each isolated by disabling the OTHER in the base mut)
  assert.equal(validatePackage(byId('PF-164').package, { ignoreXcJLaneTransfer: true }).package_admissible, false); // S-7 still catches
  assert.equal(validatePackage(byId('PF-164').package, { ignoreS7TransferLeg: true }).package_admissible, false);   // XC still catches
  assert.equal(validatePackage(byId('PF-164').package, { ignoreS7TransferLeg: true, ignoreXcJLaneTransfer: true }).package_admissible, true); // both off -> improper PASS
  // a legacy bank_cleared J bound to a transfer leg is likewise blocked (registry-accepted)
  const lp = golden(); Object.assign(lp.cash_commitment_evidence[0], { expected_item_id: PIN, status: 'cleared', resolution_type: 'cleared' });
  const l1 = { txn_id: 'lleg1', account_key: 'truist_checking', amount_cents: -200000, cleared: true, is_transfer_leg: true, transfer_group_id: 'TPL', transfer_pair_id: 'TPL', represented_as_deduction: false, transaction_date: '2026-07-30', as_of_utc: AS };
  const l2 = { txn_id: 'lleg2', account_key: 'amex_savings', amount_cents: 200000, cleared: true, is_transfer_leg: true, transfer_group_id: 'TPL', transfer_pair_id: 'TPL', represented_as_deduction: false, transaction_date: '2026-07-30', as_of_utc: AS };
  lp.register_transaction_evidence.push(l1, l2);
  const lj = { commitment_expected_item_id: PIN, evidence_source: 'legacy_adjudication', disposition: 'matched_bank_clearing', adjudicated_by_subject_id: OWNER, resolution_type: 'cleared', resolution_evidence: 'x', resolution_evidence_type: 'bank_cleared', cleared_transaction_id: 'lleg1', cleared_amount_cents: 200000, cleared_source_account: 'truist_checking', cleared_state: 'cleared', cleared_as_of: AS, direction: 'debit', amount_cents: 200000, source_account: 'truist_checking', as_of_utc: AS, cleared_transaction_digest: digest(l1) };
  { const { record_digest, ...rest } = lj; lj.record_digest = digest(rest); }
  lp.terminal_resolution_evidence.push(lj); _stamp(lp);
  const lr = validatePackage(lp, { testAcceptedRegistry: [lj.record_digest] });
  assert.equal(lr.package_admissible, false);
  assert.ok(lr.fail_stops.includes('S7_CLEARING_TXN_IS_TRANSFER') || lr.fail_stops.includes('XC_TRANSFER_ALSO_CLEARING'));
});
// N-2: legacy paid_from_other_account durable binding (fabricated id / missing / dup / digest / source / valid)
function legacyAltPkg(o = {}) {
  const p = golden(); const payAcct = o.payAccount || 'amex_savings';
  Object.assign(p.cash_commitment_evidence[0], { expected_item_id: PIN, status: 'open', resolution_type: 'paid_from_other_account', reflected_model_week: 7 });
  const row = { txn_id: o.txn || 'pay_tx', account_key: payAcct, amount_cents: -200000, cleared: true, is_transfer_leg: false, transfer_pair_id: null, represented_as_deduction: false, transaction_date: '2026-07-30', as_of_utc: AS };
  if (!o.noRow) p.register_transaction_evidence.push(row);
  if (o.dupRow) p.register_transaction_evidence.push({ ...row });
  const j = { commitment_expected_item_id: PIN, evidence_source: 'legacy_adjudication', disposition: 'paid_from_other_account', adjudicated_by_subject_id: OWNER, resolution_type: 'paid_from_other_account', resolution_evidence: 'legacy-alt', resolution_evidence_type: 'alternate_payment', cleared_transaction_id: o.txn || 'pay_tx', cleared_amount_cents: 200000, cleared_source_account: payAcct, cleared_state: 'cleared', cleared_as_of: AS, direction: 'debit', amount_cents: 200000, source_account: 'truist_checking', as_of_utc: AS, cleared_transaction_digest: o.digest !== undefined ? o.digest : digest(row) };
  { const { record_digest, ...rest } = j; j.record_digest = digest(rest); }
  p.terminal_resolution_evidence.push(j); _stamp(p);
  return { p, reg: { testAcceptedRegistry: [j.record_digest] } };
}
test('N-2: a legacy paid_from_other_account cleared_transaction_id must resolve to a real Register row (no fabricated id)', () => {
  const valid = legacyAltPkg();
  assert.equal(validatePackage(valid.p, valid.reg).package_admissible, true);                       // valid alternate-payment -> PASS
  const fab = legacyAltPkg({ noRow: true });
  assert.ok(validatePackage(fab.p, fab.reg).holds.includes('S7_CLEARING_TXN_NOT_FOUND'));            // fabricated/missing id
  const dup = legacyAltPkg({ dupRow: true });
  assert.ok(validatePackage(dup.p, dup.reg).fail_stops.includes('S7_CLEARING_TXN_AMBIGUOUS'));       // duplicate row
  const dm = legacyAltPkg({ digest: 'f'.repeat(64) });
  assert.ok(validatePackage(dm.p, dm.reg).holds.includes('S7_CLEARING_DIGEST_MISMATCH'));            // digest mismatch
  const ws = legacyAltPkg({ payAccount: 'truist_checking' });                                        // "other" account == commitment source
  assert.ok(validatePackage(ws.p, ws.reg).holds.includes('S7_CLEARING_SOURCE_MISMATCH'));            // wrong source (not actually "other")
  // the existence guard is load-bearing for the legacy alt-payment lane
  assert.equal(validatePackage(fab.p, { ...fab.reg, ignoreClearingTxnExistence: true }).package_admissible, true);
});
test('N-3: cleared_as_of exact-binds to the referenced row transaction_date (mismatch/missing/malformed all HOLD)', () => {
  assert.equal(V('PF-142').package_admissible, true);                                 // exact date match
  assert.ok(holds('PF-165').includes('S7_CLEARING_ASOF_ROW_MISMATCH'));               // J date != row date
  assert.ok(holds('PF-166').includes('S7_CLEARING_ROW_DATE_MISSING'));                // row date missing
  assert.ok(holds('PF-167').includes('S7_CLEARING_ROW_DATE_MALFORMED'));              // row date malformed
});
test('N-4: a clearing txn that is also an active pending deduction FAIL-STOPs (contradictory representation)', () => {
  assert.ok(stops('PF-168').includes('S7_CLEARING_TXN_ALSO_DEDUCTED'));
  assert.equal(V('PF-168').package_admissible, false);
});
test('N-5: S7_RESOLUTION_TYPE_UNDETERMINED has dedicated coverage; the guard is load-bearing', () => {
  assert.ok(holds('PF-169').includes('S7_RESOLUTION_TYPE_UNDETERMINED'));
  assert.equal(validatePackage(byId('PF-169').package, { ignoreResolutionUndetermined: true }).package_admissible, true);
});

// ── S-1 referential integrity ──
test('S-1: authoritative off-model references must resolve to a real deduction', () => {
  assert.ok(holds('PF-48').includes('S1_DANGLING_REFERENCE'));
  assert.equal(V('PF-49').package_admissible, true);  // matching commitment
  assert.equal(V('PF-50').package_admissible, true);  // matching adjustment
  assert.ok(holds('PF-51').includes('S1_REFERENCE_AMOUNT_MISMATCH'));
  assert.ok(holds('PF-52').includes('S1_REFERENCE_SOURCE_MISMATCH'));
  assert.ok(holds('PF-53').includes('S1_SHARED_DEDUCTION'));
});

// ── S-5 threshold closed ──
test('S-5: unauthorized self-asserted materiality threshold HOLDs; unreconciled uncleared HOLDs', () => {
  assert.ok(holds('PF-54').includes('S5_UNAUTHORIZED_THRESHOLD'));
  assert.ok(holds('PF-55').includes('S5_UNCLEARED_UNRECONCILED'));
});

// ── minimum authoritative checking anchor ──
test('AN: a package with no authoritative checking anchor is inadmissible', () => {
  assert.ok(holds('PF-56').includes('ANCHOR_MISSING_AUTHORITATIVE_CHECKING'));
  assert.ok(holds('PF-57').some((h) => h === 'S2_UNUSABLE_BASIS' || h === 'P9_NON_AUTHORITATIVE_BALANCE' || h === 'ANCHOR_MISSING_AUTHORITATIVE_CHECKING')); // projected-only
  assert.equal(V('PF-58').package_admissible, true);
  assert.ok(holds('PF-59').includes('ANCHOR_AMBIGUOUS_COMPETING') || holds('PF-59').includes('P9_AMBIGUOUS_BALANCE'));
});

// ── S-6 full coverage ──
test('S-6: verified_empty strict + all evidence sections attested', () => {
  assert.ok(holds('PF-60').includes('S6_NO_ROWS_VISIBLE'));
  assert.ok(holds('PF-61').includes('S6_ZERO_NOT_VERIFIED'));
  assert.ok(holds('PF-62').includes('S6_UNATTESTED'));
  assert.ok(holds('PF-63').includes('S6_UNATTESTED'));
  assert.equal(V('PF-64').package_admissible, true);
});

// ── P-8 strict transfers ──
test('P-8: only exactly-two well-formed mirror legs pass; no near-net, no malformed group', () => {
  assert.ok(holds('PF-65').includes('P8_MALFORMED_LEG_COUNT'));
  assert.ok(holds('PF-66').includes('P8_UNEQUAL_AMOUNTS'));
  assert.ok(holds('PF-67').includes('P8_SAME_DIRECTION'));
  assert.equal(V('PF-68').package_admissible, true);
  assert.ok(holds('PF-69').includes('P8_MISSING_TRANSFER_IDENTITY'));
});

// ── P-7 economic identity ──
test('P-7: free-text identity HOLDs; authoritative event id passes; duplicate/one-to-many caught', () => {
  assert.ok(holds('PF-70').includes('P7_LINKAGE_AUTHORITATIVE_IDENTITY_REQUIRED'));
  assert.equal(V('PF-71').package_admissible, true);
  assert.ok(holds('PF-72').includes('P7_DUPLICATE_LINKAGE'));
  assert.ok(stops('PF-73').includes('P7_DUPLICATE_LINKED_ECONOMIC_EVENT')); // pending linked to a commitment (cross-path)
});

// ── query provenance + P-2 timestamps ──
test('PQ + P-2: provenance and canonical UTC timestamps enforced on all sections', () => {
  assert.ok(holds('PF-74').includes('PQ_MISSING_QUERY_LINK'));
  assert.ok(holds('PF-75').includes('PQ_ORPHAN_MANIFEST'));
  assert.ok(holds('PF-76').includes('PQ_ROWCOUNT_MISMATCH'));
  assert.ok(holds('PF-77').includes('P2_INVALID_OR_NON_UTC_TIMESTAMP'));
  assert.ok(holds('PF-78').includes('P2_INVALID_OR_NON_UTC_TIMESTAMP')); // +00:00 offset is not canonical Z
  assert.ok(holds('PF-79').includes('P2_INCOHERENT_AS_OF'));
  assert.ok(holds('PF-80').includes('P2_FRESHNESS_POLICY_NOT_AUTHORIZED'));
});

// ── cross-control consistency ──
test('XC: a transfer leg cannot also be counted as a pending deduction', () => {
  assert.ok(stops('PF-81').includes('XC_TRANSFER_ALSO_DEDUCTED'));
});

// ── NEW-A..E closures ──
test('NEW-A: duplicate manifest relation entries rejected', () => {
  assert.ok(stops('PF-82').includes('PQ_DUPLICATE_RELATION_ENTRY'));
  assert.ok(stops('PF-83').includes('PQ_CONFLICTING_RELATION_COUNT'));
  assert.ok(stops('PF-84').includes('PQ_CONFLICTING_RELATION_SCOPE'));
  assert.ok(stops('PF-85').includes('PQ_CONFLICTING_RELATION_DIGEST'));
  assert.ok(stops('PF-86').includes('PQ_DUPLICATE_QUERY_ID'));
});
test('NEW-B: self-asserted material:false does not exempt; only a real deduction does', () => {
  assert.ok(holds('PF-88').includes('S1_SELF_ASSERTED_IMMATERIALITY'));
  assert.ok(holds('PF-89').includes('S1_MATERIALITY_UNRESOLVED'));
  assert.equal(V('PF-90').package_admissible, true); // material:false but live deduction -> admissible via the deduction
  assert.ok(holds('PF-91').includes('S1_OFF_MODEL_DEDUCTION_MISSING'));
});
test('NEW-C: referenced deduction must be live/reserving (aligned with state-parity)', () => {
  assert.ok(holds('PF-92').includes('S1_REFERENCED_COMMITMENT_NOT_RESERVING')); // voided
  assert.ok(holds('PF-93').includes('S1_REFERENCED_DEDUCTION_NOT_LIVE'));       // affects_deployable_cash=false
  assert.ok(holds('PF-94').includes('S1_REFERENCED_DEDUCTION_ALREADY_REFLECTED'));
  assert.ok(holds('PF-95').includes('S1_REFERENCED_ADJUSTMENT_INACTIVE'));
  assert.equal(V('PF-96').package_admissible, true);
});
test('NEW-D: extended integrity detects post-stamp tamper of non-evidence sections', () => {
  assert.ok(stops('PF-97').includes('P4_SECTION_DIGEST_MISMATCH'));
  assert.ok(stops('PF-98').includes('P4_LINKAGE_DIGEST_MISMATCH'));
  assert.ok(stops('PF-99').includes('P4_ATTESTATION_DIGEST_MISMATCH'));
  assert.ok(stops('PF-100').includes('P4_MANIFEST_DIGEST_MISMATCH'));
  assert.ok(stops('PF-101').includes('P4_PACKAGE_DIGEST_MISMATCH'));
});
test('NEW-E: within-path duplicate economic identity rejected; distinct ids with same label pass', () => {
  assert.ok(stops('PF-102').includes('P7_LINKAGE_WITHIN_PATH_DOUBLE_COUNT'));
  assert.ok(stops('PF-103').includes('P7_LINKAGE_WITHIN_PATH_DOUBLE_COUNT'));
  assert.equal(V('PF-104').package_admissible, true);
});

// ── control-flow admissibility invariant (meta) ──
test('META: golden executes every required control exactly once; admissibility is derived only', () => {
  const g = validatePackage(byId('PF-01').package);
  assert.equal(g.all_required_controls_executed, true);
  assert.deepEqual(g.missing_control_ids, []);
  assert.deepEqual(g.duplicate_control_ids, []);
  assert.deepEqual(g.unknown_control_ids, []);
  assert.equal(g.admissibility_derived_only, true);
  assert.equal(new Set(g.executed_control_ids).size, REQUIRED_CONTROL_IDS.length);
});
test('META: a skipped required control cannot yield admissible (missing detected)', () => {
  const r = validatePackage(byId('PF-01').package, { skipControl: 'reserve_release_evidence_complete' });
  assert.equal(r.package_admissible, false);
  assert.ok(r.fail_stops.includes('META_REQUIRED_CONTROL_MISSING'));
});
test('META: injected duplicate / unknown control result is detected (fail-closed)', () => {
  const dup = validatePackage(byId('PF-01').package, { injectDuplicatePass: 'commitments_valid' });
  assert.equal(dup.package_admissible, false);
  assert.ok(dup.fail_stops.includes('META_DUPLICATE_CONTROL_RESULT'));
  const unk = validatePackage(byId('PF-01').package, { injectUnknownPass: true });
  assert.equal(unk.package_admissible, false);
  assert.ok(unk.fail_stops.includes('META_UNKNOWN_CONTROL_RESULT'));
});

// ── NEW-F linkage-derived authoritative identity ──
test('NEW-F: linkage-authoritative deductions dedup on the linked target, not the local row id', () => {
  assert.ok(stops('PF-105').includes('P7_LINKAGE_WITHIN_PATH_DOUBLE_COUNT')); // two pendings, same target
  assert.ok(stops('PF-106').includes('P7_LINKAGE_WITHIN_PATH_DOUBLE_COUNT')); // two adjustments, same target
  assert.ok(stops('PF-107').includes('P7_DUPLICATE_LINKED_ECONOMIC_EVENT')); // pending + adjustment, same target
  assert.ok(stops('PF-108').some((c) => c.startsWith('P7_')));                // direct + linked, same target
  assert.equal(V('PF-109').package_admissible, true);                         // distinct targets
  assert.ok(holds('PF-110').includes('P7_LINKAGE_TARGET_AMBIGUOUS'));
  assert.ok(holds('PF-111').includes('P7_DUPLICATE_LINKAGE'));
  assert.ok(holds('PF-114').includes('P7_LINKAGE_AUTHORITATIVE_IDENTITY_REQUIRED')); // no direct id, no linkage
  assert.equal(V('PF-115').package_admissible, true);                         // valid single linkage-authoritative deduction
});
test('NEW-F: renaming the local label cannot dodge the linked-target dedup', () => {
  assert.ok(stops('PF-113').some((c) => c.startsWith('P7_')));
});

// ── section-G source authority (no self-asserted exemption) ──
test('SEC-G: no self-asserted section-G exemption; only a live authoritative deduction covers', () => {
  assert.ok(holds('PF-116').includes('S1_UNSUPPORTED_CASH_IMPACT_CLASSIFICATION')); // affects:false builder
  assert.ok(holds('PF-117').includes('S1_OFF_MODEL_DEDUCTION_REQUIRED'));           // completed:true
  assert.ok(holds('PF-118').includes('S1_UNSUPPORTED_AUTHORITY_FIELD'));             // RG-6 dedicated unsupported-field code
  assert.ok(holds('PF-119').includes('S1_REFERENCED_COMMITMENT_NOT_RESERVING'));     // linked to non-live
  assert.equal(V('PF-120').package_admissible, true);                                // linked to valid active adjustment
});

// ── RG-1..RG-6 linkage-graph residual hardening ──
const p7 = (id, mut) => (V(id, mut).control_results.find((c) => c.id === 'P-7') || {}).reason_code;
test('RG-1: linkage namespace vocabulary is closed (unknown source/target fail closed)', () => {
  assert.equal(p7('PF-121'), 'P7_LINKAGE_TARGET_NOT_AUTHORITATIVE'); // `evt` is not `event`
  assert.equal(p7('PF-122'), 'P7_LINKAGE_SOURCE_NAMESPACE_UNKNOWN');
  assert.equal(V('PF-121').package_admissible, false);
  assert.equal(V('PF-122').package_admissible, false);
});
test('RG-2: a direct economic_event_id equal to a commitment expected_item_id is the same event', () => {
  assert.equal(p7('PF-123'), 'P7_DUPLICATE_LINKED_ECONOMIC_EVENT'); // event:X collides with commitment:X
  assert.equal(V('PF-123').package_admissible, false);
  // the equivalence is load-bearing: without it the two ids do not collide
  assert.notEqual(validatePackage(byId('PF-123').package, { ignoreEventCommitmentEquivalence: true }).control_results.find((c) => c.id === 'P-7').disposition, 'FAIL_STOP');
});
test('RG-3: no linkage-graph indirection — chains/2-cycles fail closed; the graph guard is load-bearing', () => {
  assert.equal(p7('PF-124'), 'P7_LINKAGE_TARGET_NOT_AUTHORITATIVE');       // caught by vocab at the fixture level
  assert.equal(p7('PF-124', { ignoreNamespaceVocab: true }), 'P7_LINKAGE_GRAPH_INDIRECTION'); // guard behind vocab
  assert.equal(V('PF-124', { ignoreNamespaceVocab: true }).package_admissible, false);
});
test('RG-4: a linkage target that is another deduction local row id fails closed', () => {
  assert.equal(p7('PF-125'), 'P7_LINKAGE_TARGET_NOT_AUTHORITATIVE');
  assert.equal(V('PF-125').package_admissible, false);
});
test('RG-5: declared_aggregations is removed — a self-asserted aggregation cannot excuse a double count', () => {
  assert.ok(byId('PF-126').package.declared_aggregations, 'fixture carries a declared_aggregations exemption');
  assert.equal(p7('PF-126'), 'P7_LINKAGE_WITHIN_PATH_DOUBLE_COUNT'); // exemption ignored, still fails closed
  assert.equal(V('PF-126').package_admissible, false);
});

// ── OBS-5 identity validation + source/target existence + orphan linkages ──
test('OBS-5: empty / whitespace linkage identities fail closed (validated before namespace construction)', () => {
  assert.equal(p7('PF-128'), 'P7_LINKAGE_SOURCE_ID_MISSING');
  assert.equal(p7('PF-129'), 'P7_LINKAGE_SOURCE_ID_MISSING'); // whitespace-only treated as missing
  assert.equal(p7('PF-130'), 'P7_LINKAGE_TARGET_ID_MISSING');
  assert.equal(p7('PF-131'), 'P7_LINKAGE_TARGET_ID_MISSING');
  // attribution: bypassing the id check does not admit — a deeper guard (existence) still rejects
  assert.notEqual(p7('PF-128', { acceptEmptySourceId: true }), 'P7_LINKAGE_SOURCE_ID_MISSING');
  assert.notEqual(p7('PF-130', { acceptEmptyTargetId: true }), 'P7_LINKAGE_TARGET_ID_MISSING');
  assert.equal(V('PF-128', { acceptEmptySourceId: true }).package_admissible, false);
});
test('OBS-5: a linkage source must resolve to exactly one deduction record', () => {
  assert.equal(p7('PF-132'), 'P7_LINKAGE_SOURCE_NOT_FOUND');
  assert.notEqual(p7('PF-132', { ignoreSourceExistence: true }), 'P7_LINKAGE_SOURCE_NOT_FOUND'); // guard is load-bearing
});
test('OBS-5: a linkage target must resolve to an ESTABLISHED authoritative identity (never the linkage string)', () => {
  assert.equal(p7('PF-133'), 'P7_LINKAGE_COMMITMENT_NOT_FOUND');      // nonexistent commitment
  assert.equal(p7('PF-134'), 'P7_LINKAGE_EVENT_NOT_ESTABLISHED');     // event referenced only by the linkage
  assert.equal(p7('PF-139'), 'P7_LINKAGE_EVENT_NOT_ESTABLISHED');     // target only in an unknown top-level section
  assert.equal(V('PF-135').package_admissible, true);                 // event established by a direct-id record → valid
  assert.equal(V('PF-140').package_admissible, true);                 // valid source + valid authoritative target → admissible
  assert.equal(p7('PF-136'), 'P7_DUPLICATE_LINKED_ECONOMIC_EVENT');   // commitment resolves to one → deducting source double-counts
});
test('OBS-5: commitment target ambiguity fails closed (P-6 identity uniqueness + P-7 defense-in-depth)', () => {
  assert.ok(stops('PF-137').includes('P6_DUPLICATE_IDENTITY'));
  assert.equal(p7('PF-137'), 'P7_LINKAGE_TARGET_AMBIGUOUS');
  assert.equal(V('PF-137').package_admissible, false);
});
test('OBS-5: an orphan (unconsumed) linkage is never silently ignored', () => {
  assert.equal(p7('PF-138'), 'P7_ORPHAN_LINKAGE');
  assert.equal(V('PF-138', { allowOrphanLinkage: true }).package_admissible, true); // guard is load-bearing
});
test('OBS-5 / PF-115 correction: the prior "valid single linkage" now requires an established target', () => {
  // PF-115 previously admitted a linkage whose event target was referenced ONLY by the linkage itself.
  const pkg = byId('PF-115').package;
  assert.ok((pkg.pending_or_uncleared_evidence || []).some((r) => r.economic_event_id === 'T1' && r.represented_as_deduction === false),
    'PF-115 now carries a non-deducting establisher record for its target');
  assert.equal(V('PF-115').package_admissible, true);
});
test('RG-3 INDEPENDENT: the graph-indirection guard is load-bearing with namespace validation ACTIVE', () => {
  // PF-127 uses a namespace-VALID shared-token indirection (id token appears as both a source and a target).
  assert.equal(p7('PF-127'), 'P7_LINKAGE_GRAPH_INDIRECTION');                      // fires though every namespace is valid
  assert.notEqual(p7('PF-127', { allowGraphIndirection: true }), 'P7_LINKAGE_GRAPH_INDIRECTION'); // isolated: only this guard toggled
  assert.equal(V('PF-127').package_admissible, false);
});

// ── 47 executable mutations ──
for (const [id, fixtureId, mut, baseMut] of MUTATIONS) {
  test(`MUTATION ${id}: disabling the control lets ${fixtureId} through (deterministic)`, () => {
    const base = baseMut || {};
    const correct = V(fixtureId, base).package_admissible;
    const m1 = validatePackage(byId(fixtureId).package, { ...base, ...mut }).package_admissible;
    const m2 = validatePackage(byId(fixtureId).package, { ...base, ...mut }).package_admissible;
    assert.equal(correct, false, `${fixtureId} must be blocked by the correct control`);
    assert.equal(m1, true, `${id} mutant must let the defect through`);
    assert.notEqual(m1, correct);
    assert.equal(m1, m2, 'deterministic');
  });
}

test('repeatability: validation is deterministic', () => {
  const sig = () => FIXTURES.map((f) => f.id + ':' + validatePackage(f.package).package_admissible).join('|');
  assert.equal(sig(), sig());
});
