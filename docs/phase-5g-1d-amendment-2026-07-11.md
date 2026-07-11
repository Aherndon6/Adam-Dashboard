# Phase 5G-1D — Amendment Addendum (Fable red-team corrections)

**Status:** DRAFT — PREPARED, NOT IMPLEMENTED. No code, SQL, schema, RPC, RLS, migration,
seed, grant change, browser activation, or production action is authorized by this
document. No Slice-2 wrapper/Option-B SQL is authored under the previously cleared
specification pending these corrections.
**Date:** 2026-07-11
**Author:** Claude (session under Adam)
**Type:** Amendment-by-companion-document (does **not** edit or rewrite the cleared
artifacts).

## Relationship to the cleared artifacts (control rule)

This is an **amendment-by-companion-document**. It **does not edit or rewrite** the cleared
5G-1D artifacts, which **remain historically unchanged** as written:

1. `docs/phase-5g-1c-2-e2-runbook.md` — cleared E2 first-anchor seed gate (`c439d68`).
2. `docs/phase-5g-1d-plan-2026-07-09.md` — cleared write-through plan (`6de4614`).
3. `docs/phase-5g-1d-snapshot-correction-procedure-2026-07-10.md` — cleared correction /
   reopen / remediation companion spec (`f005263`).
4. `docs/phase-5g-1d-implementation-readiness-2026-07-10.md` — cleared implementation-
   readiness package (`a55d899`).

**Control rule (authoritative for implementation).** For implementation, **this companion
amendment CONTROLS wherever it is stricter than, or directly conflicts with, the cleared
text — the amendment's rule is the one that ships.** The cleared documents remain on file,
unchanged, as the historical record. This is **not** subordination in the sense of an older
conflicting rule winning: **where a cleared document conflicts with this amendment, the
amendment governs implementation.** **No conflict may be resolved silently** — any conflict
surfaced during implementation is **stopped and recorded here first**, and the amendment's
rule applied only after it is written down.

**Trigger.** Fable 5G-1D red-team verdict accepted (2026-07-11). The corrections below are
mandatory before Slice-2 SQL is authored. The Slice-1 client payload builder has already
been corrected in code (strict finite-primitive-number typing; see “Slice-1 status” at the
end).

**Privacy.** Balance-free. No household financial values, custodian figures, or per-goal
amounts appear here. The two Week-5 holding-goal correction rows are referenced by id
(`wewe_rccl`, `wewe_dcl`) only.

---

## A. Week-5 anchor and completeness scoping

- The opening-anchor guard must require **exactly the nine approved eligible goal IDs at
  Week 5 with `source='opening_anchor'`** (`adam_ira, wendy_ira, wendy_sep, alaska,
  bailey_529, bryce_529, preston_529, bryce_vehicle, christmas_cruise`).
- The guard must **tolerate additional Week-5 rows for non-eligible goals**, explicitly
  including the two holding-goal `source='correction'` rows (`wewe_rccl`, `wewe_dcl`) added
  by 5G-1C-2.1 Leg 2. Their presence must **not** fail the anchor guard.
- **Week completeness** means **all nine eligible IDs are present for the week, regardless
  of `source`** — not a raw row count and not a same-source constraint.
- **All anchor, completeness, latest-complete-week, sequence, and monotonicity predicates
  must be eligible-set-scoped** (restricted to the approved nine) **and source-scoped where
  appropriate** (anchor check keys on `opening_anchor`; completeness ignores source;
  monotonicity uses the effective natural-key row regardless of source).
- The **anchor week remains literal Week 5.** It must **not** be silently derived from
  `max(week_num)` or moved. (Supersedes any “derive latest anchor week” reading.)

**Correction vs the cleared plan §5.6/§4:** the cleared guard said “exactly the approved
nine goal IDs … no stray extra id.” That “no extra id” language is **narrowed** to “no
extra *eligible* id and no missing eligible id”; non-eligible correction/holding rows at
Week 5 are permitted and ignored by the eligible-set-scoped predicates.

---

## B. Server-side idempotent identity short-circuit

