-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — SYNTHETIC goal_registry FIXTURE CLEANUP / RESET. Authored, NOT executed.
-- Deletes ONLY the 13 marked synthetic fixture rows (id in the canonical 13 AND notes contains
-- [STAGING-FIXTURE]). NOT an unrestricted delete. REFUSES while any goal_registry-dependent object
-- still holds data — the FK dependent goal_funding_snapshots must be gone first (run the E1 fixture
-- cleanup + E1 rollback before this). Before deleting it proves the table is exactly those 13 marked
-- rows (hard-stop on any unmarked/unexpected/non-13 row); after, proves exactly 13 deleted and the
-- table is EMPTY. Preserves table structure / grants / RLS (row delete only). PRODUCTION IS NOT TOUCHED.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT;
  v_total INT; v_marked INT; v_unmarked INT; v_del INT; v_left INT; v_fk INT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
  c_canonical13 CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise','adam_401k','wewe_rccl','wewe_dcl','taxable_etf'];
BEGIN
  -- EXACT staging fingerprint
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production system_identifier — staging-only cleanup. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint. Aborting.'; END IF;
  IF to_regclass('public.goal_registry') IS NULL THEN RAISE EXCEPTION 'HARD STOP: goal_registry missing (nothing to clean). Aborting.'; END IF;

  -- REFUSE while the known FK dependent still exists (run E1 fixture cleanup + E1 rollback first).
  -- goal_funding_snapshots.goal_id -> goal_registry(id) ON DELETE RESTRICT; deleting registry rows
  -- while that table exists risks a RESTRICT block and would leave the E1 layer dangling.
  IF to_regclass('public.goal_funding_snapshots') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: goal_funding_snapshots still present — run the E1 fixture cleanup + E1 rollback before the registry cleanup. Aborting.'; END IF;

  -- GENERIC catalog guard: refuse if ANY current FK anywhere references goal_registry (future-proof
  -- beyond the named E1 table). Zero at fixture-teardown time under the deployed pre-E1 contract.
  SELECT count(*) INTO v_fk FROM pg_constraint
    WHERE contype='f' AND confrelid='public.goal_registry'::regclass;
  IF v_fk <> 0 THEN
    RAISE EXCEPTION 'HARD STOP: % FK constraint(s) still reference goal_registry — remove dependent objects before the registry cleanup. Aborting.', v_fk; END IF;

  -- PRE: the table must be EXACTLY the 13 marked canonical fixture rows.
  SELECT count(*) INTO v_total FROM public.goal_registry;
  SELECT count(*) INTO v_marked FROM public.goal_registry
    WHERE id = ANY(c_canonical13) AND COALESCE(notes,'') LIKE '%[STAGING-FIXTURE]%';
  SELECT count(*) INTO v_unmarked FROM public.goal_registry
    WHERE NOT (id = ANY(c_canonical13) AND COALESCE(notes,'') LIKE '%[STAGING-FIXTURE]%');
  IF v_marked <> 13 THEN RAISE EXCEPTION 'HARD STOP: expected 13 marked canonical fixture rows, found %. Aborting.', v_marked; END IF;
  IF v_unmarked <> 0 THEN RAISE EXCEPTION 'HARD STOP: % unmarked/unexpected goal_registry row(s) present — refusing to clean. Aborting.', v_unmarked; END IF;
  IF v_total <> 13 THEN RAISE EXCEPTION 'HARD STOP: goal_registry has % rows but only 13 are the fixture. Aborting.', v_total; END IF;

  -- DELETE only the exact marked fixture rows (both predicates), never an unrestricted sweep.
  DELETE FROM public.goal_registry
    WHERE id = ANY(c_canonical13) AND COALESCE(notes,'') LIKE '%[STAGING-FIXTURE]%';
  GET DIAGNOSTICS v_del = ROW_COUNT;

  -- POST: exactly 13 deleted; table EMPTY.
  IF v_del <> 13 THEN RAISE EXCEPTION 'CLEANUP: deleted % rows <> 13', v_del; END IF;
  SELECT count(*) INTO v_left FROM public.goal_registry;
  IF v_left <> 0 THEN RAISE EXCEPTION 'CLEANUP: % row(s) remain after delete (expected empty)', v_left; END IF;
  RAISE NOTICE 'REGISTRY FIXTURE CLEANUP PASS: exactly 13 marked fixture rows deleted; goal_registry is empty; structure/grants/RLS preserved.';
END $$;

COMMIT;
