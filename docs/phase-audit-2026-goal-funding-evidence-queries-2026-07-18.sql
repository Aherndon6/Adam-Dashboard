-- ═══════════════════════════════════════════════════════════════════════════
-- 2026 Goal-Funding & Waterfall Integrity Audit — READ-ONLY EVIDENCE (v5)
-- query_version = 2026-07-18-v5. AUTHORED, NOT EXECUTED. Run ONCE, read-only,
-- v5 fix: replaced `= ANY((SELECT array_col FROM cte))` (v4 failed 42883 text=text[])
--   with type-safe `IN (SELECT unnest(array_col) FROM cte)` at snap_latest + reg.
-- v4 fix: model_week_overrides has NO physical `deleted` column (v3 failed 42703).
--   VERIFIED physical override columns (from the write payload index.html:3641):
--     week_num, events_json, ct, ca, is_custom, updated_at, dates  → referenced directly.
--     `deleted` / `created_at` are NOT written → accessed schema-tolerantly via to_jsonb(m)->>'…' (null-safe).
-- in the Supabase SQL Editor against production Adam-Dashboard
-- (usayoldrawwmjsmretin). Returns EXACTLY ONE ROW / ONE COLUMN (audit_evidence
-- jsonb) — copy it verbatim into the local evidence artifact.
--
--   SAFETY .... wholly inside BEGIN READ ONLY … COMMIT. Only SELECT + CTEs +
--               built-in functions (jsonb_*, md5, current_setting, now).
--               No RPC, DML, DDL, GRANT, dynamic SQL, temp tables, or DO blocks.
--   SCOPE ..... audit horizon = MODEL weeks 6–31 (Cal Wk 28–53); tax detail
--               weeks 6–12; Investigation A pulls weeks 1–2 only; snapshots =
--               latest per audited goal. NO `SELECT *` of a whole table; every
--               table is week/goal/status-scoped.
--   PRIVACY ... weekly_reconciliations exposes ONLY `tax` (renamed
--               reconciled_tax_value; it is an ACCOUNT/RESERVE state value, NOT
--               a transfer) + basis; chk/sav/amx/lc appear ONLY inside an md5
--               fingerprint. Snapshot/override/commitment amounts + goal funded
--               values are the audit's essential math inputs.
--   MAPPING ... Cal Wk = model week + 22.
-- ─────────────────────────────────────────────────────────────────────────
BEGIN READ ONLY;
SET LOCAL search_path TO public;

WITH
-- ── audited goal sets (exact stored IDs from goal_registry / the eligible-9 array) ──
ag AS (SELECT ARRAY['alaska','wewe_rccl','wewe_dcl','adam_ira','wendy_sep','wendy_ira',
                    'bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise','taxable_etf']::text[] AS all12),
sg AS (SELECT ARRAY['alaska','wewe_rccl','wewe_dcl','adam_ira','wendy_sep','wendy_ira',
                    'bailey_529','bryce_529','preston_529','bryce_vehicle','christmas_cruise']::text[] AS snap11),
amts_num AS (SELECT ARRAY[843.51,478.19,365.32,417.83,700.90,52.51,1118.73,425.68]::numeric[] AS a),
amts_cents AS (SELECT ARRAY[84351,47819,36532,41783,70090,5251,111873,42568]::int[] AS c),

-- ══ A1: Weeks 1 & 2 (= Cal 23/24) durable task state (narrow fields; uncertain cols via to_jsonb ->>) ══
a1 AS (
  SELECT wt.week_num, wt.task_idx, wt.action_key, wt.completed, wt.completed_amount,
         wt.completed_label, wt.completed_at,
         to_jsonb(wt)->>'created_at' AS created_at,
         to_jsonb(wt)->>'updated_at' AS updated_at,
         to_jsonb(wt)->>'id'         AS row_id,
         CASE
           WHEN wt.completed IS NOT TRUE                                                        THEN 'PRESENT_INCOMPLETE_possible_mutation'
           WHEN wt.action_key IS NULL AND (wt.completed_label IS NULL OR wt.completed_label='') THEN 'PRESENT_COMPLETED_UNRESOLVABLE_null_key_and_label'
           WHEN wt.action_key IS NULL                                                          THEN 'PRESENT_COMPLETED_LABEL_ONLY_null_key'
           ELSE 'PRESENT_COMPLETED_IDENTIFIED'
         END AS resolution_class
  FROM public.weekly_tasks wt WHERE wt.week_num IN (1,2)
),
a1_custom AS (SELECT id, week_num, label, completed FROM public.custom_tasks WHERE week_num IN (1,2)),

