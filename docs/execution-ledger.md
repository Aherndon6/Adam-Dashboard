# Production Execution Ledger

**Role:** History tier of the four-document model. **Append-only.** One line per SQL artifact (or config change touching prod behavior) **ever run against production** — the DR operator's "what has touched prod" index and the close/audit tier's spine.
**Authority:** `docs/roadmap/canonical-roadmap.md` §14 (AF-8). **Rule:** never delete or rewrite a row; corrections are new rows. **Secrets-free, balance-free.**

**`Rerunnable?`** — `NO` marks a one-shot that must **never** be rerun (e.g. a plain `INSERT` with no `ON CONFLICT` that would raise a UNIQUE violation on rerun). These are quarantined by convention now; the DOC-3 reorg will move executed one-shots under `docs/sql/executed/` so the quarantine becomes structural.

| Date | Artifact (file) | Commit | Target project | Rerunnable? | Evidence (closeout doc) |
|---|---|---|---|---|---|
| 2026-07-09 | `docs/phase-5g-1c-2-migration.sql` (E1 DDL: `goal_funding_snapshots` + RPC) | (E1) | prod `usayoldrawwmjsmretin` | NO (DDL create) | `docs/phase-5g-1c-2-e1-*` |
| 2026-07-11 | `docs/phase-5g-1c-2-seed-anchor.sql` (E2 first-anchor seed, 9 rows) | (E2) | prod `usayoldrawwmjsmretin` | NO | `docs/phase-5g-1c-2-e2-closeout-2026-07-11.md` |
| 2026-07-11 | `docs/phase-5g-1c-2.1-prod-holding-correction.sql` (2 Week-5 `correction` rows) | `b863266` | prod `usayoldrawwmjsmretin` | **NO — never rerun** (plain INSERT, no ON CONFLICT) | `docs/phase-5g-1c-2.1-hotfix.md` |
| 2026-07-13 | `docs/phase-5g-1d-migration.sql` (Slice 6 inert deploy: 2 SECURITY DEFINER functions) | (Slice 6) | prod `usayoldrawwmjsmretin` | NO (DDL create) | `docs/phase-5g-1d-slice6-closeout-2026-07-13.md` |

*This is a seeded starting index reconstructed from committed closeouts — verify each row against its closeout before relying on it, and append every future production execution. Not a substitute for the closeout docs; a one-line index over them.*

---

*Append-only. Secrets-free, balance-free. New session appends; never edits prior rows.*
