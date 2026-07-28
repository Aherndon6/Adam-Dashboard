-- Step 8 · Baseline A · Environment & Schema Safety (READ-ONLY, phased gates)
-- Target: PRODUCTION usayoldrawwmjsmretin. Precondition: A0_OPERATOR_PROJECT_CONFIRMATION recorded externally.
-- Run A0..A4 as separate executions. Gates: B, B6, BCAT, C, D. AU-11 presence = GLOBAL stop.

-- A0_SESSION_METADATA
SELECT 'A0_SESSION_METADATA' AS result_set, current_database() AS current_database, current_user AS current_user_name,
  session_user AS session_user_name, current_timestamp AS current_ts, (current_timestamp AT TIME ZONE 'UTC') AS current_ts_utc,
  current_setting('TimeZone') AS session_timezone, version() AS server_version;

-- A1_REQUIRED_TABLES
WITH required(tname, gate, severity) AS (
  VALUES ('accounts','B','HARD_REQUIRED'),('transactions','B','HARD_REQUIRED'),('categories','B','HARD_REQUIRED'),
    ('weekly_reconciliations','C','HARD_REQUIRED'),('cash_commitments','D','HARD_REQUIRED'),('custom_tasks','D','HARD_REQUIRED'),
    ('weekly_tasks','D','HARD_REQUIRED'),('goals','D','HARD_REQUIRED'),
    ('model_week_overrides','INFO','OPTIONAL_INFORMATIONAL'),('goal_registry','INFO','OPTIONAL_INFORMATIONAL'),
    ('goal_funding_snapshots','INFO','OPTIONAL_INFORMATIONAL'),('weekly_notes','INFO','OPTIONAL_INFORMATIONAL'),
    ('budget_line_rules','INFO','OPTIONAL_INFORMATIONAL'),('budget_rules','INFO','OPTIONAL_INFORMATIONAL'),
    ('wishlist_items','INFO','OPTIONAL_INFORMATIONAL'),('budget_transactions','INFO','OPTIONAL_INFORMATIONAL')
)
SELECT 'A1_REQUIRED_TABLES' AS result_set, r.gate, r.tname AS table_name, true AS expected_present,
  EXISTS (SELECT 1 FROM information_schema.tables t WHERE t.table_schema='public' AND t.table_name=r.tname) AS actual_present,
  r.severity,
  CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables t WHERE t.table_schema='public' AND t.table_name=r.tname) THEN 'PASS'
       WHEN r.severity='HARD_REQUIRED' THEN 'FAIL_BLOCK' ELSE 'FAIL_INFO' END AS result
FROM required r ORDER BY r.gate, (r.severity='HARD_REQUIRED') DESC, r.tname;

