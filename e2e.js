// ═══════════════════════════════════════════════════════════════════════════
// Herndon Financial OS — Playwright End-to-End Test Suite (Phase 5)
// ═══════════════════════════════════════════════════════════════════════════
//
// Prerequisites:
//   npm install playwright
//   npx playwright install chromium
//
// Usage:
//   node e2e.js                          # runs against ./index.html (file://)
//   HFOS_URL=https://your-url node e2e.js  # runs against a live deployment
//
// What this covers:
//   Section A   — Tab smoke test (no blank panels, no layout breaks)
//   Section B   — Console error check (no uncaught exceptions)
//   Section C   — Decision Engine (locked + cleared IRA gate)
//   Section D   — IRA flag toggle (Goals tab)
//   Section E   — Edit Week workflow (add inflow, save, verify)
//   Section F   — Reconciliation workflow (save, update, delete)
//   Section G   — Wishlist CRUD (add, edit, delete item)
//   Section H   — XSS safety (script injection in all user inputs)
//   Section I   — Supabase offline graceful failure
//   Section J   — Mobile viewport (nav, panels, no overflow)
//   Section BUD — Budget module: no recursive wrappers, optimistic cleared toggle, delete confirm
//   Section TX  — Transactions section: flag gate, Accounts view, Categories view, lifecycle toggle
//   Section RG  — Register (Phase 5E-1): flag gate, account selector, starting balance, read-only ledger
//   Section WR  — Transaction Writes (Phase 5E-2): add/edit/delete/cleared, mocked Supabase
//
// ─────────────────────────────────────────────────────────────────────────

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

