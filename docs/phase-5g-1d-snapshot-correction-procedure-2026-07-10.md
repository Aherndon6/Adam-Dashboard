# Phase 5G-1D — Snapshot Correction / Reconciliation Reopen / Historical Remediation Procedure

**Status:** PLAN-ONLY companion specification. **Not started, not implemented, not
activated.** No code, SQL, schema, RPC, RLS, migration, seed, grant change, or test
written or run this pass. No Supabase access. E2 has **not** executed;
`goal_funding_snapshots` is **EMPTY**; the 5G-1D wrapper does **not** exist yet.
**Author:** Claude (session under Adam)
**Date:** 2026-07-10
**Revision:** R1 (2026-07-10) — folded in four Fable pre-review anchors: **A**
existing-row requirement, **B** opening-anchor source collision, **C**
shared-`authenticated`-role grant reality, **D** `is_owner()` identity preflight.
R2 (2026-07-10) — folds in the eight Fable review findings: **F-1** governs the deployed
`repair_commitments_for_week` RPC (Finding 11, §3.1, §14, §17, §18); **F-2** adds the
E2→activation interim-window rule (§3.2, §18); **F-3** makes Option B concrete and
time-bound to 5G-1D Slice-2 (§4.1, §4.2); **F-4** defines nearest-existing adjacent
semantics (§7.0); **F-5** removes row-creation ambiguity (§4, §9, §10, §14, §15, §18);
**F-6** requires hard-reload live-render verification (§6.1, §9, §15, §16); **F-7**
strengthens the evidence/artifact model (§11); **F-8** expands the tests (§15). Plus
tightened opening-anchor execution (§8), strengthened `is_owner()` preflight (Finding 8,
§19), and the subordinate-artifact boundary (§17.1).

> **Review-state note.** This file being **committed on the feature branch
> `claude/5g-1d-snapshot-correction-spec-efjplu` is NOT the same as being cleared.** The
> commit exists only to give Fable a stable, hash-pinned artifact to review. Clearance is
> a separate act by Fable + Adam; nothing here authorizes merge, implementation, SQL,
> Supabase access, or any production action.

**Subordinate to — and consistent with, not a replacement for:**
- `docs/phase-5g-1c-2-e2-runbook.md` (E2 first-anchor seed gate; cleared).
- `docs/phase-5g-1d-plan-2026-07-09.md` (the cleared 5G-1D write-through plan; the
  authoritative slice plan — this document does **not** restate or rewrite it).
- the deployed reconciliation RPC `public.save_reconciliation_with_commitments`
  (`docs/phase-5f-1-migration.sql:454`).
- the deployed E1 snapshot table + RPC `public.goal_funding_snapshots` /
  `public.save_goal_funding_snapshots` (`docs/phase-5g-1c-2-prod-migration.sql`).
- the deployed role predicates `public.is_owner()` / `public.can_write_financials()`
  (`docs/phase-5a-role-enforcement.sql`).
- the shipped C3 loader/overlay (`index.html` — loader 7843–7856, overlay 2571–2588,
  `getGoalFunded` 4349–4366, `_latestGoalSnapshot` 4341–4348).

**What this document is.** A focused **delta** specification for the *exceptional*
correction and remediation operations that sit beside the ordinary 5G-1D weekly
closeout: reconciliation reopen, snapshot correction, opening-anchor correction,
historical single-week and multi-week remediation, and their boundary against rollback
and ordinary retry. Where the cleared 5G-1D plan already decides a rule (§3.5, §5.8,
§6.4, §9 of that plan), this document **cites and operationalizes** it — it never
overrides it. Where the plan leaves a mechanism open (notably *how* an owner-only
correction is actually executed), this document supplies the grounded recommendation
and flags it for Adam's decision.

> **Grounding note (read before trusting any "owner-only" claim below).** The deployed
> `save_goal_funding_snapshots` RPC authorizes on **`can_write_financials()`**, which
> passes for **both** Adam (owner) and Wendy (household_admin), and its `source` CHECK
> already permits `'correction'`. **The deployed RPC does not, by itself, enforce an
> owner-only correction boundary.** Every "owner-only" requirement in this document
> therefore depends on a mechanism *other than* the deployed snapshot RPC — see §4/§5.

---

## 0. Grounded repository findings that shape this design

These are the facts read out of the actual repository/DDL/app this pass. They are the
load-bearing constraints for every section below.

1. **Deployed reconciliation RPC** — `save_reconciliation_with_commitments(p_week_num
   INT, p_model_year INT, p_chk NUMERIC, p_sav NUMERIC, p_amx NUMERIC, p_tax NUMERIC,
   p_lc NUMERIC, p_balance_basis TEXT, p_recorded_at TIMESTAMPTZ, p_new_commitments
   JSONB, p_patched JSONB) RETURNS JSONB` — SECURITY DEFINER, `SET search_path=public`,
   gated on `can_write_financials()` (`phase-5f-1-migration.sql:454–503`), `model_year`
   pinned to 2026. **Its body and signature are immutable for this work.**

2. **Deployed snapshot table** — `public.goal_funding_snapshots` with
   `UNIQUE(model_year, week_num, goal_id)` (natural key), `funded_amount >= 0`,
   `source IN ('opening_anchor','reconciliation','correction')`, `week_num BETWEEN 1
   AND 31`, `created_by_user_id UUID DEFAULT auth.uid()`, `updated_at` bumped by
   `fn_set_updated_at()` trigger. **No DELETE policy; no DELETE grant**
   (`phase-5g-1c-2-prod-migration.sql:120–283`).

3. **Deployed snapshot RPC** — `save_goal_funding_snapshots(p_model_year INT, p_week_num
   INT, p_rows JSONB) RETURNS INTEGER`, SECURITY DEFINER, `SET search_path=public`,
   **authorized via `can_write_financials()`** (line 179 — *not* `is_owner()`).
   Validates: auth → model_year → week 1..31 → non-empty JSON array → **week reconciled
   (week_num-only)** → per-row (goal present, funded numeric ≥ 0, source ∈ the three
   literals, goal in registry, **not auto**, **not in holding/deferred exclusion set**)
   → idempotent upsert on the natural key. **It does not enforce adjacent-week
   monotonicity.** Grants: `authenticated = {SELECT,INSERT,UPDATE}` (no DELETE).

4. **`can_write_financials()` vs `is_owner()`** (`phase-5a-role-enforcement.sql`):
   `can_write_financials()` = `role IN ('owner','household_admin')`;
   `is_owner()` = `role = 'owner'`. Both SECURITY DEFINER, both key on
   `auth_user_id = auth.uid()`. **Consequence: any RPC gated on
   `can_write_financials()` permits Wendy.** Owner-only requires `is_owner()` (or an
   operational boundary — §5).

5. **SQL-editor auth reality.** In the Supabase SQL editor, `auth.uid()` is **NULL**.
   Therefore `can_write_financials()` and `is_owner()` both return **false** there, and
   any RPC gated on them **raises 'not authorized'** if invoked from the SQL editor.
   This is exactly why the E2 first anchor is a **guarded direct INSERT**
   (`seed-anchor.sql`), not an RPC call. A guarded direct SQL statement in the editor
   runs as the table owner and **bypasses RLS and the RPC gate entirely** — it has no
   caller identity at all.

6. **Correction is in-place; there is no row history.** Under the natural key +
   `ON CONFLICT DO UPDATE`, a correction **replaces `funded_amount` and `source` in the
   existing row** and leaves exactly one row per `(model_year, week_num, goal_id)`. The
   row carries `source`, `note`, `created_by_user_id`, `created_at`, `updated_at` — but
   an in-place update **is not a complete audit ledger.** External before/after evidence
   is mandatory (matches 5G-1D plan §3.5).

7. **Overlay/loader are source-blind and resolve by natural key.** The C3 loader
   (`index.html:7843`) selects `week_num,goal_id,funded_amount` — **`source` is never
   fetched.** `_latestGoalSnapshot(id,wk)` (4341–4348) returns the value at the highest
   `week_num ≤ wk`. The overlay (2580–2587) overwrites `goalSaved[gid]` for
   model-tracked goals when `goalSnapData[num]` exists. So a `correction` row is fully
   visible and effective the moment it exists; `source` changes nothing about
   resolution or display.

8. **`is_owner()` identity — a mandatory read-only production preflight, NOT a presumed
   defect (Fable anchor D).** Phase 5A set `role='owner'` `WHERE
   email='adam@herndons.us'`, while AGENTS.md states the real Adam app login is
   `aherndon6@gmail.com` and that `adam@herndons.us` "exists in auth.users for seed UUID
   purposes only, not app_users." This is **not** asserted here as a live bug — it is a
   verification obligation. **Before any owner-only correction or reopen feature ships, a
   read-only production preflight must prove all of:**
   - **exactly one active owner row exists** in `app_users` (`role='owner' AND
     active=true`);
   - **its `auth_user_id` maps to Adam's real authenticated account** (the app login, not
     the seed identity);
   - **Adam's real login session returns `public.is_owner() = true`**;
   - **Wendy's session returns `public.is_owner() = false`**;
   - **no role-data change is inferred or authorized by the preflight** (it is read-only).

   **This task makes NO production role-data change** — it only records the preflight
   requirement. The 5G-1 RLS smoke's confirmation that `can_write_financials()` keys on
   `auth.uid()` is **supporting expectation, not a substitute** for this owner-row
   production verification.

