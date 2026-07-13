# Phase 5G-1D — Slice 6 Inert Production Deployment — FINAL EXECUTION PACKAGE

**Status:** **FINAL — READY FOR EXECUTION APPROVAL; NOT EXECUTED, NOT AUTHORIZED.** Deploys the
closeout wrapper + Option B to **production, INERT** (no grants, nothing calls them). **No
activation, no browser change, no grant change** — Slice 6 is Gate-C-independent (all grant changes
are Gate B). Execution requires its own explicit in-session Adam approval **and** the pre-approved
rollback (§6.1). Nothing here is production-affecting until Adam runs it.
**Date:** 2026-07-13
**Author:** Claude (session under Adam)
**Gate D:** Option A (pre-freeze) — APPROVED. **Gate C:** all 11 dispositions APPROVED (Adam,
2026-07-13) — executes at Gate B, **not here.** Browser (Slices 3/4/5) COMPLETE; local E2E 142/0,
readiness fallbacks 0/0.
**Target:** PRODUCTION Adam-Dashboard (`usayoldrawwmjsmretin`), `system_identifier`
`7632885393857617092`.
**Committed SQL used (byte-for-byte, unmodified):** `docs/phase-5g-1d-preflight.sql`,
`docs/phase-5g-1d-migration.sql`, `docs/phase-5g-1d-validation.sql`, `docs/phase-5g-1d-rollback.sql`
(all env-guarded; production resolves with no `c_staging_sysid` fill). **Execution model = the E1
discipline:** Adam runs each step in the Supabase SQL Editor in one sitting; Claude runs no SQL;
outputs saved verbatim; value-bearing artifacts local-only.
**Privacy:** balance-free.

---

## 0. What Slice 6 is

Deploy `public.save_weekly_closeout_with_snapshots` (13-arg wrapper) and
`public.correct_goal_funding_snapshot` (6-arg Option B) to production, **created inert** — the
migration ends with `REVOKE ALL … FROM PUBLIC, anon, authenticated` on both, so **no API role can
call them**. E1 (`goal_funding_snapshots` + `save_goal_funding_snapshots`) and the reconciliation
RPC are **untouched**. The deployed browser still writes via the old RPC. **Production behavior is
unchanged.**

---

## 1. Preconditions (all must hold before the sitting)

- ☐ **Gate D decided** = Option A (✓, 2026-07-13).
- ☐ **Browser complete + verified:** Slices 3/4/5 done; local full `node e2e.js` = **142/0**,
  readiness fallbacks **0/0** (Adam-verified). Static **1486/0**.
- ☐ **Gate A CLOSED** (`public.is_owner()` identity) — ✓ (2026-07-11).
- ☐ **Rollback pre-approved:** `docs/phase-5g-1d-rollback.sql` reviewed + separately approved
  **before** the migration runs.
- ☐ **Fresh full-data restore point** captured same-sitting (§2) — the last one (2026-07-09)
  predates E2/2.1/Week-5.
- ☐ **No freeze conflict:** the sitting is before Jul 24 (Option A) or the inert DB deploy is
  explicitly acceptable outside the freeze window per Adam.
- ☐ **In-session Slice-6 execution approval** given.
- ☐ Working from `origin/main` (docs) with the feature branch **not yet merged** (browser stays on
  the old flow until Gate B).

---

## 2. Backup / restore-point requirements (Free-plan mechanism — P1-2 hardened)

Supabase Free plan = no PITR, so the restore point is a manual dump captured **in the same sitting,
immediately before the migration**. Requirements (all ☐ must hold):

1. ☐ **Format — custom, restorable:** `pg_dump -Fc` (custom format), **schema + DATA**, with
   `--no-owner --no-acl` (the restore target re-derives ownership/ACLs; this also keeps role names
   out of the artifact). Example (run by Adam; **credentials never pasted into any committed file or
   this runbook** — use `~/.pgpass` or an env var):
   `pg_dump -Fc --no-owner --no-acl --schema=public -f 5G-1D-slice6-restorepoint-<ts>.dump "$PROD_DSN"`
2. ☐ **Scope is explicit:** this is a **public-schema dump** — it captures the application tables,
   functions, RLS policies, and data in `public`, **not** a full Supabase *platform* backup (it does
   not include `auth`/`storage` schemas, Edge configs, or project settings). For this phase the
   public schema is the system of record; note the scope in the metadata so no one mistakes it for a
   whole-project restore.
3. ☐ **Restorability verified before trusting it:** `pg_restore --list <dump>` succeeds and shows the
   expected `public` objects (tables + the deployed RPCs). A dump that will not `--list` is not a
   restore point.
