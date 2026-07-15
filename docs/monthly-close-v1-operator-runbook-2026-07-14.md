# Monthly Close v1 — Operator Runbook

**Date:** 2026-07-14 · **Type:** Operator checklist. **Docs only. No implementation authority.** No code, SQL writes, schema, migration, or production change is performed by this runbook — it drives **read-only verification** + **document authoring**.
**Companion spec:** `docs/monthly-close-v1-spec-2026-07-14.md` (definitions, semantics, exclusions). **Balance-free** committed record; dollar figures stay in the local worksheet.
**Who runs it:** Adam (owner), on desktop, with the month's bank/credit-card statements in hand. **Not runnable mid-trip.**

**Pass/fail rule:** every gate below must **PASS** to certify. Any **FAIL** → stop, do not certify, remediate through the weekly/correction path, then re-run. Record the failure in the certification record's "conditions" section either way.

---

## Phase 0 — Preconditions (gate: all PASS)

| # | Check | Expected (PASS) |
|---|---|---|
| 0.1 | 5G-1D activated; wrapper live+granted | Gate B complete; `closeoutState` predicate available |
| 0.2 | Month-bearing weeks identified | The month's week set enumerated (e.g. July → model wk 6/7/8 = Cal Wk 28/29/30) |
| 0.3 | All month-bearing weeks caught up (no skip outstanding) | Each week has a `weekly_reconciliations` row; none skipped/pending |
| 0.4 | Not mid-trip; statements available | Desktop; bank + credit-card statements for the month in hand |
| 0.5 | Pre-close dump taken + verified (DR-1) | Fresh `pg_dump` (`-Fc --no-owner --no-acl`, public schema), `pg_restore --list` OK, chmod 600, SHA-256 recorded, off-device copy verified |

*If 0.1 fails → the month is not closeable yet (activation slipped; §5.6 of the spec). If 0.3 fails → catch up the skipped week(s) first (§5.5).*

## Phase 1 — Completeness & contiguity (gate: all PASS)

| # | Check | Expected (PASS) |
|---|---|---|
| 1.1 | Each month-bearing week `complete` | `closeoutState(n)==='complete'` for every week — no `half_closed`/`corrupt`/`reconciled-only` |
| 1.2 | Contiguity | No gap in the month's week sequence (a skipped/missing week = FAIL) |
| 1.3 | Nine snapshots per certified week | Each certified `week_num` has exactly 9 `goal_funding_snapshots`, `source='reconciliation'` |
| 1.4 | Monotonicity / non-decrease intact | Wrapper non-decrease guards hold across the certified weeks (no snapshot regression) |
| 1.5 | Week-5 opening anchor unchanged | 9 `opening_anchor` + 2 `correction` rows at wk 5, unaltered |

## Phase 2 — Grant posture (F-09; gate: PASS or recorded accepted variance)

| # | Check (read-only) | Expected (PASS) |
|---|---|---|
| 2.1 | Wrapper + Option B granted (owner path) | `save_weekly_closeout_with_snapshots` + `correct_goal_funding_snapshot` = owner-executable |
| 2.2 | Old recon RPC revoked | `save_reconciliation_with_commitments` API-role EXECUTE = **false** |
| 2.3 | Repair RPC revoked | `repair_commitments_for_week` = per Gate C posture (revoked/owner-only) |
| 2.4 | Direct snapshot RPC revoked | `save_goal_funding_snapshots` API-role EXECUTE = **false** |
| 2.5 | Snapshot table locked | `goal_funding_snapshots` INS/UPD(/DEL) for API roles = **false** |

*If Phase-2 lockdown is incomplete (a §7 contingency stop state): record an **accepted variance** in the certification record citing the missing lockdown + its expiry (when Phase-2 completes). Do not silently certify over it.*

## Phase 3 — Statement attestation (gate: matched or named variance)