9. **No wrapper, no anchor, no snapshots yet.** `save_weekly_closeout_with_snapshots` /
   `approved_reopen` are plan-only. E2 has not run. `goal_funding_snapshots` is empty.
   **Nothing in this document is exercisable until E2 seeds the Week-5 anchor and 5G-1D
   ships.** This is a forward specification, not an operable procedure today.

10. **Precedent for supervised one-off corrections already exists in-repo:** the A4 AMEX
    Gold starting-balance correction (`docs/2026-07-06-amex-gold-starting-balance-A4.sql`
    — natural-key-pinned, guarded single transaction, preflight/postflight assertions
    inside the transaction, no row history disturbed) and the E2 seed-anchor pattern.
    The correction mechanism recommended here (§4/§5) follows that established shape.

11. **A second deployed reconciliation-mutation path exists and is REST-callable by Wendy:
    `repair_commitments_for_week` (Fable finding F-1).** Signature (grounded in
    `docs/phase-5f-1-migration.sql:997`):
    `public.repair_commitments_for_week(p_week_num INT, p_model_year INT, p_balance_basis
    TEXT DEFAULT NULL, p_new_commitments JSONB DEFAULT '[]', p_patched JSONB DEFAULT '[]')
    RETURNS JSONB`. It is:
    - **`SECURITY DEFINER`**, `SET search_path = public` (line 1006–1007);
    - **gated by `can_write_financials()`** (line 1036) — so **executable by
      `authenticated`, i.e. callable by BOTH Adam and Wendy/household_admin**;
    - granted `GRANT EXECUTE … TO authenticated` (line ~1338; `REVOKE ALL … FROM PUBLIC,
      anon, authenticated` first);
    - **currently unwired in the UI** (historical-repair mode was never built — 5F-1
      Phase-4 handoff) **but fully REST-callable** at `POST /rest/v1/rpc/`;
    - able to **insert new historical commitments** (`p_new_commitments`) and **patch
      existing ones** (`p_patched`) for a week whose reconciliation row already exists;
    - **able to mutate terminal (cleared/voided) commitment rows** — explicitly intended
      (line 975–995), unlike `save_reconciliation_with_commitments`, though every call is
      scope-confined to `origin_model_week = p_week_num`;
    - able to **update `weekly_reconciliations.balance_basis` for a reconciled week**
      (line ~1066, `UPDATE weekly_reconciliations SET balance_basis = p_balance_basis
      WHERE week_num = p_week_num`).
    **Consequence:** `repair_commitments_for_week` is a *pre-wrapper* REST path — usable by
    Wendy today — that can change a **closed, reconciled, anchored, or historical** week's
    commitments and `balance_basis`. It is therefore an **exceptional remediation operation
    governed by this specification** (§3.1). **This task does not alter the deployed RPC.**

---

## 1. Purpose and scope — the eight operations are distinct and non-interchangeable

This document governs a family of operations that share a table but are **separately
authorized**. Approval for one **never** authorizes another (§12).

| Operation | What it changes | Normal or exceptional | Governing authority |
|---|---|---|---|
| **Ordinary weekly closeout** | writes the next sequential week's nine `reconciliation` snapshots + reconciliation | normal | 5G-1D plan §2, §6.1 (not this doc) |
| **Identical retry** | re-submits an already-persisted closeout with **byte-identical** values (idempotent upsert) | normal | 5G-1D plan §2.3.1 (not this doc) |
| **Half-closed-week repair** | completes the snapshot half of a reconciled-but-unsnapshotted week | normal | 5G-1D plan §6.3 (not this doc) |
| **Reconciliation reopen** | corrects persisted reconciliation actuals/commitments for a **closed** week | **exceptional** | §3 (this doc) + 5G-1D plan §5.8 |
| **Snapshot correction** | replaces a `funded_amount` in place for one `(year,week,goal)` | **exceptional** | §4–§7 (this doc) + 5G-1D plan §3.5/§6.4 |
| **Opening-anchor correction** | corrects a Week-5 `opening_anchor` value | **exceptional (special)** | §8 (this doc) |
| **Historical single-week remediation** | corrects a past week with **no** later-week change | **exceptional** | §9 (this doc) |
| **Historical multi-week remediation** | correction that forces changes to later weeks | **exceptional (escalated)** | §10 (this doc) |
| **Rollback** | break-glass DROP of the table/RPC for a structural defect | **exceptional (never a value fix)** | 5G-1D plan §9 + E2 runbook §8 |

**Hard rule.** These are **not interchangeable**. In particular: a rollback is **not** a
correction; a correction is **not** an ordinary retry; a reconciliation reopen is
**not** a snapshot correction; a historical remediation is **not** a latest-week
correction. Mislabeling any one of these as another is a stop condition (§14, §18).

**Scope of this document.** The *exceptional* rows above. The three *normal* rows are
owned by the cleared 5G-1D plan and are referenced here only for boundary definition.

---

## 2. Governing principles (preserved verbatim in intent from the cleared plans)

The following invariants are inherited and **must not be weakened** by any operation in
this document. Each cites its source of truth.

1. **No destructive automatic rollback of a completed reconciliation.** A wrong value is
   fixed forward (correction / reopen); the completed reconciliation stays. (5G-1D plan
   §3.5, §9; E2 runbook §8.)
2. **No silent rewriting of later weeks.** No correction cascades. A correction that
   would require later-week changes escalates to multi-week remediation (§10). (5G-1D
   plan §6.4.1.)
3. **No duplicate natural-key rows.** Every correction is an in-place upsert on
   `(model_year, week_num, goal_id)` — exactly one row survives. (Finding 6; deployed
   `UNIQUE` + `ON CONFLICT DO UPDATE`.)
4. **No bypass of the Week-5 opening anchor.** The E2 anchor is the floor of all
   forward reasoning; no operation here creates, replaces, or reinterprets it except the
   explicitly-gated opening-anchor correction (§8). (5G-1D plan §5.6; E2 runbook §1.)
5. **No changes to the deployed E1 snapshot RPC.** If any design below would require
   editing `save_goal_funding_snapshots`, the design instead halts and reports it as a
   hard stop (§18) — the RPC is never silently edited.
6. **No changes to the deployed reconciliation RPC body or signature.** Reopen uses the
   future 5G-1D wrapper, which *calls* the deployed RPC directly; it never edits it.
   (5G-1D plan §1, §5.2.)
7. **No ordinary household-admin access to exceptional operations.** Wendy may run
   ordinary closeout (`can_write_financials()`); she may **not** perform reopen,
   correction, or remediation. (§3, §4, §13; 5G-1D plan §5.8.)
8. **All exceptional operations require explicit Adam approval.** No approval is inferred
   from another (§12).
9. **Correction evidence is mandatory** because an in-place update does not preserve full
   row history (Finding 6; §11).

---

## 3. Reconciliation reopen (supervised, owner-only)

Corrects persisted reconciliation actuals, commitments, or other reconciliation fields
**after a week has closed** (reconciled **and** anchored with a complete nine-row
snapshot set).

**This operationalizes 5G-1D plan §5.8 / §5.8.1 — it does not redefine it.** Reopen is a
mode of the *future* 5G-1D orchestration wrapper (`p_mode='approved_reopen'`), not a
standalone artifact. Until that wrapper is built and activated, **there is no approved
*owner-only* reopen mechanism.** Note (correcting an earlier draft): a direct SQL editor
action is **not** the only pre-wrapper way to touch closed reconciliation — the deployed
`repair_commitments_for_week` RPC (Finding 11) is a **REST-callable pre-wrapper path**,
usable by Wendy today, that can mutate a closed/anchored week's commitments and
`balance_basis`. Both surfaces (direct SQL and `repair_commitments_for_week`) are
**forbidden outside the exceptional-remediation gate** defined in §3.1 and §3.2; neither
is an ordinary or self-authorizing path.

Requirements (all mandatory; any missing → HALT):

- **Latest completed week only** for the initial scope. Older weeks require the
  separately reviewed historical-remediation path (§9/§10). (5G-1D plan §5.8 scope
  limit.)
- **Database-enforced owner authorization through `public.is_owner()`** inside the
  wrapper's `approved_reopen` branch. The client `isOwnerUser()`
  (`index.html:7786`, `USER_ROLE==='owner'`) is UI-only and is **not** the enforcement.
  A non-owner authenticated writer (Wendy) must be rejected even though
  `can_write_financials()` would otherwise permit weekly closeout. (5G-1D plan §5.8.)
- **No restoration of ordinary direct authenticated access to the old reconciliation
  RPC.** After the §7-activation revocation (5G-1D plan §7), reopen executes **through
  the wrapper's owner-only branch as the definer owner** — never by re-granting direct
  `authenticated` EXECUTE on `save_reconciliation_with_commitments`. (5G-1D plan §6.2,
  §9.)
