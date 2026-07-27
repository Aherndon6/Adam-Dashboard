-- ============================================================================
-- AU-11 Step 6C-D2 — DETERMINISTIC STAGING FIXTURE (setup) — ledger-tracked ownership
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Executed by Adam. Creates a clearly-labeled, provably-removable fixture sufficient to run
-- the FULL D2 validation matrix with NO SKIPs. Idempotent / re-runnable. Fails CLOSED before any mutation
-- if it cannot install safely.
--
-- OWNER IDENTITY (revised — app_users.auth_user_id HAS a FK to auth.users on staging): the fixture does NOT
-- synthesize an owner. It REUSES an existing active owner via the CANONICAL selection used identically in
-- fixture/validation/concurrency:
--     WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
--       AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id)   -- proves auth.users backing
--     ORDER BY au.auth_user_id LIMIT 1                                          -- deterministic, immutable
-- If none qualifies it HARD STOPs and directs provisioning via a supported Supabase mechanism (Dashboard →
-- Authentication → Add user, then set that user's app_users row role='owner', active=true). No auth.users
-- manual insert, no FK/constraint change. The real is_owner() gate is exercised with a genuine owner identity.
--
-- OWNERSHIP MECHANISM (Req 3): `public.d2_fixture_ledger(kind,ref)` records exactly which rows this fixture
-- OWNS and later removes (goal_registry, goal_funding_snapshots, weekly_reconciliations — NOT app_users, which
-- the fixture never creates). A PREFLIGHT aborts, before touching anything, if any fixture key already exists
-- WITHOUT being ledgered (a legitimate/foreign row) — so the fixture never overwrites real data and teardown
-- (which deletes ONLY ledgered keys) can never remove a legitimate row.
--
-- Deterministic identifiers:
--   basis    : weekly_reconciliations.week_num = 31 (forced MAX; sentinel balances 3131.31.. secondary marker)
--   snapshots: 9 at (2026, 31) — one per fixture goal; created_by_user_id NULL (avoids auth.users FK)
--   goals    : goal_registry.id d2fix_g01..d2fix_g09
--     g01,g02,g03 reservable=true/status funding/valid dest  → happy path
--     g04 reservable=false ; g05 status=funded ; g06 empty dest ; g07-09 planned filler (for the ≥9 count)
-- ============================================================================
BEGIN;

-- ── guards ──
DO $$ BEGIN
  IF to_regclass('public.app_environment') IS NULL OR NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') THEN
    RAISE EXCEPTION 'HARD STOP: not staging — refusing to seed D2 fixture.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable') THEN
    RAISE EXCEPTION 'HARD STOP: goal_registry.reservable missing — apply phase-au11-6c-d2-goal-registry-reservable.sql first.'; END IF;
END $$;

-- ── owner prerequisite: an existing active owner with a real auth identity MUST exist (fixture reuses it) ──
DO $$
DECLARE v_owner UUID;
BEGIN
  -- CANONICAL owner selection (identical in fixture/validation/concurrency): owner + active + real
  -- auth.users backing (EXISTS proves the FK-referenced row is present + detects drift), deterministic
  -- immutable ORDER BY auth_user_id.
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au
   WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id)
   ORDER BY au.auth_user_id LIMIT 1;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: no active owner with a real auth.users identity in app_users. The fixture does not synthesize an owner (app_users.auth_user_id -> auth.users FK). Provision a staging owner via Supabase Dashboard (Authentication -> Add user), set its app_users row role=owner/active, then re-run.';
  END IF;
END $$;

-- ── ledger table (fixture scaffolding; dropped by teardown). Secured explicitly: RLS ON, no policies,
--    client roles revoked. It is only ever touched by the administrative SQL execution context (fixture /
--    validation / teardown), so no client-role access is required; RLS-with-no-policy denies all non-owner/
--    non-superuser access by default. ──
CREATE TABLE IF NOT EXISTS public.d2_fixture_ledger (
  kind TEXT NOT NULL,
  ref  TEXT NOT NULL,
  PRIMARY KEY (kind, ref)
);
ALTER TABLE public.d2_fixture_ledger ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.d2_fixture_ledger FROM anon, authenticated;

