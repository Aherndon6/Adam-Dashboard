-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1C-2 Validation (post-migration SCHEMA validation)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — run on STAGING immediately after phase-5g-1c-2-migration.sql and BEFORE
-- the seed. Schema/RLS/trigger/constraint/RPC-surface validation only. All
-- V-checks must return their documented expected value.
--
-- Seed validation (SA1..SAn) lives in a SEPARATE file
-- (phase-5g-1c-2-seed-anchor-validation.sql), run only AFTER the seed. This file's
-- V7 asserts the table is EMPTY, so running it post-seed would falsely fail — run
-- this pre-seed. All probes below insert-then-rollback, so this file is
-- non-mutating and safe to re-run pre-seed.
--
-- RPC scope note: this file validates the RPC's SURFACE (exists, SECURITY DEFINER,
-- search_path, exact grants) and that its authorization gate rejects an
-- unauthenticated caller (auth.uid()=NULL under the SQL editor). The RPC's
-- authorized happy-path + input-validation rejection matrix needs a real/
-- impersonated writer identity and is exercised in the RLS smoke (Gate 1/Gate 2).
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

-- ── STAGING GUARD ───────────────────────────────────────────────────────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.'; END IF;
  IF to_regclass('public.accounts') IS NULL OR to_regclass('public.transactions') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: baseline schema missing. Aborting.'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint. Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (tx=%). Aborting.', v_tx; END IF;
END $$;

-- ── V1: table exists ────────────────────────────────────────────────────────
SELECT 'V1' AS check,
       (SELECT count(*) FROM information_schema.tables
        WHERE table_schema='public' AND table_name='goal_funding_snapshots') = 1 AS expected_true;

-- ── V2: RLS enabled ─────────────────────────────────────────────────────────
SELECT 'V2' AS check, bool_and(c.relrowsecurity) AS expected_true
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname='goal_funding_snapshots';

-- ── V3: policy counts / shape ───────────────────────────────────────────────
SELECT 'V3a' AS check, (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='goal_funding_snapshots') = 3 AS expected_true;
SELECT 'V3b' AS check, NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='goal_funding_snapshots' AND cmd='DELETE') AS expected_true;

-- ── V4: predicates + roles + grants ─────────────────────────────────────────
SELECT 'V4a' AS check,
       bool_and(qual LIKE '%can_write_financials%' OR with_check LIKE '%can_write_financials%') AS expected_true
  FROM pg_policies WHERE schemaname='public' AND tablename='goal_funding_snapshots' AND cmd IN ('INSERT','UPDATE');
SELECT 'V4b' AS check,
       bool_and(qual LIKE '%is_allowed_user%') AS expected_true
  FROM pg_policies WHERE schemaname='public' AND tablename='goal_funding_snapshots' AND cmd='SELECT';
SELECT 'V4c' AS check,
       bool_and(roles = ARRAY['authenticated']::name[]) AS expected_true
  FROM pg_policies WHERE schemaname='public' AND tablename='goal_funding_snapshots';
SELECT 'V4d' AS check,
       NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
         AND tablename='goal_funding_snapshots' AND ('public' = ANY(roles) OR 'anon' = ANY(roles))) AS expected_true;
SELECT 'V4e' AS check,
       NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants
         WHERE table_schema='public' AND table_name='goal_funding_snapshots' AND grantee='anon') AS expected_true;
-- V4f: authenticated grant is EXACTLY {SELECT,INSERT,UPDATE} — catches stray
-- DELETE/TRUNCATE/REFERENCES/TRIGGER left by Supabase default privileges.
SELECT 'V4f' AS check,
       (SELECT array_agg(privilege_type::text ORDER BY privilege_type::text)
          FROM information_schema.role_table_grants
         WHERE table_schema='public' AND table_name='goal_funding_snapshots' AND grantee='authenticated')
       = ARRAY['INSERT','SELECT','UPDATE']::text[] AS expected_true;
