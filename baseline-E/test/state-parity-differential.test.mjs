// baseline-E/test/state-parity-differential.test.mjs
// runModel / application-state-resolution parity suite (revised D-1..D-4 + S-6/S-7) + embedded reservation
// cross-product + 14 EXECUTABLE mutation probes (each runs through runStateDifferential).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FIXTURES } from '../state-parity/state-fixtures.mjs';
import { runStateDifferential, CLASS } from '../state-parity/state-differential.mjs';
import { adaptState, beIsReserved } from '../state-parity/state-adapter.mjs';
import { resolversFor, APP_CONSTS } from '../state-parity/app-state-oracle.mjs';

const R = runStateDifferential(FIXTURES);
const PLAN_YEAR = APP_CONSTS.PLAN_YEAR;
const byId = (id) => FIXTURES.find((f) => f.id === id);
const A = (id) => adaptState(byId(id));
const clsOf = (res, id) => res.rows.find((r) => r.id === id).classification;

// ── corpus + classification integrity ──────────────────────────────────────────────────────────────────
test('107 synthetic SP-NN fixtures, unique ids', () => {
  assert.equal(FIXTURES.length, 107);
  assert.equal(new Set(FIXTURES.map((f) => f.id)).size, 107);
  for (const f of FIXTURES) assert.match(f.id, /^SP-\d{2,3}$/);
});
test('every fixture classifies to an allowed disposition; NO defects', () => {
  const allowed = new Set(Object.values(CLASS));
  for (const r of R.rows) assert.ok(allowed.has(r.classification), `${r.id}: ${r.classification}`);
  assert.deepEqual(R.beDefects.map((r) => r.id), []);
});
test('reservation + prefilter parity: independent BE == verbatim app on ALL fixtures', () => {
  assert.equal(R.reservationParityAll, true);
  for (const r of R.rows) {
    if (!r.layers) continue;
    assert.equal(r.layers.reserved_protected_cents.match, true, `${r.id} reserved`);
    assert.equal(r.layers.reserved_commitments.match, true, `${r.id} list`);
    assert.equal(r.layers.prefilter_eligibility.match, true, `${r.id} prefilter`);
  }
});

// ── D-2 reservation-clause coverage ─────────────────────────────────────────────────────────────────────
test('D-2 clause fixtures resolve correctly (app oracle)', () => {
  assert.equal(A('SP-51').app.reservedProtectedCents, 0);     // model_year mismatch
  assert.equal(A('SP-52').app.reservedProtectedCents, 0);     // resolution voided
  assert.equal(A('SP-53').app.reservedProtectedCents, 0);     // paid_from_other_account
  assert.equal(A('SP-54').app.reservedProtectedCents, 50000); // resolved > week
  assert.equal(A('SP-55').app.reservedProtectedCents, 0);     // resolved <= week
  assert.equal(A('SP-56').app.reservedProtectedCents, 50000); // reflected > week
  assert.equal(A('SP-57').app.reservedProtectedCents, 0);     // reflected == week
  assert.equal(A('SP-58').app.reservedProtectedCents, 0);     // reflected < week
});
test('D-2 embedded reservation cross-product: beIsReserved == verbatim isReservedAsOf, 0 mismatches', () => {
  const isReservedAsOf = resolversFor({}).isReservedAsOf;
  const YEARS = [2025, 2026, 2027], ORIGINS = [7, 8, 9], AFFECTS = [true, false];
  const STATUS = ['open', 'executed', 'cleared', 'voided', 'bank_pending', 'stale'];
  const RESTYPE = [null, 'voided', 'paid_from_other_account', 'cleared'];
  const REFLECTED = [null, 7, 8, 9], RESOLVED = [null, 7, 8, 9];
  const week = 8; let cases = 0, mismatches = 0;
  for (const model_year of YEARS) for (const origin_model_week of ORIGINS) for (const affects_deployable_cash of AFFECTS)
    for (const status of STATUS) for (const resolution_type of RESTYPE) for (const reflected_model_week of REFLECTED)
      for (const resolved_model_week of RESOLVED) {
        const c = { model_year, origin_model_week, affects_deployable_cash, status, resolution_type, reflected_model_week, resolved_model_week, amount_cents: 50000, source_account: 'truist_checking' };
        cases++;
        if (beIsReserved(c, week, PLAN_YEAR) !== isReservedAsOf(c, week)) mismatches++;
      }
  assert.equal(cases, 6912);
  assert.equal(mismatches, 0);
});
test('cross-product is repeatable (deterministic)', () => {
  const run = () => { const f = resolversFor({}).isReservedAsOf; let m = 0; for (const y of [2025, 2026, 2027]) for (const o of [7, 8, 9]) { const c = { model_year: y, origin_model_week: o, affects_deployable_cash: true, status: 'open', resolution_type: null, reflected_model_week: null, resolved_model_week: null, amount_cents: 1, source_account: 'truist_checking' }; if (beIsReserved(c, 8, PLAN_YEAR) !== f(c, 8)) m++; } return m; };
  assert.equal(run(), run());
});

