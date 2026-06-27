-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 5D-1 Migration — Herndon Financial OS
-- Supabase registry foundation: accounts + categories tables
-- Generated: 2026-06-26
--
-- Scope: accounts table, categories table, RLS, updated_at triggers,
--        account seed (14 rows), category seed (51 rows), budget_line_rules
--        Diablos + GLP Meds inserts.
--
-- Idempotent: safely rerunnable.
--   Tables:   CREATE TABLE IF NOT EXISTS
--   Policies: DROP POLICY IF EXISTS before each CREATE POLICY
--   Triggers: DROP TRIGGER IF EXISTS before each CREATE TRIGGER
--   Seeds:    ON CONFLICT (key) DO UPDATE — deterministic convergence on rerun
--   BLR rows: WHERE NOT EXISTS guards
--
-- Prerequisite: is_allowed_user() and is_owner() functions must exist (confirmed present).
-- Note: get_my_role() does not exist in this project. Write policies use is_owner(),
-- matching the established pattern on budget_line_rules and all other existing tables.
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Block 0: Shared updated_at trigger function
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Block 1: accounts table
-- lifecycle_status replaces os_scope + is_active.
-- starting_balance fields left NULL; captured at go-live (7/1/26).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS accounts (
  id                       uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  key                      text         NOT NULL UNIQUE,
  label                    text         NOT NULL,
  institution              text,
  account_type             text         NOT NULL,
  lifecycle_status         text         NOT NULL DEFAULT 'active',
  include_in_budget        boolean      NOT NULL DEFAULT true,
  include_in_cashflow      boolean      NOT NULL DEFAULT true,
  starting_balance         numeric(12,2),
  starting_balance_as_of   date,
  starting_balance_source  text,
  starting_balance_note    text,
  quicken_name             text,
  notes                    text,
  display_order            integer      NOT NULL DEFAULT 0,
  created_at               timestamptz  NOT NULL DEFAULT now(),
  updated_at               timestamptz  NOT NULL DEFAULT now(),
  created_by               uuid         REFERENCES auth.users(id),
  updated_by               uuid         REFERENCES auth.users(id),
  CONSTRAINT chk_account_type CHECK (account_type IN
    ('checking','savings','credit_card','investment','property','loan','cash')),
  CONSTRAINT chk_account_lifecycle CHECK (lifecycle_status IN
    ('active','view_only','hidden','closed','excluded'))
);

DROP TRIGGER IF EXISTS trg_accounts_updated_at ON accounts;
CREATE TRIGGER trg_accounts_updated_at
  BEFORE UPDATE ON accounts
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- Block 2: categories table
-- assignable and is_income NOT stored — derived in JS via _normalizeCatRow().
-- reimbursement_pairing_key set post-insert to avoid circular FK at insert time.
-- linked_goal_id: no FK in Phase 5D-1 (goals table is key-value, not UUID-keyed).
--   NULL for all seed rows. FK + population deferred to Phase 5H.
-- chk_leaf_behavior bypasses for archived/merged rows.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS categories (
  id                        uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  key                       text         NOT NULL UNIQUE,
  label                     text         NOT NULL,
  parent_key                text         REFERENCES categories(key),
  is_leaf                   boolean      NOT NULL DEFAULT true,
  behavior_class            text,
  budget_treatment          text,
  cashflow_treatment        text,
  budget_line_key           text,
  budget_group_key          text,
  reimbursement_pairing_key text         REFERENCES categories(key),
  merged_into_key           text         REFERENCES categories(key),
  linked_goal_id            uuid,
  is_system                 boolean      NOT NULL DEFAULT false,
  lifecycle_status          text         NOT NULL DEFAULT 'active',
  display_order             integer      NOT NULL DEFAULT 0,
  created_at                timestamptz  NOT NULL DEFAULT now(),
  updated_at                timestamptz  NOT NULL DEFAULT now(),
  created_by                uuid         REFERENCES auth.users(id),
  updated_by                uuid         REFERENCES auth.users(id),
  CONSTRAINT chk_behavior_class CHECK (behavior_class IS NULL OR behavior_class IN
    ('expense','income','reimbursable_expense','reimbursable_income',
     'goal_linked','savings_allocation','transfer','commission_income')),
  CONSTRAINT chk_budget_treatment CHECK (budget_treatment IS NULL OR budget_treatment IN
    ('tracked','planned_allocation','display_only','excluded')),
  CONSTRAINT chk_cashflow_treatment CHECK (cashflow_treatment IS NULL OR cashflow_treatment IN
    ('operating','goal_funding','goal_spending','tax_reserve','reimbursable','excluded')),
  CONSTRAINT chk_cat_lifecycle CHECK (lifecycle_status IN ('active','archived','merged')),
  CONSTRAINT chk_leaf_behavior CHECK (
    lifecycle_status IN ('archived','merged')
    OR is_leaf = false
    OR (
      behavior_class     IS NOT NULL AND
      budget_treatment   IS NOT NULL AND
      cashflow_treatment IS NOT NULL
    )
  )
);

