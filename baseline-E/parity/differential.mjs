// baseline-E/parity/differential.mjs
// Differential engine: runs BOTH implementations over each fixture and classifies per Phase-5 rules.
//   - APPLICATION side: the verbatim extracted oracle (app-oracle.mjs) — process-TZ + pinned-clock dependent.
//   - BASELINE E side : the real canon.mjs primitives + the pure UTC-integer reference week (adapter.mjs).
// classification ∈ EXACT_MATCH | SEMANTIC_MATCH_REPR_DIFF | MISMATCH | APPLICATION_AMBIGUITY | BASELINE_E_FAIL_STOP
import { adapt, beRefModelWeek, AdapterRejection } from './adapter.mjs';
import { appDateToModelWeek, appIsValidISODate, appGetCurrentWeek } from './app-oracle.mjs';

const CLASS = {
  EXACT: 'EXACT_MATCH',
  SEMANTIC: 'SEMANTIC_MATCH_REPR_DIFF',
  MISMATCH: 'MISMATCH',
  AMBIGUITY: 'APPLICATION_AMBIGUITY',
  FAILSTOP: 'BASELINE_E_FAIL_STOP',
};

// naive (ungated) app date derived from the malformed instant, for the reject-parity comparison
function naiveDateFromInstant(iso) {
  if (typeof iso !== 'string') return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

function classifyOne(fx) {
  const attrs = {};
  let cls;

  // ── current-week cursor fixture (PX-34): handled specially; getCurrentWeek is a clock+TZ cursor, not placement.
  if (fx.current_week_probes) {
    const probes = fx.current_week_probes.map((p) => ({
      label: p.label, iso: p.iso,
      app_current_week: appGetCurrentWeek(Date.parse(p.iso)),
    }));
    attrs.current_week_probes = probes;
    // dateToModelWeek endpoint checks (deterministic placement) at the band edges:
    attrs.band_edge = {
      'week31_last_day 2027-01-09': { app: appDateToModelWeek('2027-01-09'), be: beRefModelWeek('2027-01-09').week },
      'past_band 2027-01-10': { app: appDateToModelWeek('2027-01-10'), be: beRefModelWeek('2027-01-10').week },
    };
    const edgeOk = attrs.band_edge['week31_last_day 2027-01-09'].app === 31 && attrs.band_edge['week31_last_day 2027-01-09'].be === 31
      && attrs.band_edge['past_band 2027-01-10'].app === null && attrs.band_edge['past_band 2027-01-10'].be === null;
    // getCurrentWeek is intentionally clock/TZ dependent -> flagged as a GOVERNANCE item, represented here as
    // SEMANTIC (placement band edges match exactly; the cursor is a separate, environment-dependent concept).
    attrs.governance_flag = 'getCurrentWeek() depends on system clock AND process timezone (see report §Governance).';
    cls = edgeOk ? CLASS.SEMANTIC : CLASS.MISMATCH;
    return { id: fx.id, cls: fx.cls, classification: cls, attrs };
  }

  // ── deterministic-rejection fixtures (PX-29 invalid, PX-30 missing tz) ──────────────────────────────────
  if (fx.expect_reject) {
    let a;
    try { a = adapt(fx); } catch (e) { if (e instanceof AdapterRejection) { a = { rejected: { code: e.code } }; } else throw e; }
    const be_rejects = !!a.rejected || a.canonical_utc === false;
    let app_rejects;
    if (fx.expect_reject === 'NON_CANONICAL_INSTANT') {
      // app has NO instant input class -> not representable; treat as app-side reject (cannot enter placement)
      app_rejects = true;
      attrs.app_note = 'application has no UTC-instant input; a timezone-less instant is not representable in the app date class';
      attrs.classification_basis = 'both fail-closed';
    } else {
      const naive = fx.naive_date ?? naiveDateFromInstant(fx.instant_utc);
      app_rejects = appIsValidISODate(naive) === false; // app acceptance gate
      attrs.app_isValidISODate = { input: naive, result: appIsValidISODate(naive) };
    }
    attrs.be_rejects = be_rejects;
    attrs.app_rejects = app_rejects;
    attrs.failure_code = a.rejected?.code ?? fx.expect_reject;
    cls = (be_rejects && app_rejects) ? CLASS.EXACT : CLASS.MISMATCH;
    return { id: fx.id, cls: fx.cls, classification: cls, attrs };
  }

  // ── normal placement fixtures ───────────────────────────────────────────────────────────────────────────
  const a = adapt(fx);
  const etDate = a.et_date;
  const appWeek = appDateToModelWeek(etDate);          // application oracle (process-TZ dependent by construction)
  const beWeek = a.be.model_week;                       // Baseline E interpretation (pure, TZ-invariant)

  attrs.effective_calendar_date = { app: a.app_input.date_str, be: a.be.et_date, equal: a.app_input.date_str === a.be.et_date };
  attrs.effective_timestamp = { app: null, be: fx.instant_utc, note: 'app date class is timezone-less; BE carries a UTC instant (representation difference, no placement effect)' };
  attrs.model_week_number = { app: appWeek, be: beWeek.week, equal: appWeek === beWeek.week };
  attrs.in_model_horizon = { app: appWeek !== null, be: beWeek.in_band, equal: (appWeek !== null) === beWeek.in_band };
  attrs.retained_horizon = { app: appWeek !== null, be: beWeek.in_band, equal: (appWeek !== null) === beWeek.in_band };
  attrs.boundary_inclusivity = { be_reason: beWeek.reason, app_in_band: appWeek !== null };
  attrs.cleared_pending = { cleared: fx.cleared ?? null, placement_invariant: true, note: 'neither side varies date/week by cleared flag' };
  attrs.reason_or_failure_code = { app: appWeek === null ? 'OUTSIDE_BAND' : 'IN_BAND', be: beWeek.reason };

  if (a.be.candidate_proximity) {
    attrs.candidate_date_proximity = { be: a.be.candidate_proximity, app: 'N/A (no candidate-proximity concept in application)' };
  }
  if (a.be.expected_date_interval) {
    // app analog: band each endpoint via the app oracle
    const iv = fx.expected_date_interval;
    attrs.expected_date_interval = {
      be_canonical: a.be.expected_date_interval.canonical,
      app_endpoints: { start_week: appDateToModelWeek(iv.start), end_week: appDateToModelWeek(iv.end) },
      note: 'BE canonicalizes the inclusive interval; app has no interval type but bands each endpoint identically',
    };
  }

  // classification: the shared, placement-affecting attributes must all agree
  const shared = [attrs.effective_calendar_date.equal, attrs.model_week_number.equal, attrs.in_model_horizon.equal, attrs.retained_horizon.equal];
  if (shared.every(Boolean)) {
    // representation differences exist (timezone-less date vs UTC instant; BE-only ±14) but cannot affect
    // candidate generation / graph identity / classification / allocation / coverage / capacity here.
    cls = CLASS.EXACT;
  } else {
    cls = CLASS.MISMATCH;
  }
  return { id: fx.id, cls: fx.cls, classification: cls, attrs };
}

export function runDifferential(fixtures) {
  const rows = fixtures.map(classifyOne);
  const summary = {};
  for (const r of rows) summary[r.classification] = (summary[r.classification] ?? 0) + 1;
  const mismatches = rows.filter((r) => r.classification === CLASS.MISMATCH);
  return { tz: process.env.TZ ?? '(unset -> system local)', node: process.version, total: rows.length, summary, mismatches, rows };
}

export { CLASS };
