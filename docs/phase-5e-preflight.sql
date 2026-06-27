-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5E-1 Preflight Checks
-- ═══════════════════════════════════════════════════════════════════════════
-- Run ALL queries before executing phase-5e-migration.sql.
-- Every check must return the documented expected value.
-- Stop and investigate any failure before proceeding.
-- ─────────────────────────────────────────────────────────────────────────

-- P1: transactions table must NOT already exist
SELECT 'P1' AS check,
       NOT EXISTS (
         SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = 'transactions'
       ) AS expected_true;

-- P2: fn_set_updated_at trigger function must exist (created in Phase 5D-1)
SELECT 'P2' AS check,
       EXISTS (
         SELECT 1 FROM pg_proc
         WHERE proname = 'fn_set_updated_at'
           AND pronamespace = 'public'::regnamespace
       ) AS expected_true;

-- P3: is_allowed_user() function must exist
SELECT 'P3' AS check,
       EXISTS (
         SELECT 1 FROM pg_proc
         WHERE proname = 'is_allowed_user'
           AND pronamespace = 'public'::regnamespace
       ) AS expected_true;

-- P4: is_owner() function must exist
SELECT 'P4' AS check,
       EXISTS (
         SELECT 1 FROM pg_proc
         WHERE proname = 'is_owner'
           AND pronamespace = 'public'::regnamespace
       ) AS expected_true;

-- P5: accounts table must exist with key column
SELECT 'P5' AS check,
       EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name   = 'accounts'
           AND column_name  = 'key'
       ) AS expected_true;

-- P5a: accounts.key must be a PK or UNIQUE — valid FK target.
-- The migration's REFERENCES accounts(key) will fail at runtime if this check fails,
-- but catching it here avoids a confusing error mid-migration.
SELECT 'P5a' AS check,
       EXISTS (
         SELECT 1
           FROM information_schema.table_constraints tc
           JOIN information_schema.key_column_usage kcu
             ON kcu.constraint_name = tc.constraint_name
            AND kcu.table_schema    = tc.table_schema
          WHERE tc.table_schema  = 'public'
            AND tc.table_name    = 'accounts'
            AND kcu.column_name  = 'key'
            AND tc.constraint_type IN ('PRIMARY KEY','UNIQUE')
       ) AS expected_true;

-- P6: categories table must exist with key column
SELECT 'P6' AS check,
       EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name   = 'categories'
           AND column_name  = 'key'
       ) AS expected_true;

-- P6a: categories.key must be a PK or UNIQUE — valid FK target.
SELECT 'P6a' AS check,
       EXISTS (
         SELECT 1
           FROM information_schema.table_constraints tc
           JOIN information_schema.key_column_usage kcu
             ON kcu.constraint_name = tc.constraint_name
            AND kcu.table_schema    = tc.table_schema
          WHERE tc.table_schema  = 'public'
            AND tc.table_name    = 'categories'
            AND kcu.column_name  = 'key'
            AND tc.constraint_type IN ('PRIMARY KEY','UNIQUE')
       ) AS expected_true;

-- P7: auth schema must be present (Supabase auth)
SELECT 'P7' AS check,
       EXISTS (
         SELECT 1 FROM information_schema.schemata
         WHERE schema_name = 'auth'
       ) AS expected_true;
