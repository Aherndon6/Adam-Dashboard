# AU-11 Step 6C-D2 — reservation lifecycle RPCs: staging package + execution record (2026-07-26)

**Status:** package **AUTHORED + REVISED + 11/10-HARDENED + CLOSURE-VERIFIED** (2026-07-26), **NOT executed**,
**NOT committed/pushed**. Fable review #1 (APPROVE-WITH-CHANGES; F1/F3/F4/F5/F7 applied; F2→R7, F6→R8 ruled);
Fable review #2 hardening (APPROVE-WITH-CHANGES; F-A material fixed, F-B/F-F applied, F-C/F-E dispositioned);
**Fable review #3 post-fix verification = APPROVE (9/10), no BLOCKING/MATERIAL** (F-A/F-B/F-C/F-F confirmed present,
no regressions, record matches SQL). Classified **11/10 — GO for Checkpoint A**.

**Staging execution progress (2026-07-26, staging `pkwotgqivgaapwuqgwqb`, Adam-executed, Claude ran no SQL):**
Checkpoint **A PASS** (reservable column boolean/NO/false) · **B PASS** (all CHK_* incl. frozen-RPC oidvectortypes
fix) · **C PASS** (ledger-tracked fixture, 19 refs, idempotent; owner reused `aherndon6@gmail.com`; FK/balance_basis/
ledger-RLS/role-leak defects fixed) · **D PASS** (full matrix green after N4 stale-expectation + N10/E4/E5/L-BPSR
RLS-scaffolding fixes; RLS diagnostic authenticated=0/admin=1 confirmed classification C; 8-row summary residue 0/0,
frozen RPCs intact, basis 31 / 9 snapshots / owner 1 / reservable 3) · **E PASS** (two-session psql proof, distinct
backend PIDs 34187/34190, both staging) · **F PASS** (fixture teardown; asserted harness; persisted post-state: six
residue counts all 0 — goals/snapshots/reconciliation removed, ledger dropped, 0 reservations/0 batches — and reused
owner `aherndon6@gmail.com` intact/auth-linked; a first attempt hit a parse-time `42601` reserved-word alias defect
that executed nothing, fixed `check`→`check_name`). RPC + D1 schema + frozen surfaces unchanged throughout · **G PASS** (rollback proof, Adam-executed staging: 4-row
`RB_*` corroboration all 0 [functions/column/batches/reservations]; committed → all in-txn gates A/B/C/D/E passed;
post-verifier PART-1 structural asserts passed + PART-2 constraintdef/indexdef matched D1 baseline, frozen repair
`integer,integer,text,jsonb,jsonb` + save_reconciliation 11-arg sigs exact; no errors). D2 RPCs + reservable column
removed, D1 + frozen intact — exact reversibility proven.
**Checkpoint H (2026-07-27, Adam-executed staging): H-A…H-E PASSED; H-F PENDING.**
- H-A PASS (reservable boolean/NOT NULL/default false). H-B PASS (all catalog checks at expected values; 3 RPCs
  secdef+empty search_path, no overloads, ACLs, status-CHECK admits planned/funding, no implicit reservable, D1
  shape + frozen sigs preserved, residue 0). H-C PASS (exactly one qualifying active owner; basis max wk 31; 9
  snapshots @2026/wk31; 3 fixture reservable goals; 0 implicit). H-D PASS (8-row summary: PRE_owner=1, PRE_max_week=31,
  PRE_snapshots_wk31=9, PRE_reservable_goals=3, FROZEN_repair_ok=1, FROZEN_saverecon_ok=1, CLEAN_reservations=0,
  CLEAN_batches=0). **H-E PASS — genuine two-session psql contention proof** (both sessions env-certified staging):
  PASS-A1 (cc000001 active, txn held open) · PASS-B1 (`55P03 canceling statement due to lock timeout`, blocked at
  `pg_advisory_xact_lock(hashtextextended('au11_disc:'||p_model_year||':'||p_source_account,0))`) · PASS-A2 (commit) ·
  PASS-B2 (`an active discretionary batch already exists for 2026/truist_checking …`) · PASS-C (active_batches=1) ·
  PASS-CLEAN (0/0). Advisory-lock serialization + single-active-batch objectively proven; the earlier SQL-Editor
  attempt is superseded (editor did not hold an independent open transaction).
- **H-F PASS (2026-07-27):** teardown TD_planned 9/9/1; asserted transaction COMMITTED (BEGIN→DO×3→DROP TABLE→DO→
  COMMIT ⇒ all in-txn manifest/identity/coherence/ROW_COUNT(9/1/9)/residue/ledger-absent asserts passed); six RES_*
  all 0; owner_integrity gate=PASS (1 owner, aherndon6@gmail.com, auth uid [redacted before public push], backing
  present — unchanged from H-C). **CHECKPOINT H COMPLETE + PASSED** — end-state: D2 installed (reservable + 3 RPCs),
  fixture fully removed, D1 + frozen intact, reused owner untouched, zero residue.
- **Checkpoint I PASS (2026-07-27, Adam-executed staging, read-only enforced verifier):** env cert 1/1/0/true;
  PART-1 mechanically-enforced gate completed with NO `FINAL-STATE FAIL` (all ~20 assertions passed — D2 install
  exact sigs/no-overloads/secdef/empty search_path/owner/ACLs/reservable shape; D1 shape incl. exact index
  predicate; status-CHECK admits planned+funding; no implicit reservable; frozen sigs; fixture absence; residue;
  pinned owner); PART-2 11-row summary all at expected values (D2_reservable_present=1, D2_rpcs_present=3, all
  FIX_*_absent=0, IMPLICIT_reservable_nonfixture=0, ONE_ACTIVE_IDX_predicate_ok=1, RESIDUE_batches/reservations=0,
  STATUS_admits_planned_funding=1); PART-3 owner_integrity gate=PASS (1 owner, aherndon6@gmail.com,
  auth uid [redacted before public push], backing present).