// ── D-3 unreconciled-branch prefilter (index.html:3159-3172) ────────────────────────────────────────────
test('D-3 unreconciled prefilter admits/excludes per the verbatim branch logic', () => {
  assert.equal(A('SP-59').isRec, false);
  assert.equal(A('SP-59').app.reservedProtectedCents, 50000); // origin reconciled -> admitted
  assert.equal(A('SP-60').app.reservedProtectedCents, 0);     // origin unreconciled, no historical_repair -> excluded
  assert.equal(A('SP-61').app.reservedProtectedCents, 50000); // historical_repair -> admitted
  assert.equal(A('SP-62').app.reservedProtectedCents, 0);     // strict origin (origin==week) -> excluded
  assert.equal(A('SP-63').app.reservedProtectedCents, 0);     // model_year mismatch -> excluded
  assert.equal(A('SP-64').app.reservedProtectedCents, 30000); // mixed -> only the admitted one
  assert.equal(A('SP-65').app.reservedProtectedCents, 35000); // two reconciled origins
  assert.equal(A('SP-66').app.reservedProtectedCents, 0);     // admitted-by-prefilter but voided
  assert.equal(A('SP-67').app.reservedProtectedCents, 0);     // historical_repair but not affects
  assert.equal(A('SP-68').app.reservedProtectedCents, 0);     // no commitments
  for (const id of ['SP-59', 'SP-60', 'SP-61', 'SP-62', 'SP-63', 'SP-64', 'SP-65', 'SP-66', 'SP-67', 'SP-68'])
    assert.equal(R.rows.find((r) => r.id === id).classification, CLASS.EXACT, `${id} app==be over unreconciled branch`);
});

// ── D-4 chk:null vs chk-missing (distinct) ──────────────────────────────────────────────────────────────
test('D-4 chk:null (->0) and chk-missing (->NaN) are distinct; both BE HOLD, never authoritative', () => {
  const n = A('SP-03'), m = A('SP-69');
  assert.equal(n.app.chk_state, 'null');
  assert.equal(n.app.adjustedDeployableSurplusCents, 0);      // app: round(null*100)=0
  assert.equal(n.be.resolvedChk, null);
  assert.ok(n.be.dispositions.includes('BE_HOLD_NULL_CHK'));
  assert.equal(m.app.chk_state, 'missing');
  assert.ok(Number.isNaN(m.app.adjustedDeployableSurplusCents)); // app: round(undefined*100)=NaN
  assert.equal(m.be.resolvedChk, null);
  assert.ok(m.be.dispositions.includes('BE_HOLD_MISSING_CHK'));
});

// ── S-6 obligation-set completeness attestation ─────────────────────────────────────────────────────────
test('S-6: only complete/verified-empty+attested proceed; every uncertain load HOLDs', () => {
  assert.equal(A('SP-70').be.obligation_set_complete, true);
  assert.equal(A('SP-71').be.obligation_set_complete, true);
  for (const id of ['SP-72', 'SP-73', 'SP-74', 'SP-75', 'SP-76', 'SP-77', 'SP-78']) {
    assert.equal(A(id).be.obligation_set_complete, false, `${id} must not be complete`);
    assert.ok(A(id).be.dispositions.includes('S6_OBLIGATION_SET_INCOMPLETE_HOLD'), `${id} must HOLD`);
    assert.equal(clsOf(R, id), CLASS.INTENTIONAL);
  }
});