- Retry must **not** be implemented by blindly re-running the two inner RPCs.
- For a week already fully closed, the wrapper performs an **in-transaction full-identity
  comparison** against the persisted **reconciliation**, **commitments**, and the **nine
  eligible snapshots** (read back inside the transaction).
- **If identical:** return **idempotent success**; **call neither inner RPC**; **do not
  change `recorded_at`**; **do not recreate or alter commitments**; **do not change snapshot
  `source` or `note`.**
- **If non-identical:** **raise a hard error** and require the appropriate supervised
  **reopen** (reconciliation change) or **correction** (amount change) path.
- **Client re-read is UX support only.** The authoritative, race-free enforcement is
  **server-side**, inside the wrapper transaction.

**Identical retry returns success WITHOUT calling either inner RPC and WITHOUT changing any
persisted audit field** (`recorded_at`, `created_at`, `updated_at`, snapshot `source`/`note`).

### B.1 Full-identity comparison contract (implementation-ready)

All comparisons are performed **server-side, in-transaction**, on **cents-normalized**
values. `p_model_year` is pinned to **2026** and `p_week_num` must equal the target week
exactly; a mismatch on either is never an identity match.

**Reconciliation identity** — the submitted reconciliation must equal the persisted
`weekly_reconciliations` row on **every** field below:
- `model_year` and `week_num` — **exact match** (pinned; not normalized away);
- the five balances `chk`, `sav`, `amx`, `tax`, `lc` — equal at **canonical cents**
  (round to 2 decimals / integer cents before comparison; `-0` ≡ `0`);
- `balance_basis` — exact string equality (case-sensitive, not trimmed).
- **`recorded_at` is EXCLUDED from the identity comparison** (a resubmit legitimately
  carries a new client timestamp) **but MUST remain unchanged on the identity-success
  branch** — the wrapper does not call the reconciliation RPC and does not rewrite it.
- **Null vs omitted:** a request field that is **omitted** is treated as **not provided**
  and must be supplied by the confirmation payload; it is **not** silently coerced to `0` or
  to the persisted value. An explicit `null` balance is **invalid input** (hard-stop), not a
  match. Identity requires a fully specified balance set.

**Commitment identity** — compared as the **intended final commitment state**, matched by
the canonical business key **`expected_item_id`** (`cash_commitments.expected_item_id`,
`TEXT UNIQUE NOT NULL`). **A non-empty `p_new_commitments`/`p_patched` on the fully-closed
identity branch is NOT an automatic hard-stop** — the retry of a committed-but-lost-response
closeout legitimately resubmits the original non-empty operation arrays. The comparison is
on the *resulting state*, not on the presence of operations.

- **Derive the intended final state (do NOT execute it):** project the submitted
  `p_new_commitments` (creates) and `p_patched` (updates/deletes) onto the persisted set to
  obtain the request's intended final commitment set for the week — **by computation, with
  no create/update/delete performed.** Compare that intended final set against the **current
  persisted** commitment set for the week.
- **Identical intended final state → idempotent success:** **do not invoke the reconciliation
  RPC; do not replay any create/update/delete; do not change `id`, `created_at`,
  `updated_at`, `recorded_at`, or any persisted commitment field.** (A resubmitted create of
  an already-identical row, or a patch to a value already persisted, projects to an identical
  final state and is therefore a no-op success — this is the committed-but-lost-response
  retry case.)
- **Differing intended final state → hard-stop** to the supervised reopen path.
- **Comparison keys/fields:** the intended-final and persisted sets must contain the **same
  set of `expected_item_id`s** (no missing, no extra); for each `expected_item_id`, equality
  participates over: `commitment_source`, `commitment_class`, `amount_cents` (integer cents),
  `original_amount_cents` (nullable), `status`, `due_date`, `funding_account_key`,
  `resolution_type`, `reflected_model_week`, `resolved_model_week`, `cleared_date`, `memo`.
- **Database-generated fields are EXCLUDED:** surrogate `id`, `created_at`, `updated_at`
  (and any server-defaulted audit column) — unless a field is explicitly part of the
  approved persisted contract above.
- **Operation-array ORDER is IGNORED** — the submitted operations and the resulting sets are
  compared **keyed by `expected_item_id`**, never by position.
