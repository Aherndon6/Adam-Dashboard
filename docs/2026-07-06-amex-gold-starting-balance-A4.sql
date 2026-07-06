-- ============================================================================
-- 5F-1.5 A4: AMEX Gold starting-balance correction (data-only, balance-only)
-- REVISED 2026-07-06 (hardening pass 2). Supersedes
-- docs/2026-07-05-amex-gold-starting-balance.sql.
-- ============================================================================
-- Change history:
--   v1 (2026-07-05, superseded): wrong on two counts -- guarded/wrote POSITIVE
--     8248.07->8248.50 (column stores NEGATIVE), and used a "no tx before
--     2026-07-01" guard that blocked the legitimate 2026-06-30 Foxtail row.
--   v2 (2026-07-06, this file):
--     - Correct NEGATIVE values: -8248.07 -> -8248.50.
--     - Account scoped to the CANONICAL KEY 'amex_gold' (no ILIKE matcher),
--       plus a sanity guard that the pinned row still looks like AMEX Gold.
--     - Foxtail proven to be the FIRST ledger row by the Register's real order
--       (transaction_date ASC, created_at ASC, id ASC), not merely min(date).
--       Source: index.html Register fetch/balance order (lines ~5570, ~5710).
--
-- Confirmed old (wrong) value: -8248.07
-- Confirmed new (correct) value: -8248.50
-- Accounting anchor (Wendy): -8248.50 is the CLEARED balance as of end of
--   2026-06-29, BEFORE the 2026-06-30 Foxtail -7.17. Foxtail stays dated 6/30.
--   Running balance at the (first) Foxtail row: -8248.50 + -7.17 = -8255.67.
--
-- Treatment: balance-only. accounts.starting_balance is used ONLY by the
--   read-only Accounts table and the Register ledger opening balance. It does
--   NOT feed Budget spend, the 31-week cashflow model (runModel), or
--   reconciliation. Correcting it changes only the AMEX Gold Register running
--   balance display.
--
-- This script:
--   * touches ONLY the accounts table, ONLY the starting_balance column,
--     ONLY the single row WHERE key = 'amex_gold'.
--   * does NOT insert, update, or delete any transactions row.
--   * does NOT move or edit the 2026-06-30 Foxtail transaction.
--   * does NOT change any transaction date.
--   * does NOT change schema, RLS, RPC, application code, the Register write
--     path, or Budget calculations.
--
-- Canonical account selector (used identically everywhere below):
--     key = 'amex_gold'
--   If the live DB key is not 'amex_gold', preflight 1b/1c return no/!=1 row
--   and the Section 3 DO block aborts. We STOP rather than broaden the match.
--
-- Foxtail definition (the FIRST ledger row):
--     first row of (account_key = 'amex_gold'
--                   ORDER BY transaction_date ASC, created_at ASC, id ASC)
--     must be: transaction_date = 2026-06-30, amount = -7.17,
--              payee ILIKE '%foxtail%' OR memo ILIKE '%foxtail%'
--
-- ----------------------------------------------------------------------------
-- RUNBOOK (Supabase SQL editor friendly; a persistent session is NOT assumed):
--   Step 1: Run SECTION 1 (read-only preflight) by itself.
--   Step 2: Review every output against the STOP conditions below.
--   Step 3: If all preflight checks match, run SECTION 3 as ONE execution. It
--           is a single self-contained transaction: BEGIN ... DO (all guards +
--           update + postflight assertions) ... COMMIT, all in one run. Do NOT
--           split BEGIN and COMMIT across separate executions.
--   Step 4: If any DO-block assertion fails, the transaction aborts and the
--           trailing COMMIT commits nothing (an aborted tx rolls back). No
--           partial change is possible. Fix the cause and re-run.
--   Step 5: Run SECTION 4 (read-only verification).
--   Rollback: SECTION 5 is DISABLED (block comment) and reverts a COMMITTED
--           change only. Copy the SQL out of the /* ... */ block to use it.
-- ----------------------------------------------------------------------------
-- ============================================================================


-- ============================================================================
-- SECTION 1: PREFLIGHT (read-only). Review every result before Section 3.
-- ============================================================================

-- 1a. Column type. Exact equality guards (= -8248.07 / -8248.50) are only safe
--     for exact numeric types. STOP unless data_type = 'numeric' AND udt_name
--     = 'numeric'. If it is double precision / real / float, STOP and report.
SELECT data_type, numeric_precision, numeric_scale, udt_name
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'accounts'
  AND  column_name  = 'starting_balance';

-- 1b. The pinned AMEX Gold account row (human verification).
--     STOP unless this returns exactly ONE row AND it is clearly AMEX Gold.
SELECT key, label, institution, account_type, lifecycle_status,
       starting_balance, include_in_budget, include_in_cashflow,
       display_order, notes
