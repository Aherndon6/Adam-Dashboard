-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D — ACTIVATION GRANT MATRIX (READ ONLY). AUTHORED, NOT EXECUTED.
-- Run BEFORE Phase 1 (capture the pre-activation baseline), AFTER Phase 1 (activation grants),
-- and AFTER Phase 2 (lockdown revokes) to produce the before/after grant matrix Gate C requires.
-- Read-only: no writes, no grants, no DDL. Balance-free.
-- Companion to docs/phase-5g-1d-gatec-register-2026-07-13.md ; grant SQL: -activation-grants.sql /
-- -activation-revokes.sql / -activation-grants-rollback.sql.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

-- Function EXECUTE matrix (anon must be false everywhere; authenticated per posture).
SELECT 'fn-grant' AS check, label, grantee,
       has_function_privilege(grantee, sig, 'EXECUTE') AS execute
FROM (VALUES
  ('G-01 old recon RPC',      'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)'),
  ('G-02 repair RPC',         'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)'),
  ('G-03 snapshot RPC',       'public.save_goal_funding_snapshots(INT, INT, JSONB)'),
  ('G-10 wrapper',            'public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)'),
  ('G-11 Option B',           'public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)')
) AS f(label, sig)
CROSS JOIN (VALUES ('anon'),('authenticated')) AS g(grantee)
ORDER BY label, grantee;

-- Table privilege matrix (SELECT must remain; INSERT/UPDATE/DELETE per posture).
SELECT 'tbl-grant' AS check, tbl, grantee,
       has_table_privilege(grantee, tbl, 'SELECT') AS sel,
       has_table_privilege(grantee, tbl, 'INSERT') AS ins,
       has_table_privilege(grantee, tbl, 'UPDATE') AS upd,
       has_table_privilege(grantee, tbl, 'DELETE') AS del
FROM (VALUES ('public.goal_funding_snapshots'),('public.weekly_reconciliations')) AS t(tbl)
CROSS JOIN (VALUES ('anon'),('authenticated')) AS g(grantee)
ORDER BY tbl, grantee;

-- Function-definition byte-unchanged proof (grant changes must not alter any body).
SELECT 'fn-body-md5' AS check, p.proname,
       md5(pg_get_functiondef(p.oid)) AS body_md5
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
  ('save_reconciliation_with_commitments','save_goal_funding_snapshots',
   'save_weekly_closeout_with_snapshots','correct_goal_funding_snapshot','repair_commitments_for_week')
ORDER BY p.proname;

-- EXPECTED after full activation (Phase 1 + Phase 2):
--   fn-grant  : anon EXECUTE = false for ALL; authenticated EXECUTE — wrapper=T, Option B=T,
--               old recon RPC=F, repair=F, snapshot RPC=F.
--   tbl-grant : authenticated SELECT=T both tables; goal_funding_snapshots INS/UPD=F;
--               weekly_reconciliations INS/UPD/DEL=F; anon all=F.
--   fn-body-md5: identical to the pre-activation capture (bodies unchanged; grants only).
COMMIT;