- **omitted array vs `[]`:** an **omitted** `p_new_commitments`/`p_patched` is normalized to
  `[]` (no operation of that kind); `[]` contributes no change to the intended final state.
- **null / omitted / default equivalence:** an **omitted** nullable field ≡ persisted
  `NULL`; an explicit `null` ≡ persisted `NULL`; a value equal to a column default ≡ that
  default; **a provided non-null value is never equal to persisted `NULL`**.
- **The identity-success branch performs NO create/update/delete** on `cash_commitments` — it
  verifies the intended final state already equals the persisted state and writes nothing.

*(Contrast — the **half-close repair branch (§C) requires all commitment arrays to be empty**
and never modifies commitments. That empty-array constraint is specific to §C; it does **not**
apply to this fully-closed identity branch, where non-empty arrays that project to an
identical final state are a valid idempotent retry.)*

**Snapshot identity** — over the eligible nine only:
- compare by the **exact eligible-nine `goal_id` set** (all nine present; the persisted week
  has a complete eligible-nine set);
- each `funded_amount` must match at **canonical cents precision**;
- the persisted **`source` and `note` must remain unchanged** — the identity branch never
  rewrites them;
- **a same-`funded_amount` row with a different persisted `source`/`note` is NOT overwritten**
  (a `source='correction'`/noted row stays as-is; identity holds on amount, and no write
  occurs);
- **non-eligible rows** at the week (e.g. the `wewe_rccl`/`wewe_dcl` correction rows) are
  **ignored for eligible-nine completeness and are NEVER mutated** by this operation.

---

## B.2 Ordered wrapper branch decision table (evaluated before any write)

The wrapper evaluates these guards **in this exact order** and takes the **first** matching
branch. The order is designed so **no state can match more than one write path**; each
branch either hard-stops or selects exactly one write behavior. All predicates are
**eligible-set-scoped** (the approved nine) and **source-scoped** where noted (§A), with
`p_model_year` pinned to **2026** and the anchor week literal **5**.

| Order | Condition | Action |
|---|---|---|
| **A** | Invalid caller (`can_write_financials()` false), invalid/NULL/unknown `p_mode`, wrong `model_year`, week outside 1..31, malformed payload, or any client-supplied `source` field | **HARD-STOP before any inner call** (strict validation; no coercion) |
| **B** | Target week ∈ **{1,2,3,4}** | **Out of snapshot-closeout scope** — legacy pre-anchor; **no repair path**, no snapshot write |
| **C** | Target week = **5** | **Literal opening anchor** — validate the eligible-nine `opening_anchor` guard (§A); **never a normal-closeout write**; anchor amendments are the guarded-SQL path only |
| **D** | `p_mode = 'approved_reopen'` | **Owner-only first-action gate** (`public.is_owner()`); require persisted reconciliation **and** complete eligible-nine set; equality-check snapshots; **do not mutate snapshots**; perform only approved reconciliation-reopen behavior (§D of corrections) |
| **E** | Contiguous next week has **no reconciliation and no eligible snapshots** | **Normal new-closeout branch** (`normal_closeout`) — reconciliation → eligible-nine snapshots, atomic |
| **F** | Reconciliation exists **and** a complete eligible-nine snapshot set exists (target week) | **Full-identity comparison (§B.1):** identical → **idempotent success, no inner calls, no audit-field change**; non-identical → **HARD-STOP** to reopen/correction |
| **G** | Reconciliation exists **and** eligible-nine snapshots are **incomplete** | **Supervised half-close repair branch (§C)** |
| **H** | Eligible snapshots exist **without** a reconciliation | **HARD-STOP anomaly** — impossible/corrupt; **no automatic repair** |
| **I** | Target week is **non-contiguous** (skip/future/past) or a **prior post-anchor week is incomplete** | **HARD-STOP** — require sequential backfill/repair first (no advancement past an incomplete prior week) |

**Mutual exclusivity.** A, B, C, and D are mode/week gates evaluated before the state
branches E–I. Among the state branches, E (no recon, no snapshots), F (recon + complete
snapshots), G (recon + incomplete snapshots), and H (snapshots, no recon) are **mutually
exclusive by construction** on `(reconciliation-present?, eligible-nine-complete?)`; I is a
sequencing precondition checked so that E/G cannot proceed on a non-contiguous or
prior-incomplete week. No input can satisfy two branches.

