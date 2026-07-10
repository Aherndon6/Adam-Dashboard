# Phase 5G-1C-2 — E2 First-Anchor Seed Execution Gate: Runbook

> **Reviewed artifact.** This file IS the E2 runbook (the seed counterpart to the
> Fable-cleared E1 runbook `docs/phase-5g-1c-2-e1-runbook.md`). It is the committed
> reference for the E2 execution gate. **Nothing in this file has been executed.**
> No Supabase access, no SQL, no seed, no Value-Card fill. E2 does not start until
> the approval chain in §0 clears.
>
> Status: **PRE-EXECUTION — plan/spec cleanup only.** E1 is COMPLETE and GREEN
> (production holds `goal_funding_snapshots` + `save_goal_funding_snapshots`,
> schema-only and EMPTY). E2 is the **first `opening_anchor` seed** — the go-live
> event that makes the shipped C3 overlay stop being inert.

---

## 0. Approval chain — read first (E2 cannot start until this clears)

E2 is a **separate, explicit** approval gate from E1. E1 clearance does **not**
carry into E2. E2 also has an extra gate E1 did not: **First-Anchor Value Card
approval** (the nine seeded values).

1. **ChatGPT/Fable review gate.** E2 execution **requires review of THIS committed
   runbook file** and of the **First-Anchor Value Card** (§4) — and resolution of
   every correction/finding raised. No preflight-recheck, seed, or seed-validation
   runs against production until this file and the Value Card are cleared.
2. **Value-Card approval + LOCAL value-filled execution copies (NOT committed).** After
   the Value Card is approved, the operator creates **local-only** execution copies of
   `seed-anchor.sql` and `seed-anchor-validation.sql` with the nine values filled in,
   verifies a **value-only diff** against the committed sentinel templates (only the
   nine numeric literals change; no logic/guard/structure change), and stores those
   copies + their outputs **outside the repo (or in gitignored `exports/`)**. **The
   committed sentinel templates stay unchanged, and the value-filled SQL is NOT
   committed** — it contains the nine observed household balances. Only metadata
   (filename, byte size, SHA-256, timestamp, purpose) is committed in the closeout
   (§6, §8). The nine approved values are pinned in the approved Value Card, not in the
   repository.
3. **Adam execution approval.** Adam's in-session seed go-ahead comes **only after**
   the runbook + Value Card are cleared, the sentinels are filled, and the value-only
   diff is confirmed. Review clearance is a precondition of, not a substitute for,
   Adam's approval.
4. **Rollback is excluded from that approval.** Post-seed rollback is **never
   automatic**, is **break-glass only for a structural/schema/RLS defect** (value
   mistakes are corrected with `source='correction'`, not a drop), and requires a
   **separate** in-session approval plus a mandatory row export (§8).

### Clearance freshness (see §9)

Clearance is **not durable**. It lapses and must be refreshed if **any** of the
following happen after clearance is granted:

- **The session ends** — review clearance AND Adam execution approval both lapse.
- **`origin/main` moves** (any new commit) — clearance lapses.
- **This runbook, the Value Card, `seed-anchor.sql`, or `seed-anchor-validation.sql`
  changes** — clearance lapses; the changed file must be re-reviewed.
- **A new weekly reconciliation lands** (the latest reconciled week changes) — the
  anchor basis and the Value Card must be re-derived (see §9).

If clearance has lapsed, return to §0 step 1 before doing anything else.

---

## 1. Scope confirmation — E2 boundaries (what E2 is and is NOT)

**E2 includes ONLY:**

1. Confirm the E1 objects exist and are correct (relation + RPC present; table still
   schema-only/EMPTY before the seed).
2. Confirm **Week 5 is reconciled** and is the anchor basis (see §2, §3).
3. Build + get approval for the **First-Anchor Value Card** (§4).
4. Create **local-only** value-filled execution copies from the committed sentinel
   templates; verify the value-only diff; record their metadata/hashes (do **not**
   commit the value-filled SQL — §6).
5. Fresh pre-seed re-check (preflight read-only re-run to reconfirm production
   identity, the empty table, and the reconciled-week map).
6. Run `seed-anchor.sql` (the guarded direct INSERT — the first `opening_anchor`).
7. Run `seed-anchor-validation.sql` (SA-PROD block + SA8/SA9 evidence).
8. Live-site verification that the overlay now consumes the anchor correctly.
9. Evidence capture + post-execution commit.

**E2 explicitly EXCLUDES:**

- **E1 DDL** — the production migration `migration.sql` is **DONE**. E2 must **not**
  rerun, modify, or re-execute it, and must **not** absorb it. (Preflight `P1` would
  now report `false` — the table already exists — so E2 does **not** rerun the E1
  preflight as a gate; it runs a **read-only re-check** for identity + empty-table +
  reconciled-week only. See §7 Step 3.)
- **5G-1D write-through** — the recurring weekly closeout snapshot write is a separate
  phase. E2 writes exactly **one** week's `opening_anchor` rows. No closeout UI, no
  `save_goal_funding_snapshots` RPC caller, no per-week roll-forward. See the 5G-1D
  plan (`docs/phase-5g-1d-plan-2026-07-09.md`).
- **No historical replay.** E2 seeds a single anchor at the latest reconciled week.
  It does **not** back-fill prior weeks, does **not** reconstruct week-by-week
  history, and does **not** write any week other than the anchor. (Seed-validation
  step (2) HARD-STOPS if any snapshot row exists at a week other than the anchor.)
- **No speculative values.** Every seeded value is an **observed** custodian/bank
  reality captured at seed time from the reconciled Week-5 state (§4, §5). No model
  projection, no `goalSaved` output, no "expected" figure is ever seeded.

