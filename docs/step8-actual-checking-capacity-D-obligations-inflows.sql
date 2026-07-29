-- ============================================================================
-- Step 8 · Baseline D · Obligations & Inflows  (READ-ONLY, DRAFT — Fable-reviewed rev 3)
-- Target: PRODUCTION usayoldrawwmjsmretin (Phase 5F-1 schema; pre-AU-11).
-- Purpose: establish the AUTHORITATIVE, DB-representable near-term checking
--   OBLIGATIONS and INFLOWS that must feed the actual-checking-capacity calculation
--   (Baseline E / final). Baseline D does NOT compute checking capacity, does NOT
--   authorize any transfer, and preserves the operational HOLD.
--
-- ─── HEADLINE ARCHITECTURAL LIMITATION (grounded, not assumed) ───────────────
--   The deployed weekly cash model's BASE inflows/obligations — paychecks &
--   commissions (inflows), rent, ALL card payments (AMEX Gold/Platinum, Disney
--   Visa), the Kia payment, and the wk15 Alaska $7,000 draw — are HARDCODED IN JS
--   in the `WD` array (index.html:909-941) and in runModel (Alaska draw 3056-3068).
--   They are NOT stored in the database and are INVISIBLE to any SQL baseline.
--   Baseline D inventories only the DB OVERLAYS (cash_commitments, weekly_tasks,
--   custom_tasks, transactions, goal_funding_snapshots, weekly_reconciliations,
--   categories). The FINAL capacity calc still needs the code-side WD base schedule
--   + forward modeled inflows as an OUT-OF-BAND input.
--
-- ─── AUTHORITATIVE OBLIGATION MODEL (grounded; Fable F1) ────────────────────
--   The deployed Cash Availability Engine (index.html:2453-2463) withholds capacity
--   for truist_checking cash_commitments rows, but the set DEPENDS ON WHETHER THE
--   AS-OF WEEK IS RECONCILED (build at index.html:3156-3176):
--     * RECONCILED as-of week: reserve = source_account='truist_checking' AND
--         isReservedAsOf(c, w).                            (index.html:3159-3162)
--     * PROJECTED (UNRECONCILED) as-of week: reserve ADDS stricter guards
--         (index.html:3166-3171): origin_model_week < w (STRICT) AND
--         (origin week reconciled OR commitment_source='historical_repair'),
--       so a commitment does NOT double-reserve against its WD origin-week event.
--   Baseline C proved reconciled prefix = weeks 1-7 only, so at as-of ~week 8 the
--   PROJECTED branch governs. D3/D7 compute a branch-correct `is_engine_reserved`.
--   isReservedAsOf(c,w) (index.html:2438-2448) is encoded verbatim. amount_cents is a
--   POSITIVE magnitude = a DEBIT/reserve vs checking. Floor OP_FL=6500 (index.html:896);
--   engine seeded with effFl=OP_FL (index.html:3011/3174), not laFl (3141).
--
-- ─── BKX / COMMISSION-TAX OVERLAP CONTROL (grounded; Fable F5, rev-3) ────────
--   The same real obligation can appear in more than one place: BKX ($700.90) is one
--   Week-29 custom_tasks transfer with the amount IN LABEL TEXT (custom_tasks has NO
--   amount column; decision-log.md:45); commission-tax obligations live in weekly_tasks
--   legs; and a cash_commitments row could duplicate either. Because exact amount/week
--   equality is BRITTLE (partial-transfer/carry-forward change the amount and/or shift
--   the week; the merged-artifact figure $700.91 sits adjacent to $700.90), D uses
--   BROADENED, DISCLOSED heuristics:
--     * BKX evidence on a cash_commitments row: amount_cents IN (70090,70091) [±1¢
--       tolerance for the 700.90/700.91 pair], OR payee/notes ILIKE '%bkx%'/'%extra bk%'.
--     * commission-tax overlap on a cash_commitments row: commitment_class='tax_transfer'
--       AND a COMPLETED weekly_tasks commission_tax leg within ±1 model week of the
--       commitment's origin OR reflected week, OR within ±1¢ of amount_cents (±1 week
--       captures carry-forward; ±1¢ captures rounding/merged-artifact; same-week captures
--       partial-in-same-week).
--   ANY such overlap candidate is classified `owner_review_required` in D3 and is
--   EXCLUDED from the D7 authoritative total until the owner resolves it. D9 emits
--   D_HANDOFF_FAIL_STOP while any engine-reserved, well-formed overlap candidate exists,
--   so an unresolved duplicate can never double-count in Baseline E. LIMITATION: these
--   are heuristics — a partial transfer whose amount AND week both diverge beyond the
--   windows is still surfaced only if it shares the tax_transfer class + a ±1-week leg;
--   genuinely disjoint representations require owner adjudication (see D6/D8).
--
-- ─── AMOUNT EXPOSURE (Fable F6) ─────────────────────────────────────────────
--   Amount-bearing: D2, D2B, D3, D4 (label text / completed_amount for owner-review),
--   D6, D7. NON-amount: D0, D1, D5, D8, D9. NO account balances; no raw ledger dumps;
--   amounts labeled modeled/posted/completed/cleared/inferred.
--
-- ─── PROVENANCE / CLASSIFICATION CONTRACT ───────────────────────────────────
--   direction ∈ {obligation_debit, inflow_credit, transfer_out_chk_to_goal,
--                transfer_in_goal_to_chk, tax_reserve_out, informational_na}
--   authority_classification ∈ {authoritative, informational, excluded, owner_review_required}
--   uncleared_class (D2B) ∈ {valid_candidate, overlap_owner_review, malformed}
--
-- Preconditions (same frozen protocol as A/B/C): A0 project confirmation; A3 AU-11
--   absent (D0 re-asserts); A4 gates B+C+D = GATE_PASS; D0 = D_GATE_PASS. Editor shows
--   only the LAST result set — run each block as a SEPARATE execution.
--
-- CUTOFF / HORIZON (grounded; do not mix conventions): horizon 31 = WD length
--   (index.html:909-941); as-of = MODEL-WEEK integer (getCurrentWeek, index.html:3441)
--   + model_year=2026; due_date/statement dates descriptive-only (index.html:2519-2529);
--   transaction_date only for the transactions overlay (D2/D2B/D5). `p_as_of_model_week`
--   parameterized (default 8 = 2026-07-28; owner-set at capture); echoed in every as-of block.
--
-- Rev-3 changes (this revision): fully apply Fable F5 (broadened BKX/commission-tax
--   overlap heuristics in D3/D6/D7/D9; overlap → owner_review, excluded from D7; D9
--   fail-closed on unresolved overlap) and tighten the uncleared-Register handoff (D2B
--   per-item uncleared_class valid/overlap/malformed; D9 fail-closed on malformed/overlap;
--   E consumes only the deterministic valid_candidate set). Rev-2 applied F1/F2/F3/F4/F6/F8.
--   F7 (D6 class-1 grouping tidy) DEFERRED — operationally immaterial: expected_item_id is
--   UNIQUE (phase-5f-1-migration.sql:50), so the extra GROUP BY keys cannot mask a true
--   duplicate; D9's eid-only grouping is the authoritative duplicate gate.
--
-- No D result is checking capacity or transfer authorization. Operational result HOLD.
-- ============================================================================

