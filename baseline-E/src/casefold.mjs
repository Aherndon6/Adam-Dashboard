// baseline-E/src/casefold.mjs
// rev-6.1 §C.4 (owner Option-1 ruling): Unicode 15.1.0 FULL case folding via the repository-pinned generated
// table — NOT String.prototype.toLowerCase(), NOT simple folding, NOT the runtime ICU (Node's runtime Unicode
// may differ; the pinned table is authoritative). Deterministic; dependency-free.
import { CASEFOLD_TABLE, CASEFOLD_UNICODE_VERSION, CASEFOLD_SOURCE_SHA256, CASEFOLD_GENERATOR_VERSION } from './casefold-table-15.1.0.mjs';

export { CASEFOLD_UNICODE_VERSION, CASEFOLD_SOURCE_SHA256, CASEFOLD_GENERATOR_VERSION };

// Apply Unicode 15.1.0 default full case folding, code point by code point, from the pinned table.
// No pre/post normalization here (callers apply NFC before folding per the frozen operation).
export function fullCaseFold(s) {
  if (typeof s !== 'string') throw new TypeError('fullCaseFold: expected string');
  let out = '';
  for (const ch of s) {                 // iterates by code point
    const cp = ch.codePointAt(0);
    const m = CASEFOLD_TABLE[cp];
    out += m ? String.fromCodePoint(...m) : ch;
  }
  return out;
}
