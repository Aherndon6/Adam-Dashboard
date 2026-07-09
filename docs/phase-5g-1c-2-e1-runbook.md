# Phase 5G-1C-2 — E1 Production DDL Execution Gate: Runbook

> **Reviewed artifact (R1).** This file IS the E1 runbook Fable reviews. It is the
> committed reference for the E1 execution gate. **Nothing in this file has been
> executed.** No Supabase access, no SQL, no seed. E1 does not start until the
> approval chain in §0 clears.
>
> Status: **PRE-EXECUTION — awaiting Fable clearance of this file, then Adam's
> in-session execution approval.**

---

## 0. Approval chain — read first (E1 cannot start until this clears)

1. **Fable review gate.** E1 execution **requires Fable review of THIS committed
   runbook file** (`docs/phase-5g-1c-2-e1-runbook.md`) and resolution of every
   correction/finding Fable raises. No preflight, migration, or validation runs
   against production until Fable has cleared this file.
2. **Adam execution approval.** Adam's in-session execution go-ahead comes **only
   after Fable clears this runbook** (and its corrections are resolved). Fable
   clearance is a precondition of, not a substitute for, Adam's approval.
3. **Rollback is excluded from that approval.** Rollback is **never automatic** and
   requires a **separate** in-session approval (see §4), even though E1's rollback
   is empty-table and low-risk.

### Clearance freshness (R4)

Clearance is **not durable**. It lapses and must be refreshed if any of the
following happen after clearance is granted:

- **The session ends** — Fable clearance AND Adam execution approval both lapse.
- **`origin/main` moves** (any new commit) — clearance lapses.
- **This runbook file changes** — clearance lapses; the changed file must be
  re-reviewed.

If clearance has lapsed, return to §0 step 1 before doing anything else.

---

## 1. Scope confirmation — E1 / E2 separation (acceptance criterion 2)

**E1 includes ONLY:**

1. Confirm target = Adam-Dashboard (`usayoldrawwmjsmretin`).
2. Pre-migration schema baseline (pg_dump preferred; documented fallback).
3. Mandatory AI review pack (`scripts/export-ai-review-pack.sh`).
4. Backup / PITR confirmation (STOP condition).
5. Fresh mechanical-diff verification (R2).
6. Pre-migration live-site baseline.
7. Preflight (read-only).
8. Migration (schema-only DDL).
9. Validation (post-migration, pre-seed).
10. Empty-table inert live-site check.

**E1 explicitly EXCLUDES:** first-anchor seed, filling the nine Value-Card
sentinels, the First-Anchor Value Card, seed-validation, E2, and 5G-1D
write-through. **No seed, no Value Card, no seed-validation, no 5G-1D.**

**Source files (committed at `3061644`, all `docs/phase-5g-1c-2-prod-*`):**

- E1 **executes**: `preflight.sql`, `migration.sql`, `validation.sql`.
- E1 **holds in reserve** (break-glass, separately approved — §4): `rollback.sql`.
- **NOT used in E1** (belong to E2): `seed-anchor.sql`, `seed-anchor-validation.sql`
  — both still hold nine `-1` Value-Card sentinels.

**Behavior-inert claim.** The C3 overlay (shipped `c6fbb32`) is inert until snapshot
rows exist. After E1 the relation exists but is EMPTY, so the loader returns zero
rows → `goalSnapData={}` → runModel identity holds (byte-identical to the C1
golden). The **security surface goes live** (table + RPC + RLS + grants); there is
**no rendered behavior change** in the UI.

---

## 2. Step-by-step runbook

### Step 0 — Fable clearance + Adam approval (gate, no execution)

- **Who:** Adam routes this file to Fable; Fable reviews; Adam gives in-session
  execution approval after clearance.
- **Stop condition:** No Fable clearance, unresolved Fable findings, or lapsed
  clearance (§0 freshness) → **do not start any step below.**

### Step 1 — Confirm target = Adam-Dashboard (usayoldrawwmjsmretin)

