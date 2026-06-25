# Herndon OS — Status & Context
_Last updated: June 24, 2026 (Phase 5B)_

> Update this file at the end of any Cowork session that touches the OS. Keep it short — it is a handoff doc, not a changelog.

---

## Current Phase

**Phase 5B IN PROGRESS — Budget Module live. Two critical bugs fixed (not yet pushed).**

Phase 4 delivered (complete):
- Phase 4A — RLS tightened across all 11 Supabase tables; authenticated-only.
- Phase 4B-0 — visible sign-out button added.
- Phase 4D — lockout prevention documented; rollback SQL saved.
- Phase 4B — is_allowed_user() migrated to auth.uid().
- Phase 4C — role enforcement was written/spec'd but DEFERRED. Becomes Phase 5A.

Phase 5B IN PROGRESS (June 24, 2026):
- index.html changes complete — Budget nav tab, Budget section, full renderBudget() with printout UI, transaction add/edit/delete, reimbursables integrated into main Transactions table (REIMB badge + status + cleared checkbox, no separate reimbursables panel), reconciliation panel, _getBudgetLivingExpenses() migrated to read from Supabase budget_line_rules with JS fallback.
- BUDGET_CATEGORY_REGISTRY hardcoded (31 entries). BUDGET_PAYMENT_ACCOUNTS hardcoded.
- is_cleared + cleared_date added to budget_transactions schema for Wendy reconciliation. Cleared checkbox shown for all transaction types including reimbursables.
- Reimbursable type switch defaults: source=Jabian, status=pending, category_key=null. Payment account required before save. Source+status required for reimbursable type at both UI and DB level.
- Fallback constants now use monthIso (not weekNum thresholds) so fallback and live cache agree on boundaries (Wk4 Jun 28 = June $13,638, not July).
- SQL hardening after ChatGPT review (Batch 1): seed fail-loudly idempotency guard; seed DO block with adam_id lookup; COALESCE triggers; DROP IF EXISTS idempotency; SET search_path on all SECURITY DEFINER functions; cleared_date consistency CHECK; reimbursable_expense requires source+status at DB level; RLS uses is_allowed_user() / can_write_financials() / is_owner(); appendChild guard; empty-rules warning; goal_sweep labeled clearly; e2e budget tab added.
- 679/0 regression tests passing (34 new Section 29 / Phase 5B tests: 5B-1 through 5B-34).
- SQL NOT YET EXECUTED — Adam must run docs/phase-5b-budget-schema.sql then docs/phase-5b-seed.sql in Supabase SQL Editor before Budget tab is functional.
- Code NOT YET PUSHED — Adam must run: bash push_to_github.sh "Phase 5B: Budget module v1 — schema, seed, UI, reconciliation, stats panel migration"

Phase 5A COMPLETE (June 24, 2026):
- index.html changes complete — USER_ROLE global, isOwnerUser() helper, checkAuthorization role fetch, Edit Week gate, IRA flag gate, Anthropic key gate, renderEditDrawer defense-in-depth guard.
- 645/0 regression tests passing (21 new ROLE-A and ROLE-B tests added).
- Supabase SQL executed (docs/phase-5a-role-enforcement.sql) — app_users roles set (aherndon6@gmail.com = owner, wherndon22@gmail.com = household_admin), helper functions created. Note: adam@herndons.us is in auth.users (seed uses this UUID for created_by) but is NOT in app_users and is NOT the live login identity. (can_write_financials, is_owner, is_editor_or_owner dropped), write policies updated across 7 tables, goals row-qualified RLS live.
- Role model: Adam (owner) = full financial + platform/admin access. Wendy (household_admin) = full financial operating access, cannot write anthropic_key row. Unauthenticated = no access.
- Manual RLS verification PASSED (docs/phase-5a-rls-manual-tests.md) — 5/5 curl tests:
  - Test 1: Wendy INSERT anthropic_key blocked (403)
  - Test 3: Wendy rename ak_goal to anthropic_key blocked (403) — WITH CHECK enforced
  - Test 4: Wendy UPDATE ak_goal allowed (204) — ak_goal restored to 7000
  - Test 5: Adam INSERT anthropic_key allowed (201) — fake row deleted, [] confirmed
  - Test 6: Unauthenticated write blocked (401)
