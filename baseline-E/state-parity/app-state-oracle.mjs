// baseline-E/state-parity/app-state-oracle.mjs
// ORACLE (not adapter). Read-only. Executes the *verbatim* Financial-OS state-resolution functions extracted
// from index.html — the capacity-relevant resolution layer, NOT the full WD projection (see the boundary note).
//
// Extracted verbatim (brace-matched):
//   - getCashAvailabilityEngine(actualBalanceCents, floorCents, commitments, sourceAccount, modelWeekNum)  [~2453]
//   - isReservedAsOf(c, weekNum)                                                                            [~2438]
//   - authoritativeCurrentChk(num, projectedChk)                                                            [~1756]
//   - isWeekReconciled(weekNum)                                                                             [~1043]
// Verbatim constant lines: OP_FL/MIN_XFR/AK_START [~896], PLAN_YEAR [~902], START_* [~889].
//
// BOUNDARY (documented, honest): the app's projected checking for an UNRECONCILED week is produced by the full
// runModel() WD forward simulation, which depends on dozens of module globals (WD, overrideData, budgetRules,
// GOALS_REGISTRY, waterfalls, action overrides, …) and is NOT extracted. This oracle takes the projected checking
// as an INPUT to the resolution layer — exactly how runModel passes `chk` into the engine. This gate tests state
// RESOLUTION (reconciled-vs-projected precedence, commitment reservation, capacity inputs), not re-derivation of
// the projection. `isReservedAsOf` + `getCashAvailabilityEngine` + `authoritativeCurrentChk` are the entire
// capacity-input resolution surface and ARE extracted and executed verbatim.
//
// F-1 fail-closed integrity: the pinned index.html hash is enforced (reusing app-oracle.mjs's guard) BEFORE any
// extraction. No network, no Supabase, no writes, no clock/timezone dependence (these functions use neither).
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { assertIndexHtmlIntegrity, PINNED_INDEX_HTML_SHA256 } from '../parity/app-oracle.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const INDEX_HTML = join(HERE, '..', '..', 'index.html');

export class StateOracleError extends Error {}
const sha256 = (s) => createHash('sha256').update(s, 'utf8').digest('hex');

function extractFunction(src, name) {
  const sig = `function ${name}(`;
  const start = src.indexOf(sig);
  if (start < 0) throw new StateOracleError(`cannot locate function ${name}() in index.html`);
  const braceOpen = src.indexOf('{', start);
  let depth = 0;
  for (let i = braceOpen; i < src.length; i++) {
    const c = src[i];
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return src.slice(start, i + 1); }
  }
  throw new StateOracleError(`unbalanced braces extracting ${name}()`);
}
function extractLine(src, re, label) {
  const m = re.exec(src);
  if (!m) throw new StateOracleError(`cannot locate ${label} in index.html`);
  return m[0];
}

const html = readFileSync(INDEX_HTML, 'utf8');
assertIndexHtmlIntegrity(html); // F-1: fail-closed BEFORE extraction (throws OracleIntegrityError on drift)

const SRC = {
  CONST_MONEY:  extractLine(html, /const START_CHK=18037\.73,START_SAV=3772\.77,START_AMX=103\.64,START_TAX=0,START_LC=13488\.88;/, 'START_* consts'),
  CONST_FLOOR:  extractLine(html, /const OP_FL=6500,MIN_XFR=100,AK_START=5;/, 'OP_FL/MIN_XFR/AK_START'),
  CONST_YEAR:   extractLine(html, /const PLAN_YEAR=2026;/, 'PLAN_YEAR'),
  isWeekReconciled:          extractFunction(html, 'isWeekReconciled'),
  authoritativeCurrentChk:   extractFunction(html, 'authoritativeCurrentChk'),
  isReservedAsOf:            extractFunction(html, 'isReservedAsOf'),
  getCashAvailabilityEngine: extractFunction(html, 'getCashAvailabilityEngine'),
};

export const EXTRACTION = {
  index_html_sha256: sha256(html),
  pinned_index_html_sha256: PINNED_INDEX_HTML_SHA256,
  fragments: Object.fromEntries(Object.entries(SRC).map(([k, v]) => [k, { sha256: sha256(v), source: v }])),
};

// Verbatim constants (evaluated from the extracted const lines — no hand-typed values).
const CONSTS = (new Function(SRC.CONST_MONEY + '\n' + SRC.CONST_FLOOR + '\n' + SRC.CONST_YEAR +
  '\n return {START_CHK,START_SAV,START_AMX,START_TAX,START_LC,OP_FL,MIN_XFR,AK_START,PLAN_YEAR};'))();
export const APP_CONSTS = CONSTS;

// Build the resolution functions bound to a caller-supplied reconData + PLAN_YEAR. The extracted bodies reference
// `reconData` and `PLAN_YEAR` as free variables; here they resolve to the factory params — so each call executes
// the VERBATIM app logic against the fixture's state. Rebuilt per fixture (cheap) to bind that fixture's reconData.
const factoryBody =
  SRC.isWeekReconciled + '\n' + SRC.authoritativeCurrentChk + '\n' + SRC.isReservedAsOf + '\n' + SRC.getCashAvailabilityEngine + '\n' +
  'return { isWeekReconciled, authoritativeCurrentChk, isReservedAsOf, getCashAvailabilityEngine };';
// eslint-disable-next-line no-new-func
const RESOLVER_FACTORY = new Function('PLAN_YEAR', 'reconData', factoryBody);

// Returns the four verbatim resolvers bound to `reconData` (a {weekNum:{chk,sav,amx,tax,lc,balance_basis}} map).
export function resolversFor(reconData) {
  if (reconData === null || typeof reconData !== 'object') throw new StateOracleError('resolversFor: reconData must be an object map');
  return RESOLVER_FACTORY(CONSTS.PLAN_YEAR, reconData);
}
