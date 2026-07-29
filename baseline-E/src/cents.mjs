// baseline-E/src/cents.mjs
// Design ref: spec §8 (exact decimal-string → integer-cents contract) + §2 "all monetary values: integer cents".
// Dependency-free. No float×100. All amounts flow as integer cents everywhere downstream.

export class MoneyError extends Error {}

// Canonical signed decimal token: optional leading '-', integer part, optional 1–2 fractional digits.
// Rejects: >2 fractional digits, exponent notation, thousands separators, NaN/Infinity, empty, locale commas.
const MONEY_RE = /^(-?)(\d+)(?:\.(\d{1,2}))?$/;

// Parse a canonical decimal STRING token into exact integer cents.
export function parseMoneyToken(token, { field = 'amount', allowNegative = false } = {}) {
  if (typeof token !== 'string') throw new MoneyError(`${field}: expected decimal string token, got ${typeof token}`);
  const s = token.trim();
  if (s === '') throw new MoneyError(`${field}: empty token`);
  if (/[eE]/.test(s)) throw new MoneyError(`${field}: exponent notation rejected ("${s}")`);
  const m = MONEY_RE.exec(s);
  if (!m) throw new MoneyError(`${field}: malformed or >2-decimal currency token ("${s}")`);
  const neg = m[1] === '-';
  if (neg && !allowNegative) throw new MoneyError(`${field}: negative not allowed by field contract ("${s}")`);
  const intPart = m[2];
  const fracPart = (m[3] ?? '').padEnd(2, '0'); // 1 dp → pad to 2; 0 dp → "00" — exact, no rounding
  const cents = Number(intPart) * 100 + Number(fracPart);
  if (!Number.isSafeInteger(cents)) throw new MoneyError(`${field}: amount out of safe-integer range ("${s}")`);
  return neg ? -cents : cents;
}

// §8 alternative path: a value that can only be obtained as a JS number is canonicalized fail-closed by
// routing it through its own decimal token — never value×100. 0.1+0.2 → "0.30000000000000004" → >2dp → reject.
export function canonicalizeNumberToCents(num, opts = {}) {
  const field = opts.field ?? 'amount';
  if (typeof num !== 'number' || !Number.isFinite(num)) throw new MoneyError(`${field}: non-finite / non-number rejected`);
  const s = String(num);
  if (/[eE]/.test(s)) throw new MoneyError(`${field}: exponent-form number rejected (${s})`);
  return parseMoneyToken(s, opts);
}

// events_json amount canonicalization (§8): PREFERRED path = raw decimal token (string); a parsed PostgREST
// number is accepted only via the fail-closed number canonicalizer. Returns {cents, path} for audit.
export function canonicalizeEventsJsonAmount(raw, opts = {}) {
  const field = opts.field ?? 'events_json.amount';
  if (typeof raw === 'string') return { cents: parseMoneyToken(raw, { ...opts, field }), path: 'decimal_token' };
  if (typeof raw === 'number') return { cents: canonicalizeNumberToCents(raw, { ...opts, field }), path: 'js_number_canonicalized' };
  throw new MoneyError(`${field}: unsupported raw amount type ${typeof raw}`);
}

export const isIntegerCents = (v) => Number.isInteger(v) && Number.isSafeInteger(v);