- **Who:** Adam, manually (Supabase UI; or `psql \conninfo`).
- **Action:** Confirm the project ref reads **`usayoldrawwmjsmretin`** (Adam-Dashboard),
  **not** `pkwotgqivgaapwuqgwqb` (staging).
- **Expected:** Project ref = `usayoldrawwmjsmretin`.
- **Stop condition:** Any other ref or ambiguity → **HALT.**
- **Backstop:** All three executed files also re-check
  `system_identifier = 7632885393857617092` in-SQL and refuse staging.

### Step 2 — Pre-migration schema baseline (acceptance criterion 3)

**Preferred — pg_dump schema-only baseline:**

- **Who:** Adam (requires a live read connection + prod connection string).
  **Claude is NOT assumed to hold production credentials.**
- **Command:**
  ```
  pg_dump "<prod connection string>" \
    --schema=public --schema-only --no-owner --no-privileges \
    -f exports/db-baseline-5G-1C-2-prod-pre-<timestamp>.sql
  ```
  (`pg_dump` is available locally at `/opt/homebrew/opt/libpq/bin/pg_dump`.)
- **Expected:** Schema-only `.sql` under `exports/` that does **not** contain
  `goal_funding_snapshots` or `save_goal_funding_snapshots`.

**Fallback — acceptable ONLY if documented:**

If Adam cannot run pg_dump (no connection string / credential in-session), the
fallback is acceptable **only if all of the following are recorded**:

- **What failed and why** pg_dump was unavailable (explicit note).
- **Supabase dashboard backup/PITR evidence** (from Step 4) captured as the
  restore-point proof.
- **Preflight P6 evidence saved** (Step 7 output) as the schema-shape + object-
  absence proof (P1/P2/P3a–c prove the objects do not pre-exist).

- **Stop condition:** Dump fails/empty or already contains the 5G-1C-2 objects →
  HALT. In the fallback path, if the three documentation items above cannot all be
  produced → HALT.

### Step 3 — Mandatory AI review pack (acceptance criterion 3; local-only)

- **Who:** Claude/local. **Local-only — reads repo files, never touches Supabase.**
  May be run **before Fable review** if desired.
- **Per AGENTS.md this is MANDATORY before migration, not optional.**
- **Command:** `scripts/export-ai-review-pack.sh` → `exports/ai-review-pack-*.md`.
- **Stop condition:** Pack not generated before migration → HALT (mandatory
  pre-migration evidence).

### Step 4 — Backup / PITR confirmation (STOP condition)

- **Who:** Adam, manually (Supabase UI → Database → Backups).
- **Action:** Confirm a recent daily backup and/or PITR restore point predating any
  DDL.
- **Expected:** A confirmed restore point captured before DDL.
- **Stop condition:** **No backup AND no PITR → HALT.** This is a hard STOP
  condition, not advisory. Also serves as the fallback evidence for Step 2.

### Step 5 — Fresh mechanical-diff verification (R2) — local, pre-execution

Prove the production SQL bodies still match the staging-validated bodies, so a
legitimate comment delta is not mistaken for an unexpected schema/body delta.

- **Who:** Claude/local or Adam (local git/diff only; no Supabase).
- **Migration body diff — expected EMPTY:** after stripping the production header +
  `PRODUCTION GUARD` block (and the staging header + staging guard from its
  counterpart), the executable body of
  `docs/phase-5g-1c-2-prod-migration.sql` must diff **EMPTY** against
  `docs/phase-5g-1c-2-migration.sql`.
- **Validation body diff — expected EMPTY EXCEPT the known trailing RPC-coverage
  comment block:** after stripping headers + guards, the body of
  `docs/phase-5g-1c-2-prod-validation.sql` must diff clean against
  `docs/phase-5g-1c-2-validation.sql` **except** for the trailing
  "RPC coverage boundary (PRODUCTION — corrected per Fable)" comment block, which
  is a **known, expected** production-only comment delta.
