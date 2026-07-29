-- ============================================================================
-- Step 8 · Baseline C · Reconciliation & Week State  (READ-ONLY)
-- Target: PRODUCTION usayoldrawwmjsmretin.
-- Purpose: validate reconciliation integrity and model-week state so that later
--   capacity work (D/E and the final capacity calculation) rests on a proven,
--   internally-consistent reconciliation/closeout ledger. Baseline C does NOT
--   compute checking capacity, does NOT authorize any transfer, and makes NO
--   live-balance assumption. It is balance-free: it returns ONLY presence flags,
--   counts, dates, states, and enum labels — never a chk/sav/amx/tax/lc value and
--   never a goal funded_amount value.
--
-- Preconditions (same frozen protocol as Baselines A and B):
--   * A0_OPERATOR_PROJECT_CONFIRMATION recorded (operator visually confirmed the
--     SQL-Editor project selector = usayoldrawwmjsmretin; SQL cannot prove it).
--   * A3 showed NO AU-11 object present (global stop otherwise).
--   * A4 gate C = GATE_PASS (weekly_reconciliations week_num/chk) for C1/C2/C3/C4.
--   * A4 gate B = GATE_PASS (accounts.key, transactions.account_key/transaction_date)
--     AND Baseline B's B1a = TARGET_OK (canonical checking key present + unique) —
--     additionally required for C3 (per-week checking-ledger coverage). C3 also emits
--     `checking_account_present` so an absent account row cannot masquerade as an empty
--     ledger (Fable F8).
--   * C0_SCHEMA_PREFLIGHT = C_GATE_PASS. Baseline A did NOT hard-validate the
--     goal_funding_snapshots columns or the weekly_reconciliations sav/amx/tax/lc
--     columns that C uses, so C self-preflights its exact dependency set in C0.
--     Run C1..C4 only when C0 = C_GATE_PASS.
--
-- Editor: the Supabase SQL Editor shows only the LAST result set — run C0..C4 as
--   SEPARATE executions and capture each verbatim. One result set per block.
--
-- Grounded constants (code-cited; not balances):
--   * Model-week domain = 1..31 (goal_funding_snapshots CHECK week_num 1..31;
--     runModel horizon; getCurrentWeek caps at 31, index.html:3441).
--   * Anchor boundary week = 5 (CT_ATTESTATION.anchor_boundary_week, index.html:4041);
--     pre-anchor era = model week <= 5; legacy_pre_anchor = <=4; anchor = 5
--     (closeoutState, index.html:3816-3826).
--   * `reconciled` = a weekly_reconciliations ROW EXISTS for the week — the DEPLOYED
--     predicate (isWeekReconciled index.html:1043 keys on the loaded row; the engine
--     uses !!(reconData[num]) index.html:3156), NOT chk-non-NULL. Any NULL-chk row is a
--     data-quality anomaly, surfaced by C1.chk_present and gated by C4.9 (Fable F3).
--   * Immutable week (application-derived) = reconciled OR week <= 5
--     (_weekIsImmutable, index.html:4448-4451).
--   * Closeout-complete (application-derived) = reconciled AND all nine
--     SNAPSHOT_ELIGIBLE_GOAL_IDS present (_eligibleSnapCount>=9, index.html:2166/3760).
--   * The nine eligible goals: adam_ira, wendy_ira, wendy_sep, alaska, bailey_529,
--     bryce_529, preston_529, bryce_vehicle, christmas_cruise (index.html:3760).
--   * weekly_reconciliations has NO model_year (week_num is the MODEL week, unique);
--     goal_funding_snapshots is model_year-scoped — C filters model_year = 2026.
--   * Model-week -> calendar-date span is JS-derived from epoch new Date(2026,5,7)
--     = 2026-06-07, 7-day weeks (index.html:3441). It is NOT stored in the DB;
--     C3 reconstructs it and labels every span INFERRED.
--   * The authoritative closeout state machine (closeoutState, index.html:3816-3826)
--     runs client-side; C2/C4 emit a DB-side RECONSTRUCTION, clearly labeled.
--
-- No B figure or C figure is checking capacity or transfer authorization. The live
--   bank snapshot (Baseline F) remains the primary actual-balance truth. Operational
--   result stays HOLD.
-- ============================================================================