------------------------------------------------------------------------------
-- D0_SCHEMA_ENVIRONMENT_GATE  (self-gate for D's dependency set + AU-11 absence)
------------------------------------------------------------------------------
WITH required(ord, kind, tname, cname, expect_present) AS (
  VALUES
    (1,'table','cash_commitments',CAST(NULL AS text), true),
    (2,'column','cash_commitments','id', true),
    (3,'column','cash_commitments','expected_item_id', true),
    (4,'column','cash_commitments','model_year', true),
    (5,'column','cash_commitments','source_account', true),
    (6,'column','cash_commitments','origin_model_week', true),
    (7,'column','cash_commitments','reflected_model_week', true),
    (8,'column','cash_commitments','resolved_model_week', true),
    (9,'column','cash_commitments','status', true),
    (10,'column','cash_commitments','resolution_type', true),
    (11,'column','cash_commitments','affects_deployable_cash', true),
    (12,'column','cash_commitments','amount_cents', true),
    (13,'column','cash_commitments','commitment_class', true),
    (14,'column','cash_commitments','required_or_discretionary', true),
    (15,'column','cash_commitments','commitment_source', true),
    (16,'column','cash_commitments','due_date', true),
    (17,'column','cash_commitments','cleared_date', true),
    (18,'column','cash_commitments','payee', true),
    (19,'column','cash_commitments','notes', true),
    (20,'column','transactions','id', true),
    (21,'column','transactions','account_key', true),
    (22,'column','transactions','transaction_date', true),
    (23,'column','transactions','amount', true),
    (24,'column','transactions','category_key', true),
    (25,'column','transactions','cleared', true),
    (26,'column','transactions','reconciled', true),
    (27,'column','transactions','payee', true),
    (28,'column','transactions','memo', true),
    (29,'column','transactions','notes', true),
    (30,'column','categories','key', true),
    (31,'column','categories','behavior_class', true),
    (32,'column','categories','budget_treatment', true),
    (33,'column','categories','cashflow_treatment', true),
    (34,'column','custom_tasks','id', true),
    (35,'column','custom_tasks','week_num', true),
    (36,'column','custom_tasks','label', true),
    (37,'column','custom_tasks','completed', true),
    (38,'column','weekly_tasks','week_num', true),
    (39,'column','weekly_tasks','task_idx', true),
    (40,'column','weekly_tasks','completed', true),
    (41,'column','weekly_tasks','completed_amount', true),
    (42,'column','weekly_tasks','action_key', true),
    (43,'column','weekly_tasks','completed_label', true),
    (44,'column','goal_funding_snapshots','model_year', true),
    (45,'column','goal_funding_snapshots','week_num', true),
    (46,'column','goal_funding_snapshots','goal_id', true),
    (47,'column','goal_funding_snapshots','source', true),
    (48,'column','weekly_reconciliations','week_num', true),
    (49,'column','accounts','key', true),
    (50,'column','cash_commitments','reservation_batch_id', false),
    (51,'column','cash_commitments','goal_id', false),
    (52,'column','cash_commitments','cleared_transaction_id', false),
    (53,'table','discretionary_reservation_batches',NULL, false)
),
evaluated AS (
  SELECT r.ord, r.kind, r.tname, r.cname, r.expect_present,
    CASE r.kind
      WHEN 'table'  THEN EXISTS (SELECT 1 FROM information_schema.tables  WHERE table_schema='public' AND table_name=r.tname)
      ELSE               EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=r.tname AND column_name=r.cname)
    END AS actual_present
  FROM required r
)
SELECT 'D0_SCHEMA_ENVIRONMENT_GATE' AS result_set, e.ord AS sort_ord, e.kind AS object_kind,
       e.tname AS table_name, e.cname AS column_name, e.expect_present, e.actual_present,
       CASE WHEN e.actual_present = e.expect_present THEN 'PASS'
            WHEN e.expect_present THEN 'FAIL_MISSING_STOP'
            ELSE 'FAIL_AU11_PRESENT_STOP' END AS result
FROM evaluated e
UNION ALL
SELECT 'D0_SCHEMA_ENVIRONMENT_GATE', 9999, 'gate', NULL, NULL, NULL,
       (SELECT bool_and(actual_present = expect_present) FROM evaluated),
       CASE WHEN (SELECT bool_and(actual_present = expect_present) FROM evaluated) THEN 'D_GATE_PASS' ELSE 'D_GATE_FAIL_STOP' END
ORDER BY sort_ord;

------------------------------------------------------------------------------
-- D1_HORIZON_AND_CUTOFF  (deployed horizon + cutoff reconstruction; non-amount)
------------------------------------------------------------------------------
WITH params AS (
  SELECT 2026 AS p_model_year, 31 AS p_horizon_weeks,
         8 AS p_as_of_model_week    -- << SET AT CAPTURE (getCurrentWeek, index.html:3441). Illustrative 8 = 2026-07-28.
),
rec AS (SELECT count(DISTINCT week_num) AS n, min(week_num) AS mn, max(week_num) AS mx FROM public.weekly_reconciliations)
SELECT 'D1_HORIZON_AND_CUTOFF' AS result_set,
  (SELECT p_model_year FROM params)       AS model_year,
  (SELECT p_horizon_weeks FROM params)    AS horizon_weeks,
  (SELECT p_as_of_model_week FROM params) AS as_of_model_week,
  (EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=(SELECT p_as_of_model_week FROM params))) AS as_of_is_reconciled,
  DATE '2026-06-07'                        AS model_epoch_wk1_start_inferred,
  (DATE '2026-06-07' + (7 * ((SELECT p_horizon_weeks FROM params) - 1)) + 6) AS horizon_end_inferred,
  (SELECT n FROM rec)                      AS reconciled_week_count,
  (SELECT mn FROM rec)                     AS reconciled_min_week,
  (SELECT mx FROM rec)                     AS reconciled_max_week,
  ((SELECT n FROM rec) = (SELECT mx FROM rec) AND (SELECT mn FROM rec) = 1) AS reconciled_prefix_contiguous,
  'HORIZON 31 = WD array length (index.html:909-941); reservation cutoff is MODEL-WEEK integer (isReservedAsOf, index.html:2438-2448), never due_date. If as_of_is_reconciled=false the ENGINE uses the projected branch (index.html:3166-3171) — D3/D7 apply it. BASE modeled inflows/obligations (paychecks, rent, all card payments, Kia, Alaska wk15 draw) are HARDCODED IN JS and NOT in the DB — this baseline inventories DB overlays only; the code-side base schedule + forward modeled inflows are OUT-OF-BAND inputs to the final capacity calc.' AS scope_disclosure;

