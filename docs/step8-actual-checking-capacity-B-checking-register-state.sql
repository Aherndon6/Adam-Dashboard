-- ============================================================================
-- Step 8 · Baseline B · Checking Account & Register State  (READ-ONLY)
-- Preconditions: A0_OPERATOR_PROJECT_CONFIRMATION recorded; the gate for the
--   statement you run = GATE_PASS (B; B6 for B6a; B6+BCAT for B6b; BCAT for B8).
-- Editor: run each result set separately. Canonical key = 'truist_checking' (B1a).
-- Sign: outflow<0, inflow>0; CHECK amount<>0.
-- Anchor: starting_balance = CLEARED balance as of END of starting_balance_as_of;
--   required population = transaction_date > as_of. App sums all rows (no filter),
--   capped at 500 (index.html:7880-7883) — see B1c.
-- updated_at (trigger-maintained, phase-5e-migration.sql:98-102) proves a row was
--   modified after cutoff; it does NOT preserve prior field values. POST-CUTOFF
--   UPDATE EXISTENCE IS DETECTABLE; PRIOR ROW STATE IS NOT RECONSTRUCTABLE FROM
--   transactions ALONE.
-- CANONICAL PARAMS (set at capture; illustrative placeholders, not frozen):
--   cutoff_ts = TIMESTAMPTZ '2026-07-28 18:00:00-04:00' (America/New_York EDT)
--   cutoff_business_date = DATE '2026-07-28'
--   inspection_start_date = DATE '2026-06-30'  (B4/B5/B6 window; NOT the capacity cutoff)
-- No B figure is checking capacity or transfer authorization. The full-DB aggregate
--   is the complete database-derived ledger calculation, subject to anchor validation,
--   duplicate/transfer review, cutoff integrity, and reconciliation to the live bank
--   snapshot (Baseline F), which remains the primary actual-balance truth.
-- Run order: B1a, B1b, B1c, B2, B3, B4, B5_PRIMARY, B5_FULL_HISTORY, B6a, B6b, B7a, B7b, B8.
-- ============================================================================

------------------------------------------------------------------------------
-- B1a_TARGET_GATE  (multi-row/null-safe; canonical key does NOT prove institution)
------------------------------------------------------------------------------
WITH target AS (SELECT * FROM public.accounts WHERE key='truist_checking'),
tstat AS (SELECT count(*) AS exact_target_count, array_agg(id ORDER BY id) AS target_ids FROM target),
tone  AS (SELECT * FROM target ORDER BY id LIMIT 1),
plausible AS (
  SELECT count(*) AS plausible_candidate_count FROM public.accounts a
  WHERE a.key='truist_checking' OR a.account_type ILIKE '%check%' OR a.label ILIKE '%check%' OR a.institution ILIKE '%truist%'
)
SELECT
  'B1a_TARGET_GATE'                              AS result_set,
  (SELECT exact_target_count FROM tstat)         AS exact_target_count,        -- MUST be 1
  (SELECT plausible_candidate_count FROM plausible) AS plausible_candidate_count,
  (SELECT target_ids FROM tstat)                 AS all_exact_target_ids,
  (SELECT key FROM tone)                         AS target_account_key,
  (SELECT id FROM tone)                          AS target_account_id,
  (SELECT label FROM tone)                       AS target_account_label,
  (SELECT institution FROM tone)                 AS target_institution,
  (SELECT account_type FROM tone)                AS target_account_type,
  (SELECT lifecycle_status FROM tone)            AS target_lifecycle_status,
  (SELECT starting_balance FROM tone)            AS target_starting_balance,
  (SELECT starting_balance_as_of FROM tone)      AS target_starting_balance_as_of,
  (SELECT starting_balance_source FROM tone)     AS target_starting_balance_source,
  (SELECT starting_balance_note FROM tone)       AS target_starting_balance_note,
  -- SEPARATE, INDEPENDENT CONTROLS
  ((SELECT key FROM tone) = 'truist_checking')                                                       AS canonical_key_consistent,
  ((SELECT lifecycle_status FROM tone) IS NOT DISTINCT FROM 'active')                                AS target_active,
  coalesce((SELECT account_type FROM tone) ILIKE '%check%' OR (SELECT label FROM tone) ILIKE '%check%', false) AS type_or_label_checking_consistent,
  coalesce((SELECT institution FROM tone) ILIKE '%truist%', false)                                   AS institution_truist_consistent,
  CASE
    WHEN (SELECT exact_target_count FROM tstat)=0 THEN 'EXACT_TARGET_MISSING_STOP'
    WHEN (SELECT exact_target_count FROM tstat)>1 THEN 'EXACT_TARGET_NONUNIQUE_STOP'
    WHEN (SELECT lifecycle_status FROM tone) IS DISTINCT FROM 'active' THEN 'EXACT_TARGET_INACTIVE_STOP'
    WHEN NOT coalesce((SELECT account_type FROM tone) ILIKE '%check%' OR (SELECT label FROM tone) ILIKE '%check%', false) THEN 'EXACT_TARGET_TYPE_LABEL_REVIEW_STOP'
    WHEN NOT coalesce((SELECT institution FROM tone) ILIKE '%truist%', false) THEN 'EXACT_TARGET_INSTITUTION_REVIEW_STOP'
    ELSE 'TARGET_OK'
  END AS gate_result;

