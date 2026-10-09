// ════════════════════════════════════════════════════════════════════════════
// Release 2 (2026-10-09): Register entry assist — ENTRY ASSISTANCE ONLY.
//
// Adds to the Register's Add form (rendered by the protected _renderTxRegister, which is NOT changed):
//   • Save & Add Another — saves through the existing _saveTxForm path; the next form opens only after
//     that save reports success, keeping the date just used (visibly marked) and clearing the rest.
//   • Category search + grouping — over the options the form already offers (same keys, same authority).
//   • Payee → category suggestion — from this account's loaded Register history; shown, never applied.
//   • Possible-duplicate warning — before saving; the person can go back or explicitly save anyway.
// Nothing here writes data, reads the network, assigns a category on its own, or merges/suppresses rows.
// Sections: DOMAIN (pure, exported, unit-tested) · DATA (read-only view of the app's Register state) ·
// VIEW (DOM wiring). No globals: state is module-local; the mount marker is a document attribute.
// ════════════════════════════════════════════════════════════════════════════

// ── DOMAIN ──────────────────────────────────────────────────────────────────
export const SUGGEST_WINDOW = 10;     // most recent matching entries considered
export const SUGGEST_MIN_ROWS = 2;    // fewer matching categorized entries → no suggestion
export const SUGGEST_SHARE = 0.75;    // one category must hold ≥ 75% of the considered entries
export const DUP_DAY_WINDOW = 3;      // possible duplicate: dates at most 3 days apart

function words(s) {
  return String(s == null ? '' : s).normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
    .replace(/['’]/g, '').replace(/&/g, ' and ').replace(/[^a-z0-9]+/g, ' ').trim().split(' ').filter(Boolean);
}

// Exact-match key for a payee: case, accents, apostrophes and punctuation fold; trailing store/reference
// numbers drop ("Publix #1234" → "publix") — except a check number ("Check 1052" stays distinct).
// No fuzzy or prefix matching.
const CHECK_WORDS = ['check', 'chk', 'ck', 'cheque'];
export function normalizePayee(s) {
  const w = words(s);
  while (w.length > 1 && /^\d+$/.test(w[w.length - 1]) && CHECK_WORDS.indexOf(w[w.length - 2]) < 0) w.pop();
  return w.join(' ');
}

function dayNumber(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso == null ? '' : iso));
  if (!m) return null;
  const y = +m[1], mo = +m[2], d = +m[3], t = Date.UTC(y, mo - 1, d), dt = new Date(t);
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null;
  return t / 86400000;
}
function cents(v) {
  const n = typeof v === 'number' ? v : parseFloat(v);
  return isFinite(n) ? Math.round(n * 100) : null;
}
function desc(x, y) {
  x = x == null ? '' : String(x); y = y == null ? '' : String(y);
  return x < y ? 1 : x > y ? -1 : 0;
}
function recentFirst(a, b) {
  return desc(a.transaction_date, b.transaction_date) || desc(a.created_at, b.created_at) || desc(a.id, b.id);
}

// Suggest a category for a payee from Register history (rows), or null.
// Considered: categorized rows whose normalized payee equals this payee's, newest SUGGEST_WINDOW only.
// Suggest only when at least SUGGEST_MIN_ROWS are considered and one category holds ≥ SUGGEST_SHARE of them
// (so ties never suggest), and that category is assignable now. Otherwise null — no runner-up fallback.
export function suggestCategory(payee, rows, isAssignable) {
  const key = normalizePayee(payee);
  if (key.length < 2 || !Array.isArray(rows)) return null;
  const considered = rows.filter(r => r && typeof r.category_key === 'string' && r.category_key !== ''
    && normalizePayee(r.payee) === key).sort(recentFirst).slice(0, SUGGEST_WINDOW);
  if (considered.length < SUGGEST_MIN_ROWS) return null;
  const counts = new Map();
  for (const r of considered) counts.set(r.category_key, (counts.get(r.category_key) || 0) + 1);
  let best = null, n = 0;
  for (const [k, c] of counts) if (c > n) { best = k; n = c; }
  if (n < SUGGEST_MIN_ROWS || n / considered.length < SUGGEST_SHARE) return null;
  if (typeof isAssignable !== 'function' || !isAssignable(best)) return null;
  return { categoryKey: best, count: n, of: considered.length, payeeKey: key };
}