-- A2_REQUIRED_COLUMNS
WITH required(tname, cname, gate, severity) AS (
  VALUES ('accounts','key','B','HARD_REQUIRED'),('accounts','id','B','HARD_REQUIRED'),('accounts','label','B','HARD_REQUIRED'),
    ('accounts','account_type','B','HARD_REQUIRED'),('accounts','lifecycle_status','B','HARD_REQUIRED'),
    ('accounts','starting_balance','B','HARD_REQUIRED'),('accounts','starting_balance_as_of','B','HARD_REQUIRED'),
    ('accounts','institution','B','HARD_REQUIRED'),('accounts','starting_balance_source','B','OPTIONAL_INFORMATIONAL'),
    ('accounts','starting_balance_note','B','OPTIONAL_INFORMATIONAL'),('accounts','include_in_cashflow','B','OPTIONAL_INFORMATIONAL'),
    ('accounts','display_order','B','OPTIONAL_INFORMATIONAL'),
    ('transactions','id','B','HARD_REQUIRED'),('transactions','account_key','B','HARD_REQUIRED'),('transactions','amount','B','HARD_REQUIRED'),
    ('transactions','cleared','B','HARD_REQUIRED'),('transactions','transaction_date','B','HARD_REQUIRED'),('transactions','posted_date','B','HARD_REQUIRED'),
    ('transactions','reconciled','B','HARD_REQUIRED'),('transactions','category_key','B','HARD_REQUIRED'),('transactions','payee','B','HARD_REQUIRED'),
    ('transactions','memo','B','HARD_REQUIRED'),('transactions','notes','B','HARD_REQUIRED'),('transactions','source','B','HARD_REQUIRED'),
    ('transactions','created_at','B','HARD_REQUIRED'),('transactions','updated_at','B','HARD_REQUIRED'),
    ('transactions','transfer_pair_id','B6','HARD_REQUIRED'),
    ('categories','key','B','HARD_REQUIRED'),('categories','label','B','HARD_REQUIRED'),
    ('categories','behavior_class','BCAT','HARD_REQUIRED'),('categories','parent_key','BCAT','HARD_REQUIRED'),
    ('weekly_reconciliations','week_num','C','HARD_REQUIRED'),('weekly_reconciliations','chk','C','HARD_REQUIRED'),
    ('weekly_reconciliations','balance_basis','C','OPTIONAL_INFORMATIONAL'),('weekly_reconciliations','recorded_at','C','OPTIONAL_INFORMATIONAL'),
    ('cash_commitments','status','D','HARD_REQUIRED'),('cash_commitments','commitment_class','D','HARD_REQUIRED'),
    ('cash_commitments','required_or_discretionary','D','HARD_REQUIRED'),('cash_commitments','amount_cents','D','HARD_REQUIRED'),
    ('cash_commitments','affects_deployable_cash','D','HARD_REQUIRED'),('cash_commitments','model_year','D','HARD_REQUIRED'),
    ('custom_tasks','id','D','HARD_REQUIRED'),('custom_tasks','week_num','D','HARD_REQUIRED'),('custom_tasks','label','D','HARD_REQUIRED'),
    ('custom_tasks','completed','D','HARD_REQUIRED'),('weekly_tasks','week_num','D','HARD_REQUIRED'),
    ('goals','key','D','HARD_REQUIRED'),('goals','value','D','HARD_REQUIRED')
)
SELECT 'A2_REQUIRED_COLUMNS' AS result_set, r.gate, r.tname AS table_name, r.cname AS column_name, true AS expected_present,
  EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=r.tname AND c.column_name=r.cname) AS actual_present,
  r.severity,
  CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=r.tname AND c.column_name=r.cname) THEN 'PASS'
       WHEN r.severity='HARD_REQUIRED' THEN 'FAIL_BLOCK' ELSE 'FAIL_INFO' END AS result
FROM required r ORDER BY r.gate, (r.severity='HARD_REQUIRED') DESC, r.tname, r.cname;