- **Use of the future 5G-1D wrapper `approved_reopen` mode** (`p_mode`), supervised and
  manually executed. The ordinary browser UX may pass only `normal_closeout`.
- **Resubmission of the existing nine snapshot values unchanged.** The reopen resubmits
  the already-approved nine amounts idempotently (natural-key upsert, no change) with
  **`source` remaining `reconciliation`** (never `correction`). If the snapshot amounts
  *also* need fixing, that is a **separate** snapshot correction (§4) under its **own**
  approval — never bundled into the reopen. (5G-1D plan §5.8.1/§5.8.2.)
- **Source remains `reconciliation`** on the resubmitted snapshot rows.
- **Complete atomic rollback if any step fails.** Straight-line, no swallowed error;
  any exception aborts the whole transaction — nothing partial persists. (5G-1D plan
  §5.4, §5.8.1 step 6.)
- **Before/after reconciliation evidence** captured: the persisted actuals/commitments
  before, the corrected values after, rationale, approving Adam decision, timestamp,
  target week (§11).

**Approval / execution boundary.** Reopen has its own explicit per-week Adam approval
(§12). It may **not** be executed before the 5G-1D wrapper ships and is activated, and
**not** on any week other than the latest completed one.

**Preflight gate specific to reopen:** production must first confirm `is_owner()`
returns true for the real Adam login (Finding 8) — otherwise the owner-only branch would
reject Adam.

### 3.1 Governance of `repair_commitments_for_week` (F-1)

**Any invocation of `repair_commitments_for_week` that affects a closed, reconciled,
anchored, or historical week is an exceptional remediation operation governed by this
specification** — not an ordinary reconciliation write, and never a self-authorizing one.
Because the deployed RPC is gated only on `can_write_financials()` (Finding 11), the
owner-only and evidence boundaries below are **procedural** until the 5G-1D activation
step revisits its grant (see §17 handoff); the DB does not yet enforce them for this RPC.

Every such invocation requires **all** of:

- **explicit Adam approval** for that specific week and change (its own gate; §12);
- **the full §11 evidence package**, including **pre/post capture of both the
  reconciliation row (`weekly_reconciliations`, incl. `balance_basis`) and the affected
  `cash_commitments` rows** (before and after);
- **no household_admin (Wendy) use** — even though the deployed grant technically permits
  it, Wendy must not invoke `repair_commitments_for_week` against a closed/anchored/
  historical week under this design;
- **no ordinary UI or retry-path invocation** — it is not wired into the UI and must not
  be reached through any ordinary closeout, resave, or retry control;
- **no silent use outside this documented remediation gate** — no unlogged, unapproved,
  or "quick fix" call.

If the repaired week is **anchored**, and the commitment/`balance_basis` change alters the
factual basis of a seeded anchor amount, **route to the opening-anchor correction process
(§8)** — a `repair_commitments_for_week` call cannot silently invalidate an anchor.

### 3.2 E2-to-activation interim-window rule (F-2)

This subsection governs the interval **from E2 production seed complete through 5G-1D
production activation.** During this window the 5G-1D wrapper does not yet exist, so the
deployed `save_reconciliation_with_commitments` **and** `repair_commitments_for_week`
remain directly callable (both `authenticated`, i.e. Adam and Wendy).

Plainly, during the interim window:

- **Any change to an anchored week's reconciliation actuals, commitments, or
  `balance_basis` requires explicit Adam approval.** Once the E2 anchor is established, the
  anchored week's reconciliation is no longer freely editable.
- **Ordinary UI resave of an anchored week is NOT treated as routine.** The convenience of
  re-saving reconciliation from the UI does not carry over to a week that has been
  anchored.
- **Any such change requires the full §11 evidence package** (with pre/post reconciliation
  + commitment capture, §3.1).
- **The original E2 First-Anchor Value Card basis must be re-verified** — confirm whether
  the change affects the reconciled state the anchor was built on.
- **If the changed reconciliation state affects the factual basis of an anchor amount,
  route to the opening-anchor correction process (§8).**
- **This control is procedural only** until the 5G-1D wrapper and the activation grant
  changes (§7 of the 5G-1D plan) exist to enforce it in the database.
- **Wendy (household_admin) must not perform an anchored-week reconciliation amendment
  during the interim window.**

This is an explicit **risk** (a stale-anchor / silent-reconciliation-drift window) and an
**operational stop condition** (§18): an unapproved anchored-week reconciliation or
commitment change during the interim window is a hard stop.

---

## 4. Snapshot correction (in-place `funded_amount` fix)

Corrects the funded amount for an existing `(model_year, week_num, goal_id)` natural key.

**Explicit properties (grounded in the deployed DDL — Findings 3, 6, 7):**

- **The exact target natural-key row MUST already exist — verified first (Fable anchor
  A).** The deployed RPC and any guarded upsert use `INSERT … ON CONFLICT DO UPDATE`, so
  a correction call for a `(model_year, week_num, goal_id)` that does **not** already
  exist would silently **INSERT a brand-new historical row** — i.e. a backfill disguised
  as a correction. **Every correction mechanism must first confirm the target row
  exists** (`SELECT … WHERE (model_year, week_num, goal_id) = target` returns exactly one
  row). **If it does not exist → HARD STOP.** A correction is an amendment of an existing
  value, never a backfill; creating a missing week/goal row is historical remediation
  (§9/§10) or belongs to E2/closeout, and requires its own separate design + approval —
  it is never reached through the correction path.
- **Replaces the existing `funded_amount` in place** via upsert on the natural key.
- **Sets `source='correction'` — EXCEPT for a Week-5 opening-anchor row, which preserves
  `source='opening_anchor'` (Fable anchor B; see §8).** For any *post-anchor*
  (`reconciliation`) row, a correction pins `source='correction'`. For a Week-5
  `opening_anchor` row, a value amendment **keeps `source='opening_anchor'`** so the
  anchor set stays nine rows all `opening_anchor` and the future wrapper anchor guard
  (5G-1D plan §5.6) continues to pass; the fact of correction is recorded in the external
  evidence and the row `note`, not by flipping `source`.
- **Leaves exactly one row** for the week and goal — **does not append a second row.**
- **Does not automatically alter reconciliation** (the reconciled `weekly_reconciliations`
  row and any commitments are untouched by a snapshot correction).
- **Requires separate Adam approval** (distinct from any reopen or closeout approval).
- **Requires owner-only execution** (§5 — this is where the deployed RPC is insufficient).
- **Requires mandatory before/after evidence** (§11) because the write is in place.

### 4.1 Initial mechanism — A vs B, and why the deployed RPC is not option A

**The deployed `save_goal_funding_snapshots` RPC is NOT a sufficient correction
mechanism**, for three grounded reasons:

1. **It authorizes Wendy.** Its gate is `can_write_financials()` (Finding 3), so
   `household_admin` could submit `source='correction'` — violating the owner-only
   boundary this operation requires. **Could Wendy technically submit `source='correction'`
   today? Yes** — via the deployed RPC over an authenticated REST call: the CHECK permits
   the literal and `can_write_financials()` passes for her. That is precisely the boundary
   violation this spec must close.
2. **It cannot be called from the SQL editor** (`auth.uid()` NULL → 'not authorized',
   Finding 5), so the usual supervised-SQL execution surface is unavailable through it.
3. **It enforces no correction-specific invariant** — no adjacent-week monotonicity
   (§7), no "single target goal" scoping, no owner check. It would happily accept a
   value that breaks the cumulative sequence.

So the two real candidate mechanisms are:

**Option A — documented supervised manual guarded procedure (SQL-editor, Adam-only).**
A guarded single-transaction SQL correction executed by Adam in the Supabase SQL editor,
following the A4 / E2-seed precedent (Finding 10): explicit preflight (row exists,
current value, preceding + following effective values), a natural-key-targeted
`INSERT … ON CONFLICT DO UPDATE` (or guarded `UPDATE`) that sets `funded_amount` and
`source='correction'`, and postflight assertions inside the transaction (row count
unchanged, single row, adjacent-week monotonicity holds), all wrapped `BEGIN/COMMIT`.
- **Owner-only is enforced *operationally*** — only Adam has SQL-editor access, and each
  run is explicitly Adam-approved. There is **no `is_owner()` caller check** because the
  SQL editor has no `auth.uid()` (Finding 5); the statement runs as table owner and
  bypasses RLS.
- **Adjacent-week monotonicity (§7) is enforced by the guard block**, not by any RPC.
- Pros: works **today** with **zero new deployed surface**; matches the established A4/E2
  precedent; the guard can enforce every correction invariant; no attack surface added.
- Cons: "owner-only" is an **operational** property (SQL-editor access + approval), not a
  DB-cryptographic one; a hand-authored guarded UPDATE is inherently more error-prone
  than a reviewed function and must be diffed against a reviewed template each time.

**Option B — new additive owner-only *call-through* correction RPC (planned into 5G-1D
Slice-2; F-3).** `public.correct_goal_funding_snapshot(...)` is an additive SECURITY
DEFINER wrapper — the **post-anchor correction counterpart** of the 5G-1D closeout
wrapper — with the concrete contract:
- **`SECURITY DEFINER`**, safe fixed `SET search_path`, fully schema-qualified, no dynamic
  SQL;