// Rows that the proposed entry may duplicate: same account, same signed amount to the cent, same normalized
// payee, dates at most DUP_DAY_WINDOW days apart. Nearest date first. An incomplete proposal → [].
export function findPossibleDuplicates(c, rows) {
  const day = dayNumber(c && c.date), amt = cents(c && c.amount), key = normalizePayee(c && c.payee);
  if (!c || !c.accountKey || day === null || amt === null || amt === 0 || !key || !Array.isArray(rows)) return [];
  const dist = r => Math.abs(dayNumber(r.transaction_date) - day);
  return rows.filter(r => r && r.account_key === c.accountKey && cents(r.amount) === amt
      && dayNumber(r.transaction_date) !== null && dist(r) <= DUP_DAY_WINDOW && normalizePayee(r.payee) === key)
    .sort((a, b) => dist(a) - dist(b) || recentFirst(a, b));
}

// Payee autocomplete (owner, 2026-10-09): historical payees for what has been typed — offered, never applied.
// Same normalization as above; one candidate per normalized payee, shown in its most recent spelling.
// Classes: exact, then prefix of the whole name, then substring; within a class most entries, then most recent.
// defaultIndex (what Tab/Enter accept without arrowing) is 0 only when exactly ONE name starts with the typed text,
// none equals it, and the typing stops mid-word ("ube"→Uber yes; "Target" vs "Target Optical" no). Otherwise -1.
export const PAYEE_MIN_CHARS = 3;
export const PAYEE_MAX_SHOWN = 6;
export function payeeCompletions(query, rows) {
  const q = normalizePayee(query), none = { candidates: [], more: 0, defaultIndex: -1 };
  if (q.replace(/ /g, '').length < PAYEE_MIN_CHARS || !Array.isArray(rows)) return none;
  const groups = new Map();
  for (const r of rows) {
    if (!r || typeof r.payee !== 'string') continue;
    const key = normalizePayee(r.payee);
    if (!key) continue;
    const cls = key === q ? 'exact' : key.startsWith(q) ? 'prefix' : key.indexOf(q) >= 0 ? 'substring' : null;
    if (!cls) continue;
    const g = groups.get(key);
    if (!g) groups.set(key, { key, cls, count: 1, latest: r });
    else { g.count++; if (recentFirst(r, g.latest) < 0) g.latest = r; }
  }
  const rank = { exact: 0, prefix: 1, substring: 2 };
  const all = [...groups.values()]
    .sort((a, b) => rank[a.cls] - rank[b.cls] || b.count - a.count || recentFirst(a.latest, b.latest) || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
    .map(g => ({ key: g.key, payee: g.latest.payee.trim(), count: g.count, cls: g.cls }));
  const prefix = all.filter(c => c.cls === 'prefix');
  const defaultIndex = !all.some(c => c.cls === 'exact') && prefix.length === 1 && prefix[0].key.charAt(q.length) !== ' ' ? 0 : -1;
  return { candidates: all.slice(0, PAYEE_MAX_SHOWN), more: Math.max(0, all.length - PAYEE_MAX_SHOWN), defaultIndex };
}

// The next entry after a successful Save & Add Another: the fresh Add form, with the date just used kept
// (when valid). Payee, memo, amounts and category clear; Cleared returns to unchecked.
export function nextEntryFormData(saved, fresh) {
  const out = Object.assign({}, fresh, { payee: '', memo: '', category_key: '', outflow: '', inflow: '', cleared: false });
  if (saved && dayNumber(saved.transaction_date) !== null) out.transaction_date = saved.transaction_date;
  return out;
}

// Category search over [{key,label,group}]: every query word must start a word of the label or group.
// Label-prefix matches first, otherwise the given order. Blank query → none.
export function matchCategoryOptions(query, options) {
  const q = words(query);
  if (!q.length || !Array.isArray(options)) return [];
  const phrase = q.join(' '), hits = [];
  options.forEach((o, i) => {
    const ws = words(o.label).concat(words(o.group));
    if (!q.every(t => ws.some(w => w.startsWith(t)))) return;
    hits.push({ o, i, rank: words(o.label).join(' ').startsWith(phrase) ? 0 : 1 });
  });
  return hits.sort((a, b) => a.rank - b.rank || a.i - b.i).map(h => h.o);
}

// Presentation-only grouping: groups sorted by name, ungrouped ("Other") last, labels sorted within a group.
// The option objects pass through unchanged; each appears exactly once.
export function groupCategoryOptions(options) {
  const byLabel = (a, b) => String(a.label).localeCompare(String(b.label)) || desc(b.key, a.key);
  const by = new Map();
  (options || []).forEach(o => { const g = o.group || null; if (!by.has(g)) by.set(g, []); by.get(g).push(o); });
  const out = [...by.keys()].filter(g => g !== null).sort((a, b) => a.localeCompare(b))
    .map(g => ({ group: g, options: by.get(g).slice().sort(byLabel) }));
  if (by.has(null)) out.push({ group: 'Other', options: by.get(null).slice().sort(byLabel) });
  return out;
}

// ── DATA (read-only view of the Register state the app has already loaded) ──
// The classic script's top-level vars are globals; typeof keeps every read safe if one is absent.
function formMode() { return typeof _txFormMode !== 'undefined' ? _txFormMode : null; }
function formSaving() { return typeof _txFormSaving !== 'undefined' && _txFormSaving === true; }
function deleteConfirmOpen() { return typeof _txDeleteConfirmId !== 'undefined' && !!_txDeleteConfirmId; }
function ledgerRows() {
  return typeof _txLedgerLoadStatus !== 'undefined' && _txLedgerLoadStatus === 'loaded' && Array.isArray(_txLedgerCache) ? _txLedgerCache : null;
}
function accountLabel(key) {
  const a = (typeof _accountsCache !== 'undefined' && Array.isArray(_accountsCache) ? _accountsCache : []).find(x => x.key === key);
  return a ? a.label : key;
}
function categoryRow(key) {
  return (typeof _categoriesCache !== 'undefined' && Array.isArray(_categoriesCache) ? _categoriesCache : []).find(c => c.key === key) || null;
}
function groupLabel(key) {
  const row = categoryRow(key), parent = row && row.parent_key;
  if (!parent) return null;
  const p = categoryRow(parent);
  return p && p.label ? p.label : parent;
}
// The entry as _saveTxForm would read it, or null when it would not pass the same validation.
function proposedEntry() {
  if (formMode() !== 'add') return null;
  const d = _txFormData || {}, date = String(d.transaction_date || '').trim();
  const outRaw = String(d.outflow || '').trim(), inRaw = String(d.inflow || '').trim(), payee = String(d.payee || '').trim();
  if (!_isValidTxDate(date) || !payee || !!outRaw === !!inRaw) return null;
  const v = _parseTxAmount(outRaw || inRaw);
  if (v === null) return null;
  return { accountKey: _txLedgerAccountKey, date, amount: outRaw ? -v : v, payee };
}
const signature = c => [c.accountKey, c.date, cents(c.amount), normalizePayee(c.payee)].join('|');

// ── VIEW ────────────────────────────────────────────────────────────────────
const ROOT_ID = 'transactions-content';
const PRIMARY = 'button[onclick="_saveTxForm()"]';
const CANCEL = 'button[onclick="_closeTxForm()"]';
const PAYEE = 'input[oninput="_setTxFormField(\'payee\',this.value)"]';
const DATE = 'input[type="date"][onchange="_setTxFormField(\'transaction_date\',this.value)"]';
let busy = false;          // a save started here is in flight
let cancelled = false;     // the person pressed Cancel while it was in flight → do not reopen
let carriedDate = null;    // the date kept from the previous entry (shown as such)
let pending = null;        // {sig, mode, matches} — a possible-duplicate warning awaiting a decision
let acknowledged = null;   // signature the person chose to "Save anyway"
let editDuringSave = false;
let ac = null;              // payee autocomplete on screen: {items, more, index} — nothing is applied until accepted // an edit form was opened while a save started here was in flight → do not reopen

function el(tag, attrs, text) {
  const n = document.createElement(tag);
  Object.keys(attrs || {}).forEach(k => n.setAttribute(k, attrs[k]));
  if (text != null) n.textContent = text;
  return n;
}
function fmtAmount(v) {
  const n = Math.abs(parseFloat(v)) || 0;
  return '$' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + (parseFloat(v) > 0 ? ' (inflow)' : '');
}
function fmtDate(iso, refIso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || ''));
  if (!m) return String(iso || '');
  const opts = { month: 'short', day: 'numeric', timeZone: 'UTC' };
  if (!refIso || String(refIso).slice(0, 4) !== m[1]) opts.year = 'numeric';
  return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])).toLocaleDateString('en-US', opts);
}
function formParts() {
  const root = document.getElementById(ROOT_ID);
  if (!root) return null;
  const primary = root.querySelector(PRIMARY), sel = root.querySelector('#tx-form-category');
  if (!primary || !sel) return null;
  let form = primary;
  while (form && form !== root && !/blueSoft/.test(form.getAttribute('style') || '')) form = form.parentElement;
  const grid = primary.closest('div[style*="display:grid"]');
  return { root, primary, sel, form: form && form !== root ? form : primary.parentElement, grid };
}

