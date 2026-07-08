-- ═══════════════════════════════════════════════════════════════════════════
-- Herndon Financial OS — Phase 5G-1 RLS Behavioral Smoke — GATE 1 (policy-level)
-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — STAGING ONLY (project pkwotgqivgaapwuqgwqb). DO NOT RUN on production
-- (usayoldrawwmjsmretin). Run AFTER re-applying phase-5g-1-migration.sql on a
-- freshly-marked staging DB, and AFTER seeding the two [STAGING] app_users rows.
--
-- WHAT THIS IS: a POLICY-LEVEL RLS smoke via SET LOCAL ROLE + request.jwt.claims,
-- entirely inside one transaction that ROLLS BACK. It proves policy predicates,
-- USING/WITH CHECK, GRANTs, TRUNCATE protection, and triggers as the impersonated
-- role. It is NOT a complete real-caller smoke — the Auth/JWT/PostgREST path is
-- Gate 2 (phase-5g-1-rls-smoke-gate2). RLS is not "cleared" until Gate 2 passes.
--
-- SAFETY: outer BEGIN/ROLLBACK — nothing here persists. Every expected-error probe
-- is caught with an inner BEGIN/EXCEPTION so it cannot poison the transaction.
-- Any deviation from the expected matrix RAISEs EXCEPTION and aborts loudly.
--
-- PROBE HARDENING (why the probes look the way they do):
--   * DETERMINISTIC PARENT IDs (D1): the ground-truth plan is seeded with a fixed
--     literal id so outflow_events probes reference it via VALUES(...) — never via
--     an RLS-filtered subquery (a subquery returns 0 rows to a caller who cannot
--     read the parent, turning a denial test into a silent 0-row no-op).
--   * NARROW EXCEPTIONS (D2): RLS/grant denials are caught as `insufficient_privilege`
--     (SQLSTATE 42501 — both grant-denied and RLS WITH CHECK violations use it), so an
--     unrelated failure (FK/constraint) cannot masquerade as an expected denial. The
--     immutability case catches OTHERS but re-RAISEs unless SQLERRM mentions "immutable".
--   * ISOLATE RLS FROM FK: expected-denial INSERTs set created_by_user_id = NULL, so
--     the ONLY possible rejection is RLS (a NULL FK column is not FK-checked).
--   * NULL-SAFE POST-CHECKS (D4): "unchanged" checks use IF NOT FOUND + counts so a
--     deletion cannot pass silently.
--
-- HARNESS SELF-CHECK: each identity block first asserts current_user and
-- auth.uid()/auth.jwt()->>'email' actually reflect the intended identity. If the
-- role/claims plumbing did not take effect, the block aborts — a green matrix on a
-- broken harness would be meaningless. On FIRST run, confirm the "harness ok"
-- NOTICEs appear before trusting any PASS.
--
-- BEFORE RUNNING, replace the four tokens below (staging values only). To keep real
-- staging identifiers OUT of git (D10), fill them into a LOCAL/scratch copy or via
-- psql \set — do not commit real UUIDs/emails into this file:
--   <<W_UUID>>      auth.users id of the [STAGING] writer  (role household_admin)
--   <<W_EMAIL>>     email of the [STAGING] writer          (matches app_users)
--   <<V_UUID>>      auth.users id of the [STAGING] viewer  (role viewer)
--   <<V_EMAIL>>     email of the [STAGING] viewer          (matches app_users)
-- ─────────────────────────────────────────────────────────────────────────
SET search_path TO public;

BEGIN;

