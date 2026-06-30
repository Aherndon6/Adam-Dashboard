# Phase 5E-8 Smoke Checklist — Wendy 7/1 Operating Readiness

Manual browser smoke run by Adam against the live deployed build (dashboard.herndons.us) after b1fc82d/7760d2a were pushed and GitHub Pages redeployed. Footer confirmed at Jun 30, 2026 · 3:15 PM during this pass.

Two sessions: Wendy (household_admin) and Adam (owner). Plus a July budget readiness check on live data.

---

## Wendy household_admin smoke

| ID | Check | Result |
|---|---|---|
| W1 | Login works | PASS |
| W2 | Current Register loads; default account = Truist Checking | PASS |
| W3 | Add manual transaction | PASS |
| W4 | Edit manual transaction | PASS |
| W5 | Toggle cleared, persists | PASS |
| W6 | Delete test transaction, cleanup complete | PASS |
| W7 | Budget page loads; June 2026 displayed | PASS |
| W8 | Budget Line Admin / Manage Lines opens for Wendy | PASS |
| W9 | Ask Claude owner-only after deploy — no chat box, no Send, no API key input | PASS |
| W10 | Weekly task/note workflow works, cleanup completed | PASS |

W9 initially failed on first pass (stale deployment — see Deployment Note below). Re-tested after `git push origin main` and a hard refresh; passed clean against the live build.

## Adam owner smoke

| ID | Check | Result |
|---|---|---|
| A1 | Login / live build; footer Jun 30, 2026 · 3:15 PM | PASS |
| A2 | Adam sees Ask Claude owner controls / API key setup | PASS |
| A3 | Register loads; default account = Truist Checking; Add Transaction visible | PASS |
| A4 | Budget Line Admin opens for Adam | PASS |

## July budget readiness

| ID | Check | Result |
|---|---|---|
| J1 | July 2026 budget loads | PASS |
| J2 | July Entertainment total = $1,500 (Seattle $300, Wewe's Lunches $200, Week 1–4 = $250 each) | PASS |
| J3 | June Entertainment remains legacy $1,500, no child breakout | PASS |

No June/July Entertainment double-count detected. Budget is balanced: Income $15,938 − Total Planned $15,938 = $0.

---

## Deployment note (resolved during this phase)

First W9 pass surfaced a stale-deployment symptom: Ask Claude showed the chat input/Send button to Wendy instead of the owner-only message, and the footer read Jun 29, 2026 · 9:49 AM. Root cause: `origin/main` was 2 commits behind local (`7760d2a` 5E-7 role enforcement, `b1fc82d` BLR RLS alignment had not been pushed). The committed code was already correct — `renderAskClaude()`'s non-owner branch returns before any chat/input/send markup is built (landed in `7760d2a`). This was a deploy gap, not a code defect. Adam pushed `origin main` directly (no `push_to_github.sh`, no new commit, no code change) and GitHub Pages redeployed. W9 then passed against the live build.

## Known readiness limitation: Register starting balances

- Schema already supports this: `accounts.starting_balance`, `starting_balance_as_of`, `starting_balance_source`, `starting_balance_note` (added in Phase 5D-1).
- All 14 seeded accounts have `starting_balance = NULL` by design — the 5D-1 migration and Phase 5C discovery doc both specify this is captured manually at go-live (7/1/26), not during discovery or build.
- No in-app UI exists to set it (Accounts is read-only in the app); it requires a direct SQL `UPDATE` against `accounts`, owner-only per RLS (`accounts_update_owner`, `is_owner()`).
- Effect: Register running balances currently anchor from $0.00 and show an explicit "Starting balance not set" warning. This is the app's documented fallback behavior, not a crash or silent wrong number.
- Status: Budget is ready. Transactions CRUD / activity capture is ready. Register running balances are not ready for trust/use until starting balances are set.
- This is a manual owner data-readiness task, not a code blocker. Adam will capture online account balances and set starting balances the morning of 7/1, before Wendy relies on register balances for reconciliation-adjacent decisions.

## Known limitations (documented, not in scope for 5E-8)

- No transaction splits (`transaction_splits` table not built)
- No transfers (transfer pairing / `transfer_group_id` not built)
- No imports (Phase 5J, not started)
- No full reconciliation workflow (Phase 5F-1/5F-2, not started)
- No cash commitment / available-surplus engine yet (Phase 5F-1 scope, not started)
- Register starting balances not yet set (see above — manual owner task, planned for 7/1 morning)
- 5F-1 not started; this phase did not touch cash commitments, reconciliation lifecycle, transfer architecture, imports, splits, or `runModel`

---

## 5E-8 Gate

- [x] All Wendy WC-equivalent checks pass (W1–W10)
- [x] All Adam AC-equivalent checks pass (A1–A4)
- [x] July budget readiness checks pass (J1–J3), no double-count
- [x] Deployment mismatch found during smoke (W9) diagnosed and resolved — code unchanged, push-only fix
- [x] Regression suite: `node test_regression.js` — 904 passed / 0 failed
- [ ] Starting balances set for in-scope accounts — **pending, owner task, targeted for 7/1 morning before Wendy relies on register balances**
- [x] No app code changes made this phase
- [x] No schema/RLS changes made this phase
- [x] 5F-1 not started

**Status: Smoke passed. Conditionally ready — pending 7/1 starting balance setup (manual, owner-only, non-blocking for Budget/Transactions use).**

**Sign off:** Adam Herndon · Date: 2026-06-30
