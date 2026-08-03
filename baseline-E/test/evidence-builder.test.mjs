// baseline-E/test/evidence-builder.test.mjs
// Durable coverage for the authoritative transfer-attribution builder mapping (live-preflight-evidence-builder.mjs):
// production transactions.transfer_pair_id -> register_transaction_evidence {is_transfer_leg, transfer_group_id},
// and its downstream recognition by P-8 / S-7 (matched_internal_transfer) / XC. No inference; shared-group-id only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deriveTransferAttribution, applyTransferAttribution, dollarsToCents, buildRegisterTransactionEvidence, transferAttributionProvenance } from '../live-preflight/live-preflight-evidence-builder.mjs';
import { golden, _stamp } from '../live-preflight/live-preflight-fixtures.mjs';
import { validatePackage } from '../live-preflight/live-preflight-validator.mjs';
import { digest } from '../live-preflight/live-preflight-contract.mjs';

const OWNER = '9f6c9e09-209d-4533-8cd9-9143e8d570fc';
const ROW_ASOF = '2026-07-30T12:00:00.000Z';
const WIN = { start: '2026-06-01T00:00:00.000Z', end: '2026-07-31T23:59:59.999Z' };
// a raw production-shaped transaction row (cents already; the builder's dollar->cents step is out of scope here)
const raw = (id, acct, cents, date, pairId = null) => ({ id, account_key: acct, amount_cents: cents, cleared: true, transaction_date: date, transfer_pair_id: pairId });
// map a raw txn -> register_transaction_evidence row via the authoritative mapping
const mapRow = (rt) => applyTransferAttribution({ txn_id: rt.id, account_key: rt.account_key, amount_cents: rt.amount_cents, cleared: rt.cleared, represented_as_deduction: false, transaction_date: rt.transaction_date, as_of_utc: ROW_ASOF }, rt.transfer_pair_id);

// Build a package: pinned transfer commitment cleared + mapped register rows + a matched_internal_transfer J bound to
// the debit leg, validated with the empty registry bypassed (recordGid overridable to probe group binding).
function pkgFromRaw(commitmentId, amountCents, rawTxns, recordGid, opts = {}) {
  const p = golden();
  p.execution_identity.extraction_window = { ...WIN };
  Object.assign(p.cash_commitment_evidence[0], { expected_item_id: commitmentId, source_account: 'truist_checking', amount_cents: amountCents, status: 'cleared', resolution_type: 'cleared' });
  const rows = rawTxns.map(mapRow);
  for (const r of rows) p.register_transaction_evidence.push(r);
  const debit = rows.find((r) => r.amount_cents < 0) || rows[0];
  const j = { commitment_expected_item_id: commitmentId, evidence_source: 'legacy_adjudication', disposition: opts.disposition || 'matched_internal_transfer', adjudicated_by_subject_id: OWNER, resolution_type: 'cleared', resolution_evidence: 'legacy', resolution_evidence_type: 'bank_cleared', cleared_transaction_id: debit.txn_id, cleared_transaction_digest: digest(debit), cleared_amount_cents: amountCents, cleared_source_account: 'truist_checking', cleared_state: 'cleared', cleared_as_of: debit.transaction_date + 'T12:00:00.000Z', direction: 'debit', amount_cents: amountCents, source_account: 'truist_checking', as_of_utc: ROW_ASOF, cleared_transfer_group_id: recordGid };
  const { record_digest, ...rest } = j; j.record_digest = digest(rest);
  p.terminal_resolution_evidence.push(j); _stamp(p);
  return validatePackage(p, { testAcceptedRegistry: [j.record_digest] });
}

// ── unit: the pure derivation ──
test('builder: is_transfer_leg = (transfer_pair_id is not null); transfer_group_id = transfer_pair_id (verbatim)', () => {
  assert.deepEqual(deriveTransferAttribution(null), { is_transfer_leg: false, transfer_group_id: null });
  assert.deepEqual(deriveTransferAttribution(undefined), { is_transfer_leg: false, transfer_group_id: null });
  const gid = '598b8e61-731d-472b-8966-ac6695a2fa74';
  assert.deepEqual(deriveTransferAttribution(gid), { is_transfer_leg: true, transfer_group_id: gid });
  // no normalization/reinterpretation — the identifier is returned exactly as given
  assert.equal(deriveTransferAttribution(' spaced ').transfer_group_id, ' spaced ');
});