------------------------------------------------------------------------------
-- B1b_PLAUSIBLE_CANDIDATES  (informational)
------------------------------------------------------------------------------
SELECT 'B1b_PLAUSIBLE_CANDIDATES' AS result_set,
  a.key AS account_key, a.id AS account_id, a.label AS account_label, a.institution,
  a.account_type, a.lifecycle_status, a.include_in_cashflow, a.starting_balance, a.starting_balance_as_of, a.display_order,
  (a.key='truist_checking') AS is_exact_target,
  array_to_string(array_remove(ARRAY[
    CASE WHEN a.key='truist_checking' THEN 'key=truist_checking' END,
    CASE WHEN a.account_type ILIKE '%check%' THEN 'account_type~check' END,
    CASE WHEN a.label ILIKE '%check%' THEN 'label~check' END,
    CASE WHEN a.institution ILIKE '%truist%' THEN 'institution~truist' END], NULL), ', ') AS match_reasons
FROM public.accounts a
WHERE a.key='truist_checking' OR a.account_type ILIKE '%check%' OR a.label ILIKE '%check%' OR a.institution ILIKE '%truist%'
ORDER BY (a.key='truist_checking') DESC, a.display_order, a.key;

------------------------------------------------------------------------------
-- B1c_APPLICATION_LEDGER_CAP  (deployed order transaction_date,created_at,id ASC)
------------------------------------------------------------------------------
WITH chk AS (SELECT key AS account_key, starting_balance FROM public.accounts WHERE key='truist_checking'),
allrows AS (SELECT amount FROM public.transactions WHERE account_key=(SELECT account_key FROM chk)),
app500 AS (
  SELECT id, transaction_date, created_at, amount
  FROM public.transactions
  WHERE account_key=(SELECT account_key FROM chk)
  ORDER BY transaction_date ASC, created_at ASC, id ASC
  LIMIT 500
),
app_first AS (SELECT id, transaction_date, created_at FROM app500 ORDER BY transaction_date ASC, created_at ASC, id ASC LIMIT 1),
app_last  AS (SELECT id, transaction_date, created_at FROM app500 ORDER BY transaction_date DESC, created_at DESC, id DESC LIMIT 1)
SELECT
  'B1c_APPLICATION_LEDGER_CAP' AS result_set,
  (SELECT account_key FROM chk)                          AS checking_key,
  (SELECT count(*) FROM allrows)                         AS total_checking_txn_count,
  ((SELECT count(*) FROM allrows) > 500)                 AS exceeds_500,
  (SELECT count(*) FROM app500)                          AS app_equiv_population_count,
  (SELECT id FROM app_first)                             AS app_first_txn_id,
  (SELECT transaction_date FROM app_first)               AS app_first_txn_date,
  (SELECT created_at FROM app_first)                     AS app_first_txn_created_at,
  (SELECT id FROM app_last)                              AS app_last_txn_id,
  (SELECT transaction_date FROM app_last)                AS app_last_txn_date,
  (SELECT created_at FROM app_last)                      AS app_last_txn_created_at,
  (SELECT coalesce(sum(amount),0) FROM allrows)          AS full_db_allrow_aggregate,
  (SELECT coalesce(sum(amount),0) FROM app500)           AS app_equiv_allrow_aggregate,
  (SELECT starting_balance FROM chk) + (SELECT coalesce(sum(amount),0) FROM allrows) AS full_db_derived_balance,
  (SELECT starting_balance FROM chk) + (SELECT coalesce(sum(amount),0) FROM app500)  AS app_equiv_derived_balance,
  ((SELECT coalesce(sum(amount),0) FROM allrows) - (SELECT coalesce(sum(amount),0) FROM app500)) AS full_minus_app_difference,
  CASE WHEN (SELECT count(*) FROM allrows) > 500 THEN 'APPLICATION_LEDGER_LIMIT_EXCEEDED_STOP' ELSE 'WITHIN_APP_CAP_OK' END AS app_cap_result;

------------------------------------------------------------------------------
-- B2_ANCHOR_INTEGRITY
------------------------------------------------------------------------------
WITH chk AS (SELECT key AS account_key, starting_balance, starting_balance_as_of, starting_balance_source, starting_balance_note
             FROM public.accounts WHERE key='truist_checking'),
