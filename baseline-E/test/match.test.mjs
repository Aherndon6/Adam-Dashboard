// rev-6.1 routing (§4/§11/rev-5.1 F) + IS-1 + H-3 vocabulary + N-1 + M11/M23. Exact reason codes asserted.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classify } from '../src/match.mjs';
import { isIdentityStrong } from '../src/identity.mjs';

const hx = (n) => n.toString(16).padStart(64, '0');
// anchor with a valid H-3 type; category is DERIVED from type. sameCvdAs forces collapse (T-c).
function anchor(type, seed, { sameCvdAs = null, deriv = 'direct_read', authoritative_role = false, category } = {}) {
  return {
    type, category, authoritative_role,
    canonical_value_digest: hx(sameCvdAs != null ? 1000 + sameCvdAs : 1000 + seed),
    anchor_evidence_digest: hx(2000 + seed), evidence_root_digest: hx(3000 + seed),
    evidence_root: { source_system: 'sys' + seed, source_record_digest: hx(4000 + seed), source_field: 'f' + seed, derivation_method: deriv },
  };
}
const bank = { amount_cents: 5000, direction: 'credit', bank_transaction_id: 't1' };
const strongAnchors = () => [anchor('bank_reference', 1), anchor('source_system_identity', 2)];   // 2 A, 2 groups ⇒ strong
const weakAnchors = () => [anchor('source_account_identity', 3), anchor('counterparty_identity', 4)]; // 2 B, no A ⇒ not strong
const cand = (event_id, anchors, amount = 5000, direction = 'credit') => ({ event_id, event: { amount_cents: amount, direction }, anchors });

test('IS-1: two independent A anchors ⇒ strong; two B ⇒ not strong; T-c collapse ⇒ not strong', () => {
  assert.equal(isIdentityStrong(strongAnchors()).strong, true);
  assert.equal(isIdentityStrong(weakAnchors()).strong, false);
  assert.equal(isIdentityStrong([anchor('bank_reference', 1), anchor('content_bound_external_reference', 2, { sameCvdAs: 1 })]).strong, false);
});

test('Disposition A: one strong+consistent (+weak recorded)', () => {
  const r = classify({ bankTxn: bank, candidates: [cand('e1', strongAnchors()), cand('e2', weakAnchors())] });
  assert.equal(r.disposition, 'A'); assert.equal(r.code, 'A_SINGLE_STRONG'); assert.equal(r.candidate_set.confirmed_candidate_id, 'e1');
});
test('§17-76 strong + amount conflict ⇒ D/FAIL-STOP', () => {
  const r = classify({ bankTxn: bank, candidates: [cand('e1', strongAnchors(), 4999)] });
  assert.equal(r.disposition, 'D-FAIL-STOP'); assert.equal(r.code, 'D_STRONG_CONFLICT');
});
test('§17-76 constraint: non-IS-1 conflict is 72-family (C/HOLD)', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', weakAnchors(), 4999)] }).disposition, 'C-HOLD');
});
test('§17-69 >1 strong without graph ⇒ C/HOLD', () => {
  const r = classify({ bankTxn: bank, candidates: [cand('e1', strongAnchors()), cand('e2', [anchor('bank_reference', 5), anchor('source_system_identity', 6)])] });
  assert.equal(r.disposition, 'C-HOLD'); assert.equal(r.code, 'C_MULTI_STRONG');
});
test('§17-72 plausible-but-not-strong ⇒ C/HOLD', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', weakAnchors())] }).code, 'C_NO_STRONG');
});