------------------------------------------------------------------------------
-- D2_INFLOWS_IN_SCOPE_DB  (AMOUNT-BEARING; DB-visible inflows only)
--   Only DB-representable forward inflow relevant to capacity is the Alaska goal
--   DISBURSEMENT (category transfers.goal_disbursement; 0 rows by design — PKG-TAX-1).
--   Jabian = reminder-only (index.html:7346-7350). FSA = health_fitness.flexible_spending_2026,
--   budget_treatment='excluded', net-zero (phase-5d-1-migration.sql:401,412). Both excluded.
------------------------------------------------------------------------------
WITH disb AS (
  SELECT t.id, t.transaction_date, t.amount, t.category_key, t.cleared, t.reconciled
  FROM public.transactions t
  WHERE t.account_key='truist_checking' AND t.category_key='transfers.goal_disbursement'
)
SELECT 'D2_INFLOWS_IN_SCOPE_DB' AS result_set,
  'transactions'                    AS source_table,
  d.id::text                        AS source_id,
  NULL::int                         AS model_week,
  d.transaction_date                AS relevant_date,
  d.category_key                    AS class_or_type,
  'transfer_in_goal_to_chk'         AS direction,
  CASE WHEN d.cleared THEN 'posted_cleared' WHEN d.reconciled THEN 'reconciled' ELSE 'posted' END AS status,
  d.amount                          AS amount_signed_posted,
  'informational'                   AS authority_classification,
  'goal-disbursement reimbursement (e.g. Alaska); expect 0 rows pre-settlement. Executed disbursements are already in the actual checking balance (Baseline B/C).' AS note
FROM disb d
UNION ALL
SELECT 'D2_INFLOWS_IN_SCOPE_DB', '(disclosure)', NULL, NULL, NULL,
  'modeled_forward_inflows', 'informational_na', 'out_of_band', NULL::numeric,
  'owner_review_required',
  'Paychecks/commissions (WD inflows, index.html:909-941) are code-side and NOT in the DB; Jabian reimbursements are reminder-only (index.html:7346-7350) and FSA (health_fitness.flexible_spending_2026) is budget_treatment=excluded/net-zero (phase-5d-1-migration.sql:401,412) — both excluded from capacity; supply out-of-band to the final capacity calc.'
ORDER BY relevant_date NULLS LAST, source_id;

------------------------------------------------------------------------------
-- D2B_UNCLEARED_REGISTER_ITEMS  (AMOUNT-BEARING; Fable F2 + tightened handoff, rev-3)
--   Uncleared truist_checking Register items (both signs) are NOT cash_commitments and
--   are seen by neither D2 nor D3, yet a pending uncleared debit consumes real capacity.
--   Each item is classified `uncleared_class`:
--     valid_candidate      = complete identity/amount/date; E-eligible (after live-bank recon)
--     overlap_owner_review = a debit whose magnitude matches an OPEN reserved commitment
--                            (±1¢) or carries BKX text → may double-count → blocks handoff
--     malformed            = NULL id/amount/date → fail-closed
--   E consumes only the deterministic valid_candidate SET (with direction + classification),
--   never a bare count; D9 fails while any overlap/malformed exists.
------------------------------------------------------------------------------
WITH cc_reserved AS (   -- OPEN, unreflected truist_checking reserves (overlap basis)
  SELECT c.amount_cents FROM public.cash_commitments c
  WHERE c.model_year=2026 AND c.source_account='truist_checking' AND c.affects_deployable_cash=true
    AND c.status <> 'voided'
    AND (c.resolution_type IS NULL OR c.resolution_type NOT IN ('voided','paid_from_other_account'))
    AND c.reflected_model_week IS NULL AND c.resolved_model_week IS NULL
)
SELECT 'D2B_UNCLEARED_REGISTER_ITEMS' AS result_set,
  'transactions'                    AS source_table,
  t.id::text                        AS source_id,
  t.transaction_date                AS relevant_date,
  t.category_key                    AS class_or_type,
  CASE WHEN t.amount < 0 THEN 'obligation_debit' WHEN t.amount > 0 THEN 'inflow_credit' ELSE 'informational_na' END AS direction,
  'uncleared'                       AS status,
  t.amount                          AS amount_signed_posted,
  CASE
    WHEN t.id IS NULL OR t.amount IS NULL OR t.transaction_date IS NULL THEN 'malformed'
    WHEN t.amount < 0 AND (
         EXISTS (SELECT 1 FROM cc_reserved r WHERE abs(r.amount_cents - round(-t.amount*100)::int) <= 1)
      OR t.payee ILIKE '%bkx%' OR t.payee ILIKE '%extra bk%'
      OR (t.memo  IS NOT NULL AND (t.memo  ILIKE '%bkx%' OR t.memo  ILIKE '%extra bk%'))
      OR (t.notes IS NOT NULL AND (t.notes ILIKE '%bkx%' OR t.notes ILIKE '%extra bk%')) )
      THEN 'overlap_owner_review'
    ELSE 'valid_candidate'
  END AS uncleared_class,
  CASE
    WHEN t.id IS NULL OR t.amount IS NULL OR t.transaction_date IS NULL THEN 'owner_review_required'
    WHEN t.amount < 0 AND (
         EXISTS (SELECT 1 FROM cc_reserved r WHERE abs(r.amount_cents - round(-t.amount*100)::int) <= 1)
      OR t.payee ILIKE '%bkx%' OR t.payee ILIKE '%extra bk%'
      OR (t.memo  IS NOT NULL AND (t.memo  ILIKE '%bkx%' OR t.memo  ILIKE '%extra bk%'))
      OR (t.notes IS NOT NULL AND (t.notes ILIKE '%bkx%' OR t.notes ILIKE '%extra bk%')) )
      THEN 'owner_review_required'
    ELSE 'informational'   -- valid_candidate: E-eligible after live-bank reconciliation
  END AS authority_classification,
  'Uncleared Register item (cleared=false). valid_candidate = deterministic pending item E consumes after live-bank recon; overlap_owner_review = may duplicate an open reserved commitment/BKX (blocks handoff); malformed = incomplete identity (fail-closed).' AS note