-- ── STAGING GUARD (identical hard-stops to the migration/rollback) ───────────
DO $$
DECLARE v_is_staging BOOLEAN; v_bal NUMERIC(12,2); v_tx BIGINT;
BEGIN
  IF to_regclass('public.app_environment') IS NULL THEN RAISE EXCEPTION 'HARD STOP: app_environment missing. Aborting.'; END IF;
  IF to_regclass('public.planned_outflows') IS NULL OR to_regclass('public.outflow_events') IS NULL THEN
    RAISE EXCEPTION 'HARD STOP: 5G-1 tables absent. Re-apply phase-5g-1-migration.sql before the smoke. Aborting.'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.app_environment WHERE env='staging') INTO v_is_staging;
  IF NOT v_is_staging THEN RAISE EXCEPTION 'HARD STOP: app_environment.env<>staging. Aborting.'; END IF;
  SELECT starting_balance INTO v_bal FROM public.accounts WHERE key='amex_gold';
  IF NOT FOUND THEN RAISE EXCEPTION 'HARD STOP: staging baseline incomplete (accounts.amex_gold missing). Aborting.'; END IF;
  IF v_bal = -8248.50 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (amex_gold=-8248.50). Aborting.'; END IF;
  SELECT count(*) INTO v_tx FROM public.transactions;
  IF v_tx > 25 THEN RAISE EXCEPTION 'HARD STOP: production fingerprint (transactions=% > 25). Aborting.', v_tx; END IF;
END $$;

-- ── IDENTITY PREREQ: the two [STAGING] app_users rows + auth.users rows exist ─
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.app_users
                 WHERE auth_user_id = '<<W_UUID>>' AND lower(email)=lower('<<W_EMAIL>>')
                   AND active AND role IN ('owner','household_admin')) THEN
    RAISE EXCEPTION 'HARD STOP: writer app_users row missing/misconfigured (uuid/email/active/role). Aborting.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.app_users
                 WHERE auth_user_id = '<<V_UUID>>' AND lower(email)=lower('<<V_EMAIL>>')
                   AND active AND role = 'viewer') THEN
    RAISE EXCEPTION 'HARD STOP: viewer app_users row missing/misconfigured (must be active, role=viewer). Aborting.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id='<<W_UUID>>') THEN
    RAISE EXCEPTION 'HARD STOP: writer auth.users row <<W_UUID>> missing (FK target for created_by_user_id). Aborting.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id='<<V_UUID>>') THEN
    RAISE EXCEPTION 'HARD STOP: viewer auth.users row <<V_UUID>> missing. Aborting.';
  END IF;
  RAISE NOTICE 'PREREQ ok: writer + viewer identities present and configured.';
END $$;