// Search box + grouped options for the category select. Keys, labels and the selection are untouched.
function enhanceCategory(p) {
  const sel = p.sel;
  if (sel.getAttribute('data-r2') === 'on') return;
  sel.setAttribute('data-r2', 'on');
  const opts = [...sel.querySelectorAll('option[data-mlabel="1"]')].map(o => ({ key: o.value, label: o.textContent, group: groupLabel(o.value), el: o }));
  const legacy = [...sel.options].filter(o => o.value !== '' && o.getAttribute('data-mlabel') !== '1');
  const chosen = sel.value;
  groupCategoryOptions(opts).forEach(g => {
    const og = el('optgroup', { label: g.group });
    g.options.forEach(o => og.appendChild(o.el));
    sel.appendChild(og);
  });
  legacy.forEach(o => sel.appendChild(o));
  sel.value = chosen;
  const cell = sel.parentElement;
  cell.style.position = 'relative';
  const box = el('input', { type: 'search', id: 'r2-cat-search', placeholder: 'Search categories…', 'aria-label': 'Search categories', autocomplete: 'off',
    style: 'font-family:inherit;font-size:12px;padding:4px 8px;border:1px solid var(--line);border-radius:6px;background:var(--surface);color:var(--text);width:100%;margin-bottom:4px;box-sizing:border-box' });
  const list = el('div', { id: 'r2-cat-results', role: 'listbox',
    style: 'display:none;position:absolute;left:0;right:0;top:100%;z-index:30;margin-top:2px;background:var(--surface);border:1px solid var(--line);border-radius:6px;box-shadow:0 6px 16px rgba(0,0,0,.12);max-height:240px;overflow:auto' });
  const show = () => {
    list.textContent = '';
    const q = box.value;
    if (!q.trim()) { list.style.display = 'none'; return; }
    const hits = matchCategoryOptions(q, opts);
    hits.slice(0, 8).forEach(o => {
      const b = el('button', { type: 'button', role: 'option', 'data-key': o.key,
        style: 'display:block;width:100%;text-align:left;border:0;background:none;padding:6px 10px;font:inherit;font-size:12px;cursor:pointer;color:var(--text)' }, o.label);
      if (o.group) b.appendChild(el('span', { style: 'color:var(--muted);margin-left:6px' }, '· ' + o.group));
      b.addEventListener('click', () => _setTxFormField('category_key', o.key));
      list.appendChild(b);
    });
    if (!hits.length) list.appendChild(el('div', { style: 'padding:6px 10px;font-size:12px;color:var(--muted)' }, 'No matching category'));
    else if (hits.length > 8) list.appendChild(el('div', { style: 'padding:6px 10px;font-size:11px;color:var(--muted)' }, (hits.length - 8) + ' more — keep typing'));
    list.style.display = 'block';
  };
  box.addEventListener('input', show);
  box.addEventListener('keydown', ev => {
    if (ev.key === 'Escape') { box.value = ''; show(); }
    if (ev.key === 'Enter') {
      ev.preventDefault();
      const hits = matchCategoryOptions(box.value, opts);
      const only = hits.length === 1 ? list.querySelector('button[data-key]') : null;   // only an unambiguous match
      if (only) only.click();
    }
  });
  cell.insertBefore(box, sel);
  cell.appendChild(list);
}