------------------------------------------------------------------------------
-- C0_SCHEMA_PREFLIGHT  (self-gate for C's exact dependency set; one result set)
--   Baseline A validated env + gates B/B6/BCAT/C/D, but did NOT hard-validate the
--   goal_funding_snapshots columns or weekly_reconciliations sav/amx/tax/lc that C
--   references. C0 confirms every table/column C uses is present and emits a single
--   C_SCHEMA_GATE. Run C1..C4 only when the GATE row = C_GATE_PASS.
------------------------------------------------------------------------------
WITH required(ord, obj_kind, tname, cname) AS (
  VALUES
    (1,'table','weekly_reconciliations',CAST(NULL AS text)),
    (2,'column','weekly_reconciliations','week_num'),
    (3,'column','weekly_reconciliations','chk'),
    (4,'column','weekly_reconciliations','sav'),
    (5,'column','weekly_reconciliations','amx'),
    (6,'column','weekly_reconciliations','tax'),
    (7,'column','weekly_reconciliations','lc'),
    (8,'column','weekly_reconciliations','balance_basis'),
    (9,'column','weekly_reconciliations','recorded_at'),
    (10,'table','goal_funding_snapshots',NULL),
    (11,'column','goal_funding_snapshots','model_year'),
    (12,'column','goal_funding_snapshots','week_num'),
    (13,'column','goal_funding_snapshots','goal_id'),
    (14,'column','goal_funding_snapshots','source'),
    (15,'table','transactions',NULL),
    (16,'column','transactions','account_key'),
    (17,'column','transactions','transaction_date'),
    (18,'table','accounts',NULL),
    (19,'column','accounts','key')
),
evaluated AS (
  SELECT r.ord, r.obj_kind, r.tname, r.cname,
    CASE r.obj_kind
      WHEN 'table'  THEN EXISTS (SELECT 1 FROM information_schema.tables  WHERE table_schema='public' AND table_name=r.tname)
      ELSE               EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=r.tname AND column_name=r.cname)
    END AS actual_present
  FROM required r
)
SELECT 'C0_SCHEMA_PREFLIGHT' AS result_set, e.ord AS sort_ord, e.obj_kind, e.tname AS table_name, e.cname AS column_name,
       'HARD_REQUIRED_FOR_C' AS severity, e.actual_present,
       CASE WHEN e.actual_present THEN 'PASS' ELSE 'FAIL_BLOCK' END AS result
FROM evaluated e
UNION ALL
SELECT 'C0_SCHEMA_PREFLIGHT', 9999, 'gate', NULL, NULL, 'C_SCHEMA_GATE',
       (SELECT bool_and(actual_present) FROM evaluated),
       CASE WHEN (SELECT bool_and(actual_present) FROM evaluated) THEN 'C_GATE_PASS' ELSE 'C_GATE_FAIL_STOP' END
ORDER BY sort_ord;

------------------------------------------------------------------------------
-- C1_RECONCILIATION_INVENTORY  (stored reconciliation facts; balance-free)
--   One row per stored weekly_reconciliations record. Returns ONLY the week_num,
--   the balance_basis enum, the recorded_at timestamp, and per-account PRESENCE
--   FLAGS (IS NOT NULL) — never the chk/sav/amx/tax/lc amounts. This is the
--   Register reconciliation status inventory. Deterministic by week_num.
------------------------------------------------------------------------------
SELECT 'C1_RECONCILIATION_INVENTORY' AS result_set,
  wr.week_num,
  (wr.week_num BETWEEN 1 AND 31)      AS week_in_model_domain,
  wr.balance_basis,                    -- enum text (posted_current_balance|available_balance|unknown|NULL); not a balance
  wr.recorded_at,
  (wr.chk IS NOT NULL)                 AS chk_present,
  (wr.sav IS NOT NULL)                 AS sav_present,
  (wr.amx IS NOT NULL)                 AS amx_present,
  (wr.tax IS NOT NULL)                 AS tax_present,
  (wr.lc  IS NOT NULL)                 AS lc_present,
  (wr.chk IS NOT NULL AND wr.sav IS NOT NULL AND wr.amx IS NOT NULL AND wr.tax IS NOT NULL AND wr.lc IS NOT NULL) AS all_five_balances_present