-- ── PRE-SMOKE EXACT GRANT + TRUNCATE ASSERTIONS (run as owner) ───────────────
-- Re-assert on this fresh migration application (the rehearsal run was rolled back).
DO $$
DECLARE g TEXT[];
BEGIN
  -- anon: zero privileges on both tables (covers DELETE/REFERENCES/TRIGGER transitively)
  SELECT array_agg(privilege_type ORDER BY privilege_type) INTO g
    FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name IN ('planned_outflows','outflow_events') AND grantee='anon';
  IF g IS NOT NULL THEN RAISE EXCEPTION 'GRANT FAIL: anon has privileges % (expected none).', g; END IF;

  -- authenticated on planned_outflows: EXACTLY {SELECT,INSERT,UPDATE}
  SELECT array_agg(privilege_type::text ORDER BY privilege_type::text) INTO g
    FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name='planned_outflows' AND grantee='authenticated';
  IF g IS DISTINCT FROM ARRAY['INSERT','SELECT','UPDATE']::text[] THEN
    RAISE EXCEPTION 'GRANT FAIL: planned_outflows authenticated grants = % (expected INSERT,SELECT,UPDATE).', g; END IF;

  -- authenticated on outflow_events: EXACTLY {SELECT,INSERT}
  SELECT array_agg(privilege_type::text ORDER BY privilege_type::text) INTO g
    FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name='outflow_events' AND grantee='authenticated';
  IF g IS DISTINCT FROM ARRAY['INSERT','SELECT']::text[] THEN
    RAISE EXCEPTION 'GRANT FAIL: outflow_events authenticated grants = % (expected INSERT,SELECT).', g; END IF;

  -- has_table_privilege: DELETE/TRUNCATE/REFERENCES/TRIGGER must be FALSE for anon+authenticated on both tables
  IF has_table_privilege('authenticated','public.planned_outflows','DELETE')    THEN RAISE EXCEPTION 'GRANT FAIL: authenticated DELETE on planned_outflows.'; END IF;
  IF has_table_privilege('authenticated','public.planned_outflows','TRUNCATE')  THEN RAISE EXCEPTION 'GRANT FAIL: authenticated TRUNCATE on planned_outflows.'; END IF;
  IF has_table_privilege('authenticated','public.planned_outflows','REFERENCES')THEN RAISE EXCEPTION 'GRANT FAIL: authenticated REFERENCES on planned_outflows.'; END IF;
  IF has_table_privilege('authenticated','public.planned_outflows','TRIGGER')   THEN RAISE EXCEPTION 'GRANT FAIL: authenticated TRIGGER on planned_outflows.'; END IF;
  IF has_table_privilege('authenticated','public.outflow_events','DELETE')      THEN RAISE EXCEPTION 'GRANT FAIL: authenticated DELETE on outflow_events.'; END IF;
  IF has_table_privilege('authenticated','public.outflow_events','TRUNCATE')    THEN RAISE EXCEPTION 'GRANT FAIL: authenticated TRUNCATE on outflow_events.'; END IF;
  IF has_table_privilege('authenticated','public.outflow_events','REFERENCES')  THEN RAISE EXCEPTION 'GRANT FAIL: authenticated REFERENCES on outflow_events.'; END IF;
  IF has_table_privilege('authenticated','public.outflow_events','TRIGGER')     THEN RAISE EXCEPTION 'GRANT FAIL: authenticated TRIGGER on outflow_events.'; END IF;
  IF has_table_privilege('anon','public.planned_outflows','DELETE')             THEN RAISE EXCEPTION 'GRANT FAIL: anon DELETE on planned_outflows.'; END IF;
  IF has_table_privilege('anon','public.planned_outflows','TRUNCATE')           THEN RAISE EXCEPTION 'GRANT FAIL: anon TRUNCATE on planned_outflows.'; END IF;
  IF has_table_privilege('anon','public.outflow_events','DELETE')               THEN RAISE EXCEPTION 'GRANT FAIL: anon DELETE on outflow_events.'; END IF;
  IF has_table_privilege('anon','public.outflow_events','TRUNCATE')             THEN RAISE EXCEPTION 'GRANT FAIL: anon TRUNCATE on outflow_events.'; END IF;
  RAISE NOTICE 'GRANTS ok: exact authenticated set; anon empty; no DELETE/TRUNCATE/REFERENCES/TRIGGER.';
END $$;

-- ── GROUND-TRUTH SEED (owner insert; bypasses RLS by design) ─────────────────
-- Deterministic literal ids (D1) so OE probes reference them via VALUES(...) with
-- no read-visibility dependency. created_by_user_id set explicitly to the writer
-- (FK-valid). Rolled back with the outer transaction.
--   __smoke_target__  = 00000000-0000-0000-0000-0000000000d1
INSERT INTO public.planned_outflows
  (id,key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key,created_by_user_id)
VALUES ('00000000-0000-0000-0000-0000000000d1','__smoke_target__','SMOKE target','save_up_bill', DATE '2027-05-01',
        'transfer_funded','amex_savings','truist_checking','<<W_UUID>>');
INSERT INTO public.outflow_events
  (planned_outflow_id,event_type,amount_cents,event_date,funding_account_key,created_by_user_id)
VALUES ('00000000-0000-0000-0000-0000000000d1','set_aside',1000, DATE '2027-05-01','amex_savings','<<W_UUID>>');