function isAssignableNow(key, sel) {
  const row = categoryRow(key);
  return !!row && _isAssignableCategory(row) && [...sel.querySelectorAll('option[data-mlabel="1"]')].some(o => o.value === key);
}

// The line under the form (kept outside the form's one-row grid so its columns keep their width):
// account, kept date, history note and category suggestion on the left; Save & Add Another on the right.
function assistLine(p) {
  let line = document.getElementById('r2-line');
  if (!line) {
    line = el('div', { id: 'r2-line', style: 'margin-top:8px;display:flex;gap:12px;align-items:flex-start;justify-content:space-between' });
    line.appendChild(el('div', { id: 'r2-assist', style: 'display:flex;flex-wrap:wrap;gap:6px 16px;align-items:center;font-size:12px;color:var(--muted);flex:1;min-width:0' }));
    line.appendChild(el('div', { id: 'r2-actions', style: 'flex:none' }));
    if (p.grid && p.grid.parentElement === p.form) p.grid.insertAdjacentElement('afterend', line); else p.form.appendChild(line);
  }
  return line;
}
function renderAssist(p) {
  assistLine(p);
  const bar = document.getElementById('r2-assist');
  bar.textContent = '';
  bar.appendChild(el('span', { id: 'r2-account' }, 'Account: ' + accountLabel(_txLedgerAccountKey)));
  const dateInput = p.root.querySelector(DATE);
  const kept = carriedDate && _txFormData && _txFormData.transaction_date === carriedDate;
  if (dateInput) dateInput.style.outline = kept ? '2px solid var(--amber)' : '';
  if (kept) bar.appendChild(el('span', { id: 'r2-date-kept', style: 'color:var(--amber);font-weight:600' },
    'Date kept from your last entry (' + fmtDate(carriedDate) + ') — change it if this one is different.'));
  if (busy && !formSaving()) bar.appendChild(el('span', { id: 'r2-still-saving', style: 'color:var(--amber);font-weight:600' },
    'Your previous entry is still saving — wait a moment before saving this one.'));
  const rows = ledgerRows(), payee = (_txFormData && _txFormData.payee) || '';
  if (!rows) bar.appendChild(el('span', { id: 'r2-history-unavailable', style: 'color:var(--amber)' },
    'This account\'s history isn\'t loaded, so payee suggestions and the duplicate check are off for now.'));
  const s = rows ? suggestCategory(payee, rows, k => isAssignableNow(k, p.sel)) : null;
  if (s && s.categoryKey !== (_txFormData.category_key || '')) {
    const opt = [...p.sel.querySelectorAll('option[data-mlabel="1"]')].find(o => o.value === s.categoryKey);
    const label = opt ? opt.textContent : s.categoryKey;
    const wrap = el('span', { id: 'r2-suggest' });
    wrap.appendChild(el('span', null, 'Suggested category: '));
    wrap.appendChild(el('strong', { style: 'color:var(--text)' }, label));
    wrap.appendChild(el('span', null, ' — used for ' + s.count + ' of the last ' + s.of + ' “' + payee.trim() + '” entries in this account. '));
    const use = el('button', { type: 'button', id: 'r2-use-suggestion',
      style: 'font:inherit;font-size:12px;font-weight:600;padding:2px 8px;border:1px solid var(--blue);border-radius:5px;background:var(--surface);color:var(--blue);cursor:pointer' }, 'Use ' + label);
    use.addEventListener('click', () => _setTxFormField('category_key', s.categoryKey));
    wrap.appendChild(use);
    bar.appendChild(wrap);
  }
}

