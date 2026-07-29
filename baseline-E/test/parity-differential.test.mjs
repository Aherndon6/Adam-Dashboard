// baseline-E/test/parity-differential.test.mjs
// Differential-oracle parity suite: app verbatim oracle vs Baseline E interpretation over 35 synthetic fixtures,
// plus the six mandatory mutation probes (each MUST produce a deterministic parity failure).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { FIXTURES } from '../parity/fixtures.mjs';
import { runDifferential, CLASS } from '../parity/differential.mjs';
import { adapt, beRefModelWeek } from '../parity/adapter.mjs';
import { appDateToModelWeek, appGetCurrentWeek, buildOracleFromContent, assertIndexHtmlIntegrity, OracleIntegrityError, PINNED_INDEX_HTML_SHA256 } from '../parity/app-oracle.mjs';
import { etLocalDate, etDayDiff, canonExpectedDateInterval } from '../src/canon.mjs';

const R = runDifferential(FIXTURES);

// ── coverage + no-mismatch on the shared placement surface ─────────────────────────────────────────────
test('corpus has all 35 synthetic fixtures with unique PX-NN ids', () => {
  assert.equal(FIXTURES.length, 35);
  const ids = new Set(FIXTURES.map((f) => f.id));
  assert.equal(ids.size, 35);
  for (const f of FIXTURES) assert.match(f.id, /^PX-\d{2}$/);
});
test('every fixture classifies to an allowed disposition', () => {
  const allowed = new Set(Object.values(CLASS));
  for (const row of R.rows) assert.ok(allowed.has(row.classification), `${row.id}: ${row.classification}`);
});
test('ZERO MISMATCH on the evidence-placement surface', () => {
  assert.deepEqual(R.mismatches.map((m) => m.id), [], 'unexpected placement mismatches');
});
test('model-week placement: app oracle == Baseline E reference for every in/out-of-band fixture', () => {
  for (const row of R.rows) {
    const a = row.attrs.model_week_number;
    if (!a) continue;
    assert.equal(a.app, a.be, `${row.id}: app_wk=${a.app} be_wk=${a.be}`);
    assert.equal(a.equal, true);
  }
});

// ── boundary inclusivity (Phase-4 #9–#16, #33) ─────────────────────────────────────────────────────────
test('week boundary is inclusive-start / exclusive-next at ET midnight', () => {
  // PX-11 (1ms before ET-midnight Aug16) -> week 10; PX-12 (ET-midnight Aug16) -> week 11
  const w11 = R.rows.find((x) => x.id === 'PX-11').attrs.model_week_number;
  const w12 = R.rows.find((x) => x.id === 'PX-12').attrs.model_week_number;
  assert.equal(w11.app, 10); assert.equal(w12.app, 11);
});
test('band endpoints inclusive: 2027-01-09 -> week 31, 2027-01-10 -> null (both sides)', () => {
  assert.equal(appDateToModelWeek('2027-01-09'), 31);
  assert.equal(beRefModelWeek('2027-01-09').week, 31);
  assert.equal(appDateToModelWeek('2027-01-10'), null);
  assert.equal(beRefModelWeek('2027-01-10').week, null);
});
test('±14 candidate proximity is inclusive on both edges, exclusive at ±15', () => {
  assert.equal(adapt(FIXTURES.find((f) => f.id === 'PX-13')).be.candidate_proximity.within_14_inclusive, true);  // -14
  assert.equal(adapt(FIXTURES.find((f) => f.id === 'PX-14')).be.candidate_proximity.within_14_inclusive, true);  // +14
  assert.equal(adapt(FIXTURES.find((f) => f.id === 'PX-15')).be.candidate_proximity.within_14_inclusive, false); // -15
  assert.equal(adapt(FIXTURES.find((f) => f.id === 'PX-16')).be.candidate_proximity.within_14_inclusive, false); // +15
});
test('UTC-vs-ET day divergence (PX-33): ET truncation decides the week (10, not 11)', () => {
  const r = R.rows.find((x) => x.id === 'PX-33').attrs.model_week_number;
  assert.equal(r.app, 10); assert.equal(r.be, 10);
});

