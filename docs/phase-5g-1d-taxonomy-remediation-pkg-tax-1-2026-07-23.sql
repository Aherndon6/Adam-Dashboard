-- ═══════════════════════════════════════════════════════════════════════════
-- PKG-TAX-1 — Goal-Transfer Taxonomy Remediation  ·  HARDENED, EXECUTION QUALITY
-- Target: production Adam-Dashboard (usayoldrawwmjsmretin)
-- Venue:  Supabase SQL editor — REQUIRED FOR ATOMICITY, not for permission (see §0)
-- Scope:  2 category INSERTs + 4 transaction category_key UPDATEs. Nothing else.
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │ POST-EXECUTION ARCHIVAL COPY of the executed PKG-TAX-1 SQL package.     │
-- │ NOT byte-identical to the text run in the SQL Editor — see PROVENANCE.  │
-- │                                                                         │
-- │ EXECUTED AGAINST PRODUCTION 2026-07-23 — SUCCESS.                       │
-- │   §1 preflight P0 = EXPECTED_PRE_STATE                                  │
-- │   §2 committed in one SQL-Editor session, one transaction               │
-- │   §3 + §4 validation and blast radius = 27 / 27 PASS                    │
-- │   application validation A1–A8 = PASS (owner-verified after refresh)    │
-- │ Closeout: docs/phase-5g-1d-taxonomy-remediation-closeout-2026-07-23.md  │
-- │ RERUN PROHIBITED — the E0 gate raises ALREADY APPLIED and mutates       │
-- │ nothing, but this artifact is a one-shot record. Do not re-run.         │
-- └─────────────────────────────────────────────────────────────────────────┘
--
-- Executed under AUTHORIZATION 2 of 2. AUTHORIZATION 1 (the documentation-only
-- governance disposition, DOC-TAX-1) was committed and pushed at 8c23006 first.
--
-- PROVENANCE — what changed after execution (full delta in the execution package,
-- PKG-TAX-1-post-execution-delta.diff; reconstructed as-executed text alongside it):
--   1. This header block (comment only).
--   2. §1 P2  — 3 comment lines added; SELECT output label 'P2 tx-global'
--                -> 'P2 register-integrity-aggregate'; SELECT reformatted onto 2 lines.
--   3. §2 E5i — 1 comment line added; RAISE EXCEPTION message text relabelled.
--   4. §4 B2  — 1 comment line added; SELECT output label 'B2 tx-global'
--                -> 'B2 register-integrity-aggregate'; SELECT reformatted.
-- All four applied the owner-approved "Register integrity aggregate" label (2026-07-23).
--
-- NO DDL OR DML STATEMENT CHANGED. The INSERT, the four UPDATEs, the E0 idempotency
-- gate, the temp-table captures, and every assertion CONDITION are unchanged. The three
-- altered string literals do not execute: two are SELECT output labels in the read-only
-- §1/§4 sections (outside the transaction), and the third is a RAISE EXCEPTION message
-- in §2 that never fired because the assertion passed. Executed behaviour is unchanged.
--
-- The pre-execution source was NOT preserved as a file; the as-executed text alongside
-- this artifact is a reconstruction derived from the recorded post-execution edits.
--
-- RERUN PROHIBITED — this is a one-shot archival record. The E0 gate would raise
-- ALREADY APPLIED and mutate nothing, but the artifact must not be re-run.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- §0  GOVERNANCE POSTURE — CORRECTED FROM THE DRAFT
-- ───────────────────────────────────────────────────────────────────────────
-- The draft asserted "no authenticated write grant" on public.categories. THAT WAS
-- WRONG. Verified against the production schema, categories carries FOUR RLS policies,
-- all already owner-gated:
--     categories_select        SELECT  TO authenticated  USING (is_allowed_user())
--     categories_insert_owner  INSERT  TO authenticated  WITH CHECK (is_owner())
--     categories_update_owner  UPDATE  TO authenticated  USING/CHECK (is_owner())
--     categories_delete_owner  DELETE  TO authenticated  USING (is_owner() AND is_system = false)
--
-- CONSEQUENCES:
--  1. The write surface is ALREADY RESTRICTED to the owner at the RLS tier. DOC-TAX-1
--     CONFIRMS AND DOCUMENTS the existing posture; it does not create it and adds no grant.
--  2. This package COULD run over PostgREST as the owner. It must NOT — PostgREST cannot
--     wrap 2 INSERTs + 4 UPDATEs in one transaction. The SQL editor is required so a
--     mid-package failure cannot leave a half-applied taxonomy.
--  3. is_system = false IS LOAD-BEARING, not cosmetic: categories_delete_owner requires
--     is_system = false. Setting it true would make §7 rollback impossible under RLS.
--
-- Also verified:
--  • public.transactions has trigger set_transactions_updated_at BEFORE UPDATE
--    → updated_at WILL change on all four rows. This is EXPECTED and asserted for.
--  • All four target rows are source='manual', satisfying financial_writer_update
--    (can_write_financials() AND source='manual') had this run over the API.
-- ───────────────────────────────────────────────────────────────────────────