function renderWarning(p) {
  const old = document.getElementById('r2-dup');
  if (old) old.remove();
  if (!pending) return;
  const box = el('div', { id: 'r2-dup', role: 'alert',
    style: 'margin-top:10px;padding:10px 12px;border:1px solid var(--amber);border-radius:8px;background:var(--amberSoft);font-size:12px;color:var(--text)' });
  box.appendChild(el('div', { style: 'font-weight:700;margin-bottom:4px' }, 'Possible duplicate — nothing has been saved yet.'));
  box.appendChild(el('div', { style: 'margin-bottom:6px;color:var(--muted)' },
    'The Register already has an entry with the same account, amount and payee within ' + DUP_DAY_WINDOW + ' days:'));
  const ul = el('ul', { style: 'margin:0 0 8px 18px;padding:0' });
  pending.matches.slice(0, 3).forEach(r => ul.appendChild(el('li', null,
    'Possible duplicate: ' + (r.payee || '') + ' · ' + fmtAmount(r.amount) + ' · ' + accountLabel(r.account_key) + ' · ' + fmtDate(r.transaction_date, pending.date))));
  if (pending.matches.length > 3) ul.appendChild(el('li', null, '…and ' + (pending.matches.length - 3) + ' more'));
  box.appendChild(ul);
  const back = el('button', { type: 'button', id: 'r2-dup-back',
    style: 'font:inherit;font-size:12px;font-weight:600;padding:4px 12px;border:1px solid var(--line);border-radius:6px;background:var(--surface);color:var(--text);cursor:pointer;margin-right:6px' }, 'Go back');
  const go = el('button', { type: 'button', id: 'r2-dup-save',
    style: 'font:inherit;font-size:12px;font-weight:600;padding:4px 12px;border:1px solid var(--amber);border-radius:6px;background:var(--surface);color:var(--text);cursor:pointer' }, 'Save anyway');
  back.addEventListener('click', () => { pending = null; renderWarning(p); });
  go.addEventListener('click', saveAnyway);
  box.appendChild(back); box.appendChild(go);
  p.form.appendChild(box);
}