-- ══ A2/A3: unified tax evidence (weeks 6–12) — persisted rows only, typed ══
tax_recon AS (
  SELECT week_num AS model_week, 'weekly_reconciliations'::text AS durable_source_table,
         'account_reserve_state'::text AS durable_source_type, ('week='||week_num)::text AS record_identifier,
         'reconciliation_tax_account_balance'::text AS tax_semantic_class,
         tax AS amount, balance_basis AS status,
         jsonb_build_object('field','tax(reconciled_tax_value)','note','reserve/account state value, NOT a transfer') AS identity,
         NULL::text AS created_at, recorded_at::text AS updated_at, true AS persisted
  FROM public.weekly_reconciliations WHERE week_num BETWEEN 6 AND 12
),
tax_tasks AS (
  SELECT week_num AS model_week, 'weekly_tasks'::text, 'task'::text, ('wk'||week_num||'#'||task_idx)::text,
         (CASE WHEN completed THEN 'executed_tax_transfer' ELSE 'projected_tax_transfer' END)::text,
         completed_amount, (CASE WHEN completed THEN 'completed' ELSE 'planned' END)::text,
         jsonb_build_object('action_key',action_key,'completed_label',completed_label,'task_idx',task_idx),
         to_jsonb(t)->>'created_at', to_jsonb(t)->>'updated_at', true
  FROM public.weekly_tasks t WHERE week_num BETWEEN 6 AND 12
    AND (action_key IN ('commission_tax','tax_base') OR completed_label ILIKE '%tax%' OR completed_label ILIKE '%vio%')
),
tax_cc AS (
  SELECT origin_model_week, 'cash_commitments'::text, 'commitment'::text, expected_item_id,
         'cash_commitment'::text, (amount_cents/100.0)::numeric, status,
         jsonb_build_object('payee',payee,'commitment_class',commitment_class,'commitment_source',commitment_source,
                            'reflected_model_week',reflected_model_week,'resolved_model_week',resolved_model_week),
         to_jsonb(c)->>'created_at', to_jsonb(c)->>'resolved_at', true
  FROM public.cash_commitments c WHERE origin_model_week BETWEEN 6 AND 12
    AND (commitment_class ILIKE '%tax%' OR payee ILIKE '%tax%' OR payee ILIKE '%vio%' OR expected_item_id ILIKE '%tax%')
),
tax_ov AS (
  SELECT week_num, 'model_week_overrides'::text, 'model_input'::text, ('override_wk'||week_num)::text,
         'total_tax_obligation_input'::text, ct::numeric,
         (CASE WHEN lower(coalesce(to_jsonb(m)->>'deleted','false')) IN ('true','t','1') THEN 'deleted' ELSE 'active' END)::text,
         jsonb_build_object('ca',m.ca,'is_custom',m.is_custom,'deleted',to_jsonb(m)->>'deleted'),
         to_jsonb(m)->>'created_at', m.updated_at::text, true
  FROM public.model_week_overrides m WHERE week_num BETWEEN 6 AND 12 AND ct IS NOT NULL AND ct <> 0
),
tax_all AS (
  SELECT * FROM tax_recon UNION ALL SELECT * FROM tax_tasks UNION ALL SELECT * FROM tax_cc UNION ALL SELECT * FROM tax_ov
),
-- durability of each audit amount: found in a persisted field, or application-derived only
amount_probe AS (
  SELECT x.amt,
         EXISTS (SELECT 1 FROM public.weekly_tasks WHERE week_num BETWEEN 6 AND 12 AND round(completed_amount,2)=x.amt) AS in_tasks,
         EXISTS (SELECT 1 FROM public.cash_commitments WHERE origin_model_week BETWEEN 6 AND 12 AND amount_cents=round(x.amt*100)::int) AS in_commitments,
         EXISTS (SELECT 1 FROM public.model_week_overrides WHERE week_num BETWEEN 6 AND 12 AND round(ct::numeric,2)=x.amt) AS in_overrides
  FROM (SELECT unnest(a) AS amt FROM amts_num) x
),