- **`GRANT EXECUTE … TO authenticated`** (PostgREST routing) with an **internal
  `public.is_owner()` check as its first action** that **rejects `household_admin`**
  (Wendy) — owner-only is DB-enforced, not grant-enforced (§13);
- **asserts the target natural-key row already exists** (F-5; a missing row → raise, never
  a backfill);
- **derives and enforces the nearest-existing preceding and following bounds** (§7.0)
  server-side;
- **calls the deployed `public.save_goal_funding_snapshots(...)` directly** to perform the
  write — it does **not** reproduce that RPC's validation/write logic and does **not**
  write `goal_funding_snapshots` directly;
- **submits exactly one post-anchor row with `source='correction'`**;
- **performs post-call returned-row validation** (the written row equals the intended
  corrected value; count = 1);
- **propagates all exceptions** (straight-line, no swallowed error);
- **does NOT handle Week-5 opening-anchor amendments** — those preserve
  `source='opening_anchor'` and stay on the separate guarded-SQL path (§8).
- Owner-only is DB-enforced (`is_owner()` rejects Wendy). Pros: durable, testable,
  reusable for a later correction UX (5G-1E+); invariants are code, not prose. Cons: a
  **new deployed surface** (staging-first migration + validation + RLS/grant smoke + Fable
  review + separate Adam deploy approval); cannot run from the SQL editor (needs
  REST-as-Adam); **depends on Finding 8** (`is_owner()` must return true for the real Adam
  login or it rejects Adam).

### 4.2 Recommendation

**A-FIRST / B-LATER, but time-bound — not open-ended (F-3).** Option A is the **bridge
path only**; **Option B is planned into the 5G-1D Slice-2 staging package** (the same
slice that builds the closeout wrapper — 5G-1D plan §10 execution checklist, Slice 2).

The concrete rule (replacing the earlier vague "once corrections become routine / when a
button is needed" triggers, which are removed):

- **Option A is the bridge path only.** It exists to make a rare correction executable
  *before* Option B is deployed, using the guarded-SQL / A4 precedent.
- **Option A retires for post-anchor corrections the moment Option B is deployed.** Once
  `correct_goal_funding_snapshot` exists, post-anchor `source='correction'` fixes go
  through it, not through hand-authored SQL.
- **5G-1D activation is GATED on Option B** being deployed and tested — *unless* Adam
  explicitly approves a documented deferral.
- **Any deferral must be written into the implementation-readiness package** with:
  **rationale; owner; a dated expiration or review point; interim operating controls; and
  explicit Adam approval.** A deferral is never implicit and never open-ended.
- **Week-5 opening-anchor amendments are excluded from Option B** and remain on the
  separate guarded-SQL path (they preserve `source='opening_anchor'`, §8).

Rationale (the tradeoff, stated plainly): corrections are expected to be **rare,
exceptional** events, and E2 has not even run — there is nothing to correct yet. Option A
delivers the full safety envelope (guarded transaction, natural-key targeting,
nearest-existing adjacent monotonicity, before/after evidence, single-row proof) with
**no new deployed surface** and follows the exact precedent Adam has already executed
safely (A4). Its one concession — owner-only is operational rather than
`is_owner()`-enforced — is acceptable for a *bridge* window that closes when Slice-2 lands
Option B. Option B's DB-enforced owner boundary is the durable state and is what 5G-1D
activation is gated on.

**Do NOT use the deployed `save_goal_funding_snapshots` RPC directly for corrections under
either option** — it permits Wendy and enforces no monotonicity. (Option B *calls* it as
the write primitive behind an `is_owner()` gate and the monotonicity checks; it does not
expose it directly.)

**Unresolved for Adam:** confirm A-bridge / B-in-Slice-2 with activation gated on B, or an
explicitly documented deferral (see §19).

---

## 5. SQL-editor and authentication reality

Grounded answers to the execution-constraint questions:

- **Would calling the deployed RPC from the SQL editor fail because `auth.uid()` is
  null?** **Yes.** `save_goal_funding_snapshots` and `save_reconciliation_with_commitments`
  both gate on `can_write_financials()` → `EXISTS(... auth_user_id = auth.uid() ...)`. In
  the SQL editor `auth.uid()` is NULL, so the gate is false and the RPC **raises 'not
  authorized'**. (This is the same reason the E2 anchor is a guarded direct INSERT, not
  an RPC call — E2 runbook / `seed-anchor.sql`.)
- **Is a REST-authenticated call as Adam viable?** **Yes**, technically — a POST to
  `/rest/v1/rpc/<fn>` with Adam's real JWT propagates `auth.uid()` and passes
  `can_write_financials()`. **But** for corrections this is *not* owner-only (it also
  passes for Wendy) and enforces no monotonicity, so REST-via-the-deployed-RPC is
  rejected as the correction mechanism (§4). A REST call to a **new `is_owner()`-gated
  correction RPC (Option B)** *is* the viable owner-only REST path.
- **Would a guarded direct `UPDATE` procedure be safer or less safe?** **Both, on
  different axes.** *Safer* operationally: it works today, runs in one guarded
  transaction with pre/post assertions, and adds no deployed surface (Option A). *Less
  safe* on authorization: it has **no caller identity** — the SQL editor bypasses RLS and
  every gate, so "only Adam" is an access-control fact about the SQL editor, not a
  property the database checks. Its safety rests entirely on the guard block and on Adam
  being the sole operator.
- **Is a separate SECURITY DEFINER owner-only correction wrapper required?** **Not
  required to correct a value safely** (Option A suffices for rare one-offs), **but it is
  the only way to make owner-only a DB-enforced property** and is required if corrections
  are ever exposed through UX or delegated. Recommended as the durable path (Option B),
  deferred until justified.
- **How are caller identity and `public.is_owner()` enforced?** For Option A: not by the
  DB (operational only). For Option B / reconciliation reopen: `is_owner()` runs
  SECURITY DEFINER and checks `app_users.role='owner' AND active AND
  auth_user_id=auth.uid()`; it is meaningful **only** on an authenticated REST call
  (never the SQL editor), and **only after** production confirms it returns true for the
  real Adam login (Finding 8).

**No executable production SQL appears in this planning document.**

---

## 6. Correction effectivity

Grounded in the actual loader/overlay (Finding 7).

- **The corrected row is the effective snapshot for that week.** Because the loader keys
  on `(model_year, week_num, goal_id)` and there is exactly one row per natural key, the
  corrected value *is* the value the app reads.
- **C3 overlay resolves the row by natural key, independent of `source`.** For a
  model-tracked (active) goal, the overlay overwrites `goalSaved[gid]` with the corrected
  value at that week (`index.html:2586`). For a complete/manual goal, `getGoalFunded`
  reads `_latestGoalSnapshot(id, currentW)` (4357) — the highest `week_num ≤ currentW`.
- **`source` affects neither visibility nor resolution.** `source` is never fetched by
  the loader (7843). A `correction` row is exactly as visible/effective as a
  `reconciliation` or `opening_anchor` row at the same natural key. (Matches 5G-1D plan
  §3.7.)
- **Subsequent weekly closeouts use the corrected value as the effective prior.** The
  next ordinary closeout's monotonicity check and roll-forward compare against the
  current natural-key row value — i.e. the corrected value (5G-1D plan §3.7 "effective
  prior snapshot").
- **Future monotonicity checks use the corrected value** (both the next closeout's
  non-decrease check and any later adjacent-week correction check).
- **Same-week corrections interact cleanly with the unique key:** a correction to an
  existing week/goal is an in-place upsert — one row before, one row after; no duplicate,
  no second row (Finding 6).

### 6.1 Post-write live verification requires a hard reload (F-6)

An open browser session **retains stale `goalSnapData` after a database correction** — the
C3 loader runs at `loadAll` (`index.html:7843`), so a session that loaded before the write
keeps the pre-correction value in memory and will *appear* unchanged. **Post-write
validation must therefore never rely on an unreloaded session.** Aligned with the E2
Step-7 browser-verification pattern, post-write verification must include:

- a **hard reload** of the application (same login used for the write);
- a **fresh loader request** to `goal_funding_snapshots`;
- **confirmation the corrected natural-key row is returned** by the loader (200,
  non-empty, expected `week_num`/`goal_id`);
- **confirmation the rendered funded value equals the corrected value**;
- **confirmation unaffected included goals remain unchanged**;
- **confirmation excluded goals remain unchanged** (`adam_401k`, `wewe_rccl`, `wewe_dcl`,
  `taxable_etf`);
- **confirmation that no validation step relied on an unreloaded browser session**
  (an unreloaded session is not accepted as evidence).

As with E2 Step 7, "no visible movement" can be a correct result where the corrected value
equals what was already displayed — success is validated by the loader row + rendered
value agreeing with the correction, not by the screen changing.

---

## 7. Adjacent-week monotonicity

### 7.0 Nearest-existing adjacent-snapshot semantics (F-4)

"Adjacent" means **nearest existing snapshot row for that goal**, by `week_num` — **not**
`week_num − 1` / `week_num + 1`. Snapshot weeks can be sparse (reconciliation-only gaps,
skipped snapshot weeks, prior corrections), so the neighbors are defined by row existence,
not by arithmetic adjacency. This reuses the cleared 5G-1D plan §3.7 "effective prior
snapshot" definition (the latest applicable natural-key row for a goal, regardless of
`source`), extended symmetrically to the following side; it does **not** invent a new
definition.