DROP TRIGGER IF EXISTS trg_categories_updated_at ON categories;
CREATE TRIGGER trg_categories_updated_at
  BEFORE UPDATE ON categories
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- Block 3: RLS — accounts
-- SELECT: all authenticated household users; lifecycle filtering in query/UI layer.
-- INSERT/UPDATE/DELETE: owner only.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "accounts_select"        ON accounts;
DROP POLICY IF EXISTS "accounts_insert_owner"  ON accounts;
DROP POLICY IF EXISTS "accounts_update_owner"  ON accounts;
DROP POLICY IF EXISTS "accounts_delete_owner"  ON accounts;

CREATE POLICY "accounts_select" ON accounts
  FOR SELECT TO authenticated
  USING (is_allowed_user());

CREATE POLICY "accounts_insert_owner" ON accounts
  FOR INSERT TO authenticated
  WITH CHECK (is_owner());

CREATE POLICY "accounts_update_owner" ON accounts
  FOR UPDATE TO authenticated
  USING  (is_owner())
  WITH CHECK (is_owner());

CREATE POLICY "accounts_delete_owner" ON accounts
  FOR DELETE TO authenticated
  USING (is_owner());

-- ─────────────────────────────────────────────────────────────────────────────
-- Block 4: RLS — categories
-- SELECT: all authenticated household users; lifecycle filtering in query/UI layer.
-- INSERT/UPDATE: owner only. DELETE: owner only AND is_system = false.
-- household_admin behavior-class change block enforced at RPC layer (Phase 5E).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "categories_select"        ON categories;
DROP POLICY IF EXISTS "categories_insert_owner"  ON categories;
DROP POLICY IF EXISTS "categories_update_owner"  ON categories;
DROP POLICY IF EXISTS "categories_delete_owner"  ON categories;

CREATE POLICY "categories_select" ON categories
  FOR SELECT TO authenticated
  USING (is_allowed_user());

CREATE POLICY "categories_insert_owner" ON categories
  FOR INSERT TO authenticated
  WITH CHECK (is_owner());

CREATE POLICY "categories_update_owner" ON categories
  FOR UPDATE TO authenticated
  USING  (is_owner())
  WITH CHECK (is_owner());

CREATE POLICY "categories_delete_owner" ON categories
  FOR DELETE TO authenticated
  USING (is_owner() AND is_system = false);

-- ─────────────────────────────────────────────────────────────────────────────
-- Block 5: Seed — accounts (14 rows)
-- ON CONFLICT (key) DO UPDATE: converges to canonical state on rerun.
-- Does NOT overwrite: id, created_at, created_by, starting_balance fields
--   (starting_balance captured manually at go-live 7/1/26).
-- 12 active + 1 view_only (Fidelity) + 1 hidden (Costco Visa, planned).
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO accounts
  (key, label, institution, account_type, lifecycle_status,
   include_in_budget, include_in_cashflow, quicken_name, notes, display_order)