-- ══ A4: deterministic S0–S3 inputs (scoped) ══
snap_latest AS (   -- latest snapshot per audited goal that has snapshots
  SELECT DISTINCT ON (goal_id) goal_id, model_year, week_num, funded_amount, source AS snap_source, updated_at
  FROM public.goal_funding_snapshots
  WHERE model_year=2026 AND goal_id IN (SELECT unnest(snap11) FROM sg)
  ORDER BY goal_id, week_num DESC
),
adamira AS (       -- full adam_ira chain (documents the S0→S1 correction state)
  SELECT week_num, funded_amount, source, updated_at
  FROM public.goal_funding_snapshots WHERE model_year=2026 AND goal_id='adam_ira' ORDER BY week_num
),
comp_tasks AS (    -- completed AUDITED goal-transfer + commission-tax keys only (verified convention: 'goal_'||id)
  SELECT week_num, task_idx, action_key, completed_amount, completed_label
  FROM public.weekly_tasks
  WHERE completed=true AND week_num BETWEEN 6 AND 31
    AND ( action_key IN (SELECT 'goal_'||g FROM (SELECT unnest(all12) AS g FROM ag) s)   -- goal_<audited id>
          OR action_key IN ('goal_adam_ira_seed','commission_tax','tax_base') )          -- IRA seed + tax keys
),
active_cc AS (     -- commitments still reserving deployable cash from wk6 forward
  SELECT origin_model_week, expected_item_id, payee, commitment_class, required_or_discretionary,
         amount_cents, status, affects_deployable_cash, reflected_model_week, resolved_model_week, source_account, due_date
  FROM public.cash_commitments
  WHERE affects_deployable_cash=true AND origin_model_week<=31 AND (resolved_model_week IS NULL OR resolved_model_week>=6)
),
mwo AS (           -- data-driven forward schedule; verified physical cols direct, `deleted` schema-tolerant
  SELECT week_num, dates, ct, ca, events_json, is_custom, to_jsonb(m)->>'deleted' AS deleted
  FROM public.model_week_overrides m WHERE week_num BETWEEN 6 AND 31
),
reg AS (           -- registry: ONLY the model-consumed columns (verified from mapGoalFromDB, index.html:1606).
                   -- id verified by FK goal_funding_snapshots.goal_id -> goal_registry(id). `complete` is
                   -- DERIVED (status IN ('funded','executed')); waterfall also excludes status paused/archived.
  SELECT gr.id AS goal_id, gr.target AS target_amount, gr.priority, gr.status,
         gr.tier AS goal_type, gr.stretch, gr.auto, gr.starts_after, gr.needs_flag
  FROM public.goal_registry gr WHERE gr.id IN (SELECT unnest(all12) FROM ag)
),
reconfp AS (       -- balance-free proof wk6 recon == local before-image (expect d6fa5d0e…)
  SELECT md5(week_num||'|'||chk||'|'||sav||'|'||amx||'|'||tax||'|'||lc||'|'||coalesce(balance_basis,'')||'|'||recorded_at) AS fp
  FROM public.weekly_reconciliations WHERE week_num=6
),
a1fp AS (SELECT md5(coalesce(string_agg(
           week_num||'|'||task_idx||'|'||coalesce(action_key,'∅')||'|'||completed||'|'||
           coalesce(completed_amount::text,'∅')||'|'||coalesce(completed_label,'∅')||'|'||
           coalesce(completed_at::text,'∅')||'|'||coalesce(updated_at,'∅'),';'
           ORDER BY week_num,task_idx),'∅')) AS fp FROM a1)