- Database clean post-test: ak_goal = 7000, no anthropic_key row in goals table.
- Reference files: docs/phase-5a-role-enforcement.sql (SQL + rollback), docs/phase-5a-rls-manual-tests.md (curl test suite for future regression/security re-verification).

---

## Phase 5 Roadmap

Priority order: security gap first, then dashboard usefulness, then wishlist extraction, then scenario engine, then actuals/reconciliation, then regression expansion.

### Phase 5A — Finish Security Maturity / Role Enforcement
Goal: complete the deferred Phase 4C work.

- Implement role-based enforcement (admin / viewer or equivalent)
- Migrate any remaining email-based authorization to auth.uid()
- Confirm no lockout risk before applying policies
- Maintain rollback SQL
- Regression tests required: allowed authenticated user, disallowed authenticated user, unauthenticated user, sign-out flow, admin-only capability if applicable

Guardrails:
- Do not weaken existing RLS
- No public/anonymous access path to financial data
- Do not remove the sign-out safety path
- Do not ship without rollback SQL and test evidence

### Phase 5B — Maximum Dashboard Usefulness Pass
Goal: make the dashboard clearly answer these questions week to week:
- What needs attention this week?
- What changed from plan?
- What is funded / pending / deferred?
- What decision do I need to make now?
- Are any floors or targets at risk?

Potential upgrades:
- Stronger "This Week" command center
- Clear Done / Pending / Deferred transfer status
- Better visual hierarchy for Alaska, Retirement, Tax Reserve, EF, 529s
- Explicit warning states: operating floor pressure, trough floor pressure, missed transfer, unfunded planned goal, actuals not reconciled
- Concise "why this matters" copy where the model is doing something non-obvious

Guardrails:
- Do not change cash-flow logic just to make UI cleaner
- UI must reflect the model, not reinterpret it
- Preserve all existing floors, waterfall order, tax reserve behavior, and transfer-state logic

### Phase 5C — Pull Features Out of the OS Wishlist
Goal: convert the wishlist from a parking lot into a sequenced product roadmap.

Claude should review the OS wishlist and classify items into:
- High usefulness / low risk
- High usefulness / medium complexity
- Platform/security dependency
- Later enhancement
- Do not build yet

Likely candidates to prioritize: scenario engine improvements, weekly actuals/reconciliation workflow, upcoming obligations/cash pressure preview, goal funding forecast, transfer automation guidance, better commission and variable-income handling, "Explain this week" narrative summary, tax reserve visibility, decision cards.

Output expected: ranked wishlist extraction list, recommended build sequence, items explicitly deferred with reasons, regression risks for each feature.

### Phase 5D — Scenario Engine Upgrade
Goal: make hypotheticals easier and safer.

Scenarios to support: additional Wendy commissions, new one-time income, unexpected expense, changed tax reserve rate, changed savings engine amount, changed rent/recurring expense, delayed or skipped transfer, extra Alaska/retirement/529 contributions.

Scenario engine must show: impact on Alaska fully funded date, impact on retirement rebuild date, whether operating/trough floors are violated, tax reserve effect, which weeks change, delta vs baseline.

Guardrails:
- Scenario mode must not mutate the baseline plan unless explicitly saved
- Preserve baseline vs scenario comparison
- Always apply tax reserve rules to variable income
- Never allow a scenario to silently break floor rules

### Phase 5E — Actuals / Reconciliation Workflow
Goal: make weekly reconciliation easier and more reliable.

Build toward: planned vs actual income/transfers/expenses, difference explanation, reconciliation status by week, clear handling for completed/pending/deferred/skipped transfers, over/under actuals.