- **Pinned expected result:**
  - migration → **zero** body-diff lines.
  - validation → diff limited to the trailing RPC-coverage comment block **only**;
    **zero** executable (`SELECT`/`DO`/DDL) differences.
- **Prior verification:** Fable already verified this mechanical diff at **`e45f7c3`**.
  A **fresh** re-run is REQUIRED immediately before E1 execution (origin/main or the
  files may have moved since — see §0 freshness).
- **Stop condition:** Any executable-body difference (migration non-empty, or
  validation differing outside the pinned RPC-coverage comment block) → **HALT**;
  the prod file is out of sync with the validated staging body.

### Step 6 — Pre-migration live-site baseline (compared by Step 10)

- **Who:** Adam, on dashboard.herndons.us (Claude may assist reading).
- **Action — record, before any DDL, with a consistent method (acceptance
  criterion 7):**
  - **Same login** to be used for the post-check.
  - **Hard reload.**
  - **BUILD_TS** noted.
  - **Overview**, **Weekly**, **Goals/Funding**, **Budget**, **Register** tabs load
    and render.
  - **Funding Plan / Funding Timeline** current labels noted
    (e.g. Bailey "Partial in 2026 · Continues in 2027").
  - **Adam IRA timing** noted (e.g. "Cal Wk 29", locked).
  - **Wendy SEP behavior** noted (e.g. "✅ Funded").
  - **Console/network snapshot** noted — expect the C3 loader to **404 quietly** on
    the missing `goal_funding_snapshots` relation pre-migration.
- **Expected:** A written pre-migration reference saved to `exports/` with BUILD_TS.
- **Stop condition:** Site not loading / pre-existing errors → resolve or HALT
  before DDL.

### Step 7 — Preflight (READ-ONLY) — gate before migration (acceptance criterion 4)

- **Who:** Adam, in the Supabase **SQL Editor** (primary) or `psql`.
- **File:** `docs/phase-5g-1c-2-prod-preflight.sql` — run whole, unmodified.
- **Output capture:** save full output to
  `exports/db-baseline-5G-1C-2-prod-preflight-<timestamp>.txt` (see §5). Prefer
  **text output, not screenshots.**
- **Gate — ALL of the following required to proceed:**
  - Guard `DO` block completes with **no exception** (any guard exception STOPS).
  - **`P1`–`P5` all `expected_true = true`** (any not-true STOPS).
  - **`P6` evidence eyeballed** (not just present): `P6-sysid = 7632885393857617092`,
    `P6-txcount ≈ 95`.
  - **Latest reconciled week noted** (`P6-latestrec` / `P6-recweeks`).
  - **Excluded-goal list matches expectation** (`P6-excluded` = auto goal
    `adam_401k` + holding/deferred `wewe_rccl`, `wewe_dcl`, `taxable_etf`).
  - **Fresh mechanical diff clean** (Step 5 pinned result).
  - **Outside Wendy's active Budget-entry hours** (R3).
  - **Same-sitting freshness rule satisfied** (R3 — see §3).
- **Stop condition:** any of the above not met → **HALT, do not run migration.**

### Step 8 — Migration (schema-only DDL, atomic) — gate (acceptance criterion 5)

- **Who:** Adam, in the Supabase SQL Editor, **in the same sitting as preflight** (R3).
- **File:** `docs/phase-5g-1c-2-prod-migration.sql` — run whole, unmodified.
- **Expected:** Guard passes; statements run through `COMMIT` with no error;
  post-commit `M-table = 1`, `M-rpc = 1`; the empty-proof `DO` block
  (`migration.sql:287-292`) does not fire.
- **Gate / stop conditions:**
  - **Any error → STOP.**
  - A **pre-COMMIT failure should persist nothing** (whole txn auto-rolls-back;
    `CREATE`, not `CREATE OR REPLACE`, wrapped in `BEGIN/COMMIT`). Do **not** rerun
    blind — **prove no partial objects by rerunning preflight `P1`–`P3`** before any
    retry (R4).
  - **If the session drops after `COMMIT` but before the M-table/M-rpc sanity
    checks, proceed directly to validation** — validation is the authority (R4).
  - If `M-table`/`M-rpc` ≠ 1 after an apparent commit → HALT.

