# Phase 5G-1D Slice 2 — Gate 2 staging execution package (RUNBOOK)

**STAGING ONLY** (`herndon-fos-staging`, `pkwotgqivgaapwuqgwqb`, `system_identifier = 7656985631720456337`,
`public.app_environment` = exactly one row `env='staging'`). **Authored, NOT executed.** No SQL or
HTTP/PostgREST call in this package has been run. **Balance-free** — every value is clearly synthetic.
**Production is never touched.**

This runbook orchestrates the cleared Gate-2 matrix in `docs/phase-5g-1d-rls-smoke-gate2.md` (the
matrix is authoritative and is **preserved unchanged**). It splits execution into ten operator-gated
sub-phases; **no sub-phase auto-flows into the next** — each ends with a **STOP ▲ (operator review)** point.

---

## 0. Grounding facts (verified against the committed repo at HEAD `ff80971`)

- **Wrapper** `public.save_weekly_closeout_with_snapshots(p_week_num INT, p_model_year INT, p_chk NUMERIC,
  p_sav NUMERIC, p_amx NUMERIC, p_tax NUMERIC, p_lc NUMERIC, p_balance_basis TEXT, p_new_commitments JSONB,
  p_patched JSONB, p_snapshot_rows JSONB, p_mode TEXT, p_expected_count INT) RETURNS JSONB`.
  Note the parameter order: **`p_week_num` first, then `p_model_year`**.
- **Option B** `public.correct_goal_funding_snapshot(p_model_year INT, p_week_num INT, p_goal_id TEXT,
  p_new_funded_amount NUMERIC, p_expected_prior NUMERIC, p_note TEXT) RETURNS JSONB` (owner-only in body).
- **Deployed recon RPC** `save_reconciliation_with_commitments(p_week_num,p_model_year,p_chk,p_sav,p_amx,
  p_tax,p_lc,p_balance_basis,p_recorded_at,p_new_commitments,p_patched)` — **ignores `p_recorded_at`, stamps
  `recorded_at=NOW()`**; ON CONFLICT `(week_num)`. `weekly_reconciliations` has **no `model_year` column**.
- **Deployed snapshot RPC** `save_goal_funding_snapshots(INT,INT,JSONB)` — upsert on `(model_year,week_num,
  goal_id)`; requires the week reconciled; rejects `auto` goals (`adam_401k`) and excluded ids
  (`wewe_rccl,wewe_dcl,taxable_etf`).
- **`goal_funding_snapshots`**: PK `id`; UNIQUE `(model_year,week_num,goal_id)`;
  `goal_id → goal_registry(id) ON DELETE RESTRICT` (the ONLY FK among the three write tables);
  `source ∈ {opening_anchor,reconciliation,correction}`.
- **`cash_commitments`**: PK `id`; UNIQUE `expected_item_id`; create requires `origin_model_week = p_week_num`,
  `model_year = 2026`, `payee`, `commitment_class ∈ {credit_card_payment,rent,bill_payment,tax_transfer,
  savings_transfer,manual_hold,other_transfer}`, `required_or_discretionary ∈ {protected_required,
  discretionary_deployment,forecast_only}`, `amount_cents > 0`; `source_account` allow-list = `truist_checking`
  only; patch keyed by `id` with `origin_model_week <= p_week_num`.
- **Eligible nine** (snapshot goals): `adam_ira, wendy_ira, wendy_sep, alaska, bailey_529, bryce_529,
  preston_529, bryce_vehicle, christmas_cruise`.
- **Advisory namespace** `1734501000`.

### Synthetic Week-5 opening anchor (current staging state — the immutable baseline)
Nine `opening_anchor` rows at `model_year=2026, week_num=5`, each note contains `[STAGING-FIXTURE]`:
`adam_ira=100, wendy_ira=200, wendy_sep=300, alaska=400, bailey_529=500, bryce_529=600, preston_529=700,
bryce_vehicle=800, christmas_cruise=900`. No Week-5 `wewe_*` rows. No snapshot rows outside Week 5.

