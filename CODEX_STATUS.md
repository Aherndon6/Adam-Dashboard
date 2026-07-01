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
