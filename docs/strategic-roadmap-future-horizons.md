# Herndon Financial OS — Strategic Roadmap & Future Capability Horizons

**Status:** Documentation only. No app code, schema, RLS, or tests. No implementation authorized.
**Date:** Jul 1, 2026

---

## Numbering note

This document uses letter labels (A–D) for long-term strategic horizons. These are **not** a renumbering of existing Phase 6A / 6B work. Phase 6A (Goal Registry read-only foundation) and Phase 6B (Goal Registry write capability), as defined in `stabilization-roadmap-spec.md` and `phase-6a-goal-registry-spec.md`, remain unchanged and keep their current labels. Do not conflate the two numbering tracks.

---

## 1. Post-5F-1 Agreed Build Path

Once Phase 5F-1 is built and committed, the agreed near-term build order is:

1. **5F-2** — Quicken parallel-run comparison, read-only
2. **5G-1** — Wendy daily transaction-entry polish
3. **5I-0** — Local operator workflow hardening *(see Section 4 for full definition)*
4. **5I-3** — Test hardening around Wendy workflows
5. **5G-2** — Budget variance clarity
6. **5F-3** — Pending / posted transaction rules *(carries the month-boundary/carryover design item below)*
7. **5G-3** — Reimbursables
8. **5F-4** — Full usable reconciliation workflow

Beyond this list, **5I-4 — Architecture modernization plan** (Section 4) comes later still: after 5I-3 test hardening, before any frontend modularization, and well before any framework migration decision.

### Guardrail

Do not jump to bank import, AI finance assistant, weekly forecast integration, or broader household OS expansion until there is at least one clean July operating week with Wendy entering transactions.

Do not refactor architecture during the 5F-1 / Wendy adoption window. Do not rewrite the app now. Do not move off Supabase now. Do not move hosting now. See Section 4 for the full architecture modernization guardrail.

### Design backlog item — month-boundary / carryover charge treatment

**Captured:** Jul 1, 2026, during the AMEX Gold starting-balance correction (5E-8 Wendy readiness).
**Target phase: 5F-3 (Pending / posted transaction rules).**

Reasoning: the underlying problem is exactly what 5F-3 is scoped to solve — the relationship between `posted_date` and the date a charge should count against for budget purposes. It is a data-model and workflow question, not a display question, so it belongs in 5F-3 rather than 5G-2 (Budget variance clarity), which is about presenting variance once the underlying numbers are already correct. 5G-2 may end up consuming this once 5F-3 ships (e.g., surfacing carried-over charges in variance views), but the mechanism itself is 5F-3's job.

Problem: end-of-month charges regularly post in one calendar month but belong to the next month's budget (e.g., the AMEX Gold Diablos/Fandango case on 7/1/26, corrected via one-off starting-balance adjustment).

Future rule:
- Starting balances are go-live anchors, not a recurring monthly adjustment tool. Do not solve recurring month-boundary cases by editing `starting_balance`.
- Build a proper workflow for "posted in prior month, assigned to next month's budget" using the existing distinction between transaction date / budget date and posted date.
- `posted_date` already exists on `public.transactions` but is not currently wired into any budget or reconciliation logic. Do not rely on it until 5F-3 formally defines its behavior.

---

## 2. Strategic Roadmap / Future Capability Horizons

These are long-term horizons beyond the 5F/5G/5I build path above. Sequencing among them is not yet locked except where noted below.

- **A. Bank integration readiness**
- **B. AI assistant usefulness**
- **C. Financial planning / retirement planning layer**
- **D. Broader household operating system expansion**

### Priority note: C before D

Financial planning / retirement planning (C) should come before broader household OS expansion (D). C is a natural extension of Budget + Transactions — it draws directly on data the system already has: household actuals, balances, savings behavior, retirement contributions, emergency reserves, 529s, tax reserves, and major goals. D is valuable but broader, with more product-sprawl risk, so it stays later.

---

## 3. Horizon C Definition — Financial Planning / Retirement Planning Layer

The long-term owner-facing planning layer that connects household actuals, savings behavior, retirement contributions, emergency reserves, 529 funding, tax reserves, annual surplus waterfall, and major goals into one financial planning dashboard.