### Step 9 — Validation (post-migration, PRE-seed) — gate (acceptance criterion 6)

- **Who:** Adam, in the Supabase SQL Editor.
- **File:** `docs/phase-5g-1c-2-prod-validation.sql` — run whole, unmodified.
- **Output capture:** **full validation output captured to `exports/`** as
  `exports/db-baseline-5G-1C-2-prod-validation-<timestamp>.txt` (text, not
  screenshots).
- **Gate — ALL required:**
  - Guard passes.
  - **All V checks `true`** (`V1, V2, V3a/b, V4a–j, V5a/b, V6a–e, V7, V8a–d, V9a–e`).
  - **`V7` empty** (`count(*) = 0`).
  - **`V4f` exact grant set** — authenticated = exactly `{INSERT, SELECT, UPDATE}`.
  - **`V8e` / `V9f` PASS / no exception** (these `DO` blocks `RAISE EXCEPTION` on
    fail; **no exception = pass**; a `NOTICE ... PASS` line is confirmatory but not
    required).
  - **Zero rows written** (V9f additionally proves the unauthenticated caller is
    rejected and the table stays empty).
- **Stop condition:** any V-check ≠ `true`, V8e/V9f exception, or V7 ≠ empty →
  **HALT**; treat as structural defect → §4 (rollback consideration).

### Step 10 — Empty-table inert live-site check (acceptance criterion 7)

- **Who:** Adam, on dashboard.herndons.us (Claude may assist reading), **same login
  + hard reload** as the Step 6 baseline.
- **Expected network delta (defined):**
  - **Before migration:** the C3 loader may **404 quietly** on the missing
    `goal_funding_snapshots` relation.
  - **After migration:** the same request should return **200 with an empty array**.
  - **"Inert" means unchanged RENDERED behavior, NOT identical network traffic.**
    The 404→200(empty) change is expected and correct.
- **Compare against Step 6 baseline** across Overview, Weekly, Goals/Funding, Budget,
  Register; Funding Plan / Timeline labels, Adam IRA timing, and Wendy SEP behavior
  must be **unchanged**. Note post-check BUILD_TS.
- **Stop condition:** any changed rendered number/label vs the Step 6 baseline, or a
  loader error path firing → investigate; a real regression → §4.

---

## 3. Same-sitting freshness + Wendy-hours rule (R3)

- **Preflight and migration must happen in the SAME sitting.**
- **If migration does not immediately follow preflight, RERUN preflight before
  migration** (a stale preflight does not authorize a later migration).
- **Run outside Wendy's active Budget-entry hours.**

---

## 4. Session-interruption handling (R4) + rollback (separate approval)

**Interruption handling:**

- **If any failed run occurs, do NOT rerun blind.**
- **Rerun preflight `P1`–`P3` to prove no partial objects exist** before any retry.
- **If the session drops after `COMMIT` but before the M-table/M-rpc sanity checks,
  proceed directly to validation** — validation is the authority on the committed
  state.
- **If the session ends,** Fable clearance and Adam execution approval **lapse and
  must be refreshed** (§0).
- **If `origin/main` moves or this runbook changes,** clearance **lapses and must be
  refreshed** (§0).

**Rollback — separately approved, never automatic.** E1's rollback is empty-table
and low-risk, **but it is not automatic and is excluded from Adam's execution
approval.** If preflight, migration, validation, or the live-site check fails:

1. **Stop** at the failing step.
2. **Diagnose** (rerun preflight `P1`–`P3` first if a partial-object question exists).
3. **Decide** whether rollback is actually needed (a pre-COMMIT migration failure
   auto-rolls-back and needs no explicit rollback).