// ── S-7 reserve-release clearing evidence ───────────────────────────────────────────────────────────────
test('S-7: released reserve needs durable clearing evidence, else HOLD; no double-release', () => {
  assert.ok(A('SP-79').be.dispositions.includes('S7_RESERVE_RELEASE_NO_CLEARING_EVIDENCE'));
  assert.equal(A('SP-80').be.dispositions.filter((d) => d.startsWith('S7')).length, 0); // valid linkage -> clean
  assert.equal(A('SP-81').be.dispositions.filter((d) => d.startsWith('S7')).length, 0); // cleared before reflect -> valid
  assert.ok(A('SP-82').be.dispositions.includes('S7_DUPLICATE_CLEARING_LINKAGE'));
  assert.ok(A('SP-83').be.dispositions.includes('S7_CLEARING_AMOUNT_MISMATCH'));
  assert.ok(A('SP-84').be.dispositions.includes('S7_CLEARING_SOURCE_MISMATCH'));
  assert.equal(A('SP-85').be.dispositions.filter((d) => d.startsWith('S7')).length, 0); // paid_from_other + evidence
  assert.equal(A('SP-86').be.dispositions.filter((d) => d.startsWith('S7')).length, 0); // voided + evidence
  assert.ok(A('SP-87').be.dispositions.includes('S7_STALE_RESOLUTION'));
  assert.ok(A('SP-88').be.dispositions.includes('S7_DUPLICATE_CLEARING_LINKAGE')); // one txn -> two obligations
});

// ── C-1: terminal-resolution reserve-release evidence ───────────────────────────────────────────────────
test('C-1: terminal-resolution exclusions (voided/paid_from_other) require valid consistent evidence, else HOLD', () => {
  const s7 = (id) => A(id).be.dispositions.filter((d) => d.startsWith('S7'));
  // fixed clause tests remain clean with valid evidence
  for (const id of ['SP-22', 'SP-52', 'SP-66', 'SP-91', 'SP-93', 'SP-98', 'SP-99']) assert.deepEqual(s7(id), [], `${id} should be clean`);
  // no-evidence / wrong-type / stale / duplicate / contradictory -> HOLD
  assert.ok(s7('SP-89').includes('S7_TERMINAL_RESOLUTION_NO_EVIDENCE'), 'voided resolution no evidence');
  assert.ok(s7('SP-90').includes('S7_TERMINAL_RESOLUTION_NO_EVIDENCE'), 'voided status no evidence');
  assert.ok(s7('SP-92').includes('S7_TERMINAL_RESOLUTION_NO_EVIDENCE'), 'paid_from_other no evidence');
  assert.ok(s7('SP-94').includes('S7_TERMINAL_EVIDENCE_WRONG_TYPE'), 'wrong evidence type');
  assert.ok(s7('SP-95').includes('S7_STALE_RESOLUTION'), 'stale terminal evidence');
  assert.ok(s7('SP-96').includes('S7_DUPLICATE_CLEARING_LINKAGE'), 'duplicate terminal evidence');
  assert.ok(s7('SP-97').includes('S7_CONTRADICTORY_STATUS_RESOLUTION'), 'contradictory status/resolution');
  assert.ok(s7('SP-100').includes('S7_DUPLICATE_CLEARING_LINKAGE'), 'one evidence -> multiple commitments');
  // both release weeks null still requires evidence (SP-89/90/92 above have both weeks null)
  assert.equal(byId('SP-89').commitments[0].reflected_model_week ?? null, null);
  assert.equal(byId('SP-89').commitments[0].resolved_model_week ?? null, null);
});
test('S-7 evidence-TYPE hardening: untyped/blank/unsupported evidence type -> HOLD; typed -> clean', () => {
  const s7 = (id) => A(id).be.dispositions.filter((d) => d.startsWith('S7'));
  assert.ok(s7('SP-101').includes('S7_TERMINAL_EVIDENCE_TYPE_MISSING'), 'voided evidence, type absent');
  assert.ok(s7('SP-102').includes('S7_TERMINAL_EVIDENCE_TYPE_MISSING'), 'voided evidence, blank type');
  assert.ok(s7('SP-103').includes('S7_TERMINAL_EVIDENCE_WRONG_TYPE'), 'voided evidence, unsupported type');
  assert.ok(s7('SP-104').includes('S7_TERMINAL_EVIDENCE_TYPE_MISSING'), 'paid evidence, type absent');
  assert.ok(s7('SP-105').includes('S7_TERMINAL_EVIDENCE_WRONG_TYPE'), 'paid evidence, inconsistent type');
  assert.deepEqual(s7('SP-106'), [], 'valid typed void -> clean');
  assert.deepEqual(s7('SP-107'), [], 'valid typed alternate-payment -> clean');
  // every valid-release fixture now carries an explicit supported type (no untyped acceptance anywhere)
  for (const id of ['SP-22', 'SP-52', 'SP-53', 'SP-55', 'SP-66', 'SP-85', 'SP-86', 'SP-91', 'SP-93', 'SP-98', 'SP-99'])
    assert.deepEqual(A(id).be.dispositions.filter((d) => d.startsWith('S7')), [], `${id} clean with explicit type`);
});