-- ══════════════════════════════════════════════════════════════════════════
-- D — ANON  (SET ROLE anon, no claims): every operation permission-denied
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE ok BOOLEAN;
BEGIN
  PERFORM set_config('role','anon', true);
  PERFORM set_config('request.jwt.claims', '', true);   -- D5: empty, not NULL
  IF current_user <> 'anon' THEN RAISE EXCEPTION 'harness: anon role not applied (current_user=%).', current_user; END IF;

  ok := true;
  BEGIN PERFORM 1 FROM public.planned_outflows LIMIT 1; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON FAIL: SELECT planned_outflows was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN PERFORM 1 FROM public.outflow_events LIMIT 1; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON FAIL: SELECT outflow_events was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN INSERT INTO public.planned_outflows (key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key,created_by_user_id)
          VALUES ('__anon__','x','save_up_bill',DATE '2027-05-01','transfer_funded','amex_savings','truist_checking',NULL);
    ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON FAIL: INSERT planned_outflows was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN TRUNCATE public.planned_outflows; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON FAIL: TRUNCATE planned_outflows was NOT permission-denied.'; END IF;
  RAISE NOTICE 'D ANON PASS: harness ok; all ops permission-denied.';
END $$;
RESET ROLE;

-- ══════════════════════════════════════════════════════════════════════════
-- C — UNAUTHORIZED AUTHENTICATED (valid claims, email NOT in app_users)
--   SELECT -> 0 rows (silent, no error); INSERT -> RLS violation (42501)
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE cnt INT; ok BOOLEAN;
BEGIN
  PERFORM set_config('role','authenticated', true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000000cc","email":"nobody-not-allowlisted@herndons.test","role":"authenticated"}', true);
  IF current_user <> 'authenticated' THEN RAISE EXCEPTION 'harness: authenticated role not applied.'; END IF;
  IF (auth.jwt()->>'email') <> 'nobody-not-allowlisted@herndons.test' THEN RAISE EXCEPTION 'harness: email claim not applied.'; END IF;

  -- read filter: must see 0 of the seeded target row (which DOES exist) -> proves RLS is live
  SELECT count(*) INTO cnt FROM public.planned_outflows;  IF cnt <> 0 THEN RAISE EXCEPTION 'UNAUTH FAIL: PO SELECT leaked % rows (expected 0).', cnt; END IF;
  SELECT count(*) INTO cnt FROM public.outflow_events;    IF cnt <> 0 THEN RAISE EXCEPTION 'UNAUTH FAIL: OE SELECT leaked % rows (expected 0).', cnt; END IF;

  -- INSERT denials: created_by_user_id NULL isolates RLS from FK; literal parent id (D1)
  ok := true;
  BEGIN INSERT INTO public.planned_outflows (key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key,created_by_user_id)
          VALUES ('__unauth__','x','save_up_bill',DATE '2027-05-01','transfer_funded','amex_savings','truist_checking',NULL);
    ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'UNAUTH FAIL: PO INSERT was NOT denied by RLS.'; END IF;
  ok := true;
  BEGIN INSERT INTO public.outflow_events (planned_outflow_id,event_type,amount_cents,event_date,funding_account_key,created_by_user_id)
          VALUES ('00000000-0000-0000-0000-0000000000d1','set_aside',500,DATE '2027-05-01','amex_savings',NULL);
    ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'UNAUTH FAIL: OE INSERT was NOT denied by RLS.'; END IF;
  RAISE NOTICE 'C UNAUTH PASS: harness ok; reads 0-row; writes denied.';
END $$;
RESET ROLE;

-- post-check as owner: unauthorized probes changed nothing
DO $$
DECLARE n_po INT; n_oe INT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.planned_outflows WHERE key='__smoke_target__') THEN
    RAISE EXCEPTION 'POST-UNAUTH FAIL: smoke target row missing (unexpected deletion).'; END IF;
  SELECT count(*) INTO n_po FROM public.planned_outflows; SELECT count(*) INTO n_oe FROM public.outflow_events;
  IF n_po <> 1 OR n_oe <> 1 THEN RAISE EXCEPTION 'POST-UNAUTH FAIL: row counts changed (po=%, oe=%; expected 1,1).', n_po, n_oe; END IF;
  RAISE NOTICE 'POST-UNAUTH ok: no mutation from denied writes.';
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- B — VIEWER (active, role=viewer): read yes, write no
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE cnt INT; upd INT; ok BOOLEAN;
BEGIN
  PERFORM set_config('role','authenticated', true);
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","email":"%s","role":"authenticated"}','<<V_UUID>>','<<V_EMAIL>>'), true);
  IF (auth.uid())::text <> '<<V_UUID>>' THEN RAISE EXCEPTION 'harness: viewer uid claim not applied.'; END IF;

  SELECT count(*) INTO cnt FROM public.planned_outflows;  IF cnt < 1 THEN RAISE EXCEPTION 'VIEWER FAIL: PO SELECT returned 0 (read gate should pass).'; END IF;
  SELECT count(*) INTO cnt FROM public.outflow_events;    IF cnt < 1 THEN RAISE EXCEPTION 'VIEWER FAIL: OE SELECT returned 0 (read gate should pass).'; END IF;

  ok := true;
  BEGIN INSERT INTO public.planned_outflows (key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key,created_by_user_id)
          VALUES ('__viewer__','x','save_up_bill',DATE '2027-05-01','transfer_funded','amex_savings','truist_checking',NULL);
    ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'VIEWER FAIL: PO INSERT was NOT denied by RLS.'; END IF;
  ok := true;
  BEGIN INSERT INTO public.outflow_events (planned_outflow_id,event_type,amount_cents,event_date,funding_account_key,created_by_user_id)
          VALUES ('00000000-0000-0000-0000-0000000000d1','set_aside',500,DATE '2027-05-01','amex_savings',NULL);
    ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'VIEWER FAIL: OE INSERT was NOT denied by RLS.'; END IF;

  -- UPDATE denial is a silent 0-row (USING can_write_financials() = false)
  UPDATE public.planned_outflows SET label='viewer-edit' WHERE key='__smoke_target__';
  GET DIAGNOSTICS upd = ROW_COUNT;
  IF upd <> 0 THEN RAISE EXCEPTION 'VIEWER FAIL: PO UPDATE affected % rows (expected 0).', upd; END IF;
  RAISE NOTICE 'B VIEWER PASS: harness ok; reads ok; writes denied; update 0-row.';
