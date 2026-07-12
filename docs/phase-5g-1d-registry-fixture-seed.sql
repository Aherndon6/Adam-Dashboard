-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — SYNTHETIC goal_registry FIXTURE SEED. Authored, NOT executed.
-- INSERT-ONLY. Seeds the 13 canonical goal ids with SYNTHETIC, NON-HOUSEHOLD values so the
-- E1 staging preflight (needs the eligible nine) and the 5G-1D 13-id checks can run. Every row
-- carries the [STAGING-FIXTURE] marker in `notes`; target is a uniform synthetic 1000.00 (matches
-- NO real household target); `auto` is behaviorally exact (true only for adam_401k). Hard-stops
-- unless goal_registry is EMPTY. PRODUCTION IS NOT TOUCHED; production goal_registry is not modified.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT; v_cnt INT; v_ins INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
BEGIN
  -- EXACT staging fingerprint — sysid + app_environment exactly one row, env='staging'
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production system_identifier — staging-only seed. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint (sysid=%, appenv total=%, staging=%). Aborting.', v_sysid, v_appenv_total, v_appenv_staging; END IF;

  -- goal_registry must exist and be COMPLETELY EMPTY (insert-only, never touch existing rows)
  IF to_regclass('public.goal_registry') IS NULL THEN RAISE EXCEPTION 'HARD STOP: goal_registry missing. Aborting.'; END IF;
  SELECT count(*) INTO v_cnt FROM public.goal_registry;
  IF v_cnt <> 0 THEN RAISE EXCEPTION 'HARD STOP: goal_registry is non-empty (% rows) — refusing to seed over existing data. Aborting.', v_cnt; END IF;

  -- INSERT-ONLY. 13 canonical ids; synthetic target 1000.00; marker in notes; auto true only for adam_401k.
  -- eligible nine (auto=false) → snapshottable; adam_401k (auto=true) → RPC-excluded; wewe_rccl/wewe_dcl/
  -- taxable_etf (auto=false) → excluded by id in the RPC. priority 1..13 distinct positive (safe under any check).
  INSERT INTO public.goal_registry (id, name, tier, target, priority, status, auto, notes) VALUES
    ('adam_ira',         'adam_ira',         'staging_fixture', 1000.00,  1, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('wendy_ira',        'wendy_ira',        'staging_fixture', 1000.00,  2, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('wendy_sep',        'wendy_sep',        'staging_fixture', 1000.00,  3, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('alaska',           'alaska',           'staging_fixture', 1000.00,  4, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('bailey_529',       'bailey_529',       'staging_fixture', 1000.00,  5, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('bryce_529',        'bryce_529',        'staging_fixture', 1000.00,  6, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('preston_529',      'preston_529',      'staging_fixture', 1000.00,  7, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('bryce_vehicle',    'bryce_vehicle',    'staging_fixture', 1000.00,  8, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('christmas_cruise', 'christmas_cruise', 'staging_fixture', 1000.00,  9, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('adam_401k',        'adam_401k',        'staging_fixture', 1000.00, 10, 'planned', true,  '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('wewe_rccl',        'wewe_rccl',        'staging_fixture', 1000.00, 11, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('wewe_dcl',         'wewe_dcl',         'staging_fixture', 1000.00, 12, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)'),
    ('taxable_etf',      'taxable_etf',      'staging_fixture', 1000.00, 13, 'planned', false, '[STAGING-FIXTURE] synthetic goal (non-household)');
  GET DIAGNOSTICS v_ins = ROW_COUNT;

  IF v_ins <> 13 THEN RAISE EXCEPTION 'SEED: inserted % rows <> 13. Aborting.', v_ins; END IF;
  SELECT count(*) INTO v_cnt FROM public.goal_registry;
  IF v_cnt <> 13 THEN RAISE EXCEPTION 'SEED: goal_registry has % rows after insert <> 13. Aborting.', v_cnt; END IF;
  RAISE NOTICE 'REGISTRY FIXTURE SEED PASS: 13 synthetic goals inserted (auto=true only adam_401k); all marked [STAGING-FIXTURE]; target uniform 1000.00.';
END $$;

COMMIT;
