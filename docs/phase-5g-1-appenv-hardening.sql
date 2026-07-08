-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — app_environment RLS hardening (SEPARATE follow-on)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — NOT part of the 5G-1 RLS smoke. Its own tiny migration + verification.
-- Requires separate Adam approval. STAGING ONLY first (pkwotgqivgaapwuqgwqb);
-- a prod equivalent is a separate decision (prod currently has NO app_environment).
--
-- WHY: public.app_environment was created with no RLS and no REVOKE, so it inherits
-- Supabase's broad default public-table grants. The content (env='staging') is not
-- sensitive, but the migration/rollback GUARDS key off app_environment.env='staging'.
-- With default grants + no RLS, an API caller (authenticated, maybe anon) could
-- modify/TRUNCATE the sentinel and undermine that guard. Scope of harm is LOW
-- (staging holds no real data; prod has no app_environment at all), but this is a
-- latent guard-integrity gap inconsistent with the least-privilege posture next door.
--
-- OPTION 2 (this file): REVOKE from anon/authenticated + ENABLE RLS with NO policies
-- => default-deny for API roles; migrations/service_role/SQL-editor bypass RLS and
-- keep working. Clears the Supabase "RLS Disabled in Public" warning.
-- (Option 3 — move future sentinel/ops tables to a non-PostgREST schema — is the
--  go-forward convention for NEW tables, not a retrofit of this one.)
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

-- ── Harden ───────────────────────────────────────────────────────────────────
REVOKE ALL ON public.app_environment FROM PUBLIC, anon, authenticated;
ALTER TABLE public.app_environment ENABLE ROW LEVEL SECURITY;
-- No policies created on purpose: default-deny for anon/authenticated.
-- service_role / table owner (migrations, SQL editor) bypass RLS and are unaffected.

COMMIT;

-- ── Verify guard integrity is preserved AND API roles are locked out ─────────
-- H1: owner can still read the sentinel (migration guards run as owner/service_role).
SELECT 'H1' AS check, EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') AS expected_true;

-- H2: RLS now enabled.
SELECT 'H2' AS check,
       (SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname='public' AND c.relname='app_environment') AS expected_true;

-- H3: anon + authenticated have ZERO grants on the sentinel.
SELECT 'H3' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants
         WHERE table_schema='public' AND table_name='app_environment'
           AND grantee IN ('anon','authenticated')) AS expected_true;

-- H4: behavioral — as authenticated, SELECT returns 0 rows (RLS default-deny) and
--     TRUNCATE is permission-denied. Rolled back.
DO $$
DECLARE cnt INT; ok BOOLEAN;
BEGIN
  PERFORM set_config('role','authenticated', true);
  PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000aa","email":"x@herndons.test","role":"authenticated"}', true);
  SELECT count(*) INTO cnt FROM public.app_environment;   -- expect 0 (no grant -> may raise; catch either way)
  IF cnt <> 0 THEN RAISE EXCEPTION 'H4 FAIL: authenticated read returned % rows (expected 0/denied).', cnt; END IF;
  ok := true;
  BEGIN TRUNCATE public.app_environment; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'H4 FAIL: authenticated TRUNCATE not denied.'; END IF;
  RAISE NOTICE 'H4 PASS: authenticated locked out; owner/service_role guards unaffected.';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'H4 PASS: authenticated SELECT permission-denied (stronger than 0-row); guards unaffected.';
END $$;
RESET ROLE;

-- ── ROLLBACK / UNDO (D9) — commented; run manually only if you must revert ────
-- WARNING: this does NOT perfectly reconstruct the ORIGINAL Supabase default
-- grants. app_environment was created with no explicit REVOKE, so before this
-- hardening it inherited whatever broad defaults Supabase's `postgres`/default-
-- privilege setup grants to anon/authenticated on new public tables (historically
-- a wide set incl. TRUNCATE). The re-GRANT below restores a REASONABLE superset
-- (SELECT/INSERT/UPDATE/DELETE) but intentionally NOT TRUNCATE, and cannot recover
-- the exact prior grant list. Prefer leaving the hardening in place. Undo only if a
-- specific breakage forces it, then re-review grants explicitly.
--
-- BEGIN;
--   -- staging guard omitted here for brevity — re-add the guard block above if used.
--   ALTER TABLE public.app_environment DISABLE ROW LEVEL SECURITY;
--   -- Approximate restore (NOT the exact Supabase defaults; no TRUNCATE by choice):
--   GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_environment TO anon, authenticated;
-- COMMIT;
-- -- Verify after undo: RLS disabled, and grants match your intended (documented) set.
-- SELECT 'UNDO' AS check,
--        (SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
--          WHERE n.nspname='public' AND c.relname='app_environment') AS rls_should_be_false;
