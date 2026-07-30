// baseline-E/state-parity/state-adapter.mjs
// ADAPTER (clearly labeled — NOT oracle). Maps ONE canonical synthetic state fixture into:
//   A. the application oracle inputs + runs the VERBATIM extracted resolvers (app-state-oracle.mjs); and
//   B. an INDEPENDENT Baseline-E-side resolution (reservation predicate reimplemented + rev-6.1 dispositions +
//      the S-6/S-7 before-live controls).
// The commitment prefilter models runModel's inline two-branch logic (index.html:3159-3172) — that logic is NOT a
// standalone function (it is loop-body code depending on loop-local `_reconciledWeekNums`/`num`), so exact
// function extraction is infeasible; the RESERVATION CORE it calls (`isReservedAsOf`) IS the verbatim extracted
// function, and the branch wrapper reproduces the verbatim source lines (documented in the report §2/§3.D).
//
// No silent coercion. Malformed/incomplete/duplicate/ambiguous fixtures rejected deterministically. All synthetic.
import { resolversFor, APP_CONSTS } from './app-state-oracle.mjs';

export class StateAdapterRejection extends Error { constructor(code, msg) { super(msg); this.code = code; } }

const SOURCE_ACCOUNTS = new Set(['truist_checking', 'vio_tax', 'lending_club_ef', 'fidelity', 'amex_savings']);
const COMMIT_STATUS = new Set(['open', 'executed', 'cleared', 'voided', 'bank_pending', 'pending', 'stale', 'reflected']);
const RESOLUTION_TYPES = new Set(['voided', 'paid_from_other_account', 'cleared', 'reflected', null, undefined]);
const BASIS = new Set(['posted_current_balance', 'available_balance', 'unknown', null]);
// runModel hardcodes the capacity source account at index.html:3161/3167/3175
export const CAPACITY_SOURCE = 'truist_checking';

// ── INDEPENDENT Baseline-E-side reservation predicate (reimplemented; NOT the extracted app function) ──────────
export function beIsReserved(c, weekNum, PLAN_YEAR) {
  if (c.model_year !== PLAN_YEAR) return false;
  if (c.origin_model_week > weekNum) return false;
  if (!c.affects_deployable_cash) return false;
  if (c.status === 'voided') return false;
  if (c.resolution_type === 'voided') return false;
  if (c.resolution_type === 'paid_from_other_account') return false;
  if (c.reflected_model_week != null && c.reflected_model_week <= weekNum) return false;
  if (c.resolved_model_week == null) return true;
  return c.resolved_model_week > weekNum;
}

// ── commitment prefilter (models index.html:3159-3172; reservation core = the injected isReservedFn) ───────────
//   reconciled week:   c.source===SOURCE && isReservedFn(c,week)
//   unreconciled week: c.source===SOURCE && origin<week (STRICT) && (reconciledOrigin || historical_repair) && isReservedFn
function prefilter(commitments, week, isRec, reconciledWeekNums, isReservedFn, { ignoreSource = false } = {}) {
  return commitments.filter((c) => {
    if (!ignoreSource && c.source_account !== CAPACITY_SOURCE) return false;
    if (!isRec) {
      if (!(c.origin_model_week < week)) return false; // strict
      if (!(reconciledWeekNums[c.origin_model_week] || c.commitment_source === 'historical_repair')) return false;
    }
    return isReservedFn(c, week);
  });
}

