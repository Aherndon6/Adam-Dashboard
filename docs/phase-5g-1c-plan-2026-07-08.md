# Phase 5G-1C Plan — Goal Funding State Integrity + Funding Plan Projection Semantics

**Status:** PLAN ONLY. No code written. Prepared for Fable architecture review before implementation.
**Date:** 2026-07-08
**Author:** Claude (session under Adam)
**Predecessor:** 5G-1A.5 hotfix (commit `f307db7`), which resolved the AMEX-hold sub-`MIN_XFR` waterfall deadlock. This phase is "Phase B" of `docs/funding-model-integrity-review-2026-07-08.md` §5/§7.
**Authoritative inputs read:** the integrity review (2026-07-08), `CODEX_STATUS.md`, `docs/phase-status.md`, `index.html` (runModel + Funding Plan + reconciliation overlay + loaders), `test_regression.js` (harness, GR-A1, PHASE-A), `e2e.js`, `AGENTS.md` (Do Not Touch, schema/migration conventions), the on-disk 5G-1 SQL package.

---

## 0. TL;DR for the review gate

1. **Two problems, two clocks.** (A) The Funding Plan "When" column reads *current-week* funded state, so a goal that receives **projected** partial funding but is $0 today and never completes falls through to "Beyond 2026" (Bailey's 73%). This is a **display bug fixable with pure model output, no schema.** (B) Per-goal funded state (`goalSaved`) is unreconciled simulation; model/reality agreement is coincidental (integrity review §1.4/§3-Layer-2). This is the **architecture fix** and needs durable, week-anchored, reconciled state.
2. **Recommended split: two slices inside one phase.** **5G-1C-1 (Funding Plan Projection Semantics)** — display-only, no schema, safe before July close and before the Alaska freeze. **5G-1C-2 (Goal Funding State Integrity)** — additive `goal_funding_snapshots` table + SECURITY DEFINER write RPC + identity-gated runModel overlay + first opening anchor, staging-first. Slice 1's label logic is written to consume *two* inputs (current funded, projected year-end funded) so it is forward-compatible with slice 2 with zero rework.
3. **Snapshot design is confirmed (Option B), with the overwrite-at-anchor semantics as the load-bearing invariant** — it is the only semantics compatible with runModel re-simulating all 31 weeks from scratch, and it makes double-counting structurally impossible past an anchor.
4. **The recurring weekly write-through-the-closeout UI is deferred to 5G-1D** (Weekly Closeout Goal Attribution). 5G-1C-2 ships the table, RPC, overlay, read path, and the *first* anchor (seeded via a SQL package like the Mint seed). This keeps 5G-1C from ballooning and matches the roadmap.
5. **Identity gate is the freeze-safety proof:** zero snapshot rows ⇒ `runModel` output deep-equals current behavior (GR-A1 pattern, all 31 weeks × goals × balances). 5G-1C-2 also captures the **first stored `runModel` golden-master fixture** (none exists today; AGENTS.md standing rule, integrity review §8).

---

## 1. Report requested before implementation

### 1.1 Exact files and database objects expected to touch

**Database (new, additive only; staging-first per AGENTS.md):**
- New table `public.goal_funding_snapshots`.
- New SECURITY DEFINER RPC `public.save_goal_funding_snapshots(...)`.
- RLS policies (`allow_read` via `is_allowed_user()`; `financial_writer_insert`/`_update` via `can_write_financials()`), grant normalization (REVOKE ALL from PUBLIC/anon/authenticated → GRANT least-privilege), trigger `set_..._updated_at` reusing the shared `public.fn_set_updated_at()`.
- SQL package files in `docs/` mirroring the 5G-1 skeleton: `phase-5g-1c-preflight.sql`, `phase-5g-1c-migration.sql`, `phase-5g-1c-validation.sql`, `phase-5g-1c-seed-anchor.sql`, `phase-5g-1c-seed-validation.sql`, `phase-5g-1c-rollback.sql`. Reuse the existing `app_environment` staging marker and its guard block; do **not** recreate it.
- **Untouched:** `goal_registry` stays SELECT-only; `weekly_reconciliations`, `cash_commitments`, `save_reconciliation_with_commitments`, and the reconciliation state machine are not modified (Do Not Touch).

**`index.html` (in-place additive edits; requires explicit runModel-freeze exception — 5G-1A.5 precedent):**
- `runModel` reconciliation overlay site (`index.html:2561-2566`): after the balance overwrite, apply the goal-snapshot overlay behind the identity gate; capture per-goal variance. Deep-copy of `goalSaved` into the week object is already at 2606-2610 and needs no change.
- `getGoalFunded` (`index.html:4304-4314`): complete/auto-goal branch reads the latest snapshot ≤ `currentW`, falling back to `goalFundedAmounts`. Model-backed branch is **unchanged** (it already reads `goalSaved`, which is now anchored).
- `_renderGoalsFunding` "When"/status decision tree (`index.html:4757-4777`) and remaining/progress cells (4778-4809): new projection-aware labels + projected year-end funded/remaining display. **This is slice 1 and does not require any of the above snapshot work.**
- `loadAll` (`index.html:~7757`, beside the `reconData` load): fetch snapshots into a new `goalSnapData` structure. Add a fallback/absent-rows banner mirroring the existing goals fallback banner pattern.
- New snapshot **data-access / view helper code** ships as ES module(s) in separate files per the 5G "new feature code" rule; only the runModel overlay, `getGoalFunded`, and the Funding Plan render (which live in the frozen index.html script body) are edited in place under the freeze exception.

**Test files:**
- `test_regression.js`: identity gate (GR-A1 pattern), overlay-behavior tests, `getGoalFunded` snapshot-read tests, Funding Plan label-logic truth table, DQ-invariant JS assertion, first golden-master `runModel` fixture.
- `e2e.js`: Funding Plan projection-label tests (Bailey no longer "Beyond 2026"; partial/continues wording), snapshot-missing banner. (Closeout write-through e2e belongs to 5G-1D.)

### 1.2 One phase or split?

**One phase, two internally-sequenced slices**, plus a clean handoff boundary to 5G-1D:
- **5G-1C-1 — Funding Plan Projection Semantics** (display-only, no schema). Fixes the misleading "Beyond 2026" row using projected year-end funded from existing model output. Ships fast, low risk, pre-close and pre-freeze safe.
- **5G-1C-2 — Goal Funding State Integrity** (schema + RPC + overlay + first anchor). The architectural core. Staging-first, identity-gated, golden-master fixture captured.
- **Boundary:** recurring per-week snapshot *writing* via the weekly closeout UI is **5G-1D**. 5G-1C-2 ships the write RPC and seeds the first anchor via a SQL package; 5G-1D only adds the UI caller (a prefilled one-click confirm at closeout).

Rationale: slice 1's payoff (the visible label fix) is independent of the schema and can land immediately. Slice 2 is where the staging gate, freeze exception, and golden-master capture concentrate. Keeping the weekly-write UI out of 5G-1C prevents the phase from absorbing 5G-1D.

### 1.3 Risks and rollback path

- **Slice 1 risk:** low. Display-only; no model math, schema, or routing changes. Golden-master of `runModel` is untouched because labels are derived at render time from existing `vm` output. Rollback = revert the commit.
- **Slice 2 risk:** medium, concentrated in three places: (a) the overlay must be a **full overwrite** at the anchor, not additive, or it double-counts; (b) wrong first-anchor values would anchor the model to a wrong reality; (c) editing frozen `runModel` internals (freeze exception required). All three are mitigated (see §11). Rollback = drop the RPC + table; the identity gate guarantees the app reverts to exact pre-phase behavior with zero snapshot rows, so even a partial rollback is safe (absent rows ≡ today).
- **No data-loss surface:** snapshots are additive observations; nothing overwrites `goal_registry`, `weekly_reconciliations`, or balances.

### 1.4 What can be safely done before July month-end close

- **Slice 1 (projection semantics): yes, immediately.** No schema, no freeze conflict, fixes the operator-facing confusion before close.
- **Slice 2 schema rehearsal on staging: yes** (staging Supabase + baseline export already in place from 5G-1). Production DDL + the overlay build should land **before the Alaska freeze (Jul 24–Aug 10)** if gates pass; otherwise after Aug 10. The 5G-1A.5 hotfix keeps the model correct through the freeze regardless, provided reality keeps following the plan.
- **First anchor seed** rides the next weekly closeout (Wk 27 / model week 5, once reconciled). It is valuable for the 5G-1F month-end close but is **not** a close blocker.

### 1.5 Reasons to route back to Fable before implementation

Yes — this plan is explicitly for Fable review. Specific decisions I want blessed (see §12 Open Questions for the full list): the overwrite-at-anchor overlay semantics and its interaction with the re-fired `RET_SAV_XFR` seed; the two-slice split and the 5G-1D boundary for weekly writes; whether the write RPC ships in 5G-1C-2 or waits for 5G-1D; the `adam_401k` exclusion; the AMEX invariant as **advisory** (not a hard gate) while 5G-1B holding-release is unbuilt; whether completed goals get `opening_anchor` snapshots or stay status-driven; and the golden-master fixture capture as part of this phase.

---

## 2. Current-state facts this design is built on (verified in `index.html`)

1. `runModel(akGoal,rtGoal,flags)` (2199) **re-simulates all 31 weeks from scratch every call.** There is no persisted running state.
2. `goalSaved` (per-goal cumulative funded) is initialized from **frozen constants** every run: `goalSaved['adam_ira']=START_AMX` (=$103.64, line 2211), `goalSaved['adam_401k']=goalFundedAmounts['adam_401k']` (=$10,208 YTD, line 2212), all others 0 (2210). Plus a one-time `RET_SAV_XFR` (=$3,772.74) seed sweep into `adam_ira` when Alaska completes (2537-2542).
3. The **reconciliation overlay** at 2561-2566 overwrites `chk/sav/amx/tax/lc` from `reconData[num]` and records a balance `variance`, **but never touches `goalSaved`.** This is the exact site the goal overlay mirrors.
4. Each week's `goalSaved` is deep-copied into the week object as `gSnap` (2606) → consumed by the Funding Plan, the Funding Timeline, `getGoalFunded`, and GR-A1.
5. `getGoalFunded(id,vm)` (4304) reads `w.goalSaved[id]` on the **currentW** week for model-backed goals; complete goals read the static `goalFundedAmounts[id]`.
6. `goalCompletion[g.id]` (3108-3113) = first week where `goalSaved[id] ≥ target`. This is `item.comp` in the Funding Plan.
7. **The Funding Plan "When" column (4760-4777)** decides label from: `isFunded` (pct≥100 at currentW), `isLocked`, `auto`, `stretch`, `comp` (completes within horizon), `item.funded>0` ("In Progress · Continues in 2027"), else **"Beyond 2026."** `item.funded` = `getGoalFunded` = **current-week** funded.
8. **Why Bailey shows "Beyond 2026":** at currentW (model wk 5), Bailey's funded is $0 (its projected funding is in *future* weeks — the timeline reaches 73% by week 31). So `item.funded==0` and `comp==null` → the row falls to "Beyond 2026", even though the timeline (which reads the *final* week's `goalSaved`, line 4732) shows 73%. **The row and the timeline read different weeks.** That is the whole bug.
9. `getCurrentWeek()` (2646): base date 2026-06-07; today (2026-07-08) → model week 5 = **Cal Wk 27** (cal week = 22 + model week, line 4708). Last reconciled week is model week 4 (the "Week 26" closeout, stored `week_num` 4).
10. `reconData` is loaded in `loadAll` (7757) keyed by `week_num`; the snapshot loader mirrors it.