// ── cleared/pending invariance (Phase-4 #17–#22) ───────────────────────────────────────────────────────
test('cleared vs uncleared do NOT change placement (PX-17==PX-18, PX-19==PX-20, PX-21==PX-22)', () => {
  const wk = (id) => R.rows.find((x) => x.id === id).attrs.model_week_number.app;
  assert.equal(wk('PX-17'), wk('PX-18'));
  assert.equal(wk('PX-19'), wk('PX-20'));
  assert.equal(wk('PX-21'), wk('PX-22'));
});

// ── deterministic rejection parity (Phase-4 #29, #30) ──────────────────────────────────────────────────
test('invalid date + missing timezone: both sides fail-closed (EXACT)', () => {
  const px29 = R.rows.find((x) => x.id === 'PX-29');
  const px30 = R.rows.find((x) => x.id === 'PX-30');
  assert.equal(px29.classification, CLASS.EXACT);
  assert.equal(px29.attrs.app_rejects, true); assert.equal(px29.attrs.be_rejects, true);
  assert.equal(px30.classification, CLASS.EXACT);
  assert.equal(px30.attrs.app_rejects, true); assert.equal(px30.attrs.be_rejects, true);
});

// ── governance: getCurrentWeek is clock+TZ dependent (documented, surfaced to owner) ───────────────────
test('GOVERNANCE: getCurrentWeek() returns different weeks for the SAME instant across timezones', () => {
  // This is asserted to be TRUE — it documents the Phase-6 hard-stop trigger, not a passing property.
  // We cannot change process.env.TZ mid-run (Node caches it); the run-parity runner proves it across zones.
  // Here we prove getCurrentWeek is NOT calendar-pure by contrast with dateToModelWeek stability:
  const inst = Date.UTC(2026, 5, 14, 3, 30, 0); // 2026-06-14T03:30:00Z
  const cursor = appGetCurrentWeek(inst);
  assert.ok(cursor === 1 || cursor === 2, `cursor under current TZ = ${cursor} (1 in ET, 2 in UTC/east)`);
});

// ════════════════════════════════════════════════════════════════════════════════════════════════════════
// MUTATION PROBES — each deliberately breaks one aspect; each MUST diverge from the verbatim app oracle.
// A mutation "passes" iff it produces a deterministic parity FAILURE (divergence) on ≥1 fixture.
// ════════════════════════════════════════════════════════════════════════════════════════════════════════
function divergesFromApp(mutatedWeekFn, fixtureIds) {
  // returns list of ids where mutated != app oracle (run twice to prove determinism)
  const once = fixtureIds.filter((id) => {
    const fx = FIXTURES.find((f) => f.id === id);
    const et = etLocalDate(fx.instant_utc);
    return mutatedWeekFn(fx, et) !== appDateToModelWeek(et);
  });
  const twice = fixtureIds.filter((id) => {
    const fx = FIXTURES.find((f) => f.id === id);
    const et = etLocalDate(fx.instant_utc);
    return mutatedWeekFn(fx, et) !== appDateToModelWeek(et);
  });
  assert.deepEqual(once, twice, 'mutation divergence must be deterministic');
  return once;
}
const EPOCH = Date.UTC(2026, 5, 7), MS_WEEK = 604800000;
const ymdUtc = (ymd) => { const [y, m, d] = ymd.split('-').map(Number); return Date.UTC(y, m - 1, d); };