---

## C. Half-close repair branch (reconciliation present, snapshots incomplete)

When a week has a persisted reconciliation but an incomplete eligible-nine snapshot set,
the wrapper’s repair branch must, in one transaction, **in this order, before any snapshot
RPC call:**

1. **Read the currently present eligible rows** for the week (in-transaction).
2. **Require every already-present eligible row’s `funded_amount` to equal the submitted
   amount** (canonical cents). **Preserve each existing row’s `source` and `note`.**
3. **If any already-present eligible row differs → HARD-STOP as a correction anomaly**
   (repair may not overwrite an existing value; that is a snapshot correction, a separate
   supervised gate).
4. **Compute the missing eligible-ID set** (the eligible nine not yet present).
5. **Submit ONLY the absent eligible rows** (`source='reconciliation'`) — never re-write a
   present row.
6. **Require submitted reconciliation balances and `balance_basis` to equal the persisted
   values** (in-transaction); a mismatch hard-stops (that is a reopen, not a repair).
7. **Require all commitment create/update/delete arrays to be empty** — repair never mutates
   commitments.
8. **Do NOT call the reconciliation RPC.**
9. **Do NOT change `recorded_at`.**
10. **Read back and assert the complete eligible-nine set and exact values** (completeness +
    equality) before COMMIT.
11. **Preserve existing historical reconciliation and commitment state**, and every
    non-eligible row (incl. `wewe_rccl`/`wewe_dcl`) untouched.

This branch is the mechanism for post-freeze gap-week repair (branch **G** of §B.2 / §H).

---

## D. Reopen behavior and correction-marker preservation

- Reopen must **not** overwrite snapshot `source` or `note`.
- If submitted funded amounts **equal** the persisted eligible-nine amounts, **prefer
  skipping the snapshot RPC entirely** (no-op write avoidance).
- Reopen may change **only the authorized reconciliation state**.
- **Any snapshot-value change is a separate supervised correction** (Option B / guarded-SQL)
  and must **not** be bundled into a reopen.
- A row previously marked **`source='correction'` must remain `source='correction'`**, with
  its `note` **preserved** — reopen never reverts a correction marker to `reconciliation`.

**Correction vs cleared plan §5.8.1 step 3:** where the cleared text said reopen “calls the
deployed snapshot RPC with the exact already-approved nine amounts,” this addendum
**prefers skipping** the snapshot RPC when the amounts are unchanged, and **forbids**
overwriting `source`/`note` — closing the correction-marker-clobber gap Fable flagged.

---

## E. Wrapper mechanics

- The snapshot RPC returns only a **count**, so exact **ID-set and value assertions require
  an in-transaction read-back `SELECT`** of the persisted eligible-nine rows (not trust in
  the returned integer).
- The **client builder emits no `source`** (done in Slice 1).
- The wrapper must **reject any client-supplied `source` field** and **inject
  `source='reconciliation'`** for normal new snapshot writes.
- **Pin `p_model_year = 2026` consistently** across every predicate, read-back, and write.
- **Keep the anchor week literal `5`.**
- **Strict `TEXT` `p_mode` validation:** only the approved literals (`normal_closeout`,
  `approved_reopen`); **explicit `NULL` raises**; **unknown/misspelled values raise before
  any inner call**; **no permissive coercion / no default-to-normal.**
- Preserve the approved **one-wrapper architecture** and **direct calls** to the two
  deployed RPCs (no reproduced logic, no direct table writes from the wrapper).
- **Do not edit or rerun E1 DDL.**

---

## F. Client closeout state machine

- **Remove the optimistic `reconData[n]` assignment** from the wrapper flow (today
  `saveRecon` sets it before the POST — `index.html:2765`).
- Update local reconciled state **only after successful server completion and reload**.
- **Re-read snapshots immediately before rendering the confirmation view.**
- **Freeze the exact nine-row payload when the confirmation renders**; **display that frozen
  object and submit that exact same object.** **Do not re-derive values at click time.**