---

## 1. Identities & secrets (LOCAL ONLY — never committed)

| Role | Maps | UUID (LOCAL copies only) |
|------|------|--------------------------|
| **owner** (Adam) | `is_owner()=true`, `can_write_financials()=true` | `<ADAM_UID>` |
| **household_admin** (Wendy) | `is_owner()=false`, `can_write_financials()=true` | `<WENDY_UID>` |
| **anon** | no auth | (anon key only) |

Gate-2 RPC calls are made **through PostgREST** (`POST {SUPA_URL}/rest/v1/rpc/<fn>`, `Authorization: Bearer
<token>`) so the real grant/RLS/SECURITY-DEFINER path is exercised — the SQL editor bypasses RLS. The
per-identity **access tokens, anon key, and `SUPA_URL`** live only in the local filled copy of
`phase-5g-1d-gate2-exec-template.sh` and are **never committed**. Committed templates use placeholders
(`<ADAM_UID>`, `<WENDY_UID>`, `{{SUPA_URL}}`, `{{ANON_KEY}}`, `{{OWNER_TOKEN}}`, `{{WENDY_TOKEN}}`).

**Prohibited to commit:** UUID-filled execution SQL, access tokens, Supabase keys, local env values.

**Local fill-copy workflow (single control against overlooked placeholders — see §Placeholder guards):**
1. `bash phase-5g-1d-gate2-fill-check.sh init <local-dir>` — copies every committed `gate2-*.sql`/`.sh` into
   `<local-dir>` as `*.FILLED.local.*` (chmod 600). Edit **only** those; put real FP-3 md5s, `recorded_at`
   literals, `{{OWNER_UID}}`, `{{PATCH_ID}}`, tokens, and keys there — never in a committed file.
2. `bash phase-5g-1d-gate2-fill-check.sh check <local-dir>` — **hard-stops (exit 1)** if any `{{...}}` /
   `<ADAM_UID>` / `<WENDY_UID>` remains. Run it after filling and again before each sub-phase.
3. In the harness, `gate2_preflight` additionally hard-stops if a shell placeholder is unfilled; the G2-20b
   pre-seed carries an in-SQL `{{OWNER_UID}}` guard. Read-only POST blocks fail closed on an unresolved
   placeholder (md5 mismatch / bad `::timestamptz` cast), so a placeholder can never silently pass.

---

## 2. Package files

| Sub-phase | File | Kind | Role |
|---|------|------|------|
| — | `phase-5g-1d-gate2-runbook.md` | md | this runbook |
| — | `phase-5g-1d-gate2-fingerprints.sql` | SQL (read-only) | canonical FP-3 whole-state capture (run before/after every reject) |
| 1 | `phase-5g-1d-gate2-inspect.sql` | SQL (read-only) | current-state inspection & capture |
| 2 | `phase-5g-1d-gate2-setup.sql` | SQL (read-only assert) | precondition gate (anchor complete, no Week-6+ state, grant active) |
| 3 | `phase-5g-1d-gate2-core.sql` | SQL (read-only capture/assert) | G2-1, G2-2, G2-3, G2-4, G2-5, G2-6, G2-7, G2-8 |
| 4 | `phase-5g-1d-gate2-reopen.sql` | SQL (read-only capture/assert) | G2-9, G2-10b, G2-10, G2-11, G2-12, G2-13 |
| 5 | `phase-5g-1d-gate2-optionb.sql` | SQL (read-only capture/assert) | G2-14, G2-15, G2-16a, G2-17 (+ G2-16b block, run in Sub-phase 7) |
| 6 | `phase-5g-1d-gate2-monotonic.sql` | SQL (controlled mutation + assert) | G2-19a (run in Sub-phase 3), G2-19b, G2-19c, G2-19d |
| 7 | `phase-5g-1d-gate2-halfclose.sql` | SQL (controlled mutation + assert) | CLOSE-W8, **G2-16b**, CLOSE-W9, G2-18, G2-18b (+ mandatory blocked-advance) |
| 8 | `phase-5g-1d-gate2-20a-create-rollback.sql` | SQL (mutation: trigger) | G2-20a |
| 9 | `phase-5g-1d-gate2-20b-patch-rollback.sql` | SQL (mutation: trigger + pre-seed) | G2-20b |
| 10 | `phase-5g-1d-gate2-teardown.sql` | SQL (mutation: cleanup + restore) | teardown & restore |
| — | `phase-5g-1d-gate2-exec-template.sh` | shell template | PostgREST calls + response-classification asserts (placeholders) |
| — | `phase-5g-1d-gate2-fill-check.sh` | shell tool | local fill-copy init + unresolved-placeholder hard-stop scan |