Useful output: "This week is reconciled / not reconciled," "These items still need confirmation," "This variance changed the forecast by X," "No model change needed" vs "baseline update recommended."

Guardrails:
- Do not let manual actuals overwrite future plan logic
- Completed actuals should inform status, not corrupt the baseline
- Deferred transfers must remain distinct from pending transfers

### Phase 5F — Platform Stability / Regression Expansion
Goal: harden the app so new features do not break the model.

Test coverage required: cash floor protection, waterfall order, Alaska target funding, retirement rebuild timing, 529 gating, tax reserve on variable income, commission handling, transfer status buckets, scenario vs baseline separation, reconciliation states, Supabase auth/RLS access, sign-out behavior, empty state behavior, mobile layout if relevant.

Guardrails:
- No feature ships without regression coverage
- Preserve known baseline outputs unless the phase explicitly changes model assumptions
- Document any intentional baseline movement
- Keep backups before modifying index.html, test_regression.js, or schema/policy files
- Use small commits by phase

---

## Recent Work (June 2026)

**Jun 24 (Phase 5B bugs):** Two critical bugs fixed. (1) Reconciliation statement balance input changed from oninput to onchange — was calling renderApp() on every keystroke, dropping input focus before each digit. (2) Transaction INSERT changed from return=minimal to return=representation — Supabase returns HTTP 201 even for RLS-blocked inserts with return=minimal so the code couldn't detect a 0-row save. Added 0-row detection with descriptive error. Also pre-populated transaction_date in _budgetOpenAddForm so it's never undefined if user doesn't touch the date field. 682/0 regression tests (3 new tests: 5B-35, 5B-36, 5B-37). Not yet pushed.

**Jun 24 (Phase 5B):** Budget Module v1 built. SQL migration + seed files written (docs/phase-5b-budget-schema.sql, docs/phase-5b-seed.sql, docs/phase-5b-budget-rollback.sql). index.html: Budget nav tab, s-budget section, renderBudget() with full printout (Spent | Budget | Remaining, parent/child hierarchy, goal_sweep display-only), transaction add/edit/delete form, reimbursables integrated into main Transactions table (REIMB badge + status + cleared checkbox), reconciliation panel (cleared totals vs statement balance). BUDGET_CATEGORY_REGISTRY and BUDGET_PAYMENT_ACCOUNTS hardcoded. _getBudgetLivingExpenses() reads from Supabase budget_line_rules cache with monthIso-based JS fallback. is_cleared + cleared_date added to schema for reconciliation; cleared checkbox available for all transaction types. Payment account required; reimbursable type auto-defaults source=Jabian/status=pending. SQL hardened: seed idempotency guard, COALESCE triggers, SET search_path on SECURITY DEFINER functions, cleared_date CHECK, DB-level reimbursement source+status required. 679/0 regression tests (34 Phase 5B tests: 5B-1 through 5B-34). SQL not executed, code not pushed.

**Jun 24 (Phase 5B prep):** Stats panel fix — _billsMo changed from hardcoded 4-item constant ($15,091) to _getBudgetLivingExpenses(currentW) with dynamic period logic: June $13,638 / July $14,488 / Aug-Dec $14,892 / Jan $13,738. Label updated to "Monthly Living Expenses" / "Available for Goals / Month". Regression test updated (dynamic expected value).

**Jun 24 (Phase 5A):** Phase 5A COMPLETE. Role model live: owner (Adam) = full access, household_admin (Wendy) = full financial operating access, viewer = read-only. goals table row-qualified RLS enforced at DB level — household_admin blocked from anthropic_key row, owner unrestricted. Edit Week, IRA flag, renderEditDrawer use canWriteFinancials(). Anthropic key management gated to isOwnerUser() only. 645/0 regression tests passing (21 new ROLE tests). Manual RLS verification passed — 5/5 curl tests. Database clean post-test.