function renderSaveAnother(p) {
  let b = document.getElementById('r2-save-add');
  if (!b) {
    b = el('button', { type: 'button', id: 'r2-save-add' });
    b.addEventListener('click', () => requestSave('again'));
    assistLine(p);
    document.getElementById('r2-actions').appendChild(b);
  }
  const off = p.primary.disabled || busy;
  b.disabled = off;
  b.textContent = busy ? 'Saving…' : 'Save & Add Another';
  b.setAttribute('style', 'font-family:inherit;font-size:12px;font-weight:600;padding:5px 12px;border:1px solid var(--blue);border-radius:6px;white-space:nowrap;'
    + 'background:var(--surface);color:' + (off ? 'var(--muted2)' : 'var(--blue)') + ';cursor:' + (off ? 'default' : 'pointer'));
}

// ── Payee autocomplete (view). The list sits under the Payee field; nothing changes until the person accepts an
// item (Tab/Enter on the highlighted one, or a click). Escape dismisses; typing on or leaving the field keeps her text.
function payeeInput(root) { return root.querySelector(PAYEE); }
function closeAutocomplete() {
  ac = null;
  const l = document.getElementById('r2-payee-list');
  if (l) l.remove();
  const root = document.getElementById(ROOT_ID), inp = root && payeeInput(root);
  if (inp) { inp.setAttribute('aria-expanded', 'false'); inp.removeAttribute('aria-activedescendant'); }
}
function renderAutocomplete(inp) {
  let l = document.getElementById('r2-payee-list');
  if (!ac || !ac.items.length) { closeAutocomplete(); return; }
  if (!l) {
    l = el('div', { id: 'r2-payee-list', role: 'listbox', 'aria-label': 'Payees used in this account',
      style: 'position:absolute;left:0;right:0;top:100%;z-index:30;margin-top:2px;min-width:220px;background:var(--surface);border:1px solid var(--line);border-radius:6px;box-shadow:0 6px 16px rgba(0,0,0,.12);max-height:260px;overflow:auto' });
    inp.parentElement.style.position = 'relative';
    inp.parentElement.appendChild(l);
  }
  l.textContent = '';
  l.appendChild(el('div', { style: 'padding:5px 10px 3px;font-size:10.5px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em' },
    'Payees in this account' + (ac.index >= 0 ? ' · Tab or Enter to use' : ' · click or ↓ to choose')));
  ac.items.forEach((c, i) => {
    const o = el('div', { role: 'option', id: 'r2-payee-opt-' + i, 'data-payee': c.payee, 'aria-selected': i === ac.index ? 'true' : 'false',
      style: 'padding:6px 10px;font-size:12px;cursor:pointer;color:var(--text);' + (i === ac.index ? 'background:var(--blueSoft);' : '') }, c.payee);
    o.appendChild(el('span', { style: 'color:var(--muted);margin-left:6px' }, '· ' + c.count + (c.count === 1 ? ' entry' : ' entries')));
    o.addEventListener('mousedown', ev => ev.preventDefault());   // keep the cursor in Payee until the click lands
    o.addEventListener('click', () => acceptPayee(c.payee));
    l.appendChild(o);
  });
  if (ac.more) l.appendChild(el('div', { style: 'padding:5px 10px;font-size:11px;color:var(--muted)' }, ac.more + ' more — keep typing'));
  inp.setAttribute('aria-expanded', 'true');
  if (ac.index >= 0) inp.setAttribute('aria-activedescendant', 'r2-payee-opt-' + ac.index); else inp.removeAttribute('aria-activedescendant');
}
function updateAutocomplete(inp) {
  const rows = ledgerRows();
  const r = rows ? payeeCompletions(inp.value, rows) : { candidates: [] };
  ac = r.candidates.length ? { items: r.candidates, more: r.more, index: r.defaultIndex } : null;
  renderAutocomplete(inp);
}
// The person's explicit acceptance: only the payee changes (the category suggestion then re-evaluates separately).
function acceptPayee(name) {
  const root = document.getElementById(ROOT_ID), inp = root && payeeInput(root);
  closeAutocomplete();
  if (!inp || formMode() !== 'add') return;
  inp.value = name;
  _setTxFormField('payee', name);
  const p = formParts();
  if (p) { if (pending) { const c = proposedEntry(); if (!c || signature(c) !== pending.sig) { pending = null; renderWarning(p); } } renderAssist(p); }
}
function onPayeeKey(ev, inp) {
  if (ev.key === 'Escape') { if (ac) { ev.preventDefault(); closeAutocomplete(); } return; }
  if (ev.key === 'ArrowDown' || ev.key === 'ArrowUp') {
    if (!ac) { updateAutocomplete(inp); if (!ac) return; }
    ev.preventDefault();
    const n = ac.items.length;
    ac.index = ev.key === 'ArrowDown' ? Math.min(ac.index + 1, n - 1) : Math.max(ac.index - 1, -1);
    renderAutocomplete(inp);
    return;
  }
  if ((ev.key === 'Enter' || (ev.key === 'Tab' && !ev.shiftKey)) && ac && ac.index >= 0) {
    if (ev.key === 'Enter') ev.preventDefault();   // Tab still moves on to the next field as usual
    acceptPayee(ac.items[ac.index].payee);
  }
}