FROM public.transactions t
WHERE t.account_key='truist_checking' AND t.cleared = false
ORDER BY t.transaction_date DESC, t.id;

------------------------------------------------------------------------------
-- D3_CHECKING_OBLIGATIONS_CASH_COMMITMENTS  (AMOUNT-BEARING; the core obligation set)
--   Full provenance; verbatim isReservedAsOf(c,w) (index.html:2438-2448); branch-correct
--   is_engine_reserved (Fable F1); BKX/commission-tax overlap flags (Fable F5).
--   authority_classification: malformed → owner_review; overlap candidate → owner_review
--   (EXCLUDED from D7); engine-reserved & well-formed & non-overlap → authoritative; else excluded.
------------------------------------------------------------------------------
WITH params AS (SELECT 2026 AS p_model_year, 8 AS p_as_of_model_week),  -- << SET AT CAPTURE
reconw AS (SELECT DISTINCT week_num FROM public.weekly_reconciliations),
cc AS (
  SELECT c.*, p.p_as_of_model_week AS w,
         EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = p.p_as_of_model_week) AS asof_recon,
         EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = c.origin_model_week)  AS origin_week_reconciled,
         ( c.amount_cents IN (70090,70091)
           OR c.payee ILIKE '%bkx%' OR c.payee ILIKE '%extra bk%'
           OR (c.notes IS NOT NULL AND (c.notes ILIKE '%bkx%' OR c.notes ILIKE '%extra bk%')) ) AS bkx_evidence,
         ( c.commitment_class='tax_transfer' AND EXISTS (
             SELECT 1 FROM public.weekly_tasks wt
             WHERE wt.action_key='commission_tax' AND wt.completed=true
               AND ( abs(wt.week_num - c.origin_model_week) <= 1
                     OR abs(wt.week_num - coalesce(c.reflected_model_week, c.origin_model_week)) <= 1
                     OR abs(round(wt.completed_amount*100)::int - c.amount_cents) <= 1 ) ) ) AS commtax_overlap
  FROM public.cash_commitments c CROSS JOIN params p
  WHERE c.model_year = p.p_model_year AND c.source_account='truist_checking'
)
SELECT 'D3_CHECKING_OBLIGATIONS_CASH_COMMITMENTS' AS result_set,
  'cash_commitments'          AS source_table,
  cc.id::text                 AS source_id,
  cc.expected_item_id         AS expected_item_id,
  cc.w                        AS as_of_model_week,
  cc.asof_recon               AS as_of_is_reconciled,
  cc.origin_model_week        AS model_week,
  cc.reflected_model_week,
  cc.resolved_model_week,
  cc.due_date                 AS relevant_date,
  cc.commitment_class         AS class_or_type,
  cc.required_or_discretionary,
  cc.affects_deployable_cash,
  cc.status,
  cc.resolution_type,
  cc.commitment_source,
  'obligation_debit'          AS direction,
  cc.amount_cents             AS amount_cents_modeled_reserve,
  ( cc.model_year = 2026 AND cc.origin_model_week <= cc.w AND cc.affects_deployable_cash = true
    AND cc.status <> 'voided'
    AND (cc.resolution_type IS NULL OR cc.resolution_type NOT IN ('voided','paid_from_other_account'))
    AND NOT (cc.reflected_model_week IS NOT NULL AND cc.reflected_model_week <= cc.w)
    AND (cc.resolved_model_week IS NULL OR cc.resolved_model_week > cc.w)
  )                           AS is_reserved_as_of,
  ( ( cc.model_year = 2026 AND cc.origin_model_week <= cc.w AND cc.affects_deployable_cash = true
      AND cc.status <> 'voided'
      AND (cc.resolution_type IS NULL OR cc.resolution_type NOT IN ('voided','paid_from_other_account'))
      AND NOT (cc.reflected_model_week IS NOT NULL AND cc.reflected_model_week <= cc.w)
      AND (cc.resolved_model_week IS NULL OR cc.resolved_model_week > cc.w) )
    AND ( cc.asof_recon
          OR ( cc.origin_model_week < cc.w
               AND ( cc.origin_week_reconciled OR cc.commitment_source = 'historical_repair' ) ) )
  )                           AS is_engine_reserved,
  cc.bkx_evidence             AS bkx_overlap_flag,
  cc.commtax_overlap          AS commission_tax_overlap_flag,
  CASE
    WHEN cc.expected_item_id IS NULL OR cc.origin_model_week IS NULL OR cc.status IS NULL
      OR cc.amount_cents IS NULL OR cc.amount_cents <= 0
      OR cc.commitment_class IS NULL OR cc.required_or_discretionary IS NULL OR cc.affects_deployable_cash IS NULL
      OR cc.status NOT IN ('planned','scheduled','initiated','bank_pending','cleared','voided','carried_unresolved','stale_review')
      OR cc.commitment_source NOT IN ('wd_reconciliation','manual_reconciliation','historical_repair')
      THEN 'owner_review_required'
    WHEN cc.bkx_evidence OR cc.commtax_overlap
      THEN 'owner_review_required'   -- ambiguous overlap (Fable F5); excluded from D7 until resolved
    WHEN ( ( cc.model_year = 2026 AND cc.origin_model_week <= cc.w AND cc.affects_deployable_cash = true
             AND cc.status <> 'voided'
             AND (cc.resolution_type IS NULL OR cc.resolution_type NOT IN ('voided','paid_from_other_account'))
             AND NOT (cc.reflected_model_week IS NOT NULL AND cc.reflected_model_week <= cc.w)
             AND (cc.resolved_model_week IS NULL OR cc.resolved_model_week > cc.w) )
           AND ( cc.asof_recon
                 OR ( cc.origin_model_week < cc.w AND ( cc.origin_week_reconciled OR cc.commitment_source = 'historical_repair' ) ) ) )
      THEN 'authoritative'
    ELSE 'excluded'
  END AS authority_classification
FROM cc
ORDER BY cc.origin_model_week NULLS FIRST, cc.id;