FROM   accounts
WHERE  key = 'amex_gold';

-- 1c. Pinned-key count guard. STOP unless account_count = 1.
SELECT count(*) AS account_count
FROM   accounts
WHERE  key = 'amex_gold';

-- 1d. Confirm the existing starting_balance is exactly -8248.07.
--     STOP unless existing_value_ok = true.
SELECT (starting_balance = -8248.07) AS existing_value_ok,
       starting_balance              AS current_starting_balance
FROM   accounts
WHERE  key = 'amex_gold';

-- 1e. AMEX Gold ledger shape. Note tx_count / first_tx / last_tx / net_amount
--     and the timestamps (compared again in Section 4 to prove no tx changed).
SELECT count(*)                AS tx_count,
       min(transaction_date)   AS first_tx,
       max(transaction_date)   AS last_tx,
       coalesce(sum(amount),0) AS net_amount_since_start,
       max(created_at)         AS last_created_at,
       max(updated_at)         AS last_updated_at
FROM   transactions
WHERE  account_key = 'amex_gold';

-- 1f. FIRST ledger row by the Register's real order. STOP unless this row is
--     the Foxtail row: date 2026-06-30, amount -7.17, payee/memo ~ 'foxtail'.
--     This proves Foxtail is row #1 (so the checkpoint below is valid) even if
--     other 2026-06-30 rows exist after it.
SELECT id, transaction_date, amount, payee, memo, created_at, updated_at
FROM   transactions
WHERE  account_key = 'amex_gold'
ORDER  BY transaction_date ASC, created_at ASC, id ASC
LIMIT  1;

-- Do not proceed unless: 1a data_type='numeric' AND udt_name='numeric';
-- 1b exactly one row and clearly AMEX Gold; 1c account_count=1;
-- 1d existing_value_ok=true; 1f first row is Foxtail (2026-06-30, -7.17).
-- The Section 3 DO block re-checks all of these and aborts on any violation.


-- ============================================================================
-- SECTION 3: PATCH. Run this ENTIRE section as ONE execution. It is a single
-- self-contained transaction (BEGIN ... DO ... COMMIT). Every go/no-go is
-- enforced IN SQL; the DO block RAISE EXCEPTIONs on any violation, which aborts
-- the transaction so the trailing COMMIT commits nothing. Do NOT split BEGIN
-- and COMMIT across separate editor runs (no cross-execution session assumed).
-- ============================================================================

BEGIN;

DO $$
DECLARE
  v_dtype        text;
  v_udt          text;
  v_n            int;
  v_key          text;
  v_label        text;
  v_inst         text;
  v_cur          numeric;
  v_txcount_pre  int;
  v_txcount_post int;
  v_fox_id       text;
  v_fox_amt      numeric;
  v_fox_date     date;
  v_fox_payee    text;
  v_fox_memo     text;
  v_fox_upd_pre  timestamptz;
  v_first_id     text;
  v_new          numeric;
  v_after_fox    numeric;
  v_rows         int;