**Source files (committed at `3061644`, all `docs/phase-5g-1c-2-prod-*`):**

- E2 **executes**: the **local value-filled execution copies** of `seed-anchor.sql`
  and `seed-anchor-validation.sql` (created from the committed sentinel templates after
  the Value Card is approved; the committed templates themselves stay at `-1` sentinels
  and are never altered by E2 — §6).
- E2 **holds in reserve** (break-glass, separately approved — §8): `rollback.sql`.
- **NOT used in E2** (belong to E1, already executed): `preflight.sql` (re-run
  read-only only, not as the E1 gate), `migration.sql` (**do not rerun**),
  `validation.sql` (E1 validation, already GREEN).

**Go-live claim.** With the anchor rows present, the shipped C3 overlay (`c6fbb32`,
live) **stops being inert**: the loader returns the seeded rows → `goalSnapData`
populates → `runModel` overwrites `goalSaved[gid]` at the anchor week for
model-tracked goals, and `getGoalFunded` reads the snapshot for complete/manual
goals. **This is a rendered-behavior change** (unlike E1). The live-site check (§7
Step 7) verifies it is the *correct* change and nothing else moved.

---

## 2. Anchor basis — Week 5, and why (challenges to stale language)

**The E2 anchor basis is model Week 5 (Cal Wk 27), and ONLY after the Week-5
reconciliation is complete and all relevant transfers have cleared.** This is the
binding basis for this runbook.

The seed and seed-validation files already encode this: `seed-anchor.sql` sets
`v_anchor_week INT := 5` and **Guard A** HARD-STOPS unless `v_anchor_week =
max(week_num)` from `weekly_reconciliations`. So a wk-5 seed cannot run until Week 5
is the latest reconciled week — which is exactly the "only after Week 5
reconciliation is complete" precondition, enforced mechanically.

### Stale assumptions this runbook explicitly corrects

1. **The "wk-4 basis" language is superseded.** E1's preflight (2026-07-09) observed
   `latest_reconciled_week = 4`, and CODEX_STATUS / the seed-file header at that time
   said the Value Card "must use the wk-4 basis or wait for a wk-5 reconciliation."
   **The decision is now made: wait for wk 5.** Do not seed on a wk-4 basis. Guard A
   enforces this — while Week 4 is still the max, a wk-5 seed HARD-STOPS, and a wk-4
   seed is prohibited by this runbook (it would pin an older, staler basis than the
   directive requires and re-introduce the wk-4→wk-5 projection gap 5G-1C-2 exists to
   close).

2. **The "re-anchor to wk 6 / Jul 18" language in `seed-anchor.sql` (lines 32–33) is
   NOT authorized by this runbook.** That comment predates the Week-5 basis decision.
   Under the current directive the basis is **Week 5**, not "whatever the latest
   reconciled week happens to be." **This is a decided operating rule, not an
   unresolved design option.** It creates a real mechanical tension with Guard A
   (which requires `v_anchor_week = max(week_num)`), resolved as follows:

   > **Week 5 must be the latest reconciled week when E2 runs.** If Week 6 becomes
   > reconciled *before* E2 executes, `max(week_num)` becomes 6 and the wk-5 seed
   > HARD-STOPS (Guard A). When that happens:
   > - **Hard stop.** Do not proceed.
   > - **Do not promote the anchor automatically** to Week 6. There is no silent
   >   auto-promotion.
   > - **Do not reuse the Week-5 Value Card.** The observed reality has moved.
   > - **Require a new Value Card built on the Week-6 basis and a fresh, explicit Adam
   >   approval** (plus re-review — §9 freshness) before any re-anchored seed. Deferral
   >   past the Alaska freeze (Jul 24–Aug 10) is the other admissible outcome; both are
   >   Adam's explicit decision, never the operator's default.
   >
   > The intended operating window is therefore: run E2 **after** the Week-5 closeout
   > and **before** the Week-6 closeout. Missing that window forces the new-Value-Card /
   > new-approval path above — it does not license an automatic wk-6 re-anchor.

3. **"Nine values, not four."** `seed-anchor.sql`'s header (line 16) still says "The
   four CAPTURE-AT-SEED-TIME values ship UNSET." That is a **stale comment**: Guard B
   and the SA-PROD validation both require **all nine** eligible values to be set
   (four "observed" + five "expected-$0-but-still-confirmed"). The comment is
   cosmetic (the guards already enforce nine), but it MUST be corrected to "nine" as
   part of the §0 step-2 value-fill edit so the file is not self-contradictory. Flag
   this to reviewers; it is the item the E1 runbook §10.7 deferred to E2.

4. **"Production-state" language must be re-derived live, not copied.** Any figure in
   the plan doc (`docs/phase-5g-1c-plan-2026-07-08.md` §4.4 — e.g. `adam_ira`
   $7,438.94, `wendy_sep` $17,859) is **illustrative only (R5)** and is **not** a
   seed value. The Value Card is built from the reconciled Week-5 custodian/bank
   reality at seed time. In particular: at a **Week-5** anchor, `adam_ira` is
   **~$7,438.94 (99%, ~$61.06 remaining)** — the $61.06 remainder clears at Cal Wk 29
   (5G-1A.5 hotfix), which is *after* Week 5, so **do not seed `adam_ira` at the
   completed $7,500** unless the custodian actually shows it cleared by the Week-5
   anchor. Seed what has actually cleared as of the anchor, nothing projected.

---

## 3. Preconditions and dependency on the completed Week-5 reconciliation

E2 must not begin until **all** of the following hold:

- **E1 complete + GREEN** (already true): production holds
  `public.goal_funding_snapshots` (schema-only, EMPTY) and
  `public.save_goal_funding_snapshots`; the E1 validation was all-`true`, V7 empty,
  V4f grant `{INSERT,SELECT,UPDATE}`. The C3 overlay is live and currently inert.