-- ═══════════════════════════════════════════════════════════════════════════
-- §1  PREFLIGHT — READ-ONLY, RUN AND READ BEFORE ANYTHING ELSE
-- ═══════════════════════════════════════════════════════════════════════════

-- P0 · STATE CLASSIFIER — the single verdict that governs whether §2 may run.
WITH cat AS (
  SELECT count(*) FILTER (WHERE key = 'transfers.goal_funding')      AS gf,
         count(*) FILTER (WHERE key = 'transfers.goal_disbursement') AS gd,
         count(*) FILTER (WHERE key = 'transfers.goal_funding'
                            AND label='Goal Funding Transfer' AND parent_key='transfers'
                            AND is_leaf AND NOT is_system AND lifecycle_status='active'
                            AND behavior_class='transfer' AND budget_treatment='excluded'
                            AND cashflow_treatment='excluded')       AS gf_exact,
         count(*) FILTER (WHERE key = 'transfers.goal_disbursement'
                            AND label='Goal Disbursement Transfer' AND parent_key='transfers'
                            AND is_leaf AND NOT is_system AND lifecycle_status='active'
                            AND behavior_class='transfer' AND budget_treatment='excluded'
                            AND cashflow_treatment='excluded')       AS gd_exact
  FROM public.categories
), tx AS (
  SELECT
    count(*) FILTER (WHERE id='6b4afc32-9e0d-4b12-a703-833cb9cd86c0' AND category_key='trips.seattle_alaska_2026') +
    count(*) FILTER (WHERE id='14cbcba7-bffd-4fda-8427-850fe1edaa95' AND category_key IS NULL) +
    count(*) FILTER (WHERE id='a87b3516-f5c2-4a3b-aa2f-5a694b8e172a' AND category_key='taxes.vio_transfer_2026') +
    count(*) FILTER (WHERE id='3d3d1ead-8aaf-47e6-8070-d32bcff05af2' AND category_key IS NULL)   AS pre_ok,
    count(*) FILTER (WHERE id IN ('6b4afc32-9e0d-4b12-a703-833cb9cd86c0',
                                  '14cbcba7-bffd-4fda-8427-850fe1edaa95',
                                  'a87b3516-f5c2-4a3b-aa2f-5a694b8e172a')
                       AND category_key='transfers.goal_funding') +
    count(*) FILTER (WHERE id='3d3d1ead-8aaf-47e6-8070-d32bcff05af2'
                       AND category_key='taxes.vio_transfer_2026')                                AS post_ok
  FROM public.transactions
)
SELECT CASE
  WHEN cat.gf=0 AND cat.gd=0 AND tx.pre_ok=4  THEN 'EXPECTED_PRE_STATE — §2 MAY RUN'
  WHEN cat.gf_exact=1 AND cat.gd_exact=1 AND tx.post_ok=4 THEN 'ALREADY APPLIED — NO ACTION. Do not run §2.'
  ELSE 'MIXED / UNEXPECTED — ABORT. Investigate; do not run §2.'
END AS verdict, cat.gf, cat.gd, cat.gf_exact, cat.gd_exact, tx.pre_ok, tx.post_ok
FROM cat, tx;