BEGIN
  -- column type must be exact numeric, or exact-compare guards are unsafe
  SELECT data_type, udt_name INTO v_dtype, v_udt
  FROM   information_schema.columns
  WHERE  table_schema = 'public' AND table_name = 'accounts'
    AND  column_name = 'starting_balance';
  IF v_dtype IS DISTINCT FROM 'numeric' OR v_udt IS DISTINCT FROM 'numeric' THEN
    RAISE EXCEPTION 'A4 abort: accounts.starting_balance is data_type=% udt=%, expected numeric/numeric (exact-compare unsafe)', v_dtype, v_udt;
  END IF;

  -- exactly one account with the canonical key
  SELECT count(*) INTO v_n FROM accounts WHERE key = 'amex_gold';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A4 abort: expected exactly 1 account with key=amex_gold, found % (STOP; do not broaden the match)', v_n;
  END IF;

  -- resolve the pinned row
  SELECT key, label, institution, starting_balance
    INTO v_key, v_label, v_inst, v_cur
  FROM   accounts WHERE key = 'amex_gold';

  -- defense in depth: the pinned key must still look like AMEX Gold
  IF NOT ( (v_label ILIKE '%gold%' OR v_key ILIKE '%gold%')
           AND ( v_label ILIKE '%amex%' OR v_label ILIKE '%american express%'
                 OR v_inst ILIKE '%amex%' OR v_inst ILIKE '%american express%'
                 OR v_key ILIKE '%amex%' ) ) THEN
    RAISE EXCEPTION 'A4 abort: key=amex_gold does not look like AMEX Gold (label=%, institution=%)', v_label, v_inst;
  END IF;

  -- current value must be exactly -8248.07
  IF v_cur IS DISTINCT FROM -8248.07 THEN
    RAISE EXCEPTION 'A4 abort: current starting_balance is %, expected -8248.07 (key %)', v_cur, v_key;
  END IF;

  -- FIRST ledger row (Register order) must be the Foxtail row. Capture its id
  -- so every Foxtail immutability check below tracks that exact row.
  SELECT id::text, transaction_date, amount, payee, memo, updated_at
    INTO v_fox_id, v_fox_date, v_fox_amt, v_fox_payee, v_fox_memo, v_fox_upd_pre
  FROM   transactions
  WHERE  account_key = 'amex_gold'
  ORDER  BY transaction_date ASC, created_at ASC, id ASC
  LIMIT  1;
  IF v_fox_id IS NULL THEN
    RAISE EXCEPTION 'A4 abort: AMEX Gold has no transactions; expected first row to be Foxtail';
  END IF;
  IF v_fox_date IS DISTINCT FROM DATE '2026-06-30'
     OR v_fox_amt IS DISTINCT FROM -7.17
     OR NOT (coalesce(v_fox_payee,'') ILIKE '%foxtail%' OR coalesce(v_fox_memo,'') ILIKE '%foxtail%') THEN
    RAISE EXCEPTION 'A4 abort: first ledger row is not Foxtail (id=% date=% amount=% payee=% memo=%)', v_fox_id, v_fox_date, v_fox_amt, v_fox_payee, v_fox_memo;
  END IF;

  -- capture tx count before the update (must be unchanged after)
  SELECT count(*) INTO v_txcount_pre FROM transactions WHERE account_key = 'amex_gold';

  -- apply, scoped to the pinned key and guarded on the old value
  UPDATE accounts
  SET    starting_balance = -8248.50
  WHERE  key = 'amex_gold'
    AND  starting_balance = -8248.07;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'A4 abort: expected to update exactly 1 row, updated % (key amex_gold)', v_rows;
  END IF;

  -- POSTFLIGHT ASSERTIONS (still inside the transaction; abort before COMMIT).

  -- new value must be exactly -8248.50
  SELECT starting_balance INTO v_new FROM accounts WHERE key = 'amex_gold';
  IF v_new IS DISTINCT FROM -8248.50 THEN
    RAISE EXCEPTION 'A4 abort: post-update starting_balance is %, expected -8248.50', v_new;
  END IF;

  -- running balance AT the first (Foxtail) row = starting_balance + Foxtail amt
  v_after_fox := v_new + v_fox_amt;
  IF v_after_fox IS DISTINCT FROM -8255.67 THEN
    RAISE EXCEPTION 'A4 abort: ledger check failed, -8248.50 + (%) = %, expected -8255.67', v_fox_amt, v_after_fox;
  END IF;

  -- Foxtail is STILL the first ledger row, same id, and unchanged
  SELECT id::text INTO v_first_id
  FROM   transactions
  WHERE  account_key = 'amex_gold'
  ORDER  BY transaction_date ASC, created_at ASC, id ASC
  LIMIT  1;
  IF v_first_id IS DISTINCT FROM v_fox_id THEN
    RAISE EXCEPTION 'A4 abort: first ledger row changed from % to % during patch', v_fox_id, v_first_id;
  END IF;

  -- the tracked Foxtail row's date/amount/updated_at are unchanged (not edited)
  PERFORM 1 FROM transactions
   WHERE id::text = v_fox_id
     AND transaction_date = DATE '2026-06-30'
     AND amount = -7.17
     AND updated_at IS NOT DISTINCT FROM v_fox_upd_pre;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'A4 abort: Foxtail row % changed during patch (date/amount/updated_at)', v_fox_id;
  END IF;

  -- tx count unchanged
  SELECT count(*) INTO v_txcount_post FROM transactions WHERE account_key = 'amex_gold';
  IF v_txcount_post <> v_txcount_pre THEN
    RAISE EXCEPTION 'A4 abort: AMEX Gold tx count changed % -> %', v_txcount_pre, v_txcount_post;
  END IF;

  RAISE NOTICE 'A4 OK: account amex_gold starting_balance -8248.07 -> -8248.50; Foxtail row % is first and intact; ledger at Foxtail = -8255.67; tx_count % unchanged (rows=%)', v_fox_id, v_txcount_post, v_rows;
END $$;

-- Preview the pending (uncommitted) change before deciding.
SELECT key, label, starting_balance AS pending_starting_balance
FROM   accounts
WHERE  key = 'amex_gold';

