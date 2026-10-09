# Release 0: reconciled-week model-edit guard (closed 2026-10-09)

| | |
|---|---|
| Status | **DEPLOYED — PASS · PRODUCTION ACCEPTANCE — PASS · CLOSED** (owner, 2026-10-09) |
| Production commit | `96328a7`, a fast-forward from `42ab2cf` (pushed with `git push origin release-0-reconciled-week-guard:main`) |
| Build | `BUILD_TS` `2026-10-09T10:42:07`. The served `index.html` sha256 `f74de2b3…` equals the commit blob |
| Private evidence | `~/Herndon-Financial-OS-Evidence/release-0-2026-10-09/` (RED/GREEN runs, 12/12 mutants killed, validation, December merge preview, deployment record) |

## Invariant

Once a week is reconciled, the ordinary household UI paths must not alter that week's `model_week_overrides` row. Those paths are:
- Edit Week Save;
- "Remove all edits" (`deleteWeekOverride`);
- What-If Scenario commit.

Previewing a What-If scenario on such a week stays allowed. Goal scenarios and new custom weeks are unaffected. No correction or reopen mechanism was created.

## Design

**Authority.** There are two layers:
- the existing `_weekIsImmutable` rule gives an immediate local refusal;
- at the write boundary, a **fresh read-only `weekly_reconciliations` check** runs under a 10 s overall deadline, so a stale tab cannot rely on stale local state.

**Failure handling.** The check fails closed, with two distinct messages:

| State | Message |
|---|---|
| Known locked | "Wk X is reconciled — its model edits are locked." (pre-anchor weeks say "a locked historical week") |
| Cannot verify | "Couldn't verify that Wk X is open for editing. Nothing was changed. Reload and try again." This is never shown as "reconciled". |

**Save in the drawer.** The drawer Save button goes through a guarded wrapper. The wrapper does four things:
- disables Save in place (no re-render, so unsaved typing is never lost);
- ignores a second Save while the check is pending;
- proceeds only if the **same drawer session for the same week** is still open;
- calls the protected `saveWeekEdits` **byte-identical** (pin `1a508534…`).

**Not changed.** `runModel`, `reconEffectiveWD`, the WD schedule, SQL, schema, RLS, grants, closeout and goal behavior.

## Acceptance (owner, 2026-10-09): PASS

| Check | Result |
|---|---|
| A. Edit Week on reconciled Wk 39 | Lock message; no drawer |
| B. Scenario commit on reconciled Wk 39 | Preview allowed; commit refused with the lock message; week unchanged |
| C. Edit Week on open Wk 40 | Normal drawer; cancelled without saving |
| D. Two devices | Adam and Wendy each reloaded and confirmed the Release 0 build |

## Accepted non-blocking findings (Fable)

- **N1:** a double-click on Scenario commit can send the same idempotent POST twice.
- **N2:** Edit week stays visible on locked weeks; it explains the lock when clicked.
- **N4:** "Wk 54+" labels for custom weeks in the refusal text.
- **N5:** a Save click while a check is pending is ignored without a message.
- **N6:** the pre-existing hazard that any full re-render while editing loses typing; the check latency only widens it.

Do not broaden Release 0.

## Security boundary (explicit)

Release 0 protects the **ordinary household client paths only**. It does **not** provide server-enforced reconciled-week immutability. Direct authenticated REST or devtools writes remain possible. That belongs to **post-rollover GR-1**, together with the explicit correction/reopen design.

## December integration requirement

When Release 0 is merged into the rollover candidate (`rollover-package-d`), two things must happen:
- **Labels:** the two refusal labels must use **Package D's household-week helper** instead of `getCalWeek` (Package D's `PKGD-D2-SRC` rule).
- **Conflict:** the only merge conflict is the `BUILD_TS` line, as previewed on 2026-10-09.

## Rollback

`git revert 96328a7` on `main`, then the normal push/deploy and a household reload. No data rollback is needed.