4. **Get explicit in-session rollback approval** from Adam.
5. **Only then** run `docs/phase-5g-1c-2-prod-rollback.sql`. With an empty table it
   drops cleanly (its non-empty export refusal will not fire); confirm
   `RB1`–`RB4 = true`.

---

## 5. SQL Editor output capture (practical)

For preflight (Step 7) and validation (Step 9):

- **Save/export the full result output** to `exports/` as text.
- If SQL Editor export is awkward, **copy/paste the raw output into a local `.txt`**.
- **Prefer SQL Editor text output over screenshots.**
- **Capture NOTICE and ERROR messages**, not just the result grid.
- For **`V8e` / `V9f`**: **success = no exception raised and rows remain zero.** A
  `NOTICE ... PASS` line is helpful confirmation but **not required** if no exception
  fired and the table is still empty.

---

## 6. Evidence capture & commit timing (acceptance criterion 8)

**Capture (save under `exports/` with timestamps, LOCAL only during execution):**

- Schema baseline (`db-baseline-5G-1C-2-prod-pre-<ts>.sql`) **or** the documented
  fallback (Step 2).
- AI review pack (`ai-review-pack-*.md`).
- Full preflight output (`db-baseline-5G-1C-2-prod-preflight-<ts>.txt`).
- Full validation output (`db-baseline-5G-1C-2-prod-validation-<ts>.txt`).
- Live pre/post notes **with BUILD_TS** (Steps 6 and 10).

**Commit timing:**

- **Save evidence locally during E1. No automatic evidence commit mid-execution.**
- **Commit evidence only AFTER the execution session ends**, once the evidence has
  been reviewed.
- The evidence commit (`exports/` + any status update) is a **separate docs/evidence
  commit** using **`git commit --no-verify`** (so the pre-commit hook does not
  rewrite `index.html` BUILD_TS).
- `CODEX_STATUS.md` is updated in that post-execution docs commit, not during E1.

---

## 7. Who runs what — summary

| Step | Surface | Runner |
|---|---|---|
| 0 Fable clearance + approval | Review | **Adam + Fable** |
| 1 Confirm target | Supabase UI (or `psql \conninfo`) | **Adam** |
| 2 Schema baseline (pg_dump / fallback) | Local shell → prod, or Supabase UI | **Adam** (Claude does **not** hold prod creds) |
| 3 AI review pack (mandatory) | Local shell, repo files only | **Claude/local — no Supabase** |
| 4 Backup/PITR (STOP) | Supabase UI → Backups | **Adam** |
| 5 Fresh mechanical diff | Local git/diff | **Claude/local or Adam** |
| 6 Live-site baseline | Browser (prod site) | **Adam** (Claude may assist reading) |
| 7 Preflight | Supabase **SQL Editor** | **Adam** |
| 8 Migration | Supabase SQL Editor | **Adam** |
| 9 Validation | Supabase SQL Editor | **Adam** |
| 10 Inert live check | Browser (prod site) | **Adam** (Claude may assist reading) |

- **Steps requiring the Supabase UI:** 1, 4, 7, 8, 9 (7–9 in the SQL Editor; 1/4 are
  console navigation); Step 10 is the live site.
- **Local, safe, no Supabase:** Steps 3 and 5. pg_dump (Step 2) reads prod and needs
  prod credentials → Adam's; Claude is not assumed to hold prod creds.

---

## 8. Acceptance criteria (Fable) — checklist

1. **Approval chain:** Fable clearance of THIS committed file → separate Adam
   in-session approval → rollback excluded, separate approval. (§0, §4)
2. **E1/E2 separation:** E1 = preflight, migration, validation, empty-table inert
   live check only; no seed, no Value Card, no seed-validation, no 5G-1D. (§1)
3. **Baseline / backup:** pg_dump preferred; fallback only if documented (what
   failed + backup/PITR evidence + preflight P6 saved); backup/PITR is a STOP
   condition; AI review pack mandatory before migration per AGENTS.md. (Steps 2–4)
