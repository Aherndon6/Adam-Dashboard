-- ═══════════════════════════════════════════════════════════════════════════
-- ██████████  PRODUCTION — Adam-Dashboard (usayoldrawwmjsmretin)  ██████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 5G-1D — CONSOLIDATED 17-CHECK ACTIVATION VALIDATION (READ ONLY).
-- AUTHORED 2026-07-17, NOT EXECUTED. Design authority: Fable independent review 2026-07-17
-- (adopted as controlling); operator package v6 §12 carries the expected matrix this file
-- implements. Companion to — NEVER a replacement for — the raw matrices in
-- docs/phase-5g-1d-activation-grants-validation.sql: run BOTH files at operator-package §2
-- steps 3 (stage=pre_phase_1), 5 (stage=post_phase_1), and 13 (stage=post_phase_2). The raw
-- file remains the capture / rollback-exact-restore reference; THIS file is the boolean gate.
--
--   NEVER MUTATES .. read-only; no DML, no DDL, no GRANT/REVOKE, no temp objects, no
--                    set_config/session GUCs. Wholly wrapped in BEGIN READ ONLY.
--   OUTPUT ......... one CTX context row (informational, NOT scored), then EXACTLY 17 scored
--                    check rows C-01…C-17 plus one SUMMARY row, then one DO assertion that
--                    independently re-derives all 17 checks and RAISEs on any failure.
--   HARD STOP ...... ANY pass=false (or any DO exception) = HARD STOP per operator package
--                    §3/§5. Do not proceed to the next activation step.
--
-- ── STAGE SELECTOR — EDIT THE TWO MARKED LITERALS TOGETHER ──────────────────
-- The stage appears in EXACTLY TWO places and both MUST carry the same value:
--   (1) the `stage` VALUES CTE literal in the consolidated SELECT below;
--   (2) the `c_stage` constant in the trailing DO assertion.
-- Legal values: 'pre_phase_1' | 'post_phase_1' | 'post_phase_2'.  Committed default:
-- 'pre_phase_1'.  Anything else fails CLOSED (every scored row false + DO exception).
-- The SUMMARY row and the DO PASS notice each name their stage — VERIFY THEY MATCH when
-- capturing evidence; a mismatch means the two literals were not edited together.
--
-- ── Check inventory (operator package v6 §12 = the authoritative expected matrix) ──
--   C-01…C-10  fn-grant   : per-role EXECUTE on the five activation-surface functions
--   C-11…C-14  tbl-grant  : per (table × role) SELECT/INSERT/UPDATE/DELETE posture
--   C-15…C-16  fn-body-md5: the two PROTECTED pinned bodies (recon RPC / snapshot RPC)
--   C-17       fn-owner   : owner=postgres ×6 (+ SECURITY DEFINER ×4) consolidated invariant
--
-- ── C-13 interpretation (Fable review; corrects the former blanket "anon all=F") ──
-- weekly_reconciliations carries Supabase-DEFAULT role grants (never grant-normalized in any
-- committed migration — Gate C register §2; rollback file §B note), so its raw anon ACL bits
-- are NOT pinned and are emitted as INFORMATIONAL evidence only. What C-13 scores is the
-- control that actually holds: RLS ENABLED on the table AND zero policies naming anon or
-- public. TRUNCATE bits (both tables × both roles) are likewise informational, never scored;
-- their normalization is a recorded POST-ACTIVATION backlog item (package v6 §12), not any
-- part of this sitting's approved grant/revoke scope.
--
-- ── Deliberate exclusions (unchanged by both activation phases; not among the 17) ──
-- service_role (bypasses RLS by design — Supabase-internal; intentionally untouched);
-- cash_commitments (definer-RPC-only since 5F-1); weekly_tasks and all other tables (outside
-- Gate C scope); RLS policy CONTENT (Gate A territory, closed); wrapper/Option B/repair body
-- MD5s (no committed pins — capture all five bodies via the RAW file at each stage and
-- compare the three unpinned bodies byte-for-byte ACROSS stages; package v6 §12 requires it).
--
-- ── Environment guard ──
-- The DO assertion hard-stops unless the environment resolves to production
-- (system_identifier 7632885393857617092, app_environment ABSENT) or the explicitly pinned
-- staging rehearsal (c_staging_sysid <> 0 AND app_environment marker present — same pattern
-- as -activation-grants.sql; c_staging_sysid=0 means staging hard-stops until pinned).
-- An unknown/ambiguous environment can NEVER pass. The CTX row displays the fingerprint; a
-- staging rehearsal is a SEPARATELY authorized action and may show legitimate fixture deltas.
--
-- ── Run modes (Supabase SQL Editor) ──
--   Evidence capture: run statements 1–4 (through the consolidated SELECT) and record the
--   CTX row + all 18 rows verbatim; then run statement 5 (DO) + COMMIT. On a whole-file run
--   the editor surfaces the LAST statement's result — the DO exception makes any failure
--   unmissable; on success re-run the SELECT alone to capture the rowset.
-- Spec: docs/phase-5g-1d-saturday-operator-package-2026-07-18.md v6 (§2 steps 3/5/13, §12);
-- grant SQL: -activation-grants.sql (Phase 1) / -activation-revokes.sql (Phase 2).
-- Balance-free. Secrets-free.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

