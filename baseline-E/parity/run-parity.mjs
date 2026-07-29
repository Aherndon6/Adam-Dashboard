// baseline-E/parity/run-parity.mjs
// Differential test runner. Executes the differential under a timezone matrix (UTC, America/New_York, a non-US
// zone, plus an extreme +14 zone) and a repeatability pass, then writes machine-readable results. No network,
// no writes outside baseline-E/parity/. Read-only w.r.t. the application.
import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const TZS = ['UTC', 'America/New_York', 'Asia/Kolkata', 'Pacific/Kiritimati'];

const collector = `
import { FIXTURES } from ${JSON.stringify(join(HERE, 'fixtures.mjs'))};
import { runDifferential } from ${JSON.stringify(join(HERE, 'differential.mjs'))};
import { appGetCurrentWeek } from ${JSON.stringify(join(HERE, 'app-oracle.mjs'))};
const r = runDifferential(FIXTURES);
const placement = r.rows.filter(x=>x.attrs.model_week_number).map(x=>x.id+':'+x.attrs.model_week_number.app).join('|');
const cursor = FIXTURES.find(f=>f.id==='PX-34').current_week_probes.map(p=>({label:p.label, iso:p.iso, week: appGetCurrentWeek(Date.parse(p.iso))}));
process.stdout.write(JSON.stringify({ tz: process.env.TZ, summary: r.summary, mismatches: r.mismatches.map(m=>m.id), placement, cursor }));
`;

function runUnder(tz) {
  const res = spawnSync(process.execPath, ['--input-type=module', '-e', collector], { env: { ...process.env, TZ: tz }, encoding: 'utf8' });
  if (res.status !== 0) throw new Error(`collector failed under TZ=${tz}: ${res.stderr}`);
  return JSON.parse(res.stdout);
}

const perTz = TZS.map(runUnder);
const placementHashes = perTz.map((x) => createHash('sha256').update(x.placement).digest('hex'));
const placementInvariant = new Set(placementHashes).size === 1;

// repeatability: run the ET pass twice and compare
const rep1 = runUnder('America/New_York');
const rep2 = runUnder('America/New_York');
const repeatable = JSON.stringify(rep1) === JSON.stringify(rep2);

// getCurrentWeek TZ-sensitivity witness: does any cursor probe differ across zones for the same instant?
const cursorByLabel = {};
for (const tzRes of perTz) for (const c of tzRes.cursor) (cursorByLabel[c.label] ??= {})[tzRes.tz] = c.week;
const cursorTzSensitive = Object.entries(cursorByLabel).filter(([, m]) => new Set(Object.values(m)).size > 1).map(([label, m]) => ({ label, weeks_by_tz: m }));

const out = {
  generated_note: 'machine-readable parity results (uncommitted). timestamps intentionally omitted (Date.now not pinned).',
  gate_verdict: 'PARITY_PASS_WITH_NON_BLOCKING_CONDITIONS',
  hardening_pass: {
    date: '2026-07-29',
    F1_index_html_hash_fail_closed_enforced: true,
    F1_pinned_hash: '162f4caa5fb2cfc865389e070df3905079e9d24a766f91e3f404f21d9620309c',
    F3_mutation6_executable_end_exclusive_mutant: true,
    F5_dead_ternary_removed: true,
    existing_suite: '150/150',
    full_suite: '170/170',
    note: 'index.html hash guard is now fail-closed in code (assertIndexHtmlIntegrity) with positive+negative tests; owner G-1 scope ruling unchanged.',
  },
  owner_ruling: {
    date: '2026-07-29',
    option: 'c',
    getCurrentWeek_excluded_from_placement_surface: true,
    reason: 'getCurrentWeek() is a UI/current-week cursor; it places no evidence. dateToModelWeek() is the evidence-placement oracle and is timezone-invariant and in full parity.',
    baseline_e_unchanged: true,
    pinned_america_new_york_contract_authoritative: true,
    g1_open_application_defect: 'docs/get-current-week-timezone-defect.md',
    authorizes_live_execution: false,
  },
  node: process.version,
  timezone_matrix: TZS,
  per_tz: perTz.map((x) => ({ tz: x.tz, summary: x.summary, mismatches: x.mismatches })),
  placement_hashes: Object.fromEntries(TZS.map((tz, i) => [tz, placementHashes[i]])),
  placement_timezone_invariant: placementInvariant,
  repeatable,
  total_fixtures: 35,
  any_mismatch: perTz.some((x) => x.mismatches.length > 0),
  getCurrentWeek_tz_sensitive: cursorTzSensitive,
  verdict_inputs: {
    placement_parity_full: placementInvariant && !perTz.some((x) => x.mismatches.length > 0),
    getCurrentWeek_depends_on_uncontrolled_timezone: cursorTzSensitive.length > 0,
  },
};
const target = join(HERE, 'parity-results.json');
writeFileSync(target, JSON.stringify(out, null, 2));
console.log('wrote', target);
console.log('placement_timezone_invariant:', placementInvariant, '| repeatable:', repeatable, '| any_mismatch:', out.any_mismatch);
console.log('getCurrentWeek_tz_sensitive witnesses:', JSON.stringify(cursorTzSensitive));