-- ── PREFLIGHT: fail CLOSED before any mutation if a fixture key exists un-ledgered (= foreign/legitimate) ──
DO $$
DECLARE v_bad TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM public.weekly_reconciliations w
              WHERE w.week_num = 31
                AND NOT EXISTS (SELECT 1 FROM public.d2_fixture_ledger l WHERE l.kind='weekly_reconciliations' AND l.ref='31')) THEN
    RAISE EXCEPTION 'HARD STOP: weekly_reconciliations week 31 exists and is NOT fixture-owned — refusing (would overwrite legitimate data).'; END IF;

  SELECT string_agg(g.id, ', ') INTO v_bad
    FROM public.goal_registry g
   WHERE g.id LIKE 'd2fix_%'
     AND NOT EXISTS (SELECT 1 FROM public.d2_fixture_ledger l WHERE l.kind='goal_registry' AND l.ref=g.id);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: d2fix_ goal(s) exist and are NOT fixture-owned [%] — refusing.', v_bad; END IF;

  SELECT string_agg(s.goal_id, ', ') INTO v_bad
    FROM public.goal_funding_snapshots s
   WHERE s.model_year=2026 AND s.week_num=31 AND s.goal_id LIKE 'd2fix_%'
     AND NOT EXISTS (SELECT 1 FROM public.d2_fixture_ledger l WHERE l.kind='goal_funding_snapshots' AND l.ref = '2026:31:'||s.goal_id);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: fixture snapshot(s) exist and are NOT fixture-owned [%] — refusing.', v_bad; END IF;
END $$;

-- ── record ownership in the ledger (idempotent) BEFORE writing the base tables ──
INSERT INTO public.d2_fixture_ledger (kind, ref) VALUES ('weekly_reconciliations','31') ON CONFLICT DO NOTHING;
INSERT INTO public.d2_fixture_ledger (kind, ref)
  SELECT 'goal_registry', x FROM unnest(ARRAY['d2fix_g01','d2fix_g02','d2fix_g03','d2fix_g04','d2fix_g05','d2fix_g06','d2fix_g07','d2fix_g08','d2fix_g09']) AS x
  ON CONFLICT DO NOTHING;
INSERT INTO public.d2_fixture_ledger (kind, ref)
  SELECT 'goal_funding_snapshots', '2026:31:'||x FROM unnest(ARRAY['d2fix_g01','d2fix_g02','d2fix_g03','d2fix_g04','d2fix_g05','d2fix_g06','d2fix_g07','d2fix_g08','d2fix_g09']) AS x
  ON CONFLICT DO NOTHING;

-- ── 1) fixture goals (upsert reaches DO UPDATE only for fixture-owned keys — preflight guaranteed) ──
INSERT INTO public.goal_registry (id, name, tier, target, priority, status, reservable, dest, auto)
VALUES
  ('d2fix_g01','D2 Fixture Goal 01','fixture',1000,101,'funding',true ,'Fixture Checking A',false),
  ('d2fix_g02','D2 Fixture Goal 02','fixture',1000,102,'funding',true ,'Fixture Checking B',false),
  ('d2fix_g03','D2 Fixture Goal 03','fixture',1000,103,'funding',true ,'Fixture Checking C',false),
  ('d2fix_g04','D2 Fixture Goal 04','fixture',1000,104,'funding',false,'Fixture Checking D',false),
  ('d2fix_g05','D2 Fixture Goal 05','fixture',1000,105,'funded' ,true ,'Fixture Checking E',false),
  ('d2fix_g06','D2 Fixture Goal 06','fixture',1000,106,'funding',true ,''                  ,false),
  ('d2fix_g07','D2 Fixture Goal 07','fixture',1000,107,'planned',false,'Fixture Checking G',false),
  ('d2fix_g08','D2 Fixture Goal 08','fixture',1000,108,'planned',false,'Fixture Checking H',false),
  ('d2fix_g09','D2 Fixture Goal 09','fixture',1000,109,'planned',false,'Fixture Checking I',false)
ON CONFLICT (id) DO UPDATE
  SET name=EXCLUDED.name, tier=EXCLUDED.tier, target=EXCLUDED.target, priority=EXCLUDED.priority,
      status=EXCLUDED.status, reservable=EXCLUDED.reservable, dest=EXCLUDED.dest, auto=EXCLUDED.auto;

-- ── 2) fixture basis reconciliation (forces MAX(week_num)=31). balance_basis is a value-restricted TEXT
--    column (CHECK IN 'posted_current_balance','available_balance','unknown') — use 'unknown' for the synthetic
--    fixture row. The fixture-ownership sentinel is the numeric chk=3131.31 (unchanged). ──
INSERT INTO public.weekly_reconciliations (week_num, chk, sav, amx, tax, lc, balance_basis, recorded_at)
VALUES (31, 3131.31, 3131.32, 3131.33, 3131.34, 3131.35, 'unknown', NOW())
ON CONFLICT (week_num) DO UPDATE
  SET chk=EXCLUDED.chk, sav=EXCLUDED.sav, amx=EXCLUDED.amx, tax=EXCLUDED.tax, lc=EXCLUDED.lc,
      balance_basis=EXCLUDED.balance_basis, recorded_at=NOW();

