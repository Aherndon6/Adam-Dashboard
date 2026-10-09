// ════════════════════════════════════════════════════════════════════════════
// R-lite V1 — Statement Compare (owner authorization 2026-10-09; design locked in docs/r-lite-design-proposal.md §23).
//
// Compares one bank download (OFX/QFX) with the selected account's COMPLETE Register history and lists matches and
// exceptions for the owner to review. Assistance only: it never writes anything (no Register Add/Edit/Delete/Cleared,
// no category, no reconciliation state), never certifies, and the existing reconciliation process stays authoritative.
// The file is parsed in this browser, in memory; nothing is uploaded or logged. The only thing kept is the per-account
// last-4 binding in this browser's storage (a convenience; the owner confirms every import).
// Sections: DOMAIN (pure, exported, unit-tested) · DATA (read-only view of the loaded Register) · VIEW (DOM).
// ════════════════════════════════════════════════════════════════════════════

// ── DOMAIN ──────────────────────────────────────────────────────────────────
export const RLITE_BEFORE_DAYS = 4;   // Register date may be up to 4 days before the bank posting date …
export const RLITE_AFTER_DAYS = 3;    // … and up to 3 days after it (evidence: docs §22.3)
export const RLITE_GUARD_DAYS = 7;    // repeated-amount veto (§23 F)
export const RLITE_HINT_DAYS = 15;    // "possible counterpart outside the window" hint for BANK ONLY rows (evidence only)
export const RLITE_MAX_BYTES = 2 * 1024 * 1024;
export const RLITE_ACCOUNTS = ['truist_checking', 'amex_gold', 'amex_platinum', 'costco_visa', 'chase_disney_visa'];