function validateFixture(fx) {
  if (!fx || typeof fx !== 'object') throw new StateAdapterRejection('FX_NOT_OBJECT', 'fixture not an object');
  if (typeof fx.id !== 'string' || !/^SP-\d{2,3}$/.test(fx.id)) throw new StateAdapterRejection('FX_BAD_ID', `id must be SP-NN (${fx.id})`);
  if (!Number.isInteger(fx.model_week) || fx.model_week < 1 || fx.model_week > 31) throw new StateAdapterRejection('FX_BAD_WEEK', `${fx.id}: model_week 1..31`);
  if (typeof fx.projected_chk !== 'number' || !Number.isFinite(fx.projected_chk)) throw new StateAdapterRejection('FX_BAD_PROJ', `${fx.id}: projected_chk finite number`);
  for (const rr of fx.recon_rows ?? []) {
    if (!Number.isInteger(rr.week)) throw new StateAdapterRejection('FX_RECON_WEEK', `${fx.id}: recon week int`);
    if (!BASIS.has(rr.balance_basis ?? null)) throw new StateAdapterRejection('FX_RECON_BASIS', `${fx.id}: bad basis`);
  }
  for (const c of fx.commitments ?? []) {
    if (typeof c.amount_cents !== 'number' || !Number.isFinite(c.amount_cents)) throw new StateAdapterRejection('FX_COMMIT_AMT', `${fx.id}: amount_cents finite`);
    if (c.source_account != null && !SOURCE_ACCOUNTS.has(c.source_account)) throw new StateAdapterRejection('FX_COMMIT_SRC', `${fx.id}: bad source`);
    if (c.status != null && !COMMIT_STATUS.has(c.status)) throw new StateAdapterRejection('FX_COMMIT_STATUS', `${fx.id}: bad status`);
    if (!RESOLUTION_TYPES.has(c.resolution_type)) throw new StateAdapterRejection('FX_COMMIT_RESTYPE', `${fx.id}: bad resolution_type`);
  }
}

// build reconData; preserve the chk:null vs chk-MISSING distinction (D-4); detect duplicate/conflict (S-3)
function buildReconData(recon_rows) {
  const map = {}; const seen = {}; let duplicate = null, conflict = null;
  for (const rr of recon_rows ?? []) {
    const hasChkKey = Object.prototype.hasOwnProperty.call(rr, 'chk');
    if (seen[rr.week] !== undefined) { duplicate = rr.week; if (seen[rr.week] !== (hasChkKey ? rr.chk : '__MISSING__')) conflict = rr.week; }
    seen[rr.week] = hasChkKey ? rr.chk : '__MISSING__';
    const row = { sav: rr.sav ?? 0, amx: rr.amx ?? 0, tax: rr.tax ?? 0, lc: rr.lc ?? 0, balance_basis: rr.balance_basis ?? null };
    if (hasChkKey) row.chk = rr.chk; // MISSING chk key preserved as absent -> engine reads undefined -> NaN
    map[rr.week] = row;
  }
  return { map, duplicate, conflict };
}

