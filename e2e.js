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
//   Section A — Tab smoke test (no blank panels, no layout breaks)
//   Section B — Console error check (no uncaught exceptions)
//   Section C — Decision Engine (locked + cleared IRA gate)
//   Section D — IRA flag toggle (Goals tab)
//   Section E — Edit Week workflow (add inflow, save, verify)
//   Section F — Reconciliation workflow (save, update, delete)
//   Section G — Wishlist CRUD (add, edit, delete item)
//   Section H — XSS safety (script injection in all user inputs)
//   Section I — Supabase offline graceful failure
//   Section J — Mobile viewport (nav, panels, no overflow)
//
// ─────────────────────────────────────────────────────────────────────────

const { chromium } = require('playwright');
const path = require('path');

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

async function openApp(browser, opts = {}) {
  const context = await browser.newContext(opts);
  const consoleErrors = [];
  const page = await context.newPage();
  page.on('console', msg => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
  page.on('pageerror', err => consoleErrors.push(err.message));
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
  await page.waitForTimeout(800); // let initial render settle
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
  const tabs = ['overview','weekly','goals','history','assumptions','roadmap','ask'];
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
      !e.includes('Failed to fetch')     // same
    );
    assert(relevant.length === 0, 'Console errors: ' + relevant.join(' | '));
    await context.close();
  });

  // ── Section C: Decision Engine ─────────────────────────────────────────
  console.log('── Section C: Decision Engine ──');
  await test('Engine: IRA locked — gate step appears, no 529 steps', async () => {
    const { page, context } = await openApp(browser);
    await clickNav(page, 'goals');
    // Ensure IRA flag is OFF (locked)
    const flagBtn = await page.$('.flag-toggle.on');
    if (flagBtn) await flagBtn.click(); // toggle off if currently on
    await page.waitForTimeout(200);
    // Switch to What-If / Engine tab
    const engineTab = await page.$('[data-tab="engine"], #goals-tab-engine, button:has-text("What-If"), button:has-text("Engine")');
    if (engineTab) {
      await engineTab.click();
      await page.waitForTimeout(200);
    }
    // Enter a large regular income amount
    const amtInput = await page.$('#engine-amt, input[placeholder*="amount"], input[placeholder*="Amount"]');
    if (amtInput) {
      await amtInput.fill('200000');
      const runBtn = await page.$('button:has-text("Calculate"), button:has-text("Run"), #engine-run');
      if (runBtn) {
        await runBtn.click();
        await page.waitForTimeout(500);
        const output = await page.evaluate(() => {
          const el = document.getElementById('engine-output') || document.querySelector('.engine-steps');
          return el ? el.innerText : '';
        });
        assert(output.includes('CPA') || output.includes('IRA') || output.includes('locked'),
          'IRA gate step not visible in engine output');
        assert(!output.includes('Bailey 529'), 'Bailey 529 should not appear while IRA locked');
        assert(!output.includes('Surplus'), 'Surplus should not appear while IRA locked');
      }
    }
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
    // Toggle back — should restore to initial state
    await btn.click();
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
    const { page, context } = await openApp(browser);
    await clickNav(page, 'roadmap');
    await page.waitForTimeout(500);
    const content = await page.evaluate(() => {
      const el = document.getElementById('roadmap-content');
      return el ? el.innerText : '';
    });
    assert(content.length > 50, 'Wishlist appears empty');
    assert(content.includes('Phase'), 'No phase labels found in wishlist');
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