function augment() {
  const mode = formMode();
  if (busy && mode === 'edit') editDuringSave = true;
  if (mode !== 'add' && !busy) { carriedDate = null; pending = null; acknowledged = null; }
  const p = formParts();
  if (!p) return;
  // A cleared (blank/invalid) date stays blank on screen: the renderer redraws an empty date as today, which would
  // show a date the form does not hold. The data is never changed here; Save then gives "Date is required."
  const dateInput = p.root.querySelector(DATE);
  if (dateInput && typeof _txFormData !== 'undefined' && _txFormData && String(_txFormData.transaction_date || '') === '' && dateInput.value !== '') dateInput.value = '';
  enhanceCategory(p);
  ac = null;   // a re-render replaced the Payee field and its list
  if (mode !== 'add') return;
  renderSaveAnother(p);
  renderAssist(p);
  renderWarning(p);
}

async function requestSave(mode) {
  if (busy || formMode() !== 'add' || formSaving()) return;
  const c = proposedEntry();
  if (c) {
    const sig = signature(c);
    if (sig !== acknowledged) {
      const matches = findPossibleDuplicates(c, ledgerRows());
      if (matches.length) { pending = { sig, mode, matches, date: c.date }; augment(); return; }
    }
  }
  pending = null;
  await runSave(mode);
}
function saveAnyway() {
  if (!pending) return;
  const c = proposedEntry(), was = pending;
  pending = null;
  if (c && signature(c) === was.sig) acknowledged = was.sig;   // the decision covers exactly what was shown
  requestSave(was.mode);
}

