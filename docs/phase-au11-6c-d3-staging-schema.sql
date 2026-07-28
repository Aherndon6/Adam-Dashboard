-- ============================================================================
-- AU-11 Step 6C-D3 — STAGING SCHEMA (D-9 durable attribution)  [7D-B DRAFT]
-- ----------------------------------------------------------------------------
-- STAGING ONLY. NOT executed by Claude. Adam executes in the Supabase SQL Editor.
-- Implements the EXACT verified §E2 contract (design addendum lines 90-140), D-9:
--   • cash_commitments.cleared_transaction_id UUID
--   • fk_au11_cleared_txn  → transactions(id) ON UPDATE CASCADE ON DELETE RESTRICT (NOT DEFERRABLE)
--       (ON UPDATE CASCADE is present in §E2 addendum L96-99 — preserved verbatim, not added)
--   • chk_au11_cleared_txn_attribution  (total CASE CHECK)
--   • uix_au11_cleared_txn  partial UNIQUE index WHERE cleared_transaction_id IS NOT NULL
-- Migration order A→H, each step FAIL-CLOSED. The committed D1 reservation-shape CHECK is UNTOUCHED.
-- RESUMABILITY (precision #2): a same-named object is accepted ONLY if its catalog definition matches
--   the expected definition EXACTLY; any mismatch HARD-FAILs. IF NOT EXISTS alone is never relied upon.
-- ============================================================================

-- ── PRECONDITIONS (fail closed if the D1/D2/base surfaces are not present) ──
DO $$
BEGIN
  IF to_regclass('public.cash_commitments') IS NULL THEN RAISE EXCEPTION 'D3-SCHEMA precondition: public.cash_commitments missing'; END IF;
  IF to_regclass('public.transactions')     IS NULL THEN RAISE EXCEPTION 'D3-SCHEMA precondition: public.transactions missing'; END IF;
  IF to_regclass('public.discretionary_reservation_batches') IS NULL THEN RAISE EXCEPTION 'D3-SCHEMA precondition: D1 batch table missing'; END IF;
  -- staging guard
  IF NOT EXISTS (SELECT 1 FROM public.app_environment) OR EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging') THEN
    RAISE EXCEPTION 'D3-SCHEMA precondition: not staging (app_environment)'; END IF;
END $$;

-- ── STEP A — add column (resumable: accept only an exact-match existing column) ──
DO $$
DECLARE v_type text; v_nullable text; v_default text;
BEGIN
  SELECT data_type, is_nullable, column_default INTO v_type, v_nullable, v_default
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id';
  IF FOUND THEN
    IF v_type <> 'uuid' OR v_nullable <> 'YES' OR v_default IS NOT NULL THEN
      RAISE EXCEPTION 'D3-SCHEMA A: cleared_transaction_id exists with wrong shape (type=%, nullable=%, default=%); expected uuid/YES/NULL', v_type, v_nullable, v_default;
    END IF;  -- exact match ⇒ resume (no-op)
  ELSE
    ALTER TABLE public.cash_commitments ADD COLUMN cleared_transaction_id UUID;
  END IF;
END $$;

-- ── STEP B — FK NOT VALID (resumable: exact target + actions + deferrability) ──
DO $$
DECLARE v_deferrable boolean; v_updtype "char"; v_deltype "char"; v_confrelid oid; v_conkey smallint[]; v_confkey smallint[];
        v_exp_conkey smallint[]; v_exp_confkey smallint[];
BEGIN
  -- expected referencing/referenced column attnums (catalog identities, search_path-independent)
  SELECT ARRAY[attnum]::smallint[] INTO v_exp_conkey  FROM pg_attribute WHERE attrelid='public.cash_commitments'::regclass AND attname='cleared_transaction_id' AND NOT attisdropped;
  SELECT ARRAY[attnum]::smallint[] INTO v_exp_confkey FROM pg_attribute WHERE attrelid='public.transactions'::regclass     AND attname='id'                     AND NOT attisdropped;
  SELECT c.condeferrable, c.confupdtype, c.confdeltype, c.confrelid, c.conkey, c.confkey
    INTO v_deferrable, v_updtype, v_deltype, v_confrelid, v_conkey, v_confkey
    FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
   WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='fk_au11_cleared_txn' AND c.contype='f';
  IF FOUND THEN
    -- CATALOG-BASED exact match (search_path-independent; no formatted-text dependency):
    -- confupdtype 'c'=CASCADE, confdeltype 'r'=RESTRICT; NOT DEFERRABLE ⇒ condeferrable=false; referenced table + referencing/referenced columns exact.
    IF v_deferrable IS TRUE OR v_updtype <> 'c' OR v_deltype <> 'r'
       OR v_confrelid <> 'public.transactions'::regclass
       OR v_conkey  IS DISTINCT FROM v_exp_conkey
       OR v_confkey IS DISTINCT FROM v_exp_confkey THEN
      RAISE EXCEPTION 'D3-SCHEMA B: fk_au11_cleared_txn exists with wrong catalog definition (deferrable=%, updtype=%, deltype=%, confrelid=%, conkey=%, confkey=%)', v_deferrable, v_updtype, v_deltype, v_confrelid::regclass, v_conkey, v_confkey;
    END IF;  -- exact catalog match ⇒ resume
  ELSE
    ALTER TABLE public.cash_commitments
      ADD CONSTRAINT fk_au11_cleared_txn FOREIGN KEY (cleared_transaction_id)
      REFERENCES public.transactions(id) ON UPDATE CASCADE ON DELETE RESTRICT NOT VALID;  -- NOT DEFERRABLE (default)
  END IF;
END $$;

-- ── STEP C — attribution CHECK NOT VALID (resumable: exact canonical CASE expression) ──
DO $$
DECLARE v_def text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_def
    FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
   WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_cleared_txn_attribution';
  IF FOUND THEN
    -- normalize PostgreSQL canonical output: strip ::text casts AND parentheses AND whitespace before comparing (search_path/canonicalization-independent)
    IF lower(regexp_replace(regexp_replace(v_def,'::text','','g'),'[[:space:]()]','','g')) NOT LIKE '%casewhencommitment_source=''au11_reservation''andstatus=''cleared''thencleared_transaction_idisnotnullelsecleared_transaction_idisnull%' THEN
      RAISE EXCEPTION 'D3-SCHEMA C: chk_au11_cleared_txn_attribution exists with wrong expression: %', v_def;
    END IF;  -- exact match ⇒ resume
  ELSE
    ALTER TABLE public.cash_commitments
      ADD CONSTRAINT chk_au11_cleared_txn_attribution CHECK (
        CASE
          WHEN commitment_source = 'au11_reservation' AND status = 'cleared'
            THEN cleared_transaction_id IS NOT NULL
          ELSE cleared_transaction_id IS NULL
        END
      ) NOT VALID;
  END IF;
END $$;

-- ── STEP D — partial UNIQUE index (resumable: exact def + predicate; NO NOT VALID phase) ──
DO $$
DECLARE v_def text;
BEGIN
  SELECT pg_get_indexdef(i.indexrelid) INTO v_def
    FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
   WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn';
  IF FOUND THEN
    IF NOT (v_def ILIKE '%UNIQUE INDEX uix_au11_cleared_txn%' AND v_def ILIKE '%(cleared_transaction_id)%'
            AND v_def ILIKE '%WHERE (cleared_transaction_id IS NOT NULL)%') THEN
      RAISE EXCEPTION 'D3-SCHEMA D: uix_au11_cleared_txn exists with wrong definition: %', v_def;
    END IF;  -- exact match ⇒ resume
  ELSE
    CREATE UNIQUE INDEX uix_au11_cleared_txn
      ON public.cash_commitments (cleared_transaction_id)
      WHERE cleared_transaction_id IS NOT NULL;
  END IF;
END $$;

-- ── STEP E — VALIDATE FK (safe/idempotent; errors on any violating row) ──
ALTER TABLE public.cash_commitments VALIDATE CONSTRAINT fk_au11_cleared_txn;

-- ── STEP F — VALIDATE CHECK (safe/idempotent; errors on any invariant violation) ──
ALTER TABLE public.cash_commitments VALIDATE CONSTRAINT chk_au11_cleared_txn_attribution;

-- ── STEP G — explicit invariant queries: ALL THREE must be 0, plus valid flags ──
DO $$
DECLARE v_a bigint; v_b bigint; v_c bigint; v_fkvalid boolean; v_chkvalid boolean; v_idx boolean;
BEGIN
  SELECT count(*) INTO v_a FROM public.cash_commitments
    WHERE commitment_source <> 'au11_reservation' AND cleared_transaction_id IS NOT NULL;
  SELECT count(*) INTO v_b FROM public.cash_commitments
    WHERE commitment_source = 'au11_reservation' AND status = 'cleared' AND cleared_transaction_id IS NULL;
  SELECT count(*) INTO v_c FROM public.cash_commitments
    WHERE commitment_source = 'au11_reservation' AND status <> 'cleared' AND cleared_transaction_id IS NOT NULL;
  IF v_a <> 0 OR v_b <> 0 OR v_c <> 0 THEN
    RAISE EXCEPTION 'D3-SCHEMA G: attribution invariant violated (non_au11_set=%, au11_cleared_null=%, au11_noncleared_set=%)', v_a, v_b, v_c;
  END IF;
  SELECT c.convalidated INTO v_fkvalid  FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='fk_au11_cleared_txn';
  SELECT c.convalidated INTO v_chkvalid FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_cleared_txn_attribution';
  SELECT EXISTS (SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace
                  WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i') INTO v_idx;
  IF v_fkvalid IS NOT TRUE OR v_chkvalid IS NOT TRUE OR v_idx IS NOT TRUE THEN
    RAISE EXCEPTION 'D3-SCHEMA G: post-validate flags (fk_valid=%, chk_valid=%, index_present=%)', v_fkvalid, v_chkvalid, v_idx;
  END IF;
  RAISE NOTICE 'D3-SCHEMA A-G PASS: cleared_transaction_id + fk_au11_cleared_txn + chk_au11_cleared_txn_attribution + uix_au11_cleared_txn installed & validated; attribution invariant = 0/0/0.';
END $$;

-- ── STEP H — the composite RPC is created by phase-au11-6c-d3-staging-composite-rpc.sql
--             ONLY AFTER A-G pass. (Kept in a separate artifact so schema and RPC apply independently.)
-- ============================================================================