// ── reconciliation precedence + floor boundary ──────────────────────────────────────────────────────────
test('reconciled overrides projected; floor boundary exact/±1cent', () => {
  assert.equal(A('SP-02').app.resolvedChk, 10000);
  assert.equal(A('SP-01').app.resolvedChk, 12000);
  assert.equal(A('SP-34').app.adjustedDeployableSurplusCents, 0);
  assert.equal(A('SP-35').app.adjustedDeployableSurplusCents, 0);
  assert.equal(A('SP-36').app.adjustedDeployableSurplusCents, 1);
});
test('off-model material omission still escalated (SP-31, SP-50)', () => {
  assert.deepEqual(R.materialGaps.map((r) => r.id).sort(), ['SP-31', 'SP-50']);
});
test('repeatability: differential deterministic', () => {
  assert.equal(JSON.stringify(runStateDifferential(FIXTURES).summary), JSON.stringify(runStateDifferential(FIXTURES).summary));
});

// ════════════════════════════════════════════════════════════════════════════════════════════════════════
// 14 EXECUTABLE MUTATION PROBES (D-1) — each runs a mutated control THROUGH runStateDifferential and asserts a
// deterministic degraded classification / state-resolution divergence caught by the intended control.
// ════════════════════════════════════════════════════════════════════════════════════════════════════════
const dropAffects = (c, w) => c.model_year === 2026 && c.origin_model_week <= w && c.status !== 'voided' && c.resolution_type !== 'voided' && c.resolution_type !== 'paid_from_other_account' && !(c.reflected_model_week != null && c.reflected_model_week <= w) && (c.resolved_model_week == null || c.resolved_model_week > w) && false;
const dropVoided = (c, w) => c.model_year === 2026 && c.origin_model_week <= w && c.affects_deployable_cash && (c.resolved_model_week == null || c.resolved_model_week > w) && !(c.reflected_model_week != null && c.reflected_model_week <= w);