// ── S-7 reserve-release clearing-evidence control (C-1 closed 2026-07-30) ──────────────────────────────────────
// EVERY path that releases/excludes a previously-reservable commitment must carry valid, consistent supporting
// evidence, else HOLD. Release paths recognized: reflected_model_week<=week, resolved_model_week<=week, AND
// terminal-resolution exclusions (resolution_type in {voided, paid_from_other_account}, or status='voided') even
// when BOTH release weeks are null. A terminal status/resolution field ALONE never bypasses the evidence check.
function reserveReleaseEvidence(commitments, week, seenClearingIds, PLAN_YEAR, opts = {}) {
  const disp = [];
  const termResType = (c) => c.resolution_type === 'voided' || c.resolution_type === 'paid_from_other_account';
  const termStatus = (c) => c.status === 'voided';
  for (const c of commitments) {
    const releasedByReflect = c.reflected_model_week != null && c.reflected_model_week <= week;
    const releasedByResolve = c.resolved_model_week != null && c.resolved_model_week <= week;
    // MUT c1Escape: restore the pre-C-1 escape — terminal-only exclusions (no reflected/resolved week) skip evidence
    const terminalExclusion = opts.c1Escape ? false : (termResType(c) || termStatus(c)); // voided/paid_from_other_account -> not reserved by isReservedAsOf
    // Only a commitment that would OTHERWISE be reservable (right year/origin/affects) needs release justification.
    const wouldReserveButForRelease = c.model_year === PLAN_YEAR && c.origin_model_week <= week && !!c.affects_deployable_cash;
    if (!releasedByReflect && !releasedByResolve && !terminalExclusion) continue; // still reserved -> nothing to justify
    if (!wouldReserveButForRelease && !terminalExclusion) continue; // never reservable for a non-terminal reason (e.g. wrong year) -> no release
    const kind = terminalExclusion ? 'TERMINAL' : 'MODELED';

    // consistency: resolution_type and evidence type must agree
    if (c.resolution_type === 'voided' && c.status != null && c.status !== 'voided') disp.push('S7_CONTRADICTORY_STATUS_RESOLUTION');
    if (c.resolution_stale === true) disp.push('S7_STALE_RESOLUTION');

    // acceptable, non-overlapping evidence paths. Terminal evidence REQUIRES a non-empty resolution_evidence AND an
    // explicit supported resolution_evidence_type consistent with the resolution (untyped evidence is NOT accepted).
    const hasClearedTxn = typeof c.cleared_transaction_id === 'string' && c.cleared_transaction_id.length > 0;
    const evPresent = typeof c.resolution_evidence === 'string' && c.resolution_evidence.length > 0;
    const evTypePresent = typeof c.resolution_evidence_type === 'string' && c.resolution_evidence_type.length > 0;
    // MUT untypedEscape: restore the pre-hardening behavior that accepted evidence with NO type.
    const untypedAccept = (t) => c.resolution_evidence_type === t || (opts.untypedEscape && !evTypePresent);
    const paidOtherOk = c.resolution_type === 'paid_from_other_account' && evPresent && untypedAccept('alternate_payment');
    const voidedOk = (c.resolution_type === 'voided' || c.status === 'voided') && evPresent && untypedAccept('void_cancellation');

    if (terminalExclusion) {
      // terminal void / paid-from-other: REQUIRE non-empty evidence AND a supported, consistent evidence TYPE.
      const wantVoid = c.resolution_type !== 'paid_from_other_account'; // voided (resolution_type or status)
      const ok = wantVoid ? voidedOk : paidOtherOk;
      if (!ok) {
        if (!evPresent) disp.push('S7_TERMINAL_RESOLUTION_NO_EVIDENCE');           // no evidence item at all
        else if (!evTypePresent) disp.push('S7_TERMINAL_EVIDENCE_TYPE_MISSING');   // evidence present, type absent/blank
        else disp.push('S7_TERMINAL_EVIDENCE_WRONG_TYPE');                          // type present but unsupported/inconsistent
      }
      // one evidence item must not release multiple commitments (dedup on txn id OR resolution_evidence_id)
      if (hasClearedTxn) { if (seenClearingIds.has(c.cleared_transaction_id)) disp.push('S7_DUPLICATE_CLEARING_LINKAGE'); else seenClearingIds.add(c.cleared_transaction_id); }
      if (c.resolution_evidence_id != null) { if (seenClearingIds.has('re:' + c.resolution_evidence_id)) disp.push('S7_DUPLICATE_CLEARING_LINKAGE'); else seenClearingIds.add('re:' + c.resolution_evidence_id); }
    } else if (hasClearedTxn) {
      if (seenClearingIds.has(c.cleared_transaction_id)) disp.push('S7_DUPLICATE_CLEARING_LINKAGE'); // one txn, multiple obligations
      else seenClearingIds.add(c.cleared_transaction_id);
      if (c.cleared_amount_cents == null || c.cleared_source_account == null) disp.push('S7_CLEARING_METADATA_MISSING'); // bare id insufficient (C-1 low)
      if (c.cleared_amount_cents != null && c.cleared_amount_cents !== c.amount_cents) disp.push('S7_CLEARING_AMOUNT_MISMATCH');
      if (c.cleared_source_account != null && c.cleared_source_account !== c.source_account) disp.push('S7_CLEARING_SOURCE_MISMATCH');
    } else if (paidOtherOk || voidedOk) {
      // modeled release justified by a terminal resolution with valid evidence — acceptable
    } else {
      disp.push('S7_RESERVE_RELEASE_NO_CLEARING_EVIDENCE'); // modeled release on state alone -> HOLD
    }
    void kind;
  }
  return disp;
}