t AS (SELECT tr.transaction_date, c.starting_balance_as_of AS as_of FROM public.transactions tr CROSS JOIN chk c WHERE tr.account_key=c.account_key)
SELECT 'B2_ANCHOR_INTEGRITY' AS result_set,
  (SELECT account_key FROM chk) AS checking_key, (SELECT count(*) FROM chk) AS account_row_matches,
  (SELECT starting_balance FROM chk) AS starting_balance_cleared_anchor,
  (SELECT starting_balance_as_of FROM chk) AS starting_balance_as_of,
  (SELECT starting_balance_source FROM chk) AS starting_balance_source,
  (SELECT starting_balance_note FROM chk) AS starting_balance_note,
  (SELECT min(transaction_date) FROM t) AS earliest_txn_date, (SELECT max(transaction_date) FROM t) AS latest_txn_date,
  (SELECT count(*) FROM t WHERE as_of IS NOT NULL AND transaction_date < as_of) AS rows_before_anchor,
  (SELECT count(*) FROM t WHERE as_of IS NOT NULL AND transaction_date = as_of) AS rows_on_anchor_date,
  (SELECT count(*) FROM t WHERE as_of IS NOT NULL AND transaction_date > as_of) AS rows_after_anchor,
  'starting_balance = CLEARED balance as of END of starting_balance_as_of; required population = transaction_date > as_of (AMEX A4 precedent). App sums ALL rows (capped 500) and does not enforce this.' AS anchor_convention,
  CASE
    WHEN (SELECT count(*) FROM chk) <> 1 THEN 'ACCOUNT_NOT_UNIQUE_STOP'
    WHEN (SELECT starting_balance FROM chk) IS NULL THEN 'STARTING_BALANCE_NULL_REVIEW'
    WHEN (SELECT starting_balance_as_of FROM chk) IS NULL THEN 'ANCHOR_DATE_NULL_AMBIGUOUS_REVIEW'
    WHEN (SELECT count(*) FROM t WHERE transaction_date < (SELECT starting_balance_as_of FROM chk)) > 0 THEN 'ROWS_BEFORE_ANCHOR_STOP_REVIEW'
    WHEN (SELECT count(*) FROM t WHERE transaction_date = (SELECT starting_balance_as_of FROM chk)) > 0 THEN 'ROWS_ON_ANCHOR_AMBIGUOUS_REVIEW'
    ELSE 'ANCHOR_CLEAN' END AS anchor_basis_result;

