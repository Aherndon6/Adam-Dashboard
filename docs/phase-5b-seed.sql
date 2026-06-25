-- =============================================================================
-- Phase 5B — Budget Module: Seed Data for budget_line_rules
-- Run AFTER phase-5b-budget-schema.sql
-- All start_month / end_month values are first day of month.
--
-- IMPORTANT — auth.uid() is null in Supabase SQL Editor.
-- This script uses a DO block to look up Adam's UUID from auth.users and
-- supplies it explicitly as created_by / updated_by.
-- The COALESCE trigger in budget_line_rules_set_created() will accept this
-- value when auth.uid() is null (SQL Editor context).
-- =============================================================================

DO $$
DECLARE
  adam_id        uuid;
  existing_count integer;
BEGIN

  -- Resolve Adam's UUID from auth.users. Fails loudly if not found.
  SELECT id INTO adam_id
  FROM auth.users
  WHERE email = 'adam@herndons.us'
  LIMIT 1;

  IF adam_id IS NULL THEN
    RAISE EXCEPTION 'adam@herndons.us not found in auth.users — cannot seed budget_line_rules';
  END IF;

  -- Idempotency guard: fail loudly if any Phase 5B seed rows already exist.
  -- Running twice would double all budget amounts and create overlapping rules.
  -- If you need to re-seed, run docs/phase-5b-budget-rollback.sql first.
  SELECT COUNT(*) INTO existing_count
  FROM budget_line_rules
  WHERE category_key IN (
    'income.net_salary',
    'home.mortgage_rent',
    'misc.goal_sweep',
    'entertainment',
    'food_dining.groceries'
  );

  IF existing_count > 0 THEN
    RAISE EXCEPTION
      'Phase 5B budget seed rows already exist (% rows found). '
      'Stop to avoid duplicate budget rules. '
      'Run docs/phase-5b-budget-rollback.sql first if you need to re-seed.',
      existing_count;
  END IF;

  RAISE NOTICE 'Seeding budget_line_rules as user %', adam_id;

  -- ===========================================================================
  -- INCOME LINES (display-only in Budget UI; no transaction entry in v1)
  -- ===========================================================================

  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, notes, created_by, updated_by)
  VALUES
    ('income.net_salary',        'Net Salary',        11633, '2026-06-01', NULL,
      'Adam net monthly salary', adam_id, adam_id),
    ('income.net_salary_spouse', 'Net Salary Spouse',  4305, '2026-06-01', NULL,
      'Wendy net monthly salary', adam_id, adam_id);

  -- ===========================================================================
  -- EXPENSE LINES — JUNE BASELINE
  -- ===========================================================================

  -- Auto & Transport
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, created_by, updated_by)
  VALUES
    ('auto_transport.auto_insurance', 'Auto Insurance',  501, '2026-06-01', NULL, adam_id, adam_id),
    ('auto_transport.auto_payment',   'Auto Payment',    791, '2026-06-01', NULL, adam_id, adam_id),
    ('auto_transport.gas_fuel',       'Gas & Fuel',      500, '2026-06-01', NULL, adam_id, adam_id);

  -- Bills & Utilities
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, created_by, updated_by)
  VALUES
    ('bills_utilities.apple',        'Apple',         26,  '2026-06-01', NULL, adam_id, adam_id),
    ('bills_utilities.gas_power',    'Gas and Power', 320, '2026-06-01', NULL, adam_id, adam_id),
    ('bills_utilities.mobile_phone', 'Mobile Phone',   88, '2026-06-01', NULL, adam_id, adam_id),
    ('bills_utilities.water',        'Water',         240, '2026-06-01', NULL, adam_id, adam_id);

  -- Entertainment (standalone leaf)
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, created_by, updated_by)
  VALUES
    ('entertainment', 'Entertainment', 1500, '2026-06-01', NULL, adam_id, adam_id);

  -- Food & Dining
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, created_by, updated_by)
  VALUES
    ('food_dining.groceries', 'Groceries', 2000, '2026-06-01', NULL, adam_id, adam_id);

  -- Health & Fitness — base lines (no time-bounded items yet)
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, created_by, updated_by)
  VALUES
    ('health_fitness.ymca',       'YMCA',       86,  '2026-06-01', NULL, adam_id, adam_id),
    ('health_fitness.f_training', 'F Training', 179, '2026-06-01', NULL, adam_id, adam_id),
    ('health_fitness.peloton',    'Peloton',     20, '2026-06-01', NULL, adam_id, adam_id);

  -- Home
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, created_by, updated_by)
  VALUES
    ('home.claudai', 'ClaudAI', 20, '2026-06-01', NULL, adam_id, adam_id),
    ('home.google',  'Google',  34, '2026-06-01', NULL, adam_id, adam_id),
    ('home.openai',  'OpenAI',  20, '2026-06-01', NULL, adam_id, adam_id);

  -- Mortgage/Rent: June only at $5,300 (end_month = 2026-06-01 = last active month)
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, notes, created_by, updated_by)
  VALUES
    ('home.mortgage_rent', 'Mortgage & Rent', 5300, '2026-06-01', '2026-06-01',
      'June rate before rent increase', adam_id, adam_id);

  -- Mortgage/Rent: July onward at $5,400 (no end)
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, notes, created_by, updated_by)
  VALUES
    ('home.mortgage_rent', 'Mortgage & Rent', 5400, '2026-07-01', NULL,
      'Post-rent-increase rate', adam_id, adam_id);

  -- Misc
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, notes, created_by, updated_by)
  VALUES
    ('misc.extra',      'Extra',                          1869, '2026-06-01', NULL, NULL, adam_id, adam_id),
    ('misc.goal_sweep', 'Extra Pay Going to Spreadsheet', 2300, '2026-06-01', NULL,
      'Display-only. Excluded from living expenses and transaction assignment. Available-for-goals baseline.',
      adam_id, adam_id);

  -- Personal Care
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, created_by, updated_by)
  VALUES
    ('personal_care.hair', 'Hair', 144, '2026-06-01', NULL, adam_id, adam_id);

  -- ===========================================================================
  -- TIME-BOUNDED ADDITIONS
  -- ===========================================================================

  -- Diablos Preston Fee: July 2026 through December 2026
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, notes, created_by, updated_by)
  VALUES
    ('health_fitness.diablos_preston_fee', 'Diablos (Preston) Fee', 750,
     '2026-07-01', '2026-12-01',
     'Jul-Dec 2026. Reassess January 2027.', adam_id, adam_id);

  -- Wendy GLP Meds: August 2026 through December 2026
  INSERT INTO budget_line_rules
    (category_key, line_label, amount, start_month, end_month, notes, created_by, updated_by)
  VALUES
    ('health_fitness.wendy_glp_meds', 'Wendy GLP Meds', 404,
     '2026-08-01', '2026-12-01',
     'Aug-Dec 2026. Reassess January 2027.', adam_id, adam_id);

  RAISE NOTICE 'Seed complete. Run verification queries below to confirm.';