---

## 3. Slice 5G-1C-1 — Funding Plan Projection Semantics (display-only)

### 3.1 Three inputs the row needs (all available from today's `vm`)

- **`fundedNow`** = `getGoalFunded(id, vm)` — funded as of `currentW`. (After slice 2 this becomes *anchored + modeled-since*; the label logic does not change.)
- **`fundedYE`** = `vm.weeks[last].goalSaved[id]` — projected **year-end** funded (Cal Wk 53 / model wk 31). New read; the Funding Timeline already uses exactly this (4731-4733).
- **`comp`** = `vm.goalCompletion[id]` — completion week if the goal reaches 100% within the horizon.
- Derived: `remYE = max(0, target - fundedYE)` (projected year-end remaining).

### 3.2 New "When" / status decision tree

In priority order (replacing 4760-4777):

| # | Condition | Label (wording TBD — Adam confirms) | Class |
|---|---|---|---|
| 1 | `complete`/`executed` | `✅ Funded` | funded |
| 2 | `isLocked` (needsFlag off) | `🔒 Awaiting CPA` | locked |
| 3 | `auto` | `Auto · Cal Wk N` / `Auto · Payroll` | auto |
| 4 | `stretch` | `2027 restart` | stretch |
| 5 | `comp` within horizon | `Cal Wk N` (+ dates) | projected |
| 6 | `fundedNow > 0`, no `comp` | `In Progress · Continues in 2027` | pending |
| 7 | **`fundedNow == 0`, `fundedYE > 0`, no `comp`** | **`Partial in 2026 · Continues 2027`** (NEW — Bailey) | pending |
| 8 | `fundedNow == 0`, `fundedYE == 0` | `No 2026 funding projected` (replaces bare "Beyond 2026") | pending |

