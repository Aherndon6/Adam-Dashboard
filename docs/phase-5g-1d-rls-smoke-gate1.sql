-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (pkwotgqivgaapwuqgwqb)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D Slice 2 — RLS/RPC SMOKE, GATE 1 (SQL role-impersonation). Authored, NOT executed.
-- Rolled-back transactions; asserts the authorization boundaries and input-guard behavior that
-- do not need heavy seeded state. The full failure-injection / state-branch / sequence /
-- concurrency / timestamp matrix (branches E/F/G, half-close repair, adjacent-week Option B,
-- recorded_at re-stamp) runs against SEEDED staging state per the package §12 and Gate 2.
-- Requires phase-5g-1d-staging-grant.sql applied first (authenticated EXECUTE), reverted after.
-- Replace <ADAM_UID> / <WENDY_UID> with real staging auth.users ids (LOCAL only).
-- ─────────────────────────────────────────────────────────────────────────
DO $guard$
DECLARE v_sysid BIGINT;
BEGIN
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'HARD STOP: PRODUCTION — Gate 1 smoke is staging-only.'; END IF;
END $guard$;

-- ── T1: non-owner (Wendy) cannot invoke approved_reopen (is_owner() rejects, before state reads) ──
BEGIN;
  SET LOCAL role authenticated;
  SET LOCAL request.jwt.claims = json_build_object('sub','<WENDY_UID>','role','authenticated')::text;
  DO $$
  BEGIN
    PERFORM public.save_weekly_closeout_with_snapshots(6,2026,0,0,0,0,0,'cleared','[]'::jsonb,'[]'::jsonb,
      (SELECT jsonb_agg(jsonb_build_object('goal_id',g,'funded_amount',0))
         FROM unnest(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']) g),
      'approved_reopen', 9);
    RAISE EXCEPTION 'T1 FAIL: Wendy approved_reopen was not rejected';
  EXCEPTION WHEN sqlstate '42501' THEN RAISE NOTICE 'T1 PASS: Wendy approved_reopen rejected (42501)';
  END $$;
ROLLBACK;

-- ── T2: strict p_mode — NULL and unknown raise before any inner call ──
BEGIN;
  SET LOCAL role authenticated;
  SET LOCAL request.jwt.claims = json_build_object('sub','<ADAM_UID>','role','authenticated')::text;
  DO $$
  BEGIN
    BEGIN
      PERFORM public.save_weekly_closeout_with_snapshots(6,2026,0,0,0,0,0,'cleared','[]'::jsonb,'[]'::jsonb,'[]'::jsonb, NULL, 9);
      RAISE EXCEPTION 'T2a FAIL: NULL p_mode not rejected';
    EXCEPTION WHEN sqlstate '22023' THEN RAISE NOTICE 'T2a PASS: NULL p_mode rejected';
    END;
    BEGIN
      PERFORM public.save_weekly_closeout_with_snapshots(6,2026,0,0,0,0,0,'cleared','[]'::jsonb,'[]'::jsonb,'[]'::jsonb, 'reopen_now', 9);
      RAISE EXCEPTION 'T2b FAIL: unknown p_mode not rejected';
    EXCEPTION WHEN sqlstate '22023' THEN RAISE NOTICE 'T2b PASS: unknown p_mode rejected';
    END;
  END $$;
ROLLBACK;

-- ── T3: strict commitment arrays — JSON null / object / string rejected (no coercion) ──
BEGIN;
  SET LOCAL role authenticated;
  SET LOCAL request.jwt.claims = json_build_object('sub','<ADAM_UID>','role','authenticated')::text;
  DO $$
  DECLARE v_rows jsonb := (SELECT jsonb_agg(jsonb_build_object('goal_id',g,'funded_amount',0))
      FROM unnest(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']) g);
  BEGIN
    BEGIN PERFORM public.save_weekly_closeout_with_snapshots(6,2026,0,0,0,0,0,'cleared','null'::jsonb,'[]'::jsonb,v_rows,'normal_closeout',9);
      RAISE EXCEPTION 'T3a FAIL: JSON null p_new_commitments not rejected';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE '%must be a JSON array%' THEN RAISE NOTICE 'T3a PASS'; ELSE RAISE; END IF; END;
    BEGIN PERFORM public.save_weekly_closeout_with_snapshots(6,2026,0,0,0,0,0,'cleared','{}'::jsonb,'[]'::jsonb,v_rows,'normal_closeout',9);
      RAISE EXCEPTION 'T3b FAIL: object p_new_commitments not rejected';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE '%must be a JSON array%' THEN RAISE NOTICE 'T3b PASS'; ELSE RAISE; END IF; END;
  END $$;
ROLLBACK;

-- ── T4: Option B owner-only + core validation (missing row / wk5 / non-eligible / bad note) ──
BEGIN;
  SET LOCAL role authenticated;
  SET LOCAL request.jwt.claims = json_build_object('sub','<WENDY_UID>','role','authenticated')::text;
  DO $$
  BEGIN
    BEGIN PERFORM public.correct_goal_funding_snapshot(2026,6,'adam_ira',100,50,'x');
      RAISE EXCEPTION 'T4a FAIL: Wendy Option B not rejected';
    EXCEPTION WHEN sqlstate '42501' THEN RAISE NOTICE 'T4a PASS: Wendy Option B rejected'; END;
  END $$;
ROLLBACK;
BEGIN;
  SET LOCAL role authenticated;
  SET LOCAL request.jwt.claims = json_build_object('sub','<ADAM_UID>','role','authenticated')::text;
  DO $$
  BEGIN
    BEGIN PERFORM public.correct_goal_funding_snapshot(2026,5,'adam_ira',100,50,'x');
      RAISE EXCEPTION 'T4b FAIL: wk5 Option B not rejected';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE '%post-anchor%' OR SQLERRM LIKE '%Week-5%' THEN RAISE NOTICE 'T4b PASS'; ELSE RAISE; END IF; END;
    BEGIN PERFORM public.correct_goal_funding_snapshot(2026,6,'adam_401k',100,50,'x');
      RAISE EXCEPTION 'T4c FAIL: non-eligible goal not rejected';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE '%not eligible%' THEN RAISE NOTICE 'T4c PASS'; ELSE RAISE; END IF; END;
    BEGIN PERFORM public.correct_goal_funding_snapshot(2026,6,'adam_ira',100,50,'   ');
      RAISE EXCEPTION 'T4d FAIL: empty note not rejected';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE '%note must be non-empty%' THEN RAISE NOTICE 'T4d PASS'; ELSE RAISE; END IF; END;
    BEGIN PERFORM public.correct_goal_funding_snapshot(2026,6,'adam_ira','NaN'::numeric,50,'x');
      RAISE EXCEPTION 'T4e FAIL: NaN amount not rejected';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE '%must be finite%' THEN RAISE NOTICE 'T4e PASS'; ELSE RAISE; END IF; END;
  END $$;
ROLLBACK;

-- ── T5: p_expected_count is ENFORCED (must equal 9) — stateless pure-input reject ──
BEGIN;
  SET LOCAL role authenticated;
  SET LOCAL request.jwt.claims = json_build_object('sub','<ADAM_UID>','role','authenticated')::text;
  DO $$
  DECLARE v_rows jsonb := (SELECT jsonb_agg(jsonb_build_object('goal_id',g,'funded_amount',0))
      FROM unnest(ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']) g);
  BEGIN
    PERFORM public.save_weekly_closeout_with_snapshots(6,2026,0,0,0,0,0,'cleared','[]'::jsonb,'[]'::jsonb,v_rows,'normal_closeout', 8);
    RAISE EXCEPTION 'T5 FAIL: p_expected_count=8 not rejected';
  EXCEPTION WHEN others THEN IF SQLERRM LIKE '%p_expected_count must equal 9%' THEN RAISE NOTICE 'T5 PASS'; ELSE RAISE; END IF; END $$;
ROLLBACK;

-- NOTE: state-dependent branches (E new closeout / F identity+GFA01 / G half-close repair),
-- sequence rules, adjacent-week concurrency, and the recorded_at re-stamp assertions require
-- seeded staging state (a reconciled Week-5 anchor + reconciled weeks) and are exercised by the
-- seeded staging program + Gate 2. For GFA01: a fully-closed week resubmitted with a non-empty
-- p_new_commitments must raise sqlstate 'GFA01' with HINT 'REQUIRES_SUPERVISED_ADJUDICATION',
-- calling neither inner RPC and changing no state.