4. ☐ **Integrity + perms:** compute **SHA-256** of the `.dump`; store the file with restrictive perms
   (`chmod 600`).
5. ☐ **Location:** stored **outside the repo** at `~/Herndon-FOS-DB-Backups/Adam-Dashboard/5G-1D-Slice6/`
   — **never committed** (it contains household data).
6. ☐ **Off-device, encrypted copy:** a second copy encrypted at rest and off the primary device
   (Synthesis P1 recovery-floor tie-in) — the immediate DR requirement for the sole live system of
   record. Record only *that* it exists + its SHA-256 in the metadata; **no keys, no credentials**.
7. ☐ **Committable metadata ONLY** (`exports/db-restorepoint-5G-1D-slice6-metadata-<ts>.md`): file
   name, byte size, SHA-256, timestamp, scope (`public`-schema custom-format dump), `pg_restore
   --list` object count, off-device-copy confirmation. **No connection strings, no credentials, no
   household values.**
8. ☐ This dump is the **disaster floor** beneath the SQL rollback: `-rollback.sql` drops the two new
   functions; the dump restores the public schema if a deeper problem appears.

**P0-3 owner capture (same sitting, from the preflight):** record the `definer-owner-baseline`
(`current_user`/`session_user` + the owners of `save_reconciliation_with_commitments`,
`save_goal_funding_snapshots`, `is_owner`, `can_write_financials`) in the Slice-6 evidence — this is
the trusted owner the migration pins the two new functions to, and the Gate-B lockdown re-asserts.

---

## 3. Deployment sequence (ordered; one sitting; Adam runs each step)

1. ☐ Confirm target project = **Adam-Dashboard `usayoldrawwmjsmretin`** (NOT staging).
2. ☐ **Preflight** — run `docs/phase-5g-1d-preflight.sql` (READ ONLY): environment fingerprint
   (sysid `7632885393857617092`, `app_environment` ABSENT); baseline + E1 objects present; both
   deployed RPCs at exact signatures — **capture their `md5(pg_get_functiondef())`** (the
   byte-unchanged baseline for §4 and for the Gate-B/grant validation); `is_owner()` /
   `can_write_financials()` present; **both new functions ABSENT**; Week-5 anchor complete by
   goal_id (nine eligible `opening_anchor`; the two `wewe_*` correction rows tolerated). **Capture
   the `definer-owner-baseline` (P0-3)** — `current_user`/`session_user` + the shared owner of the
   deployed RPCs / `is_owner` / `can_write_financials`; the preflight hard-stops if they do not share
   one non-client owner. Save output verbatim.
3. ☐ **Restore point** — §2 dump captured; metadata recorded.
4. ☐ **Migration** — run `docs/phase-5g-1d-migration.sql`: env guard resolves `production`; creates
   **exactly two** functions; ends with `REVOKE ALL … FROM PUBLIC, anon, authenticated` on both.
   `BEGIN…COMMIT`. Save output.
5. ☐ **Validation** — run `docs/phase-5g-1d-validation.sql` (READ ONLY; paste the step-2 md5s into
   `v_recon_md5` / `v_snap_md5` locally first). All asserts must pass (§4).
6. ☐ **Inert live checks** (§4 manual block).
7. ☐ Write the Slice-6 closeout evidence doc (balance-free) + the status-doc pointer proposal.
   **STOP.** Do not proceed to grants, browser deploy, or activation — those are Gate B.

**Hard stops:** any preflight assert fails; the migration guard resolves anything but
`production`; any validation assert fails; any rendered/behavioral change observed; any need to
touch E1 or the reconciliation RPC. On a hard stop: nothing further; rollback only under its own
separate approval.

---

## 4. Validation sequence

From `docs/phase-5g-1d-validation.sql` (one READ-ONLY transaction), all must pass:
- ☐ both new functions exist at their **exact signatures**; **no** third/helper function
  (`_gf_is_finite_amount` absent — inlined by design);
- ☐ **INERT grant state**: zero `anon`/`authenticated` EXECUTE on both; no explicit PUBLIC EXECUTE
  aclitem on either;
- ☐ **byte-unchanged proofs**: deployed `save_reconciliation_with_commitments` md5 == preflight
  baseline; deployed `save_goal_funding_snapshots` md5 == preflight baseline;
- ☐ structural: SECURITY DEFINER + `search_path=public,pg_temp` on both; no dynamic SQL; no
  EXCEPTION handler; inlined finiteness rejection in both; per-goal `goal_registry FOR UPDATE`
  mutex in both; advisory-lock namespace `1734501000`;
- ☐ **owner pinned (P0-3):** both new functions owned by the trusted definer owner (== the deployed
  recon/snapshot RPC owner from the preflight baseline); owner is not a client role. The migration
  hard-stops on owner drift; validation re-proves it (`definer-owner` row);