FROM public.weekly_reconciliations wr
ORDER BY wr.week_num;

------------------------------------------------------------------------------
-- C2_WEEK_STATE_MATRIX  (weeks 1..31; reconciled/anchor/immutable/closeout state)
--   Generates the full 31-week model domain and LEFT JOINs reconciliation +
--   closeout-snapshot facts. `is_immutable_app_derived` and `closeout_state_db_derived`
--   are DB-side RECONSTRUCTIONS of application logic (immutability index.html:4448-4451;
--   closeoutState index.html:3816-3826) — the authoritative values are computed
--   client-side. `reconciled` follows the DEPLOYED predicate: a weekly_reconciliations
--   ROW EXISTS for the week (isWeekReconciled index.html:1043; engine !!(reconData[num])
--   index.html:3156 both treat row-existence as reconciled) — NOT chk-non-NULL; a NULL-chk
--   row is a data-quality anomaly surfaced by C1.chk_present and C4.9 (Fable F3).
--   The closeout CASE is TOTAL and app-faithful (Fable F1/F6): reconciled AND >=9 =>
--   complete; reconciled AND <9 (incl 0) => half_closed; NOT reconciled AND >=1 =>
--   corrupt (the app's hard-stop state); NOT reconciled AND 0 => open_or_blocked. Snapshot
--   columns are COUNTS of the nine eligible goal ids and of total rows — never funded_amount
--   values. Deterministic by week_num.
------------------------------------------------------------------------------
WITH weeks AS (SELECT generate_series(1,31) AS week_num),
eligible(goal_id) AS (
  VALUES ('adam_ira'),('wendy_ira'),('wendy_sep'),('alaska'),('bailey_529'),
         ('bryce_529'),('preston_529'),('bryce_vehicle'),('christmas_cruise')
),
recon AS (SELECT week_num, true AS reconciled FROM public.weekly_reconciliations GROUP BY week_num),  -- row-existence (deployed predicate); GROUP BY collapses any duplicate
snap AS (
  SELECT gfs.week_num,
         count(DISTINCT gfs.goal_id) FILTER (WHERE el.goal_id IS NOT NULL) AS distinct_eligible,
         count(*)                                                          AS total_rows
  FROM public.goal_funding_snapshots gfs
  LEFT JOIN eligible el ON el.goal_id = gfs.goal_id
  WHERE gfs.model_year = 2026
  GROUP BY gfs.week_num
)
SELECT 'C2_WEEK_STATE_MATRIX' AS result_set,
  w.week_num,
  coalesce(r.reconciled, false)                         AS reconciled,               -- row-existence (deployed predicate)
  (w.week_num <= 4)                                     AS is_legacy_pre_anchor,      -- closeoutState==legacy_pre_anchor
  (w.week_num = 5)                                      AS is_anchor,                 -- closeoutState==anchor
  (coalesce(r.reconciled,false) OR w.week_num <= 5)     AS is_immutable_app_derived,  -- reconciled OR week<=anchor_boundary(5)
  coalesce(s.distinct_eligible, 0)                      AS snapshot_distinct_eligible_goals, -- of the nine (index.html:3760); a COUNT, not amounts
  coalesce(s.total_rows, 0)                             AS snapshot_total_rows,
  CASE
    WHEN w.week_num <= 4 THEN 'legacy_pre_anchor'
    WHEN w.week_num = 5  THEN 'anchor'
    WHEN coalesce(r.reconciled,false) AND coalesce(s.distinct_eligible,0) >= 9 THEN 'complete_db_derived'
    WHEN coalesce(r.reconciled,false)                                          THEN 'half_closed_db_derived'  -- reconciled, elig<9 incl 0 (app half_closed)
    WHEN coalesce(s.distinct_eligible,0) >= 1                                  THEN 'corrupt_db_derived'      -- NOT reconciled, elig>=1 (app hard-stop corrupt)
    ELSE 'open_or_blocked_db_derived'                                          -- NOT reconciled, elig=0 (app open / blocked_prior_incomplete)
  END AS closeout_state_db_derived   -- DB reconstruction; authoritative state is client-side (index.html:3816-3826)
FROM weeks w
LEFT JOIN recon r ON r.week_num = w.week_num
LEFT JOIN snap  s ON s.week_num = w.week_num
ORDER BY w.week_num;

------------------------------------------------------------------------------
-- C3_LEDGER_COVERAGE_BY_WEEK  (INFERRED week->date span; checking-ledger coverage)
--   Requires A4 gate B AND Baseline B's B1a = TARGET_OK (the canonical checking key
--   is present and unique) in addition to gate C. For each model week 1..31 this
--   reconstructs the calendar span from the JS epoch (2026-06-07, 7-day weeks;
--   index.html:3441) and returns the COUNT of Truist Checking transactions whose
--   transaction_date falls in that span, alongside the reconciled flag (row-existence,
--   deployed predicate). `checking_account_present` guards the silent-zero case
--   (Fable F8): when it is 0 the canonical account row is absent and the all-zero
--   counts mean "account missing", not "empty ledger". It exposes week-level ledger
--   coverage (e.g. reconciled weeks with zero checking activity, or activity in
--   unreconciled weeks) WITHOUT any amount. The span is INFERRED, NOT stored — every
--   downstream use must carry that caveat (U2). Balance-free; counts only.
--   Deterministic by week_num.
------------------------------------------------------------------------------
WITH weeks AS (
  SELECT g AS week_num,
         (DATE '2026-06-07' + (7 * (g - 1)))     AS week_start_inferred,  -- INFERRED (not stored)
         (DATE '2026-06-07' + (7 * (g - 1)) + 6) AS week_end_inferred     -- INFERRED (not stored)
  FROM generate_series(1,31) AS g
),
chk AS (SELECT key AS account_key FROM public.accounts WHERE key='truist_checking'),
recon AS (SELECT week_num FROM public.weekly_reconciliations)  -- row-existence (deployed predicate)
SELECT 'C3_LEDGER_COVERAGE_BY_WEEK' AS result_set,
  w.week_num,
  w.week_start_inferred,
  w.week_end_inferred,
  (SELECT count(*) FROM chk)                                     AS checking_account_present,  -- 1 = present; 0 = missing (counts below then meaningless)
  EXISTS (SELECT 1 FROM recon rc WHERE rc.week_num = w.week_num) AS reconciled,                -- row-existence (deployed predicate)
  (SELECT count(*) FROM public.transactions t
     WHERE t.account_key = (SELECT account_key FROM chk)
       AND t.transaction_date >= w.week_start_inferred
       AND t.transaction_date <= w.week_end_inferred) AS checking_txn_count_in_inferred_span