async function runSave(mode) {
  busy = true; cancelled = false; editDuringSave = false;
  const account = _txLedgerAccountKey, saved = Object.assign({}, _txFormData);
  augment();
  let ok = false;
  try { ok = (await _saveTxForm()) === true; } catch (e) { ok = false; } finally { busy = false; }
  if (ok) { acknowledged = null; pending = null; carriedDate = null; }
  const reopen = ok && mode === 'again' && !cancelled && !editDuringSave && formMode() === null
    && _txLedgerAccountKey === account && !deleteConfirmOpen();
  if (!reopen) { augment(); return; }
  _openTxForm('add', null);
  if (formMode() !== 'add') return;
  const next = nextEntryFormData(saved, _txFormData);
  Object.keys(next).forEach(k => { if (next[k] !== _txFormData[k]) _setTxFormField(k, next[k]); });
  carriedDate = next.transaction_date === saved.transaction_date ? next.transaction_date : null;
  renderApp();
  const payee = document.querySelector('#' + ROOT_ID + ' ' + PAYEE);
  if (payee) payee.focus();
}

// Browser wiring (skipped when the module is loaded for tests).
if (typeof document !== 'undefined' && typeof window !== 'undefined') {
  const root = document.getElementById(ROOT_ID);
  if (root) {
    new MutationObserver(augment).observe(root, { childList: true });
    // The form's own Add button goes through the duplicate check first, then the same _saveTxForm.
    document.addEventListener('click', ev => {
      const t = ev.target;
      if (!t || !t.closest || !root.contains(t)) return;
      if (busy && t.closest(CANCEL)) { cancelled = true; return; }
      if (t.closest(PRIMARY) && formMode() === 'add') { ev.stopPropagation(); ev.preventDefault(); requestSave('save'); }
    }, true);
    // Any edit to the entry: a duplicate warning that no longer describes what is entered is withdrawn (the
    // next save re-checks), and the assist line (kept date, suggestion) follows the new values.
    // (A blur-time "change" from Payee must not rebuild the line: that would remove a button mid-click.)
    const onEdit = refreshLine => {
      if (formMode() !== 'add') return;
      const p = formParts();
      if (!p) return;
      if (pending) { const c = proposedEntry(); if (!c || signature(c) !== pending.sig) { pending = null; renderWarning(p); } }
      if (refreshLine) renderAssist(p);
    };
    root.addEventListener('input', ev => {
      if (!ev.target || ev.target.id === 'r2-cat-search') return;
      const isPayee = !!(ev.target.matches && ev.target.matches(PAYEE));
      onEdit(isPayee);
      if (isPayee && formMode() === 'add') updateAutocomplete(ev.target);
    });
    root.addEventListener('keydown', ev => { if (ev.target && ev.target.matches && ev.target.matches(PAYEE) && formMode() === 'add') onPayeeKey(ev, ev.target); });
    root.addEventListener('focusout', ev => { if (ev.target && ev.target.matches && ev.target.matches(PAYEE)) closeAutocomplete(); });
    root.addEventListener('change', ev => onEdit(!!(ev.target && ev.target.matches && ev.target.matches(DATE))));
    augment();
  }
  document.documentElement.setAttribute('data-hfos-register-assist', 'on');   // mount marker for acceptance checks
}