-- ── 3) fixture snapshots: 9 at (2026, 31), one per fixture goal (created_by_user_id NULL on purpose) ──
INSERT INTO public.goal_funding_snapshots (model_year, week_num, goal_id, funded_amount, source, note, created_by_user_id)
SELECT 2026, 31, id, 100.00, 'reconciliation', '[STAGING-FIXTURE-D2]', NULL
  FROM public.goal_registry WHERE id LIKE 'd2fix_%'
ON CONFLICT (model_year, week_num, goal_id) DO UPDATE
  SET funded_amount=EXCLUDED.funded_amount, source=EXCLUDED.source, note=EXCLUDED.note;

COMMIT;

-- ── verification (post-commit; simulation GUCs are transaction-local and auto-reset) ──
DO $$
DECLARE v_owner UUID; v_ok BOOLEAN; v_n INT;
BEGIN
  SELECT au.auth_user_id INTO v_owner FROM public.app_users au
   WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id)
   ORDER BY au.auth_user_id LIMIT 1;

  IF (SELECT max(week_num) FROM public.weekly_reconciliations) <> 31 THEN
    RAISE WARNING 'FIX-CHECK basis: MAX(week_num) is % (expected 31)', (SELECT max(week_num) FROM public.weekly_reconciliations);
  ELSE RAISE NOTICE 'FIX-CHECK basis OK: MAX(week_num)=31'; END IF;

  SELECT count(*) INTO v_n FROM public.goal_funding_snapshots WHERE model_year=2026 AND week_num=31;
  IF v_n < 9 THEN RAISE WARNING 'FIX-CHECK snapshots: only % at (2026,31) (need >=9)', v_n;
  ELSE RAISE NOTICE 'FIX-CHECK snapshots OK: % at (2026,31)', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.goal_registry WHERE id LIKE 'd2fix_%' AND reservable=true AND status IN ('planned','funding') AND btrim(COALESCE(dest,''))<>'';
  IF v_n < 2 THEN RAISE WARNING 'FIX-CHECK reservable goals: only % eligible (need >=2)', v_n;
  ELSE RAISE NOTICE 'FIX-CHECK reservable goals OK: % eligible (d2fix_g01..g03)', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.goal_registry WHERE reservable=true AND id NOT LIKE 'd2fix_%';
  IF v_n <> 0 THEN RAISE WARNING 'FIX-CHECK implicit-reservable: % non-fixture goals are reservable (expected 0)', v_n;
  ELSE RAISE NOTICE 'FIX-CHECK implicit-reservable OK: 0 non-fixture goals reservable'; END IF;

  IF v_owner IS NULL THEN
    RAISE WARNING 'FIX-CHECK owner: no active owner found (should not happen — prerequisite passed)';
  ELSE
    -- The is_owner() simulation must set role=authenticated + jwt claims. Those are TRANSACTION-scoped GUCs, so
    -- they would otherwise leak past this DO into the FIX_ledger SELECT below and hit the RLS'd/revoked ledger
    -- as authenticated (permission denied). Run the simulation inside a nested subtransaction that ALWAYS rolls
    -- back (via a sentinel), which UNDOES the SET LOCAL role/claims and restores the administrative role. v_ok is
    -- captured before the rollback, so the result survives. No GRANT to the ledger is required or made.
    BEGIN
      PERFORM set_config('role','authenticated',true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
      SELECT public.is_owner() INTO v_ok;
      RAISE EXCEPTION 'au11 role-reset sentinel';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE 'au11 role-reset sentinel%' THEN RAISE; END IF;
    END;
    -- role/claims are now restored to the administrative context
    IF v_ok THEN RAISE NOTICE 'FIX-CHECK owner OK: is_owner() true for the reused staging owner (%).', v_owner;
    ELSE RAISE WARNING 'FIX-CHECK owner: is_owner() FALSE for the reused owner uid %', v_owner; END IF;
  END IF;
END $$;

-- ── ledger snapshot (evidence of exactly what the fixture owns — 19 refs total). Runs as the administrative
--    role (the is_owner() simulation above self-reset via subtransaction rollback), so it can read the secured
--    ledger without any grant to anon/authenticated. ──
SELECT 'FIX_ledger' AS check_name, kind, count(*) AS n FROM public.d2_fixture_ledger GROUP BY kind ORDER BY kind;
-- Fixture ready. Run validation next; remove with the teardown file.