- **Week 5 reconciliation is COMPLETE.** The model Week 5 (Cal Wk 27) closeout has
  been saved via the normal `save_reconciliation_with_commitments` path, and
  `weekly_reconciliations` now contains `week_num = 5` as the **latest** (max) row.
- **All relevant transfers for Week 5 have cleared.** The custodian/bank movements
  that the Week-5 anchor will snapshot (IRA contributions, Alaska, SEP, any 529 /
  vehicle / cruise activity) have actually posted — the anchor captures **cleared,
  observed** balances, not in-flight amounts. If a relevant transfer is still
  pending, either wait for it to clear or record the not-yet-cleared value truthfully
  (observed = what has cleared).
- **The table is still EMPTY** (no prior seed, no stray rows). The pre-seed re-check
  (§7 Step 3) confirms `count(*) = 0` before the seed.
- **Registry unchanged (13 canonical IDs; IRA targets = 7500; `adam_401k.auto =
  true`).** If `goal_registry` has changed since E1 (a goal added/removed/archived →
  count ≠ 13, or an IRA target reverted), the production guard HARD-STOPS and the
  Value Card + seed must be re-derived. See §5 "newly added goals."
- **Approval chain (§0) cleared and fresh.** Runbook + Value Card reviewed; sentinels
  filled; value-only diff confirmed; Adam's in-session go-ahead given; no lapse
  trigger (§9) has fired.
- **Timing:** run outside Wendy's active Budget-entry hours, in a supervised window,
  and inside the wk-5 window (after the Week-5 closeout, before a Week-6 closeout —
  see §2 point 2). Respect the Alaska freeze (Jul 24–Aug 10).

**What Adam must collect from the reconciled Week-5 state before execution** (feeds
the Value Card, §4):

1. Confirmation that `weekly_reconciliations` max week_num = **5** (from the pre-seed
   re-check `P6-latestrec`, §7 Step 3).
2. For each of the **nine eligible goals**, the **observed cumulative funded amount as
   of the end of Week 5**, read from the actual source of truth (custodian statement /
   bank / AMEX Savings held balance), **not** from the app's modeled `goalSaved`:
   - `adam_ira` — T. Rowe (or custodian) observed IRA balance attributable to the
     goal at Week-5 close (~$7,438.94 expected; confirm actual cleared).
   - `wendy_ira` — observed Wendy IRA funded at Week-5 close.
   - `wendy_sep` — observed SEP balance (completed goal; planning figure ~$17,859 —
     confirm the exact custodian value).
   - `alaska` — observed **funded amount only** (this does not change Alaska's
     status or any payout/release behavior).
   - `bailey_529`, `bryce_529`, `preston_529`, `bryce_vehicle`, `christmas_cruise` —
     observed funded (expected $0; **still explicitly confirmed** — Guard B forces a
     value for each).
3. Confirmation of any goal that is **completed, zero-funded, inactive, archived, or
   newly added** and how it is treated (§5).

---

## 4. First-Anchor Value Card

The Value Card is the **single approved source of truth** for the nine seeded values.
It is filled into **both** `seed-anchor.sql` (the `v_*` capture vars) and
`seed-anchor-validation.sql` (the `v_card_*` pins), which must match exactly (the
SA-PROD block pins each seeded `funded_amount` to its card value).

**Rules:**

- **Every value is observed reality at the Week-5 anchor.** No projections, no model
  output, no "expected" placeholders committed as truth.
- **All nine are explicitly set** — including the five expected-$0 goals. There is no
  "leave it blank / default to 0"; Guard B HARD-STOPS on any remaining `-1`.
- **`source='opening_anchor'`** for every row (set by the seed, not the card).
- **The card is approved by Adam before the sentinels are filled**, and re-approved
  if the anchor basis changes (§9).

**Value Card template** (fill `<observed>`; replace the `-1` sentinels in the SQL with
these exact values):

| # | goal_id | Eligibility | Card value | Source of truth | Notes |
|---|---|---|---|---|---|
| 1 | `adam_ira` | eligible (active) | `<observed>` | IRA custodian @ Wk-5 close | ~7438.94 expected; **not** 7500 unless cleared |
| 2 | `wendy_ira` | eligible (active) | `<observed>` | IRA custodian @ Wk-5 close | |
| 3 | `wendy_sep` | eligible (completed) | `<observed>` | SEP custodian | completed goal; funded value only, no status change |
| 4 | `alaska` | eligible (completed) | `<observed>` | AMEX Savings held | **funded amount only**; status/payout unchanged |
| 5 | `bailey_529` | eligible (zero-funded) | `<observed, expect 0>` | 529 custodian | confirm explicitly |
| 6 | `bryce_529` | eligible (zero-funded) | `<observed, expect 0>` | 529 custodian | confirm explicitly |
| 7 | `preston_529` | eligible (zero-funded) | `<observed, expect 0>` | 529 custodian | confirm explicitly |
| 8 | `bryce_vehicle` | eligible (zero-funded) | `<observed, expect 0>` | savings source | confirm explicitly |
| 9 | `christmas_cruise` | eligible (zero-funded) | `<observed, expect 0>` | savings source | confirm explicitly |

**Excluded — NOT on the card, never seeded** (see §5): `adam_401k` (auto/payroll YTD),
`wewe_rccl`, `wewe_dcl`, `taxable_etf` (holding/deferred).