-- The preview above (pending_starting_balance = -8248.50) is informational; it
-- runs inside the still-open transaction. The COMMIT below finalizes it in the
-- SAME execution. If any assertion failed, execution never reaches here and the
-- transaction is already aborted, so this COMMIT commits nothing.
COMMIT;

-- To undo a COMMITTED change, use SECTION 5 (rollback), not this section.


-- ============================================================================
-- SECTION 4: VERIFICATION (read-only, run after COMMIT).
-- ============================================================================

-- 4a. The AMEX Gold row now holds -8248.50 (value_ok = true).
SELECT key, label, starting_balance,
       (starting_balance = -8248.50) AS value_ok
FROM   accounts
WHERE  key = 'amex_gold';

-- 4b. Running balance at the first (Foxtail) row (the confirmed checkpoint)
--     plus the full computed current balance (informational, not pinned to a
--     constant since later rows move it). ledger_at_foxtail_ok MUST be true.
WITH fox AS (
  SELECT amount
  FROM   transactions
  WHERE  account_key = 'amex_gold'
  ORDER  BY transaction_date ASC, created_at ASC, id ASC
  LIMIT  1
)
SELECT a.key, a.label, a.starting_balance,
       (SELECT amount FROM fox)                          AS first_row_amount,
       a.starting_balance + (SELECT amount FROM fox)     AS ledger_at_foxtail,
       (a.starting_balance + (SELECT amount FROM fox) = -8255.67) AS ledger_at_foxtail_ok,
       coalesce((SELECT sum(t.amount) FROM transactions t WHERE t.account_key = a.key), 0)
         AS net_amount_since_start,
       a.starting_balance
       + coalesce((SELECT sum(t.amount) FROM transactions t WHERE t.account_key = a.key), 0)
         AS computed_current_balance
FROM   accounts a
WHERE  a.key = 'amex_gold';

-- 4c. Confirm no transactions were inserted/updated/deleted by this script, and
--     the first ledger row is still Foxtail. Compare tx_count / last_created_at
--     / last_updated_at to Section 1e; first_row_* to Section 1f.
SELECT (SELECT count(*)        FROM transactions WHERE account_key='amex_gold') AS tx_count,
       (SELECT max(created_at) FROM transactions WHERE account_key='amex_gold') AS last_created_at,
       (SELECT max(updated_at) FROM transactions WHERE account_key='amex_gold') AS last_updated_at,
       f.transaction_date AS first_row_date,
       f.amount           AS first_row_amount,
       f.payee            AS first_row_payee
FROM (
  SELECT transaction_date, amount, payee
  FROM   transactions
  WHERE  account_key = 'amex_gold'
  ORDER  BY transaction_date ASC, created_at ASC, id ASC
  LIMIT  1
) f;


-- ============================================================================
-- SECTION 5: ROLLBACK -- DISABLED BY DEFAULT (DO NOT run top-to-bottom).
-- ----------------------------------------------------------------------------
-- The entire rollback is wrapped in a block comment so a full-file run CANNOT
-- execute it. To revert -8248.50 back to -8248.07, deliberately copy the SQL
-- between the /* ROLLBACK-BEGIN and ROLLBACK-END */ markers into a new editor
-- tab and run it. It enforces the same guards: pinned key, current value
-- -8248.50, exactly one row updated. It does NOT touch any transaction.
-- ============================================================================

/* ROLLBACK-BEGIN  (copy the lines below this marker, excluding the markers)

BEGIN;

DO $ROLLBACK$
DECLARE
  v_n    int;
  v_cur  numeric;
  v_rows int;
BEGIN
  SELECT count(*) INTO v_n FROM accounts WHERE key = 'amex_gold';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A4 rollback abort: expected exactly 1 account with key=amex_gold, found %', v_n;
  END IF;

  SELECT starting_balance INTO v_cur FROM accounts WHERE key = 'amex_gold';
  IF v_cur IS DISTINCT FROM -8248.50 THEN
    RAISE EXCEPTION 'A4 rollback abort: current starting_balance is %, expected -8248.50', v_cur;
  END IF;

  UPDATE accounts
  SET    starting_balance = -8248.07
  WHERE  key = 'amex_gold'
    AND  starting_balance = -8248.50;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'A4 rollback abort: expected to update exactly 1 row, updated %', v_rows;
  END IF;

  RAISE NOTICE 'A4 ROLLBACK OK: account amex_gold starting_balance -8248.50 -> -8248.07 (rows=%)', v_rows;
END $ROLLBACK$;

SELECT key, label, starting_balance AS reverted_starting_balance
FROM   accounts
WHERE  key = 'amex_gold';

-- Expect NOTICE 'A4 ROLLBACK OK ...' and reverted_starting_balance = -8248.07.
-- Then run COMMIT;  (or ROLLBACK; to abort the revert.)

ROLLBACK-END */