END $$;
RESET ROLE;

-- post-check as owner: viewer's denied/no-op writes changed nothing (D4: NOT FOUND + count)
DO $$
DECLARE lbl TEXT; n_po INT; n_oe INT;
BEGIN
  SELECT label INTO lbl FROM public.planned_outflows WHERE key='__smoke_target__';
  IF NOT FOUND THEN RAISE EXCEPTION 'POST-VIEWER FAIL: smoke target row missing (unexpected deletion).'; END IF;
  IF lbl <> 'SMOKE target' THEN RAISE EXCEPTION 'POST-VIEWER FAIL: target label mutated to "%".', lbl; END IF;
  SELECT count(*) INTO n_po FROM public.planned_outflows; SELECT count(*) INTO n_oe FROM public.outflow_events;
  IF n_po <> 1 OR n_oe <> 1 THEN RAISE EXCEPTION 'POST-VIEWER FAIL: row counts changed (po=%, oe=%; expected 1,1).', n_po, n_oe; END IF;
  RAISE NOTICE 'POST-VIEWER ok: no mutation from denied writes.';
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- A — WRITER (role household_admin): read/insert ok; append-only + immutability enforced
--   __writer_ok__ = 00000000-0000-0000-0000-0000000000d2 (literal id for OE probe)
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE new_cbu UUID; ok BOOLEAN; upd INT;
BEGIN
  PERFORM set_config('role','authenticated', true);
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","email":"%s","role":"authenticated"}','<<W_UUID>>','<<W_EMAIL>>'), true);
  IF (auth.uid())::text <> '<<W_UUID>>' THEN RAISE EXCEPTION 'harness: writer uid claim not applied.'; END IF;

  -- INSERT relying on DEFAULT auth.uid() -> proves auth.uid(), FK to auth.users, and write policy together
  INSERT INTO public.planned_outflows (id,key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key)
    VALUES ('00000000-0000-0000-0000-0000000000d2','__writer_ok__','writer insert','save_up_bill',DATE '2027-05-01','transfer_funded','amex_savings','truist_checking')
    RETURNING created_by_user_id INTO new_cbu;
  IF new_cbu::text <> '<<W_UUID>>' THEN RAISE EXCEPTION 'WRITER FAIL: created_by_user_id=% (expected default auth.uid()=<<W_UUID>>).', new_cbu; END IF;

  INSERT INTO public.outflow_events (planned_outflow_id,event_type,amount_cents,event_date,funding_account_key)
    VALUES ('00000000-0000-0000-0000-0000000000d2','set_aside',2500,DATE '2027-05-01','amex_savings')
    RETURNING created_by_user_id INTO new_cbu;
  IF new_cbu::text <> '<<W_UUID>>' THEN RAISE EXCEPTION 'WRITER FAIL: OE created_by_user_id=% (expected auth.uid()).', new_cbu; END IF;

  -- label edit allowed
  UPDATE public.planned_outflows SET label='writer-edited' WHERE key='__writer_ok__';
  GET DIAGNOSTICS upd = ROW_COUNT;
  IF upd <> 1 THEN RAISE EXCEPTION 'WRITER FAIL: label UPDATE affected % rows (expected 1).', upd; END IF;

  -- key edit blocked by immutability trigger (D2: assert the expected error text)
  ok := true;
  BEGIN
    UPDATE public.planned_outflows SET key='__renamed__' WHERE key='__writer_ok__'; ok := false;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%immutable%' THEN RAISE; END IF;   -- unexpected error -> propagate loudly
  END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: key UPDATE was NOT blocked by the immutability trigger.'; END IF;

  -- OE UPDATE / DELETE, PO DELETE, TRUNCATE blocked (no grant -> insufficient_privilege)
  ok := true;
  BEGIN UPDATE public.outflow_events SET memo='x' WHERE planned_outflow_id='00000000-0000-0000-0000-0000000000d2'; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: OE UPDATE was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN DELETE FROM public.outflow_events WHERE planned_outflow_id='00000000-0000-0000-0000-0000000000d2'; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: OE DELETE was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN DELETE FROM public.planned_outflows WHERE key='__writer_ok__'; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: PO DELETE was NOT permission-denied.'; END IF;
  ok := true;
  BEGIN TRUNCATE public.outflow_events; ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'WRITER FAIL: OE TRUNCATE was NOT permission-denied.'; END IF;
  RAISE NOTICE 'A WRITER PASS: harness ok; insert(default uid) ok; label edit ok; key/append-only/delete/truncate all blocked.';
