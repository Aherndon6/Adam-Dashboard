-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — SYNTHETIC goal_registry FIXTURE VALIDATION (READ ONLY). Authored, NOT executed.
-- Proves goal_registry contains EXACTLY the 13 canonical fixture rows with the EXACT per-id contract:
-- tier='staging_fixture', status='planned', target=1000.00, notes carries [STAGING-FIXTURE], priority is the
-- exact 1..13 mapping, and auto is exact (true only adam_401k; eligible nine + excluded three false). Also
-- re-asserts the deployed structural contract (19 cols, PK(id), 3 CHECKs, 0 FK) is unchanged — seed added
-- rows only. Self-contained: no pasted baseline required. Staging only.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT;
  v_total INT; v_extras INT; v_marked INT; v_tier INT; v_status INT; v_target INT;
  v_prio_bad INT; v_auto_bad INT;
  v_colcount INT; v_pk INT; v_chk INT; v_fk INT;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
  c_canonical13 CONSTANT text[] := ARRAY['adam_ira','wendy_ira','wendy_sep','alaska','bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise','adam_401k','wewe_rccl','wewe_dcl','taxable_etf'];
BEGIN
  -- EXACT staging fingerprint
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = 7632885393857617092 THEN RAISE EXCEPTION 'RV: production system_identifier — staging only'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'RV: app_environment absent — not the approved staging env'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'RV: not the approved staging fingerprint (sysid=%, appenv total=%, staging=%)', v_sysid, v_appenv_total, v_appenv_staging; END IF;

  -- exactly the 13 canonical ids, no extras
  SELECT count(*) INTO v_total FROM public.goal_registry;
  IF v_total <> 13 THEN RAISE EXCEPTION 'RV: goal_registry has % rows, expected exactly 13', v_total; END IF;
  SELECT count(*) INTO v_extras FROM public.goal_registry WHERE id <> ALL(c_canonical13);
  IF v_extras <> 0 THEN RAISE EXCEPTION 'RV: % non-canonical goal id(s) present', v_extras; END IF;

  -- exact scalar contract across all 13 rows: marker, tier, status, target
  SELECT count(*) INTO v_marked FROM public.goal_registry WHERE COALESCE(notes,'') LIKE '%[STAGING-FIXTURE]%';
  IF v_marked <> 13 THEN RAISE EXCEPTION 'RV: only % of 13 rows carry the [STAGING-FIXTURE] marker', v_marked; END IF;
  SELECT count(*) INTO v_tier FROM public.goal_registry WHERE tier = 'staging_fixture';
  IF v_tier <> 13 THEN RAISE EXCEPTION 'RV: only % of 13 rows have tier=staging_fixture', v_tier; END IF;
  SELECT count(*) INTO v_status FROM public.goal_registry WHERE status = 'planned';
  IF v_status <> 13 THEN RAISE EXCEPTION 'RV: only % of 13 rows have status=planned', v_status; END IF;
  SELECT count(*) INTO v_target FROM public.goal_registry WHERE target = 1000.00;
  IF v_target <> 13 THEN RAISE EXCEPTION 'RV: only % of 13 rows have the synthetic target 1000.00 (household value leaked?)', v_target; END IF;

  -- exact per-id priority (1..13) AND exact per-id auto flag, in one comparison
  SELECT count(*) INTO v_prio_bad
  FROM ( VALUES
      ('adam_ira',1),('wendy_ira',2),('wendy_sep',3),('alaska',4),('bailey_529',5),
      ('bryce_529',6),('preston_529',7),('bryce_vehicle',8),('christmas_cruise',9),
      ('adam_401k',10),('wewe_rccl',11),('wewe_dcl',12),('taxable_etf',13)
  ) AS e(id,prio)
  LEFT JOIN public.goal_registry g ON g.id = e.id
  WHERE g.id IS NULL OR g.priority <> e.prio;
  IF v_prio_bad <> 0 THEN RAISE EXCEPTION 'RV: % row(s) drift from the exact 1..13 priority mapping', v_prio_bad; END IF;

  SELECT count(*) INTO v_auto_bad
  FROM ( VALUES
      ('adam_ira',false),('wendy_ira',false),('wendy_sep',false),('alaska',false),('bailey_529',false),
      ('bryce_529',false),('preston_529',false),('bryce_vehicle',false),('christmas_cruise',false),
      ('adam_401k',true),('wewe_rccl',false),('wewe_dcl',false),('taxable_etf',false)
  ) AS e(id,auto)
  LEFT JOIN public.goal_registry g ON g.id = e.id
  WHERE g.id IS NULL OR g.auto <> e.auto;
  IF v_auto_bad <> 0 THEN RAISE EXCEPTION 'RV: % row(s) drift from the exact auto-flag map (true only adam_401k)', v_auto_bad; END IF;

  -- deployed structural contract unchanged (seed added rows only): 19 cols, PK(id), 3 CHECKs, 0 FK
  SELECT count(*) INTO v_colcount FROM information_schema.columns WHERE table_schema='public' AND table_name='goal_registry';
  IF v_colcount <> 19 THEN RAISE EXCEPTION 'RV: goal_registry column count changed (% <> 19)', v_colcount; END IF;
  SELECT count(*) INTO v_pk  FROM pg_constraint WHERE conrelid='public.goal_registry'::regclass AND contype='p';
  SELECT count(*) INTO v_chk FROM pg_constraint WHERE conrelid='public.goal_registry'::regclass AND contype='c';
  SELECT count(*) INTO v_fk  FROM pg_constraint WHERE contype='f' AND (conrelid='public.goal_registry'::regclass OR confrelid='public.goal_registry'::regclass);
  IF v_pk <> 1 OR v_chk <> 3 OR v_fk <> 0 THEN
    RAISE EXCEPTION 'RV: structural contract drift (pk=%, checks=%, fk=%; expected 1/3/0)', v_pk, v_chk, v_fk; END IF;

  RAISE NOTICE 'REGISTRY FIXTURE VALIDATION PASS: exactly the 13 canonical ids; tier=staging_fixture; status=planned; target=1000.00; all marked; priority 1..13 exact; auto true only adam_401k; structure PK(id)+3 CHECK+0 FK unchanged.';
END $$;

-- Rows dump (eyeball the synthetic values; no household balances).
SELECT 'RV-rows' AS check, id, name, tier, target, priority, status, auto, notes
  FROM public.goal_registry ORDER BY priority;

COMMIT;