// ── S-6 obligation-set completeness attestation ───────────────────────────────────────────────────────────────
// Only an affirmatively verified complete/verified-empty load may proceed; every uncertain load -> HOLD.
function obligationSetAttestation(load) {
  const a = load ?? { status: 'unattested' };
  const OK = new Set(['complete', 'verified_empty']);
  const complete = OK.has(a.status) && a.attested === true;
  const disp = [];
  if (!complete) disp.push('S6_OBLIGATION_SET_INCOMPLETE_HOLD');
  if (a.status === 'failed_fetch') disp.push('S6_FAILED_FETCH');
  if (a.status === 'partial') disp.push('S6_PARTIAL_LOAD');
  if (a.status === 'malformed') disp.push('S6_MALFORMED_RESULT');
  if (a.status === 'rls_filtered') disp.push('S6_RLS_FILTERED');
  if (a.status === 'schema_mismatch') disp.push('S6_SCHEMA_MISMATCH');
  if (a.status === 'silent_empty') disp.push('S6_SILENT_EMPTY_DEFAULT');
  return { complete, disp };
}

// Map a fixture -> both resolutions. `mut` injects executable control mutations (D-1) through this path.
export function adaptState(fx, mut = {}) {
  validateFixture(fx);
  const PLAN_YEAR = APP_CONSTS.PLAN_YEAR, OP_FL = APP_CONSTS.OP_FL;
  const floorCents = Math.round(OP_FL * 100); // app uses the true floor; MUT crossFloor mutates only the BE floor (in the differential)
  const week = fx.model_week;
  const { map: reconData, duplicate, conflict } = buildReconData(fx.recon_rows);
  const commitments = fx.commitments ?? [];
  const reconciledWeekNums = {}; for (const k in reconData) reconciledWeekNums[parseInt(k, 10)] = true;
  const R = resolversFor(reconData);
  const isRec = !!reconData[week];

  // ── A. APPLICATION side (verbatim resolvers + verbatim-sourced two-branch prefilter) ───────────────────────
  const app = {};
  app.isReconciled_engineGate = isRec;
  app.isWeekReconciled = R.isWeekReconciled(week);
  const rowMissingChk = isRec && !Object.prototype.hasOwnProperty.call(reconData[week], 'chk');
  const rowNullChk = isRec && !rowMissingChk && reconData[week].chk === null;
  app.chk_state = rowMissingChk ? 'missing' : rowNullChk ? 'null' : (isRec ? 'present' : 'unreconciled');
  app.resolvedChk = R.authoritativeCurrentChk(week, fx.projected_chk); // app oracle is ground truth (never mutated)
  const actualChkForEngine = isRec ? reconData[week].chk : fx.projected_chk; // undefined if MISSING -> NaN downstream
  app.actualChkForEngine = actualChkForEngine;
  const appPrefiltered = prefilter(commitments, week, isRec, reconciledWeekNums, R.isReservedAsOf);
  const engine = R.getCashAvailabilityEngine(Math.round((actualChkForEngine ?? 0) * 100), floorCents, appPrefiltered, CAPACITY_SOURCE, week);
  app.engine = engine;
  app.reservedProtectedCents = engine.reservedProtectedCents;
  app.reservedCommitments = appPrefiltered.map((c) => c.cid);
  // app deployable — NaN if actualChk is missing (round(undefined*100)=NaN); app never guards this
  app.adjustedDeployableSurplusCents = Number.isFinite(actualChkForEngine)
    ? engine.adjustedDeployableSurplusCents
    : (Number.isNaN(Math.round(actualChkForEngine * 100)) ? NaN : engine.adjustedDeployableSurplusCents);
  const _basisUnknown = isRec && reconData[week].balance_basis === 'unknown';
  const _hasActiveReserves = app.reservedCommitments.length > 0 && engine.reservedProtectedCents > 0;
  const _hasBankPending = appPrefiltered.some((c) => c.status === 'bank_pending');
  app.reviewRequired = _hasActiveReserves && (_basisUnknown || _hasBankPending);
  app.offModelObligationsReserved = false; // runModel never scans customTaskData (index.html:3899)
  app.registerAggregatedIntoCapacity = false;
  app.weekImmutable = mut.immutableFalse ? false : (app.isWeekReconciled || week <= 5); // _weekIsImmutable (index.html:4448); anchor boundary=5

  // ── B. BASELINE E side (independent predicate + prefilter + rev-6.1 dispositions + S-6/S-7) ────────────────
  const be = { dispositions: [] };
  const seen = new Set(be.dispositions);
  const disp = (code) => { if (!seen.has(code)) { be.dispositions.push(code); seen.add(code); } };
  const bePred = mut.beReserved ? mut.beReserved : (c, w) => beIsReserved(c, w, PLAN_YEAR);
  const bePrefiltered = prefilter(commitments, week, isRec, reconciledWeekNums, bePred, { ignoreSource: !!mut.wrongSource });
  be.reservedCommitments = bePrefiltered.map((c) => c.cid);
  be.reservedProtectedCents = bePrefiltered.reduce((s, c) => s + c.amount_cents, 0);
  if (mut.autoReserveOffModel) { // MUT: wrongly auto-model an off-model obligation into the reserve
    for (const t of fx.custom_tasks ?? []) if (t.is_obligation && !t.completed && t.amount_hint_cents != null) be.reservedProtectedCents += t.amount_hint_cents;
  }
  // MUT: wrongly fold a register uncleared item / a transfer leg into the reserve total (capacity-affecting)
  if (mut.beExtraReserveCents) be.reservedProtectedCents += mut.beExtraReserveCents;
  // reconciled-vs-projected with a PRESENT numeric chk required (S-2: null AND missing distinguished)
  const rr = reconData[week];
  if (mut.beProjectedAlways) be.resolvedChk = fx.projected_chk; // MUT: bypass reconciliation precedence (BE ignores reconciled chk)
  else if (rr) {
    if (rowMissingChk) { disp('BE_HOLD_MISSING_CHK'); be.resolvedChk = null; }
    else if (rr.chk === null || typeof rr.chk !== 'number' || !Number.isFinite(rr.chk)) { disp('BE_HOLD_NULL_CHK'); be.resolvedChk = null; }
    else be.resolvedChk = rr.chk;
  } else be.resolvedChk = fx.projected_chk;
  if (!mut.skipDupConflict) {
    if (conflict != null) disp('BE_FAILSTOP_CONFLICTING_RECON');
    else if (duplicate != null) disp('BE_FAILSTOP_DUPLICATE_RECON');
  }
  if (!mut.skipUnknownBasis && rr && rr.balance_basis === 'unknown') disp('BE_REVIEW_UNKNOWN_BASIS');
  if (commitments.some((c) => c.amount_cents < 0 || !Number.isInteger(c.amount_cents))) disp('BE_FAILSTOP_MALFORMED_AMOUNT');
  if (!mut.skipOffModel && (fx.custom_tasks ?? []).some((t) => !t.completed && t.is_obligation)) disp('BE_OFF_MODEL_OBLIGATION_FLAG');
  if ((fx.register_txns ?? []).some((t) => t.account === 'truist_checking' && t.cleared === false && t.direction === 'debit')) disp('BE_UNCLEARED_EXCLUDED_INFORMATIONAL');
  const legs = fx.transfer_legs ?? [];
  if (legs.length) {
    if (!legs.every((l) => l.transfer_pair_id != null)) disp('BE_TRANSFER_NO_PAIR_ID');
    if (legs.length === 2 && Math.abs(legs[0].amount_cents) !== Math.abs(legs[1].amount_cents)) disp('BE_TRANSFER_AMOUNT_MISMATCH');
  }
  if (!mut.skipHorizonIncomplete && fx.retained_horizon_complete === false) disp('BE_RETAINED_HORIZON_INCOMPLETE');
  if (fx.evidence_after_horizon === true) disp('BE_EVIDENCE_AFTER_HORIZON_EXCLUDED');
  if (fx.unknown_account === true) disp('BE_FAILSTOP_UNKNOWN_ACCOUNT');
  // S-7 reserve-release clearing evidence (all release paths incl. terminal-resolution exclusions — C-1 closed)
  for (const code of reserveReleaseEvidence(commitments, week, new Set(), PLAN_YEAR, { c1Escape: !!mut.c1Escape, untypedEscape: !!mut.untypedEvidenceEscape })) disp(code);
  // S-6 obligation-set completeness attestation
  const att = obligationSetAttestation(fx.load_attestation);
  be.obligation_set_complete = att.complete;
  for (const code of att.disp) disp(code);

  return { id: fx.id, cls: fx.cls, week, source: CAPACITY_SOURCE, isRec, app, be, meta: { duplicate, conflict, appPrefiltered: appPrefiltered.map((c) => c.cid), bePrefiltered: bePrefiltered.map((c) => c.cid) } };
}