Every executable `.sql` opens with the **exact committed staging fingerprint guard** (sysid
`7656985631720456337`, `app_environment` total=1 AND `env='staging'`=1; production and any
unknown/ambiguous environment hard-stop). Read-only artifacts wrap in `BEGIN READ ONLY … COMMIT`.

**Whole-state assertions (item 7):** every rejection/adjudication asserts the canonical **FP-3** whole-state
fingerprint (`FP_CC` all commitments, `FP_RECON` all reconciliations incl. `recorded_at`, `FP_SNAP` all 2026
snapshots across every week) is unchanged — not a focal-row or count-only check. A test that legitimately
mutates one surface asserts the other two FP-3 members unchanged plus the exact focal change. The three
expressions are defined once in `phase-5g-1d-gate2-fingerprints.sql` and inlined in each POST block.

---

## 3. Week allocation (avoids state collisions across the matrix)

Because several tests mutate persisted state and depend on prior tests' state, weeks are allocated so no
test invalidates another. Two couplings drive the order: (i) **Option B on an earlier week is bounded by
later closed weeks**, so wk7's reopen + Option B must complete **before** wk8+ are closed; (ii) **the
monotonic floor for a week is its goal's latest effective prior**, so payloads must respect corrected
priors. **Follow this exact order.**

| Week | Purpose | Tests that read/write it |
|------|---------|--------------------------|
| wk5 | opening anchor (immutable baseline) | prior for wk6 monotonicity; G2-19d removes+restores one row |
| wk6 | first owner closeout | G2-19a (anchor-prior monotonicity, **before** close), then G2-3/4/5/6; G2-13 older-week reopen target |
| wk7 | Wendy closeout → reopen → Option B | G2-8, G2-9/10b/10/11/12/13, G2-14/15/16a/17 (**before** wk8+ close); **G2-16b after CLOSE-W8** |
| wk8 | non-contiguous probe → monotonic rejects → real close | G2-7 (skip probe, **before** wk7 closed), G2-19b (recon prior), G2-19c (correction prior) — all rejects; then real close (CLOSE-W8) in half-close |
| wk9 | half-close repair | CLOSE-W9 → G2-18 (one-missing, + blocked-advance) → reset → G2-18b (zero-snapshot, + blocked-advance) |
| wk10 | blocked-advance probes (reject) then atomic rollback | G2-18/18b blocked-advance (reject, no state), then G2-20a (CREATE) + G2-20b (PATCH) — both roll back, week stays open |
| wk5 | broken-chain probe | G2-19d removes one wk5 anchor row, runs a later week → anchor-incomplete hard-stop; restores in-test |

**G2-7 ordering note:** "skip wk7" only reads as non-contiguous while wk7 is still open. Run G2-7 in
Sub-phase 3 **before** G2-8 closes wk7 (complete=1 → next=wk7; wk8 is a skip).

**Monotonicity note (all G2-19 are rejects — no week is left closed by them):**
- **G2-19a** prior=`opening_anchor`: targets **wk6, run before G2-3 closes wk6** (latest prior = wk5 anchor).
  Submit `adam_ira` below its anchor 100 → reject.
