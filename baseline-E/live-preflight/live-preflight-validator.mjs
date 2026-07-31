// baseline-E/live-preflight/live-preflight-validator.mjs
// Orchestrates the fail-closed preflight with a CONTROL-FLOW ADMISSIBILITY INVARIANT (meta-control): a package may
// be admissible ONLY after every required blocking control has executed exactly once, none HOLD/FAIL_STOP, and no
// alternate/early-return/caller-supplied path is used. `mut` injects control breaks (including validator-flow bugs).
import { REQUIRED_SECTIONS, CONTRACT_VERSION } from './live-preflight-contract.mjs';
import { CONTROLS } from './live-preflight-controls.mjs';

const RANK = { PASS: 0, HOLD: 1, FAIL_STOP: 2 };
export const REQUIRED_CONTROL_IDS = CONTROLS.map((c) => c.key);

export function validatePackage(pkg, mut = {}) {
  const declaredVersion = (pkg && pkg.package_manifest && pkg.package_manifest.contract_version) || null;
  const versionOk = declaredVersion === CONTRACT_VERSION;
  const missingSecs = REQUIRED_SECTIONS.filter((s) => pkg == null || pkg[s] === undefined || pkg[s] === null);
  const sectionsPresent = missingSecs.length === 0;

  const control_results = [];
  control_results.push({ key: 'contract_version_supported', id: 'CV', disposition: versionOk ? 'PASS' : 'FAIL_STOP', reason_code: versionOk ? null : 'CV_UNSUPPORTED_CONTRACT_VERSION', detail: declaredVersion });
  control_results.push({ key: 'required_sections_present', id: 'SEC', disposition: sectionsPresent ? 'PASS' : 'FAIL_STOP', reason_code: sectionsPresent ? null : 'SEC_MISSING_REQUIRED_SECTION', detail: missingSecs });

  const executed = [];
  if (versionOk && sectionsPresent) {
    for (const c of CONTROLS) {
      if (mut.earlyReturnBeforeControl === c.key) break;   // BUG: alternate early-success path (skips the tail)
      if (mut.skipControl === c.key) continue;             // BUG: a required control is omitted
      let r; try { r = c.fn(pkg, mut); } catch (e) { r = { id: c.key, disposition: 'FAIL_STOP', reason_code: 'CONTROL_THREW', detail: String(e && e.message) }; }
      control_results.push({ key: c.key, id: r.id, disposition: r.disposition, reason_code: r.reason_code ?? null, detail: r.detail ?? null });
      executed.push(c.key);
    }
    if (mut.injectDuplicatePass) { control_results.push({ key: mut.injectDuplicatePass, id: 'DUP', disposition: 'PASS', reason_code: null }); executed.push(mut.injectDuplicatePass); }
    if (mut.injectUnknownPass) { control_results.push({ key: '__unknown_control__', id: 'UNK', disposition: 'PASS', reason_code: null }); executed.push('__unknown_control__'); }
  }

  // ── META control-flow invariant ─────────────────────────────────────────────────────────────────────────
  const missingControls = (versionOk && sectionsPresent) ? REQUIRED_CONTROL_IDS.filter((id) => !executed.includes(id)) : [];
  const seenCount = new Map(); for (const k of executed) seenCount.set(k, (seenCount.get(k) ?? 0) + 1);
  const duplicateControls = [...seenCount].filter(([, n]) => n > 1).map(([k]) => k);
  const unknownControls = executed.filter((k) => !REQUIRED_CONTROL_IDS.includes(k));
  const metaAnomaly = missingControls.length ? 'META_REQUIRED_CONTROL_MISSING' : duplicateControls.length ? 'META_DUPLICATE_CONTROL_RESULT' : unknownControls.length ? 'META_UNKNOWN_CONTROL_RESULT' : null;
  const metaOk = mut.metaBlind ? true : (metaAnomaly == null);
  if (versionOk && sectionsPresent && !mut.metaBlind && metaAnomaly) control_results.push({ key: 'META', id: 'META', disposition: 'FAIL_STOP', reason_code: metaAnomaly, detail: { missingControls, duplicateControls, unknownControls } });

  const worst = control_results.reduce((w, r) => (RANK[r.disposition] > RANK[w] ? r.disposition : w), 'PASS');
  const allPass = control_results.every((r) => r.disposition === 'PASS');
  // Admissibility is DERIVED ONLY from the complete control-result set + the meta invariant. Caller-supplied
  // admissibility and HOLD-promotion are BUGS the mutations simulate; the correct validator never trusts them.
  let package_admissible;
  if (mut.callerAdmissible) package_admissible = true;   // BUG: META_CALLER_SUPPLIED_ADMISSIBILITY
  else if (mut.holdToPass) package_admissible = true;    // BUG: promote a HOLD to PASS
  else package_admissible = versionOk && sectionsPresent && metaOk && allPass;

  const alternate_success_path_detected = !!(mut.callerAdmissible || mut.holdToPass || mut.earlyReturnBeforeControl || mut.skipControl || mut.metaBlind);

  return {
    contract_version: CONTRACT_VERSION,
    declared_contract_version: declaredVersion,
    required_sections_present: sectionsPresent,
    missing_sections: missingSecs,
    control_results,
    worst_disposition: worst,
    package_admissible,
    holds: control_results.filter((r) => r.disposition === 'HOLD').map((r) => r.reason_code),
    fail_stops: control_results.filter((r) => r.disposition === 'FAIL_STOP').map((r) => r.reason_code),
    // meta-control evidence
    required_control_ids: REQUIRED_CONTROL_IDS,
    executed_control_ids: executed,
    missing_control_ids: missingControls,
    duplicate_control_ids: duplicateControls,
    unknown_control_ids: unknownControls,
    all_required_controls_executed: missingControls.length === 0 && duplicateControls.length === 0 && unknownControls.length === 0,
    control_flow_complete: metaOk && missingControls.length === 0,
    admissibility_derived_only: !(mut.callerAdmissible || mut.holdToPass),
    alternate_success_path_detected,
  };
}

export function controlBooleans(result) {
  const b = {};
  for (const r of result.control_results) b[r.key] = r.disposition === 'PASS';
  return b;
}