VALUES
  ('truist_checking',       'Truist Checking',              'Truist',           'checking',    'active',    true,  true,  'SunTrust Checking',   NULL,                                                                  10),
  ('truist_savings',        'Truist Savings',               'Truist',           'savings',     'active',    true,  true,  'Suntrust Savings 2',  NULL,                                                                  20),
  ('amex_blue',             'AMEX Blue',                    'American Express', 'credit_card', 'active',    true,  true,  'AMEX2',               NULL,                                                                  30),
  ('boa_visa',              'BOA Visa',                     'Bank of America',  'credit_card', 'active',    true,  true,  'BOA VISA',            NULL,                                                                  40),
  ('chase_disney_visa',     'Disney Visa',                  'Chase',            'credit_card', 'active',    true,  true,  'Chase Disney Visa',   NULL,                                                                  50),
  ('amex_gold',             'AMEX Gold',                    'American Express', 'credit_card', 'active',    true,  true,  'Gold AMEX',           NULL,                                                                  60),
  ('amex_platinum',         'AMEX Platinum',                'American Express', 'credit_card', 'active',    true,  true,  'Platinum AMEX',       NULL,                                                                  70),
  ('truist_mastercard',     'Truist Mastercard',            'Truist',           'credit_card', 'active',    true,  true,  'Suntrust Mastercard', NULL,                                                                  80),
  ('amex_savings',          'AMEX Savings',                 'American Express', 'savings',     'active',    true,  true,  NULL,                  NULL,                                                                  90),
  ('vio_emergency_savings', 'Vio Bank - Emergency Savings', 'Vio Bank',         'savings',     'active',    true,  true,  NULL,                  NULL,                                                                 100),
  ('vio_tax_reserve',       'Vio Bank - Tax Reserve',       'Vio Bank',         'savings',     'active',    true,  true,  NULL,                  NULL,                                                                 110),
  ('lending_club_ef',       'Lending Club (EF)',            'Lending Club',     'savings',     'active',    true,  true,  NULL,                  NULL,                                                                 120),
  ('fidelity_wros',         'Fidelity Joint WROS-TOD',      'Fidelity',         'investment',  'view_only', false, true,  NULL,                  NULL,                                                                 130),
  ('costco_visa',           'Costco Visa',                  'Citi',             'credit_card', 'hidden',    true,  true,  NULL,                  'Planned card; not yet received/activated as of Phase 5D-1.',         140)
ON CONFLICT (key) DO UPDATE SET
  label               = EXCLUDED.label,
  institution         = EXCLUDED.institution,
  account_type        = EXCLUDED.account_type,
  lifecycle_status    = EXCLUDED.lifecycle_status,
  include_in_budget   = EXCLUDED.include_in_budget,
  include_in_cashflow = EXCLUDED.include_in_cashflow,
  quicken_name        = EXCLUDED.quicken_name,
  notes               = EXCLUDED.notes,
  display_order       = EXCLUDED.display_order,
  updated_at          = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- Block 6: Seed — categories (51 rows)
-- ON CONFLICT (key) DO UPDATE: converges to canonical classification on rerun.
-- Does NOT overwrite: id, created_at, created_by, linked_goal_id (Phase 5H).
-- Note: reimbursement_pairing_key is reset to EXCLUDED value (NULL for most rows)
--   then re-set correctly by the post-insert UPDATEs in Block 6p.
--   This is intentional: DO UPDATE + post-insert UPDATE = idempotent correct state.
--
-- Global display_order: parent = N*1000, leaves = N*1000 + 10*seq.
-- Parents seeded first to satisfy self-referencing parent_key FK.
-- is_system = true:  structural / foundation categories.
-- is_system = false: year-specific cohorts (trips, jabian, FSA) — can be archived.
-- ─────────────────────────────────────────────────────────────────────────────

-- 6a: Parent categories (13 rows, is_leaf=false, all behavior fields NULL)

INSERT INTO categories
  (key, label, parent_key, is_leaf, is_system, lifecycle_status, display_order)