------------------------------------------------------------------------------
-- D4_CUSTOM_AND_OFFPOOL_ITEMS  (owner-review + informational; label/completed_amount exposed)
--   custom_tasks (no amount column; NOT read by the engine, index.html:3899). BKX $700.90
--   is one Week-29 custom_tasks transfer, amount in LABEL text (decision-log.md:45) →
--   owner_review_required. custom_tasks has ONLY {id,week_num,label,completed}, so BKX
--   detection uses label text (bkx / extra bk / 700.9). weekly_tasks commission-tax legs
--   (also matched on completed_label for BKX text) → informational tax_reserve_out.
------------------------------------------------------------------------------
SELECT 'D4_CUSTOM_AND_OFFPOOL_ITEMS' AS result_set,
  'custom_tasks'      AS source_table,
  ct.id::text         AS source_id,
  ct.week_num         AS model_week,
  NULL::date          AS relevant_date,
  CASE WHEN ct.label ILIKE '%bkx%' OR ct.label ILIKE '%extra bk%' OR ct.label LIKE '%700.9%' THEN 'bkx_offpool_tax_transfer' ELSE 'custom_task' END AS class_or_type,
  'informational_na'  AS direction,
  CASE WHEN ct.completed THEN 'completed' ELSE 'open' END AS status,
  'owner_review_required' AS authority_classification,
  ct.label            AS label_amount_in_text,
  'custom_tasks has no amount column and is NOT read by the capacity engine (index.html:3899); amount (e.g. BKX $700.90) is in label text — owner must resolve before any capacity use.' AS note
FROM public.custom_tasks ct
UNION ALL
SELECT 'D4_CUSTOM_AND_OFFPOOL_ITEMS',
  'weekly_tasks',
  (wt.week_num::text || '_' || wt.task_idx::text) AS source_id,
  wt.week_num,
  NULL::date,
  CASE WHEN (wt.completed_label IS NOT NULL AND (wt.completed_label ILIKE '%bkx%' OR wt.completed_label ILIKE '%extra bk%')) THEN 'bkx_text_in_commission_tax_leg' ELSE 'commission_tax_leg' END,
  'tax_reserve_out',
  CASE WHEN wt.completed THEN 'completed_executed' ELSE 'open' END,
  'informational',
  ('completed_amount=' || coalesce(wt.completed_amount::text,'(null)') || '; completed_label=' || coalesce(wt.completed_label,'(null)')) AS label_amount_in_text,
  'weekly_tasks commission-tax leg (action_key=commission_tax); executed legs are the durable tax authority (index.html:4023), already moved to the Vio tax reserve. weekly_tasks has NO model_year. BKX text here would be an overlap (see D6).' AS note
FROM public.weekly_tasks wt
WHERE wt.action_key='commission_tax'
ORDER BY source_table, model_week NULLS FIRST, source_id;

------------------------------------------------------------------------------
-- D5_EXCLUSION_STATE  (NON-amount; items no longer available to count, with reason)
------------------------------------------------------------------------------
WITH params AS (SELECT 2026 AS p_model_year, 8 AS p_as_of_model_week),  -- << SET AT CAPTURE
reconw AS (SELECT DISTINCT week_num FROM public.weekly_reconciliations),
cc AS (
  SELECT c.*, p.p_as_of_model_week AS w,
         EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = p.p_as_of_model_week) AS asof_recon,
         EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = c.origin_model_week)  AS origin_week_reconciled
  FROM public.cash_commitments c CROSS JOIN params p
  WHERE c.model_year=2026 AND c.source_account='truist_checking'
)
SELECT 'D5_EXCLUSION_STATE' AS result_set,
  cc.w AS as_of_model_week,
  'cash_commitments' AS source_table, cc.id::text AS source_id, cc.origin_model_week AS model_week, cc.status,
  CASE
    WHEN cc.status='voided' OR cc.resolution_type IN ('voided','paid_from_other_account') THEN 'voided_or_paid_elsewhere'
    WHEN cc.reflected_model_week IS NOT NULL AND cc.reflected_model_week <= cc.w THEN 'reflected_into_balance'
    WHEN cc.resolved_model_week IS NOT NULL AND cc.resolved_model_week <= cc.w THEN 'resolved_at_or_before_asof'
    WHEN cc.origin_model_week > cc.w THEN 'not_yet_originated_future'
    WHEN cc.affects_deployable_cash = false THEN 'does_not_affect_deployable_cash'
    WHEN NOT cc.asof_recon AND cc.origin_model_week = cc.w THEN 'projected_branch_origin_equals_asof_excluded'
    WHEN NOT cc.asof_recon AND NOT cc.origin_week_reconciled AND cc.commitment_source <> 'historical_repair' THEN 'projected_branch_unreconciled_origin_excluded'
    ELSE 'still_reserved_do_not_exclude'
  END AS exclusion_reason
FROM cc
WHERE NOT ( ( cc.model_year=2026 AND cc.origin_model_week <= cc.w AND cc.affects_deployable_cash=true
              AND cc.status<>'voided'
              AND (cc.resolution_type IS NULL OR cc.resolution_type NOT IN ('voided','paid_from_other_account'))
              AND NOT (cc.reflected_model_week IS NOT NULL AND cc.reflected_model_week <= cc.w)
              AND (cc.resolved_model_week IS NULL OR cc.resolved_model_week > cc.w) )
            AND ( cc.asof_recon OR ( cc.origin_model_week < cc.w AND ( cc.origin_week_reconciled OR cc.commitment_source='historical_repair' ) ) ) )
UNION ALL
SELECT 'D5_EXCLUSION_STATE', (SELECT p_as_of_model_week FROM params),
  'weekly_tasks', (wt.week_num::text||'_'||wt.task_idx::text), wt.week_num,
  CASE WHEN wt.completed THEN 'completed' ELSE 'open' END,
  'commission_tax_executed_leg_moved_to_tax_reserve'
FROM public.weekly_tasks wt WHERE wt.action_key='commission_tax' AND wt.completed=true
UNION ALL
SELECT 'D5_EXCLUSION_STATE', (SELECT p_as_of_model_week FROM params),
  'goal_funding_snapshots', (gfs.week_num::text||'_'||gfs.goal_id), gfs.week_num,
  gfs.source, 'goal_funding_snapshot_context_not_a_checking_obligation'
FROM public.goal_funding_snapshots gfs WHERE gfs.model_year=2026
ORDER BY source_table, model_week NULLS FIRST, source_id;

------------------------------------------------------------------------------
-- D6_DUPLICATE_OVERLAP_DIAGNOSTICS  (AMOUNT-BEARING only to match; candidates, NOT confirmed)
--   BROADENED per Fable F5. Classes:
--     DUP_EXPECTED_ITEM_ID          — >1 cash_commitments per expected_item_id (UNIQUE ⇒ expect 0).
--     CC_VS_COMMISSION_TAX_NEAR      — a tax_transfer commitment within ±1 model week (origin OR
--                                      reflected) of a completed commission_tax leg, OR within ±1¢
--                                      of amount (catches exact, carry-forward, partial-same-week,
--                                      rounding). LIMITATION: a partial whose amount AND week both
--                                      diverge beyond ±1 is NOT caught here (owner adjudication).
--     BKX_EVIDENCE_OUTSIDE_CUSTOM_TASKS — BKX by amount (70090/70091, ±1¢) or by text in
--                                      cash_commitments (payee/notes) or weekly_tasks (completed_label).
--   All candidates are owner_review_required; the matching rows are EXCLUDED from D7 (see D3).
--   F7 deferred: class-1 grouping keeps amount/week keys — immaterial because expected_item_id is
--   UNIQUE (phase-5f-1-migration.sql:50); D9's eid-only grouping is the authoritative duplicate gate.
------------------------------------------------------------------------------
SELECT 'D6_DUPLICATE_OVERLAP_DIAGNOSTICS' AS result_set, 'DUP_EXPECTED_ITEM_ID' AS overlap_class,
  cc.expected_item_id AS key_a, NULL::text AS key_b, cc.amount_cents AS amount_cents, cc.origin_model_week AS model_week,
  count(*) AS candidate_count, 'owner_review_required' AS disposition