- **AU-11 Step 6C-D2 STAGING VALIDATION A–I COMPLETE (2026-07-27).** Final staging state: D2 installed
  (goal_registry.reservable + 3 RPCs), D1 + frozen surfaces intact, fixture fully removed, zero D2 residue,
  reused owner unchanged. Reversibility (G) and redeployability (H) proven; final state (I) certified.
- **NOT done (deferred to next session, owner-gated):** D2 repo commit/push (the 11 untracked D2 docs),
  CODEX_STATUS.md pointer advance, and Step 6C-D3 (composite closeout). Production untouched; engine hold + all
  operational holds (incl. Wendy IRA) UNCHANGED and in force. Baseline HEAD still 78538f9.

**Pre-push identity remediation + Checkpoint I revalidation (2026-07-27):**
- **Why:** the repository `Aherndon6/Adam-Dashboard` is **public** and GitHub Pages serves `main` root at
  `dashboard.herndons.us`, so `docs/` is publicly served. The literal staging owner auth UUID (previously embedded
  in this record and in `phase-au11-6c-d2-staging-final-state-verify.sql`) was removed before any push so that no
  pushed commit or public page exposes a staging identity. The owner email `aherndon6@gmail.com` is retained
  (already public throughout the repo) as the identity anchor.
- **Verifier change (Strategy A):** the Checkpoint-I owner gate no longer pins the exact auth UUID. It now asserts
  **exactly one qualifying active owner ∧ email=aherndon6@gmail.com ∧ auth_user_id IS NOT NULL ∧ a matching
  auth.users backing row.** PART 3 reports only non-sensitive structural evidence: `qualifying_owners`,
  `selected_email`, `auth_user_id_present`, `auth_user_backing_exists`, `gate`. This is an **intentional semantic
  change**: the exact-UUID pin is deliberately replaced by a unique, email-anchored, auth-backed owner-integrity
  assertion to avoid publishing a staging identity — it is **not** claimed to be identical in discriminating power.
- **Scope of rerun:** only **Checkpoint I** was re-executed. Checkpoints **A–H artifacts are byte-unchanged** (the
  UUID appeared only in the final-state verifier and this record), so A–H were **not** re-run; the revised verifier
  was re-executed against the existing final staging state (D2 installed, D1+frozen intact, fixture absent, zero
  residue, owner intact).
- **Revised Checkpoint I results (2026-07-27, staging `pkwotgqivgaapwuqgwqb`, Adam-executed, Claude ran no SQL):**
  environment certification 1/1/0/true (environment_rows=1, staging_rows=1, non_staging_rows=0,
  all_rows_are_staging=true). PART-1 mechanically-enforced gate completed with **no FINAL-STATE FAIL** and no SQL
  error — the complete verifier reached PART 3, which it could not have done had PART 1 raised. PART-2 11-row summary
  all at expected values: D2_reservable_present=1, D2_rpcs_present=3, FIX_goals_absent=0, FIX_ledger_absent=0,
  FIX_recon_wk31_absent=0, FIX_snapshots_absent=0, IMPLICIT_reservable_nonfixture=0, ONE_ACTIVE_IDX_predicate_ok=1,
  RESIDUE_batches=0, RESIDUE_reservations=0, STATUS_admits_planned_funding=1. PART-3 owner_integrity **gate=PASS**
  with qualifying_owners=1, selected_email=aherndon6@gmail.com, auth_user_id_present=true,
  auth_user_backing_exists=true (revised schema — no raw auth UUID emitted). **Checkpoint I revalidation PASSED.**
- **Executed==committed (SHA-256 control):** the revised verifier executed for Checkpoint I had SHA-256
  `4ab6c215cd35b01432ffbce8d10834511ab60495692edfddd9fd49fbe19b3b6f` (16,357 bytes, 185 lines), confirmed unchanged
  after execution. The same unchanged file, at this identical SHA-256, must enter the rewritten D2 artifact commit;
  this equality will be re-verified against the committed blob during the history-rewrite step.

**Checkpoint E evidence (2026-07-26, psql two-terminal, staging):**
- PASS-A1: `create_…('cc000001', d2fix_g01, 1000)` → ok/active; Session A (PID 34187) held open (xid 1750).
- PASS-B1: Session B (PID 34190) `cc000002` → **SQLSTATE 55P03 canceling statement due to lock timeout**, blocked
  exactly at `pg_advisory_xact_lock(hashtextextended('au11_disc:'||p_model_year||':'||p_source_account,0))` — objective
  proof of single-flight advisory-lock contention.
- PASS-A2: Session A COMMIT succeeded.
- PASS-B2: Session B retry `cc000002` → **P0001 `an active discretionary batch already exists for 2026/truist_checking …`**
  (single-active-batch invariant; no second active batch).