VALUES
  ('income',          'Income',           NULL, false, true, 'active',  1000),
  ('auto_transport',  'Auto & Transport', NULL, false, true, 'active',  2000),
  ('bills_utilities', 'Bills & Utilities',NULL, false, true, 'active',  3000),
  ('entertainment',   'Entertainment',    NULL, false, true, 'active',  4000),
  ('food_dining',     'Food & Dining',    NULL, false, true, 'active',  5000),
  ('health_fitness',  'Health & Fitness', NULL, false, true, 'active',  6000),
  ('home',            'Home',             NULL, false, true, 'active',  7000),
  ('misc',            'Misc.',            NULL, false, true, 'active',  8000),
  ('personal_care',   'Personal Care',    NULL, false, true, 'active',  9000),
  ('trips',           'Trips',            NULL, false, true, 'active', 10000),
  ('business',        'Business',         NULL, false, true, 'active', 11000),
  ('transfers',       'Transfers',        NULL, false, true, 'active', 12000),
  ('taxes',           'Taxes',            NULL, false, true, 'active', 13000)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6b: Income leaves (3 rows)

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('income.net_salary',             'Net Salary',             'income', true, 'income',           'display_only', 'operating', NULL, 'income', true, 'active', 1010),
  ('income.net_salary_spouse',      'Net Salary Spouse',      'income', true, 'income',           'display_only', 'operating', NULL, 'income', true, 'active', 1020),
  ('income.deep_south_commissions', 'Deep South Commissions', 'income', true, 'commission_income','display_only', 'operating', NULL, 'income', true, 'active', 1030)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6c: Auto & Transport leaves (3 rows)

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('auto_transport.auto_insurance','Auto Insurance','auto_transport',true,'expense','tracked','operating','auto_transport.auto_insurance','auto_transport',true,'active',2010),
  ('auto_transport.auto_payment',  'Auto Payment',  'auto_transport',true,'expense','tracked','operating','auto_transport.auto_payment',  'auto_transport',true,'active',2020),
  ('auto_transport.gas_fuel',      'Gas & Fuel',    'auto_transport',true,'expense','tracked','operating','auto_transport.gas_fuel',      'auto_transport',true,'active',2030)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6d: Bills & Utilities leaves (4 rows)

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('bills_utilities.apple',       'Apple',        'bills_utilities',true,'expense','tracked','operating','bills_utilities.apple',       'bills_utilities',true,'active',3010),
  ('bills_utilities.gas_power',   'Gas and Power','bills_utilities',true,'expense','tracked','operating','bills_utilities.gas_power',   'bills_utilities',true,'active',3020),
  ('bills_utilities.mobile_phone','Mobile Phone', 'bills_utilities',true,'expense','tracked','operating','bills_utilities.mobile_phone','bills_utilities',true,'active',3030),
  ('bills_utilities.water',       'Water',        'bills_utilities',true,'expense','tracked','operating','bills_utilities.water',       'bills_utilities',true,'active',3040)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6e: Entertainment leaves (4 rows)
-- All 4 roll into the shared 'entertainment' budget_line_key.

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('entertainment.birthday_dinner',    'Birthday Dinner',    'entertainment',true,'expense','tracked','operating','entertainment','entertainment',true,'active',4010),
  ('entertainment.brunch',             'Brunch',             'entertainment',true,'expense','tracked','operating','entertainment','entertainment',true,'active',4020),
  ('entertainment.big_dinner_out',     'Big Dinner Out',     'entertainment',true,'expense','tracked','operating','entertainment','entertainment',true,'active',4030),
  ('entertainment.entertainment_other','Entertainment Other','entertainment',true,'expense','tracked','operating','entertainment','entertainment',true,'active',4040)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6f: Food & Dining leaves (1 row)

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('food_dining.groceries','Groceries','food_dining',true,'expense','tracked','operating','food_dining.groceries','food_dining',true,'active',5010)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6g: Health & Fitness leaves (6 rows)
-- flexible_spending_2026: is_system=false (year cohort); excluded; no budget_line_key/group_key.

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('health_fitness.ymca',                  'YMCA',                   'health_fitness',true,'expense',            'tracked', 'operating',  'health_fitness.ymca',                'health_fitness',true, 'active',6010),
  ('health_fitness.f_training',            'F Training',             'health_fitness',true,'expense',            'tracked', 'operating',  'health_fitness.f_training',          'health_fitness',true, 'active',6020),
  ('health_fitness.peloton',               'Peloton',                'health_fitness',true,'expense',            'tracked', 'operating',  'health_fitness.peloton',             'health_fitness',true, 'active',6030),
  ('health_fitness.diablos_preston_fee',   'Diablos (Preston) Fee',  'health_fitness',true,'expense',            'tracked', 'operating',  'health_fitness.diablos_preston_fee', 'health_fitness',true, 'active',6040),
  ('health_fitness.wendy_glp_meds',        'Wendy GLP Meds',         'health_fitness',true,'expense',            'tracked', 'operating',  'health_fitness.wendy_glp_meds',      'health_fitness',true, 'active',6050),
  ('health_fitness.flexible_spending_2026','Flexible Spending 2026', 'health_fitness',true,'reimbursable_expense','excluded','reimbursable',NULL,                               NULL,             false,'active',6060)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6h: Home leaves (4 rows)

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('home.claudai',      'ClaudAI',        'home',true,'expense','tracked','operating','home.claudai',      'home',true,'active',7010),
  ('home.google',       'Google',         'home',true,'expense','tracked','operating','home.google',       'home',true,'active',7020),
  ('home.mortgage_rent','Mortgage & Rent','home',true,'expense','tracked','operating','home.mortgage_rent','home',true,'active',7030),
  ('home.openai',       'OpenAI',         'home',true,'expense','tracked','operating','home.openai',       'home',true,'active',7040)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6i: Misc leaves (2 rows)