-- A3_AU11_PRODUCTION_ABSENCE (functions signature-checked via to_regprocedure)
WITH absence(ord, check_id, object_kind, object_name, severity) AS (
  VALUES (1,'A3.1','column','public.cash_commitments.cleared_transaction_id (D3)','AU11_ABSENCE_SAFETY'),
    (2,'A3.2','column','public.cash_commitments.reservation_batch_id (D1)','AU11_ABSENCE_SAFETY'),
    (3,'A3.3','column','public.cash_commitments.goal_id (D1)','AU11_ABSENCE_SAFETY'),
    (4,'A3.4','column','public.cash_commitments.destination_account_ref (D1)','AU11_ABSENCE_SAFETY'),
    (5,'A3.5','column','public.cash_commitments.bank_reference (D1)','AU11_ABSENCE_SAFETY'),
    (6,'A3.6','column','public.cash_commitments.bank_submitted_at (D1)','AU11_ABSENCE_SAFETY'),
    (7,'A3.7','column','public.goal_registry.reservable (D2)','AU11_ABSENCE_SAFETY'),
    (8,'A3.8','table','public.discretionary_reservation_batches (D1)','AU11_ABSENCE_SAFETY'),
    (9,'A3.9','function_signature','public.close_week_with_reservations_v1(14-arg) (D3)','AU11_ABSENCE_SAFETY'),
    (10,'A3.10','function_signature','public.create_discretionary_goal_reservation_v1(7-arg) (D2)','AU11_ABSENCE_SAFETY'),
    (11,'A3.11','function_signature','public.mark_discretionary_goal_reservation_initiated_v1(6-arg) (D2)','AU11_ABSENCE_SAFETY'),
    (12,'A3.12','function_signature','public.void_scheduled_discretionary_goal_reservation_v1(4-arg) (D2)','AU11_ABSENCE_SAFETY'),
    (13,'A3.13','constraint','fk_au11_cleared_txn ON public.cash_commitments (D3)','AU11_ABSENCE_SAFETY'),
    (14,'A3.14','constraint','chk_au11_cleared_txn_attribution ON public.cash_commitments (D3)','AU11_ABSENCE_SAFETY'),
    (15,'A3.15','index','uix_au11_cleared_txn ON public.cash_commitments (D3)','AU11_ABSENCE_SAFETY'),
    (16,'A3.16','check_constraint_token','public.cash_commitments CHECK contains discretionary_goal_transfer (D1)','AU11_ABSENCE_SAFETY'),
    (17,'A3.17','check_constraint_token','public.cash_commitments CHECK contains au11_reservation (D1)','AU11_ABSENCE_SAFETY'),
    (18,'A3.18','function_wildcard','any public function ILIKE %reserv% not in the exact D2/D3 set','OPTIONAL_INFORMATIONAL'),
    (19,'A3.19','function_name_overload','a D2/D3 name present with a non-matching signature','OPTIONAL_INFORMATIONAL')
),
evaluated AS (
  SELECT a.ord, a.check_id, a.object_kind, a.object_name, a.severity,
    CASE a.check_id
      WHEN 'A3.1'  THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id')
      WHEN 'A3.2'  THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='reservation_batch_id')
      WHEN 'A3.3'  THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='goal_id')
      WHEN 'A3.4'  THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='destination_account_ref')
      WHEN 'A3.5'  THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='bank_reference')
      WHEN 'A3.6'  THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='bank_submitted_at')
      WHEN 'A3.7'  THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable')
      WHEN 'A3.8'  THEN EXISTS (SELECT 1 FROM information_schema.tables  WHERE table_schema='public' AND table_name='discretionary_reservation_batches')
      WHEN 'A3.9'  THEN to_regprocedure('public.close_week_with_reservations_v1(integer,integer,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,integer,jsonb)') IS NOT NULL
      WHEN 'A3.10' THEN to_regprocedure('public.create_discretionary_goal_reservation_v1(integer,integer,text,text,date,jsonb,integer)') IS NOT NULL
      WHEN 'A3.11' THEN to_regprocedure('public.mark_discretionary_goal_reservation_initiated_v1(integer,text,text[],text,timestamp with time zone,date)') IS NOT NULL
      WHEN 'A3.12' THEN to_regprocedure('public.void_scheduled_discretionary_goal_reservation_v1(integer,text,text[],text)') IS NOT NULL
      WHEN 'A3.13' THEN EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace nn ON nn.oid=cl.relnamespace WHERE nn.nspname='public' AND cl.relname='cash_commitments' AND con.conname='fk_au11_cleared_txn')
      WHEN 'A3.14' THEN EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace nn ON nn.oid=cl.relnamespace WHERE nn.nspname='public' AND cl.relname='cash_commitments' AND con.contype='c' AND con.conname='chk_au11_cleared_txn_attribution')
      WHEN 'A3.15' THEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='cash_commitments' AND indexname='uix_au11_cleared_txn')
      WHEN 'A3.16' THEN EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace nn ON nn.oid=cl.relnamespace WHERE nn.nspname='public' AND cl.relname='cash_commitments' AND con.contype='c' AND pg_get_constraintdef(con.oid) ILIKE '%discretionary_goal_transfer%')
      WHEN 'A3.17' THEN EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace nn ON nn.oid=cl.relnamespace WHERE nn.nspname='public' AND cl.relname='cash_commitments' AND con.contype='c' AND pg_get_constraintdef(con.oid) ILIKE '%au11_reservation%')
      WHEN 'A3.18' THEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname ILIKE '%reserv%' AND p.proname NOT IN ('close_week_with_reservations_v1','create_discretionary_goal_reservation_v1','mark_discretionary_goal_reservation_initiated_v1','void_scheduled_discretionary_goal_reservation_v1'))
      WHEN 'A3.19' THEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('close_week_with_reservations_v1','create_discretionary_goal_reservation_v1','mark_discretionary_goal_reservation_initiated_v1','void_scheduled_discretionary_goal_reservation_v1'))
                        AND to_regprocedure('public.close_week_with_reservations_v1(integer,integer,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,integer,jsonb)') IS NULL
                        AND to_regprocedure('public.create_discretionary_goal_reservation_v1(integer,integer,text,text,date,jsonb,integer)') IS NULL
                        AND to_regprocedure('public.mark_discretionary_goal_reservation_initiated_v1(integer,text,text[],text,timestamp with time zone,date)') IS NULL
                        AND to_regprocedure('public.void_scheduled_discretionary_goal_reservation_v1(integer,text,text[],text)') IS NULL
    END AS actual_present
  FROM absence a
)
SELECT 'A3_AU11_PRODUCTION_ABSENCE' AS result_set, check_id, object_kind, object_name, false AS expected_present, actual_present, severity,
  CASE WHEN actual_present AND severity='AU11_ABSENCE_SAFETY' THEN 'FAIL_AU11_PRESENT_GLOBAL_STOP'
       WHEN actual_present AND severity='OPTIONAL_INFORMATIONAL' THEN 'INFO_UNEXPECTED_REVIEW' ELSE 'PASS' END AS result
