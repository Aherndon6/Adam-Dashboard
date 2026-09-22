-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- income.extra_pay — "Adam Extra Pay"
-- Requested by Wendy 2026-09-22: only budgeted salaries may sit in Net Salary / Net Salary Spouse;
-- net pay above the budgeted base gets its own category.
-- Owner decisions 2026-09-22: key income.extra_pay, label "Adam Extra Pay",
--   Wendy's income.bkcpa_extra_pay left untouched, budgeted base for Adam = $5,816.50,
--   no retroactive splitting of history ("start clean going forward").
--
-- SEQUENCING — THIS MUST NOT RUN BEFORE THE 2026-09-26 A1b SITTING.
--   The frozen A1b drift-check.sql carries a 4-key exclusion list. A fifth active income leaf that
--   is neither represented in the 41-entry registry nor excluded is an INV-C violation, which
--   turns the A1b verdict from PASS to HOLD and flips every month's expected display state from
--   VERIFIED to UNVERIFIED. Run this only in the Release A sitting, together with the matching
--   BUDGET_INCOME_EXCLUSIONS code change and the regenerated drift-check.sql excl list.
--
-- STAGING FIRST (AGENTS.md). No direct prod DDL/DML without owner authorization at the time.
-- This is DML on `categories`; it adds one row and changes no existing row.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Preflight: refuse if the world is not what this script was written against ──────────────────
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM categories WHERE key = 'income.extra_pay';
  IF n <> 0 THEN RAISE EXCEPTION 'PREFLIGHT FAIL: income.extra_pay already exists (n=%)', n; END IF;

  SELECT count(*) INTO n FROM categories WHERE key = 'income' AND is_leaf IS false AND lifecycle_status = 'active';
  IF n <> 1 THEN RAISE EXCEPTION 'PREFLIGHT FAIL: active non-leaf parent "income" not found (n=%)', n; END IF;

  -- Wendy's sibling category must be present and untouched; this script must never disturb it.
  SELECT count(*) INTO n FROM categories
   WHERE key = 'income.bkcpa_extra_pay' AND label = 'Wendy Extra BK Pay' AND lifecycle_status = 'active';
  IF n <> 1 THEN RAISE EXCEPTION 'PREFLIGHT FAIL: income.bkcpa_extra_pay is not in its expected state (n=%)', n; END IF;

  -- display_order 1045 must be free (it seats Adam Extra Pay directly below Wendy Extra BK Pay,
  -- keeping the two budgeted-salary lines adjacent at 1010/1020).
  SELECT count(*) INTO n FROM categories WHERE parent_key = 'income' AND display_order = 1045;
  IF n <> 0 THEN RAISE EXCEPTION 'PREFLIGHT FAIL: display_order 1045 already taken under income (n=%)', n; END IF;
END $$;

-- ── The change: exactly one row ─────────────────────────────────────────────────────────────────
INSERT INTO categories
  (key,               label,             parent_key, is_leaf, behavior_class, budget_treatment,
   cashflow_treatment, is_system, lifecycle_status, display_order)
VALUES
  ('income.extra_pay','Adam Extra Pay',  'income',   true,    'income',       'display_only',
   'operating',        false,     'active',         1045);

-- ── Postflight: assert inside the transaction, so a wrong result rolls back ─────────────────────
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM categories
   WHERE key = 'income.extra_pay' AND label = 'Adam Extra Pay' AND parent_key = 'income'
     AND is_leaf IS true AND behavior_class = 'income' AND budget_treatment = 'display_only'
     AND cashflow_treatment = 'operating' AND is_system IS false AND lifecycle_status = 'active'
     AND display_order = 1045;
  IF n <> 1 THEN RAISE EXCEPTION 'POSTFLIGHT FAIL: income.extra_pay not created as specified (n=%)', n; END IF;

  -- Income leaves must now be exactly six, and Wendy's row must be byte-for-byte as it was.
  SELECT count(*) INTO n FROM categories WHERE parent_key = 'income' AND is_leaf IS true;
  IF n <> 6 THEN RAISE EXCEPTION 'POSTFLIGHT FAIL: expected 6 income leaves, found %', n; END IF;

  SELECT count(*) INTO n FROM categories
   WHERE key = 'income.bkcpa_extra_pay' AND label = 'Wendy Extra BK Pay'
     AND behavior_class = 'income' AND budget_treatment = 'display_only'
     AND lifecycle_status = 'active' AND display_order = 1040;
  IF n <> 1 THEN RAISE EXCEPTION 'POSTFLIGHT FAIL: income.bkcpa_extra_pay was disturbed (n=%)', n; END IF;

  -- No transaction may have been recategorised by this script.
  SELECT count(*) INTO n FROM transactions WHERE category_key = 'income.extra_pay';
  IF n <> 0 THEN RAISE EXCEPTION 'POSTFLIGHT FAIL: this script must not move transactions (n=%)', n; END IF;
END $$;

COMMIT;

-- Verification (run after COMMIT):
-- SELECT key, label, parent_key, behavior_class, budget_treatment, lifecycle_status, display_order
--   FROM categories WHERE parent_key = 'income' ORDER BY display_order;