-- goal_sweep: savings_allocation / planned_allocation — not assignable per JS derivation.

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('misc.extra',     'Extra',                         'misc',true,'expense',          'tracked',          'operating',  'misc.extra','misc',true,'active',8010),
  ('misc.goal_sweep','Extra Pay Going to Spreadsheet','misc',true,'savings_allocation','planned_allocation','goal_funding',NULL,       'misc',true,'active',8020)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6j: Personal Care leaves (1 row)

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('personal_care.hair','Hair','personal_care',true,'expense','tracked','operating','personal_care.hair','personal_care',true,'active',9010)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6k: Trip leaves (4 rows)
-- goal_linked / excluded / goal_spending — Goals section only; no budget impact.
-- is_system=false: archive after trip concludes.

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('trips.seattle_alaska_2026',       '2026 Seattle/Alaska',       'trips',true,'goal_linked','excluded','goal_spending',NULL,NULL,false,'active',10010),
  ('trips.rccl_girls_trip_2026',      '2026 RCCL Girls Trip',      'trips',true,'goal_linked','excluded','goal_spending',NULL,NULL,false,'active',10020),
  ('trips.dcl_trip_2026',             '2026 DCL Trip',             'trips',true,'goal_linked','excluded','goal_spending',NULL,NULL,false,'active',10030),
  ('trips.rccl_christmas_cruise_2026','2026 RCCL Christmas Cruise','trips',true,'goal_linked','excluded','goal_spending',NULL,NULL,false,'active',10040)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6l: Business leaves (2 rows)
-- jabian_deposits_2026: display_only with budget_group_key='business' so V9 passes.

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('business.jabian_expenses_2026','Jabian Expenses 2026','business',true,'reimbursable_expense','excluded',    'reimbursable',NULL,NULL,      false,'active',11010),
  ('business.jabian_deposits_2026','Jabian Deposits 2026','business',true,'reimbursable_income', 'display_only','reimbursable',NULL,'business',false,'active',11020)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6m: Transfers leaves (1 row)

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('transfers.greenlight','Greenlight','transfers',true,'transfer','excluded','excluded',NULL,NULL,true,'active',12010)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6n: Tax leaves (2 rows)

INSERT INTO categories
  (key, label, parent_key, is_leaf, behavior_class, budget_treatment, cashflow_treatment,
   budget_line_key, budget_group_key, is_system, lifecycle_status, display_order)
VALUES
  ('taxes.vio_transfer_2026', 'Taxes 2026', 'taxes',true,'transfer','excluded','tax_reserve',NULL,NULL,true,'active',13010),
  ('taxes.actual_tax_payment','Tax Payment', 'taxes',true,'expense', 'excluded','tax_reserve',NULL,NULL,true,'active',13020)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6o: Merged duplicate (1 row)
-- business.jabian_2026_dup: confirmed duplicate of jabian_expenses_2026.
-- lifecycle_status='merged'; is_leaf=true (preserves semantic meaning).
-- chk_leaf_behavior bypasses for lifecycle_status='merged'.

INSERT INTO categories
  (key, label, parent_key, is_leaf, is_system, lifecycle_status, merged_into_key, display_order)
VALUES
  ('business.jabian_2026_dup','jabian 2026','business',true,false,'merged','business.jabian_expenses_2026',11030)