### Potential submodules

- Net worth / account snapshot
- Retirement contribution tracker
- Coast FI / retirement runway model
- Emergency fund / reserve health
- College / 529 planning
- Annual surplus waterfall
- Scenario planner for income, bonus, rent, travel, 529, and retirement contribution changes

---

## 4. Platform / Architecture Roadmap Items

Future phases, not active work. Captured Jul 1, 2026, ahead of the 5F-1 build session, per explicit instruction not to refactor architecture during 5F-1 / Wendy adoption.

### 5I-0 — Local Operator Workflow Hardening

**Purpose:** Make Adam's local commit/push process safer and easier.

**Problem:**
- `push_to_github.sh` is not consistently available from Terminal unless called correctly.
- Claude/Codex sandbox can prepare files but may fail on commits due to permission/`index.lock` issues.
- There are intentionally untracked files (e.g. `docs/phase-5f-1-spec.md`), so `git add -A` is risky.
- Adam is often running multiple manual commands and handling lock files by hand.

**Future scope:**
- Create a safe local commit/push script.
- Script stages only explicitly passed files — never `git add -A`.
- Script detects `.git/index.lock` and stops with clear instructions rather than guessing.
- Script shows `git status` before and after.
- Script commits with a provided message and pushes to `origin/main`.
- Script preserves intentionally untracked files unless explicitly included.
- Standard operating model: Claude prepares/reviews files; Adam runs the final local commit/push.

**Example future command shape:**
```
./scripts/safe_commit_push.sh "docs: message here" file1 file2 file3
```

### 5I-4 — Architecture Modernization Plan

**Purpose:** Create a deliberate path for Herndon Financial OS to become Herndon Household OS without a risky rewrite.

**Current architecture:**
- Static app hosted at dashboard.herndons.us
- Supabase backend/auth/data/RLS
- Large single-file frontend centered on `index.html`
- Regression/e2e test scripts

**Assessment:** This architecture is acceptable for the current Financial OS launch and Wendy adoption window, but it will not scale cleanly forever as the OS expands into retirement planning, household planning, travel, documents, family tasks, AI, and future bank/import capabilities.

**Future target direction:**
- Keep Supabase as the backend for now.
- Keep current hosting for now unless there is a specific reason to move.
- First stabilize Budget + Transactions + Reconciliation.
- Then improve tests.
- Then document a target architecture.
- Then gradually modularize the frontend.
- Only later consider framework migration, such as Vite/React or Next.js.

**Target architecture concepts:**

*Frontend:*
- Modular components
- Feature folders for budget, transactions, reconciliation, planning, goals, household, admin
- Shared utilities for Supabase, auth, roles, money, dates
- Eventually TypeScript, if/when the app is migrated

*Backend/data:*
- Supabase Postgres
- Supabase Auth
- RLS
- Migrations
- Audit logs
- SQL views/RPC functions for financial calculations where useful

*Future server-side layer:*
- Only when needed for AI, bank integrations, scheduled jobs, imports, or secrets.
- Possible options: Supabase Edge Functions, Vercel/Netlify serverless functions, or a small backend.

**Sequencing guardrail:** Do not refactor architecture during the 5F-1 / Wendy adoption window. Do not rewrite the app now. Do not move off Supabase now. Do not move hosting now.

**Recommended order:**
1. Finish 5F-1.
2. Complete 5F-2 Quicken parallel-run comparison.
3. Complete Wendy daily transaction-entry stabilization.
4. Add 5I-0 local operator workflow hardening.
5. Add 5I-3 test hardening.
6. Then create 5I-4 architecture modernization plan.
7. Later: careful frontend modularization with no behavior change.
8. Much later: framework migration only if justified.

**Principle to preserve:** The current setup is good enough for launch, but not the final Household OS architecture. Stabilize first, modularize later, rewrite last if needed.

---

## 5. Explicitly Out of Scope Right Now

- No app code
- No schema or migration work
- No RLS changes
- No tests
- No implementation of any kind

This document exists to capture agreed sequencing and definitions ahead of time. Nothing here is build-authorized.