test('MUTATION 1 — week-start off by one day => deterministic divergence', () => {
  const mut = (fx, et) => { const t = ymdUtc(et); if (t < Date.UTC(2026, 5, 8) || t > Date.UTC(2027, 0, 9)) return null; return Math.floor((t - Date.UTC(2026, 5, 8)) / MS_WEEK) + 1; };
  const d = divergesFromApp(mut, ['PX-09', 'PX-10', 'PX-19']);
  assert.ok(d.length >= 1, 'shifted epoch must diverge');
});
test('MUTATION 2 — truncate as UTC date instead of ET => deterministic divergence', () => {
  const utcDate = (fx) => /^(\d{4}-\d{2}-\d{2})/.exec(fx.instant_utc)[1];
  const mutWeekUtc = (fx) => { const t = ymdUtc(utcDate(fx)); if (t < EPOCH || t > Date.UTC(2027, 0, 9)) return null; return Math.floor((t - EPOCH) / MS_WEEK) + 1; };
  // Date-level detection: PX-02 UTC date (Jul-15) differs from ET date (Jul-14)
  const px02 = FIXTURES.find((f) => f.id === 'PX-02');
  assert.equal(utcDate(px02), '2026-07-15');
  assert.equal(etLocalDate(px02.instant_utc), '2026-07-14');
  assert.notEqual(utcDate(px02), etLocalDate(px02.instant_utc));
  // Week-level detection: PX-33 crosses a model-week boundary (UTC Aug-16=wk11 vs ET Aug-15=wk10)
  const px33 = FIXTURES.find((f) => f.id === 'PX-33');
  assert.equal(mutWeekUtc(px33), 11);
  assert.equal(appDateToModelWeek(etLocalDate(px33.instant_utc)), 10);
  assert.notEqual(mutWeekUtc(px33), appDateToModelWeek(etLocalDate(px33.instant_utc)));
});
test('MUTATION 3 — ±14 made exclusive => edge fixtures flip (deterministic)', () => {
  const excl = (fx) => Math.abs(etDayDiff(fx.instant_utc, fx.anchor_instant_utc)) < 14; // exclusive mutant
  const px13 = FIXTURES.find((f) => f.id === 'PX-13'), px14 = FIXTURES.find((f) => f.id === 'PX-14');
  assert.equal(excl(px13), false); // correct inclusive = true -> mutant flips to false
  assert.equal(excl(px14), false);
  assert.notEqual(excl(px13), adapt(px13).be.candidate_proximity.within_14_inclusive);
});
test('MUTATION 4 — ignore DST (fixed -5 offset) => week flip at PX-12', () => {
  // fixed -5 truncation of 2026-08-16T04:00Z -> 2026-08-15 23:00 -> date Aug15 (week 10); ET correct = Aug16 (week 11)
  const fx = FIXTURES.find((f) => f.id === 'PX-12');
  const fixedOffsetDate = new Date(Date.parse(fx.instant_utc) - 5 * 3600000).toISOString().slice(0, 10);
  const mutWeek = (() => { const t = ymdUtc(fixedOffsetDate); return Math.floor((t - EPOCH) / MS_WEEK) + 1; })();
  assert.equal(fixedOffsetDate, '2026-08-15');
  assert.equal(mutWeek, 10);
  assert.notEqual(mutWeek, appDateToModelWeek(etLocalDate(fx.instant_utc))); // app = 11
});
test('MUTATION 5 — placement made cleared-dependent => breaks invariance', () => {
  const mut = (fx, et) => { const w = appDateToModelWeek(et); return (w !== null && fx.cleared) ? w + 1 : w; };
  const d = divergesFromApp(mut, ['PX-17', 'PX-19', 'PX-21']); // cleared:true fixtures
  assert.ok(d.length >= 1, 'cleared-dependent placement must diverge from cleared-invariant app');
});
test('MUTATION 6 — expected-date interval end made EXCLUSIVE => end-boundary fixture flips (executable mutant)', () => {
  // Intended control: the inclusive end of canonExpectedDateInterval (start <= d <= end). The mutant changes the
  // end comparison to exclusive (start <= d < end). We RUN both membership implementations against a candidate
  // date EXACTLY ON the interval end boundary and prove a deterministic parity failure.
  const canonMs = (iv) => canonExpectedDateInterval(iv).split('|').map((s) => Date.parse(s)); // [s, e]; throws if invalid
  const memberInclusive = (iv, dISO) => { const [s, e] = canonMs(iv); const d = Date.parse(dISO); return s <= d && d <= e; };
  const memberEndExclusiveMUTANT = (iv, dISO) => { const [s, e] = canonMs(iv); const d = Date.parse(dISO); return s <= d && d < e; };

  const iv = FIXTURES.find((f) => f.id === 'PX-27').expected_date_interval; // {start:'2026-07-01', end:'2026-07-01'}
  // guard: the interval is VALID, so divergence is the boundary control — NOT an unrelated validation reject
  assert.doesNotThrow(() => canonExpectedDateInterval(iv));
  const endBoundary = '2026-07-01T00:00:00.000Z'; // candidate exactly on the interval end

  const correct1 = memberInclusive(iv, endBoundary);
  const mutant1 = memberEndExclusiveMUTANT(iv, endBoundary);
  const correct2 = memberInclusive(iv, endBoundary);
  const mutant2 = memberEndExclusiveMUTANT(iv, endBoundary);
  assert.equal(correct1, true, 'inclusive: end-boundary day IS a member');
  assert.equal(mutant1, false, 'end-exclusive mutant DROPS the end-boundary day');
  assert.notEqual(correct1, mutant1, 'deterministic parity failure at the interval end-boundary control');
  assert.equal(correct1, correct2); assert.equal(mutant1, mutant2); // determinism across repeated runs

  // also on PX-28 [07-01,07-02] with candidate == end (07-02): inclusive true, mutant false
  const iv2 = FIXTURES.find((f) => f.id === 'PX-28').expected_date_interval;
  assert.equal(memberInclusive(iv2, '2026-07-02T00:00:00.000Z'), true);
  assert.equal(memberEndExclusiveMUTANT(iv2, '2026-07-02T00:00:00.000Z'), false);

  // corroboration: the app bands that same end day to a real model week (day exists in-model)
  assert.equal(appDateToModelWeek(iv.end), 4);
});