END;
$$;


-- =============================================================================
-- VERIFICATION QUERIES — run after the DO block to confirm
-- Uncomment one at a time and run separately.
-- =============================================================================

-- Active rules for June 2026 (expect: all baseline rows, no Diablos, no GLP)
-- SELECT category_key, line_label, amount
-- FROM budget_line_rules
-- WHERE start_month <= '2026-06-01'
--   AND (end_month IS NULL OR end_month >= '2026-06-01')
--   AND is_active = true
-- ORDER BY category_key;

-- Active rules for July 2026 (expect: rent = $5,400, Diablos = $750, no GLP)
-- SELECT category_key, line_label, amount
-- FROM budget_line_rules
-- WHERE start_month <= '2026-07-01'
--   AND (end_month IS NULL OR end_month >= '2026-07-01')
--   AND is_active = true
-- ORDER BY category_key;

-- Active rules for August 2026 (expect: rent = $5,400, Diablos = $750, GLP = $404)
-- SELECT category_key, line_label, amount
-- FROM budget_line_rules
-- WHERE start_month <= '2026-08-01'
--   AND (end_month IS NULL OR end_month >= '2026-08-01')
--   AND is_active = true
-- ORDER BY category_key;

-- Active rules for January 2027 (expect: no Diablos, no GLP, rent = $5,400)
-- SELECT category_key, line_label, amount
-- FROM budget_line_rules
-- WHERE start_month <= '2027-01-01'
--   AND (end_month IS NULL OR end_month >= '2027-01-01')
--   AND is_active = true
-- ORDER BY category_key;

-- Overlap check — should return 0 rows if seed is clean:
-- SELECT a.category_key, a.start_month AS a_start, a.end_month AS a_end,
--        b.start_month AS b_start, b.end_month AS b_end
-- FROM budget_line_rules a
-- JOIN budget_line_rules b
--   ON a.category_key = b.category_key
--   AND a.id <> b.id
--   AND a.is_active = true
--   AND b.is_active = true
--   AND a.start_month <= COALESCE(b.end_month, '2099-01-01')
--   AND b.start_month <= COALESCE(a.end_month, '2099-01-01');

-- Living expense totals by month (excl income.* and misc.goal_sweep):
-- SELECT
--   to_char(m, 'Mon YYYY') AS month,
--   SUM(amount) AS living_expenses,
--   15938 - SUM(amount) AS available_for_goals
-- FROM budget_line_rules,
--      unnest(ARRAY['2026-06-01','2026-07-01','2026-08-01','2026-12-01','2027-01-01']::date[]) AS m
-- WHERE is_active = true
--   AND start_month <= m
--   AND (end_month IS NULL OR end_month >= m)
--   AND category_key NOT LIKE 'income.%'
--   AND category_key <> 'misc.goal_sweep'
-- GROUP BY m
-- ORDER BY m;
-- Expected: Jun=$13,638/$2,300 | Jul=$14,488/$1,450 | Aug=$14,892/$1,046 | Dec=$14,892/$1,046 | Jan=$13,738/$2,200