------------------------------------------------------------------------------
-- B3_REGISTER_AGGREGATES  (historical as-of-cutoff verdict uses historical counts;
--   current-state verdict uses all current rows; late-created ≠ historical edit)
------------------------------------------------------------------------------
WITH params AS (
  SELECT TIMESTAMPTZ '2026-07-28 18:00:00-04:00' AS cutoff_ts,     -- << SET AT CAPTURE
         DATE        '2026-07-28'                AS cutoff_business_date -- << SET AT CAPTURE
),
chk AS (SELECT key AS account_key, starting_balance, starting_balance_as_of FROM public.accounts WHERE key='truist_checking'),
t AS (
  SELECT tr.amount, tr.cleared, tr.transaction_date, tr.created_at, tr.updated_at,
         c.starting_balance_as_of AS as_of, p.cutoff_ts, p.cutoff_business_date
  FROM public.transactions tr CROSS JOIN chk c CROSS JOIN params p
  WHERE tr.account_key=c.account_key
)
SELECT
  'B3_REGISTER_AGGREGATES' AS result_set,
  (SELECT account_key FROM chk) AS checking_key,
  (SELECT count(*) FROM chk) AS account_row_matches,
  (SELECT starting_balance FROM chk) AS starting_balance_cleared_anchor,
  (SELECT starting_balance_as_of FROM chk) AS starting_balance_as_of,
  (SELECT cutoff_ts FROM params) AS cutoff_ts,
  (SELECT cutoff_business_date FROM params) AS cutoff_business_date,
  -- population counts
  (SELECT count(*) FROM t WHERE transaction_date <= cutoff_business_date) AS current_count,
  (SELECT count(*) FROM t WHERE transaction_date <= cutoff_business_date AND created_at <= cutoff_ts) AS existed_at_cutoff_count,
  (SELECT count(*) FROM t WHERE transaction_date <= cutoff_business_date AND created_at > cutoff_ts) AS backdated_late_count,
  (SELECT count(*) FROM t WHERE transaction_date <= cutoff_business_date AND created_at <= cutoff_ts AND updated_at > cutoff_ts) AS existed_but_edited_after_cutoff_count,
  (SELECT count(*) FROM t WHERE transaction_date > cutoff_business_date) AS future_after_cutoff_count,
  -- HISTORICAL anchor (created<=cutoff only)
  (SELECT count(*) FROM t WHERE created_at <= cutoff_ts AND as_of IS NOT NULL AND transaction_date < as_of) AS historical_before_anchor_count,
  (SELECT count(*) FROM t WHERE created_at <= cutoff_ts AND as_of IS NOT NULL AND transaction_date = as_of) AS historical_on_anchor_count,
  -- CURRENT anchor (all current rows)
  (SELECT count(*) FROM t WHERE as_of IS NOT NULL AND transaction_date < as_of) AS current_before_anchor_count,
  (SELECT count(*) FROM t WHERE as_of IS NOT NULL AND transaction_date = as_of) AS current_on_anchor_count,
  -- PRIMARY candidate: existed_at_cutoff
  (SELECT coalesce(sum(amount) FILTER (WHERE cleared),0) FROM t WHERE transaction_date <= cutoff_business_date AND created_at <= cutoff_ts) AS primary_existed_cleared_agg,
  (SELECT coalesce(sum(amount),0)                        FROM t WHERE transaction_date <= cutoff_business_date AND created_at <= cutoff_ts) AS primary_existed_allrow_agg,
  (SELECT starting_balance FROM chk) + (SELECT coalesce(sum(amount) FILTER (WHERE cleared),0) FROM t WHERE transaction_date <= cutoff_business_date AND created_at <= cutoff_ts) AS cand_primary_derived_cleared_balance,
  (SELECT starting_balance FROM chk) + (SELECT coalesce(sum(amount),0)                        FROM t WHERE transaction_date <= cutoff_business_date AND created_at <= cutoff_ts) AS cand_primary_derived_allrow_balance,
  -- PRIMARY + anchor-strict (transaction_date > as_of); NULL when as_of NULL
  CASE WHEN (SELECT starting_balance_as_of FROM chk) IS NULL THEN NULL ELSE
    (SELECT starting_balance FROM chk) + (SELECT coalesce(sum(amount) FILTER (WHERE cleared),0) FROM t WHERE transaction_date <= cutoff_business_date AND created_at <= cutoff_ts AND transaction_date > as_of) END AS cand_primary_strict_derived_cleared_balance,
  CASE WHEN (SELECT starting_balance_as_of FROM chk) IS NULL THEN NULL ELSE
    (SELECT starting_balance FROM chk) + (SELECT coalesce(sum(amount),0)                        FROM t WHERE transaction_date <= cutoff_business_date AND created_at <= cutoff_ts AND transaction_date > as_of) END AS cand_primary_strict_derived_allrow_balance,
  -- CURRENT-STATE aggregate (all created) + backdated drift magnitude
  (SELECT coalesce(sum(amount),0) FROM t WHERE transaction_date <= cutoff_business_date) AS current_allrow_agg,
  (SELECT starting_balance FROM chk) + (SELECT coalesce(sum(amount),0) FROM t WHERE transaction_date <= cutoff_business_date) AS cand_current_derived_allrow_balance,
  (SELECT coalesce(sum(amount),0) FROM t WHERE transaction_date <= cutoff_business_date AND created_at > cutoff_ts) AS backdated_late_allrow_agg,
  'Full-DB current-state equals the deployed Register ONLY if B1c.total_checking_txn_count <= 500. This is the complete database-derived ledger calculation, subject to anchor validation, duplicate/transfer review, cutoff integrity, and reconciliation to live bank truth. No B3 figure is checking capacity or transfer authorization.' AS scope_note,
  -- HISTORICAL as-of-cutoff verdict (historical counts + existed-but-edited only)
  CASE
    WHEN (SELECT count(*) FROM chk) <> 1 THEN 'ACCOUNT_NOT_UNIQUE_STOP'
    WHEN (SELECT starting_balance FROM chk) IS NULL THEN 'STARTING_BALANCE_NULL_PROVISIONAL'
    WHEN (SELECT starting_balance_as_of FROM chk) IS NULL THEN 'ANCHOR_NULL_PROVISIONAL_MULTIPLE_CANDIDATES'
    WHEN (SELECT count(*) FROM t WHERE created_at <= cutoff_ts AND as_of IS NOT NULL AND transaction_date < as_of) > 0
      OR (SELECT count(*) FROM t WHERE created_at <= cutoff_ts AND as_of IS NOT NULL AND transaction_date = as_of) > 0
      THEN 'HISTORICAL_ANCHOR_OVERLAP_PROVISIONAL_MULTIPLE_CANDIDATES'
    WHEN (SELECT count(*) FROM t WHERE transaction_date <= cutoff_business_date AND created_at <= cutoff_ts AND updated_at > cutoff_ts) > 0
      THEN 'HISTORICAL_NON_RECONSTRUCTABLE_REVIEW'
    ELSE 'HISTORICAL_CLEAN'
  END AS historical_balance_basis_result,
  -- CURRENT-STATE integrity verdict (all current rows; catches backdated drift)
  CASE
    WHEN (SELECT count(*) FROM chk) <> 1 THEN 'ACCOUNT_NOT_UNIQUE_STOP'
    WHEN (SELECT starting_balance_as_of FROM chk) IS NULL THEN 'ANCHOR_NULL_REVIEW'
    WHEN (SELECT count(*) FROM t WHERE as_of IS NOT NULL AND transaction_date < as_of) > 0
      OR (SELECT count(*) FROM t WHERE as_of IS NOT NULL AND transaction_date = as_of) > 0
      THEN 'CURRENT_ANCHOR_OVERLAP_REVIEW'
    WHEN (SELECT count(*) FROM t WHERE transaction_date <= cutoff_business_date AND created_at > cutoff_ts) > 0
      THEN 'CURRENT_HAS_BACKDATED_LATE_DRIFT_REVIEW'
    ELSE 'CURRENT_CLEAN'
  END AS current_state_anchor_result;