- ☐ **old reconciliation RPC `authenticated` EXECUTE still PRESENT** (its revocation is Gate B /
  Slice 7, not now).

Manual inert checks (same sitting):
- ☐ **REST probe:** an authenticated POST to `/rest/v1/rpc/save_weekly_closeout_with_snapshots`
  returns a **grant-layer denial** (401/403/404 class) — proves not-callable, writes nothing.
- ☐ **Live browser** (dashboard.herndons.us, hard refresh): `BUILD_TS` unchanged; snapshot loader
  still 200 with the existing 11 Week-5 rows; weekly/recon/goals/budget render unchanged; console
  clean.
- ☐ `goal_funding_snapshots` row count unchanged (**11**); `weekly_reconciliations` untouched.
- ☐ The next ordinary weekly closeout still uses `save_reconciliation_with_commitments` (the
  Slice-3 client is deliberately **not** deployed yet).

---

## 5. Expected inert end state (after Slice 6)

- `public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)`
  and `public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)` **exist**, SECURITY
  DEFINER, **zero API-role EXECUTE** → not REST-callable by anon/authenticated/PUBLIC.
- E1 table + snapshot RPC, the reconciliation RPC (body, signature, **and its `authenticated`
  grant**), `repair_commitments_for_week`, all RLS, and all data **byte/state-unchanged** (Week-5
  snapshot rows still **11**).
- The deployed browser is unchanged and still writes through the old RPC; nothing deployed
  references the new functions.
- **Production behavior is INERT** on three independent grounds: (1) grant-layer — no API role can
  EXECUTE either function; (2) caller-layer — no deployed code calls them; (3) proven-by-check —
  the §4 REST probe + live checks.

---

## 6. Rollback boundary (Slice 6)

- `docs/phase-5g-1d-rollback.sql` drops **exactly the two new functions** (env-guarded;
  staging-rehearsable) and proves E1 + the reconciliation RPC + the snapshot table survive.
  **No data is ever deleted.** Separate Adam approval.
- **Boundary:** up to and including Slice 6, rollback = that DROP and nothing else; production data,
  deployed contracts, grants, and app behavior are exactly pre-Slice-6. The §2 restore-point dump
  is the disaster floor beneath it.
- Anything Gate B / Slice 7 later changes (activation grants, old-RPC revocation, Gate-C postures,
  browser deploy) carries its **own** rollback (`docs/phase-5g-1d-activation-grants-rollback.sql`,
  the browser-revert) — **outside this boundary.**

### 6.1 Rollback pre-approval language (Adam signs this BEFORE the migration runs)

> *I pre-approve the Slice-6 rollback: if the Slice-6 preflight, migration, or validation fails, or
> any behavioral/rendered change is observed, execution stops immediately and
> `docs/phase-5g-1d-rollback.sql` may be run in the same sitting to DROP exactly the two new
> functions `save_weekly_closeout_with_snapshots` and `correct_goal_funding_snapshot`. This rollback
> touches nothing else: the E1 table + `save_goal_funding_snapshots`, the reconciliation RPC, all
> RLS, all grants, and all rows (incl. the 11 Week-5 snapshot rows) remain unchanged, and NO
> reconciliation or snapshot data is deleted. If a deeper problem is found, the same-sitting
> restore-point `pg_dump` (§2) is the disaster floor. No grant change, browser deploy, or activation
> is authorized by this pre-approval — those remain Gate B.*

This pre-approval is **required before step 4 (migration)**. It authorizes only the Slice-6 DROP
rollback; it does not authorize any Gate B action.

---

## 7. Evidence to capture (balance-free, saved verbatim)

- ☐ Preflight output incl. the two deployed-RPC md5 baselines **and the `definer-owner-baseline`
  (P0-3)** — the trusted owner + `current_user`/`session_user`.
- ☐ Restore-point metadata (name, size, sha256, timestamp, scope, `pg_restore --list` count,
  off-device-copy confirmation) — committable; the dump itself local-only, credentials never recorded.
- ☐ Migration output (`M-*` notices; `COMMIT`).
- ☐ Validation output (all asserts PASS; the byte-unchanged md5 comparisons).
- ☐ Inert-check results: REST-probe status code; BUILD_TS; snapshot row count (11); console-clean
  screenshot/note.
- ☐ Slice-6 closeout evidence doc (`docs/phase-5g-1d-slice6-closeout-<date>.md`) summarizing the
  above with no household values.

**Slice 6 ends at "wrapper + Option B live but INERT; contracts byte-unchanged; rollback prepared."
Gate B is the next, separate gate.**