- PASS-C: `CONC_active_batch_count=1` (only cc000001 active).
- PASS-CLEAN: cleanup DELETE 1 commitment + 1 batch → `CONC_residue` batches=0/reservations=0.
- *Harness fix (test-only):* concurrency A1/B1/B2 set `role=authenticated` before the claims subquery read
  `auth.users` → `permission denied for auth.users` under psql. Reordered to set `request.jwt.claims` (as admin,
  auth.users readable) BEFORE `set role=authenticated`. No RPC/schema/D1/frozen-surface change. Per governance ("Claude ran no
SQL"), Adam executes on staging `pkwotgqivgaapwuqgwqb` (≠ prod). No production, no client wiring/callers, no
canonical status-pointer change in this gate. Baseline HEAD `78538f9` (D1 pushed).

**Frozen/untouched:** runModel, authoritativeCurrentChk, getCashAvailabilityEngine, isReservedAsOf, the
existing commitment RPCs (`save_reconciliation_with_commitments`, `repair_commitments_for_week`), the frozen
closeout wrapper, and the nine-goal closeout contract. D2 adds three NEW functions + one additive column
(`goal_registry.reservable`, R8). Local frozen hashes unchanged (`runModel 5181b79c` / `netting 4670447c` /
`resolver 20d17438`); `index.html`/`test_regression.js` untouched; no BUILD_TS change.

## Files (docs/, uncommitted) — 9
- `phase-au11-6c-d2-goal-registry-reservable.sql` — **(R8):** additive `goal_registry.reservable BOOLEAN NOT NULL
  DEFAULT false`. Smallest additive metadata change; fail-closed default.
- `phase-au11-6c-d2-staging-rpcs.sql` — three owner-only SECURITY DEFINER RPCs (**`SET search_path = ''`**, all
  objects schema-qualified) + grants; guards require D1 + the `reservable` column. Hardened input validation.
- `phase-au11-6c-d2-staging-catalog-verify.sql` — **NEW (hardening, checkpoint B):** proves prosecdef, empty
  search_path, owner∉{anon,authenticated}, ACLs, exact signatures, no overloads, reservable column shape, status
  CHECK admits the predicate, no implicit reservable, D1 shape, residue, frozen RPCs present.
- `phase-au11-6c-d2-staging-fixture.sql` — **(R1, hardened):** deterministic, idempotent fixture with a
  **`d2_fixture_ledger` ownership table** + fail-closed preflight (never overwrites foreign rows) + post-seed checks.
- `phase-au11-6c-d2-staging-fixture-teardown.sql` — **(R1, hardened):** deletes ONLY ledgered rows (FK-ordered),
  drops the ledger, proves zero residue; structurally cannot delete legitimate rows.
- `phase-au11-6c-d2-staging-concurrency.sql` — **NEW (hardening, checkpoint E):** executable two-session proof with
  `lock_timeout`, objective PASS criteria (SQLSTATE 55P03; single-active-batch conflict; active count=1), self-cleanup.
- `phase-au11-6c-d2-staging-validation.sql` — fixture-driven role matrix + lifecycle-A/B + eligibility E1–E5 +
  N1–N11 + Req-5/6/7 blocks (L-MIX/L-SEL/L-BPSR/L-DUP/L-ARR, D2-INPUT, I-ORDER/I-REPLAY/I-TERM/I-F4), all with
  expected-error assertions; all mutations rolled back.
- `phase-au11-6c-d2-staging-rollback.sql` — **STAGING-PROOF** rollback [Checkpoint G]: acquires the RPCs' advisory
  lock (closes the preflight→DDL race); asserts the COMPLETE install (3 exact `oidvectortypes` signatures, no
  overloads, reservable column shape) then DROPs **without IF EXISTS**; fail-closed preflight (batches/residue/any
  `reservable=true`/no `d2fix_%` remain); asserts absence in-transaction; 4-row corroboration (functions/column/
  batches/reservations all 0). (Production rollback is a separate future design.)
- `phase-au11-6c-d2-staging-post-rollback-verify.sql` — **NEW (Checkpoint G):** read-only D1-intact + frozen-RPC
  verification run AFTER rollback (D1 batch table / shape CHECK / one-active index / cash_commitments additive
  columns present; frozen repair + save_reconciliation exact signatures present; reservable column absent).
- this record.

## RPC signatures & lifecycle semantics (post-R7/R8)
1. `create_discretionary_goal_reservation_v1(p_model_year int, p_basis_model_week int, p_batch_digest text, p_source_account text, p_expected_clear_date date, p_rows jsonb, p_expected_total_cents int=NULL) → jsonb`
   — inserts one `discretionary_reservation_batches` row (`status='active'`) + one `cash_commitments` row per goal
   (`commitment_class='discretionary_goal_transfer'`, `commitment_source='au11_reservation'`, `status='scheduled'`).
   Enforces the **R8 registry-eligibility predicate** per row (see below).
2. `mark_discretionary_goal_reservation_initiated_v1(p_model_year int, p_batch_digest text, p_goal_ids text[], p_bank_reference text, p_bank_submitted_at timestamptz, p_expected_clear_date date=NULL) → jsonb`
   — `scheduled → initiated` (records bank_reference + bank_submitted_at). `p_goal_ids` NULL ⇒ all scheduled rows.
3. `void_scheduled_discretionary_goal_reservation_v1(p_model_year int, p_batch_digest text, p_goal_ids text[], p_reason text) → jsonb`
   — **R7:** voids ONLY rows in `scheduled` state (`resolution_type='voided'`); retires the batch to `voided` when
   no non-terminal rows remain (partial void keeps the batch active). If ANY targeted row is `initiated`/
   `bank_pending`/`stale_review`, the whole call is **rejected** — D2 cannot cancel or release an initiated reservation.
   (The former `dispose_or_void…` with `cancel_initiated`/`paid_other_account` is **removed**.)

Lifecycle (post-R7): `— → scheduled → initiated → (cleared via D3 closeout)`. From `scheduled`, `void_scheduled`
→ `voided`. From `initiated` onward there is **no D2 exit** — an initiated reservation stays withholding and is
resolved ONLY by the D3 composite closeout (cleared Register evidence + posted-date controls). Active/withholding
states: scheduled, initiated, bank_pending, stale_review.

## R8 Goal Registry eligibility predicate (exact)
Per row, `create()` requires (driven by centralized `goal_registry` metadata, no embedded goal list, no inference
from `auto`/`stretch`):
```
status IN ('planned','funding')              -- (1) eligible/active goal state
AND COALESCE(reservable,false) = true         -- (2) explicit reservation eligibility (additive column)
AND dest IS NOT NULL AND btrim(dest) <> ''    -- (3) valid destination account (registry dest)
```
Distinct rejection messages: `is not in an eligible state` / `is not reservable` / `has no valid destination account`.
**Additive schema decision:** the registry had `status` and `dest` but NO explicit reservation-eligibility field
(`auto`/`stretch` are ambiguous), so the smallest additive change is one boolean `goal_registry.reservable`
(DEFAULT false ⇒ fail-closed; app mapper ignores unknown columns ⇒ client-inert). This is staging-only here, like D1.

## R1 fixture (deterministic, removable)
**Owner identity (revised 2026-07-26 — staging `app_users.auth_user_id` HAS a FK to `auth.users`):** the fixture
does **not** synthesize an owner. It **reuses an existing active owner** via the single **canonical selection used
identically in fixture / validation / concurrency**:
```
WHERE au.role='owner' AND au.active IS TRUE AND au.auth_user_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = au.auth_user_id)   -- proves auth.users backing + detects drift
ORDER BY au.auth_user_id LIMIT 1                                          -- deterministic, immutable
```
It HARD STOPs if none qualifies, directing provisioning via a supported Supabase mechanism (Dashboard →
Authentication → Add user, then set that user's `app_users` row `role='owner'`, `active=true`). No `auth.users`
manual insert, no FK/constraint change; the real `is_owner()` gate is exercised with a genuine owner. No file
selects by email or uses a weaker owner predicate. The non-owner test (D2-ROLE-2) simulates a uid **absent** from
`app_users` (no insert). The `d2_fixture_ledger` scaffolding is created with **RLS enabled, no policies, and
anon/authenticated revoked**; dropping it in teardown removes its RLS state and grants with the table.

`phase-au11-6c-d2-staging-fixture.sql` then seeds (all ledger-owned): basis `weekly_reconciliations.week_num=31`
(top of 1..31, forced MAX; numeric sentinel `chk=3131.31` marks fixture ownership; `balance_basis='unknown'` per its
value-restricted CHECK); nine `goal_funding_snapshots` at (2026,31)
(`created_by_user_id` NULL to dodge the auth.users FK); goals `d2fix_g01..g09` (g01–g03 reservable/funding/valid-dest
= happy path; g04 reservable=false; g05 status=funded; g06 empty dest; g07–g09 filler for the ≥9 count). Idempotent
(upserts; preflight aborts only on a NON-fixture week-31/goal/snapshot). **Ledger = 19 owned refs** (1
weekly_reconciliations + 9 goal_registry + 9 goal_funding_snapshots; NO app_users). Teardown removes all fixture
artifacts FK-ordered (snapshots before goals — ON DELETE RESTRICT), never touches app_users, and proves zero
residue. The validation suite's mutating tests roll back independently; the fixture rows persist only until teardown.

## Authorization model
Owner-only: every body asserts `public.is_owner()` (= `app_users.auth_user_id = auth.uid()` with `role='owner'`
active) → else `42501`. EXECUTE granted to `authenticated` but the in-body gate is the real control; PUBLIC/anon
revoked. Direct table writes remain RPC-only (D1 RLS). household_admin cannot create/initiate/dispose.

## Locking & idempotency
- Single-flight: `pg_advisory_xact_lock(hashtextextended('au11_disc:'||model_year||':'||source_account,0))` held
  for each RPC's transaction → serializes create/initiate/dispose (and, later, the D3 composite).
- Idempotency (post-Fable): `(model_year, batch_digest)` identity + `expected_item_id` UNIQUE. The replay branch
  is evaluated **before** the reconciled-latest-basis precondition (**F4** — a valid replay of an existing active
  batch must not fail merely because a newer week has since reconciled). Replay compares the request only against
  **non-terminal** rows (`scheduled/initiated/bank_pending/stale_review`) and includes `destination_account_ref`
  (**F1/F5** — a partially-voided batch, a disposed goal, or a changed destination is a **conflict**, never a
  silent idempotent no-op). Identical, fully-intact replay → no-op; any amount/goal/row-count/destination/status
  divergence → conflict `RAISE`. batch_digest is amount-free (Step-6B cycle digest) so amount changes surface as
  conflicts, never new identities.
- `mark_initiated` (**F7**): explicit `p_goal_ids` matching zero `scheduled` rows now **fails closed** (operator
  error), and the false "bank_reference idempotency" comment was removed; a genuine all-rows re-call where every
  row is already initiated returns `idempotent:true, transitioned:0`.
- Single-active-batch: explicit RPC check + the `uix_one_active_batch` partial-unique DB backstop.

## Independent (Fable) control-design/concurrency review — APPROVE-WITH-CHANGES (7/10), corrections applied
Fable cleared as correct: advisory-lock key consistency, TOCTOU coverage under the lock, withholding semantics
for live/voided states, JWT/role simulation adequacy, rolled-back DO blocks persisting nothing, staging guards.
Findings and disposition:
- **F1 (HIGH, fail-open) — FIXED.** Replay conflict check ignored row status → a partially-voided batch replayed
  as an idempotent no-op while a voided goal silently stopped withholding. Replay now matches only non-terminal
  rows; a disposed goal → conflict. (Regression test N9.)
- **F4 (idempotency vs newer week) — FIXED.** Replay short-circuit now precedes the basis-latest precondition.
- **F5 (destination drift) — FIXED.** Replay match now includes `destination_account_ref`. (Regression test N10.)
- **F3 (tests false-pass) — FIXED.** Every negative now asserts the **expected** SQLERRM substring; a rejection
  for the wrong reason fails loudly as `FALSE-PASS RISK`. Added N9/N10/N11.
- **F7 (mark_initiated idempotency claim) — FIXED.** See above. (Regression test N11.)
- **F2 (HIGH, double-spend) — RESOLVED via owner ruling R7 (option b).** `cancel_initiated` and `paid_other_account`
  are **removed**. D2 has no path that releases an initiated reservation; initiated reservations stay withholding and
  resolve only through the D3 composite closeout (cleared Register evidence). D2's only undo is `void_scheduled`
  (scheduled-only). Proven by validation D2-LIFECYCLE-B.
- **F6 (goal eligibility) — RESOLVED via owner ruling R8.** Eligibility is driven by centralized Goal Registry
  metadata (status + `reservable` + valid dest), not an embedded list; the smallest additive change (`reservable`
  boolean) was added rather than inferring from ambiguous fields. Proven by validation D2-ELIG (E1/E2/E3).
- Column/CHECK items Fable asked to confirm are **grounded-OK** in the repo schema (`docs/phase-5f-1-migration.sql`,
  `mapGoalFromDB`): `cash_commitments` has `updated_at/updated_by/resolved_at/resolved_by/resolution_notes` and its
  `resolution_type` CHECK admits `voided`/`paid_from_other_account`; `goal_registry` has `dest/name/auto/status`.
  Live staging capture at D2 execution (D2-PRE) will re-verify against the running catalog.

## Validation matrix (all mutations rolled back; NOTICES carry PASS/FAIL)
D2-PRE (fixture owner present; MAX week 31 + ≥9 snapshots; 3 reservable fixture goals) · D2-ROLE-1 owner create
PASS · D2-ROLE-2 household_admin 42501 · D2-ROLE-3 anon rejected · **D2-LIFECYCLE-A** create→void_scheduled →
row voided, batch retired voided · **D2-LIFECYCLE-B (R7 control proof)** create→mark_initiated→void attempt
**REJECTED** (`cannot void initiated reservation`); row stays `initiated`, batch stays `active` · **D2-ELIG (R8):**
E1 reservable=false rejected, E2 ineligible status rejected, E3 empty dest rejected · D2-NEG (each asserts the
**expected** rejection message — wrong-reason → `FALSE-PASS RISK`): N1 conservation, N2 unknown goal, N3 dup goal,
N4 amount≤0, N5 non-latest basis, N6 wrong source, N7 second active batch, N8a idempotent replay, N8b conflicting
(changed-amount) replay, **N9 partial-void replay → conflict (F1)**, **N10 destination-change replay → conflict
(F5)**, **N11 mark_initiated zero-match → fail closed (F7)**. N8–N11 each run in their own rolled-back transaction
so a persisting active batch never poisons the next test. D2-FROZEN repair/save present · D2-CONCURRENCY documented
two-session test · D2-CLEAN zero reservation/batch residue (fixture rows persist until teardown).

## Rollback approach
Drop the three functions (stateless) **and** the additive `goal_registry.reservable` column; D1 schema/data
untouched; re-installable. `DROP FUNCTION IF EXISTS` with exact signatures + `ALTER TABLE … DROP COLUMN IF EXISTS`,
guarded to refuse while any reservation batch exists. Fixture is removed separately by the teardown file.

## Risks / decisions
- **R1 — staging fixture — RESOLVED (built).** `phase-au11-6c-d2-staging-fixture.sql` seeds a deterministic,
  idempotent, removable fixture (owner + basis week 31 + ≥9 snapshots + eligible/ineligible goals) so the full
  matrix runs with **no SKIPs**; teardown proves zero residue. See the R1 fixture section above.
- **R2 — role simulation:** tests set `request.jwt.claims.sub` + `role=authenticated`; confirm staging honors
  this GUC path for `auth.uid()`/`is_owner()` inside SECURITY DEFINER (5G-1 RLS smoke used the same pattern).
  The fixture's FIX-CHECK owner probe verifies `is_owner()` resolves true under the fixture uid before validation.
- **R3 — `stale_review` producer:** D2 has no automatic scheduled→stale_review transition (grace-expiry). v1
  leaves stale detection to a later slice / read-time flag. (`void_scheduled` refuses stale_review — it is a
  non-scheduled state; such rows resolve via D3.)
- **R4 — `bank_pending` producer:** no explicit setter in D2. (`void_scheduled` refuses bank_pending; resolve via D3.)
  Confirm whether a `mark_bank_pending` transition is needed in a later slice or deferred.
- **R5 — concurrency proof is manual** (two SQL Editor sessions); single-session tests can't exercise the
  advisory-lock contention. Documented; consider a scripted two-session harness at D2 execution.
- **R6 — payee source:** create() sets `payee = goal_registry.name` (fallback goal_id); confirm acceptable
  (payee is display/audit, not identity).
- **R7 — F2 double-spend — RESOLVED (owner ruling: option b).** No D2 release-of-initiated path exists; initiated
  reservations resolve only via the D3 composite (cleared Register evidence + posted-date). See F2 above and
  validation D2-LIFECYCLE-B.
- **R8 — F6 goal eligibility — RESOLVED (owner ruling).** Registry-driven predicate + additive `reservable` column;
  no embedded goal list. See the R8 eligibility section and validation D2-ELIG.

## Independent (Fable) review #2 — focused hardening review — APPROVE-WITH-CHANGES (8/10), no BLOCKING
Scope: SECURITY DEFINER/search_path, fixture isolation, rollback safety, lifecycle atomicity, idempotency,
concurrency-proof quality. Fable's six yes/no gates all passed: no shadowing vector under `search_path=''`;
setup cannot modify/delete non-fixture rows; no D2 RPC can move initiated/bank_pending/stale_review out of
withholding; no bad replay yields a partial batch; concurrency PASS is objective (SQLSTATE/row-count); nothing
fails to parse. Findings + dispositions:
- **F-A (MATERIAL) — FIXED.** Teardown step 0 (D2-artifact sweep) was not ledger-scoped yet the trailing comment
  claimed it was. Now gated on this fixture owning week 31, scoped to the fixture basis + goal-prefix, and the
  SAFETY PROOF comment is corrected to state steps 1–4 (durable business tables) are ledger-proven while step 0
  is a defensive sweep that can only match fixture-downstream D2 artifacts (normally 0 rows).
- **F-D (ADVISORY) — CONFIRMED against real DDL.** `discretionary_reservation_batches` has
  `resolved_at/resolved_by/resolution_type/resolution_notes` and status CHECK(active,retired,voided)
  (`phase-au11-6c-d1-staging-migration.sql:122-137`); `cash_commitments.status` admits
  scheduled/initiated/bank_pending/stale_review/voided (`phase-5f-1-migration.sql:83-84`). The void/insert paths
  are valid; catalog-verify + D2-LIFECYCLE re-confirm at execution.
- **F-B (ADVISORY) — APPLIED.** Replay now rejects a client-supplied `destination_account_ref` that disagrees
  with the registry (parity with the new-batch path) instead of a silent no-op.
- **F-F (ADVISORY) — APPLIED.** `mark_initiated`/`void_scheduled` now assert `v_batch.source_account =
  'truist_checking'` (future-proofs the hardcoded advisory-lock key against a second source).
- **F-C (ADVISORY) — HARDENED to fully fail-closed (closure pass).** `mark_initiated` now requires that EVERY
  goal in an explicit `p_goal_ids` list is currently a `scheduled` row in the batch; any overlap/mix/absent goal
  aborts the whole call atomically (nothing transitioned). Behavior matrix:

  | Case | Observable result |
  |---|---|
  | identical replay (`NULL` after full initiate) | no-op → `{ok:true, transitioned:0, idempotent:true}` |
  | overlapping subset (`[g_init, g_sched]`) | **RAISE** `goal(s) not scheduled in batch …: g_init` — g_sched NOT initiated (atomic) |
  | already-initiated (`[g_init]`) | **RAISE** `… not scheduled …` |
  | mixed scheduled+initiated (explicit) | **RAISE** (atomic) — no scheduled row advances |
  | mismatched bank_reference (full re-initiate, all already initiated) | no-op → `transitioned:0, idempotent:true`; bank_reference is **write-once** at the scheduled→initiated transition and is never overwritten on replay (documented, not silent — the `transitioned:0` + `idempotent:true` signal it) |

  No case can silently partially succeed. Proven by validation **F-C-OVERLAP** + N11.
- **F-E (ADVISORY) — dispositioned as a NAMED PRODUCTION GATE: `PROD-GATE-DIGEST-IDENTITY`.** Today, once a
  `(model_year, batch_digest)` batch reaches a terminal state (voided/retired), that digest **cannot be reused**
  in the same model_year (create() raises `batch … is terminal — cannot recreate`). Because the Step-6B digest is
  goal-set-derived and amount/week-free, the SAME goal set in a later cycle produces the SAME digest → a legitimate
  re-reservation of that goal set after a void would be blocked. This is safe and correct for STAGING D2 (no
  duplication/residue is possible: terminal-digest check + advisory lock + `uix_one_active_batch`), so it does not
  block Checkpoint A. **Before production wiring**, the owner must choose ONE and it must be implemented in a D1
  addendum: (a) adopt permanent per-model_year digest non-reuse as the audit-identity rule (add
  `UNIQUE(model_year, batch_digest)` to make it authoritative), OR (b) salt the digest with `basis_model_week` so
  each cycle has a distinct identity that permits post-void re-reservation (plus the UNIQUE constraint). Recorded
  here as a blocking **production** gate, not an unspecified note.

## Hardening pass (11/10) — summary
- **SECURITY DEFINER:** all three functions `SET search_path = ''` (pg_catalog implicit-first ⇒ built-ins safe;
  pg_temp not in path ⇒ no temp-object shadowing). Every application object schema-qualified (`public.*`, `auth.uid()`,
  `pg_catalog.pg_advisory_xact_lock`/`hashtextextended`). Ownership = SQL-Editor admin role (postgres), verified ∉
  {anon,authenticated}. Grants: EXECUTE→authenticated only; PUBLIC/anon revoked. All asserted in catalog-verify.
- **Input hardening:** allowed JSON keys only; digit-only amounts in [1..100000000]; BIGINT total (overflow-proof);
  empty/NULL/blank goal-id arrays fail closed; NULL/ineligible status fails closed; 8-lowercase-hex digest (uppercase
  rejected, no normalization); case-sensitive source_account; set-based, order-independent replay.
- **Lifecycle atomicity (R7):** mixed scheduled+initiated void fails atomically (nothing voided); bank_pending &
  stale_review cannot be released by any D2 RPC; terminal batch cannot be recreated.
- **Fixture isolation (R1):** ledger-tracked ownership + fail-closed preflight; teardown deletes only ledgered rows.
- **Rollback:** fail-closed on batches/residue/real reservable metadata; functions dropped before column; verified.

## Execution checkpoints (Req 9) — mandatory stops
Adam executes each; Claude runs no SQL. Abort at any stop that does not meet the expected output.
- **A. Metadata migration** — run `…-goal-registry-reservable.sql`. Expect: column added; verify query returns
  boolean / NO / false. Abort if the column is nullable or defaulted true.
- **B. RPC install + catalog inspection** — run `…-staging-rpcs.sql` (reload PostgREST cache), then
  `…-staging-catalog-verify.sql`. Expect: every `CHK_*` = PASS (secdef+empty search_path+owner, 1 row/function, ACLs,
  reservable shape, status CHECK admits planned+funding, no implicit reservable, D1 shape, residue 0; and
  `CHK_frozen_rpcs_present` = 2 rows both PASS via exact identity signature). Abort on any FAIL.
  - *Execution note (2026-07-26):* `CHK_frozen_rpcs_present` went through two rejected probe forms on staging before
    landing on the correct one, while the live frozen RPC was intact throughout (owner postgres, canonical 11-arg
    sig, ACLs unchanged; D2 never references that RPC): (1) `to_regprocedure(text)` false-negatived on the
    `save_reconciliation_with_commitments` numeric/timestamptz arg-string parse; (2) `pg_get_function_identity_arguments()`
    emitted parameter names+types so the types-only equality compare failed. Final form uses
    `pg_catalog.oidvectortypes(p.proargtypes)` (canonical types-only) + owner, in both catalog-verify and validation
    D2-FROZEN. Verification-only change; **no staging object and no D2 RPC was modified or reinstalled.** Owner's
    rerun returned both rows PASS.
- **C. Fixture install + verification** — run `…-staging-fixture.sql`. Requires an existing active staging owner
  (real `auth.users` identity) — the fixture reuses it and HARD STOPs if none exists (provision via Supabase
  Dashboard first). Expect: no HARD STOP; FIX-CHECK basis=31, snapshots≥9, reservable goals≥2, implicit-reservable=0,
  owner is_owner()=true (for the reused owner); ledger shows the **19** owned refs (1 weekly_reconciliations +
  9 goal_registry + 9 goal_funding_snapshots; NO app_users). Abort on any HARD STOP or WARNING.
  - *Execution note (2026-07-26):* first Checkpoint-C attempt hit `ERROR 23503 app_users_auth_user_id_fkey` — staging
    `app_users.auth_user_id` has a FK to `auth.users` (the v1.4 spec showed none). The failed transaction rolled back
    fully (no owner/auth/ledger residue, confirmed). Fixture redesigned to REUSE an existing owner (no synthetic
    app_users/auth row); D2-ROLE-2 now uses an absent uid. No prohibited action (no auth.users insert, no FK/constraint
    change, no weakened authz). Doc/fixture change only; no D2 RPC or D1 schema touched.
  - *Execution note 2 (2026-07-26):* second Checkpoint-C attempt (after all preconditions PASSED — residue 0/6, owner
    precheck 1 owner `aherndon6@gmail.com`, env staging) hit `ERROR 23514 weekly_reconciliations_balance_basis_check`.
    `balance_basis` is `TEXT CHECK IN ('posted_current_balance','available_balance','unknown')` (5F-1) — the fixture
    inserted the numeric sentinel `3131.31` into it. Fixed: fixture week-31 row and validation I-F4 week-32 row now
    use `balance_basis='unknown'`; the fixture-ownership sentinel remains the numeric `chk=3131.31`. Fixture/validation
    doc change only; no D2 RPC or D1 schema touched.
- **D. Automated validation** — run `…-staging-validation.sql`. Expect: every PASS line present, **no** `FALSE-PASS
  RISK`, no unexpected SKIP; D2-CLEAN reservations/batches = 0. Abort on any FAIL/FALSE-PASS.
  - *Execution note 4 (2026-07-26):* Checkpoint-D run halted (correctly) at `N10 FAIL` (destination-change replay
    not treated as a conflict). Classified **C — test-setup defect, not an RPC defect.** `goal_registry` has RLS
    enabled with only an `anon` SELECT policy and NO UPDATE policy (phase-6a-goal-registry-spec.md:66–75), so N10's
    transient `UPDATE goal_registry SET dest` executed under the simulated `authenticated` role was silently
    filtered to 0 rows — the destination never changed, so the replay correctly returned idempotent. The RPC's F5
    logic is correct (replay recomputes registry dest and compares it to the stored `destination_account_ref` via
    `IS NOT DISTINCT FROM` before the idempotent return; a genuine drift → conflict). The identical latent defect
    existed in E4/E5 (`UPDATE goal_registry`) and L-BPSR (`UPDATE cash_commitments`), which hadn't executed yet.
    Fix (test-only): all five scaffolding UPDATEs now run under the ADMIN session role (`session_user`, RLS bypass),
    bracketed back to `authenticated` for the RPC calls; N10 asserts the UPDATE affected 1 row. RPC/D1 untouched.
  - *Execution note 3 (2026-07-26):* first Checkpoint-D run halted (correctly) at `N4 FALSE-PASS RISK` — a STALE test
    expectation, not an RPC defect. The 11/10 hardening unified amount validation into one range guard (1..1e8), so
    `amount_cents=0` (digit-valid) is rejected as `out of range` rather than the pre-hardening `amount_cents must be`
    wording N4 still expected. Fixed N4 to assert `%out of range%` (lower-bound counterpart to N-AMT-range's upper
    bound); exact-reason assertion preserved, RPC unchanged. Prior blocks rolled back as designed (no residue; fixture
    intact) — the halting DO subtransaction rolls back its own work, and negative tests create nothing.
- **E. Two-session concurrency** — run `…-staging-concurrency.sql` across two tabs in the A1→B1→A2→B2→V→CLEANUP
  order. Expect: PASS-A1, PASS-B1 (SQLSTATE 55P03), PASS-A2, PASS-B2 (single-active-batch), PASS-C (count=1),
  PASS-CLEAN (0/0). Abort if B1 succeeds, times out for another reason, B2 succeeds, or count≠1.
- **F. Fixture teardown + residue** — run `…-staging-fixture-teardown.sql`. Expect: all `RES_*` = 0 (incl. ledger dropped).
  - *Hardening (2026-07-26, second review):* teardown converted from display-only manifest to ENFORCED. In-transaction
    HARD assertions BEFORE any delete: ledger manifest 9/9/1/19 with no unknown kinds; recon ref exactly `31` + week-31
    sentinel `chk=3131.31`; the nine goal refs are the exact `d2fix_g01..g09`; the nine snapshot refs are exactly
    `2026:31:<those ids>`; every ledger ref resolves to a business row; snapshot goal-set == ledgered goal-set; and
    global D2 residue already 0 (ASSERTED, not attribute-deleted — the old unledgered basis/source sweep is removed).
    Deletes assert exact ROW_COUNT (snapshots=9, recon=1, goals=9); zero-residue asserted; `DROP TABLE` (no IF EXISTS,
    existence required); ledger-absence asserted — all before COMMIT. Staging guard hardened (>=1 row, every row
    env=staging). Any deviation aborts the transaction with nothing deleted. Teardown-harness only; no RPC/schema/D1/frozen change.
  - *Execution note (2026-07-26):* The submitted batch failed during SQL parsing at the final post-commit
    evidence query (`42601 syntax error at or near "check"` — the six-row residue SELECT aliased its label column
    `check`, a reserved keyword, and `ORDER BY check` is invalid). PostgreSQL therefore executed none of the batch,
    including BEGIN or any destructive statement. Read-only verification confirmed that the fixture remained fully
    intact: ledger + 9 goals + 9 snapshots + 1 reconciliation. This incident did not exercise the teardown
    transaction's rollback behavior; it was a teardown-harness parse-time syntax defect. Fixed: alias renamed to
    `check_name` (SELECT + ORDER BY). `ORDER BY check` existed only in the teardown; `AS check` as an output label
    elsewhere (catalog-verify/validation) is valid and already ran at B/D. Harness-only.
  - *Hardening 2 (2026-07-26, third review — three-valued-logic + set-semantics):* added FIRST an integrity guard
    rejecting NULL `kind`/`ref` and any duplicate `(kind,ref)` (defense-in-depth over the ledger's `NOT NULL` +
    `PRIMARY KEY(kind,ref)`, since `CREATE TABLE IF NOT EXISTS` would not re-constrain a foreign table); changed the
    reconciliation-ref check to `IS DISTINCT FROM '31'`; made the goal/snapshot allowed-set checks count-based
    (`count(*)<>0`, string_agg for diagnostics only); and added `count(DISTINCT ref)=9` for goal_registry and
    goal_funding_snapshots to prove nine UNIQUE identities per kind.
- **G. Rollback proof** — run `…-staging-rollback.sql`, then `…-staging-post-rollback-verify.sql`. Expect: preflight
  NOTICE `batches=0, au11_reservations=0, d2fix_goals=0, reservable_true=0 [none]`; no HARD STOP; commit; the 4-row
  result `RB_functions_absent=0 / RB_column_absent=0 / RB_batches=0 / RB_reservations=0`; then the post-rollback
  verify shows every `D1_*` and `FROZEN_*` = 1 and `D2_reservable_column_absent` = 0. Abort on any HARD STOP or
  `55P03` lock timeout (contended lifecycle lock — retry when quiescent). (After G: D2 RPCs + column GONE, D1 + frozen
  intact — proves exact reversibility.)
  - *Hardening (2026-07-26, external review):* added the RPC advisory-lock acquisition (identical key
    `hashtextextended('au11_disc:2026:truist_checking',0)`) held through COMMIT to close the preflight→DDL race;
    complete-install precondition with exact `oidvectortypes` signatures + no-overload counts; bare DROPs (no
    IF EXISTS); metadata guard no longer excludes `d2fix_%` and blocks on ANY `reservable=true`; corroboration
    expanded to batches + reservations; and D1/frozen integrity in the dedicated post-rollback-verify.
  - *Hardening 2 (2026-07-26, second external review):* the rollback now proves a CONTROLLED TRANSITION from the
    expected installed state — a pre-destructive block (A) certifies the D1/frozen foundation with the SAME critical
    machine-checkable assertions as the post-verifier (batch base table; cash_commitments D1 columns exact
    type+nullability; chk_au11_reservation_shape exactly one validated CHECK on cash_commitments with the expected
    CANONICALIZED definition; uix_one_active_batch unique/partial with exact key columns + canonicalized predicate;
    frozen repair/save_recon exact `oidvectortypes` sigs + no overloads) BEFORE the D2-install cert (B), lock (C),
    residue cert (D), bare DROPs, and in-transaction absence cert (E). Constraint/index defs compared in a canonical
    form (lowercase; `::text`/parens/whitespace stripped) — machine-exact, robust to PG rendering, fail-closed with
    actual-vs-expected emitted. Standalone post-rollback verifier retained (independent post-state recertification).
- **H. Clean reapply + final validation + FINAL FIXTURE REMOVAL** — re-run **A → B → C → D → E → F**. Expect:
  identical green at each, and F (teardown) leaves all `RES_*`=0. This proves reversibility *and* redeployability
  AND ends with the fixture removed. Then run a **final-state check** (I) below.
- **I. Final-state verification (closure)** — after H, re-run `…-catalog-verify.sql` and confirm: RPCs + `reservable`
  present (CHK_* PASS); `CHK_residue` batches=0 / reservations=0; no fixture rows (`goal_registry` has no `d2fix_%`;
  no week-31 fixture reconciliation; `to_regclass('public.d2_fixture_ledger') IS NULL`). The pre-existing staging
  owner (reused, never a fixture artifact) remains untouched. This is the authoritative end state.

### Execution-state contract after Checkpoint H/I (Req 4)
The **preferred and adopted** final staging state is: **`goal_registry.reservable` INSTALLED · the three D2 RPCs
INSTALLED · fixture COMPLETELY REMOVED · zero reservation batches · zero au11 cash_commitments · no fixture
registry / snapshot / reconciliation / ledger rows · the reused pre-existing owner untouched · staging ready for D3
authorship.** The fixture does NOT remain installed after final proof (checkpoint H ends with teardown F; checkpoint
I verifies zero fixture residue). The fixture never creates an app_users/auth row, so there is no owner artifact to
remove. The transient install-then-rollback (G) proves reversibility; the reapply (H) restores the intended metadata+RPC
state without the fixture.

## Confirmations
No production; no SQL executed by Claude; no client/caller; no D3 composite work; no canonical status change;
frozen surfaces untouched; operational hold (incl. Wendy IRA) unchanged.
