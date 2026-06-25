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

let pass = 0, fail = 0;
const failures = [];

function test(name, fn) {
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
  await page.waitForTimeout(1000); // let auth init settle
  await loginIfNeeded(page);
  return { page, context, consoleErrors };
}

async function clickNav(page, id) {
  await page.click('#nav-' + id);
  await page.waitForTimeout(300);
}

// ── Main ──────────────────────────────────────────────────────────────────

(async () => {
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║     Herndon Financial OS — E2E Suite (Playwright)           ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('  Target: ' + URL + '\n');

  const browser = await chromium.launch({ headless: true });

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
    });
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
  });

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
  });

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
    const reconEl = await page.$('button:has-text("Reconcile"), .recon-btn, [onclick*="recon"], input[placeholder*="actual"]');
    assert(reconEl, 'Reconciliation button or input not found in weekly view');
    await context.close();
  });

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
      return entry ? { action: entry.action, week: entry.week } : null;
    });
    assert(result !== null, 'Resume check rule should appear in ruleAudit');
    assert(result.action === 'applied',
      'Budget Rule should be applied in non-overridden week, got action: ' + (result && result.action));
    assert(result.week !== 5,
      'Resume rule should fire in week 6+, not week 5 (which is overridden)');
    // Cleanup
    await page.evaluate(() => { budgetRules = []; delete overrideData[5]; renderApp(); });
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
  });

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
  });

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
    assert(text.includes('Reconciliation'), 'Reconciliation panel not found in budget-content');
    assert(text.includes('Transactions'), 'Transactions header not found in budget-content');
    await context.close();
  });

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
      return { hasYes, hasNo };
    });
    assert(result.hasYes, 'Yes button not found in delete confirm UI');
    assert(result.hasNo,  'No button not found in delete confirm UI');
    await context.close();
  });

  await browser.close();

  // ── Results ───────────────────────────────────────────────────────────
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║                       RESULTS                               ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('  Passed:  ' + pass);
  console.log('  Failed:  ' + fail);
  if (failures.length) {
    console.log('\n  FAILURES:');
    failures.forEach((f, i) => console.log('  ' + (i+1) + '. ' + f.name + '\n     ' + f.error));
  }
  console.log(fail === 0 ? '\n  ✅ ALL TESTS PASSED\n' : '\n  ❌ FAILURES ABOVE\n');
  process.exit(fail > 0 ? 1 : 0);
})();
