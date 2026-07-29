// baseline-E/src/match.mjs
// rev-6.1 identity-matching predicate — A/C/D/E routing under FAIL-STOP precedence (§11 + rev-5.1 F).
// Global FAIL-STOP conditions (endpoint invalid, candgen invalid, N-1, anchor-vocabulary) are evaluated BEFORE
// any accepted A/E path or ordinary HOLD. Delegates disposition G to acceptGraph.
import { isIdentityStrong, amountDirectionConflict, provenanceOk, validateAnchorType } from './identity.mjs';
import { acceptGraph } from './allocation-g.mjs';

export const IDENTITY_STRONG_PREDICATE_STATUS = 'IMPLEMENTED_REV_6_1';

// coverageContext: { endpoint_ok:bool, candgen_valid:bool, candidates_exhaustive:bool, coverage_sufficient:bool }.
// endpoint_ok/candgen_valid === false ⇒ global FAIL-STOP (cannot be masked by A/C/E). Insufficient coverage
// (valid config) ⇒ COVERAGE-HOLD on the zero-candidate path.
export function classify({ bankTxn, candidates = [], coverageContext = {} }) {
  // 1. N-1 / §13: authoritative anchor without provenance ⇒ FAIL-STOP.
  for (const c of candidates) {
    for (const a of c.anchors || []) {
      if (a.authoritative_role === true && !provenanceOk(a)) {
        return R('FAIL-STOP', 'N1_AUTHORITATIVE_NO_PROVENANCE', `authoritative anchor without derivation provenance (N-1/§13) for ${c.event_id}`);
      }
    }
  }
  // 2. H-3 anchor-vocabulary FAIL-STOP (amount/direction/unknown/incompatible).
  for (const c of candidates) {
    for (const a of c.anchors || []) {
      try { validateAnchorType(a); } catch (err) { return R('FAIL-STOP', 'H3_ANCHOR_VOCABULARY', err.message); }
    }
  }
  // 3. GLOBAL config FAIL-STOP precedence (dominates A/C/E; rev-5.1 F, M11).
  if (coverageContext.endpoint_ok === false) return R('FAIL-STOP', 'ENDPOINT_INVALID', 'coverage_horizon_end endpoint not validated (rev-6.1 §1A) — dominates all dispositions');
  if (coverageContext.candgen_valid === false) return R('FAIL-STOP', 'CANDGEN_INVALID', 'candgen-v1 manifest invalid/unversioned (rev-6.1 §D) — dominates accepted A');

  // 4. Evaluate candidates.
  const evaluated = candidates.map((c) => {
    const is1 = isIdentityStrong(c.anchors || []);
    return { event_id: c.event_id, strong: is1.strong, conflict: amountDirectionConflict(bankTxn, c.event), gc: is1.independent_group_count, a: is1.category_A_present };
  });
  const strong = evaluated.filter((e) => e.strong);

  // §11 precedence: a strong candidate with amount/direction conflict ⇒ D/FAIL-STOP (dominates C/HOLD).
  if (strong.some((e) => e.conflict)) return R('D-FAIL-STOP', 'D_STRONG_CONFLICT', 'identity-strong candidate with amount/direction conflict (test 76)', evaluated);
  if (strong.length > 1) return R('C-HOLD', 'C_MULTI_STRONG', '>1 identity-strong candidate without an approved graph (test 69)', evaluated);
  if (strong.length === 1) return R('A', 'A_SINGLE_STRONG', 'exactly one identity-strong consistent candidate; weak candidates recorded', evaluated, strong[0].event_id);
  if (candidates.length > 0) return R('C-HOLD', 'C_NO_STRONG', '≥1 plausible, zero identity-strong (test 72)', evaluated);

  // 5. Zero candidates → E only if exhaustive recall + coverage sufficient (config already validated global).
  if (coverageContext.candidates_exhaustive !== true) return R('C-HOLD', 'C_NOT_EXHAUSTIVE', 'candidate search not proven exhaustive — E prohibited (N-2, M23)', evaluated);
  if (coverageContext.coverage_sufficient !== true) return R('COVERAGE-HOLD', 'COVERAGE_INSUFFICIENT', 'coverage insufficient — E prohibited; transfer routes to coverage HOLD (§1A)', evaluated);
  return R('E', 'E_TRUE_NO_MATCH', 'zero plausible candidates after exhaustive pinned-window search; balance-only; schedule byte-identical (test 77)', evaluated);
}

function R(disposition, code, reason, evaluated = [], confirmed) {
  return {
    disposition, code, reason,
    candidate_set: {
      candidates: evaluated.map((e) => ({ candidate_event_id: e.event_id, identity_result: e.strong ? 'identity_strong' : 'plausible_not_strong',
        non_confirmation_rationale: e.strong ? null : `not identity-strong (groups=${e.gc}, category_A=${e.a})` })),
      confirmed_candidate_id: confirmed || null,
      second_identity_strong_present: evaluated.filter((e) => e.strong).length > 1,
    },
  };
}

export function classifyAllocationGraph(input) { return acceptGraph(input); }