END $$;
RESET ROLE;

-- ══════════════════════════════════════════════════════════════════════════
-- CLAIM-KEYING PROBES — GATE-1 POLICY/HARNESS ONLY (not normal GoTrue behavior;
--   arise only if JWT claims drift/are forged). NOT part of the Gate-2 matrix.
--
-- CORRECTED MODEL (Gate-1 run 2026-07-08): BOTH gates key on auth.uid(); NEITHER
-- consults the email claim. is_allowed_user() was migrated off email onto
-- auth_user_id = auth.uid() in Phase 4B (email is mutable; uid is stable):
--     is_allowed_user()      = auth_user_id = auth.uid() AND active            (read)
--     can_write_financials() = auth_user_id = auth.uid() AND active AND role   (write)
-- So the JWT email claim is IRRELEVANT to authorization. M1/M2 now PROVE that:
-- there is NO read/write claim asymmetry (the earlier "write-cannot-read" note is VOID).
-- ══════════════════════════════════════════════════════════════════════════
-- M1: matching email + WRONG sub  -> read DENY + write DENY
--   (email match grants nothing; both gates require the sub to be in app_users)
DO $$
DECLARE cnt INT; ok BOOLEAN;
BEGIN
  PERFORM set_config('role','authenticated', true);
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","email":"%s","role":"authenticated"}','00000000-0000-0000-0000-0000000000ff','<<W_EMAIL>>'), true);
  -- read: is_allowed_user keys on auth.uid()=...ff (not in app_users) -> 0 rows
  SELECT count(*) INTO cnt FROM public.planned_outflows;
  IF cnt <> 0 THEN RAISE EXCEPTION 'M1 FAIL: read should be DENIED (sub not allowlisted; email is not consulted). Got % rows.', cnt; END IF;
  -- write: can_write_financials keys on auth.uid()=...ff -> denied. created_by NULL isolates RLS from FK.
  ok := true;
  BEGIN INSERT INTO public.planned_outflows (key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key,created_by_user_id)
          VALUES ('__m1__','x','save_up_bill',DATE '2027-05-01','transfer_funded','amex_savings','truist_checking',NULL);
    ok := false; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF NOT ok THEN RAISE EXCEPTION 'M1 FAIL: write should be DENIED (sub not allowlisted).'; END IF;
  RAISE NOTICE 'M1 (email match + wrong sub): read DENY + write DENY — email claim is not consulted; auth.uid() governs.';
