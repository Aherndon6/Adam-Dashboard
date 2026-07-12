-- ═══════════════════════════════════════════════════════════════════════════
-- ██  STAGING ONLY — herndon-fos-staging (system_identifier 7656985631720456337)  ██
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D prerequisite — SYNTHETIC goal_registry FIXTURE PREFLIGHT (READ ONLY).
-- Authored, NOT executed. Confirms staging is ready to receive the synthetic 13-row
-- goal_registry fixture (the E1 staging preflight hard-stops without the eligible nine).
-- Validates the EXACT DEPLOYED goal_registry contract read from the staging catalog
-- (19 columns w/ types+nullability+default posture; PK(id); CHECK priority>=0; CHECK target>=0;
-- CHECK status IN (6 enum); NO FK dependencies) — NOT the Phase-6A design spec. Hard-stops on drift.
-- PRODUCTION IS NOT TOUCHED; production goal_registry artifacts are not modified.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

DO $$
DECLARE
  v_sysid BIGINT; v_appenv_total INT; v_appenv_staging INT; v_cnt INT; v_col INT;
  v_badcol INT; v_numprec INT; v_colcount INT; v_extra INT;
  v_pk INT; v_pkdef TEXT; v_chk INT; v_uq INT; v_fk INT; v_statusdef TEXT;
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 7656985631720456337;
  c_needcols CONSTANT text[] := ARRAY['id','name','tier','target','priority','status','auto','notes'];
  c_allcols  CONSTANT text[] := ARRAY['id','name','tier','target','priority','status','notes','starts_after','due_week','needs_flag','milestone','stretch','auto','from_model','src','dest','color','created_at','updated_at'];