- **G2-19b** prior=`reconciliation`: targets **wk8** after wk7 closed. Lower an **uncorrected** goal
  (`wendy_ira`, wk7=200 reconciliation) below its prior while every other goal is ≥ its prior → reject.
- **G2-19c** prior=`correction`: targets **wk8** reusing wk7's Option-B-**corrected** `adam_ira` (=120,
  `source=correction`, from G2-14) as the prior. Submit `adam_ira` below 120 → reject (proves the check
  uses the effective row regardless of source).
- **G2-19d** broken chain: remove one wk5 eligible anchor row, run any later week → STEP-3 anchor-incomplete
  hard-stop; the removed row is **restored in the same artifact**.

Because G2-19b/c only need wk7's persisted priors and are rejects, they run **after** the wk7 reopen +
Option B sub-phases and **before** wk8 is really closed in half-close.

---

## 4. Every cleared test → assigned artifact & caller

| # | Test | Caller | Artifact | Persisted effect after test |
|---|------|--------|----------|------------------------------|
| G2-1 | anon wrapper wk6 | anon | core | none (pre-write reject) |
| G2-2 | unauthorized authenticated wrapper wk6 | no-app_users token | core | none (pre-write reject) |
| G2-3 | new closeout wk6 (**run after G2-19a**) | owner | core | **wk6 closed** (9 `reconciliation` rows, recon row) |
| G2-4 | identity retry wk6 (empty arrays) | owner | core | none (idempotent) |
| G2-5 | GFA01 non-empty resubmit wk6 | owner | core | none (`GFA01`) |
| G2-6 | changed-value resubmit wk6 | owner | core | none (hard-stop route-to-reopen) |
| G2-7 | non-contiguous wk8 (wk7 open) | owner | core | none (pre-write reject) |
| G2-8 | Wendy normal close wk7 | household_admin | core | **wk7 closed** |
| G2-9 | Wendy approved_reopen wk7 | household_admin | reopen | none (`42501`) |
| G2-10b | reopen wk7 changed recon + non-empty commitment (**before G2-10**) | owner | reopen | none (branch-E "must not carry commitment operations" reject) |
| G2-10 | genuine reopen wk7 (changed recon, empty arrays) | owner | reopen | **wk7 recon re-stamped** (recorded_at later; snapshots unchanged) |
| G2-11 | identity reopen wk7 (identical recon, empty) | owner | reopen | none (idempotent) |
| G2-12 | reopen wk7 identical recon, non-empty | owner | reopen | none (`GFA01`) |
| G2-13 | reopen older week (wk6, non-latest) | owner | reopen | none (reject) |
| G2-14 | Option B correct wk7 `adam_ira` 100→120 within bounds | owner | optionb | **one wk7 `correction` row** |
| G2-15 | Option B stale expected_prior wk7 | owner | optionb | none (reject) |
| G2-16a | Option B below preceding bound (new 50 < wk6 100) wk7 | owner | optionb | none (reject) |
| G2-16b | Option B above following bound (new 130 > wk8 120) wk7 — **after CLOSE-W8, in Sub-phase 7** | owner | optionb (run in halfclose seq) | none (reject) |
| G2-17 | Wendy Option B | household_admin | optionb | none (`42501`) |
| G2-18 | half-close one-missing repair wk9 (+ blocked-advance) | owner | halfclose | wk9 closed then repaired (net: closed) |
| G2-18b | half-close zero-snapshot repair wk9 (+ blocked-advance) | owner | halfclose | wk9 reconciliation-only then repaired |
| G2-19a | monotonicity, anchor prior, wk6 below-anchor (before G2-3) | owner | monotonic | none (reject) |
| G2-19b | monotonicity, reconciliation prior, wk8 lower `wendy_ira` below wk7=200 | owner | monotonic | none (reject) |
| G2-19c | monotonicity, correction prior, wk8 lower `adam_ira` below wk7 corrected=120 | owner | monotonic | none (reject) |
| G2-19d | broken chain: remove wk5 anchor row, run later week | owner | monotonic | none (hard-stop; row restored in-test) |
| G2-20a | atomic rollback — commitment CREATE wk10 | owner | 20a | none (full rollback) |
| G2-20b | atomic rollback — commitment PATCH wk10 | owner | 20b | none (full rollback) |

