# Release 1: trust / household quick wins (frozen candidate, 2026-10-09)

| | |
|---|---|
| Status | **FROZEN CANDIDATE — awaiting owner authorization to push.** Not pushed, not deployed |
| Branch | `production-line-2026q4`. Product commits `c4daf1c` (six items) and `05d4d3f` (Fable review fixes), on top of live `96328a7` (Release 0) and docs `ad4a877` |
| Authority | Owner authorization of 2026-10-09 (six items; the Budget "Statement check" item was dropped) |
| Private evidence | `~/Herndon-Financial-OS-Evidence/release-1-2026-10-09/` (RED/GREEN, mutation run, browser acceptance with screenshots, final validation, December merge preview) |

## The six items

| # | Problem observed | Change | Where |
|---|---|---|---|
| 1 | The sign-in form pre-filled one household member's email | No `value`; `autocomplete="username"` kept so each browser or password manager supplies its own saved identity | `setAuthState` |
| 2 | Household-facing messages sent the user to the console, Supabase, SQL or row ids, and a page render error showed the raw error and stack | Plain household wording. The technical detail moves to `console.error` for Adam. Render-error banner: "⚠ Something went wrong displaying this page. Reload to try again." No collapsed details | `_renderTxAccounts`, `_renderTxCategories`, `_blrRenderModal`, `_blrSaveEdit`, `_budgetSaveTransaction`, the `renderApp` catch |
| 3 | Typing a date into a Register From/To filter: Chrome reports `0002-10-05` after the first year digit, the re-render destroys the field, and the filter is left at year 0002 | While that date field has focus, the value is kept and applied once on blur or Enter. Everything else applies immediately. The pinned `_renderTxRegister` markup is unchanged | `setTxFilter` + new `_txDeferDateFilterWhileTyping` |
| 4 | Ask Claude said the key was "stored encrypted in Supabase" | Footer and key-entry text: "stored, not encrypted, in the household database (visible to signed-in household users) and in this browser". **Wording only; the credential defect stays post-rollover work** (roadmap record) | `renderAskClaude` |
| 5 | A tab left open keeps running an old build after a deploy | New ES module `js/version-check.js` (see below) | `js/version-check.js`, one `<script type="module">` line |
| 6 | FD-3: What-If Apply set an undeclared `activeGoalsTab`, so Goals opened on the wrong tab | `goalsSubTab='engine'` (Goals → Waterfall / Scenarios) | `applyScenario` |

### New-version notice contract (item 5)

- **When it checks:** when the tab becomes visible, and every 15 minutes.
- **How it checks:** it fetches the live page uncached (`cache: 'no-store'` plus a unique query) and reads its `BUILD_TS`.
- **When it shows:** whenever the live `BUILD_TS` **differs** from the running one, whether newer or a rollback. No timestamp ordering is assumed.
- **What it shows:** a non-blocking bar with `role="status"`. It reads "An updated version of the dashboard is available. Reload when you've finished what you're entering." On phones it sits above the bottom nav.
- **Reload:** first asks "Reload the dashboard now? Any unsaved work will be lost."
- **Never** reloads by itself. **Never** takes focus. **Never** re-renders the app.
- **Failures:** a failed check (network error, HTTP error, page without a stamp) is silent and retried at the next trigger.
- **Globals:** none; the mount marker is the `data-hfos-version-check` attribute.
- **Limits:** this is a household UX safeguard only. It is **not** deployment certification and does **not** replace the December stale-client / build-stamp / override controls.

## Not changed

- `runModel`, `reconEffectiveWD`, the WD schedule.
- Closeout, goal-funding authority, commission tax.
- Rollover code.
- Schema, RLS, grants.
- Every protected function: D-1 production baseline PASS 49/49. The 2026 golden is identical.

## Verification (summary; detail in private evidence)

| Check | Result |
|---|---|
| RED on the pre-fix code | 13 regression failures. R1-E1 (real Chromium keyboard) on live `96328a7` reproduces the bug: field replaced, filter `0002-10-05` |
| GREEN on `05d4d3f` | Regression 1993/0. e2e 178/0 (2 prod-verify skipped) |
| Other suites | Release A 62/0. Release B 16/0. D1 26/0. A1b 212/0. G1 32/0. Rollover 49/0. Rollover server 25/0 |
| Pins and golden | Protected pins D1 49/49. Golden identical |
| Mutation | 25/25 mutants killed |
| Browser acceptance | 21/21 PASS: local static server, Chromium, desktop and 375 px phone. Covers deploy, rollback, same build, 500 / dropped / no-stamp failures, focus kept, no auto-reload, confirm declined/accepted, 15-minute interval |
| Independent review (Fable) | APPROVE WITH NON-BLOCKING FINDINGS; fixes in `05d4d3f` |

Accepted non-blocking findings, not fixed:
- **N-2:** after a confirmed reload, GitHub Pages' ~10 min edge cache can still serve the old page, so the notice may reappear once.
- **N-4(a):** the goals-validation banner in `renderApp` still says "Check console". The rollover branch rewrites that line, so it is left for the December merge.
- **N-6:** a date chosen from the calendar picker while the field has focus applies when the user leaves the field. A debounce would bring back the mid-typing re-render for slow typists.
- **N-7:** a deploy followed quickly by a revert can leave a stale notice until the next reload.
- **N-8:** other pre-existing raw `HTTP nnn` messages in Manage Lines.

## Production acceptance (after an authorized push)

1. Confirm the served `index.html` equals the commit blob and carries the new `BUILD_TS`. Confirm `js/version-check.js` is served.
2. Sign out, or use a private window: the email field is empty.
3. Register: type a full date into From, then press Tab. The list filters to that date, and the field shows the full year.
4. What-If: Apply a scenario. Goals opens on Waterfall / Scenarios.
5. Ask Claude (Adam): the footer shows the not-encrypted wording.
6. Version notice: per the owner's ruling, local acceptance is sufficient for now. The first production proof comes at the Release 2 deploy: a tab left open on Release 1 should show the notice within 15 minutes or on returning to the tab.
7. Adam and Wendy each reload once and confirm the new build.

## Rollback

`git revert 05d4d3f c4daf1c` on `main`, then the normal push/deploy and a household reload. No data rollback is needed. Tabs still open on Release 1 will show the notice for the rolled-back build (by design: different build → notice).

## December integration

- Merge preview against `rollover-package-d` (`260169b`): the **only conflict is the `BUILD_TS` line**.
- `e2e.js` and `test_regression.js` auto-merge; `js/` is new.
- Merged suites: regression 1993/0; e2e 178/0; pins (D candidate v2) 49/49; golden identical.
- `test_rollover` shows the same two reds as the Release 0 preview:
  - `PKGD-D2-SRC`: Release 0 labels, already a recorded December requirement;
  - `PKGD-DEPLOY-GUARD`: Package E pending.
- Release 1 adds no new December requirement. When merging, take the rollover side's rewrite of the goals-validation banner text (Fable N-4(a)).
