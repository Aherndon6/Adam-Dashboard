// baseline-E/parity/app-oracle.mjs
// ORACLE (not adapter). Read-only. Executes the *verbatim* Financial-OS runtime date/model-week functions
// extracted from index.html, inside a sandbox whose only injected dependency is a controllable `Date` (so the
// system clock and the process timezone are the only environmental inputs, and both are pinned by the caller).
//
// It does NOT reimplement application logic: the function bodies below are lifted byte-for-byte from index.html
// via brace-matching, then instantiated with `new Function('Date', <verbatim source>)`. If the extraction cannot
// isolate the exact source, this module THROWS (Phase-1/Phase-2 hard-stop: "cannot isolate without guessing").
//
// F-1 (fail-closed integrity): before ANY extraction or execution, the whole index.html SHA-256 is compared to the
// pinned starting-state hash and a mismatch throws OracleIntegrityError. A drifted index.html is never oracled.
//
// Restrictions honored: no writes, no network, no Supabase, no state mutation, does NOT read the system clock
// (getCurrentWeek's `new Date()` is redirected to a caller-pinned instant), does NOT depend on the machine's
// local timezone for correctness (the process TZ is an *input* the differential harness varies deliberately).
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const INDEX_HTML = join(HERE, '..', '..', 'index.html');

// Pinned starting-state hash of index.html (Step-8 before-live gate). Fail-closed against drift.
export const PINNED_INDEX_HTML_SHA256 = '162f4caa5fb2cfc865389e070df3905079e9d24a766f91e3f404f21d9620309c';

export class OracleExtractionError extends Error {}
export class OracleIntegrityError extends Error {}

const sha256 = (s) => createHash('sha256').update(s, 'utf8').digest('hex');

// F-1 fail-closed guard. Pure: computes the hash of `content` and throws if it is not the pinned value. Callers
// MUST invoke this before extraction/execution. Error carries BOTH expected and actual hashes.
export function assertIndexHtmlIntegrity(content, expected = PINNED_INDEX_HTML_SHA256) {
  if (typeof content !== 'string') throw new OracleIntegrityError('index.html integrity: content is not a string');
  const actual = sha256(content);
  if (actual !== expected) {
    throw new OracleIntegrityError(`index.html integrity FAIL (hash-guard): expected ${expected}, actual ${actual}`);
  }
  return actual;
}

// Brace-matched extraction of `function <name>(...){ ... }` from a source string. Verbatim; no edits.
function extractFunction(src, name) {
  const sig = `function ${name}(`;
  const start = src.indexOf(sig);
  if (start < 0) throw new OracleExtractionError(`cannot locate function ${name}() in index.html`);
  const braceOpen = src.indexOf('{', start);
  if (braceOpen < 0) throw new OracleExtractionError(`no body open-brace for ${name}()`);
  let depth = 0;
  for (let i = braceOpen; i < src.length; i++) {
    const c = src[i];
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return src.slice(start, i + 1); }
  }
  throw new OracleExtractionError(`unbalanced braces extracting ${name}()`);
}

function extractLine(src, re, label) {
  const m = re.exec(src);
  if (!m) throw new OracleExtractionError(`cannot locate ${label} in index.html`);
  return m[0];
}

// ── sandbox Date: no-arg `new Date()` returns a caller-pinned instant; all other forms delegate to real Date ──
let __PINNED_NOW_MS = null;
class SandboxDate extends Date {
  constructor(...args) {
    if (args.length === 0) {
      if (__PINNED_NOW_MS === null) throw new OracleExtractionError('oracle: getCurrentWeek() read the clock but no pinned now was set');
      super(__PINNED_NOW_MS);
    } else super(...args);
  }
  static now() { if (__PINNED_NOW_MS === null) throw new OracleExtractionError('oracle: Date.now() with no pinned now'); return __PINNED_NOW_MS; }
}

// Extract the verbatim fragments from `content` and build the sandboxed function set. Callers MUST have already
// passed `content` through assertIndexHtmlIntegrity() — buildOracleFromContent() enforces that ordering.
function extractAndBuild(content) {
  const SRC = {
    _BR_START:        extractLine(content, /var _BR_START=new Date\(2026,5,7,12,0,0\);/, 'const _BR_START'),
    _BR_END:          extractLine(content, /var _BR_END {2}=new Date\(2027,0,9,12,0,0\);/, 'const _BR_END'),
    _BR_END_STR:      extractLine(content, /var _BR_END_STR='2027-01-09';/, 'const _BR_END_STR'),
    isValidISODate:   extractFunction(content, 'isValidISODate'),
    dateToModelWeek:  extractFunction(content, 'dateToModelWeek'),
    getWeekStartDate: extractFunction(content, 'getWeekStartDate'),
    getCurrentWeek:   extractFunction(content, 'getCurrentWeek'),
  };
  const extraction = {
    index_html_sha256: sha256(content),
    fragments: Object.fromEntries(Object.entries(SRC).map(([k, v]) => [k, { sha256: sha256(v), source: v }])),
  };
  const factoryBody =
    SRC._BR_START + '\n' + SRC._BR_END + '\n' + SRC._BR_END_STR + '\n' +
    SRC.isValidISODate + '\n' + SRC.dateToModelWeek + '\n' + SRC.getWeekStartDate + '\n' + SRC.getCurrentWeek + '\n' +
    'return { dateToModelWeek, getWeekStartDate, getCurrentWeek, isValidISODate, _BR_START, _BR_END, _BR_END_STR };';
  // eslint-disable-next-line no-new-func
  const app = (new Function('Date', factoryBody))(SandboxDate);
  return { app, extraction };
}

// Public builder used by tests: fail-closed guard FIRST, then extraction/execution. A tampered `content` throws
// OracleIntegrityError before any function is extracted or run (proving rejection precedes oracle execution).
export function buildOracleFromContent(content, expected = PINNED_INDEX_HTML_SHA256) {
  assertIndexHtmlIntegrity(content, expected);
  return extractAndBuild(content);
}

// ── load-time singleton: read → GUARD (fail-closed) → extract/build ─────────────────────────────────────────
const html = readFileSync(INDEX_HTML, 'utf8');
assertIndexHtmlIntegrity(html);              // F-1: throws before extractAndBuild if index.html drifted
const { app: APP, extraction: EXTRACTION_INTERNAL } = extractAndBuild(html);

export const EXTRACTION = EXTRACTION_INTERNAL;

// ── public oracle surface (each call is pure w.r.t. its inputs; process TZ is an explicit environmental input) ──
export function appDateToModelWeek(ymd) { return APP.dateToModelWeek(ymd); }        // 'YYYY-MM-DD' -> week|null
export function appIsValidISODate(s) { return APP.isValidISODate(s); }             // -> boolean
export function appGetWeekStartDate(n) { return APP.getWeekStartDate(n); }         // -> Date (process-local)
export function appGetCurrentWeek(pinnedNowMs) {                                   // clock+TZ dependent (BY DESIGN of the app)
  if (!Number.isFinite(pinnedNowMs)) throw new OracleExtractionError('appGetCurrentWeek: pinnedNowMs must be a finite epoch-ms');
  __PINNED_NOW_MS = pinnedNowMs;
  try { return APP.getCurrentWeek(); } finally { __PINNED_NOW_MS = null; }
}
export const APP_BAND = { start: APP._BR_START.getTime(), end: APP._BR_END.getTime(), end_str: APP._BR_END_STR };
