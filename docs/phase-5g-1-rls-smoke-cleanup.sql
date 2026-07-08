-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1 RLS Smoke — CLEANUP (staging only)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — STAGING ONLY (pkwotgqivgaapwuqgwqb). Removes the [STAGING] test
-- identities left behind after Gate 1 + Gate 2. FK-SAFE ORDER:
--
--   1. phase-5g-1-rollback.sql  (RUN FIRST, separately — drops outflow_events +
--      planned_outflows, clearing any Gate-2 rows whose created_by_user_id FKs to
--      auth.users). This file assumes the 5G-1 tables are already dropped.
--   2. This file: assert no dangling FK refs -> delete [STAGING] app_users rows.
--   3. This file: assert again -> delete [STAGING] auth.users rows (writer, viewer,
--      AND the real unauthorized Gate-2 user).
--   4. Verify nothing remains.
--
-- Deleting auth.users BEFORE the 5G-1 tables are dropped would hit a RESTRICT
-- violation via outflow_events.created_by_user_id / planned_outflows.created_by_user_id.
-- That is why rollback.sql runs first.
--
-- IDENTITIES (D6): three staging auth.users rows are removed —
--   <<W_UUID>>  writer  (has [STAGING] app_users row)
--   <<V_UUID>>  viewer  (has [STAGING] app_users row)
--   <<U_UUID>>  Gate-2 "unauthorized" real user (NO app_users row, but a real
--               auth.users row that still must be deleted from staging)
--
-- TOKEN HYGIENE (D10): fill <<W_UUID>>/<<V_UUID>>/<<U_UUID>> into a LOCAL/scratch
-- copy or via psql \set — do NOT commit real staging UUIDs into this file.
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ── STAGING GUARD ────────────────────────────────────────────────────────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete. Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint. Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (tx=%). Aborting.', v_tx; END IF;
END $$;

-- ── D6/D4: assert NO remaining FK references to ANY of the test auth_user_ids ─
-- Defensive: if rollback.sql ran, the 5G-1 tables are gone (to_regclass NULL) and
-- there is nothing to reference. If they somehow still exist, prove zero rows
-- reference the test users (writer, viewer, unauthorized) before we touch auth.users.
DO $$
DECLARE ids UUID[] := ARRAY['<<W_UUID>>','<<V_UUID>>','<<U_UUID>>']::UUID[]; n BIGINT;
BEGIN
  IF to_regclass('public.planned_outflows') IS NOT NULL THEN
    SELECT count(*) INTO n FROM public.planned_outflows WHERE created_by_user_id = ANY(ids);
    IF n > 0 THEN RAISE EXCEPTION 'HARD STOP: % planned_outflows rows still reference test users. Run rollback.sql first.', n; END IF;
  END IF;
  IF to_regclass('public.outflow_events') IS NOT NULL THEN
    SELECT count(*) INTO n FROM public.outflow_events WHERE created_by_user_id = ANY(ids);
    IF n > 0 THEN RAISE EXCEPTION 'HARD STOP: % outflow_events rows still reference test users. Run rollback.sql first.', n; END IF;
  END IF;
  RAISE NOTICE 'FK-ref check ok: no planned_outflows/outflow_events rows reference the test users.';
END $$;

-- ── Delete [STAGING] app_users rows (writer + viewer; the unauthorized user has
--    none). Must precede auth.users delete (app_users.auth_user_id FKs auth.users).
DELETE FROM public.app_users WHERE auth_user_id IN ('<<W_UUID>>','<<V_UUID>>');

-- ── Assert app_users no longer references ANY test user, then delete auth.users ─
DO $$
DECLARE ids UUID[] := ARRAY['<<W_UUID>>','<<V_UUID>>','<<U_UUID>>']::UUID[]; n BIGINT;
BEGIN
  SELECT count(*) INTO n FROM public.app_users WHERE auth_user_id = ANY(ids);
  IF n > 0 THEN RAISE EXCEPTION 'HARD STOP: % app_users rows still reference test users; not deleting auth.users.', n; END IF;
END $$;

-- Delete all three staging test auth users (writer, viewer, unauthorized).
DELETE FROM auth.users WHERE id IN ('<<W_UUID>>','<<V_UUID>>','<<U_UUID>>');

-- ── Verify nothing remains ───────────────────────────────────────────────────
DO $$
DECLARE n_au BIGINT; n_u BIGINT;
BEGIN
  SELECT count(*) INTO n_au FROM public.app_users WHERE auth_user_id IN ('<<W_UUID>>','<<V_UUID>>','<<U_UUID>>');
  SELECT count(*) INTO n_u  FROM auth.users        WHERE id           IN ('<<W_UUID>>','<<V_UUID>>','<<U_UUID>>');
  IF n_au <> 0 OR n_u <> 0 THEN RAISE EXCEPTION 'CLEANUP FAIL: residual rows (app_users=%, auth.users=%).', n_au, n_u; END IF;
  RAISE NOTICE 'CLEANUP ok: test app_users + all three test auth.users removed.';
END $$;

COMMIT;

-- Final checks (owner):
SELECT 'CL1' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.tables
         WHERE table_schema='public' AND table_name IN ('planned_outflows','outflow_events')) AS expected_true;  -- 5G-1 objects absent
SELECT 'CL2' AS check, EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') AS expected_true;        -- sentinel retained