// ── A: null transfer_pair_id (ordinary bank-clearing row unchanged) ──
test('builder A: null transfer_pair_id -> is_transfer_leg=false, transfer_group_id omitted, committed shape preserved', () => {
  const r = mapRow(raw('t1', 'truist_checking', -200000, '2026-07-01', null));
  assert.equal(r.is_transfer_leg, false);
  assert.equal('transfer_group_id' in r, false);   // omitted, not null-with-key
  assert.equal(r.transfer_pair_id, null);
  // byte-identical (by digest) to the committed non-transfer clearing-row shape
  const committed = { txn_id: 't1', account_key: 'truist_checking', amount_cents: -200000, cleared: true, is_transfer_leg: false, transfer_pair_id: null, represented_as_deduction: false, transaction_date: '2026-07-01', as_of_utc: ROW_ASOF };
  assert.equal(digest(r), digest(committed));
});

// ── B: valid shared-group pair recognized by P-8 and consumed by matched_internal_transfer ──
test('builder B: shared-group pair -> both is_transfer_leg=true, same group id; P-8 sees 2 legs; S-7 consumes debit', () => {
  const gid = '598b8e61-731d-472b-8966-ac6695a2fa74';
  const d = mapRow(raw(gid, 'truist_checking', -43563, '2026-07-07', gid));            // debit (self-referencing pair id)
  const c = mapRow(raw('f7f7ec17-5c5c-4edc-961d-08ed4976c075', 'vio_tax_reserve', 43563, '2026-07-07', gid)); // credit
  assert.equal(d.is_transfer_leg, true); assert.equal(c.is_transfer_leg, true);
  assert.equal(d.transfer_group_id, gid); assert.equal(c.transfer_group_id, gid);       // SAME group id
  const r = pkgFromRaw('2026mw4_tax_transfer_vio_2026_06_28', 43563,
    [raw(gid, 'truist_checking', -43563, '2026-07-07', gid), raw('f7f7ec17-5c5c-4edc-961d-08ed4976c075', 'vio_tax_reserve', 43563, '2026-07-07', gid)], gid);
  assert.equal(r.package_admissible, true, 'valid shared-group internal transfer is admissible (registry bypassed)');
  assert.equal((r.control_results.find((x) => x.id === 'P-8') || {}).disposition, 'PASS');
});

// ── C: debit self-reference accepted as a group identifier (no cycle/pointer semantics) ──
test('builder C: debit row id == transfer_pair_id is valid (opaque group id; no pointer chasing)', () => {
  const gid = 'bc8b3a62-a3ef-4871-805a-553ef7cdd82a';
  const r = pkgFromRaw('manual_18313b87-a03b-4034-a1a8-a73fa0bfadd9', 566601,
    [raw(gid, 'truist_checking', -566601, '2026-07-20', gid), raw('3af39fcd-644f-4acc-a472-43431476a5f6', 'amex_gold', 566601, '2026-07-18', gid)], gid);
  assert.equal(r.package_admissible, true);
});

// ── D: mutual-pointer shape must NOT be silently treated as one group ──
test('builder D: mutual-pointer (debit->credit, credit->debit) fails closed (two 1-leg groups, not one)', () => {
  const dId = 'bc8b3a62-a3ef-4871-805a-553ef7cdd82a', cId = '3af39fcd-644f-4acc-a472-43431476a5f6';
  const d = mapRow(raw(dId, 'truist_checking', -566601, '2026-07-20', cId));   // debit points to credit
  const c = mapRow(raw(cId, 'amex_gold', 566601, '2026-07-18', dId));          // credit points to debit
  assert.notEqual(d.transfer_group_id, c.transfer_group_id);                    // DIFFERENT group ids -> not one group
  const r = pkgFromRaw('manual_18313b87-a03b-4034-a1a8-a73fa0bfadd9', 566601,
    [raw(dId, 'truist_checking', -566601, '2026-07-20', cId), raw(cId, 'amex_gold', 566601, '2026-07-18', dId)], dId);
  assert.equal(r.package_admissible, false);
  assert.ok(r.holds.includes('P8_MALFORMED_LEG_COUNT') || r.fail_stops.includes('S7_TRANSFER_GROUP_MALFORMED') || r.fail_stops.includes('S7_TRANSFER_GROUP_MISMATCH'));
});

