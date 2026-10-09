// ════════════════════════════════════════════════════════════════════════════
// Release 1 (2026-10-09): new-version notice — a household UX safeguard only.
//
// When the tab becomes visible, and every 15 minutes while it is open, fetch the live page uncached and
// compare its build stamp with the build this tab is running. If they DIFFER (a newer deployment or a
// rollback — no timestamp ordering is assumed), show a non-blocking notice with a Reload action that first
// warns unsaved work will be lost. It never reloads by itself and never takes focus. A failed check is
// silent and is simply retried at the next trigger. It is NOT a deployment-certification mechanism and does
// not replace the rollover's explicit stale-client / build-stamp / override controls.
// ════════════════════════════════════════════════════════════════════════════
export const VERSION_CHECK_INTERVAL_MS = 15 * 60 * 1000;

// The build stamp written into index.html by the pre-commit hook.
export function extractBuildTs(html) {
  const m = /const BUILD_TS='([^']+)'/.exec(String(html == null ? '' : html));
  return m ? m[1] : null;
}

// "Different build" is the authority: never assume newer timestamps sort later.
export function isDifferentBuild(running, live) {
  return typeof running === 'string' && running !== '' && typeof live === 'string' && live !== '' && live !== running;
}

// env: { running, url(), fetch(url, opts), showNotice(liveStamp), confirm(message), reload() }
export function createVersionCheck(env) {
  let shown = false, inFlight = false;
  async function check() {
    if (shown || inFlight) return;
    inFlight = true;
    try {
      const base = env.url();
      const r = await env.fetch(base + (base.indexOf('?') >= 0 ? '&' : '?') + 'hfos_version_check=' + Date.now(), { cache: 'no-store' });
      if (!r || !r.ok) return;
      const live = extractBuildTs(await r.text());
      if (isDifferentBuild(env.running, live)) { shown = true; env.showNotice(live); }
    } catch (e) {
      // silent: retried at the next trigger
    } finally {
      inFlight = false;
    }
  }
  function reloadClicked() {
    if (env.confirm('Reload the dashboard now? Any unsaved work will be lost.')) env.reload();
  }
  return { check, reloadClicked, isShown: () => shown };
}

// Browser wiring (skipped when the module is loaded for tests).
if (typeof window !== 'undefined' && typeof document !== 'undefined' && !window.__hfosVersionCheck) {
  const vc = createVersionCheck({
    running: (typeof BUILD_TS !== 'undefined') ? BUILD_TS : null,   // the classic script's build stamp
    url: () => location.pathname || '/',
    fetch: (u, o) => fetch(u, o),
    confirm: (m) => window.confirm(m),
    reload: () => location.reload(),
    showNotice: () => {
      if (document.getElementById('hfos-version-notice')) return;
      const bar = document.createElement('div');
      bar.id = 'hfos-version-notice';
      bar.setAttribute('role', 'status');
      bar.setAttribute('aria-live', 'polite');
      bar.style.cssText = 'position:fixed;left:50%;bottom:16px;transform:translateX(-50%);z-index:9999;max-width:calc(100% - 32px);'
        + 'background:#1e293b;color:#fff;border-radius:10px;padding:10px 14px;font:13px/1.4 system-ui,sans-serif;'
        + 'box-shadow:0 6px 20px rgba(0,0,0,.25);display:flex;gap:12px;align-items:center;flex-wrap:wrap';
      const msg = document.createElement('span');
      msg.textContent = 'An updated version of the dashboard is available. Reload when you\'ve finished what you\'re entering.';
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.textContent = 'Reload';
      btn.style.cssText = 'background:#fff;color:#1e293b;border:0;border-radius:6px;padding:5px 12px;font-weight:600;cursor:pointer';
      btn.addEventListener('click', () => vc.reloadClicked());
      bar.appendChild(msg); bar.appendChild(btn);
      document.body.appendChild(bar);
    },
  });
  window.__hfosVersionCheck = vc;
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') vc.check(); });
  setInterval(() => { vc.check(); }, VERSION_CHECK_INTERVAL_MS);
}