Strict-input, timestamp, atomicity, source, note, and no-unrelated-change assertions from the cleared
package are embedded **inside each artifact** at the relevant test (not omitted). Timestamp rules:
- G2-3 → `recorded_at` is a server `NOW()` (not client-supplied).
- G2-10 → `recorded_at` **strictly later** than pre-reopen; pre-value retained only in the captured evidence.
- G2-4/G2-11/G2-5/G2-12/G2-10b/G2-18/G2-18b/G2-19 → `recorded_at` **unchanged** (recon RPC not called / rejected first).

### Response-assertion map (harness classification — item 1; each `G2_*` asserts its class, not just prints)
| Test(s) | Harness helper | Proves |
|---|---|---|
| G2-3, G2-8, G2-14, CLOSE-W8/W9 | `expect_success` | HTTP 200 + `ok:true` |
| G2-4, G2-11 | `expect_success_idem` | 200 + `ok:true` + `idempotent:true` |
| G2-10 | `expect_reopened` | 200 + `ok:true` + `reopened:true` |
| G2-18, G2-18b | `expect_repaired` | 200 + `ok:true` + `repaired:true` |
| G2-1 | `expect_anon_denied` | grant-layer denial (HTTP 401/403/404) — the no-anon path |
| G2-2, G2-9, G2-17 | `expect_authz_reject` | `code=42501` (owner/writer authorization) |
| G2-5, G2-12 | `expect_gfa01` | `code=GFA01` + `hint=REQUIRES_SUPERVISED_ADJUDICATION` |
| G2-6, G2-7, G2-10b, G2-13, G2-15, G2-16a, G2-16b, G2-19a, G2-19b, G2-19c, G2-19d, blocked-advance | `expect_domain_reject "<phrase>"` | HTTP 400 non-auth + the exact deployed RAISE phrase (proves the *domain* guard, not a transport/auth/input failure) |
| G2-20a, G2-20b | `expect_atomic_fail` | HTTP 400 + `ATOMIC-TEST synthetic failure` (the injected trigger, not an earlier guard) |

Domain phrases are matched verbatim against the deployed RAISE messages: `monotonic violation` (G2-19a/b/c),
`opening anchor incomplete at week 5` (G2-19d), `already fully closed with different values` (G2-6),
`not the next contiguous closeout week` (G2-7, blocked-advance), `must not carry commitment operations`
(G2-10b), `not the latest completed week` (G2-13), `stale expected_prior` (G2-15), `below preceding effective
value` (G2-16a), `above following effective value` (G2-16b).

---

## 5. Mutation discipline (applies to every mutating test)

Each mutating test documents & implements, in order:
1. **Pre-state capture** — exact rows (reconciliation, cash_commitments, snapshots) for the target week +
   `recorded_at`, saved by the operator from the artifact's `PRE` block output.
2. **Synthetic call payload** — the exact `p_*` body (in `phase-5g-1d-gate2-exec-template.sh`).
3. **Expected mutation or rollback** — stated per test.
4. **Post-state assertion** — the artifact's `POST` block hard-stops on any deviation.
5. **No-unrelated-change assertion** — other weeks, the two `wewe_*` rows, and untargeted goals proven
   byte-unchanged.
6. **Cleanup / restoration** — per test (half-close reset; anchor row restore; G2-20 trigger drop; final
   teardown removes all Week-6+ synthetic state).