------------------------------------------------------------------------------
-- B4_RECENT_TRANSACTIONS
------------------------------------------------------------------------------
WITH params AS (SELECT TIMESTAMPTZ '2026-07-28 18:00:00-04:00' AS cutoff_ts, DATE '2026-07-28' AS cutoff_business_date, DATE '2026-06-30' AS inspection_start_date), -- << SET AT CAPTURE
chk AS (SELECT key AS account_key FROM public.accounts WHERE key='truist_checking')
SELECT 'B4_RECENT_TRANSACTIONS' AS result_set,
  t.id AS transaction_id, t.account_key, t.transaction_date, t.posted_date, t.created_at, t.updated_at,
  t.cleared AS register_marked_cleared, t.reconciled, t.amount AS signed_amount,
  t.payee AS payee_merchant, t.memo, t.notes, t.source, t.category_key, c.label AS category_label, t.transfer_pair_id,
  (t.created_at > (SELECT cutoff_ts FROM params)) AS is_created_after_cutoff,
  (t.created_at <= (SELECT cutoff_ts FROM params) AND t.updated_at > (SELECT cutoff_ts FROM params)) AS is_existed_but_updated_after_cutoff,
  (t.created_at > (SELECT cutoff_ts FROM params) AND t.transaction_date <= (SELECT cutoff_business_date FROM params)) AS is_backdated_late_entry,
  (t.posted_date IS NOT NULL AND t.posted_date > (SELECT cutoff_business_date FROM params)) AS is_posted_after_cutoff
FROM public.transactions t LEFT JOIN public.categories c ON c.key=t.category_key CROSS JOIN params p
WHERE t.account_key=(SELECT account_key FROM chk) AND t.transaction_date >= p.inspection_start_date AND t.transaction_date <= p.cutoff_business_date
ORDER BY t.transaction_date DESC, t.created_at DESC, t.id DESC LIMIT 500;

------------------------------------------------------------------------------
-- B5_PRIMARY_DUPLICATE_CANDIDATES  (bounded: window + created_at<=cutoff_ts)
------------------------------------------------------------------------------
WITH params AS (SELECT TIMESTAMPTZ '2026-07-28 18:00:00-04:00' AS cutoff_ts, DATE '2026-07-28' AS cutoff_business_date, DATE '2026-06-30' AS inspection_start_date), -- << SET AT CAPTURE
chk AS (SELECT key AS account_key FROM public.accounts WHERE key='truist_checking'),
reg AS (SELECT tr.id, tr.account_key, tr.transaction_date, tr.posted_date, tr.amount, tr.payee, tr.memo, tr.notes, tr.category_key, tr.source, tr.cleared, tr.reconciled, tr.transfer_pair_id
        FROM public.transactions tr CROSS JOIN params p
        WHERE tr.account_key=(SELECT account_key FROM chk) AND tr.transaction_date >= p.inspection_start_date AND tr.transaction_date <= p.cutoff_business_date AND tr.created_at <= p.cutoff_ts)
SELECT 'B5_PRIMARY_DUPLICATE_CANDIDATES' AS result_set, 'EXACT_ALL_ECONOMIC_FIELDS' AS candidate_type,
       to_char(transaction_date,'YYYY-MM-DD') AS group_key, amount AS group_amount, count(*) AS candidate_count, array_agg(id ORDER BY id) AS transaction_ids
FROM reg GROUP BY transaction_date, posted_date, amount, coalesce(lower(payee),'∅'), coalesce(lower(memo),'∅'), coalesce(lower(notes),'∅'),
         coalesce(category_key,'∅'), coalesce(source,'∅'), cleared, reconciled, coalesce(transfer_pair_id::text,'∅'), account_key HAVING count(*)>1
UNION ALL SELECT 'B5_PRIMARY_DUPLICATE_CANDIDATES','SAME_DATE_AMOUNT_NORMALIZED_PAYEE', to_char(transaction_date,'YYYY-MM-DD'), amount, count(*), array_agg(id ORDER BY id)
FROM reg GROUP BY transaction_date, amount, coalesce(lower(payee),'∅') HAVING count(*)>1
UNION ALL SELECT 'B5_PRIMARY_DUPLICATE_CANDIDATES','SAME_DATE_AMOUNT', to_char(transaction_date,'YYYY-MM-DD'), amount, count(*), array_agg(id ORDER BY id)
FROM reg GROUP BY transaction_date, amount HAVING count(*)>1
UNION ALL SELECT 'B5_PRIMARY_DUPLICATE_CANDIDATES','SAME_AMOUNT_NORMALIZED_PAYEE_WITHIN_3_DAYS',
       to_char(r1.transaction_date,'YYYY-MM-DD')||'~'||to_char(r2.transaction_date,'YYYY-MM-DD'), r1.amount, 2, ARRAY[r1.id, r2.id]