4. **Preflight gate:** guard exception stops; any `P1`–`P5` not-true stops; P6
   eyeballed; latest reconciled week noted; excluded-goal list matches; fresh
   mechanical diff clean; outside Wendy-hours; same-sitting freshness. (Step 5, 7, §3)
5. **Migration gate:** any error stops; pre-COMMIT failure persists nothing — prove
   via preflight `P1`–`P3` before retry; session drop after COMMIT before sanity →
   proceed to validation. (Step 8, §4)
6. **Validation gate:** full output to `exports/`; all V true; V7 empty; V4f exact
   grant set; V8e/V9f PASS/no exception; zero rows written. (Step 9)
7. **Live inert check:** network delta defined (404 quiet → 200 empty array); inert =
   unchanged rendered behavior, not identical network traffic; baseline includes same
   login, hard reload, BUILD_TS, Overview, Weekly, Goals/Funding, Budget, Register.
   (Steps 6, 10)
8. **Evidence capture:** schema baseline or documented fallback; AI review pack; full
   preflight output; full validation output; live pre/post notes with BUILD_TS; saved
   under `exports/` with timestamps; commit only after the execution session ends;
   `--no-verify` for docs/evidence commits. (§6)

---

## 9. Gate checklist (condensed)

- **Before preflight → migration:** Fable cleared (fresh) + Adam approved; schema
  baseline (pg_dump or documented fallback) captured; AI review pack generated;
  backup/PITR confirmed (STOP if absent); fresh mechanical diff clean (pinned
  result); live-site baseline recorded with BUILD_TS; all preflight `P1`–`P5` true,
  guard clean, P6 eyeballed, latest reconciled week noted, excluded-goal list
  matches; outside Wendy's Budget-entry hours; same-sitting freshness satisfied.
- **Before migration → validation:** migration ran through `COMMIT` with no error;
  `M-table=1`, `M-rpc=1` (or session-drop rule → go to validation); no partial-object
  state (proven via `P1`–`P3` if in doubt).
- **Before declaring E1 complete:** all validation V-checks true; `V7` empty; `V4f`
  exact grant set; V8e/V9f no exception; zero rows; post-migration live-site check
  matches the Step 6 baseline (inert; loader 404→200-empty is the only expected
  network delta).

---

## 10. Open questions / notes before E1 execution

1. **Fable clearance of this file is the top gate** — E1 does not start until Fable
   reviews `docs/phase-5g-1c-2-e1-runbook.md` and its corrections are resolved.
2. **SQL execution surface** — recommend the Supabase **SQL Editor** for the three
   files; text output preferred over screenshots. Confirm SQL Editor vs `psql`.
3. **pg_dump prod connection string availability** — if absent, the Step 2 fallback
   applies (UI capture + backup/PITR evidence + saved preflight P6 + documented
   reason). Claude is **not** assumed to hold prod credentials.
4. **Backup/PITR must be verified to actually exist** (Step 4) — a hard STOP.
5. **Timing** — E1 has no anchor-week dependency (empty, inert) but must run outside
   Wendy's active Budget-entry hours and precede E2, whose wk-5 anchor is valid only
   **Jul 12–17** (else re-anchor wk 6 / Jul 18, or defer past the Alaska freeze
   **Jul 24–Aug 10**).
6. **`app_users` identity assertion is intentionally omitted** from all guards
   (schema unverified); `system_identifier` equality is the accepted unique
   production fingerprint — confirm Adam accepts that backstop.
7. **Cosmetic, deferred to E2 (not E1):** the seed header's "four capture values"
   wording is an E2-time polish in `seed-anchor.sql`; it is out of scope for E1 and
   is intentionally not touched here.

---

**This runbook is the reviewed artifact for the E1 gate. It authorizes nothing on
its own — execution requires fresh Fable clearance (§0) then Adam's separate
in-session approval. No SQL, no Supabase, no E1/E2/5G-1D has been run.**