// Exact money: "-84.22" → -8422. Up to two decimals, no exponent, no separators; anything else → null.
export function toCents(s) {
  if (typeof s !== 'string' && typeof s !== 'number') return null;
  const m = /^\s*([+-]?)(\d+)(?:\.(\d{1,2}))?\s*$/.exec(String(s));
  if (!m) return null;
  const v = parseInt(m[2], 10) * 100 + parseInt((m[3] || '').padEnd(2, '0') || '0', 10);
  if (!Number.isSafeInteger(v)) return null;
  return m[1] === '-' ? -v : v;
}
function ofxDate(v) {   // the first 8 digits (YYYYMMDD) of an OFX date; time and zone ignored
  const m = /^(\d{4})(\d{2})(\d{2})/.exec(String(v == null ? '' : v).trim());
  if (!m) return null;
  const y = +m[1], mo = +m[2], d = +m[3], dt = new Date(Date.UTC(y, mo - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null;
  return m[1] + '-' + m[2] + '-' + m[3];
}
function decode(s) {
  return String(s).replace(/&#x([0-9a-f]+);/gi, (m, h) => String.fromCharCode(parseInt(h, 16))).replace(/&#(\d+);/g, (m, d) => String.fromCharCode(+d))
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}

// Parse one OFX 1.x (SGML) or 2.x (XML) bank/card download. All-or-nothing: {ok:false, reason} or {ok:true, file}.
export function parseOfx(text) {
  const fail = reason => ({ ok: false, reason });
  const t = String(text == null ? '' : text).replace(/^﻿/, '');
  if (!t.trim()) return fail('The file is empty.');
  const head = t.slice(0, 4096);
  if (/<!doctype\s+html|<html[\s>]|<head[\s>]|<body[\s>]/i.test(head))
    return fail('This is a web page (HTML), not a bank download — the bank may have shown an error or sign-in page. Download the file again.');
  const version = /^\s*OFXHEADER:\s*100/m.test(head) ? '1' : /<\?OFX[^>]*OFXHEADER\s*=\s*"200"/i.test(head) ? '2' : null;
  const start = t.search(/<OFX>/i);
  if (!version || start < 0) return fail('This isn\'t an OFX/QFX bank download.');
  const tokens = [...t.slice(start).matchAll(/<(\/?)([A-Za-z0-9.]+)>([^<]*)/g)].map(m => ({ close: !!m[1], tag: m[2].toUpperCase(), val: m[3].trim() }));
  if (tokens.some(x => !x.close && x.tag === 'CODE' && x.val !== '' && x.val !== '0')) return fail('The bank file reports an error status. Download the file again.');
  const has = tag => tokens.some(x => !x.close && x.tag === tag);
  const isBank = has('BANKMSGSRSV1'), isCard = has('CREDITCARDMSGSRSV1');
  if (isBank === isCard) return fail('The file must hold exactly one bank or credit-card statement.');
  if (tokens.filter(x => !x.close && (x.tag === 'STMTRS' || x.tag === 'CCSTMTRS')).length !== 1) return fail('The file must hold exactly one statement (one account).');

  const raws = [], acctIds = new Set(), notices = [];
  let cur = null, inBal = false, acctType = null, org = null, dtStart = null, dtEnd = null, balAmt = null, balAsOf = null, balSeen = false, nested = 0;
  const finish = () => { if (cur) raws.push(cur); cur = null; nested = 0; };
  for (const x of tokens) {
    if (x.tag === 'STMTTRN') { if (x.close) finish(); else { finish(); cur = {}; } continue; }
    if (x.close && x.tag === 'BANKTRANLIST') { finish(); continue; }
    if (cur) {
      if (/^(BANKACCTTO|CCACCTTO|PAYEE)$/.test(x.tag)) nested += x.close ? -1 : 1;
      else if (!x.close && !nested && x.val && cur[x.tag] === undefined) cur[x.tag] = x.val;
      continue;
    }
    if (x.tag === 'LEDGERBAL') { inBal = !x.close; if (!x.close) balSeen = true; continue; }
    if (x.close) continue;
    if (x.tag === 'ACCTID' && x.val) acctIds.add(x.val);
    else if (x.tag === 'ACCTTYPE') acctType = x.val.toUpperCase();
    else if (x.tag === 'ORG') org = decode(x.val);
    else if (x.tag === 'DTSTART') dtStart = ofxDate(x.val);
    else if (x.tag === 'DTEND') dtEnd = ofxDate(x.val);
    else if (inBal && x.tag === 'BALAMT') balAmt = x.val;
    else if (inBal && x.tag === 'DTASOF') balAsOf = x.val;
  }
  finish();
  if (acctIds.size !== 1) return fail('The file must name exactly one account.');
  const digits = [...acctIds][0].replace(/\D/g, '');
  if (digits.length < 4) return fail('The file\'s account number can\'t be identified.');
  const kind = isCard ? 'credit_card' : ({ CHECKING: 'checking', SAVINGS: 'savings', CREDITLINE: 'credit_card' })[acctType];
  if (!kind) return fail('This account type isn\'t supported by Statement Compare.');

  const rows = [], seen = new Map();
  for (const r of raws) {
    if (!r.FITID) return fail('A transaction in the file has no ID (FITID). Nothing was compared.');
    const cents = toCents(r.TRNAMT);
    if (cents === null) return fail('A transaction amount in the file can\'t be read. Nothing was compared.');
    if (cents === 0) return fail('A transaction in the file has a zero amount. Nothing was compared.');
    const posted = ofxDate(r.DTPOSTED);
    if (!posted) return fail('A transaction date in the file is missing or invalid. Nothing was compared.');
    const sig = JSON.stringify(r);
    if (seen.has(r.FITID)) {
      if (seen.get(r.FITID) !== sig) return fail('Two different transactions in the file share one ID. Nothing was compared.');
      continue;   // a byte-identical repeat
    }
    seen.set(r.FITID, sig);
    rows.push({ fitid: r.FITID, cents, posted, user: r.DTUSER ? ofxDate(r.DTUSER) : null, type: (r.TRNTYPE || '').toUpperCase(),
      name: decode(r.NAME || ''), memo: decode(r.MEMO || '') });
  }
  const dupes = raws.length - rows.length;
  if (dupes) notices.push(dupes + ' duplicate transaction' + (dupes === 1 ? '' : 's') + ' in the file (identical repeats) counted once.');
  let balance = null;
  if (balSeen) {
    const c = toCents(balAmt), d = ofxDate(balAsOf);
    if (c !== null && d) balance = { cents: c, asOf: d, asOfRaw: String(balAsOf) };
    else notices.push('The file\'s balance is incomplete, so the balance check is unavailable.');
  }
  if (!rows.length && !balance) return fail('The file has no transactions and no balance — nothing to compare.');
  const dates = rows.map(r => r.posted).sort();
  return { ok: true, file: { version, kind, last4: digits.slice(-4), org, rows, balance, notices,
    period: { start: dtStart, end: dtEnd }, range: dates.length ? { start: dates[0], end: dates[dates.length - 1] } : null } };
}

const dayNum = iso => Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)) / 864e5;
function groupByCents(list) { const m = new Map(); list.forEach(x => { if (!m.has(x.c)) m.set(x.c, []); m.get(x.c).push(x); }); return m; }
const byDateThenKey = (a, b) => a.d - b.d || String(a.key).localeCompare(String(b.key));

// The locked MATCHED contract (§23 A–F). bank: [{fitid, cents, posted, …}], register: one account's rows [{id, date, cents, …}].
export function compareStatement(bank, register) {
  const B = bank.map(row => ({ row, d: dayNum(row.posted), c: row.cents, key: row.fitid }));
  const R = register.map(row => ({ row, d: dayNum(row.date), c: row.cents, key: row.id }));
  const rBy = groupByCents(R), bBy = groupByCents(B);
  const gap = (b, r) => r.d - b.d;
  const eligible = (b, r) => b.c === r.c && gap(b, r) >= -RLITE_BEFORE_DAYS && gap(b, r) <= RLITE_AFTER_DAYS;   // A–C
  const candR = b => (rBy.get(b.c) || []).filter(r => eligible(b, r)).sort(byDateThenKey);
  const candB = r => (bBy.get(r.c) || []).filter(b => eligible(b, r)).sort(byDateThenKey);
  const range = B.length ? { start: B.reduce((m, b) => b.row.posted < m ? b.row.posted : m, B[0].row.posted), end: B.reduce((m, b) => b.row.posted > m ? b.row.posted : m, B[0].row.posted) } : null;
  const inRange = r => !!range && r.row.date >= range.start && r.row.date <= range.end;
  const matchedR = new Map(), bankOut = [];
  for (const b of B) {
    const cr = candR(b);
    if (!cr.length) {
      const near = (rBy.get(b.c) || []).filter(r => Math.abs(gap(b, r)) <= RLITE_HINT_DAYS)
        .sort((x, y) => Math.abs(gap(b, x)) - Math.abs(gap(b, y)) || gap(b, x) - gap(b, y) || String(x.key).localeCompare(String(y.key)))[0];
      bankOut.push({ row: b.row, state: 'BANK ONLY', reason: 'No Register entry of this amount within 4 days before to 3 days after.',
        hint: near ? { register: near.row, days: gap(b, near) } : null });
      continue;
    }
    const r = cr[0];
    if (cr.length === 1 && candB(r).length === 1) {   // D and E
      const lo = Math.min(b.d, r.d) - RLITE_GUARD_DAYS, hi = Math.max(b.d, r.d) + RLITE_GUARD_DAYS;
      const nearR = (rBy.get(b.c) || []).filter(x => x !== r && x.d >= lo && x.d <= hi).sort(byDateThenKey);
      const nearB = (bBy.get(b.c) || []).filter(x => x !== b && x.d >= lo && x.d <= hi).sort(byDateThenKey);
      if (nearR.length || nearB.length) {   // F: veto
        bankOut.push({ row: b.row, state: 'AMBIGUOUS', reason: 'The same amount appears again within 7 days, so it isn\'t matched automatically.',
          candidates: [r.row], nearbyRegister: nearR.map(x => x.row), nearbyBank: nearB.map(x => x.row) });
        continue;
      }
      const g = gap(b, r);
      matchedR.set(r, b);
      bankOut.push({ row: b.row, state: 'MATCHED', register: r.row, days: g,
        reason: g === 0 ? 'Same amount and date.' : 'Same amount, Register date ' + Math.abs(g) + ' day' + (Math.abs(g) === 1 ? '' : 's') + (g < 0 ? ' earlier.' : ' later.') });
      continue;
    }
    bankOut.push({ row: b.row, state: 'AMBIGUOUS', candidates: cr.map(x => x.row),
      reason: cr.length > 1 ? cr.length + ' Register entries could be this transaction.' : 'That Register entry could also belong to another bank transaction.' });
  }
  const registerOut = [];
  let before = 0, after = 0;
  for (const r of R) {
    const listed = inRange(r);
    if (matchedR.has(r)) { registerOut.push({ row: r.row, state: 'MATCHED', bank: matchedR.get(r).row, context: !listed }); continue; }
    if (candB(r).length) { registerOut.push({ row: r.row, state: 'AMBIGUOUS', context: !listed }); continue; }
    if (listed) { registerOut.push({ row: r.row, state: 'REGISTER ONLY' }); continue; }
    if (range && r.row.date > range.end) after++; else before++;
  }
  return { range, bank: bankOut, register: registerOut, context: { notComparedAfter: after, notComparedBefore: before } };
}

// Informational totals for the effective range (never "reconciled").
export function statementTotals(res) {
  const sum = list => list.reduce((s, x) => s + x.row.cents, 0);
  const inR = res.register.filter(x => !x.context);
  const bankCents = sum(res.bank), registerInRangeCents = sum(inR);
  const st = (list, s) => list.filter(x => x.state === s);
  return { bankCents, registerInRangeCents, diffCents: bankCents - registerInRangeCents,
    matchedBankCents: sum(st(res.bank, 'MATCHED')), bankOnlyCents: sum(st(res.bank, 'BANK ONLY')), ambiguousBankCents: sum(st(res.bank, 'AMBIGUOUS')),
    registerOnlyCents: sum(st(inR, 'REGISTER ONLY')), ambiguousRegisterCents: sum(st(inR, 'AMBIGUOUS')),
    counts: { matched: st(res.bank, 'MATCHED').length, bankOnly: st(res.bank, 'BANK ONLY').length, ambiguousBank: st(res.bank, 'AMBIGUOUS').length,
      registerOnly: st(inR, 'REGISTER ONLY').length, ambiguousRegister: st(inR, 'AMBIGUOUS').length } };
}

// Current posted balance check: the file's posted balance vs the Register CLEARED balance at a compatible cutoff.
export function postedBalanceCheck(balance, register, startingCents, todayIso) {
  const na = reason => ({ state: 'UNAVAILABLE', reason });
  if (!balance) return na('There\'s no posted balance in this file.');
  if (startingCents === null || startingCents === undefined) return na('This account has no starting balance in the Register, so its cleared balance can\'t be worked out.');
  if (balance.asOf < todayIso) return na('The file\'s balance is as of ' + balance.asOf + '. The Register\'s Cleared marks reflect today, so the balance can only be checked with a file downloaded today.');
  if (balance.asOf > todayIso) return na('The file\'s balance date (' + balance.asOf + ') is in the future, so it can\'t be checked.');
  const registerCents = startingCents + register.filter(r => r.cleared && r.date <= balance.asOf).reduce((s, r) => s + r.cents, 0);
  const diffCents = balance.cents - registerCents;
  return { state: diffCents === 0 ? 'AGREES' : 'DIFFERS', bankCents: balance.cents, registerCents, diffCents, asOf: balance.asOf, asOfRaw: balance.asOfRaw };
}

// Account binding: owner-selected account + type compatibility + remembered last-4 (fail closed on any mismatch).
const KIND_WORDS = { checking: 'a checking account', savings: 'a savings account', credit_card: 'a credit card' };
export function bindingDecision(file, account, remembered, labels) {
  const lab = k => (labels && labels[k]) || 'another account';
  if (account.account_type !== file.kind)
    return { decision: 'refuse', message: 'This file is for ' + KIND_WORDS[file.kind] + ' ending •' + file.last4 + ', but ' + account.label + ' is ' + (KIND_WORDS[account.account_type] || 'a different kind of account') + '. Nothing was compared.' };
  const other = Object.keys(remembered || {}).find(k => k !== account.key && remembered[k] === file.last4);
  if (other) return { decision: 'refuse', message: 'The account ending •' + file.last4 + ' was confirmed on this device as ' + lab(other) + ', not ' + account.label + '. Nothing was compared.' };
  const mine = (remembered || {})[account.key];
  if (mine && mine !== file.last4)
    return { decision: 'refuse', rebind: true, message: account.label + ' was confirmed on this device as the account ending •' + mine + ', but this file is for •' + file.last4 + '. Nothing was compared.' };
  return { decision: 'confirm', message: 'This file appears to be ' + KIND_WORDS[file.kind] + ' ending •' + file.last4 + '. Compare it with ' + account.label + '?'
    + (mine ? ' (Confirmed before on this device.)' : ' (First time on this device; your answer will be remembered here.)') };
}

// ── DATA (read-only view of the Register state the app has already loaded) ──
function accountsList() { return typeof _accountsCache !== 'undefined' && Array.isArray(_accountsCache) ? _accountsCache : []; }
function accountRow(key) { return accountsList().find(a => a.key === key) || null; }
function ledgerState() {
  return { key: typeof _txLedgerAccountKey !== 'undefined' ? _txLedgerAccountKey : null, status: typeof _txLedgerLoadStatus !== 'undefined' ? _txLedgerLoadStatus : null,
    rows: typeof _txLedgerCache !== 'undefined' ? _txLedgerCache : null };
}
function registerRowsFor(key, rows) {
  const out = [];
  for (const t of rows) {
    if (t.account_key !== key) continue;
    const c = toCents(typeof t.amount === 'number' ? String(t.amount) : t.amount);
    if (c === null || !/^\d{4}-\d{2}-\d{2}$/.test(String(t.transaction_date))) return null;   // unreadable → fail closed
    out.push({ id: t.id, date: t.transaction_date, cents: c, payee: t.payee || '', memo: t.memo || '', cleared: t.cleared === true });
  }
  return out;
}
function todayIso() { const n = new Date(); return n.getFullYear() + '-' + String(n.getMonth() + 1).padStart(2, '0') + '-' + String(n.getDate()).padStart(2, '0'); }
const STORE_KEY = 'hfos.rlite.bindings';
function loadBindings() { try { const v = JSON.parse(window.localStorage.getItem(STORE_KEY) || '{}'); return v && typeof v === 'object' ? v : {}; } catch (e) { return {}; } }
function saveBinding(key, last4) { try { const v = loadBindings(); v[key] = last4; window.localStorage.setItem(STORE_KEY, JSON.stringify(v)); } catch (e) { /* storage unavailable: nothing remembered */ } }

// ── VIEW ────────────────────────────────────────────────────────────────────
const ROOT_ID = 'rlite-root';
const S = { accountKey: null, fileName: null, parsed: null, binding: null, confirmed: false, result: null, stale: false, busy: false };
function el(tag, attrs, text) {
  const n = document.createElement(tag);
  Object.keys(attrs || {}).forEach(k => n.setAttribute(k, attrs[k]));
  if (text != null) n.textContent = text;
  return n;
}
function money(c) { const a = Math.abs(c) / 100; return (c < 0 ? '−' : '') + '$' + a.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
const BTN = 'font:inherit;font-size:12px;font-weight:600;padding:5px 12px;border-radius:6px;cursor:pointer;';
const PRIMARY = BTN + 'border:1px solid var(--blue);background:var(--blue);color:#fff;';
const SECONDARY = BTN + 'border:1px solid var(--line);background:var(--surface);color:var(--text);';
function labelFor(key) { const a = accountRow(key); return a ? a.label : key; }
function supportedAccounts() { return RLITE_ACCOUNTS.map(accountRow).filter(a => a && a.lifecycle_status === 'active'); }
function resetFile() { S.fileName = null; S.parsed = null; S.binding = null; S.confirmed = false; S.result = null; S.stale = false; }

function compareNow() {
  const L = ledgerState(), acct = accountRow(S.accountKey);
  if (!S.parsed || !S.parsed.ok || !S.confirmed || !acct || L.key !== S.accountKey || L.status !== 'loaded' || !Array.isArray(L.rows)) { S.result = null; return; }
  const reg = registerRowsFor(S.accountKey, L.rows);
  if (!reg) { S.result = { error: 'A Register entry for this account couldn\'t be read, so nothing was compared.' }; return; }
  const file = S.parsed.file;
  const res = file.rows.length ? compareStatement(file.rows, reg) : null;
  const sb = acct.starting_balance === null || acct.starting_balance === undefined ? null : toCents(String(acct.starting_balance));
  S.result = { forRows: L.rows, accountKey: S.accountKey, res, totals: res ? statementTotals(res) : null, balance: postedBalanceCheck(file.balance, reg, sb, todayIso()) };
  S.stale = false;
}

function section(root, title) {
  const box = el('div', { style: 'border:1px solid var(--line);border-radius:8px;padding:12px 14px;margin-bottom:12px;background:var(--surface)' });
  if (title) box.appendChild(el('div', { style: 'font-size:12px;font-weight:700;color:var(--ink);margin-bottom:8px;text-transform:uppercase;letter-spacing:.04em' }, title));
  root.appendChild(box);
  return box;
}
function line(box, text, style) { box.appendChild(el('div', { style: 'font-size:12px;color:var(--muted);margin:2px 0;' + (style || '') }, text)); }

function renderRows(box, title, items, kind) {
  if (!items.length) return;
  box.appendChild(el('div', { style: 'font-size:12px;font-weight:700;margin:10px 0 4px;color:var(--ink)' }, title + ' (' + items.length + ')'));
  const table = el('table', { style: 'width:100%;border-collapse:collapse;font-size:12px' });
  items.forEach(it => {
    const tr = el('tr', { style: 'border-top:1px solid var(--line);vertical-align:top' });
    const r = it.row;
    tr.appendChild(el('td', { style: 'padding:5px 6px;white-space:nowrap' }, kind === 'bank' ? r.posted : r.date));
    tr.appendChild(el('td', { style: 'padding:5px 6px;white-space:nowrap;text-align:right' }, money(r.cents)));
    tr.appendChild(el('td', { style: 'padding:5px 6px' }, kind === 'bank' ? [r.name, r.memo].filter(Boolean).join(' · ') : (r.payee || '') + (r.cleared ? ' · cleared' : '')));
    const why = el('td', { style: 'padding:5px 6px;color:var(--muted)' }, it.reason || '');
    const rel = [];
    if (it.register) rel.push('Register: ' + it.register.date + ' ' + money(it.register.cents) + ' ' + (it.register.payee || ''));
    (it.candidates || []).forEach(c => rel.push('Possible: ' + c.date + ' ' + money(c.cents) + ' ' + (c.payee || '')));
    (it.nearbyRegister || []).forEach(c => rel.push('Same amount nearby (Register): ' + c.date + ' ' + (c.payee || '')));
    (it.nearbyBank || []).forEach(c => rel.push('Same amount nearby (bank): ' + c.posted + ' ' + (c.name || '')));
    if (it.hint) rel.push('Possible counterpart outside the window: Register ' + it.hint.register.date + ' (' + (it.hint.days < 0 ? Math.abs(it.hint.days) + ' days earlier' : it.hint.days + ' days later') + ') ' + (it.hint.register.payee || ''));
    if (it.bank) rel.push('Bank: ' + it.bank.posted + ' ' + (it.bank.name || ''));
    if (it.context) rel.push('(dated outside the file\'s range — shown as context)');
    rel.forEach(t => why.appendChild(el('div', { style: 'color:var(--text)' }, t)));
    tr.appendChild(why);
    table.appendChild(tr);
  });
  box.appendChild(table);
}

function render() {
  const root = document.getElementById(ROOT_ID);
  if (!root) return;
  root.textContent = '';
  root.setAttribute('style', 'padding:16px');
  const intro = section(root, 'Statement Compare');
  line(intro, 'Compares a bank download (QFX/OFX) with this account\'s Register and lists matches and exceptions for you to review. It doesn\'t reconcile, clear or change anything — your normal reconciliation stays authoritative.', 'color:var(--text)');
  line(intro, 'The file is read only in this browser; nothing is uploaded or saved.');

  const accts = supportedAccounts();
  if (!S.accountKey) { const cur = ledgerState().key; S.accountKey = accts.some(a => a.key === cur) ? cur : (accts[0] && accts[0].key) || null; }
  const step1 = section(root, '1 · Account');
  const sel = el('select', { id: 'rlite-account', style: 'font:inherit;font-size:13px;padding:4px 8px;border:1px solid var(--line);border-radius:6px;background:var(--surface);color:var(--text)' });
  accts.forEach(a => { const o = el('option', { value: a.key }, a.label); if (a.key === S.accountKey) o.selected = true; sel.appendChild(o); });
  sel.addEventListener('change', () => { S.accountKey = sel.value; resetFile(); if (typeof setTxLedgerAccount === 'function') setTxLedgerAccount(S.accountKey); render(); });
  step1.appendChild(sel);
  const L = ledgerState();
  const ready = L.key === S.accountKey && L.status === 'loaded' && Array.isArray(L.rows);
  if (!ready) {
    const msg = el('div', { id: 'rlite-unavailable', style: 'margin-top:8px;font-size:12px;color:var(--amber);font-weight:600' },
      'Comparison unavailable — this account\'s Register history isn\'t fully loaded' + (L.key === S.accountKey && L.status ? ' (' + L.status + ')' : '') + '.');
    step1.appendChild(msg);
    if (L.key !== S.accountKey || L.status === 'failed' || L.status === 'incomplete' || L.status === 'not_loaded') {
      const b = el('button', { type: 'button', id: 'rlite-load', style: SECONDARY + 'margin-top:6px' }, 'Load Register history');
      b.addEventListener('click', () => { if (typeof setTxLedgerAccount === 'function') { if (L.key === S.accountKey && typeof _loadTxLedger === 'function') _loadTxLedger(S.accountKey); else setTxLedgerAccount(S.accountKey); } });
      step1.appendChild(b);
    }
  }

  const step2 = section(root, '2 · Bank file');
  const inp = el('input', { type: 'file', id: 'rlite-file', accept: '.qfx,.ofx,.QFX,.OFX' });
  inp.addEventListener('change', () => { const f = inp.files && inp.files[0]; if (f) readFile(f); });
  step2.appendChild(inp);
  if (S.fileName) line(step2, 'File: ' + S.fileName);
  if (S.parsed && !S.parsed.ok) step2.appendChild(el('div', { id: 'rlite-rejected', style: 'margin-top:6px;font-size:12px;color:var(--red);font-weight:600' }, 'File not used: ' + S.parsed.reason));

  if (S.parsed && S.parsed.ok) {
    const file = S.parsed.file, acct = accountRow(S.accountKey);
    const step3 = section(root, '3 · Confirm the account');
    if (!S.binding) S.binding = acct ? bindingDecision(file, { key: acct.key, label: acct.label, account_type: acct.account_type }, loadBindings(), Object.fromEntries(accountsList().map(a => [a.key, a.label]))) : { decision: 'refuse', message: 'Choose an account first.' };
    if (S.binding.decision === 'refuse') {
      step3.appendChild(el('div', { id: 'rlite-binding-refused', style: 'font-size:12px;color:var(--red);font-weight:600' }, S.binding.message));
      if (S.binding.rebind) {
        const rb = el('button', { type: 'button', id: 'rlite-rebind', style: SECONDARY + 'margin-top:6px' }, 'Change the remembered account number for ' + acct.label + '…');
        rb.addEventListener('click', () => {
          if (window.confirm('Remember the account ending •' + file.last4 + ' as ' + acct.label + ' on this device? Only do this if ' + acct.label + '\'s account number has changed.')) {
            saveBinding(acct.key, file.last4); S.binding = null; render();
          }
        });
        step3.appendChild(rb);
      }
    } else if (!S.confirmed) {
      step3.appendChild(el('div', { id: 'rlite-binding-ask', style: 'font-size:13px;color:var(--text);margin-bottom:8px' }, S.binding.message));
      const yes = el('button', { type: 'button', id: 'rlite-confirm', style: PRIMARY }, 'Compare with ' + acct.label);
      const no = el('button', { type: 'button', id: 'rlite-cancel', style: SECONDARY + 'margin-left:6px' }, 'Cancel');
      yes.addEventListener('click', () => { saveBinding(acct.key, file.last4); S.confirmed = true; compareNow(); render(); });
      no.addEventListener('click', () => { resetFile(); render(); });
      step3.appendChild(yes); step3.appendChild(no);
    } else line(step3, 'Comparing with ' + acct.label + ' (account ending •' + file.last4 + ').', 'color:var(--text)');
  }

  if (S.confirmed && S.result && S.result.forRows !== ledgerState().rows) { S.result = null; S.stale = true; }
  if (S.confirmed) {
    const out = section(root, '4 · Results');
    out.setAttribute('id', 'rlite-results');
    if (!ready) { line(out, 'Comparison unavailable until this account\'s Register history is fully loaded.', 'color:var(--amber);font-weight:600'); return; }
    if (S.stale || !S.result) {
      line(out, 'The Register changed or reloaded since the last comparison, so those results were discarded.', 'color:var(--amber);font-weight:600');
      const again = el('button', { type: 'button', id: 'rlite-again', style: PRIMARY + 'margin-top:6px' }, 'Compare again');
      again.addEventListener('click', () => { compareNow(); render(); });
      out.appendChild(again);
      return;
    }
    if (S.result.error) { out.appendChild(el('div', { style: 'font-size:12px;color:var(--red);font-weight:600' }, S.result.error)); return; }
    const file = S.parsed.file, res = S.result.res, tot = S.result.totals, bal = S.result.balance;
    file.notices.forEach(n => line(out, n, 'color:var(--amber)'));
    if (res) {
      line(out, 'Compared: bank transactions posted ' + res.range.start + ' to ' + res.range.end + ' (the file says ' + (file.period.start || '?') + ' to ' + (file.period.end || '?') + '; the transactions themselves set the range).', 'color:var(--text)');
      const c = tot.counts;
      const chips = el('div', { id: 'rlite-summary', style: 'display:flex;flex-wrap:wrap;gap:8px;margin:8px 0' });
      [['Matched', c.matched], ['Bank only', c.bankOnly], ['Register only', c.registerOnly], ['Ambiguous (bank)', c.ambiguousBank], ['Ambiguous (Register)', c.ambiguousRegister]]
        .forEach(([k, v]) => chips.appendChild(el('span', { style: 'font-size:12px;padding:3px 9px;border:1px solid var(--line);border-radius:99px' }, k + ': ' + v)));
      out.appendChild(chips);
      line(out, 'Totals for that range (information only): bank ' + money(tot.bankCents) + ' · Register ' + money(tot.registerInRangeCents) + ' · difference ' + money(tot.diffCents)
        + ' — bank only ' + money(tot.bankOnlyCents) + ', Register only ' + money(tot.registerOnlyCents) + ', ambiguous bank ' + money(tot.ambiguousBankCents) + ', ambiguous Register ' + money(tot.ambiguousRegisterCents) + '.');
      if (res.context.notComparedAfter) line(out, res.context.notComparedAfter + ' Register entr' + (res.context.notComparedAfter === 1 ? 'y is' : 'ies are') + ' dated after the file\'s last transaction and weren\'t compared.');
    } else line(out, 'The file has no transactions, so only the balance check ran.', 'color:var(--text)');
    const bb = el('div', { id: 'rlite-balance', style: 'margin:10px 0;padding:8px 10px;border:1px solid var(--line);border-radius:6px;font-size:12px' });
    bb.appendChild(el('div', { style: 'font-weight:700;color:var(--ink)' }, 'Current posted balance check'));
    if (bal.state === 'UNAVAILABLE') bb.appendChild(el('div', { style: 'color:var(--muted)' }, 'Unavailable — ' + bal.reason));
    else bb.appendChild(el('div', { style: 'color:var(--text)' }, 'Bank posted balance as of ' + bal.asOf + ' (' + bal.asOfRaw + '): ' + money(bal.bankCents) + ' · Register cleared balance: ' + money(bal.registerCents)
      + ' — ' + (bal.state === 'AGREES' ? 'they agree.' : 'they differ by ' + money(bal.diffCents) + '.') + ' This is a balance check only; it doesn\'t confirm each transaction.'));
    out.appendChild(bb);
    if (res) {
      renderRows(out, 'Ambiguous — your review', res.bank.filter(x => x.state === 'AMBIGUOUS'), 'bank');
      renderRows(out, 'Bank only — not found in the Register', res.bank.filter(x => x.state === 'BANK ONLY'), 'bank');
      renderRows(out, 'Register only — not in the bank file', res.register.filter(x => x.state === 'REGISTER ONLY'), 'register');
      renderRows(out, 'Ambiguous Register entries', res.register.filter(x => x.state === 'AMBIGUOUS' && !x.context), 'register');
      renderRows(out, 'Matched', res.bank.filter(x => x.state === 'MATCHED'), 'bank');
      line(out, 'To fix anything, use the Register (Add, Edit, Delete, Cleared). Statement Compare changes nothing.');
    }
    const clr = el('button', { type: 'button', id: 'rlite-clear', style: SECONDARY + 'margin-top:8px' }, 'Clear this comparison');
    clr.addEventListener('click', () => { resetFile(); render(); });
    out.appendChild(clr);
  }
}

async function readFile(f) {
  resetFile();
  S.fileName = f.name;
  if (f.size > RLITE_MAX_BYTES) { S.parsed = { ok: false, reason: 'The file is larger than 2 MB, which is too big for a statement download.' }; render(); return; }
  if (!/\.(qfx|ofx)$/i.test(f.name)) { S.parsed = { ok: false, reason: 'Choose a .qfx or .ofx file.' }; render(); return; }
  try {
    const buf = new Uint8Array(await f.arrayBuffer());
    const xml = buf[0] === 0x3C && buf[1] === 0x3F || (buf[0] === 0xEF && buf[3] === 0x3C);
    S.parsed = parseOfx(new TextDecoder(xml ? 'utf-8' : 'windows-1252').decode(buf));
  } catch (e) { S.parsed = { ok: false, reason: 'The file couldn\'t be read.' }; }
  render();
}

// Browser wiring (skipped when the module is loaded for tests).
if (typeof document !== 'undefined' && typeof window !== 'undefined') {
  const host = document.getElementById('transactions-content');
  if (host) new MutationObserver(() => { if (document.getElementById(ROOT_ID) && !document.getElementById(ROOT_ID).hasChildNodes()) render(); }).observe(host, { childList: true });
  render();
  document.documentElement.setAttribute('data-hfos-rlite', 'on');   // mount marker for acceptance checks
}