-- ── Statement 3: CTX context row (informational — NOT one of the 17 scored checks) ──
SELECT 'CTX'::text AS check,
       (SELECT system_identifier FROM pg_control_system()) AS system_identifier,
       (to_regclass('public.app_environment') IS NOT NULL)  AS app_environment_present,
       CASE WHEN to_regclass('public.app_environment') IS NULL
            THEN 'ABSENT (expected for production)'
            ELSE 'PRESENT (staging marker table; DO-block resolves/validates its content)'
       END AS app_environment_note,
       current_user  AS "current_user",
       session_user  AS "session_user",
       ((SELECT system_identifier FROM pg_control_system()) = 7632885393857617092
        AND to_regclass('public.app_environment') IS NULL)  AS production_fingerprint_ok;

-- ── Statement 4: the consolidated evidence SELECT — 17 scored rows + 1 SUMMARY row ──
WITH
-- ▼▼ STAGE SELECTOR (edit 1 of 2 — MUST match c_stage in the DO block below) ▼▼
stage AS (SELECT 'pre_phase_1'::text AS s),
-- ▲▲ legal: pre_phase_1 | post_phase_1 | post_phase_2 ▲▲
st AS (SELECT s, (s IN ('pre_phase_1','post_phase_1','post_phase_2')) AS ok FROM stage),
-- C-01…C-10: function EXECUTE posture (exact committed signatures; to_regprocedure fail-closed)
fn AS (
  SELECT v.cid, v.rol, v.obj, v.sig,
         CASE (SELECT s FROM st) WHEN 'pre_phase_1'  THEN v.e_pre
                                 WHEN 'post_phase_1' THEN v.e_p1
                                 WHEN 'post_phase_2' THEN v.e_p2 END AS exp,
         CASE WHEN to_regprocedure(v.sig) IS NULL THEN NULL
              ELSE has_function_privilege(v.rol, to_regprocedure(v.sig), 'EXECUTE') END AS act
  FROM (VALUES
    ('C-01','anon',          'save_reconciliation_with_commitments (old recon RPC)',
     'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)',
     false, false, false),
    ('C-02','authenticated', 'save_reconciliation_with_commitments (old recon RPC)',
     'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)',
     true,  true,  false),
    ('C-03','anon',          'repair_commitments_for_week (repair RPC)',
     'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)',
     false, false, false),
    ('C-04','authenticated', 'repair_commitments_for_week (repair RPC)',
     'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)',
     true,  true,  false),
    ('C-05','anon',          'save_goal_funding_snapshots (direct snapshot RPC)',
     'public.save_goal_funding_snapshots(INT, INT, JSONB)',
     false, false, false),
    ('C-06','authenticated', 'save_goal_funding_snapshots (direct snapshot RPC)',
     'public.save_goal_funding_snapshots(INT, INT, JSONB)',
     true,  true,  false),
    ('C-07','anon',          'save_weekly_closeout_with_snapshots (wrapper)',
     'public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)',
     false, false, false),
    ('C-08','authenticated', 'save_weekly_closeout_with_snapshots (wrapper)',
     'public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)',
     false, true,  true),
    ('C-09','anon',          'correct_goal_funding_snapshot (Option B)',
     'public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)',
     false, false, false),
    ('C-10','authenticated', 'correct_goal_funding_snapshot (Option B)',
     'public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)',
     false, true,  true)
  ) AS v(cid, rol, obj, sig, e_pre, e_p1, e_p2)
),
fn_rows AS (
  SELECT cid AS check_id, 'fn-grant'::text AS category, obj AS object, rol AS role,
         (SELECT s FROM st) AS stage,
         CASE WHEN NOT (SELECT ok FROM st) THEN 'INVALID STAGE'
              WHEN exp THEN 'EXECUTE=T' ELSE 'EXECUTE=F' END AS expected,
         COALESCE(CASE WHEN act THEN 'EXECUTE=T' WHEN NOT act THEN 'EXECUTE=F' END,
                  'MISSING') AS actual,
         ((SELECT ok FROM st) AND COALESCE(act = exp, false)) AS pass
  FROM fn
),
-- C-11 / C-12 / C-14: grouped table-privilege posture (scored 4-tuple; TRUNCATE informational)
tb AS (
  SELECT v.cid, v.rol, v.obj, to_regclass(v.tbl) AS rc,
         CASE (SELECT s FROM st) WHEN 'pre_phase_1'  THEN v.e_pre
                                 WHEN 'post_phase_1' THEN v.e_p1
                                 WHEN 'post_phase_2' THEN v.e_p2 END AS exp
  FROM (VALUES
    ('C-11','anon',          'public.goal_funding_snapshots','goal_funding_snapshots',
     'sel=F ins=F upd=F del=F','sel=F ins=F upd=F del=F','sel=F ins=F upd=F del=F'),
    ('C-12','authenticated', 'public.goal_funding_snapshots','goal_funding_snapshots',
     'sel=T ins=T upd=T del=F','sel=T ins=T upd=T del=F','sel=T ins=F upd=F del=F'),
    ('C-14','authenticated', 'public.weekly_reconciliations','weekly_reconciliations',
     'sel=T ins=T upd=T del=T','sel=T ins=T upd=T del=T','sel=T ins=F upd=F del=F')
  ) AS v(cid, rol, tbl, obj, e_pre, e_p1, e_p2)
),
tb_act AS (
  SELECT cid, rol, obj, exp, rc,
         CASE WHEN rc IS NULL THEN NULL ELSE
           format('sel=%s ins=%s upd=%s del=%s',
             CASE WHEN has_table_privilege(rol, rc, 'SELECT') THEN 'T' ELSE 'F' END,
             CASE WHEN has_table_privilege(rol, rc, 'INSERT') THEN 'T' ELSE 'F' END,
             CASE WHEN has_table_privilege(rol, rc, 'UPDATE') THEN 'T' ELSE 'F' END,
             CASE WHEN has_table_privilege(rol, rc, 'DELETE') THEN 'T' ELSE 'F' END)
         END AS scored_act,
         CASE WHEN rc IS NULL THEN NULL ELSE
           CASE WHEN has_table_privilege(rol, rc, 'TRUNCATE') THEN 'T' ELSE 'F' END
         END AS trunc_info
  FROM tb
),
tb_rows AS (
  SELECT cid AS check_id, 'tbl-grant'::text AS category, obj AS object, rol AS role,
         (SELECT s FROM st) AS stage,
         CASE WHEN NOT (SELECT ok FROM st) THEN 'INVALID STAGE' ELSE exp END AS expected,
         COALESCE(scored_act || ' | info trunc=' || trunc_info, 'MISSING') AS actual,
         ((SELECT ok FROM st) AND COALESCE(scored_act = exp, false)) AS pass
  FROM tb_act
),
-- C-13: weekly_reconciliations × anon — RLS-inert control (NOT a raw ACL-equality assertion)
wrf AS (
  SELECT w.rc,
         (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = w.rc) AS rls_on,
         (SELECT count(*)::int FROM pg_policies p
           WHERE p.schemaname = 'public' AND p.tablename = 'weekly_reconciliations'
             AND (p.roles @> ARRAY['anon'::name] OR p.roles @> ARRAY['public'::name])
         ) AS anon_pub_policies,
         CASE WHEN w.rc IS NULL THEN NULL ELSE
           format('sel=%s ins=%s upd=%s del=%s trunc=%s',
             CASE WHEN has_table_privilege('anon', w.rc, 'SELECT')   THEN 'T' ELSE 'F' END,
             CASE WHEN has_table_privilege('anon', w.rc, 'INSERT')   THEN 'T' ELSE 'F' END,
             CASE WHEN has_table_privilege('anon', w.rc, 'UPDATE')   THEN 'T' ELSE 'F' END,
             CASE WHEN has_table_privilege('anon', w.rc, 'DELETE')   THEN 'T' ELSE 'F' END,
             CASE WHEN has_table_privilege('anon', w.rc, 'TRUNCATE') THEN 'T' ELSE 'F' END)
         END AS anon_acl_info
  FROM (SELECT to_regclass('public.weekly_reconciliations') AS rc) w
),
c13_row AS (
  SELECT 'C-13'::text AS check_id, 'tbl-grant'::text AS category,
         'weekly_reconciliations (anon RLS-inert control; raw ACL bits informational)'::text AS object,
         'anon'::text AS role, (SELECT s FROM st) AS stage,
         CASE WHEN NOT (SELECT ok FROM st) THEN 'INVALID STAGE'
              ELSE 'rls=T anon/public-policies=0' END AS expected,
         CASE WHEN rc IS NULL THEN 'MISSING'
              ELSE format('rls=%s anon/public-policies=%s | info anon-acl %s',
                          CASE WHEN COALESCE(rls_on, false) THEN 'T' ELSE 'F' END,
                          anon_pub_policies, anon_acl_info) END AS actual,
         ((SELECT ok FROM st) AND rc IS NOT NULL AND COALESCE(rls_on, false)
          AND anon_pub_policies = 0) AS pass
  FROM wrf
),
-- C-15 / C-16: the two PROTECTED pinned function-body MD5s (invariant all sitting)
md AS (
  SELECT v.cid, v.obj, v.pin,
         CASE WHEN to_regprocedure(v.sig) IS NULL THEN NULL
              ELSE md5(pg_get_functiondef(to_regprocedure(v.sig))) END AS act
  FROM (VALUES
    ('C-15','save_reconciliation_with_commitments body md5',
     'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)',
     '1bfde751ac647c5e9a25ba168d08150c'),
    ('C-16','save_goal_funding_snapshots body md5',
     'public.save_goal_funding_snapshots(INT, INT, JSONB)',
     '154231b3f180349ec328f08ccbe77076')
  ) AS v(cid, obj, sig, pin)
),
md_rows AS (
  SELECT cid AS check_id, 'fn-body-md5'::text AS category, obj AS object, '—'::text AS role,
         (SELECT s FROM st) AS stage,
         CASE WHEN NOT (SELECT ok FROM st) THEN 'INVALID STAGE' ELSE pin END AS expected,
         COALESCE(act, 'MISSING') AS actual,
         ((SELECT ok FROM st) AND COALESCE(act = pin, false)) AS pass
  FROM md
),
-- C-17: consolidated owner / SECURITY DEFINER invariant (owner=postgres ×6; secdef ×4)
ow AS (
  SELECT v.ord, v.k, v.need_sd, to_regprocedure(v.sig) AS f
  FROM (VALUES
    (1,'recon',     true,  'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)'),
    (2,'snap',      true,  'public.save_goal_funding_snapshots(INT, INT, JSONB)'),
    (3,'wrap',      true,  'public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)'),
    (4,'optb',      true,  'public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)'),
    (5,'is_owner',  false, 'public.is_owner()'),
    (6,'can_write', false, 'public.can_write_financials()')
  ) AS v(ord, k, need_sd, sig)
),
ow_f AS (
  SELECT o.ord, o.k, o.need_sd, o.f,
         (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid = o.f) AS owner,
         (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = o.f) AS sd
  FROM ow o
),
c17_row AS (
  SELECT 'C-17'::text AS check_id, 'fn-owner'::text AS category,
         'definer owner sweep (recon, snap, wrap, optb, is_owner, can_write)'::text AS object,
         '—'::text AS role, (SELECT s FROM st) AS stage,
         CASE WHEN NOT (SELECT ok FROM st) THEN 'INVALID STAGE'
              ELSE 'owner=postgres x6; secdef=T x4' END AS expected,
         (SELECT string_agg(
                   k || '=' || COALESCE(owner, 'MISSING') ||
                   CASE WHEN need_sd
                        THEN '/secdef=' || CASE WHEN COALESCE(sd, false) THEN 'T' ELSE 'F' END
                        ELSE '' END,
                   ', ' ORDER BY ord)
            FROM ow_f) AS actual,
         ((SELECT ok FROM st) AND
          (SELECT bool_and(f IS NOT NULL AND owner = 'postgres'
                           AND (NOT need_sd OR COALESCE(sd, false)))
             FROM ow_f)) AS pass
  FROM (SELECT 1) one
),
scored AS (
  SELECT * FROM fn_rows
  UNION ALL SELECT * FROM tb_rows
  UNION ALL SELECT * FROM c13_row
  UNION ALL SELECT * FROM md_rows
  UNION ALL SELECT * FROM c17_row
),
summary AS (
  SELECT 'SUMMARY'::text AS check_id, 'summary'::text AS category,
         'consolidated 17-check gate'::text AS object, '—'::text AS role,
         (SELECT s FROM st) AS stage,
         'pass_count=17 fail_count=0 emitted_rows=17'::text AS expected,
         format('pass_count=%s fail_count=%s emitted_rows=%s',
                count(*) FILTER (WHERE pass),
                count(*) FILTER (WHERE NOT pass),
                count(*)) AS actual,
         (count(*) = 17 AND count(*) FILTER (WHERE pass) = 17) AS pass   -- overall_pass
  FROM scored
)
SELECT check_id, category, object, role, stage, expected, actual, pass
FROM (SELECT * FROM scored UNION ALL SELECT * FROM summary) z
ORDER BY check_id;

