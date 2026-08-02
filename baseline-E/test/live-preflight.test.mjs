// baseline-E/test/live-preflight.test.mjs
// Hardened fail-closed live-input preflight: 199 synthetic fixtures + 81 executable mutations + invariants.
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

test('199 synthetic PF-NN fixtures, unique ids', () => {
  assert.equal(FIXTURES.length, 199);
  assert.equal(new Set(FIXTURES.map((f) => f.id)).size, 199);
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

// ── Obs-B: pinned-legacy commitments cannot bypass the registry via an untagged committed-class record ──
test('Obs-B: an active record on a pinned legacy commitment MUST be legacy_adjudication (absent/null/blank/au11/other STOP)', () => {
  for (const id of ['PF-170', 'PF-171', 'PF-172', 'PF-173', 'PF-174']) {
    assert.ok(stops(id).includes('S7_PINNED_LEGACY_SOURCE_REQUIRED'), `${id} must STOP with the pinned-legacy code`);
    assert.equal(V(id).package_admissible, false);
  }
  // the guard is load-bearing: with it disabled the absent-source valid clearing improperly PASSES through committed behavior
  assert.equal(validatePackage(byId('PF-170').package, { ignorePinnedLegacySource: true }).package_admissible, true);
});
test('Obs-B: G2 preserved — a NON-pinned commitment with an absent-source valid clearing retains committed behavior (PASS)', () => {
  assert.equal(V('PF-175').package_admissible, true);
  // and the committed non-pinned S-7 fixtures are untouched
  assert.equal(V('PF-31').package_admissible, false);
  for (const id of ['PF-41', 'PF-42', 'PF-43', 'PF-44', 'PF-45', 'PF-46', 'PF-47']) assert.ok(V(id) !== undefined);
  assert.equal(V('PF-43').package_admissible, true);
});
test('Obs-B: a pinned commitment can only PASS via legacy_adjudication + accepted registry + owner + digest (registry unavoidable)', () => {
  const ok = legacyPkg([{}]);
  assert.equal(validatePackage(ok.p).package_admissible, false);                                   // empty frozen registry -> fail-closed
  assert.ok(validatePackage(ok.p).fail_stops.includes('S7_ADJUDICATION_NOT_IN_REGISTRY'));
  assert.equal(validatePackage(ok.p, { testAcceptedRegistry: ok.rds }).package_admissible, true);   // accepted -> PASS
});
test('Obs-B: an invalid UNTAGGED superseded record does not block a valid active legacy record (inert per supersession rules)', () => {
  const p = golden();
  Object.assign(p.cash_commitment_evidence[0], { expected_item_id: PIN, status: 'cleared', resolution_type: 'cleared' });
  const row = { txn_id: 'ltxA', account_key: 'truist_checking', amount_cents: -200000, cleared: true, is_transfer_leg: false, transfer_pair_id: null, represented_as_deduction: false, transaction_date: '2026-07-30', as_of_utc: AS };
  p.register_transaction_evidence.push(row);
  const active = { commitment_expected_item_id: PIN, evidence_source: 'legacy_adjudication', disposition: 'matched_bank_clearing', adjudicated_by_subject_id: OWNER, resolution_type: 'cleared', resolution_evidence: 'x', resolution_evidence_type: 'bank_cleared', cleared_transaction_id: 'ltxA', cleared_amount_cents: 200000, cleared_source_account: 'truist_checking', cleared_state: 'cleared', cleared_as_of: AS, direction: 'debit', amount_cents: 200000, source_account: 'truist_checking', as_of_utc: AS, cleared_transaction_digest: digest(row) };
  { const { record_digest, ...rest } = active; active.record_digest = digest(rest); }
  const superseded = { commitment_expected_item_id: PIN, superseded: true, resolution_evidence: 'stale', resolution_evidence_type: 'bank_cleared', amount_cents: 200000, source_account: 'truist_checking', as_of_utc: AS }; // untagged, inert
  p.terminal_resolution_evidence.push(active, superseded); _stamp(p);
  assert.equal(validatePackage(p, { testAcceptedRegistry: [active.record_digest] }).package_admissible, true);
});

// ── legacy-clearing-v2: commitment-specific lower bound, Kia pinned variance, matched_internal_transfer ──
// build a legacy bank_cleared package with controllable dates (window stays golden 2026-07-30; row.as_of_utc in-window,
// but cleared_as_of/row.transaction_date can be an earlier July date to exercise the lane-specific lower bound).
function lcPkg(o = {}) {
  const cid = o.commitment || '2026mw4_rent_tiffany_dye_2026_07_01';   // pinned, floor 2026-07-01
  const amount = o.amount != null ? o.amount : 200000;
  const p = golden();
  Object.assign(p.cash_commitment_evidence[0], { expected_item_id: cid, status: 'cleared', resolution_type: 'cleared', amount_cents: amount });
  const clearedAsOf = o.cleared_as_of || AS;
  const txn = o.txn || 'lc_tx';
  const row = { txn_id: txn, account_key: 'truist_checking', amount_cents: o.rowAmount != null ? o.rowAmount : -amount, cleared: true, is_transfer_leg: false, transfer_pair_id: null, represented_as_deduction: false, transaction_date: o.rowDate || clearedAsOf.slice(0, 10), as_of_utc: AS };
  if (!o.noRow) p.register_transaction_evidence.push(row);
  const j = { commitment_expected_item_id: cid, disposition: 'matched_bank_clearing', adjudicated_by_subject_id: OWNER, resolution_type: 'cleared', resolution_evidence: 'legacy', resolution_evidence_type: 'bank_cleared', cleared_transaction_id: txn, cleared_transaction_digest: o.noRow ? 'x'.repeat(64) : digest(row), cleared_amount_cents: o.clearedAmount != null ? o.clearedAmount : amount, cleared_source_account: 'truist_checking', cleared_state: 'cleared', cleared_as_of: clearedAsOf, direction: 'debit', amount_cents: amount, source_account: 'truist_checking', as_of_utc: AS };
  if (o.committed) { /* absent evidence_source (committed lane) */ } else j.evidence_source = 'legacy_adjudication';
  if (j.evidence_source === 'legacy_adjudication') { const { record_digest, ...rest } = j; j.record_digest = digest(rest); }
  p.terminal_resolution_evidence.push(j); _stamp(p);
  return { p, reg: j.record_digest ? { testAcceptedRegistry: [j.record_digest] } : {} };
}
test('v2 F-LGW: commitment-specific legacy lower bound (permits historical July clearing; excludes pre-obligation)', () => {
  const ok = lcPkg({ cleared_as_of: '2026-07-15T12:00:00.000Z' });                 // legacy, floor 07-01, as-of 07-15
  assert.equal(validatePackage(ok.p, ok.reg).package_admissible, true);            // F-LGW-1 permitted (map floor, not window.start)
  const kiaLow = lcPkg({ commitment: '2026mw5_kia_payment_2026_07_07', amount: 79100, clearedAmount: 79050, rowAmount: -79050, cleared_as_of: '2026-07-06T12:00:00.000Z' });
  const r2 = validatePackage(kiaLow.p, kiaLow.reg);                                // F-LGW-2 Kia as-of 07-06 < its 07-07 floor
  assert.ok(r2.holds.includes('S7_CLEARING_ASOF_OUT_OF_WINDOW'));
  assert.equal(r2.package_admissible, false);
  // useGlobalLegacyFloor is load-bearing AND proves the map is STRICTER than a single global 06-28 floor
  assert.equal(validatePackage(kiaLow.p, { ...kiaLow.reg, useGlobalLegacyFloor: true }).package_admissible, true);
  const after = lcPkg({ cleared_as_of: '2026-07-31T12:00:00.000Z' });             // F-LGW-3 after window.end 2026-07-30
  assert.ok(validatePackage(after.p, after.reg).holds.includes('S7_CLEARING_ASOF_OUT_OF_WINDOW'));
  const committed = lcPkg({ committed: true, commitment: '2026mw6_rent_2026_07_01', cleared_as_of: '2026-07-15T12:00:00.000Z' });
  assert.ok(validatePackage(committed.p).holds.includes('S7_CLEARING_ASOF_OUT_OF_WINDOW')); // F-LGW-5 committed lane still uses window.start (Jul-15 < Jul-30)
  assert.equal(validatePackage(committed.p, { applyLegacyFloorToCommittedLane: true }).package_admissible, true); // mutation flips (proves committed lane unweakened)
  // F-LGW-6: N-3 exact date binding intact — cleared_as_of date != row date HOLDs
  const mism = lcPkg({ cleared_as_of: '2026-07-16T12:00:00.000Z', rowDate: '2026-07-15' }); // as-of date 07-16 != row date 07-15
  assert.ok(validatePackage(mism.p, mism.reg).holds.includes('S7_CLEARING_ASOF_ROW_MISMATCH'));
});
test('v2 F-VAR: Kia -50 pinned variance (exact; no band; strict elsewhere) — shared S-4/S-7 helper', () => {
  const kia = lcPkg({ commitment: '2026mw5_kia_payment_2026_07_07', amount: 79100, clearedAmount: 79050, rowAmount: -79050, cleared_as_of: '2026-07-07T12:00:00.000Z' });
  assert.equal(validatePackage(kia.p, kia.reg).package_admissible, true);          // F-VAR-1 Kia expected 79100 / cleared 79050 -> PASS
  const rent = lcPkg({ amount: 200000, clearedAmount: 79050, rowAmount: -79050, cleared_as_of: '2026-07-15T12:00:00.000Z' });
  assert.ok(validatePackage(rent.p, rent.reg).holds.includes('S7_CLEARING_AMOUNT_MISMATCH')); // F-VAR-2 non-pinned commitment, variance not accepted
  assert.equal(validatePackage(rent.p, { ...rent.reg, acceptAnyVariance: true }).package_admissible, true); // acceptAnyVariance flips (load-bearing)
  const kia49 = lcPkg({ commitment: '2026mw5_kia_payment_2026_07_07', amount: 79100, clearedAmount: 79051, rowAmount: -79051, cleared_as_of: '2026-07-07T12:00:00.000Z' });
  assert.ok(validatePackage(kia49.p, kia49.reg).holds.includes('S7_CLEARING_AMOUNT_MISMATCH')); // F-VAR-3 delta -49 (not exactly -50) HOLDs
  assert.equal(validatePackage(kia49.p, { ...kia49.reg, applyToleranceBand: true }).package_admissible, true); // tolerance-band flips (proves no band exists)
  const kiaRow = lcPkg({ commitment: '2026mw5_kia_payment_2026_07_07', amount: 79100, clearedAmount: 79050, rowAmount: -70000, cleared_as_of: '2026-07-07T12:00:00.000Z' });
  assert.ok(validatePackage(kiaRow.p, kiaRow.reg).holds.includes('S7_CLEARING_AMOUNT_MISMATCH')); // F-VAR-4 |row| != expected cleared
});
// matched_internal_transfer package: a 2-leg group (debit on source account, credit on destination)
function tfPkg(o = {}) {
  const cid = o.commitment || '2026mw4_tax_transfer_vio_2026_06_28'; const amount = o.amount != null ? o.amount : 43563; const gid = o.gid || 'GRP1';
  const p = golden();
  Object.assign(p.cash_commitment_evidence[0], { expected_item_id: cid, status: 'cleared', resolution_type: 'cleared', amount_cents: amount });
  const debit = { txn_id: 'tleg_d', account_key: 'truist_checking', amount_cents: -amount, cleared: true, is_transfer_leg: o.debitNotLeg ? false : true, transfer_group_id: gid, transfer_pair_id: gid, represented_as_deduction: !!o.debitDeducted, transaction_date: '2026-07-07', as_of_utc: AS };
  const credit = { txn_id: 'tleg_c', account_key: 'vio_tax_reserve', amount_cents: o.creditAmt != null ? o.creditAmt : amount, cleared: true, is_transfer_leg: true, transfer_group_id: gid, transfer_pair_id: gid, represented_as_deduction: !!o.creditDeducted, transaction_date: '2026-07-07', as_of_utc: AS };
  if (o.debitNotLeg) { debit.transfer_group_id = null; debit.transfer_pair_id = null; }
  p.register_transaction_evidence.push(debit); if (!o.noCredit && !o.debitNotLeg) p.register_transaction_evidence.push(credit);
  if (o.reuse) p.terminal_resolution_evidence.push({ commitment_expected_item_id: '2026mw6_bkx_2026_07_01', evidence_source: 'au11', resolution_type: 'cleared', resolution_evidence: 'x', resolution_evidence_type: 'bank_cleared', cleared_transaction_id: 'tleg_c', cleared_amount_cents: 70090, cleared_source_account: 'truist_checking', cleared_state: 'cleared', cleared_as_of: AS, direction: 'debit', amount_cents: 70090, source_account: 'truist_checking', as_of_utc: AS });
  const j = { commitment_expected_item_id: cid, evidence_source: 'legacy_adjudication', disposition: o.disposition || 'matched_internal_transfer', adjudicated_by_subject_id: OWNER, resolution_type: 'cleared', resolution_evidence: 'legacy', resolution_evidence_type: 'bank_cleared', cleared_transaction_id: 'tleg_d', cleared_transaction_digest: digest(debit), cleared_amount_cents: amount, cleared_source_account: 'truist_checking', cleared_state: 'cleared', cleared_as_of: '2026-07-07T12:00:00.000Z', direction: 'debit', amount_cents: amount, source_account: 'truist_checking', as_of_utc: AS, cleared_transfer_group_id: o.recordGid !== undefined ? o.recordGid : gid };
  const { record_digest, ...rest } = j; j.record_digest = digest(rest);
  p.terminal_resolution_evidence.push(j); _stamp(p);
  return { p, reg: { testAcceptedRegistry: [j.record_digest] } };
}
test('v2 F-TRF: matched_internal_transfer eligibility (pinned set, authoritative pair, both-leg reuse, no inference)', () => {
  const ok = tfPkg();
  assert.equal(validatePackage(ok.p, ok.reg).package_admissible, true);                              // F-TRF-1 valid internal transfer
  const bank = tfPkg({ disposition: 'matched_bank_clearing' });
  const rB = validatePackage(bank.p, bank.reg);
  assert.ok(rB.fail_stops.includes('S7_CLEARING_TXN_IS_TRANSFER') || rB.fail_stops.includes('XC_TRANSFER_ALSO_CLEARING')); // F-TRF-2 bank_clearing on a leg blocked
  assert.equal(validatePackage(bank.p, { ...bank.reg, ignoreS7TransferLeg: true, ignoreXcJLaneTransfer: true }).package_admissible, true); // both transfer guards load-bearing
  const notLeg = tfPkg({ debitNotLeg: true });
  assert.ok(validatePackage(notLeg.p, notLeg.reg).fail_stops.includes('S7_INTERNAL_TRANSFER_LEG_REQUIRED'));   // F-TRF-3 unmarked row
  assert.equal(validatePackage(notLeg.p, { ...notLeg.reg, ignoreInternalTransferLegRequired: true, ignoreTransferGroup: true }).package_admissible, true);
  const notPinned = tfPkg({ commitment: '2026mw4_rent_tiffany_dye_2026_07_01', amount: 200000 }); // pinned-six rent, NOT a pinned transfer commitment
  assert.ok(validatePackage(notPinned.p, notPinned.reg).fail_stops.includes('S7_TRANSFER_DISPOSITION_NOT_PINNED')); // F-TRF-4 transfer disposition outside the pinned transfer set
  // F-1 defense-in-depth: the pinned-transfer check is now enforced in S-7 AND XC, so both gates must be disabled to admit.
  assert.equal(validatePackage(notPinned.p, { ...notPinned.reg, ignoreTransferDispositionGate: true, ignoreXcJLaneTransfer: true }).package_admissible, true);
  const reuse = tfPkg({ reuse: true });
  assert.ok(validatePackage(reuse.p, reuse.reg).fail_stops.includes('S7_CLEARING_TXN_REUSE_CONFLICT'));         // F-TRF-5 mirror leg reused elsewhere
  // ignoreMirrorLegReuse is isolated by neutralizing XC's redundant transfer-leg guard in the base:
  assert.equal(validatePackage(reuse.p, { ...reuse.reg, ignoreXcJLaneTransfer: true }).package_admissible, false);                        // S-7 reuse map catches it
  assert.equal(validatePackage(reuse.p, { ...reuse.reg, ignoreXcJLaneTransfer: true, ignoreMirrorLegReuse: true }).package_admissible, true); // load-bearing
  const dedu = tfPkg({ creditDeducted: true });
  assert.ok(validatePackage(dedu.p, dedu.reg).fail_stops.includes('S7_CLEARING_TXN_ALSO_DEDUCTED'));            // F-TRF-6 mirror leg also a deduction
  const gmis = tfPkg({ recordGid: 'WRONG' });
  assert.ok(validatePackage(gmis.p, gmis.reg).fail_stops.includes('S7_TRANSFER_GROUP_MISMATCH'));               // F-TRF-7 record group id != row group id
  // no inference: bank_clearing on a leg with a mirror present only passes under the explicit inference mutation
  assert.equal(validatePackage(bank.p, { ...bank.reg, inferTransferFromMirrorPresence: true, ignoreXcJLaneTransfer: true }).package_admissible, true);
});

// F-1 (v2 hardening): the XC J-lane internal-transfer exemption is active-only + pinned-only + group-valid + leg-bound.
// Build a package where TAX is validly cleared by an ACTIVE internal transfer and add a SECOND internal-transfer record
// (bound to the mirror leg tleg_c) whose eligibility we vary. Only an active/pinned/group-valid/leg-bound record may
// suppress the XC transfer STOP.
function tfPlusSecond(second) {
  const base = tfPkg();                                  // active valid internal transfer on TAX (legs tleg_d/tleg_c, GRP1)
  base.p.terminal_resolution_evidence.push(Object.assign({
    commitment_expected_item_id: '2026mw4_tax_transfer_vio_2026_06_28', evidence_source: 'legacy_adjudication',
    disposition: 'matched_internal_transfer', adjudicated_by_subject_id: OWNER, resolution_type: 'cleared',
    resolution_evidence: 'x', resolution_evidence_type: 'bank_cleared', cleared_transaction_id: 'tleg_c',
    cleared_transfer_group_id: 'GRP1', record_digest: 'deadbeef', amount_cents: 43563, source_account: 'truist_checking', as_of_utc: AS,
  }, second));
  _stamp(base.p);
  return base;   // base.reg accepts the ACTIVE record's digest; the second record rides the acceptAll bypass below
}
test('v2 F-1: XC transfer exemption is active-only, pinned-only, group-valid', () => {
  const REG = { acceptAllLegacyRegistry: true };
  // active valid pinned internal-transfer record → exemption granted (no XC stop; admissible under registry bypass).
  assert.equal(validatePackage(tfPkg().p, REG).package_admissible, true);
  // superseded record bound to a leg → NO exemption → XC STOPs; looseXcExemption (old predicate) reverts.
  const sup = tfPlusSecond({ superseded: true });
  assert.ok(validatePackage(sup.p, REG).fail_stops.includes('XC_TRANSFER_ALSO_CLEARING'));
  assert.equal(validatePackage(sup.p, { ...REG, looseXcExemption: true }).package_admissible, true);
  // ACTIVE record on a NON-pinned commitment bound to a leg → NO exemption (pinned clause) → XC STOPs.
  const np = tfPlusSecond({ commitment_expected_item_id: '2026mw6_rent_2026_07_01' });
  assert.ok(validatePackage(np.p, REG).fail_stops.includes('XC_TRANSFER_ALSO_CLEARING'));
  // superseded + wrong group identity → NO exemption → XC STOPs.
  const wg = tfPlusSecond({ superseded: true, cleared_transfer_group_id: 'NOPE' });
  assert.ok(validatePackage(wg.p, REG).fail_stops.includes('XC_TRANSFER_ALSO_CLEARING'));
  // superseded + missing group identity → NO exemption → XC STOPs.
  const mg = tfPlusSecond({ superseded: true, cleared_transfer_group_id: undefined });
  assert.ok(validatePackage(mg.p, REG).fail_stops.includes('XC_TRANSFER_ALSO_CLEARING'));
});
test('v2 F-2: transfer group id must be a non-empty canonical token (fails closed otherwise)', () => {
  const REG = { acceptAllLegacyRegistry: true };
  // legacyTransfer-equivalent invalid-id probe: vary the RECORD's cleared_transfer_group_id (rows keep GRP1), XC off to
  //   isolate the S-7 identity gate from XC's (redundant) rejection of the same non-canonical id.
  const inv = (recordGid) => validatePackage(tfPkg({ recordGid }).p, { ...REG, ignoreXcJLaneTransfer: true });
  assert.ok(inv(null).fail_stops.includes('S7_TRANSFER_GROUP_ID_INVALID'));        // null
  assert.ok(inv('').fail_stops.includes('S7_TRANSFER_GROUP_ID_INVALID'));          // empty
  assert.ok(inv('   ').fail_stops.includes('S7_TRANSFER_GROUP_ID_INVALID'));       // whitespace-only
  assert.ok(inv('a b/c').fail_stops.includes('S7_TRANSFER_GROUP_ID_INVALID'));     // malformed (space + slash)
  // valid canonical UUID passes the identity gate (whole package admissible under registry bypass).
  assert.equal(validatePackage(tfPkg({ gid: 'bc8b3a62-1111-4111-8111-111111111111', recordGid: 'bc8b3a62-1111-4111-8111-111111111111' }).p, REG).package_admissible, true);
  // record group id present+canonical but != row group id → mismatch (not invalid).
  assert.ok(validatePackage(tfPkg({ recordGid: 'GRP2' }).p, REG).fail_stops.includes('S7_TRANSFER_GROUP_MISMATCH'));
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

// ── 81 executable mutations ──
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
