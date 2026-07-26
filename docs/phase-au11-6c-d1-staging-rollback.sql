-- ============================================================================
-- AU-11 Step 6C-D1 — STAGING-ONLY rollback of the reservation-persistence migration
-- ----------------------------------------------------------------------------
-- STAGING ONLY. Executed by Adam. Reverses phase-au11-6c-d1-staging-migration.sql
-- exactly. LEGAL ONLY while: zero discretionary_goal_transfer rows AND zero batch
-- rows AND no dependent 6C-D2+ RPCs/objects. One transaction.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.app_environment') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.app_environment WHERE env = 'staging') THEN
    RAISE EXCEPTION 'HARD STOP: not staging. Refusing to roll back.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.cash_commitments WHERE commitment_class = 'discretionary_goal_transfer') THEN
    RAISE EXCEPTION 'HARD STOP: discretionary_goal_transfer rows exist — rollback illegal.';
  END IF;
  IF to_regclass('public.discretionary_reservation_batches') IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.discretionary_reservation_batches) THEN
    RAISE EXCEPTION 'HARD STOP: batch rows exist — rollback illegal.';
  END IF;
  -- 6C-D2+ dependency guard: refuse if the create RPC already exists
  IF to_regprocedure('public.create_discretionary_goal_reservation_v1(int,int,text,text,date,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'HARD STOP: 6C-D2 RPC present — resolve later slices before rolling back D1.';
  END IF;
END $$;

-- reverse order: indexes -> FK -> shape -> batch table -> widened CHECKs -> columns
DROP INDEX IF EXISTS public.ix_au11_active;
DROP INDEX IF EXISTS public.uix_au11_batch_goal;
ALTER TABLE public.cash_commitments DROP CONSTRAINT IF EXISTS fk_au11_batch;
DROP INDEX IF EXISTS public.uix_one_active_batch;   -- dropped with the table, explicit for clarity
DROP TABLE IF EXISTS public.discretionary_reservation_batches;
ALTER TABLE public.cash_commitments DROP CONSTRAINT IF EXISTS chk_au11_reservation_shape;

-- restore the ORIGINAL 7-value class CHECK and 3-value source CHECK (catalog-dynamic drop of the widened ones)
DO $$
DECLARE v_cls TEXT; v_src TEXT;
BEGIN
  SELECT conname INTO v_cls FROM pg_constraint
    WHERE conrelid='public.cash_commitments'::regclass AND contype='c'
      AND pg_get_constraintdef(oid) ILIKE '%commitment_class%';
  SELECT conname INTO v_src FROM pg_constraint
    WHERE conrelid='public.cash_commitments'::regclass AND contype='c'
      AND pg_get_constraintdef(oid) ILIKE '%commitment_source%';
  IF v_cls IS NOT NULL THEN EXECUTE format('ALTER TABLE public.cash_commitments DROP CONSTRAINT %I', v_cls); END IF;
  IF v_src IS NOT NULL THEN EXECUTE format('ALTER TABLE public.cash_commitments DROP CONSTRAINT %I', v_src); END IF;
  ALTER TABLE public.cash_commitments ADD CONSTRAINT cash_commitments_commitment_class_check
    CHECK (commitment_class IN ('credit_card_payment','rent','bill_payment','tax_transfer',
                                'savings_transfer','manual_hold','other_transfer'));   -- restore 7
  ALTER TABLE public.cash_commitments ADD CONSTRAINT cash_commitments_commitment_source_check
    CHECK (commitment_source IN ('wd_reconciliation','manual_reconciliation','historical_repair')); -- restore 3
END $$;

ALTER TABLE public.cash_commitments
  DROP COLUMN IF EXISTS bank_submitted_at,
  DROP COLUMN IF EXISTS bank_reference,
  DROP COLUMN IF EXISTS destination_account_ref,
  DROP COLUMN IF EXISTS goal_id,
  DROP COLUMN IF EXISTS reservation_batch_id;

COMMIT;
-- NOTE: the ORIGINAL CHECK constraint NAMES must match the preflight-captured names.
-- If the preflight shows different original names, edit the two ADD CONSTRAINT names above
-- before running (do not assume the July-7 export names).