FROM public.cash_commitments cc WHERE cc.model_year=2026
GROUP BY cc.expected_item_id, cc.amount_cents, cc.origin_model_week HAVING count(*) > 1
UNION ALL
SELECT 'D6_DUPLICATE_OVERLAP_DIAGNOSTICS','CC_VS_COMMISSION_TAX_NEAR',
  cc.id::text, (wt.week_num::text||'_'||wt.task_idx::text), cc.amount_cents, cc.origin_model_week, 2, 'owner_review_required'
FROM public.cash_commitments cc
JOIN public.weekly_tasks wt
  ON wt.action_key='commission_tax' AND wt.completed=true
 AND ( abs(wt.week_num - cc.origin_model_week) <= 1
       OR abs(wt.week_num - coalesce(cc.reflected_model_week, cc.origin_model_week)) <= 1
       OR abs(round(wt.completed_amount*100)::int - cc.amount_cents) <= 1 )
WHERE cc.model_year=2026 AND cc.source_account='truist_checking' AND cc.commitment_class='tax_transfer'
UNION ALL
SELECT 'D6_DUPLICATE_OVERLAP_DIAGNOSTICS','BKX_EVIDENCE_OUTSIDE_CUSTOM_TASKS',
  cc.id::text, 'cash_commitments', cc.amount_cents, cc.origin_model_week, 1, 'owner_review_required'
FROM public.cash_commitments cc
WHERE cc.model_year=2026
  AND ( cc.amount_cents IN (70090,70091)
        OR cc.payee ILIKE '%bkx%' OR cc.payee ILIKE '%extra bk%'
        OR (cc.notes IS NOT NULL AND (cc.notes ILIKE '%bkx%' OR cc.notes ILIKE '%extra bk%')) )
UNION ALL
SELECT 'D6_DUPLICATE_OVERLAP_DIAGNOSTICS','BKX_EVIDENCE_OUTSIDE_CUSTOM_TASKS',
  (wt.week_num::text||'_'||wt.task_idx::text), 'weekly_tasks',
  CASE WHEN wt.completed_amount IS NULL THEN NULL ELSE round(wt.completed_amount*100)::int END, wt.week_num, 1, 'owner_review_required'
FROM public.weekly_tasks wt
WHERE ( wt.completed_amount IS NOT NULL AND round(wt.completed_amount*100)::int IN (70090,70091) )
   OR ( wt.completed_label IS NOT NULL AND (wt.completed_label ILIKE '%bkx%' OR wt.completed_label ILIKE '%extra bk%') )
ORDER BY overlap_class, model_week NULLS FIRST, key_a;

------------------------------------------------------------------------------
-- D7_AUTHORITATIVE_CANDIDATE_SET  (AMOUNT-BEARING; the precise E handoff)
--   ENGINE-reserved (branch-correct, F1) AND well-formed AND NOT an overlap candidate
--   (BKX/commission-tax, F5). Aggregated by class. DB-side reserved-obligation total ONLY.
------------------------------------------------------------------------------
WITH params AS (SELECT 2026 AS p_model_year, 8 AS p_as_of_model_week),  -- << SET AT CAPTURE
reconw AS (SELECT DISTINCT week_num FROM public.weekly_reconciliations),
auth AS (
  SELECT c.commitment_class, c.required_or_discretionary, c.amount_cents
  FROM public.cash_commitments c CROSS JOIN params p
  WHERE c.model_year=2026 AND c.source_account='truist_checking'
    AND c.origin_model_week <= p.p_as_of_model_week AND c.affects_deployable_cash=true AND c.status<>'voided'
    AND (c.resolution_type IS NULL OR c.resolution_type NOT IN ('voided','paid_from_other_account'))
    AND NOT (c.reflected_model_week IS NOT NULL AND c.reflected_model_week <= p.p_as_of_model_week)
    AND (c.resolved_model_week IS NULL OR c.resolved_model_week > p.p_as_of_model_week)
    -- ENGINE branch-correct (F1)
    AND ( EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = p.p_as_of_model_week)
          OR ( c.origin_model_week < p.p_as_of_model_week
               AND ( EXISTS (SELECT 1 FROM reconw r2 WHERE r2.week_num = c.origin_model_week) OR c.commitment_source='historical_repair' ) ) )
    -- well-formed guard (fail-closed)
    AND c.expected_item_id IS NOT NULL AND c.origin_model_week IS NOT NULL AND c.status IS NOT NULL
    AND c.amount_cents IS NOT NULL AND c.amount_cents > 0
    AND c.commitment_class IS NOT NULL AND c.required_or_discretionary IS NOT NULL
    -- NOT an ambiguous overlap candidate (F5): BKX evidence OR commission-tax near-match
    AND NOT ( c.amount_cents IN (70090,70091)
              OR c.payee ILIKE '%bkx%' OR c.payee ILIKE '%extra bk%'
              OR (c.notes IS NOT NULL AND (c.notes ILIKE '%bkx%' OR c.notes ILIKE '%extra bk%')) )
    AND NOT ( c.commitment_class='tax_transfer' AND EXISTS (
                SELECT 1 FROM public.weekly_tasks wt
                WHERE wt.action_key='commission_tax' AND wt.completed=true
                  AND ( abs(wt.week_num - c.origin_model_week) <= 1
                        OR abs(wt.week_num - coalesce(c.reflected_model_week, c.origin_model_week)) <= 1
                        OR abs(round(wt.completed_amount*100)::int - c.amount_cents) <= 1 ) ) )
)
SELECT 'D7_AUTHORITATIVE_CANDIDATE_SET' AS result_set,
  (SELECT p_as_of_model_week FROM params) AS as_of_model_week,
  'obligation_debit'                       AS direction,
  commitment_class,
  required_or_discretionary,
  count(*)                                 AS obligation_count,
  coalesce(sum(amount_cents),0)            AS reserved_amount_cents_authoritative,
  'authoritative'                          AS authority_classification,
  'DB ENGINE-reserved obligation total (branch-correct; BKX/commission-tax overlap candidates EXCLUDED, Fable F5) as of the D1 as-of model week. EXCLUDES the code-side WD base schedule and all informational/owner-review items. Not a capacity number.' AS note