This satisfies every bullet of the task's "Required Funding Plan behavior" list. Row 7 is the missing case that produces the Bailey mislabel today.

### 3.3 Additional row display

- Show **projected year-end funded** and **projected year-end remaining** in the row (candidate: a sub-line under Remaining, or a second small figure in the Remaining cell). Keeps the existing `Remaining` (target − current funded) but adds the projected pair so the row and timeline agree. Exact layout is a design detail for Adam/Fable; the data is `fundedYE` / `remYE`.
- The Funding Timeline panel already renders projection fill and needs no change — slice 1 makes the **row** consistent with the **timeline**.

### 3.4 Forward compatibility with slice 2

`fundedNow` is sourced from `getGoalFunded`. Slice 2 changes what `getGoalFunded` *returns* (anchored vs pure simulation) but not its signature or the label logic. So slice 1 requires **zero rework** when slice 2 lands. `fundedYE` remains pure projection in both slices (future weeks are always projected).

### 3.5 Slice 1 scope guards

No schema, no RPC, no `runModel` math change, no routing, no priority/target change. `index.html` (`_renderGoalsFunding` only) + `test_regression.js` + `e2e.js`. No freeze exception needed (no `runModel` internals touched).

---

## 4. Slice 5G-1C-2 — Goal Funding State Integrity (schema + overlay)

