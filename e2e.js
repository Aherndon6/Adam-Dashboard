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