-- P1 · Reference-data fingerprints (pin these; §4 re-computes and compares)
SELECT 'P1 cats-fp' AS check, count(*) AS rows,
       md5(string_agg(key||'|'||label||'|'||coalesce(parent_key,'~')||'|'||is_leaf||'|'||is_system||'|'||
                      lifecycle_status||'|'||coalesce(behavior_class,'~')||'|'||coalesce(budget_treatment,'~')||'|'||
                      coalesce(cashflow_treatment,'~')||'|'||display_order, E'\n' ORDER BY key)) AS fp
FROM public.categories
WHERE key NOT IN ('transfers.goal_funding','transfers.goal_disbursement');
-- EXPECT rows = 57. Record fp — §4 must return the IDENTICAL value.

-- REGISTER INTEGRITY AGGREGATE — a row-count-and-sum fingerprint over public.transactions used to
-- prove no amount was mutated. It is NOT an account balance, cash position, available balance, or
-- spending total, and must never be described as one.
SELECT 'P2 register-integrity-aggregate' AS check, count(*) AS rows, sum(amount) AS total
FROM public.transactions;
-- EXPECT rows = 197, total = -7527.79   (Register integrity aggregate)

SELECT 'P3 alaska-before' AS check, count(*) AS rows, sum(amount) AS total
FROM public.transactions WHERE category_key='trips.seattle_alaska_2026';
-- EXPECT rows = 4, total = -7607.10

SELECT 'P4 targets' AS check, id, transaction_date, account_key, amount, payee, memo,
       cleared, reconciled, transfer_pair_id, source, category_key, created_at, updated_at
FROM public.transactions
WHERE id IN ('6b4afc32-9e0d-4b12-a703-833cb9cd86c0','14cbcba7-bffd-4fda-8427-850fe1edaa95',
             'a87b3516-f5c2-4a3b-aa2f-5a694b8e172a','3d3d1ead-8aaf-47e6-8070-d32bcff05af2')
ORDER BY transaction_date;
-- EXPECT exactly 4 rows, all account_key='truist_checking', cleared=true, reconciled=false,
-- transfer_pair_id NULL, source='manual', memo NULL.

SELECT 'P5 slots' AS check, count(*) AS n FROM public.categories WHERE display_order IN (12020,12030);
-- EXPECT 0

SELECT 'P6 parent' AS check, key, is_leaf, lifecycle_status FROM public.categories WHERE key='transfers';
-- EXPECT 1 row: is_leaf=false, active


-- ═══════════════════════════════════════════════════════════════════════════
-- §2  EXECUTION — ONE SESSION, ONE TRANSACTION
--     Run ONLY if P0 returned 'EXPECTED_PRE_STATE'.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;

-- E0 · IDEMPOTENCY GATE — the FIRST statement inside the transaction. If state is not
--      exactly the expected pre-state, this raises and the transaction aborts having
--      mutated NOTHING. A rerun after success lands in ALREADY_APPLIED and aborts here.
DO $$
DECLARE n_new int; n_pre int; n_post int;
BEGIN
  SELECT count(*) INTO n_new FROM public.categories
    WHERE key IN ('transfers.goal_funding','transfers.goal_disbursement');
  SELECT count(*) INTO n_pre FROM public.transactions WHERE
       (id='6b4afc32-9e0d-4b12-a703-833cb9cd86c0' AND category_key='trips.seattle_alaska_2026')
    OR (id='14cbcba7-bffd-4fda-8427-850fe1edaa95' AND category_key IS NULL)
    OR (id='a87b3516-f5c2-4a3b-aa2f-5a694b8e172a' AND category_key='taxes.vio_transfer_2026')
    OR (id='3d3d1ead-8aaf-47e6-8070-d32bcff05af2' AND category_key IS NULL);
  SELECT count(*) INTO n_post FROM public.transactions WHERE
       (id IN ('6b4afc32-9e0d-4b12-a703-833cb9cd86c0','14cbcba7-bffd-4fda-8427-850fe1edaa95',
               'a87b3516-f5c2-4a3b-aa2f-5a694b8e172a') AND category_key='transfers.goal_funding')
    OR (id='3d3d1ead-8aaf-47e6-8070-d32bcff05af2' AND category_key='taxes.vio_transfer_2026');

  IF n_new = 2 AND n_post = 4 THEN
    RAISE EXCEPTION 'PKG-TAX-1 ALREADY APPLIED — no action taken, nothing mutated.';
  END IF;
  IF n_new <> 0 OR n_pre <> 4 THEN
    RAISE EXCEPTION 'PKG-TAX-1 MIXED/UNEXPECTED STATE (new_cats=%, pre_ok=%, post_ok=%) — aborting before any mutation.',
      n_new, n_pre, n_post;
  END IF;