ON CONFLICT (key) DO UPDATE SET
  label             = EXCLUDED.label,
  parent_key        = EXCLUDED.parent_key,
  is_leaf           = EXCLUDED.is_leaf,
  behavior_class    = EXCLUDED.behavior_class,
  budget_treatment  = EXCLUDED.budget_treatment,
  cashflow_treatment= EXCLUDED.cashflow_treatment,
  budget_line_key   = EXCLUDED.budget_line_key,
  budget_group_key  = EXCLUDED.budget_group_key,
  reimbursement_pairing_key = EXCLUDED.reimbursement_pairing_key,
  merged_into_key   = EXCLUDED.merged_into_key,
  is_system         = EXCLUDED.is_system,
  lifecycle_status  = EXCLUDED.lifecycle_status,
  display_order     = EXCLUDED.display_order,
  updated_at        = now();

-- 6p: Reimbursement pairing keys
-- Set after all rows inserted to avoid circular FK at insert time.
-- DO UPDATE in 6b-6o resets pairing_key to NULL (EXCLUDED = NULL for most rows);
--   these UPDATEs then re-set the correct pairings. Net result: idempotent.
-- flexible_spending_2026: no paired category (same category for FSA charges + deposits);
--   reimbursement_pairing_key intentionally left NULL.

UPDATE categories SET reimbursement_pairing_key = 'business.jabian_deposits_2026',  updated_at = now()
WHERE key = 'business.jabian_expenses_2026';

UPDATE categories SET reimbursement_pairing_key = 'business.jabian_expenses_2026',  updated_at = now()
WHERE key = 'business.jabian_deposits_2026';

-- ─────────────────────────────────────────────────────────────────────────────
-- Block 7: budget_line_rules — Diablos and GLP Meds
-- Rent rows already correct: $5,300 end-dated 2026-06-01; $5,400 active 2026-07-01.
-- No rent migration needed. V5 confirms the existing state.
-- WHERE NOT EXISTS: safe to rerun regardless of unique constraint presence.
-- ─────────────────────────────────────────────────────────────────────────────

-- Diablos Preston Fee: $750/month, July–December 2026
INSERT INTO budget_line_rules (category_key, amount, start_month, end_month, is_active)
SELECT 'health_fitness.diablos_preston_fee', 750.00, '2026-07-01'::date, '2026-12-01'::date, true
WHERE NOT EXISTS (
  SELECT 1 FROM budget_line_rules
  WHERE category_key = 'health_fitness.diablos_preston_fee'
    AND start_month   = '2026-07-01'
    AND is_active     = true
);

-- Wendy GLP Meds: $404/month, August–December 2026
INSERT INTO budget_line_rules (category_key, amount, start_month, end_month, is_active)
SELECT 'health_fitness.wendy_glp_meds', 404.00, '2026-08-01'::date, '2026-12-01'::date, true
WHERE NOT EXISTS (
  SELECT 1 FROM budget_line_rules
  WHERE category_key = 'health_fitness.wendy_glp_meds'
    AND start_month   = '2026-08-01'
    AND is_active     = true
);

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════════
-- POST-MIGRATION VALIDATION QUERIES
-- Run AFTER the COMMIT in a separate execution. All must match expected results.
-- These are manual checks — not embedded in the migration transaction.
-- ═══════════════════════════════════════════════════════════════════════════════

-- V1: Tracked active leaf categories with NULL budget_line_key — expect 0 rows
SELECT key, budget_treatment FROM categories
WHERE is_leaf = true AND lifecycle_status = 'active' AND budget_treatment = 'tracked'
  AND budget_line_key IS NULL;

-- V2: Tracked active leaf categories whose budget_line_key has no active budget_line_rules row
-- Month-independent existence check — expect 0 rows
SELECT c.key, c.budget_line_key
FROM categories c
WHERE c.is_leaf = true AND c.lifecycle_status = 'active' AND c.budget_treatment = 'tracked'
  AND NOT EXISTS (
    SELECT 1 FROM budget_line_rules r
    WHERE r.category_key = c.budget_line_key AND r.is_active = true
  );

-- V3a: Diablos = $750 in July 2026 — expect 750.00
SELECT COALESCE(SUM(amount),0) AS diablos_july_2026 FROM budget_line_rules
WHERE category_key = 'health_fitness.diablos_preston_fee' AND is_active = true
  AND start_month <= '2026-07-01' AND (end_month IS NULL OR end_month >= '2026-07-01');