// ── H-3 anchor vocabulary ────────────────────────────────────────────────────────────────────────────
test('H-3: amount mislabeled as anchor ⇒ FAIL-STOP', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', [anchor('amount', 1), anchor('bank_reference', 2)])] }).code, 'H3_ANCHOR_VOCABULARY');
});
test('H-3: direction mislabeled as anchor ⇒ FAIL-STOP', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', [anchor('direction', 1), anchor('bank_reference', 2)])] }).code, 'H3_ANCHOR_VOCABULARY');
});
test('H-3: unknown anchor type ⇒ FAIL-STOP', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', [anchor('mystery', 1), anchor('bank_reference', 2)])] }).code, 'H3_ANCHOR_VOCABULARY');
});
test('H-3: incompatible type/category (bank_reference declared B) ⇒ FAIL-STOP', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', [anchor('bank_reference', 1, { category: 'B' }), anchor('source_system_identity', 2)])] }).code, 'H3_ANCHOR_VOCABULARY');
});
test('H-3: Category-C declared as A ⇒ FAIL-STOP; C alone ⇒ not strong (C/HOLD)', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', [anchor('description_token', 1, { category: 'A' }), anchor('bank_reference', 2)])] }).code, 'H3_ANCHOR_VOCABULARY');
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', [anchor('description_token', 1), anchor('date_proximity', 2)])] }).disposition, 'C-HOLD');
});
test('H-3: two anchors, one independence group ⇒ not strong; no Category-A ⇒ not strong', () => {
  assert.equal(isIdentityStrong([anchor('bank_reference', 1), anchor('source_system_identity', 2, { sameCvdAs: 1 })]).strong, false);
  assert.equal(isIdentityStrong(weakAnchors()).strong, false);
});

// ── N-1 ──────────────────────────────────────────────────────────────────────────────────────────────
test('N-1: authoritative anchor without provenance ⇒ FAIL-STOP', () => {
  const bad = anchor('bank_reference', 9, { deriv: 'copied_from:notahex', authoritative_role: true });
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', [bad, anchor('source_system_identity', 10)])] }).code, 'N1_AUTHORITATIVE_NO_PROVENANCE');
});

// ── F routing precedence (global FAIL-STOP dominates A/C/E) + M11/M23 ────────────────────────────────
const cc = (o) => ({ endpoint_ok: true, candgen_valid: true, candidates_exhaustive: true, coverage_sufficient: true, ...o });
test('F/M11: one strong + invalid endpoint ⇒ FAIL-STOP (not A)', () => {
  const r = classify({ bankTxn: bank, candidates: [cand('e1', strongAnchors())], coverageContext: cc({ endpoint_ok: false }) });
  assert.equal(r.disposition, 'FAIL-STOP'); assert.equal(r.code, 'ENDPOINT_INVALID');
});
test('F/M11: multiple strong + invalid endpoint ⇒ FAIL-STOP', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', strongAnchors()), cand('e2', [anchor('bank_reference', 5), anchor('source_system_identity', 6)])], coverageContext: cc({ endpoint_ok: false }) }).code, 'ENDPOINT_INVALID');
});
test('F/M11: zero candidates + invalid endpoint ⇒ FAIL-STOP (not E/HOLD)', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [], coverageContext: cc({ endpoint_ok: false }) }).code, 'ENDPOINT_INVALID');
});
test('F: one strong + invalid candgen manifest ⇒ FAIL-STOP (not A)', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', strongAnchors())], coverageContext: cc({ candgen_valid: false }) }).code, 'CANDGEN_INVALID');
});
test('§17-77: exhaustive no-match + sufficient coverage ⇒ E', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [], coverageContext: cc({}) }).disposition, 'E');
});
test('F: valid endpoint + insufficient coverage ⇒ COVERAGE-HOLD (not E, not FAIL-STOP)', () => {
  const r = classify({ bankTxn: bank, candidates: [], coverageContext: cc({ coverage_sufficient: false }) });
  assert.equal(r.disposition, 'COVERAGE-HOLD'); assert.equal(r.code, 'COVERAGE_INSUFFICIENT');
});
test('M23: candidates_exhaustive false on E path ⇒ C/HOLD (E prohibited)', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [], coverageContext: cc({ candidates_exhaustive: false }) }).code, 'C_NOT_EXHAUSTIVE');
});
test('FAIL-STOP precedence: one strong-consistent + one strong-conflicted ⇒ D/FAIL-STOP', () => {
  assert.equal(classify({ bankTxn: bank, candidates: [cand('e1', strongAnchors()), cand('e2', [anchor('bank_reference', 7), anchor('source_system_identity', 8)], 1)] }).disposition, 'D-FAIL-STOP');
});