**Placeholder / sentinel removal happens in LOCAL copies, not the committed files.**
The committed seed templates ship with nine `-1` sentinels (seed) and nine `-1` pins
(validation), and **remain unchanged in the repository.** "Removing placeholders"
means replacing each `-1` with its approved card value **only in the local value-filled
execution copies** (§6) — the committed templates keep their sentinels. The
value-filled copies change only the nine numeric literals (value-only diff vs the
templates; guards, structure, and logic byte-unchanged). The stale "four capture
values" header comment is likewise corrected **only in the local execution copy**, not
the committed template (which is left untouched this pass; the comment is cosmetic —
Guard B and SA-PROD already enforce all nine). Until the local copies are filled, both
templates HARD-STOP by design.

---

## 5. Eligible goals, exclusions, and edge-case treatment

**Eligible (seeded — exactly these nine):** `adam_ira`, `wendy_ira`, `wendy_sep`,
`alaska`, `bailey_529`, `bryce_529`, `preston_529`, `bryce_vehicle`,
`christmas_cruise`.

**Excluded (never seeded):**

- **Automatic:** `adam_401k` — payroll/401(k) YTD accrual; grows every paycheck; a
  static snapshot would go stale immediately. Excluded by the seed JOIN
  (`COALESCE(g.auto,false)=false`), the WHERE-list, the RPC (`g.auto = true` reject),
  **and** the C3 overlay (auto path untouched). Reads its `goalFundedAmounts` /
  `PAY_401K` path unchanged.
- **Holding/deferred:** `wewe_rccl`, `wewe_dcl` (AMEX Savings *holding*; snapshot +
  payout-release modeling is 5G-1B) and `taxable_etf` (deferred). Excluded by the seed
  WHERE-list and the RPC `v_excluded` array (`wewe_rccl`, `wewe_dcl`, `taxable_etf`).

**Edge-case treatment:**

- **Completed goals** (`wendy_sep`, `alaska`): seeded with their **observed funded
  amount only**. The snapshot is the single source of truth `getGoalFunded` reads for
  complete goals (fixes the SEP hardcoding). Seeding does **not** flip any
  `goal_registry.status` and does **not** change Alaska payout/release behavior
  (per G1: no status flips).
- **Zero-funded eligible goals** (529s, `bryce_vehicle`, `christmas_cruise`): seeded
  with an explicit, confirmed `0` — a legitimate zero is a real value, not "absent."
  Guard B forces the explicit confirmation; SA-PROD pins each to its card value
  (which may be `0`).
- **Inactive goals:** none in the current 13-ID registry. If a goal is inactive at
  seed time, it is treated by its registry flags — if it is not one of the nine
  eligible active/complete IDs, it is not seeded. Any inactive goal that would change
  the 13-ID count trips the guard (see "newly added").
- **Archived goals:** not seeded (DQ invariant: no snapshots for archived goals). None
  are archived in the current registry. **Any goal archival before E2 requires
  escalation to Adam — regardless of the archival mechanism.** Whether archival
  *deletes* the `goal_registry` row or merely flips an archival/active *flag* while
  keeping the row, it must be escalated:
  - If archival **deletes** the row, `P6-goals` drops below 13 and the presence guard
    fires (the SQL detects the missing canonical ID).
  - If archival only **flips a flag** and leaves the row, `P6-goals` may still read 13
    and the SQL guard **will not detect it** — this is exactly why archival is an
    explicit escalation-to-Adam item, not something the guard is trusted to catch.
  Either way: HALT, escalate to Adam, and re-derive the Value Card / eligible set.
- **Newly added goals — the guard's exact limit (goal-drift protection).** The SQL
  production guard verifies the **presence** of the thirteen canonical goal IDs; it
  does **not** by itself detect a newly added *fourteenth* goal. Detection is layered:
  - **Missing canonical IDs** are detected by the guard (the 13-ID `IN (...)` presence
    check fails if one of the thirteen is absent).
  - **Added goals** are detected by requiring **`P6-goals = 13`** — a fourteenth
    registry row makes `P6-goals = 14`, which is a **hard stop** (§7 Step 3 / §8).
  - **`P6-excluded`** must be **manually compared** with the four approved exclusions
    (`adam_401k`, `taxable_etf`, `wewe_dcl`, `wewe_rccl`); the SQL reports the excluded
    set but does not assert it is exactly those four. **Any deviation from the exact
    four excluded IDs is a hard stop.**
  A new goal is NOT auto-seeded: on any `P6-goals ≠ 13`, exclusion-set deviation, or
  archival, HALT — the Value Card, the seed VALUES list, and the SA-PROD `v_expected`
  array must be deliberately regenerated and re-reviewed (fresh Adam approval) before
  E2 can run. First-anchor seeding is an explicit, reviewed act, never an implicit
  "whatever is in the registry."

**Overlay guard note (rider to 5G-1D/1E).** The C3 overlay writes only `goal_id`s
already tracked in `goalSaved` and never injects auto goals; the seed + RPC + SA-PROD
table-wide exclusion assertions are the DDL-gate defense that no excluded id ever
gets a row. The **overlay does not itself guard auto/holding goals** — that C3 overlay
auto/holding exclusion guard remains a named follow-up carried into 5G-1D (§ rider).
It is **not** part of E2.

---

## 6. Value-fill (local only), value-only diff, and the privacy-preserving artifact model

**Principle (aligned with the accepted E1 model):** the value-filled seed and
validation SQL contain the nine observed household balances and are **execution
artifacts, not repository content.** Repository = **sentinel templates + metadata/
hashes only.** Production financial-data artifacts stay **local.** There is **no path
that commits the nine observed balances** without a separate, explicit Adam privacy
override (below) — code/process must never infer that approval.

1. **Committed sentinel templates remain unchanged.** Do **not** edit
   `docs/phase-5g-1c-2-prod-seed-anchor.sql` or
   `docs/phase-5g-1c-2-prod-seed-anchor-validation.sql` in the repo. They keep their
   nine `-1` sentinels / pins.