-- ── Statement 5: trailing DO assertion — independently re-derives all 17 checks ──
-- RAISEs on: unknown/ambiguous environment; invalid stage; scored count <> 17; ANY check
-- false (failure list names the C-xx ids). Otherwise emits exactly ONE PASS notice naming
-- the stage. Read-only throughout (SELECT + RAISE only; an aborted READ ONLY txn has
-- nothing to roll back).
DO $$
DECLARE
  -- ▼▼ STAGE SELECTOR (edit 2 of 2 — MUST match the stage CTE literal above) ▼▼
  c_stage CONSTANT text := 'pre_phase_1';
  -- ▲▲ legal: pre_phase_1 | post_phase_1 | post_phase_2 ▲▲
  c_prod_sysid    CONSTANT BIGINT := 7632885393857617092;
  c_staging_sysid CONSTANT BIGINT := 0;  -- <<FILL exact staging system_identifier ONLY for a separately-authorized staging rehearsal; 0 = staging hard-stops until pinned.
  v_sysid BIGINT; v_has_appenv BOOLEAN; v_appenv_total INT; v_appenv_staging INT;
  v_staging_marker BOOLEAN; v_env TEXT;
  r RECORD;
  v_exp BOOLEAN; v_act BOOLEAN;
  v_exp_t TEXT; v_act_t TEXT;
  v_rc regclass; v_rls BOOLEAN; v_pol INT;
  v_all_ok BOOLEAN;
  v_pass BOOLEAN;
  v_emitted INT := 0;
  v_fails TEXT[] := ARRAY[]::text[];
