# Codex Status: Herndon Financial OS

## Current Phase

Phase 5B complete.
Budget Module v1 live.
Wendy live-use target: July 1, 2026.

## Current Goal

Prepare the system for Wendy using the Budget tab in live household workflow while preserving platform stability, RLS security, and reconciliation accuracy.

## Recent Verified State

- Regression tests: 687/0 passing
- E2E tests: 63/0 passing
- Dashboard stable
- GitHub Pages deploys from main

## Do Not Break

- Adam/Wendy role model
- RLS protection
- Budget transactions
- Reimbursable behavior
- Reconciliation panel
- Existing Quicken parallel-run workflow

## Next Candidate Work

1. Finish Phase 5E-7.
2. Prepare Phase 5E-8.
3. Resolve or quarantine BR-3.
4. Add Diablos/GLP into WD cash-flow projection.
5. Improve Wendy usability only after core logic is safe.

## 5E-8 CLOSED: Register Category Sync (2026-07-02)

Live-use bug: Register's Add Transaction category dropdown/row display didn't match Budget's categories (Wendy-facing, reported live). Root-caused and resolved across three rounds:

1. **Code fix** (commit 238b245, confirmed live at the 10:00 AM build) — Register sources categories from live `_categoriesCache` (normalized via `_normalizeCatRow`) with month-aware label resolution via new `_getRegisterCategoryLabel()`, deliberately NOT `_getActiveCategoryRegistry()`/`BUDGET_CATEGORY_REGISTRY` (that registry is scoped to Budget's fixed 31 lines and gated behind `FEATURE_FLAGS.useSupabaseRegistries`, false in production). Also: `transaction_date` field now triggers a re-render (dropdown labels are month-derived; date input switched `oninput`→`onchange`).
2. **Root cause of the remaining live gap** — a DATA gap, not code. `entertainment.event_1/event_2/week_1-4` were seeded into `budget_line_rules` for July (`docs/phase-5e-6-migration.sql`) but never inserted into `categories` (`docs/phase-5d-1-migration.sql` only seeded 4 static Entertainment leaves — birthday_dinner/brunch/big_dinner_out/entertainment_other). Register can only offer categories that exist in `categories`.
3. **Data-only correction — EXECUTED AND VALIDATED (2026-07-02)**: `docs/2026-07-02-register-budget-category-sync.sql` (preflight → preview → guarded INSERT, entertainment-pattern-scoped, `ON CONFLICT DO NOTHING` only, no UPDATE/DELETE/schema/RLS). Adam ran preflight + insert + validation in production. Confirmed results: `still_missing=0`; all 6 new rows `leaf=true`/`active`/`assignable=true`; parent/group rows remain non-assignable; no duplicate/near-duplicate keys; `entertainment.*` now shows 10 active child rows. Live Register dropdown for a July 2 AMEX Gold transaction confirmed showing Seattle / Wewe's Lunches / Entertainment Week 1-4, alongside the original 4 real Entertainment categories and other existing live categories (Net Salary, Deep South Commissions, Auto Payment, Gas & Fuel), with "Entertainment" itself correctly not selectable.

Reusable future guard drafted (not applied to anything today): `docs/validation-blr-category-sync.sql` — copy-paste template for future budget/category migrations to run as their last step, encoding the rule "any active `budget_line_rules.category_key` for an operating month must exist in `categories` first." Also logged in `AGENTS.md` Known Gaps + Wishlist ID 39 (FK from `budget_line_rules.category_key`→`categories.key` considered but NOT added — needs a historical/legacy BLR row audit first).

Test status: static regression 1039/1039 passing. `5E8-R1`–`R20`, `R22` all reflect the confirmed post-fix production state (temporary diagnostic tests `5E8-R18`/`R19` and e2e `RG-7c`, which previously asserted the pre-fix data-gap-limited state on purpose, are now flipped to assert Seattle/Wewe's Lunches/Week 1-4 resolve, existing categories are preserved, and parent/group rows stay non-assignable). New end-to-end test `5E8-R22` calls `_renderTxRegister()` directly and reproduces Adam's exact confirmed live result. e2e.js Reconciliation selector was also widened this round (unrelated pre-existing gap, not a Register regression) — pending Adam's e2e re-run for final confirmation.

5E-8 is fully closed pending Adam's e2e.js re-run. 5F-1 remains gated behind 5E-7 and 5E-8 per the existing rule below — with 5E-8 now closed (contingent on e2e confirmation), that gate condition is satisfied, but 5F-1 should not resume without Adam's explicit go-ahead in a future session.

## 5F-1 Handoff (next session)

- 5F-1 v3.12 is build-ready but NOT started.
- Build remains gated behind 5E-7 and 5E-8 per the spec. Do not start until both are complete and committed.

Tomorrow afternoon build sequence:
1. Run preflight SQL.
2. Migration + validation SQL (all checks green before proceeding).
3. Implement all 116 ACs in `test_regression.js` before any UI.
4. Then build the 4-phase reconciliation UI.
5. Week 3 $10,265.40 smoke gate is hard go/no-go, run against staging.

- Use the re-grepped regression baseline per AC-76, not any stale 832 count.
- Prose spec stays frozen unless implementation surfaces an actual failing AC or a cash-safety defect.
- UI carryover: Phase 2 current-week protected WD prompts have no hard completion gate (ignored prompts rely on backfill detection). Do not redesign. Make protected prompts hard to miss and make backfill / Review Required warnings prominent.

## Post-5F-1 Build Path & Strategic Horizons

See `docs/strategic-roadmap-future-horizons.md` for the agreed post-5F-1 build order (5F-2, 5G-1, 5I-3, 5G-2, 5F-3, 5G-3, 5F-4) and the longer-term Strategic Roadmap (bank integration, AI assistant, financial planning/retirement layer, household OS expansion — documentation only, not build-authorized). Guardrail: no bank import, AI assistant, forecast integration, or household OS expansion work until one clean July operating week with Wendy is complete.

## Codex Operating Rule

Before editing, Codex should perform a read-only orientation against:
- `/Users/aherndon/AI-Context/00-README.md`
- `/Users/aherndon/AI-Context/02-working-style.md`
- `/Users/aherndon/AI-Context/05-financial-os-context.md`
- `/Users/aherndon/AI-Context/08-open-items.md`
- `AGENTS.md`
- `CODEX_STATUS.md`

Codex should not change files until it confirms the active goal, affected files/functions, intended tests, and risk areas.