END $$;

-- E1 · Full before-image of every material column, captured inside the transaction.
CREATE TEMP TABLE tax1_tx_before ON COMMIT DROP AS
  SELECT * FROM public.transactions
  WHERE id IN ('6b4afc32-9e0d-4b12-a703-833cb9cd86c0','14cbcba7-bffd-4fda-8427-850fe1edaa95',
               'a87b3516-f5c2-4a3b-aa2f-5a694b8e172a','3d3d1ead-8aaf-47e6-8070-d32bcff05af2');

CREATE TEMP TABLE tax1_cats_before ON COMMIT DROP AS
  SELECT * FROM public.categories;

-- E2 · Create the two approved categories.
--      All values satisfy chk_behavior_class / chk_budget_treatment /
--      chk_cashflow_treatment / chk_cat_lifecycle / chk_leaf_behavior.
INSERT INTO public.categories
  (key, label, parent_key, is_leaf, is_system, lifecycle_status,
   behavior_class, budget_treatment, cashflow_treatment, display_order)
VALUES
  ('transfers.goal_funding',      'Goal Funding Transfer',      'transfers', true, false, 'active',
   'transfer','excluded','excluded', 12020),
  ('transfers.goal_disbursement', 'Goal Disbursement Transfer', 'transfers', true, false, 'active',
   'transfer','excluded','excluded', 12030);

-- E3 · Recategorize the three goal-FUNDING legs (checking → goal holding).
UPDATE public.transactions SET category_key='transfers.goal_funding'
 WHERE id='6b4afc32-9e0d-4b12-a703-833cb9cd86c0'
   AND amount=-7000.00 AND category_key='trips.seattle_alaska_2026';
UPDATE public.transactions SET category_key='transfers.goal_funding'
 WHERE id='14cbcba7-bffd-4fda-8427-850fe1edaa95'
   AND amount=-4662.56 AND category_key IS NULL;
UPDATE public.transactions SET category_key='transfers.goal_funding'
 WHERE id='a87b3516-f5c2-4a3b-aa2f-5a694b8e172a'
   AND amount=-61.06   AND category_key='taxes.vio_transfer_2026';

-- E4 · File the orphan commission-tax leg with its siblings.
UPDATE public.transactions SET category_key='taxes.vio_transfer_2026'
 WHERE id='3d3d1ead-8aaf-47e6-8070-d32bcff05af2'
   AND amount=-425.68  AND category_key IS NULL;