FROM reg r1 JOIN reg r2 ON r1.amount=r2.amount AND coalesce(lower(r1.payee),'∅')=coalesce(lower(r2.payee),'∅') AND r1.id<r2.id AND r1.transaction_date<>r2.transaction_date AND abs(r1.transaction_date-r2.transaction_date)<=3
ORDER BY candidate_type, group_amount DESC, group_key;

------------------------------------------------------------------------------
-- B5_FULL_HISTORY_DUPLICATE_CANDIDATES  (OPTIONAL; entire account)
------------------------------------------------------------------------------
WITH chk AS (SELECT key AS account_key FROM public.accounts WHERE key='truist_checking'),
reg AS (SELECT id, account_key, transaction_date, posted_date, amount, payee, memo, notes, category_key, source, cleared, reconciled, transfer_pair_id
        FROM public.transactions WHERE account_key=(SELECT account_key FROM chk))
SELECT 'B5_FULL_HISTORY_DUPLICATE_CANDIDATES' AS result_set, 'EXACT_ALL_ECONOMIC_FIELDS' AS candidate_type,
       to_char(transaction_date,'YYYY-MM-DD') AS group_key, amount AS group_amount, count(*) AS candidate_count, array_agg(id ORDER BY id) AS transaction_ids
FROM reg GROUP BY transaction_date, posted_date, amount, coalesce(lower(payee),'∅'), coalesce(lower(memo),'∅'), coalesce(lower(notes),'∅'),
         coalesce(category_key,'∅'), coalesce(source,'∅'), cleared, reconciled, coalesce(transfer_pair_id::text,'∅'), account_key HAVING count(*)>1
UNION ALL SELECT 'B5_FULL_HISTORY_DUPLICATE_CANDIDATES','SAME_DATE_AMOUNT_NORMALIZED_PAYEE', to_char(transaction_date,'YYYY-MM-DD'), amount, count(*), array_agg(id ORDER BY id)
FROM reg GROUP BY transaction_date, amount, coalesce(lower(payee),'∅') HAVING count(*)>1
ORDER BY candidate_type, group_amount DESC, group_key;

------------------------------------------------------------------------------
-- B6a_TRANSFER_PAIR_POPULATED  (RUN ONLY IF gate B6 = GATE_PASS; all accounts)
------------------------------------------------------------------------------
SELECT 'B6a_TRANSFER_PAIR_POPULATED' AS result_set, transfer_pair_id, count(*) AS leg_count, count(DISTINCT account_key) AS account_count,
  sum(amount) AS signed_net, array_agg(id ORDER BY id) AS member_transaction_ids, array_agg(DISTINCT account_key) AS accounts,
  CASE WHEN count(*)=2 AND count(DISTINCT account_key)=2 AND sum(amount)=0 THEN 'BALANCED_PAIR_OK' ELSE 'INTEGRITY_REVIEW' END AS integrity_result
FROM public.transactions WHERE transfer_pair_id IS NOT NULL GROUP BY transfer_pair_id ORDER BY transfer_pair_id;