FROM auth
GROUP BY commitment_class, required_or_discretionary
ORDER BY required_or_discretionary, commitment_class;

------------------------------------------------------------------------------
-- D8_UNRESOLVED_REVIEW_ITEMS  (NON-amount; must stay OUTSIDE the capacity calc until resolved)
------------------------------------------------------------------------------
WITH items(seq, item, classification, basis) AS (
  VALUES
    (10,'Code-side WD base schedule (paychecks, rent, all card payments, Kia, wk15 Alaska draw) is JS-hardcoded and NOT in the DB','limitation','index.html:909-941, 3056-3068'),
    (20,'Forward modeled inflows (paychecks/commissions) are code-side; DB has no forward inflow representation','limitation','index.html:909-941'),
    (30,'BKX Wendy Extra-BK $700.90 obligation amount is in custom_tasks.label text (no amount column); one Week-29 custom_tasks transfer','owner_review_required','decision-log.md:45; index.html:1503/9909'),
    (35,'Ambiguous BKX/commission-tax overlaps across custom_tasks/weekly_tasks/cash_commitments are owner_review_required and EXCLUDED from the D7 authoritative total until resolved; D9 fails while any engine-reserved overlap candidate exists','owner_review_required','Fable F5; step8-D D3/D6/D7/D9'),
    (40,'custom_tasks are NOT read by the capacity engine (pre-AU-11); custom transfers do not reserve modeled capacity','limitation','index.html:3899'),
    (50,'weekly_tasks carries NO model_year; commission-tax year attribution not provable in-table','limitation','index.html:4015'),
    (60,'Commission-tax pool OBLIGATION total is a client-side model input (ct column); only executed legs are in the DB (weekly_tasks)','informational','index.html:4020-4029'),
    (70,'Alaska reimbursement is a scheduled goal_disbursement (savings->checking), NOT yet recorded (reserved category, 0 rows)','owner_review_required','pkg-tax-1 sql:306-308; alaska interim decision 2026-07-23'),
    (75,'Uncleared Register items are classified in D2B (valid_candidate/overlap_owner_review/malformed); overlap/malformed block the D9 handoff; E consumes only the valid_candidate set after live-bank reconciliation','owner_review_required','Fable F2; step8-D D2B/D9'),
    (80,'Jabian (reminder-only, index.html:7346-7350) and FSA (health_fitness.flexible_spending_2026, budget_treatment=excluded, net-zero, phase-5d-1-migration.sql:401,412) reimbursements are excluded from model capacity','informational','index.html:7346-7350; phase-5d-1-migration.sql:401,412'),
    (90,'Baseline B: one uncleared +$15 Bailey inflow (owner-reviewed, legitimate pending inflow; surfaced live by D2B)','owner_review_required','execution record — Baseline B exceptions'),
    (100,'Baseline B: one PAYMENT_LIKE_BUT_POSITIVE sign candidate (owner-resolved as expected)','informational','execution record — Baseline B exceptions'),
    (110,'Baseline C: future weeks 8-31 showed 0 checking transactions (expected; open/unreconciled)','informational','execution record — Baseline C C3'),
    (120,'Production is pre-AU-11 reservation architecture; discretionary goal-transfer reservations are NOT represented as commitments','limitation','step8-A A3.*; AU-11 staging-only'),
    (130,'When the as-of week is unreconciled, the engine uses the projected branch (index.html:3166-3171); D7 applies it — E must NOT re-add WD-overlapping rows','limitation','Fable F1; index.html:3156-3176')
)
SELECT 'D8_UNRESOLVED_REVIEW_ITEMS' AS result_set, seq, item, classification, basis
FROM items
ORDER BY seq;