**Synthetic markers only** (never household balances/production data):
`[STAGING-FIXTURE][GATE2]` (notes), `__GATE2_*` (payees/expected_item_ids), `__ATOMIC_TEST_WD__`
(G2-20a create), `__ATOMIC_TEST_PATCH__` (G2-20b patch), `_gf_atomic_test_fail` / `_gf_atomic_test_fail_trg`
(G2-20 trigger/helper), `_gate2_wk5_backup` (G2-19d anchor backup). **Synthetic value ranges:** snapshot
`funded_amount` values are the round-hundreds anchor set 100–900, plus the Option-B-corrected `120` (wk7/wk8/wk9
`adam_ira` floor), the Option-B reject probes `50` and `130`, and the atomic sentinel `424242.42`; reconciliation
balances are round thousands (`p_chk..p_lc` = 1000–5000, with `1001` as the changed-reopen variant); commitment
`amount_cents` are small synthetic integers (100, 222). No value resembles a household balance.

---

## 6. G2-20 discipline (atomic rollback injection)

Neither deployed RPC is modified. The only mechanism is the **cleared temporary staging trigger/helper**
`public._gf_atomic_test_fail()` + `_gf_atomic_test_fail_trg` on `public.goal_funding_snapshots`
(BEFORE INSERT; raises when `NEW.funded_amount = 424242.42`). For each of G2-20a / G2-20b the artifact:
1. **asserts absent** before setup (`to_regproc`/`pg_trigger`) — if either exists, **STOP the suite**;
2. installs helper then trigger;
3. calls the wrapper (PostgREST) with the sentinel row `424242.42` so the snapshot INSERT trips the
   trigger **after** the reconciliation RPC has already run (persisting the create/patch);
4. proves **full rollback** — no wk-N reconciliation row, no wk-N snapshots, and the commitment
   create/patch reverted;
5. **drops the trigger first, the helper second**;
6. **asserts both absent**;
7. includes **emergency idempotent cleanup** (`DROP … IF EXISTS` ×2, owner) for operator disconnect.

G2-20a proves rollback of a commitment **CREATE** (`__ATOMIC_TEST_WD__` still absent after).
G2-20b proves rollback of a commitment **PATCH** (`__ATOMIC_TEST_PATCH__` fields identical to pre-state).

---

## 7. Teardown (`phase-5g-1d-gate2-teardown.sql`) — restore inert baseline

FK-safe order (only FK among the write tables is `goal_funding_snapshots.goal_id → goal_registry`; the
three write tables have no FKs to each other, so intra-table order is free — this order is chosen for
clarity/safety):
1. drop any residual G2-20 trigger then helper (idempotent);
2. delete all synthetic **Week-6+** `goal_funding_snapshots` rows;
3. delete all synthetic **Week-6+** `weekly_reconciliations` rows;
4. delete all synthetic commitment effects (marked `__GATE2_*` / `__ATOMIC_TEST_*`);
5. **genuinely restore the exact Week-5 nine-row synthetic opening anchor** after any interruption:
   (a) if a surviving `_gate2_wk5_backup` exists, re-insert its rows `ON CONFLICT DO NOTHING` (never
   overwrite); (b) reconstruct any still-missing row from the repository-grounded canonical baseline
   (values 100–900, `source='opening_anchor'`, `[STAGING-FIXTURE]`), again never overwriting; (c) validate
   the exact nine values/sources/markers; (d) drop the backup **only** after validation succeeds;
6. prove **no Week-6+ test rows remain** and the **Week-5 baseline is exact**;
7. run `phase-5g-1d-ungrant.sql` (**the only grant-change mechanism** — not re-authored here);
8. re-run `phase-5g-1d-validation.sql` — prove both new functions **inert** again and the deployed RPC
   definitions **byte-unchanged** (MD5s: recon `1bfde751ac647c5e9a25ba168d08150c`, snapshot
   `154231b3f180349ec328f08ccbe77076`).

**Deferred:** cleanup of the Adam/Wendy staging `auth`/`app_users` fixtures is **explicitly deferred to a
later, separately approved step**. This package does **not** delete those two identities (no existing
authoritative cleanup file requires it here).

---

## 8. Recommended execution order & STOP points

> Each **STOP ▲** is an operator review gate. Do not proceed until the prior sub-phase's assertions all
> passed and the operator has reviewed the captured evidence.