------------------------------------------------------------------------------
-- B6b_TRANSFER_CANDIDATES_HEURISTIC  (RUN ONLY IF gates B6 + BCAT = GATE_PASS)
--   Cutoff-synchronized: legs require created_at <= cutoff_ts.
------------------------------------------------------------------------------
WITH params AS (
  SELECT TIMESTAMPTZ '2026-07-28 18:00:00-04:00' AS cutoff_ts,     -- << SET AT CAPTURE
         DATE        '2026-06-30'                AS inspection_start_date, -- << SET AT CAPTURE
         DATE        '2026-07-28'                AS cutoff_business_date   -- << SET AT CAPTURE
),
tcat AS (SELECT key FROM public.categories WHERE behavior_class='transfer' OR parent_key='transfers' OR key LIKE 'transfers.%'),
legs AS (
  SELECT tr.id, tr.account_key, tr.transaction_date, tr.created_at, tr.amount, tr.category_key, tr.payee, tr.memo
  FROM public.transactions tr CROSS JOIN params p
  WHERE tr.transfer_pair_id IS NULL
    AND tr.transaction_date >= p.inspection_start_date
    AND tr.transaction_date <= p.cutoff_business_date
    AND tr.created_at <= p.cutoff_ts
)
SELECT
  'B6b_TRANSFER_CANDIDATES_HEURISTIC' AS result_set,
  d.id AS debit_txn_id, d.account_key AS debit_account, d.amount AS debit_amount, d.transaction_date AS debit_date, d.created_at AS debit_created_at,
  cr.id AS credit_txn_id, cr.account_key AS credit_account, cr.amount AS credit_amount, cr.transaction_date AS credit_date, cr.created_at AS credit_created_at,
  (cr.amount = -d.amount) AS exact_amount_match,
  (d.amount < 0 AND cr.amount > 0) AS opposite_sign,
  abs(cr.transaction_date - d.transaction_date) AS date_gap_days,
  ((d.category_key IN (SELECT key FROM tcat)) OR (cr.category_key IN (SELECT key FROM tcat))) AS transfer_category_flag,
  (d.payee ILIKE '%transfer%' OR d.memo ILIKE '%transfer%' OR cr.payee ILIKE '%transfer%' OR cr.memo ILIKE '%transfer%') AS transfer_like_text_flag,
  (SELECT count(*) FROM legs x WHERE x.amount = -d.amount AND x.account_key <> d.account_key AND x.amount > 0 AND abs(x.transaction_date - d.transaction_date) <= 3) AS credit_counterparts_for_debit,
  (SELECT count(*) FROM legs y WHERE y.amount = -cr.amount AND y.account_key <> cr.account_key AND y.amount < 0 AND abs(y.transaction_date - cr.transaction_date) <= 3) AS debit_counterparts_for_credit,
  CASE WHEN (SELECT count(*) FROM legs x WHERE x.amount = -d.amount AND x.account_key <> d.account_key AND x.amount > 0 AND abs(x.transaction_date - d.transaction_date) <= 3) > 1
        OR (SELECT count(*) FROM legs y WHERE y.amount = -cr.amount AND y.account_key <> cr.account_key AND y.amount < 0 AND abs(y.transaction_date - cr.transaction_date) <= 3) > 1
       THEN 'AMBIGUOUS_MULTIPLE_CANDIDATES' ELSE 'SINGLE_CANDIDATE_HEURISTIC' END AS ambiguity_result,
  true AS owner_review_required,
  'HEURISTIC_ONLY_NOT_CONFIRMED: cutoff-synchronized (created_at<=cutoff_ts); rows created after cutoff belong in B7 drift, not here; null transfer_pair_id prevents definitive pairing' AS match_basis
FROM legs d
JOIN legs cr ON d.amount < 0 AND cr.amount > 0 AND cr.amount = -d.amount AND d.account_key <> cr.account_key AND abs(cr.transaction_date - d.transaction_date) <= 3
ORDER BY d.transaction_date DESC, d.id, cr.id;

------------------------------------------------------------------------------
-- B7a_POST_CUTOFF_DRIFT_COUNTS  (checking; distinct drift classes)
------------------------------------------------------------------------------
WITH params AS (SELECT TIMESTAMPTZ '2026-07-28 18:00:00-04:00' AS cutoff_ts, DATE '2026-07-28' AS cutoff_business_date), -- << SET AT CAPTURE
chk AS (SELECT key AS account_key FROM public.accounts WHERE key='truist_checking'),
t AS (SELECT tr.transaction_date, tr.posted_date, tr.created_at, tr.updated_at, tr.amount
      FROM public.transactions tr WHERE tr.account_key=(SELECT account_key FROM chk))
SELECT 'B7a_POST_CUTOFF_DRIFT_COUNTS' AS result_set, 'CREATED_AFTER_CUTOFF' AS drift_class, count(*) AS row_count, coalesce(sum(amount),0) AS signed_sum,
       'row did not exist at cutoff; no prior-state reconstruction needed' AS note
FROM t, params p WHERE t.created_at > p.cutoff_ts
UNION ALL SELECT 'B7a_POST_CUTOFF_DRIFT_COUNTS','EXISTED_AT_CUTOFF_BUT_UPDATED_AFTER', count(*), coalesce(sum(amount),0),
       'created<=cutoff AND updated>cutoff; prior row state NOT reconstructable from transactions alone'
FROM t, params p WHERE t.created_at <= p.cutoff_ts AND t.updated_at > p.cutoff_ts
UNION ALL SELECT 'B7a_POST_CUTOFF_DRIFT_COUNTS','TRANSACTION_DATE_AFTER_CUTOFF_BUSINESS_DATE', count(*), coalesce(sum(amount),0),
       'future-dated relative to cutoff'
FROM t, params p WHERE t.transaction_date > p.cutoff_business_date
UNION ALL SELECT 'B7a_POST_CUTOFF_DRIFT_COUNTS','BACKDATED_LATE_ENTRY_CREATED_AFTER_DATED_ONOR_BEFORE', count(*), coalesce(sum(amount),0),
       'created>cutoff AND transaction_date<=cutoff_business_date; current drift, not historical'
FROM t, params p WHERE t.created_at > p.cutoff_ts AND t.transaction_date <= p.cutoff_business_date
UNION ALL SELECT 'B7a_POST_CUTOFF_DRIFT_COUNTS','POSTED_AFTER_CUTOFF_BUSINESS_DATE', count(*), coalesce(sum(amount),0),
       'posted_date after cutoff'