FROM weeks w
ORDER BY w.week_num;

------------------------------------------------------------------------------
-- C4_RECONCILIATION_PREREQUISITES  (named control checks; single gate result set)
--   The controls that must hold before any later capacity calculation trusts the
--   reconciliation/closeout ledger. Each row is one named check with an observed
--   value, its expectation, and a verdict (PASS | REVIEW | STOP | INFO). The final
--   C4.OVERALL row rolls up the GATING checks ONLY (STOP dominates REVIEW dominates
--   PASS); the two INFO checks (C4.11 legacy pre-anchor NULL basis, C4.12 recorded_at
--   monotonicity) are observability-only and are EXCLUDED from OVERALL (Fable F2/F4)
--   so a legitimate legacy NULL basis or an owner-approved historical correction
--   cannot permanently pin the gate at REVIEW. `reconciled` = row-existence (deployed
--   predicate). Counts/booleans only — balance-free. Deterministic by `seq` (an
--   explicit integer sort key; OVERALL last).
------------------------------------------------------------------------------
WITH eligible(goal_id) AS (
  VALUES ('adam_ira'),('wendy_ira'),('wendy_sep'),('alaska'),('bailey_529'),
         ('bryce_529'),('preston_529'),('bryce_vehicle'),('christmas_cruise')
),
wr AS (SELECT week_num, balance_basis, recorded_at, chk FROM public.weekly_reconciliations),
reconw AS (SELECT week_num FROM public.weekly_reconciliations GROUP BY week_num),   -- distinct reconciled weeks (row-existence)
perweek AS (SELECT week_num, min(recorded_at) AS recorded_at FROM wr GROUP BY week_num),  -- dup-safe: one timestamp per week
snap AS (
  SELECT gfs.week_num, count(DISTINCT gfs.goal_id) FILTER (WHERE el.goal_id IS NOT NULL) AS distinct_eligible
  FROM public.goal_funding_snapshots gfs
  LEFT JOIN eligible el ON el.goal_id = gfs.goal_id
  WHERE gfs.model_year = 2026
  GROUP BY gfs.week_num
),
dupes AS (SELECT week_num FROM public.weekly_reconciliations GROUP BY week_num HAVING count(*) > 1),
recset AS (SELECT count(DISTINCT week_num) AS n, min(week_num) AS mn, max(week_num) AS mx FROM public.weekly_reconciliations),  -- Fable F5: DISTINCT so duplicates cannot mask a hole
inversions AS (
  SELECT count(*) AS n FROM (
    SELECT recorded_at, lag(recorded_at) OVER (ORDER BY week_num) AS prev FROM perweek
  ) q WHERE prev IS NOT NULL AND recorded_at < prev
)
SELECT 'C4_RECONCILIATION_PREREQUISITES' AS result_set, 10 AS seq, 'C4.1' AS check_id,
  'No duplicate weekly_reconciliations rows per week_num' AS description,
  (SELECT count(*) FROM dupes)::text AS observed, '0' AS expected,
  CASE WHEN (SELECT count(*) FROM dupes)=0 THEN 'PASS' ELSE 'STOP' END AS verdict
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 20, 'C4.2',
  'All weekly_reconciliations.week_num within model domain 1..31',
  (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num < 1 OR week_num > 31)::text, '0',
  CASE WHEN (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num < 1 OR week_num > 31)=0 THEN 'PASS' ELSE 'STOP' END
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 30, 'C4.3',
  'Anchor week (model week 5) is reconciled (row exists)',
  (SELECT count(*) FROM reconw WHERE week_num = 5)::text, '1 (present)',
  CASE WHEN (SELECT count(*) FROM reconw WHERE week_num = 5) >= 1 THEN 'PASS' ELSE 'REVIEW' END
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 40, 'C4.4',
  'Reconciled weeks form a contiguous prefix 1..N (no holes; distinct week_num)',
  (SELECT (n = mx AND mn = 1) FROM recset)::text, 'true',
  CASE WHEN (SELECT (n = mx AND mn = 1) FROM recset) THEN 'PASS' ELSE 'REVIEW' END
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 50, 'C4.5',
  'Post-anchor reconciled weeks (>=6) carry a balance_basis (non-NULL)',
  (SELECT count(*) FROM wr WHERE week_num >= 6 AND balance_basis IS NULL)::text, '0',
  CASE WHEN (SELECT count(*) FROM wr WHERE week_num >= 6 AND balance_basis IS NULL)=0 THEN 'PASS' ELSE 'REVIEW' END
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 60, 'C4.6',
  'Post-anchor reconciled weeks (>=6) have full closeout snapshots (9 distinct eligible)',
  (SELECT count(*) FROM reconw r WHERE r.week_num >= 6
     AND coalesce((SELECT distinct_eligible FROM snap s WHERE s.week_num = r.week_num),0) < 9)::text, '0',
  CASE WHEN (SELECT count(*) FROM reconw r WHERE r.week_num >= 6
     AND coalesce((SELECT distinct_eligible FROM snap s WHERE s.week_num = r.week_num),0) < 9)=0 THEN 'PASS' ELSE 'REVIEW' END
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 70, 'C4.7',
  'No closeout snapshots on unreconciled post-anchor weeks (>=6)',
  (SELECT count(*) FROM snap s WHERE s.week_num >= 6 AND NOT EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = s.week_num))::text, '0',
  CASE WHEN (SELECT count(*) FROM snap s WHERE s.week_num >= 6 AND NOT EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = s.week_num))=0 THEN 'PASS' ELSE 'REVIEW' END
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 80, 'C4.8',
  'All goal_funding_snapshots (2026) week_num within 1..31',
  (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND (week_num < 1 OR week_num > 31))::text, '0',
  CASE WHEN (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND (week_num < 1 OR week_num > 31))=0 THEN 'PASS' ELSE 'STOP' END
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 90, 'C4.9',
  'No weekly_reconciliations rows with NULL chk (app treats row-existence as reconciled; a NULL chk is a data-quality divergence — Fable F3)',
  (SELECT count(*) FROM wr WHERE chk IS NULL)::text, '0',
  CASE WHEN (SELECT count(*) FROM wr WHERE chk IS NULL)=0 THEN 'PASS' ELSE 'REVIEW' END
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 100, 'C4.10',
  'No goal_funding_snapshots (2026) on legacy pre-anchor weeks (<=4) or on an unreconciled anchor week 5 (Fable F7)',
  (SELECT count(*) FROM snap s WHERE s.week_num <= 4 OR (s.week_num = 5 AND NOT EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = 5)))::text, '0',
  CASE WHEN (SELECT count(*) FROM snap s WHERE s.week_num <= 4 OR (s.week_num = 5 AND NOT EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = 5)))=0 THEN 'PASS' ELSE 'REVIEW' END
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 110, 'C4.11',
  'INFO (excluded from OVERALL): legacy pre-anchor/anchor reconciled weeks (<=5) with NULL balance_basis — legitimate pre-5F-1; observability only (Fable F2)',
  (SELECT count(*) FROM wr WHERE week_num <= 5 AND balance_basis IS NULL)::text, 'informational',
  'INFO'
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 120, 'C4.12',
  'INFO (excluded from OVERALL): recorded_at non-decreasing across ascending week_num — an owner-approved historical correction legitimately inverts it (Fable F4)',
  (SELECT n FROM inversions)::text, 'informational',
  'INFO'