SELECT jsonb_build_object(
  'metadata', jsonb_build_object(
     'query_version','2026-07-18-v5',
     'sql_sha256','verify externally with shasum -a256 (reported in the audit message)',
     'production_project','usayoldrawwmjsmretin',
     'model_year',2026,
     'model_week_horizon','6-31 (Cal 28-53); A1 pulls wk1-2; tax detail wk6-12',
     'generated_at', now()::text,
     'transaction_read_only', current_setting('transaction_read_only'),
     'transaction_isolation', current_setting('transaction_isolation'),
     'section_row_counts', jsonb_build_object(
        'A1_tasks',(SELECT count(*) FROM a1),'A1_custom',(SELECT count(*) FROM a1_custom),
        'A2_A3_tax_records',(SELECT count(*) FROM tax_all),'A2_A3_amount_probe',(SELECT count(*) FROM amount_probe),
        'A4_snap_latest',(SELECT count(*) FROM snap_latest),'A4_adamira',(SELECT count(*) FROM adamira),
        'A4_completed_tasks',(SELECT count(*) FROM comp_tasks),'A4_active_commitments',(SELECT count(*) FROM active_cc),
        'A4_overrides',(SELECT count(*) FROM mwo),'A4_registry',(SELECT count(*) FROM reg))),
  'A1_week23_24_tasks', jsonb_build_object(
     'model_weeks',jsonb_build_array(1,2),'calendar_weeks',jsonb_build_array(23,24),
     'note','proves durable presence/mutation; UI resolution still requires comparison vs the current generated candidate set',
     'tasks',(SELECT coalesce(jsonb_agg(to_jsonb(a1) ORDER BY week_num,task_idx),'[]'::jsonb) FROM a1),
     'custom_tasks',(SELECT coalesce(jsonb_agg(to_jsonb(a1_custom) ORDER BY week_num),'[]'::jsonb) FROM a1_custom),
     'task_set_fingerprint',(SELECT fp FROM a1fp)),
  'A2_A3_tax_evidence', jsonb_build_object(
     'model_weeks','6-12',
     'field_note','weekly_reconciliations.tax is returned as reconciled_tax_value = an account/reserve STATE value, never a transfer',
     'tax_records',(SELECT coalesce(jsonb_agg(to_jsonb(tax_all) ORDER BY model_week, durable_source_table),'[]'::jsonb) FROM tax_all),
     'audit_amount_durability',(SELECT coalesce(jsonb_agg(to_jsonb(amount_probe) ORDER BY amt),'[]'::jsonb) FROM amount_probe)),
  'A4_model_inputs', jsonb_build_object(
     'latest_snapshots',(SELECT coalesce(jsonb_agg(to_jsonb(snap_latest) ORDER BY goal_id),'[]'::jsonb) FROM snap_latest),
     'adam_ira_snapshot_chain',(SELECT coalesce(jsonb_agg(to_jsonb(adamira) ORDER BY week_num),'[]'::jsonb) FROM adamira),
     'completed_goal_tasks',(SELECT coalesce(jsonb_agg(to_jsonb(comp_tasks) ORDER BY week_num,task_idx),'[]'::jsonb) FROM comp_tasks),
     'active_cash_commitments',(SELECT coalesce(jsonb_agg(to_jsonb(active_cc) ORDER BY origin_model_week),'[]'::jsonb) FROM active_cc),
     'model_week_overrides',(SELECT coalesce(jsonb_agg(to_jsonb(mwo) ORDER BY week_num),'[]'::jsonb) FROM mwo),
     'goal_registry',(SELECT coalesce(jsonb_agg(to_jsonb(reg) ORDER BY priority),'[]'::jsonb) FROM reg),
     'wk6_recon_fingerprint',(SELECT fp FROM reconfp))
) AS audit_evidence;

COMMIT;
