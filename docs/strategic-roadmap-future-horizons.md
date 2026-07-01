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
3. **5I-3** — Test hardening around Wendy workflows
4. **5G-2** — Budget variance clarity
5. **5F-3** — Pending / posted transaction rules *(carries the month-boundary/carryover design item below)*
6. **5G-3** — Reimbursables
7. **5F-4** — Full usable reconciliation workflow

### Guardrail

Do not jump to bank import, AI finance assistant, weekly forecast integration, or broader household OS expansion until there is at least one clean July operating week with Wendy entering transactions.

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

## 4. Explicitly Out of Scope Right Now

- No app code
- No schema or migration work
- No RLS changes
- No tests
- No implementation of any kind

This document exists to capture agreed sequencing and definitions ahead of time. Nothing here is build-authorized.