END $$;
RESET ROLE;

-- M2: matching sub + WRONG email  -> read ALLOW + write ALLOW
--   (email claim ignored; a valid allowlisted sub grants BOTH read and write)
DO $$
DECLARE cnt INT; ins INT;
BEGIN
  PERFORM set_config('role','authenticated', true);
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s","email":"%s","role":"authenticated"}','<<W_UUID>>','junk-not-allowlisted@herndons.test'), true);
  -- read: is_allowed_user keys on auth.uid()=writer -> rows visible (email mismatch does not matter)
  SELECT count(*) INTO cnt FROM public.planned_outflows;
  IF cnt < 1 THEN RAISE EXCEPTION 'M2 FAIL: read should be ALLOWED (sub matches; email is not consulted). Got 0 rows.'; END IF;
  -- write: can_write_financials keys on auth.uid()=writer (role household_admin) -> allowed.
  -- created_by_user_id defaults to auth.uid()=writer (FK-valid).
  INSERT INTO public.planned_outflows (key,label,planning_bucket,due_date,funding_mode,funding_account_key,source_account_key)
    VALUES ('__m2__','m2','save_up_bill',DATE '2027-05-01','transfer_funded','amex_savings','truist_checking');
  GET DIAGNOSTICS ins = ROW_COUNT;
  IF ins <> 1 THEN RAISE EXCEPTION 'M2 FAIL: write should be ALLOWED (sub matches).'; END IF;
  RAISE NOTICE 'M2 (sub match + wrong email): read ALLOW + write ALLOW — email claim is not consulted; auth.uid() governs. No read/write asymmetry.';
END $$;
RESET ROLE;

-- ── FINAL GROUND-TRUTH: smoke target intact (owner view; D4: NOT FOUND-safe) ──
DO $$
DECLARE n_po INT; n_oe INT; lbl TEXT;
BEGIN
  SELECT label INTO lbl FROM public.planned_outflows WHERE key='__smoke_target__';
  IF NOT FOUND THEN RAISE EXCEPTION 'FINAL FAIL: smoke target row missing (unexpected deletion).'; END IF;
  IF lbl <> 'SMOKE target' THEN RAISE EXCEPTION 'FINAL FAIL: smoke target label mutated to "%".', lbl; END IF;
  SELECT count(*) INTO n_po FROM public.planned_outflows;
  SELECT count(*) INTO n_oe FROM public.outflow_events;
  RAISE NOTICE 'FINAL owner view: planned_outflows=% outflow_events=% (all rolled back next). Matrix PASSED if you saw D/C/B/A PASS + M1 + M2 notices.', n_po, n_oe;
END $$;

-- ── NOTHING PERSISTS ─────────────────────────────────────────────────────────
ROLLBACK;

-- Post-rollback confirmation (run as owner): both tables empty again.
SELECT 'G1-empty' AS check,
       (SELECT count(*) FROM public.planned_outflows)=0 AND (SELECT count(*) FROM public.outflow_events)=0 AS expected_true;