SELECT 'V4g' AS check, NOT has_table_privilege('authenticated','public.goal_funding_snapshots','DELETE')    AS expected_true;
SELECT 'V4h' AS check, NOT has_table_privilege('authenticated','public.goal_funding_snapshots','TRUNCATE')  AS expected_true;
SELECT 'V4i' AS check, NOT has_table_privilege('authenticated','public.goal_funding_snapshots','REFERENCES')AS expected_true;
SELECT 'V4j' AS check, NOT has_table_privilege('authenticated','public.goal_funding_snapshots','TRIGGER')   AS expected_true;

-- ── V5: updated_at trigger present + reuses the shared helper ────────────────
SELECT 'V5a' AS check, EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='set_goal_funding_snapshots_updated_at') AS expected_true;
SELECT 'V5b' AS check,
       (SELECT p.proname FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
        WHERE t.tgname='set_goal_funding_snapshots_updated_at') = 'fn_set_updated_at' AS expected_true;

-- ── V6: column shape ────────────────────────────────────────────────────────
SELECT 'V6a' AS check,
       (SELECT data_type FROM information_schema.columns
        WHERE table_schema='public' AND table_name='goal_funding_snapshots' AND column_name='id') = 'uuid' AS expected_true;
SELECT 'V6b' AS check,
       (SELECT data_type FROM information_schema.columns
        WHERE table_schema='public' AND table_name='goal_funding_snapshots' AND column_name='goal_id') = 'text' AS expected_true;
SELECT 'V6c' AS check,
       (SELECT data_type FROM information_schema.columns
        WHERE table_schema='public' AND table_name='goal_funding_snapshots' AND column_name='funded_amount') = 'numeric' AS expected_true;
SELECT 'V6d' AS check,
       (SELECT is_nullable FROM information_schema.columns
        WHERE table_schema='public' AND table_name='goal_funding_snapshots' AND column_name='created_by_user_id') = 'YES' AS expected_true;
-- V6e: FK goal_id -> goal_registry(id) present.
SELECT 'V6e' AS check,
       EXISTS (SELECT 1 FROM pg_constraint c
               WHERE c.conrelid='public.goal_funding_snapshots'::regclass AND c.contype='f'
                 AND c.confrelid='public.goal_registry'::regclass) AS expected_true;

-- ── V7: schema-only migration — table empty (run PRE-seed) ───────────────────
SELECT 'V7' AS check, (SELECT count(*) FROM public.goal_funding_snapshots) = 0 AS expected_true;

-- ── V8: constraints present (existence) ─────────────────────────────────────
SELECT 'V8a' AS check, EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_gfs_year_week_goal') AS expected_true;
SELECT 'V8b' AS check, EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_gfs_funded_nonneg') AS expected_true;
SELECT 'V8c' AS check, EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_gfs_source') AS expected_true;
SELECT 'V8d' AS check, EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_gfs_week_range') AS expected_true;

-- ── V8e: constraints BEHAVE — bad rows rejected (owner probe, rolled back) ────
-- Owner INSERT bypasses RLS; this proves the CHECK/UNIQUE layer, not RLS. Uses a
-- real non-auto, non-excluded goal_id and a throwaway model_year (2099) that
-- cannot collide with live data.
DO $$
DECLARE
  v_goal TEXT;
  v_neg_amount BOOLEAN := false;
  v_bad_source BOOLEAN := false;
  v_bad_week   BOOLEAN := false;
  v_dup_key    BOOLEAN := false;