0. **Prereqs already in place** (per the provided state): registry fixture seeded, E1 deployed, Week-5
   anchor seeded, migration deployed + inert, **temporary grant currently active**, Gate 1 passed.
1. **Sub-phase 1 — inspect** (`gate2-inspect.sql`, read-only): capture the full current state. **STOP ▲**
2. **Sub-phase 2 — setup gate** (`gate2-setup.sql`, read-only): assert anchor complete + zero Week-6+
   state + grant active + no G2-20 objects present. **STOP ▲**
3. **Sub-phase 3 — core** (`gate2-core.sql` + `gate2-monotonic.sql` G2-19a block + exec template): G2-1,
   G2-2, **G2-19a (before G2-3)**, G2-3, G2-4, G2-5, G2-6, **G2-7 (before G2-8)**, G2-8. **STOP ▲**
4. **Sub-phase 4 — reopen** (`gate2-reopen.sql`): G2-9, **G2-10b (before G2-10)**, G2-10, G2-11, G2-12,
   G2-13. G2-10b uses a *changed* recon + non-empty commitment so it enters the genuine-reopen branch where
   the "must not carry commitment operations" guard lives (an identical-recon non-empty resubmit is G2-12's
   GFA01). G2-10 then applies the genuine reopen (recon re-stamped; snapshots unchanged). **STOP ▲**
5. **Sub-phase 5 — Option B** (`gate2-optionb.sql`): G2-14 (corrects wk7 `adam_ira`→120), G2-15, **G2-16a**
   (below preceding), G2-17. Runs **before** wk8+ close so the wk7 correction is unbounded above.
   **G2-16b is deferred to Sub-phase 7** (it needs the wk8 following bound). **STOP ▲**
6. **Sub-phase 6 — monotonicity** (`gate2-monotonic.sql`): G2-19b (wk8, recon prior), G2-19c (wk8,
   correction prior via wk7's corrected `adam_ira`), G2-19d (wk5 remove+restore). All rejects — wk8 stays
   open. (G2-19a already run in Sub-phase 3.) **STOP ▲**
7. **Sub-phase 7 — half-close** (`gate2-halfclose.sql`): **CLOSE-W8** → **G2-16b** (`gate2-optionb.sql`
   above-following reject, now that wk8=120 is the following bound) → **CLOSE-W9** → G2-18 (one-missing
   repair) → **G2-18 blocked-advance** (wk10 cannot close) → reset → G2-18b (zero-snapshot repair) →
   **G2-18b blocked-advance**. **STOP ▲**
8. **Sub-phase 8 — G2-20a** (`gate2-20a-create-rollback.sql`): target wk10 (next contiguous, now that wk9 is
   fully closed). trigger install → PostgREST CREATE call with sentinel → prove full rollback + FP unchanged
   → drop. **STOP ▲**
9. **Sub-phase 9 — G2-20b** (`gate2-20b-patch-rollback.sql`): pre-seed `__ATOMIC_TEST_PATCH__` at wk10 →
   trigger → PostgREST PATCH call with sentinel → prove full rollback + pre-seed byte-identical + FP
   unchanged → drop + remove pre-seed. **STOP ▲**
10. **Sub-phase 10 — teardown** (`gate2-teardown.sql`): cleanup Week-6+ + genuinely restore wk5 anchor
    (from `_gate2_wk5_backup` if present, else reconstruct missing rows from the canonical baseline; never
    overwrite) + ungrant + re-validate. **STOP ▲**

**Fingerprint capture cadence:** before each rejection/adjudication call, run
`phase-5g-1d-gate2-fingerprints.sql` to capture FP-3; after the call, the test's POST block compares. Recapture
after every legitimate mutation (G2-3, G2-8, G2-10, G2-14, each CLOSE/repair) so the next reject compares
against the then-current state.

**Never** run the ungrant script before Sub-phase 10. **Never** run Gate 2 until explicitly approved —
this package is authored only.
