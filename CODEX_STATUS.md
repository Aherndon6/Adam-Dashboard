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

## Codex Operating Rule

Before editing, Codex should perform a read-only orientation against:
- `/Users/aherndon/AI-Context/00-README.md`
- `/Users/aherndon/AI-Context/02-working-style.md`
- `/Users/aherndon/AI-Context/05-financial-os-context.md`
- `/Users/aherndon/AI-Context/08-open-items.md`
- `AGENTS.md`
- `CODEX_STATUS.md`

Codex should not change files until it confirms the active goal, affected files/functions, intended tests, and risk areas.