BEGIN
  SELECT id INTO v_goal FROM public.goal_registry
   WHERE COALESCE(auto,false)=false AND id <> ALL (ARRAY['wewe_rccl','wewe_dcl','taxable_etf'])
   ORDER BY id LIMIT 1;
  IF v_goal IS NULL THEN RAISE EXCEPTION 'V8e SETUP FAIL: no eligible goal_id in goal_registry.'; END IF;

  BEGIN
    -- baseline valid row (week 1, throwaway year) so the duplicate probe has a target
    INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source)
      VALUES (2099,1,v_goal,0,'opening_anchor');

    BEGIN INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source)
            VALUES (2099,2,v_goal,-1,'opening_anchor');           -- funded_amount >= 0
      EXCEPTION WHEN OTHERS THEN v_neg_amount := true; END;
    BEGIN INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source)
            VALUES (2099,3,v_goal,0,'made_up_source');            -- source domain
      EXCEPTION WHEN OTHERS THEN v_bad_source := true; END;
    BEGIN INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source)
            VALUES (2099,32,v_goal,0,'opening_anchor');           -- week_num 1..31
      EXCEPTION WHEN OTHERS THEN v_bad_week := true; END;
    BEGIN INSERT INTO public.goal_funding_snapshots (model_year,week_num,goal_id,funded_amount,source)
            VALUES (2099,1,v_goal,5,'correction');                -- UNIQUE(model_year,week_num,goal_id)
      EXCEPTION WHEN OTHERS THEN v_dup_key := true; END;

    RAISE EXCEPTION 'V8E_PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%V8E_PROBE_ROLLBACK%' THEN RAISE; END IF;
  END;
  IF NOT (v_neg_amount AND v_bad_source AND v_bad_week AND v_dup_key) THEN
    RAISE EXCEPTION 'V8e FAIL: constraint rejection wrong (neg=%, bad_source=%, bad_week=%, dup=%).',
      v_neg_amount, v_bad_source, v_bad_week, v_dup_key;
  END IF;
  RAISE NOTICE 'V8e PASS: nonneg/source/week-range/unique constraints reject bad rows; probe rolled back.';
END $$;

-- ── V9: RPC surface — exists, SECURITY DEFINER, search_path=public ───────────
SELECT 'V9a' AS check,
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='save_goal_funding_snapshots') AS expected_true;
SELECT 'V9b' AS check,
       (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='save_goal_funding_snapshots') AS expected_true;  -- SECURITY DEFINER
SELECT 'V9c' AS check,
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='save_goal_funding_snapshots'
                 AND 'search_path=public' = ANY(p.proconfig)) AS expected_true;

-- ── V9d: RPC grants — authenticated EXECUTE yes; anon/PUBLIC no ──────────────
SELECT 'V9d' AS check, has_function_privilege('authenticated','public.save_goal_funding_snapshots(int,int,jsonb)','EXECUTE') AS expected_true;
SELECT 'V9e' AS check, NOT has_function_privilege('anon','public.save_goal_funding_snapshots(int,int,jsonb)','EXECUTE') AS expected_true;

-- ── V9f: RPC authorization gate fires FIRST — an unauthenticated caller
--         (auth.uid()=NULL under the SQL editor ⇒ can_write_financials()=false)
--         is rejected with 'not authorized' before any row is written.
DO $$
DECLARE v_denied BOOLEAN := false;
BEGIN
  BEGIN
    PERFORM public.save_goal_funding_snapshots(
      2099, 1, '[{"goal_id":"__nope__","funded_amount":0,"source":"opening_anchor"}]'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%not authorized%' THEN v_denied := true; ELSE RAISE; END IF;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'V9f FAIL: RPC did NOT reject an unauthenticated caller (can_write_financials gate).';
  END IF;
  IF (SELECT count(*) FROM public.goal_funding_snapshots) <> 0 THEN
    RAISE EXCEPTION 'V9f FAIL: RPC wrote rows despite the authorization denial.';
  END IF;
  RAISE NOTICE 'V9f PASS: RPC authorization gate rejects unauthenticated caller; no rows written.';
END $$;

-- Full authorized RPC behavior (happy-path upsert, idempotent re-upsert, and the
-- input-validation rejection matrix) is exercised under an impersonated/real
-- writer identity in phase-5g-1c-2-rls-smoke-gate1.sql and -gate2.md.
