-- ════════════════════════════════════════════════════════════════════════════
-- 2027 rollover Package C: stand-ins for the hermetic server tests (tools/rollover-pg.js).
--
-- SYNTHETIC HARNESS, NOT PRODUCTION. Each object below replaces a Supabase or pre-repository
-- object that Package C does not change or test. Everything else in the test database is the
-- repository's own SQL, extracted verbatim (tools/rollover-pg.js BASE_OBJECTS).
--
--   Stand-in                         Real object                                 Fidelity
--   anon, authenticated roles        Supabase API roles                          name only (for ACL checks)
--   auth.users, auth.uid()           Supabase auth schema                        uid() reads the test GUC request.jwt.claim.sub
--   is_owner(), can_write_financials(),
--   is_allowed_user()                role helpers keyed on auth.uid() + role     read the test GUC test.role
--                                                                                (owner | household_admin | none)
--   goal_registry                    phase-6a table (more columns)               only the columns these functions read:
--                                                                                id, status (same CHECK), auto, updated_at
--   weekly_reconciliations           pre-repository table (more columns)         week_num UNIQUE + the columns the RPCs read
-- ════════════════════════════════════════════════════════════════════════════
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $$;

CREATE SCHEMA auth;
CREATE TABLE auth.users (id UUID PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS
  $$ SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

CREATE FUNCTION public.is_owner() RETURNS BOOLEAN LANGUAGE sql STABLE AS
  $$ SELECT COALESCE(current_setting('test.role', true), 'owner') = 'owner' $$;
CREATE FUNCTION public.can_write_financials() RETURNS BOOLEAN LANGUAGE sql STABLE AS
  $$ SELECT COALESCE(current_setting('test.role', true), 'owner') IN ('owner', 'household_admin') $$;
CREATE FUNCTION public.is_allowed_user() RETURNS BOOLEAN LANGUAGE sql STABLE AS
  $$ SELECT COALESCE(current_setting('test.role', true), 'owner') IN ('owner', 'household_admin') $$;

CREATE TABLE public.goal_registry (
  id         TEXT PRIMARY KEY,
  status     TEXT NOT NULL DEFAULT 'planned'
               CHECK (status IN ('planned','funding','funded','executed','paused','archived')),
  auto       BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.weekly_reconciliations (
  week_num    INT NOT NULL UNIQUE,
  chk         NUMERIC, sav NUMERIC, amx NUMERIC, tax NUMERIC, lc NUMERIC,
  recorded_at TIMESTAMPTZ
);