-- E5 · COMPLETE ROW-LEVEL PROOF — every material column compared, not just counts.
DO $$
DECLARE bad int; n int; t numeric; fp_b text; fp_a text;
BEGIN
  -- (a) Only category_key and updated_at may differ on the four rows.
  SELECT count(*) INTO bad
  FROM tax1_tx_before b JOIN public.transactions a USING (id)
  WHERE b.user_id IS DISTINCT FROM a.user_id
     OR b.account_key IS DISTINCT FROM a.account_key
     OR b.transaction_date IS DISTINCT FROM a.transaction_date
     OR b.posted_date IS DISTINCT FROM a.posted_date
     OR b.payee IS DISTINCT FROM a.payee
     OR b.memo IS DISTINCT FROM a.memo
     OR b.amount IS DISTINCT FROM a.amount
     OR b.cleared IS DISTINCT FROM a.cleared
     OR b.reconciled IS DISTINCT FROM a.reconciled
     OR b.transfer_pair_id IS DISTINCT FROM a.transfer_pair_id
     OR b.source IS DISTINCT FROM a.source
     OR b.notes IS DISTINCT FROM a.notes
     OR b.created_at IS DISTINCT FROM a.created_at;
  IF bad <> 0 THEN RAISE EXCEPTION 'E5a: % target row(s) changed a column other than category_key/updated_at', bad; END IF;

  -- (b) category_key changed on exactly 4 rows, to the intended values.
  SELECT count(*) INTO bad FROM tax1_tx_before b JOIN public.transactions a USING (id)
   WHERE b.category_key IS NOT DISTINCT FROM a.category_key;
  IF bad <> 0 THEN RAISE EXCEPTION 'E5b: % target row(s) did not change category_key', bad; END IF;

  -- (c) updated_at advanced on all four (trigger set_transactions_updated_at).
  SELECT count(*) INTO bad FROM tax1_tx_before b JOIN public.transactions a USING (id)
   WHERE a.updated_at <= b.updated_at;
  IF bad <> 0 THEN RAISE EXCEPTION 'E5c: updated_at did not advance on % row(s)', bad; END IF;

  -- (d) EVERY pre-existing category row byte-identical — fingerprint, not a count.
  SELECT md5(string_agg(key||'|'||label||'|'||coalesce(parent_key,'~')||'|'||is_leaf||'|'||is_system||'|'||
             lifecycle_status||'|'||coalesce(behavior_class,'~')||'|'||coalesce(budget_treatment,'~')||'|'||
             coalesce(cashflow_treatment,'~')||'|'||display_order, E'\n' ORDER BY key)) INTO fp_b
    FROM tax1_cats_before;
  SELECT md5(string_agg(key||'|'||label||'|'||coalesce(parent_key,'~')||'|'||is_leaf||'|'||is_system||'|'||
             lifecycle_status||'|'||coalesce(behavior_class,'~')||'|'||coalesce(budget_treatment,'~')||'|'||
             coalesce(cashflow_treatment,'~')||'|'||display_order, E'\n' ORDER BY key)) INTO fp_a
    FROM public.categories WHERE key NOT IN ('transfers.goal_funding','transfers.goal_disbursement');
  IF fp_b IS DISTINCT FROM fp_a THEN RAISE EXCEPTION 'E5d: pre-existing category rows changed (fp % -> %)', fp_b, fp_a; END IF;

  -- (e) Outcome assertions.
  SELECT count(*) INTO n FROM public.categories;
  IF n <> 59 THEN RAISE EXCEPTION 'E5e: expected 59 categories, got %', n; END IF;
  SELECT count(*) INTO n FROM public.transactions WHERE category_key='transfers.goal_funding';
  IF n <> 3 THEN RAISE EXCEPTION 'E5f: expected 3 goal_funding rows, got %', n; END IF;
  SELECT count(*), sum(amount) INTO n, t FROM public.transactions WHERE category_key='trips.seattle_alaska_2026';
  IF n <> 3 OR t <> -607.10 THEN RAISE EXCEPTION 'E5g: Alaska expected 3 / -607.10, got % / %', n, t; END IF;
  SELECT count(*) INTO n FROM public.transactions WHERE category_key='taxes.vio_transfer_2026';
  IF n <> 4 THEN RAISE EXCEPTION 'E5h: expected 4 tax-transfer rows, got %', n; END IF;
  SELECT count(*), sum(amount) INTO n, t FROM public.transactions;
  -- Register integrity aggregate check (not an account balance)
  IF n <> 197 OR t <> -7527.79 THEN RAISE EXCEPTION 'E5i: Register integrity aggregate changed — % rows / %', n, t; END IF;
END $$;

COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════
-- §3  VALIDATION  (read-only, post-commit)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT 'V1' AS check, key, label, parent_key, is_leaf, is_system, lifecycle_status,
       behavior_class, budget_treatment, cashflow_treatment, display_order,
       (is_leaf AND lifecycle_status='active' AND behavior_class<>'savings_allocation'
        AND budget_treatment<>'planned_allocation') AS assignable_in_register
FROM public.categories WHERE key IN ('transfers.goal_funding','transfers.goal_disbursement')
ORDER BY display_order;                       -- EXPECT 2 rows, assignable = true

SELECT 'V2 alaska-after' AS check, count(*) AS rows, sum(amount) AS total
FROM public.transactions WHERE category_key='trips.seattle_alaska_2026';   -- EXPECT 3 / -607.10

SELECT 'V3 alaska-charges' AS check, transaction_date, amount, payee
FROM public.transactions WHERE category_key='trips.seattle_alaska_2026' ORDER BY transaction_date;
-- EXPECT -489.86 NCL · -30.00 Alaska Fishing Licenses · -87.24 AMC Seattle