| # | Step | Expected |
|---|---|---|
| 3.1 | Reconcile month-end **checking/savings** balances to statements | Matched (worksheet, local) |
| 3.2 | Reconcile month-end **credit-card / AMEX holding** to statements | Matched, or the standing AMEX-holding **accepted variance** (expires with 5G-1B) is named |
| 3.3 | Attestation outcome recorded | Record states **matched** / **variance-noted** — **no dollar figures committed** |

## Phase 4 — Basis & watermark capture

| # | Step | Expected |
|---|---|---|
| 4.1 | Record the certified week set + as-of month-end date | In the certification record |
| 4.2 | Capture the max server write timestamp across certified weeks | `max(recorded_at/updated_at)` recorded |
| 4.3 | Capture the certification timestamp | Recorded (this is the divergence baseline) |
| 4.4 | Note the late-`recorded_at` nuance (first close) | Catch-up rows carry August `recorded_at` on July weeks — benign; watermark keys on *new writes after certification* (F-03) |

## Phase 5 — Author the certification record

Author `docs/closes/<YYYY-MM>-close.md` (balance-free) with: period · certified week set · as-of date · basis watermark (4.2/4.3) · grant-posture assertion (Phase 2) · attestation outcome (Phase 3) · accepted variances · evidence pointers (worksheet, dump SHA-256, badge/query screenshots — pointers, not values) · derived state · Adam sign-off line.

## Phase 6 — Review, sign, record

| # | Step | Expected |
|---|---|---|
| 6.1 | Adam reviews the record (§6.4 of spec) | Completeness, grant assertion, attestation, watermark, evidence, balance-free — all OK |
| 6.2 | Sign-off | Adam signs + dates → derived state = **CERTIFIED** |
| 6.3 | Commit (docs-only) | `git commit --no-verify` (keeps `index.html`/`BUILD_TS` untouched); no cash-model merge |
| 6.4 | Append to `docs/decision-log.md` | One line: date · "Monthly close <month> certified" · Adam · record link |
| 6.5 | **Do NOT** append to `docs/execution-ledger.md` | No SQL ran against production |

---

## Divergence / reopen / re-certification (as needed)

- **Divergence (§4.9):** a certified week changed after its watermark with no reopen record → state **DIVERGED**. Investigate; record a divergence note; then either reconcile + re-certify (below) or route to remediation. Never leave DIVERGED silent.
- **Reopen (§4.10):** to legitimately change a certified week, author a **reopen record** *first* (week, reason, approver, correction-evidence link) → state **REOPENED**. Perform the change through the owner-only weekly/Option-B path (not this runbook).
- **Re-certification (§4.11):** after the reopened/diverged weeks are corrected and re-verified (Phase 1), author a **new** certification record (append; never edit the prior) with a fresh watermark → state returns **CERTIFIED**.

---

## Dry-run mode (§6.3 of spec)

Run Phases 0–4 over already-closed weeks (e.g. wk 6/7) to validate mechanics. **Author no certification record; commit nothing; sign nothing.** A dry run certifies nothing — it only exercises the checklist and the grant-posture/watermark queries.

---

## Failure quick-reference

| Symptom | Gate | Action |
|---|---|---|
| A month week is missing / skipped | 1.2 | Catch up the week (weekly path), then re-run |
| A week is `half_closed`/`corrupt` | 1.1 | Repair via the weekly half-close repair path, then re-run |
| Snapshot count ≠ 9 | 1.3 | Investigate the weekly closeout; do not certify |
| Old RPC still granted / table not locked | 2.x | Complete Phase-2 lockdown, or record an accepted variance with expiry |
| Statement mismatch beyond accepted variance | 3.x | Reconcile the discrepancy through the register/weekly path first |
| Week-5 anchor altered | 1.5 | Stop — escalate (anchor is not a close-time surface) |

---

*Operator runbook only. Read-only verification + balance-free document authoring; no writes, no SQL, no schema, no production change. Execute per the spec and the canonical roadmap sequence.*