// ── E: malformed groups fail closed ──
test('builder E: malformed groups (1-leg / 3-leg / same-sign / unequal / same-account / dup-id) fail closed', () => {
  const gid = '598b8e61-731d-472b-8966-ac6695a2fa74', cid = '2026mw4_tax_transfer_vio_2026_06_28';
  const oneLeg = pkgFromRaw(cid, 43563, [raw(gid, 'truist_checking', -43563, '2026-07-07', gid)], gid);
  assert.equal(oneLeg.package_admissible, false);
  const threeLeg = pkgFromRaw(cid, 43563, [raw(gid, 'truist_checking', -43563, '2026-07-07', gid), raw('c1', 'vio_tax_reserve', 43563, '2026-07-07', gid), raw('c2', 'sav', 43563, '2026-07-07', gid)], gid);
  assert.equal(threeLeg.package_admissible, false);
  const sameSign = pkgFromRaw(cid, 43563, [raw(gid, 'truist_checking', -43563, '2026-07-07', gid), raw('c1', 'vio_tax_reserve', -43563, '2026-07-07', gid)], gid);
  assert.equal(sameSign.package_admissible, false);
  const unequal = pkgFromRaw(cid, 43563, [raw(gid, 'truist_checking', -43563, '2026-07-07', gid), raw('c1', 'vio_tax_reserve', 43564, '2026-07-07', gid)], gid);
  assert.equal(unequal.package_admissible, false);
  const sameAcct = pkgFromRaw(cid, 43563, [raw(gid, 'truist_checking', -43563, '2026-07-07', gid), raw('c1', 'truist_checking', 43563, '2026-07-07', gid)], gid);
  assert.equal(sameAcct.package_admissible, false);
  // noncanonical group id (whitespace) fails the S-7 canonical-id gate
  const bad = 'bad id';
  const nonCanon = pkgFromRaw(cid, 43563, [raw(bad, 'truist_checking', -43563, '2026-07-07', bad), raw('c1', 'vio_tax_reserve', 43563, '2026-07-07', bad)], bad);
  assert.equal(nonCanon.package_admissible, false);
  assert.ok(nonCanon.fail_stops.includes('S7_TRANSFER_GROUP_ID_INVALID') || nonCanon.fail_stops.includes('XC_TRANSFER_ALSO_CLEARING'));
});

// ── F: digest sensitivity ──
test('builder F: adding transfer attribution changes the row digest; mapping is deterministic; group id is digest-relevant', () => {
  const base = { txn_id: 'x', account_key: 'truist_checking', amount_cents: -43563, cleared: true, represented_as_deduction: false, transaction_date: '2026-07-07', as_of_utc: ROW_ASOF };
  const gidA = '598b8e61-731d-472b-8966-ac6695a2fa74', gidB = 'bc8b3a62-a3ef-4871-805a-553ef7cdd82a';
  const pre = applyTransferAttribution(base, null);     // is_transfer_leg=false, no group id
  const postA = applyTransferAttribution(base, gidA);   // is_transfer_leg=true, group A
  const postB = applyTransferAttribution(base, gidB);   // is_transfer_leg=true, group B
  assert.notEqual(digest(pre), digest(postA), 'pre- vs post-mapping digests differ');
  assert.notEqual(digest(postA), digest(postB), 'altering the group identity changes the digest');
  assert.equal(digest(applyTransferAttribution(base, gidA)), digest(postA), 'repeat mapping is deterministic');
  // input is not mutated
  assert.equal('is_transfer_leg' in base, false);
});

