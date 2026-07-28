-- ============================================================================
-- AU-11 Step 6C-D3 — STAGING ROLLBACK (§8A pre-live-attribution bare-drop)  [7D-B DRAFT]
-- STAGING ONLY. NOT executed by Claude. Reverses the D-9 schema + composite RPC in reverse dependency order.
-- FAIL-CLOSED: aborts if ANY non-fixture cleared_transaction_id exists (live attribution) — bare-drop would
-- erase real cleared evidence. Post-live-attribution rollback (§8B) is a SEPARATE evidence-preservation
-- migration requiring explicit owner approval + independent architecture review, and is NOT this artifact.
-- CERTIFICATION: all D3-object absence checks are SCHEMA/TABLE-QUALIFIED (public.cash_commitments), and the
-- rollback ALSO certifies the D1 shape CHECK (chk_au11_reservation_shape) survives — exactly one validated CHECK
-- on public.cash_commitments with the pinned normalized definition (reused from the D2-proven canon).
-- ============================================================================
BEGIN;

-- ── GUARD: no non-fixture attribution may exist ──
DO $g$
DECLARE v_live int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.app_environment) OR EXISTS (SELECT 1 FROM public.app_environment WHERE env IS DISTINCT FROM 'staging') THEN
    RAISE EXCEPTION 'D3-ROLLBACK: not staging'; END IF;
  -- "non-fixture" = an au11 reservation carrying an attribution whose expected_item_id is NOT a d3fix row.
  SELECT count(*) INTO v_live FROM public.cash_commitments
   WHERE commitment_source='au11_reservation' AND cleared_transaction_id IS NOT NULL
     AND expected_item_id NOT LIKE 'd3fix_%';
  IF v_live > 0 THEN
    RAISE EXCEPTION 'D3-ROLLBACK ABORT: % non-fixture attribution row(s) exist — bare-drop prohibited; use the §8B evidence-preservation migration (owner approval + independent review)', v_live;
  END IF;
END $g$;

-- ── (1) drop the composite RPC ──
DROP FUNCTION IF EXISTS public.close_week_with_reservations_v1(
  INT,INT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,JSONB,JSONB,JSONB,TEXT,INT,JSONB);

-- ── (2) drop the attribution CHECK (additive; nothing to restore — D1 shape CHECK was never modified) ──
ALTER TABLE public.cash_commitments DROP CONSTRAINT IF EXISTS chk_au11_cleared_txn_attribution;

-- ── (3) drop the partial unique index ──
DROP INDEX IF EXISTS public.uix_au11_cleared_txn;

-- ── (4) drop the FK ──
ALTER TABLE public.cash_commitments DROP CONSTRAINT IF EXISTS fk_au11_cleared_txn;

-- ── (5) drop the column ──
ALTER TABLE public.cash_commitments DROP COLUMN IF EXISTS cleared_transaction_id;

-- ── (6) absence certification (SCHEMA/TABLE-QUALIFIED) + D1 shape CHECK invariant certification ──
DO $c$
DECLARE
  v_def text;
  -- pinned normalized def of the LIVE chk_au11_reservation_shape (reused verbatim from the D2-proven canon;
  -- normalization = lower + strip ::text + strip parens/whitespace).
  c_expected_def CONSTANT text :=
    $canon$checkcommitment_class='discretionary_goal_transfer'andcommitment_source='au11_reservation'andreservation_batch_idisnotnullandgoal_idisnotnullanddestination_account_refisnotnullandrequired_or_discretionary='discretionary_deployment'andsource_account='truist_checking'orcommitment_class<>'discretionary_goal_transfer'andcommitment_source<>'au11_reservation'andreservation_batch_idisnullandgoal_idisnullanddestination_account_refisnullandbank_referenceisnullandbank_submitted_atisnull$canon$;
BEGIN
  -- D3 objects ABSENT (schema/table-qualified: cannot false-detect a same-named object elsewhere)
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id') THEN
    RAISE EXCEPTION 'D3-ROLLBACK residue: column'; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
              WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname IN ('fk_au11_cleared_txn','chk_au11_cleared_txn_attribution')) THEN
    RAISE EXCEPTION 'D3-ROLLBACK residue: constraint'; END IF;
  IF EXISTS (SELECT 1 FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace
              WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i') THEN
    RAISE EXCEPTION 'D3-ROLLBACK residue: index'; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public' AND p.proname='close_week_with_reservations_v1') THEN
    RAISE EXCEPTION 'D3-ROLLBACK residue: function'; END IF;

  -- D1 INVARIANT: exactly one VALIDATED chk_au11_reservation_shape CHECK on public.cash_commitments...
  IF (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
       WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_reservation_shape'
         AND c.contype='c' AND c.convalidated) <> 1 THEN
    RAISE EXCEPTION 'D3-ROLLBACK: D1 shape CHECK (chk_au11_reservation_shape) is not exactly one validated CHECK on public.cash_commitments'; END IF;
  -- ...with the pinned normalized definition (fail-closed on drift)
  SELECT lower(regexp_replace(regexp_replace(pg_get_constraintdef(c.oid), '::text', '', 'g'), '[()[:space:]]', '', 'g')) INTO v_def
    FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
   WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_reservation_shape';
  IF v_def IS DISTINCT FROM c_expected_def THEN
    RAISE EXCEPTION 'D3-ROLLBACK: D1 shape CHECK definition drift.  actual=[%]', v_def; END IF;

  RAISE NOTICE 'D3-ROLLBACK PASS: D3 objects removed (schema/table-qualified); D1 shape CHECK present, validated, definition intact.';
END $c$;

-- ── (7) corroboration result — DURABLE EVIDENCE (editor shows this last result set) ──
--   D3 objects absent (qualified) + D1 shape CHECK present & valid + computed result.
SELECT 'RB_absence' AS check_name,
       (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id') AS col,                                                                       -- 0
       (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='fk_au11_cleared_txn') AS fk,               -- 0
       (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_cleared_txn_attribution') AS chk, -- 0
       (SELECT count(*) FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i') AS idx,  -- 0
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='close_week_with_reservations_v1') AS fn,                                                                              -- 0
       (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_reservation_shape' AND c.contype='c' AND c.convalidated) AS d1_shape_valid,  -- 1
       CASE WHEN (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id')=0
             AND (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname IN ('fk_au11_cleared_txn','chk_au11_cleared_txn_attribution'))=0
             AND (SELECT count(*) FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND ic.relname='uix_au11_cleared_txn' AND ic.relkind='i')=0
             AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='close_week_with_reservations_v1')=0
             AND (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='public' AND t.relname='cash_commitments' AND c.conname='chk_au11_reservation_shape' AND c.contype='c' AND c.convalidated)=1
            THEN 'PASS' ELSE 'FAIL' END AS result;
COMMIT;
-- ============================================================================