------------------------------------------------------------------------------
-- D9_HANDOFF_GATE  (machine-readable; may Baseline E proceed?)  NON-amount, fail-closed
--   FAILS while ANY of: malformed authoritative candidate; duplicate expected_item_id;
--   BKX evidence outside custom_tasks; engine-reserved BKX/commission-tax overlap candidate
--   (Fable F5, would double-count); malformed uncleared Register item; uncleared overlap
--   candidate (Fable F2). uncleared valid_candidate count is informational (E handoff).
------------------------------------------------------------------------------
WITH params AS (SELECT 2026 AS p_model_year, 8 AS p_as_of_model_week),  -- << SET AT CAPTURE
reconw AS (SELECT DISTINCT week_num FROM public.weekly_reconciliations),
cc_reserved AS (
  SELECT c.amount_cents FROM public.cash_commitments c
  WHERE c.model_year=2026 AND c.source_account='truist_checking' AND c.affects_deployable_cash=true
    AND c.status <> 'voided'
    AND (c.resolution_type IS NULL OR c.resolution_type NOT IN ('voided','paid_from_other_account'))
    AND c.reflected_model_week IS NULL AND c.resolved_model_week IS NULL
),
malformed AS (
  SELECT count(*) AS n FROM public.cash_commitments c
  WHERE c.model_year=2026 AND c.source_account='truist_checking'
    AND ( c.expected_item_id IS NULL OR c.origin_model_week IS NULL OR c.status IS NULL
       OR c.amount_cents IS NULL OR c.amount_cents <= 0
       OR c.commitment_class IS NULL OR c.required_or_discretionary IS NULL OR c.affects_deployable_cash IS NULL
       OR c.status NOT IN ('planned','scheduled','initiated','bank_pending','cleared','voided','carried_unresolved','stale_review')
       OR c.commitment_source NOT IN ('wd_reconciliation','manual_reconciliation','historical_repair') )
),
dup_eid AS (
  SELECT count(*) AS n FROM (
    SELECT expected_item_id FROM public.cash_commitments WHERE model_year=2026
    GROUP BY expected_item_id HAVING count(*) > 1
  ) q
),
bkx_outside AS (
  SELECT (SELECT count(*) FROM public.cash_commitments c
            WHERE c.model_year=2026
              AND ( c.amount_cents IN (70090,70091)
                    OR c.payee ILIKE '%bkx%' OR c.payee ILIKE '%extra bk%'
                    OR (c.notes IS NOT NULL AND (c.notes ILIKE '%bkx%' OR c.notes ILIKE '%extra bk%')) ))
       + (SELECT count(*) FROM public.weekly_tasks wt
            WHERE ( wt.completed_amount IS NOT NULL AND round(wt.completed_amount*100)::int IN (70090,70091) )
               OR ( wt.completed_label IS NOT NULL AND (wt.completed_label ILIKE '%bkx%' OR wt.completed_label ILIKE '%extra bk%') )) AS n
),
overlap_cc AS (   -- engine-reserved, well-formed rows that are ALSO overlap candidates (double-count risk)
  SELECT count(*) AS n FROM public.cash_commitments c CROSS JOIN params p
  WHERE c.model_year=2026 AND c.source_account='truist_checking'
    AND c.origin_model_week <= p.p_as_of_model_week AND c.affects_deployable_cash=true AND c.status<>'voided'
    AND (c.resolution_type IS NULL OR c.resolution_type NOT IN ('voided','paid_from_other_account'))
    AND NOT (c.reflected_model_week IS NOT NULL AND c.reflected_model_week <= p.p_as_of_model_week)
    AND (c.resolved_model_week IS NULL OR c.resolved_model_week > p.p_as_of_model_week)
    AND ( EXISTS (SELECT 1 FROM reconw r WHERE r.week_num = p.p_as_of_model_week)
          OR ( c.origin_model_week < p.p_as_of_model_week
               AND ( EXISTS (SELECT 1 FROM reconw r2 WHERE r2.week_num = c.origin_model_week) OR c.commitment_source='historical_repair' ) ) )
    AND c.expected_item_id IS NOT NULL AND c.amount_cents IS NOT NULL AND c.amount_cents > 0
    AND ( c.amount_cents IN (70090,70091)
          OR c.payee ILIKE '%bkx%' OR c.payee ILIKE '%extra bk%'
          OR (c.notes IS NOT NULL AND (c.notes ILIKE '%bkx%' OR c.notes ILIKE '%extra bk%'))
          OR ( c.commitment_class='tax_transfer' AND EXISTS (
                 SELECT 1 FROM public.weekly_tasks wt
                 WHERE wt.action_key='commission_tax' AND wt.completed=true
                   AND ( abs(wt.week_num - c.origin_model_week) <= 1
                         OR abs(wt.week_num - coalesce(c.reflected_model_week, c.origin_model_week)) <= 1
                         OR abs(round(wt.completed_amount*100)::int - c.amount_cents) <= 1 ) ) ) )
),
unc AS (SELECT id, amount, transaction_date, payee, memo, notes FROM public.transactions WHERE account_key='truist_checking' AND cleared=false),
unc_malformed AS (SELECT count(*) AS n FROM unc WHERE id IS NULL OR amount IS NULL OR transaction_date IS NULL),
unc_overlap AS (
  SELECT count(*) AS n FROM unc u
  WHERE u.amount < 0 AND (
        EXISTS (SELECT 1 FROM cc_reserved r WHERE abs(r.amount_cents - round(-u.amount*100)::int) <= 1)
     OR u.payee ILIKE '%bkx%' OR u.payee ILIKE '%extra bk%'
     OR (u.memo  IS NOT NULL AND (u.memo  ILIKE '%bkx%' OR u.memo  ILIKE '%extra bk%'))
     OR (u.notes IS NOT NULL AND (u.notes ILIKE '%bkx%' OR u.notes ILIKE '%extra bk%')) )
),
unc_valid AS (
  SELECT count(*) AS n FROM unc u
  WHERE NOT (u.id IS NULL OR u.amount IS NULL OR u.transaction_date IS NULL)
    AND NOT ( u.amount < 0 AND (
              EXISTS (SELECT 1 FROM cc_reserved r WHERE abs(r.amount_cents - round(-u.amount*100)::int) <= 1)
           OR u.payee ILIKE '%bkx%' OR u.payee ILIKE '%extra bk%'
           OR (u.memo  IS NOT NULL AND (u.memo  ILIKE '%bkx%' OR u.memo  ILIKE '%extra bk%'))
           OR (u.notes IS NOT NULL AND (u.notes ILIKE '%bkx%' OR u.notes ILIKE '%extra bk%')) ) )
),
au11_present AS (
  SELECT (CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name IN ('reservation_batch_id','goal_id','cleared_transaction_id')) THEN 1 ELSE 0 END
       +  CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables  WHERE table_schema='public' AND table_name='discretionary_reservation_batches') THEN 1 ELSE 0 END) AS n
)
SELECT 'D9_HANDOFF_GATE' AS result_set,
  (SELECT p_as_of_model_week FROM params) AS as_of_model_week,
  (EXISTS (SELECT 1 FROM public.weekly_reconciliations WHERE week_num=(SELECT p_as_of_model_week FROM params))) AS as_of_is_reconciled,
  (SELECT n FROM malformed)    AS malformed_authoritative_candidates,
  (SELECT n FROM dup_eid)      AS duplicate_expected_item_ids,
  (SELECT n FROM bkx_outside)  AS bkx_evidence_outside_custom_tasks,
  (SELECT n FROM overlap_cc)   AS engine_reserved_overlap_candidates,
  (SELECT n FROM unc_malformed) AS uncleared_malformed_count,
  (SELECT n FROM unc_overlap)  AS uncleared_overlap_candidates,
  (SELECT n FROM unc_valid)    AS uncleared_valid_candidates,          -- informational; E consumes this deterministic set (D2B)
  (SELECT n FROM au11_present) AS au11_objects_present,
  CASE WHEN (SELECT n FROM malformed)=0 AND (SELECT n FROM dup_eid)=0
        AND (SELECT n FROM bkx_outside)=0 AND (SELECT n FROM overlap_cc)=0
        AND (SELECT n FROM unc_malformed)=0 AND (SELECT n FROM unc_overlap)=0
        AND (SELECT n FROM au11_present)=0
       THEN 'D_HANDOFF_PASS' ELSE 'D_HANDOFF_FAIL_STOP' END AS handoff_gate,
  'BASELINE E CONTRACT — E consumes: (1) the D7 authoritative ENGINE-reserved obligation total (branch-correct for the as-of week; BKX/commission-tax overlap candidates already EXCLUDED) by class; (2) the D2 DB-visible inflow disbursements; (3) the D2B uncleared_class=valid_candidate SET (deterministic per-item id/amount/date/direction), consumed only after a live-bank reconciliation. E MUST additionally obtain OUT-OF-BAND: the code-side WD base schedule (paychecks, rent, all card payments, Kia, wk15 Alaska draw); the current actual checking balance (Baseline B); the operating floor OP_FL=6500; and owner-resolution of every D8/D3/D2B owner_review_required item. Baseline E MUST NOT proceed unless handoff_gate=D_HANDOFF_PASS (unresolved BKX/commission-tax overlap or malformed/overlapping uncleared items fail closed), and MUST NOT re-add any obligation already counted in D7. No D result is a checking-capacity number or a transfer authorization; operational result remains HOLD.' AS baseline_e_handoff_contract;