// ── END-TO-END: production-shaped raw transaction rows -> committed adapter -> package -> P-8/S-7/XC ──
// Extraction-shaped input (amount in DOLLARS, as 13-transactions.json stores it): two null-pair rows + the tax pair
// (sharing the debit UUID) + the AMEX pair (sharing the debit UUID). The adapter is the single authoritative producer.
const TAXD = '598b8e61-731d-472b-8966-ac6695a2fa74', TAXC = 'f7f7ec17-5c5c-4edc-961d-08ed4976c075';
const AMXD = 'bc8b3a62-a3ef-4871-805a-553ef7cdd82a', AMXC = '3af39fcd-644f-4acc-a472-43431476a5f6';
const RAW = () => ([
  { id: 'r-rent01', account_key: 'truist_checking', amount: -2000.00, cleared: true, transaction_date: '2026-07-01', transfer_pair_id: null },
  { id: 'r-kia',    account_key: 'truist_checking', amount: -790.50,  cleared: true, transaction_date: '2026-07-07', transfer_pair_id: null },
  { id: TAXD, account_key: 'truist_checking', amount: -435.63,  cleared: true, transaction_date: '2026-07-07', transfer_pair_id: TAXD },  // tax debit (self-ref)
  { id: TAXC, account_key: 'vio_tax_reserve', amount:  435.63,  cleared: true, transaction_date: '2026-07-07', transfer_pair_id: TAXD },  // tax credit
  { id: AMXD, account_key: 'truist_checking', amount: -5666.01, cleared: true, transaction_date: '2026-07-20', transfer_pair_id: AMXD },  // amex debit (self-ref)
  { id: AMXC, account_key: 'amex_gold',       amount:  5666.01, cleared: true, transaction_date: '2026-07-18', transfer_pair_id: AMXD },  // amex credit
]);

test('E2E: adapter emits correct attribution from raw rows; null-pair=false, pairs share one group, self-ref preserved', () => {
  const { rows, gaps } = buildRegisterTransactionEvidence(RAW(), { as_of_utc: ROW_ASOF });
  assert.equal(gaps.length, 0, 'all amounts convert to integer cents');
  const byId = Object.fromEntries(rows.map((r) => [r.txn_id, r]));
  // null-pair rows: is_transfer_leg=false, no transfer_group_id key, dollars->cents applied
  for (const id of ['r-rent01', 'r-kia']) { assert.equal(byId[id].is_transfer_leg, false); assert.equal('transfer_group_id' in byId[id], false); }
  assert.equal(byId['r-rent01'].amount_cents, -200000);
  assert.equal(byId['r-kia'].amount_cents, -79050);
  // tax + amex legs: is_transfer_leg=true, transfer_group_id EXACTLY = transfer_pair_id, both legs share one group
  for (const [d, c, g, amt] of [[TAXD, TAXC, TAXD, 43563], [AMXD, AMXC, AMXD, 566601]]) {
    assert.equal(byId[d].is_transfer_leg, true); assert.equal(byId[c].is_transfer_leg, true);
    assert.equal(byId[d].transfer_group_id, g); assert.equal(byId[c].transfer_group_id, g);   // same group
    assert.equal(byId[d].transfer_group_id, byId[d].transfer_pair_id);                          // group id == pair id (no reinterpretation)
    assert.equal(byId[d].amount_cents, -amt); assert.equal(byId[c].amount_cents, amt);
  }
  // debit self-reference preserved (group id equals the debit's own txn_id); no mutual-pointer
  assert.equal(byId[TAXD].transfer_group_id, TAXD);
  assert.equal(byId[AMXD].transfer_group_id, AMXD);
});

test('E2E: adapter output flows through P-8 / S-7 / XC as a valid internal transfer (registry bypassed)', () => {
  // build a full package whose register section is the ADAPTER output; add a matched_internal_transfer J on the tax pair.
  const { rows } = buildRegisterTransactionEvidence(RAW(), { as_of_utc: ROW_ASOF });
  const p = golden(); p.execution_identity.extraction_window = { ...WIN };
  Object.assign(p.cash_commitment_evidence[0], { expected_item_id: '2026mw4_tax_transfer_vio_2026_06_28', source_account: 'truist_checking', amount_cents: 43563, status: 'cleared', resolution_type: 'cleared' });
  for (const r of rows) p.register_transaction_evidence.push(r);
  const debit = rows.find((r) => r.txn_id === TAXD);
  const j = { commitment_expected_item_id: '2026mw4_tax_transfer_vio_2026_06_28', evidence_source: 'legacy_adjudication', disposition: 'matched_internal_transfer', adjudicated_by_subject_id: OWNER, resolution_type: 'cleared', resolution_evidence: 'legacy', resolution_evidence_type: 'bank_cleared', cleared_transaction_id: TAXD, cleared_transaction_digest: digest(debit), cleared_amount_cents: 43563, cleared_source_account: 'truist_checking', cleared_state: 'cleared', cleared_as_of: '2026-07-07T12:00:00.000Z', direction: 'debit', amount_cents: 43563, source_account: 'truist_checking', as_of_utc: ROW_ASOF, cleared_transfer_group_id: TAXD };
  const { record_digest, ...rest } = j; j.record_digest = digest(rest);
  p.terminal_resolution_evidence.push(j); _stamp(p);
  const r = validatePackage(p, { testAcceptedRegistry: [j.record_digest] });
  assert.equal(r.package_admissible, true);
  assert.equal((r.control_results.find((x) => x.id === 'P-8') || {}).disposition, 'PASS');
  assert.equal((r.control_results.find((x) => x.id === 'S-7') || {}).disposition, 'PASS');
  assert.equal((r.control_results.find((x) => x.id === 'XC') || {}).disposition, 'PASS');
});

