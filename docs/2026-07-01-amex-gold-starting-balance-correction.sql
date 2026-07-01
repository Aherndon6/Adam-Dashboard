-- ============================================================
-- AMEX Gold starting balance correction — 5E-8 Wendy readiness
-- Owner-run only, via Supabase SQL editor. NOT app code.
-- No schema, RLS, or table changes. Affects one row in
-- public.accounts (key = 'amex_gold') only.
--
-- GATE: Step 1 is conditional on Step 0b returning 0. Do not run
-- Step 1 if amex_gold already has transactions.
--
-- SEQUENCING:
--   1. Run Step 0 (pre-flight).
--   2. If 0b = 0, run Step 1 (update).
--   3. Run Step 2 (verify).
--   4. Only then have Wendy enter, in-app (not SQL):
--        - Diablos, $750 outflow, account = AMEX Gold, date = 7/1/26
--          memo: "Posted in June; assigned to July budget."
--        - Fandango, $40 outflow, account = AMEX Gold, date = 7/1/26
--          memo: "Posted in June; assigned to July budget."
--      If these are entered before the update, the register will
--      briefly show a double-counted balance (-9038.07 minus
--      another 790.00).
-- ============================================================

-- STEP 0 — Pre-flight. Run first and read the output before
-- proceeding to Step 1.

-- 0a. Confirm current state.
SELECT key, label, starting_balance, starting_balance_as_of,
       starting_balance_source, starting_balance_note, updated_at
FROM public.accounts
WHERE key = 'amex_gold';
-- Expect: starting_balance = -9038.07 before this script runs.

-- 0b. Confirm no transactions exist yet against amex_gold.
-- Changing starting_balance after transactions exist silently
-- shifts every already-computed running balance for the account
-- (see docs/phase-5c-architecture-design.md, REG-RLS-OWNER-2A).
-- This should return 0. If it does not, STOP — do not run Step 1
-- without first understanding the downstream balance impact on
-- existing amex_gold transactions.
SELECT count(*) AS existing_amex_gold_transactions
FROM public.transactions
WHERE account_key = 'amex_gold';

-- STEP 1 — Apply the correction. Only run after 0a/0b look right.

UPDATE public.accounts
SET
  starting_balance = -8248.07,
  starting_balance_as_of = '2026-07-01',
  starting_balance_source = 'online_account',
  starting_balance_note = 'Adjusted during 5E-8 Wendy readiness: original online balance was -9038.07; excluded $790 of June-posted charges intentionally entered as 7/1 July budget transactions ($750 Diablos, $40 Fandango).'
WHERE key = 'amex_gold';

-- STEP 2 — Verify. No other account row should show a changed
-- updated_at from this script.

SELECT key, label, starting_balance, starting_balance_as_of,
       starting_balance_source, starting_balance_note, updated_at
FROM public.accounts
WHERE key = 'amex_gold';
-- Expect: starting_balance = -8248.07, note as above, updated_at bumped.