2. **Create LOCAL value-filled execution copies (after Value-Card approval).** Copy
   each template to the external backup directory (E2 subdirectory preferred:
   `~/Herndon-FOS-DB-Backups/Adam-Dashboard/e2-first-anchor/`) **or** gitignored
   `exports/`. In the copies: fill the nine seed vars (`v_adam_ira` …
   `v_christmas_cruise`) and the nine validation pins (`v_card_adam_ira` …
   `v_card_christmas_cruise`) with the approved Value-Card values; confirm
   `v_anchor_week := 5` in both; and correct the stale "four"→"nine" header comment in
   the copy. These copies are what Step 5/6 execute.
3. **Value-only diff (local).** `diff` each execution copy against its committed
   template: **only** the nine numeric literals may differ (plus the one local comment
   fix). Any change to a guard, the VALUES structure, the JOIN/WHERE, the SA-PROD
   logic, or the anchor-week logic is a red flag → STOP.
4. **Do NOT commit the value-filled SQL or its outputs.** They live outside the repo
   (or in gitignored `exports/`). The closeout commits **metadata only** for each
   execution copy + output file: **path/filename, byte size, SHA-256, creation
   timestamp, purpose** (§8). This mirrors E1's restore-point metadata model.
5. **Privacy override is the only exception.** If — and only if — Adam gives a
   **separate, explicit privacy override**, the value-filled SQL may be committed.
   Absent that explicit override, the nine observed balances are never committed; no
   process step may assume the override.
6. **Freshness.** Because the committed templates are not changed, they do not
   re-trigger the §9 "file changed" lapse. Reviewers instead confirm the **local**
   value-only diff and the recorded metadata/hashes before Adam's final go-ahead.

---

## 7. Step-by-step runbook

> **Execution-tooling note (applies to every SQL step below).** Whenever `psql` is
> used, run with **`ON_ERROR_STOP=1`** (e.g. `psql "…" -v ON_ERROR_STOP=1 -f <file>`)
> so a mid-script error aborts immediately instead of continuing past a failed guard.
> The Supabase SQL Editor already stops the batch on error. **Idempotency note:** an
> accidental *identical* rerun of the seed is **value-idempotent** — the RPC/seed
> upsert on `(model_year, week_num, goal_id)` overwrites the same nine rows with the
> same values, so no duplicate rows or double-counting result. **This does NOT make a
> rerun permitted:** any rerun still requires fresh authorization (§0/§9); value-
> idempotency is a safety property, not a license to re-execute.

### Step 0 — Review clearance + Value Card + Adam approval (gate, no execution)

- **Who:** Adam routes this runbook + the filled Value Card to ChatGPT/Fable; they
  review; Adam gives in-session seed approval after clearance and the value-only diff.
- **Stop condition:** No clearance, unresolved findings, unfilled/again-changed
  sentinels, an anchor-basis change (§9), or lapsed clearance → **do not start any
  step below.**

### Step 1 — Confirm Week-5 reconciliation is complete + transfers cleared

- **Who:** Adam.
- **Action:** Confirm the model Week-5 (Cal Wk 27) closeout is saved and that all
  relevant custodian/bank transfers for the anchor have cleared (§3). Gather the nine
  observed values for the Value Card from the source-of-truth statements.
- **Stop condition:** Week 5 not reconciled, or a relevant transfer still pending with
  no truthful observed value → **HALT** (wait, or record only what has cleared).

### Step 2 — Confirm target = Adam-Dashboard (usayoldrawwmjsmretin)

- **Who:** Adam (Supabase UI, or `psql \conninfo`).
- **Action:** Confirm project ref = `usayoldrawwmjsmretin`, **not** `pkwotgqivgaapwuqgwqb`.
- **Backstop:** Both executed files re-check `system_identifier = 7632885393857617092`
  in-SQL and refuse staging.
- **Stop condition:** Any other ref or ambiguity → **HALT.**

### Step 3 — Pre-seed read-only re-check (NOT the E1 preflight gate)

- **Who:** Adam, Supabase SQL Editor (or `psql` with **`ON_ERROR_STOP=1`** — see the
  §7 execution-tooling note).