### 4.1 Architecture decision — confirmed Option B, with the challenge run

The task asked me to confirm `goal_funding_snapshots` **or challenge it if a better design exists.** I ran the challenge and **confirm Option B.**

- **Option A — mutable `goal_registry.funded_amount` column: rejected.** No as-of-week semantics. Because `runModel` re-simulates all 31 weeks from scratch, a single "funded as of today" number seeded at week 1 double-counts the seed/waterfall flows already inside that number. No audit trail. Violates the house doctrine (derived views, no stored running balances). This is the disease, not the cure.
- **Option B — week-anchored `goal_funding_snapshots`, applied like `reconData`: recommended.** Same mental model as the proven reconciliation architecture (accounts re-anchor weekly; goals re-anchor weekly; one cadence, one closeout moment, one variance concept). **Solves re-simulation semantics exactly** (see §4.5). Kills the constant-drift class gradually (constants become pre-first-anchor seeds only). Enables the missing AMEX invariant.
- **Option C — append-only `goal_funding_events` ledger: correct end-state, not now.** Event-grain audit (contribution/release/adjustment) is the right home once 5G-1B payout releases and custodian moves need first-class history. Snapshots do not block it; events can be layered later with snapshots as the weekly checkpoint. Building C first is heavier UI/discipline for no additional protection this quarter.