FROM t, params p WHERE t.posted_date IS NOT NULL AND t.posted_date > p.cutoff_business_date
ORDER BY drift_class;

------------------------------------------------------------------------------
-- B7b_POST_CUTOFF_DRIFT_DETAIL  (checking; per-row flags; edit flag requires created<=cutoff)
------------------------------------------------------------------------------
WITH params AS (SELECT TIMESTAMPTZ '2026-07-28 18:00:00-04:00' AS cutoff_ts, DATE '2026-07-28' AS cutoff_business_date), -- << SET AT CAPTURE
chk AS (SELECT key AS account_key FROM public.accounts WHERE key='truist_checking')
SELECT
  'B7b_POST_CUTOFF_DRIFT_DETAIL' AS result_set,
  t.id AS transaction_id, t.transaction_date, t.posted_date, t.created_at, t.updated_at,
  t.amount AS signed_amount, t.payee AS payee_merchant, t.cleared AS register_marked_cleared,
  (t.created_at > (SELECT cutoff_ts FROM params)) AS created_after_cutoff,
  (t.created_at <= (SELECT cutoff_ts FROM params) AND t.updated_at > (SELECT cutoff_ts FROM params)) AS existed_but_updated_after_cutoff_prior_state_unknown,
  (t.created_at > (SELECT cutoff_ts FROM params) AND t.transaction_date <= (SELECT cutoff_business_date FROM params)) AS backdated_late_entry,
  (t.transaction_date > (SELECT cutoff_business_date FROM params)) AS dated_after_cutoff,
  (t.posted_date IS NOT NULL AND t.posted_date > (SELECT cutoff_business_date FROM params)) AS posted_after_cutoff
FROM public.transactions t CROSS JOIN params p
WHERE t.account_key=(SELECT account_key FROM chk)
  AND (t.created_at > p.cutoff_ts OR t.updated_at > p.cutoff_ts OR t.transaction_date > p.cutoff_business_date
       OR (t.posted_date IS NOT NULL AND t.posted_date > p.cutoff_business_date))
ORDER BY t.created_at DESC, t.id DESC;

------------------------------------------------------------------------------
-- B8_SIGN_REFERENCE_CLASSES  (RUN ONLY IF gate BCAT = GATE_PASS; exceptions only)
------------------------------------------------------------------------------
WITH chk AS (SELECT key AS account_key FROM public.accounts WHERE key='truist_checking'),
reg AS (SELECT tr.id, tr.amount, tr.payee, tr.memo, tr.category_key, tr.transaction_date FROM public.transactions tr WHERE tr.account_key=(SELECT account_key FROM chk)),
tcat AS (SELECT key FROM public.categories WHERE behavior_class='transfer' OR parent_key='transfers' OR key LIKE 'transfers.%')
SELECT 'B8_SIGN_REFERENCE_CLASSES' AS result_set, 'ZERO_AMOUNT_INTEGRITY' AS reference_class, count(*) AS exception_count, (array_agg(id ORDER BY transaction_date DESC))[1:10] AS sample_ids, 'Expect 0 (DB CHECK amount<>0)' AS note
FROM reg WHERE amount = 0
UNION ALL SELECT 'B8_SIGN_REFERENCE_CLASSES','INCOME_LIKE_BUT_NEGATIVE', count(*), (array_agg(id ORDER BY transaction_date DESC))[1:10], 'Heuristic: income/deposit/payroll/reimbursement-like payee/memo but amount<0 — review'
FROM reg WHERE amount < 0 AND (payee ILIKE '%payroll%' OR payee ILIKE '%deposit%' OR payee ILIKE '%direct dep%' OR payee ILIKE '%reimburs%' OR memo ILIKE '%payroll%' OR memo ILIKE '%deposit%' OR payee ILIKE '%jabian%' OR payee ILIKE '%interest%')
UNION ALL SELECT 'B8_SIGN_REFERENCE_CLASSES','PAYMENT_LIKE_BUT_POSITIVE', count(*), (array_agg(id ORDER BY transaction_date DESC))[1:10], 'Heuristic: card/bill-payment-like payee/memo but amount>0 — review'
FROM reg WHERE amount > 0 AND (payee ILIKE '%payment%' OR payee ILIKE '%bill pay%' OR memo ILIKE '%payment%' OR payee ILIKE '%amex%' OR payee ILIKE '%visa%' OR payee ILIKE '%mastercard%')
UNION ALL SELECT 'B8_SIGN_REFERENCE_CLASSES','TRANSFER_CATEGORY_SIGN_SPREAD_INFO', count(*), (array_agg(id ORDER BY transaction_date DESC))[1:10], 'Informational: transfer-category rows may be either sign; not an exception'
FROM reg WHERE category_key IN (SELECT key FROM tcat) ORDER BY reference_class;