- **File:** `docs/phase-5g-1c-2-prod-preflight.sql` — run whole, read-only.
- **Purpose here is different from E1:** the E1 gate asserted the object names were
  **unused** (table/policies/index/trigger/function absent). After E1 those objects
  exist, so several `expected_true` checks now legitimately return `false`. **The full
  post-E1 profile below is the reference — read it precisely: some `false` results are
  EXPECTED post-E1 and are NOT failures.**

  **EXPECTED-`false` post-E1 (do NOT stop on these):**
  - **`P1 = false`** — the `goal_funding_snapshots` table now exists (created by E1).
  - **`P2 = false`** — the three table policies (`allow_read`,
    `financial_writer_insert`, `financial_writer_update`) now exist.
  - **`P3a = false`** — the index/unique-constraint names now exist.
  - **`P3b = false`** — the `set_goal_funding_snapshots_updated_at` trigger now exists.
  - **`P3c = false`** — the `save_goal_funding_snapshots` function now exists.

  **MUST be `true` (STOP if any is `false`):**
  - **`P4a`–`P4j` all `true`** — dependencies + prod hard gates (`fn_set_updated_at`,
    `can_write_financials`, `is_allowed_user`, `goal_registry`,
    `weekly_reconciliations`; 9 seeded IDs present; IRA targets 7500; `adam_401k.auto`
    true; 4 excluded IDs present). Any `false` → **HALT.**
  - **`P5a`–`P5c` all `true`** — FK/schema assumptions (`goal_registry.id` is `text`;
    `weekly_reconciliations` has `week_num`; it has **no** `model_year`). Any `false`
    → **HALT.**

  **P6 evidence — exact expected values (eyeball each; deviation = investigate/HALT):**
  - **`P6-tables = 18`** — public-table count after E1.
  - **`P6-goals = 13`** — canonical goal_registry row count (see §5 goal-drift).
  - **`P6-sysid = 7632885393857617092`** and **`P6-txcount ≥ 95`** — production
    identity + transaction floor. **Growth above 95 from live use is NORMAL and
    expected.** Any **shrinkage below the recorded E1 baseline (95)** is an anomaly →
    **HALT and investigate** (a shrinking transaction count on a live household DB is
    not normal).
  - **`P6-recweeks` = exactly weeks 1, 2, 3, 4, 5** — the reconciled model weeks. More
    or fewer, or a gap, → investigate.
  - **`P6-latestrec = 5`** (exactly) — Week 5 is the latest reconciled week (the anchor
    basis). **`P6-latestrec ≠ 5` → HALT** (4 = Week 5 not yet reconciled; 6 = Week 6
    landed → the §2.2 hard-stop / new-Value-Card path).
  - **`P6-excluded` = exactly the four approved IDs: `adam_401k`, `taxable_etf`,
    `wewe_dcl`, `wewe_rccl`** (any order). This set is **manually compared** with the
    four approved exclusions — the SQL does not assert the exact set (see §5). Any
    deviation → **HALT.**
  - The table is **EMPTY** (confirm separately: `SELECT count(*) FROM
    public.goal_funding_snapshots;` → 0).
- **Output capture:** save to `exports/db-baseline-5G-1C-2-prod-e2-precheck-<ts>.txt`
  (a read-only, non-financial-data artifact — committable per §8).
- **Stop condition:** guard exception; any `P4*`/`P5*` `false`; `P6-tables ≠ 18`;
  `P6-goals ≠ 13`; `P6-txcount` below 95; `P6-recweeks` not exactly {1,2,3,4,5};
  `P6-latestrec ≠ 5`; `P6-excluded` not exactly the four approved IDs; table non-empty
  → **HALT.** (A `P1`/`P2`/`P3a`/`P3b`/`P3c` `false` is **expected** and is **not** a
  stop condition.)

### Step 4 — Live-site baseline (pre-seed reference; compared by Step 7)

- **Who:** Adam, on dashboard.herndons.us (Claude may assist reading).
- **Action — record, before the seed, with a consistent method:** same login to be
  used post-seed; hard reload; BUILD_TS noted; Overview/Weekly/Goals-Funding/Budget/
  Register load; Funding Plan / Funding Timeline current labels noted; Adam IRA timing;
  Wendy SEP behavior; console/network snapshot (the C3 loader currently returns
  **200 with an empty array** — inert).
- **Expected:** written pre-seed reference saved to `exports/` with BUILD_TS.
- **Stop condition:** site not loading / pre-existing errors → resolve or HALT.

### Step 5 — Seed the first `opening_anchor` (gate)

- **Who:** Adam, Supabase SQL Editor (or `psql` with **`ON_ERROR_STOP=1`**), same
  sitting as Step 3.
- **File:** the **local value-filled execution copy** of `seed-anchor.sql` (§6) — run
  whole. The committed template stays at `-1` sentinels and is not run.
- **Expected:** production guard passes; **Guard A** passes (`v_anchor_week = 5 =
  max(week_num)`); **Guard B** passes (all nine values set, none `-1`); the guarded
  INSERT writes **9 rows** (`RAISE NOTICE 'SEED-ANCHOR: 9 opening_anchor rows …'`);
  the trailing report SELECT shows the nine rows at `week_num = 5`.
- **Gate / stop conditions:**
  - **Any error → STOP.** A failure inside `BEGIN/COMMIT` rolls the whole seed back —
    no partial rows. Do not rerun blind; diagnose first (§8).
  - Guard A HARD-STOP (`v_anchor_week ≠ max`) → Week 5 is not the latest reconciled
    week (either not yet reconciled, or Week 6 already landed) → **STOP, escalate
    per §2.2.**
  - Guard B HARD-STOP → a sentinel is still `-1` → the Value-Card fill (§6) is
    incomplete → **STOP, do not improvise a value.**
  - Row count ≠ 9 → **STOP** (registry/exclusion drift; investigate before validation).

### Step 6 — Seed-anchor validation (gate)

- **Who:** Adam, Supabase SQL Editor (or `psql` with **`ON_ERROR_STOP=1`**).
- **File:** the **local value-filled execution copy** of `seed-anchor-validation.sql`
  (§6, with the nine `v_card_*` pins filled) — run whole. The committed template stays
  at `-1` pins.
- **Output capture (financial-data artifact — LOCAL only):** save full output to the
  external backup dir or gitignored `exports/` as
  `…-e2-seedvalidation-<ts>.txt` (text, not screenshots; capture NOTICE + any ERROR).
  The SA9 dump contains the nine seeded balances, so this file is **not committed** —
  only its metadata/hash is (§8).
- **Gate — ALL required:**
  - Production guard passes.
  - **SA-PROD `DO` block raises no exception** and prints `SA-PROD PASS: 9 rows at
    single anchor week 5, …` (pins set; anchor week reconciled; exactly one seeded
    week = the anchor; **table-wide count = 9**; **no excluded id present table-wide**;
    all nine expected ids present exactly once; source=`opening_anchor`, funded ≥ 0,
    in registry, non-auto; **each funded_amount = its Value-Card pin**).
  - **SA8 advisory** reviewed (informational; over-attribution > $1 is the only flag;
    under-attribution is expected — RCCL/DCL holding excluded; hard gate is 5G-1E). The
    SA8 AMEX subset it sums is exactly the five AMEX-attributable goals: **`adam_ira`,
    `wendy_ira`, and the three 529 goals (`bailey_529`, `bryce_529`, `preston_529`)** —
    compared against the reconciled `amx` at the anchor.
  - **SA9 row dump** eyeballed against the approved Value Card.