- **Disable duplicate submission while the request is in flight.**
- **Closeout-completeness scoping:**
  - **Weeks 1–4:** legacy pre-anchor — **not flagged or repaired**;
  - **Week 5:** the anchor;
  - **Weeks 6+:** complete **only when all nine eligible IDs exist for the week, any
    `source`.**

---

## G. Expanded Gate C — write-surface posture register

One explicit **retain / restrict / revoke** decision per surface, each with **exact
signature**, **staging proof**, and the change-package requirements below. **No production
grant change is authorized here** — this register is the decision scaffold for Gate C.

| # | Write surface | Exact target (signature/object) | Recommended target posture |
|---|---|---|---|
| 1 | Old reconciliation RPC direct EXECUTE by `authenticated` | `save_reconciliation_with_commitments(INT, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, JSONB, JSONB)` — exact deployed signature, grounded at `docs/phase-5f-1-migration.sql:454` (REVOKE `:961`, GRANT `:964`) | **REVOKE** `authenticated` EXECUTE (wrapper calls it as definer owner) |
| 2 | `repair_commitments_for_week` | `repair_commitments_for_week(INT,INT,TEXT,JSONB,JSONB)` | **RESTRICT** — owner-only or revoke `authenticated` EXECUTE (decide after Slice-2 caller audit) |
| 3 | `save_goal_funding_snapshots` direct EXECUTE by `authenticated` | `save_goal_funding_snapshots(INT,INT,JSONB)` | **REVOKE** `authenticated` EXECUTE (wrapper + Option B call it as definer owner) |
| 4 | `goal_funding_snapshots` direct table INSERT | table `public.goal_funding_snapshots` | **REVOKE** `authenticated` INSERT |
| 5 | `goal_funding_snapshots` direct table UPDATE | table `public.goal_funding_snapshots` | **REVOKE** `authenticated` UPDATE |
| 6 | `weekly_reconciliations` direct table INSERT | table `public.weekly_reconciliations` | **REVOKE** `authenticated` INSERT |
| 7 | `weekly_reconciliations` direct table UPDATE | table `public.weekly_reconciliations` | **REVOKE** `authenticated` UPDATE |
| 8 | `weekly_reconciliations` direct table DELETE | table `public.weekly_reconciliations` | **REVOKE** `authenticated` DELETE |
| 9 | Shipped `deleteRecon` product behavior | `index.html` `deleteRecon(n)` → `DELETE /weekly_reconciliations?week_num=eq.N` | **RESTRICT** — anchored/completed weeks must not be deletable through ordinary UI (depends on #8) |
| 10 | New wrapper RPC | `save_weekly_closeout_with_snapshots(...)` — **TBD — exact ordered signature must be amendment-cleared before SQL authorship** (proposed shape in §G.1; NOT an exact target) | **RETAIN** `authenticated` EXECUTE (intended financial writers only; anon/PUBLIC none) |
| 11 | Option B correction RPC | `correct_goal_funding_snapshot(...)` — **TBD — exact ordered signature must be amendment-cleared before SQL authorship** (proposed shape in §G.1; NOT an exact target) | **RETAIN** `authenticated` EXECUTE for routing; **owner-only enforced in-body** via `public.is_owner()` |

**Net recommended target posture:** reconciliation and goal-snapshot writes become
**RPC-only for `authenticated`**; revoke direct EXECUTE on the old reconciliation RPC (#1)
and on `save_goal_funding_snapshots` (#3); revoke `authenticated` direct INSERT/UPDATE on
`goal_funding_snapshots` (#4/#5); revoke `authenticated` direct INSERT/UPDATE/DELETE on
`weekly_reconciliations` (#6/#7/#8); anchored completed weeks not deletable through ordinary
UI (#9); Option B owner-only inside the function (#11); the wrapper available only to the
intended authenticated financial writers (#10).

**Every posture change requires, each separately:**
- a **separately approved exact grant change** (name + full ordered arg type list; never the
  bare name);
- **staging rehearsal**;
- a **before/after grant matrix**;
- **rollback SQL**;
- **proof the wrapper still succeeds** (definer-owner path intact after revocation);
- **proof the bypass path fails** (stale/direct caller denied before any persistence).

**Dependency note.** #9 (UI non-deletability of anchored weeks) depends on #8 (table DELETE
revocation) plus a client guard; deciding #2 requires the Slice-2 `repair_commitments_for_week`
caller/dependency audit first.

**Exact-signature discipline (retained).** Every `REVOKE`/`GRANT`/validation/restoration for
**every** surface above targets the **full ordered function signature** (name **and** the
complete ordered argument type list) — **never the bare function name** (Postgres resolves
by signature; the bare name risks hitting or missing an overload). Rows 2 and 3 carry their
exact deployed signatures; row 1 is now exact (above); rows 10 and 11 are **TBD** and must be
made exact per §G.1 before any grant SQL is authored.

### G.1 Proposed (NON-BINDING, TBD) signatures for rows 10 and 11

These are **design intent only, NOT exact targets.** No grant/REVOKE/validation may cite
them until the exact ordered argument-type list is **amendment-cleared** and this section is
updated to record it.

- **Row 10 — `save_weekly_closeout_with_snapshots` (wrapper).** Proposed parameter set,
  mirroring the deployed reconciliation RPC inputs plus the three closeout controls:
  `p_week_num INT`, `p_model_year INT`, `p_chk NUMERIC`, `p_sav NUMERIC`, `p_amx NUMERIC`,
  `p_tax NUMERIC`, `p_lc NUMERIC`, `p_balance_basis TEXT`, `p_recorded_at TIMESTAMPTZ`,
  `p_new_commitments JSONB`, `p_patched JSONB`, `p_snapshot_rows JSONB`, `p_mode TEXT`,
  `p_expected_count INT`.
  **Open items that must be resolved before this becomes exact:** (a) PostgreSQL requires
  that once any parameter carries a `DEFAULT`, **all following parameters also carry
  defaults** — the deployed reconciliation RPC defaults `p_new_commitments`/`p_patched` to
  `'[]'`, so the **exact ordered list and which parameters carry `DEFAULT`** (and therefore
  the final ordering) must be fixed deliberately; (b) whether `p_mode`/`p_expected_count`
  default; (c) the return type. Until fixed and cleared here: **TBD.**
- **Row 11 — `correct_goal_funding_snapshot` (Option B).** The cleared readiness D2 defines
  its **behavior** but no signature. Proposed parameter set: `p_model_year INT`,
  `p_week_num INT`, `p_goal_id TEXT`, `p_funded_amount NUMERIC`, `p_note TEXT` (and possibly
  an explicit prior-value assertion parameter). **Exact ordered list, defaults, and return
  type: TBD — must be amendment-cleared before SQL authorship.**

---

## H. Activation timing

- **Recommendation: continue implementation and staging now, but activate in production
  AFTER the Alaska freeze (Jul 24 – Aug 10).**
- **Do not compress controls to force pre-freeze activation.** No 5G merge during the
  freeze under any option; an explicit timing decision does not override the freeze.
- The **first supervised production use may be the sequential repair of post-anchor gap
  weeks** (the reconciled-but-unsnapshotted weeks accrued during the gap), executed through
  the **corrected half-close repair branch (§C)**, one week at a time, no advancement past
  an incomplete prior week.
- **No production SQL, grant changes, browser activation, or first live closeout** without
  **separately approved runbooks and evidence gates.**

---

## Slice-1 status (already corrected in code this session — not committed)

`buildCloseoutSnapshotRows()` + `SNAPSHOT_ELIGIBLE_GOAL_IDS` (`index.html`, inert, zero call
sites) now accept **finite primitive numbers only** — strings (incl. numeric/empty/
whitespace), booleans, null/undefined, arrays, objects, NaN, Infinity, -Infinity are all
rejected; parsing belongs at the UI boundary. Static regression and full e2e green. This
addendum records the design corrections A–H for the **subsequent** slices; it authorizes
none of them.

---

## Explicit non-authorization

This addendum authorizes **no** implementation. It does **not** author Slice-2 wrapper or
Option-B SQL, change any grant, run any SQL, deploy, or activate anything. Every gate
(0, A–E, and each Gate C posture change) remains an explicit Adam decision at its trigger,
with its own runbook, staging rehearsal, and evidence. E1 DDL remains immutable. No
household financial values are recorded here.