test('E2E provenance: counts reconcile and reconciliation fails closed on any disagreement', () => {
  const raw = RAW();
  const { rows } = buildRegisterTransactionEvidence(raw, { as_of_utc: ROW_ASOF });
  const prov = transferAttributionProvenance(raw, rows, { repo_commit: '2f4d7ce', source_extraction_digest: 'ddbd03aa…', builder_path: 'external/build-live-evidence-package.mjs', builder_digest: 'c1d13ef3…' });
  assert.equal(prov.transfer_attribution_applied, true);
  assert.equal(prov.raw_rows_with_transfer_pair_id, 4);
  assert.equal(prov.emitted_is_transfer_leg_true, 4);
  assert.equal(prov.transfer_groups.length, 2);
  assert.deepEqual(prov.transfer_groups.map((g) => g.group_id).sort(), [AMXD, TAXD].sort());
  assert.equal(prov.reconciliation_ok, true);
  assert.equal(prov.errors.length, 0);
  // fail-closed: a raw pair row whose emitted leg is stripped of is_transfer_leg -> reconciliation error
  const tampered = rows.map((r) => r.txn_id === TAXD ? { ...r, is_transfer_leg: false } : r);
  const bad = transferAttributionProvenance(raw, tampered, {});
  assert.equal(bad.reconciliation_ok, false);
  assert.ok(bad.errors.some((e) => e.startsWith('RAW_PAIR_WITHOUT_EMITTED_LEG')));
  // fail-closed: an unrecognized mapping version
  assert.equal(transferAttributionProvenance(raw, rows, { mapping_spec_version: 'legacy-clearing-v9' }).reconciliation_ok, false);
  // fail-closed: emitted group id != raw pair id
  const regrouped = rows.map((r) => r.txn_id === AMXD ? { ...r, transfer_group_id: 'WRONG' } : r);
  assert.ok(transferAttributionProvenance(raw, regrouped, {}).errors.some((e) => e.startsWith('EMITTED_GROUP_ID_NEQ_PAIR_ID')));
});

test('E2E digest: attribution changes the mapped-row digest through the actual adapter; deterministic; pre-backfill cannot satisfy post-backfill', () => {
  // pre-backfill raw (all transfer_pair_id null) vs post-backfill raw (tax/amex pairs set)
  const pre = buildRegisterTransactionEvidence(RAW().map((t) => ({ ...t, transfer_pair_id: null })), { as_of_utc: ROW_ASOF }).rows;
  const post = buildRegisterTransactionEvidence(RAW(), { as_of_utc: ROW_ASOF }).rows;
  const preD = pre.find((r) => r.txn_id === TAXD), postD = post.find((r) => r.txn_id === TAXD);
  assert.notEqual(digest(preD), digest(postD), 'adding transfer attribution changes the mapped debit-leg digest');
  // determinism: two builds of the same raw are byte-identical
  assert.equal(digest(post.find((r) => r.txn_id === TAXD)), digest(buildRegisterTransactionEvidence(RAW(), { as_of_utc: ROW_ASOF }).rows.find((r) => r.txn_id === TAXD)));
  // changing transfer_pair_id changes the digest
  const alt = buildRegisterTransactionEvidence(RAW().map((t) => t.id === TAXD ? { ...t, transfer_pair_id: AMXD } : t), { as_of_utc: ROW_ASOF }).rows.find((r) => r.txn_id === TAXD);
  assert.notEqual(digest(postD), digest(alt));
  // a PRE-backfill clearing digest cannot satisfy a record bound to the POST-backfill row (recomputeClearingDigest differs)
  assert.notEqual(digest(preD), digest(postD));
});