- **preceding effective snapshot** = the natural-key row for that goal with the **greatest
  `week_num` strictly less than** the target week that **exists** (any `source`);
- **following effective snapshot** = the natural-key row for that goal with the **least
  `week_num` strictly greater than** the target week that **exists** (any `source`).

Applied consistently to every case:

- **latest-week correction** — following = none (no higher row exists); preceding =
  nearest existing lower row.
- **middle-week correction** — both = the nearest existing lower and higher rows (which
  may be several weeks away).
- **opening-anchor amendment** — preceding = none (the anchor is the floor); following =
  the nearest existing higher row (the first post-anchor week that has a snapshot).
- **first post-anchor correction** — preceding = the Week-5 anchor row (nearest existing
  lower); following = the nearest existing higher row, if any.
- **weeks with reconciliation-only gaps** — a week reconciled but not snapshotted has **no
  snapshot row**, so it is **skipped** when finding the nearest neighbor; the neighbor is
  the nearest week that actually has a snapshot row.
- **weeks with a prior correction** — the corrected row is the effective row at its week
  (source-blind, §6), so it is a valid neighbor like any other existing row.
- **skipped snapshot weeks** — likewise skipped; adjacency follows existing rows only.

### 7.1 The two-sided bound

For each corrected `(goal_id)` at the target week, the correction must satisfy **both
bounds against the nearest-existing effective neighboring snapshots** (§7.0), consistent
with 5G-1D plan §6.4.1:

- **corrected value ≥ preceding effective snapshot** for that goal, if one exists;
- **corrected value ≤ following effective snapshot** for that goal, if one exists.

Cases:

- **Latest-week correction:** only the **preceding-bound** check applies (no following
  snapshot exists yet).
- **Opening-anchor correction:** no preceding snapshot exists; only the **following-bound**
  check applies (the anchor is the floor). Governed additionally by §8's special path.
- **Middle-week correction:** **both** bounds apply.
- **When the corrected value violates either bound → HARD STOP.** Do not write. The
  correction is either wrong, or it implies later/earlier weeks must also change — which
  is **multi-week remediation** (§10), a separately approved operation.
- **No automatic cascade is allowed.** A correction never silently rewrites neighboring
  weeks to "make room." Cascading is the exact failure mode §2 principle 2 forbids; the
  bounded check is what makes an out-of-range correction *fail loudly* instead of
  spreading. (5G-1D plan §6.4.1.)
- **When it becomes multi-week remediation:** the moment a correction cannot satisfy both
  bounds without also changing a preceding or following week, it is no longer a
  single-week correction and must escalate to §10.

---

## 8. Opening-anchor correction (special case)

A correction to the Week-5 `opening_anchor` is **not** an ordinary snapshot correction
and must never be treated as one.

### 8.0 Source-collision resolution (Fable anchor B) — the anchor stays `opening_anchor`

There is a real contradiction between two cleared artifacts:

- the **E2 runbook §8** says "A wrong seeded value is corrected with `source='correction'`
  (a new/updated snapshot row), not a table drop"; while
- the **cleared 5G-1D plan §5.6** requires the opening anchor to be **exactly nine Week-5
  rows, all `source='opening_anchor'`**, or the future wrapper's anchor guard raises.

If a Week-5 anchor value were amended to `source='correction'`, the anchor set would
become a mix of `opening_anchor` + `correction` rows and the wrapper's anchor guard —
which checks `source='opening_anchor'` for all nine — would **fail**, wedging every
forward closeout. **This document resolves the collision explicitly and in favor of the
guard:**

- **A value amendment to an existing Week-5 `opening_anchor` row PRESERVES
  `source='opening_anchor'`.** Only `funded_amount` (and `note`) change in place; `source`
  is not flipped.
- **The fact that the row was corrected is recorded in the external evidence (§11) and the
  row `note`,** not by changing `source`.
- **`source='correction'` is used ONLY for post-anchor `reconciliation` snapshots**
  (weeks 6+), never for a Week-5 anchor row.
- **The Week-5 anchor set must remain nine rows, all `source='opening_anchor'`,** so the
  wrapper anchor guard continues to pass unchanged.

This is the safer rule because it keeps the anchor guard's invariant intact without
editing the guard, the plan, or the deployed RPC. **The E2 runbook's "`source='correction'`
for a wrong seeded value" language is therefore overridden for the Week-5 anchor case and
flagged for Adam (§18/§19); the cleared E2 runbook file is NOT edited here** — the
override is recorded in this companion spec. (An alternative — allow the anchor row to
become `source='correction'` and relax the wrapper guard to accept
`opening_anchor|correction` at Week 5 — is explicitly **rejected**: it would weaken the
anchor-integrity guard and blur the anchor/correction boundary. If Adam prefers it, it
must be an explicit plan change, not a silent one.)

- **Separate approval** from ordinary snapshot correction (§12). An opening-anchor
  correction touches the floor of all forward reasoning.
- **E2 First-Anchor Value Card impact:** if the anchor value was wrong, the **E2
  First-Anchor Value Card must be revised** and re-approved (the Value Card is the
  approved source of truth for the nine anchor values — E2 runbook §4). A corrected
  anchor whose Value Card is not revised is an inconsistent record → HALT.
- **Required evidence:** the full §11 package, plus the revised Value Card reference and
  the reason the original anchor was wrong.
- **Downstream impact assessment:** because forward weeks roll from the anchor, changing
  it may invalidate the monotonic relationship to Week 6+ snapshots. The following-bound
  check (§7) against the earliest existing `reconciliation` snapshot is mandatory.
- **Adjacent-week checks:** anchor correction has no preceding snapshot; the
  **following-bound** check applies against the first post-anchor week that has a
  snapshot.
- **Cleared E2 runbook closeout record:** if the anchor value in the *executed* E2
  evidence was wrong, the E2 **closeout evidence must be amended** (a correction addendum
  referencing the revised Value Card) — the cleared runbook *file* is not edited (it is a
  cleared artifact), but the execution record/evidence must reflect the corrected anchor.
- **5G-1D plan / anchor guard reconsideration:** the 5G-1D wrapper's opening-anchor guard
  (5G-1D plan §5.6) verifies the anchor exists and is complete at Week 5 with exactly the
  nine IDs. An anchor *value* correction does not change the guard's shape (same week,
  same nine IDs, same `source='opening_anchor'`), so the guard need not be edited — **but
  it must be re-run/re-verified after the correction** to confirm the anchor is still
  complete and single-week. If the correction would change the anchor *week* or the ID
  set, that is out of scope here and forces a revised plan + new Value Card + fresh Adam
  approval (5G-1D plan §5.6).
- **Hard-stop conditions:** any attempt to (a) treat the anchor correction as an ordinary
  weekly correction, (b) change the anchor week or ID set, (c) proceed without a revised
  Value Card, or (d) proceed without re-verifying the anchor guard → **STOP**.

### 8.1 Execution requirements for a Week-5 opening-anchor amendment

Any Week-5 opening-anchor amendment:

- **runs in its own supervised production session** (not folded into any other operation);
- **requires a fresh pre-correction state check** (re-verify the current anchor rows, the
  reconciled-week map, and production identity immediately before the write);
- **requires a revised First-Anchor Value Card** (E2 runbook §4), re-approved;
- **requires explicit opening-anchor correction approval** (its own gate, §12 — distinct
  from ordinary snapshot correction);
- **preserves `source='opening_anchor'`** (§8.0 — never flips to `correction`);
- **requires a new local backup/export** of `goal_funding_snapshots` before the write
  (§11);
- **requires new artifact hashes** (fresh SHA-256 of the pre-write export and the
  execution copy/output);
- **requires downstream Week-6+ impact review** (does any existing post-anchor snapshot now
  violate the following-bound against the corrected anchor? §7.0);
- **requires the future anchor guard (5G-1D plan §5.6) to be revalidated** after the write
  (still nine rows, all `opening_anchor`, single anchor week);
- **requires the E2 closeout evidence to be amended** (a correction addendum referencing
  the revised Value Card; the cleared E2 runbook *file* is not edited — §8);
- **does NOT use Option B** (the correction RPC excludes anchor amendments, §4.1) — it uses
  the separate guarded-SQL path;
- **defaults to escalation until Adam resolves the spec's open anchor-correction decision**
  (§19) — an anchor amendment is never the operator's default action.

**An opening-anchor correction may not be run as an ordinary weekly snapshot correction.**

---

## 9. Historical single-week remediation

Corrects a **past** week (not the latest) where the fix requires **no** changes to any
later week.

