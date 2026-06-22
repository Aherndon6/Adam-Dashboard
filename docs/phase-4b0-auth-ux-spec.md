# Herndon Financial OS — Phase 4B-0: Auth UX Hygiene / Visible Sign-Out

**Version:** 1.0
**Date:** June 22, 2026
**Status:** Awaiting approval before build
**Prior closed builds:** Auth v1 (0f98fb3), Wishlist v2 (6fdc7ea), Phase 4A (caece2c)

---

## Problem Statement

AUTH-E2E-5 confirms sign-out works programmatically, but the test bypasses the UI — it calls `doSignOut()` directly via `page.evaluate()`. During Phase 4A manual validation, Adam reported no visible sign-out button in the live dashboard.

Investigation: the button exists. `#signout-btn` is in the topbar HTML, wired to `doSignOut()`, and the auth state machine shows it (`signoutBtn.style.display=''`) when `AUTH_STATE === 'ready'`. The issue is visibility: `font-size:11px`, `color:var(--muted)`, `background:var(--surface2)` makes it blend into the topbar, especially on a dark theme.

The fix is styling, not wiring. AUTH-E2E-5 also needs to be updated to click the actual button element rather than calling the function programmatically.

---

## Scope

**In scope:**
- Improve visual prominence of `#signout-btn` in the topbar
- Add a logged-in user display (email or name indicator) adjacent to sign-out, so the user knows whose session is active
- Update AUTH-E2E-5 to click `#signout-btn` via DOM instead of `page.evaluate(() => doSignOut())`
- Confirm session clears and login form returns after button click
- Confirm re-login works after sign-out

**Out of scope:**
- No RLS changes
- No `is_allowed_user()` changes
- No auth.uid migration
- No role enforcement
- No financial model changes
- No new Playwright sections — AUTH-E2E-5 update only
- No Wishlist changes

---

## Current State

In `index.html`, the topbar right section:
```html
<div class="top-right" id="topbar-right">
  <div class="sync-badge">
    <div class="sync-dot" id="sync-dot"></div>
    <span id="lastReconLabel">Connecting...</span>
  </div>
  <button class="auth-signout-btn" id="signout-btn" onclick="doSignOut()" style="display:none">Sign out</button>
</div>
```

Current CSS:
```css
.auth-signout-btn {
  font-size:11px; font-weight:600; padding:5px 12px;
  border-radius:99px; border:1px solid var(--line2);
  background:var(--surface2); color:var(--muted);
  cursor:pointer; font-family:inherit; transition:all .1s;
}
.auth-signout-btn:hover { color:var(--red); border-color:var(--red); }
```

Problem: `color:var(--muted)` on `background:var(--surface2)` is low contrast in the dark theme.

Current `setAuthState('ready')` in index.html:
```javascript
if(state==='ready'){
  if(overlay)overlay.classList.add('hidden');
  if(signoutBtn)signoutBtn.style.display='';
  return;
}
```

Current AUTH-E2E-5 (calls function directly, does not click the button):
```javascript
await page.evaluate(() => doSignOut());
```

---

## Code Changes

### 1. index.html — Topbar HTML

Replace the current topbar right section to add a user indicator:

```html
<div class="top-right" id="topbar-right">
  <div class="sync-badge">
    <div class="sync-dot" id="sync-dot"></div>
    <span id="lastReconLabel">Connecting...</span>
  </div>
  <div class="auth-user-bar" id="auth-user-bar" style="display:none">
    <span class="auth-user-label" id="auth-user-label"></span>
    <button class="auth-signout-btn" id="signout-btn" onclick="doSignOut()">Sign out</button>
  </div>
</div>
```

Notes:
- The `style="display:none"` moves to the wrapper `#auth-user-bar` instead of the button
- `#auth-user-label` will display the logged-in email (populated by setAuthState)
- The button no longer needs its own inline display style

### 2. index.html — CSS

Replace current `.auth-signout-btn` styles:

```css
.auth-user-bar{display:flex;align-items:center;gap:8px;}
.auth-user-label{font-size:11px;color:var(--muted);max-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.auth-signout-btn{font-size:11px;font-weight:600;padding:4px 10px;border-radius:99px;border:1px solid var(--line2);background:transparent;color:var(--ink);cursor:pointer;font-family:inherit;transition:all .15s;}
.auth-signout-btn:hover{color:var(--red);border-color:var(--red);background:var(--surface2);}
```

Key changes: `color:var(--ink)` instead of `var(--muted)` for legibility. `background:transparent` instead of `var(--surface2)` so it sits cleanly in the topbar.

### 3. index.html — setAuthState('ready')

Update to populate user label and show wrapper:

```javascript
if(state==='ready'){
  if(overlay)overlay.classList.add('hidden');
  var userBar=document.getElementById('auth-user-bar');
  var userLabel=document.getElementById('auth-user-label');
  if(userBar)userBar.style.display='flex';
  if(userLabel){
    _supabase.auth.getSession().then(function(s){
      var email=s&&s.data&&s.data.session&&s.data.session.user&&s.data.session.user.email;
      if(email)userLabel.textContent=email;
    });
  }
  return;
}
```

Update all sign-out / non-ready states to hide the user bar:

```javascript
var userBar=document.getElementById('auth-user-bar');
if(userBar)userBar.style.display='none';
```

Add to the top of `setAuthState` (before the state-specific branches), replacing the previous `signoutBtn` reference:

```javascript
var signoutBtn=document.getElementById('signout-btn'); // kept for backward compat with AUTH-E2E-1 assertion
```

Note: AUTH-E2E-1 checks `document.getElementById('signout-btn')` — this must remain the button's ID.

### 4. e2e.js — AUTH-E2E-5

Replace `page.evaluate(() => doSignOut())` with an actual button click:

```javascript
// Click the visible sign-out button
const signoutBtn = await page.$('#signout-btn');
assert(signoutBtn, 'AUTH-E2E-5: #signout-btn not found in DOM after login');
const btnVisible = await signoutBtn.isVisible();
assert(btnVisible, 'AUTH-E2E-5: #signout-btn is not visible after login');
await signoutBtn.click();
await page.waitForTimeout(1500);
```

---

## Rollback Plan

This is a CSS and HTML layout change only. Rollback = revert `index.html` to the prior topbar HTML and CSS. No Supabase changes. No SQL.

Rollback trigger: visual regression in topbar, sign-out stops working after the DOM change, or AUTH-E2E-1/5 fail after the change.

---

## Test Gates

| Gate | Target |
|---|---|
| `node test_regression.js` | 623/0 |
| `node e2e.js` (local) | 57/0 |
| AUTH-E2E-1: sign-out button hidden before auth | passes |
| AUTH-E2E-5: clicks visible button, session clears | passes |
| `HFOS_URL=https://dashboard.herndons.us node e2e.js` | 57/0 |

---

## Manual Checklist

- [ ] Load live dashboard, sign in as Adam
- [ ] Confirm `#auth-user-bar` is visible in topbar after login
- [ ] Confirm email label displays correctly
- [ ] Confirm "Sign out" button is clearly visible (not blending into background)
- [ ] Click "Sign out" — login form returns
- [ ] Re-login as Adam — dashboard loads correctly, no console errors
- [ ] Sign in as Wendy in incognito — confirm user label shows Wendy's email
- [ ] Sign out as Wendy — login form returns cleanly

---

## Acceptance Criteria

- [ ] "Sign out" button is clearly visible in the topbar when authenticated
- [ ] Logged-in email is displayed adjacent to the button
- [ ] Clicking the button clears the session and returns to login form
- [ ] Re-login works after sign-out
- [ ] No console errors
- [ ] AUTH-E2E-5 clicks the button element, not `page.evaluate(() => doSignOut())`
- [ ] AUTH-E2E-1 still confirms button is hidden before auth
- [ ] Regression 623/0, local Playwright 57/0, live Playwright 57/0
- [ ] No RLS, auth.uid, model, or Wishlist changes