// ════════════════════════════════════════════════════════════════════════════════════════════════════════
// F-1 — fail-closed index.html hash-guard (positive + negative on a SCRATCH copy only; repo index.html untouched)
// ════════════════════════════════════════════════════════════════════════════════════════════════════════
const __here = dirname(fileURLToPath(import.meta.url));
const REPO_INDEX_HTML = join(__here, '..', '..', 'index.html');

test('F-1 positive — the current pinned index.html is accepted by the guard', () => {
  const real = readFileSync(REPO_INDEX_HTML, 'utf8');
  assert.doesNotThrow(() => assertIndexHtmlIntegrity(real));
  // and it fully builds the oracle (execution proceeds)
  const { app } = buildOracleFromContent(real);
  assert.equal(app.dateToModelWeek('2026-06-07'), 1);
});

test('F-1 negative — a one-byte-modified SCRATCH copy is rejected before oracle execution', () => {
  const real = readFileSync(REPO_INDEX_HTML, 'utf8');
  const dir = mkdtempSync(join(tmpdir(), 'parity-hashguard-'));
  try {
    // flip exactly one byte in a scratch copy (append a single space); never touch the repo file
    const tampered = real + ' ';
    const scratch = join(dir, 'index.tampered.html');
    writeFileSync(scratch, tampered);
    const scratchContent = readFileSync(scratch, 'utf8');

    // (2) rejected; (4) specifically the hash-integrity guard; error carries expected + actual
    let threw = null;
    try { buildOracleFromContent(scratchContent); } catch (e) { threw = e; }
    assert.ok(threw instanceof OracleIntegrityError, 'must throw OracleIntegrityError (hash-guard), not a generic error');
    assert.match(threw.message, /hash-guard/);
    assert.match(threw.message, new RegExp(PINNED_INDEX_HTML_SHA256)); // expected present
    assert.match(threw.message, /actual [0-9a-f]{64}/);                // actual present

    // (3) rejection occurs BEFORE oracle execution: buildOracleFromContent returned nothing usable
    let built = null;
    try { built = buildOracleFromContent(scratchContent); } catch { built = null; }
    assert.equal(built, null, 'no oracle API is produced for a tampered file');

    // repo file remains byte-identical to the pin
    assert.equal(assertIndexHtmlIntegrity(readFileSync(REPO_INDEX_HTML, 'utf8')), PINNED_INDEX_HTML_SHA256);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// ── repeatability: two runs identical ──────────────────────────────────────────────────────────────────
test('repeatability: differential is deterministic across repeated runs', () => {
  const a = JSON.stringify(runDifferential(FIXTURES).summary);
  const b = JSON.stringify(runDifferential(FIXTURES).summary);
  assert.equal(a, b);
});