- **Stop condition:** any SA-PROD exception, count ≠ 9, an excluded id present, a
  pin mismatch, or a row-invariant violation → **HALT**; treat as a seed defect →
  §8 (correction or, for a structural defect only, break-glass rollback).

### Step 7 — Live-site verification (overlay now active)

- **Who:** Adam, on dashboard.herndons.us (Claude may assist reading), **same login +
  hard reload** as the Step 4 baseline.
- **Expected behavior change (this is the go-live):**
  - The C3 loader returns the **nine seeded rows** (200, non-empty) →
    `goalSnapData[5]` populated.
  - `runModel` overwrites `goalSaved[gid]` at week 5 for model-tracked goals; the
    Funding Plan **row** and the **Funding Timeline** now agree (both anchored to the
    reconciled Week-5 reality for weeks ≤ 5, projection after).
  - `getGoalFunded` reads the snapshot for complete goals (`wendy_sep`, `alaska`).
  - **Excluded goals unchanged:** `adam_401k` still `Auto · Payroll`; RCCL/DCL/taxable
    unaffected.
  - No console errors; no goal moved that should not have (spot-check against the
    Value Card and the Step 4 baseline — only the anchored figures should change, and
    only to their observed values).
- **"No visible movement" can be a CORRECT result.** Where the observed Value-Card
  value equals the value the model already displayed, the overlay overwrites
  `goalSaved` with the same number and the UI does not visibly change. **Little or no
  browser movement is therefore expected and is not evidence of failure.** Do not
  validate success by "did the screen change." Validate it three concrete ways:
  1. the loader returns **nine rows** for week 5 (200, non-empty; check
     console/network);
  2. each rendered funded value **agrees with the approved Value-Card value**;
  3. excluded goals (`adam_401k`, RCCL/DCL/taxable) are unchanged.
- **Stop condition:** a rendered value disagrees with the seeded Value-Card value, the
  loader returns other than nine rows, an excluded goal changed, a completion week
  shifted implausibly, or a loader/overlay error fires → investigate; a real
  regression → §8.

---

## 8. Evidence capture, rollback, and stop conditions

### Evidence capture (E1-aligned: repo metadata/hashes may be committed; production financial-data artifacts stay LOCAL)

**Two tiers.** Repository holds **metadata + hashes + non-financial read-only
evidence**; the external backup dir / gitignored `exports/` holds every artifact that
contains household balances. **Nothing containing the nine observed balances is
committed** without a separate explicit Adam privacy override (§6).

**Committable to the repo (no household balances):**

- Pre-seed read-only re-check output (`…-e2-precheck-<ts>.txt`) — P1–P6 checks; counts,
  week numbers, and goal IDs only, no funded amounts.
- **Metadata records** for every local financial-data artifact: **path/filename, byte
  size, SHA-256, creation timestamp, purpose** — for each value-filled execution copy
  (§6), the seed run output, the seed-validation output, and any rollback export.
- A `CODEX_STATUS.md` pointer update (no balances).

**LOCAL only — NEVER committed (contain balances); store under the external backup dir
or gitignored `exports/`:**

- The two **value-filled execution copies** of the seed / seed-validation SQL (§6).
- **Seed run output** (the `SEED-ANCHOR: 9 … rows` NOTICE + the report SELECT, which
  lists the nine `funded_amount` values).
- **Seed-validation output** (`…-e2-seedvalidation-<ts>.txt`) incl. SA-PROD PASS
  notice, SA8 advisory, and the SA9 row dump (nine seeded balances).
- Live pre-/post-seed notes if they capture rendered funded values (keep the
  balance-bearing detail local; a balance-free summary may be committed).

**Commit timing:** save all evidence locally during E2; **after** the execution session
ends, commit **only the committable tier** (metadata/hashes + precheck + status
pointer) as a separate docs/evidence commit using `git commit --no-verify` (keep
`index.html`/BUILD_TS untouched).

### Rollback (separate approval; break-glass only)

Post-seed rollback is **never automatic** and is **excluded from Adam's seed
approval.** Once the anchor rows exist, the table holds real household data.

- **A wrong seeded value is corrected with `source='correction'`** (a new/updated
  snapshot row), **not** a table drop. The monotonicity DQ invariant explicitly allows
  `correction` as the only sanctioned decrease.
