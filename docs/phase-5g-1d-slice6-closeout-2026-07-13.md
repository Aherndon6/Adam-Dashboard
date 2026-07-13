# Phase 5G-1D — Slice 6 Inert Production Deployment — CLOSEOUT EVIDENCE

**Status:** **COMPLETE + GREEN (2026-07-13).** The closeout wrapper + Option B are live in
**production, INERT** — no API role can execute them, nothing calls them, and production behavior is
unchanged. **Balance-free** (no household values; the MD5s are function-definition hashes, the
counts are row counts).
**Target:** PRODUCTION Adam-Dashboard (`usayoldrawwmjsmretin`), `system_identifier`
`7632885393857617092`.
**Execution model:** E1 discipline — Adam ran each gate in the Supabase SQL Editor / his terminal,
one at a time; Claude ran no SQL and verified each verbatim output against the finalized runbook
(`docs/phase-5g-1d-slice6-deploy-runbook-2026-07-13.md`).
**Committed SQL used (byte-for-byte, unmodified):** `docs/phase-5g-1d-preflight.sql`,
`-migration.sql`, `-validation.sql` (validation had only the two local md5 paste-ins). Rollback
(`-rollback.sql`) **not** needed.
**NOT authorized by this deployment:** Gate B, Phase-1 grants, Phase-2 revokes, merge to `main`,
`BUILD_TS` stamp, browser activation, Week-6 closeout, Option B use, any correction, any production
write beyond creating the two inert functions.

---

## Gate 1 — Production identity & preflight (READ ONLY) — PASS
- Environment **production**; `system_identifier 7632885393857617092`; `app_environment` **absent**.
- `current_user = session_user = postgres`.
- SECURITY DEFINER owner baseline (one trusted, non-client owner): `save_reconciliation_with_commitments`,
  `save_goal_funding_snapshots`, `is_owner`, `can_write_financials` all owned by **`postgres`**.
- Deployed-RPC MD5 baselines (== the approved baselines in `CODEX_STATUS.md` / `-gate2-inspect.sql`):
  recon `1bfde751ac647c5e9a25ba168d08150c`; snapshot `154231b3f180349ec328f08ccbe77076`.
- Both new functions + the `_gf_is_finite_amount` helper **absent** (fresh deploy).
- Week-5 opening anchor: **9** rows / **9** distinct eligible goals. Advisory namespace `1734501000`.
- No hard stops.

## Gate 2 — Same-sitting restore point — PASS (DR floor)
- Custom-format public-schema `pg_dump` (schema + DATA, `--no-owner --no-acl`); `pg_dump` exit 0.
- `pg_restore --list` exit 0; expected-object match **4/4**. Permissions `-rw-------`.
- Filename `5G-1D-slice6-restorepoint-20260713T222223Z.dump`; size 182,028 bytes; SHA-256
  `e3d24dfa…8410`. Encrypted off-device copy (iCloud) SHA-256 `8dc172d1…a69c9`, post-transfer
  verification PASS. Metadata: `docs/phase-5g-1d-slice6-restorepoint-metadata-20260713T222223Z.md`
  (dump itself local-only, never committed; DR-only, not a routine rollback).

## Gate 3 — Migration (`-migration.sql`) — PASS
- Executed successfully (atomic `BEGIN…COMMIT`; no rows returned). Env guard resolved **production**;
  owner-consistency assertion passed.
- Read-only verification: exactly **two** new functions; both owner **postgres**, SECURITY DEFINER,
  `search_path=public,pg_temp`; both `anon`/`authenticated` EXECUTE **false** (inert).

## Gate 4 — Validation (`-validation.sql`, READ ONLY) — PASS
- `new_function_count = 2`; both owner **postgres**, SECURITY DEFINER, search_path pinned.
- **Bodies byte-unchanged:** recon `1bfde751…150c`, snapshot `154231b3…7076` (== Gate-1 baselines).
- Wrapper + Option B: `anon`/`authenticated` EXECUTE **false** (INERT).
- **Old reconciliation RPC `authenticated` EXECUTE = true** (correctly retained — its revoke is Gate B).
- No validation exception raised.

## Gate 5 — Inert REST + browser checks — PASS
- **REST:** authenticated POST to both new functions → **HTTP 404 / PGRST202** (not in the schema
  cache for the role); no 2xx; writes nothing.
- **Live browser** (dashboard.herndons.us, hard refresh): `BUILD_TS` **unchanged**
  (`2026-07-11T17:26:14`); `goal_funding_snapshots` loader **200**; Overview / Weekly / Goals /
  Budget / History render normally; console clean (only normal registry-load messages); no write
  action performed.
- **No data changed:** `goal_funding_snapshots` total **11**; Week-5 eligible opening-anchor **9**.

---

## Final inert end state
- `public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)`
  and `public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)` **exist**, SECURITY
  DEFINER, owned by `postgres`, **zero API-role EXECUTE** → not REST-callable by anon/authenticated/PUBLIC.
- E1 table + snapshot RPC, the reconciliation RPC (body, signature, **and** its `authenticated`
  grant), all RLS, and all data **byte/state-unchanged** (Week-5 snapshot rows still **11**).
- The deployed browser is unchanged and still writes through the old RPC; nothing deployed references
  the new functions. **Production behavior is INERT** on three independent grounds: grant-layer (no
  API-role EXECUTE), caller-layer (no deployed caller), and proven-by-check (§Gate 5).

## Rollback
- **Not needed.** No preflight/migration/validation failure and no behavioral/rendered change.
  `docs/phase-5g-1d-rollback.sql` (drops only the two functions) remains available under its
  standing pre-approval; the restore point is the DR floor beneath it.

**Slice 6 ends at "wrapper + Option B live but INERT; contracts byte-unchanged; rollback prepared."
Gate B is the next, separate gate and is NOT authorized by this deployment.**