UNION ALL
SELECT 'C4_RECONCILIATION_PREREQUISITES', 9999, 'C4.OVERALL',
  'Overall reconciliation-prerequisite gate over GATING checks only (STOP dominates REVIEW dominates PASS; INFO excluded)',
  NULL, 'C_PREREQ_PASS',
  CASE
    WHEN (SELECT count(*) FROM dupes) > 0
      OR (SELECT count(*) FROM public.weekly_reconciliations WHERE week_num < 1 OR week_num > 31) > 0
      OR (SELECT count(*) FROM public.goal_funding_snapshots WHERE model_year=2026 AND (week_num < 1 OR week_num > 31)) > 0
      THEN 'C_PREREQ_STOP'
    WHEN (SELECT count(*) FROM reconw WHERE week_num = 5) < 1
      OR NOT coalesce((SELECT (n = mx AND mn = 1) FROM recset), false)
      OR (SELECT count(*) FROM wr WHERE week_num >= 6 AND balance_basis IS NULL) > 0
      OR (SELECT count(*) FROM reconw r WHERE r.week_num >= 6
            AND coalesce((SELECT distinct_eligible FROM snap s WHERE s.week_num = r.week_num),0) < 9) > 0
      OR (SELECT count(*) FROM snap s WHERE s.week_num >= 6 AND NOT EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = s.week_num)) > 0
      OR (SELECT count(*) FROM wr WHERE chk IS NULL) > 0
      OR (SELECT count(*) FROM snap s WHERE s.week_num <= 4 OR (s.week_num = 5 AND NOT EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = 5))) > 0
      THEN 'C_PREREQ_REVIEW'
    ELSE 'C_PREREQ_PASS'
  END
ORDER BY seq;