FROM evaluated ORDER BY ord;

-- A4_PHASED_GATES
WITH req_tables(tname, gate) AS (
  VALUES ('accounts','B'),('transactions','B'),('categories','B'),('weekly_reconciliations','C'),
         ('cash_commitments','D'),('custom_tasks','D'),('weekly_tasks','D'),('goals','D')
),
req_cols(tname, cname, gate) AS (
  VALUES ('accounts','key','B'),('accounts','id','B'),('accounts','label','B'),('accounts','account_type','B'),
    ('accounts','lifecycle_status','B'),('accounts','starting_balance','B'),('accounts','starting_balance_as_of','B'),('accounts','institution','B'),
    ('transactions','id','B'),('transactions','account_key','B'),('transactions','amount','B'),('transactions','cleared','B'),
    ('transactions','transaction_date','B'),('transactions','posted_date','B'),('transactions','reconciled','B'),
    ('transactions','category_key','B'),('transactions','payee','B'),('transactions','memo','B'),('transactions','notes','B'),
    ('transactions','source','B'),('transactions','created_at','B'),('transactions','updated_at','B'),
    ('categories','key','B'),('categories','label','B'),('transactions','transfer_pair_id','B6'),
    ('categories','behavior_class','BCAT'),('categories','parent_key','BCAT'),
    ('weekly_reconciliations','week_num','C'),('weekly_reconciliations','chk','C'),
    ('cash_commitments','status','D'),('cash_commitments','commitment_class','D'),('cash_commitments','required_or_discretionary','D'),
    ('cash_commitments','amount_cents','D'),('cash_commitments','affects_deployable_cash','D'),('cash_commitments','model_year','D'),
    ('custom_tasks','id','D'),('custom_tasks','week_num','D'),('custom_tasks','label','D'),('custom_tasks','completed','D'),
    ('weekly_tasks','week_num','D'),('goals','key','D'),('goals','value','D')
),
au11(present) AS (
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='cleared_transaction_id')
  UNION ALL SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='reservation_batch_id')
  UNION ALL SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='goal_id')
  UNION ALL SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='destination_account_ref')
  UNION ALL SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='bank_reference')
  UNION ALL SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cash_commitments' AND column_name='bank_submitted_at')
  UNION ALL SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='goal_registry' AND column_name='reservable')
  UNION ALL SELECT EXISTS (SELECT 1 FROM information_schema.tables  WHERE table_schema='public' AND table_name='discretionary_reservation_batches')
  UNION ALL SELECT (to_regprocedure('public.close_week_with_reservations_v1(integer,integer,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,integer,jsonb)') IS NOT NULL)
  UNION ALL SELECT (to_regprocedure('public.create_discretionary_goal_reservation_v1(integer,integer,text,text,date,jsonb,integer)') IS NOT NULL)
  UNION ALL SELECT (to_regprocedure('public.mark_discretionary_goal_reservation_initiated_v1(integer,text,text[],text,timestamp with time zone,date)') IS NOT NULL)
  UNION ALL SELECT (to_regprocedure('public.void_scheduled_discretionary_goal_reservation_v1(integer,text,text[],text)') IS NOT NULL)
  UNION ALL SELECT EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace nn ON nn.oid=cl.relnamespace WHERE nn.nspname='public' AND cl.relname='cash_commitments' AND con.conname='fk_au11_cleared_txn')
  UNION ALL SELECT EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace nn ON nn.oid=cl.relnamespace WHERE nn.nspname='public' AND cl.relname='cash_commitments' AND con.contype='c' AND con.conname='chk_au11_cleared_txn_attribution')
  UNION ALL SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='cash_commitments' AND indexname='uix_au11_cleared_txn')
  UNION ALL SELECT EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace nn ON nn.oid=cl.relnamespace WHERE nn.nspname='public' AND cl.relname='cash_commitments' AND con.contype='c' AND pg_get_constraintdef(con.oid) ILIKE '%discretionary_goal_transfer%')
  UNION ALL SELECT EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace nn ON nn.oid=cl.relnamespace WHERE nn.nspname='public' AND cl.relname='cash_commitments' AND con.contype='c' AND pg_get_constraintdef(con.oid) ILIKE '%au11_reservation%')
),
au11p AS (SELECT count(*) FILTER (WHERE present) AS n FROM au11),
gates(gate) AS (VALUES ('B'),('B6'),('BCAT'),('C'),('D')),
tbl_fail AS (SELECT g.gate, (SELECT count(*) FROM req_tables r WHERE r.gate=g.gate AND NOT EXISTS (SELECT 1 FROM information_schema.tables t WHERE t.table_schema='public' AND t.table_name=r.tname)) AS n FROM gates g),
col_fail AS (SELECT g.gate, (SELECT count(*) FROM req_cols r WHERE r.gate=g.gate AND NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=r.tname AND c.column_name=r.cname)) AS n FROM gates g)
SELECT 'A4_PHASED_GATES' AS result_set, g.gate,
  (SELECT n FROM tbl_fail WHERE gate=g.gate) AS hard_required_table_failures,
  (SELECT n FROM col_fail WHERE gate=g.gate) AS hard_required_column_failures,
  (SELECT n FROM au11p) AS au11_unexpected_present_global,
  CASE WHEN (SELECT n FROM tbl_fail WHERE gate=g.gate)=0 AND (SELECT n FROM col_fail WHERE gate=g.gate)=0 AND (SELECT n FROM au11p)=0 THEN 'GATE_PASS' ELSE 'GATE_FAIL_STOP' END AS gate_result
FROM gates g
UNION ALL
SELECT 'A4_PHASED_GATES','MANUAL_NOTE', NULL, NULL, (SELECT n FROM au11p),
  'EXTERNAL: A0_OPERATOR_PROJECT_CONFIRMATION (project selector = usayoldrawwmjsmretin) recorded separately; SQL cannot prove it. Run a B statement only when its gate = GATE_PASS AND the manual confirmation is recorded. B6a needs B6; B6b needs B6+BCAT; B8 needs BCAT.'
ORDER BY gate;
