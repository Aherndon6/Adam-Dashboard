// baseline-E/state-parity/state-differential.mjs
// Differential engine: runs both resolutions per fixture and classifies per Phase-6 rules.
import { adaptState, StateAdapterRejection } from './state-adapter.mjs';
import { APP_CONSTS } from './app-state-oracle.mjs';

export const CLASS = {
  EXACT: 'EXACT_MATCH',
  SEMANTIC: 'SEMANTIC_MATCH_REPR_DIFF',
  INTENTIONAL: 'INTENTIONAL_CONTROL_DIFFERENCE',
  APP_GAP: 'APPLICATION_GAP',
  BE_DEFECT: 'BASELINE_E_DEFECT',
  ADAPTER_DEFECT: 'ADAPTER_DEFECT',
  FAILSTOP: 'FAIL_STOP',
};

// dispositions where Baseline E is safely STRICTER than a permissive application -> INTENTIONAL_CONTROL_DIFFERENCE
const STRICTER = new Set([
  'BE_HOLD_NULL_CHK', 'BE_HOLD_MISSING_CHK', 'BE_FAILSTOP_CONFLICTING_RECON', 'BE_FAILSTOP_DUPLICATE_RECON',
  'BE_FAILSTOP_MALFORMED_AMOUNT', 'BE_FAILSTOP_UNKNOWN_ACCOUNT', 'BE_REVIEW_UNKNOWN_BASIS',
  'BE_UNCLEARED_EXCLUDED_INFORMATIONAL', 'BE_TRANSFER_NO_PAIR_ID', 'BE_TRANSFER_AMOUNT_MISMATCH',
  'BE_RETAINED_HORIZON_INCOMPLETE',
  // S-6 / S-7 before-live controls (all HOLD/fail-closed -> stricter)
  'S6_OBLIGATION_SET_INCOMPLETE_HOLD', 'S6_FAILED_FETCH', 'S6_PARTIAL_LOAD', 'S6_MALFORMED_RESULT',
  'S6_RLS_FILTERED', 'S6_SCHEMA_MISMATCH', 'S6_SILENT_EMPTY_DEFAULT',
  'S7_RESERVE_RELEASE_NO_CLEARING_EVIDENCE', 'S7_DUPLICATE_CLEARING_LINKAGE', 'S7_CLEARING_AMOUNT_MISMATCH',
  'S7_CLEARING_SOURCE_MISMATCH', 'S7_STALE_RESOLUTION',
]);
const AGREE = new Set(['BE_EVIDENCE_AFTER_HORIZON_EXCLUDED']);
const APP_GAP_DISP = new Set(['BE_OFF_MODEL_OBLIGATION_FLAG']);

function beDeployableCents(be, floorCents) {
  if (be.resolvedChk == null) return null;
  return Math.max(0, Math.round(be.resolvedChk * 100) - be.reservedProtectedCents - floorCents);
}

function classifyOne(fx, mut) {
  let a;
  try { a = adaptState(fx, mut); }
  catch (e) { if (e instanceof StateAdapterRejection) return { id: fx.id, cls: fx.cls, classification: CLASS.ADAPTER_DEFECT, note: `adapter rejected: ${e.code}` }; throw e; }
  const floorCents = Math.round(APP_CONSTS.OP_FL * 100) - (mut.floorDeltaCents ?? 0);
  const { app, be, meta } = a;

  const reservedMatch = app.reservedProtectedCents === be.reservedProtectedCents;
  const reservedListMatch = JSON.stringify([...app.reservedCommitments].sort()) === JSON.stringify([...be.reservedCommitments].sort());
  const prefilterMatch = JSON.stringify([...meta.appPrefiltered].sort()) === JSON.stringify([...meta.bePrefiltered].sort());
  const beDep = beDeployableCents(be, floorCents);
  const resolvedMatch = (be.resolvedChk != null) ? (app.resolvedChk === be.resolvedChk) : true; // BE HOLD -> not a defect
  const appDepFinite = Number.isFinite(app.adjustedDeployableSurplusCents);
  const deployableMatch = (beDep != null && appDepFinite) ? (app.adjustedDeployableSurplusCents === beDep) : true;

  const layers = {
    resolved_checking: { app: app.resolvedChk, be: be.resolvedChk, match: resolvedMatch },
    reserved_protected_cents: { app: app.reservedProtectedCents, be: be.reservedProtectedCents, match: reservedMatch },
    reserved_commitments: { app: app.reservedCommitments, be: be.reservedCommitments, match: reservedListMatch },
    prefilter_eligibility: { app: meta.appPrefiltered, be: meta.bePrefiltered, match: prefilterMatch },
    deployable_surplus_cents: { app: app.adjustedDeployableSurplusCents, be: beDep, match: deployableMatch },
    review_required: { app: app.reviewRequired, be: be.dispositions.includes('BE_REVIEW_UNKNOWN_BASIS') || app.reviewRequired },
    week_immutable: { app: app.weekImmutable },
    off_model_reserved: { app: app.offModelObligationsReserved, be: false },
    register_in_capacity: { app: app.registerAggregatedIntoCapacity, be: false },
    obligation_set_complete: { be: be.obligation_set_complete },
    dispositions: be.dispositions,
  };

  // numeric / structural divergence between the app oracle and the independent BE side = defect (caught controls)
  if (!reservedMatch || !reservedListMatch || !prefilterMatch || !resolvedMatch || !deployableMatch) {
    return { id: fx.id, cls: fx.cls, classification: CLASS.BE_DEFECT, layers, dispositions: be.dispositions,
      note: `divergence: reserved=${reservedMatch} list=${reservedListMatch} prefilter=${prefilterMatch} resolved=${resolvedMatch} deployable=${deployableMatch}` };
  }

  const d = be.dispositions;
  const hasAppGap = d.some((x) => APP_GAP_DISP.has(x));
  const hasStricter = d.some((x) => STRICTER.has(x));
  const onlyAgree = d.length > 0 && d.every((x) => AGREE.has(x));

  let classification, material = false;
  if (hasAppGap) {
    classification = CLASS.APP_GAP;
    material = (fx.custom_tasks ?? []).some((t) => t.is_obligation && !t.completed && (t.amount_hint_cents != null || /BKX|tax reserve|reserve/i.test(t.label || '')));
  } else if (hasStricter) classification = CLASS.INTENTIONAL;
  else if (onlyAgree) classification = CLASS.EXACT;
  else if (d.length === 0) classification = CLASS.EXACT;
  else classification = CLASS.INTENTIONAL;

  return { id: fx.id, cls: fx.cls, classification, material, layers, dispositions: d };
}

export function runStateDifferential(fixtures, mut = {}) {
  const rows = fixtures.map((fx) => classifyOne(fx, mut));
  const summary = {};
  for (const r of rows) summary[r.classification] = (summary[r.classification] ?? 0) + 1;
  const appGaps = rows.filter((r) => r.classification === CLASS.APP_GAP);
  const materialGaps = appGaps.filter((r) => r.material);
  const beDefects = rows.filter((r) => r.classification === CLASS.BE_DEFECT || r.classification === CLASS.ADAPTER_DEFECT);
  const reservationParityAll = rows.every((r) => !r.layers || (r.layers.reserved_protected_cents.match && r.layers.reserved_commitments.match && r.layers.prefilter_eligibility.match));
  return { total: rows.length, summary, appGaps, materialGaps, beDefects, reservationParityAll, rows };
}