- **`rollback.sql` (DROP RPC → DROP TABLE) is break-glass ONLY for a
  structural/schema/RLS defect.** Before any post-seed rollback: **export every row**
  (`SELECT * … ORDER BY model_year, week_num, goal_id;` or the header's `COPY … CSV`).
- **Export storage — override the stale `prod-rollback.sql` header instruction.** The
  committed `docs/phase-5g-1c-2-prod-rollback.sql` header says to write the CSV to
  `exports/…csv` **and commit it.** **That instruction is stale and is overridden here:
  the export contains real household anchor data and must NOT be committed.** Instead:
  - Store the CSV **locally** under **`~/Herndon-FOS-DB-Backups/Adam-Dashboard/`** (an
    E2-specific subdirectory preferred, e.g. `…/e2-first-anchor/`).
  - A copy **may** remain under **gitignored `exports/`**, but **no CSV containing
    household financial data may be committed.**
  - The closeout records **metadata only**: path/filename, byte size, SHA-256, creation
    timestamp, purpose.
  - **This change does not edit `prod-rollback.sql`** — the runbook overrides its
    header at execution time; the SQL file is untouched this pass.
- **Then** set `v_confirm_export_done := true` in the refusal block (the file
  HARD-STOPS on a non-empty table if the flag is false). **Creating the export does NOT
  authorize rollback** — rollback remains a **separate, explicit Adam approval gate**
  and is never automatic. Confirm `RB1`–`RB4 = true` after.

### Stop conditions (consolidated)

- Week 5 not reconciled / relevant transfer not cleared → HALT (§3).
- `P6-latestrec ≠ 5` at seed time (wk 4 still latest, or wk 6 landed) → HALT; a wk-6
  landing forces the §2.2 hard stop — no auto-promote, no Week-5 Value-Card reuse, new
  Value Card + explicit Adam approval required.
- `P6-recweeks` not exactly {1,2,3,4,5}, or `P6-tables ≠ 18` → HALT, investigate.
- **`P6-goals ≠ 13` → hard stop** (missing canonical ID *or* a newly added 14th goal).
- **`P6-excluded` not exactly the four approved IDs (`adam_401k`, `taxable_etf`,
  `wewe_dcl`, `wewe_rccl`) → hard stop** (manual comparison; the SQL does not assert
  the exact set).
- **Any goal archival before E2 → escalate to Adam** (whether it deletes the row or
  only flips a flag; the flag case is not guard-detectable — §5).
- `P6-txcount` below the recorded E1 baseline of 95 → HALT, investigate (growth is
  normal; shrinkage is an anomaly).
- Any `P4a`–`P4j` or `P5a`–`P5c` `false` → HALT. (A `P1`/`P2`/`P3a`/`P3b`/`P3c` `false`
  is EXPECTED post-E1 and is **not** a stop condition — §7 Step 3.)
- Registry drift (IRA target ≠ 7500, `adam_401k.auto` ≠ true) → guard HARD-STOP →
  re-derive the Value Card + seed (§5).
- Any sentinel still `-1` (Guard B) → HALT; do not improvise values.
- Row count ≠ 9, SA-PROD exception, excluded id present, or pin mismatch → HALT (§6/§7).
- Live-site value disagrees with the Value Card, or an excluded/unrelated goal moved →
  HALT (§7).
- Any §9 freshness trigger fired since clearance → refresh clearance before proceeding.

---

## 9. Freshness rules (clearance lapse triggers)

Re-derive and re-clear before E2 if, after clearance:

- **`origin/main` moves** (any new commit) — mechanical/value diffs may no longer
  match; re-verify.
- **This runbook, the Value Card, `seed-anchor.sql`, or `seed-anchor-validation.sql`
  changes** — re-review the changed file(s) and re-confirm the value-only diff.
- **The session ends** — both review clearance and Adam approval lapse.
- **A new weekly reconciliation lands / the latest reconciled week changes** — the
  anchor basis (§2) and the Value Card (§4) must be re-derived. In particular, if
  Week 6 reconciles before E2 runs, the wk-5 seed will HARD-STOP (Guard A); escalate
  per §2.2 for an explicit re-anchor-or-defer decision.
- **Reconciliation state or Week-5 observed values change** (a late-clearing transfer,
  a corrected closeout) — rebuild the Value Card from the new observed reality.

---

## 10. Separation from E1 and 5G-1D (explicit)

- **E1 (production DDL) is DONE and immutable for E2.** E2 does not rerun, modify, or
  absorb `migration.sql`; the E1 preflight/validation gates are E1's, not E2's. E2's
  only use of `preflight.sql` is a **read-only re-check** (§7 Step 3) where `P1`/`P3*`
  returning `false` is expected.
- **5G-1D (weekly closeout write-through) is a separate, later phase.** E2 writes
  exactly one `opening_anchor`; it does **not** build or activate the closeout UI,
  the `save_goal_funding_snapshots` RPC caller, per-week roll-forward, or correction
  UX. 5G-1D **may not be implemented or activated until E2 has successfully created
  and validated the first anchor.** `docs/phase-5g-1d-plan-2026-07-09.md` is a
  **pending, unapproved working draft** — it is **not authoritative** and **does not
  authorize any 5G-1D implementation**; it is referenced here for continuity only and
  remains untracked/uncommitted.
- **No historical replay, no speculative values** (§1): one anchor, at the latest
  reconciled week, from observed reality only.

---

## 11. Who runs what — summary

| Step | Surface | Runner |
|---|---|---|
| 0 Review + Value Card + approval | Review | **Adam + ChatGPT/Fable** |
| Local value-fill + value-only diff + metadata/hashes (no value commit) | Local shell/diff (outside repo or gitignored) | **Claude/local** (Adam approves); value-filled SQL NOT committed |
| 1 Confirm Week-5 recon + transfers | Custodian/bank + app | **Adam** |
| 2 Confirm target | Supabase UI (or `psql \conninfo`) | **Adam** |
| 3 Pre-seed read-only re-check | Supabase SQL Editor | **Adam** |
| 4 Live pre-seed baseline | Browser (prod site) | **Adam** (Claude may assist reading) |
| 5 Seed `opening_anchor` | Supabase SQL Editor | **Adam** |
| 6 Seed-anchor validation | Supabase SQL Editor | **Adam** |
| 7 Live post-seed verification | Browser (prod site) | **Adam** (Claude may assist reading) |
| 8 Rollback (break-glass, separate approval) | Supabase SQL Editor | **Adam** |

---

**This runbook is the reviewed artifact for the E2 gate. It authorizes nothing on its
own — execution requires fresh review clearance + Value-Card approval (§0), the nine
sentinels filled and value-only-diffed, then Adam's separate in-session seed approval.
No SQL, no Supabase, no seed has been run. E1 is done; 5G-1D has not started.**