SELECT 'V4 goal-funding' AS check, transaction_date, amount, payee
FROM public.transactions WHERE category_key='transfers.goal_funding' ORDER BY transaction_date;
-- EXPECT -7000.00 · -4662.56 · -61.06   (sum -11723.62)

SELECT 'V5 tax-transfers' AS check, transaction_date, amount, payee
FROM public.transactions WHERE category_key='taxes.vio_transfer_2026' ORDER BY transaction_date;
-- EXPECT 4 rows: -435.63 · -700.90 · -417.83 · -425.68

SELECT 'V6 disbursement-empty' AS check, count(*) AS rows
FROM public.transactions WHERE category_key='transfers.goal_disbursement';
-- EXPECT 0 — CORRECT, not a failure. Reserved for the future $770.95 Alaska release.


-- ═══════════════════════════════════════════════════════════════════════════
-- §4  BLAST RADIUS  (read-only)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT 'B1 cats-fp' AS check, count(*) AS rows,
       md5(string_agg(key||'|'||label||'|'||coalesce(parent_key,'~')||'|'||is_leaf||'|'||is_system||'|'||
           lifecycle_status||'|'||coalesce(behavior_class,'~')||'|'||coalesce(budget_treatment,'~')||'|'||
           coalesce(cashflow_treatment,'~')||'|'||display_order, E'\n' ORDER BY key)) AS fp
FROM public.categories WHERE key NOT IN ('transfers.goal_funding','transfers.goal_disbursement');
-- EXPECT rows = 57 AND fp IDENTICAL to P1

-- Register integrity aggregate (NOT an account balance / cash position / available balance / spending total)
SELECT 'B2 register-integrity-aggregate' AS check, count(*) AS rows, sum(amount) AS total
FROM public.transactions;   -- EXPECT 197 / -7527.79
SELECT 'B3 recon'      AS check, count(*) FROM public.weekly_reconciliations;                       -- 6
SELECT 'B4 snapshots'  AS check, count(*) FROM public.goal_funding_snapshots WHERE model_year=2026; -- 20
SELECT 'B5 wk-tasks'   AS check, count(*) FROM public.weekly_tasks;                                 -- 16
SELECT 'B6 custom'     AS check, count(*) FROM public.custom_tasks;                                 -- 17
SELECT 'B7 commit'     AS check, count(*) FROM public.cash_commitments WHERE model_year=2026;       -- 6
SELECT 'B8 accounts'   AS check, count(*) FROM public.accounts;                                     -- 14
SELECT 'B9 costco'     AS check, lifecycle_status, starting_balance FROM public.accounts WHERE key='costco_visa'; -- active / NULL
SELECT 'B10 overrides' AS check, week_num, ct, ca, events_json FROM public.model_week_overrides ORDER BY week_num;
-- EXPECT weeks 2,3,4,6,7,8 · wk7 ct=0 ca=0 · Jabian 1099.45 (AU-1) · Disney -3494.94 (AU-2)


-- ═══════════════════════════════════════════════════════════════════════════
-- §5  ROLLBACK  (valid ONLY in the immediate post-package state — see §5b)
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;
DO $$
DECLARE dep int;
BEGIN
  -- §5b DEPENDENCY GATE: rollback is only directly executable while NOTHING else
  -- references either category. Once downstream rows exist (e.g. the AU-8 $770.95
  -- filed under transfers.goal_disbursement), this raises and rollback becomes a
  -- larger operation: scan dependants, recategorize every one, THEN delete.
  SELECT count(*) INTO dep FROM public.transactions
   WHERE category_key IN ('transfers.goal_funding','transfers.goal_disbursement')
     AND id NOT IN ('6b4afc32-9e0d-4b12-a703-833cb9cd86c0','14cbcba7-bffd-4fda-8427-850fe1edaa95',
                    'a87b3516-f5c2-4a3b-aa2f-5a694b8e172a');
  IF dep <> 0 THEN
    RAISE EXCEPTION 'ROLLBACK BLOCKED: % downstream transaction(s) reference the new categories. Perform a dependency scan and recategorize them before deletion.', dep;
  END IF;
END $$;