BEGIN
  -- ── environment guard (same resolution pattern as -activation-grants.sql; unknown = HARD STOP) ──
  SELECT system_identifier INTO v_sysid FROM pg_control_system();
  v_has_appenv := to_regclass('public.app_environment') IS NOT NULL;
  v_staging_marker := false;
  IF v_has_appenv THEN
    SELECT count(*), count(*) FILTER (WHERE env = 'staging') INTO v_appenv_total, v_appenv_staging
      FROM public.app_environment;
    v_staging_marker := (v_appenv_total = 1 AND v_appenv_staging = 1);
  END IF;
  IF v_sysid = c_prod_sysid AND NOT v_has_appenv THEN v_env := 'production';
  ELSIF v_sysid = c_staging_sysid AND v_has_appenv AND v_staging_marker THEN v_env := 'staging';
  ELSE RAISE EXCEPTION 'CONSOLIDATED VALIDATION FAIL: unknown/ambiguous environment (sysid=%, app_environment=%, staging_marker=%). Aborting.', v_sysid, v_has_appenv, v_staging_marker;
  END IF;

  -- ── stage guard (fail closed on anything but the three legal stages) ──
  IF c_stage NOT IN ('pre_phase_1','post_phase_1','post_phase_2') THEN
    RAISE EXCEPTION 'CONSOLIDATED VALIDATION FAIL: invalid stage %. Legal: pre_phase_1 | post_phase_1 | post_phase_2.', c_stage;
  END IF;

  -- ── C-01…C-10: function EXECUTE posture ──
  FOR r IN
    SELECT * FROM (VALUES
      ('C-01','anon',          'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)', false, false, false),
      ('C-02','authenticated', 'public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)', true,  true,  false),
      ('C-03','anon',          'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)', false, false, false),
      ('C-04','authenticated', 'public.repair_commitments_for_week(INT, INT, TEXT, JSONB, JSONB)', true,  true,  false),
      ('C-05','anon',          'public.save_goal_funding_snapshots(INT, INT, JSONB)', false, false, false),
      ('C-06','authenticated', 'public.save_goal_funding_snapshots(INT, INT, JSONB)', true,  true,  false),
      ('C-07','anon',          'public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)', false, false, false),
      ('C-08','authenticated', 'public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)', false, true,  true),
      ('C-09','anon',          'public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)', false, false, false),
      ('C-10','authenticated', 'public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)', false, true,  true)
    ) AS v(cid, rol, sig, e_pre, e_p1, e_p2)
  LOOP
    v_exp := CASE c_stage WHEN 'pre_phase_1' THEN r.e_pre
                          WHEN 'post_phase_1' THEN r.e_p1
                          ELSE r.e_p2 END;
    v_act := CASE WHEN to_regprocedure(r.sig) IS NULL THEN NULL
                  ELSE has_function_privilege(r.rol, to_regprocedure(r.sig), 'EXECUTE') END;
    v_pass := COALESCE(v_act = v_exp, false);
    v_emitted := v_emitted + 1;
    IF NOT v_pass THEN v_fails := v_fails || r.cid; END IF;
  END LOOP;

  -- ── C-11 / C-12 / C-14: grouped table-privilege posture ──
  FOR r IN
    SELECT * FROM (VALUES
      ('C-11','anon',          'public.goal_funding_snapshots',
       'sel=F ins=F upd=F del=F','sel=F ins=F upd=F del=F','sel=F ins=F upd=F del=F'),
      ('C-12','authenticated', 'public.goal_funding_snapshots',
       'sel=T ins=T upd=T del=F','sel=T ins=T upd=T del=F','sel=T ins=F upd=F del=F'),
      ('C-14','authenticated', 'public.weekly_reconciliations',
       'sel=T ins=T upd=T del=T','sel=T ins=T upd=T del=T','sel=T ins=F upd=F del=F')
    ) AS v(cid, rol, tbl, e_pre, e_p1, e_p2)
  LOOP
    v_exp_t := CASE c_stage WHEN 'pre_phase_1' THEN r.e_pre
                            WHEN 'post_phase_1' THEN r.e_p1
                            ELSE r.e_p2 END;
    v_rc := to_regclass(r.tbl);
    v_act_t := CASE WHEN v_rc IS NULL THEN NULL ELSE
                 format('sel=%s ins=%s upd=%s del=%s',
                   CASE WHEN has_table_privilege(r.rol, v_rc, 'SELECT') THEN 'T' ELSE 'F' END,
                   CASE WHEN has_table_privilege(r.rol, v_rc, 'INSERT') THEN 'T' ELSE 'F' END,
                   CASE WHEN has_table_privilege(r.rol, v_rc, 'UPDATE') THEN 'T' ELSE 'F' END,
                   CASE WHEN has_table_privilege(r.rol, v_rc, 'DELETE') THEN 'T' ELSE 'F' END)
               END;
    v_pass := COALESCE(v_act_t = v_exp_t, false);
    v_emitted := v_emitted + 1;
    IF NOT v_pass THEN v_fails := v_fails || r.cid; END IF;
  END LOOP;

  -- ── C-13: weekly_reconciliations × anon — RLS-inert control ──
  v_rc := to_regclass('public.weekly_reconciliations');
  SELECT c.relrowsecurity INTO v_rls FROM pg_class c WHERE c.oid = v_rc;
  SELECT count(*)::int INTO v_pol FROM pg_policies p
   WHERE p.schemaname = 'public' AND p.tablename = 'weekly_reconciliations'
     AND (p.roles @> ARRAY['anon'::name] OR p.roles @> ARRAY['public'::name]);
  v_pass := (v_rc IS NOT NULL) AND COALESCE(v_rls, false) AND v_pol = 0;
  v_emitted := v_emitted + 1;
  IF NOT v_pass THEN v_fails := v_fails || 'C-13'::text; END IF;

  -- ── C-15 / C-16: pinned protected-body MD5s ──
  FOR r IN
    SELECT * FROM (VALUES
      ('C-15','public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)',
       '1bfde751ac647c5e9a25ba168d08150c'),
      ('C-16','public.save_goal_funding_snapshots(INT, INT, JSONB)',
       '154231b3f180349ec328f08ccbe77076')
    ) AS v(cid, sig, pin)
  LOOP
    v_act_t := CASE WHEN to_regprocedure(r.sig) IS NULL THEN NULL
                    ELSE md5(pg_get_functiondef(to_regprocedure(r.sig))) END;
    v_pass := COALESCE(v_act_t = r.pin, false);
    v_emitted := v_emitted + 1;
    IF NOT v_pass THEN v_fails := v_fails || r.cid; END IF;
  END LOOP;

  -- ── C-17: consolidated owner / SECURITY DEFINER invariant ──
  SELECT bool_and(f.oid IS NOT NULL
                  AND (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid = f.oid) = 'postgres'
                  AND (NOT f.need_sd OR COALESCE((SELECT p.prosecdef FROM pg_proc p WHERE p.oid = f.oid), false)))
    INTO v_all_ok
  FROM (
    SELECT to_regprocedure(v.sig) AS oid, v.need_sd
    FROM (VALUES
      ('public.save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)', true),
      ('public.save_goal_funding_snapshots(INT, INT, JSONB)', true),
      ('public.save_weekly_closeout_with_snapshots(INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT)', true),
      ('public.correct_goal_funding_snapshot(INT,INT,TEXT,NUMERIC,NUMERIC,TEXT)', true),
      ('public.is_owner()', false),
      ('public.can_write_financials()', false)
    ) AS v(sig, need_sd)
  ) f;
  v_pass := COALESCE(v_all_ok, false);
  v_emitted := v_emitted + 1;
  IF NOT v_pass THEN v_fails := v_fails || 'C-17'::text; END IF;

  -- ── gate ──
  IF v_emitted <> 17 THEN
    RAISE EXCEPTION 'CONSOLIDATED VALIDATION FAIL: derived % scored checks, expected exactly 17.', v_emitted;
  END IF;
  IF COALESCE(array_length(v_fails, 1), 0) > 0 THEN
    RAISE EXCEPTION 'CONSOLIDATED VALIDATION FAIL (stage=%, env=%): % of 17 checks false: %.',
      c_stage, v_env, array_length(v_fails, 1), array_to_string(v_fails, ', ');
  END IF;
  RAISE NOTICE 'CONSOLIDATED 17/17 PASS (stage=%, env=%).', c_stage, v_env;
END $$;

COMMIT;