**Did I find anything better than B?** No. The one genuinely different idea considered was storing a *delta-per-week* (contribution ledger) instead of a *cumulative snapshot*. Rejected for 5G-1C because deltas re-introduce the double-count risk under from-scratch re-simulation (you'd have to know which simulated deltas to suppress), whereas a cumulative snapshot **overwrites** and is self-correcting. Deltas are Option C's job, later.

### 4.2 Proposed schema

```sql
CREATE TABLE public.goal_funding_snapshots (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_year          INT  NOT NULL,
  week_num            INT  NOT NULL,           -- MODEL week (1..31), matches reconData / weekly_reconciliations
  goal_id             TEXT NOT NULL REFERENCES public.goal_registry(id),
  funded_amount       NUMERIC(12,2) NOT NULL,  -- observed CUMULATIVE funded at that reconciled week's end
  source              TEXT NOT NULL,           -- 'opening_anchor' | 'reconciliation' | 'correction'  (later: 'release')
  note                TEXT,
  created_by_user_id  UUID DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_gfs_year_week_goal UNIQUE (model_year, week_num, goal_id),
  CONSTRAINT chk_gfs_funded_nonneg CHECK (funded_amount >= 0),
  CONSTRAINT chk_gfs_source CHECK (source IN ('opening_anchor','reconciliation','correction')),
  CONSTRAINT chk_gfs_week_range CHECK (week_num BETWEEN 1 AND 31)
);
COMMENT ON TABLE public.goal_funding_snapshots IS
  'Week-anchored observed cumulative funded amount per goal. Applied in runModel like reconData (overwrite at anchor). Zero rows => identical to pre-5G-1C behavior.';
CREATE INDEX idx_gfs_year_week ON public.goal_funding_snapshots (model_year, week_num);
```

Notes:
- **Cumulative** funded, not delta (see §4.1). `funded_amount` is what the AMEX/T Rowe/custodian actually holds for that goal at that week's end.
- PK `(model_year, week_num, goal_id)` — one observation per goal per reconciled week.
- FK `goal_id → goal_registry(id)`. (`goal_registry.id` is the PK; confirm type is `TEXT`/`text` in the live schema during preflight.)
- `source`: `opening_anchor` for the first seed; `reconciliation` for weekly closeout anchors (5G-1D writes these); `correction` for ad-hoc fixes — the **only** source allowed to break cumulative monotonicity (DQ check §9). `release` reserved for 5G-1B, added then.
- Shared `updated_at` trigger via `public.fn_set_updated_at()`.

### 4.3 RLS / RPC approach

- **RLS:** `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`. `allow_read` `FOR SELECT TO authenticated USING (public.is_allowed_user())`. Writes go **only** through the RPC, but the table also carries conforming `financial_writer_insert`/`_update` policies (`WITH CHECK (public.can_write_financials())`) as defense-in-depth. **No DELETE policy** (snapshots are append/correct-only; no hard delete). No anon anything.
- **Grant normalization (the 5G-1 v1.4 lesson):** `REVOKE ALL ON public.goal_funding_snapshots FROM PUBLIC, anon, authenticated;` then `GRANT SELECT, INSERT, UPDATE ON public.goal_funding_snapshots TO authenticated;` (`service_role` untouched). Validation asserts the exact grant set (no DELETE/TRUNCATE/REFERENCES).
- **Write RPC** `save_goal_funding_snapshots(p_model_year INT, p_week_num INT, p_rows JSONB)` — mirrors the 5F-1 `save_reconciliation_with_commitments` pattern:
  - `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public` (closes the search_path hijack class).
  - First statement: `IF NOT can_write_financials() THEN RAISE EXCEPTION 'save_goal_funding_snapshots: not authorized'; END IF;` — authorization is **not** delegated to RLS.
  - Explicit `IS NULL` input validation (the 5F-1 comment warns bare `<>`/`NOT IN` vs NULL silently bypasses guards); `jsonb_typeof(COALESCE(p_rows,'[]')) = 'array'`.
  - Upsert each row `ON CONFLICT (model_year, week_num, goal_id) DO UPDATE` (so a re-confirmed closeout is idempotent). Every row validated: `goal_id` exists in `goal_registry`; `funded_amount >= 0`; `source` in the allowed set; **the week must be reconciled** (an `EXISTS` check against `weekly_reconciliations` for `(model_year, week_num)`) unless `source='opening_anchor'`.
  - Grant: `REVOKE ALL ON FUNCTION save_goal_funding_snapshots(...) FROM PUBLIC, anon, authenticated;` then `GRANT EXECUTE ... TO authenticated;`.
- **Ships in 5G-1C-2** so the table is not write-dead and the first anchor can be written the house way. **5G-1D** adds the UI caller. (Open question for Fable: acceptable, or hold the RPC for 5G-1D and seed the first anchor via SQL only? Recommendation: ship the RPC now.)

### 4.4 Seed / preflight plan — first anchor

- **Anchor week:** the latest **reconciled** week at seed time. Target is model week 5 (Cal Wk 27) once its closeout is saved; if only week 4 (Week 26) is reconciled at seed time, anchor there and let 5G-1D roll forward. Preflight asserts the chosen week has a `weekly_reconciliations` row.
- **`source='opening_anchor'`** for this first seed.
- **Confirmed values (Adam confirms before run):**

| goal_id | funded_amount | Rationale |
|---|---|---|
| `adam_ira` | **$7,438.94** | Post-Wk-27-sweep observed basis (integrity review; matches the deadlock-fix live state). |
| `wendy_ira` | $0 | Unless Adam confirms otherwise. |
| `bailey_529` | $0 | Unless confirmed. |
| `bryce_529` | $0 | Unless confirmed. |
| `preston_529` | $0 | Unless confirmed. |
| `alaska` | observed (likely $7,000 complete by Wk 27) | Alaska completes in-model; snapshot its observed funded value. Confirm. |
| `wendy_sep` | $17,859 | `opening_anchor`, completed goal — single source of truth for `getGoalFunded`. |
| `adam_401k` | **excluded** | Payroll/YTD model state, grows every paycheck. Stays `goalFundedAmounts` + `PAY_401K` accrual; 401k reconciliation deferred (see §4.6). |
| `wewe_rccl`, `wewe_dcl` | **excluded** | AMEX Savings *holding*; their snapshot/release modeling is 5G-1B. |
| `bryce_vehicle`, `christmas_cruise` | $0 | Confirm. |

- **Preflight** also asserts the AMEX invariant holds at the anchor within tolerance (§9), and that `goal_registry` contains every seeded `goal_id`.

### 4.5 runModel overlay design (the load-bearing part)

At the reconciliation overlay site (`index.html:2561-2566`), **after** `chk=rec.chk; ... lc=rec.lc;`, add — behind the identity gate:

```
if (goalSnapData[num]) {                      // absent => untouched => identity with today
  const snap = goalSnapData[num];             // { goal_id: funded_amount, ... }
  goalVariance = {};                          // per-goal modeled-minus-observed, mirrors balance `variance`
  Object.keys(snap).forEach(function(gid){
    if (goalSaved[gid] !== undefined) goalVariance[gid] = r(goalSaved[gid] - snap[gid]);
    goalSaved[gid] = snap[gid];               // OVERWRITE (not add) — reality wins
  });
}
```

Then include `goalVariance` in the week object beside `variance` (2606-2616), for display.

**Why overwrite-at-anchor is the correct and only safe semantics under from-scratch re-simulation:**
- Weeks are simulated in order. The overlay runs at the **end** of each week's iteration, *after* that week's waterfall already ran. So week W's own displayed sweeps stay simulation, but the **end-of-week** `goalSaved` is pinned to the observed anchor — exactly as `chk` is modeled (`mChk`) but reconciled (`chk`) after.
- Week W+1's `startsAfter` gates and `rem0` computations read `goalSaved` **after** the overlay → they start from anchored reality.
- The re-fired `RET_SAV_XFR` seed and every prior simulated sweep that happened *before* an anchor are **superseded** by the overwrite at that anchor. Double-counting past an anchor is therefore **structurally impossible** — this is precisely the property a week-1-seeded stored balance (Option A) cannot provide.
- `getGoalFunded` (currentW) and the Funding Timeline (final week) then read anchored-history for weeks ≤ last snapshot and projection for weeks after — the "current actual vs projected future" split the task requires.

**`getGoalFunded` change:** the complete/auto branch (4308, 4311) reads the latest snapshot with `week_num ≤ currentW` for that goal, falling back to `goalFundedAmounts[id]`. The model-backed branch (4310-4313) is unchanged — `goalSaved` is already anchored by the overlay.

### 4.6 Interaction answers (task objectives 4-9)

- **reconData:** snapshots ride the same weeks; the goal overlay runs *after* the balance overlay at the same site; a snapshot for an unreconciled week is disallowed by the RPC/validation (except `opening_anchor`).
- **Completed/executed goals:** `opening_anchor` at their completion/observed value; `getGoalFunded` reads snapshots instead of the hardcoded `goalFundedAmounts` (fixes the Wendy SEP hardcoding). Snapshot at completion week freezes the value.
- **`adam_401k`:** **excluded** from snapshots in 5G-1C. It is payroll YTD that accrues every paycheck; a static snapshot would go stale immediately and a per-paycheck reconciled snapshot is 401k-specific discipline out of scope here. Remains `goalFundedAmounts`/`PAY_401K` model state. Flag for a later dedicated item.
- **Alaska / RCCL / DCL:** Alaska completes in-model and gets normal reconciliation snapshots (seed its observed value at the anchor). RCCL/DCL are AMEX *holding*; their snapshot + payout-release modeling is **5G-1B** — excluded here. This keeps the AMEX invariant honest about the known holding offset.
- **AMEX holding balances:** the DQ invariant (§9) ties Σ(`_amxHold` goal snapshots) + non-goal AMEX float + (later) holding to the reconciled `amx`. In 5G-1C it is **advisory** (tolerance, holding-offset-aware), not a hard gate, because 5G-1B is unbuilt.
- **Double-counting on re-simulation:** solved by overwrite-at-anchor (§4.5).
- **Drift detection:** per-goal `goalVariance` at each anchor + the AMEX invariant + snapshot⊆registry + snapshot-week-reconciled + monotonicity-except-`correction`.
- **Snapshot disagrees with model's expected `goalSaved`:** the **observed snapshot wins** (like reconciled balances). The variance is **surfaced, not silently absorbed**; a large variance raises a DQ flag / closeout nag. Reality anchors; the model projects forward from reality.

---

## 5. Proposed rollback

- **SQL:** `phase-5g-1c-rollback.sql` (BEGIN; staging guard; `DROP FUNCTION save_goal_funding_snapshots(...)`; `DROP TABLE public.goal_funding_snapshots` — **no CASCADE**, fail loud on unexpected dependency; do **not** drop shared `fn_set_updated_at()` or the `app_environment` marker; COMMIT; RB1–RBn confirmation SELECTs; post-rollback schema-only diff vs the pre-migration baseline).
- **App:** the identity gate means zero snapshot rows ≡ pre-phase behavior, so reverting the `index.html` commit (or simply having no rows) restores exact prior output. Slice 1 rolls back independently by reverting its render commit.

---

## 6. Test plan

**Slice 1 (projection semantics):**
- Label truth table (static, pure-function over the decision tree): the 8 rows of §3.2, including the Bailey case (`fundedNow==0, fundedYE>0, comp==null → "Partial in 2026"`), the current-funded-incomplete case, and the genuinely-no-funding case.
- Assert row label agrees with the timeline for a fixture where `fundedYE>0` but `fundedNow==0`.
- e2e: Funding Plan under injected near-target/partial state no longer shows Bailey "Beyond 2026"; shows the partial/continues wording.

**Slice 2 (snapshots):**
- **Identity gate (freeze-safety proof):** zero snapshot rows ⇒ `runModel` output deep-equals current behavior (GR-A1 pattern, all 31 weeks × all goals × balances). Harness = the existing eval mechanism (test sets `goalSnapData={}`, runs, deep-compares to the pre-change golden-master).
- **Overlay behavior:** seed-from-anchor (goalSaved pinned at the anchor week; forward weeks project from it); mid-model re-anchor; **re-fired `RET_SAV_XFR` seed absorbed by a later anchor (no double-count)**; variance math (`goalVariance[id] == modeled − observed`); complete-goal reads via snapshot; missing-week passthrough (unsnapshotted week identical to today).
- **Display cases (the task's required set):** current-funded vs projected-year-end funded; complete within horizon; partial projected funding within horizon (Bailey); no projected funding within horizon; current funded but incomplete; **AMEX-held goal snapshot variance** surfaced.
- **DQ:** SQL validation suite in the migration package (AMEX invariant, snapshot⊆registry, snapshot-week-reconciled, no snapshots for archived goals, monotonicity-except-`correction`) + a JS assertion mirroring the AMEX invariant.
- **Golden-master:** capture the pre-change `runModel` output as the **first stored golden-master fixture** (none exists today); the identity gate diffs against it. Begins the 5G-2.5 convention early per AGENTS.md.
- **RPC:** authorization gate (`can_write_financials()` false ⇒ reject), input validation (`IS NULL`, non-array `p_rows`, bad `goal_id`, negative amount, unreconciled non-anchor week), idempotent upsert.

**Regression families to review (flagged in the integrity review §8):** `test_regression.js` seed-sensitive families and the PHASE-A section; GR-A1 (3978-4030). Re-run WC-3/WC-4 (break-semantics adjacency).

**Manual verification before deploy:** run the two integrity-review scenario scripts against the working tree; Adam eyeballs Wk 29 prescribed transfers and the Funding Plan tab; after Wk-27/28 closeouts confirm per-goal variance reads $0.00 while reality follows the plan.

## 7. e2e smoke plan

- Slice 1: Funding Plan tab renders projection-aware labels; Bailey shows partial/continues, not "Beyond 2026"; a $0-projected goal shows "No 2026 funding projected."
- Slice 2: snapshot-missing banner appears when `goalSnapData` is empty; with an injected anchor, `getGoalFunded` on a complete goal reads the snapshot; Funding Plan shows "anchored to weekly reconciliation; future weeks are projections" framing. (Closeout **write** e2e is 5G-1D.)
- Note the known intermittent LEDGER-1/A9-1 headless flakiness (clears on re-run).

---

## 8. Data-quality checks / invariants (SQL + JS)

1. **AMEX invariant (advisory in 5G-1C):** at any snapshotted week, `Σ(funded_amount for _amxHold goals) + non-goal AMEX float (+ holding once 5G-1B) ≈ reconciled amx` within tolerance.
2. **snapshot ⊆ registry:** every `goal_id` exists in `goal_registry`.
3. **snapshot-week-is-reconciled:** every non-`opening_anchor` snapshot week has a `weekly_reconciliations` row.
4. **no snapshots for archived goals.**
5. **cumulative monotonicity:** `funded_amount` per goal is non-decreasing across weeks **except** rows with `source='correction'` (the only sanctioned decrease, e.g. a custodian correction or a future `release`).

---

## 9. Answers to the 10 architecture questions (consolidated)

1. **Is `goal_funding_snapshots` right for 5G-1C?** Yes (Option B), confirmed after challenge (§4.1).
2. **Exact schema?** §4.2.
3. **Weekly anchors only, or ad-hoc corrections?** Primarily weekly closeout anchors (`reconciliation`) + first `opening_anchor`; `correction` is an explicit, DQ-visible escape hatch and the only monotonicity exception.
4. **Interaction with reconData?** Same weeks; goal overlay after balance overlay at 2566; non-anchor snapshots require a reconciled week (§4.6).
5. **Completed/executed goals?** `opening_anchor` at observed value; `getGoalFunded` reads snapshots (fixes hardcoding) (§4.6).
6. **AMEX Savings holding?** Advisory invariant now; holding-release-aware at 5G-1B; RCCL/DCL excluded from 5G-1C snapshots (§4.6).
7. **Avoid double-counting on re-simulation?** Overwrite-at-anchor supersedes all prior simulated flows including the re-fired seed (§4.5).
8. **Drift detection?** Per-goal variance + AMEX invariant + registry/reconciled/monotonicity DQ (§8).
9. **Snapshot disagrees with model?** Observed wins; variance surfaced + nagged, not absorbed (§4.6).
10. **Deferred to 5G-1D/1E (and beyond)?** Weekly closeout write-through UI → **5G-1D**. Full account-purpose/holding-bucket logic and the AMEX invariant as a hard gate → **5G-1E**. `adam_401k` reconciliation, 5G-1B release rows, Ask Claude payload rebuild, seed/`mvS` hardening + target cap, `ira_cpa_cleared` persistence, `goalRt`/`goalAk` fallback tidy, full actuals-implying-language copy sweep → later, explicitly out of 5G-1C.

---

## 10. Recommended sequencing with 5G-1D / 1E / 1F

Using the roadmap in the task brief:

1. **5G-1C-1 (projection semantics)** — now; pre-close, pre-freeze, low risk. Fixes the visible Bailey mislabel.
2. **5G-1C-2 (snapshot integrity)** — staging rehearsal next; prod DDL + overlay before the Alaska freeze (Jul 24) if gates pass, else after Aug 10. Ships table + RPC + overlay + first `opening_anchor` + golden-master fixture.
3. **5G-1D — Weekly Closeout Goal Attribution** — adds the prefilled one-click snapshot write at each weekly closeout, calling the 5G-1C-2 RPC. Turns coincidental agreement into a reconciled cadence.
4. **5G-1E — Account Purpose / Holding Bucket Integrity** — promotes the AMEX invariant from advisory to a hard invariant; full purpose/holding allocation; consumes 5G-1B releases.
5. **5G-1F — July Month-End Close** — benefits from having at least the opening anchor + one or two reconciled weekly snapshots in place.
6. **5G-2+ (Planned Outflows / Cash Allocation)** — the Spoken For / Free to Use view derives from this attribution; must be built on reconciled snapshots, not simulation. Gated on 5G-1C-2.

**Note for Fable:** the on-disk `docs/phase-status.md` still labels 5G-2 as "Derived Account Allocation view" and has 5G-1 = planned_outflows (staging-validated). The task brief's roadmap inserts 5G-1D/1E/1F and renumbers 5G-2 to "Planned Outflows Foundation." These two maps disagree; I followed the task brief for sequencing. **Reconciling the phase map is an open decision for Adam** (§12 Q9).

---

## 11. Risk register (beyond §1.3)

| Risk | Mitigation |
|---|---|
| Overlay implemented as additive, not overwrite → double-count | Explicit overwrite in the overlay; a dedicated "re-fired seed absorbed by later anchor" test; identity gate. |
| Wrong first-anchor values anchor model to wrong reality | Adam confirms every seeded value; preflight asserts the AMEX invariant at the anchor. |
| Editing frozen `runModel` internals | Explicit freeze exception (5G-1A.5 precedent); characterization/golden-master pins everything else byte-identical; overlay is behind the identity gate. |
| Non-atomicity between recon save and snapshot save (separate RPCs) | 5G-1D sequences them in the closeout UI + a "snapshot missing for reconciled week" nag + DQ check #3. (Not a 5G-1C concern beyond the RPC contract.) |
| AMEX invariant false alarms from the known RCCL/DCL holding offset | Invariant is advisory + holding-offset-aware in 5G-1C; hard gate deferred to 5G-1E after 5G-1B releases. |
| Golden-master captured from a wrong baseline | Capture on a clean tree at the exact pre-slice-2 commit; identity gate is the acceptance test. |

---

## 12. Open questions / decisions needed from Adam (for the Fable gate)

1. **Two-slice split approved?** Projection-semantics slice ships first (display-only, pre-close), snapshot slice second.
2. **Confirm first-anchor values** (§4.4), especially: Alaska observed value at the anchor week; bryce_vehicle/christmas_cruise = $0; wendy_ira/529s = $0.
3. **`adam_401k` excluded from snapshots** in 5G-1C (payroll YTD) — agree?
4. **RCCL/DCL excluded** (holding, 5G-1B) — agree?
5. **Write RPC ships in 5G-1C-2** (vs held for 5G-1D)? Recommendation: ship now so the first anchor is written the house way and the table isn't write-dead.
6. **Wording** for the new "When" labels (§3.2 rows 6-8) — "Partial in 2026 · Continues 2027", "In Progress · Continues in 2027", "No 2026 funding projected" acceptable, or preferred phrasing?
7. **Anchor week:** Wk 27 (model wk 5) once reconciled, or Wk 26 (model wk 4) now with 5G-1D rolling forward?
8. **AMEX invariant advisory in 5G-1C**, hard gate in 5G-1E — agree?
9. **Phase-map reconciliation:** adopt the task-brief roadmap (5G-1D/1E/1F + 5G-2 = Planned Outflows) as authoritative and update `docs/phase-status.md`?
10. **Freeze exception** for the 5G-1C-2 `runModel` overlay edit — approve (5G-1A.5 precedent)?
11. **Golden-master fixture:** capture the first stored `runModel` fixture as part of 5G-1C-2 (begins 5G-2.5 convention early) — approve?

---

*Plan-only. No code changed. Prepared for Fable architecture review. On approval, implementation proceeds slice 1 → staging rehearsal of slice 2 → prod DDL + overlay, each behind the standing test gates (static regression + e2e) and the golden-master identity gate.*