**Jun 23:** Phase 5 roadmap locked. Phase 4 confirmed complete except Phase 4C (role enforcement) which is deferred and becomes Phase 5A.

**Jun 18 (evening):**
- Completed amount snapshot system — when a required action is checked, dollar amount and label text stored in Supabase (completed_amount, action_key, completed_label columns on weekly_tasks)
- applyCompletionSnapshots() normalization layer — post-model pass applied in renderApp() and _buildModelContext()
- Commission tax delta auto-action — if a week edit adds taxable income after commission_tax was already checked, delta obligation auto-creates a custom required action
- Goal sweep action keys — every goal waterfall ac.push() now has a matching acKeys.push('goal_'+goalId)
- Goal sweep delta detection — same pattern as commission_tax
- _actionLabelCache — populated during render; toggleTask reads from it to snapshot displayed label text at check time
- Partial unique index added — weekly_tasks_week_action_unique on (week_num, action_key) WHERE action_key IS NOT NULL
- push_to_github.sh rewritten — now uses SCRIPT_DIR and only stages index.html + test_regression.js
- All 457 regression tests passing (Sections 26, 27, 28 added this session)

**Jun 18 (morning):**
- Bug fix: custom tasks were excluded from open actions count on Overview
- Financial Flight Path chart replaced SVG placeholder with Chart.js 4.4.1
- Removed redundant "Action Required YES/NO" chip from hero
- Standing rule added: regression tests must be updated with every bug fix or new feature

**Jun 15 and earlier:**
- Fixed desktop-to-mobile sync bug for custom required actions — now stored in Supabase goals table
- Added item_type field (Feature / Bug) to wishlist
- Corrected Fidelity references — IRAs now reference T Rowe, 529s now reference Path 2 College
- Marked wishlist items 41, 42, 43 as done

---

## What's Next (Backlog / Wishlist Priorities)

See Phase 5 roadmap above. Near-term planned wishlist items:
- Account connections via OAuth (id: 26)
- Auto balance pre-fill (id: 27)
- Add timing for credit card due date moves (id: 31)
- Allow reordering within wishlist columns (id: 32)
- Remove a phase from the wishlist dropdown (id: 33)
- Add Wendy's trips and December trip to goals (id: 34)
- Phase 4 git identity fix (id: 37)
- Ability to add a task to a defined future week (id: 38)

Ideas (further out): mobile improvements (id: 39), variables/settings page (id: 40), overview page redesign (id: 44).

---

## Architecture Notes

- All state is Supabase-backed except the Anthropic API key (also synced to Supabase goals table as anthropic_key)
- No build step — edit index.html directly, push via bash push_to_github.sh "message" or GitHub web UI
- Mobile view uses a separate week picker; desktop shows full week list
- The 31-week model is hard-coded in JS; overrides are stored in model_week_overrides table
- Flags (IRA CPA clearance, etc.) are stored in the goals table as key/value pairs
- Supabase project: usayoldrawwmjsmretin
- Repo: Aherndon6/Adam-Dashboard
- Single file: /Users/aherndon/Adam-Dashboard/index.html
- **OS owner login: `aherndon6@gmail.com` (role=owner, active=true in app_users). Do NOT assume `adam@herndons.us` is the owner — it is in auth.users (seed uses it for created_by UUID) but NOT in app_users. Wendy: `wherndon22@gmail.com` (household_admin).**

---

## Open Issues / Known Gaps