const MUT = [
  ['M1 remove off-model detection', 'SP-31', { skipOffModel: true }, CLASS.APP_GAP, CLASS.EXACT],
  ['M2 auto-model custom task', 'SP-31', { autoReserveOffModel: true }, CLASS.APP_GAP, CLASS.BE_DEFECT],
  ['M3 horizon incomplete->exhaustive', 'SP-41', { skipHorizonIncomplete: true }, CLASS.INTENTIONAL, CLASS.EXACT],
  ['M4 allow duplicate recon', 'SP-43', { skipDupConflict: true }, CLASS.INTENTIONAL, CLASS.EXACT],
  ['M5 allow conflicting recon', 'SP-44', { skipDupConflict: true }, CLASS.INTENTIONAL, CLASS.EXACT],
  ['M6 unknown basis authoritative', 'SP-06', { skipUnknownBasis: true }, CLASS.INTENTIONAL, CLASS.EXACT],
  ['M7 bypass recon precedence', 'SP-02', { beProjectedAlways: true }, CLASS.EXACT, CLASS.BE_DEFECT],
  ['M8 incorrect uncleared handling', 'SP-08', { beExtraReserveCents: 20000 }, CLASS.INTENTIONAL, CLASS.BE_DEFECT],
  ['M9 double-count transfer', 'SP-15', { beExtraReserveCents: 30000 }, CLASS.EXACT, CLASS.BE_DEFECT],
  ['M10 ignore open commitment', 'SP-18', { beReserved: dropAffects }, CLASS.EXACT, CLASS.BE_DEFECT],
  ['M11 include voided commitment', 'SP-22', { beReserved: dropVoided }, CLASS.EXACT, CLASS.BE_DEFECT],
  ['M12 wrong source account', 'SP-24', { wrongSource: true }, CLASS.EXACT, CLASS.BE_DEFECT],
  ['M13 cross floor by one cent', 'SP-34', { floorDeltaCents: 1 }, CLASS.EXACT, CLASS.BE_DEFECT],
];
for (const [name, id, mut, base, expectMut] of MUT) {
  test(`MUTATION ${name} => ${base} -> ${expectMut} (executable, deterministic)`, () => {
    assert.equal(clsOf(R, id), base, `baseline ${id}`);
    const m1 = runStateDifferential(FIXTURES, mut);
    const m2 = runStateDifferential(FIXTURES, mut);
    assert.equal(clsOf(m1, id), expectMut, `${name}: expected mutated ${expectMut}`);
    assert.notEqual(clsOf(m1, id), base, `${name}: must diverge from baseline`);
    assert.equal(clsOf(m1, id), clsOf(m2, id), `${name}: deterministic`);
  });
}
test('MUTATION M16 untyped-evidence escape: terminal evidence accepted without a type (must be caught by S-7)', () => {
  // correct: SP-101 (voided, evidence present, type absent) HOLDs -> INTENTIONAL
  assert.equal(clsOf(R, 'SP-101'), CLASS.INTENTIONAL);
  const m1 = runStateDifferential(FIXTURES, { untypedEvidenceEscape: true });
  const m2 = runStateDifferential(FIXTURES, { untypedEvidenceEscape: true });
  assert.equal(clsOf(m1, 'SP-101'), CLASS.EXACT, 'mutant accepts untyped evidence -> no HOLD');
  assert.notEqual(clsOf(m1, 'SP-101'), clsOf(R, 'SP-101'), 'untyped escape must diverge from the correct HOLD');
  assert.equal(clsOf(m1, 'SP-101'), clsOf(m2, 'SP-101'), 'deterministic');
});
test('MUTATION M15 C-1 escape: terminal-resolution release without evidence allowed (must be caught by S-7)', () => {
  // correct: SP-89 (voided, both release weeks null, no evidence) HOLDs -> INTENTIONAL
  assert.equal(clsOf(R, 'SP-89'), CLASS.INTENTIONAL);
  const m1 = runStateDifferential(FIXTURES, { c1Escape: true });
  const m2 = runStateDifferential(FIXTURES, { c1Escape: true });
  assert.equal(clsOf(m1, 'SP-89'), CLASS.EXACT, 'mutant restores the escape -> no HOLD');
  assert.notEqual(clsOf(m1, 'SP-89'), clsOf(R, 'SP-89'), 'C-1 escape must diverge from the correct HOLD');
  assert.equal(clsOf(m1, 'SP-89'), clsOf(m2, 'SP-89'), 'deterministic');
});
test('MUTATION M14 immutable-week -> mutable (state-resolution divergence, deterministic)', () => {
  const base = R.rows.find((r) => r.id === 'SP-37').layers.week_immutable.app;
  assert.equal(base, true); // week 3 <= anchor 5
  const m1 = runStateDifferential(FIXTURES, { immutableFalse: true });
  const m2 = runStateDifferential(FIXTURES, { immutableFalse: true });
  const v1 = m1.rows.find((r) => r.id === 'SP-37').layers.week_immutable.app;
  assert.equal(v1, false);
  assert.notEqual(v1, base);
  assert.equal(v1, m2.rows.find((r) => r.id === 'SP-37').layers.week_immutable.app);
});