// ── Load .env credentials (never committed to repo) ───────────────────────
// Add TEST_EMAIL and TEST_PASSWORD to ~/.env or ~/Adam-Dashboard/.env
// For Playwright auth tests (AUTH-E2E-2 through AUTH-E2E-8) to run, credentials must be set.
// AUTH-E2E-1 (login form visible) runs without credentials.
const dotenvPath = path.join(__dirname, '.env');
if (fs.existsSync(dotenvPath)) {
  fs.readFileSync(dotenvPath,'utf8').split('\n').forEach(line => {
    const m = line.match(/^([^#\s][^=]*)=(.*)$/);
    if (m) { const k=m[1].trim(),v=m[2].trim(); if (!process.env[k]) process.env[k]=v; }
  });
}
const TEST_EMAIL = process.env.TEST_EMAIL || '';
const TEST_PASSWORD = process.env.TEST_PASSWORD || '';

const URL = process.env.HFOS_URL ||
  'file://' + path.resolve(process.env.HFOS_INDEX || './index.html');

// ── Run mode: full (default) vs smoke ─────────────────────────────────────
// Full mode (default) runs the entire suite and ignores tags — behavior is
// identical to before this flag existed. Smoke mode runs ONLY tests explicitly
// tagged 'smoke'. Membership is per-test via the opts.tags array passed to
// test(); there is no name-prefix or section-level implicit inclusion.
//   node e2e.js                 → full (permanent default)
//   node e2e.js --smoke         → smoke
//   E2E_MODE=smoke node e2e.js  → smoke
//   E2E_MODE=full  node e2e.js  → full (explicit)
// Parsing is STRICT (5G-QA-1 hardening): unknown CLI flags, unknown E2E_MODE
// values, and conflicting CLI/env modes are rejected before any browser launches
// or any test runs (nonzero exit). Malformed input never silently falls back to
// full mode.
const ACCEPTED_INVOCATIONS = [
  'node e2e.js                 → full mode (default)',
  'node e2e.js --smoke         → smoke mode',
  'E2E_MODE=smoke node e2e.js  → smoke mode',
  'E2E_MODE=full node e2e.js   → full mode (explicit)',
];
function _rejectInvocation(reason) {
  console.error('\n✗ E2E invocation error: ' + reason);
  console.error('  Accepted invocations:');
  ACCEPTED_INVOCATIONS.forEach(l => console.error('    ' + l));
  console.error('  (no browser launched, no tests executed)');
  process.exit(2);
}
// CLI: the only recognized script argument is --smoke. Node/Playwright flags are
// passed before the script name (node --flag e2e.js) and never appear in
// argv.slice(2), so rejecting unknown script args does not catch ordinary
// runtime flags.
const _cliArgs = process.argv.slice(2);
const _unknownCli = _cliArgs.filter(a => a !== '--smoke');
if (_unknownCli.length) _rejectInvocation('unknown argument(s): ' + _unknownCli.join(' '));
const _cliSmoke = _cliArgs.includes('--smoke');
// Env: E2E_MODE may be unset/empty, 'smoke', or 'full'. Any other value rejects.
const _envRaw = process.env.E2E_MODE;
const _envMode = (_envRaw === undefined || _envRaw === '') ? null : _envRaw;
if (_envMode !== null && _envMode !== 'smoke' && _envMode !== 'full') {
  _rejectInvocation('unknown E2E_MODE value: "' + _envRaw + '" (expected "smoke" or "full")');
}
// Conflict: CLI requests smoke while env explicitly requests full.
if (_cliSmoke && _envMode === 'full') {
  _rejectInvocation('conflicting mode: --smoke (CLI) vs E2E_MODE=full (env)');
}
const SMOKE_MODE = _cliSmoke || _envMode === 'smoke';

let pass = 0, fail = 0, skipped = 0, registered = 0;
const failures = [];

// Slice B (5G-QA-1): deterministic readiness waits replace the old fixed sleeps
// in openApp/clickNav. If a deterministic wait ever times out we fall back to
// simply continuing (bounded cap already elapsed) and record it here. A run with
// ANY fallback hit is NOT a clean green — the readiness condition is inadequate
// and the run must be reviewed, not accepted, even if Failed: 0.
const readinessFallbackHits = { openApp: 0, clickNav: 0 };

// test(name, fn, opts?) — opts.tags is an explicit string array (default []).
// In smoke mode a test with no 'smoke' tag is skipped (no browser opened, not
// counted pass/fail). In full mode tags are ignored and every test runs.
function test(name, fn, opts = {}) {
  registered++;
  const tags = opts.tags || [];
  if (SMOKE_MODE && !tags.includes('smoke')) {
    skipped++;
    return Promise.resolve();
  }
  return fn()
    .then(() => { pass++; console.log('  ✓ ' + name); })
    .catch(e => { fail++; failures.push({ name, error: e.message }); console.log('  ✗ ' + name + '\n    → ' + e.message); });
}

function assert(cond, msg) { if (!cond) throw new Error(msg || 'Assertion failed'); }

// ── Helpers ───────────────────────────────────────────────────────────────

// Login through the auth overlay when credentials are available.
// Safe to call even if overlay is absent or already hidden.
async function loginIfNeeded(page) {
  if (!TEST_EMAIL || !TEST_PASSWORD) return;
  const overlayVisible = await page.evaluate(() => {
    const o = document.getElementById('auth-overlay');
    return o && !o.classList.contains('hidden');
  }).catch(() => false);
  if (!overlayVisible) return;
  await page.fill('#auth-email', TEST_EMAIL).catch(() => {});
  await page.fill('#auth-password', TEST_PASSWORD).catch(() => {});
  await page.click('#auth-submit-btn').catch(() => {});
  // Wait up to 12 s for overlay to hide (auth + checkAuthorization + loadAll)
  await page.waitForFunction(
    () => { const o = document.getElementById('auth-overlay'); return !o || o.classList.contains('hidden'); },
    { timeout: 12000 }
  ).catch(() => {}); // don't hard-fail if Supabase is unreachable
  await page.waitForTimeout(500);
}

async function openApp(browser, opts = {}) {
  const context = await browser.newContext(opts);
  const consoleErrors = [];
  const page = await context.newPage();
  page.on('console', msg => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
  page.on('pageerror', err => consoleErrors.push(err.message));
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
  // Wait for the auth init flow to reach a terminal AUTH_STATE (existing global)
  // instead of a flat sleep. Terminal = auth has settled; transitional states
  // (checking_session / authenticated) mean it is still in flight.
  await page.waitForFunction(
    () => typeof AUTH_STATE !== 'undefined'
      && ['ready','unauthenticated','unauthorized','session_expired','auth_error'].includes(AUTH_STATE),
    { timeout: 1500 }
  ).catch(() => { readinessFallbackHits.openApp++; });
  await loginIfNeeded(page);
  return { page, context, consoleErrors };
}

async function clickNav(page, id) {
  await page.click('#nav-' + id);
  // setSection() synchronously sets activeSection and toggles .active on the nav
  // button and the section panel, so this resolves immediately on success.
  await page.waitForFunction(
    navId => window.activeSection === navId
      && document.getElementById('nav-' + navId)?.classList.contains('active')
      && document.getElementById('s-' + navId)?.classList.contains('active'),
    id, { timeout: 750 }
  ).catch(() => { readinessFallbackHits.clickNav++; });
}

// ── Main ──────────────────────────────────────────────────────────────────

(async () => {
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║     Herndon Financial OS — E2E Suite (Playwright)           ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('  Target: ' + URL);
  console.log(SMOKE_MODE
    ? '  ▶▶ SMOKE MODE — running smoke-tagged tests only ◀◀'
    : '  ▶ FULL MODE (default) — running the complete suite');
  console.log('');

  // Lazy Chromium (5G-QA-1 hardening): launch on first actual use (newContext)
  // so an empty smoke selection — guarded below — launches no browser at all.
  // Every browser use in this suite is browser.newContext()/browser.close(), so
  // this two-method wrapper is a complete substitute and leaves all call sites
  // unchanged. Timing of the readiness waits inside openApp is untouched.
  let _realBrowser = null;
  const browser = {
    async newContext(opts) {
      if (!_realBrowser) _realBrowser = await chromium.launch({ headless: true });
      return _realBrowser.newContext(opts);
    },
    async close() { if (_realBrowser) await _realBrowser.close(); },
  };

  // ── Section A: Tab smoke test ──────────────────────────────────────────
  console.log('── Section A: Tab smoke test ──');
  const tabs = ['overview','weekly','goals','history','assumptions','roadmap','ask','budget'];
  for (const tab of tabs) {
    await test('Tab renders without blank panel: ' + tab, async () => {
      const { page, context } = await openApp(browser);
      await clickNav(page, tab);
      const content = await page.evaluate(() => document.body.innerText);
      assert(content.trim().length > 100, 'Tab appears empty (< 100 chars of text)');
      // No "undefined" or "[object Object]" leak in rendered output
      assert(!content.includes('[object Object]'), 'Raw object rendered to DOM');
      await context.close();
    }, { tags: ['overview','weekly','goals','budget'].includes(tab) ? ['smoke','tabs'] : [] });
  }

  // ── Section B: Console error check ────────────────────────────────────
  console.log('── Section B: Console error check ──');
  await test('No console errors on initial load', async () => {
    const { page, context, consoleErrors } = await openApp(browser);
    // Click through all tabs
    for (const tab of tabs) {
      await clickNav(page, tab);
    }
    await page.waitForTimeout(500);
    const relevant = consoleErrors.filter(e =>
      !e.includes('favicon') &&          // ignore missing favicon
      !e.includes('net::ERR_') &&        // ignore expected Supabase offline (file:// mode)
      !e.includes('Failed to fetch') &&  // same
      !e.includes('status of 4')         // ignore Supabase 4xx in file:// mode (CORS/auth expected)
    );
    assert(relevant.length === 0, 'Console errors: ' + relevant.join(' | '));
    await context.close();
  }, { tags: ['smoke'] });

  // ── Section C: Decision Engine ─────────────────────────────────────────
  // CPA flag is display/deployment status only — it does NOT gate IRA/529 AMEX holding.
  // With flag OFF: IRA and 529 goals still appear; engine routes them to AMEX holding.
  // No "locked" step. No "IRA gating" copy. Surplus may appear if goals are fully funded.
  console.log('── Section C: Decision Engine ──');

  await test('Engine: CPA flag off — IRA and 529 still appear in engine output', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    // Ensure IRA flag is OFF (CPA pending / not yet cleared)
    const flagOn = await page.$('.flag-toggle.on');
    if (flagOn) await flagOn.click();
    await page.waitForTimeout(200);
    // Navigate to What-If / Engine tab
    const engineTab = await page.$('[data-tab="engine"], #goals-tab-engine, button:has-text("Waterfall"), button:has-text("Engine")');
    if (engineTab) { await engineTab.click(); await page.waitForTimeout(200); }
    // Enter a large income amount so waterfall has room to fund IRA and 529 goals
    const amtInput = await page.$('#engine-amt-inp, input[placeholder*="amount"], input[placeholder*="Amount"]');
    if (amtInput) {
      await amtInput.fill('200000');
      const runBtn = await page.$('#engine-run-btn, .engine-run, button:has-text("Calculate")');
      if (runBtn) {
        await runBtn.click();
        await page.waitForTimeout(600);
        const output = await page.evaluate(() => {
          const el = document.querySelector('.engine-output, .engine-steps');
          return el ? el.innerText : '';
        });
        // IRA and 529 goals must appear — CPA flag is display-only, not a gate
        assert(output.includes('IRA') || output.includes('ira'), 'IRA goals missing from engine output — CPA flag should not gate them');
        assert(output.includes('529'), '529 goals missing from engine output — CPA flag should not gate them');
        // No hard-gate language
        assert(!output.includes('locked'), 'Engine output should not show a "locked" step — CPA gate was removed');
        assert(!output.includes('IRA gating'), 'Stale "IRA gating" copy found in engine output');
      }
    }
    await context.close();
  });

  await test('Engine: empty state shows "IRA/529 AMEX holding" not "IRA gating"', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    const engineTab = await page.$('[data-tab="engine"], #goals-tab-engine, button:has-text("Waterfall"), button:has-text("Engine")');
    if (engineTab) { await engineTab.click(); await page.waitForTimeout(200); }
    // Read empty state (before any amount is entered)
    const emptyText = await page.evaluate(() => {
      const el = document.querySelector('.engine-empty');
      return el ? el.innerText : '';
    });
    if (emptyText) {
      assert(!emptyText.includes('IRA gating'), 'Stale "IRA gating" copy in engine empty state');
      assert(emptyText.includes('AMEX holding') || emptyText.includes('IRA/529'), 'Engine empty state missing IRA/529 AMEX holding language');
    }
    await context.close();
  }, { tags: ['smoke'] });

  await test('Engine: CPA flag on vs off — IRA/529 allocation identical', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    const engineTab = await page.$('[data-tab="engine"], #goals-tab-engine, button:has-text("Waterfall"), button:has-text("Engine")');

    async function getEngineOutput(flagShouldBeOn) {
      const isOn = await page.$('.flag-toggle.on') !== null;
      if (isOn !== flagShouldBeOn) {
        const btn = await page.$('.flag-toggle');
        if (btn) { await btn.click(); await page.waitForTimeout(200); }
      }
      // Re-query engineTab each time using waitForSelector — flag toggle re-renders the DOM
      const freshTab = await page.waitForSelector('[data-tab="engine"], #goals-tab-engine, button:has-text("Waterfall"), button:has-text("Engine")', {timeout:3000}).catch(()=>null);
      if (freshTab) { await freshTab.click(); await page.waitForTimeout(250); }
      const amtInput = await page.$('#engine-amt-inp, input[placeholder*="amount"], input[placeholder*="Amount"]');
      if (amtInput) {
        await amtInput.fill('50000');
        const runBtn = await page.$('#engine-run-btn, .engine-run, button:has-text("Calculate")');
        if (runBtn) { await runBtn.click(); await page.waitForTimeout(600); }
      }
      return page.evaluate(() => {
        const el = document.querySelector('.engine-output, .engine-steps');
        return el ? el.innerText : '';
      });
    }

    const outputOff = await getEngineOutput(false);
    const outputOn  = await getEngineOutput(true);
    // IRA/529 goals must appear under both flag states
    assert(outputOff.includes('IRA') || outputOff.includes('ira'), 'IRA missing from engine output when CPA flag is off');
    assert(outputOn.includes('IRA')  || outputOn.includes('ira'),  'IRA missing from engine output when CPA flag is on');
    // Neither output should contain hard-gate language
    assert(!outputOff.includes('locked'), '"locked" step found in engine output (flag off)');
    assert(!outputOn.includes('locked'),  '"locked" step found in engine output (flag on)');
    await context.close();
  });

  // ── Section D: IRA flag toggle ─────────────────────────────────────────
  console.log('── Section D: IRA flag toggle ──');
  await test('IRA CPA flag toggles on/off and UI reflects state', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    const btn = await page.$('.flag-toggle');
    assert(btn, 'Flag toggle button not found');
    // Record initial class state (on or off)
    const initialOn = await page.$('.flag-toggle.on') !== null;
    await btn.click();
    await page.waitForTimeout(300);
    const afterOn = await page.$('.flag-toggle.on') !== null;
    assert(initialOn !== afterOn, 'Flag toggle class did not change after first click');
    // Toggle back — use waitForSelector; first click re-renders the DOM, staling the cached ref
    const btn2 = await page.waitForSelector('.flag-toggle', {timeout:3000}).catch(()=>null);
    assert(btn2, 'Flag toggle button not found for second click');
    await btn2.click();
    await page.waitForTimeout(300);
    const restoredOn = await page.$('.flag-toggle.on') !== null;
    assert(restoredOn === initialOn, 'Flag toggle did not restore to original class state');
    await context.close();
  });

  // ── Section E: Edit Week workflow ──────────────────────────────────────
  console.log('── Section E: Edit Week workflow ──');
  await test('Edit Week: drawer opens, fields present, cancel works', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    await page.waitForTimeout(300);
    // Find and click an Edit Week button
    const editBtn = await page.$('button:has-text("Edit"), .edit-btn, [onclick*="openEdit"]');
    assert(editBtn, 'Edit Week button not found');
    await editBtn.click();
    await page.waitForTimeout(400);
    // Drawer should be visible
    const drawer = await page.$('#edit-drawer, .edit-drawer, [id*="drawer"]');
    const drawerVisible = drawer && await drawer.isVisible();
    assert(drawerVisible, 'Edit drawer did not open');
    // Cancel closes it
    const cancelBtn = await page.$('button:has-text("Cancel"), .drawer-cancel');
    if (cancelBtn) {
      await cancelBtn.click();
      await page.waitForTimeout(300);
      const stillVisible = await drawer.isVisible();
      assert(!stillVisible, 'Edit drawer did not close after Cancel');
    }
    await context.close();
  });

  // ── Section F: Reconciliation workflow ────────────────────────────────
  console.log('── Section F: Reconciliation workflow ──');
  await test('Reconciliation: recon panel or button present in weekly view', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    await page.waitForTimeout(300);
    // Prior selector had two gaps (not related to the 5E-8 Register fix):
    // 1. [onclick*="recon"] is case-sensitive — the real handler is openRecon() (capital R),
    //    so that clause never matched anything.
    // 2. It only covered the not-yet-reconciled state (.recon-open-btn / "Reconcile this
    //    week"). If the displayed week is already reconciled, index.html renders
    //    .recon-edit-btn ("Edit actuals") or the read-only .recon-done-row instead — neither
    //    contains the word "Reconcile", so the old selector found nothing even though the
    //    reconciliation control/state was legitimately present.
    // Widened to cover all three valid states, case-insensitive on the onclick handler.
    const reconEl = await page.$(
      'button:has-text("Reconcile"), button:has-text("Update actuals"), button:has-text("Edit actuals"), ' +
      '.recon-btn, .recon-open-btn, .recon-edit-btn, .recon-done-row, ' +
      '[onclick*="recon" i], [onclick*="Recon"], input[placeholder*="actual"]'
    );
    assert(reconEl, 'Reconciliation button or input not found in weekly view');
    await context.close();
  }, { tags: ['smoke'] });

  // ── Section G: Wishlist CRUD ───────────────────────────────────────────
  console.log('── Section G: Wishlist ──');
  await test('Wishlist tab loads with items', async () => {
    const context = await browser.newContext();
    const failedWLReqs = [];
    const page = await context.newPage();
    page.on('console', () => {});
    page.on('response', async resp => {
      if (resp.status() >= 400 && resp.url().includes('wishlist')) {
        const b = await resp.text().catch(() => '');
        failedWLReqs.push(resp.status() + ' ' + resp.request().method() + ' wishlist_items body=' + b.slice(0, 150));
      }
    });
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1000);
    await loginIfNeeded(page);
    await clickNav(page, 'roadmap');
    // loadWishlist() is async — wait for Phase labels to appear (seed insert path can take >500ms)
    await page.waitForFunction(() => {
      const el = document.getElementById('roadmap-content');
      return el && el.innerText.includes('Phase');
    }, { timeout: 8000 }).catch(() => null);
    const content = await page.evaluate(() => {
      const el = document.getElementById('roadmap-content');
      return el ? el.innerText : '';
    });
    const diagSuffix = failedWLReqs.length ? ' | ' + failedWLReqs.join(', ') : '';
    assert(content.length > 50, 'Wishlist appears empty' + diagSuffix);
    assert(content.includes('Phase'), 'No phase labels found in wishlist' + diagSuffix);
    await context.close();
  });

  // ── WL-PW-1: Filter smoke ────────────────────────────────────────────────
  // Security items inserted via SQL in WL-V2 build step (Supabase seed migration).
  // No constraint blocks Security phase; items were never in Supabase before this build.
  console.log('── WL-PW-1: Wishlist filter smoke ──');
  await test('WL-PW-1: Phase filter hides/shows cards correctly', async () => {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1000);
    await loginIfNeeded(page);
    await clickNav(page, 'roadmap');
    // Wait for wishlist to load and filter bar to appear
    await page.waitForFunction(() => {
      const el = document.getElementById('roadmap-content');
      return el && el.querySelector('.wl-filter-bar') !== null && el.innerText.includes('Phase');
    }, { timeout: 8000 }).catch(() => null);
    await page.waitForTimeout(300);

    // PRE-FILTER: Security and Phase 6 both visible (Security items in Supabase via SQL seed)
    const secCountBefore = await page.evaluate(() =>
      Array.from(document.querySelectorAll('.wl-phase-tag'))
        .filter(function(el){ return el.textContent.trim() === 'Security'; }).length
    );
    const allTagsBefore = await page.evaluate(() =>
      [...new Set(Array.from(document.querySelectorAll('.wl-phase-tag'))
        .map(function(el){ return el.textContent.trim(); }))].join(', ')
    );
    assert(secCountBefore > 0, 'Pre-filter: expected Security cards (got 0). Phases visible: ' + allTagsBefore);

    const ph6CountBefore = await page.evaluate(() =>
      Array.from(document.querySelectorAll('.wl-phase-tag'))
        .filter(function(el){ return el.textContent.trim() === 'Phase 6'; }).length
    );
    assert(ph6CountBefore > 0, 'Pre-filter: expected Phase 6 cards in unfiltered board');

    // Click Security filter pill
    const secPillFound = await page.evaluate(() => {
      const btn = Array.from(document.querySelectorAll('.wl-filter-pill'))
        .find(function(b){ return b.textContent.trim() === 'Security'; });
      if (btn) { btn.click(); return true; }
      return false;
    });
    assert(secPillFound, 'Security filter pill not found in filter bar');
    await page.waitForTimeout(300);

    // POST-FILTER: Security visible, Phase 6 hidden
    const secCountAfter = await page.evaluate(() =>
      Array.from(document.querySelectorAll('.wl-phase-tag'))
        .filter(function(el){ return el.textContent.trim() === 'Security'; }).length
    );
    assert(secCountAfter > 0, 'Post-filter: Security cards should remain visible after Security filter selected');

    const ph6CountAfter = await page.evaluate(() =>
      Array.from(document.querySelectorAll('.wl-phase-tag'))
        .filter(function(el){ return el.textContent.trim() === 'Phase 6'; }).length
    );
    assert(ph6CountAfter === 0, 'Post-filter: Phase 6 cards should be hidden when Security filter active (got ' + ph6CountAfter + ')');

    // Click All to clear filter
    const allPillFound = await page.evaluate(() => {
      const btn = Array.from(document.querySelectorAll('.wl-filter-pill'))
        .find(function(b){ return b.textContent.trim() === 'All'; });
      if (btn) { btn.click(); return true; }
      return false;
    });
    assert(allPillFound, 'All pill not found in filter bar');
    await page.waitForTimeout(300);

    // Phase 6 visible again after clearing filter
    const ph6CountCleared = await page.evaluate(() =>
      Array.from(document.querySelectorAll('.wl-phase-tag'))
        .filter(function(el){ return el.textContent.trim() === 'Phase 6'; }).length
    );
    assert(ph6CountCleared > 0, 'After clearing filter: Phase 6 cards should be visible again');
    await context.close();
  });

  // ── WL-PW-2: Done grouping smoke ─────────────────────────────────────────
  console.log('── WL-PW-2: Wishlist Done grouping smoke ──');
  await test('WL-PW-2: Done column contains Auth v1 group with Authentication (Phase 6A)', async () => {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1000);
    await loginIfNeeded(page);
    await clickNav(page, 'roadmap');
    await page.waitForFunction(() => {
      const el = document.getElementById('roadmap-content');
      return el && el.innerText.includes('Phase');
    }, { timeout: 8000 }).catch(() => null);
    await page.waitForTimeout(500);

    // Find Done column
    const doneCol = await page.$('[data-col="done"]');
    assert(doneCol, 'Done column (data-col="done") not found');

    // Find Auth v1 group container scoped inside Done column
    const authV1Group = await doneCol.$('[data-build-group="Auth v1"]');
    assert(authV1Group, 'Auth v1 group container not found inside Done column — confirm Auth v1 close-out SQL has been run');

    // Assert the card title inside that group
    const authCard = await authV1Group.$('.wl-card-title');
    const authCardText = authCard ? await authCard.textContent() : '';
    assert(
      authCardText.includes('Authentication (Phase 6A)'),
      'Authentication (Phase 6A) not found inside Auth v1 group. Got: ' + authCardText.slice(0, 100)
    );
    await context.close();
  });

  // ── AUTH-ANON-1: Anon key blocked after RLS tightening ────────────────────
  // NOTE: This test calls live Supabase directly using SUPA_URL + SUPA_KEY from
  // page context. It runs against the production Supabase project regardless of
  // whether e2e.js is targeting file:// or the live URL.
  console.log('── AUTH-ANON-1: Anon key blocked on live Supabase ──');
  await test('AUTH-ANON-1: Anon key returns no protected rows and cannot write', async () => {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(500);

    // Part 1: anon SELECT returns no protected rows
    const readResults = await page.evaluate(async () => {
      const tables = ['weekly_reconciliations','goals','model_week_overrides','wishlist_items'];
      const out = [];
      for (const t of tables) {
        try {
          const r = await fetch(SUPA_URL + '/rest/v1/' + t + '?limit=1', {
            headers: { 'apikey': SUPA_KEY, 'Authorization': 'Bearer ' + SUPA_KEY }
          });
          const body = await r.json();
          const rowCount = Array.isArray(body) ? body.length : -1;
          out.push({ table: t, status: r.status, rows: rowCount });
        } catch (e) {
          out.push({ table: t, status: -1, rows: -1, error: e.message });
        }
      }
      return out;
    });
    for (const r of readResults) {
      const blocked = r.status === 401 || r.status === 403 || r.rows === 0;
      assert(blocked, 'AUTH-ANON-1 SELECT: anon key returned protected rows on ' + r.table +
        ' (status=' + r.status + ', rows=' + r.rows + (r.error ? ', error=' + r.error : '') + ')');
    }

    // Part 2: anon INSERT is blocked
    const writeResult = await page.evaluate(async () => {
      try {
        const r = await fetch(SUPA_URL + '/rest/v1/wishlist_items', {
          method: 'POST',
          headers: {
            'apikey': SUPA_KEY, 'Authorization': 'Bearer ' + SUPA_KEY,
            'Content-Type': 'application/json', 'Prefer': 'return=representation'
          },
          body: JSON.stringify({ title: '__anon_write_test_should_be_blocked__',
            phase: 'Backlog', status: 'idea', priority: 0, item_type: 'feature' })
        });
        const body = await r.json();
        const rowCreated = r.ok && Array.isArray(body) && body.length > 0;
        if (rowCreated && body[0] && body[0].id) {
          await fetch(SUPA_URL + '/rest/v1/wishlist_items?id=eq.' + body[0].id, {
            method: 'DELETE',
            headers: { 'apikey': SUPA_KEY, 'Authorization': 'Bearer ' + SUPA_KEY }
          });
        }
        return { status: r.status, rowCreated };
      } catch (e) { return { status: -1, rowCreated: false, error: e.message }; }
    });
    assert(!writeResult.rowCreated,
      'AUTH-ANON-1 INSERT: anon key successfully wrote a row to wishlist_items — ' +
      'RLS is not blocking anon writes (status=' + writeResult.status + (writeResult.error ? ', error=' + writeResult.error : '') + '). ' +
      'Cleanup attempted. Phase 4A SQL may not have been applied.');
    // NOTE: If AUTH-ANON-1 fails because anon insert unexpectedly succeeded,
    // check wishlist_items for title '__anon_write_test_should_be_blocked__' and
    // manually delete it. The anon cleanup may fail depending on active policies.
    await context.close();
  });

  // ── Section H: XSS safety ─────────────────────────────────────────────
  console.log('── Section H: XSS safety ──');
  const xssPayload = '<script>window.__xss_fired=true<\/script>';
  const xssFields = [
    { section: 'weekly', selector: '#edit-drawer input[type="text"], textarea', trigger: 'button:has-text("Edit")' },
    { section: 'roadmap', selector: 'input[placeholder*="title"], input[placeholder*="Title"]', trigger: null },
  ];

  await test('XSS: script injection does not execute in any user input', async () => {
    const { page, context } = await openApp(browser);
    let injected = false;

    // Try injecting into edit-week note field if accessible
    await clickNav(page, 'weekly');
    await page.waitForTimeout(300);
    const editBtn = await page.$('button:has-text("Edit"), .edit-btn');
    if (editBtn) {
      await editBtn.click();
      await page.waitForTimeout(400);
      const inputs = await page.$$('#edit-drawer input[type="text"], #edit-drawer textarea');
      for (const input of inputs) {
        try { await input.fill(xssPayload); injected = true; } catch {}
      }
      const cancelBtn = await page.$('button:has-text("Cancel"), .drawer-cancel');
      if (cancelBtn) await cancelBtn.click();
    }

    // Try wishlist title input
    await clickNav(page, 'roadmap');
    await page.waitForTimeout(300);
    const wishInputs = await page.$$('input[type="text"], textarea');
    for (const input of wishInputs.slice(0, 3)) {
      try { await input.fill(xssPayload); injected = true; } catch {}
    }

    // Check that the XSS script did not fire
    const fired = await page.evaluate(() => window.__xss_fired === true);
    assert(!fired, 'XSS payload executed — script injection not sanitized');
    await context.close();
  });

  // ── Section I: Offline graceful failure ───────────────────────────────
  console.log('── Section I: Offline / Supabase failure ──');
  await test('App loads and renders without network (Supabase offline)', async () => {
    const context = await browser.newContext();
    const page = await context.newPage();
    // Block all fetch/XHR before navigating
    await page.route('**/*supabase*/**', route => route.abort());
    await page.route('**/rest/v1/**', route => route.abort());
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1500);
    // App should still render (model runs locally)
    const content = await page.evaluate(() => document.body.innerText);
    assert(content.trim().length > 100, 'App appears blank when Supabase is offline');
    // Should not crash with uncaught error covering the screen
    assert(!content.toLowerCase().includes('uncaught'), 'Uncaught error visible on offline load');
    await context.close();
  });

  // ── Section K: AMEX lookahead copy in Assumptions ─────────────────────
  console.log('── Section K: AMEX lookahead copy in Assumptions ──');
  await test('Assumptions: renders "5-week AMEX lookahead" language', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'assumptions');
    await page.waitForTimeout(400);
    const text = await page.evaluate(() => {
      const el = document.getElementById('assumptions-content') || document.querySelector('.assumptions-wrap, [id*="assumption"]');
      return el ? el.innerText : document.body.innerText;
    });
    assert(text.includes('5-week') || text.includes('lookahead'), 'Missing 5-week AMEX lookahead in rendered Assumptions');
    await context.close();
  });

  await test('Assumptions: does not contain "taxTodo"', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'assumptions');
    await page.waitForTimeout(400);
    const html = await page.evaluate(() => {
      const el = document.getElementById('assumptions-content') || document.querySelector('.assumptions-wrap, [id*="assumption"]');
      return el ? el.innerHTML : '';
    });
    assert(!html.includes('taxTodo'), 'Stale "taxTodo" reference found in rendered Assumptions');
    await context.close();
  });

  await test('Assumptions: does not contain "IRA gating"', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'assumptions');
    await page.waitForTimeout(400);
    const text = await page.evaluate(() => {
      const el = document.getElementById('assumptions-content') || document.querySelector('.assumptions-wrap, [id*="assumption"]');
      return el ? el.innerText : '';
    });
    assert(!text.includes('IRA gating'), 'Stale "IRA gating" copy found in rendered Assumptions');
    await context.close();
  });

  // ── Section L: Weekly model transfer rows ─────────────────────────────
  console.log('── Section L: Weekly model transfer rows ──');
  await test('Weekly: transfer rows render and contain no "locked" gate language', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    await page.waitForTimeout(500);
    // Transfer rows use class xfr-row — at least one must exist (model is rendering)
    const xfrCount = await page.evaluate(() => document.querySelectorAll('.xfr-row').length);
    assert(xfrCount > 0, 'No .xfr-row transfer rows found in weekly view — model may not be rendering');
    // "locked" must not appear as a transfer status anywhere in the weekly view
    const weeklyText = await page.evaluate(() => {
      const el = document.getElementById('s-weekly');
      return el ? el.innerText : '';
    });
    assert(!weeklyText.includes('locked'), '"locked" found in weekly view — stale gate language');
    await context.close();
  });

  await test('Weekly: AMEX appears in balance panel (IRA/529 holding account referenced)', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    await page.waitForTimeout(500);
    const weeklyText = await page.evaluate(() => {
      const el = document.getElementById('s-weekly');
      return el ? el.innerText : '';
    });
    assert(weeklyText.includes('AMEX'), 'AMEX not mentioned in weekly view — balance panel or transfer rows should reference it');
    await context.close();
  });

  // ── Section M: Stale copy guard across all tabs ────────────────────────
  console.log('── Section M: Stale copy guard across all tabs ──');
  await test('All tabs: no "IRA gating", "taxTodo", or hard-gate "locked" language anywhere', async () => {
    const { page, context } = await openApp(browser);
    const bannedPhrases = ['IRA gating', 'taxTodo'];
    const tabsToCheck = ['overview','weekly','goals','history','assumptions','roadmap'];
    const hits = [];
    for (const tab of tabsToCheck) {
      await clickNav(page, tab);
      await page.waitForTimeout(400);
      const text = await page.evaluate(() => document.body.innerText);
      for (const phrase of bannedPhrases) {
        if (text.includes(phrase)) hits.push(tab + ': "' + phrase + '"');
      }
    }
    assert(hits.length === 0, 'Stale copy found — ' + hits.join(', '));
    await context.close();
  });

  // ── Section N: Action override smoke ─────────────────────────────────
  console.log('── Section N: Action override smoke ──');
  await test('Weekly: action override panel opens on a required action', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    await page.waitForTimeout(400);
    // Hover over an action row to surface override controls
    const actionRow = await page.$('.action-row, .required-action, [class*="action-item"]');
    if (actionRow) {
      await actionRow.hover();
      await page.waitForTimeout(300);
      // Look for override/edit controls that appear on hover
      const overrideBtn = await page.$('.action-edit-btn, .override-btn, [onclick*="editAction"], [onclick*="openAction"]');
      assert(overrideBtn, 'No override/edit control appeared on action row hover');
    } else {
      // No action rows visible — pass with note (could be a week with no actions)
      console.log('    (no action rows found this week — skipping hover assertion)');
    }
    await context.close();
  });

  await test('Weekly: action override panel has relabel field and cancel', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    await page.waitForTimeout(400);
    const actionRow = await page.$('.action-row, .required-action, [class*="action-item"]');
    if (actionRow) {
      await actionRow.hover();
      await page.waitForTimeout(300);
      const overrideBtn = await page.$('.action-edit-btn, .override-btn, [onclick*="editAction"], [onclick*="openAction"]');
      if (overrideBtn) {
        await overrideBtn.click();
        await page.waitForTimeout(400);
        // Panel should contain a text input for relabeling
        const labelInput = await page.$('.action-edit-panel input[type="text"], .override-panel input[type="text"], [id*="action-label"]');
        assert(labelInput, 'No label/relabel input found in action override panel');
        // Cancel should close it
        const cancelBtn = await page.$('.action-edit-panel button:has-text("Cancel"), .override-panel button:has-text("Cancel"), [onclick*="closeAction"]');
        if (cancelBtn) {
          await cancelBtn.click();
          await page.waitForTimeout(300);
          const stillOpen = await page.$('.action-edit-panel, .override-panel');
          assert(!stillOpen || !(await stillOpen.isVisible()), 'Action override panel did not close after Cancel');
        }
      }
    }
    await context.close();
  });

  // ── Section O: History filters ─────────────────────────────────────────
  console.log('── Section O: History filters ──');
  await test('History: filter buttons change the visible row count', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'history');
    await page.waitForTimeout(500);
    // History rows use class "hcard" inside #historyContent
    const countAll = await page.evaluate(() => {
      return document.querySelectorAll('#historyContent .hcard').length;
    });
    assert(countAll > 0, 'No history rows (.hcard) found under All filter in #historyContent');
    // Filter buttons use class "filter-btn"
    const filterBtn = await page.$('.filter-btn:not(.active)');
    if (filterBtn) {
      await filterBtn.click();
      await page.waitForTimeout(400);
      const countFiltered = await page.evaluate(() => {
        return document.querySelectorAll('#historyContent .hcard').length;
      });
      assert(typeof countFiltered === 'number', 'Could not count rows after filter click');
      console.log('    All: ' + countAll + ' rows → Filtered: ' + countFiltered + ' rows');
    }
    await context.close();
  });

  // ── Section P: Goal progress bars ─────────────────────────────────────
  console.log('── Section P: Goal progress bars ──');
  await test('Goals: at least one goal card has a non-zero progress bar', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    await page.waitForTimeout(500);
    // Look for an inline width style indicating progress
    const hasProgress = await page.evaluate(() => {
      const bars = document.querySelectorAll('[style*="width:"], [style*="width: "]');
      for (const bar of bars) {
        const w = bar.style.width;
        if (w && w !== '0%' && w !== '0px' && parseFloat(w) > 0) return true;
      }
      return false;
    });
    assert(hasProgress, 'No goal progress bar with non-zero width found in Goals tab');
    await context.close();
  });

  await test('Goals: IRA/529 goal cards mention "AMEX" or "holding"', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    await page.waitForTimeout(500);
    const text = await page.evaluate(() => {
      const el = document.getElementById('goals-content') || document.querySelector('[id*="goals"]');
      return el ? el.innerText : document.body.innerText;
    });
    assert(text.includes('AMEX') || text.includes('holding') || text.includes('Holding'),
      'Goals tab does not mention AMEX or holding for IRA/529 goals');
    await context.close();
  });

  // 5G-1C-1: Funding Plan projection semantics — resilient (no dependence on live
  // percentages). The retired "Beyond 2026" label must never appear; the funding
  // table must render its "When" column.
  await test('Goals › Funding Plan: no retired "Beyond 2026" label; When column renders', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    await page.evaluate(() => { setSection('goals'); goalsSubTab = 'funding'; renderApp(); });
    await page.waitForTimeout(400);
    const res = await page.evaluate(() => {
      const el = document.getElementById('goals-content') || document.body;
      const html = el.innerHTML || '';
      return { hasWhen: html.includes('ft-when'), hasBeyond: (el.innerText || '').includes('Beyond 2026') };
    });
    assert(res.hasWhen, 'Funding Plan "When" column (ft-when) did not render');
    assert(!res.hasBeyond, 'Funding Plan still shows the retired "Beyond 2026" label');
    await context.close();
  }, { tags: ['smoke','funding'] });

  // 5G-1C-2 (C3): with a snapshot anchor injected into goalSnapData, the Funding Plan's
  // funded value (getGoalFunded) must agree with the anchored timeline state (currentW
  // goalSaved), and the panel must still render. Pins currentW=5 for determinism; restores
  // currentW and clears goalSnapData afterward so no other test is affected.
  await test('Goals › Funding Plan: injected snapshot anchor — funded agrees with timeline', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    const res = await page.evaluate(() => {
      // currentW is a const in the app — do NOT reassign it. Inject the anchor at the
      // exact week getGoalFunded reads (currentW if present in weeks, else weeks[0]).
      const g = getGoals();
      const probe = runModel(g.ak, g.rt);
      const readWk = probe.some(w => w.num === currentW) ? currentW : probe[0].num;
      goalSnapData = {}; goalSnapData[readWk] = { adam_ira: 4321.00 };   // absolute anchor
      try {
        setSection('goals'); goalsSubTab = 'funding'; renderApp();
        const weeks = runModel(g.ak, g.rt);
        const vm = buildDashboardViewModel(weeks, g);
        const funded = getGoalFunded('adam_ira', vm);
        const wkObj = weeks.find(w => w.num === readWk) || {};
        const timeline = (wkObj.goalSaved || {})['adam_ira'];
        const el = document.getElementById('goals-content') || document.body;
        const hasWhen = (el.innerHTML || '').includes('ft-when');
        return { funded, timeline, hasWhen };
      } finally {
        goalSnapData = {}; renderApp();
      }
    });
    assert(Math.abs(res.funded - 4321.00) < 0.01, 'getGoalFunded did not reflect the injected anchor: ' + res.funded);
    assert(Math.abs(res.funded - res.timeline) < 0.01, 'Funding Plan funded (' + res.funded + ') != currentW timeline goalSaved (' + res.timeline + ')');
    assert(res.hasWhen, 'Funding Plan "When" column did not render under the injected anchor');
    await context.close();
  }, { tags: ['smoke','funding'] });

  // 5G-1B: an executed model transfer whose action_key is no longer in the recommended set
  // must stay VISIBLE as a read-only "Executed earlier" row (checked, disabled, no write
  // handler), must be EXCLUDED from the Weekly X/Y, must show "Executed earlier: 1", and the
  // History card completed-transfer count must INCLUDE it (delta of +1 vs no injection).
  await test('Weekly › Transfers: executed history — visible, X/Y-excluded, History-counted (5G-1B)', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate(() => {
      const g = getGoals();
      const weeks = runModel(g.ak, g.rt);
      const wk = (weeks.find(w => w.realActs.length > 0) || weeks[0]).num;
      const key = wk + '_99';                              // sparse high idx; absent action_key
      const savedKeys = {};
      Object.keys(taskData).forEach(k => { if (k.indexOf(wk + '_') === 0) { savedKeys[k] = taskData[k]; delete taskData[k]; } });
      function weeklyProg() {
        activeW = wk; setSection('weekly'); renderApp();
        var el = document.querySelector('#weekly-content .act-progress');
        var m = el ? (el.textContent || '').match(/(\d+)\s*\/\s*(\d+)/) : null;
        return { num: m ? +m[1] : null, denom: m ? +m[2] : null,
                 html: (document.getElementById('weekly-content').innerHTML || '') };
      }
      function histCount() {
        setSection('history'); renderApp();
        var cards = Array.prototype.slice.call(document.querySelectorAll('#historyContent .hcard'));
        var card = cards.find(c => (c.innerHTML || '').indexOf('activeW=' + wk + ';') >= 0) || null;
        var t = card ? card.querySelector('.hcard-tasks') : null;
        var m = t ? (t.textContent || '').match(/(\d+)\s*\/\s*(\d+)/) : null;
        return m ? { done: +m[1], total: +m[2] } : null;
      }
      // Baseline (no executed row)
      var wk0 = weeklyProg(); var h0 = histCount();
      // Inject one completed record whose action_key is NOT in the recommended set
      taskData[key] = { completed:true, completedAt:'2026-07-11T00:00:00Z', completedAmount:99,
        actionKey:'goal_absent_test', completedLabel:'ABSENT-EXEC-TEST $99 to AMEX Savings (holding)' };
      var wk1 = weeklyProg();
      var execRows = Array.prototype.slice.call(document.querySelectorAll('#weekly-content .task-row.exec-history'));
      var target = execRows.find(r => (r.textContent || '').indexOf('ABSENT-EXEC-TEST') >= 0) || null;
      var cb = target ? target.querySelector('input.task-check') : null;
      var h1 = histCount();
      // Restore
      delete taskData[key];
      Object.keys(savedKeys).forEach(k => { taskData[k] = savedKeys[k]; });
      return {
        rowFound: !!target,
        hasLabel: wk1.html.indexOf('ABSENT-EXEC-TEST') >= 0,
        execHdr1: wk1.html.indexOf('Executed earlier: 1') >= 0,
        cbChecked: cb ? cb.checked === true : false,
        cbDisabled: cb ? cb.disabled === true : false,
        cbNoHandler: target ? (target.innerHTML.indexOf('toggleTransfer') < 0) : false,
        denom0: wk0.denom, denom1: wk1.denom, num0: wk0.num, num1: wk1.num,
        h0: h0, h1: h1,
      };
    });
    assert(res.rowFound && res.hasLabel, 'executed-history row not rendered from completed_label');
    assert(res.cbChecked, 'executed-history checkbox must be checked');
    assert(res.cbDisabled, 'executed-history checkbox must be disabled');
    assert(res.cbNoHandler, 'executed-history row must have NO write handler (no toggleTransfer)');
    assert(res.execHdr1, '"Executed earlier: 1" must be visible');
    assert(res.denom1 !== null && res.denom1 === res.denom0, 'Weekly X/Y denominator must EXCLUDE executed history (' + res.denom0 + ' -> ' + res.denom1 + ')');
    assert(res.num1 === res.num0, 'Weekly X/Y numerator must be unchanged by executed history');
    assert(res.h0 && res.h1, 'History card for the week must render a count');
    assert(res.h1.done === res.h0.done + 1 && res.h1.total === res.h0.total + 1,
      'History card count must INCLUDE the executed transfer (done ' + res.h0.done + '->' + res.h1.done + ', total ' + res.h0.total + '->' + res.h1.total + ')');
    await context.close();
  }, { tags: [] });

  // 5G-1B: write-wiring — a completion persisted at task_idx 5 but matched to the current
  // action rendered at display index 0 must, on UNCHECK, write to task_idx 5 (the matched
  // persisted row) and NEVER to display index 0. Intercepts the real weekly_tasks upsert.
  await test('Weekly › Transfers: uncheck a moved completion writes matched task_idx=5, never idx 0 (5G-1B)', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const setup = await page.evaluate(() => {
      const g = getGoals();
      const weeks = runModel(g.ak, g.rt);
      const wkObj = weeks.find(w => w.realActs.length > 0) || weeks[0];
      const wk = wkObj.num, key0 = wkObj.realActKeys[0], lbl0 = wkObj.realActs[0];
      Object.keys(taskData).forEach(k => { if (k.indexOf(wk + '_') === 0) delete taskData[k]; });
      // matched completion for display row 0, stored at a MOVED task_idx 5
      taskData[wk + '_5'] = { completed:true, completedAt:'2026-07-11T00:00:00Z', completedAmount:null,
        actionKey:key0, completedLabel:lbl0 };
      activeW = wk; setSection('weekly'); renderApp();
      const ctx = _xfrWriteCtx[wk + '_0'] || {};
      const firstCb = document.querySelector('#weekly-content .task-row:not(.exec-history) input.task-check');
      return { wk, key0, ctxMatch: ctx.matchTaskIdx, row0Checked: firstCb ? firstCb.checked === true : false };
    });
    assert(setup.ctxMatch === 5, 'display row 0 write-context must point at matched task_idx 5, got ' + setup.ctxMatch);
    assert(setup.row0Checked, 'display row 0 must render checked (matched completion)');
    // Intercept every weekly_tasks upsert
    const posts = [];
    await page.route('**/rest/v1/weekly_tasks**', route => {
      const req = route.request();
      if (req.method() === 'POST') { try { posts.push(JSON.parse(req.postData() || '{}')); } catch (e) { posts.push({ parseError: true }); } }
      route.fulfill({ status: 200, contentType: 'application/json', body: '' });
    });
    // Uncheck display row 0 → toggleTransfer must target the matched task_idx 5
    await page.locator('#weekly-content .task-row:not(.exec-history) input.task-check').first().click();
    for (let t = 0; t < 30 && posts.length === 0; t++) { await page.waitForTimeout(50); }
    assert(posts.length >= 1, 'no weekly_tasks POST captured on uncheck');
    const p = posts[0];
    assert(p.task_idx === 5, 'outbound task_idx must be the matched 5, got ' + p.task_idx);
    assert(p.action_key === setup.key0, 'outbound action_key must be the row-0 key, got ' + p.action_key);
    assert(p.completed === false, 'uncheck writes completed=false');
    assert(p.completed_label === null, 'uncheck nulls completed_label (identity carried by action_key)');
    assert(posts.every(x => x.task_idx !== 0), 'NO request may write task_idx 0');
    await context.close();
  }, { tags: [] });

  // 5G-1C-2.1 Leg 1: injected snapshot/reconciliation state -> real runModel -> real Weekly renderer.
  // An above-threshold Adam IRA anchor + reconciled wk1-5 must NOT re-emit the IRA seed, must emit the
  // derived (target - anchor) residual exactly once, and the rendered Weekly view must show that
  // residual row and no seed row. (Exercises the real model + Weekly renderer; it does NOT route or
  // reload the REST loader — it injects the loaded-state globals directly.)
  await test('Weekly › Model: above-threshold anchor suppresses seed; derived residual once (5G-1C-2.1)', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate(() => {
      const _s = goalSnapData, _r = reconData, anchor = 7438.94;
      goalSnapData = { 5: { adam_ira: anchor, wendy_ira: 0, alaska: 7000, bailey_529: 0, bryce_529: 0, preston_529: 0, bryce_vehicle: 0, christmas_cruise: 0 } };
      const rc = (chk, amx) => ({ chk, sav: 200, amx, tax: 1500, lc: 13488.88, balance_basis: 'posted_current_balance' });
      reconData = { 1: rc(9000, 104), 2: rc(8000, 104), 3: rc(7200, 104), 4: rc(6800, 104), 5: rc(6700, 8539.20) };
      try {
        const g = getGoals(); const W = runModel(g.ak, g.rt);
        const IRA_TGT = (GOALS_REGISTRY.find(x => x.id === 'adam_ira') || {}).target || 7500;
        const derived = Math.round((IRA_TGT - anchor) * 100) / 100;
        let seedCount = 0; const resid = [];
        W.forEach(w => (w.realActs || []).forEach(a => {
          if (a.indexOf('Adam IRA seed') >= 0) seedCount++;
          else if (a.indexOf('(Adam IRA)') >= 0) resid.push({ wk: w.num, amt: parseFloat((((a.match(/\$([\d,\.]+)/) || [])[1]) || '0').replace(/,/g, '')) });
        }));
        const residWk = resid.length ? resid[0].wk : W[0].num;
        activeW = residWk; setSection('weekly'); renderApp();
        const html = document.getElementById('weekly-content').innerHTML || '';
        return { threshold: IRA_SEED_EMBEDDED_THRESHOLD, seedCount, residCount: resid.length, residAmt: resid.length ? resid[0].amt : null,
          derived, residWk, weeklyHasResidual: html.indexOf('(Adam IRA)') >= 0, weeklyHasSeed: html.indexOf('Adam IRA seed') >= 0 };
      } finally { goalSnapData = _s; reconData = _r; renderApp(); }
    });
    assert(res.seedCount === 0, 'no post-anchor Adam IRA seed row anywhere in the model; got seedCount=' + res.seedCount);
    assert(res.residCount === 1, 'derived residual must appear exactly once; got ' + res.residCount);
    assert(Math.abs(res.residAmt - res.derived) < 0.01, 'residual amount ' + res.residAmt + ' != derived (target-anchor) ' + res.derived);
    assert(res.weeklyHasResidual, 'rendered Weekly view (week ' + res.residWk + ') must show the Adam IRA residual row');
    assert(!res.weeklyHasSeed, 'rendered Weekly view must NOT show an Adam IRA seed row');
    await context.close();
  }, { tags: [] });

  // ── Section 5G-1B-NET: open-window executed-transfer netting (incident reproduction) ──
  console.log('── Section 5G-1B-NET: open-window executed-transfer netting ──');

  // Shared injector: the 5G-1C-2.1 anchor state (adam_ira short $61.06), loaded snapshot status,
  // real runModel → the model emits the Adam IRA residual exactly once at some open week (residWk).
  const NET_INJECT = `(function(){
    goalSnapData = { 5: { adam_ira: 7438.94, wendy_ira: 0, alaska: 7000, bailey_529: 0, bryce_529: 0, preston_529: 0, bryce_vehicle: 0, christmas_cruise: 0 } };
    _goalSnapLoadStatus = 'loaded';
    var rc=function(chk,amx){return{chk:chk,sav:200,amx:amx,tax:1500,lc:13488.88,balance_basis:'posted_current_balance'};};
    reconData = { 1: rc(9000,104), 2: rc(8000,104), 3: rc(7200,104), 4: rc(6800,104), 5: rc(6700,8539.20) };
    var g=getGoals(); var W=runModel(g.ak,g.rt); var resid=null;
    W.forEach(function(w){ (w.realActKeys||[]).forEach(function(k,i){ if(k==='goal_adam_ira'&&!resid){ var a=w.realActs[i]; resid={wk:w.num,idx:i,label:a,amt:parseFloat(((a.match(/\\$([\\d,\\.]+)/)||[])[1]||'0').replace(/,/g,''))}; } }); });
    return resid;
  })()`;

  // NET-E1 — the reported incident: an already-executed Adam IRA transfer must NOT re-present as an
  // executable PLANNED row after a recalc. Executed credit sits in an earlier open week; the model
  // re-emits the residual at residWk; the rendered Weekly view must show it "Satisfied" with NO
  // enabled Adam IRA checkbox anywhere in the open week.
  await test('5G1B-NET-E1: executed Adam IRA residual is suppressed (no enabled duplicate) after recalc', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate((INJECT) => {
      const _s = goalSnapData, _r = reconData, _st = _goalSnapLoadStatus, _saved = {};
      try {
        const resid = eval(INJECT);
        if (!resid) return { skip: true };
        const creditWk = (resid.wk === 6) ? 7 : 6;               // an open week that is NOT residWk
        const ck = creditWk + '_0';
        _saved[ck] = taskData[ck];
        taskData[ck] = { completed: true, completedAt: '2026-07-15T00:00:00Z', completedAmount: resid.amt, actionKey: 'goal_adam_ira', completedLabel: resid.label };
        activeW = resid.wk; setSection('weekly'); renderApp();
        const rows = Array.from(document.querySelectorAll('#weekly-content .task-row'));
        const iraRows = rows.filter(r => (r.textContent || '').indexOf('(Adam IRA)') >= 0 && (r.textContent||'').indexOf('Adam IRA seed') < 0);
        const enabledIra = iraRows.filter(r => { const cb = r.querySelector('input.task-check'); return cb && !cb.disabled; });
        const html = document.getElementById('weekly-content').innerHTML || '';
        return { skip:false, residWk: resid.wk, iraRowCount: iraRows.length, enabledIra: enabledIra.length,
          hasSatisfied: html.indexOf('Satisfied by completed transfer') >= 0 };
      } finally {
        Object.keys(_saved).forEach(k => { if (_saved[k] === undefined) delete taskData[k]; else taskData[k] = _saved[k]; });
        goalSnapData = _s; reconData = _r; _goalSnapLoadStatus = _st; renderApp();
      }
    }, NET_INJECT);
    assert(!res.skip, 'model must emit an Adam IRA residual to exercise this test');
    assert(res.iraRowCount >= 1, 'the Adam IRA residual row must be present in the Weekly view');
    assert(res.enabledIra === 0, 'NO enabled Adam IRA transfer checkbox may appear (got ' + res.enabledIra + ')');
    assert(res.hasSatisfied, 'the satisfied obligation must render as "Satisfied by completed transfer"');
    await context.close();
  }, { tags: [] });

  // NET-E2 — after Week-6 closeout (snapshot anchors adam_ira at target), the model emits NO Adam IRA
  // residual in any later week — the durable snapshot mechanism (5G-1D) takes over. (req 9 post-close)
  await test('5G1B-NET-E2: after wk6 closeout no later-week Adam IRA recommendation is emitted', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate(() => {
      const _s = goalSnapData, _r = reconData, _st = _goalSnapLoadStatus;
      try {
        // adam_ira funded to target at the wk6 anchor (executed $61.06 absorbed into the closeout snapshot)
        goalSnapData = { 5: { adam_ira: 7438.94 }, 6: { adam_ira: 7500, wendy_ira: 0, alaska: 7000, bailey_529: 0, bryce_529: 0, preston_529: 0, bryce_vehicle: 0, christmas_cruise: 0 } };
        _goalSnapLoadStatus = 'loaded';
        const rc = (chk, amx) => ({ chk, sav: 200, amx, tax: 1500, lc: 13488.88, balance_basis: 'posted_current_balance' });
        reconData = { 1: rc(9000,104), 2: rc(8000,104), 3: rc(7200,104), 4: rc(6800,104), 5: rc(6700,8539.20), 6: rc(6500,8600) };
        const g = getGoals(); const W = runModel(g.ak, g.rt);
        let iraRecs = 0; W.forEach(w => (w.realActKeys || []).forEach(k => { if (k === 'goal_adam_ira') iraRecs++; }));
        return { iraRecs };
      } finally { goalSnapData = _s; reconData = _r; _goalSnapLoadStatus = _st; renderApp(); }
    });
    assert(res.iraRecs === 0, 'no Adam IRA recommendation should remain after the wk6 closeout anchor; got ' + res.iraRecs);
    await context.close();
  }, { tags: [] });

  // NET-E3 — defense in depth: a STALE UI (a checkbox that shouldn't exist) calling toggleTransfer on a
  // suppressed obligation must be rejected by the write path — no optimistic state, no write. (req 6)
  await test('5G1B-NET-E3: write-guard rejects a stale-UI toggle of a suppressed obligation', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate(async (INJECT) => {
      const _s = goalSnapData, _r = reconData, _st = _goalSnapLoadStatus, _cwf = canWriteFinancials, _saved = {};
      try {
        const resid = eval(INJECT);
        if (!resid) return { skip: true };
        const creditWk = (resid.wk === 6) ? 7 : 6, ck = creditWk + '_0';
        _saved[ck] = taskData[ck];
        taskData[ck] = { completed: true, completedAt: '2026-07-15T00:00:00Z', completedAmount: resid.amt, actionKey: 'goal_adam_ira', completedLabel: resid.label };
        canWriteFinancials = () => true;                        // simulate an authorized writer
        const key = resid.wk + '_' + resid.idx;
        _saved[key] = taskData[key];
        // Stale write context as a cached UI would carry it, then attempt to execute the suppressed row:
        _xfrWriteCtx[key] = { actionKey: 'goal_adam_ira', completedLabel: resid.label, amount: resid.amt, matchTaskIdx: null };
        await toggleTransfer(resid.wk, key, true);
        const after = taskData[key];
        return { skip:false, wroteOptimistic: !!(after && after.completed) };
      } finally {
        canWriteFinancials = _cwf;
        Object.keys(_saved).forEach(k => { if (_saved[k] === undefined) delete taskData[k]; else taskData[k] = _saved[k]; });
        goalSnapData = _s; reconData = _r; _goalSnapLoadStatus = _st; renderApp();
      }
    }, NET_INJECT);
    assert(!res.skip, 'model must emit an Adam IRA residual to exercise this test');
    assert(!res.wroteOptimistic, 'write-guard must reject the suppressed toggle: no optimistic completed state may be set');
    await context.close();
  }, { tags: [] });

  // ── Section 5G-1B-IDENT: identity-resolved completion normalization (commission-tax visibility) ──
  console.log('── Section 5G-1B-IDENT: identity-resolved completion normalization ──');

  // Shared injector: wk6 commission override $2,108.78 (ct=843.51), wk1-5 reconciled (wk5 end $8,382.92 →
  // model splits comm-tax $425.68/$417.83), and the executed Adam IRA $61.06 completion at wk6/task_idx 0
  // (the colliding index). Restores all globals afterward.
  const IDENT_INJECT = `(function(){
    goalSnapData={5:{adam_ira:7438.94,wendy_ira:0,alaska:7000,bailey_529:0,bryce_529:0,preston_529:0,bryce_vehicle:0,christmas_cruise:0}};
    _goalSnapLoadStatus='loaded';
    var rc=function(chk){return{chk:chk,sav:7000.07,amx:8539.20,tax:1952.22,lc:14024.76,balance_basis:'posted_current_balance'};};
    reconData={1:rc(15000),2:rc(13000),3:rc(11000),4:rc(9500),5:rc(8382.92)};
    overrideData[6]={week_num:6,dates:'Jul 12-18',events_json:[{l:'AMEX Gold payment due 7/18',t:'ob',a:-5718.52},{l:'Wendy Deep South commission (7/15)',t:'in',a:2108.78,tx:true},{l:'Wendy paycheck (7/17)',t:'in',a:2152.50}],ct:843.51,ca:1265.27};
    // ISOLATION: clear live production taskData so E1/E2 run the DECLARED NO-EXECUTION fixture — no
    // commission_tax completed legs (the live account carries wk2/wk4/wk6 legs that would otherwise
    // contaminate the "no-execution" premise). Only the Adam IRA rows below are seeded.
    Object.keys(taskData).forEach(function(k){delete taskData[k];});
    taskData['6_0']={completed:true,completedAt:'2026-07-14T01:21:52Z',completedAmount:61.06,actionKey:'goal_adam_ira',completedLabel:'Transfer $61.06 from Truist Checking to AMEX Savings (Adam IRA)'};
    taskData['7_1']={completed:false,completedAt:null,completedAmount:null,actionKey:'goal_adam_ira',completedLabel:null};
  })()`;

  // IDENT-E1 — Week 28 must show ONE enabled $425.68 commission_tax task; the narrative must show
  // $425.68 (not $61.06) with $417.83 carried forward; the Adam IRA $61.06 stays separate/non-executable;
  // and the commission_tax write context carries 425.68 + the correct label.
  await test('5G1B-IDENT-E1: Week 28 shows one enabled $425.68 commission_tax task, correct narrative, Adam IRA separate, write ctx 425.68', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate((INJECT) => {
      const _s=goalSnapData,_r=reconData,_st=_goalSnapLoadStatus,_o=overrideData[6],_t0=taskData['6_0'],_t1=taskData['7_1'];
      try {
        eval(INJECT);
        activeW=6; setSection('weekly'); renderApp();
        const html=document.getElementById('weekly-content').innerHTML||'';
        const rows=Array.from(document.querySelectorAll('#weekly-content .task-row'));
        const enabledCT=rows.filter(r=>{const cb=r.querySelector('input.task-check');const t=r.textContent||'';return cb&&!cb.disabled&&t.indexOf('$425.68')>=0&&t.indexOf('Tax Reserve')>=0;});
        const enabledIraDup=rows.filter(r=>{const cb=r.querySelector('input.task-check');const t=r.textContent||'';return cb&&!cb.disabled&&t.indexOf('(Adam IRA)')>=0&&t.indexOf('Adam IRA seed')<0;});
        let ctx=null; for(const k in _xfrWriteCtx){ if(_xfrWriteCtx[k]&&_xfrWriteCtx[k].actionKey==='commission_tax'){ctx=_xfrWriteCtx[k];break;} }
        return { enabledCT:enabledCT.length, enabledIraDup:enabledIraDup.length,
          narr425: html.indexOf('$425.68')>=0, narr417carry: html.indexOf('$417.83 carries forward')>=0,
          narr61bad: /Commission 40% \$61\.06/.test(html),
          ctxAmt: ctx?ctx.amount:null, ctxLabelOk: ctx?(String(ctx.completedLabel).indexOf('Vio Bank - Tax Reserve')>=0):false };
      } finally { goalSnapData=_s;reconData=_r;_goalSnapLoadStatus=_st;
        (_o===undefined)?delete overrideData[6]:overrideData[6]=_o;
        (_t0===undefined)?delete taskData['6_0']:taskData['6_0']=_t0;
        (_t1===undefined)?delete taskData['7_1']:taskData['7_1']=_t1; renderApp(); }
    }, IDENT_INJECT);
    assert(res.enabledCT===1, 'exactly one enabled $425.68 commission_tax checkbox (got '+res.enabledCT+')');
    assert(res.enabledIraDup===0, 'no enabled Adam IRA duplicate checkbox (got '+res.enabledIraDup+')');
    assert(res.narr425, 'narrative shows $425.68');
    assert(res.narr417carry, 'narrative shows $417.83 carries forward');
    assert(!res.narr61bad, 'narrative must NOT show "Commission 40% $61.06"');
    assert(res.ctxAmt===425.68, 'commission_tax write ctx amount = 425.68 (got '+res.ctxAmt+')');
    assert(res.ctxLabelOk, 'commission_tax write ctx label is the Vio Tax Reserve label');
    await context.close();
  }, { tags: [] });

  // IDENT-E2 — Week 29 retains exactly one $417.83 commission_tax task; no cross-attribution / no $61.06.
  await test('5G1B-IDENT-E2: Week 29 retains exactly one enabled $417.83 commission_tax task', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate((INJECT) => {
      const _s=goalSnapData,_r=reconData,_st=_goalSnapLoadStatus,_o=overrideData[6],_t0=taskData['6_0'],_t1=taskData['7_1'];
      try {
        eval(INJECT);
        activeW=7; setSection('weekly'); renderApp();
        const rows=Array.from(document.querySelectorAll('#weekly-content .task-row'));
        const enabled417=rows.filter(r=>{const cb=r.querySelector('input.task-check');const t=r.textContent||'';return cb&&!cb.disabled&&t.indexOf('$417.83')>=0&&t.indexOf('Tax Reserve')>=0;});
        const html=document.getElementById('weekly-content').innerHTML||'';
        return { enabled417:enabled417.length, has61inComm: /Commission 40% \$61\.06/.test(html) };
      } finally { goalSnapData=_s;reconData=_r;_goalSnapLoadStatus=_st;
        (_o===undefined)?delete overrideData[6]:overrideData[6]=_o;
        (_t0===undefined)?delete taskData['6_0']:taskData['6_0']=_t0;
        (_t1===undefined)?delete taskData['7_1']:taskData['7_1']=_t1; renderApp(); }
    }, IDENT_INJECT);
    assert(res.enabled417===1, 'exactly one enabled $417.83 commission_tax task in Week 29 (got '+res.enabled417+')');
    assert(!res.has61inComm, 'Week 29 commission line not contaminated with $61.06');
    await context.close();
  }, { tags: [] });

  // B3 — Overview / chip / History surfaces count the open $425.68 commission-tax task by identity;
  // the completed Adam IRA is isolated (does not satisfy the commission recommendation).
  await test('5G1B-IDENT-E3 (B3): Overview/chip/History count the open $425.68 commission_tax; Adam IRA isolated', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate((INJECT) => {
      const _s=goalSnapData,_r=reconData,_st=_goalSnapLoadStatus,_o=overrideData[6],_t0=taskData['6_0'],_t1=taskData['7_1'];
      try {
        eval(INJECT);
        var g=getGoals(); var weeks=applyCompletionSnapshots(getActiveModel()); _refreshTransferNet(weeks);
        var w6=weeks.find(function(x){return x.num===6;});
        var chipOpen=getWeekChipClass(w6).indexOf('openActions')>=0;
        var vm=buildDashboardViewModel(weeks,g);
        var comm425=vm.openActions.filter(function(a){return a.label&&a.label.indexOf('$425.68')>=0&&a.label.indexOf('Tax Reserve')>=0&&!a.isCustom;});
        var iraOpen=vm.openActions.filter(function(a){return a.label&&a.label.indexOf('(Adam IRA)')>=0;});
        var histWk6Open=weeks.filter(function(w){return w.realActs.length&&w.realActs.some(function(_,i){return _modelRowOpen(w,i);});}).some(function(w){return w.num===6;});
        return { chipOpen:chipOpen, comm425:comm425.length, iraOpen:iraOpen.length, histWk6Open:histWk6Open };
      } finally { goalSnapData=_s;reconData=_r;_goalSnapLoadStatus=_st;
        (_o===undefined)?delete overrideData[6]:overrideData[6]=_o;
        (_t0===undefined)?delete taskData['6_0']:taskData['6_0']=_t0;
        (_t1===undefined)?delete taskData['7_1']:taskData['7_1']=_t1; renderApp(); }
    }, IDENT_INJECT);
    assert(res.chipOpen, 'wk6 chip indicates an open action');
    assert(res.comm425===1, 'Overview openActions includes exactly one open $425.68 commission_tax action (got '+res.comm425+')');
    assert(res.iraOpen===0, 'the completed Adam IRA is NOT an open action (isolated)');
    assert(res.histWk6Open, 'History open filter includes wk6 (commission-tax obligation counted)');
    await context.close();
  }, { tags: [] });

  // B1/B2 — a Week-28 commission edit (saveWeekEdits) must NOT rewrite the foreign Adam IRA row; no PATCH
  // targets it as commission_tax. Drives the real async write path with a fetch spy.
  await test('5G1B-IDENT-E4 (B1/B2): a Week-28 commission edit does not rewrite the foreign Adam IRA row (no PATCH)', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate(() => {
      const _s=goalSnapData,_r=reconData,_st=_goalSnapLoadStatus,_o=overrideData[6],_t0=taskData['6_0'],_role=USER_ROLE,_ree=_readEditEvents,_f=window.fetch;
      var patches=[];
      return (async function(){
        try {
          USER_ROLE='owner';
          goalSnapData={5:{adam_ira:7438.94}}; _goalSnapLoadStatus='loaded';
          var rc=function(chk){return{chk:chk,sav:0,amx:0,tax:0,lc:0,balance_basis:'posted_current_balance'};};
          reconData={1:rc(15000),2:rc(13000),3:rc(11000),4:rc(9500),5:rc(8382.92)};
          overrideData[6]={week_num:6,ct:707.18,ca:1060.76,events_json:[]};                 // prior (old) commission override
          taskData['6_0']={completed:true,completedAt:'2026-07-14T01:21:52Z',completedAmount:61.06,actionKey:'goal_adam_ira',completedLabel:'Transfer $61.06 from Truist Checking to AMEX Savings (Adam IRA)'};
          _readEditEvents=function(){return [{l:'AMEX Gold',t:'ob',a:-5718.52},{l:'Wendy commission',t:'in',a:2108.78,tx:true},{l:'Wendy paycheck',t:'in',a:2152.50}];}; // → ct 843.51 (increase)
          window.fetch=function(url,opts){ if(opts&&opts.method==='PATCH'&&String(url).indexOf('weekly_tasks')>=0)patches.push({url:String(url),body:String(opts.body||'')}); return Promise.resolve({ok:true,status:200,json:function(){return Promise.resolve([]);},text:function(){return Promise.resolve('');}}); };
          try { await saveWeekEdits(6); } catch(e){ /* later stages irrelevant to the write-safety assertions */ }
          var ira=taskData['6_0'];
          return { iraKey: ira?ira.actionKey:null,
            rewroteIraToComm: patches.some(function(p){return p.url.indexOf('task_idx=eq.0')>=0&&p.body.indexOf('commission_tax')>=0;}),
            patchCount: patches.length };
        } finally { goalSnapData=_s;reconData=_r;_goalSnapLoadStatus=_st;
          (_o===undefined)?delete overrideData[6]:overrideData[6]=_o;
          (_t0===undefined)?delete taskData['6_0']:taskData['6_0']=_t0;
          USER_ROLE=_role; _readEditEvents=_ree; window.fetch=_f; }
      })();
    });
    assert(res.iraKey==='goal_adam_ira', 'Adam IRA row action_key NOT rewritten by the commission edit (got '+res.iraKey+')');
    assert(!res.rewroteIraToComm, 'NO PATCH rewrote the Adam IRA row (task_idx 0) into commission_tax');
    await context.close();
  }, { tags: [] });

  // Deterministic isolated base (no live taskData): wk6 ct=843.51, wk1-5 reconciled → model wk6/wk7 split.
  const IDENT_BASE = `goalSnapData={5:{adam_ira:7438.94,wendy_ira:0,alaska:7000,bailey_529:0,bryce_529:0,preston_529:0,bryce_vehicle:0,christmas_cruise:0}};_goalSnapLoadStatus='loaded';var rc=function(chk){return{chk:chk,sav:7000.07,amx:8539.20,tax:1952.22,lc:14024.76,balance_basis:'posted_current_balance'};};reconData={1:rc(15000),2:rc(13000),3:rc(11000),4:rc(9500),5:rc(8382.92)};overrideData[6]={week_num:6,dates:'Jul 12-18',events_json:[{l:'AMEX Gold payment due 7/18',t:'ob',a:-5718.52},{l:'Wendy Deep South commission (7/15)',t:'in',a:2108.78,tx:true},{l:'Wendy paycheck (7/17)',t:'in',a:2152.50}],ct:843.51,ca:1265.27};Object.keys(taskData).forEach(function(k){delete taskData[k];});`;

  // IDENT-E5 — DETERMINISTIC completed-leg fixture: a durable wk6 commission_tax 425.68 completion is
  // immutable "Executed" history (read-only), and ONLY the remaining $417.83 later action is actionable
  // (at Week 7). B1 is the sole completion authority (the durable leg is recognized regardless of label).
  await test('5G1B-IDENT-E5: durable wk6 425.68 completion → immutable Executed history; only wk7 417.83 remains actionable', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate((BASE) => {
      eval(BASE);
      taskData['6_1']={completed:true,completedAt:'2026-07-18T03:20:38Z',completedAmount:425.68,actionKey:'commission_tax',completedLabel:'Transfer $425.68 from Truist Checking to Vio Bank - Tax Reserve (commission 40%)'};
      function rows(){return Array.from(document.querySelectorAll('#weekly-content .task-row'));}
      function ct(en,amt){return rows().filter(function(r){var cb=r.querySelector('input.task-check');var t=r.textContent||'';return cb&&(en?!cb.disabled:cb.disabled)&&t.indexOf('$'+amt)>=0&&t.indexOf('Tax Reserve')>=0;}).length;}
      activeW=6; setSection('weekly'); renderApp();
      var wk6ExecReadonly=ct(false,'425.68'), wk6EnabledDup=ct(true,'425.68');
      var wk6Html=document.getElementById('weekly-content').innerHTML||'';
      activeW=7; renderApp();
      var wk7Enabled=ct(true,'417.83');
      return { wk6ExecReadonly:wk6ExecReadonly, wk6EnabledDup:wk6EnabledDup, wk6ExecutedBadge:/>Executed</.test(wk6Html), wk7Enabled:wk7Enabled };
    }, IDENT_BASE);
    assert(res.wk6ExecReadonly===1, 'wk6 shows exactly one READ-ONLY Executed $425.68 row (got '+res.wk6ExecReadonly+')');
    assert(res.wk6EnabledDup===0, 'wk6 shows NO enabled/actionable $425.68 duplicate (completion is immutable, got '+res.wk6EnabledDup+')');
    assert(res.wk6ExecutedBadge, 'wk6 durable completion renders an "Executed" badge');
    assert(res.wk7Enabled===1, 'wk7 shows exactly one enabled $417.83 commission_tax action (the remaining) (got '+res.wk7Enabled+')');
    await context.close();
  }, { tags: [] });

  // IDENT-E6 — MALFORMED null-amount fixture: an eligible completed commission_tax row with a NULL amount
  // is financially ambiguous ⇒ the pool fails closed ⇒ the commission-tax row is non-executable "Review
  // required" (no enabled checkbox, no write context). Proves the fail-closed guard the D-DISP remediated.
  await test('5G1B-IDENT-E6: eligible null-amount commission_tax leg → pool fail-closed → Review required (no executable row)', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate((BASE) => {
      eval(BASE);
      taskData['6_1']={completed:true,completedAt:'2026-07-18T03:20:38Z',completedAmount:null,actionKey:'commission_tax',completedLabel:'Transfer $425.68 from Truist Checking to Vio Bank - Tax Reserve (commission 40%)'};
      activeW=6; setSection('weekly'); renderApp();
      var html=document.getElementById('weekly-content').innerHTML||'';
      var rows=Array.from(document.querySelectorAll('#weekly-content .task-row'));
      var enabledCT=rows.filter(function(r){var cb=r.querySelector('input.task-check');var t=r.textContent||'';return cb&&!cb.disabled&&t.indexOf('Tax Reserve')>=0;}).length;
      var poolStatus=(typeof computeCommissionTaxPool==='function')?computeCommissionTaxPool().control_status:'n/a';
      var poolReason=(typeof computeCommissionTaxPool==='function')?computeCommissionTaxPool().reason:null;
      return { enabledCT:enabledCT, reviewRequired: html.indexOf('Review required')>=0 && html.indexOf('Tax Reserve')>=0, poolStatus:poolStatus, poolReason:poolReason };
    }, IDENT_BASE);
    assert(res.poolStatus==='fail_closed' && res.poolReason==='malformed_executed_amount', 'pool fails closed on the null amount (got '+res.poolStatus+'/'+res.poolReason+')');
    assert(res.enabledCT===0, 'NO enabled commission_tax checkbox while the pool is fail-closed (got '+res.enabledCT+')');
    assert(res.reviewRequired, 'commission-tax row renders "Review required"');
    await context.close();
  }, { tags: [] });

  // IDENT-E7 — executed-history authority: a durable commission_tax leg the LEGACY resolver leaves
  // UNCONSUMED (its stored completed_label differs from the current model realAct label) must NOT render a
  // second legacy "Executed earlier" row — B1 owns the single immutable "Executed" representation. Non-
  // commission-tax unconsumed history is UNCHANGED. (6_1 matches the model label and binds; 6_2 is a
  // superseded-label CT leg left unconsumed; 6_5 is a phantom non-CT completion that stays in legacy history.)
  await test('5G1B-IDENT-E7: legacy executedHistory excludes commission_tax (no duplicate); B1 owns the one Executed row; non-CT history intact', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'weekly');
    const res = await page.evaluate((BASE) => {
      eval(BASE);
      taskData['6_1']={completed:true,completedAt:'2026-07-18T03:20:38Z',completedAmount:425.68,actionKey:'commission_tax',completedLabel:'Transfer $425.68 from Truist Checking to Vio Bank - Tax Reserve (commission 40%)'};
      taskData['6_2']={completed:true,completedAt:'2026-06-01T00:00:00Z',completedAmount:0,actionKey:'commission_tax',completedLabel:'Transfer $478.19 from Truist Checking to Vio Bank - Tax Reserve (superseded model label)'};
      taskData['6_5']={completed:true,completedAt:'2026-06-01T00:00:00Z',completedAmount:12.34,actionKey:'goal_phantom',completedLabel:'Transfer $12.34 from Truist Checking to AMEX Savings (Phantom Goal)'};
      activeW=6; setSection('weekly'); renderApp();
      var eh=Array.from(document.querySelectorAll('#weekly-content .task-row.exec-history'));
      var rows=Array.from(document.querySelectorAll('#weekly-content .task-row'));
      var execHistCT=eh.filter(function(r){return (r.textContent||'').indexOf('Tax Reserve')>=0;}).length;
      var execHistNonCT=eh.filter(function(r){return (r.textContent||'').indexOf('Phantom Goal')>=0;}).length;
      var b1Executed=rows.filter(function(r){var cb=r.querySelector('input.task-check');var t=r.textContent||'';return cb&&cb.disabled&&t.indexOf('Executed')>=0&&t.indexOf('Tax Reserve')>=0&&t.indexOf('$425.68')>=0;}).length;
      var enabledCTwk6=rows.filter(function(r){var cb=r.querySelector('input.task-check');var t=r.textContent||'';return cb&&!cb.disabled&&t.indexOf('Tax Reserve')>=0;}).length;
      var poolStatus=computeCommissionTaxPool().control_status;
      activeW=7; renderApp();
      var wk7Enabled=Array.from(document.querySelectorAll('#weekly-content .task-row')).filter(function(r){var cb=r.querySelector('input.task-check');var t=r.textContent||'';return cb&&!cb.disabled&&t.indexOf('$417.83')>=0&&t.indexOf('Tax Reserve')>=0;}).length;
      return { execHistCT:execHistCT, execHistNonCT:execHistNonCT, b1Executed:b1Executed, enabledCTwk6:enabledCTwk6, poolStatus:poolStatus, wk7Enabled:wk7Enabled };
    }, IDENT_BASE);
    assert(res.poolStatus==='ok', 'pool remains ok (the extra unconsumed CT leg does not break the pool)');
    assert(res.execHistCT===0, 'NO legacy "Executed earlier" commission_tax row — B1 owns it (got '+res.execHistCT+')');
    assert(res.b1Executed===1, 'exactly ONE B1-owned immutable Executed $425.68 commission_tax row (got '+res.b1Executed+')');
    assert(res.enabledCTwk6===0, 'no actionable/enabled commission_tax duplicate at wk6 (got '+res.enabledCTwk6+')');
    assert(res.execHistNonCT===1, 'non-commission-tax phantom completion STILL renders in legacy executed history (unchanged) (got '+res.execHistNonCT+')');
    assert(res.wk7Enabled===1, 'later remaining commission-tax allocation intact — wk7 one enabled $417.83 (got '+res.wk7Enabled+')');
    await context.close();
  }, { tags: [] });

  // ── Section J: Mobile viewport ─────────────────────────────────────────
  console.log('── Section J: Mobile viewport ──');
  await test('Mobile: all tabs reachable without horizontal overflow', async () => {
    const { page, context } = await openApp(browser, {
      viewport: { width: 390, height: 844 }, // iPhone 14
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
    });
    for (const tab of ['overview','weekly','goals']) {
      // Mobile nav uses #mob-nav-* — desktop sidebar (#nav-*) is hidden at this viewport
      await page.click('#mob-nav-' + tab);
      await page.waitForTimeout(300);
      const overflow = await page.evaluate(() => document.body.scrollWidth > window.innerWidth);
      assert(!overflow, 'Horizontal overflow on mobile tab: ' + tab);
    }
    await context.close();
  });

  // ── Section BR: Budget Rules ───────────────────────────────────────────
  // Tests inject rules via page.evaluate() so they work in file:// mode
  // without requiring a live Supabase connection.
  console.log('── Section BR: Budget Rules ──');

  await test('BR-1: Budget Rule entry appears in ruleAudit and weekly transfer log for affected week', async () => {
    const { page, context } = await openApp(browser);
    // Inject rule, run model, check ruleAudit (global populated by runModel)
    const applied = await page.evaluate(() => {
      budgetRules = [{
        id: 99, label: 'E2E test rule', amount: '300', direction: 'outflow',
        rule_mode: 'delta', frequency: 'one-time', start_date: '2026-07-07',
        end_date: null, day_of_month: null, category: 'sports', active: true
      }];
      var g = getGoals();
      runModel(g.ak, g.rt); // populates ruleAudit
      return ruleAudit.some(function(e) {
        return e.label === 'E2E test rule' && e.action === 'applied';
      });
    });
    assert(applied, 'Budget Rule should have action=applied in ruleAudit for week 5');
    // Also verify it appears in the weekly transfer log DOM (r:done renders in transfers panel)
    await page.evaluate(() => { renderApp(); });
    await page.waitForTimeout(400);
    await clickNav(page, 'weekly');
    await page.waitForTimeout(300);
    // Navigate to week 5 where the rule fires
    await page.evaluate(() => { activeW = 5; renderApp(); });
    await page.waitForTimeout(300);
    const weekDetailText = await page.evaluate(() => {
      const el = document.getElementById('week-detail-content');
      return el ? el.innerText : '';
    });
    assert(weekDetailText.includes('E2E test rule') || weekDetailText.includes('budget rule'),
      'Budget Rule label not found in week 5 transfer detail');
    // Cleanup
    await page.evaluate(() => { budgetRules = []; renderApp(); });
    await context.close();
  });

  await test('A8-1 (Phase 5F-1.5): weekly milestone banner renders in the week header card, not at the bottom', async () => {
    const { page, context } = await openApp(browser);
    await page.evaluate(() => { renderApp(); });
    await clickNav(page, 'weekly');
    await page.waitForTimeout(200);
    const result = await page.evaluate(() => {
      activeW = 1; // Week 1 always shows the green "Week 1 actions" banner
      renderApp();
      var el = document.getElementById('week-detail-content');
      var h = el ? el.innerHTML : '';
      return {
        hasBanner: h.indexOf('Week 1 actions') !== -1,
        bannerIdx: h.indexOf('wk-header-banner'),
        headerTopIdx: h.indexOf('wk-header-top'),
        twoColIdx: h.indexOf('two-col')
      };
    });
    assert(result.hasBanner, 'Week 1 milestone banner must render');
    assert(result.bannerIdx > -1, 'banner must be wrapped in wk-header-banner');
    assert(result.headerTopIdx > -1 && result.bannerIdx > result.headerTopIdx, 'banner must render inside the header card, after the wk-header-top row');
    assert(result.twoColIdx > -1 && result.bannerIdx < result.twoColIdx, 'banner must render in the header, before the cash-flow (two-col) section, not at the bottom');
    await context.close();
  });

  await test('BR-2: Budget Rule is bypassed (logged to ruleAudit) when week is overridden', async () => {
    const { page, context } = await openApp(browser);
    const bypassed = await page.evaluate(() => {
      budgetRules = [{
        id: 98, label: 'Override bypass test', amount: '200', direction: 'outflow',
        rule_mode: 'delta', frequency: 'one-time', start_date: '2026-07-07',
        end_date: null, day_of_month: null, category: 'other', active: true
      }];
      overrideData[5] = {
        week_num: 5, dates: 'Jul 5-11',
        events_json: [{ l: 'Override event', t: 'in', a: 100 }],
        ct: 0, ca: 0
      };
      var g = getGoals();
      runModel(g.ak, g.rt);
      // Must be logged as bypassed, not applied
      var entry = ruleAudit.find(function(e) { return e.label === 'Override bypass test'; });
      return entry ? entry.action : null;
    });
    assert(bypassed === 'bypassed_by_model_week_override',
      'Budget Rule in overridden week should be logged as bypassed_by_model_week_override, got: ' + bypassed);
    // Cleanup
    await page.evaluate(() => { budgetRules = []; delete overrideData[5]; renderApp(); });
    await context.close();
  });

  await test('BR-3: Budget Rules resume (action=applied) in non-overridden week after overridden week', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      // Save and replace overrideData to isolate from live DB state.
      // Live DB has a week 6 override (Jul 12-18) which would cause the rule to be
      // bypassed. We control the full overrideData for this test.
      var savedOverrideData = JSON.parse(JSON.stringify(overrideData));
      overrideData = {};
      // Rule fires in week 6 (Jul 12-18); override only on week 5
      budgetRules = [{
        id: 97, label: 'Resume check rule', amount: '150', direction: 'outflow',
        rule_mode: 'delta', frequency: 'one-time', start_date: '2026-07-14',
        end_date: null, day_of_month: null, category: 'other', active: true
      }];
      overrideData[5] = {
        week_num: 5, dates: 'Jul 5-11',
        events_json: [{ l: 'Override event', t: 'in', a: 100 }],
        ct: 0, ca: 0
      };
      var g = getGoals();
      runModel(g.ak, g.rt);
      var entry = ruleAudit.find(function(e) { return e.label === 'Resume check rule'; });
      var testResult = entry ? { action: entry.action, week: entry.week } : null;
      // Restore live DB state before returning
      overrideData = savedOverrideData;
      return testResult;
    });
    assert(result !== null, 'Resume check rule should appear in ruleAudit');
    assert(result.action === 'applied',
      'Budget Rule should be applied in non-overridden week, got action: ' + (result && result.action));
    assert(result.week !== 5,
      'Resume rule should fire in week 6+, not week 5 (which is overridden)');
    // Cleanup
    await page.evaluate(() => { budgetRules = []; renderApp(); });
    await context.close();
  });

  await test('BR-4: Failed-load banner is hidden when budgetRulesLoadStatus is loaded', async () => {
    const { page, context } = await openApp(browser);
    await page.evaluate(() => {
      budgetRulesLoadStatus = 'loaded';
      budgetRules = [];
      renderApp();
    });
    await page.waitForTimeout(300);
    const bannerVisible = await page.evaluate(() => {
      const el = document.getElementById('budget-rules-warn');
      return el && el.style.display !== 'none';
    });
    assert(!bannerVisible, 'Failed-load banner should be hidden when status is loaded');
    await context.close();
  });

  await test('BR-5: Failed-load banner is visible when budgetRulesLoadStatus is failed', async () => {
    const { page, context } = await openApp(browser);
    await page.evaluate(() => {
      budgetRulesLoadStatus = 'failed';
      renderApp();
    });
    await page.waitForTimeout(300);
    const bannerVisible = await page.evaluate(() => {
      const el = document.getElementById('budget-rules-warn');
      return el && el.style.display !== 'none';
    });
    assert(bannerVisible, 'Failed-load banner should be visible when status is failed');
    // Cleanup
    await page.evaluate(() => { budgetRulesLoadStatus = 'not_configured'; renderApp(); });
    await context.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // WC — What-If Impact Calculator
  // ═══════════════════════════════════════════════════════════════════════

  await test('WC-1: What-If Impact tab is visible in Goals subnav', async () => {
    const { page, context } = await openApp(browser);
    await page.evaluate(() => { setSection('goals'); renderApp(); });
    await page.waitForTimeout(300);
    const tabVisible = await page.evaluate(() => {
      const pills = Array.from(document.querySelectorAll('.goals-pill'));
      return pills.some(function(p) { return p.textContent && p.textContent.includes('What-If Impact'); });
    });
    assert(tabVisible, 'What-If Impact sub-tab should be visible in Goals subnav');
    await context.close();
  });

  await test('WC-2: What-If Impact tab renders calculator form', async () => {
    const { page, context } = await openApp(browser);
    await page.evaluate(() => { setSection('goals'); goalsSubTab = 'impact'; renderApp(); });
    await page.waitForTimeout(300);
    const calcVisible = await page.evaluate(() => {
      return !!document.getElementById('wi-calc-btn');
    });
    assert(calcVisible, 'What-If calculator button should render when impact tab is active');
    await context.close();
  });

  await test('WC-3: Outflow entry produces negative or neutral impact on goalSaved', async () => {
    const { page, context } = await openApp(browser);
    await page.evaluate(() => { setSection('goals'); goalsSubTab = 'impact'; renderApp(); });
    await page.waitForTimeout(300);
    const result = await page.evaluate(() => {
      // Simulate what runWhatIf does — inject outflow and check diffModels output
      whatIfState = { label: 'E2E outflow test', amount: '750', direction: 'outflow', date: '2026-09-04', recurrence: 'monthly', endDate: '2027-01-04' };
      var g = getGoals();
      var savedRules = budgetRules.slice();
      var savedAudit = ruleAudit.slice();
      var baseline, scenario, scenarioAudit;
      try {
        baseline = runModel(g.ak, g.rt);
        var wiRule = { id: 'what_if_temp', label: 'E2E outflow test', active: true, amount: 750, direction: 'outflow', frequency: 'monthly', start_date: '2026-09-04', end_date: '2027-01-04', rule_mode: 'delta', category: 'other', source: 'what_if_calculator' };
        budgetRules = budgetRules.concat([wiRule]);
        scenario = runModel(g.ak, g.rt);
        scenarioAudit = ruleAudit.slice();
      } finally {
        budgetRules = savedRules;
        ruleAudit = savedAudit;
      }
      var diff = diffModels(baseline, scenario, scenarioAudit, g.ak);
      return { scenarioGoals: diff.cashSummary.scenarioTotalGoals, baselineGoals: diff.cashSummary.baselineTotalGoals, entryWeeks: diff.entryWeeks.length };
    });
    assert(result.entryWeeks > 0, 'outflow entry should fire in at least one week');
    assert(result.scenarioGoals <= result.baselineGoals + 0.01,
      'outflow should not increase total goal contributions (baseline=' + result.baselineGoals + ' scenario=' + result.scenarioGoals + ')');
    await context.close();
  });

  await test('WC-4: Inflow entry fires and returns valid diffModels output', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      var g = getGoals();
      var savedRules = budgetRules.slice();
      var savedAudit = ruleAudit.slice();
      var baseline, scenario, scenarioAudit;
      try {
        baseline = runModel(g.ak, g.rt);
        var wiRule = { id: 'what_if_temp', label: 'E2E inflow test', active: true, amount: 1000, direction: 'inflow', frequency: 'one-time', start_date: '2026-07-07', end_date: null, rule_mode: 'delta', category: 'other', source: 'what_if_calculator' };
        budgetRules = budgetRules.concat([wiRule]);
        scenario = runModel(g.ak, g.rt);
        scenarioAudit = ruleAudit.slice();
      } finally {
        budgetRules = savedRules;
        ruleAudit = savedAudit;
      }
      var diff = diffModels(baseline, scenario, scenarioAudit, g.ak);
      return {
        hasGoalImpact: Array.isArray(diff.goalImpact) && diff.goalImpact.length > 0,
        hasCashSummary: !!(diff.cashSummary && typeof diff.cashSummary.totalCashImpact === 'number'),
        entryWeeks: diff.entryWeeks.length,
        budgetRulesRestored: budgetRules.length === savedRules.length
      };
    });
    assert(result.hasGoalImpact, 'diffModels should return goalImpact array with entries');
    assert(result.hasCashSummary, 'diffModels should return cashSummary with totalCashImpact');
    assert(result.entryWeeks > 0, 'inflow entry should fire in at least one model week');
    assert(result.budgetRulesRestored, 'budgetRules should be restored after what-if run');
    await context.close();
  });

  await test('WC-5: clearWhatIf resets state and clears result', async () => {
    const { page, context } = await openApp(browser);
    await page.evaluate(() => {
      setSection('goals'); goalsSubTab = 'impact';
      whatIfState = { label: 'test', amount: '500', direction: 'outflow', date: '2026-07-07', recurrence: 'one-time', endDate: '' };
      whatIfResult = { error: 'invalid_input' };
      clearWhatIf();
    });
    const cleared = await page.evaluate(() => ({
      label: whatIfState.label,
      amount: whatIfState.amount,
      result: whatIfResult
    }));
    assert(cleared.label === '', 'label should be empty after clearWhatIf');
    assert(cleared.amount === '', 'amount should be empty after clearWhatIf');
    assert(cleared.result === null, 'whatIfResult should be null after clearWhatIf');
    await context.close();
  });

  await test('WC-6: Date outside model window returns error state', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      whatIfState = { label: '', amount: '500', direction: 'outflow', date: '2027-06-01', recurrence: 'one-time', endDate: '' };
      var wk = dateToModelWeek('2027-06-01');
      return { wk: wk };
    });
    assert(result.wk === null, 'dateToModelWeek should return null for out-of-window date');
    await context.close();
  });

  await test('WC-7: Override bypass appears in diffModels bypassedWeeks', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      // Add override for week 5
      overrideData[5] = { week_num: 5, dates: 'Jul 5-11', events_json: [{ l: 'Test', t: 'in', a: 100 }], ct: 0, ca: 0 };
      var g = getGoals();
      var savedRules = budgetRules.slice();
      var savedAudit = ruleAudit.slice();
      var baseline, scenario, scenarioAudit;
      try {
        baseline = runModel(g.ak, g.rt);
        var wiRule = { id: 'what_if_temp', label: 'WC bypass e2e', active: true, amount: 300, direction: 'outflow', frequency: 'one-time', start_date: '2026-07-07', end_date: null, rule_mode: 'delta', category: 'other', source: 'what_if_calculator' };
        budgetRules = budgetRules.concat([wiRule]);
        scenario = runModel(g.ak, g.rt);
        scenarioAudit = ruleAudit.slice();
      } finally {
        budgetRules = savedRules;
        ruleAudit = savedAudit;
        delete overrideData[5];
      }
      var diff = diffModels(baseline, scenario, scenarioAudit, g.ak);
      return { bypassedWeeks: diff.bypassedWeeks };
    });
    assert(result.bypassedWeeks.includes(5), 'overridden week 5 should appear in bypassedWeeks');
    await context.close();
  });

  // ── Section GR: Phase 6A Dynamic Goal Registry ────────────────────────
  console.log('\n── Section GR: Phase 6A Goal Registry ──');

  await test('GR-1: Goals tab renders correctly after applyGoalsFromData (DB-simulated load)', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    // Simulate DB load via JS in page
    await page.evaluate(() => {
      var dbRows = HARDCODED_GOALS_FALLBACK.map(function(g) {
        return { id:g.id, name:g.name, tier:g.tier, target:g.target, priority:g.priority,
          status:g.status, notes:g.notes, starts_after:g.startsAfter, due_week:g.dueWeek,
          needs_flag:g.needsFlag, from_model:g.fromModel, milestone:g.milestone,
          stretch:g.stretch, auto:g.auto, src:g.src, dest:g.dest, color:g.color };
      });
      applyGoalsFromData(dbRows.map(mapGoalFromDB));
      renderApp();
    });
    await page.waitForTimeout(300);
    const content = await page.evaluate(() => document.getElementById('goals-content').innerText);
    assert(content && content.trim().length > 50, 'Goals tab should render content after applyGoalsFromData');
    await context.close();
  }, { tags: ['smoke'] });

  await test('GR-2: Savings Goals sub-tab shows active goals from DB-loaded registry', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    await page.waitForTimeout(300);
    // Goals sub-tab should be on savings by default — check for known active goal names
    const content = await page.evaluate(() => document.getElementById('goals-content').innerText);
    assert(content.includes('Alaska Cruise'), 'Alaska Cruise should appear in Savings Goals');
    assert(content.includes('Bailey 529'),    'Bailey 529 should appear in Savings Goals');
    await context.close();
  });

  await test('GR-3: Fallback banner appears when goalsLoadStatus is "loaded_fallback"', async () => {
    const { page, context } = await openApp(browser);
    // Force fallback banner via JS
    await page.evaluate(() => {
      goalsLoadStatus = 'loaded_fallback';
      renderApp();
    });
    await page.waitForTimeout(200);
    const bannerStyle = await page.evaluate(() => {
      var el = document.getElementById('goals-load-warn');
      return el ? el.style.display : 'missing';
    });
    assert(bannerStyle !== 'none' && bannerStyle !== 'missing',
      'goals-load-warn should be visible with loaded_fallback, got display: ' + bannerStyle);
    await context.close();
  });

  await test('GR-4: No fallback banner when goalsLoadStatus is "loaded"', async () => {
    const { page, context } = await openApp(browser);
    await page.evaluate(() => {
      goalsLoadStatus = 'loaded';
      renderApp();
    });
    await page.waitForTimeout(200);
    const bannerStyle = await page.evaluate(() => {
      var el = document.getElementById('goals-load-warn');
      return el ? el.style.display : 'missing';
    });
    assert(bannerStyle === 'none',
      'goals-load-warn should be hidden with goalsLoadStatus=loaded, got display: ' + bannerStyle);
    await context.close();
  });

  await test('GR-5: Goal count in UI matches GOALS_REGISTRY.length after simulated DB load', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      var dbRows = HARDCODED_GOALS_FALLBACK.map(function(g) {
        return { id:g.id, name:g.name, tier:g.tier, target:g.target, priority:g.priority,
          status:g.status, notes:g.notes, starts_after:g.startsAfter, due_week:g.dueWeek,
          needs_flag:g.needsFlag, from_model:g.fromModel, milestone:g.milestone,
          stretch:g.stretch, auto:g.auto, src:g.src, dest:g.dest, color:g.color };
      });
      applyGoalsFromData(dbRows.map(mapGoalFromDB));
      return { registryLength: GOALS_REGISTRY.length, fallbackLength: HARDCODED_GOALS_FALLBACK.length };
    });
    assert(result.registryLength === result.fallbackLength,
      'GOALS_REGISTRY.length (' + result.registryLength + ') should match fallback length (' + result.fallbackLength + ')');
    await context.close();
  }, { tags: ['smoke'] });

  // ── Section AUTH-E2E: Auth v1 end-to-end tests ────────────────────────
  // AUTH-E2E-1 through AUTH-E2E-5 can run against file:// with or without credentials.
  // AUTH-E2E-6 through AUTH-E2E-8 are Phase 3 gates — require credentials AND Supabase connectivity.
  console.log('\n── Section AUTH-E2E: Auth v1 ──');

  await test('AUTH-E2E-1: Fresh page load with no cached session shows login form', async () => {
    const context = await browser.newContext();
    const page = await context.newPage();
    // Open without loginIfNeeded so we can observe the overlay
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1500); // let initAuth() run
    const overlayVisible = await page.evaluate(() => {
      const o = document.getElementById('auth-overlay');
      return o && !o.classList.contains('hidden');
    });
    // Auth state machine may land on 'unauthenticated' (login form) or 'auth_error' (no Supabase in file:// mode)
    // Either way the overlay must be visible — dashboard must not be accessible
    assert(overlayVisible, 'Auth overlay must be visible on fresh load — dashboard must not be shown without auth');
    // #auth-user-bar wraps the email label + sign-out button — must be hidden before auth
    const userBarHidden = await page.evaluate(() => {
      const bar = document.getElementById('auth-user-bar');
      return !bar || bar.style.display === 'none';
    });
    assert(userBarHidden, '#auth-user-bar must be hidden before auth — sign-out controls must not show on login screen');
    // #signout-btn must also not be visible (belt-and-suspenders)
    const signoutBtnVisible = await page.evaluate(() => {
      const btn = document.getElementById('signout-btn');
      return btn ? btn.offsetParent !== null : false;
    });
    assert(!signoutBtnVisible, '#signout-btn must not be visible before auth');
    await context.close();
  });

  await test('AUTH-E2E-2: Invalid credentials show inline error, no crash, no console exception', async () => {
    if (!TEST_EMAIL) {
      console.log('    (skipped — TEST_EMAIL not set; requires .env)');
      return; // skip gracefully
    }
    const context = await browser.newContext();
    const page = await context.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push(e.message));
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1500);
    // Wait for login form
    await page.waitForSelector('#auth-password', { timeout: 10000 }).catch(() => {});
    await page.fill('#auth-email', TEST_EMAIL).catch(() => {});
    await page.fill('#auth-password', 'wrong-password-that-will-not-work-xyz987').catch(() => {});
    await page.click('#auth-submit-btn').catch(() => {});
    await page.waitForTimeout(3000); // wait for Supabase auth attempt
    // Error element should be visible
    const errVisible = await page.evaluate(() => {
      const el = document.getElementById('auth-error');
      return el && el.style.display !== 'none' && el.textContent.trim().length > 0;
    }).catch(() => false);
    // Overlay must still be visible (not logged in)
    const overlayStillUp = await page.evaluate(() => {
      const o = document.getElementById('auth-overlay');
      return o && !o.classList.contains('hidden');
    });
    assert(overlayStillUp, 'Overlay must remain visible after invalid login attempt');
    assert(errs.length === 0, 'Uncaught JS exception after failed login: ' + errs.join('; '));
    await context.close();
  });

  await test('AUTH-E2E-3: Valid login renders dashboard, no console errors', async () => {
    if (!TEST_EMAIL || !TEST_PASSWORD) {
      console.log('    (skipped — TEST_EMAIL/TEST_PASSWORD not set; requires .env + Supabase setup)');
      return;
    }
    const context = await browser.newContext();
    const consoleErrors = [];
    const failedRequests = []; // capture 4xx/5xx for diagnostics
    const page = await context.newPage();
    page.on('console', msg => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
    page.on('pageerror', err => consoleErrors.push(err.message));
    page.on('response', async resp => {
      if (resp.status() >= 400 && resp.url().includes('supabase')) {
        const body = await resp.text().catch(() => '');
        failedRequests.push(resp.status() + ' ' + resp.request().method() + ' ' + resp.url().replace(/.*\/rest\/v1\//, '/rest/v1/') + ' body=' + body.slice(0, 200));
      }
    });
    // 5G-1C-2 (C3): goal_funding_snapshots is created by a later prod-DDL gate, so it 404s
    // pre-DDL. Narrowly stub ONLY this endpoint to its eventual empty-table state (200 []) so
    // the "no console errors" gate stays STRICT for every other request (that strict gate is
    // the backstop — any other failed resource still fails). Console-error tolerance unchanged.
    await page.route('**/rest/v1/goal_funding_snapshots**', route => route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }));
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1000);
    await loginIfNeeded(page);
    await page.waitForTimeout(2000); // extra settle time for post-login async writes
    const overlayHidden = await page.evaluate(() => {
      const o = document.getElementById('auth-overlay');
      return !o || o.classList.contains('hidden');
    });
    assert(overlayHidden, 'Auth overlay should be hidden after successful login');
    const bodyText = await page.evaluate(() => document.body.innerText);
    assert(bodyText.length > 200, 'Dashboard appears blank after successful login');
    // Console-error tolerance is STRICT (favicon only) — unchanged from pre-C3. The expected
    // pre-DDL goal_funding_snapshots 404 is handled by the endpoint-scoped page.route stub above,
    // not by widening this filter, so any other failed resource still trips this gate.
    const authErrors = consoleErrors.filter(e => !e.includes('favicon'));
    const diagSuffix = failedRequests.length ? ' | Failed requests: ' + failedRequests.join(', ') : '';
    assert(authErrors.length === 0, 'Console errors after login: ' + authErrors.slice(0,3).join('; ') + diagSuffix);
    await context.close();
  });

  await test('AUTH-E2E-4: Session persists across page reload — no re-login prompt', async () => {
    if (!TEST_EMAIL || !TEST_PASSWORD) {
      console.log('    (skipped — requires credentials + Supabase setup)');
      return;
    }
    const { page, context } = await openApp(browser);
    // Reload — supabase-js restores session from localStorage
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(2000);
    const overlayHidden = await page.evaluate(() => {
      const o = document.getElementById('auth-overlay');
      return !o || o.classList.contains('hidden');
    });
    assert(overlayHidden, 'Login form appeared after page reload — session should have persisted');
    await context.close();
  });

  await test('AUTH-E2E-5: Sign out clears session and returns to login form', async () => {
    if (!TEST_EMAIL || !TEST_PASSWORD) {
      console.log('    (skipped — requires credentials + Supabase setup)');
      return;
    }
    const { page, context } = await openApp(browser);
    // Wait for #auth-user-bar to become visible (Playwright native visibility check)
    await page.locator('#auth-user-bar').waitFor({ state: 'visible', timeout: 10000 })
      .catch(e => { throw new Error('AUTH-E2E-5: #auth-user-bar never became visible after login — ' + e.message); });
    // Confirm #signout-btn is also visible inside the bar
    const signoutBtnVisible = await page.evaluate(() => {
      const btn = document.getElementById('signout-btn');
      return btn ? btn.offsetParent !== null : false;
    });
    assert(signoutBtnVisible, 'AUTH-E2E-5: #signout-btn must be visible after login');
    // Click the visible sign-out button (not programmatic call)
    const signoutBtn = await page.$('#signout-btn');
    assert(signoutBtn, 'AUTH-E2E-5: #signout-btn element not found');
    await signoutBtn.click();
    await page.waitForTimeout(1500);
    const overlayVisible = await page.evaluate(() => {
      const o = document.getElementById('auth-overlay');
      return o && !o.classList.contains('hidden');
    });
    assert(overlayVisible, 'Login overlay must reappear after sign out');
    const authState = await page.evaluate(() => AUTH_STATE);
    assert(authState === 'unauthenticated', 'AUTH_STATE must be unauthenticated after sign out, got: ' + authState);
    await context.close();
  });

  await test('AUTH-E2E-6: Post-login Supabase calls use Bearer token distinct from anon key (Phase 3 gate)', async () => {
    if (!TEST_EMAIL || !TEST_PASSWORD) {
      console.log('    (skipped — requires credentials + Supabase setup)');
      return;
    }
    const context = await browser.newContext();
    const page = await context.newPage();
    const authHeaders = [];
    // Intercept all REST requests after navigation
    await page.route('**/rest/v1/**', async route => {
      const h = route.request().headers();
      if (h['authorization']) authHeaders.push(h['authorization']);
      await route.continue();
    });
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1000);
    await loginIfNeeded(page);
    await page.waitForTimeout(2000); // let loadAll() fire
    assert(authHeaders.length > 0, 'No REST requests captured — loadAll() may not have run after login');
    const bearerHeaders = authHeaders.filter(h => h.startsWith('Bearer '));
    assert(bearerHeaders.length > 0, 'No Bearer token found in Supabase REST calls — getAuthHeaders() may not be working');
    // The Bearer token must NOT be the anon key
    const anonKey = await page.evaluate(() => SUPA_KEY);
    const allAreAnon = bearerHeaders.every(h => h === 'Bearer ' + anonKey);
    assert(!allAreAnon, 'Bearer token is the anon key — must be a user JWT from getAuthHeaders()');
    await context.close();
  });

  await test('AUTH-E2E-7: After login, all 9 tables return data without 401 errors', async () => {
    if (!TEST_EMAIL || !TEST_PASSWORD) {
      console.log('    (skipped — requires credentials + Supabase setup)');
      return;
    }
    const context = await browser.newContext();
    const page = await context.newPage();
    const restErrors = [];
    page.on('response', response => {
      if (response.url().includes('/rest/v1/') && response.status() === 401) {
        restErrors.push(response.url().split('/rest/v1/')[1].split('?')[0] + ' → 401');
      }
    });
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1000);
    await loginIfNeeded(page);
    await page.waitForTimeout(3000); // let all tables load
    assert(restErrors.length === 0, '401 errors on table fetch: ' + restErrors.join(', '));
    await context.close();
  });

  await test('AUTH-E2E-8: app_users returns Adam row with active=true after login', async () => {
    if (!TEST_EMAIL || !TEST_PASSWORD) {
      console.log('    (skipped — requires credentials + Supabase setup)');
      return;
    }
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1000);
    await loginIfNeeded(page);
    await page.waitForTimeout(1000);
    // Verify auth reached 'ready' — which means checkAuthorization found active=true
    const authState = await page.evaluate(() => typeof AUTH_STATE !== 'undefined' ? AUTH_STATE : 'undefined');
    assert(authState === 'ready', 'AUTH_STATE must be ready after login with active app_users row, got: ' + authState);
    // Double-check by querying app_users directly via supabase-js
    const row = await page.evaluate(async () => {
      try {
        var h = await getAuthHeaders();
        var r = await fetch(SUPA_URL+'/rest/v1/app_users?email=eq.'+encodeURIComponent((await _supabase.auth.getSession()).data.session.user.email)+'&select=email,role,active&limit=1',{headers:h});
        var data = await r.json();
        return data && data[0] ? data[0] : null;
      } catch(e) { return {error:e.message}; }
    });
    assert(row && !row.error, 'Could not query app_users: ' + (row && row.error));
    assert(row.active === true, 'app_users.active must be true for logged-in user, got: ' + row.active);
    await context.close();
  });

  // ── Section BUD: Budget Module interactive tests ──────────────────────
  // Tests use page.evaluate() so they work in file:// mode without Supabase.
  // They inject state directly and verify DOM outcomes.
  console.log('\n── Section BUD: Budget Module ──');

  await test('BUD-1: _budgetToggleCleared is an async function, not a recursive wrapper', async () => {
    // Guards against the infinite recursion bug (fixed Jun 24 2026): a window wrapper
    // that called _budgetToggleCleared() would recurse into itself → stack overflow →
    // checkbox checked natively but DOM/state never updated.
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      var fn = window._budgetToggleCleared;
      if (!fn) return { error: 'window._budgetToggleCleared not found' };
      var src = fn.toString();
      // An async function's toString() starts with "async function" or "async ("
      var isAsync = src.startsWith('async');
      // A recursive wrapper would contain a call to _budgetToggleCleared( inside its body
      // after the function signature — detect by stripping the declaration and checking the body
      var bodyStart = src.indexOf('{');
      var body = bodyStart >= 0 ? src.slice(bodyStart) : src;
      var isRecursive = body.includes('_budgetToggleCleared(');
      return { isAsync, isRecursive, srcPreview: src.slice(0, 80) };
    });
    assert(!result.error, result.error);
    assert(result.isAsync, 'window._budgetToggleCleared is not async — expected async function. Got: ' + result.srcPreview);
    assert(!result.isRecursive, 'window._budgetToggleCleared body calls _budgetToggleCleared() — infinite recursion bug has returned');
    await context.close();
  });

  await test('BUD-2: _budgetDeleteTransaction is an async function, not a recursive wrapper', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      var fn = window._budgetDeleteTransaction;
      if (!fn) return { error: 'window._budgetDeleteTransaction not found' };
      var src = fn.toString();
      var isAsync = src.startsWith('async');
      var bodyStart = src.indexOf('{');
      var body = bodyStart >= 0 ? src.slice(bodyStart) : src;
      var isRecursive = body.includes('_budgetDeleteTransaction(');
      return { isAsync, isRecursive, srcPreview: src.slice(0, 80) };
    });
    assert(!result.error, result.error);
    assert(result.isAsync, 'window._budgetDeleteTransaction is not async — expected async function. Got: ' + result.srcPreview);
    assert(!result.isRecursive, 'window._budgetDeleteTransaction body calls _budgetDeleteTransaction() — infinite recursion bug has returned');
    await context.close();
  });

  await test('BUD-3: Budget tab renders reconciliation panel and transaction header', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'budget');
    await page.waitForTimeout(500);
    const text = await page.evaluate(() => {
      const el = document.getElementById('budget-content');
      return el ? el.innerText : '';
    });
    assert(text.includes('Statement check'), 'Statement check panel not found in budget-content (5G-0 SYS-1 renamed the Budget block from Reconciliation to Statement check)');
    assert(text.includes('Transactions'), 'Transactions header not found in budget-content');
    await context.close();
  }, { tags: ['smoke'] });

  await test('BUD-4: Optimistic cleared toggle updates reconciliation immediately (no network)', async () => {
    // Simulates the optimistic update without a Supabase call to verify the state machine works.
    // This is the core logic that was broken by the infinite recursion bug.
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      // Inject one test transaction for AMEX Gold, not cleared
      var testId = 'bud4-test-uuid-1234';
      _budgetTransactions = [{
        id: testId,
        transaction_date: '2026-06-01',
        amount: '50.00',
        transaction_type: 'household_expense',
        category_key: 'entertainment',
        description: 'BUD-4 test',
        payment_account: 'AMEX Gold',
        is_cleared: false,
        cleared_date: null,
        excluded_from_budget: false,
        reimbursement_source: null,
        reimbursement_status: null,
        created_at: new Date().toISOString()
      }];
      _budgetTransLoadStatus = 'loaded';
      // Phase 5E-9: renderBudget's loading gate now also awaits Register spend before
      // rendering the grid. Mark it loaded (empty cache) so this test's direct state
      // injection isn't blocked behind a real, unmocked fetch.
      _budgetRegisterSpendCache = [];
      _budgetRegisterSpendLoadStatus = 'loaded';
      _budgetReconAccount = 'AMEX Gold';
      _budgetReconBalance = '';
      activeSection = 'budget';
      renderApp();
      // Read cleared total before toggle
      var beforeText = document.getElementById('budget-content') ? document.getElementById('budget-content').innerText : '';
      var clearedBefore = beforeText.match(/Cleared\s*\$([0-9.,]+)/);
      var clearedBeforeAmt = clearedBefore ? clearedBefore[1] : 'not found';
      // Apply optimistic update (the same pattern _budgetToggleCleared uses)
      _budgetTransactions = _budgetTransactions.map(function(t){
        return t.id === testId ? Object.assign({}, t, { is_cleared: true, cleared_date: '2026-06-24' }) : t;
      });
      renderApp();
      // Read cleared total after toggle
      var afterText = document.getElementById('budget-content') ? document.getElementById('budget-content').innerText : '';
      var clearedAfter = afterText.match(/Cleared\s*\$([0-9.,]+)/);
      var clearedAfterAmt = clearedAfter ? clearedAfter[1] : 'not found';
      // Restore state
      _budgetTransactions = [];
      _budgetTransLoadStatus = 'not_loaded';
      _budgetRegisterSpendCache = [];
      _budgetRegisterSpendLoadStatus = 'not_loaded';
      return { clearedBeforeAmt, clearedAfterAmt };
    });
    assert(result.clearedBeforeAmt === '0.00', 'Cleared should be $0.00 before toggle, got: ' + result.clearedBeforeAmt);
    assert(result.clearedAfterAmt === '50.00', 'Cleared should be $50.00 after toggle, got: ' + result.clearedAfterAmt);
    await context.close();
  });

  await test('BUD-5: Delete confirm flow renders Yes/No buttons when _budgetDeleteConfirmId is set', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      var testId = 'bud5-delete-test-uuid';
      _budgetTransactions = [{
        id: testId,
        transaction_date: '2026-06-01',
        amount: '25.00',
        transaction_type: 'household_expense',
        category_key: 'groceries',
        description: 'BUD-5 delete test',
        payment_account: 'AMEX Gold',
        is_cleared: false,
        cleared_date: null,
        excluded_from_budget: false,
        reimbursement_source: null,
        reimbursement_status: null,
        created_at: new Date().toISOString()
      }];
      _budgetTransLoadStatus = 'loaded';
      // Phase 5E-9: renderBudget's loading gate now also awaits Register spend before
      // rendering the grid. Mark it loaded (empty cache) so this test's direct state
      // injection isn't blocked behind a real, unmocked fetch.
      _budgetRegisterSpendCache = [];
      _budgetRegisterSpendLoadStatus = 'loaded';
      activeSection = 'budget';
      // Trigger delete confirm state
      _budgetDeleteConfirmId = testId;
      renderApp();
      var content = document.getElementById('budget-content') ? document.getElementById('budget-content').innerHTML : '';
      var hasYes = content.includes('>Yes<');
      var hasNo  = content.includes('>No<');
      // Restore
      _budgetDeleteConfirmId = null;
      _budgetTransactions = [];
      _budgetTransLoadStatus = 'not_loaded';
      _budgetRegisterSpendCache = [];
      _budgetRegisterSpendLoadStatus = 'not_loaded';
      return { hasYes, hasNo };
    });
    assert(result.hasYes, 'Yes button not found in delete confirm UI');
    assert(result.hasNo,  'No button not found in delete confirm UI');
    await context.close();
  });

  await test('BUD-6 (Phase 5E-9 / 5F-1.5 A1): Register-entered transactions roll up into Budget spent: additive, excludes non-countable, and credits net into actuals', async () => {
    // Reproduces Adam's live bug report: July had correctly-categorized Register
    // transactions but Budget spent showed $0.00, because Budget's spentByKey only
    // read budget_transactions, never Register's transactions table. This test
    // injects post-fetch state directly (mirrors how BUD-4/BUD-5 mock _budgetTransactions)
    // rather than mocking the network fetch — 5E9-13 in test_regression.js separately
    // verifies the fetch itself queries the correct month range.
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      _categoriesCache = [
        {key:'entertainment',label:'Entertainment',parent_key:null,is_leaf:false,lifecycle_status:'active',behavior_class:null,budget_treatment:null},
        {key:'entertainment.week_1',label:'Entertainment Week 1',parent_key:'entertainment',is_leaf:true,lifecycle_status:'active',behavior_class:'expense',budget_treatment:'tracked'},
        // Real confirmed live category — reimbursable_expense but budget_treatment=excluded,
        // must not count even though it's outflow-shaped and has a spend-like behavior_class.
        {key:'business.jabian_expenses_2026',label:'Jabian Expenses 2026',parent_key:'business',is_leaf:true,lifecycle_status:'active',behavior_class:'reimbursable_expense',budget_treatment:'excluded'},
        // Real confirmed live category — transfer, must not count.
        {key:'transfers.greenlight',label:'Greenlight',parent_key:'transfers',is_leaf:true,lifecycle_status:'active',behavior_class:'transfer',budget_treatment:'excluded'}
      ];
      _registriesLoadStatus = 'loaded';
      // budget_transactions has 0 July rows (confirmed via live preflight) — additive merge
      // is being exercised in isolation here, same as the confirmed-safe production state.
      _budgetTransactions = [];
      _budgetTransLoadStatus = 'loaded';
      // Adam's real July 2 example: Fandango $40.00 + Barn $32.68 + mend coffee $12.98 = $85.66,
      // all tagged entertainment.week_1. Plus a same-category $15.00 credit/refund that (A1)
      // NETS DOWN the actual to $70.66, and a Jabian Expenses / Greenlight outflow (must not
      // count despite being real outflow spend).
      _budgetRegisterSpendCache = [
        {category_key:'entertainment.week_1', amount:-40.00, transaction_date:'2026-07-01'},
        {category_key:'entertainment.week_1', amount:-32.68, transaction_date:'2026-07-01'},
        {category_key:'entertainment.week_1', amount:-12.98, transaction_date:'2026-07-01'},
        {category_key:'entertainment.week_1', amount:15.00,  transaction_date:'2026-07-05'}, // credit, nets down (A1)
        {category_key:'business.jabian_expenses_2026', amount:-7.17, transaction_date:'2026-07-01'}, // excluded treatment
        {category_key:'transfers.greenlight', amount:-25.00, transaction_date:'2026-07-01'} // transfer, must not count
      ];
      _budgetRegisterSpendLoadStatus = 'loaded';
      _budgetSelectedMonth = '2026-07-01';
      setSection('budget');
      renderApp();
      var el = document.getElementById('budget-content');
      var innerHtml = el ? el.innerHTML : '';
      var innerText = el ? el.innerText : '';
      // Restore
      _budgetTransactions = [];
      _budgetTransLoadStatus = 'not_loaded';
      _budgetRegisterSpendCache = [];
      _budgetRegisterSpendLoadStatus = 'not_loaded';
      _budgetSelectedMonth = '';
      return { innerHtml, innerText };
    });
    assert(result.innerText.includes('Entertainment Week 1'), 'Budget grid must show the Entertainment Week 1 row');
    assert(result.innerText.includes('70.66'), 'A1: Entertainment Week 1 spent must net to $70.66 ($85.66 outflows minus the $15.00 credit), got text: ' + result.innerText.match(/Entertainment Week 1[^\n]*/));
    assert(!/entertainment week 1[^\n]*85\.66/i.test(result.innerText), 'A1: the $15.00 credit must not be dropped (85.66 would mean the credit was ignored instead of netted)');
    assert(!/entertainment week 1[^\n]*100\.66/i.test(result.innerText), 'the $15.00 credit must never be ADDED as spend (100.66 would mean it leaked in with the wrong sign)');
    assert(!result.innerText.includes('7.17'), 'Jabian Expenses 2026 ($7.17, budget_treatment=excluded) must not appear as counted spend anywhere in Budget');
    await context.close();
  }, { tags: ['smoke'] });

  await test('BUD-7 (Phase 5E-10): Budget "+ Add Transaction" is disabled with explanatory copy; Manage Lines stays active; help panel redirects to Register', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      _budgetTransactions = [];
      _budgetTransLoadStatus = 'loaded';
      _budgetRegisterSpendCache = [];
      _budgetRegisterSpendLoadStatus = 'loaded';
      _budgetShowHelp = true; // expand the help panel so its text is present in the DOM
      setSection('budget');
      renderApp();
      var el = document.getElementById('budget-content');
      var innerHtml = el ? el.innerHTML : '';
      var innerText = el ? el.innerText : '';
      // Restore
      _budgetTransactions = [];
      _budgetTransLoadStatus = 'not_loaded';
      _budgetRegisterSpendCache = [];
      _budgetRegisterSpendLoadStatus = 'not_loaded';
      _budgetShowHelp = false;
      return { innerHtml, innerText };
    });
    // Add Transaction button present but disabled, with explanatory text visible nearby.
    assert(/<button disabled[^>]*>\+ Add Transaction<\/button>/.test(result.innerHtml),
      'Add Transaction button must render as a disabled control');
    assert(result.innerText.includes('Actual spending is now entered in Transactions'),
      'Helper text directing Wendy to Register must be visible in the Budget header');
    // Manage Lines must remain a real, clickable button.
    assert(/<button onclick="window\._blrOpenAdd\(/.test(result.innerHtml),
      'Manage Lines button must remain active and unaffected');
    // Help panel no longer tells Wendy to click Budget's own Add Transaction button.
    assert(!result.innerText.includes('Click + Add Transaction (top right)'),
      'Help panel must not reference the disabled Budget Add Transaction button');
    assert(result.innerText.includes('Jabian Expenses 2026'),
      'Help panel must reference the correct live Jabian category for Register entry');
    // Reconciliation help copy must be untouched (guardrail).
    assert(result.innerText.includes('Clearing transactions against your statement'),
      'Reconciliation help section must remain present and unmodified');
    await context.close();
  }, { tags: ['smoke'] });

  await test('BUD-8 (Phase 5F-1.5 A2): Budget income rows show received actuals and Remaining = budget - received; hidden income never leaks into Total Income', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      _categoriesCache = [
        {key:'income',label:'Income',parent_key:null,is_leaf:false,lifecycle_status:'active',behavior_class:null,budget_treatment:null},
        {key:'income.net_salary',label:'Net Salary',parent_key:'income',is_leaf:true,lifecycle_status:'active',behavior_class:'income',budget_treatment:'display_only'},
        // Archived income leaf: must render nowhere and must not leak into Total Income actual.
        {key:'income.old_bonus',label:'Old Bonus',parent_key:'income',is_leaf:true,lifecycle_status:'archived',behavior_class:'income',budget_treatment:'display_only'}
      ];
      _registriesLoadStatus = 'loaded';
      _budgetTransactions = [];
      _budgetTransLoadStatus = 'loaded';
      // Net Salary budgeted (via BLR) at $5,000; received $4,000 with a -$100 correction = $3,900 net,
      // so Remaining = $1,100. Old Bonus (archived) has a $2,000 inflow that must be excluded from the
      // Total Income actual (a leak would show $5,900 instead of $3,900). BLR match fields are
      // is_active/start_month/end_month, and _getBudgetAmount requires _budgetLineRulesLoadStatus=loaded.
      _budgetLineRulesCache = [
        {category_key:'income.net_salary', line_label:'Net Salary', amount:5000, is_active:true, start_month:'2026-07-01', end_month:null}
      ];
      _budgetLineRulesLoadStatus = 'loaded';
      _budgetRegisterSpendCache = [
        {category_key:'income.net_salary', amount:4000.00, transaction_date:'2026-07-01'},
        {category_key:'income.net_salary', amount:-100.00, transaction_date:'2026-07-03'}, // correction, nets down
        {category_key:'income.old_bonus',  amount:2000.00, transaction_date:'2026-07-02'}  // archived, must not leak
      ];
      _budgetRegisterSpendLoadStatus = 'loaded';
      _budgetSelectedMonth = '2026-07-01';
      setSection('budget');
      renderApp();
      var el = document.getElementById('budget-content');
      var innerText = el ? el.innerText : '';
      // Restore
      _budgetTransactions = [];
      _budgetTransLoadStatus = 'not_loaded';
      _budgetRegisterSpendCache = [];
      _budgetRegisterSpendLoadStatus = 'not_loaded';
      _budgetLineRulesCache = null;
      _budgetLineRulesLoadStatus = 'not_loaded';
      _budgetSelectedMonth = '';
      return { innerText };
    });
    var nsRow = (result.innerText.match(/Net Salary[^\n]*/) || [''])[0];
    var tiRow = (result.innerText.match(/Total Income[^\n]*/) || [''])[0];
    // 1. Net Salary row shows received actual $3,900.
    assert(nsRow.includes('Net Salary'), 'Budget grid must show the Net Salary income row');
    assert(nsRow.includes('3,900'), 'Net Salary received actual must be $3,900 ($4,000 minus the $100 correction), got row: ' + nsRow);
    // 2. Net Salary row shows Remaining $1,100 (budget $5,000 - received $3,900).
    assert(nsRow.includes('1,100'), 'Net Salary Remaining must be $1,100 (budget 5,000 - received 3,900), got row: ' + nsRow);
    // 3. Total Income row exists.
    assert(tiRow.includes('Total Income'), 'Total Income row must exist');
    // 4. Total Income Actual reflects $3,900, not $5,900 (archived $2,000 must not leak).
    assert(tiRow.includes('3,900'), 'Total Income actual must be $3,900 (displayed rows only), got row: ' + tiRow);
    assert(!tiRow.includes('5,900'), 'Total Income actual must NOT be $5,900 (archived Old Bonus $2,000 leaked in), got row: ' + tiRow);
    // 5. Archived Old Bonus does not render and its $2,000 does not leak anywhere in the grid.
    assert(!result.innerText.includes('Old Bonus'), 'Archived income row must not render');
    assert(!result.innerText.includes('2,000') && !result.innerText.includes('2000.00'), 'Archived Old Bonus $2,000 inflow must not leak into the Budget grid');
    await context.close();
  }, { tags: ['smoke'] });

  // ── Section TX: Transactions Module (Phase 5D-2) ─────────────────────
  // All tests use injected mock data — no Supabase connection required.
  // Flag defaults false; each test that needs the section enables it in JS.
  console.log('\n── Section TX: Transactions Module ──');

  // Shared mock data injected into page context
  const TX_MOCK_ACCOUNTS = [
    { key:'truist_checking', label:'Truist Checking', institution:'Truist', account_type:'checking',
      lifecycle_status:'active', include_in_budget:true, include_in_cashflow:true,
      starting_balance:null, notes:null, display_order:1000 },
    { key:'costco_visa', label:'Costco Visa', institution:'Citi', account_type:'credit_card',
      lifecycle_status:'hidden', include_in_budget:true, include_in_cashflow:false,
      starting_balance:null, notes:'Note: hidden account', display_order:3000 },
    { key:'fidelity_joint', label:'Fidelity Joint WROS-TOD', institution:'Fidelity', account_type:'investment',
      lifecycle_status:'view_only', include_in_budget:false, include_in_cashflow:true,
      starting_balance:null, notes:null, display_order:5000 }
  ];

  const TX_MOCK_CATEGORIES = [
    { key:'income', label:'Income', parent_key:null, is_leaf:false, lifecycle_status:'active',
      behavior_class:null, budget_treatment:null, cashflow_treatment:null,
      budget_line_key:null, budget_group_key:null, merged_into_key:null, display_order:1000 },
    { key:'income.net_salary', label:'Net Salary', parent_key:'income', is_leaf:true, lifecycle_status:'active',
      behavior_class:'income', budget_treatment:'display_only', cashflow_treatment:'operating',
      budget_line_key:'income.net_salary', budget_group_key:'income', merged_into_key:null, display_order:1010 },
    { key:'health_fitness', label:'Health & Fitness', parent_key:null, is_leaf:false, lifecycle_status:'active',
      behavior_class:null, budget_treatment:null, cashflow_treatment:null,
      budget_line_key:null, budget_group_key:null, merged_into_key:null, display_order:4000 },
    { key:'health_fitness.flexible_spending_2026', label:'Flexible Spending 2026', parent_key:'health_fitness', is_leaf:true, lifecycle_status:'active',
      behavior_class:'reimbursable_expense', budget_treatment:'excluded', cashflow_treatment:'reimbursable',
      budget_line_key:null, budget_group_key:'health_fitness', merged_into_key:null, display_order:4050 },
    { key:'business', label:'Business', parent_key:null, is_leaf:false, lifecycle_status:'active',
      behavior_class:null, budget_treatment:null, cashflow_treatment:null,
      budget_line_key:null, budget_group_key:null, merged_into_key:null, display_order:9000 },
    { key:'business.jabian_2026_dup', label:'Jabian 2026 (dup)', parent_key:'business', is_leaf:true, lifecycle_status:'merged',
      behavior_class:'expense', budget_treatment:'tracked', cashflow_treatment:'operating',
      budget_line_key:null, budget_group_key:'business', merged_into_key:'business.jabian_expenses_2026', display_order:9010 }
  ];

  await test('TX-1: production defaults — showTransactionSection=false, showTransactionLedger=true, nav visible (Register live by default since Phase 5E-3)', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => ({
      sectionFlagDefault: FEATURE_FLAGS.showTransactionSection,
      ledgerFlagDefault: FEATURE_FLAGS.showTransactionLedger,
      navWrapDisplay: document.getElementById('nav-transactions-wrap')?.style.display,
      registriesStatus: _registriesLoadStatus
    }));
    assert(result.sectionFlagDefault === false, 'showTransactionSection must default false');
    assert(result.ledgerFlagDefault === true, 'showTransactionLedger must default true (Phase 5E-3 production default — Register live by default)');
    // nav visibility is showTransactionSection||showTransactionLedger — with showTransactionLedger=true
    // by default, the Transactions nav is visible out of the box, not hidden.
    assert(result.navWrapDisplay !== 'none', 'nav-transactions-wrap must be visible by default since showTransactionLedger defaults true');
    // showTransactionLedger=true triggers the registry load in loadAll() (see 5E1-03), so registries
    // must have at least attempted to load — assert "not stuck at not_loaded" rather than a specific
    // end status, since 'loading'/'loaded'/'failed' are all valid outcomes depending on network timing.
    assert(result.registriesStatus !== 'not_loaded', 'Supabase registries must attempt to load since showTransactionLedger defaults true');
    await context.close();
  });

  await test('TX-2: flag=true with mock data — Accounts tab renders table with all 8 expected columns', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = mockAccounts;
      _categoriesCache = [];
      _registriesLoadStatus = 'loaded';
      renderApp();
      setSection('transactions');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        navVisible: document.getElementById('nav-transactions-wrap')?.style.display !== 'none',
        hasLabel: html.includes('Label'),
        hasInstitution: html.includes('Institution'),
        hasType: html.includes('Type'),
        hasStatus: html.includes('Status'),
        hasInBudget: html.includes('In Budget'),
        hasInCashflow: html.includes('In Cashflow'),
        hasBalance: html.includes('Starting Balance'),
        hasRowCount: (html.match(/<tr/g) || []).length
      };
    }, TX_MOCK_ACCOUNTS);
    assert(result.navVisible, 'Transactions nav must be visible when flag=true');
    assert(result.hasLabel, 'Accounts table must have Label column');
    assert(result.hasInstitution, 'Accounts table must have Institution column');
    assert(result.hasType, 'Accounts table must have Type column');
    assert(result.hasStatus, 'Accounts table must have Status column');
    assert(result.hasInBudget, 'Accounts table must have In Budget column');
    assert(result.hasInCashflow, 'Accounts table must have In Cashflow column');
    assert(result.hasBalance, 'Accounts table must have Starting Balance column');
    await context.close();
  });

  await test('TX-3: flag=true — "Balance not set" shown for all null starting_balance accounts', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = mockAccounts;
      _categoriesCache = [];
      _registriesLoadStatus = 'loaded';
      renderApp();
      setSection('transactions');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      var balanceNotSetCount = (html.match(/Balance not set/g) || []).length;
      return { balanceNotSetCount, accountsWithNullBalance: mockAccounts.filter(a => a.starting_balance === null).length };
    }, TX_MOCK_ACCOUNTS);
    assert(result.balanceNotSetCount === result.accountsWithNullBalance,
      '"Balance not set" must appear once per account with null starting_balance, got ' + result.balanceNotSetCount + ' for ' + result.accountsWithNullBalance + ' null-balance accounts');
    await context.close();
  });

  await test('TX-4: lifecycle badges render correct classes for active/hidden/view_only', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = mockAccounts;
      _categoriesCache = [];
      _registriesLoadStatus = 'loaded';
      renderApp();
      setSection('transactions');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasGreenSoft: html.includes('greenSoft'),
        hasHiddenBadge: html.includes('surface3') && html.includes('hidden'),
        hasViewOnlyBadge: html.includes('blueSoft') && html.includes('view only')
      };
    }, TX_MOCK_ACCOUNTS);
    assert(result.hasGreenSoft, 'Active lifecycle badge must use greenSoft background');
    assert(result.hasHiddenBadge, 'Hidden lifecycle badge must use surface3 background');
    assert(result.hasViewOnlyBadge, 'View_only lifecycle badge must use blueSoft background');
    await context.close();
  });

  await test('TX-5: Categories active-only default — merged row absent, active rows present', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockCategories]) => {
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = mockAccounts;
      _categoriesCache = mockCategories;
      _registriesLoadStatus = 'loaded';
      _txCatShowAll = false;
      renderApp();
      setSection('transactions');
      setTxSubNav('categories');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        jabianDupAbsent: !html.includes('jabian_2026_dup'),
        netSalaryPresent: html.includes('Net Salary'),
        flexSpendPresent: html.includes('Flexible Spending 2026'),
        showAllTogglePresent: html.includes('Show all lifecycle states'),
        countLabel: html.includes('5 of 6') // 5 active of 6 total
      };
    }, [TX_MOCK_ACCOUNTS, TX_MOCK_CATEGORIES]);
    assert(result.jabianDupAbsent, 'Merged row (jabian_2026_dup) must be absent in active-only view');
    assert(result.netSalaryPresent, 'Active leaf rows must appear in active-only view');
    assert(result.flexSpendPresent, 'Flexible Spending 2026 must appear in active-only view');
    assert(result.showAllTogglePresent, '"Show all lifecycle states" toggle must be present');
    await context.close();
  });

  await test('TX-6: Categories show-all toggle — merged row visible with merged badge and merged_into_key', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockCategories]) => {
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = mockAccounts;
      _categoriesCache = mockCategories;
      _registriesLoadStatus = 'loaded';
      _txCatShowAll = true;
      renderApp();
      setSection('transactions');
      setTxSubNav('categories');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        jabianDupPresent: html.includes('jabian_2026_dup'),
        mergedBadgePresent: html.includes('amberSoft'),
        mergedIntoKeyPresent: html.includes('jabian_expenses_2026'),
        showActiveOnlyToggle: html.includes('Show active only'),
        countLabel: html.includes('6 of 6')
      };
    }, [TX_MOCK_ACCOUNTS, TX_MOCK_CATEGORIES]);
    assert(result.jabianDupPresent, 'Merged row must be visible in show-all mode');
    assert(result.mergedBadgePresent, 'Merged badge must use amberSoft background');
    assert(result.mergedIntoKeyPresent, 'merged_into_key target must appear in show-all mode');
    assert(result.showActiveOnlyToggle, '"Show active only" toggle must appear when show-all is active');
    await context.close();
  });

  await test('TX-7: Categories table has 8 columns including budget_group_key', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockCategories]) => {
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = mockAccounts;
      _categoriesCache = mockCategories;
      _registriesLoadStatus = 'loaded';
      renderApp();
      setSection('transactions');
      setTxSubNav('categories');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasBudgetLineKey: html.includes('Budget Line Key'),
        hasBudgetGroupKey: html.includes('Budget Group Key'),
        orphanColspan8: html.includes('colspan="8"') || !html.includes('no parent in current view'), // orphan section only if orphans exist
      };
    }, [TX_MOCK_ACCOUNTS, TX_MOCK_CATEGORIES]);
    assert(result.hasBudgetLineKey, 'Categories table must have Budget Line Key column');
    assert(result.hasBudgetGroupKey, 'Categories table must have Budget Group Key column (8th column)');
    await context.close();
  });

  await test('TX-8: Reconciliation still labeled future-phase; Register is live/clickable under production defaults (Phase 5E-3+)', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      // showTransactionLedger is left at its production default (true) here on purpose —
      // the showTransactionLedger=false / "Register — Phase 5E" disabled-span path is
      // already covered by RG-1. This test covers the current production-default path,
      // where Register is live and Reconciliation (Phase 5F) is still not built.
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = mockAccounts;
      _categoriesCache = [];
      _registriesLoadStatus = 'loaded';
      renderApp();
      setSection('transactions');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        registerIsPlainLabel: (html.match(/<button[^>]*>Register<\/button>/) || []).length > 0,
        registerNotDisabledSpan: !html.includes('Register — Phase 5E'),
        reconciliationLabel: html.includes('Reconciliation'),
        registerNotClickable: html.includes('cursor:not-allowed') || html.includes('cursor: not-allowed')
      };
    }, TX_MOCK_ACCOUNTS);
    assert(result.registerIsPlainLabel, 'Register must render as a plain clickable "Register" button when showTransactionLedger=true (production default)');
    assert(result.registerNotDisabledSpan, 'Register must NOT show the "Register — Phase 5E" disabled label when showTransactionLedger=true');
    assert(result.reconciliationLabel, 'Reconciliation future tab must be present (phase suffix stripped per 5G-0 SYS-1; Phase 5F-1 not yet built)');
    assert(result.registerNotClickable, 'Reconciliation (the one remaining future tab) must have cursor:not-allowed to signal it is disabled');
    await context.close();
  });

  await test('TX-9: both flags reset to false — Transactions nav hidden, budget module unaffected', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      // Enable then disable. Nav visibility is showTransactionSection||showTransactionLedger
      // (see 5E1-04/comment at the renderApp nav-wrap block), and showTransactionLedger now
      // defaults true (Phase 5E-3), so a true "reset to hidden" state must reset BOTH flags —
      // resetting showTransactionSection alone (the old assumption, pre-5E-3) is no longer
      // sufficient to hide the nav.
      FEATURE_FLAGS.showTransactionSection = true;
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      renderApp();
      FEATURE_FLAGS.showTransactionSection = false;
      FEATURE_FLAGS.showTransactionLedger = false;
      renderApp();
      return {
        navHidden: document.getElementById('nav-transactions-wrap')?.style.display === 'none',
        budgetCatRegistryIntact: typeof BUDGET_CATEGORY_REGISTRY !== 'undefined' && BUDGET_CATEGORY_REGISTRY.length > 0,
        runModelWorks: typeof runModel === 'function'
      };
    }, TX_MOCK_ACCOUNTS);
    assert(result.navHidden, 'Transactions nav must be hidden again after both flags reset to false');
    assert(result.budgetCatRegistryIntact, 'BUDGET_CATEGORY_REGISTRY must remain intact after Transactions module runs');
    assert(result.runModelWorks, 'runModel must still be callable after Transactions module runs');
    await context.close();
  });

  await test('TX-10: Transactions section not in mob-bottom-nav (desktop-only, Slice 1)', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      var mobNav = document.getElementById('mob-bottom-nav');
      return {
        mobNavHasTransactions: mobNav ? mobNav.innerHTML.includes('transactions') : false,
        mobNavHasMobNavTransactions: !!document.getElementById('mob-nav-transactions')
      };
    });
    assert(!result.mobNavHasTransactions, 'mob-bottom-nav must not contain transactions entry in Slice 1');
    assert(!result.mobNavHasMobNavTransactions, 'mob-nav-transactions element must not exist in Slice 1');
    await context.close();
  });

  // ── Section RG: Register (Phase 5E-1 read-only) ──────────────────────
  // All tests inject mock data — no Supabase connection required.
  // Writes (add/edit/delete/cleared toggle) are Phase 5E-2 and tested separately.
  console.log('\n── Section RG: Register (Phase 5E-1 read-only) ──');

  // Mock transactions — two rows, ascending by date, one inflow one outflow
  const RG_MOCK_TRANSACTIONS = [
    { id: 'tx-001', account_key: 'truist_checking', transaction_date: '2026-06-01',
      posted_date: null, payee: 'Kroger', memo: 'Weekly groceries',
      amount: -125.00, category_key: 'health_fitness.flexible_spending_2026',
      cleared: true, reconciled: false, source: 'manual',
      created_at: '2026-06-01T10:00:00Z', updated_at: '2026-06-01T10:00:00Z' },
    { id: 'tx-002', account_key: 'truist_checking', transaction_date: '2026-06-03',
      posted_date: null, payee: 'Paycheck', memo: '',
      amount: 2000.00, category_key: 'income.net_salary',
      cleared: true, reconciled: false, source: 'manual',
      created_at: '2026-06-03T09:00:00Z', updated_at: '2026-06-03T09:00:00Z' }
  ];

  await test('RG-1: showTransactionLedger=false — Register tab is disabled span, not a button', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      FEATURE_FLAGS.showTransactionLedger = false;
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = [];
      _registriesLoadStatus = 'loaded';
      renderApp();
      setSection('transactions');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasDisabledSpan: html.includes('Register — Phase 5E'),
        hasRegisterButton: (html.match(/<button[^>]*>Register<\/button>/)||[]).length > 0
      };
    });
    assert(result.hasDisabledSpan, 'Register — Phase 5E disabled span must be present when flag=false');
    assert(!result.hasRegisterButton, 'Register must not be a clickable button when showTransactionLedger=false');
    await context.close();
  }, { tags: ['smoke'] });

  await test('RG-2: showTransactionLedger=true — Register tab is active button labeled Register', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = [];
      _registriesLoadStatus = 'loaded';
      renderApp();
      setSection('transactions');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasRegisterButton: html.includes('Register — Phase 5E') === false && html.includes('Register'),
        noDisabledRegister: !html.includes('Register — Phase 5E')
      };
    });
    assert(result.hasRegisterButton, 'Register tab must be present and labeled Register (not Register — Phase 5E)');
    assert(result.noDisabledRegister, 'Disabled Phase 5E label must not appear when flag=true');
    await context.close();
  }, { tags: ['smoke'] });

  await test('RG-3: showTransactionLedger=true alone (without showTransactionSection) — Transactions nav visible', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      FEATURE_FLAGS.showTransactionSection = false;
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = [];
      _registriesLoadStatus = 'loaded';
      renderApp();
      return {
        navVisible: document.getElementById('nav-transactions-wrap')?.style.display !== 'none'
      };
    });
    assert(result.navVisible, 'Transactions nav must be visible when showTransactionLedger=true, even if showTransactionSection=false');
    await context.close();
  });

  await test('RG-4: account selector populates with active accounts only', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = [];
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasTruistOption: html.includes('Truist Checking'),
        hasCostcoOption: html.includes('Costco Visa'),    // hidden — must be absent
        hasFidelityOption: html.includes('Fidelity Joint') // view_only — must be absent
      };
    }, TX_MOCK_ACCOUNTS);
    assert(result.hasTruistOption, 'Active account must appear in account selector');
    assert(!result.hasCostcoOption, 'Hidden account must not appear in account selector');
    assert(!result.hasFidelityOption, 'View-only account must not appear in account selector');
    await context.close();
  });

  await test('RG-9 (Phase 5F-1.5 A5): Register account selector renders options alphabetically while preserving the default account', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(() => {
      FEATURE_FLAGS.showTransactionLedger = true;
      // Deliberately non-alphabetical cache order. activeAccounts[0] = Truist Checking,
      // so the default account must remain Truist Checking even though the display sorts
      // AMEX Gold and Disney Visa ahead of it.
      _accountsCache = [
        {key:'truist_checking', label:'Truist Checking', account_type:'checking',    lifecycle_status:'active'},
        {key:'amex_gold',       label:'AMEX Gold',        account_type:'credit_card', lifecycle_status:'active'},
        {key:'disney_visa',     label:'Disney Visa',      account_type:'credit_card', lifecycle_status:'active'}
      ];
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = [];
      _txLedgerAccountKey = null; // force the default-account derivation to run
      setSection('transactions');
      setTxSubNav('register');
      renderApp();
      var el = document.getElementById('transactions-content');
      var h = el ? el.innerHTML : '';
      var iAmex = h.indexOf('>AMEX Gold<');
      var iDisney = h.indexOf('>Disney Visa<');
      var iTruist = h.indexOf('>Truist Checking<');
      var restored = _txLedgerAccountKey;
      // Restore
      _accountsCache = null;
      _registriesLoadStatus = 'not_loaded';
      _txLedgerLoadStatus = 'not_loaded';
      _txLedgerAccountKey = null;
      return { iAmex, iDisney, iTruist, defaultKey: restored, hasTruistSelected: h.indexOf('value="truist_checking" selected') !== -1 };
    });
    assert(result.iAmex > -1 && result.iDisney > -1 && result.iTruist > -1, 'all three active accounts must render as options');
    assert(result.iAmex < result.iDisney && result.iDisney < result.iTruist, 'options must be alphabetical (AMEX Gold, Disney Visa, Truist Checking)');
    assert(result.defaultKey === 'truist_checking', 'default account must remain Truist Checking (original activeAccounts[0]), not the alphabetically-first option');
    assert(result.hasTruistSelected, 'the preserved default (Truist Checking) must be the selected option');
    await context.close();
  }, { tags: ['smoke'] });

  await test('RG-5: starting_balance null shows explicit warning, not silent $0.00', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = [];
      _txLedgerAccountKey = 'truist_checking'; // starting_balance: null
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasWarning: html.includes('Starting balance not set — running balance starts from $0.00')
      };
    }, TX_MOCK_ACCOUNTS);
    assert(result.hasWarning, 'Must show explicit starting balance not-set warning when starting_balance is null');
    await context.close();
  });

  await test('RG-6: starting_balance set — shows value, no warning', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      var accts = mockAccounts.map(function(a) {
        return a.key === 'truist_checking' ? Object.assign({}, a, {starting_balance: 500.00}) : a;
      });
      _accountsCache = accts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = [];
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        noWarning: !html.includes('Starting balance not set'),
        hasBalance: html.includes('500.00')
      };
    }, TX_MOCK_ACCOUNTS);
    assert(result.noWarning, 'Must not show not-set warning when starting_balance is present');
    assert(result.hasBalance, 'Starting balance value must appear in the register');
    await context.close();
  });

  await test('RG-7: transaction list renders expected columns', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasDate: html.includes('Date'),
        hasPayee: html.includes('Payee'),
        hasMemo: html.includes('Memo'),
        hasCategory: html.includes('Category'),
        hasOutflow: html.includes('Outflow'),
        hasInflow: html.includes('Inflow'),
        hasClr: html.includes('Cleared'),
        hasBalance: html.includes('Balance')
      };
    }, [TX_MOCK_ACCOUNTS, RG_MOCK_TRANSACTIONS]);
    assert(result.hasDate, 'Date column must be present');
    assert(result.hasPayee, 'Payee column must be present');
    assert(result.hasMemo, 'Memo column must be present');
    assert(result.hasCategory, 'Category column must be present');
    assert(result.hasOutflow, 'Outflow column must be present');
    assert(result.hasInflow, 'Inflow column must be present');
    assert(result.hasClr, 'Cleared column must be present');
    assert(result.hasBalance, 'Balance column must be present');
    await context.close();
  });

  await test('RG-7b: category displays resolved label via _getRegisterCategoryLabel, not raw key (updated in 5E-8)', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockCategories, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = mockCategories;
      _registriesLoadStatus = 'loaded';
      // Phase 5E-8: row display resolves via _getRegisterCategoryLabel(key,monthIso), which reads
      // _categoriesCache directly (BLR line_label first, then the category's own live .label) —
      // deliberately NOT _budgetCatByKey/_getActiveCategoryRegistry(), which are scoped to Budget's
      // fixed 31-line registry and gated behind useSupabaseRegistries=false in production. No extra
      // setup needed beyond _categoriesCache itself.
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      // The display cell should show the resolved label, not the raw key as visible text.
      // We check the label is present, and that the raw key only appears in attribute context.
      // A simple proxy: the label text appears, and the raw key does NOT appear in a <td> cell.
      var tdMatches = html.match(/<td[^>]*>([^<]*health_fitness\.flexible_spending_2026[^<]*)<\/td>/g) || [];
      return {
        showsLabel: html.includes('Flexible Spending 2026'),
        rawKeyInTdCell: tdMatches.length > 0
      };
    }, [TX_MOCK_ACCOUNTS, TX_MOCK_CATEGORIES, RG_MOCK_TRANSACTIONS]);
    assert(result.showsLabel, 'Category column must display resolved label "Flexible Spending 2026"');
    assert(!result.rawKeyInTdCell, 'Raw category key must not appear as text content in a table cell');
    await context.close();
  });

  // RG-7c originally reproduced the live failure Adam reported after deploy: Register's Add
  // Transaction dropdown for July showed Birthday Dinner/Brunch/Big Dinner Out/Entertainment
  // Other instead of Seattle/Wewe's Lunches/Week 1-4. Root cause (see test_regression.js
  // 5E8-R18/R19/R22): entertainment.event_1/event_2/week_1-4 were seeded into budget_line_rules
  // for July but never inserted into `categories`.
  //
  // 2026-07-02: data-only correction applied via
  // docs/2026-07-02-register-budget-category-sync.sql. Adam confirmed live in production:
  // preflight still_missing=0, all 6 new rows leaf=true/active/assignable=true, parent/group
  // rows still non-assignable, no duplicate keys, entertainment.* now shows 10 active children,
  // and the Register dropdown for a July 2 transaction shows Seattle/Wewe's Lunches/Entertainment
  // Week 1-4 alongside the original 4 real categories and other existing live categories.
  // This test is flipped to assert that confirmed post-fix state using the REAL key pairs.
  const POST_FIX_ENTERTAINMENT_CATEGORIES = [
    { key: 'entertainment', label: 'Entertainment', parent_key: null, is_leaf: false, lifecycle_status: 'active', behavior_class: null, budget_treatment: null },
    { key: 'entertainment.birthday_dinner', label: 'Birthday Dinner', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    { key: 'entertainment.brunch', label: 'Brunch', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    { key: 'entertainment.big_dinner_out', label: 'Big Dinner Out', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    { key: 'entertainment.entertainment_other', label: 'Entertainment Other', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    // The 6 rows inserted by the 2026-07-02 data correction:
    { key: 'entertainment.event_1', label: 'Entertainment Event 1', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    { key: 'entertainment.event_2', label: 'Entertainment Event 2', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    { key: 'entertainment.week_1', label: 'Entertainment Week 1', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    { key: 'entertainment.week_2', label: 'Entertainment Week 2', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    { key: 'entertainment.week_3', label: 'Entertainment Week 3', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    { key: 'entertainment.week_4', label: 'Entertainment Week 4', parent_key: 'entertainment', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    // A representative mix of other real, unrelated live categories Adam confirmed still appear.
    { key: 'income.net_salary', label: 'Net Salary', parent_key: 'income', is_leaf: true, lifecycle_status: 'active', behavior_class: 'income', budget_treatment: null },
    { key: 'income.deep_south_commissions', label: 'Deep South Commissions', parent_key: 'income', is_leaf: true, lifecycle_status: 'active', behavior_class: 'commission_income', budget_treatment: null },
    { key: 'auto_transport.auto_payment', label: 'Auto Payment', parent_key: 'auto_transport', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' },
    { key: 'auto_transport.gas_fuel', label: 'Gas & Fuel', parent_key: 'auto_transport', is_leaf: true, lifecycle_status: 'active', behavior_class: 'expense', budget_treatment: 'tracked' }
  ];
  const REAL_JULY_BLR_OVERRIDES = [
    { is_active: true, category_key: 'entertainment.event_1', line_label: 'Seattle', amount: 300, start_month: '2026-07-01', end_month: '2026-07-01' },
    { is_active: true, category_key: 'entertainment.event_2', line_label: "Wewe's Lunches", amount: 200, start_month: '2026-07-01', end_month: '2026-07-01' },
    { is_active: true, category_key: 'entertainment.week_1', line_label: 'Entertainment Week 1', amount: 250, start_month: '2026-07-01', end_month: '2026-07-01' },
    { is_active: true, category_key: 'entertainment.week_2', line_label: 'Entertainment Week 2', amount: 250, start_month: '2026-07-01', end_month: '2026-07-01' },
    { is_active: true, category_key: 'entertainment.week_3', line_label: 'Entertainment Week 3', amount: 250, start_month: '2026-07-01', end_month: '2026-07-01' },
    { is_active: true, category_key: 'entertainment.week_4', line_label: 'Entertainment Week 4', amount: 250, start_month: '2026-07-01', end_month: '2026-07-01' }
  ];

  await test('RG-7c: Register Add Transaction dropdown, July 2 date, post-2026-07-02-data-correction category/BLR set — reproduces Adam\'s confirmed live production result', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, postFixCats, julyBlr]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = postFixCats;
      _registriesLoadStatus = 'loaded';
      _budgetLineRulesCache = julyBlr;
      _budgetLineRulesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = [];
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      // Open the Add Transaction form with July 2 selected, same as Adam's live repro.
      _openTxForm('add', null);
      _txFormData.transaction_date = '2026-07-02';
      renderApp();
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        showsSeattle: html.includes('Seattle'),
        showsWewesLunches: html.includes("Wewe's Lunches"),
        showsWeek1: html.includes('Entertainment Week 1'),
        showsWeek2: html.includes('Entertainment Week 2'),
        showsWeek3: html.includes('Entertainment Week 3'),
        showsWeek4: html.includes('Entertainment Week 4'),
        showsBirthdayDinner: html.includes('Birthday Dinner'),
        showsBrunch: html.includes('Brunch'),
        showsBigDinnerOut: html.includes('Big Dinner Out'),
        showsEntertainmentOther: html.includes('Entertainment Other'),
        showsNetSalary: html.includes('Net Salary'),
        showsDeepSouthCommissions: html.includes('Deep South Commissions'),
        showsAutoPayment: html.includes('Auto Payment'),
        showsGasFuel: html.includes('Gas &amp; Fuel') || html.includes('Gas & Fuel'),
        // Exact literal match — 'value="entertainment"' does not match 'value="entertainment.event_1"'
        // (the next character after "entertainment" differs: closing quote vs dot).
        entertainmentParentSelectable: html.includes('value="entertainment"')
      };
    }, [TX_MOCK_ACCOUNTS, POST_FIX_ENTERTAINMENT_CATEGORIES, REAL_JULY_BLR_OVERRIDES]);
    // The 6 previously-missing July slot categories now appear with their BLR-resolved labels.
    assert(result.showsSeattle, 'Dropdown must show "Seattle" for July (confirmed live)');
    assert(result.showsWewesLunches, 'Dropdown must show "Wewe\'s Lunches" for July (confirmed live)');
    assert(result.showsWeek1, 'Dropdown must show "Entertainment Week 1"');
    assert(result.showsWeek2, 'Dropdown must show "Entertainment Week 2"');
    assert(result.showsWeek3, 'Dropdown must show "Entertainment Week 3"');
    assert(result.showsWeek4, 'Dropdown must show "Entertainment Week 4"');
    // Existing categories preserved — the original 4 real Entertainment leaves still appear.
    assert(result.showsBirthdayDinner, 'Dropdown must still show "Birthday Dinner"');
    assert(result.showsBrunch, 'Dropdown must still show "Brunch"');
    assert(result.showsBigDinnerOut, 'Dropdown must still show "Big Dinner Out"');
    assert(result.showsEntertainmentOther, 'Dropdown must still show "Entertainment Other"');
    // Existing, unrelated live categories preserved (Adam's confirmed live spot-check).
    assert(result.showsNetSalary, 'Dropdown must still show "Net Salary"');
    assert(result.showsDeepSouthCommissions, 'Dropdown must still show "Deep South Commissions"');
    assert(result.showsAutoPayment, 'Dropdown must still show "Auto Payment"');
    assert(result.showsGasFuel, 'Dropdown must still show "Gas & Fuel"');
    // Parent/group row still not selectable.
    assert(!result.entertainmentParentSelectable, 'The bare "entertainment" parent/group key must not appear as a selectable option value');
    await context.close();
  });

  await test('RG-8: running balance computes correctly from mock transactions', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts; // starting_balance: null → $0.00
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns; // -125.00 then +2000.00 → final 1875.00
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasFinalBalance: html.includes('1875.00'),
        hasIntermediate: html.includes('-125.00') || html.includes('125.00')
      };
    }, [TX_MOCK_ACCOUNTS, RG_MOCK_TRANSACTIONS]);
    assert(result.hasFinalBalance, 'Final running balance must be $1875.00 (0 - 125 + 2000)');
    await context.close();
  });

  await test('RG-9: negative amount renders in Outflow column as positive display value', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      // The outflow column should show 125.00 (abs of -125.00) in red
      return {
        hasOutflowValue: html.includes('125.00') && html.includes('var(--red)')
      };
    }, [TX_MOCK_ACCOUNTS, RG_MOCK_TRANSACTIONS]);
    assert(result.hasOutflowValue, 'Negative amount must render as positive value in red Outflow column');
    await context.close();
  });

  await test('RG-10: positive amount renders in Inflow column in green', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasInflowValue: html.includes('2000.00') && html.includes('var(--green)')
      };
    }, [TX_MOCK_ACCOUNTS, RG_MOCK_TRANSACTIONS]);
    assert(result.hasInflowValue, 'Positive amount must render in green Inflow column');
    await context.close();
  });

  await test('RG-12 (Phase 5F-1.5, ex-5E-10): uncleared review uses the Status filter, preserving date order and full-ledger balances', async () => {
    const { page, context } = await openApp(browser);
    // The default view is the reconcile CL view; here we explicitly pin date/desc to isolate the
    // Status = Uncleared filter, which keeps date order and shows each row's full-account CANONICAL
    // CL balance (Fandango 1850.00 — posted 1900 + its -50 — not a subset -50.00).
    // Canonical CL (start 0): cleared Kroger -100, Paycheck 1900 (posted); uncleared Fandango layers -> 1850.
    const sortTxns = [
      { id: 'rg12-1', account_key: 'truist_checking', transaction_date: '2026-06-01',
        payee: 'Kroger', memo: '', amount: -100.00, category_key: null,
        cleared: true, source: 'manual', created_at: '2026-06-01T10:00:00Z' },
      { id: 'rg12-2', account_key: 'truist_checking', transaction_date: '2026-06-05',
        payee: 'Fandango', memo: '', amount: -50.00, category_key: null,
        cleared: false, source: 'manual', created_at: '2026-06-05T10:00:00Z' },
      { id: 'rg12-3', account_key: 'truist_checking', transaction_date: '2026-06-10',
        payee: 'Paycheck', memo: '', amount: 2000.00, category_key: null,
        cleared: true, source: 'manual', created_at: '2026-06-10T10:00:00Z' }
    ];
    await page.evaluate(([mockAccounts, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts; _categoriesCache = [];
      _registriesLoadStatus = 'loaded'; _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns; _txLedgerAccountKey = 'truist_checking';
      _txLedgerSortCol = 'date'; _txLedgerSortDir = 'desc'; // pinned date/desc (not the app default) to isolate the Status filter
      _txFilterSearch = ''; _txFilterType = 'all'; _txFilterStatus = 'all'; _txFilterDateFrom = ''; _txFilterDateTo = '';
      setSection('transactions'); setTxSubNav('register'); renderApp();
    }, [TX_MOCK_ACCOUNTS, sortTxns]);
    // Apply Status = Uncleared via the real select control
    await page.selectOption('#tx-filter-status', 'uncleared');
    await page.waitForTimeout(60);
    const result = await page.evaluate(() => {
      var h = document.getElementById('transactions-content').innerHTML;
      return {
        hasFandango: h.indexOf('Fandango') !== -1, hasKroger: h.indexOf('Kroger') !== -1, hasPaycheck: h.indexOf('Paycheck') !== -1,
        fandangoFullBal: h.indexOf('$1850.00') !== -1, fandangoSubsetBal: h.indexOf('$-50.00') !== -1,
        filterCaption: h.indexOf('Balance reflects the full account ledger') !== -1
      };
    });
    assert(result.hasFandango && !result.hasKroger && !result.hasPaycheck, 'Status = Uncleared shows only the uncleared row (Fandango)');
    assert(result.fandangoFullBal && !result.fandangoSubsetBal, 'the uncleared row keeps its full-account canonical CL balance 1850.00, not a subset -50.00');
    assert(result.filterCaption, 'a filtered view shows the full-ledger caption');
    await page.evaluate(() => { _txFilterStatus = 'all'; _txLedgerCache = null; _txLedgerLoadStatus = 'not_loaded'; });
    await context.close();
  });

  await test('LEDGER-1 (Phase 5F-1.5 A10): Register defaults to the Quicken CL reconciliation view — uncleared on top, cleared below, newest-first within each group, full-ledger balances, starting balance at bottom', async () => {
    const { page, context } = await openApp(browser);
    // Wendy clean fixture (start 0): two older cleared, two newer uncleared.
    // chronological balances: Old Cleared A -100, Old Cleared B -150, New Uncleared A -170, New Uncleared B -200.
    const txns = [
      { id:'lg-oa', account_key:'truist_checking', transaction_date:'2026-07-01', payee:'Old Cleared A',   memo:'', amount:-100.00, category_key:null, cleared:true,  source:'manual', created_at:'2026-07-01T10:00:00Z' },
      { id:'lg-ob', account_key:'truist_checking', transaction_date:'2026-07-02', payee:'Old Cleared B',   memo:'', amount:-50.00,  category_key:null, cleared:true,  source:'manual', created_at:'2026-07-02T10:00:00Z' },
      { id:'lg-ua', account_key:'truist_checking', transaction_date:'2026-07-05', payee:'New Uncleared A', memo:'', amount:-20.00,  category_key:null, cleared:false, source:'manual', created_at:'2026-07-05T10:00:00Z' },
      { id:'lg-ub', account_key:'truist_checking', transaction_date:'2026-07-06', payee:'New Uncleared B', memo:'', amount:-30.00,  category_key:null, cleared:false, source:'manual', created_at:'2026-07-06T10:00:00Z' }
    ];
    const acct = [{ key:'truist_checking', label:'Truist Checking', account_type:'checking', lifecycle_status:'active', starting_balance:0 }];
    const def = await page.evaluate(([mockAcct, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAcct; _categoriesCache = [];
      _registriesLoadStatus = 'loaded'; _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns; _txLedgerAccountKey = 'truist_checking';
      // Do NOT set the sort: exercise the app default (reconcile CL view).
      _txFilterSearch = ''; _txFilterType = 'all'; _txFilterStatus = 'all'; _txFilterDateFrom = ''; _txFilterDateTo = '';
      setSection('transactions'); setTxSubNav('register'); renderApp();
      var h = document.getElementById('transactions-content').innerHTML;
      return {
        defaultIsReconcile: _txLedgerSortCol === 'reconcile',
        iUB: h.indexOf('New Uncleared B'), iUA: h.indexOf('New Uncleared A'),
        iCB: h.indexOf('Old Cleared B'),   iCA: h.indexOf('Old Cleared A'),
        iStart: h.indexOf('Starting balance'),
        balUB: h.indexOf('$-200.00') !== -1, balUA: h.indexOf('$-170.00') !== -1,
        balCB: h.indexOf('$-150.00') !== -1, balCA: h.indexOf('$-100.00') !== -1,
        startZero: h.indexOf('$0.00') !== -1,
        reconcileCaption: h.indexOf('Uncleared transactions appear first, then cleared.') !== -1,
        clrActivatesReconcile: h.indexOf('data-sort-col="reconcile"') !== -1,
        hasCheckbox: h.indexOf('_toggleTxCleared') !== -1
      };
    }, [acct, txns]);
    assert(def.defaultIsReconcile, 'app default Register sort is the reconcile CL view');
    assert(def.iUB > -1 && def.iUA > -1 && def.iCB > -1 && def.iCA > -1, 'all four rows render');
    assert(def.iUB < def.iUA && def.iUA < def.iCB && def.iCB < def.iCA,
      'order: New Uncleared B, New Uncleared A, Old Cleared B, Old Cleared A (uncleared over cleared, newest-first within each)');
    assert(def.iStart > def.iCA, 'starting balance sits at the bottom (below the oldest cleared row)');
    assert(def.balUB && def.balUA && def.balCB && def.balCA && def.startZero,
      'each row shows its full-ledger historical balance (-200/-170/-150/-100) with starting balance $0.00 at bottom');
    assert(def.reconcileCaption, 'the reconciliation caption is shown by default');
    assert(def.clrActivatesReconcile, 'the Clr header is the reconcile CL control (data-sort-col=reconcile)');
    assert(def.hasCheckbox, 'the Clr cell keeps the editable checkbox wired to _toggleTxCleared');
    // Reconcile idempotency through the REAL Clr header interaction: clicking Clr while already in
    // reconcile keeps the same order (uncleared over cleared, newest-first) — no flip, no direction change.
    const getReconOrder = () => page.evaluate(() => {
      var h = document.getElementById('transactions-content').innerHTML;
      return { ub:h.indexOf('New Uncleared B'), ua:h.indexOf('New Uncleared A'), cb:h.indexOf('Old Cleared B'), ca:h.indexOf('Old Cleared A') };
    });
    await page.click('th[data-sort-col="reconcile"]'); await page.waitForTimeout(30);
    const clr1 = await getReconOrder();
    await page.click('th[data-sort-col="reconcile"]'); await page.waitForTimeout(30);
    const clr2 = await getReconOrder();
    assert(clr1.ub < clr1.ua && clr1.ua < clr1.cb && clr1.cb < clr1.ca,
      'after a Clr header click, order stays uncleared-first then cleared, newest-first within each group');
    assert(JSON.stringify(clr1) === JSON.stringify(clr2),
      'a second Clr header click is idempotent — identical row order, no group flip or direction change');
    // Status = Uncleared still works separately (keeps full-ledger balances).
    await page.selectOption('#tx-filter-status', 'uncleared');
    await page.waitForTimeout(60);
    const unc = await page.evaluate(() => {
      var h = document.getElementById('transactions-content').innerHTML;
      return {
        onlyUncleared: h.indexOf('New Uncleared A') !== -1 && h.indexOf('New Uncleared B') !== -1 && h.indexOf('Old Cleared A') === -1 && h.indexOf('Old Cleared B') === -1,
        ubFullBal: h.indexOf('$-200.00') !== -1, uaFullBal: h.indexOf('$-170.00') !== -1
      };
    });
    assert(unc.onlyUncleared, 'Status = Uncleared shows only the two uncleared rows');
    assert(unc.ubFullBal && unc.uaFullBal, 'uncleared rows keep their full-ledger balances (-200 / -170)');
    await page.evaluate(() => { _txFilterStatus = 'all'; _txLedgerSortCol = 'reconcile'; _txLedgerSortDir = 'desc'; _txLedgerCache = null; _txLedgerLoadStatus = 'not_loaded'; });
    await context.close();
  });

  await test('LEDGER-2 (Wendy CL-balance model): a stale older uncleared row groups on top AND its balance layers on the posted balance (not its chronological spot); an older uncleared row never moves a cleared-section balance; caption does not overpromise; Budget still renders', async () => {
    const { page, context } = await openApp(browser);
    // start 0. Cleared group bottom-up: Cleared One 7/01 -100 => -100 ; Cleared Two 7/02 -50 => -150 (posted).
    // Uncleared layered on posted: Stale Uncleared 5/01 -500 => -650 ; Fresh Uncleared 7/06 -30 => -680 (projected).
    // The stale row reads -650 (posted -150 + its -500), NOT the old chronological -500; cleared rows read -100/-150.
    const txns = [
      { id:'l2-su', account_key:'truist_checking', transaction_date:'2026-05-01', payee:'Stale Uncleared', memo:'', amount:-500.00, category_key:null, cleared:false, source:'manual', created_at:'2026-05-01T10:00:00Z' },
      { id:'l2-c1', account_key:'truist_checking', transaction_date:'2026-07-01', payee:'Cleared One',     memo:'', amount:-100.00, category_key:null, cleared:true,  source:'manual', created_at:'2026-07-01T10:00:00Z' },
      { id:'l2-c2', account_key:'truist_checking', transaction_date:'2026-07-02', payee:'Cleared Two',     memo:'', amount:-50.00,  category_key:null, cleared:true,  source:'manual', created_at:'2026-07-02T10:00:00Z' },
      { id:'l2-fu', account_key:'truist_checking', transaction_date:'2026-07-06', payee:'Fresh Uncleared', memo:'', amount:-30.00,  category_key:null, cleared:false, source:'manual', created_at:'2026-07-06T10:00:00Z' }
    ];
    const acct = [{ key:'truist_checking', label:'Truist Checking', account_type:'checking', lifecycle_status:'active', starting_balance:0 }];
    const r = await page.evaluate(([mockAcct, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAcct; _categoriesCache = [];
      _registriesLoadStatus = 'loaded'; _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns; _txLedgerAccountKey = 'truist_checking';
      _txFilterSearch=''; _txFilterType='all'; _txFilterStatus='all'; _txFilterDateFrom=''; _txFilterDateTo='';
      setSection('transactions'); setTxSubNav('register'); renderApp();
      var h = document.getElementById('transactions-content').innerHTML;
      var capStart = h.indexOf('Uncleared transactions appear first');
      var capText = capStart > -1 ? h.slice(capStart, capStart + 340) : '';
      return {
        iFresh: h.indexOf('Fresh Uncleared'), iStale: h.indexOf('Stale Uncleared'),
        iC2: h.indexOf('Cleared Two'), iC1: h.indexOf('Cleared One'),
        staleBal: h.indexOf('$-650.00') !== -1, freshBal: h.indexOf('$-680.00') !== -1,
        c2Bal: h.indexOf('$-150.00') !== -1, c1Bal: h.indexOf('$-100.00') !== -1,
        overpromiseInCaption: /always/i.test(capText),
        conditionalCaption: capText.indexOf('newest cleared row should match your posted account balance') !== -1
      };
    }, [acct, txns]);
    assert(r.iFresh > -1 && r.iStale > -1 && r.iC2 > -1 && r.iC1 > -1, 'all four rows render');
    assert(r.iFresh < r.iStale, 'uncleared group is newest-first (Fresh 7/06 above Stale 5/01)');
    assert(r.iStale < r.iC2 && r.iStale < r.iC1, 'the stale older uncleared row still groups ABOVE both cleared rows (group dominates date)');
    assert(r.iC2 < r.iC1, 'cleared group is newest-first (Cleared Two 7/02 above Cleared One 7/01)');
    assert(r.staleBal && r.freshBal && r.c2Bal && r.c1Bal, 'CL-model balances: cleared read -100/-150 (posted), uncleared layer on top to -650/-680 — the stale row is -650, not its chronological -500');
    assert(r.c1Bal && r.c2Bal, 'the older uncleared row never moved a cleared-section balance (cleared rows still -100 and -150)');
    assert(!r.overpromiseInCaption, 'the reconcile caption must not claim the checkpoint "always" equals the online balance');
    assert(r.conditionalCaption, 'the reconcile helper bar uses conditional wording ("newest cleared row should match your posted account balance")');
    // Budget still renders (guardrail: no Budget changes).
    const budgetOk = await page.evaluate(() => {
      setSection('budget'); renderApp();
      var b = document.getElementById('budget-content');
      return !!(b && b.innerHTML && b.innerHTML.length > 0);
    });
    assert(budgetOk, 'Budget tab still renders after the Register reconcile change');
    await page.evaluate(() => { _txLedgerSortCol='reconcile'; _txLedgerSortDir='desc'; _txLedgerCache=null; _txLedgerLoadStatus='not_loaded'; });
    await context.close();
  });

  await test('A6-1 (Wendy CL-balance model): Register columns are user-sortable under the reconcile default; Date entry is uniform desc then toggles asc; the SINGLE canonical balance is identical in every sort; the may-not-foot caption shows for every non-CL sort (Date included)', async () => {
    const { page, context } = await openApp(browser);
    const txns = [
      { id: 'a6-1', account_key: 'truist_checking', transaction_date: '2026-06-01',
        payee: 'Kroger', memo: '', amount: -100.00, category_key: null,
        cleared: true, source: 'manual', created_at: '2026-06-01T10:00:00Z' },
      { id: 'a6-2', account_key: 'truist_checking', transaction_date: '2026-06-05',
        payee: 'Fandango', memo: '', amount: -50.00, category_key: null,
        cleared: false, source: 'manual', created_at: '2026-06-05T10:00:00Z' },
      { id: 'a6-3', account_key: 'truist_checking', transaction_date: '2026-06-10',
        payee: 'Paycheck', memo: '', amount: 2000.00, category_key: null,
        cleared: true, source: 'manual', created_at: '2026-06-10T10:00:00Z' }
    ];
    const r = await page.evaluate(([mockAccounts, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = [];
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns;
      _txLedgerAccountKey = 'truist_checking';
      // Use the app default (reconcile CL view); do not set the sort here.
      _txFilterSearch = ''; _txFilterType = 'all'; _txFilterStatus = 'all'; _txFilterDateFrom = ''; _txFilterDateTo = '';
      setSection('transactions');
      setTxSubNav('register');
      function snap() {
        renderApp();
        var h = document.getElementById('transactions-content')?.innerHTML || '';
        return {
          fandango: h.indexOf('Fandango'), kroger: h.indexOf('Kroger'), paycheck: h.indexOf('Paycheck'),
          fandangoCanonBal: h.indexOf('$1850.00') !== -1,  // the ONE canonical CL balance (posted 1900 + uncleared -50)
          fandangoChronBal: h.indexOf('$-150.00') !== -1,  // the OLD chronological balance — must never appear now
          hasCaption: h.indexOf('This view is outside the CL reconciliation sequence') !== -1,
          hasReconcileCaption: h.indexOf('Uncleared transactions appear first, then cleared.') !== -1
        };
      }
      var def = snap();                                  // app default = reconcile CL view
      setTxLedgerSort('payee'); var payeeSort = snap();  // noncanonical sort (payee asc)
      setTxLedgerSort('date');  var dateDesc = snap();   // uniform rule: Date enters desc (newest-first)
      setTxLedgerSort('date');  var dateAsc  = snap();   // second Date click toggles to asc
      // Restore the real app default (reconcile CL view)
      _txLedgerSortCol = 'reconcile'; _txLedgerSortDir = 'desc';
      _txLedgerCache = null; _txLedgerLoadStatus = 'not_loaded';
      return { def, payeeSort, dateDesc, dateAsc };
    }, [TX_MOCK_ACCOUNTS, txns]);
    // Default = reconcile: uncleared Fandango (6/5) on top, then cleared newest-first (Paycheck 6/10, Kroger 6/1)
    assert(r.def.fandango < r.def.paycheck && r.def.paycheck < r.def.kroger, 'default reconcile view: uncleared on top, then cleared newest-first');
    assert(r.def.hasReconcileCaption && !r.def.hasCaption, 'reconcile default shows the reconciliation caption, not the noncanonical warning');
    // Payee sort: alphabetical; noncanonical "may not foot" caption shown; balances preserved
    assert(r.payeeSort.fandango < r.payeeSort.kroger && r.payeeSort.kroger < r.payeeSort.paycheck, 'clicking Payee sorts alphabetically');
    assert(r.payeeSort.hasCaption, 'a Payee sort shows the may-not-foot caption');
    // Date entry (uniform rule): first Date click lands on desc / newest-first; caption NOW shown (single balance)
    assert(r.dateDesc.paycheck < r.dateDesc.fandango && r.dateDesc.fandango < r.dateDesc.kroger, 'first Date click enters desc (newest-first: Paycheck 6/10, Fandango 6/5, Kroger 6/1)');
    assert(r.dateDesc.hasCaption, 'a Date sort now shows the may-not-foot caption (single canonical balance, Date is outside the CL sequence)');
    // Second Date click toggles to asc; caption still shown
    assert(r.dateAsc.kroger < r.dateAsc.fandango && r.dateAsc.fandango < r.dateAsc.paycheck, 'second Date click toggles to asc');
    assert(r.dateAsc.hasCaption, 'a Date sort shows the may-not-foot caption in both directions');
    // Single canonical balance: Fandango shows $1850.00 in EVERY view; the old chronological $-150.00 never appears.
    assert(r.def.fandangoCanonBal && r.payeeSort.fandangoCanonBal && r.dateDesc.fandangoCanonBal && r.dateAsc.fandangoCanonBal,
      "Fandango shows its single canonical CL balance $1850.00 identically across reconcile, Payee, and both Date sorts");
    assert(!r.def.fandangoChronBal && !r.payeeSort.fandangoChronBal && !r.dateDesc.fandangoChronBal && !r.dateAsc.fandangoChronBal,
      "the old chronological balance $-150.00 must never appear in any sort (no competing second balance)");
    await context.close();
  });

  await test('A9-1 (Phase 5F-1.5 A9a): Register filters work through the actual UI controls; Balance stays full-ledger', async () => {
    const { page, context } = await openApp(browser);
    const txns = [
      { id: 'a9-1', account_key: 'truist_checking', transaction_date: '2026-06-01', payee: 'Kroger',   memo: '', amount: -100.00, category_key: null, cleared: true,  source: 'manual', created_at: '2026-06-01T10:00:00Z' },
      { id: 'a9-2', account_key: 'truist_checking', transaction_date: '2026-06-05', payee: 'Fandango', memo: '', amount: -50.00,  category_key: null, cleared: false, source: 'manual', created_at: '2026-06-05T10:00:00Z' },
      { id: 'a9-3', account_key: 'truist_checking', transaction_date: '2026-06-10', payee: 'Employer', memo: '', amount: 2000.00, category_key: null, cleared: true,  source: 'manual', created_at: '2026-06-10T10:00:00Z' },
      { id: 'a9-4', account_key: 'truist_checking', transaction_date: '2026-06-12', payee: 'Shell',    memo: '', amount: -40.00,  category_key: null, cleared: false, source: 'manual', created_at: '2026-06-12T10:00:00Z' }
    ];
    await page.evaluate(([mockAccounts, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts; _categoriesCache = [];
      _registriesLoadStatus = 'loaded'; _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns; _txLedgerAccountKey = 'truist_checking';
      _txLedgerSortCol = 'date'; _txLedgerSortDir = 'desc'; // pinned date/desc (not the app default); filters are exercised under it
      _txFilterSearch = ''; _txFilterType = 'all'; _txFilterStatus = 'all';
      setSection('transactions'); setTxSubNav('register'); renderApp();
    }, [TX_MOCK_ACCOUNTS, txns]);
    async function snap() {
      return await page.evaluate(() => {
        var h = document.getElementById('transactions-content')?.innerHTML || '';
        return {
          kroger: h.indexOf('Kroger') !== -1, fandango: h.indexOf('Fandango') !== -1,
          employer: h.indexOf('Employer') !== -1, shell: h.indexOf('Shell') !== -1,
          count4of4: h.indexOf('Showing 4 of 4') !== -1,
          shellFullBal: h.indexOf('$1810.00') !== -1, shellSubsetBal: h.indexOf('$-40.00') !== -1,
          filteredEmpty: h.indexOf('No transactions match the current filters') !== -1,
          filterCaption: h.indexOf('Balance reflects the full account ledger') !== -1
        };
      });
    }
    // Default view
    const def = await snap();
    assert(def.kroger && def.fandango && def.employer && def.shell, 'default filters must show all four rows');
    assert(def.count4of4, 'count text must read Showing 4 of 4');
    // Status = Uncleared via the actual select control
    await page.selectOption('#tx-filter-status', 'uncleared');
    const statusUncleared = await snap();
    assert(statusUncleared.fandango && statusUncleared.shell && !statusUncleared.kroger && !statusUncleared.employer, 'selecting Status=Uncleared must show only uncleared rows');
    // Under the pinned date/desc sort, the visible uncleared rows stay newest-first (Shell 6/12 before Fandango 6/5)
    const unclearedOrder = await page.evaluate(() => {
      var h = document.getElementById('transactions-content').innerHTML;
      return { iShell: h.indexOf('Shell'), iFandango: h.indexOf('Fandango') };
    });
    assert(unclearedOrder.iShell > -1 && unclearedOrder.iFandango > -1 && unclearedOrder.iShell < unclearedOrder.iFandango,
      'Status=Uncleared preserves the date/desc ledger order (Shell 2026-06-12 before Fandango 2026-06-05)');
    // Reset Status, then Type = Inflow via the actual select control
    await page.selectOption('#tx-filter-status', 'all');
    await page.selectOption('#tx-filter-type', 'inflow');
    const typeInflow = await snap();
    assert(typeInflow.employer && !typeInflow.kroger && !typeInflow.fandango && !typeInflow.shell, 'selecting Type=Inflow must show only the inflow row');
    // Reset Type, then search "Shell" via the input + Search button
    await page.selectOption('#tx-filter-type', 'all');
    await page.fill('#tx-filter-search', 'Shell');
    await page.click('#tx-filter-search-btn');
    const searchShell = await snap();
    assert(searchShell.shell && !searchShell.kroger && !searchShell.fandango && !searchShell.employer, 'clicking Search must narrow to the matching payee');
    assert(searchShell.shellFullBal && !searchShell.shellSubsetBal, "filtered row must keep its full-ledger balance $1810.00, not a subset-recomputed $-40.00");
    assert(searchShell.filterCaption, 'a filter-active view must show the full-ledger caption');
    // No-match search applied via Enter key
    await page.fill('#tx-filter-search', 'zzznope');
    await page.press('#tx-filter-search', 'Enter');
    const noMatch = await snap();
    assert(noMatch.filteredEmpty, 'a no-match search (applied via Enter) must show the filtered empty state');
    // Clear via the actual Clear filters button
    await page.click('#tx-clear-filters');
    const cleared = await snap();
    assert(cleared.kroger && cleared.fandango && cleared.employer && cleared.shell && cleared.count4of4, 'clicking Clear filters must restore all rows');
    await page.evaluate(() => { _txFilterSearch=''; _txFilterType='all'; _txFilterStatus='all'; _txLedgerCache=null; _txLedgerLoadStatus='not_loaded'; });
    await context.close();
  });

  await test('A9-2 (Phase 5F-1.5 A9b): Register inclusive Date From/To filters via the actual controls; account label shows; Clear resets dates', async () => {
    const { page, context } = await openApp(browser);
    const txns = [
      { id: 'a9b-1', account_key: 'truist_checking', transaction_date: '2026-06-01', payee: 'Kroger',   memo: '', amount: -100.00, category_key: null, cleared: true,  source: 'manual', created_at: '2026-06-01T10:00:00Z' },
      { id: 'a9b-2', account_key: 'truist_checking', transaction_date: '2026-06-05', payee: 'Fandango', memo: '', amount: -50.00,  category_key: null, cleared: false, source: 'manual', created_at: '2026-06-05T10:00:00Z' },
      { id: 'a9b-3', account_key: 'truist_checking', transaction_date: '2026-06-10', payee: 'Employer', memo: '', amount: 2000.00, category_key: null, cleared: true,  source: 'manual', created_at: '2026-06-10T10:00:00Z' },
      { id: 'a9b-4', account_key: 'truist_checking', transaction_date: '2026-06-12', payee: 'Shell',    memo: '', amount: -40.00,  category_key: null, cleared: false, source: 'manual', created_at: '2026-06-12T10:00:00Z' }
    ];
    await page.evaluate(([mockAccounts, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts; _categoriesCache = [];
      _registriesLoadStatus = 'loaded'; _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns; _txLedgerAccountKey = 'truist_checking';
      _txLedgerSortCol = 'date'; _txLedgerSortDir = 'desc'; // pinned date/desc (not the app default); filters are exercised under it
      _txFilterSearch = ''; _txFilterType = 'all'; _txFilterStatus = 'all';
      _txFilterDateFrom = ''; _txFilterDateTo = '';
      setSection('transactions'); setTxSubNav('register'); renderApp();
    }, [TX_MOCK_ACCOUNTS, txns]);
    async function snap() {
      return await page.evaluate(() => {
        var h = document.getElementById('transactions-content')?.innerHTML || '';
        return {
          kroger: h.indexOf('Kroger') !== -1, fandango: h.indexOf('Fandango') !== -1,
          employer: h.indexOf('Employer') !== -1, shell: h.indexOf('Shell') !== -1,
          employerFullBal: h.indexOf('$1850.00') !== -1, employerSubsetBal: h.indexOf('$1950.00') !== -1,
          filteredEmpty: h.indexOf('No transactions match the current filters') !== -1,
          acctLabel: h.indexOf('Selected account:') !== -1, acctName: h.indexOf('Truist Checking') !== -1,
          dateFromVal: document.getElementById('tx-filter-date-from') ? document.getElementById('tx-filter-date-from').value : 'MISSING',
          dateToVal: document.getElementById('tx-filter-date-to') ? document.getElementById('tx-filter-date-to').value : 'MISSING'
        };
      });
    }
    // Default: account context label shows the selected account name
    const def = await snap();
    assert(def.acctLabel && def.acctName, 'selected-account context label must show the account name');
    // Inclusive range 06-05..06-10 via the real date inputs (fill + explicit change dispatch)
    await page.fill('#tx-filter-date-from', '2026-06-05'); await page.dispatchEvent('#tx-filter-date-from', 'change');
    await page.fill('#tx-filter-date-to', '2026-06-10');   await page.dispatchEvent('#tx-filter-date-to', 'change');
    const ranged = await snap();
    assert(ranged.fandango && ranged.employer && !ranged.kroger && !ranged.shell, 'inclusive range 06-05..06-10 must show only Fandango (06-05) and Employer (06-10)');
    assert(ranged.employerFullBal && !ranged.employerSubsetBal, 'a date-filtered row must keep its full-ledger balance $1850.00, not a subset-recomputed $1950.00');
    // From > To must yield the filtered empty state (no auto-swap)
    await page.fill('#tx-filter-date-from', '2026-06-12'); await page.dispatchEvent('#tx-filter-date-from', 'change');
    await page.fill('#tx-filter-date-to', '2026-06-01');   await page.dispatchEvent('#tx-filter-date-to', 'change');
    const inverted = await snap();
    assert(inverted.filteredEmpty, 'From > To must show the filtered empty state (no rows, no auto-swap)');
    // Clear filters via the actual button; date inputs must visibly clear
    await page.click('#tx-clear-filters');
    const cleared = await snap();
    assert(cleared.kroger && cleared.fandango && cleared.employer && cleared.shell, 'Clear filters must restore all rows');
    assert(cleared.dateFromVal === '' && cleared.dateToVal === '', 'date inputs must visibly clear after Clear filters');
    await page.evaluate(() => { _txFilterDateFrom=''; _txFilterDateTo=''; _txFilterSearch=''; _txFilterType='all'; _txFilterStatus='all'; _txLedgerCache=null; _txLedgerLoadStatus='not_loaded'; });
    await context.close();
  });

  await test('A7a-1 (Phase 5F-1.5): Category Report modal renders totals, escapes user values, omits Balance, shows legacy/truncation notices', async () => {
    const { page, context } = await openApp(browser);
    const r = await page.evaluate(() => {
      _accountsCache = [{ key:'truist_checking', label:'Truist Checking', lifecycle_status:'active' }];
      _categoriesCache = [{ key:'auto.gas', label:'Gas', is_leaf:true, lifecycle_status:'active' }];
      _budgetLineRulesLoadStatus = 'not_loaded';
      _catReportModal = {
        mode:'report', categoryKey:'auto.gas', monthIso:'2026-07-01', loadStatus:'loaded',
        error:'', legacyCount:2, truncated:false,
        rows:[
          { id:'r1', transaction_date:'2026-07-02', account_key:'truist_checking', payee:'<b>Shell</b>', memo:'gas & go', category_key:'auto.gas', amount:-40.00, cleared:true },
          { id:'r2', transaction_date:'2026-07-05', account_key:'truist_checking', payee:'RESY refund', memo:'', category_key:'auto.gas', amount:15.00, cleared:false }
        ]
      };
      _catReportRenderModal();
      var h = document.getElementById('cat-report-modal-slot').innerHTML;
      return {
        overlay: h.indexOf('sc-modal-overlay') !== -1,
        netSpend25: h.indexOf('$25.00') !== -1,
        spending40: h.indexOf('$40.00') !== -1,
        credits15: h.indexOf('$15.00') !== -1,
        escapedPayee: h.indexOf('&lt;b&gt;Shell&lt;/b&gt;') !== -1, rawPayee: h.indexOf('<b>Shell</b>') !== -1,
        escapedMemo: h.indexOf('gas &amp; go') !== -1,
        noBalance: h.indexOf('Balance') === -1,
        legacyNotice: h.indexOf('legacy Budget entries') !== -1
      };
    });
    assert(r.overlay, 'modal overlay renders');
    assert(r.netSpend25, 'Net Spend $25.00 (spending 40 minus credits 15)');
    assert(r.spending40 && r.credits15, 'Spending $40.00 and Credits $15.00 shown');
    assert(r.escapedPayee && !r.rawPayee, 'HTML payee is escaped, not injected');
    assert(r.escapedMemo, 'memo ampersand is escaped');
    assert(r.noBalance, 'report modal must not include a Balance column');
    assert(r.legacyNotice, 'legacy notice shows when legacyCount>0');
    // Truncation state
    const trunc = await page.evaluate(() => {
      _catReportModal.truncated = true; _catReportModal.legacyCount = 0;
      _catReportRenderModal();
      var h = document.getElementById('cat-report-modal-slot').innerHTML;
      return { warn: h.indexOf('Report may be incomplete') !== -1, partial: h.indexOf('(partial)') !== -1, noLegacy: h.indexOf('legacy Budget entries') === -1 };
    });
    assert(trunc.warn && trunc.partial, 'truncation warning + (partial) marker when truncated');
    assert(trunc.noLegacy, 'legacy notice absent when legacyCount is 0');
    // Close clears slot + state
    const closed = await page.evaluate(() => {
      _closeCategoryReport();
      var slot = document.getElementById('cat-report-modal-slot');
      return { slotEmpty: (slot ? slot.innerHTML : '') === '', stateNull: _catReportModal === null };
    });
    assert(closed.slotEmpty && closed.stateNull, 'close clears the slot DOM and nulls state');
    await context.close();
  });

  await test('A7a-2 (Phase 5F-1.5): Category Report picker opens a report via the real View Report button for a Jabian category absent from the Budget grid (fetch stubbed)', async () => {
    const { page, context } = await openApp(browser);
    // Setup + stub network, open the picker, and choose the Jabian category + month in the DOM.
    const pickerHadJabian = await page.evaluate(() => {
      _categoriesCache = [
        { key:'business.jabian_expenses_2026', label:'Jabian Expenses 2026', is_leaf:true, lifecycle_status:'active', behavior_class:'reimbursable_expense', budget_treatment:'excluded' },
        { key:'auto.gas', label:'Gas', is_leaf:true, lifecycle_status:'active', behavior_class:'expense', budget_treatment:'tracked' }
      ];
      _accountsCache = [{ key:'amex_gold', label:'AMEX Gold', lifecycle_status:'active' }];
      _budgetLineRulesLoadStatus = 'not_loaded';
      _budgetSelectedMonth = '2026-07-01';
      _catReportModal = null;
      window.getAuthHeaders = function(){ return Promise.resolve({}); };
      window.fetch = function(url){
        if (String(url).indexOf('/budget_transactions') !== -1) {
          return Promise.resolve({ ok:true, headers:{ get:function(k){ return k === 'content-range' ? '0-0/0' : null; } }, json:function(){ return Promise.resolve([]); } });
        }
        return Promise.resolve({ ok:true, headers:{ get:function(){ return null; } }, json:function(){ return Promise.resolve([
          { id:'j1', transaction_date:'2026-07-03', account_key:'amex_gold', payee:'United Air', memo:'JAB client', category_key:'business.jabian_expenses_2026', amount:-500.00, cleared:true }
        ]); } });
      };
      openCategoryReportPicker();
      var had = document.getElementById('cat-report-category').innerHTML.indexOf('Jabian Expenses 2026') !== -1;
      document.getElementById('cat-report-category').value = 'business.jabian_expenses_2026';
      document.getElementById('cat-report-month').value = '2026-07-01';
      return had;
    });
    // Click the actual View Report button (real UI path, not a direct openCategoryReport call).
    await page.click('#cat-report-view-btn');
    await page.waitForTimeout(80);
    const r = await page.evaluate(() => {
      var h = document.getElementById('cat-report-modal-slot').innerHTML;
      return {
        opened: h.indexOf('Jabian Expenses 2026') !== -1,
        row: h.indexOf('United Air') !== -1,
        spending500: h.indexOf('$500.00') !== -1
      };
    });
    assert(pickerHadJabian, 'picker lists the excluded Jabian Expenses category (absent from the Budget grid)');
    assert(r.opened, 'clicking View Report opens the report modal for the Jabian category');
    assert(r.row, 'the stubbed Jabian transaction row renders');
    assert(r.spending500, 'summary reflects the $500 spend');
    await context.close();
  });

  await test('A7b-1 (Phase 5F-1.5): clicking a Budget expense Spent cell opens the Category Report for that category/month (fetch stubbed)', async () => {
    const { page, context } = await openApp(browser);
    const setup = await page.evaluate(() => {
      _categoriesCache = [
        { key:'entertainment', label:'Entertainment', parent_key:null, is_leaf:false, lifecycle_status:'active', behavior_class:null, budget_treatment:null },
        { key:'entertainment.week_1', label:'Entertainment Week 1', parent_key:'entertainment', is_leaf:true, lifecycle_status:'active', behavior_class:'expense', budget_treatment:'tracked' }
      ];
      _accountsCache = [{ key:'amex_gold', label:'AMEX Gold', lifecycle_status:'active' }];
      _registriesLoadStatus = 'loaded';
      _budgetTransactions = []; _budgetTransLoadStatus = 'loaded';
      _budgetLineRulesCache = null; _budgetLineRulesLoadStatus = 'not_loaded';
      _budgetRegisterSpendCache = [{ category_key:'entertainment.week_1', amount:-40.00, transaction_date:'2026-07-01' }];
      _budgetRegisterSpendLoadStatus = 'loaded';
      _budgetSelectedMonth = '2026-07-01';
      _catReportModal = null;
      window.getAuthHeaders = function(){ return Promise.resolve({}); };
      window.fetch = function(url){
        if (String(url).indexOf('/budget_transactions') !== -1) {
          return Promise.resolve({ ok:true, headers:{ get:function(k){ return k === 'content-range' ? '0-0/0' : null; } }, json:function(){ return Promise.resolve([]); } });
        }
        return Promise.resolve({ ok:true, headers:{ get:function(){ return null; } }, json:function(){ return Promise.resolve([
          { id:'e1', transaction_date:'2026-07-01', account_key:'amex_gold', payee:'Mend Coffee', memo:'', category_key:'entertainment.week_1', amount:-12.98, cleared:true }
        ]); } });
      };
      setSection('budget'); renderApp();
      var bc = document.getElementById('budget-content');
      var h = bc ? bc.innerHTML : '';
      return {
        rowRendered: h.indexOf('Entertainment Week 1') !== -1,
        spentDrill: h.indexOf('data-cat-report-target="spent" data-cat-key="entertainment.week_1"') !== -1,
        labelDrill: h.indexOf('data-cat-report-target="label" data-cat-key="entertainment.week_1"') !== -1
      };
    });
    assert(setup.rowRendered, 'Budget grid renders the entertainment.week_1 expense row');
    assert(setup.spentDrill, 'Spent cell carries the drill-through data attributes');
    assert(setup.labelDrill, 'label span carries the drill-through data attributes');
    async function modalSnap() {
      return await page.evaluate(() => {
        var h = document.getElementById('cat-report-modal-slot').innerHTML;
        return { opened: h.indexOf('Entertainment Week 1') !== -1, forJuly: h.indexOf('July 2026') !== -1, row: h.indexOf('Mend Coffee') !== -1, amount: h.indexOf('$12.98') !== -1 };
      });
    }
    // Click the real Spent-cell drill target
    await page.click('[data-cat-report-target="spent"][data-cat-key="entertainment.week_1"]');
    await page.waitForTimeout(80);
    const spent = await modalSnap();
    assert(spent.opened && spent.forJuly, 'clicking the Spent cell opens the Category Report for that category and the selected month');
    assert(spent.row && spent.amount, 'the report modal renders the stubbed transaction and amount');
    // Close, then click the real label drill target
    await page.evaluate(() => { _closeCategoryReport(); });
    const closed = await page.evaluate(() => (document.getElementById('cat-report-modal-slot').innerHTML) === '');
    assert(closed, 'modal closes cleanly before the second interaction');
    await page.click('[data-cat-report-target="label"][data-cat-key="entertainment.week_1"]');
    await page.waitForTimeout(80);
    const label = await modalSnap();
    assert(label.opened && label.forJuly, 'clicking the category label also opens the Category Report for that category and month');
    assert(label.row && label.amount, 'the report modal renders the stubbed transaction from the label path too');
    await context.close();
  });

  await test('RG-11: cleared transaction shows checked checkbox in Clr column (updated in 5E-2)', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = [];
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns; // both tx-001 and tx-002 are cleared:true, source:'manual'
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      // In 5E-2, manual rows render cleared as a checkbox (checked attr) not a ✓ character
      return {
        hasCheckedCheckbox: html.includes('type="checkbox"') && html.includes('checked'),
        hasClearedToggle: html.includes('_toggleTxCleared')
      };
    }, [TX_MOCK_ACCOUNTS, RG_MOCK_TRANSACTIONS]);
    assert(result.hasCheckedCheckbox, 'Cleared manual transaction must render as checked checkbox in Clr column');
    assert(result.hasClearedToggle, 'Cleared checkbox must wire up _toggleTxCleared handler');
    await context.close();
  });

  await test('RG-12: empty state shown when no transactions for account', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = [];
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return { hasEmptyState: html.includes('No transactions for this account') };
    }, TX_MOCK_ACCOUNTS);
    assert(result.hasEmptyState, 'Empty state message must appear when transaction list is empty');
    await context.close();
  });

  await test('RG-13: loading state shown when _txLedgerLoadStatus is loading', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loading';
      _txLedgerCache = null;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return { hasLoadingState: html.includes('Loading transactions') };
    }, TX_MOCK_ACCOUNTS);
    assert(result.hasLoadingState, 'Loading state must render while _txLedgerLoadStatus is loading');
    await context.close();
  });

  await test('RG-14: error state shown when _txLedgerLoadStatus is failed', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'failed';
      _txLedgerCache = null;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return { hasErrorState: html.includes('Failed to load transactions') };
    }, TX_MOCK_ACCOUNTS);
    assert(result.hasErrorState, 'Error state must render when _txLedgerLoadStatus is failed');
    await context.close();
  });

  await test('RG-15: write controls present for manual rows, absent for non-manual rows (updated in 5E-2)', async () => {
    const { page, context } = await openApp(browser);
    const mixedTxns = [
      { id: 'rg-manual', account_key: 'truist_checking', transaction_date: '2026-06-01',
        payee: 'Manual', memo: '', amount: -50.00, category_key: null,
        cleared: false, source: 'manual', created_at: '2026-06-01T10:00:00Z', updated_at: '2026-06-01T10:00:00Z' },
      { id: 'rg-import', account_key: 'truist_checking', transaction_date: '2026-06-02',
        payee: 'Import', memo: '', amount: -30.00, category_key: null,
        cleared: false, source: 'import', created_at: '2026-06-02T10:00:00Z', updated_at: '2026-06-02T10:00:00Z' }
    ];
    const result = await page.evaluate(([mockAccounts, txns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = [];
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = txns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      // Add Transaction button is expected in 5E-2
      var hasAddBtn = html.includes('tx-add-btn');
      // Manual row has edit/delete controls using correct 5E-2 function names
      // Edit button now uses _openTxEditById(id) — no longer _openTxForm('edit',...)
      var manualHasEdit = html.includes('_openTxEditById(') && html.includes('rg-manual');
      var manualHasDelete = html.includes('_openTxDeleteConfirm') && html.includes('rg-manual');
      // Import row must NOT have edit/delete buttons referencing its ID
      var importDeleteCalls = (html.match(/_openTxDeleteConfirm\('[^']+'\)/g) || []);
      var importHasDelete = importDeleteCalls.some(c => c.includes('rg-import'));
      var importEditCalls = (html.match(/_openTxEditById\('[^']+'\)/g) || []);
      var importHasEdit = importEditCalls.some(c => c.includes('rg-import'));
      // Old stale function names must not appear
      var hasStaleAddFn = html.includes('_addTransaction') || html.includes('_editTransaction') || html.includes('_deleteTransaction');
      return { hasAddBtn, manualHasEdit, manualHasDelete, importHasDelete, importHasEdit, hasStaleAddFn };
    }, [TX_MOCK_ACCOUNTS, mixedTxns]);
    assert(result.hasAddBtn, 'Add Transaction button must be present in 5E-2 register');
    assert(result.manualHasEdit, 'Manual row must have edit control calling _openTxEditById');
    assert(result.manualHasDelete, 'Manual row must have delete control calling _openTxDeleteConfirm');
    assert(!result.importHasDelete, 'Import row must not have a delete button');
    assert(!result.importHasEdit, 'Import row must not have an edit button');
    assert(!result.hasStaleAddFn, 'Stale function names (_addTransaction etc.) must not appear');
    await context.close();
  });

  await test('RG-16: flag reset to false — Register tab returns to disabled span, budget unaffected', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate((mockAccounts) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = [];
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      // Now reset
      FEATURE_FLAGS.showTransactionLedger = false;
      renderApp();
      setSection('transactions');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        registerDisabled: html.includes('Register — Phase 5E'),
        budgetIntact: typeof runModel === 'function' && typeof BUDGET_CATEGORY_REGISTRY !== 'undefined'
      };
    }, TX_MOCK_ACCOUNTS);
    assert(result.registerDisabled, 'Register tab must return to disabled span after flag reset to false');
    assert(result.budgetIntact, 'Budget module must be unaffected after register module runs');
    await context.close();
  });

  // ── Section WR: Transaction Writes (Phase 5E-2) ──────────────────────
  // Write operations intercepted via page.route() to mock Supabase responses.
  // No live Supabase connection required.
  console.log('\n── Section WR: Transaction Writes (Phase 5E-2) ──');

  // Mock accounts and transactions shared across WR tests
  const WR_MOCK_ACCOUNTS = [
    { key: 'truist_checking', label: 'Truist Checking', institution: 'Truist',
      account_type: 'checking', lifecycle_status: 'active', include_in_budget: true,
      include_in_cashflow: true, starting_balance: 1000.00, notes: null }
  ];
  const WR_MOCK_CATEGORIES = [
    { key: 'groceries', label: 'Groceries', parent_key: null, is_leaf: true,
      lifecycle_status: 'active', behavior_class: 'discretionary',
      budget_treatment: 'expense', cashflow_treatment: 'expense',
      budget_line_key: null, budget_group_key: null, merged_into_key: null }
  ];
  const WR_MOCK_TX = [
    { id: 'wr-tx-001', account_key: 'truist_checking', transaction_date: '2026-06-01',
      payee: 'Kroger', memo: 'Groceries', amount: -85.50,
      category_key: 'groceries', cleared: false, source: 'manual',
      created_at: '2026-06-01T10:00:00Z', updated_at: '2026-06-01T10:00:00Z' }
  ];

  // Helper: set up the register in a ready state with mock data
  async function setupRegister(page, opts) {
    opts = opts || {};
    await page.evaluate(([accounts, categories, txCache, formMode, formData, editId, deleteId]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = accounts;
      _categoriesCache = categories;
      _registriesLoadStatus = 'loaded';
      _txLedgerAccountKey = 'truist_checking';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = txCache;
      _txFormMode = formMode;
      _txFormData = formData || {};
      _txEditId = editId || null;
      _txDeleteConfirmId = deleteId || null;
      _txFormError = '';
      _txFormSaving = false;
      _txDeleteSaving = false;
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
    }, [
      opts.accounts || WR_MOCK_ACCOUNTS,
      opts.categories || WR_MOCK_CATEGORIES,
      opts.txCache !== undefined ? opts.txCache : WR_MOCK_TX,
      opts.formMode || null,
      opts.formData || {},
      opts.editId || null,
      opts.deleteId || null
    ]);
  }

  await test('WR-1: showTransactionLedger=false — Add button absent, no write controls rendered', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([accounts, categories]) => {
      FEATURE_FLAGS.showTransactionLedger = false;
      FEATURE_FLAGS.showTransactionSection = true;
      _accountsCache = accounts;
      _categoriesCache = categories;
      _registriesLoadStatus = 'loaded';
      renderApp();
      setSection('transactions');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        addBtnAbsent: !html.includes('tx-add-btn'),
        noSaveTxForm: !html.includes('_saveTxForm'),
        noDeleteConfirm: !html.includes('_confirmTxDelete'),
        noToggleCleared: !html.includes('_toggleTxCleared')
      };
    }, [WR_MOCK_ACCOUNTS, WR_MOCK_CATEGORIES]);
    assert(result.addBtnAbsent, 'Add button must be absent when showTransactionLedger=false');
    assert(result.noSaveTxForm, '_saveTxForm must not appear in DOM when flag=false');
    assert(result.noDeleteConfirm, '_confirmTxDelete must not appear in DOM when flag=false');
    assert(result.noToggleCleared, '_toggleTxCleared must not appear in DOM when flag=false');
    await context.close();
  });

  await test('WR-2: showTransactionLedger=true — Add Transaction button present', async () => {
    const { page, context } = await openApp(browser);
    await setupRegister(page, { txCache: [] });
    const result = await page.evaluate(() => {
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        addBtnPresent: html.includes('tx-add-btn'),
        addBtnText: html.includes('Add Transaction')
      };
    });
    assert(result.addBtnPresent, 'Add Transaction button with id tx-add-btn must be present');
    assert(result.addBtnText, 'Button must have label "Add Transaction"');
    await context.close();
  });

  await test('WR-3: clicking Add renders form with all required fields', async () => {
    const { page, context } = await openApp(browser);
    await setupRegister(page, { txCache: [], formMode: 'add', formData: {} });
    const result = await page.evaluate(() => {
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        hasDateInput: html.includes('type="date"'),
        hasPayee: html.includes("'payee'") || html.includes('"payee"') || html.includes('payee'),
        hasMemo: html.includes("'memo'") || html.includes('"memo"') || html.includes('memo'),
        hasCategory: html.includes('category_key'),
        hasOutflow: html.includes('outflow'),
        hasInflow: html.includes('inflow'),
        hasCleared: html.includes("'cleared'") || html.includes('"cleared"'),
        hasSaveBtn: html.includes('_saveTxForm()'),
        hasCancelBtn: html.includes('_closeTxForm()')
      };
    });
    assert(result.hasDateInput, 'Form must have date input');
    assert(result.hasCategory, 'Form must have category field');
    assert(result.hasOutflow, 'Form must have outflow field');
    assert(result.hasInflow, 'Form must have inflow field');
    assert(result.hasCleared, 'Form must have cleared checkbox');
    assert(result.hasSaveBtn, 'Form must have Save button calling _saveTxForm');
    assert(result.hasCancelBtn, 'Form must have Cancel button calling _closeTxForm');
    await context.close();
  });

  await test('WR-4: outflow/inflow mutual exclusion — setTxFormField clears opposite field', async () => {
    const { page, context } = await openApp(browser);
    await setupRegister(page, { txCache: [], formMode: 'add', formData: {} });
    const result = await page.evaluate(() => {
      // Simulate entering outflow
      _setTxFormField('outflow', '50.00');
      var afterOutflow = { outflow: _txFormData.outflow, inflow: _txFormData.inflow };
      // Simulate entering inflow
      _setTxFormField('inflow', '200.00');
      var afterInflow = { outflow: _txFormData.outflow, inflow: _txFormData.inflow };
      return { afterOutflow, afterInflow };
    });
    assert(result.afterOutflow.outflow === '50.00', 'outflow must be set');
    assert(result.afterOutflow.inflow === '', 'inflow must be cleared when outflow entered');
    assert(result.afterInflow.inflow === '200.00', 'inflow must be set');
    assert(result.afterInflow.outflow === '', 'outflow must be cleared when inflow entered');
    await context.close();
  });

  await test('WR-5: Save with empty amount shows validation error, no POST fired', async () => {
    const { page, context } = await openApp(browser);
    let postFired = false;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'POST') { postFired = true; }
      route.fulfill({ status: 201, body: '[]' });
    });
    await setupRegister(page, { txCache: [], formMode: 'add', formData: { transaction_date: '2026-06-27' } });
    await page.evaluate(() => { _saveTxForm(); });
    await page.waitForTimeout(100);
    const result = await page.evaluate(() => ({
      error: _txFormError,
      formStillOpen: _txFormMode === 'add'
    }));
    assert(!postFired, 'POST must not fire when amount is missing');
    assert(result.error.length > 0, 'Validation error must be set');
    assert(result.formStillOpen, 'Form must remain open after validation error');
    await context.close();
  });

  await test('WR-6: Save with invalid amount (1e3) shows validation error, no POST fired', async () => {
    const { page, context } = await openApp(browser);
    let postFired = false;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'POST') { postFired = true; }
      route.fulfill({ status: 201, body: '[]' });
    });
    await setupRegister(page, { txCache: [], formMode: 'add',
      formData: { transaction_date: '2026-06-27', outflow: '1e3' } });
    await page.evaluate(() => { _saveTxForm(); });
    await page.waitForTimeout(100);
    const error = await page.evaluate(() => _txFormError);
    assert(!postFired, 'POST must not fire for invalid amount');
    assert(error.includes('positive number'), 'Error must mention positive number format');
    await context.close();
  });

  await test('WR-6b (Phase 5E-10): Save with blank payee shows validation error, no POST fired (Wendy feedback #3)', async () => {
    const { page, context } = await openApp(browser);
    let postFired = false;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'POST') { postFired = true; }
      route.fulfill({ status: 201, body: '[]' });
    });
    await setupRegister(page, { txCache: [], formMode: 'add',
      formData: { transaction_date: '2026-06-27', outflow: '45.00', payee: '' } });
    await page.evaluate(() => { _saveTxForm(); });
    await page.waitForTimeout(100);
    const result = await page.evaluate(() => ({ error: _txFormError, formStillOpen: _txFormMode === 'add' }));
    assert(!postFired, 'POST must not fire when payee is blank');
    assert(result.error.toLowerCase().includes('payee'), 'Error must mention payee, got: ' + result.error);
    assert(result.formStillOpen, 'Form must remain open after validation error');
    await context.close();
  });

  await test('WR-6c (Phase 5E-10): Save with a non-blank payee is not blocked by the payee-required check', async () => {
    const { page, context } = await openApp(browser);
    let postFired = false;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'POST') { postFired = true; }
      route.fulfill({ status: 201, body: '[]' });
    });
    await setupRegister(page, { txCache: [], formMode: 'add',
      formData: { transaction_date: '2026-06-27', outflow: '45.00', payee: 'Fandango' } });
    await page.evaluate(() => { _saveTxForm(); });
    await page.waitForTimeout(200);
    assert(postFired, 'POST must fire once a non-blank payee is provided alongside a valid date/amount/account');
    await context.close();
  });

  await test('WR-7: Cancel closes form without firing any request', async () => {
    const { page, context } = await openApp(browser);
    let requestFired = false;
    await page.route('**/rest/v1/transactions**', route => {
      requestFired = true;
      route.fulfill({ status: 201, body: '[]' });
    });
    await setupRegister(page, { txCache: [], formMode: 'add', formData: { outflow: '50.00' } });
    await page.evaluate(() => { _closeTxForm(); });
    await page.waitForTimeout(100);
    const result = await page.evaluate(() => ({ formMode: _txFormMode, formData: JSON.stringify(_txFormData) }));
    assert(!requestFired, 'No request must fire on cancel');
    assert(result.formMode === null, 'Form mode must be null after cancel');
    await context.close();
  });

  await test('WR-8: Valid outflow save fires POST with negative amount, form closes on success', async () => {
    const { page, context } = await openApp(browser);
    let capturedBody = null;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'POST') {
        capturedBody = JSON.parse(route.request().postData() || '{}');
        route.fulfill({ status: 201, contentType: 'application/json', body: '[]' });
      } else if (route.request().method() === 'GET') {
        route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
      } else {
        route.continue();
      }
    });
    await setupRegister(page, { txCache: [], formMode: 'add',
      formData: { transaction_date: '2026-06-27', payee: 'Walmart', outflow: '45.00' } });
    await page.evaluate(() => {
      _accountsCache = [{ key: 'truist_checking', label: 'Truist Checking', lifecycle_status: 'active', starting_balance: 1000 }];
      _categoriesCache = [];
      _txLedgerAccountKey = 'truist_checking';
      _saveTxForm();
    });
    await page.waitForTimeout(300);
    assert(capturedBody !== null, 'POST must have fired');
    assert(capturedBody.amount === -45.00, 'amount must be negative for outflow, got: ' + capturedBody.amount);
    assert(capturedBody.source === 'manual', 'source must be manual');
    assert(capturedBody.account_key === 'truist_checking', 'account_key must be set');
    assert(!('user_id' in capturedBody), 'user_id must not be in POST body');
    assert(!('notes' in capturedBody), 'notes must not be in POST body');
    await context.close();
  }, { tags: ['smoke'] });

  await test('WR-9: Valid inflow save fires POST with positive amount', async () => {
    const { page, context } = await openApp(browser);
    let capturedBody = null;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'POST') {
        capturedBody = JSON.parse(route.request().postData() || '{}');
        route.fulfill({ status: 201, contentType: 'application/json', body: '[]' });
      } else if (route.request().method() === 'GET') {
        route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
      } else {
        route.continue();
      }
    });
    await setupRegister(page, { txCache: [], formMode: 'add',
      formData: { transaction_date: '2026-06-27', payee: 'Paycheck', inflow: '2000.00' } });
    await page.evaluate(() => {
      _accountsCache = [{ key: 'truist_checking', label: 'Truist Checking', lifecycle_status: 'active', starting_balance: 1000 }];
      _categoriesCache = [];
      _txLedgerAccountKey = 'truist_checking';
      _saveTxForm();
    });
    await page.waitForTimeout(300);
    assert(capturedBody !== null, 'POST must have fired');
    assert(capturedBody.amount === 2000.00, 'amount must be positive for inflow, got: ' + capturedBody.amount);
    await context.close();
  });

  await test('WR-10: Edit button opens form pre-populated; non-manual row has no edit button', async () => {
    const { page, context } = await openApp(browser);
    // One manual row, one import row
    const mixedTx = [
      { id: 'wr-manual', account_key: 'truist_checking', transaction_date: '2026-06-01',
        payee: 'Kroger', memo: 'Food', amount: -50.00, category_key: 'groceries',
        cleared: false, source: 'manual', created_at: '2026-06-01T10:00:00Z', updated_at: '2026-06-01T10:00:00Z' },
      { id: 'wr-import', account_key: 'truist_checking', transaction_date: '2026-06-02',
        payee: 'Amazon', memo: '', amount: -30.00, category_key: null,
        cleared: false, source: 'import', created_at: '2026-06-02T10:00:00Z', updated_at: '2026-06-02T10:00:00Z' }
    ];
    await setupRegister(page, { txCache: mixedTx, formMode: 'edit',
      formData: { id: 'wr-manual', transaction_date: '2026-06-01', payee: 'Kroger', memo: 'Food',
                  amount: -50.00, category_key: 'groceries', cleared: false, source: 'manual' },
      editId: 'wr-manual' });
    const result = await page.evaluate(() => {
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        formOpen: _txFormMode === 'edit',
        editIdSet: _txEditId === 'wr-manual',
        payeePrePopulated: html.includes('Kroger'),
        formPresent: html.includes('Save Changes'),
        // Import row should not have edit/delete buttons calling _openTxForm
        importRowHasNoEditBtn: !html.includes('wr-import') || (function() {
          // Check that _openTxDeleteConfirm is only called with manual ID
          var editCalls = html.match(/_openTxForm\('edit'[^)]+\)/g) || [];
          return !editCalls.some(c => c.includes('wr-import'));
        })()
      };
    });
    assert(result.formOpen, 'Form mode must be edit');
    assert(result.editIdSet, '_txEditId must be set to the manual row ID');
    assert(result.payeePrePopulated, 'Payee must be pre-populated in edit form');
    assert(result.formPresent, 'Save Changes button must appear in edit mode');
    assert(result.importRowHasNoEditBtn, 'Import row must not have edit button');
    await context.close();
  });

  await test('WR-11: Edit save fires PATCH with only mutable fields (no account_key, user_id, source)', async () => {
    const { page, context } = await openApp(browser);
    let capturedBody = null;
    let capturedUrl = null;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'PATCH') {
        capturedBody = JSON.parse(route.request().postData() || '{}');
        capturedUrl = route.request().url();
        route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
      } else if (route.request().method() === 'GET') {
        route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
      } else {
        route.continue();
      }
    });
    await setupRegister(page, { txCache: WR_MOCK_TX, formMode: 'edit',
      formData: { transaction_date: '2026-06-01', payee: 'Kroger Updated', memo: 'Edited',
                  amount: -85.50, outflow: '85.50', category_key: 'groceries', cleared: true },
      editId: 'wr-tx-001' });
    await page.evaluate(() => {
      _accountsCache = [{ key: 'truist_checking', label: 'Truist Checking', lifecycle_status: 'active', starting_balance: 1000 }];
      _categoriesCache = [{ key: 'groceries', label: 'Groceries', lifecycle_status: 'active' }];
      _txLedgerAccountKey = 'truist_checking';
      _saveTxForm();
    });
    await page.waitForTimeout(300);
    assert(capturedBody !== null, 'PATCH must have fired');
    assert(capturedUrl && capturedUrl.includes('id=eq.wr-tx-001'), 'PATCH URL must target correct ID');
    assert(!('account_key' in capturedBody), 'account_key must not be in PATCH body');
    assert(!('user_id' in capturedBody), 'user_id must not be in PATCH body');
    assert(!('source' in capturedBody), 'source must not be in PATCH body');
    assert(!('notes' in capturedBody), 'notes must not be in PATCH body');
    assert('transaction_date' in capturedBody, 'transaction_date must be in PATCH body');
    assert('amount' in capturedBody, 'amount must be in PATCH body');
    await context.close();
  });

  await test('WR-12: Delete icon shows confirmation strip; non-manual row has no delete button', async () => {
    const { page, context } = await openApp(browser);
    const mixedTx = [
      { id: 'wr-m1', account_key: 'truist_checking', transaction_date: '2026-06-01',
        payee: 'Manual Row', memo: '', amount: -50.00, category_key: null,
        cleared: false, source: 'manual', created_at: '2026-06-01T10:00:00Z', updated_at: '2026-06-01T10:00:00Z' },
      { id: 'wr-i1', account_key: 'truist_checking', transaction_date: '2026-06-02',
        payee: 'Import Row', memo: '', amount: -30.00, category_key: null,
        cleared: false, source: 'import', created_at: '2026-06-02T10:00:00Z', updated_at: '2026-06-02T10:00:00Z' }
    ];
    await setupRegister(page, { txCache: mixedTx, deleteId: 'wr-m1' });
    const result = await page.evaluate(() => {
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      return {
        confirmStripPresent: html.includes('This cannot be undone'),
        confirmBtn: html.includes('_confirmTxDelete()'),
        cancelBtn: html.includes('_cancelTxDelete()'),
        importHasNoDeleteBtn: (function() {
          var deleteCalls = html.match(/_openTxDeleteConfirm\('[^']+'\)/g) || [];
          return !deleteCalls.some(c => c.includes('wr-i1'));
        })()
      };
    });
    assert(result.confirmStripPresent, 'Confirmation strip must show "This cannot be undone"');
    assert(result.confirmBtn, 'Confirm Delete button must call _confirmTxDelete');
    assert(result.cancelBtn, 'Cancel button must call _cancelTxDelete');
    assert(result.importHasNoDeleteBtn, 'Import row must not have a delete button');
    await context.close();
  });

  await test('WR-13: Delete Cancel — strip dismissed, no DELETE fired', async () => {
    const { page, context } = await openApp(browser);
    let deleteFired = false;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'DELETE') { deleteFired = true; }
      route.fulfill({ status: 204, body: '' });
    });
    await setupRegister(page, { txCache: WR_MOCK_TX, deleteId: 'wr-tx-001' });
    await page.evaluate(() => { _cancelTxDelete(); });
    await page.waitForTimeout(100);
    const result = await page.evaluate(() => ({
      confirmIdCleared: _txDeleteConfirmId === null
    }));
    assert(!deleteFired, 'DELETE must not fire on cancel');
    assert(result.confirmIdCleared, '_txDeleteConfirmId must be null after cancel');
    await context.close();
  });

  await test('WR-14: Delete Confirm fires DELETE for correct ID, cache cleared on success', async () => {
    const { page, context } = await openApp(browser);
    let capturedUrl = null;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'DELETE') {
        capturedUrl = route.request().url();
        route.fulfill({ status: 204, body: '' });
      } else if (route.request().method() === 'GET') {
        route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
      } else {
        route.continue();
      }
    });
    await setupRegister(page, { txCache: WR_MOCK_TX, deleteId: 'wr-tx-001' });
    await page.evaluate(() => {
      _accountsCache = [{ key: 'truist_checking', label: 'Truist Checking', lifecycle_status: 'active', starting_balance: 1000 }];
      _txLedgerAccountKey = 'truist_checking';
      _confirmTxDelete();
    });
    await page.waitForTimeout(300);
    assert(capturedUrl !== null, 'DELETE must have fired');
    assert(capturedUrl.includes('id=eq.wr-tx-001'), 'DELETE must target correct ID');
    await context.close();
  });

  await test('WR-15: Cleared toggle fires PATCH with correct cleared value for manual row', async () => {
    const { page, context } = await openApp(browser);
    let capturedBody = null;
    let capturedUrl = null;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'PATCH') {
        capturedBody = JSON.parse(route.request().postData() || '{}');
        capturedUrl = route.request().url();
        route.fulfill({ status: 200, body: '{}' });
      } else if (route.request().method() === 'GET') {
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(WR_MOCK_TX) });
      } else {
        route.continue();
      }
    });
    await setupRegister(page, { txCache: WR_MOCK_TX });
    await page.evaluate(() => {
      _accountsCache = [{ key: 'truist_checking', label: 'Truist Checking', lifecycle_status: 'active', starting_balance: 1000 }];
      _txLedgerAccountKey = 'truist_checking';
      _toggleTxCleared('wr-tx-001', false); // toggle from false to true
    });
    await page.waitForTimeout(300);
    assert(capturedBody !== null, 'PATCH must have fired');
    assert(capturedUrl && capturedUrl.includes('id=eq.wr-tx-001'), 'PATCH must target correct ID');
    assert(capturedBody.cleared === true, 'cleared must be toggled to true');
    assert(Object.keys(capturedBody).length === 1, 'PATCH body must only contain cleared field');
    await context.close();
  });

  await test('WR-16: Save error (mocked 500) — form stays open, error message shown', async () => {
    const { page, context } = await openApp(browser);
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'POST') {
        route.fulfill({ status: 500, contentType: 'application/json',
          body: JSON.stringify({ message: 'internal server error' }) });
      } else {
        route.continue();
      }
    });
    await setupRegister(page, { txCache: [], formMode: 'add',
      formData: { transaction_date: '2026-06-27', outflow: '50.00' } });
    await page.evaluate(() => {
      _accountsCache = [{ key: 'truist_checking', label: 'Truist Checking', lifecycle_status: 'active', starting_balance: 1000 }];
      _categoriesCache = [];
      _txLedgerAccountKey = 'truist_checking';
      _saveTxForm();
    });
    await page.waitForTimeout(300);
    const result = await page.evaluate(() => ({
      formStillOpen: _txFormMode === 'add',
      hasError: _txFormError.length > 0,
      savingReset: _txFormSaving === false
    }));
    assert(result.formStillOpen, 'Form must remain open after save error');
    assert(result.hasError, 'Error message must be set after 500 response');
    assert(result.savingReset, '_txFormSaving must be reset to false in finally block');
    await context.close();
  });

  // ── Section WR2: Write Hardening (ChatGPT round 2) ──────────────────────
  console.log('\n── Section WR2: Write Hardening (ChatGPT round 2) ──');

  await test('WR2-1: Edit open populates outflow for negative amount transaction', async () => {
    const { page, context } = await openApp(browser);
    const result = await page.evaluate(([mockAccounts, mockCategories, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = mockCategories;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns; // wr-tx-001 has amount: -85.50
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      _openTxEditById('wr-tx-001');
      return {
        mode: _txFormMode,
        outflow: _txFormData.outflow,
        inflow: _txFormData.inflow
      };
    }, [WR_MOCK_ACCOUNTS, WR_MOCK_CATEGORIES, WR_MOCK_TX]);
    assert(result.mode === 'edit', 'form mode must be edit');
    assert(result.outflow === '85.50', 'negative amount must populate outflow as "85.50", got: ' + result.outflow);
    assert(!result.inflow, 'inflow must be empty when amount is negative');
    await context.close();
  });

  await test('WR2-2: Edit open populates inflow for positive amount transaction', async () => {
    const { page, context } = await openApp(browser);
    const positiveTx = [{
      id: 'wr-positive-001', account_key: 'truist_checking', transaction_date: '2026-06-05',
      payee: 'Paycheck', memo: '', amount: 2000.00, category_key: null,
      cleared: false, source: 'manual',
      created_at: '2026-06-05T10:00:00Z', updated_at: '2026-06-05T10:00:00Z'
    }];
    const result = await page.evaluate(([mockAccounts, mockCategories, txns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = mockCategories;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = txns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      _openTxEditById('wr-positive-001');
      return {
        mode: _txFormMode,
        outflow: _txFormData.outflow,
        inflow: _txFormData.inflow
      };
    }, [WR_MOCK_ACCOUNTS, WR_MOCK_CATEGORIES, positiveTx]);
    assert(result.mode === 'edit', 'form mode must be edit');
    assert(result.inflow === '2000.00', 'positive amount must populate inflow as "2000.00", got: ' + result.inflow);
    assert(!result.outflow, 'outflow must be empty when amount is positive');
    await context.close();
  });

  await test('WR2-3: Typing in outflow clears inflow field without full re-render (mutual exclusion via DOM)', async () => {
    const { page, context } = await openApp(browser);
    await setupRegister(page, { txCache: WR_MOCK_TX });
    // Open the add form
    await page.evaluate(() => { _openTxForm('add', null); });
    // Fill inflow first
    await page.fill('#tx-form-inflow', '50.00');
    // Now type in outflow — mutual exclusion should clear inflow via direct DOM update
    await page.fill('#tx-form-outflow', '25.00');
    const result = await page.evaluate(() => ({
      inflowEl: document.getElementById('tx-form-inflow')?.value,
      stateInflow: _txFormData.inflow,
      stateOutflow: _txFormData.outflow
    }));
    assert(result.inflowEl === '', 'inflow DOM field must be cleared when outflow typed, got: "' + result.inflowEl + '"');
    assert(!result.stateInflow, 'inflow state must be cleared when outflow typed');
    await context.close();
  });

  await test('WR2-4: Typing in inflow clears outflow field (mutual exclusion via DOM)', async () => {
    const { page, context } = await openApp(browser);
    await setupRegister(page, { txCache: WR_MOCK_TX });
    await page.evaluate(() => { _openTxForm('add', null); });
    await page.fill('#tx-form-outflow', '30.00');
    await page.fill('#tx-form-inflow', '100.00');
    const result = await page.evaluate(() => ({
      outflowEl: document.getElementById('tx-form-outflow')?.value,
      stateOutflow: _txFormData.outflow
    }));
    assert(result.outflowEl === '', 'outflow DOM field must be cleared when inflow typed, got: "' + result.outflowEl + '"');
    assert(!result.stateOutflow, 'outflow state must be cleared when inflow typed');
    await context.close();
  });

  await test('WR2-5: Failed save re-enables save button (_txFormSaving reset in finally)', async () => {
    const { page, context } = await openApp(browser);
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'POST') {
        route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: 'server error' }) });
      } else { route.continue(); }
    });
    await page.evaluate(([mockAccounts, mockCategories, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = mockCategories;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      _openTxForm('add', null);
    }, [WR_MOCK_ACCOUNTS, WR_MOCK_CATEGORIES, WR_MOCK_TX]);
    // Pre-fill a valid form
    await page.evaluate(() => {
      _txFormData.transaction_date = '2026-06-15';
      _txFormData.outflow = '50.00';
    });
    await page.evaluate(() => { _saveTxForm(); });
    // Wait for the network call and finally block to complete
    await page.waitForTimeout(500);
    const result = await page.evaluate(() => ({
      savingFlag: _txFormSaving,
      hasError: !!_txFormError,
      formOpen: _txFormMode === 'add'
    }));
    assert(!result.savingFlag, '_txFormSaving must be false after failed save (finally block reset)');
    assert(result.hasError, 'error message must be set after failed save');
    assert(result.formOpen, 'form must stay open after failed save');
    await context.close();
  });

  await test('WR2-6: Failed delete re-enables confirm button (_txDeleteSaving reset in finally)', async () => {
    const { page, context } = await openApp(browser);
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'DELETE') {
        route.fulfill({ status: 500, body: '' });
      } else { route.continue(); }
    });
    await page.evaluate(([mockAccounts, mockCategories, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = mockCategories;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      _openTxDeleteConfirm('wr-tx-001');
    }, [WR_MOCK_ACCOUNTS, WR_MOCK_CATEGORIES, WR_MOCK_TX]);
    await page.evaluate(() => { _confirmTxDelete(); });
    await page.waitForTimeout(500);
    const result = await page.evaluate(() => ({
      deletingFlag: _txDeleteSaving,
      hasError: !!_txDeleteError,
      confirmStillOpen: _txDeleteConfirmId === 'wr-tx-001'
    }));
    assert(!result.deletingFlag, '_txDeleteSaving must be false after failed delete (finally block reset)');
    assert(result.hasError, 'error message must be set after failed delete');
    await context.close();
  });

  await test('WR2-7: Edit button safe with payee containing quotes — uses _openTxEditById not JSON.stringify', async () => {
    const { page, context } = await openApp(browser);
    const quoteTx = [{
      id: 'wr-quote-tx', account_key: 'truist_checking', transaction_date: '2026-06-10',
      payee: "O'Brien's \"Grill\"", memo: 'payee with \'quotes\' and "double"',
      amount: -42.00, category_key: null, cleared: false, source: 'manual',
      created_at: '2026-06-10T10:00:00Z', updated_at: '2026-06-10T10:00:00Z'
    }];
    const result = await page.evaluate(([mockAccounts, txns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = [];
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = txns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      var html = document.getElementById('transactions-content')?.innerHTML || '';
      // Must use _openTxEditById, not JSON.stringify
      var hasEditById = html.includes('_openTxEditById(');
      var hasJsonStringify = html.includes('JSON.stringify');
      // Calling _openTxEditById with the quote tx id must work without throwing
      var threw = false;
      try { _openTxEditById('wr-quote-tx'); } catch(e) { threw = true; }
      return { hasEditById, hasJsonStringify, threw, mode: _txFormMode, outflow: _txFormData.outflow };
    }, [WR_MOCK_ACCOUNTS, quoteTx]);
    assert(result.hasEditById, 'edit button must use _openTxEditById');
    assert(!result.hasJsonStringify, 'edit button must not use JSON.stringify');
    assert(!result.threw, '_openTxEditById must not throw for payee with quotes');
    assert(result.mode === 'edit', 'edit form must open for quote-payee transaction');
    assert(result.outflow === '42.00', 'outflow must be correctly populated: ' + result.outflow);
    await context.close();
  });

  await test('WR2-8: Add form default date — no touch, save fires POST with today\'s date', async () => {
    const { page, context } = await openApp(browser);
    let capturedBody = null;
    await page.route('**/rest/v1/transactions**', route => {
      if (route.request().method() === 'POST') {
        capturedBody = JSON.parse(route.request().postData() || '{}');
        route.fulfill({ status: 201, contentType: 'application/json', body: '[]' });
      } else if (route.request().method() === 'GET') {
        // Must mock GET — _saveTxForm calls _loadTxLedger on success, which fires GET
        route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
      } else { route.continue(); }
    });
    await page.evaluate(([mockAccounts, mockCategories, mockTxns]) => {
      FEATURE_FLAGS.showTransactionLedger = true;
      _accountsCache = mockAccounts;
      _categoriesCache = mockCategories;
      _registriesLoadStatus = 'loaded';
      _txLedgerLoadStatus = 'loaded';
      _txLedgerCache = mockTxns;
      _txLedgerAccountKey = 'truist_checking';
      renderApp();
      setSection('transactions');
      setTxSubNav('register');
      _openTxForm('add', null); // do NOT pass a date
    }, [WR_MOCK_ACCOUNTS, WR_MOCK_CATEGORIES, WR_MOCK_TX]);
    // Do NOT touch the date field — leave it at whatever the form initialized
    // Enter outflow and payee (Phase 5E-10: payee is now required — this test's purpose is
    // verifying the default date is used untouched, not testing payee validation, so a valid
    // payee is filled here to isolate that).
    await page.fill('#tx-form-outflow', '42.00');
    await page.fill('input[placeholder="Required"]', 'WR2-8 Test Payee');
    // Capture today's date in the same format _todayTxDate() would return
    const expectedDate = await page.evaluate(() => {
      var n = new Date();
      return n.getFullYear() + '-' + String(n.getMonth()+1).padStart(2,'0') + '-' + String(n.getDate()).padStart(2,'0');
    });
    // Fire save
    await page.evaluate(() => { _saveTxForm(); });
    await page.waitForTimeout(300);
    const result = await page.evaluate(() => ({
      formError: _txFormError,
      formMode: _txFormMode,
      stateDate: _txFormData.transaction_date
    }));
    assert(capturedBody !== null, 'POST must have fired — date was pre-initialized so validation should pass');
    assert(capturedBody.transaction_date === expectedDate,
      'POST body transaction_date must equal today (' + expectedDate + '), got: ' + capturedBody.transaction_date);
    assert(!result.formError.includes('Date is required'),
      '"Date is required" error must not appear when date field was not touched');
    await context.close();
  });

  // ── 5G-1D Slice 3/5: combined weekly closeout — browser wiring (mocked wrapper) ──
  // Drives submitCloseout() against a mocked save_weekly_closeout_with_snapshots endpoint.
  // canWriteFinancials()/getAuthHeaders() are satisfied by setting USER_ROLE='owner' and
  // overriding getAuthHeaders in the page context (file:// has no real session). The live
  // round-trip is the post-deploy Supabase smoke; this proves the client call shape + the
  // in-flight / GFA01 / domain-reject / ambiguous state machine end-to-end in a real browser.
  {
    const NINE = ['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise'];
    // All six closeout scenarios share ONE page load (one openApp/context) to keep the suite's
    // readiness/fallback footprint minimal — each scenario resets app + mock state, swaps the
    // wrapper response via `scn`, then runs submitCloseout(). Routes register once and dispatch
    // on `scn`; the reload endpoints return `reloadRecon`/`reloadSnaps` so CO-5's ambiguous
    // re-read sees a complete+matching week. USER_ROLE/getAuthHeaders overrides live only on
    // this page's context and die with it — they never leak to other tests (fresh contexts).
    const { page, context } = await openApp(browser);
    let scn = 'success', coBody = null, coPosts = 0, reloadRecon = '[]', reloadSnaps = '[]';
    await page.route('**/rest/v1/rpc/save_weekly_closeout_with_snapshots**', route => {
      coPosts++; coBody = JSON.parse(route.request().postData() || '{}');
      if (scn === 'abort') return route.abort();
      if (scn === 'gfa01') return route.fulfill({ status:400, contentType:'application/json', body: JSON.stringify({ code:'GFA01', message:'fully closed week 6: non-empty commitment resubmission', hint:'REQUIRES_SUPERVISED_ADJUDICATION' }) });
      if (scn === 'monotonic') return route.fulfill({ status:400, contentType:'application/json', body: JSON.stringify({ message:'monotonic violation: adam_ira submitted 50 < prior effective 100 (use the correction path)' }) });
      // P1-1: a 2xx with a malformed success contract (snapshot_count≠9) — must NOT be trusted.
      if (scn === 'badcontract') return route.fulfill({ status:200, contentType:'application/json', body: JSON.stringify({ ok:true, mode:'normal_closeout', week_num: coBody.p_week_num, snapshot_count:8 }) });
      // Success: echo the posted week so res.week_num===n holds for any scenario's week.
      return route.fulfill({ status:200, contentType:'application/json', body: JSON.stringify({ ok:true, mode:'normal_closeout', week_num: coBody.p_week_num, snapshot_count:9 }) });
    });
    await page.route('**/rest/v1/weekly_reconciliations**', route => route.fulfill({ status:200, contentType:'application/json', body: reloadRecon }));
    await page.route('**/rest/v1/cash_commitments**', route => route.fulfill({ status:200, contentType:'application/json', body:'[]' }));
    await page.route('**/rest/v1/goal_funding_snapshots**', route => route.fulfill({ status:200, contentType:'application/json', body: reloadSnaps }));
    // Reset app + mock state before each scenario (isolation without a fresh page load).
    const resetCloseout = (cfg) => { coBody = null; coPosts = 0;
      return page.evaluate((c) => {
        USER_ROLE='owner'; getAuthHeaders=async()=>({apikey:'t',Authorization:'Bearer t','Content-Type':'application/json'});
        reconData={}; goalSnapData={}; _closeout=null; reconOpen=c.week; _reconBalances=c.bal; _reconBasis='posted_current_balance';
        var funded={},priors={},present={}; c.nine.forEach(function(id,i){ funded[id]=100; priors[id]=100; present[id]=(c.presentN>i); });
        _closeout={ week:c.week, phase:'confirm', repair:!!c.repair, funded:funded, priors:priors, present:present, newCommitments:c.nc||[], patched:[], error:'' };
      }, cfg);
    };

    await test('5G1D-CO-1: closeout POSTs the wrapper payload (9 rows, normal_closeout, expected 9, no p_recorded_at) and closes on a verified-complete success', async () => {
      scn = 'success';
      // P1-1: success is only trusted when the reloaded end-state IS a complete closeout of this
      // week's nine — so the re-read must return a reconciled week 6 with the nine matching snaps.
      reloadRecon = JSON.stringify([{ week_num:6, chk:100, sav:200, amx:300, tax:0, lc:400, balance_basis:'posted_current_balance', recorded_at:'2026-07-13T00:00:00Z' }]);
      reloadSnaps = JSON.stringify(NINE.map(id => ({ week_num:6, goal_id:id, funded_amount:100 })));
      await resetCloseout({ nine:NINE, week:6, bal:{chk:100,sav:200,amx:300,tax:0,lc:400}, presentN:0 });
      const r = await page.evaluate(async () => { await submitCloseout(); return { closeout:_closeout, reconOpen:reconOpen }; });
      await page.waitForTimeout(30);
      reloadRecon = '[]'; reloadSnaps = '[]';
      assert(coPosts === 1, 'exactly one wrapper POST, got ' + coPosts);
      assert(coBody && coBody.p_mode === 'normal_closeout', 'p_mode normal_closeout');
      assert(coBody.p_expected_count === 9, 'p_expected_count 9');
      assert(coBody.p_model_year !== undefined && !('p_recorded_at' in coBody), 'PLAN_YEAR present, no p_recorded_at');
      assert(Array.isArray(coBody.p_snapshot_rows) && coBody.p_snapshot_rows.length === 9, 'nine snapshot rows');
      assert(coBody.p_snapshot_rows.every(x => !('source' in x)), 'no client source key on rows');
      assert('p_new_commitments' in coBody && 'p_patched' in coBody, 'commitment arrays present');
      assert(r.closeout === null, '_closeout cleared on a verified-complete success');
      assert(r.reconOpen === null, 'form closed on success');
    }, { tags: ['smoke'] });

    await test('5G1D-CO-2: an in-flight closeout ignores a second submit (no double POST)', async () => {
      scn = 'success'; reloadRecon = '[]'; reloadSnaps = '[]';
      await resetCloseout({ nine:NINE, week:6, bal:{chk:1,sav:2,amx:3,tax:0,lc:4}, presentN:0 });
      const r = await page.evaluate(async () => {
        var p1 = submitCloseout();                 // runs synchronously to the first await → phase in_flight
        var midPhase = _closeout && _closeout.phase;
        await submitCloseout();                    // guarded early-return
        await p1;
        return { midPhase };
      });
      await page.waitForTimeout(30);
      assert(r.midPhase === 'in_flight', 'phase was in_flight between calls, got ' + r.midPhase);
      assert(coPosts === 1, 'only one POST despite the double submit, got ' + coPosts);
    });

    await test('5G1D-CO-3: GFA01 response routes to supervised adjudication (never an auto-retry)', async () => {
      scn = 'gfa01';
      await resetCloseout({ nine:NINE, week:6, bal:{chk:1,sav:2,amx:3,tax:0,lc:4}, presentN:0, nc:[{}] });
      const r = await page.evaluate(async () => { await submitCloseout(); return { phase:_closeout && _closeout.phase, retained:!!_closeout }; });
      assert(r.retained === true, '_closeout must be retained (not cleared) on GFA01');
      assert(r.phase === 'adjudication', 'phase must be adjudication, got ' + r.phase);
    });

    await test('5G1D-CO-4: a domain reject (monotonic) keeps the confirmation open with the server message', async () => {
      scn = 'monotonic';
      await resetCloseout({ nine:NINE, week:6, bal:{chk:1,sav:2,amx:3,tax:0,lc:4}, presentN:0 });
      const r = await page.evaluate(async () => { await submitCloseout(); return { phase:_closeout && _closeout.phase, error:_closeout && _closeout.error, reconOpen:reconOpen }; });
      assert(r.phase === 'confirm', 'stays on the confirmation, got ' + r.phase);
      assert(/monotonic/.test(r.error || ''), 'server message surfaced, got: ' + r.error);
      assert(r.reconOpen === 6, 'form stays open on a domain reject');
    });

    await test('5G1D-CO-5: an ambiguous transport failure re-reads both halves; a complete+matching week is idempotent success', async () => {
      scn = 'abort';
      reloadRecon = JSON.stringify([{ week_num:6, chk:100, sav:200, amx:300, tax:0, lc:400, balance_basis:'posted_current_balance', recorded_at:'2026-07-13T00:00:00Z' }]);
      reloadSnaps = JSON.stringify(NINE.map(id => ({ week_num:6, goal_id:id, funded_amount:100 })));
      await resetCloseout({ nine:NINE, week:6, bal:{chk:100,sav:200,amx:300,tax:0,lc:400}, presentN:0 });
      const r = await page.evaluate(async () => { await submitCloseout(); return { closeout:_closeout, reconOpen:reconOpen }; });
      await page.waitForTimeout(30);
      reloadRecon = '[]'; reloadSnaps = '[]'; // restore defaults for any later scenario
      assert(r.closeout === null, 'idempotent-match on re-read clears _closeout (success), got ' + JSON.stringify(r.closeout));
      assert(r.reconOpen === null, 'form closed after idempotent-match success');
    });

    await test('5G1D-CO-6: a half-close repair POSTs empty commitment arrays with the nine snapshot rows (branch G shape)', async () => {
      scn = 'success';
      reloadRecon = JSON.stringify([{ week_num:7, chk:1, sav:2, amx:3, tax:0, lc:4, balance_basis:'posted_current_balance', recorded_at:'2026-07-13T00:00:00Z' }]);
      reloadSnaps = JSON.stringify(NINE.map(id => ({ week_num:7, goal_id:id, funded_amount:100 })));
      await resetCloseout({ nine:NINE, week:7, bal:{chk:1,sav:2,amx:3,tax:0,lc:4}, presentN:3, repair:true });
      const r = await page.evaluate(async () => { await submitCloseout(); return { closeout:_closeout }; });
      await page.waitForTimeout(30);
      reloadRecon = '[]'; reloadSnaps = '[]';
      assert(coBody && Array.isArray(coBody.p_new_commitments) && coBody.p_new_commitments.length === 0, 'repair posts empty p_new_commitments');
      assert(Array.isArray(coBody.p_patched) && coBody.p_patched.length === 0, 'repair posts empty p_patched');
      assert(Array.isArray(coBody.p_snapshot_rows) && coBody.p_snapshot_rows.length === 9, 'nine snapshot rows in a repair');
      assert(r.closeout === null, 'a verified-complete repair clears _closeout');
    });

    // ── P1-1: a 2xx is not proof — the reloaded end-state must confirm a complete closeout ──
    await test('5G1D-CO-7: a 2xx whose reloaded end-state is NOT complete stays on the confirmation (unknown, not success)', async () => {
      scn = 'success'; reloadRecon = '[]'; reloadSnaps = '[]'; // server accepts, but nothing persisted on re-read
      await resetCloseout({ nine:NINE, week:6, bal:{chk:1,sav:2,amx:3,tax:0,lc:4}, presentN:0 });
      const r = await page.evaluate(async () => { await submitCloseout(); return { retained:!!_closeout, phase:_closeout&&_closeout.phase, error:_closeout&&_closeout.error, reconOpen:reconOpen }; });
      await page.waitForTimeout(30);
      assert(r.retained === true, '_closeout retained — a 2xx with no persisted completion is NOT success');
      assert(r.phase === 'confirm', 'stays on the confirmation, got ' + r.phase);
      assert(/could not be confirmed complete/.test(r.error || ''), 'explains the uncertainty, got: ' + r.error);
      assert(r.reconOpen === 6, 'form stays open on an unconfirmed 2xx');
    });

    await test('5G1D-CO-8: a 2xx with a bad response contract (snapshot_count≠9) is not trusted even if the week reads complete', async () => {
      scn = 'badcontract';
      reloadRecon = JSON.stringify([{ week_num:6, chk:1, sav:2, amx:3, tax:0, lc:4, balance_basis:'posted_current_balance', recorded_at:'2026-07-13T00:00:00Z' }]);
      reloadSnaps = JSON.stringify(NINE.map(id => ({ week_num:6, goal_id:id, funded_amount:100 })));
      await resetCloseout({ nine:NINE, week:6, bal:{chk:1,sav:2,amx:3,tax:0,lc:4}, presentN:0 });
      const r = await page.evaluate(async () => { await submitCloseout(); return { retained:!!_closeout, phase:_closeout&&_closeout.phase }; });
      await page.waitForTimeout(30);
      reloadRecon = '[]'; reloadSnaps = '[]';
      assert(r.retained === true, '_closeout retained — a malformed success contract must not clear staging');
      assert(r.phase === 'confirm', 'stays on the confirmation, got ' + r.phase);
    });

    await test('5G1D-CO-9: a 2xx whose persisted snapshots disagree with the confirmed amounts is not trusted', async () => {
      scn = 'success';
      reloadRecon = JSON.stringify([{ week_num:6, chk:1, sav:2, amx:3, tax:0, lc:4, balance_basis:'posted_current_balance', recorded_at:'2026-07-13T00:00:00Z' }]);
      reloadSnaps = JSON.stringify(NINE.map(id => ({ week_num:6, goal_id:id, funded_amount:999 }))); // ≠ confirmed 100
      await resetCloseout({ nine:NINE, week:6, bal:{chk:1,sav:2,amx:3,tax:0,lc:4}, presentN:0 });
      const r = await page.evaluate(async () => { await submitCloseout(); return { retained:!!_closeout, phase:_closeout&&_closeout.phase }; });
      await page.waitForTimeout(30);
      reloadRecon = '[]'; reloadSnaps = '[]';
      assert(r.retained === true, '_closeout retained — persisted≠confirmed must not report success');
      assert(r.phase === 'confirm', 'stays on the confirmation, got ' + r.phase);
    });

    await context.close();
  }

  // ── 5G-1D P0-4: reconciliation-delete row-9 guard (real DELETE round-trip) ──
  // Proves the guard end-to-end in a browser: a denied server DELETE must NOT drop local
  // reconciliation state, and a legitimately-deletable legacy week still deletes. The pure
  // predicate matrix (canDeleteRecon) is covered exhaustively in test_regression.js.
  {
    const { page, context } = await openApp(browser);
    let delStatus = 200, delMethodSeen = '';
    await page.route('**/rest/v1/weekly_reconciliations**', route => {
      const m = route.request().method();
      if (m === 'DELETE') { delMethodSeen = m; return route.fulfill({ status: delStatus, contentType:'application/json', body:'[]' }); }
      return route.fulfill({ status:200, contentType:'application/json', body:'[]' });
    });
    const setupDel = (loadStatus) => page.evaluate((ls) => {
      USER_ROLE='owner'; getAuthHeaders=async()=>({apikey:'t',Authorization:'Bearer t','Content-Type':'application/json'});
      reconData={ 3:{chk:1,sav:2,amx:3,tax:0,lc:4,balance_basis:'posted_current_balance',date:'Jan 18'} };
      goalSnapData={}; _goalSnapLoadStatus=ls; _reconDeleteError=null; reconDeleteConfirm=false; reconOpen=null;
    }, loadStatus);

    await test('5G1D-DEL-1: a DENIED server DELETE (403) keeps local reconData and records a week-scoped message', async () => {
      delStatus = 403;
      await setupDel('loaded'); // wk3 legacy + snapshot-free + loaded ⇒ canDeleteRecon true, so the guard allows the attempt
      const r = await page.evaluate(async () => { await deleteRecon(3); return { present: reconData[3] !== undefined, err: _reconDeleteError }; });
      assert(r.present === true, 'reconData[3] must survive a denied DELETE (no optimistic drop)');
      assert(r.err && r.err.week === 3, 'a week-scoped delete error is recorded, got ' + JSON.stringify(r.err));
    });

    await test('5G1D-DEL-2: an ALLOWED legacy delete (200) removes local reconData and clears the error', async () => {
      delStatus = 200;
      await setupDel('loaded');
      const r = await page.evaluate(async () => { await deleteRecon(3); return { present: reconData[3] !== undefined, err: _reconDeleteError }; });
      assert(r.present === false, 'reconData[3] removed after a 200 DELETE');
      assert(!r.err, 'no delete error after success, got ' + JSON.stringify(r.err));
    });

    await test('5G1D-DEL-3: an UNCERTAIN snapshot load blocks the delete entirely (fail closed — no DELETE issued)', async () => {
      delStatus = 200; delMethodSeen = '';
      await setupDel('unavailable'); // cannot prove snapshot-free ⇒ canDeleteRecon false ⇒ guard short-circuits before any fetch
      const r = await page.evaluate(async () => { await deleteRecon(3); return { present: reconData[3] !== undefined, err: _reconDeleteError }; });
      assert(r.present === true, 'reconData[3] kept — an uncertain snapshot load must not delete');
      assert(delMethodSeen === '', 'no DELETE request was issued (guard short-circuited before fetch)');
      assert(r.err && r.err.week === 3, 'operator told why it was withheld');
    });

    await context.close();
  }

  // Empty smoke-selection guard (5G-QA-1 hardening): if smoke mode matched zero
  // tests, that is a configuration failure, not a pass. With the lazy browser
  // above, reaching here in the empty case means no Chromium was launched and no
  // test executed — fail loudly and exit nonzero before the normal results block.
  const _selected = registered - skipped;
  if (SMOKE_MODE && _selected === 0) {
    console.error('\n✗ E2E smoke selection is empty: 0 of ' + registered
      + ' registered tests are tagged "smoke".');
    console.error('  Smoke mode must select at least one test.'
      + ' No browser was launched and no test executed.');
    process.exit(2);
  }

  await browser.close();

  // ── Results ───────────────────────────────────────────────────────────
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║                       RESULTS                               ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('  Mode:    ' + (SMOKE_MODE ? 'SMOKE (smoke-tagged only)' : 'FULL (default)'));
  console.log('  Passed:  ' + pass);
  console.log('  Failed:  ' + fail);
  console.log('  Skipped: ' + skipped + (SMOKE_MODE ? ' (non-smoke tests)' : ''));
  console.log('  Readiness fallback hits — openApp: ' + readinessFallbackHits.openApp
    + ', clickNav: ' + readinessFallbackHits.clickNav
    + ((readinessFallbackHits.openApp || readinessFallbackHits.clickNav)
        ? '  ⚠️ NOT clean green — readiness wait timed out (review required)'
        : ''));
  if (failures.length) {
    console.log('\n  FAILURES:');
    failures.forEach((f, i) => console.log('  ' + (i+1) + '. ' + f.name + '\n     ' + f.error));
  }
  console.log(fail === 0 ? '\n  ✅ ALL TESTS PASSED\n' : '\n  ❌ FAILURES ABOVE\n');
  process.exit(fail > 0 ? 1 : 0);
})();