UPDATE public.transactions SET category_key='trips.seattle_alaska_2026' WHERE id='6b4afc32-9e0d-4b12-a703-833cb9cd86c0';
UPDATE public.transactions SET category_key=NULL                        WHERE id='14cbcba7-bffd-4fda-8427-850fe1edaa95';
UPDATE public.transactions SET category_key='taxes.vio_transfer_2026'   WHERE id='a87b3516-f5c2-4a3b-aa2f-5a694b8e172a';
UPDATE public.transactions SET category_key=NULL                        WHERE id='3d3d1ead-8aaf-47e6-8070-d32bcff05af2';
DELETE FROM public.categories WHERE key IN ('transfers.goal_funding','transfers.goal_disbursement');

DO $$
DECLARE n int; t numeric;
BEGIN
  SELECT count(*), sum(amount) INTO n,t FROM public.transactions WHERE category_key='trips.seattle_alaska_2026';
  IF n<>4 OR t<>-7607.10 THEN RAISE EXCEPTION 'rollback incomplete: % / %', n, t; END IF;
  SELECT count(*) INTO n FROM public.categories;
  IF n<>57 THEN RAISE EXCEPTION 'rollback incomplete: % categories', n; END IF;
END $$;
COMMIT;
-- NOTE: DELETE succeeds under RLS only because is_system=false (categories_delete_owner).
-- NOTE: updated_at on the four rows will advance again; it is not restorable. Rollback
--       restores category_key, not the original updated_at.


-- ═══════════════════════════════════════════════════════════════════════════
-- §6  USER-FACING APPLICATION VALIDATION — MANDATORY
--     Perform AFTER a hard refresh / fresh authenticated owner session.
-- ═══════════════════════════════════════════════════════════════════════════
--  A1 · Register → category picker offers "Goal Funding Transfer" AND
--       "Goal Disbursement Transfer".
--  A2 · Both appear under the Transfers group.
--  A3 · Neither appears as Budget spending, and neither appears as Budget income.
--  A4 · Category report for 2026 Seattle/Alaska contains EXACTLY the three genuine
--       charges: NCL, Alaska Fishing Licenses, AMC Seattle.
--  A5 · That report totals EXACTLY $607.10.
--  A6 · The three goal-funding transfers (-7,000.00 / -4,662.56 / -61.06) appear
--       under Goal Funding Transfer.
--  A7 · The -425.68 row appears under Taxes 2026 alongside -435.63 / -417.83 / -700.90.
--  A8 · Console clean — no error, and no "[5D-1] … load failed" registry message.
--  Any A-check failing ⇒ STOP and consider §5 rollback.
--
-- No code change is required for A1/A2: FEATURE_FLAGS.showTransactionLedger=true runs
-- _loadSupabaseRegistries(), and the Register picker filters _categoriesCache on
-- leaf && assignable — both new rows qualify.


-- ═══════════════════════════════════════════════════════════════════════════
-- §7  AU-8 BOUNDARY — WHAT THIS PACKAGE DOES NOT DO
-- ═══════════════════════════════════════════════════════════════════════════
-- PKG-TAX-1:
--   ✔ creates the two categories;
--   ✔ recategorizes ONLY the four historical rows listed above;
--   ✘ does NOT initiate the $770.95 bank transfer;
--   ✘ does NOT create or categorize the future $770.95 Register row;
--   ✘ does NOT update the Goal Ledger (the Sheet is unchanged by this package).
--
-- SUPPORTED AU-8 REGISTER WORKFLOW (verified, not assumed):
--   The Register is MANUALLY MAINTAINED. There is no bank feed, no CSV/OFX/QFX import,
--   and no Plaid-style integration anywhere in the application. The only transaction
--   write paths are the Register's own form — POST (new) / PATCH (edit) / DELETE — all
--   gated by RLS on can_write_financials() AND source='manual'.
--   Therefore AU-8 is: (1) execute the bank transfer; (2) wait for BOTH legs to settle;
--   (3) the OPERATOR manually creates the +770.95 Truist Checking inflow row in the
--   Register, categorized transfers.goal_disbursement; (4) update the Goal Ledger release
--   row scheduled → settled. Nothing auto-posts. Note Truist Savings has no Register
--   coverage, so only the checking leg is recorded.