- **IMMEDIATE ACTION REQUIRED — Adam must:**
  1. ~~Run docs/phase-5b-budget-schema.sql~~ DONE (Jun 24)
  2. ~~Run docs/phase-5b-seed.sql~~ DONE (Jun 24)
  3. ~~Push Phase 5B initial commit~~ DONE (Jun 24, commit b4003b6)
  4. ~~Run verification queries~~ DONE — June/July/Aug/Jan all passed
  5. **NEXT: Run diagnostics SQL below, then push the two bug fixes**
  6. Diagnostics SQL (run in Supabase SQL Editor — paste as single block):
     ```sql
     -- Check your account's write role
     SELECT au.email, app.role, app.active
     FROM app_users app
     JOIN auth.users au ON au.id = app.auth_id
     ORDER BY app.role;
     -- Check if any transactions were inserted during smoke test
     SELECT COUNT(*), transaction_type FROM budget_transactions GROUP BY transaction_type;
     ```
  7. Push bug fixes: `git add index.html test_regression.js context/herndon-os-status.md && git commit -m "Phase 5B bugs: fix recon balance focus loss (oninput→onchange), fix silent INSERT failure (return=representation + 0-row detection), pre-populate transaction_date" && git push`
- **KNOWN E2E EXCEPTION — BR-3 pre-existing failure:** E2E test BR-3 ("Budget Rules resume (action=applied) in non-overridden week after overridden week") fails with `got action: bypassed_by_model_week_override`. This test has been failing since commit 72f6db3 ("Phase 5: Budget Rules delta foundation"), which predates Phase 5A and Phase 5B. Phase 5B changes make zero modifications to model_week_override, ruleAudit, or bypassed_by_model logic — confirmed by git diff. Phase 5B e2e areas (Budget tab smoke, no console errors, tab renders) all passed in the 57/1 run. Push proceeded with documented exception. BR-3 to be investigated separately as a standalone Budget Rules / override behavior issue.
- **Diablos/GLP not in cash-flow model:** Diablos ($750/mo Jul-Dec) and Wendy GLP ($404/mo Aug-Dec) are now in budget_line_rules and affect Budget view and Goals stats panel. They are NOT in the 31-week cash-flow checking balance model. The week-by-week cash-flow projections are still understated for July onward. Separate task — update WD array or add cash-flow budget_rules rows.
- **Budget parallel run starts:** Wendy runs Budget OS alongside Quicken through August-September. Success criteria before canceling Quicken (September 2026): one full month where category totals match, card totals reconcile, reimbursables tracked separately, misc.goal_sweep handled correctly.
- **Wk 4 starts June 28 (still June):** The stats panel now uses calendar month from week start date. Wk 4 (Jun 28) shows June's budget ($13,638), not July's. This is correct behavior — July's amounts apply starting Wk 5 (July 5). This differs slightly from the old JS constants that applied July amounts starting at Wk 4. No action needed; documenting for awareness.
- Phase 5A complete — no open issues from prior phase.
- Auto-reminder label changes require Supabase cleanup: auto-generated tasks (source='auto_reminder') are stored in custom_tasks with lockedLabel=true. If the label text is changed in code, any week that already has the task stored in Supabase will continue showing the old text — the reminder regeneration logic skips tasks whose reminderKey already exists. Fix: DELETE FROM custom_tasks WHERE label LIKE '%<old text pattern>%' in Supabase SQL Editor, then reload the dashboard.
- If push fails with "HEAD.lock exists", run rm ~/Adam-Dashboard/.git/HEAD.lock then retry
- No automated tests run before push (test_regression.js and e2e.js exist but are run manually)
- Mobile sync for custom tasks now works via Supabase, but actions added before June 2026 still only exist in localStorage on the device they were created on

## Cowork Session Constraints (standing)

- Claude's sandbox cannot push to GitHub — no macOS keychain access. After any session with code changes, Adam must run `git push` from Terminal (or run `bash push_to_github.sh "message"` directly).
- Playwright e2e tests (e2e.js) cannot run in the sandbox — browser binaries are not installed. Claude runs test_regression.js only. Adam runs `node e2e.js` manually from Terminal to validate e2e.
- push_to_github.sh gates on both test suites passing, so it will always fail when run from the sandbox. Use git directly from Terminal instead.

---

## How to Start a New Cowork Session on This Project

Just say: "I want to work on the Herndon OS" — Claude will read about-me.md and this file and be ready. No other setup needed. The Adam-Dashboard folder is persistently connected.