BEGIN
  RAISE NOTICE 'EXECUTION IDENTITY: current_user=%, session_user=%', current_user, session_user;

  -- (a) EXACT staging fingerprint — sysid + app_environment exactly one row, env='staging'
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  IF v_sysid = c_prod_sysid THEN RAISE EXCEPTION 'HARD STOP: production system_identifier — staging-only preflight. Aborting.'; END IF;
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment absent. Aborting.'; END IF;
  SELECT count(*), count(*) FILTER (WHERE env='staging') INTO v_appenv_total, v_appenv_staging FROM public.app_environment;
  IF NOT (v_sysid = c_staging_sysid AND v_appenv_total = 1 AND v_appenv_staging = 1) THEN
    RAISE EXCEPTION 'HARD STOP: not the approved staging fingerprint (sysid=%, appenv total=%, staging=%). Aborting.', v_sysid, v_appenv_total, v_appenv_staging; END IF;

  -- (b) goal_registry exists and is COMPLETELY EMPTY
  IF to_regclass('public.goal_registry') IS NULL THEN RAISE EXCEPTION 'HARD STOP: goal_registry missing. Aborting.'; END IF;
  SELECT count(*) INTO v_cnt FROM public.goal_registry;
  IF v_cnt <> 0 THEN RAISE EXCEPTION 'HARD STOP: goal_registry is non-empty (% rows) — not a fresh fixture target. Aborting.', v_cnt; END IF;

  -- (c) exact insert-column contract needed for the seed must exist
  SELECT count(*) INTO v_col FROM information_schema.columns
    WHERE table_schema='public' AND table_name='goal_registry' AND column_name = ANY(c_needcols);
  IF v_col <> array_length(c_needcols,1) THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry insert-column contract incomplete (% of % present). Aborting.', v_col, array_length(c_needcols,1); END IF;

  -- ── (d) EXACT DEPLOYED COLUMN CONTRACT — type + nullability + default posture (per staging catalog) ──
  SELECT count(*) INTO v_badcol
  FROM ( VALUES
      ('id','text','NO','none'),                       ('name','text','NO','none'),
      ('tier','text','NO','none'),                     ('target','numeric','NO','none'),
      ('priority','integer','NO','none'),              ('status','text','NO','planned'),
      ('notes','text','YES','none'),                   ('starts_after','text','YES','none'),
      ('due_week','integer','YES','none'),             ('needs_flag','text','YES','none'),
      ('milestone','numeric','YES','none'),            ('stretch','boolean','NO','false'),
      ('auto','boolean','NO','false'),                 ('from_model','text','YES','none'),
      ('src','text','YES','none'),                     ('dest','text','YES','none'),
      ('color','text','YES','none'),                   ('created_at','timestamp with time zone','YES','now'),
      ('updated_at','timestamp with time zone','YES','now')
  ) AS e(col,dtype,nullable,defkind)
  LEFT JOIN information_schema.columns c
    ON c.table_schema='public' AND c.table_name='goal_registry' AND c.column_name=e.col
  WHERE c.column_name IS NULL
     OR c.data_type   <> e.dtype
     OR c.is_nullable <> e.nullable
     OR (e.defkind='none'    AND c.column_default IS NOT NULL)
     OR (e.defkind='planned' AND COALESCE(c.column_default,'') NOT LIKE '%planned%')
     OR (e.defkind='false'   AND COALESCE(c.column_default,'') NOT LIKE '%false%')
     OR (e.defkind='now'     AND COALESCE(c.column_default,'') NOT LIKE '%now()%');
  IF v_badcol <> 0 THEN RAISE EXCEPTION 'HARD STOP: % goal_registry column(s) drift from the deployed contract (type/nullability/default). Aborting.', v_badcol; END IF;

  -- numeric(12,2) precision/scale on the two numeric columns
  SELECT count(*) INTO v_numprec FROM information_schema.columns
    WHERE table_schema='public' AND table_name='goal_registry' AND column_name IN ('target','milestone')
      AND NOT (data_type='numeric' AND numeric_precision=12 AND numeric_scale=2);
  IF v_numprec <> 0 THEN RAISE EXCEPTION 'HARD STOP: target/milestone not numeric(12,2). Aborting.'; END IF;

  -- exactly the 19 deployed columns, no extras
  SELECT count(*) INTO v_colcount FROM information_schema.columns WHERE table_schema='public' AND table_name='goal_registry';
  IF v_colcount <> 19 THEN RAISE EXCEPTION 'HARD STOP: goal_registry has % columns, expected exactly 19. Aborting.', v_colcount; END IF;
  SELECT count(*) INTO v_extra FROM information_schema.columns
    WHERE table_schema='public' AND table_name='goal_registry' AND column_name <> ALL(c_allcols);
  IF v_extra <> 0 THEN RAISE EXCEPTION 'HARD STOP: % unexpected goal_registry column(s) beyond the deployed 19. Aborting.', v_extra; END IF;

  -- ── (e) EXACT DEPLOYED CONSTRAINTS — PK(id) + CHECK priority>=0 + CHECK target>=0 + CHECK status IN(6) ──
  SELECT count(*) INTO v_pk FROM pg_constraint WHERE conrelid='public.goal_registry'::regclass AND contype='p';
  IF v_pk <> 1 THEN RAISE EXCEPTION 'HARD STOP: expected exactly 1 primary key, found %. Aborting.', v_pk; END IF;
  SELECT pg_get_constraintdef(oid) INTO v_pkdef FROM pg_constraint WHERE conrelid='public.goal_registry'::regclass AND contype='p';
  IF v_pkdef <> 'PRIMARY KEY (id)' THEN RAISE EXCEPTION 'HARD STOP: primary key is "%", expected "PRIMARY KEY (id)". Aborting.', v_pkdef; END IF;

  SELECT count(*) INTO v_chk FROM pg_constraint WHERE conrelid='public.goal_registry'::regclass AND contype='c';
  IF v_chk <> 3 THEN RAISE EXCEPTION 'HARD STOP: expected exactly 3 CHECK constraints, found %. Aborting.', v_chk; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.goal_registry'::regclass AND contype='c' AND pg_get_constraintdef(oid) ILIKE '%priority >= 0%') THEN
    RAISE EXCEPTION 'HARD STOP: CHECK (priority >= 0) absent. Aborting.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.goal_registry'::regclass AND contype='c' AND pg_get_constraintdef(oid) ILIKE '%target >= 0%') THEN
    RAISE EXCEPTION 'HARD STOP: CHECK (target >= 0) absent. Aborting.'; END IF;
  SELECT pg_get_constraintdef(oid) INTO v_statusdef FROM pg_constraint
    WHERE conrelid='public.goal_registry'::regclass AND contype='c' AND pg_get_constraintdef(oid) ILIKE '%status%';
  IF v_statusdef IS NULL
     OR v_statusdef NOT ILIKE '%planned%' OR v_statusdef NOT ILIKE '%funding%' OR v_statusdef NOT ILIKE '%funded%'
     OR v_statusdef NOT ILIKE '%executed%' OR v_statusdef NOT ILIKE '%paused%' OR v_statusdef NOT ILIKE '%archived%' THEN
    RAISE EXCEPTION 'HARD STOP: status CHECK does not enumerate exactly {planned,funding,funded,executed,paused,archived}. def=%. Aborting.', v_statusdef; END IF;

  -- no UNIQUE constraint beyond the PK
  SELECT count(*) INTO v_uq FROM pg_constraint WHERE conrelid='public.goal_registry'::regclass AND contype='u';
  IF v_uq <> 0 THEN RAISE EXCEPTION 'HARD STOP: unexpected UNIQUE constraint(s) (%). Aborting.', v_uq; END IF;

  -- ── (f) NO FK DEPENDENCIES either originating from or referencing goal_registry (generic catalog check) ──
  SELECT count(*) INTO v_fk FROM pg_constraint
    WHERE contype='f' AND (conrelid='public.goal_registry'::regclass OR confrelid='public.goal_registry'::regclass);
  IF v_fk <> 0 THEN RAISE EXCEPTION 'HARD STOP: % FK constraint(s) touch goal_registry — deployed contract expects none pre-E1. Aborting.', v_fk; END IF;

  -- (g) no goal_registry-dependent staging fixture data already exists (E1 not yet deployed).
  -- Explicit nested branch: never reference goal_funding_snapshots in a statement that could be
  -- planned when the table is absent (staging currently has no such table).
  IF to_regclass('public.goal_funding_snapshots') IS NOT NULL THEN
    SELECT count(*) INTO v_cnt
    FROM public.goal_funding_snapshots;

    IF v_cnt <> 0 THEN
      RAISE EXCEPTION
        'HARD STOP: goal_funding_snapshots already has % rows — resolve dependent fixture data first. Aborting.',
        v_cnt;
    END IF;
  END IF;

  RAISE NOTICE 'REGISTRY FIXTURE PREFLIGHT PASS: staging fingerprint OK; goal_registry present + empty; 19-column deployed contract, PK(id) + 3 CHECKs verified; no FK dependencies; no dependent fixture rows.';
END $$;

-- ── Readable deployed-contract diagnostics (eyeball; no household data) ──
SELECT 'diag-columns' AS check, ordinal_position AS ord, column_name, data_type,
       numeric_precision, numeric_scale, is_nullable, column_default
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='goal_registry' ORDER BY ordinal_position;

SELECT 'diag-constraints' AS check, conname, contype, pg_get_constraintdef(oid) AS def
  FROM pg_constraint WHERE conrelid='public.goal_registry'::regclass ORDER BY contype, conname;

SELECT 'diag-fk-dependencies' AS check, conname,
       conrelid::regclass AS from_table, confrelid::regclass AS to_table, pg_get_constraintdef(oid) AS def
  FROM pg_constraint
  WHERE contype='f' AND (conrelid='public.goal_registry'::regclass OR confrelid='public.goal_registry'::regclass)
  ORDER BY conname;

COMMIT;