-- V3b: Diablos = $0 in January 2027 (post-expiry) — expect 0
SELECT COALESCE(SUM(amount),0) AS diablos_jan_2027 FROM budget_line_rules
WHERE category_key = 'health_fitness.diablos_preston_fee' AND is_active = true
  AND start_month <= '2027-01-01' AND (end_month IS NULL OR end_month >= '2027-01-01');

-- V4a: GLP Meds = $404 in August 2026 — expect 404.00
SELECT COALESCE(SUM(amount),0) AS glp_aug_2026 FROM budget_line_rules
WHERE category_key = 'health_fitness.wendy_glp_meds' AND is_active = true
  AND start_month <= '2026-08-01' AND (end_month IS NULL OR end_month >= '2026-08-01');

-- V4b: GLP Meds = $0 in January 2027 (post-expiry) — expect 0
SELECT COALESCE(SUM(amount),0) AS glp_jan_2027 FROM budget_line_rules
WHERE category_key = 'health_fitness.wendy_glp_meds' AND is_active = true
  AND start_month <= '2027-01-01' AND (end_month IS NULL OR end_month >= '2027-01-01');

-- V5: Rent state — expect: 5400 | 2026-07-01 | NULL  and  5300 | 2026-06-01 | 2026-06-01
SELECT amount, start_month, end_month FROM budget_line_rules
WHERE category_key = 'home.mortgage_rent' AND is_active = true
ORDER BY start_month DESC;

-- V6: Overlapping active budget_line_rules — expect 0 rows
SELECT a.category_key, a.start_month, a.end_month, b.start_month AS b_start, b.end_month AS b_end
FROM budget_line_rules a
JOIN budget_line_rules b
  ON a.category_key = b.category_key AND a.id != b.id
  AND a.is_active = true AND b.is_active = true
  AND a.start_month <= COALESCE(b.end_month, '9999-01-01'::date)
  AND COALESCE(a.end_month, '9999-01-01'::date) >= b.start_month;

-- V7: Active leaf categories missing any behavior field — expect 0 rows
SELECT key FROM categories
WHERE is_leaf = true AND lifecycle_status = 'active'
  AND (behavior_class IS NULL OR budget_treatment IS NULL OR cashflow_treatment IS NULL);

-- V8: Parent categories with non-null behavior fields — expect 0 rows
SELECT key, behavior_class FROM categories
WHERE is_leaf = false AND behavior_class IS NOT NULL;

-- V9: Tracked/display_only active leaf categories missing budget_group_key — expect 0 rows
SELECT key, budget_treatment FROM categories
WHERE is_leaf = true AND lifecycle_status = 'active'
  AND budget_treatment IN ('tracked','display_only')
  AND budget_group_key IS NULL;

-- V10: Account lifecycle counts — expect: active=12, hidden=1, view_only=1
SELECT lifecycle_status, COUNT(*) AS n FROM accounts
GROUP BY lifecycle_status ORDER BY lifecycle_status;

-- V11: Costco Visa hidden — expect: costco_visa | Costco Visa | hidden
SELECT key, label, lifecycle_status FROM accounts WHERE key = 'costco_visa';

-- V12: Category lifecycle counts (raw table) — expect: active=50, merged=1
SELECT lifecycle_status, COUNT(*) AS n FROM categories
GROUP BY lifecycle_status ORDER BY lifecycle_status;

-- V13: Reimbursement pairing keys — expect both rows to have non-null pairing keys
SELECT key, reimbursement_pairing_key FROM categories
WHERE key IN ('business.jabian_expenses_2026','business.jabian_deposits_2026');
-- Note: flexible_spending_2026 pairing_key is intentionally NULL (same-category FSA pattern).

-- V14: Merged row excluded from active registry — expect 1 row (the merged duplicate)
SELECT key, lifecycle_status FROM categories WHERE lifecycle_status != 'active';
-- Expect: business.jabian_2026_dup | merged

-- V15: Merged row does NOT appear in active registry (simulates _getActiveCategoryRegistry filter)
SELECT key FROM categories
WHERE key = 'business.jabian_2026_dup' AND lifecycle_status = 'active';
-- Expect: 0 rows