**Row-creation rule (F-5).** Historical single-week remediation **amends an existing
natural-key row**; it may **not** create a missing snapshot row. A nonexistent target
natural key is **always a hard stop** — no single-week path (correction or single-week
remediation) may backfill a missed week. **Deliberately creating a missing historical row
is exclusively a §10 multi-week / historical-backfill operation under its own reviewed
plan and explicit Adam approval** — never the ordinary correction or single-week amendment
path.

Permitted only when **all** hold; require and capture:

- **The target natural-key row already exists** (else HARD STOP; §4 / F-5).
- **Exact affected week and goals** enumerated.
- **Before/after values** for each affected goal.
- **Proof that adjacent-week monotonicity remains valid** (§7) in **both** directions for
  the corrected week — i.e. the corrected value sits within `[preceding, following]`
  effective bounds.
- **Proof that later snapshots require no changes** — the corrected value does not exceed
  the immediately following effective snapshot, so no downstream row must move.
- **Explicit Adam approval** (its own gate; §12).
- **Owner-only execution** (§4/§5 mechanism; operational owner-only for Option A,
  `is_owner()` for Option B).
- **Pre/post validation** (guard block: row exists, single row after, nearest-existing
  bounds hold §7.0) **plus post-write hard-reload live verification** (§6.1).
- **Full local-only pre-write export + hash capture and the §11 evidence package.**
- **No automatic reconciliation rollback** — the reconciled `weekly_reconciliations` row
  for that historical week is untouched; a snapshot correction does not reopen
  reconciliation (§4).

If the proof that later snapshots need no change **fails**, this is **not** a single-week
remediation — escalate to §10.

---

## 10. Historical multi-week remediation (escalated)

The escalation path when a correction **would require changes to later weeks**, or when a
**missing historical row must be deliberately created (backfill)**.

**Row-creation authority (F-5).** This is the **only** place a missing snapshot natural-key
row may be created, and only under a reviewed remediation plan + explicit Adam approval —
never through the §4 correction path or a §9 single-week amendment. Each created row must
itself satisfy the nearest-existing bounds (§7.0) at the point it is written.

- **No automatic cascade** — the operator never lets a single correction ripple.
- **No bulk rewrite under an ordinary correction approval** — a multi-week change is a
  distinct operation with its own approval, never folded into a single-week correction.
- **Separate remediation plan** authored and reviewed before any write.
- **Explicit list of affected weeks and goals.**
- **Full before/after matrix** for every affected `(week, goal)` cell.
- **Sequence of writes** defined (which week/goal is written in which order), each write
  itself satisfying the adjacent-week bounds as of the point it runs.
- **Monotonicity validation for the entire range** — after all writes, every affected
  goal's series is non-decreasing across the corrected span.
- **Reconciliation impact assessment** — whether any affected week's reconciliation must
  also be reopened (a *separate* §3 operation with its *own* approval; never bundled).
- **Rollback and recovery strategy** — because rollback of the table is break-glass only
  (never a value fix), the recovery plan is itself a forward correction plan (how to
  restore the prior values if the remediation is wrong), plus a full pre-remediation row
  export stored locally (§11 / E2 runbook §8).
- **Separate Fable-style review checklist even if Fable is unavailable** — the multi-week
  plan is reviewed against a written checklist (owner-only enforcement, exact affected
  set, full before/after matrix, per-write bounds, whole-range monotonicity, evidence,
  no reconciliation change without its own approval, rollback boundary) before execution,
  regardless of reviewer availability.
- **Separate Adam approval before execution** — distinct from every single-week approval.

---

## 11. Evidence model (mandatory correction evidence package)

Because an in-place update is **not** a history ledger (Finding 6), evidence is captured
**before** the write and completed after. Minimum package per correction/remediation:

- operation type (one of §1's exceptional operations)
- model year
- target week (and, for multi-week, the full affected week list)
- affected goal IDs
- original funded amounts
- corrected funded amounts
- original sources
- corrected sources
- preceding effective values (per goal)
- following effective values (per goal)
- reconciliation before/after values **where applicable** (reopen only; a pure snapshot
  correction records "reconciliation unchanged")
- reason
- approving Adam decision (which specific approval; §12)
- operator
- execution timestamp
- preflight output
- post-validation output
- affected-row output (the resulting row(s))
- local artifact filenames
- byte sizes
- SHA-256 hashes
- **confirmation that no financial-data artifact was committed to the public repository**

**Privacy alignment (E2 local-artifact model — E2 runbook §6/§8).** Artifacts containing
household balances (the value-filled correction SQL, its output, the row dumps, any
pre-remediation row export) are stored **locally** (external backup dir, e.g.
`~/Herndon-FOS-DB-Backups/Adam-Dashboard/`, or gitignored `exports/`) and are **never
committed**. Only the **metadata tier** (filename, byte size, SHA-256, timestamp,
purpose) and balance-free preflight/counts may be committed. There is no path that
commits observed household balances without a separate explicit Adam privacy override.

### 11.1 Mandatory pre-write full export (F-7)

**Before every exceptional write — including a single-week snapshot correction — capture a
full local-only export of `goal_funding_snapshots`** (`SELECT * … ORDER BY model_year,
week_num, goal_id`). This is the recovery baseline (there is no automatic rollback of
values, §2 principle 1). Record for the export:

- path
- filename
- timestamp
- byte size
- SHA-256
- row count
- purpose

The export **remains local** under the approved backup path or gitignored `exports/` and
is **never committed** (it contains household balances). Only its metadata/hash row is
committable.

### 11.2 Option-A guarded-SQL artifact contract (E2/A4 discipline; F-7)

When Option A is the mechanism, its artifacts follow the E2/A4 model. **No executable SQL
is created in this revision — this defines the contract only:**

- a **committed sentinel/template artifact is created only after a separate explicit
  approval to create it**, and contains **no real household values** (sentinels only);
- the **value-filled execution copy remains local** (external backup dir / gitignored
  `exports/`), never committed;
- a **value-only diff** confirms the execution copy differs from the template by the
  intended numeric literals only (no logic/guard/structure change);
- the **local execution artifact is hashed** (SHA-256 recorded in metadata);
- a **standalone read-only preflight is run first** (row exists, current value, nearest
  preceding/following effective values, production identity);
- the write is **one single execution block**:
  `BEGIN` → guarded `DO`/validation → `UPDATE` (natural-key upsert with existing-row
  assertion) → postflight assertions (row count, single row, nearest-existing bounds,
  resulting value = intended) → `COMMIT`;
- **no split write sequence** (never a preflight-then-separate-write with the transaction
  reopened);
- **rollback remains a separately approved break-glass action** (§2 principle 1; never
  bundled into the correction approval).

---

## 12. Approval gates (each distinct; none inferred from another)

Separate, explicit approvals — cross-authorization is prohibited (5G-1D plan §9):

1. **Reconciliation reopen approval** (per week).
2. **Snapshot correction approval** (per week/goal set).
3. **Opening-anchor correction approval** (special; §8).
4. **Historical single-week remediation approval** (§9).
5. **Multi-week remediation approval** (§10).
6. **Rollback approval** (break-glass; structural defect only; E2 runbook §8 / 5G-1D
   plan §9).
7. **Implementation approval for any new correction RPC** (Option B; §4).
8. **Deployment approval** (staging→production of Option B, if built).
9. **Activation approval** (turning any new correction path on).

**No approval is inferred from another.** A reopen approval does not authorize a
correction; a correction approval does not authorize a reopen; neither authorizes
rollback; neither restores direct `authenticated` access to the reconciliation RPC;
implementation approval does not imply deployment or activation approval.

---

## 13. Security and grants (for any recommended additive correction RPC — Option B)

**Grant reality — Adam and Wendy share the `authenticated` PostgreSQL role (Fable anchor
C).** Both Adam (owner) and Wendy (household_admin) present JWTs that map to the **same**
`authenticated` role; PostgreSQL sees one role, not two people. **Therefore function-level
`GRANT`/`REVOKE` alone CANNOT distinguish Adam from Wendy** — a grant to `authenticated`
grants both, and there is no "grant to Adam only." Owner-only is achievable **only** by an
in-body predicate. The correct construction for a future owner-only correction RPC is:

- **`GRANT EXECUTE … TO authenticated`** (required for PostgREST to route the call at all);
- **an internal `public.is_owner()` check** as the function's first action;
- **explicit rejection of `household_admin` inside the function** (`is_owner()` is false
  for Wendy → raise).

Do **not** claim PostgreSQL function grants by themselves enforce owner-only; the grant is
routing, the `is_owner()` body is authorization.

If Option B (`public.correct_goal_funding_snapshot(...)`) is built, its DDL must specify:

- **`SECURITY DEFINER`** with a **safe fixed `SET search_path`** (house convention:
  `SET search_path = public` as the deployed RPCs use; or `public, pg_temp`).
- **Fully schema-qualified references** for every non-`pg_catalog` object.
- **Explicit `public.is_owner()` check** as the first action (rejects Wendy; §4).
- **No dynamic SQL** (no `EXECUTE`/string-built statements).
- **Exact-signature grant normalization** — every REVOKE/GRANT targets the **full
  ordered argument type list**, never the bare name (avoids hitting/missing an overload;
  5G-1D plan §5.3).
- **`REVOKE ALL … FROM PUBLIC, anon, authenticated`** before any grant (Supabase defaults
  hand `authenticated` broad privileges incl. TRUNCATE, which bypasses RLS — the same
  defect the 5G-1 rehearsal caught).
- **`GRANT EXECUTE` only as appropriate for the owner-only design.**
- **Anonymous rejection** proven (anon has no EXECUTE; `is_owner()` false for anon).
- **`household_admin` rejection** proven (Wendy authenticated but `is_owner()` false).
- **Exact validation of final grants** (assert the resolved grant set; PUBLIC/anon none).
- **No broadening of table privileges** — the correction RPC does not add any table grant
  beyond the deployed `{SELECT,INSERT,UPDATE}`; no DELETE, no TRUNCATE.

**If `authenticated` must retain EXECUTE for PostgREST routing:** PostgREST requires the
role that presents the JWT (`authenticated`) to hold EXECUTE for the function to be
routable at all. Owner-only is then enforced **inside** the function by the top-line
`public.is_owner()` check, which raises for any non-owner caller — so `authenticated`
EXECUTE is a *routing* grant, not an *authorization* grant. Validation must prove that a
`household_admin` REST call (routable, EXECUTE present) is nonetheless **rejected by the
in-body `is_owner()` gate**. (This is the same pattern the 5G-1D wrapper uses for
`approved_reopen` — 5G-1D plan §5.8.)

---

## 14. Failure handling

All failures **default to no unauthorized mutation and no silent continuation.**

| Failure | Required behavior |
|---|---|
| Authorization failure | Reject; write nothing. (Option A: guard block aborts; Option B/reopen: `is_owner()` raises.) |
| Wrong target week | Preflight mismatch → HALT before any write. |
| Missing snapshot row | HALT — a correction requires an existing natural-key row (there is nothing to correct). |
| Incomplete nine-row week | HALT — a week missing snapshots is a half-closed/remediation case (5G-1D plan §6.3), not a correction. |
| Opening anchor missing | HALT — no forward correction is valid without the E2 anchor (§2 principle 4). |
| Adjacent-week violation | HALT — bounds fail (§7); route to multi-week remediation (§10). |
| Changed reconciliation without reopen approval | HALT — reconciliation change requires a §3 reopen approval; a correction may not touch reconciliation. |
| Changed snapshot without correction approval | HALT — value change requires a §4 correction approval; ordinary retry may not change values (5G-1D plan §6.2). |
| Network timeout | Treat as **ambiguous, not failed**; re-read persisted state before any retry (5G-1D plan §2.3, §6.5). |
| Ambiguous response | Re-read the natural-key row; only proceed if the persisted value matches intent; never blind-retry a value change. |
| Partial client evidence | HALT the close-out record — evidence (§11) is mandatory and must be complete before the operation is considered done. |
| Concurrent correction attempts | Serialize; the natural-key upsert is atomic, but two operators must not both hold correction approval — one approval, one operator (§12). A second concurrent write that changes the value is a stop condition. |
| Validation mismatch after write | The post-write assertion (row count, single row, nearest-existing bounds §7.0, resulting value = intended) failing → the guarded transaction rolls back (Option A `BEGIN/COMMIT`; Option B raise); nothing persists. |
| Unauthorized or unapproved `repair_commitments_for_week` use | HALT — any invocation affecting a closed/reconciled/anchored/historical week without explicit Adam approval, by Wendy, via the UI/retry path, or silently outside the §3.1 gate, is prohibited; no commitment/`balance_basis` mutation proceeds. |
| Interim-window anchored-week reconciliation/commitment change without approval | HALT — during the E2→activation window (§3.2), an ordinary UI resave or a repair-RPC change to an anchored week requires explicit Adam approval + full evidence; Wendy may not perform it. |
| Unreloaded browser used as post-write evidence | HALT the close-out record — post-write verification requires a hard reload + fresh loader read (§6.1); an unreloaded session is not acceptable evidence. |
| Missing pre-write export | HALT — the mandatory full local pre-write export + hash (§11.1) must exist before any exceptional write. |

---

## 15. Testing requirements (implementation-ready matrix)

To be realized when a mechanism is implemented (Option A guard template tests and/or
Option B RPC tests), aligned with the 5G-QA-1 tag-based runner (explicit `opts.tags`,
no name-prefix filtering; full mode is the release gate — 5G-1D plan §8):

- Adam owner correction **success**.
- Wendy `household_admin` correction **rejection** (Option B `is_owner()`; Option A: not
  reachable — Wendy has no SQL-editor/approval path).
- Anonymous **rejection**.
- SQL-editor / `auth.uid()`-null behavior (deployed RPC raises 'not authorized';
  confirms why Option A uses a guarded direct statement, Option B uses REST).
- **Latest-week correction** (preceding-bound only).
- **Middle-week correction within bounds** (both bounds).
- **Preceding-bound violation** → rejected.
- **Following-bound violation** → rejected.
- **Opening-anchor correction** hard stop / special path (§8).
- **Row count unchanged** after in-place correction (exactly one row per natural key).
- **`source` changes to `correction`.**
- **Overlay reads corrected value** (loader/overlay resolve by natural key, source-blind —
  Finding 7).
- **Next closeout uses corrected effective prior** (roll-forward + monotonicity read the
  corrected value).
- **Reconciliation reopen with unchanged snapshots** (nine resubmitted idempotently,
  `source='reconciliation'`).
- **Attempted combined reopen + unapproved snapshot change** → rejected (must be two
  approvals; 5G-1D plan §5.8.1/§5.8.2).
- **Older-week reopen rejection** (reopen is latest-completed-week only; §3).
- **Concurrent correction** → serialized; second value-changing write rejected.
- **Ambiguous network response** → re-read before retry; no blind value change.
- **Multi-week remediation escalation** (a correction that would rewrite later weeks
  hard-stops into §10).
- **Exact grants** (Option B: `authenticated` EXECUTE routing only, PUBLIC/anon none,
  no new table privilege).
- **Unchanged E1 snapshot RPC definition** (contract non-regression).
- **Unchanged reconciliation RPC definition** (contract non-regression).

Added by F-8:

- **Correction target row does not exist → hard stop, no INSERT** (F-5; no backfill).
- **The deployed snapshot RPC upsert cannot be used to backfill under a correction
  approval** (a missing natural key is rejected before any write).
- **Week-5 anchor amendment preserves `source='opening_anchor'`** (§8.0).
- **All nine Week-5 anchor rows remain `source='opening_anchor'`** after an amendment.
- **The future §5.6-style anchor-completeness check still passes after an amendment**
  (nine rows, one anchor week, all `opening_anchor`).
- **`repair_commitments_for_week` cannot be used by Wendy for an anchored/closed-week
  amendment under the approved design** (§3.1; procedural today, DB-enforced after the
  §17 activation grant decision).
- **Repair-RPC activation posture is validated** (its `authenticated` EXECUTE grant is
  reviewed and its retain/wrap/restrict/revoke decision is recorded — §17).
- **Interim-window ordinary reconciliation resave of an anchored week requires exceptional
  approval** (§3.2) — not treated as routine.
- **Hard reload is required before UI verification** (§6.1); **an unreloaded browser state
  is not accepted as evidence.**
- **A full pre-write export exists and is hashed** before every exceptional write (§11.1).
- **Option B rejects a missing target row** (existing-row assertion).
- **Option B enforces nearest-existing lower and higher bounds** (§7.0), not `week ± 1`.
- **Option B calls the deployed `save_goal_funding_snapshots` RPC** rather than writing the
  table directly or reproducing its logic.
- **Option A retires for post-anchor corrections once Option B is deployed** (§4.2).

For every forced failure, assert **no unauthorized or partial state persisted**, and that
golden-master identity still holds for zero-snapshot runs.

---

## 16. Operational completion criteria (before 5G-1D is "operationally complete")

At minimum, all must exist:

- **Documented correction procedure** (this doc + the chosen mechanism's runbook).
- **Owner-only enforcement** (operational for Option A; `is_owner()` for Option B/reopen —
  with Finding-8 identity confirmed in production).
- **Pre/post validation** (guard block or RPC assertions, run every time).
- **Existing-row validation** — every correction/single-week-amendment mechanism proves the
  target natural-key row exists before writing; a missing row hard-stops (F-5; §4/§9).
- **Adjacent-week monotonicity checks** using nearest-existing neighbors (§7.0) enforced by
  the mechanism.
- **Post-write hard-reload live verification** (§6.1) — success is confirmed against a
  fresh loader read, never an unreloaded session.
- **Mandatory pre-write full export + hash** before every exceptional write (§11.1).
- **Evidence template** (§11) instantiated and used.
- **Tested execution path** (§15 matrix green for the chosen mechanism).
- **Explicit rollback boundary** (rollback ≠ correction; break-glass only; §2 principle 1).
- **`repair_commitments_for_week` activation posture resolved** (retain / wrap / restrict /
  revoke its `authenticated` EXECUTE — §17 handoff).
- **No dependency on undocumented session memory** — every rule is in this doc, the 5G-1D
  plan, or the DDL; nothing relies on "we remember that…".

---

## 17. Relationship to the 5G-1D implementation-readiness package (handoff)

This spec does **not** duplicate the 5G-1D slice plan. It hands the following **mandatory
acceptance criteria** to the later 5G-1D implementation-readiness package to absorb:

1. **Reopen is owner-only via DB-enforced `is_owner()`**, latest-completed-week only,
   resubmits the nine unchanged with `source='reconciliation'`, atomic, evidenced (§3).
2. **Snapshot correction is in-place, single-row, `source='correction'`, owner-only,
   evidenced, monotonicity-checked** — and does **not** use the `can_write_financials()`
   deployed RPC (§4).
3. **The initial correction mechanism decision (Option A vs B)** is recorded and its
   safety envelope (guard block or `is_owner()` RPC) is implemented and tested (§4/§13).
4. **Adjacent-week two-sided monotonicity** is enforced by the correction mechanism, with
   the escalation-to-multi-week rule (§7/§10).
5. **Opening-anchor correction is a separate special path** with Value-Card revision and
   anchor-guard re-verification (§8).
6. **Every exceptional operation is a distinct approval gate; no cross-authorization**
   (§12).
7. **Evidence package + local-artifact privacy model** is mandatory and matches E2
   (§11).
8. **`is_owner()` production-identity confirmation** (Finding 8) is a preflight for any
   owner-only path.
9. **Contract non-regression:** the deployed reconciliation RPC and E1 snapshot RPC/table
   remain byte-unchanged (§2 principles 5/6; §15).
10. **`repair_commitments_for_week` activation-posture decision (F-1).** At the 5G-1D
    activation gate, an **explicit decision must be made and recorded to retain, wrap,
    restrict, or revoke the `authenticated` EXECUTE grant** on
    `repair_commitments_for_week` (signature `(INT, INT, TEXT, JSONB, JSONB)`), so that a
    closed/anchored-week commitment or `balance_basis` mutation cannot be performed by
    `household_admin` (Wendy) or via an unapproved path once 5G-1D is active. Options to
    evaluate: leave as-is (procedural control only), wrap behind an owner-only wrapper
    like the reconciliation reopen, restrict to owner via an in-body `is_owner()` gate (a
    body edit — separately approved, out of this spec's scope), or revoke the direct
    grant. **This spec does not choose or execute any of these — it requires the decision
    be made in the readiness package.**

### 17.1 Subordinate-artifact boundary (item 11)

This document is a **companion** to, not a replacement for, the cleared 5G-1D plan. It
**may**: identify activation-posture decisions; define correction/remediation
requirements; and hand exact acceptance criteria to the implementation-readiness package.
It **must not**: rewrite the master slice sequence; silently alter the cleared wrapper
modes (`normal_closeout` / `approved_reopen`); modify the Week-5 anchor contract; or
authorize any SQL or implementation. Where it surfaces a contradiction with a cleared
artifact (§18), it **reports** it for Adam rather than overriding the cleared plan.

---

## 18. Stop conditions (hard)

Hard stop — do not proceed, report instead — if the design would require any of:

- changing the deployed E1 snapshot RPC;
- changing the deployed reconciliation RPC body or signature;
- weakening owner-only correction authorization (e.g. accepting the
  `can_write_financials()` deployed RPC as the correction path — it permits Wendy);
- allowing Wendy to perform any exceptional correction/reopen/remediation;
- silent cascading changes to later weeks;
- a correction without adjacent-week validation;
- **a correction of a natural-key row that does not already exist** (that is backfill, not
  correction — Fable anchor A / §4);
- **flipping a Week-5 `opening_anchor` row to `source='correction'`** (it must stay
  `opening_anchor` so the wrapper anchor guard passes — Fable anchor B / §8.0);
- **claiming a PostgreSQL function grant alone makes an RPC owner-only** (Adam and Wendy
  share the `authenticated` role — Fable anchor C / §13);
- committing household financial values or output artifacts to the public repo;
- treating rollback as correction;
- treating correction as ordinary retry;
- implementing any of this before E2 has seeded and validated the Week-5 anchor;
- **shipping any `is_owner()`-gated path before the read-only production preflight confirms
  `is_owner()` returns true for Adam's real session** (Fable anchor D / Finding 8);
- **invoking `repair_commitments_for_week` against a closed/reconciled/anchored/historical
  week without explicit Adam approval and the §11 evidence package, or by Wendy, or through
  the ordinary UI/retry path** (F-1 / §3.1);
- **leaving `repair_commitments_for_week` outside the activation-posture review** — 5G-1D
  must not activate without an explicit retain/wrap/restrict/revoke decision on its
  `authenticated` EXECUTE grant (F-1 / §17 item 10);
- **an unapproved anchored-week reconciliation, commitment, or `balance_basis` change during
  the E2→activation interim window** (F-2 / §3.2);
- **creating a missing snapshot natural-key row through the correction or single-week
  amendment path** (row creation is §10/reviewed-backfill only — F-5 / §4/§9/§10);
- **accepting an unreloaded browser session as post-write verification evidence** (F-6 /
  §6.1);
- **executing an exceptional write without the mandatory pre-write full export + hash**
  (F-7 / §11.1);
- editing the cleared E2 runbook or the cleared 5G-1D plan to hide a contradiction.

**Contradiction check 1 — owner-only mechanism (reported, not silently overridden).** The
5G-1D plan §5.8.2 labels snapshot correction as **"supervised owner-only correction
(`source='correction'`)"** but leaves the *mechanism* open ("a supervised manual
database/RPC action"). The **only currently-deployed** mechanism that can write
`source='correction'` — `save_goal_funding_snapshots` — is gated on
`can_write_financials()`, which **permits Wendy** (Finding 3). This is a latent
inconsistency between the plan's *owner-only intent* and the deployed *can_write_financials
reality*: **the plan's "owner-only correction" is not automatically satisfied by any
deployed artifact.** This document resolves it forward (Option A operational owner-only
now / Option B `is_owner()` DB-enforced later; never the deployed RPC) **without editing
the cleared plan.** It is reported here as a finding for Adam, not overridden silently.

**Contradiction check 2 — opening-anchor source (Fable anchor B; reported, not silently
overridden).** The cleared **E2 runbook §8** says a wrong seeded value is fixed with
`source='correction'`, while the cleared **5G-1D plan §5.6** requires all nine Week-5
anchor rows to stay `source='opening_anchor'` for the wrapper anchor guard to pass. These
conflict. **This document resolves it (§8.0) in favor of the guard: a Week-5 anchor value
amendment preserves `source='opening_anchor'`; `source='correction'` is used only for
post-anchor (`reconciliation`) rows.** The cleared E2 runbook and 5G-1D plan files are
**NOT edited**; the override is recorded here and flagged for Adam.

---

## 19. Unresolved Adam decisions

1. **Correction mechanism:** Option A as the **bridge** path with **Option B planned into
   5G-1D Slice-2** and **activation gated on Option B** (or an explicitly documented,
   dated, controlled deferral) — **recommended** — versus building Option B now. (§4.2)
2. **`is_owner()` production identity (Finding 8):** run the read-only preflight proving
   exactly one active owner row, its `auth_user_id` maps to Adam's real login, Adam's
   session returns `is_owner()=true` and Wendy's returns `false`, with no role-data change
   — before any `is_owner()`-gated path (reopen, Option B) is trusted. Required, not
   optional.
2b. **`repair_commitments_for_week` activation posture (F-1):** decide and record whether
   to retain / wrap / restrict / revoke its `authenticated` EXECUTE at 5G-1D activation so
   an anchored/closed-week commitment or `balance_basis` change cannot be made by Wendy or
   an unapproved path (§17 item 10).
3. **Sequencing:** whether this correction/remediation procedure is finalized *before*
   5G-1D implementation begins, or folded into the 5G-1D readiness package as an
   acceptance-criteria annex (§17).
4. **Reopen scope confirmation:** confirm the initial reopen scope stays "latest
   completed week only," with all older-week changes routed through historical
   remediation (§3/§9/§10).
5. **Opening-anchor source rule (Fable anchor B):** confirm the resolution in §8.0 —
   Week-5 anchor value amendments preserve `source='opening_anchor'` (not `correction`) —
   and accept that this **overrides the E2 runbook §8 "`source='correction'`" language for
   the anchor case** without editing the cleared runbook. (If Adam instead prefers
   relaxing the wrapper anchor guard to accept `opening_anchor|correction` at Week 5, that
   is an explicit plan change, not a silent one.)

---

*Plan-only companion specification. No code, SQL, schema, RPC, RLS, migration, seed,
grant change, or test written or run this pass. Subordinate to the cleared E2 runbook and
the cleared 5G-1D plan; those files are unchanged. Nothing here is executable until E2
seeds and validates the Week-5 anchor and 5G-1D ships. Every exceptional operation
requires its own explicit Adam approval; no approval is inferred from another.*
